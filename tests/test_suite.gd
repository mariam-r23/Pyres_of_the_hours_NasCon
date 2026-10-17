extends RefCounted
## Base class for test suites. run_tests.gd calls every method named "test_*".
##
## Every test method must be declared "-> bool" and end with "return true".
## GDScript has no try/catch: a script error aborts the test method, which then
## returns null, and the runner reports that as a FAIL instead of a silent PASS.
##
## Load scripts under test with preload(), not their class_name: headless runs
## on a fresh clone have no global class cache.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
