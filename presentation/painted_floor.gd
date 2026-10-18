extends RefCounted
## Noor's hour paintings as the room floors: each room's walkable cells show
## art/hours/hour_<h>.jpeg, cropped "cover"-style to the room's aspect (the
## image center is kept, nothing is stretched). Chasm cells stay dark cutouts,
## walls stay blocks, and faint cold grid lines keep the cells readable. The
## painting is darkened and desaturated so objects, the player and markers pop;
## the room grade (room_view.gd room_mood / GRADE) darkens and greys it further
## for passed hours. Rooms the level does not use show a dim painting, no grid.
##
## room_view.gd builds the meshes on every refresh (a few quads) and keeps one
## material per room; the textures are loaded once and shared. No game rules.

const GameStateScript := preload("res://core/game_state.gd")

const IMAGE_DIR := "res://art/hours/"
## The paintings are 2752x1536; a room floor never needs more than this width.
## Downscaled once with mipmaps, so a floor seen from far away does not shimmer.
const TEXTURE_WIDTH := 1024

## Look (multipliers on the painting's own colors).
const BASE_BRIGHTNESS := 0.55  # the room light adds about 20% on top, so it reads near 65%
const BASE_SATURATION := 0.7
const MIN_SATURATION := 0.25
const UNUSED_BRIGHTNESS := 0.22
const UNUSED_SATURATION := 0.45

## Height of the painted surface over the floor tiles' top (y = 0), and of the
## grid lines over it (soot specks sit at 0.004, above both).
const PAINT_Y := 0.001
const GRID_Y := 0.002
const GRID_LINE_WIDTH := 0.03

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D painting : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 0.55;
uniform float saturation = 0.7;

void fragment() {
	vec3 c = texture(painting, UV).rgb;
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	ALBEDO = mix(vec3(grey), c, saturation) * brightness;
	ROUGHNESS = 1.0;
}
"""

static var _shader: Shader = null
static var _textures: Dictionary = {}
static var _grid_material: StandardMaterial3D = null


# --- Pure functions ----------------------------------------------------------------

static func image_path(hour: int) -> String:
	return "%shour_%d.jpeg" % [IMAGE_DIR, hour]


## The part of the image (in UV, 0..1) a room of `grid` cells shows: the
## largest centered rectangle with the room's aspect ("cover", no stretch).
static func cover_uv_rect(image_size: Vector2, grid: Vector2i) -> Rect2:
	if image_size.x <= 0.0 or image_size.y <= 0.0 or grid.x <= 0 or grid.y <= 0:
		return Rect2(0, 0, 1, 1)
	var image_aspect := image_size.x / image_size.y
	var room_aspect := float(grid.x) / grid.y
	if image_aspect > room_aspect:
		var w := room_aspect / image_aspect
		return Rect2((1.0 - w) / 2.0, 0.0, w, 1.0)
	var h := image_aspect / room_aspect
	return Rect2(0.0, (1.0 - h) / 2.0, 1.0, h)


## UV of a cell corner (corner x in 0..grid.x, y in 0..grid.y) inside `rect`.
static func corner_uv(corner: Vector2, grid: Vector2i, rect: Rect2) -> Vector2:
	return rect.position + Vector2(corner.x / grid.x * rect.size.x, corner.y / grid.y * rect.size.y)


## Brightness and saturation of a room's painted floor for its grade
## {brightness, emission, soot} (room_view.gd grade_for). The current hour is a
## bit brighter (the grade's brightness); passed hours darken faster than the
## tiles did (brightness squared) and lose color with the grade's glow fade.
## A room the level does not use is dim and greyish.
static func floor_look(grade: Dictionary, used: bool) -> Dictionary:
	var b: float = grade["brightness"]
	var e: float = grade["emission"]
	var darkening := b if b >= 1.0 else b * b
	if not used:
		return {"brightness": UNUSED_BRIGHTNESS * minf(darkening, 1.0), "saturation": UNUSED_SATURATION}
	var color_left := clampf((e - 0.4) / 0.6, 0.0, 1.0)  # emission runs 1.0 .. 0.4
	return {
		"brightness": BASE_BRIGHTNESS * darkening,
		"saturation": lerpf(MIN_SATURATION, BASE_SATURATION, color_left),
	}


## True if the level puts anything in this hour's room: terrain other than
## floor, an object, a shadow or the player.
static func room_used(state: GameStateScript, hour: int) -> bool:
	if state.player_hour == hour:
		return true
	for obj in state.objects.values():
		if obj["hour"] == hour:
			return true
	for sh in state.shadows.values():
		if sh["hour"] == hour:
			return true
	for row in state.terrain.get(hour, []):
		if (row as String).replace(GameStateScript.FLOOR, "") != "":
			return true
	return false


## The cells that show the painting: walkable floor (not walls, not chasms).
static func painted_cells(state: GameStateScript, hour: int) -> Array:
	var cells: Array = []
	for y in state.grid_h:
		for x in state.grid_w:
			if state.terrain_at(hour, Vector2i(x, y)) == GameStateScript.FLOOR:
				cells.append(Vector2i(x, y))
	return cells


## The cell edges the grid draws: every side of a painted cell, each once.
## An edge is [from, to] in corner coordinates (0..grid).
static func grid_edges(cells: Array) -> Array:
	var seen := {}
	var edges: Array = []
	for cell in cells:
		var c: Vector2i = cell
		for edge in [[Vector2i(c.x, c.y), Vector2i(c.x + 1, c.y)], [Vector2i(c.x, c.y + 1), Vector2i(c.x + 1, c.y + 1)],
				[Vector2i(c.x, c.y), Vector2i(c.x, c.y + 1)], [Vector2i(c.x + 1, c.y), Vector2i(c.x + 1, c.y + 1)]]:
			var key := "%d,%d-%d,%d" % [edge[0].x, edge[0].y, edge[1].x, edge[1].y]
			if not seen.has(key):
				seen[key] = true
				edges.append(edge)
	return edges


# --- Shared resources ------------------------------------------------------------------

## The hour's painting, downscaled once with mipmaps and shared (null if missing).
static func texture_for(hour: int) -> Texture2D:
	if _textures.has(hour):
		return _textures[hour]
	var tex: Texture2D = null
	var path := image_path(hour)
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			var image: Image = (res as Texture2D).get_image()
			if image != null and not image.is_empty():
				if image.is_compressed():
					image.decompress()
				if image.get_width() > TEXTURE_WIDTH:
					image.resize(TEXTURE_WIDTH, int(round(image.get_height() * float(TEXTURE_WIDTH) / image.get_width())), Image.INTERPOLATE_LANCZOS)
				image.generate_mipmaps()
				tex = ImageTexture.create_from_image(image)
			else:
				tex = res
	_textures[hour] = tex
	return tex


static func shared_shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	return _shader


## A room's floor material (one per room, so each room has its own grade).
static func new_material(hour: int) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shared_shader()
	var tex := texture_for(hour)
	if tex != null:
		mat.set_shader_parameter("painting", tex)
	return mat


static func grid_material(color: Color) -> StandardMaterial3D:
	if _grid_material == null:
		_grid_material = StandardMaterial3D.new()
		_grid_material.albedo_color = color
		_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_grid_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _grid_material


# --- Meshes ------------------------------------------------------------------------------

## One mesh with a quad per painted cell; `origin` is the room-local position of
## grid corner (0, 0). Null when no cell is painted.
static func floor_mesh(cells: Array, grid: Vector2i, uv_rect: Rect2, origin: Vector3, cell: float) -> ArrayMesh:
	if cells.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for c in cells:
		var corners := [Vector2(c.x, c.y), Vector2(c.x + 1, c.y), Vector2(c.x + 1, c.y + 1), Vector2(c.x, c.y + 1)]
		var points: Array = []
		for k in corners:
			points.append(origin + Vector3(k.x * cell, PAINT_Y, k.y * cell))
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(corner_uv(corners[i], grid, uv_rect))
			st.add_vertex(points[i])
	return st.commit()


## Thin quads along the grid edges, just above the painting. Null when none.
static func grid_mesh(edges: Array, origin: Vector3, cell: float) -> ArrayMesh:
	if edges.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := GRID_LINE_WIDTH / 2.0
	for edge in edges:
		var a := origin + Vector3(edge[0].x * cell, GRID_Y, edge[0].y * cell)
		var b := origin + Vector3(edge[1].x * cell, GRID_Y, edge[1].y * cell)
		var along := (b - a).normalized()
		var side := Vector3(-along.z, 0.0, along.x) * half
		var quad := [a - side - along * half, b - side + along * half, b + side + along * half, a + side - along * half]
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(quad[i])
	return st.commit()
