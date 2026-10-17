extends SceneTree
## Checks every level in levels/data: loads it, validates it, solves it, compares to par.
## A level is not merged until this passes.
##
##   godot --headless -s tools/validate_levels.gd
##   godot --headless -s tools/validate_levels.gd -- res://tests/cases/fixtures/   (another folder)
##
## Prints: id, valid, solvable, shortest solution length, par_actions.
## Exit code 1 if any level fails to load, is invalid, is unsolvable, or its par_actions does
## not equal the solver's shortest length (a missing par counts as a failure).

const LevelLoader := preload("res://core/level_loader.gd")
const LevelValidator := preload("res://core/level_validator.gd")
const Solver := preload("res://tools/solver.gd")

const DEFAULT_DIR := "res://levels/data/"


func _init() -> void:
	var dir := DEFAULT_DIR
	var extra := OS.get_cmdline_user_args()
	if extra.size() > 0:
		dir = extra[0]
	quit(_run(dir))


func _run(dir: String) -> int:
	var files := _json_files(dir)
	if files.is_empty():
		print("no level files found in %s" % dir)
		return 1
	print(_row("id", "valid", "solvable", "shortest", "par"))
	var failures := 0
	for path in files:
		if not _check_file(path):
			failures += 1
	print("\n%d levels, %d failed" % [files.size(), failures])
	return 1 if failures > 0 else 0


## Prints one row. Returns true if the level passes every check.
func _check_file(path: String) -> bool:
	var name := path.get_file().get_basename()
	var loaded := LevelLoader.load_file(path)
	if loaded["state"] == null:
		print(_row(name, "NO", "-", "-", "-"))
		for line in str(loaded["error"]).split("\n"):
			print("    load error: %s" % line)
		return false

	var state = loaded["state"]
	var meta: Dictionary = loaded["meta"]
	var par: int = meta["par_actions"]
	var errors := LevelValidator.validate(state)
	if not errors.is_empty():
		print(_row(state.level_id, "NO", "-", "-", par))
		for line in errors:
			print("    invalid: %s" % line)
		return false

	var result := Solver.solve(state)
	var solved: bool = result["status"] == "solved"
	var shortest := -1
	if solved:
		shortest = result["actions"].size()
	var par_ok := solved and par == shortest
	var solvable_text: String = "yes" if solved else str(result["status"])
	var shortest_text: String = str(shortest) if solved else "-"
	var par_text: String = str(par) if par >= 0 else "missing"
	var flag: String = "" if par_ok else "   <-- FAIL"
	print(_row(state.level_id, "yes", solvable_text, shortest_text, par_text) + flag)
	if solved and not par_ok:
		print("    set par_actions to %d" % shortest)
		print("    solution: %s" % ", ".join(PackedStringArray(Solver.actions_to_strings(result["actions"]))))
	return par_ok


## One table row with fixed-width columns.
func _row(id: Variant, valid: Variant, solvable: Variant, shortest: Variant, par: Variant) -> String:
	return "%s %s %s %s %s" % [str(id).rpad(30), str(valid).rpad(6), str(solvable).rpad(9), str(shortest).rpad(9), str(par)]


func _json_files(dir: String) -> Array:
	var files: Array = []
	var access := DirAccess.open(dir)
	if access == null:
		return files
	for file in access.get_files():
		if file.get_extension() == "json":
			files.append(dir.path_join(file))
	files.sort()
	return files
