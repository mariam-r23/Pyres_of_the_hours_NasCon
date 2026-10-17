extends "res://tests/test_suite.gd"
## Tests for core/level_validator.gd: the L01 fixture passes, and each rule
## has a level that breaks it.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const Validator := preload("res://core/level_validator.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"


## A valid level. Hour 2 has a wall at [0, 0] and a chasm at [2, 2].
func _base() -> Dictionary:
	return {
		"id": "base",
		"rooms": [{"hour": 2, "terrain": ["#....", ".....", "..~..", ".....", "....."]}],
		"player": {"hour": 12, "slot": [0, 0]},
		"objects": [
			{"id": "crate_a", "type": "crate", "hour": 12, "slot": [1, 0], "flammable": true,
				"ash_link": {"hour": 2, "slot": [2, 2], "becomes": "ash_path"}},
			{"id": "stair_a", "type": "stair", "hour": 12, "slot": [4, 4], "flammable": false,
				"links_to": {"hour": 2, "slot": [1, 1]}},
			{"id": "exit_1", "type": "exit", "hour": 2, "slot": [4, 4], "flammable": false},
		],
		"shadows": [{"id": "sh_1", "hour": 2, "slot": [3, 3]}],
	}


func _load(data: Dictionary) -> GS:
	var result := Loader.load_dict(data)
	check_eq(result["error"], "", "fixture data loads")
	return result["state"]


## The object with this id in data["objects"] (edits change `data`).
func _obj(data: Dictionary, id: String) -> Dictionary:
	for obj in data["objects"]:
		if obj["id"] == id:
			return obj
	return {}


## Validates `state` and checks one error contains `expected`.
func _expect(state: GS, expected: String, label: String) -> void:
	var errors := Validator.validate(state)
	check(errors.any(func(e): return expected in e),
		"%s: expected an error containing \"%s\", got %s" % [label, expected, str(errors)])


func test_l01_fixture_is_valid() -> bool:
	var state: GS = Loader.load_file(L01_PATH)["state"]
	check_eq(Validator.validate(state), [] as Array[String], "L01 has no errors")
	return true


func test_base_is_valid() -> bool:
	check_eq(Validator.validate(_load(_base())), [] as Array[String], "base has no errors")
	return true


func test_object_slot_outside_grid() -> bool:
	var data := _base()
	_obj(data, "crate_a")["slot"] = [5, 0]
	_expect(_load(data), "object \"crate_a\": slot [5, 0] is outside the 5x5 grid", "object off grid")
	return true


func test_shadow_slot_outside_grid() -> bool:
	var data := _base()
	data["shadows"][0]["slot"] = [0, -1]
	_expect(_load(data), "shadow \"sh_1\": slot [0, -1] is outside the 5x5 grid", "shadow off grid")
	return true


func test_unknown_type() -> bool:
	var data := _base()
	_obj(data, "crate_a")["type"] = "key"
	_expect(_load(data), "object \"crate_a\": unknown type \"key\"", "unknown type")
	return true


func test_unknown_state() -> bool:
	# The loader already rejects bad states, so set one on the loaded state.
	var state := _load(_base())
	state.objects["crate_a"]["state"] = "BURNT"
	_expect(state, "object \"crate_a\": unknown state \"BURNT\"", "unknown state")
	return true


func test_no_exit() -> bool:
	var data := _base()
	data["objects"].erase(_obj(data, "exit_1"))
	_expect(_load(data), "level: no exit object", "no exit")
	return true


func test_two_exits() -> bool:
	var data := _base()
	data["objects"].append({"id": "exit_2", "type": "exit", "hour": 4, "slot": [0, 0], "flammable": false})
	_expect(_load(data), "level: 2 exit objects (exit_1, exit_2)", "two exits")
	return true


func test_two_objects_in_one_slot() -> bool:
	var data := _base()
	data["objects"].append({"id": "door_a", "type": "door", "hour": 12, "slot": [1, 0], "flammable": true})
	_expect(_load(data), "object \"door_a\": shares slot [1, 0] in hour 12 with object \"crate_a\"", "shared slot")
	return true


func test_ash_link_bad_hour() -> bool:
	var state := _load(_base())
	state.objects["crate_a"]["ash_link"]["hour"] = 3
	_expect(state, "object \"crate_a\" ash_link: hour 3 does not exist", "ash_link hour")
	return true


func test_ash_link_outside_grid() -> bool:
	var data := _base()
	_obj(data, "crate_a")["ash_link"]["slot"] = [2, 7]
	_expect(_load(data), "object \"crate_a\" ash_link: slot [2, 7] is outside the 5x5 grid", "ash_link off grid")
	return true


func test_ash_link_onto_wall() -> bool:
	var data := _base()
	_obj(data, "crate_a")["ash_link"]["slot"] = [0, 0]
	_expect(_load(data), "object \"crate_a\" ash_link: target [0, 0] in hour 2 is a wall", "ash_link wall")
	return true


func test_ash_link_onto_object() -> bool:
	var data := _base()
	_obj(data, "crate_a")["ash_link"]["slot"] = [4, 4]
	_expect(_load(data), "object \"crate_a\" ash_link: target [4, 4] in hour 2 already holds object \"exit_1\"", "ash_link occupied")
	return true


func test_ash_link_unknown_becomes() -> bool:
	var data := _base()
	_obj(data, "crate_a")["ash_link"]["becomes"] = "torch"
	_expect(_load(data), "object \"crate_a\" ash_link: becomes unknown type \"torch\"", "ash_link becomes")
	return true


func test_stair_without_links_to() -> bool:
	var data := _base()
	_obj(data, "stair_a").erase("links_to")
	_expect(_load(data), "stair \"stair_a\": has no links_to", "stair without links_to")
	return true


func test_stair_bad_hour() -> bool:
	var state := _load(_base())
	state.objects["stair_a"]["links_to"]["hour"] = 7
	_expect(state, "stair \"stair_a\" links_to: hour 7 does not exist", "stair hour")
	return true


func test_stair_outside_grid() -> bool:
	var data := _base()
	_obj(data, "stair_a")["links_to"]["slot"] = [-1, 1]
	_expect(_load(data), "stair \"stair_a\" links_to: slot [-1, 1] is outside the 5x5 grid", "stair off grid")
	return true


func test_stair_onto_wall() -> bool:
	var data := _base()
	_obj(data, "stair_a")["links_to"]["slot"] = [0, 0]
	_expect(_load(data), "stair \"stair_a\": arrival [0, 0] in hour 2 is a wall", "stair wall")
	return true


func test_shadow_on_wall() -> bool:
	var data := _base()
	data["shadows"][0]["slot"] = [0, 0]
	_expect(_load(data), "shadow \"sh_1\": placed on a wall at [0, 0] in hour 2", "shadow wall")
	return true


func test_shadow_on_chasm_is_allowed() -> bool:
	var data := _base()
	_obj(data, "crate_a").erase("ash_link")  # keep the chasm empty
	data["shadows"][0]["slot"] = [2, 2]
	check_eq(Validator.validate(_load(data)), [] as Array[String], "shadow on a chasm is fine")
	return true


func test_shadow_on_exit() -> bool:
	var data := _base()
	data["shadows"][0]["slot"] = [4, 4]
	_expect(_load(data), "shadow \"sh_1\": placed on the exit at [4, 4] in hour 2", "shadow exit")
	return true


func test_shadow_on_player_start() -> bool:
	var data := _base()
	data["shadows"][0]["hour"] = 12
	data["shadows"][0]["slot"] = [0, 0]
	_expect(_load(data), "shadow \"sh_1\": placed on the player start at [0, 0] in hour 12", "shadow player")
	return true


func test_player_outside_grid() -> bool:
	var data := _base()
	data["player"]["slot"] = [0, 5]
	_expect(_load(data), "player start: slot [0, 5] is outside the 5x5 grid", "player off grid")
	return true


func test_player_on_wall() -> bool:
	var data := _base()
	data["player"] = {"hour": 2, "slot": [0, 0]}
	_expect(_load(data), "player start: [0, 0] in hour 2 is a wall", "player wall")
	return true


func test_player_on_empty_chasm() -> bool:
	var data := _base()
	_obj(data, "crate_a").erase("ash_link")
	data["player"] = {"hour": 2, "slot": [2, 2]}
	_expect(_load(data), "player start: [2, 2] in hour 2 is a chasm with no bridge or ash_path on it", "player chasm")
	return true


func test_player_on_bridged_chasm() -> bool:
	var data := _base()
	_obj(data, "crate_a").erase("ash_link")
	data["objects"].append({"id": "bridge_a", "type": "bridge", "hour": 2, "slot": [2, 2], "flammable": true})
	data["player"] = {"hour": 2, "slot": [2, 2]}
	check_eq(Validator.validate(_load(data)), [] as Array[String], "intact bridge over the chasm is walkable")
	# A burned bridge no longer fills the chasm.
	_obj(data, "bridge_a")["state"] = "ASH"
	_expect(_load(data), "player start: [2, 2] in hour 2 is a chasm", "burned bridge")
	return true


func test_object_on_wall() -> bool:
	var data := _base()
	_obj(data, "exit_1")["slot"] = [0, 0]
	_expect(_load(data), "object \"exit_1\": placed on a wall at [0, 0] in hour 2", "object on wall")
	return true


func test_non_bridge_object_on_chasm() -> bool:
	var data := _base()
	_obj(data, "crate_a").erase("ash_link")
	_obj(data, "exit_1")["slot"] = [2, 2]
	_expect(_load(data), "object \"exit_1\": exit placed on a chasm at [2, 2] in hour 2", "exit on chasm")
	return true


func test_bridge_and_ash_path_on_chasm_are_allowed() -> bool:
	for type in ["bridge", "ash_path"]:
		var data := _base()
		_obj(data, "crate_a").erase("ash_link")
		data["objects"].append({"id": "filler", "type": type, "hour": 2, "slot": [2, 2], "flammable": type == "bridge"})
		check_eq(Validator.validate(_load(data)), [] as Array[String], type + " on a chasm is fine")
	return true


func test_player_on_intact_blocking_object() -> bool:
	for type in ["crate", "door"]:
		var data := _base()
		data["objects"].append({"id": "blocker", "type": type, "hour": 12, "slot": [0, 1], "flammable": true})
		data["player"]["slot"] = [0, 1]
		_expect(_load(data), "player start: [0, 1] in hour 12 holds INTACT %s \"blocker\", which blocks" % type, "player on " + type)
		# Once burned, it is walkable rubble or an open gate.
		_obj(data, "blocker")["state"] = "ASH"
		check_eq(Validator.validate(_load(data)), [] as Array[String], "player on ASH %s is fine" % type)
	return true


func test_shadow_id_equals_object_id() -> bool:
	var data := _base()
	data["shadows"][0]["id"] = "crate_a"
	_expect(_load(data), "shadow \"crate_a\": id is also used by an object", "shadow id clash")
	return true


func test_ash_id_clash() -> bool:
	var data := _base()
	data["objects"].append({"id": "crate_a_ash", "type": "crate", "hour": 4, "slot": [1, 1], "flammable": true})
	_expect(_load(data), "object \"crate_a_ash\": id clashes with the object \"crate_a\" creates when burned", "ash id clash")
	# Without an ash link on crate_a, that id is free.
	_obj(data, "crate_a").erase("ash_link")
	check_eq(Validator.validate(_load(data)), [] as Array[String], "no link, no clash")
	return true


func test_reports_every_problem_at_once() -> bool:
	var data := _base()
	_obj(data, "crate_a")["type"] = "key"
	data["objects"].erase(_obj(data, "exit_1"))
	data["shadows"][0]["slot"] = [0, 0]
	data["player"]["slot"] = [9, 9]
	var errors := Validator.validate(_load(data))
	check_eq(errors.size(), 4, "four problems reported (got %s)" % str(errors))
	return true
