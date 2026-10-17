extends "res://tests/test_suite.gd"
## Tests for the menus: progress save (pure), level select rows, and on the
## real main.gd: locked levels, pause blocking input and idle, Escape order,
## and progress written on a win. main.gd uses a temp progress file here.

const Progress := preload("res://presentation/menus/progress.gd")
const LevelSelectScript := preload("res://presentation/menus/level_select.gd")
const MainMenuScript := preload("res://presentation/menus/main_menu.gd")
const CreditsScript := preload("res://presentation/menus/credits.gd")
const LevelList := preload("res://presentation/level_list.gd")
const MainScript := preload("res://presentation/main.gd")
const CaseRunner := preload("res://tests/case_runner.gd")

const IDS := ["A01", "A02", "A03"]
const TEMP_PATH := "user://test_progress.json"
const L01_SOLUTION := ["move:right", "burn:right", "move:right", "move:right", "move:right",
	"interact", "move:right", "move:right", "move:right", "move:right"]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_missing_and_corrupt_files_give_fresh_progress() -> bool:
	_remove(TEMP_PATH)
	check_eq(Progress.load_from(TEMP_PATH, IDS), {"unlocked": ["A01"], "best": {}}, "missing file")
	for bad in ["not json {", "[1, 2, 3]", "\"just a string\"", ""]:
		_write(TEMP_PATH, bad)
		check_eq(Progress.load_from(TEMP_PATH, IDS), Progress.fresh(IDS), "corrupt: %s" % bad)
	_write(TEMP_PATH, JSON.stringify({"unlocked": ["A02", "ZZZ", 7], "best": {"A02": 9, "A01": -3, "A03": "x", "ZZZ": 4, "A01x": 1}}))
	check_eq(Progress.load_from(TEMP_PATH, IDS), {"unlocked": ["A01", "A02"], "best": {"A02": 9}}, "bad entries dropped, first level kept")
	_remove(TEMP_PATH)
	return true


func test_save_and_load_round_trip() -> bool:
	var p := Progress.record_win(Progress.fresh(IDS), "A01", 12, IDS)
	check(Progress.save_to(TEMP_PATH, p), "saved")
	check_eq(Progress.load_from(TEMP_PATH, IDS), p, "loads back the same")
	_remove(TEMP_PATH)
	return true


func test_unlock_order() -> bool:
	var p := Progress.fresh(IDS)
	check(Progress.is_unlocked(p, "A01") and not Progress.is_unlocked(p, "A02"), "only the first level at start")
	check(not Progress.has_progress(p), "nothing to continue yet")
	p = Progress.record_win(p, "A01", 12, IDS)
	check(Progress.is_unlocked(p, "A02"), "winning A01 unlocks A02")
	check(not Progress.is_unlocked(p, "A03"), "A03 still locked")
	check(Progress.has_progress(p), "something to continue")
	check_eq(Progress.continue_level(p, IDS), "A02", "continue goes to the furthest unlocked level")
	p = Progress.record_win(p, "A03", 5, IDS)  # e.g. a debug jump: last level unlocks nothing new
	check_eq(p["unlocked"], ["A01", "A02", "A03"], "no crash on the last level")
	return true


func test_best_only_improves() -> bool:
	var p := Progress.record_win(Progress.fresh(IDS), "A01", 12, IDS)
	p = Progress.record_win(p, "A01", 15, IDS)
	check_eq(Progress.best_of(p, "A01"), 12, "a worse run keeps the best")
	p = Progress.record_win(p, "A01", 9, IDS)
	check_eq(Progress.best_of(p, "A01"), 9, "a better run replaces it")
	check_eq(Progress.best_of(p, "A02"), -1, "never won")
	check_eq(Progress.merge({"unlocked": ["A01"], "best": {"A01": 7}}, {"unlocked": ["A02"], "best": {"A01": 8, "A02": 3}}),
		{"unlocked": ["A01", "A02"], "best": {"A01": 7, "A02": 3}}, "merge keeps the lower best and both unlocks")
	return true


func test_level_select_rows() -> bool:
	var entries := LevelList.all()
	if entries.size() < 2:
		return true
	var ids: Array = entries.map(func(e): return e["id"])
	var p := Progress.record_win(Progress.fresh(ids), ids[0], 12, ids)
	var rows := LevelSelectScript.build_rows(entries, p)
	check_eq(rows.size(), entries.size(), "one row per level")
	check(rows[0]["unlocked"] and rows[1]["unlocked"], "first two unlocked")
	check(rows[0]["text"].ends_with("12 / par %d" % rows[0]["par"]), "best / par: %s" % rows[0]["text"])
	check(rows[1]["text"].ends_with("- / par %d" % rows[1]["par"]), "never won: %s" % rows[1]["text"])
	if rows.size() > 2:
		check(not rows[2]["unlocked"] and rows[2]["text"].ends_with("locked"), "third locked: %s" % rows[2]["text"])
	check_eq(LevelSelectScript.best_par_text(-1, -1), "- / par -", "unknown best and par")
	return true


func test_main_menu_buttons_and_credits_text() -> bool:
	check_eq(MainMenuScript.buttons(false).map(func(b): return b[0]), ["new_game", "level_select", "credits", "quit"], "no Continue without progress")
	check_eq(MainMenuScript.buttons(true)[0][0], "continue", "Continue first with progress")
	var credits := CreditsScript.read_credits()
	for section in ["TEAM", "AI TOOLS USED", "ASSETS AND LICENSES", "TBD from Mariam/Noor", "Anosha", "Mariam", "Noor"]:
		check(section in credits, "credits mention %s" % section)
	check_eq(CreditsScript.read_credits("res://no_such_credits.txt"), CreditsScript.MISSING_TEXT, "missing credits file")
	return true


## The real main.gd in the tree with a fresh temp progress file.
func _main() -> Node:
	_remove(TEMP_PATH)
	var main: Node = MainScript.new()
	main.progress_path = TEMP_PATH
	Engine.get_main_loop().root.add_child(main)
	return main


func _free_main(main: Node) -> void:
	main.get_parent().remove_child(main)
	main.free()
	_remove(TEMP_PATH)


func _escape() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	return e


func test_launch_shows_the_main_menu_and_locked_levels_cannot_start() -> bool:
	var main := _main()
	check_eq(main.mode, "menu", "the main menu is shown on launch")
	check(not main._hud_layer.visible, "no HUD behind the menu")
	var before: String = main.controller.current_state().hash_key()
	check_eq(main.controller.handle_key(KEY_RIGHT), {}, "no game input behind the menu")
	check_eq(main.controller.current_state().hash_key(), before, "nothing moved")
	if main.level_ids.size() > 1:
		check(not main.start_level(main.level_ids[1]), "a locked level cannot start")
		check_eq(main.mode, "menu", "still in the menu")
	check(not main.start_level("NO_SUCH_LEVEL"), "an unknown level cannot start")
	check(main.start_level(main.level_ids[0]), "the first level starts")
	check_eq(main.mode, "playing", "playing")
	check(main._hud_layer.visible, "HUD shown in game")
	_free_main(main)
	return true


func test_pause_blocks_input_and_idle_and_skips_the_shot() -> bool:
	var main := _main()
	main.start_level(main.level_ids[0])
	var picked: Array = []
	main.director.line_picked.connect(func(r): picked.append(r["trigger"]))
	main.controller.perform({"type": "move", "dir": "right"})
	main.controller.perform({"type": "burn", "dir": "right"})
	check(main.ripple.is_playing(), "a ripple shot plays")
	main.pause()
	check_eq(main.mode, "paused", "paused")
	check(not main.ripple.is_playing(), "the shot was skipped")
	check_eq(main.ripple.hidden_slots(), {}, "nothing left hidden")
	var before: String = main.controller.current_state().hash_key()
	for key in [KEY_RIGHT, KEY_SPACE, KEY_E, KEY_B, KEY_Z, KEY_R]:
		main.controller.handle_key(key)
	check_eq(main.controller.current_state().hash_key(), before, "no game input while paused")
	main.director.advance_idle(60.0)
	check(not picked.has("on_idle"), "the idle timer does not count while paused")
	main.resume()
	check_eq(main.mode, "playing", "resumed")
	check(main.controller.handle_key(KEY_UP)["ok"], "keys work again")
	main.director.advance_idle(60.0)
	check(picked.has("on_idle"), "idle counts again after resuming")
	_free_main(main)
	return true


func test_escape_cancels_burn_mode_before_pausing() -> bool:
	var main := _main()
	main.start_level(main.level_ids[0])
	main.controller.handle_key(KEY_B)
	check(main.controller.burn_mode, "burn mode on")
	check_eq(main.escape_action(), "cancel_burn", "Escape first cancels burn mode")
	main._input(_escape())
	check_eq(main.mode, "playing", "main did not pause")
	main.controller.handle_key(KEY_ESCAPE)  # the controller gets the same key next
	check(not main.controller.burn_mode, "burn mode cancelled")
	check_eq(main.escape_action(), "pause", "the next Escape pauses")
	main._input(_escape())
	check_eq(main.mode, "paused", "paused")
	main._input(_escape())
	check_eq(main.mode, "playing", "Escape resumes")
	main.open_credits("menu")
	check_eq(main.escape_action(), "back", "Escape goes back from credits")
	main._input(_escape())
	check_eq(main.mode, "menu", "back at the main menu")
	_free_main(main)
	return true


func test_winning_writes_progress() -> bool:
	var main := _main()
	if main.level_ids.size() < 2 or main.level_ids[0] != "L01_first_crate":
		_free_main(main)
		return true
	check(not FileAccess.file_exists(TEMP_PATH), "nothing written before a win")
	main.start_level("L01_first_crate")
	for short in L01_SOLUTION:
		var parts: PackedStringArray = short.split(":")
		main.controller.perform({"type": parts[0], "dir": parts[1]} if parts.size() == 2 else {"type": parts[0]})
	check_eq(main.controller.current_state().status, "won", "won")
	var saved := Progress.load_from(TEMP_PATH, main.level_ids)
	check(Progress.is_unlocked(saved, main.level_ids[1]), "the next level unlocked on disk")
	check_eq(Progress.best_of(saved, "L01_first_crate"), 10, "best saved")
	check(main.can_start(main.level_ids[1]), "and it can start now")
	_free_main(main)
	return true


func test_after_the_ending_return_to_the_main_menu() -> bool:
	var main := _main()
	# Win the ending level for real with its shipped solution.
	var ending_id: String = main.director.ENDING_LEVEL_ID
	var actions: Array = []
	for c in JSON.parse_string(FileAccess.get_file_as_string("res://tests/cases/levels_shipped.json")):
		if c["level"] == ending_id and c["expect"].get("won", false):
			actions = c["actions"]
	if actions.is_empty():
		_free_main(main)
		return true  # no shipped solution for the ending level yet
	main.progress = Progress.merge(main.progress, {"unlocked": [ending_id], "best": {}})
	check(main.start_level(ending_id), "the ending level starts")
	for short in actions:
		main.controller.perform(CaseRunner.parse_action(short))
	check_eq(main.controller.current_state().status, "won", "the ending level is won")
	check(main.director.ending_pending, "the ending choice is pending")
	main._refresh()
	check(main._message.text != "" and not main._return_button.visible, "the prompt shows, no return button yet")
	main.bus.ending_chosen.emit("wind")
	main._refresh()
	check(main._ending_done, "ending done")
	check(main._message.text.ends_with("Press Enter to return to the main menu."), "the ending line then the prompt: %s" % main._message.text)
	check(main._message.text.begins_with(main.ENDING_TEXTS["wind"]), "the ending line comes first")
	check(main._return_button.visible, "a Return to main menu button too")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	main._input(enter)
	check_eq(main.mode, "menu", "Enter returns to the main menu")
	check(not main._ending_done, "cleared")
	_free_main(main)
	return true
