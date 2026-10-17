extends "res://tests/test_suite.gd"
## Tests for core/turn_manager.gd: move, wait, interact, legal_actions.
## (Burn, sun, shadows, win and fail are not implemented yet.)

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const TM := preload("res://core/turn_manager.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"


func _l01() -> GS:
	return Loader.load_file(L01_PATH)["state"]


func _move(dir: String) -> Dictionary:
	return {"type": "move", "dir": dir}


## Applies actions in order, stopping at the first rejection. Returns the last result.
func _run(state: GS, actions: Array) -> Dictionary:
	var result := {"ok": true, "state": state, "events": [], "reason": ""}
	for action in actions:
		result = TM.apply_action(result["state"], action)
		if not result["ok"]:
			break
	return result


## Checks a rejection: reason, the same state object returned, only one event.
func _check_rejected(state: GS, result: Dictionary, reason: String, label: String) -> void:
	check_eq(result["ok"], false, label + ": ok")
	check_eq(result["reason"], reason, label + ": reason")
	check_eq(result["events"], [{"type": "action_rejected", "reason": reason}], label + ": events")
	check(result["state"] == state, label + ": returns the input state")


func test_walk_right() -> bool:
	var s := _l01()
	var result := TM.apply_action(s, _move("right"))
	check_eq(result["ok"], true, "ok")
	check_eq(result["reason"], "", "no reason")
	var after: GS = result["state"]
	check_eq(after.player_slot, Vector2i(1, 2), "player moved to [1,2]")
	check_eq(after.player_hour, 12, "same hour")
	check_eq(after.action_count, 1, "counter +1")
	check_eq(result["events"], [
		{"type": "moved", "from_hour": 12, "from_slot": Vector2i(0, 2), "to_hour": 12, "to_slot": Vector2i(1, 2)},
		{"type": "action_applied", "actions_used": 1},
	], "events: moved then action_applied")
	return true


func test_directions() -> bool:
	var s := _l01()  # player at [0,2] in hour 12
	check_eq(TM.apply_action(s, _move("up"))["state"].player_slot, Vector2i(0, 1), "up is y-1")
	check_eq(TM.apply_action(s, _move("down"))["state"].player_slot, Vector2i(0, 3), "down is y+1")
	return true


func test_move_into_wall_is_rejected_and_free() -> bool:
	var s := _l01()
	s.terrain[12] = [".....", ".....", ".#...", ".....", "....."]
	var before := s.hash_key()
	var result := TM.apply_action(s, _move("right"))
	_check_rejected(s, result, "blocked_terrain", "wall")
	check_eq(s.action_count, 0, "counter unchanged")
	check_eq(s.player_slot, Vector2i(0, 2), "player did not move")
	check_eq(s.hash_key(), before, "hash_key unchanged")
	return true


func test_other_move_rejections() -> bool:
	var s := _l01()
	_check_rejected(s, TM.apply_action(s, _move("left")), "out_of_bounds", "off the left edge")
	var at_crate: GS = _run(s, [_move("right")])["state"]
	_check_rejected(at_crate, TM.apply_action(at_crate, _move("right")), "blocked_object", "INTACT crate")
	return true


func test_wait_advances_counter() -> bool:
	var s := _l01()
	var result := TM.apply_action(s, {"type": "wait"})
	check_eq(result["ok"], true, "ok")
	check_eq(result["state"].action_count, 1, "counter +1")
	check_eq(result["state"].player_slot, s.player_slot, "player did not move")
	check_eq(result["events"], [{"type": "action_applied", "actions_used": 1}], "only action_applied")
	check_eq(_run(s, [{"type": "wait"}, {"type": "wait"}, {"type": "wait"}])["state"].action_count, 3, "three waits")
	return true


func test_input_state_is_never_mutated() -> bool:
	var s := _l01()
	var before := s.hash_key()
	for action in [_move("right"), _move("up"), {"type": "wait"}, {"type": "interact"}, _move("left"), {"type": "bogus"}]:
		var result := TM.apply_action(s, action)
		check_eq(s.hash_key(), before, "input unchanged after %s" % str(action))
		if result["ok"]:
			check(result["state"] != s, "%s returns a new state" % str(action))
	return true


func test_interact_on_stair() -> bool:
	var s := _l01()
	s.objects["crate_a"]["state"] = GS.ASH  # clear the way to the stair at [4,2]
	var on_stair := _run(s, [_move("right"), _move("right"), _move("right"), _move("right")])
	check_eq(on_stair["ok"], true, "walked onto the stair")
	var before: GS = on_stair["state"]
	check_eq(before.player_slot, Vector2i(4, 2), "standing on the stair")
	var result := TM.apply_action(before, {"type": "interact"})
	check_eq(result["ok"], true, "interact ok")
	var after: GS = result["state"]
	check_eq(after.player_hour, 2, "arrived in hour 2")
	check_eq(after.player_slot, Vector2i(0, 2), "arrived at [0,2]")
	check_eq(after.action_count, 5, "interact costs an action")
	check_eq(result["events"], [
		{"type": "moved", "from_hour": 12, "from_slot": Vector2i(4, 2), "to_hour": 2, "to_slot": Vector2i(0, 2)},
		{"type": "action_applied", "actions_used": 5},
	], "events")
	return true


func test_interact_off_stair_is_rejected() -> bool:
	var s := _l01()
	_check_rejected(s, TM.apply_action(s, {"type": "interact"}), "not_on_stair", "not on a stair")
	return true


func test_interact_arrival_blocked() -> bool:
	var s := _l01()
	s.player_slot = Vector2i(4, 2)  # on the stair
	s.terrain[2] = [".....", ".....", "#.~..", ".....", "....."]  # wall on the arrival slot
	_check_rejected(s, TM.apply_action(s, {"type": "interact"}), "arrival_blocked", "arrival is a wall")
	return true


func test_unknown_actions_are_rejected() -> bool:
	var s := _l01()
	for action in [{"type": "fly"}, {}, {"type": "move"}, {"type": "move", "dir": "north"}, "move:right", null]:
		_check_rejected(s, TM.apply_action(s, action), "unknown_action", "action %s" % str(action))
	return true


func test_legal_actions() -> bool:
	var s := _l01()  # [0,2] hour 12: left is off the grid, not on a stair
	var legal := TM.legal_actions(s)
	check_eq(legal, [_move("up"), _move("down"), _move("right"), {"type": "wait"}], "legal at start")
	var at_crate: GS = _run(s, [_move("right")])["state"]
	check(not TM.legal_actions(at_crate).has(_move("right")), "no move into the crate")
	for state in [s, at_crate]:
		for action in TM.legal_actions(state):
			check(TM.apply_action(state, action)["ok"], "legal action %s is valid" % str(action))
	return true


func test_legal_actions_on_stair_include_interact() -> bool:
	var s := _l01()
	s.player_slot = Vector2i(4, 2)
	check(TM.legal_actions(s).has({"type": "interact"}), "interact is legal on the stair")
	return true


func test_determinism() -> bool:
	# [0,2] -> [0,1] -> [1,1] -> [2,1] -> wait -> [2,0] -> [1,0]
	var actions := [_move("up"), _move("right"), _move("right"), {"type": "wait"}, _move("up"), _move("left")]
	var a := _run(_l01(), actions)
	var b := _run(_l01(), actions)
	check_eq(a["ok"], true, "sequence is valid")
	check_eq(a["state"].hash_key(), b["state"].hash_key(), "same actions, same hash_key")
	check_eq(a["state"].action_count, 6, "six actions used")
	return true
