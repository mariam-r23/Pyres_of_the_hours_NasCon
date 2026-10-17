extends "res://tests/test_suite.gd"
## Tests for the sun and shadows (core/sun.gd via core/turn_manager.gd), 3.4 and 3.5.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const TM := preload("res://core/turn_manager.gd")
const Sun := preload("res://core/sun.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"

const WAIT := {"type": "wait"}


## An all-floor level: player in `player_hour` at [0,0], exit in hour 10 at
## [4,4], and the given shadows ({id: [hour, [x, y]]}).
func _level(player_hour: int, shadows: Dictionary, actions_per_hour: int = 3, start_index: int = 0) -> GS:
	var data := {
		"id": "sun_test",
		"sun": {"start_index": start_index, "actions_per_hour": actions_per_hour},
		"player": {"hour": player_hour, "slot": [0, 0]},
		"objects": [{"id": "exit_1", "type": "exit", "hour": 10, "slot": [4, 4], "flammable": false}],
		"shadows": [],
	}
	for id in shadows:
		data["shadows"].append({"id": id, "hour": shadows[id][0], "slot": shadows[id][1]})
	var result := Loader.load_dict(data)
	check_eq(result["error"], "", "test level loads")
	return result["state"]


func _move(dir: String) -> Dictionary:
	return {"type": "move", "dir": dir}


## Applies actions; fails the test at the first rejection. Returns
## {state, events} with every event from every action, in order.
func _play(state: GS, actions: Array) -> Dictionary:
	var events: Array = []
	for i in actions.size():
		var result := TM.apply_action(state, actions[i])
		if not result["ok"]:
			check(false, "action %d (%s) rejected: %s" % [i, str(actions[i]), result["reason"]])
			break
		state = result["state"]
		events.append_array(result["events"])
	return {"state": state, "events": events}


func _after(state: GS, actions: Array) -> GS:
	return _play(state, actions)["state"]


## Checks a rejection is free: reason, single event, input returned and unchanged.
func _expect_rejected(s: GS, action: Dictionary, reason: String, label: String) -> void:
	var before := s.hash_key()
	var result := TM.apply_action(s, action)
	check_eq(result["reason"], reason, label + ": reason")
	check_eq(result["events"], [{"type": "action_rejected", "reason": reason}], label + ": only action_rejected")
	check(result["state"] == s, label + ": returns the input state")
	check_eq(s.hash_key(), before, label + ": hash_key unchanged")


func _count(events: Array, type: String) -> int:
	return events.filter(func(e): return e["type"] == type).size()


func test_sun_math_three_actions_per_hour() -> bool:
	var s := _level(12, {}, 3)
	var expected := [0, 0, 0, 1, 1, 1, 2, 2, 2, 3]
	for count in expected.size():
		check_eq(Sun.sun_index(s), expected[count], "index after %d actions" % count)
		s = _after(s, [WAIT])
	return true


func test_sun_math_one_action_per_hour() -> bool:
	var s := _level(12, {}, 1)
	for count in 6:
		check_eq(Sun.sun_index(s), count, "index after %d actions" % count)
		check_eq(TM.is_hour_passed(s, GS.HOUR_ORDER[count]), false, "hour %d not passed yet" % GS.HOUR_ORDER[count])
		s = _after(s, [WAIT])
		check_eq(TM.is_hour_passed(s, GS.HOUR_ORDER[count]), true, "hour %d passed" % GS.HOUR_ORDER[count])
	return true


func test_sun_events_at_the_right_actions() -> bool:
	var s := _level(12, {}, 3)
	var first := TM.apply_action(s, WAIT)
	check_eq(first["events"], [{"type": "action_applied", "actions_used": 1}], "action 1: no sun events")
	s = _after(s, [WAIT, WAIT])
	var third := TM.apply_action(s, WAIT)
	check_eq(third["events"], [
		{"type": "sun_advanced", "from_index": 0, "to_index": 1},
		{"type": "hour_passed", "hour": 12},
		{"type": "action_applied", "actions_used": 3},
	], "action 3: sun_advanced, hour_passed, action_applied")
	var six: Array = _play(_level(12, {}, 3), [WAIT, WAIT, WAIT, WAIT, WAIT, WAIT])["events"]
	check_eq(_count(six, "sun_advanced"), 2, "two sun advances in six actions")
	check_eq(six.filter(func(e): return e["type"] == "hour_passed").map(func(e): return e["hour"]), [12, 2], "hours 12 then 2")
	return true


func test_start_index_makes_shadows_active_from_the_start() -> bool:
	var s := _level(2, {"sh": [2, [1, 0]]}, 3, 2)
	check(TM.is_hour_passed(s, 12), "12 passed at load")
	check(TM.is_hour_passed(s, 2), "2 passed at load")
	check(not TM.is_hour_passed(s, 4), "4 not passed")
	check(not Sun.active_shadow_at(s, 2, Vector2i(1, 0)).is_empty(), "shadow active at load")
	_expect_rejected(s, _move("right"), "shadow_blocks", "active from the start")
	var events: Array = TM.apply_action(s, WAIT)["events"]
	check_eq(_count(events, "shadow_appeared"), 0, "no shadow_appeared for shadows active at load")
	return true


func test_dormant_shadow_does_not_block() -> bool:
	var s := _level(2, {"sh": [2, [1, 0]]}, 3)
	var result := TM.apply_action(s, _move("right"))
	check_eq(result["ok"], true, "can walk onto a dormant shadow")
	check_eq(result["state"].player_slot, Vector2i(1, 0), "player on the shadow's tile")
	return true


func test_shadow_blocks_once_its_hour_is_passed() -> bool:
	var s := _level(2, {"sh": [2, [2, 0]]}, 1)
	var run := _play(s, [WAIT, WAIT])  # index 2: hours 12 and 2 passed
	var events: Array = run["events"]
	check_eq(_count(events, "shadow_appeared"), 1, "shadow_appeared fires once")
	check(events.has({"type": "shadow_appeared", "id": "sh", "hour": 2, "slot": Vector2i(2, 0)}), "shadow_appeared fields")
	var order := events.slice(events.size() - 4).map(func(e): return e["type"])
	check_eq(order, ["sun_advanced", "hour_passed", "shadow_appeared", "action_applied"], "event order on action 2")
	var later := _play(run["state"], [_move("right"), WAIT, WAIT])
	check_eq(_count(later["events"], "shadow_appeared"), 0, "never fires again")
	_expect_rejected(later["state"], _move("right"), "shadow_blocks", "active shadow")
	return true


func test_walkability_reasons_come_before_shadow_blocks() -> bool:
	var s := _level(2, {"sh": [2, [1, 0]]}, 3, 2)
	s.terrain[2] = [".#...", ".....", ".....", ".....", "....."]  # wall under the shadow
	_expect_rejected(s, _move("right"), "blocked_terrain", "wall wins over shadow")
	return true


func test_shadow_wakes_on_you_for_move() -> bool:
	var s := _after(_level(2, {"sh": [2, [1, 0]]}, 1), [WAIT])  # index 1; next action passes hour 2
	_expect_rejected(s, _move("right"), "shadow_wakes_on_you", "move onto a waking shadow")
	check_eq(s.action_count, 1, "counter unchanged")
	return true


func test_shadow_wakes_on_you_for_wait() -> bool:
	var s := _after(_level(2, {"sh": [2, [1, 0]]}, 1), [_move("right")])  # on the dormant shadow, index 1
	check_eq(s.player_slot, Vector2i(1, 0), "standing on the dormant shadow")
	_expect_rejected(s, WAIT, "shadow_wakes_on_you", "wait while it wakes")
	check_eq(s.action_count, 1, "counter unchanged")
	check_eq(TM.apply_action(s, _move("right"))["ok"], true, "stepping off is allowed")
	return true


func test_ash_target_with_active_shadow() -> bool:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.player_slot = Vector2i(1, 2)
	s.shadows["sh"] = {"id": "sh", "hour": 2, "slot": Vector2i(2, 2)}  # on the ash-link target
	check_eq(TM.apply_action(s, {"type": "burn", "dir": "right"})["ok"], true, "dormant shadow on the target is fine")
	s.sun_start_index = 2  # hour 2 passed: the shadow is active
	_expect_rejected(s, {"type": "burn", "dir": "right"}, "ash_target_occupied", "active shadow on the target")
	return true


func test_arrival_blocked_by_active_shadow() -> bool:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.player_slot = Vector2i(4, 2)  # on the stair
	s.shadows["sh"] = {"id": "sh", "hour": 2, "slot": Vector2i(0, 2)}  # on the arrival slot
	check_eq(TM.apply_action(s, {"type": "interact"})["ok"], true, "dormant shadow on arrival is fine")
	s.sun_start_index = 2
	_expect_rejected(s, {"type": "interact"}, "arrival_blocked", "active shadow on arrival")
	return true


## L01 with hour 12 already passed and shadows around the crate at [2,2].
func _burn_setup(start_index: int) -> GS:
	var s: GS = Loader.load_file(L01_PATH)["state"]
	s.sun_start_index = start_index
	s.player_slot = Vector2i(1, 2)
	for entry in [["up", Vector2i(2, 1)], ["down", Vector2i(2, 3)], ["diag", Vector2i(3, 1)], ["on", Vector2i(2, 2)]]:
		s.shadows[entry[0]] = {"id": entry[0], "hour": 12, "slot": entry[1]}
	s.shadows["other_hour"] = {"id": "other_hour", "hour": 2, "slot": Vector2i(2, 1)}
	return s


func test_burn_destroys_adjacent_active_shadows() -> bool:
	var s := _burn_setup(1)  # hour 12 passed: its shadows are active; hour 2 is not
	var result := TM.apply_action(s, {"type": "burn", "dir": "right"})
	check_eq(result["ok"], true, "burn ok")
	var after: GS = result["state"]
	check(not after.shadows.has("up"), "adjacent (up) destroyed")
	check(not after.shadows.has("down"), "adjacent (down) destroyed")
	check(after.shadows.has("diag"), "diagonal survives")
	check(after.shadows.has("on"), "shadow on the burned slot survives")
	check(after.shadows.has("other_hour"), "shadow in another hour survives")
	check_eq(result["events"].map(func(e): return e["type"]),
		["burned", "ash_moved", "shadow_destroyed", "shadow_destroyed", "action_applied"], "event order")
	check(result["events"].has({"type": "shadow_destroyed", "id": "up", "hour": 12}), "shadow_destroyed fields")
	check(after.hash_key() != s.duplicate_deep().hash_key(), "hash changes")
	# Destroyed shadows stay gone, and never "appear" again.
	var later := _play(after, [WAIT, WAIT, WAIT, WAIT, WAIT, WAIT])
	check(not later["state"].shadows.has("up"), "still gone later")
	check(not later["events"].any(func(e): return e.get("id") in ["up", "down"]), "no later events for them")
	return true


func test_burn_does_not_destroy_dormant_shadows() -> bool:
	var s := _burn_setup(0)  # nothing passed: every shadow is dormant
	var result := TM.apply_action(s, {"type": "burn", "dir": "right"})
	check_eq(result["ok"], true, "burn ok")
	check_eq(result["state"].shadows.size(), 5, "no shadow destroyed")
	check_eq(_count(result["events"], "shadow_destroyed"), 0, "no shadow_destroyed event")
	return true


func test_input_never_mutated_and_determinism() -> bool:
	var s := _burn_setup(1)
	var before := s.hash_key()
	for action in [{"type": "burn", "dir": "right"}, WAIT, _move("up"), _move("down"), {"type": "interact"}]:
		TM.apply_action(s, action)
		check_eq(s.hash_key(), before, "input unchanged after %s" % str(action))
	var actions := [{"type": "burn", "dir": "right"}, WAIT, WAIT, _move("up"), WAIT]
	var a := _play(_burn_setup(1), actions)
	var b := _play(_burn_setup(1), actions)
	check_eq(a["state"].hash_key(), b["state"].hash_key(), "same hash_key")
	check_eq(a["events"], b["events"], "same events")
	return true
