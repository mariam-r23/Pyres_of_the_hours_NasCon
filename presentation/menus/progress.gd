extends RefCounted
## Player progress: which levels are unlocked and the best action count per
## level, saved to user://progress.json. Pure helpers (no Nodes) so they are
## testable without a window. A missing or corrupt file means fresh progress,
## never a crash. Progress is written only when a level is won.
##
## Shape: { "unlocked": [level ids], "best": { level id: actions } }
## The first level is always unlocked; winning a level unlocks the next one.

const PATH := "user://progress.json"


## Fresh progress: only the first level is unlocked, no best scores.
static func fresh(level_ids: Array) -> Dictionary:
	return {"unlocked": level_ids.slice(0, 1), "best": {}}


## Reads progress from `path`. Missing, unreadable or malformed data gives
## fresh progress; unknown ids and bad numbers are dropped.
static func load_from(path: String, level_ids: Array) -> Dictionary:
	if not FileAccess.file_exists(path):
		return fresh(level_ids)
	var json := JSON.new()  # parse() reports errors quietly; parse_string() logs them
	if json.parse(FileAccess.get_file_as_string(path)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return fresh(level_ids)
	return merge(fresh(level_ids), sanitize(json.data, level_ids))


## Keeps only well-formed entries for known levels.
static func sanitize(data: Dictionary, level_ids: Array) -> Dictionary:
	var clean := {"unlocked": [], "best": {}}
	var unlocked = data.get("unlocked", [])
	if typeof(unlocked) == TYPE_ARRAY:
		for id in unlocked:
			if typeof(id) == TYPE_STRING and level_ids.has(id) and not clean["unlocked"].has(id):
				clean["unlocked"].append(id)
	var best = data.get("best", {})
	if typeof(best) == TYPE_DICTIONARY:
		for id in best:
			var n = best[id]
			if level_ids.has(id) and (typeof(n) == TYPE_INT or typeof(n) == TYPE_FLOAT) and n >= 1 and n == floorf(n):
				clean["best"][id] = int(n)
	return clean


## Writes progress. Returns false if the file cannot be written.
static func save_to(path: String, progress: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(progress, "  "))
	file.close()
	return true


## Combines two progress records: union of unlocked levels (in `a`'s order,
## then `b`'s), and the lower (better) best count for each level.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var unlocked: Array = a["unlocked"].duplicate()
	for id in b["unlocked"]:
		if not unlocked.has(id):
			unlocked.append(id)
	var best: Dictionary = a["best"].duplicate()
	for id in b["best"]:
		best[id] = mini(best[id], b["best"][id]) if best.has(id) else b["best"][id]
	return {"unlocked": unlocked, "best": best}


## Progress after winning `level_id` in `actions`: its best only improves,
## and the next level in `level_ids` unlocks.
static func record_win(progress: Dictionary, level_id: String, actions: int, level_ids: Array) -> Dictionary:
	var won := {"unlocked": [level_id], "best": {level_id: actions}}
	var i := level_ids.find(level_id)
	if i >= 0 and i + 1 < level_ids.size():
		won["unlocked"].append(level_ids[i + 1])
	return merge(progress, won)


static func is_unlocked(progress: Dictionary, level_id: String) -> bool:
	return progress["unlocked"].has(level_id)


## Best action count, or -1 if the level was never won.
static func best_of(progress: Dictionary, level_id: String) -> int:
	return progress["best"].get(level_id, -1)


## True if there is anything to continue (a win, or more than one level open).
static func has_progress(progress: Dictionary) -> bool:
	return not progress["best"].is_empty() or progress["unlocked"].size() > 1


## The level Continue starts: the last unlocked level in play order.
static func continue_level(progress: Dictionary, level_ids: Array) -> String:
	var last := ""
	for id in level_ids:
		if is_unlocked(progress, id):
			last = id
	return last
