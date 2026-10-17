extends "res://tests/test_suite.gd"
## Tests for level progression: presentation/level_list.gd and the pure text
## helpers in presentation/main.gd. Uses the real levels/data/ folder without
## assuming which levels are in it, plus temp folders under user://.

const GS := preload("res://core/game_state.gd")
const Loader := preload("res://core/level_loader.gd")
const TM := preload("res://core/turn_manager.gd")
const LevelList := preload("res://presentation/level_list.gd")
const MainScript := preload("res://presentation/main.gd")

const TEMP_DIR := "user://level_list_test"
const EMPTY_DIR := "user://level_list_empty"


func _make_dir(dir: String, files: Array) -> void:
	_remove_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	for name in files:
		var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
		f.store_string("{}")
		f.close()


func _remove_dir(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	for name in access.get_files():
		access.remove(name)
	DirAccess.remove_absolute(dir)


func test_real_levels_folder() -> bool:
	var entries := LevelList.all()
	var expected: Array = Array(DirAccess.get_files_at("res://levels/data")).filter(func(f): return f.ends_with(".json"))
	expected.sort()
	check_eq(entries.map(func(e): return e["id"] + ".json"), expected, "every level file, sorted by filename")
	for e in entries:
		check(FileAccess.file_exists(e["path"]), "%s path exists" % e["id"])
	if entries.is_empty():
		return true
	check_eq(LevelList.first(), entries[0], "first is the first entry")
	for i in entries.size():
		check_eq(LevelList.index_of(entries[i]["id"]), i, "index_of %s" % entries[i]["id"])
		var next = LevelList.next_of(entries[i]["id"])
		if i + 1 < entries.size():
			check_eq(next, entries[i + 1], "next_of %s" % entries[i]["id"])
		else:
			check(next == null, "next_of the last level is null")
	check(LevelList.previous_of(entries[0]["id"]) == null, "nothing before the first level")
	return true


func test_temp_folder_order_and_filter() -> bool:
	_make_dir(TEMP_DIR, ["c_three.json", "a_one.json", "notes.txt", "b_two.json"])
	var entries := LevelList.all(TEMP_DIR)
	check_eq(entries.map(func(e): return e["id"]), ["a_one", "b_two", "c_three"], "sorted, .json only")
	check_eq(entries[0]["path"], TEMP_DIR.path_join("a_one.json"), "path")
	check_eq(LevelList.index_of("b_two", TEMP_DIR), 1, "index_of")
	check_eq(LevelList.next_of("a_one", TEMP_DIR)["id"], "b_two", "next_of first")
	check(LevelList.next_of("c_three", TEMP_DIR) == null, "next_of last is null")
	check_eq(LevelList.previous_of("c_three", TEMP_DIR)["id"], "b_two", "previous_of")
	check_eq(LevelList.index_of("nope", TEMP_DIR), -1, "unknown id")
	check(LevelList.next_of("nope", TEMP_DIR) == null, "next_of unknown id is null")
	check(LevelList.next_of("", TEMP_DIR) == null, "next_of before any level is null")
	_remove_dir(TEMP_DIR)
	return true


func test_empty_and_missing_folder() -> bool:
	_make_dir(EMPTY_DIR, [])
	check_eq(LevelList.all(EMPTY_DIR), [], "empty folder")
	check(LevelList.first(EMPTY_DIR) == null, "no first level")
	check(LevelList.next_of("L01", EMPTY_DIR) == null, "no next level")
	_remove_dir(EMPTY_DIR)
	check_eq(LevelList.all("user://no_such_folder"), [], "missing folder")
	return true


func test_end_message() -> bool:
	check_eq(MainScript.end_message("won", true), "You reached the exit.\nPress N for the next level, R to restart.", "win with a next level")
	check_eq(MainScript.end_message("won", false), "That was the last level for now.\nPress R to restart.", "win on the last level")
	check_eq(MainScript.end_message("failed", true), "The dial completed.\nPress R to restart or Z to undo.", "fail")
	check_eq(MainScript.end_message("failed", false), MainScript.end_message("failed", true), "fail ignores next level")
	check_eq(MainScript.end_message("playing", true), "", "no message while playing (undo hides it)")
	return true


func test_sun_and_status_text() -> bool:
	var loaded := Loader.load_file("res://tests/fixtures/L01_first_crate.json")
	var s: GS = loaded["state"]
	check_eq(MainScript.sun_text(s), "Sun: 12 o'clock, moves on in 3 actions", "start")
	s = TM.apply_action(TM.apply_action(s, {"type": "wait"})["state"], {"type": "wait"})["state"]
	check_eq(MainScript.sun_text(s), "Sun: 12 o'clock, moves on in 1 action", "after 2 waits")
	s = TM.apply_action(s, {"type": "wait"})["state"]
	check_eq(MainScript.sun_text(s), "Sun: 2 o'clock, moves on in 3 actions", "after 3 waits")
	var done := s.duplicate_deep()
	done.action_count = 18
	check_eq(MainScript.sun_text(done), "Sun: dial complete", "dial complete")
	check_eq(MainScript.status_text(loaded["meta"], "L01_first_crate", s),
		"Something Warm (L01_first_crate)\nActions: 3 / par 10\nSun: 2 o'clock, moves on in 3 actions\nSpirit: amused", "status")
	check_eq(MainScript.status_text({}, "X", s).get_slice("\n", 1), "Actions: 3 / par -", "no par")
	check_eq(MainScript.status_text({}, "X", s).get_slice("\n", 0), "X", "no title")
	return true
