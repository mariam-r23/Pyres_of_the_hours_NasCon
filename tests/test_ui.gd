extends "res://tests/test_suite.gd"
## Tests for the pure parts of ui/: dial geometry, the dialogue throttle and
## no-overlap rule, display times, portrait and voice paths, the ending choice
## logic, plus a small wiring check of the dialogue box and ending screen.

const SunDial := preload("res://ui/sun_dial.gd")
const DialogueBox := preload("res://ui/dialogue_box.gd")
const EndingScreen := preload("res://ui/ending_screen.gd")
const ResultPanel := preload("res://ui/result_panel.gd")
const Hud := preload("res://ui/hud.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")


# --- Sun dial -------------------------------------------------------------------

func test_dial_is_six_hours_of_three_ticks() -> bool:
	check_eq(SunDial.HOURS, [12, 2, 4, 6, 8, 10], "the six hours")
	check_eq(SunDial.tick_count(), 18, "6 hours x 3 ticks")
	check_eq(SunDial.tick_count(2), 12, "other tick counts follow")
	for h in 6:
		check(is_equal_approx(SunDial.hour_angle(h), h * PI / 3.0), "hour %d is 60 degrees apart" % h)
	return true


func test_dial_ticks_sit_between_hour_markers() -> bool:
	for h in 6:
		var previous := SunDial.hour_angle(h)
		for t in 3:
			var a := SunDial.tick_angle(h, t)
			check(a > previous + 0.01, "tick %d of hour %d comes after the previous mark" % [t, h])
			previous = a
		check(previous < SunDial.hour_angle(h + 1) - 0.01, "the last tick stays before the next hour")
	check(is_equal_approx(SunDial.tick_angle(0, 1) - SunDial.tick_angle(0, 0), deg_to_rad(15.0)), "ticks are 15 degrees apart")
	return true


func test_dial_lit_ticks_and_highlight() -> bool:
	check_eq(SunDial.lit_ticks(0, 0), 0, "nothing lit at the start")
	check_eq(SunDial.lit_ticks(0, 4), 4, "one tick per action")
	check_eq(SunDial.lit_ticks(1, 2), 5, "a later start counts its earlier hour")
	check_eq(SunDial.lit_ticks(0, 99), 18, "never more than 18")
	check_eq(SunDial.highlight_index(0), 0, "sun at 12")
	check_eq(SunDial.highlight_index(5), 5, "sun at 10")
	check_eq(SunDial.highlight_index(6), -1, "dial complete: no hour highlighted")
	check_eq(SunDial.tick_of(7), Vector2i(2, 1), "tick 7 is the second tick after hour 4")
	var top := SunDial.ring_point(Vector2.ZERO, 10.0, 0.0)
	check(top.is_equal_approx(Vector2(0, -10)), "angle 0 is the top")
	var right := SunDial.ring_point(Vector2.ZERO, 10.0, PI / 2.0)
	check(right.is_equal_approx(Vector2(10, 0)), "a quarter turn is the right")
	return true


# --- Dialogue box -----------------------------------------------------------------

func test_paths() -> bool:
	check_eq(DialogueBox.voice_path("a1_burn_01"), "res://audio/voice/cinder_a1_burn_01.mp3", "voice path")
	for mood in ["amused", "annoyed", "menacing", "triumphant"]:
		var path := DialogueBox.portrait_path(mood)
		check_eq(path, "res://art/portraits/spirit_portrait_%s.jpeg" % mood, "portrait for " + mood)
		check(ResourceLoader.exists(path), "portrait file exists: " + path)
	check_eq(DialogueBox.portrait_path("sleepy"), DialogueBox.portrait_path("amused"), "unknown mood uses the default")
	return true


func test_every_voice_file_belongs_to_a_line() -> bool:
	var ids := {}
	for l in JSON.parse_string(FileAccess.get_file_as_string("res://dialogue/lines.json"))["lines"]:
		ids[str(l["id"])] = l
	var voiced := 0
	for f in DirAccess.get_files_at("res://audio/voice"):
		if not f.ends_with(".mp3"):
			continue
		var id := f.trim_prefix("cinder_").trim_suffix(".mp3")
		if id.begins_with("laugh_act"):
			continue
		voiced += 1
		check(ids.has(id), "voice file %s has a line in lines.json" % f)
		if ids.has(id):
			check_eq(DialogueBox.line_id_for_text(str(ids[id]["text"])), id, "text finds the id of " + id)
	check_eq(voiced, 18, "18 voiced lines")
	check_eq(DialogueBox.line_id_for_text("not a real line"), "", "unknown text has no id")
	return true


func test_display_plan() -> bool:
	var voiced := DialogueBox.display_plan(5.0, "some text")
	check(is_equal_approx(voiced["box_time"], 5.5), "box outlasts the audio by 0.5 s")
	check(is_equal_approx(voiced["type_time"], 4.0), "typewriter finishes at 80% of the audio")
	check(voiced["type_time"] < 5.0, "text is done before the voice ends")
	var text_only := DialogueBox.display_plan(0.0, "Hello there, Keeper.")
	check(is_equal_approx(text_only["box_time"], 4.0), "about 4 s for text-only")
	check(text_only["type_time"] > 0.0 and text_only["type_time"] < 4.0, "typewriter fits inside the box time")
	var long_line := DialogueBox.display_plan(0.0, "x".repeat(400))
	check(long_line["type_time"] <= 3.0, "a long text-only line still finishes typing")
	return true


func test_typewriter_chars() -> bool:
	check_eq(DialogueBox.visible_chars(100, 0.0, 4.0), 0, "starts empty")
	check_eq(DialogueBox.visible_chars(100, 2.0, 4.0), 50, "half way")
	check_eq(DialogueBox.visible_chars(100, 4.0, 4.0), 100, "complete at type_time")
	check_eq(DialogueBox.visible_chars(100, 9.0, 4.0), 100, "stays complete")
	check_eq(DialogueBox.visible_chars(100, 1.0, 0.0), 100, "no type time shows everything")
	return true


func test_throttle_and_no_overlap() -> bool:
	var s := {"voice_until": -100.0, "last_text_at": -100.0}
	check(DialogueBox.can_start(s, "on_burn", false, 10.0), "a first line may start")
	s["last_text_at"] = 10.0
	check(not DialogueBox.can_start(s, "on_burn", false, 10.5), "text-only: throttled inside 1.5 s")
	check(not DialogueBox.can_start(s, "on_undo", false, 11.4), "still throttled at 1.4 s")
	check(DialogueBox.can_start(s, "on_burn", false, 11.5), "allowed again at 1.5 s")
	check(DialogueBox.can_start(s, "on_burn", true, 10.2), "a voiced line is not text-throttled")
	s["voice_until"] = 20.0
	check(not DialogueBox.can_start(s, "on_burn", true, 15.0), "no new voice line during a voice line")
	check(not DialogueBox.can_start(s, "on_undo", false, 15.0), "no text line during a voice line")
	check(not DialogueBox.can_start(s, "on_idle", true, 19.9), "idle waits for the voice")
	check(DialogueBox.can_start(s, "on_solve", true, 15.0), "on_solve may interrupt")
	check(DialogueBox.can_start(s, "on_fail", true, 15.0), "on_fail may interrupt")
	check(DialogueBox.can_start(s, "on_choice", true, 15.0), "on_choice (replaces on_solve) may interrupt")
	check(DialogueBox.can_start(s, "on_burn", true, 20.0), "free once the voice ended")
	return true


func test_dialogue_box_wiring() -> bool:
	var bus: Node = EventBusScript.new()
	var box: Control = DialogueBox.new()
	box.setup(bus)
	var lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://dialogue/lines.json"))["lines"]
	var voiced_text := ""
	var plain_text := ""
	for l in lines:
		if l["id"] == "a1_burn_01":
			voiced_text = l["text"]
		if l["id"] == "a1_burn_03":
			plain_text = l["text"]
	check(voiced_text != "" and plain_text != "", "found a voiced and a text-only line")
	check(box.show_line("on_burn", "amused", voiced_text), "a voiced line shows")
	check(box.current_has_voice, "it has a voice")
	check(box.name_label.text == DialogueBox.SPIRIT_NAME, "named Cinder")
	check(box.voice_player.stream != null, "the voice stream is loaded")
	check(not box.show_line("on_undo", "annoyed", plain_text), "a text line is dropped during the voice")
	check(box.show_line("on_solve", "amused", plain_text), "on_solve interrupts")
	check(not box.current_has_voice, "now a text-only line")
	box.advance(0.01)
	check(box.text_label.visible_characters < plain_text.length(), "the typewriter is mid-way")
	box.advance(10.0)
	check(not box.visible, "the box hides after its time")
	box.free()
	bus.free()
	return true


func test_missing_assets_do_not_fail() -> bool:
	var box: Control = DialogueBox.new()
	box._apply_portrait("amused")
	check(box.portrait_rect.visible != box.silhouette.visible, "exactly one of portrait / silhouette shows")
	var tex: Texture2D = box._portrait_texture("nonexistent_mood_xyz")
	check(tex == null or tex is Texture2D, "an unknown mood never crashes")
	check(box._audio("res://audio/voice/cinder_does_not_exist.mp3") == null, "a missing voice file is just null")
	box.free()
	return true


# --- Ending ---------------------------------------------------------------------------

func test_ending_choice_logic() -> bool:
	check_eq(EndingScreen.move_selection(0, 1), 1, "right selects LET IT BURN")
	check_eq(EndingScreen.move_selection(1, 1), 1, "stays at the last choice")
	check_eq(EndingScreen.move_selection(0, -1), 0, "stays at the first choice")
	check_eq(EndingScreen.choice_at(0), "wind", "first choice is wind")
	check_eq(EndingScreen.choice_at(1), "burn", "second choice is burn")
	check_eq(EndingScreen.choice_for_key(KEY_1), "wind", "key 1")
	check_eq(EndingScreen.choice_for_key(KEY_2), "burn", "key 2")
	check_eq(EndingScreen.choice_for_key(KEY_3), "", "other keys choose nothing")
	check_eq(EndingScreen.key_action(KEY_LEFT), {"move": -1}, "left")
	check_eq(EndingScreen.key_action(KEY_RIGHT), {"move": 1}, "right")
	check_eq(EndingScreen.key_action(KEY_ENTER), {"confirm": true}, "enter")
	check_eq(EndingScreen.key_action(KEY_X), {}, "nothing else")
	for choice in ["wind", "burn"]:
		var n: int = EndingScreen.epilogue_lines(choice).size()
		check(n >= 4 and n <= 6, "%s epilogue has 4 to 6 lines (%d)" % [choice, n])
	check_eq(EndingScreen.epilogue_lines("nope"), [], "unknown choice has no epilogue")
	return true


func test_ending_screen_flow() -> bool:
	var bus: Node = EventBusScript.new()
	var screen: Control = EndingScreen.new()
	screen.setup(bus)
	var chosen: Array = []
	bus.ending_chosen.connect(func(c): chosen.append(c))
	check_eq(screen.state, "hidden", "starts hidden")
	screen.show_choice()
	check_eq(screen.state, "choice", "choice is up")
	check(screen.visible, "visible")
	screen.confirm("burn")
	check_eq(chosen, ["burn"], "the choice goes out as ending_chosen")
	check_eq(screen.state, "epilogue", "then the epilogue")
	check_eq(screen.choice, "burn", "remembers the choice")
	check(screen.again_label.text.begins_with("Press R"), "only the play-again prompt follows")
	screen.confirm("wind")
	check_eq(chosen, ["burn"], "a second choice is ignored")
	bus.level_restarted.emit()
	check_eq(screen.state, "hidden", "restart hides it")
	# A key 1 / 2 choice (main.gd emits the signal) reaches the epilogue too.
	screen.show_choice()
	bus.ending_chosen.emit("wind")
	check_eq(screen.state, "epilogue", "the signal alone starts the epilogue")
	check_eq(screen.epilogue_title.text, EndingScreen.EPILOGUES["wind"]["title"], "wind epilogue title")
	screen.free()
	bus.free()
	return true


# --- HUD / panel / theme --------------------------------------------------------------

func test_hud_texts() -> bool:
	check_eq(Hud.actions_text(3, 10), "Actions  3 / par 10", "actions vs par")
	check_eq(Hud.actions_text(3, -1), "Actions  3 / par -", "no par")
	check_eq(Hud.rejection_text_for({"a": "Friendly."}, "a"), "Friendly.", "mapped reason")
	check_eq(Hud.rejection_text_for({"a": "Friendly."}, "zzz"), "zzz", "unmapped reason shows raw")
	return true


func test_result_panel_buttons() -> bool:
	check_eq(ResultPanel.button_ids(true, true), ["next", "retry", "undo"], "a win with a next level")
	check_eq(ResultPanel.button_ids(true, false), ["retry", "undo"], "a win on the last level")
	check_eq(ResultPanel.button_ids(false, true), ["retry", "undo"], "a fail never offers next")
	return true


func test_theme_never_fails() -> bool:
	for kind in ["heading", "body", "emphasis", "button"]:
		check(UiTheme.font(kind) != null, "font " + kind)
	check(UiTheme.font("not_a_kind") != null, "an unknown font kind falls back")
	check_eq(UiTheme.color("background"), Color("0E1116"), "background")
	check_eq(UiTheme.color("ember"), Color("FF6A13"), "ember")
	return true


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_ending_screen_keys() -> bool:
	var bus: Node = EventBusScript.new()
	var screen: Control = EndingScreen.new()
	screen.setup(bus)
	Engine.get_main_loop().root.add_child(screen)
	var chosen: Array = []
	bus.ending_chosen.connect(func(c): chosen.append(c))
	screen._input(_key(KEY_RIGHT))
	check_eq(screen.selected, 0, "keys are ignored while the screen is hidden")
	screen.show_choice()
	screen._input(_key(KEY_RIGHT))
	check_eq(screen.selected, 1, "right selects LET IT BURN")
	screen._input(_key(KEY_LEFT))
	check_eq(screen.selected, 0, "left goes back")
	screen._input(_key(KEY_RIGHT))
	screen._input(_key(KEY_ENTER))
	check_eq(chosen, ["burn"], "Enter confirms the selected choice")
	check_eq(screen.state, "epilogue", "then the epilogue")
	Engine.get_main_loop().root.remove_child(screen)
	screen.free()
	bus.free()
	return true
