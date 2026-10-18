extends "res://tests/test_suite.gd"
## Tests for the spirit's flight: the streak's arc and timing math, the camera
## path that rides with it (and its exact restore), her laugh's pitch / volume /
## delay choices, and the voiced-line preference with a fixed seed.

const FlashScript := preload("res://presentation/spirit_flash.gd")
const RippleScript := preload("res://presentation/ripple_camera.gd")
const LaughScript := preload("res://presentation/spirit_laugh.gd")
const DirectorScript := preload("res://presentation/spirit_director.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")
const GS := preload("res://core/game_state.gd")


# --- Streak: arc and duration ---------------------------------------------------------

func test_flight_duration_grows_with_distance_and_is_capped() -> bool:
	check(is_equal_approx(FlashScript.flight_duration(0.0), FlashScript.MIN_FLIGHT_TIME), "a hop takes the minimum")
	check(FlashScript.flight_duration(9.0) > FlashScript.flight_duration(2.0), "farther takes longer")
	check(is_equal_approx(FlashScript.flight_duration(18.0), FlashScript.MAX_FLIGHT_TIME), "across the clock is about 0.9 s")
	check(is_equal_approx(FlashScript.flight_duration(500.0), FlashScript.MAX_FLIGHT_TIME), "capped")
	check(FlashScript.flight_duration(9.0) >= 0.7 and FlashScript.flight_duration(9.0) <= 0.9, "neighbouring rooms: about 0.75 s")
	return true


func test_arc_starts_and_ends_on_the_tiles_and_rises_between() -> bool:
	var start := ClockLayoutScript.hour_to_room_position(12)
	var end := ClockLayoutScript.hour_to_room_position(4)
	check(FlashScript.arc_position(start, end, 0.0).is_equal_approx(Vector3(start.x, FlashScript.BASE_HEIGHT, start.z)), "starts on the burned tile")
	check(FlashScript.arc_position(start, end, 1.0).is_equal_approx(Vector3(end.x, FlashScript.BASE_HEIGHT, end.z)), "ends on the landing tile")
	var middle := FlashScript.arc_position(start, end, 0.5)
	check(middle.y > FlashScript.BASE_HEIGHT + 1.0, "the arc rises in the middle (%.2f)" % middle.y)
	check(middle.y <= FlashScript.BASE_HEIGHT + FlashScript.ARC_HEIGHT_MAX + 0.001, "and stays under the cap")
	return true


func test_arc_is_smooth() -> bool:
	var start := ClockLayoutScript.hour_to_room_position(2) + Vector3(1, 0, -1)
	var end := ClockLayoutScript.hour_to_room_position(10) + Vector3(-1, 0, 1)
	var previous := FlashScript.arc_position(start, end, 0.0)
	var longest := 0.0
	for i in range(1, 61):
		var p := FlashScript.arc_position(start, end, i / 60.0)
		longest = maxf(longest, p.distance_to(previous))
		previous = p
	check(longest < 1.4, "no jump between 60 samples (longest step %.2f)" % longest)
	return true


func test_ground_path_goes_round_the_clock_not_through_the_hub() -> bool:
	for pair in [[12, 6], [2, 8], [4, 10], [12, 4], [10, 2]]:
		var a := ClockLayoutScript.hour_to_room_position(pair[0])
		var b := ClockLayoutScript.hour_to_room_position(pair[1])
		for i in range(0, 21):
			var p := FlashScript.ground_position(a, b, i / 20.0)
			check(p.length() > ClockLayoutScript.RADIUS - 1.0, "%s stays on the ring at %d/20 (%.2f)" % [str(pair), i, p.length()])
			check(is_zero_approx(p.y), "the ground path is on the ground")
	# 2 -> 10 goes the short way, through 12.
	var through := FlashScript.ground_position(ClockLayoutScript.hour_to_room_position(2), ClockLayoutScript.hour_to_room_position(10), 0.5)
	check(through.distance_to(ClockLayoutScript.hour_to_room_position(12)) < 0.5, "2 -> 10 passes 12 o'clock")
	return true


func test_a_hop_in_one_room_is_a_straight_line() -> bool:
	var a := Vector3(1, 0, 1)
	var b := Vector3(3, 0, 1)
	check(FlashScript.ground_position(a, b, 0.5).is_equal_approx(Vector3(2, 0, 1)), "straight between two tiles")
	return true


func test_rooms_light_up_as_she_passes() -> bool:
	var twelve := ClockLayoutScript.hour_to_room_position(12)
	check_eq(FlashScript.rooms_near(twelve), [12], "over the 12 o'clock room")
	check_eq(FlashScript.rooms_near(Vector3.ZERO), [], "over the hub: no room")
	var between := FlashScript.ground_position(twelve, ClockLayoutScript.hour_to_room_position(4), 0.5)
	check(2 in FlashScript.rooms_near(between), "passing the 2 o'clock room lights it")
	check_eq(FlashScript.nearest_hour(ClockLayoutScript.hour_to_room_position(8) + Vector3(0.5, 0, 0)), 8, "nearest hour")
	return true


func test_room_light_flickers_and_fades() -> bool:
	check(FlashScript.room_light_energy(0.0) > FlashScript.ROOM_LIGHT_PEAK * 0.7, "bright when it lights")
	check(FlashScript.room_light_energy(0.7) < FlashScript.room_light_energy(0.1), "fading")
	check_eq(FlashScript.room_light_energy(FlashScript.ROOM_LIGHT_TIME), 0.0, "out at the end")
	check_eq(FlashScript.room_light_energy(-1.0), 0.0, "not lit before")
	var distinct := {}
	for i in 10:
		distinct[snappedf(FlashScript.room_light_energy(0.05 + i * 0.01) / (1.0 - (0.05 + i * 0.01) / FlashScript.ROOM_LIGHT_TIME), 0.001)] = true
	check(distinct.size() > 3, "it flickers (the envelope-free value changes)")
	return true


func test_flash_node_flies_lights_and_cleans_up() -> bool:
	var flash: Node3D = FlashScript.new()
	Engine.get_main_loop().root.add_child(flash)
	flash.launch(ClockLayoutScript.hour_to_room_position(12), ClockLayoutScript.hour_to_room_position(2), 0.25, 0.8)
	check(flash.is_flying(), "a flight is queued")
	flash.advance(0.1)
	check(flash.get_node_or_null("SpiritStreak") == null, "nothing shows during the delay")
	flash.advance(0.3)
	check(flash.get_node_or_null("SpiritStreak") != null, "the streak shows once she leaves")
	check(flash.get_node_or_null("FlashLight_12") != null, "the 12 o'clock room is lit")
	flash.advance(1.0)
	check(not flash.is_flying(), "landed")
	check(flash.get_node_or_null("LandingAsh") != null, "ash where it landed")
	flash.advance(2.0)
	check_eq(flash.job_count(), 0, "everything is freed afterwards")
	flash.launch(Vector3(0, 0, -9), Vector3(8, 0, -4), 0.0, 0.8)
	flash.advance(0.2)
	flash.finish()
	check(not flash.is_flying(), "finish() lands what still flies (skip / cancel)")
	flash.clear()
	Engine.get_main_loop().root.remove_child(flash)
	flash.free()
	return true


# --- Camera path ------------------------------------------------------------------------

func test_flight_matches_the_plan() -> bool:
	for pair in [[12, 2], [12, 6], [2, 10], [8, 8]]:
		var flight := RippleScript.flight_of(pair[0], pair[1], Vector2i(2, 2), Vector2i(5, 5), Vector2i(1, 1))
		var plan := RippleScript.plan_shot(pair[0], pair[1], Vector2i(2, 2), Vector2i(5, 5), Vector2i(1, 1))
		check(is_equal_approx(flight["delay"], RippleScript.TO_ROOM_TIME + RippleScript.BEAT_TIME), "%s takes off after the beat" % str(pair))
		var in_flight := 0.0
		for key in plan:
			if key["phase"] in ["glide", "land"]:
				in_flight += key["duration"]
		check(is_equal_approx(in_flight, flight["duration"]), "%s: glide + land is the flight (%.3f vs %.3f)" % [str(pair), in_flight, flight["duration"]])
		check(RippleScript.total_duration(plan) < 1.5, "%s: under 1.5 s (%.2f)" % [str(pair), RippleScript.total_duration(plan)])
	return true


func test_camera_focus_rides_the_streak_path() -> bool:
	var flight := RippleScript.flight_of(12, 4, Vector2i(2, 1), Vector2i(5, 3), Vector2i(1, 1))
	var plan := RippleScript.plan_shot(12, 4, Vector2i(2, 1), Vector2i(5, 3), Vector2i(1, 1))
	var t := RippleScript.TO_ROOM_TIME + RippleScript.BEAT_TIME
	var checked := 0
	for key in plan:
		if key["phase"] == "overview" or key["phase"] == "to_room" or key["phase"] == "beat":
			continue
		t += key["duration"]
		if key["phase"] == "glide":
			var s := FlashScript.ease_time((t - flight["delay"]) / flight["duration"])
			var expected := FlashScript.ground_position(flight["start"], flight["end"], s)
			check(key["look_at"].distance_to(expected) < 0.01, "glide focus at %.2f s is on the streak's ground path" % t)
			checked += 1
	check(checked >= 3, "several glide samples checked (%d)" % checked)
	return true


func test_all_shots_are_short_and_in_range() -> bool:
	for a in GS.HOUR_ORDER:
		for b in GS.HOUR_ORDER:
			for slots in [[Vector2i(0, 0), Vector2i(4, 4)], [Vector2i(4, 4), Vector2i(0, 0)]]:
				var total := RippleScript.total_duration(RippleScript.plan_shot(a, b, slots[1], Vector2i(5, 5), slots[0]))
				check(total <= 1.5, "%d -> %d takes %.2f s" % [a, b, total])
	return true


func test_same_room_is_only_a_small_push_in() -> bool:
	var plan := RippleScript.plan_shot(8, 8, Vector2i(3, 3), Vector2i(5, 5), Vector2i(1, 1))
	var phases: Array = plan.map(func(k): return k["phase"])
	check(not phases.has("glide"), "no ripple around the clock")
	var push: Dictionary = plan[1]
	var full_room := ClockLayoutScript.hour_to_room_position(8) + RippleScript.ROOM_OFFSET
	var from_overview: float = push["position"].distance_to(RippleScript.OVERVIEW_POSITION)
	check(from_overview < RippleScript.OVERVIEW_POSITION.distance_to(full_room) * 0.5, "the camera only moves a little (%.1f)" % from_overview)
	return true


func test_overview_is_restored_exactly_after_every_kind_of_stop() -> bool:
	for how in ["finished", "skipped", "cancelled"]:
		var ripple: Node3D = RippleScript.new()
		Engine.get_main_loop().root.add_child(ripple)
		var before: Transform3D = ripple.camera.global_transform
		var before_position: Vector3 = ripple.camera.position
		ripple.play(RippleScript.plan_shot(12, 6, Vector2i(2, 2), Vector2i(5, 5), Vector2i(3, 1)))
		ripple.advance(0.6)
		check(not ripple.camera.position.is_equal_approx(before_position), "%s: the camera moved mid-shot" % how)
		match how:
			"finished":
				ripple.advance(5.0)
			"skipped":
				ripple.skip()
			"cancelled":
				ripple.cancel()
		check_eq(ripple.camera.position, before_position, "%s: exact position" % how)
		check(ripple.camera.global_transform.is_equal_approx(before), "%s: exact rotation too" % how)
		check_eq(ripple.last_stop_reason, how, "%s: stop reason" % how)
		Engine.get_main_loop().root.remove_child(ripple)
		ripple.free()
	return true


func test_flight_signal_fires_with_the_burn_and_landing() -> bool:
	var bus: Node = EventBusScript.new()
	var ripple: Node3D = RippleScript.new()
	ripple.connect_bus(bus)
	var seen: Array = []
	ripple.flight_started.connect(func(start, end, delay, duration): seen.append([start, end, delay, duration]))
	bus.emit_events([
		{"type": "burned", "id": "crate_a", "hour": 12, "slot": Vector2i(2, 2)},
		{"type": "ash_moved", "from_hour": 12, "to_hour": 4, "to_slot": Vector2i(1, 1), "becomes": "ash_path"},
		{"type": "action_applied", "actions_used": 2},
	])
	check_eq(seen.size(), 1, "one flight per ash_moved")
	check(seen[0][0].is_equal_approx(ClockLayoutScript.hour_to_room_position(12)), "from the burned tile")
	check(seen[0][1].is_equal_approx(ClockLayoutScript.hour_to_room_position(4) + Vector3(-1, 0, -1)), "to the landing tile")
	ripple.free()
	bus.free()
	return true


# --- Laugh ------------------------------------------------------------------------------------

class FakeState:
	var player_hour := 12
	var grid_w := 5
	var grid_h := 5


func test_laugh_pitch_by_hour() -> bool:
	check(is_equal_approx(LaughScript.pitch_for_hour(12), 0.92), "hour 12 is 0.92")
	check(is_equal_approx(LaughScript.pitch_for_hour(10), 1.12), "hour 10 is 1.12")
	var previous := 0.0
	for hour in [12, 2, 4, 6, 8, 10]:
		var p := LaughScript.pitch_for_hour(hour)
		check(p > previous, "pitch rises with the hour (%d: %.3f)" % [hour, p])
		previous = p
	return true


func test_laugh_volume_and_pitch_by_distance() -> bool:
	check_eq(LaughScript.room_steps(12, 12), 0, "same room")
	check_eq(LaughScript.room_steps(12, 2), 1, "neighbours")
	check_eq(LaughScript.room_steps(12, 10), 1, "neighbours round the corner")
	check_eq(LaughScript.room_steps(12, 6), 3, "opposite rooms")
	check_eq(LaughScript.room_steps(4, 10), 3, "opposite rooms again")
	check_eq(LaughScript.room_steps(2, 8), LaughScript.room_steps(8, 2), "symmetric")
	check_eq(LaughScript.volume_db_for_steps(0), 0.0, "full volume in the player's room")
	check(LaughScript.volume_db_for_steps(3) < LaughScript.volume_db_for_steps(1), "quieter when far")
	check(LaughScript.volume_db_for_steps(1) < 0.0, "even a neighbour is a little quieter")
	check(LaughScript.pitch_scale_for(6, 3) < LaughScript.pitch_scale_for(6, 0), "a bit lower when far")
	check(LaughScript.pitch_scale_for(6, 3) > 0.85, "but only a bit")
	return true


func test_line_waits_for_the_laugh() -> bool:
	check(is_equal_approx(LaughScript.line_delay(2.4, 0.0), 2.4 + LaughScript.LINE_GAP), "the whole laugh plus the gap")
	check(is_equal_approx(LaughScript.line_delay(2.4, 1.0), 1.4 + LaughScript.LINE_GAP), "what is left of it")
	check_eq(LaughScript.line_delay(2.4, 2.4), 0.0, "nothing once it is over")
	check_eq(LaughScript.line_delay(2.4, 9.0), 0.0, "nothing long after")
	return true


func test_laugh_plays_from_the_landing_room() -> bool:
	var bus: Node = EventBusScript.new()
	var laugh: Node3D = LaughScript.new()
	var state := FakeState.new()
	laugh.setup(bus, func(): return state)
	Engine.get_main_loop().root.add_child(laugh)
	bus.level_loaded.emit({"act": 2})
	check_eq(laugh.act, 2, "the level's act")
	state.player_hour = 12
	bus.ash_moved.emit({"type": "ash_moved", "from_hour": 12, "to_hour": 2, "to_slot": Vector2i(2, 2), "becomes": "ash_path"})
	check(laugh.player.stream != null, "the act's laugh file is loaded")
	check(laugh.player.position.is_equal_approx(ClockLayoutScript.hour_to_room_position(2)), "it comes from the landing room")
	var near_volume: float = laugh.last_volume_db
	check(laugh.line_wait() > 0.0, "a line chosen now has to wait")
	state.player_hour = 8
	bus.ash_moved.emit({"type": "ash_moved", "from_hour": 12, "to_hour": 2, "to_slot": Vector2i(2, 2), "becomes": "ash_path"})
	check(laugh.last_volume_db < near_volume, "quieter when the player is far from the landing room")
	laugh.stop()
	check_eq(laugh.line_wait(), 0.0, "no wait once stopped")
	Engine.get_main_loop().root.remove_child(laugh)
	laugh.free()
	bus.free()
	return true


func test_laugh_without_a_file_does_nothing() -> bool:
	var laugh: Node3D = LaughScript.new()
	laugh._stream_cache[LaughScript.laugh_path(1)] = null
	check(not laugh.on_ash_moved({"to_hour": 2, "to_slot": Vector2i(1, 1)}), "no file, no laugh, no crash")
	check_eq(laugh.line_wait(), 0.0, "and no waiting")
	check_eq(LaughScript.laugh_path(2), "res://audio/voice/cinder_laugh_act2_01.mp3", "laugh path")
	check_eq(LaughScript.laugh_path(9), "res://audio/voice/cinder_laugh_act3_01.mp3", "laugh path clamps")
	laugh.free()
	return true


func test_director_holds_the_line_for_the_laugh() -> bool:
	var bus: Node = EventBusScript.new()
	var director: Node = DirectorScript.new()
	director.connect_bus(bus)
	Engine.get_main_loop().root.add_child(director)
	director.start_level("LAUGH", {"act": 1, "spirit_mood": "amused"})
	var said: Array = []
	bus.spirit_said.connect(func(trigger, _mood, _text): said.append(trigger))
	director._deliver({"trigger": "on_burn", "line_mood": "amused", "text": "x"})
	check_eq(said, ["on_burn"], "no laugh: the line is said at once")
	var stub := LaughStub.new()
	stub.wait = 1.0
	director.laugh = stub
	director._deliver({"trigger": "on_undo", "line_mood": "amused", "text": "y"})
	check_eq(said, ["on_burn"], "a laugh is playing: the line waits")
	director._on_reset()  # undo / restart / load drops it
	Engine.get_main_loop().root.remove_child(director)
	director.free()
	bus.free()
	return true


class LaughStub:
	var wait := 0.0

	func line_wait() -> float:
		return wait


# --- Voiced lines preferred -------------------------------------------------------------------

## A (trigger, act, mood) with both voiced and unvoiced lines, from the live data.
func _mixed_group() -> Dictionary:
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string(DirectorScript.LINES_PATH))["lines"]
	var groups := {}
	for l in lines:
		var key := "%s|%d|%s" % [l["trigger"], int(l["act"]), l["mood"]]
		if not groups.has(key):
			groups[key] = {"trigger": l["trigger"], "act": int(l["act"]), "mood": l["mood"], "voiced": 0, "plain": 0}
		groups[key]["voiced" if DirectorScript.is_voiced(str(l["id"])) else "plain"] += 1
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		if groups[k]["voiced"] > 0 and groups[k]["plain"] > 0 and groups[k]["trigger"] not in ["on_choice", "on_reveal", "on_ending_wind", "on_ending_burn"]:
			return groups[k]
	return {}


func _says(group: Dictionary, level_id: String, count: int) -> Array:
	var director: Node = DirectorScript.new()
	director.start_level(level_id, {"act": group["act"], "spirit_mood": group["mood"]})
	var ids: Array = []
	for i in count:
		var r: Dictionary = director.say(group["trigger"])
		ids.append(r["text"])
	director.free()
	return ids


func test_voiced_lines_are_chosen_about_85_percent_of_the_time() -> bool:
	var group := _mixed_group()
	check(not group.is_empty(), "the live data has a trigger with voiced and unvoiced lines for one act and mood")
	if group.is_empty():
		return true
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string(DirectorScript.LINES_PATH))["lines"]
	var by_text := {}
	for l in lines:
		by_text[str(l["text"])] = str(l["id"])
	var voiced := 0
	var total := 0
	for n in 300:
		var texts := _says(group, "SEED%d" % n, 1)
		total += 1
		if DirectorScript.is_voiced(by_text[texts[0]]):
			voiced += 1
	var rate := float(voiced) / total
	check(rate > 0.78 and rate < 0.92, "voiced rate over 300 seeds is about 85%% (%.3f)" % rate)
	return true


func test_voiced_choice_is_reproducible_and_never_repeats_at_once() -> bool:
	var group := _mixed_group()
	if group.is_empty():
		return true
	check_eq(_says(group, "FIXED", 6), _says(group, "FIXED", 6), "same level and calls give the same lines")
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string(DirectorScript.LINES_PATH))["lines"]
	var by_text := {}
	for l in lines:
		by_text[str(l["text"])] = str(l["id"])
	for seed_name in ["FIXED", "A", "B", "C"]:
		var texts := _says(group, seed_name, 12)
		for i in range(1, texts.size()):
			check(texts[i] != texts[i - 1], "%s: no line twice in a row (%d)" % [seed_name, i])
	return true


func test_a_trigger_with_no_voiced_line_is_left_alone() -> bool:
	var director: Node = DirectorScript.new()
	director.start_level("PLAIN", {"act": 1, "spirit_mood": "annoyed"})
	var r: Dictionary = director.say("on_fail")
	check(r["text"] != "", "on_fail still says something")
	director.free()
	return true
