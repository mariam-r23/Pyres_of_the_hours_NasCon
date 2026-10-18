extends "res://tests/test_suite.gd"
## Tests for core/level_loader.gd.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"


## The smallest level the loader accepts: everything optional left out.
func _minimal() -> Dictionary:
	return {
		"id": "tiny",
		"player": {"hour": 12, "slot": [0, 0]},
		"objects": [{"id": "exit_1", "type": "exit", "hour": 12, "slot": [4, 4], "flammable": false}],
	}


## Loads `data` and checks it fails with an error containing `expected`.
func _expect_error(data: Variant, expected: String, label: String) -> void:
	var result := Loader.load_dict(data)
	check(result["state"] == null, label + ": state is null")
	check(expected in result["error"], "%s: error should contain \"%s\", got \"%s\"" % [label, expected, result["error"]])


func test_loads_l01_fixture() -> bool:
	var result := Loader.load_file(L01_PATH)
	check_eq(result["error"], "", "no error")
	var s: GS = result["state"]
	check_eq(s.level_id, "L01_first_crate", "id")
	check_eq(Vector2i(s.grid_w, s.grid_h), Vector2i(5, 5), "grid")
	check_eq(s.sun_start_index, 0, "sun start")
	check_eq(s.actions_per_hour, 3, "actions per hour")
	check_eq(s.player_hour, 12, "player hour")
	check_eq(s.player_slot, Vector2i(0, 2), "player slot")
	check_eq(s.action_count, 0, "action count")
	check_eq(s.objects.size(), 3, "object count")
	check_eq(s.shadows.size(), 0, "no shadows")
	return true


func test_l01_terrain() -> bool:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	check_eq(s.terrain_at(2, Vector2i(2, 0)), GS.CHASM, "hour 2 chasm column")
	check_eq(s.terrain_at(2, Vector2i(1, 0)), GS.FLOOR, "hour 2 floor")
	check_eq(s.terrain_at(12, Vector2i(2, 2)), GS.FLOOR, "hour 12 floor")
	for hour in [4, 6, 8, 10]:
		check_eq(s.terrain[hour], [".....", ".....", ".....", ".....", "....."], "unlisted hour %d is all floor" % hour)
	return true


func test_l01_objects() -> bool:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	var crate: Dictionary = s.objects["crate_a"]
	check_eq(crate["type"], "crate", "crate type")
	check_eq(crate["hour"], 12, "crate hour")
	check_eq(crate["slot"], Vector2i(2, 2), "crate slot is a Vector2i")
	check_eq(crate["state"], GS.INTACT, "crate state")
	check_eq(crate["flammable"], true, "crate flammable")
	check_eq(crate["ash_link"], {"hour": 2, "slot": Vector2i(2, 2), "becomes": "ash_path"}, "ash_link")
	check(not crate.has("links_to"), "crate has no links_to")
	var stair: Dictionary = s.objects["stair_12"]
	check_eq(stair["links_to"], {"hour": 2, "slot": Vector2i(0, 2)}, "links_to")
	check(not stair.has("ash_link"), "stair has no ash_link")
	check_eq(s.object_at(2, Vector2i(4, 2)).get("id"), "exit_1", "exit found by slot")
	return true


func test_l01_meta() -> bool:
	var meta: Dictionary = Loader.load_file(L01_PATH)["meta"]
	check_eq(meta["title"], "Something Warm", "title")
	check_eq(meta["act"], 1, "act")
	check_eq(meta["spirit_mood"], "amused", "spirit_mood")
	check_eq(meta["mood_weights"], {"amused": 0.6, "annoyed": 0.2, "triumphant": 0.2}, "mood_weights")
	check_eq(meta["par_actions"], 10, "par_actions")
	return true


func test_defaults_for_optional_fields() -> bool:
	var result := Loader.load_dict(_minimal())
	check_eq(result["error"], "", "no error")
	var s: GS = result["state"]
	check_eq(Vector2i(s.grid_w, s.grid_h), Vector2i(5, 5), "default grid")
	check_eq(s.sun_start_index, 0, "default start index")
	check_eq(s.actions_per_hour, 3, "default actions per hour")
	check_eq(s.terrain.size(), 6, "every hour has terrain")
	check_eq(s.objects["exit_1"]["state"], GS.INTACT, "state defaults to INTACT")
	var meta: Dictionary = result["meta"]
	check_eq(meta["act"], 1, "default act")
	check_eq(meta["spirit_mood"], "amused", "default mood")
	check_eq(meta["mood_weights"], {}, "default weights")
	check_eq(meta["par_actions"], -1, "no par")
	check_eq(meta["title"], "", "no title")
	return true


func test_shadows_and_other_grid() -> bool:
	var data := _minimal()
	data["grid"] = {"w": 3, "h": 2}
	data["sun"] = {"start_index": 2, "actions_per_hour": 4}
	data["rooms"] = [{"hour": 6, "terrain": ["#~.", "..."]}]
	data["objects"][0]["slot"] = [2, 1]
	data["shadows"] = [{"id": "sh_1", "hour": 2, "slot": [1, 0]}]
	var result := Loader.load_dict(data)
	check_eq(result["error"], "", "no error")
	var s: GS = result["state"]
	check_eq(Vector2i(s.grid_w, s.grid_h), Vector2i(3, 2), "grid 3x2")
	check_eq(s.sun_start_index, 2, "start index")
	check_eq(s.actions_per_hour, 4, "actions per hour")
	check_eq(s.terrain[6], ["#~.", "..."], "hour 6 terrain")
	check_eq(s.terrain[12], ["...", "..."], "unlisted room fits the grid")
	check_eq(s.shadows["sh_1"], {"id": "sh_1", "hour": 2, "slot": Vector2i(1, 0)}, "shadow")
	return true


func test_loaded_state_copies_and_hashes() -> bool:
	var a: GS = Loader.load_file(L01_PATH)["state"]
	var b: GS = Loader.load_file(L01_PATH)["state"]
	check_eq(a.hash_key(), b.hash_key(), "two loads hash the same")
	check_eq(a.duplicate_deep().hash_key(), a.hash_key(), "copy hashes the same")
	return true


func test_file_and_json_errors() -> bool:
	var missing := Loader.load_file("res://tests/fixtures/does_not_exist.json")
	check(missing["state"] == null, "missing file: state is null")
	check("cannot open file" in missing["error"], "missing file error: " + missing["error"])
	var broken := Loader.load_json_string("{ \"id\": \"x\", ", "broken.json")
	check(broken["state"] == null, "invalid JSON: state is null")
	check("broken.json: invalid JSON" in broken["error"], "invalid JSON error: " + broken["error"])
	_expect_error([1, 2], "expected a JSON object at the top level", "top level is a list")
	_expect_error("hello", "expected a JSON object at the top level", "top level is a string")
	return true


func test_missing_fields() -> bool:
	for key in ["id", "player", "objects"]:
		var data := _minimal()
		data.erase(key)
		_expect_error(data, "%s: missing required field" % key, "missing " + key)
	for key in ["id", "type", "hour", "slot", "flammable"]:
		var data := _minimal()
		data["objects"][0].erase(key)
		_expect_error(data, "objects[0].%s: missing required field" % key, "missing object " + key)
	var data := _minimal()
	data["objects"][0]["ash_link"] = {"hour": 2, "slot": [1, 1]}
	_expect_error(data, "objects[0].ash_link.becomes: missing required field", "ash_link without becomes")
	data = _minimal()
	data["rooms"] = [{"hour": 2}]
	_expect_error(data, "rooms[0].terrain: missing required field", "room without terrain")
	return true


func test_wrong_types() -> bool:
	var cases := {
		"slot is a string": [func(d): d["player"]["slot"] = "0,0", "player.slot: expected [x, y]"],
		"slot has 3 numbers": [func(d): d["player"]["slot"] = [0, 0, 0], "player.slot: expected [x, y]"],
		"slot has a float": [func(d): d["player"]["slot"] = [0.5, 1], "player.slot.x: expected an integer"],
		"hour is a string": [func(d): d["player"]["hour"] = "12", "player.hour: expected an integer"],
		"hour is not an hour": [func(d): d["player"]["hour"] = 3, "player.hour: 3 is not an hour"],
		"flammable is a string": [func(d): d["objects"][0]["flammable"] = "no", "objects[0].flammable: expected true or false"],
		"bad state": [func(d): d["objects"][0]["state"] = "BURNT", "objects[0].state: must be INTACT, ASH or GONE"],
		"objects is an object": [func(d): d["objects"] = {}, "objects: expected a list"],
		"object is a number": [func(d): d["objects"] = [7], "objects[0]: expected an object"],
		"grid w is a float": [func(d): d["grid"] = {"w": 4.5, "h": 5}, "grid.w: expected an integer"],
		"grid is zero": [func(d): d["grid"] = {"w": 0, "h": 5}, "grid: w and h must be at least 1"],
		"sun start too big": [func(d): d["sun"] = {"start_index": 6}, "sun.start_index: must be 0 to 5"],
		"actions per hour zero": [func(d): d["sun"] = {"actions_per_hour": 0}, "sun.actions_per_hour: must be at least 1"],
		"mood weight not a number": [func(d): d["mood_weights"] = {"amused": "lots"}, "mood_weights.amused: expected a number"],
		"empty id": [func(d): d["id"] = "", "id: must not be empty"],
	}
	for label in cases:
		var data := _minimal()
		cases[label][0].call(data)
		_expect_error(data, cases[label][1], label)
	return true


func test_terrain_errors() -> bool:
	var cases := {
		"unknown character": [["..x..", ".....", ".....", ".....", "....."], "rooms[0].terrain[0]: unknown terrain character 'x' at x=2"],
		"too few rows": [[".....", "....."], "rooms[0].terrain: expected 5 rows, got 2"],
		"short row": [[".....", "....", ".....", ".....", "....."], "rooms[0].terrain[1]: expected 5 characters, got 4"],
		"row not a string": [[".....", 5, ".....", ".....", "....."], "rooms[0].terrain[1]: expected a string"],
	}
	for label in cases:
		var data := _minimal()
		data["rooms"] = [{"hour": 2, "terrain": cases[label][0]}]
		_expect_error(data, cases[label][1], label)
	var data := _minimal()
	var floor_rows := [".....", ".....", ".....", ".....", "....."]
	data["rooms"] = [{"hour": 2, "terrain": floor_rows}, {"hour": 2, "terrain": floor_rows}]
	_expect_error(data, "rooms[1].hour: hour 2 is listed twice", "duplicate room")
	return true


func test_duplicate_ids() -> bool:
	var data := _minimal()
	data["objects"].append({"id": "exit_1", "type": "crate", "hour": 2, "slot": [1, 1], "flammable": true})
	_expect_error(data, "objects[1].id: duplicate id \"exit_1\"", "duplicate object id")
	data = _minimal()
	data["shadows"] = [{"id": "sh", "hour": 2, "slot": [1, 1]}, {"id": "sh", "hour": 4, "slot": [1, 1]}]
	_expect_error(data, "shadows[1].id: duplicate id \"sh\"", "duplicate shadow id")
	return true


func test_reports_every_problem_at_once() -> bool:
	var data := _minimal()
	data.erase("id")
	data["player"]["hour"] = 5
	data["objects"][0]["flammable"] = 1
	var result := Loader.load_dict(data)
	var lines: PackedStringArray = result["error"].split("\n")
	check_eq(lines.size(), 3, "three problems, one line each (got: %s)" % result["error"])
	return true


func test_stray_spirit_lines_field_is_tolerated() -> bool:
	# spirit_lines is no longer part of the level format (lines come from
	# dialogue/lines.json), but an old level file that still has it must load.
	var data := _minimal()
	data["spirit_lines"] = {"on_burn": "Oh, that was fun.", "on_solve": "You're no fun when you win."}
	var result := Loader.load_dict(data)
	check_eq(result["error"], "", "loads without errors")
	check(result["state"] != null, "state created")
	return true
