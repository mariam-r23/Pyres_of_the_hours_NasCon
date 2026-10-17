extends RefCounted
## Runs shared JSON test cases (PROJECT_CONTEXT.md 6.4 and clarification 10).
##
## A case file holds one case object or a LIST of them:
##   { "name": "...", "level": "<level id>",
##     "actions": ["move:right", "burn:up", "interact", "wait", ...],
##     "expect": { "won": bool, "failed": bool, "actions_used": int,
##                 "rejected_at": int (0-based index into actions), "reason": str } }
## The level id is looked up in LEVEL_DIRS, in order.
## Actions run in order and stop at the first rejection. A rejection that is
## not expected fails the case. won / failed / actions_used are checked on the
## state reached. Unknown expect keys fail the case, so typos are caught.
##
## Every run_* function returns an Array of { name, ok, message }; a file or
## case that cannot be read or loaded is a failed result, never a crash.

const Loader := preload("res://core/level_loader.gd")
const TurnManager := preload("res://core/turn_manager.gd")

const LEVEL_DIRS := ["res://levels/data/", "res://tests/cases/fixtures/", "res://tests/fixtures/"]
const EXPECT_KEYS := ["won", "failed", "actions_used", "rejected_at", "reason"]
const DIRECTIONS := ["up", "down", "left", "right"]


static func run_file(path: String, level_dirs: Array = LEVEL_DIRS) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return [_result(path.get_file(), false, "cannot open file (%s)" % error_string(FileAccess.get_open_error()))]
	return run_json_string(file.get_as_text(), path.get_file(), level_dirs)


static func run_json_string(text: String, source: String, level_dirs: Array = LEVEL_DIRS) -> Array:
	var json := JSON.new()
	if json.parse(text) != OK:
		return [_result(source, false, "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])]
	var cases = json.data
	if typeof(cases) == TYPE_DICTIONARY:
		cases = [cases]
	if typeof(cases) != TYPE_ARRAY:
		return [_result(source, false, "expected a case object or a list of cases")]
	if cases.is_empty():
		return [_result(source, false, "file contains no cases")]
	var results: Array = []
	for i in cases.size():
		results.append(run_case(cases[i], "%s[%d]" % [source, i], level_dirs))
	return results


static func run_case(case: Variant, fallback_name: String, level_dirs: Array = LEVEL_DIRS) -> Dictionary:
	if typeof(case) != TYPE_DICTIONARY:
		return _result(fallback_name, false, "case must be an object")
	var name: String = case["name"] if typeof(case.get("name")) == TYPE_STRING else fallback_name

	# --- format ---
	if typeof(case.get("level")) != TYPE_STRING:
		return _result(name, false, "\"level\" must be a level id string")
	if typeof(case.get("actions")) != TYPE_ARRAY:
		return _result(name, false, "\"actions\" must be a list")
	if typeof(case.get("expect")) != TYPE_DICTIONARY:
		return _result(name, false, "\"expect\" must be an object")
	var expect: Dictionary = case["expect"]
	for key in expect:
		if not EXPECT_KEYS.has(key):
			return _result(name, false, "unknown expect key \"%s\" (known: %s)" % [key, ", ".join(EXPECT_KEYS)])
	for key in ["won", "failed"]:
		if expect.has(key) and typeof(expect[key]) != TYPE_BOOL:
			return _result(name, false, "expect.%s must be true or false" % key)
	for key in ["actions_used", "rejected_at"]:
		if expect.has(key) and not _is_whole_number(expect[key]):
			return _result(name, false, "expect.%s must be a whole number" % key)
	if expect.has("reason") and typeof(expect["reason"]) != TYPE_STRING:
		return _result(name, false, "expect.reason must be a string")
	if expect.has("reason") and not expect.has("rejected_at"):
		return _result(name, false, "expect.reason needs expect.rejected_at")
	var actions: Array = []
	for i in case["actions"].size():
		var action = parse_action(case["actions"][i])
		if action == null:
			return _result(name, false, "actions[%d]: bad action %s (use move:<dir>, burn:<dir>, interact, wait)" % [i, JSON.stringify(case["actions"][i])])
		actions.append(action)

	# --- level ---
	var level_id: String = case["level"]
	var path := resolve_level(level_id, level_dirs)
	if path == "":
		return _result(name, false, "level \"%s\" not found in %s" % [level_id, ", ".join(level_dirs)])
	var loaded := Loader.load_file(path)
	if loaded["state"] == null:
		return _result(name, false, "level \"%s\" (%s) does not load: %s" % [level_id, path, loaded["error"].replace("\n", "; ")])

	# --- run ---
	var state = loaded["state"]
	var rejected_at := -1
	var reason := ""
	for i in actions.size():
		var result := TurnManager.apply_action(state, actions[i])
		if not result["ok"]:
			rejected_at = i
			reason = result["reason"]
			break
		state = result["state"]

	# --- check ---
	var problems: PackedStringArray = []
	if expect.has("rejected_at"):
		var want := int(expect["rejected_at"])
		if rejected_at == -1:
			problems.append("expected a rejection at action %d, but every action was valid" % want)
		elif rejected_at != want:
			problems.append("expected a rejection at action %d, got one at action %d (%s: %s)" % [
				want, rejected_at, case["actions"][rejected_at], reason])
		if expect.has("reason") and rejected_at != -1 and reason != expect["reason"]:
			problems.append("expected reason \"%s\", got \"%s\"" % [expect["reason"], reason])
	elif rejected_at != -1:
		problems.append("action %d (%s) was rejected: %s" % [rejected_at, case["actions"][rejected_at], reason])
	if expect.has("won") and (state.status == "won") != expect["won"]:
		problems.append("expected won = %s, status is \"%s\"" % [str(expect["won"]), state.status])
	if expect.has("failed") and (state.status == "failed") != expect["failed"]:
		problems.append("expected failed = %s, status is \"%s\"" % [str(expect["failed"]), state.status])
	if expect.has("actions_used") and state.action_count != int(expect["actions_used"]):
		problems.append("expected actions_used = %d, got %d" % [int(expect["actions_used"]), state.action_count])
	if not problems.is_empty():
		return _result(name, false, "; ".join(problems))
	return _result(name, true, "")


## "move:right" -> {"type": "move", "dir": "right"}; null if not valid shorthand.
static func parse_action(short: Variant) -> Variant:
	if typeof(short) != TYPE_STRING:
		return null
	if short == "interact" or short == "wait":
		return {"type": short}
	var parts: PackedStringArray = short.split(":")
	if parts.size() == 2 and (parts[0] == "move" or parts[0] == "burn") and DIRECTIONS.has(parts[1]):
		return {"type": parts[0], "dir": parts[1]}
	return null


## The first <dir><id>.json that exists, or "".
static func resolve_level(level_id: String, level_dirs: Array = LEVEL_DIRS) -> String:
	if level_id == "" or "/" in level_id or "\\" in level_id or ".." in level_id:
		return ""
	for dir in level_dirs:
		var path: String = dir + level_id + ".json"
		if FileAccess.file_exists(path):
			return path
	return ""


## Every *.json directly in `dir`, sorted; [] if the folder is missing.
static func json_files_in(dir: String) -> Array:
	var files: Array = []
	var access := DirAccess.open(dir)
	if access == null:
		return files
	for file in access.get_files():
		if file.get_extension() == "json":
			files.append(dir.path_join(file))
	files.sort()
	return files


static func _is_whole_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and v == floorf(v))


static func _result(name: String, ok: bool, message: String) -> Dictionary:
	return {"name": name, "ok": ok, "message": message}
