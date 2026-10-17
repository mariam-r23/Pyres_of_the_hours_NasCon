extends SceneTree
## Runs every test suite. Usage:
##   godot_console --headless -s tests/run_tests.gd
## Exits with code 1 if any test fails.
## (Loading the shared JSON cases in tests/cases/ is added in Day 1 step 12.)

const SUITES := [
	"res://tests/test_game_state.gd",
	"res://tests/test_level_loader.gd",
	"res://tests/test_level_validator.gd",
	"res://tests/test_walkability.gd",
	"res://tests/test_turn_manager.gd",
	"res://tests/test_burn.gd",
]


func _init() -> void:
	var passed := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			failed += 1
			print("FAIL  %s :: could not load (see parse errors above)" % path.get_file())
			continue
		var suite = script.new()
		for method in suite.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures.clear()
			if suite.call(name) != true:
				suite.failures.append("did not return true (script error above, or missing 'return true')")
			if suite.failures.is_empty():
				passed += 1
				print("PASS  %s :: %s" % [path.get_file(), name])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [path.get_file(), name])
				for message in suite.failures:
					print("        - " + message)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
