extends "res://tests/test_suite.gd"
## Tests for presentation/event_bus.gd and presentation/game_controller.gd.
##
## Headless test runs have no EventBus autoload, so each test creates its own
## event_bus.gd instance (the real script, not a fake) and hands it to the
## controller through `controller.bus`. Nodes are never added to a tree; their
## signals and methods work without one. Every node is freed at the end.

const EventBusScript := preload("res://presentation/event_bus.gd")
const ControllerScript := preload("res://presentation/game_controller.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"
const L01_SOLUTION := ["move:right", "burn:right", "move:right", "move:right", "move:right",
	"interact", "move:right", "move:right", "move:right", "move:right"]


## Records every bus signal as [signal_name, payload] in emission order.
class Recorder:
	var log: Array = []

	func listen(bus: Node) -> void:
		for type in EventBusScript.CORE_EVENT_TYPES:
			bus.connect(type, func(event): log.append([type, event]))
		bus.level_loaded.connect(func(meta): log.append(["level_loaded", meta]))
		bus.level_load_failed.connect(func(errors): log.append(["level_load_failed", errors]))
		bus.level_restarted.connect(func(): log.append(["level_restarted", null]))

	func names() -> Array:
		return log.map(func(entry): return entry[0])

	func clear() -> void:
		log.clear()


## A controller wired to a fresh bus with a recorder. Call _free() when done.
func _setup() -> Dictionary:
	var bus: Node = EventBusScript.new()
	var controller: Node = ControllerScript.new()
	controller.bus = bus
	var rec := Recorder.new()
	rec.listen(bus)
	return {"bus": bus, "controller": controller, "rec": rec}


func _free(env: Dictionary) -> void:
	env["controller"].free()
	env["bus"].free()


func _action(short: String) -> Dictionary:
	var parts := short.split(":")
	return {"type": parts[0]} if parts.size() == 1 else {"type": parts[0], "dir": parts[1]}


func test_emit_events_routes_in_order() -> bool:
	var env := _setup()
	var events: Array = []
	for type in EventBusScript.CORE_EVENT_TYPES:
		events.append({"type": type, "marker": type})
	env["bus"].emit_events(events)
	var rec: Recorder = env["rec"]
	check_eq(rec.names(), EventBusScript.CORE_EVENT_TYPES, "one signal per type, in order")
	for entry in rec.log:
		check_eq(entry[1]["marker"], entry[0], "%s carries its own event" % entry[0])
	_free(env)
	return true


func test_unknown_events_do_not_crash() -> bool:
	var env := _setup()
	env["bus"].emit_events([{"type": "bogus"}, "not a dict", {}, {"type": "wait_what"}, {"type": "moved", "id": 1}])
	check_eq(env["rec"].names(), ["moved"], "unknown events skipped, valid one still delivered")
	_free(env)
	return true


func test_load_level_success() -> bool:
	var env := _setup()
	var errors: Array = env["controller"].load_level(L01_PATH)
	check_eq(errors, [], "no errors")
	var rec: Recorder = env["rec"]
	check_eq(rec.names(), ["level_loaded"], "level_loaded emitted")
	check_eq(rec.log[0][1]["title"], "Something Warm", "with the meta")
	check(env["controller"].session != null, "session created")
	check_eq(env["controller"].current_state().player_slot, Vector2i(0, 2), "at the start")
	_free(env)
	return true


func test_load_level_failures_keep_the_old_session() -> bool:
	var env := _setup()
	var controller: Node = env["controller"]
	controller.load_level(L01_PATH)
	controller.perform(_action("move:right"))
	var before: String = controller.current_state().hash_key()
	var rec: Recorder = env["rec"]
	rec.clear()

	var missing: Array = controller.load_level("res://tests/fixtures/no_such_level.json")
	check(not missing.is_empty() and "cannot open file" in missing[0], "missing file error: %s" % str(missing))
	var invalid: Array = controller.load_level("res://tests/fixtures/T02_no_exit.json")
	check(invalid.has("level: no exit object (exactly one is required)"), "validation error: %s" % str(invalid))
	check_eq(rec.names(), ["level_load_failed", "level_load_failed"], "two level_load_failed")
	check_eq(rec.log[1][1], invalid, "the error list is sent")
	check_eq(controller.current_state().hash_key(), before, "old session kept")
	_free(env)
	return true


func test_perform_forwards_events() -> bool:
	var env := _setup()
	var controller: Node = env["controller"]
	controller.load_level(L01_PATH)
	var rec: Recorder = env["rec"]
	rec.clear()
	var result: Dictionary = controller.perform(_action("move:right"))
	check_eq(result["ok"], true, "ok")
	check_eq(rec.names(), ["moved", "action_applied"], "moved then action_applied on the bus")
	check_eq(rec.log[0][1]["to_slot"], Vector2i(1, 2), "moved payload")
	check_eq(result["events"], rec.log.map(func(e): return e[1]), "the same events that were returned")
	rec.clear()
	var rejected: Dictionary = controller.perform(_action("move:right"))  # into the crate
	check_eq(rejected["reason"], "blocked_object", "rejected")
	check_eq(rec.log, [["action_rejected", {"type": "action_rejected", "reason": "blocked_object"}]], "exactly one action_rejected")
	_free(env)
	return true


func test_undo_and_restart() -> bool:
	var env := _setup()
	var controller: Node = env["controller"]
	controller.load_level(L01_PATH)
	var start: String = controller.current_state().hash_key()
	var rec: Recorder = env["rec"]
	rec.clear()

	var nothing: Dictionary = controller.undo()
	check_eq(nothing["reason"], "nothing_to_undo", "nothing to undo yet")
	check_eq(rec.names(), ["action_rejected"], "forwarded as action_rejected")
	controller.perform(_action("move:right"))
	controller.perform(_action("burn:right"))
	rec.clear()
	var undone: Dictionary = controller.undo()
	check_eq(undone["ok"], true, "undo ok")
	check_eq(rec.names(), ["undo_done"], "only undo_done")
	check_eq(controller.current_state().action_count, 1, "back to 1 action")
	rec.clear()
	controller.restart()
	check_eq(rec.names(), ["level_restarted"], "level_restarted emitted")
	check_eq(controller.current_state().hash_key(), start, "back at the start")
	check_eq(controller.undo()["reason"], "nothing_to_undo", "history cleared")
	_free(env)
	return true


func test_no_level_loaded() -> bool:
	var env := _setup()
	check_eq(env["controller"].perform(_action("wait"))["reason"], "no_level_loaded", "perform without a level")
	check_eq(env["controller"].undo()["reason"], "no_level_loaded", "undo without a level")
	env["controller"].restart()
	check_eq(env["rec"].log, [], "nothing emitted")
	_free(env)
	return true


func test_key_to_action() -> bool:
	var moves := {KEY_UP: "up", KEY_W: "up", KEY_DOWN: "down", KEY_S: "down",
		KEY_LEFT: "left", KEY_A: "left", KEY_RIGHT: "right", KEY_D: "right"}
	for key in moves:
		check_eq(ControllerScript.key_to_action(key, false), {"type": "move", "dir": moves[key]}, "key %d moves" % key)
		check_eq(ControllerScript.key_to_action(key, true), {"type": "burn", "dir": moves[key]}, "key %d burns in burn mode" % key)
	check_eq(ControllerScript.key_to_action(KEY_E, false), {"type": "interact"}, "E interacts")
	check_eq(ControllerScript.key_to_action(KEY_SPACE, false), {"type": "wait"}, "Space waits")
	for key in [KEY_B, KEY_Z, KEY_R, KEY_ESCAPE, KEY_Q, KEY_ENTER]:
		check_eq(ControllerScript.key_to_action(key, false), {}, "key %d is not an action" % key)
	return true


func test_burn_mode() -> bool:
	var env := _setup()
	var controller: Node = env["controller"]
	controller.load_level(L01_PATH)
	var modes: Array = []
	controller.burn_mode_changed.connect(func(active): modes.append(active))
	controller.handle_key(KEY_RIGHT)  # move to [1,2], next to the crate
	controller.handle_key(KEY_B)
	check(controller.burn_mode, "B turns burn mode on")
	var result: Dictionary = controller.handle_key(KEY_RIGHT)
	check_eq(result["state"].objects["crate_a"]["state"], "ASH", "the direction burned the crate")
	check(not controller.burn_mode, "burn mode cleared after the burn")
	check_eq(controller.current_state().player_slot, Vector2i(1, 2), "the player did not move")
	controller.handle_key(KEY_B)
	controller.handle_key(KEY_ESCAPE)
	check(not controller.burn_mode, "Escape cancels")
	controller.handle_key(KEY_B)
	controller.handle_key(KEY_B)
	check(not controller.burn_mode, "B again cancels")
	check_eq(modes, [true, false, true, false, true, false], "burn_mode_changed for every change")
	check(controller.handle_key(KEY_ESCAPE) == null, "Escape outside burn mode is not used")
	check(controller.handle_key(KEY_Q) == null, "unused key")
	_free(env)
	return true


func test_full_l01_through_the_controller() -> bool:
	var env := _setup()
	var controller: Node = env["controller"]
	controller.load_level(L01_PATH)
	for short in L01_SOLUTION:
		var result: Dictionary = controller.perform(_action(short))
		check(result["ok"], "%s valid (%s)" % [short, result["reason"]])
	var rec: Recorder = env["rec"]
	check_eq(rec.names().back(), "level_won", "level_won is the last bus signal")
	check_eq(rec.log.back()[1], {"type": "level_won", "actions_used": 10}, "level_won payload")
	check_eq(rec.names().count("action_applied"), 10, "ten action_applied")
	check_eq(controller.current_state().status, "won", "won")
	_free(env)
	return true


func test_keys_play_l01() -> bool:
	var env := _setup()
	var controller: Node = env["controller"]
	controller.load_level(L01_PATH)
	for key in [KEY_D, KEY_B, KEY_D, KEY_D, KEY_RIGHT, KEY_RIGHT, KEY_E, KEY_D, KEY_D, KEY_D, KEY_D]:
		controller.handle_key(key)
	check_eq(controller.current_state().status, "won", "keyboard play wins L01")
	check_eq(env["rec"].names().back(), "level_won", "level_won on the bus")
	_free(env)
	return true
