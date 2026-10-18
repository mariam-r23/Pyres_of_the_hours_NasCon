extends SceneTree
## Runs every test suite, then every JSON case file. Usage:
##   godot_console --headless -s tests/run_tests.gd
## Exits with code 1 if any test or case fails.

const CaseRunner := preload("res://tests/case_runner.gd")

const SUITES := [
	"res://tests/test_game_state.gd",
	"res://tests/test_level_loader.gd",
	"res://tests/test_level_validator.gd",
	"res://tests/test_walkability.gd",
	"res://tests/test_turn_manager.gd",
	"res://tests/test_burn.gd",
	"res://tests/test_sun_shadows.gd",
	"res://tests/test_win_fail.gd",
	"res://tests/test_undo.gd",
	"res://tests/test_case_runner.gd",
	"res://tests/test_presentation.gd",
	"res://tests/test_views.gd",
	"res://tests/test_progression.gd",
	"res://tests/test_feedback.gd",
	"res://tests/test_ripple.gd",
	"res://tests/test_spirit.gd",
	"res://tests/test_passed_hours.gd",
	"res://tests/test_menus.gd",
	"res://tests/test_ui.gd",
	"res://tests/test_spirit_flight.gd",
	"res://tests/test_painted_floor.gd",
	"res://tests/test_layout.gd",
]

## Our own case file; every *.json in SHARED_CASES_DIR (Mariam's) runs too.
const OWN_CASE_FILES := ["res://tests/fixtures/sample_cases.json"]
const SHARED_CASES_DIR := "res://tests/cases"

var passed := 0
var failed := 0
var _started := false


## Runs on the first frame rather than in _init: by then the tree is live,
## so tests can add real nodes (e.g. main.gd) and their _ready runs.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_suites()
		_run_cases()
		print("\n%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false


func _run_suites() -> void:
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			_report(false, "%s :: could not load (see parse errors above)" % path.get_file(), [])
			continue
		var suite = script.new()
		for method in suite.get_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			suite.failures.clear()
			if suite.call(name) != true:
				suite.failures.append("did not return true (script error above, or missing 'return true')")
			_report(suite.failures.is_empty(), "%s :: %s" % [path.get_file(), name], suite.failures)


func _run_cases() -> void:
	var files: Array = OWN_CASE_FILES.duplicate()
	files.append_array(CaseRunner.json_files_in(SHARED_CASES_DIR))
	for path in files:
		for result in CaseRunner.run_file(path):
			var messages := [] if result["ok"] else [result["message"]]
			_report(result["ok"], "case %s :: %s" % [path.get_file(), result["name"]], messages)


func _report(ok: bool, label: String, messages: Array) -> void:
	if ok:
		passed += 1
		print("PASS  " + label)
	else:
		failed += 1
		print("FAIL  " + label)
		for message in messages:
			print("        - " + message)
