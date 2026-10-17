extends "res://tests/test_suite.gd"
## Tests for presentation/ripple_camera.gd: shot planning (pure), event
## pairing, and input lock / skip. Nodes never enter a tree; the shot is
## stepped with advance() instead of real frames.

const GS := preload("res://core/game_state.gd")
const RippleScript := preload("res://presentation/ripple_camera.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")
const ControllerScript := preload("res://presentation/game_controller.gd")

const L01_PATH := "res://tests/fixtures/L01_first_crate.json"


func _key_event(keycode: Key, pressed: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = pressed
	return e


func _glide_looks(plan: Array) -> Array:
	return plan.filter(func(k): return k["phase"] == "glide").map(func(k): return k["look_at"])


func test_plan_starts_and_ends_at_overview() -> bool:
	for pair in [[12, 4], [12, 6], [2, 10], [8, 8]]:
		var plan := RippleScript.plan_shot(pair[0], pair[1], Vector2i(2, 2))
		var first: Dictionary = plan.front()
		var last: Dictionary = plan.back()
		check_eq(first["position"], RippleScript.OVERVIEW_POSITION, "%s starts at the overview position" % str(pair))
		check_eq(first["look_at"], RippleScript.OVERVIEW_LOOK, "%s starts looking at the overview target" % str(pair))
		check_eq(first["duration"], 0.0, "%s first keyframe is the start pose" % str(pair))
		check_eq(last["position"], RippleScript.OVERVIEW_POSITION, "%s ends at the overview position" % str(pair))
		check_eq(last["look_at"], RippleScript.OVERVIEW_LOOK, "%s ends looking at the overview target" % str(pair))
	return true


func test_every_shot_is_under_one_and_a_half_seconds() -> bool:
	for a in GS.HOUR_ORDER:
		for b in GS.HOUR_ORDER:
			var total := RippleScript.total_duration(RippleScript.plan_shot(a, b, Vector2i(4, 4)))
			check(total < 1.5, "%d -> %d takes %.2f s" % [a, b, total])
			check(total > 0.5, "%d -> %d is not instant (%.2f s)" % [a, b, total])
	return true


func test_12_to_4_arcs_past_2_and_avoids_the_hub() -> bool:
	var plan := RippleScript.plan_shot(12, 4, Vector2i(2, 1), Vector2i(5, 3))
	var looks := _glide_looks(plan)
	check(looks.size() >= 3, "several arc keyframes (%d)" % looks.size())
	var two_room := ClockLayoutScript.hour_to_room_position(2)
	var nearest := INF
	for look in looks:
		nearest = minf(nearest, look.distance_to(two_room))
		check(look.length() > ClockLayoutScript.RADIUS - 2.5, "arc point %s stays away from the hub" % look)
	check(nearest < 1.0, "the arc passes the 2 o'clock room (closest %.2f)" % nearest)
	# The landing hold looks at the landing tile in the 4 o'clock room.
	var hold: Dictionary = plan.filter(func(k): return k["phase"] == "hold")[0]
	var expected := ClockLayoutScript.hour_to_room_position(4) + Vector3(0, 0, 0)  # slot [2,1] is the 5x3 center
	check(hold["look_at"].is_equal_approx(expected), "holds on the landing tile (%s)" % hold["look_at"])
	return true


func test_arc_goes_the_short_way() -> bool:
	# 2 -> 10 is 120 degrees counterclockwise (through 12), not 240 clockwise.
	var looks := _glide_looks(RippleScript.plan_shot(2, 10, Vector2i(2, 2)))
	var twelve := ClockLayoutScript.hour_to_room_position(12)
	var six := ClockLayoutScript.hour_to_room_position(6)
	var near_twelve := looks.any(func(p): return p.distance_to(twelve) < 1.0)
	var near_six := looks.any(func(p): return p.distance_to(six) < 3.0)
	check(near_twelve, "passes 12 o'clock")
	check(not near_six, "does not go round past 6 o'clock")
	return true


func test_same_hour_is_a_push_in() -> bool:
	var plan := RippleScript.plan_shot(8, 8, Vector2i(1, 3), Vector2i(5, 5), Vector2i(1, 2))
	var phases: Array = plan.map(func(k): return k["phase"])
	check(not phases.has("glide"), "no glide for the same hour")
	check_eq(phases, ["overview", "to_room", "land", "hold", "return"], "push-in phases")
	var room: Dictionary = plan[1]
	var land: Dictionary = plan[2]
	check(land["position"].distance_to(land["look_at"]) < room["position"].distance_to(room["look_at"]), "the landing pose is closer (push-in)")
	return true


func _ripple_with_bus() -> Array:
	var bus: Node = EventBusScript.new()
	var ripple: Node3D = RippleScript.new()
	ripple.connect_bus(bus)
	return [bus, ripple]


func test_burn_without_ash_moved_plays_nothing() -> bool:
	var pair := _ripple_with_bus()
	var bus: Node = pair[0]
	var ripple: Node3D = pair[1]
	var started: Array = []
	ripple.ripple_started.connect(func(): started.append(true))
	bus.emit_events([
		{"type": "burned", "id": "bridge_a", "hour": 12, "slot": Vector2i(1, 2)},
		{"type": "action_applied", "actions_used": 1},
	])
	check(not ripple.is_playing(), "a burn without ash_moved plays no shot")
	# A later stray ash_moved must not pair with the old burn.
	bus.emit_events([{"type": "ash_moved", "from_hour": 12, "to_hour": 2, "to_slot": Vector2i(2, 2), "becomes": "ash_path"}])
	check(not ripple.is_playing(), "the old burn was dropped at action_applied")
	check_eq(started, [], "ripple_started never fired")
	ripple.free()
	bus.free()
	return true


func test_burn_then_ash_moved_plays_and_finishes() -> bool:
	var pair := _ripple_with_bus()
	var bus: Node = pair[0]
	var ripple: Node3D = pair[1]
	var log: Array = []
	ripple.ripple_started.connect(func(): log.append("started"))
	ripple.ripple_finished.connect(func(): log.append("finished"))
	bus.emit_events([
		{"type": "burned", "id": "crate_a", "hour": 12, "slot": Vector2i(2, 2)},
		{"type": "ash_moved", "from_hour": 12, "to_hour": 2, "to_slot": Vector2i(2, 2), "becomes": "ash_path"},
		{"type": "action_applied", "actions_used": 2},
	])
	check(ripple.is_playing(), "burned + ash_moved plays the shot")
	ripple.advance(0.4)
	check(ripple.is_playing(), "still playing mid-shot")
	ripple.advance(2.0)
	check(not ripple.is_playing(), "done after its duration")
	check(ripple.camera.position.is_equal_approx(RippleScript.OVERVIEW_POSITION), "back at the overview")
	check_eq(log, ["started", "finished"], "signals")
	ripple.free()
	bus.free()
	return true


func test_key_press_while_playing_is_consumed_and_skips() -> bool:
	var bus: Node = EventBusScript.new()
	var ripple: Node3D = RippleScript.new()
	var controller: Node = ControllerScript.new()
	controller.bus = bus
	controller.blocker = ripple
	controller.load_level(L01_PATH)
	var before: String = controller.current_state().hash_key()

	check(not ripple.consume_input(_key_event(KEY_RIGHT)), "nothing consumed when no shot plays")
	ripple.play(RippleScript.plan_shot(12, 2, Vector2i(2, 2)))
	check(ripple.is_playing(), "playing")
	# The controller applies no actions while the shot plays.
	check_eq(controller.handle_key(KEY_RIGHT), {}, "controller ignores keys while playing")
	check_eq(controller.current_state().hash_key(), before, "no action applied")
	# The key press itself is consumed and skips the shot.
	check(ripple.consume_input(_key_event(KEY_RIGHT)), "key press consumed")
	check(not ripple.is_playing(), "the key press skipped the shot")
	check(ripple.camera.position.is_equal_approx(RippleScript.OVERVIEW_POSITION), "snapped back to the overview")
	check_eq(controller.current_state().hash_key(), before, "the skipping key was not an action")
	check(not ripple.consume_input(_key_event(KEY_RIGHT, false)), "its release after the skip is not consumed")
	# After the shot, keys act again.
	check(controller.handle_key(KEY_RIGHT)["ok"], "keys work again after the shot")
	controller.free()
	ripple.free()
	bus.free()
	return true


func test_cancel_stops_at_once() -> bool:
	var ripple: Node3D = RippleScript.new()
	ripple.play(RippleScript.plan_shot(4, 10, Vector2i(0, 0)))
	ripple.advance(0.3)
	ripple.cancel()
	check(not ripple.is_playing(), "cancelled")
	check(ripple.camera.position.is_equal_approx(RippleScript.OVERVIEW_POSITION), "overview pose")
	check(ripple.get_node_or_null("AshMote") == null, "mote removed")
	ripple.free()
	return true


func test_ease_in_out() -> bool:
	check(is_zero_approx(RippleScript.ease_in_out(0.0)), "starts at 0")
	check(is_equal_approx(RippleScript.ease_in_out(1.0), 1.0), "ends at 1")
	check(is_equal_approx(RippleScript.ease_in_out(0.5), 0.5), "half way at 0.5")
	check(RippleScript.ease_in_out(0.1) < 0.1, "slow start (not linear)")
	return true
