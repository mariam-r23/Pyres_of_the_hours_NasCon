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

## ALL colors live here so Noor can restyle in one place.
## Color rule: the world is cold (slate blue, ash gray). "fire" is the ONLY
## strongly saturated warm color. Embers and shadow tips are dim, deep
## red-orange (low brightness), never a bright saturated orange.
const COLORS := {
	"floor": Color(0.19, 0.22, 0.27),        # slate
	"wall": Color(0.36, 0.38, 0.42),         # ash gray stone
	"chasm": Color(0.04, 0.05, 0.07),        # near-black pit
	"bridge": Color(0.33, 0.36, 0.40),       # cold weathered planks
	"ash_path": Color(0.30, 0.30, 0.31),     # gameplay ash, glows (see "ember")
	"crate": Color(0.56, 0.59, 0.64),
	"door": Color(0.28, 0.36, 0.50),         # blue-steel gate (stands out from walls)
	"stair": Color(0.55, 0.60, 0.66),        # pale cold steel
	"exit": Color(0.70, 0.82, 0.90),         # pale cold light
	"exit_glow": Color(0.35, 0.50, 0.60),
	"exit_halo": Color(0.85, 0.93, 1.00, 0.35), # pale halo around the exit
	"stair_marker": Color(0.55, 0.85, 0.95, 0.55), # cold-light column over a stair
	"burnable_edge": Color(1.00, 0.93, 0.82, 0.55), # faint warm-white edge: "this burns"
	"ash": Color(0.16, 0.16, 0.17),          # burned remains (charcoal)
	"ember": Color(0.42, 0.14, 0.07),        # dim ember glow on gameplay ash
	"shadow_body": Color(0.03, 0.03, 0.04),
	"shadow_body_dormant": Color(0.03, 0.03, 0.04, 0.4),  # see-through: not here yet
	"shadow_tip": Color(0.38, 0.11, 0.06),   # deep red-orange, dimmer than fire
	"player": Color(0.10, 0.11, 0.13),
	"player_ring": Color(0.75, 0.85, 0.95),  # pale ring at the player's feet
	"active_room": Color(0.32, 0.38, 0.48),  # rim under the room the player is in
	"sun_marker": Color(0.80, 0.86, 0.92),   # cold pale dial hand
	"dial": Color(0.20, 0.22, 0.26),         # dark steel
	"fire": Color(1.00, 0.45, 0.05),         # THE warm accent. Only fire.
}

## Emission strength for gameplay ash and shadow tips.
const EMBER_ENERGY := 0.8
const SHADOW_TIP_DORMANT_ENERGY := 0.2
const SHADOW_TIP_ACTIVE_ENERGY := 2.5
const EXIT_GLOW_ENERGY := 1.6
const MARKER_ENERGY := 1.0
const BURNABLE_EDGE_ENERGY := 0.6
## How far the burnable edge sticks out past the object on each side.
const BURNABLE_EDGE_MARGIN := 0.12
const STAIR_COLUMN_HEIGHT := 1.4
## Walls are kept low so they do not hide what stands behind them.
const WALL_HEIGHT := 0.6

const CELL := 1.0

var grid_w := GameStateScript.DEFAULT_GRID_SIZE
var grid_h := GameStateScript.DEFAULT_GRID_SIZE

var _content: Node3D = null
var _materials := {}


## Look of an object: { "color": Color, "emission": Color or null }.
## Burned (ASH) objects are charcoal with an ember glow; an ash_path is
## gameplay ash, so it glows too. Unknown types fall back to the crate color.
static func object_style(type: String, state: String) -> Dictionary:
	if state == GameStateScript.ASH:
		return {"color": COLORS["ash"], "emission": COLORS["ember"]}
	match type:
		"ash_path":
			return {"color": COLORS["ash_path"], "emission": COLORS["ember"]}
		"exit":
			return {"color": COLORS["exit"], "emission": COLORS["exit_glow"]}
	return {"color": COLORS.get(type, COLORS["crate"]), "emission": null}


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


## Full rebuild of this room for `hour` from `state`.
func refresh(state: GameStateScript, hour: int) -> void:
	grid_w = state.grid_w
	grid_h = state.grid_h
	if _content != null:
		remove_child(_content)
		_content.queue_free()
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)

	if state.player_hour == hour:
		var rim := Vector3(grid_w + 0.5, 0.05, grid_h + 0.5)
		_mesh_box(rim, Vector3(0, -0.13, 0), _material(COLORS["active_room"], COLORS["active_room"], 0.4))
	for y in grid_h:
		for x in grid_w:
			_draw_terrain(state.terrain_at(hour, Vector2i(x, y)), Vector2i(x, y))
	for obj in state.objects.values():
		if obj["hour"] == hour and obj["state"] != GameStateScript.GONE:
			_draw_object(obj)
	for sh in state.shadows.values():
		if sh["hour"] == hour:
			_draw_shadow(sh["slot"], Sun.is_hour_passed(state, hour))
	if state.player_hour == hour:
		_draw_player(state, hour)


func _draw_terrain(tile: String, slot: Vector2i) -> void:
	var pos := slot_to_position(slot)
	if tile == GameStateScript.WALL:
		_box(Vector3(0.98, WALL_HEIGHT, 0.98), pos + Vector3(0, WALL_HEIGHT / 2.0, 0), "wall")
	elif tile == GameStateScript.CHASM:
		_box(Vector3(0.96, 0.1, 0.96), pos + Vector3(0, -0.6, 0), "chasm")
	else:
		_box(Vector3(0.96, 0.1, 0.96), pos + Vector3(0, -0.05, 0), "floor")


func _draw_object(obj: Dictionary) -> void:
	var pos := slot_to_position(obj["slot"])
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
	var energy := 0.0
	if style["emission"] != null:
		energy = EXIT_GLOW_ENERGY if obj["type"] == "exit" else EMBER_ENERGY
	_mesh_box(size, pos + Vector3(0, lift, 0), _material(style["color"], style["emission"], energy))

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


func _draw_shadow(slot: Vector2i, active: bool) -> void:
	var pos := slot_to_position(slot)
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 0.85
	var body_color: Color = COLORS["shadow_body"] if active else COLORS["shadow_body_dormant"]
	_mesh(body, pos + Vector3(0, 0.43, 0), _material(body_color, null, 0.0))
	var tip := SphereMesh.new()
	tip.radius = 0.1 if active else 0.07
	tip.height = tip.radius * 2.0
	var energy := SHADOW_TIP_ACTIVE_ENERGY if active else SHADOW_TIP_DORMANT_ENERGY
	_mesh(tip, pos + Vector3(0, 0.9, 0), _material(COLORS["shadow_tip"], COLORS["shadow_tip"], energy))


func _draw_player(state: GameStateScript, hour: int) -> void:
	var slot := state.player_slot
	# Stand on top of a stair box instead of inside it (stair height 0.3).
	var floor_y := 0.3 if state.object_at(hour, slot).get("type") == "stair" else 0.0
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.25
	capsule.height = 0.9
	_mesh(capsule, slot_to_position(slot) + Vector3(0, floor_y + 0.45, 0), _material(COLORS["player"], null, 0.0))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.3
	ring.outer_radius = 0.4
	_mesh(ring, slot_to_position(slot) + Vector3(0, floor_y + 0.03, 0), _material(COLORS["player_ring"], COLORS["player_ring"], 0.8))


func _box(size: Vector3, pos: Vector3, color_key: String) -> void:
	_mesh_box(size, pos, _material(COLORS[color_key], null, 0.0))


func _mesh_box(size: Vector3, pos: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(box, pos, material)


func _mesh(mesh: Mesh, pos: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	_content.add_child(node)


## One shared material per (color, emission, energy), so refreshes stay cheap.
func _material(color: Color, emission: Variant, energy: float) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color, emission, energy]
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
	return _materials[key]
