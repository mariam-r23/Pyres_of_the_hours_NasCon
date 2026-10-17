extends "res://tests/test_suite.gd"
## Tests for burning and ash links (core/ash_transfer.gd via core/turn_manager.gd).
## (Shadows, sun, win and fail are not implemented yet.)

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const TM := preload("res://core/turn_manager.gd")
const Walk := preload("res://core/walkability.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"

## Section 6.1 solution.
const L01_SOLUTION := ["move:right", "burn:right", "move:right", "move:right", "move:right",
	"interact", "move:right", "move:right", "move:right", "move:right"]


func _l01() -> GS:
	return Loader.load_file(L01_PATH)["state"]


## "move:right" -> {"type": "move", "dir": "right"} (test shorthand, 6.4).
func _action(short: String) -> Dictionary:
	var parts := short.split(":")
	return {"type": parts[0]} if parts.size() == 1 else {"type": parts[0], "dir": parts[1]}


## Applies shorthand actions; fails the test at the first rejection.
func _play(state: GS, actions: Array) -> GS:
	for i in actions.size():
		var result := TM.apply_action(state, _action(actions[i]))
		if not result["ok"]:
			check(false, "action %d (%s) rejected: %s" % [i, actions[i], result["reason"]])
			return state
		state = result["state"]
	return state


## Checks a burn in `dir` is rejected for `reason`, is free and changes nothing.
func _expect_rejected(s: GS, dir: String, reason: String, label: String) -> void:
	var before := s.hash_key()
	var count_before := s.action_count
	var result := TM.apply_action(s, {"type": "burn", "dir": dir})
	check_eq(result["ok"], false, label + ": rejected")
	check_eq(result["reason"], reason, label + ": reason")
	check_eq(result["events"], [{"type": "action_rejected", "reason": reason}], label + ": only action_rejected")
	check(result["state"] == s, label + ": returns the input state")
	check_eq(s.hash_key(), before, label + ": hash_key unchanged")
	check_eq(s.action_count, count_before, label + ": counter unchanged")


func test_l01_burn_crate() -> bool:
	var s := _play(_l01(), ["move:right"])
	var result := TM.apply_action(s, {"type": "burn", "dir": "right"})
	check_eq(result["ok"], true, "burn ok")
	var after: GS = result["state"]
	check_eq(after.objects["crate_a"]["state"], GS.ASH, "crate is ASH")
	check_eq(after.objects["crate_a"]["slot"], Vector2i(2, 2), "crate stays in place")
	check_eq(after.objects["crate_a_ash"], {
		"id": "crate_a_ash", "type": "ash_path", "hour": 2, "slot": Vector2i(2, 2),
		"state": GS.INTACT, "flammable": false,
	}, "ash_path created in hour 2 at [2,2]")
	check_eq(after.action_count, 2, "counter is 2")
	check_eq(after.player_slot, Vector2i(1, 2), "player did not move")
	check_eq(result["events"], [
		{"type": "burned", "id": "crate_a", "hour": 12, "slot": Vector2i(2, 2)},
		{"type": "ash_moved", "from_hour": 12, "to_hour": 2, "to_slot": Vector2i(2, 2), "becomes": "ash_path"},
		{"type": "action_applied", "actions_used": 2},
	], "events: burned, ash_moved, action_applied")
	check(Walk.is_walkable(after, 12, Vector2i(2, 2)), "rubble is walkable")
	check(Walk.is_walkable(after, 2, Vector2i(2, 2)), "ash_path makes the chasm walkable")
	return true


func test_l01_full_solution() -> bool:
	var s := _play(_l01(), L01_SOLUTION)
	check_eq(s.player_hour, 2, "player in hour 2")
	check_eq(s.player_slot, Vector2i(4, 2), "player on the exit slot")
	check_eq(s.object_at(2, Vector2i(4, 2)).get("type"), "exit", "that slot holds the exit")
	check_eq(s.action_count, 10, "10 actions")
	return true


func test_burn_without_ash_link() -> bool:
	var s := _l01()
	s.objects["crate_a"].erase("ash_link")
	s.player_slot = Vector2i(1, 2)
	var result := TM.apply_action(s, {"type": "burn", "dir": "right"})
	check_eq(result["ok"], true, "burn ok")
	check_eq(result["events"], [
		{"type": "burned", "id": "crate_a", "hour": 12, "slot": Vector2i(2, 2)},
		{"type": "action_applied", "actions_used": 1},
	], "no ash_moved without a link")
	check_eq(result["state"].objects.size(), 3, "no new object")
	return true


func test_burning_a_bridge_reopens_the_chasm() -> bool:
	var s := _l01()
	s.terrain[12] = [".....", ".....", ".~...", ".....", "....."]
	s.objects["bridge_a"] = {"id": "bridge_a", "type": "bridge", "hour": 12, "slot": Vector2i(1, 2),
		"state": GS.INTACT, "flammable": true}
	check_eq(Walk.check_walkable(s, 12, Vector2i(1, 2))["reason"], "", "bridge is walkable before")
	var result := TM.apply_action(s, {"type": "burn", "dir": "right"})
	check_eq(result["ok"], true, "burn ok")
	var after: GS = result["state"]
	check_eq(after.objects["bridge_a"]["state"], GS.ASH, "bridge is ASH")
	check_eq(Walk.check_walkable(after, 12, Vector2i(1, 2))["reason"], "blocked_terrain", "chasm blocks again")
	check_eq(TM.apply_action(after, {"type": "move", "dir": "right"})["reason"], "blocked_terrain", "cannot walk onto it")
	return true


func test_reject_nothing_to_burn() -> bool:
	var s := _l01()
	_expect_rejected(s, "up", "nothing_to_burn", "empty slot")
	_expect_rejected(s, "left", "nothing_to_burn", "off the grid")
	s.player_slot = Vector2i(1, 2)
	s.objects["crate_a"]["state"] = GS.GONE
	_expect_rejected(s, "right", "nothing_to_burn", "GONE object")
	return true


func test_reject_already_ash() -> bool:
	var s := _play(_l01(), ["move:right", "burn:right"])
	_expect_rejected(s, "right", "not_intact", "crate already ASH")
	check_eq(s.objects.size(), 4, "link did not fire a second time")
	return true


func test_reject_not_flammable() -> bool:
	var s := _l01()
	s.player_slot = Vector2i(3, 2)
	_expect_rejected(s, "right", "not_flammable", "the stair")
	return true


func test_reject_ash_target_holds_object() -> bool:
	var s := _l01()
	s.player_slot = Vector2i(1, 2)
	s.objects["crate_a"]["ash_link"]["slot"] = Vector2i(4, 2)  # the exit in hour 2
	_expect_rejected(s, "right", "ash_target_occupied", "target holds the exit")
	return true


func test_reject_ash_target_holds_player() -> bool:
	var s := _l01()
	s.player_slot = Vector2i(1, 2)
	s.objects["crate_a"]["ash_link"]["hour"] = 12
	s.objects["crate_a"]["ash_link"]["slot"] = Vector2i(1, 2)  # where the player stands
	_expect_rejected(s, "right", "ash_target_occupied", "target holds the player")
	return true


func test_reject_bad_direction() -> bool:
	var s := _l01()
	for action in [{"type": "burn"}, {"type": "burn", "dir": "east"}]:
		var result := TM.apply_action(s, action)
		check_eq(result["reason"], "unknown_action", "burn %s" % str(action))
	return true


func test_input_state_is_never_mutated() -> bool:
	var s := _play(_l01(), ["move:right"])
	var before := s.hash_key()
	var result := TM.apply_action(s, {"type": "burn", "dir": "right"})
	check_eq(result["ok"], true, "burn ok")
	check_eq(s.hash_key(), before, "input unchanged")
	check_eq(s.objects["crate_a"]["state"], GS.INTACT, "input crate still INTACT")
	check(not s.objects.has("crate_a_ash"), "input has no ash object")
	return true


func test_legal_actions_include_burns_in_order() -> bool:
	var s := _play(_l01(), ["move:right"])  # crate to the right
	check_eq(TM.legal_actions(s), [
		{"type": "move", "dir": "up"}, {"type": "move", "dir": "down"}, {"type": "move", "dir": "left"},
		{"type": "burn", "dir": "right"},
		{"type": "wait"},
	], "moves, then burns, then interact, then wait")
	var burned: GS = TM.apply_action(s, {"type": "burn", "dir": "right"})["state"]
	check(not TM.legal_actions(burned).has({"type": "burn", "dir": "right"}), "no burn of an ASH crate")
	return true


func test_determinism() -> bool:
	var a := _play(_l01(), L01_SOLUTION)
	var b := _play(_l01(), L01_SOLUTION)
	check_eq(a.hash_key(), b.hash_key(), "same actions, same hash_key")
	return true
