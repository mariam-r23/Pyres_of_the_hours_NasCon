extends Node3D
## Draws ONE room (one hour) from a GameState: terrain, objects, shadows and
## the player, as placeholder boxes. Holds no game rules: walkability and
## shadow activity come from core/.
##
## Positions: if this node has a child "Slots" with Marker3D children named
## slot_<x>_<y> (Noor's room scenes, PROJECT_CONTEXT.md 6.5), those are used.
## Otherwise 1 unit per cell, room centered on this node's origin, x to the
## right and grid y toward +Z.

const GameStateScript := preload("res://core/game_state.gd")
const Sun := preload("res://core/sun.gd")
const PaintedFloor := preload("res://presentation/painted_floor.gd")
const ShadowFigure := preload("res://presentation/shadow_figure.gd")

## ALL colors live here so Noor can restyle in one place.
## Color rule: the world is cold (slate blue, ash gray). Only fire effects
## (keys starting with "fire") may be strongly saturated orange, and the
## small ones (specks, cracks) stay tiny and subtle. Shadow tips are dim,
## deep red-orange (low brightness), never a bright saturated orange.
const COLORS := {
	"floor": Color(0.19, 0.22, 0.27),        # slate
	"floor_grid": Color(0.78, 0.86, 0.95, 0.2), # faint cold lines over the painted floor
	"wall": Color(0.36, 0.38, 0.42),         # ash gray stone
	"chasm": Color(0.04, 0.05, 0.07),        # near-black pit
	"bridge": Color(0.33, 0.36, 0.40),       # cold weathered planks
	"ash_path": Color(0.47, 0.46, 0.45),     # ash-grey path with glowing cracks
	"crate": Color(0.56, 0.59, 0.64),
	"door": Color(0.28, 0.36, 0.50),         # blue-steel gate (stands out from walls)
	"stair": Color(0.55, 0.60, 0.66),        # pale cold steel
	"exit": Color(0.70, 0.82, 0.90),         # pale cold light
	"exit_glow": Color(0.35, 0.50, 0.60),
	"exit_halo": Color(0.85, 0.93, 1.00, 0.35), # pale halo around the exit
	"stair_marker": Color(0.55, 0.85, 0.95, 0.55), # cold-light column over a stair
	"burnable_edge": Color(1.00, 0.93, 0.82, 0.55), # faint warm-white edge: "this burns"
	"ash": Color(0.38, 0.37, 0.37),          # burned remains: light charcoal mound
	"shadow_body": Color(0.03, 0.03, 0.04),
	"shadow_tip": Color(0.38, 0.11, 0.06),   # deep red-orange embers (eyes), dimmer than fire
	"shadow_rim": Color(0.62, 0.72, 0.88),   # faint cold rim, so a shadow reads on the painted floor
	"shadow_pool": Color(0.01, 0.01, 0.02),  # the dark smoke pool under a shadow
	"player": Color(0.10, 0.11, 0.13),
	"player_ring": Color(0.75, 0.85, 0.95),  # pale ring at the player's feet
	"player_lantern": Color(1.0, 0.94, 0.84), # pale warm-white light over the player (never a shadow)
	"active_room": Color(0.32, 0.38, 0.48),  # rim under the room the player is in
	"sun_marker": Color(0.80, 0.86, 0.92),   # cold pale dial hand
	"dial": Color(0.20, 0.22, 0.26),         # dark steel
	"fire": Color(1.00, 0.45, 0.05),         # THE warm accent. Only fire.
	"fire_speck": Color(1.00, 0.50, 0.15),   # tiny embers left in burned remains
	"fire_crack": Color(1.00, 0.42, 0.10),   # thin glowing cracks in an ash path
	"fire_streak": Color(1.00, 0.60, 0.18),  # hot core of the spirit's flying streak
	"fire_trail": Color(1.00, 0.40, 0.06),   # the ember trail behind the streak
}

## Emission strength for fire details, shadow tips and markers.
const SPECK_ENERGY := 1.4
const CRACK_ENERGY := 0.9
const EXIT_GLOW_ENERGY := 1.6
const MARKER_ENERGY := 1.0
const BURNABLE_EDGE_ENERGY := 0.6
## How far the burnable edge sticks out past the object on each side.
const BURNABLE_EDGE_MARGIN := 0.12
const STAIR_COLUMN_HEIGHT := 1.4
## Walls are kept low so they do not hide what stands behind them.
const WALL_HEIGHT := 0.6

const CELL := 1.0

## Pop-in for an object revealed after the ripple shot lands.
const POP_TIME := 0.28
const POP_START_SCALE := 0.25

## Burned remains: a low mound (radius, height) with ember specks.
const MOUND_RADIUS := 0.47
const MOUND_HEIGHT := 0.28
## How high the player stands on top of a stair or a mound of remains.
const STAIR_STAND_HEIGHT := 0.3
const MOUND_STAND_HEIGHT := 0.12
## Fixed speck spots (x, z) near the mound edge, so they peek out around a
## player standing on the remains. Fixed, not random: same look every time.
const SPECK_SPOTS := [Vector2(0.37, 0.1), Vector2(-0.31, -0.22), Vector2(0.06, 0.38),
	Vector2(-0.37, 0.14), Vector2(0.22, -0.33)]
## Player ring radii (inner, outer): normal, and tighter on a mound of remains
## so the remains stay visible around the player's feet.
const RING_RADII := Vector2(0.3, 0.4)
const RING_RADII_ON_MOUND := Vector2(0.26, 0.31)
## The player's lantern: a small glowing orb over the head and the light it casts.
const LANTERN_HEIGHT := 1.15
const LANTERN_RADIUS := 0.09
const LANTERN_ENERGY := 3.0
const LANTERN_LIGHT_ENERGY := 1.2
const LANTERN_LIGHT_RANGE := 2.2
## Ash path cracks: (x, z, angle in degrees, length).
const CRACKS := [Vector4(-0.12, -0.1, 25, 0.55), Vector4(0.14, 0.12, -40, 0.5), Vector4(0.0, 0.25, 80, 0.3)]

## Passed-hour grade: ALL values here, so Noor's assets can replace them in
## one place. Rooms the sun has passed get darker and sootier with each hour
## since ("depth"); the room the sun is on now is slightly brighter. Shadows,
## the player and the active-room rim are never graded (always readable).
const GRADE := {
	"current_brightness": 1.12,      # the "now" room
	"passed_brightness_step": 0.09,  # darker per hour since it passed
	"passed_brightness_min": 0.62,   # never darker than this: still playable
	"passed_emission_step": 0.15,    # glow (markers, embers) fades per hour
	"passed_emission_min": 0.4,
	"soot_per_depth": 3,             # soot specks added per hour since
	"soot_max": 12,
	"soot_color": Color(0.03, 0.03, 0.035, 0.8),
	"soot_size_min": 0.14,
	"soot_size_max": 0.32,
	"transition_time": 0.4,          # tween to the new grade on hour_passed
}

## Shadow animations.
const SHADOW_RISE_TIME := 0.3
const SHADOW_RISE_START := Vector3(0.6, 0.05, 0.6)

var grid_w := GameStateScript.DEFAULT_GRID_SIZE
var grid_h := GameStateScript.DEFAULT_GRID_SIZE

var _content: Node3D = null
var _fx_root: Node3D = null      # ghosts that outlive a redraw (dissipating shadows)
var _materials := {}
## material -> {"color", "energy", "graded"}: the ungraded values.
var _material_base := {}
## slot (Vector2i) -> the pivot node holding that slot's object meshes.
var _object_nodes := {}
## shadow id -> pivot node / slot, from the last redraw.
var _shadow_nodes := {}
var _shadow_slots := {}
## The grade currently shown {brightness, emission, soot} and the one aimed at.
var _shown_grade := {}
var _target_grade := {}
var _grade_tween: Tween = null
var _soot_fresh_material: StandardMaterial3D = null
var _soot_count_before := 0
## The painted floor (Noor's hour painting): one material per room, graded with it.
var _floor_material: ShaderMaterial = null
var _floor_hour := -1
var _floor_used := true
var _floor_node: MeshInstance3D = null
var _grid_node: MeshInstance3D = null
var _floor_look_shown := {}


## How the sun has treated this room: passed (and how many hours ago:
## depth 1 = the hour that just passed) or current (the sun is on it now).
## Reads core/sun.gd only.
static func room_mood(state: GameStateScript, hour: int) -> Dictionary:
	var index := GameStateScript.order_index(hour)
	var sun := Sun.sun_index(state)
	var passed := index >= 0 and index < sun
	return {
		"passed": passed,
		"current": index >= 0 and index == sun,
		"depth": sun - index if passed else 0,
	}


## The grade values for a mood: {brightness, emission, soot}.
static func grade_for(mood: Dictionary) -> Dictionary:
	if mood["passed"]:
		var depth: int = mood["depth"]
		return {
			"brightness": maxf(GRADE["passed_brightness_min"], 1.0 - GRADE["passed_brightness_step"] * depth),
			"emission": maxf(GRADE["passed_emission_min"], 1.0 - GRADE["passed_emission_step"] * depth),
			"soot": mini(GRADE["soot_max"], GRADE["soot_per_depth"] * depth),
		}
	if mood["current"]:
		return {"brightness": GRADE["current_brightness"], "emission": 1.0, "soot": 0}
	return {"brightness": 1.0, "emission": 1.0, "soot": 0}


## Deterministic soot spots for a room: [{slot, offset (x, z), size, angle}].
## Seeded from the hour and the speck index (no randf), so the same room
## always gets the same soot.
static func soot_spots(hour: int, count: int, grid: Vector2i) -> Array:
	var spots: Array = []
	for i in count:
		var h := _hash(hour * 7919 + i * 104729 + 17)
		var slot := Vector2i(h % grid.x, (h >> 8) % grid.y)
		var h2 := _hash(h ^ (slot.x * 31 + slot.y * 131))
		spots.append({
			"slot": slot,
			"offset": Vector2(((h2 & 255) / 255.0 - 0.5) * 0.6, (((h2 >> 8) & 255) / 255.0 - 0.5) * 0.6),
			"size": lerpf(GRADE["soot_size_min"], GRADE["soot_size_max"], ((h2 >> 16) & 255) / 255.0),
			"angle": float((h2 >> 24) & 255) / 255.0 * 180.0,
		})
	return spots


## A small integer hash (deterministic, 32-bit).
static func _hash(n: int) -> int:
	var h := (n * 2654435761) & 0xFFFFFFFF
	h ^= h >> 15
	h = (h * 2246822519) & 0xFFFFFFFF
	h ^= h >> 13
	return h & 0x7FFFFFFF


## The grade currently shown (after any running transition step).
func grade_shown() -> Dictionary:
	return _shown_grade.duplicate()


## Look of an object: { "color", "emission" (Color or null), "detail" }.
## detail: "specks" (burned remains: a few ember specks), "cracks" (ash path:
## thin glowing cracks) or "". Unknown types fall back to the crate color.
static func object_style(type: String, state: String) -> Dictionary:
	if state == GameStateScript.ASH:
		return {"color": COLORS["ash"], "emission": null, "detail": "specks"}
	match type:
		"ash_path":
			return {"color": COLORS["ash_path"], "emission": null, "detail": "cracks"}
		"exit":
			return {"color": COLORS["exit"], "emission": COLORS["exit_glow"], "detail": ""}
	return {"color": COLORS.get(type, COLORS["crate"]), "emission": null, "detail": ""}


## Center of a grid slot in this room's local space.
func slot_to_position(slot: Vector2i) -> Vector3:
	var slots := get_node_or_null("Slots")
	if slots != null:
		var marker := slots.get_node_or_null("slot_%d_%d" % [slot.x, slot.y]) as Node3D
		if marker != null:
			return (slots as Node3D).transform * marker.position
	return grid_slot_position(slot, Vector2i(grid_w, grid_h))


## Grid math only (no Slots markers): 1 unit per cell, room centered on its
## origin. Used by slot_to_position and by the ripple camera's shot planning.
static func grid_slot_position(slot: Vector2i, grid_size: Vector2i) -> Vector3:
	return Vector3(
		(slot.x - (grid_size.x - 1) / 2.0) * CELL,
		0.0,
		(slot.y - (grid_size.y - 1) / 2.0) * CELL)


## Full rebuild of this room for `hour` from `state`. Objects on
## `hidden_slots` and shadows in `hidden_shadows` are not drawn (held back
## for the ripple shot / a rise animation); the state itself is untouched.
## `animate_grade`: tween to a changed passed-hour grade instead of snapping.
func refresh(state: GameStateScript, hour: int, hidden_slots: Array = [],
		animate_grade: bool = false, hidden_shadows: Array = []) -> void:
	grid_w = state.grid_w
	grid_h = state.grid_h
	if _content != null:
		remove_child(_content)
		_content.queue_free()
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)
	_object_nodes = {}
	_shadow_nodes = {}
	_shadow_slots = {}

	var target := grade_for(room_mood(state, hour))
	var animate := animate_grade and not _shown_grade.is_empty() and target != _target_grade and is_inside_tree()
	if not animate and _grade_tween != null:
		_grade_tween.kill()
		_grade_tween = null
	_soot_count_before = int(_shown_grade.get("soot", 0)) if animate else int(target["soot"])

	if state.player_hour == hour:
		var rim := Vector3(grid_w + 0.5, 0.05, grid_h + 0.5)
		_mesh_box(rim, Vector3(0, -0.13, 0), _material(COLORS["active_room"], COLORS["active_room"], 0.4, false))
	for y in grid_h:
		for x in grid_w:
			_draw_terrain(state.terrain_at(hour, Vector2i(x, y)), Vector2i(x, y))
	_draw_painted_floor(state, hour)
	for obj in state.objects.values():
		if obj["hour"] == hour and obj["state"] != GameStateScript.GONE and not hidden_slots.has(obj["slot"]):
			_draw_object(obj)
	for sh in state.shadows.values():
		if sh["hour"] == hour and not hidden_shadows.has(sh["id"]):
			_draw_shadow(sh, Sun.is_hour_passed(state, hour))
	if state.player_hour == hour:
		_draw_player(state, hour)
	_draw_soot(state, hour, int(target["soot"]))

	if animate:
		_start_grade_tween(target)
	else:
		_target_grade = target
		_shown_grade = target.duplicate()
		_apply_grade(_shown_grade)
		if _soot_fresh_material != null:
			_soot_fresh_material.albedo_color.a = GRADE["soot_color"].a


func _start_grade_tween(target: Dictionary) -> void:
	if _grade_tween != null:
		_grade_tween.kill()
	var from := _shown_grade.duplicate()
	_target_grade = target
	_apply_grade(from)
	if _soot_fresh_material != null:
		_soot_fresh_material.albedo_color.a = 0.0
	_grade_tween = create_tween()
	_grade_tween.tween_method(func(t: float): _blend_grade(from, target, t), 0.0, 1.0, GRADE["transition_time"])


func _blend_grade(from: Dictionary, to: Dictionary, t: float) -> void:
	_shown_grade = {
		"brightness": lerpf(from["brightness"], to["brightness"], t),
		"emission": lerpf(from["emission"], to["emission"], t),
		"soot": to["soot"],
	}
	_apply_grade(_shown_grade)
	if _soot_fresh_material != null:
		_soot_fresh_material.albedo_color.a = GRADE["soot_color"].a * t


## Applies brightness / emission to every graded material of this room.
func _apply_grade(grade: Dictionary) -> void:
	if _floor_material != null:
		_floor_look_shown = PaintedFloor.floor_look(grade, _floor_used)
		_floor_material.set_shader_parameter("brightness", _floor_look_shown["brightness"])
		_floor_material.set_shader_parameter("saturation", _floor_look_shown["saturation"])
	for mat in _material_base:
		if _material_base[mat]["graded"]:
			_apply_grade_to(mat, grade)


## Soot specks on floor tiles; ones beyond the previous count fade in.
func _draw_soot(state: GameStateScript, hour: int, count: int) -> void:
	if count <= 0:
		return
	var soot_mat := _material(GRADE["soot_color"], null, 0.0, false)
	if _soot_fresh_material == null:
		_soot_fresh_material = StandardMaterial3D.new()
		_soot_fresh_material.albedo_color = GRADE["soot_color"]
		_soot_fresh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_soot_fresh_material.roughness = 1.0
	var spots := soot_spots(hour, count, Vector2i(grid_w, grid_h))
	for i in spots.size():
		var spot: Dictionary = spots[i]
		if state.terrain_at(hour, spot["slot"]) != GameStateScript.FLOOR:
			continue
		var quad := PlaneMesh.new()
		quad.size = Vector2(spot["size"], spot["size"] * 0.7)
		var at := slot_to_position(spot["slot"]) + Vector3(spot["offset"].x, 0.004, spot["offset"].y)
		var node := _mesh(quad, at, soot_mat if i < _soot_count_before else _soot_fresh_material)
		node.rotation_degrees.y = spot["angle"]


## The hour's painting on the walkable cells (cover-cropped to the room), and
## faint grid lines over it when the level uses this room.
func _draw_painted_floor(state: GameStateScript, hour: int) -> void:
	if _floor_material == null or _floor_hour != hour:
		_floor_material = PaintedFloor.new_material(hour)
		_floor_hour = hour
	_floor_used = PaintedFloor.room_used(state, hour)
	_floor_node = null
	_grid_node = null
	var tex := PaintedFloor.texture_for(hour)
	if tex == null:
		return  # no painting: the plain floor tiles show
	var grid := Vector2i(grid_w, grid_h)
	var origin := Vector3(-grid_w * CELL / 2.0, 0.0, -grid_h * CELL / 2.0)
	var cells := PaintedFloor.painted_cells(state, hour)
	var floor_mesh := PaintedFloor.floor_mesh(cells, grid, PaintedFloor.cover_uv_rect(tex.get_size(), grid), origin, CELL)
	if floor_mesh != null:
		_floor_node = _mesh(floor_mesh, Vector3.ZERO, _floor_material)
		_floor_node.name = "PaintedFloor"
	if _floor_used:
		var lines := PaintedFloor.grid_mesh(PaintedFloor.grid_edges(cells), origin, CELL)
		if lines != null:
			_grid_node = _mesh(lines, Vector3.ZERO, PaintedFloor.grid_material(COLORS["floor_grid"]))
			_grid_node.name = "FloorGrid"
			_grid_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## The painted floor and its grid from the last refresh (null if none).
func painted_floor() -> MeshInstance3D:
	return _floor_node


func floor_grid() -> MeshInstance3D:
	return _grid_node


## The painted floor's current {brightness, saturation}.
func floor_look_shown() -> Dictionary:
	return _floor_look_shown.duplicate()


func _draw_terrain(tile: String, slot: Vector2i) -> void:
	var pos := slot_to_position(slot)
	if tile == GameStateScript.WALL:
		_box(Vector3(0.98, WALL_HEIGHT, 0.98), pos + Vector3(0, WALL_HEIGHT / 2.0, 0), "wall")
	elif tile == GameStateScript.CHASM:
		_box(Vector3(0.96, 0.1, 0.96), pos + Vector3(0, -0.6, 0), "chasm")
	else:
		_box(Vector3(0.96, 0.1, 0.96), pos + Vector3(0, -0.05, 0), "floor")


## The pivot node of the object drawn on `slot`, or null.
func object_node_at(slot: Vector2i) -> Node3D:
	return _object_nodes.get(slot)


## Pops the object on `slot` in: scale up with a slight overshoot and fade in.
func pop_slot(slot: Vector2i) -> void:
	var pivot := object_node_at(slot)
	if pivot == null or not pivot.is_inside_tree():
		return
	pivot.scale = Vector3.ONE * POP_START_SCALE
	var tween := pivot.create_tween().set_parallel(true)
	tween.tween_property(pivot, "scale", Vector3.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for child in pivot.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			# Own copy, so the fade does not touch the shared material.
			var mat: StandardMaterial3D = child.material_override.duplicate()
			var alpha := mat.albedo_color.a
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.albedo_color.a = 0.0
			child.material_override = mat
			tween.tween_property(mat, "albedo_color:a", alpha, POP_TIME)


## Draws one object under its own pivot node at its slot (so it can pop in).
func _draw_object(obj: Dictionary) -> void:
	var pivot := Node3D.new()
	pivot.position = slot_to_position(obj["slot"])
	_content.add_child(pivot)
	_object_nodes[obj["slot"]] = pivot
	var room_content := _content
	_content = pivot
	_draw_object_meshes(obj)
	_content = room_content


func _draw_object_meshes(obj: Dictionary) -> void:
	var pos := Vector3.ZERO  # relative to the object's pivot
	var style := object_style(obj["type"], obj["state"])
	var burned: bool = obj["state"] == GameStateScript.ASH
	var size: Vector3
	var lift: float
	match obj["type"]:
		"bridge":
			size = Vector3(0.96, 0.08, 0.7)
			lift = 0.04 if not burned else -0.45   # burned planks fall into the gap
		"ash_path":
			size = Vector3(0.9, 0.06, 0.9)
			lift = 0.03
		"crate":
			size = Vector3(0.7, 0.7, 0.7) if not burned else Vector3(0.75, 0.15, 0.75)
			lift = size.y / 2.0
		"door":
			size = Vector3(0.9, 0.8, 0.18) if not burned else Vector3(0.9, 0.1, 0.18)
			lift = size.y / 2.0
		"stair":
			size = Vector3(0.8, 0.3, 0.8)
			lift = 0.15
		"exit":
			size = Vector3(0.8, 0.05, 0.8)
			lift = 0.03
		_:
			size = Vector3(0.5, 0.5, 0.5)
			lift = 0.25
	var energy := EXIT_GLOW_ENERGY if style["emission"] != null else 0.0
	var material := _material(style["color"], style["emission"], energy)
	if burned and obj["type"] in ["crate", "door"]:
		# Remains: a low mound (a door leaves a long, thin one).
		var depth := 0.45 if obj["type"] == "door" else 1.0
		_draw_mound(pos, depth, material)
		_draw_specks(pos, depth)
		size = Vector3(MOUND_RADIUS * 2.0, MOUND_HEIGHT, MOUND_RADIUS * 2.0)
		lift = MOUND_HEIGHT / 2.0
	else:
		_mesh_box(size, pos + Vector3(0, lift, 0), material)
		if style["detail"] == "specks":   # e.g. a burned bridge in the gap
			for spot in SPECK_SPOTS.slice(0, 3):
				_speck(pos + Vector3(spot.x, lift + size.y / 2.0, spot.y * 0.6))
		elif style["detail"] == "cracks":
			_draw_cracks(pos + Vector3(0, lift + size.y / 2.0 + 0.004, 0))

	var base_y := lift - size.y / 2.0
	# Burnable (flammable and INTACT): a faint warm-white edge around the base.
	if obj["flammable"] and obj["state"] == GameStateScript.INTACT:
		var edge := Vector3(size.x + 2.0 * BURNABLE_EDGE_MARGIN, 0.02, size.z + 2.0 * BURNABLE_EDGE_MARGIN)
		_mesh_box(edge, pos + Vector3(0, base_y + 0.005, 0),
			_material(COLORS["burnable_edge"], COLORS["burnable_edge"], BURNABLE_EDGE_ENERGY))
	match obj["type"]:
		"stair":
			# A thin column of cold light, so a stair reads from any distance.
			var column := CylinderMesh.new()
			column.top_radius = 0.07
			column.bottom_radius = 0.07
			column.height = STAIR_COLUMN_HEIGHT
			_mesh(column, pos + Vector3(0, base_y + size.y + STAIR_COLUMN_HEIGHT / 2.0, 0),
				_material(COLORS["stair_marker"], COLORS["stair_marker"], MARKER_ENERGY))
		"exit":
			var halo := CylinderMesh.new()
			halo.top_radius = 0.62
			halo.bottom_radius = 0.62
			halo.height = 0.02
			_mesh(halo, pos + Vector3(0, base_y + 0.004, 0),
				_material(COLORS["exit_halo"], COLORS["exit_halo"], MARKER_ENERGY))


func _draw_mound(pos: Vector3, depth: float, material: Material) -> void:
	var mound := SphereMesh.new()
	mound.radius = MOUND_RADIUS
	mound.height = MOUND_HEIGHT
	var node := _mesh(mound, pos + Vector3(0, MOUND_HEIGHT * 0.15, 0), material)
	node.scale = Vector3(1.0, 1.0, depth)


## A few ember specks on the mound surface, near its edge.
func _draw_specks(pos: Vector3, depth: float) -> void:
	for spot in SPECK_SPOTS:
		var z: float = spot.y * depth
		var t := clampf(Vector2(spot.x, spot.y).length() / MOUND_RADIUS, 0.0, 1.0)
		var y := MOUND_HEIGHT * 0.15 + MOUND_HEIGHT / 2.0 * sqrt(1.0 - t * t)
		_speck(pos + Vector3(spot.x, y, z))


func _speck(at: Vector3) -> void:
	var speck := SphereMesh.new()
	speck.radius = 0.035
	speck.height = 0.07
	_mesh(speck, at, _material(COLORS["fire_speck"], COLORS["fire_speck"], SPECK_ENERGY))


## Thin glowing cracks on top of an ash path (fire, but subtle).
func _draw_cracks(top: Vector3) -> void:
	for crack in CRACKS:
		var line := BoxMesh.new()
		line.size = Vector3(crack.w, 0.01, 0.025)
		var node := _mesh(line, top + Vector3(crack.x, 0, crack.y),
			_material(COLORS["fire_crack"], COLORS["fire_crack"], CRACK_ENERGY))
		node.rotation_degrees.y = crack.z


## A shadow creature (shadow_figure.gd) with its origin on the floor, so the
## rise animation grows it up out of the floor. Dormant until its hour passes.
func _draw_shadow(sh: Dictionary, active: bool) -> void:
	var figure: Node3D = ShadowFigure.new()
	figure.setup(sh["id"], active, COLORS)
	figure.position = slot_to_position(sh["slot"])
	_content.add_child(figure)
	_shadow_nodes[sh["id"]] = figure
	_shadow_slots[sh["id"]] = sh["slot"]


## The slot a shadow was drawn on in the last redraw, or (-1, -1).
func last_shadow_slot(id: String) -> Vector2i:
	return _shadow_slots.get(id, Vector2i(-1, -1))


func shadow_node(id: String) -> Node3D:
	return _shadow_nodes.get(id)


## The shadow grows up out of the floor (its ember tip comes with it).
func rise_shadow(id: String) -> void:
	var pivot := shadow_node(id)
	if pivot == null or not pivot.is_inside_tree():
		return
	pivot.scale = SHADOW_RISE_START
	pivot.create_tween().tween_property(pivot, "scale", Vector3.ONE, SHADOW_RISE_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A stand-in for a destroyed shadow (the same creature, awake), kept until it
## dissipates (it survives redraws). Returns the node, or null if the slot is unknown.
func add_shadow_ghost(slot: Vector2i, id: String = "") -> Node3D:
	if slot.x < 0:
		return null
	if _fx_root == null:
		_fx_root = Node3D.new()
		_fx_root.name = "Fx"
		add_child(_fx_root)
	var ghost: Node3D = ShadowFigure.new()
	ghost.setup(id, true, COLORS)
	ghost.name = "ShadowGhost"
	ghost.position = slot_to_position(slot)
	_fx_root.add_child(ghost)
	return ghost


## The smoke breaks apart and fades, the eyes go out last, then the ghost frees itself.
static func dissipate_ghost(ghost: Node3D) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	if not ghost.is_inside_tree():
		ghost.free()
		return
	ghost.start_dissolve()


func _draw_player(state: GameStateScript, hour: int) -> void:
	var slot := state.player_slot
	# Stand on top of a stair box or a mound of remains instead of inside it.
	var under := state.object_at(hour, slot)
	var floor_y := 0.0
	var ring_radii := RING_RADII
	if under.get("type") == "stair":
		floor_y = STAIR_STAND_HEIGHT
	elif under.get("state") == GameStateScript.ASH and under.get("type") in ["crate", "door"]:
		floor_y = MOUND_STAND_HEIGHT
		ring_radii = RING_RADII_ON_MOUND
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 0.9
	_mesh(capsule, slot_to_position(slot) + Vector3(0, floor_y + 0.45, 0), _material(COLORS["player"], null, 0.0, false))
	var ring := TorusMesh.new()
	ring.inner_radius = ring_radii.x
	ring.outer_radius = ring_radii.y
	_mesh(ring, slot_to_position(slot) + Vector3(0, floor_y + 0.03, 0), _material(COLORS["player_ring"], COLORS["player_ring"], 0.8, false))
	# A small warm-white lantern over the head, so the player never reads as a shadow.
	var orb := SphereMesh.new()
	orb.radius = LANTERN_RADIUS
	orb.height = LANTERN_RADIUS * 2.0
	var lantern := _mesh(orb, slot_to_position(slot) + Vector3(0, floor_y + LANTERN_HEIGHT, 0),
		_material(COLORS["player_lantern"], COLORS["player_lantern"], LANTERN_ENERGY, false))
	lantern.name = "PlayerLantern"
	var light := OmniLight3D.new()
	light.name = "PlayerLight"
	light.light_color = COLORS["player_lantern"]
	light.light_energy = LANTERN_LIGHT_ENERGY
	light.omni_range = LANTERN_LIGHT_RANGE
	light.position = lantern.position
	_content.add_child(light)


func _box(size: Vector3, pos: Vector3, color_key: String) -> void:
	_mesh_box(size, pos, _material(COLORS[color_key], null, 0.0))


func _mesh_box(size: Vector3, pos: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(box, pos, material)


func _mesh(mesh: Mesh, pos: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	_content.add_child(node)
	return node


## One shared material per (color, emission, energy), so refreshes stay cheap.
## One shared material per (color, emission, energy, graded). Graded ones
## follow this room's passed-hour grade (see _apply_grade).
func _material(color: Color, emission: Variant, energy: float, graded: bool = true) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [color, emission, energy, graded]
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		if color.a < 1.0:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if emission != null:
			mat.emission_enabled = true
			mat.emission = emission
			mat.emission_energy_multiplier = energy
		_materials[key] = mat
		_material_base[mat] = {"color": color, "energy": energy, "graded": graded}
		if graded and not _shown_grade.is_empty():
			_apply_grade_to(mat, _shown_grade)
	return _materials[key]


func _apply_grade_to(mat: StandardMaterial3D, grade: Dictionary) -> void:
	var base: Dictionary = _material_base[mat]
	var c: Color = base["color"]
	var b: float = grade["brightness"]
	mat.albedo_color = Color(minf(c.r * b, 1.0), minf(c.g * b, 1.0), minf(c.b * b, 1.0), c.a)
	if mat.emission_enabled:
		mat.emission_energy_multiplier = base["energy"] * grade["emission"]
