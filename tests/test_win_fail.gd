extends "res://tests/test_suite.gd"
## Tests for win, fail and level_over (section 3.5 check order, clarifications 14-15).

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const TM := preload("res://core/turn_manager.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"
const L01_SOLUTION := ["move:right", "burn:right", "move:right", "move:right", "move:right",
	"interact", "move:right", "move:right", "move:right", "move:right"]

const WAIT := {"type": "wait"}


func _l01() -> GS:
	return Loader.load_file(L01_PATH)["state"]


## "move:right" -> {"type": "move", "dir": "right"} (test shorthand, 6.4).
func _action(short: String) -> Dictionary:
	var parts := short.split(":")
	return {"type": parts[0]} if parts.size() == 1 else {"type": parts[0], "dir": parts[1]}


## Applies actions (shorthand strings or dictionaries); fails the test at the
## first rejection. Returns {state, last} where last is the final result.
func _play(state: GS, actions: Array) -> Dictionary:
	var last := {}
	for i in actions.size():
		var action = actions[i]
		last = TM.apply_action(state, _action(action) if action is String else action)
		if not last["ok"]:
			check(false, "action %d (%s) rejected: %s" % [i, str(action), last["reason"]])
			break
		state = last["state"]
	return {"state": state, "last": last}


func _types(events: Array) -> Array:
	return events.map(func(e): return e["type"])


## A 1-hour-per-action level with the player in hour 10 next to the exit.
## After 5 waits the next action completes the dial (sun index 6).
func _dial_level() -> GS:
	var result := Loader.load_dict({
		"id": "dial",
		"sun": {"start_index": 0, "actions_per_hour": 1},
		"player": {"hour": 10, "slot": [3, 4]},
		"objects": [{"id": "exit_1", "type": "exit", "hour": 10, "slot": [4, 4], "flammable": false}],
	})
	check_eq(result["error"], "", "dial level loads")
	return result["state"]


func test_new_state_is_playing() -> bool:
	check_eq(_l01().status, "playing", "status starts as playing")
	return true


func test_l01_solution_wins() -> bool:
	var run := _play(_l01(), L01_SOLUTION)
	var s: GS = run["state"]
	check_eq(s.status, "won", "status won")
	check_eq(s.action_count, 10, "10 actions")
	var events: Array = run["last"]["events"]
	check_eq(events.back(), {"type": "level_won", "actions_used": 10}, "level_won is the final event")
	check_eq(_types(events).slice(-2), ["action_applied", "level_won"], "level_won right after action_applied")
	return true


func test_only_the_last_action_wins() -> bool:
	var s := _l01()
	for i in L01_SOLUTION.size() - 1:
		var result := TM.apply_action(s, _action(L01_SOLUTION[i]))
		check_eq(result["state"].status, "playing", "still playing after action %d" % (i + 1))
		check(not _types(result["events"]).has("level_won"), "no level_won at action %d" % (i + 1))
		s = result["state"]
	return true


func test_ash_exit_does_not_win() -> bool:
	var s := _l01()
	s.objects["exit_1"]["state"] = GS.ASH
	check_eq(_play(s, L01_SOLUTION)["state"].status, "playing", "only an INTACT exit wins")
	return true


func test_win_on_the_action_that_completes_the_dial() -> bool:
	var run := _play(_dial_level(), [WAIT, WAIT, WAIT, WAIT, WAIT, {"type": "move", "dir": "right"}])
	var s: GS = run["state"]
	check_eq(s.action_count, 6, "6 actions: sun index 6")
	check_eq(s.status, "won", "win beats fail")
	var events: Array = run["last"]["events"]
	check_eq(events.back(), {"type": "level_won", "actions_used": 6}, "level_won")
	check(not _types(events).has("level_failed"), "no level_failed")
	check(_types(events).has("sun_advanced"), "the sun still advanced to 6")
	return true


func test_dial_complete_fails() -> bool:
	var run := _play(_dial_level(), [WAIT, WAIT, WAIT, WAIT, WAIT])
	check_eq(run["state"].status, "playing", "still playing at sun index 5")
	var last := TM.apply_action(run["state"], WAIT)
	check_eq(last["ok"], true, "the sixth action is valid")
	var s: GS = last["state"]
	check_eq(s.status, "failed", "status failed")
	check_eq(last["events"].back(), {"type": "level_failed", "reason": "dial_complete"}, "level_failed")
	check_eq(_types(last["events"]), ["sun_advanced", "hour_passed", "action_applied", "level_failed"], "event order")
	return true


func test_default_l01_fails_after_18_actions() -> bool:
	var actions: Array = []
	actions.resize(18)
	actions.fill(WAIT)
	var run := _play(_l01(), actions)
	check_eq(run["state"].status, "failed", "18 waits with 3 actions per hour complete the dial")
	return true


func _check_level_over(s: GS, label: String) -> void:
	var before := s.hash_key()
	for action in [WAIT, {"type": "move", "dir": "up"}, {"type": "move", "dir": "left"},
			{"type": "burn", "dir": "right"}, {"type": "interact"}, {"type": "fly"}]:
		var result := TM.apply_action(s, action)
		check_eq(result["reason"], "level_over", "%s: %s rejected" % [label, str(action)])
		check_eq(result["events"], [{"type": "action_rejected", "reason": "level_over"}], "%s: only action_rejected" % label)
		check(result["state"] == s, "%s: input returned" % label)
	check_eq(s.hash_key(), before, label + ": hash_key unchanged")
	check_eq(TM.legal_actions(s), [], label + ": legal_actions empty")


func test_level_over_after_win() -> bool:
	_check_level_over(_play(_l01(), L01_SOLUTION)["state"], "after win")
	return true


func test_level_over_after_fail() -> bool:
	_check_level_over(_play(_dial_level(), [WAIT, WAIT, WAIT, WAIT, WAIT, WAIT])["state"], "after fail")
	return true


func test_status_in_copy_and_hash() -> bool:
	var won: GS = _play(_l01(), L01_SOLUTION)["state"]
	check_eq(won.duplicate_deep().status, "won", "duplicate_deep keeps status")
	var playing := won.duplicate_deep()
	playing.status = GS.PLAYING
	check(playing.hash_key() != won.hash_key(), "status is part of hash_key")
	return true


func test_input_never_mutated_and_determinism() -> bool:
	var s: GS = _play(_l01(), L01_SOLUTION.slice(0, 9))["state"]  # one step from the exit
	var before := s.hash_key()
	var result := TM.apply_action(s, _action("move:right"))
	check_eq(result["state"].status, "won", "the copy is won")
	check_eq(s.status, "playing", "the input is still playing")
	check_eq(s.hash_key(), before, "input unchanged")
	var a: GS = _play(_l01(), L01_SOLUTION)["state"]
	var b: GS = _play(_l01(), L01_SOLUTION)["state"]
	check_eq(a.hash_key(), b.hash_key(), "same actions, same hash_key")
	return true
