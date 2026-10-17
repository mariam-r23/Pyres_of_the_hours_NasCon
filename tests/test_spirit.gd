extends "res://tests/test_suite.gd"
## Tests for presentation/spirit_director.gd (when the fire spirit speaks)
## and the ending / HUD signals in presentation/main.gd. Uses the real
## dialogue picker, a real event bus and a real ripple camera (stepped by hand).

const Loader := preload("res://core/level_loader.gd")
const DirectorScript := preload("res://presentation/spirit_director.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")
const RippleScript := preload("res://presentation/ripple_camera.gd")
const MainScript := preload("res://presentation/main.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"

const BURNED := {"type": "burned", "id": "crate_a", "hour": 12, "slot": Vector2i(2, 2)}
const ASH_MOVED := {"type": "ash_moved", "from_hour": 12, "to_hour": 2, "to_slot": Vector2i(2, 2), "becomes": "ash_path"}
const APPLIED := {"type": "action_applied", "actions_used": 2}
const WON := {"type": "level_won", "actions_used": 10}
const FAILED := {"type": "level_failed", "reason": "dial_complete"}
const UNDO := {"type": "undo_done"}


func _l01_meta() -> Dictionary:
	return Loader.load_file(L01_PATH)["meta"]


## A director on a fresh bus and ripple camera, recording what it decides
## (picked) and what reaches the bus (said). Call _free(env) when done.
func _setup(level_id: String = "L01_first_crate", meta: Dictionary = {}) -> Dictionary:
	var bus: Node = EventBusScript.new()
	var ripple: Node3D = RippleScript.new()
	var director: Node = DirectorScript.new()
	director.connect_bus(bus)
	director.connect_ripple(ripple)
	director.start_level(level_id, meta if not meta.is_empty() else _l01_meta())
	var env := {"bus": bus, "ripple": ripple, "director": director, "said": [], "picked": [], "endings": []}
	bus.spirit_said.connect(func(trigger, mood, text): env["said"].append([trigger, mood, text]))
	director.line_picked.connect(func(result): env["picked"].append(result))
	bus.ending_choice_requested.connect(func(id): env["endings"].append(id))
	return env


func _free(env: Dictionary) -> void:
	for key in ["director", "ripple", "bus"]:
		env[key].free()


## Emits one action's events and flushes (what the end of the frame does).
func _action(env: Dictionary, events: Array) -> void:
	env["bus"].emit_events(events)
	env["director"].flush()


func _said_triggers(env: Dictionary) -> Array:
	return env["said"].map(func(s): return s[0])


func test_each_event_maps_to_its_trigger() -> bool:
	var cases := [
		[BURNED, "on_burn"], [ASH_MOVED, "on_ash_moved"], [UNDO, "on_undo"],
		[WON, "on_solve"], [FAILED, "on_fail"],
		[{"type": "shadow_appeared", "id": "sh", "hour": 2, "slot": Vector2i(1, 1)}, "on_shadow_appeared"],
		[{"type": "shadow_destroyed", "id": "sh", "hour": 2}, "on_shadow_destroyed"],
	]
	for c in cases:
		var env := _setup()
		_action(env, [c[0]])
		check_eq(env["picked"].map(func(r): return r["trigger"]), [c[1]], "%s -> %s" % [c[0]["type"], c[1]])
		check_eq(_said_triggers(env), [c[1]], "%s line reaches the bus" % c[1])
		check(env["said"][0][2] != "", "%s has text" % c[1])
		_free(env)
	return true


func test_burn_and_ash_in_one_action_says_only_on_burn() -> bool:
	var env := _setup()
	_action(env, [BURNED, ASH_MOVED, APPLIED])
	check_eq(_said_triggers(env), ["on_burn"], "one line, on_burn")
	check_eq(env["picked"].size(), 1, "the picker was asked once")
	_free(env)
	return true


func test_win_beats_everything_in_the_same_action() -> bool:
	var env := _setup()
	_action(env, [BURNED, ASH_MOVED, {"type": "shadow_destroyed", "id": "a", "hour": 12},
		{"type": "shadow_appeared", "id": "b", "hour": 2, "slot": Vector2i(0, 0)}, APPLIED, WON])
	check_eq(_said_triggers(env), ["on_solve"], "on_solve wins")
	_free(env)
	env = _setup()
	_action(env, [{"type": "shadow_appeared", "id": "b", "hour": 2, "slot": Vector2i(0, 0)},
		{"type": "shadow_destroyed", "id": "a", "hour": 12}, BURNED])
	check_eq(_said_triggers(env), ["on_shadow_destroyed"], "destroyed beats appeared and burn")
	_free(env)
	return true


func test_line_waits_for_the_ripple_shot() -> bool:
	var env := _setup()
	var ripple: Node3D = env["ripple"]
	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	_action(env, [BURNED, ASH_MOVED, APPLIED])
	check_eq(env["said"], [], "nothing said while the shot plays")
	check(env["director"].has_pending_line(), "the line is waiting")
	ripple.advance(5.0)  # the shot finishes
	check_eq(_said_triggers(env), ["on_burn"], "said on ripple_finished")
	check(not env["director"].has_pending_line(), "nothing left waiting")
	# A skipped shot also delivers it.
	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	_action(env, [{"type": "shadow_destroyed", "id": "a", "hour": 12}])
	ripple.skip()
	check_eq(_said_triggers(env), ["on_burn", "on_shadow_destroyed"], "a skip delivers too")
	_free(env)
	return true


func test_undo_restart_and_load_drop_a_waiting_line() -> bool:
	var env := _setup()
	var ripple: Node3D = env["ripple"]
	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	_action(env, [BURNED, ASH_MOVED, APPLIED])
	check(env["director"].has_pending_line(), "waiting")
	# What main does on undo: the bus gets undo_done, the shot is cancelled.
	env["bus"].emit_events([UNDO])
	ripple.cancel()
	env["director"].flush()
	check(not _said_triggers(env).has("on_burn"), "the waiting burn line was dropped")
	check_eq(_said_triggers(env), ["on_undo"], "only the undo line is said")

	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	_action(env, [BURNED])
	env["bus"].level_restarted.emit()
	ripple.cancel()
	check(not env["director"].has_pending_line(), "restart drops it")

	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	_action(env, [BURNED])
	env["director"].start_level("L01_first_crate", _l01_meta())
	ripple.cancel()
	check(not env["director"].has_pending_line(), "a level load drops it")
	check_eq(_said_triggers(env), ["on_undo"], "no dropped line was said late")
	_free(env)
	return true


func test_idle_fires_once_and_resets_on_input() -> bool:
	var env := _setup()
	var director: Node = env["director"]
	director.advance_idle(DirectorScript.IDLE_SECONDS - 1.0)
	check_eq(env["said"], [], "not yet")
	director.advance_idle(2.0)
	check_eq(_said_triggers(env), ["on_idle"], "on_idle after IDLE_SECONDS")
	director.advance_idle(60.0)
	check_eq(_said_triggers(env), ["on_idle"], "only once")
	director.note_activity()
	director.advance_idle(DirectorScript.IDLE_SECONDS + 1.0)
	check_eq(_said_triggers(env), ["on_idle", "on_idle"], "again after the player acted")
	_free(env)
	return true


func test_idle_never_after_win_or_fail_or_during_a_shot() -> bool:
	for over in [WON, FAILED]:
		var env := _setup()
		_action(env, [over])
		env["director"].advance_idle(60.0)
		check(not _said_triggers(env).has("on_idle"), "no idle after %s" % over["type"])
		_free(env)
	var env := _setup()
	env["ripple"].play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	env["director"].advance_idle(60.0)
	check_eq(env["said"], [], "no idle during the ripple shot")
	_free(env)
	return true


func test_empty_pick_falls_back_to_level_spirit_lines() -> bool:
	# on_choice has act 3 lines only, so an act 1 level finds nothing.
	var meta := _l01_meta()
	meta["spirit_lines"] = {"on_choice": "A fallback from the level."}
	var env := _setup("L01_first_crate", meta)
	var result: Dictionary = env["director"].say("on_choice")
	check(DirectorScript.USE_LEVEL_SPIRIT_LINES, "fallback is enabled")
	check_eq(result["source"], "level", "fell back to spirit_lines")
	check_eq(env["said"], [["on_choice", result["mood"], "A fallback from the level."]], "the fallback line is said")
	var none: Dictionary = env["director"].say("on_reveal")
	check_eq(none["source"], "none", "nothing anywhere")
	check_eq(env["said"].size(), 1, "an empty pick says nothing")
	_free(env)
	return true


func test_ending_signals_only_on_the_ending_level() -> bool:
	var env := _setup()
	_action(env, [APPLIED, WON])
	check_eq(env["endings"], [], "no ending prompt on L01")
	check_eq(_said_triggers(env), ["on_solve"], "the normal win line")
	_free(env)

	var meta := {"act": 3, "spirit_mood": "menacing", "mood_weights": {"menacing": 0.7, "triumphant": 0.3}}
	env = _setup(DirectorScript.ENDING_LEVEL_ID, meta)
	var director: Node = env["director"]
	_action(env, [APPLIED, WON])
	check_eq(env["endings"], [DirectorScript.ENDING_LEVEL_ID], "ending_choice_requested")
	check_eq(_said_triggers(env), ["on_choice"], "on_choice instead of on_solve")
	check(director.ending_pending, "waiting for the choice")
	env["bus"].ending_chosen.emit("burn")
	check_eq(_said_triggers(env), ["on_choice", "on_ending_burn"], "on_ending_burn")
	check(not director.ending_pending, "choice made")
	env["bus"].ending_chosen.emit("wind")
	check_eq(env["said"].size(), 2, "a second choice is ignored")
	_free(env)
	return true


func test_hud_changed_after_undo() -> bool:
	var main: Node = MainScript.new()
	Engine.get_main_loop().root.add_child(main)
	var huds: Array = []
	main.bus.hud_changed.connect(func(info): huds.append(info))
	main.load_entry({"id": "L01_first_crate", "path": L01_PATH})
	main._refresh()
	for d in ["right", "up", "up"]:
		main.controller.perform({"type": "move", "dir": d})
	main._refresh()
	check_eq(huds.back()["actions_used"], 3, "3 actions")
	check_eq(huds.back()["sun_index"], 1, "sun index 1 after 3 actions")
	check_eq(huds.back()["sun_hour"], 2, "sun at 2 o'clock")
	main.controller.undo()
	main._refresh()
	check_eq(huds.back(), {
		"level_id": "L01_first_crate", "title": "Something Warm", "actions_used": 2, "par": 10,
		"sun_index": 0, "sun_hour": 12, "status": "playing",
	}, "hud after undo")
	main.get_parent().remove_child(main)
	main.free()
	return true
