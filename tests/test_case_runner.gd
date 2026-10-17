extends "res://tests/test_suite.gd"
## Tests for the JSON case runner itself (tests/case_runner.gd).

const CaseRunner := preload("res://tests/case_runner.gd")

const L01_SOLUTION := ["move:right", "burn:right", "move:right", "move:right", "move:right",
	"interact", "move:right", "move:right", "move:right", "move:right"]


func _case(expect: Dictionary, actions: Array = L01_SOLUTION, level: String = "L01_first_crate") -> Dictionary:
	return {"name": "c", "level": level, "actions": actions, "expect": expect}


## Runs one case and checks ok, and that the message contains `expected`
## ("" = expect no message). Note: in GDScript, "" in "" is false.
func _expect(case: Variant, ok: bool, expected: String, label: String) -> void:
	var result := CaseRunner.run_case(case, "fallback")
	check_eq(result["ok"], ok, label + ": ok (message: %s)" % result["message"])
	if expected == "":
		check_eq(result["message"], "", label + ": no message")
	else:
		check(expected in result["message"], "%s: message should contain \"%s\", got \"%s\"" % [label, expected, result["message"]])


func test_passing_cases() -> bool:
	_expect(_case({"won": true, "failed": false, "actions_used": 10}), true, "", "L01 solution")
	_expect(_case({"rejected_at": 0, "reason": "nothing_to_burn"}, ["burn:up"]), true, "", "rejection")
	_expect(_case({"rejected_at": 0, "reason": "blocked_terrain"}, ["move:right"], "T01_wall"), true, "", "wall")
	return true


func test_wrong_expectations_fail() -> bool:
	_expect(_case({"actions_used": 9}), false, "expected actions_used = 9, got 10", "wrong count")
	_expect(_case({"won": false}), false, "expected won = false", "wrong won")
	_expect(_case({"failed": true}), false, "expected failed = true", "wrong failed")
	_expect(_case({"rejected_at": 0, "reason": "blocked_object"}, ["burn:up"]), false,
		"expected reason \"blocked_object\", got \"nothing_to_burn\"", "wrong reason")
	_expect(_case({"rejected_at": 1, "reason": "nothing_to_burn"}, ["burn:up", "wait"]), false,
		"expected a rejection at action 1, got one at action 0", "wrong index")
	_expect(_case({"rejected_at": 3}), false, "every action was valid", "no rejection happened")
	_expect(_case({"won": true}, ["move:left"]), false, "action 0 (move:left) was rejected: out_of_bounds", "unexpected rejection")
	return true


func test_rejected_at_is_zero_based() -> bool:
	_expect(_case({"rejected_at": 2, "reason": "nothing_to_burn"}, ["wait", "wait", "burn:up"]), true, "", "third action is index 2")
	return true


func test_missing_level_fails() -> bool:
	_expect(_case({"won": true}, L01_SOLUTION, "NO_SUCH_LEVEL"), false, "level \"NO_SUCH_LEVEL\" not found", "missing level")
	_expect(_case({"won": true}, L01_SOLUTION, "../fixtures/L01_first_crate"), false, "not found", "no path tricks")
	return true


## Must not depend on what Mariam puts in levels/data/ or tests/cases/.
func test_level_lookup_order() -> bool:
	# T01_wall exists only in tests/fixtures/, so the default lookup falls back to it.
	check_eq(CaseRunner.resolve_level("T01_wall"), "res://tests/fixtures/T01_wall.json", "falls back to tests/fixtures")
	# levels/data/ wins over tests/fixtures/, but only check it when such a level exists.
	if FileAccess.file_exists("res://levels/data/L01_first_crate.json"):
		check_eq(CaseRunner.resolve_level("L01_first_crate"), "res://levels/data/L01_first_crate.json", "levels/data wins")
	# Explicit folder lists: independent of the shared folders.
	check_eq(CaseRunner.resolve_level("L01_first_crate", ["res://tests/", "res://tests/fixtures/"]),
		"res://tests/fixtures/L01_first_crate.json", "skips folders without the file")
	check_eq(CaseRunner.resolve_level("L01_first_crate", ["res://tests/"]), "", "not found")
	return true


func test_malformed_case_file_fails() -> bool:
	var results := CaseRunner.run_json_string("[{ \"name\": \"x\", ", "broken.json")
	check_eq(results.size(), 1, "one result")
	check_eq(results[0]["ok"], false, "fails")
	check("invalid JSON" in results[0]["message"], "message: " + results[0]["message"])
	for text in ["42", "\"hi\"", "[]"]:
		var r := CaseRunner.run_json_string(text, "odd.json")
		check(r.size() == 1 and not r[0]["ok"], "%s fails" % text)
	var missing := CaseRunner.run_file("res://tests/fixtures/no_such_cases.json")
	check(not missing[0]["ok"] and "cannot open file" in missing[0]["message"], "missing file fails")
	return true


func test_malformed_cases_fail() -> bool:
	_expect("just a string", false, "case must be an object", "case not an object")
	_expect({"name": "c", "actions": [], "expect": {}}, false, "\"level\" must be", "no level")
	_expect({"name": "c", "level": "L01_first_crate", "actions": "move:right", "expect": {}}, false, "\"actions\" must be a list", "actions not a list")
	_expect({"name": "c", "level": "L01_first_crate", "actions": []}, false, "\"expect\" must be an object", "no expect")
	_expect(_case({"win": true}), false, "unknown expect key \"win\"", "typo in expect")
	_expect(_case({"won": "yes"}), false, "expect.won must be true or false", "won not a bool")
	_expect(_case({"rejected_at": 0.5}), false, "expect.rejected_at must be a whole number", "fractional index")
	_expect(_case({"reason": "x"}), false, "expect.reason needs expect.rejected_at", "reason alone")
	_expect(_case({"won": true}, ["move:north"]), false, "actions[0]: bad action \"move:north\"", "bad direction")
	_expect(_case({"won": true}, ["fly"]), false, "actions[0]: bad action", "bad action")
	return true


func test_single_object_and_list_files() -> bool:
	var one := JSON.stringify(_case({"won": true}))
	check_eq(CaseRunner.run_json_string(one, "one.json").map(func(r): return r["ok"]), [true], "single object")
	var two := JSON.stringify([_case({"won": true}), _case({"actions_used": 1})])
	check_eq(CaseRunner.run_json_string(two, "two.json").map(func(r): return r["ok"]), [true, false], "list of two")
	return true


func test_parse_action() -> bool:
	check_eq(CaseRunner.parse_action("move:up"), {"type": "move", "dir": "up"}, "move")
	check_eq(CaseRunner.parse_action("burn:left"), {"type": "burn", "dir": "left"}, "burn")
	check_eq(CaseRunner.parse_action("interact"), {"type": "interact"}, "interact")
	check_eq(CaseRunner.parse_action("wait"), {"type": "wait"}, "wait")
	for bad in ["move", "wait:up", "move:up:down", "jump:up", 3, null]:
		check(CaseRunner.parse_action(bad) == null, "%s is not an action" % str(bad))
	return true


func test_json_files_in() -> bool:
	var files := CaseRunner.json_files_in("res://tests/fixtures")
	check(files.has("res://tests/fixtures/sample_cases.json"), "finds sample_cases.json (got %s)" % str(files))
	check(files.has("res://tests/fixtures/L01_first_crate.json"), "finds L01")
	var sorted := files.duplicate()
	sorted.sort()
	check_eq(files, sorted, "sorted")
	check(files.all(func(f): return f.ends_with(".json")), "only .json files")
	check_eq(CaseRunner.json_files_in("res://no_such_folder"), [], "missing folder gives []")
	return true


func test_sample_file_passes() -> bool:
	var results := CaseRunner.run_file("res://tests/fixtures/sample_cases.json")
	check_eq(results.size(), 4, "four sample cases")
	for r in results:
		check(r["ok"], "%s: %s" % [r["name"], r["message"]])
	return true
