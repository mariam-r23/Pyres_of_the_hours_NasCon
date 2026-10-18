extends Node3D
## The spirit's flight: Cinder herself (a camera-facing cut-out of her portrait
## for the level's mood, softly masked, flickering, wrapped in small flames)
## carries the ash from the burned tile to the tile where it lands, in a smooth
## arc, leaning into the flight, leaving an ember trail, lighting each room she
## passes, and going out in a small flare where the ash lands. The flames are a
## fire effect, the one place saturated warm color is used (room_view.gd COLORS:
## fire, fire_streak, fire_trail, fire_speck, ash).
##
## The ripple camera plans the shot and the flight (see ripple_camera.gd) and
## calls launch(); the camera focus follows the same ground path
## (ground_position), so the camera rides along with her. The math is in static
## functions so tests need no window. No game rules here.

const RoomViewScript := preload("res://presentation/room_view.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")

## Flight time: about 0.9 s for far rooms, never under 0.55 s.
const MIN_FLIGHT_TIME := 0.55
const MAX_FLIGHT_TIME := 0.9
const FLIGHT_TIME_PER_UNIT := 0.02
## Below this ground distance the path is a straight hop (same room, or very close).
const SAME_ROOM_DISTANCE := 4.0
const BASE_HEIGHT := 0.5
const ARC_HEIGHT_MIN := 1.0
const ARC_HEIGHT_MAX := 3.0
const ARC_HEIGHT_PER_UNIT := 0.1

## A room lights up while the streak is within this ground distance of its center.
const ROOM_LIGHT_RANGE := 5.5
const ROOM_LIGHT_PEAK := 4.0
const ROOM_LIGHT_TIME := 0.8
const ROOM_LIGHT_HEIGHT := 3.0
const ROOM_LIGHT_RADIUS := 10.0

## Cinder's billboard: about 1.35 tiles tall, lifted so she floats over the tile.
const CINDER_SIZE := 1.35
const CINDER_LIFT := 0.35
const PORTRAIT_DIR := "res://art/portraits/"
const MOODS := ["amused", "annoyed", "menacing", "triumphant"]
const DEFAULT_MOOD := "amused"
## Portraits are downscaled once (with mipmaps) for the small billboard.
const PORTRAIT_WIDTH := 1024
## Where she is in each painting (UV of the full image): the crop is centered on
## her head and upper body; its width in UV (the height follows, keeping it square).
const CROPS := {
	"amused": {"center": Vector2(0.49, 0.29), "width": 0.27},
	"annoyed": {"center": Vector2(0.475, 0.29), "width": 0.27},
	"triumphant": {"center": Vector2(0.50, 0.28), "width": 0.27},
	"menacing": {"center": Vector2(0.60, 0.33), "width": 0.30},
}
## Soft oval mask (in quad UV, 0.5 = the edge): fully her inside MASK_INNER,
## gone by MASK_OUTER, so the quad's edges never show.
const MASK_INNER := 0.22
const MASK_OUTER := 0.48
## Seconds she fades out after landing, and the flames around her.
const LAND_FADE := 0.3
const FLAME_AMOUNT := 26
const FLARE_AMOUNT := 22
const TRAIL_AMOUNT := 70
const LANDING_AMOUNT := 18
## Seconds the landing ash lingers before its nodes are freed.
const LINGER_TIME := 1.4

const CINDER_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D portrait : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 crop_center = vec2(0.49, 0.29);
uniform vec2 crop_size = vec2(0.27, 0.48);
uniform float mask_inner = 0.22;
uniform float mask_outer = 0.48;
uniform vec4 glow_color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
uniform float glow = 0.45;
uniform float fade = 1.0;
uniform vec3 heading = vec3(0.0);
uniform float lean_strength = 0.3;
uniform float flicker = 0.04;

void vertex() {
	// Lean into the flight: the heading as seen from the camera tips her top that way.
	vec2 h = (VIEW_MATRIX * vec4(heading, 0.0)).xy;
	float lean = length(h) > 0.0001 ? clamp(-normalize(h).x * lean_strength, -lean_strength, lean_strength) : 0.0;
	float s = 1.0 + flicker * 0.5 * (sin(TIME * 11.0) + sin(TIME * 17.3));
	vec2 v = VERTEX.xy * s;
	VERTEX.xy = vec2(v.x * cos(lean) - v.y * sin(lean), v.x * sin(lean) + v.y * cos(lean));
	// Always face the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec3 c = texture(portrait, crop_center + (UV - 0.5) * crop_size).rgb;
	// A soft oval, a little taller than wide; it is fully gone before any quad edge.
	float d = length((UV - 0.5) * vec2(1.04, 1.0));
	float mask = 1.0 - smoothstep(mask_inner, mask_outer, d);
	float rim = smoothstep(mask_inner * 0.6, mask_outer, d) * mask;
	float f = 1.0 + flicker * sin(TIME * 13.0 + 1.3);
	ALBEDO = c * f + glow_color.rgb * glow * rim;
	ALPHA = mask * fade;
}
"""

static var _cinder_shader: Shader = null
static var _portraits: Dictionary = {}

var _jobs: Array = []
## The level's spirit mood: which portrait she flies as.
var mood := DEFAULT_MOOD


func _process(delta: float) -> void:
	advance(delta)


# --- Pure functions ----------------------------------------------------------------

## Flight time for a ground distance.
static func flight_duration(distance: float) -> float:
	return clampf(MIN_FLIGHT_TIME + distance * FLIGHT_TIME_PER_UNIT, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)


## Peak height of the arc above the ground path for a ground distance.
static func arc_height(distance: float) -> float:
	return clampf(ARC_HEIGHT_MIN + distance * ARC_HEIGHT_PER_UNIT, ARC_HEIGHT_MIN, ARC_HEIGHT_MAX)


## Sine ease-in-out on 0..1 (the same curve the camera's glide uses).
static func ease_time(t: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(t, 0.0, 1.0))


## The ground point (y = 0) at path progress s in 0..1. Between different rooms
## the path swings around the clock (the short way, never through the hub);
## for a short hop it is a straight line. The camera focus follows this path.
static func ground_position(start: Vector3, end: Vector3, s: float) -> Vector3:
	var a := Vector3(start.x, 0.0, start.z)
	var b := Vector3(end.x, 0.0, end.z)
	var u := clampf(s, 0.0, 1.0)
	if a.distance_to(b) < SAME_ROOM_DISTANCE or a.length() < 1.0 or b.length() < 1.0:
		return a.lerp(b, u)
	var a0 := atan2(a.x, -a.z)
	var turn := wrapf(atan2(b.x, -b.z) - a0, -PI, PI)
	if absf(turn) > PI - 0.35:
		turn = PI  # (nearly) opposite rooms go clockwise
	var r := lerpf(a.length(), b.length(), u)
	var angle := a0 + turn * u
	return Vector3(r * sin(angle), 0.0, -r * cos(angle))


## Where the streak is at time fraction t in 0..1: along the ground path with
## eased speed and a smooth arc over it.
static func arc_position(start: Vector3, end: Vector3, t: float) -> Vector3:
	var s := ease_time(t)
	var pos := ground_position(start, end, s)
	var distance := Vector2(start.x - end.x, start.z - end.z).length()
	pos.y = BASE_HEIGHT + arc_height(distance) * sin(PI * s)
	return pos


## Hours whose room the ground point is close enough to light up.
static func rooms_near(ground: Vector3) -> Array:
	var hours: Array = []
	for hour in [12, 2, 4, 6, 8, 10]:
		var center := ClockLayoutScript.hour_to_room_position(hour)
		if Vector2(ground.x - center.x, ground.z - center.z).length() <= ROOM_LIGHT_RANGE:
			hours.append(hour)
	return hours


## A passed room's light `age` seconds after it lit: bright, flickering, fading out.
static func room_light_energy(age: float) -> float:
	if age < 0.0 or age >= ROOM_LIGHT_TIME:
		return 0.0
	var fade := 1.0 - age / ROOM_LIGHT_TIME
	var flicker := 0.85 + 0.15 * sin(age * 47.0) * sin(age * 23.0 + 1.0)
	return ROOM_LIGHT_PEAK * fade * flicker


static func nearest_hour(point: Vector3) -> int:
	var best := 12
	var best_d := INF
	for hour in [12, 2, 4, 6, 8, 10]:
		var c := ClockLayoutScript.hour_to_room_position(hour)
		var d := Vector2(point.x - c.x, point.z - c.z).length()
		if d < best_d:
			best_d = d
			best = hour
	return best


## art/portraits/spirit_portrait_<mood>.jpeg; an unknown mood uses amused.
static func portrait_path(for_mood: String) -> String:
	return "%sspirit_portrait_%s.jpeg" % [PORTRAIT_DIR, for_mood if for_mood in MOODS else DEFAULT_MOOD]


## The crop of the portrait for a mood: {center, size} in UV, square in pixels
## for an image of `image_size`.
static func crop_for(for_mood: String, image_size: Vector2 = Vector2(2752, 1536)) -> Dictionary:
	var crop: Dictionary = CROPS.get(for_mood, CROPS[DEFAULT_MOOD])
	var width: float = crop["width"]
	return {"center": crop["center"], "size": Vector2(width, width * image_size.x / image_size.y)}


## Her opacity `age` seconds after landing: 1 down to 0 over LAND_FADE.
static func landing_fade(age: float) -> float:
	return clampf(1.0 - age / LAND_FADE, 0.0, 1.0)


## The mood's portrait, downscaled once with mipmaps and shared (null if missing).
static func portrait_texture(for_mood: String) -> Texture2D:
	var path := portrait_path(for_mood)
	if _portraits.has(path):
		return _portraits[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			var image: Image = (res as Texture2D).get_image()
			if image != null and not image.is_empty():
				if image.is_compressed():
					image.decompress()
				if image.get_width() > PORTRAIT_WIDTH:
					image.resize(PORTRAIT_WIDTH, int(round(image.get_height() * float(PORTRAIT_WIDTH) / image.get_width())), Image.INTERPOLATE_LANCZOS)
				image.generate_mipmaps()
				tex = ImageTexture.create_from_image(image)
	_portraits[path] = tex
	return tex


func set_mood(new_mood: String) -> void:
	mood = new_mood if new_mood in MOODS else DEFAULT_MOOD


# --- Playback ------------------------------------------------------------------------

## Starts a flight from `start` to `end` (world positions) after `delay`
## seconds, lasting `duration` seconds.
func launch(start: Vector3, end: Vector3, delay: float, duration: float) -> void:
	_jobs.append({
		"start": start, "end": end, "delay": delay, "duration": maxf(duration, 0.01),
		"age": 0.0, "landed": false, "landed_at": 0.0, "lit": {},
		"core": null, "flames": null, "trail": null, "burst": null, "flare": null, "lights": {},
	})


func is_flying() -> bool:
	for job in _jobs:
		if not job["landed"]:
			return true
	return false


func job_count() -> int:
	return _jobs.size()


## Steps every flight forward (called every frame; tests call it directly).
func advance(delta: float) -> void:
	for job in _jobs.duplicate():
		job["age"] += delta
		var flown: float = job["age"] - job["delay"]
		if flown >= 0.0 and not job["landed"]:
			if job["core"] == null:
				_build_streak(job)
			var t: float = clampf(flown / job["duration"], 0.0, 1.0)
			_place_streak(job, t)
			if t >= 1.0:
				_land(job)
		_update_lights(job)
		if job["landed"]:
			_fade_out(job, job["age"] - job["landed_at"])
		if job["landed"] and job["age"] - job["landed_at"] >= LINGER_TIME:
			_free_job(job)
			_jobs.erase(job)


## The shot ended (finished, skipped or cancelled): land whatever still flies.
func finish() -> void:
	for job in _jobs.duplicate():
		if not job["landed"]:
			if job["core"] != null:
				_land(job)
			else:
				_free_job(job)
				_jobs.erase(job)


func clear() -> void:
	for job in _jobs:
		_free_job(job)
	_jobs = []


# --- Streak, trail, lights, landing ------------------------------------------------------

func _build_streak(job: Dictionary) -> void:
	var cinder := MeshInstance3D.new()
	cinder.name = "SpiritCinder"
	var quad := QuadMesh.new()
	quad.size = Vector2(CINDER_SIZE, CINDER_SIZE)
	cinder.mesh = quad
	cinder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cinder.material_override = _cinder_material()
	cinder.extra_cull_margin = CINDER_SIZE  # the shader moves her vertices (billboard, lean)
	add_child(cinder)
	job["core"] = cinder

	# Small flames licking around her edge, rising.
	var flames := CPUParticles3D.new()
	flames.name = "CinderFlames"
	flames.amount = FLAME_AMOUNT
	flames.lifetime = 0.3
	flames.local_coords = false
	flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
	flames.emission_sphere_radius = CINDER_SIZE * 0.36
	flames.direction = Vector3(0, 1, 0)
	flames.spread = 25.0
	flames.initial_velocity_min = 0.4
	flames.initial_velocity_max = 0.9
	flames.gravity = Vector3(0, 2.0, 0)
	flames.scale_amount_min = 0.1
	flames.scale_amount_max = 0.2
	flames.color_ramp = _ramp([RoomViewScript.COLORS["fire"], RoomViewScript.COLORS["fire_trail"],
		Color(RoomViewScript.COLORS["fire_trail"], 0.0)])
	flames.mesh = _soft_particle_mesh()
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	job["flames"] = flames

	# The ember trail stays where it was emitted (world space), so it hangs behind.
	var trail := CPUParticles3D.new()
	trail.name = "EmberTrail"
	trail.amount = TRAIL_AMOUNT
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.direction = Vector3(0, 1, 0)
	trail.spread = 55.0
	trail.initial_velocity_min = 0.2
	trail.initial_velocity_max = 1.0
	trail.gravity = Vector3(0, -1.2, 0)
	trail.scale_amount_min = 0.05
	trail.scale_amount_max = 0.13
	trail.color_ramp = _ramp([RoomViewScript.COLORS["fire_streak"], RoomViewScript.COLORS["fire_trail"],
		Color(RoomViewScript.COLORS["fire_trail"], 0.0)])
	trail.mesh = _particle_mesh()
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)
	job["trail"] = trail


func _place_streak(job: Dictionary, t: float) -> void:
	var cinder: MeshInstance3D = job["core"]
	var pos := arc_position(job["start"], job["end"], t)
	var ahead := arc_position(job["start"], job["end"], minf(t + 0.03, 1.0))
	var body := pos + Vector3(0, CINDER_LIFT, 0)
	cinder.position = body
	(cinder.material_override as ShaderMaterial).set_shader_parameter("heading", ahead - pos)
	(job["flames"] as CPUParticles3D).position = body
	(job["trail"] as CPUParticles3D).position = pos
	for hour in rooms_near(Vector3(pos.x, 0.0, pos.z)):
		_light_room(job, hour)


func _light_room(job: Dictionary, hour: int) -> void:
	var lit: Dictionary = job["lit"]
	if lit.has(hour):
		return
	lit[hour] = job["age"]
	var light := OmniLight3D.new()
	light.name = "FlashLight_%d" % hour
	light.light_color = RoomViewScript.COLORS["fire"]
	light.omni_range = ROOM_LIGHT_RADIUS
	light.light_energy = 0.0
	light.position = ClockLayoutScript.hour_to_room_position(hour) + Vector3(0, ROOM_LIGHT_HEIGHT, 0)
	add_child(light)
	job["lights"][hour] = light


func _update_lights(job: Dictionary) -> void:
	for hour in job["lights"].keys():
		var light: OmniLight3D = job["lights"][hour]
		var age: float = job["age"] - job["lit"][hour]
		if age >= ROOM_LIGHT_TIME:
			_free_node(light)
			job["lights"].erase(hour)
		elif is_instance_valid(light):
			light.light_energy = room_light_energy(age)


## The streak lands: it goes out, a few ash particles drop where it came down.
func _land(job: Dictionary) -> void:
	job["landed"] = true
	job["landed_at"] = job["age"]
	var end: Vector3 = job["end"]
	if job["core"] != null:
		# She settles on the landing tile and goes out in a small flare (_fade_out).
		var cinder: MeshInstance3D = job["core"]
		cinder.position = Vector3(end.x, BASE_HEIGHT + CINDER_LIFT, end.z)
		(job["trail"] as CPUParticles3D).emitting = false
		(job["flames"] as CPUParticles3D).emitting = false
		job["flare"] = _flare(cinder.position)
	_light_room(job, nearest_hour(end))
	var burst := CPUParticles3D.new()
	burst.name = "LandingAsh"
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = LANDING_AMOUNT
	burst.lifetime = 0.9
	burst.local_coords = false
	burst.direction = Vector3(0, 1, 0)
	burst.spread = 60.0
	burst.initial_velocity_min = 1.0
	burst.initial_velocity_max = 2.6
	burst.gravity = Vector3(0, -6.0, 0)
	burst.scale_amount_min = 0.06
	burst.scale_amount_max = 0.16
	burst.color_ramp = _ramp([RoomViewScript.COLORS["fire_speck"], RoomViewScript.COLORS["ash"],
		Color(RoomViewScript.COLORS["ash"], 0.0)])
	burst.mesh = _particle_mesh()
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.position = Vector3(end.x, 0.4, end.z)
	add_child(burst)
	burst.emitting = true
	job["burst"] = burst


func _free_job(job: Dictionary) -> void:
	for key in ["core", "flames", "trail", "burst", "flare"]:
		_free_node(job[key])
		job[key] = null
	for light in job["lights"].values():
		_free_node(light)
	job["lights"] = {}


## After landing: she fades over LAND_FADE, then her billboard and flames are freed
## (the trail, ash and lights linger a little longer).
func _fade_out(job: Dictionary, age: float) -> void:
	var cinder = job["core"]
	if cinder == null or not is_instance_valid(cinder):
		return
	var alpha := landing_fade(age)
	(cinder.material_override as ShaderMaterial).set_shader_parameter("fade", alpha)
	if alpha <= 0.0:
		_free_node(cinder)
		_free_node(job["flames"])
		job["core"] = null
		job["flames"] = null


## A quick burst of fire where she lands.
func _flare(at: Vector3) -> CPUParticles3D:
	var flare := CPUParticles3D.new()
	flare.name = "LandingFlare"
	flare.one_shot = true
	flare.explosiveness = 0.95
	flare.amount = FLARE_AMOUNT
	flare.lifetime = 0.4
	flare.local_coords = false
	flare.direction = Vector3(0, 1, 0)
	flare.spread = 180.0
	flare.initial_velocity_min = 1.5
	flare.initial_velocity_max = 3.0
	flare.gravity = Vector3.ZERO
	flare.scale_amount_min = 0.08
	flare.scale_amount_max = 0.18
	flare.color_ramp = _ramp([RoomViewScript.COLORS["fire_streak"], RoomViewScript.COLORS["fire"],
		Color(RoomViewScript.COLORS["fire_trail"], 0.0)])
	flare.mesh = _soft_particle_mesh()
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.position = at
	add_child(flare)
	flare.emitting = true
	return flare


func _cinder_material() -> ShaderMaterial:
	if _cinder_shader == null:
		_cinder_shader = Shader.new()
		_cinder_shader.code = CINDER_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _cinder_shader
	var tex := portrait_texture(mood)
	if tex != null:
		mat.set_shader_parameter("portrait", tex)
		var crop := crop_for(mood, tex.get_size())
		mat.set_shader_parameter("crop_center", crop["center"])
		mat.set_shader_parameter("crop_size", crop["size"])
	mat.set_shader_parameter("mask_inner", MASK_INNER)
	mat.set_shader_parameter("mask_outer", MASK_OUTER)
	mat.set_shader_parameter("glow_color", RoomViewScript.COLORS["fire"])
	mat.set_shader_parameter("fade", 1.0)
	return mat


func _free_node(node) -> void:
	if node != null and is_instance_valid(node):
		if node.is_inside_tree():
			node.queue_free()
		else:
			node.free()


func _particle_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.disable_receive_shadows = true
	sphere.material = mat
	return sphere


## A soft glowing sprite (camera-facing quad with a radial falloff; normal blend,
## since additive ones pile up into a white-yellow cloud that hides her):
## flames read as glow licking around her, not as hard dots.
static var _soft_mesh: QuadMesh = null


func _soft_particle_mesh() -> Mesh:
	if _soft_mesh == null:
		var falloff := Gradient.new()
		falloff.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		falloff.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		var tex := GradientTexture2D.new()
		tex.gradient = falloff
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true  # else every sprite is drawn a full unit wide
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.disable_receive_shadows = true
		_soft_mesh = QuadMesh.new()
		_soft_mesh.size = Vector2(1, 1)
		_soft_mesh.material = mat
	return _soft_mesh


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / (colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	return g
