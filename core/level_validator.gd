extends RefCounted
## Rule checks for a freshly loaded level (PROJECT_CONTEXT.md sections 3 and 11).
## No Nodes, graphics, audio or UI.
##
## level_loader.gd checks the file FORMAT. This file checks that the level
## makes sense under the rules: slots inside the grid, known types, one exit,
## ash links and stairs pointing at usable slots, shadows and the player start
## on legal tiles.
##
## validate(state) returns every problem found as a readable string;
## an empty array means the level is valid.

const GameStateScript := preload("res://core/game_state.gd")

## Object types in the section 3.2 type table (keys and torches are cut).
const KNOWN_TYPES := ["bridge", "ash_path", "crate", "door", "stair", "exit"]
const STATES := [GameStateScript.INTACT, GameStateScript.ASH, GameStateScript.GONE]


static func validate(state: GameStateScript) -> Array[String]:
	var errors: Array[String] = []
	var ids := state.objects.keys()
	ids.sort()
	_check_objects(state, ids, errors)
	_check_one_exit(state, ids, errors)
	_check_shared_slots(state, ids, errors)
	for id in ids:
		var obj: Dictionary = state.objects[id]
		if obj.has("ash_link"):
			_check_ash_link(state, obj, errors)
		if obj["type"] == "stair":
			_check_stair(state, obj, errors)
	_check_shadows(state, errors)
	_check_player_start(state, errors)
	return errors


static func _check_objects(state: GameStateScript, ids: Array, errors: Array[String]) -> void:
	for id in ids:
		var obj: Dictionary = state.objects[id]
		var name := "object \"%s\"" % id
		_check_place(state, obj["hour"], obj["slot"], name, errors)
		if not KNOWN_TYPES.has(obj["type"]):
			errors.append("%s: unknown type \"%s\" (known: %s)" % [name, obj["type"], ", ".join(KNOWN_TYPES)])
		if not STATES.has(obj["state"]):
			errors.append("%s: unknown state \"%s\" (use INTACT, ASH or GONE)" % [name, obj["state"]])


static func _check_one_exit(state: GameStateScript, ids: Array, errors: Array[String]) -> void:
	var exits := ids.filter(func(id): return state.objects[id]["type"] == "exit")
	if exits.is_empty():
		errors.append("level: no exit object (exactly one is required)")
	elif exits.size() > 1:
		errors.append("level: %d exit objects (%s), exactly one is required" % [exits.size(), ", ".join(exits)])


static func _check_shared_slots(state: GameStateScript, ids: Array, errors: Array[String]) -> void:
	var first_at := {}  # "hour@x,y" -> id of the first object seen there
	for id in ids:
		var obj: Dictionary = state.objects[id]
		var key := "%d@%s" % [obj["hour"], _slot_text(obj["slot"])]
		if first_at.has(key):
			errors.append("object \"%s\": shares slot %s in hour %d with object \"%s\" (one object per slot)" % [
				id, _slot_text(obj["slot"]), obj["hour"], first_at[key]])
		else:
			first_at[key] = id


static func _check_ash_link(state: GameStateScript, obj: Dictionary, errors: Array[String]) -> void:
	var link: Dictionary = obj["ash_link"]
	var name := "object \"%s\" ash_link" % obj["id"]
	if not KNOWN_TYPES.has(link["becomes"]):
		errors.append("%s: becomes unknown type \"%s\"" % [name, link["becomes"]])
	if not _check_place(state, link["hour"], link["slot"], name, errors):
		return
	if state.terrain_at(link["hour"], link["slot"]) == GameStateScript.WALL:
		errors.append("%s: target %s in hour %d is a wall" % [name, _slot_text(link["slot"]), link["hour"]])
	var occupant := state.object_at(link["hour"], link["slot"])
	if not occupant.is_empty():
		errors.append("%s: target %s in hour %d already holds object \"%s\"" % [
			name, _slot_text(link["slot"]), link["hour"], occupant["id"]])


static func _check_stair(state: GameStateScript, obj: Dictionary, errors: Array[String]) -> void:
	var name := "stair \"%s\"" % obj["id"]
	if not obj.has("links_to"):
		errors.append("%s: has no links_to" % name)
		return
	var to: Dictionary = obj["links_to"]
	if not _check_place(state, to["hour"], to["slot"], name + " links_to", errors):
		return
	if state.terrain_at(to["hour"], to["slot"]) == GameStateScript.WALL:
		errors.append("%s: arrival %s in hour %d is a wall" % [name, _slot_text(to["slot"]), to["hour"]])


static func _check_shadows(state: GameStateScript, errors: Array[String]) -> void:
	var ids := state.shadows.keys()
	ids.sort()
	for id in ids:
		var sh: Dictionary = state.shadows[id]
		var name := "shadow \"%s\"" % id
		if not _check_place(state, sh["hour"], sh["slot"], name, errors):
			continue
		var where := "%s in hour %d" % [_slot_text(sh["slot"]), sh["hour"]]
		if state.terrain_at(sh["hour"], sh["slot"]) == GameStateScript.WALL:
			errors.append("%s: placed on a wall at %s" % [name, where])
		if state.object_at(sh["hour"], sh["slot"]).get("type") == "exit":
			errors.append("%s: placed on the exit at %s" % [name, where])
		if sh["hour"] == state.player_hour and sh["slot"] == state.player_slot:
			errors.append("%s: placed on the player start at %s" % [name, where])


static func _check_player_start(state: GameStateScript, errors: Array[String]) -> void:
	if not _check_place(state, state.player_hour, state.player_slot, "player start", errors):
		return
	var where := "%s in hour %d" % [_slot_text(state.player_slot), state.player_hour]
	var tile := state.terrain_at(state.player_hour, state.player_slot)
	if tile == GameStateScript.WALL:
		errors.append("player start: %s is a wall" % where)
	elif tile == GameStateScript.CHASM and not _fills_chasm(state.object_at(state.player_hour, state.player_slot)):
		errors.append("player start: %s is a chasm with no bridge or ash_path on it" % where)


## An INTACT bridge or an ash_path makes a chasm walkable (type table, 3.2).
static func _fills_chasm(obj: Dictionary) -> bool:
	if obj.is_empty():
		return false
	if obj["type"] == "bridge":
		return obj["state"] == GameStateScript.INTACT
	return obj["type"] == "ash_path"


## Reports an unknown hour or an out-of-grid slot. Returns true if both are fine.
static func _check_place(state: GameStateScript, hour: int, slot: Vector2i, name: String, errors: Array[String]) -> bool:
	if GameStateScript.order_index(hour) < 0:
		errors.append("%s: hour %d does not exist (use 12, 2, 4, 6, 8 or 10)" % [name, hour])
		return false
	if not state.in_grid(slot):
		errors.append("%s: slot %s is outside the %dx%d grid" % [name, _slot_text(slot), state.grid_w, state.grid_h])
		return false
	return true


static func _slot_text(slot: Vector2i) -> String:
	return "[%d, %d]" % [slot.x, slot.y]
