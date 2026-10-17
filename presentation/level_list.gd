extends RefCounted
## The playable levels: every *.json in levels/data/, in sorted filename
## order (so L01, L02, ... play in order). Read-only: never writes the folder.
## Each entry is { "id": <filename without .json>, "path": <res:// path> }.
## Works with any number of levels, including none.
##
## Note for the export (Phase 3): *.json must be in the export filter, or the
## folder will look empty in the built game.

const DEFAULT_DIR := "res://levels/data"


static func all(dir: String = DEFAULT_DIR) -> Array:
	var entries: Array = []
	var access := DirAccess.open(dir)
	if access == null:
		return entries
	var files := Array(access.get_files()).filter(func(f): return f.get_extension() == "json")
	files.sort()
	for file in files:
		entries.append({"id": file.get_basename(), "path": dir.path_join(file)})
	return entries


static func first(dir: String = DEFAULT_DIR) -> Variant:
	var entries := all(dir)
	return null if entries.is_empty() else entries[0]


## Position of a level id in all(), or -1.
static func index_of(id: String, dir: String = DEFAULT_DIR) -> int:
	var entries := all(dir)
	for i in entries.size():
		if entries[i]["id"] == id:
			return i
	return -1


## The level after `id`, or null on the last level (or an unknown id).
static func next_of(id: String, dir: String = DEFAULT_DIR) -> Variant:
	var entries := all(dir)
	var i := index_of(id, dir)
	return null if i < 0 or i + 1 >= entries.size() else entries[i + 1]


## The level before `id`, or null on the first level (or an unknown id).
static func previous_of(id: String, dir: String = DEFAULT_DIR) -> Variant:
	var entries := all(dir)
	var i := index_of(id, dir)
	return null if i <= 0 else entries[i - 1]
