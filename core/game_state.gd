class_name GameState
extends RefCounted
## Plain data for one moment of a level (PROJECT_CONTEXT.md section 3).
## No Nodes, graphics, audio or UI. The rules live in turn_manager.gd and friends;
## this file only holds the data, copies it and hashes it.

## Sun order. An hour's order index is its position in this list.
const HOUR_ORDER := [12, 2, 4, 6, 8, 10]

const FLOOR := "."
const WALL := "#"
const CHASM := "~"

const INTACT := "INTACT"
const ASH := "ASH"
const GONE := "GONE"  # reserved and unused; behaves like an empty slot

const DEFAULT_GRID_SIZE := 5
const DEFAULT_ACTIONS_PER_HOUR := 3

# --- Level settings (fixed during play) ---
var level_id: String = ""
var grid_w: int = DEFAULT_GRID_SIZE
var grid_h: int = DEFAULT_GRID_SIZE
var sun_start_index: int = 0
var actions_per_hour: int = DEFAULT_ACTIONS_PER_HOUR
## hour (int) -> Array of grid_h Strings, grid_w characters each (row = y, char = x).
## Every hour has an entry; unlisted rooms are all floor.
var terrain: Dictionary = {}

# --- Dynamic state ---
## id -> { "id", "type", "hour", "slot": Vector2i, "state", "flammable",
##         optional "ash_link": { "hour", "slot": Vector2i, "becomes" },
##         optional "links_to": { "hour", "slot": Vector2i } }
var objects: Dictionary = {}
## id -> { "id", "hour", "slot": Vector2i }
## Dormant vs active is derived from the sun, so it is not stored.
## A destroyed shadow is removed from this dictionary.
var shadows: Dictionary = {}
var player_hour: int = 12
var player_slot: Vector2i = Vector2i.ZERO
var action_count: int = 0
var won: bool = false
var failed: bool = false
var fail_reason: String = ""


func _init(w: int = DEFAULT_GRID_SIZE, h: int = DEFAULT_GRID_SIZE) -> void:
	grid_w = w
	grid_h = h
	reset_terrain()


static func order_index(hour: int) -> int:
	return HOUR_ORDER.find(hour)


## Sets every hour to all floor at the current grid size.
func reset_terrain() -> void:
	terrain = {}
	var row := FLOOR.repeat(grid_w)
	for hour in HOUR_ORDER:
		var rows: Array = []
		for y in grid_h:
			rows.append(row)
		terrain[hour] = rows


func in_grid(slot: Vector2i) -> bool:
	return slot.x >= 0 and slot.y >= 0 and slot.x < grid_w and slot.y < grid_h


## Terrain character at a slot, or "" if the slot or hour does not exist.
func terrain_at(hour: int, slot: Vector2i) -> String:
	if not in_grid(slot) or not terrain.has(hour):
		return ""
	return terrain[hour][slot.y][slot.x]


## The object at a slot, or {} if none. GONE objects count as empty.
func object_at(hour: int, slot: Vector2i) -> Dictionary:
	for obj in objects.values():
		if obj["hour"] == hour and obj["slot"] == slot and obj["state"] != GONE:
			return obj
	return {}


## The shadow at a slot (dormant or active), or {} if none.
func shadow_at(hour: int, slot: Vector2i) -> Dictionary:
	for sh in shadows.values():
		if sh["hour"] == hour and sh["slot"] == slot:
			return sh
	return {}


## A fully independent copy: nothing is shared with the original.
func duplicate_deep() -> GameState:
	# get_script() instead of GameState.new(): headless runs on a fresh clone
	# have no global class cache, so the class_name is not known yet.
	var copy: GameState = get_script().new(grid_w, grid_h)
	copy.level_id = level_id
	copy.sun_start_index = sun_start_index
	copy.actions_per_hour = actions_per_hour
	copy.terrain = terrain.duplicate(true)
	copy.objects = objects.duplicate(true)
	copy.shadows = shadows.duplicate(true)
	copy.player_hour = player_hour
	copy.player_slot = player_slot
	copy.action_count = action_count
	copy.won = won
	copy.failed = failed
	copy.fail_reason = fail_reason
	return copy


## Canonical string of the full state. Equal states give equal keys regardless
## of the order objects or shadows were added. Used by the solver and tests.
func hash_key() -> String:
	var parts := PackedStringArray()
	parts.append("L=%s" % level_id)
	parts.append("G=%dx%d" % [grid_w, grid_h])
	parts.append("U=%d/%d" % [sun_start_index, actions_per_hour])
	for hour in HOUR_ORDER:
		parts.append("T%d=%s" % [hour, "/".join(PackedStringArray(terrain[hour]))])
	parts.append("P=%d@%s" % [player_hour, _slot_key(player_slot)])
	parts.append("N=%d" % action_count)
	parts.append("E=%d%d%s" % [int(won), int(failed), fail_reason])
	var ids := objects.keys()
	ids.sort()
	for id in ids:
		parts.append("O=" + _object_key(objects[id]))
	ids = shadows.keys()
	ids.sort()
	for id in ids:
		var sh: Dictionary = shadows[id]
		parts.append("S=%s@%d:%s" % [sh["id"], sh["hour"], _slot_key(sh["slot"])])
	return "|".join(parts)


static func _slot_key(slot: Vector2i) -> String:
	return "%d,%d" % [slot.x, slot.y]


static func _object_key(obj: Dictionary) -> String:
	var key := "%s:%s@%d:%s:%s:%d" % [
		obj["id"], obj["type"], obj["hour"], _slot_key(obj["slot"]),
		obj["state"], int(obj["flammable"])]
	if obj.has("ash_link"):
		var link: Dictionary = obj["ash_link"]
		key += ":A>%d:%s:%s" % [link["hour"], _slot_key(link["slot"]), link["becomes"]]
	if obj.has("links_to"):
		var to: Dictionary = obj["links_to"]
		key += ":S>%d:%s" % [to["hour"], _slot_key(to["slot"])]
	return key
