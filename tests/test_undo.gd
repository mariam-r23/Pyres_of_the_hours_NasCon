extends "res://tests/test_suite.gd"
## Tests for undo: core/snapshot_stack.gd, core/game_session.gd, and
## turn_manager.load_level().

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const TM := preload("res://core/turn_manager.gd")
const SnapshotStack := preload("res://core/snapshot_stack.gd")
const GameSession := preload("res://core/game_session.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"
const L01_SOLUTION := ["move:right", "burn:right", "move:right", "move:right", "move:right",
	"interact", "move:right", "move:right", "move:right", "move:right"]

const WAIT := {"type": "wait"}
const UNDO_DONE := [{"type": "undo_done"}]


func _l01() -> GS:
	return Loader.load_file(L01_PATH)["state"]


## "move:right" -> {"type": "move", "dir": "right"} (test shorthand, 6.4).
func _action(short: String) -> Dictionary:
	var parts := short.split(":")
	return {"type": parts[0]} if parts.size() == 1 else {"type": parts[0], "dir": parts[1]}


## Performs shorthand actions on a session; fails the test at a rejection.
func _perform_all(session: GameSession, actions: Array) -> void:
	for short in actions:
		var result := session.perform(_action(short))
		check(result["ok"], "%s should be valid (got %s)" % [short, result["reason"]])


func test_undo_after_one_move() -> bool:
	var start := _l01()
	var stack := SnapshotStack.new(start)
	var moved: GS = TM.apply_action(start, _action("move:right"))["state"]
	stack.push(moved)
	check_eq(stack.depth(), 1, "depth 1")
	var result := stack.undo()
	check_eq(result["ok"], true, "ok")
	check_eq(result["reason"], "", "no reason")
	check_eq(result["events"], UNDO_DONE, "only undo_done")
	check_eq(result["state"].hash_key(), start.hash_key(), "equal hash_key")
	check_eq(stack.depth(), 0, "depth 0")
	return true


func test_undo_three_times_walks_back_exactly() -> bool:
	var session := GameSession.new(_l01())
	var hashes := [session.current_state().hash_key()]
	for short in ["move:right", "burn:right", "move:up"]:
		session.perform(_action(short))
		hashes.append(session.current_state().hash_key())
	for i in 3:
		var result := session.undo()
		check_eq(result["events"], UNDO_DONE, "undo %d: only undo_done" % (i + 1))
		check_eq(result["state"].hash_key(), hashes[2 - i], "undo %d restores step %d" % [i + 1, 2 - i])
	check_eq(session.current_state().action_count, 0, "back at 0 actions")
	return true


func test_undo_is_free() -> bool:
	var session := GameSession.new(_l01())
	_perform_all(session, ["wait", "wait", "wait", "wait"])  # sun index 1
	var result := session.undo()
	check_eq(result["events"], UNDO_DONE, "no sun or action events")
	check_eq(result["state"].action_count, 3, "counter restored to 3, not advanced")
	check_eq(TM.is_hour_passed(result["state"], 12), true, "sun restored, not advanced or reset")
	return true


func test_nothing_to_undo() -> bool:
	var session := GameSession.new(_l01())
	var before := session.current_state().hash_key()
	var result := session.undo()
	check_eq(result["ok"], false, "rejected")
	check_eq(result["reason"], "nothing_to_undo", "reason")
	check_eq(result["events"], [{"type": "action_rejected", "reason": "nothing_to_undo"}], "single action_rejected")
	check_eq(session.current_state().hash_key(), before, "state unchanged")
	var stack := SnapshotStack.new(_l01())
	check(not stack.can_undo(), "fresh stack cannot undo")
	check_eq(stack.undo()["reason"], "nothing_to_undo", "stack rejects too")
	return true


func test_rejected_actions_are_not_pushed() -> bool:
	var session := GameSession.new(_l01())
	session.perform(_action("move:up"))  # valid: [0,1]
	var after_valid := session.current_state().hash_key()
	var rejected := session.perform(_action("move:left"))  # off the grid
	check_eq(rejected["ok"], false, "move left rejected")
	check_eq(session.current_state().hash_key(), after_valid, "rejection changed nothing")
	var result := session.undo()
	check_eq(result["state"].player_slot, Vector2i(0, 2), "undo undid the last VALID action")
	check(not session.can_undo(), "only one entry was pushed")
	return true


func test_undo_out_of_won() -> bool:
	var session := GameSession.new(_l01())
	_perform_all(session, L01_SOLUTION)
	check_eq(session.current_state().status, "won", "won")
	check_eq(session.perform(WAIT)["reason"], "level_over", "level over")
	var result := session.undo()
	check_eq(result["ok"], true, "undo allowed after a win")
	check_eq(result["state"].status, "playing", "playing again")
	check_eq(result["state"].action_count, 9, "one step before the exit")
	check_eq(session.perform(_action("move:right"))["state"].status, "won", "can win again")
	return true


func test_undo_out_of_failed() -> bool:
	var session := GameSession.new(_l01())
	var waits: Array = []
	waits.resize(18)
	waits.fill("wait")
	_perform_all(session, waits)
	check_eq(session.current_state().status, "failed", "failed")
	var result := session.undo()
	check_eq(result["ok"], true, "undo allowed after a fail")
	check_eq(result["state"].status, "playing", "playing again")
	check_eq(result["state"].action_count, 17, "17 actions")
	return true


func test_undo_after_burn() -> bool:
	var start := _l01()
	start.sun_start_index = 1  # hour 12 passed: shadows there are active
	start.player_slot = Vector2i(1, 2)
	start.shadows["sh"] = {"id": "sh", "hour": 12, "slot": Vector2i(2, 1)}  # next to the crate
	var session := GameSession.new(start)
	var burn := session.perform(_action("burn:right"))
	check(burn["ok"], "burn ok")
	check(not burn["state"].shadows.has("sh"), "shadow destroyed by the burn")
	check(burn["state"].objects.has("crate_a_ash"), "ash_path created")
	var undone: GS = session.undo()["state"]
	check_eq(undone.objects["crate_a"]["state"], GS.INTACT, "crate INTACT again")
	check(not undone.objects.has("crate_a_ash"), "ash_path removed")
	check(undone.shadows.has("sh"), "destroyed shadow is back")
	check_eq(undone.hash_key(), start.hash_key(), "exactly the start state")
	return true


func test_redo_after_undo_is_deterministic() -> bool:
	var session := GameSession.new(_l01())
	_perform_all(session, ["move:right", "burn:right", "move:right"])
	var first := session.current_state().hash_key()
	session.undo()
	session.undo()
	_perform_all(session, ["burn:right", "move:right"])
	check_eq(session.current_state().hash_key(), first, "same actions after undo, same hash_key")
	return true


func test_returned_states_cannot_corrupt_the_stack() -> bool:
	var start := _l01()
	var stack := SnapshotStack.new(start)
	var moved: GS = TM.apply_action(start, _action("move:right"))["state"]
	stack.push(moved)
	stack.push(TM.apply_action(moved, _action("move:up"))["state"])
	# Mutate everything we handed in or got back.
	start.objects["crate_a"]["state"] = GS.ASH
	moved.player_slot = Vector2i(4, 4)
	var back: GS = stack.undo()["state"]
	back.objects.clear()
	back.player_slot = Vector2i(3, 3)
	var again: GS = stack.undo()["state"]
	check_eq(again.objects["crate_a"]["state"], GS.INTACT, "initial snapshot unaffected")
	check_eq(again.player_slot, Vector2i(0, 2), "initial player slot unaffected")
	# Same through the session.
	var session := GameSession.new(_l01())
	var result := session.perform(_action("move:right"))
	result["state"].player_slot = Vector2i(4, 4)
	session.current_state().objects.clear()
	check_eq(session.current_state().player_slot, Vector2i(1, 2), "session state unaffected")
	check_eq(session.current_state().objects.size(), 3, "session objects unaffected")
	check_eq(session.undo()["state"].player_slot, Vector2i(0, 2), "session history unaffected")
	return true


func test_session_l01_end_to_end() -> bool:
	var start := _l01()
	var session := GameSession.new(start)
	_perform_all(session, L01_SOLUTION)
	var s := session.current_state()
	check_eq(s.status, "won", "won")
	check_eq(s.action_count, 10, "10 actions")
	for i in 10:
		check_eq(session.undo()["ok"], true, "undo %d" % (i + 1))
	check_eq(session.current_state().hash_key(), start.hash_key(), "back at the start")
	check_eq(session.undo()["reason"], "nothing_to_undo", "nothing more to undo")
	return true


func test_session_restart() -> bool:
	var start := _l01()
	var session := GameSession.new(start)
	_perform_all(session, ["move:right", "burn:right"])
	session.restart()
	check_eq(session.current_state().hash_key(), start.hash_key(), "restart returns to the start")
	check(not session.can_undo(), "restart clears the history")
	return true


func test_load_level() -> bool:
	var file := FileAccess.open(L01_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	var s: GS = TM.load_level(data)
	check(s != null, "loads")
	check_eq(s.hash_key(), _l01().hash_key(), "same as level_loader")
	check(TM.load_level({"id": "bad"}) == null, "bad data gives null")
	return true
