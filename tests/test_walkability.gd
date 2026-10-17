extends "res://tests/test_suite.gd"
## Tests for core/walkability.gd (terrain 3.1 + type table 3.2, no shadows).

const GS := preload("res://core/game_state.gd")
const Walk := preload("res://core/walkability.gd")

const FLOOR := Vector2i(0, 0)
const WALL := Vector2i(1, 0)
const CHASM := Vector2i(2, 0)


## Hour 12: floor at [0,0], wall at [1,0], chasm at [2,0]. Other hours all floor.
func _state() -> GS:
	var s: GS = GS.new()
	s.terrain[12] = [".#~..", ".....", ".....", ".....", "....."]
	return s


## A state with one object of `type` / `state` at `slot` in hour 12.
func _with(type: String, state: String, slot: Vector2i) -> GS:
	var s := _state()
	s.objects["o"] = {"id": "o", "type": type, "hour": 12, "slot": slot, "state": state, "flammable": false}
	return s


## Checks walkability at (12, slot): `reason` "" means walkable.
func _expect(s: GS, slot: Vector2i, reason: String, label: String) -> void:
	var result := Walk.check_walkable(s, 12, slot)
	check_eq(result, {"ok": reason == "", "reason": reason}, label)
	check_eq(Walk.is_walkable(s, 12, slot), reason == "", label + " (is_walkable)")


func test_floor() -> bool:
	_expect(_state(), FLOOR, "", "floor")
	return true


func test_wall() -> bool:
	_expect(_state(), WALL, "blocked_terrain", "wall")
	return true


func test_empty_chasm() -> bool:
	_expect(_state(), CHASM, "blocked_terrain", "empty chasm")
	return true


func test_chasm_with_intact_bridge() -> bool:
	_expect(_with("bridge", GS.INTACT, CHASM), CHASM, "", "chasm + INTACT bridge")
	return true


func test_chasm_with_ash_bridge() -> bool:
	_expect(_with("bridge", GS.ASH, CHASM), CHASM, "blocked_terrain", "chasm + ASH bridge")
	return true


func test_chasm_with_gone_bridge() -> bool:
	_expect(_with("bridge", GS.GONE, CHASM), CHASM, "blocked_terrain", "chasm + GONE bridge")
	return true


func test_chasm_with_ash_path() -> bool:
	_expect(_with("ash_path", GS.INTACT, CHASM), CHASM, "", "chasm + ash_path")
	return true


func test_bridge_on_floor() -> bool:
	_expect(_with("bridge", GS.INTACT, FLOOR), FLOOR, "", "INTACT bridge on floor")
	_expect(_with("bridge", GS.ASH, FLOOR), FLOOR, "", "ASH bridge on floor reverts to floor")
	return true


func test_intact_crate() -> bool:
	_expect(_with("crate", GS.INTACT, FLOOR), FLOOR, "blocked_object", "INTACT crate")
	return true


func test_ash_crate() -> bool:
	_expect(_with("crate", GS.ASH, FLOOR), FLOOR, "", "ASH crate (rubble)")
	return true


func test_intact_door() -> bool:
	_expect(_with("door", GS.INTACT, FLOOR), FLOOR, "blocked_object", "INTACT door")
	return true


func test_ash_door() -> bool:
	_expect(_with("door", GS.ASH, FLOOR), FLOOR, "", "ASH door (burned open)")
	return true


func test_gone_crate_is_empty() -> bool:
	_expect(_with("crate", GS.GONE, FLOOR), FLOOR, "", "GONE crate counts as empty")
	return true


func test_stair() -> bool:
	_expect(_with("stair", GS.INTACT, FLOOR), FLOOR, "", "stair")
	return true


func test_exit() -> bool:
	_expect(_with("exit", GS.INTACT, FLOOR), FLOOR, "", "exit")
	return true


func test_out_of_bounds() -> bool:
	var s := _state()
	for slot in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(5, 0), Vector2i(0, 5)]:
		_expect(s, slot, "out_of_bounds", "slot %s" % slot)
	var result := Walk.check_walkable(s, 3, FLOOR)
	check_eq(result["reason"], "out_of_bounds", "hour 3 does not exist")
	return true


func test_other_hours_use_their_own_terrain() -> bool:
	var s := _state()
	check(Walk.is_walkable(s, 2, WALL), "[1,0] is floor in hour 2")
	check(Walk.is_walkable(s, 2, CHASM), "[2,0] is floor in hour 2")
	return true


func test_loaded_l01() -> bool:
	var s: GS = preload("res://core/level_loader.gd").load_file("res://tests/fixtures/L01_first_crate.json")["state"]
	check_eq(Walk.check_walkable(s, 12, Vector2i(2, 2))["reason"], "blocked_object", "L01 crate blocks")
	check_eq(Walk.check_walkable(s, 2, Vector2i(2, 2))["reason"], "blocked_terrain", "L01 chasm blocks before the burn")
	check(Walk.is_walkable(s, 12, Vector2i(4, 2)), "L01 stair is walkable")
	check(Walk.is_walkable(s, 2, Vector2i(4, 2)), "L01 exit is walkable")
	return true
