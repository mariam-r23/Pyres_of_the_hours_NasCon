extends RefCounted
## Loads a level JSON file (PROJECT_CONTEXT.md section 6.1) into a GameState.
## No Nodes, graphics, audio or UI.
##
## This file checks FORMAT only: required fields, types, hours, slot shape,
## terrain strings, duplicate ids. Rule checks (slot inside the grid, ash link
## onto a wall, missing exit, unknown type, ...) belong to level_validator.gd.
##
## Every load function returns:
##   { "state": GameState (core/game_state.gd) or null,
##     "meta":  { "title", "act", "spirit_mood", "mood_weights", "par_actions", "spirit_lines" },
##     "error": "" on success, otherwise one line per problem, naming the field
##              (for example "objects[1].ash_link.hour: missing required field") }
## A bad file never crashes; every problem found is reported at once.

const GameStateScript := preload("res://core/game_state.gd")

const TERRAIN_CHARS := [GameStateScript.FLOOR, GameStateScript.WALL, GameStateScript.CHASM]
const STATES := [GameStateScript.INTACT, GameStateScript.ASH, GameStateScript.GONE]

const DEFAULT_ACT := 1
const DEFAULT_MOOD := "amused"
const NO_PAR := -1


static func load_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail(["%s: cannot open file (%s)" % [path, error_string(FileAccess.get_open_error())]])
	return load_json_string(file.get_as_text(), path)


static func load_json_string(text: String, source: String = "level") -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _fail(["%s: invalid JSON at line %d: %s" % [source, json.get_error_line(), json.get_error_message()]])
	return load_dict(json.data)


static func load_dict(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return _fail(["level: expected a JSON object at the top level, got %s" % _describe(data)])
	var errors: Array[String] = []

	var w := GameStateScript.DEFAULT_GRID_SIZE
	var h := GameStateScript.DEFAULT_GRID_SIZE
	var grid = _get_dict(data, "grid", "", errors, false)
	if grid != null:
		w = _get_int(grid, "w", "grid", errors, w)
		h = _get_int(grid, "h", "grid", errors, h)
		if w < 1 or h < 1:
			errors.append("grid: w and h must be at least 1, got %dx%d" % [w, h])
			w = GameStateScript.DEFAULT_GRID_SIZE
			h = GameStateScript.DEFAULT_GRID_SIZE

	var state: GameStateScript = GameStateScript.new(w, h)
	state.level_id = _get_string(data, "id", "", errors, "")
	if data.has("id") and state.level_id == "":
		errors.append("id: must not be empty")

	var sun = _get_dict(data, "sun", "", errors, false)
	if sun != null:
		state.sun_start_index = _get_int(sun, "start_index", "sun", errors, 0, false)
		state.actions_per_hour = _get_int(sun, "actions_per_hour", "sun", errors, GameStateScript.DEFAULT_ACTIONS_PER_HOUR, false)
		if state.sun_start_index < 0 or state.sun_start_index >= GameStateScript.HOUR_ORDER.size():
			errors.append("sun.start_index: must be 0 to 5, got %d" % state.sun_start_index)
		if state.actions_per_hour < 1:
			errors.append("sun.actions_per_hour: must be at least 1, got %d" % state.actions_per_hour)

	_load_rooms(data, state, errors)

	var player = _get_dict(data, "player", "", errors, true)
	if player != null:
		state.player_hour = _get_hour(player, "hour", "player", errors)
		state.player_slot = _get_slot(player, "slot", "player", errors)

	_load_objects(data, state, errors)
	_load_shadows(data, state, errors)
	var meta := _load_meta(data, errors)

	if not errors.is_empty():
		return _fail(errors)
	return {"state": state, "meta": meta, "error": ""}


static func _load_rooms(data: Dictionary, state: GameStateScript, errors: Array[String]) -> void:
	var rooms = _get_array(data, "rooms", "", errors, false)
	if rooms == null:
		return
	var seen := {}
	for i in rooms.size():
		var path := "rooms[%d]" % i
		var room = _as_dict(rooms[i], path, errors)
		if room == null:
			continue
		var hour := _get_hour(room, "hour", path, errors)
		if seen.has(hour):
			errors.append("%s.hour: hour %d is listed twice" % [path, hour])
		seen[hour] = true
		var rows = _get_array(room, "terrain", path, errors, true)
		if rows == null:
			continue
		if rows.size() != state.grid_h:
			errors.append("%s.terrain: expected %d rows, got %d" % [path, state.grid_h, rows.size()])
			continue
		var clean: Array = []
		for y in rows.size():
			var row_path := "%s.terrain[%d]" % [path, y]
			var row = rows[y]
			if typeof(row) != TYPE_STRING:
				errors.append("%s: expected a string, got %s" % [row_path, _describe(row)])
				continue
			if row.length() != state.grid_w:
				errors.append("%s: expected %d characters, got %d (\"%s\")" % [row_path, state.grid_w, row.length(), row])
				continue
			for x in row.length():
				if not TERRAIN_CHARS.has(row[x]):
					errors.append("%s: unknown terrain character '%s' at x=%d (use . # ~)" % [row_path, row[x], x])
			clean.append(row)
		if clean.size() == state.grid_h and GameStateScript.order_index(hour) >= 0:
			state.terrain[hour] = clean


static func _load_objects(data: Dictionary, state: GameStateScript, errors: Array[String]) -> void:
	var objects = _get_array(data, "objects", "", errors, true)
	if objects == null:
		return
	for i in objects.size():
		var path := "objects[%d]" % i
		var src = _as_dict(objects[i], path, errors)
		if src == null:
			continue
		var obj := {
			"id": _get_string(src, "id", path, errors, ""),
			"type": _get_string(src, "type", path, errors, ""),
			"hour": _get_hour(src, "hour", path, errors),
			"slot": _get_slot(src, "slot", path, errors),
			"state": _get_string(src, "state", path, errors, GameStateScript.INTACT, false),
			"flammable": _get_bool(src, "flammable", path, errors, false),
		}
		if not STATES.has(obj["state"]):
			errors.append("%s.state: must be INTACT, ASH or GONE, got \"%s\"" % [path, obj["state"]])
		var link = _get_dict(src, "ash_link", path, errors, false)
		if link != null:
			var link_path := path + ".ash_link"
			obj["ash_link"] = {
				"hour": _get_hour(link, "hour", link_path, errors),
				"slot": _get_slot(link, "slot", link_path, errors),
				"becomes": _get_string(link, "becomes", link_path, errors, ""),
			}
		var to = _get_dict(src, "links_to", path, errors, false)
		if to != null:
			var to_path := path + ".links_to"
			obj["links_to"] = {
				"hour": _get_hour(to, "hour", to_path, errors),
				"slot": _get_slot(to, "slot", to_path, errors),
			}
		_add_by_id(state.objects, obj, path, errors)


static func _load_shadows(data: Dictionary, state: GameStateScript, errors: Array[String]) -> void:
	var shadows = _get_array(data, "shadows", "", errors, false)
	if shadows == null:
		return
	for i in shadows.size():
		var path := "shadows[%d]" % i
		var src = _as_dict(shadows[i], path, errors)
		if src == null:
			continue
		var sh := {
			"id": _get_string(src, "id", path, errors, ""),
			"hour": _get_hour(src, "hour", path, errors),
			"slot": _get_slot(src, "slot", path, errors),
		}
		_add_by_id(state.shadows, sh, path, errors)


static func _load_meta(data: Dictionary, errors: Array[String]) -> Dictionary:
	var meta := {
		"title": _get_string(data, "title", "", errors, "", false),
		"act": _get_int(data, "act", "", errors, DEFAULT_ACT, false),
		"spirit_mood": _get_string(data, "spirit_mood", "", errors, DEFAULT_MOOD, false),
		"mood_weights": {},
		"par_actions": _get_int(data, "par_actions", "", errors, NO_PAR, false),
		"spirit_lines": {},
	}
	var weights = _get_dict(data, "mood_weights", "", errors, false)
	if weights != null:
		for mood in weights:
			var value = weights[mood]
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				errors.append("mood_weights.%s: expected a number, got %s" % [mood, _describe(value)])
			else:
				meta["mood_weights"][mood] = float(value)
	var lines = _get_dict(data, "spirit_lines", "", errors, false)
	if lines != null:
		for trigger in lines:
			var line = lines[trigger]
			if typeof(line) != TYPE_STRING:
				errors.append("spirit_lines.%s: expected a string, got %s" % [trigger, _describe(line)])
			else:
				meta["spirit_lines"][trigger] = line
	return meta


static func _add_by_id(target: Dictionary, entry: Dictionary, path: String, errors: Array[String]) -> void:
	var id: String = entry["id"]
	if id == "":
		if not errors.any(func(e): return e.begins_with(path + ".id")):
			errors.append("%s.id: must not be empty" % path)
		return
	if target.has(id):
		errors.append("%s.id: duplicate id \"%s\"" % [path, id])
		return
	target[id] = entry


# --- Field readers. Each one reports a problem and returns a fallback, so ---
# --- loading can continue and every problem in the file is listed.       ---

static func _get_int(d: Dictionary, key: String, path: String, errors: Array[String], fallback: int, required: bool = true) -> int:
	var where := _join(path, key)
	if not d.has(key):
		if required:
			errors.append("%s: missing required field" % where)
		return fallback
	var v = d[key]
	if typeof(v) == TYPE_INT:
		return v
	# JSON numbers arrive as floats; accept whole numbers only.
	if typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v):
		return int(v)
	errors.append("%s: expected an integer, got %s" % [where, _describe(v)])
	return fallback


static func _get_string(d: Dictionary, key: String, path: String, errors: Array[String], fallback: String, required: bool = true) -> String:
	var where := _join(path, key)
	if not d.has(key):
		if required:
			errors.append("%s: missing required field" % where)
		return fallback
	if typeof(d[key]) != TYPE_STRING:
		errors.append("%s: expected a string, got %s" % [where, _describe(d[key])])
		return fallback
	return d[key]


static func _get_bool(d: Dictionary, key: String, path: String, errors: Array[String], fallback: bool) -> bool:
	var where := _join(path, key)
	if not d.has(key):
		errors.append("%s: missing required field" % where)
		return fallback
	if typeof(d[key]) != TYPE_BOOL:
		errors.append("%s: expected true or false, got %s" % [where, _describe(d[key])])
		return fallback
	return d[key]


## Returns the Dictionary, or null if missing or the wrong type.
static func _get_dict(d: Dictionary, key: String, path: String, errors: Array[String], required: bool) -> Variant:
	if not d.has(key):
		if required:
			errors.append("%s: missing required field" % _join(path, key))
		return null
	return _as_dict(d[key], _join(path, key), errors)


## Returns the Array, or null if missing or the wrong type.
static func _get_array(d: Dictionary, key: String, path: String, errors: Array[String], required: bool) -> Variant:
	var where := _join(path, key)
	if not d.has(key):
		if required:
			errors.append("%s: missing required field" % where)
		return null
	if typeof(d[key]) != TYPE_ARRAY:
		errors.append("%s: expected a list, got %s" % [where, _describe(d[key])])
		return null
	return d[key]


static func _as_dict(v: Variant, where: String, errors: Array[String]) -> Variant:
	if typeof(v) != TYPE_DICTIONARY:
		errors.append("%s: expected an object, got %s" % [where, _describe(v)])
		return null
	return v


## An hour must be one of 12, 2, 4, 6, 8, 10.
static func _get_hour(d: Dictionary, key: String, path: String, errors: Array[String]) -> int:
	var before := errors.size()
	var hour := _get_int(d, key, path, errors, GameStateScript.HOUR_ORDER[0])
	if errors.size() == before and GameStateScript.order_index(hour) < 0:
		errors.append("%s: %d is not an hour (use 12, 2, 4, 6, 8 or 10)" % [_join(path, key), hour])
		return GameStateScript.HOUR_ORDER[0]
	return hour


## A slot is a list of two integers [x, y]. Whether it is inside the grid is
## checked by the validator.
static func _get_slot(d: Dictionary, key: String, path: String, errors: Array[String]) -> Vector2i:
	var where := _join(path, key)
	if not d.has(key):
		errors.append("%s: missing required field" % where)
		return Vector2i.ZERO
	var v = d[key]
	if typeof(v) != TYPE_ARRAY or v.size() != 2:
		errors.append("%s: expected [x, y], got %s" % [where, _describe(v)])
		return Vector2i.ZERO
	var before := errors.size()
	var xy := {"x": v[0], "y": v[1]}
	var x := _get_int(xy, "x", where, errors, 0)
	var y := _get_int(xy, "y", where, errors, 0)
	if errors.size() != before:
		return Vector2i.ZERO
	return Vector2i(x, y)


static func _join(path: String, key: String) -> String:
	return key if path == "" else path + "." + key


static func _describe(v: Variant) -> String:
	if v == null:
		return "null"
	return "%s (%s)" % [JSON.stringify(v), type_string(typeof(v))]


static func _fail(errors: Array) -> Dictionary:
	return {"state": null, "meta": {}, "error": "\n".join(PackedStringArray(errors))}
