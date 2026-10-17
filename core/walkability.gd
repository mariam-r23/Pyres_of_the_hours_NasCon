extends RefCounted
## Can the player stand on a slot? Terrain (PROJECT_CONTEXT.md 3.1) plus the
## object type table (3.2). No Nodes, graphics, audio or UI.
##
## SHADOWS ARE NOT HANDLED HERE. Whether a shadow blocks depends on the sun
## (dormant vs active, step 7), so the turn manager must check active shadows
## separately and reject with "shadow_blocks". A slot this file calls walkable
## can still be blocked by an active shadow.
##
## Rules:
##   floor  walkable
##   wall   never walkable
##   chasm  walkable only with an INTACT bridge or an ash_path on it;
##          a bridge in ASH (or GONE) leaves the bare chasm, which blocks again
##   crate, door   block while INTACT, walkable once ASH
##   stair, exit, ash_path, bridge   walkable
##   GONE objects count as an empty slot

const GameStateScript := preload("res://core/game_state.gd")

## Types that make a chasm tile passable (while not burned).
const CHASM_FILLERS := ["bridge", "ash_path"]
## Types that block their tile while INTACT.
const BLOCKING_TYPES := ["crate", "door"]

const REASON_OUT_OF_BOUNDS := "out_of_bounds"
const REASON_BLOCKED_TERRAIN := "blocked_terrain"
const REASON_BLOCKED_OBJECT := "blocked_object"


## Returns { "ok": bool, "reason": String }. reason is "" when ok, otherwise
## the first blocking cause: out_of_bounds, blocked_terrain or blocked_object.
static func check_walkable(state: GameStateScript, hour: int, slot: Vector2i) -> Dictionary:
	if GameStateScript.order_index(hour) < 0 or not state.in_grid(slot):
		return _blocked(REASON_OUT_OF_BOUNDS)
	var tile := state.terrain_at(hour, slot)
	var obj := state.object_at(hour, slot)  # {} for an empty slot or a GONE object
	if tile == GameStateScript.WALL:
		return _blocked(REASON_BLOCKED_TERRAIN)
	if tile == GameStateScript.CHASM and not fills_chasm(obj):
		return _blocked(REASON_BLOCKED_TERRAIN)
	if blocks(obj):
		return _blocked(REASON_BLOCKED_OBJECT)
	return {"ok": true, "reason": ""}


static func is_walkable(state: GameStateScript, hour: int, slot: Vector2i) -> bool:
	return check_walkable(state, hour, slot)["ok"]


## True if this object makes a chasm passable: an INTACT bridge, or an ash_path.
static func fills_chasm(obj: Dictionary) -> bool:
	if obj.is_empty() or obj["state"] == GameStateScript.GONE:
		return false
	if obj["type"] == "bridge":
		return obj["state"] == GameStateScript.INTACT
	return obj["type"] == "ash_path"


## True if this object blocks its tile: an INTACT crate or door.
static func blocks(obj: Dictionary) -> bool:
	if obj.is_empty():
		return false
	return BLOCKING_TYPES.has(obj["type"]) and obj["state"] == GameStateScript.INTACT


static func _blocked(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
