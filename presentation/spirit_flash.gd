extends Node3D
## The spirit's flight: a bright streak that carries the ash from the burned
## tile to the tile where it lands, in a smooth arc, leaving an ember trail,
## lighting each room it passes and dropping ash where it lands. It is a fire
## effect, so it is the one place saturated warm color is used (the colors are
## in room_view.gd COLORS: fire, fire_streak, fire_trail, fire_speck, ash).
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

const CORE_RADIUS := 0.22
const CORE_STRETCH := 2.4
const TRAIL_AMOUNT := 70
const LANDING_AMOUNT := 18
## Seconds the landing ash lingers before its nodes are freed.
const LINGER_TIME := 1.4

var _jobs: Array = []


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


# --- Playback ------------------------------------------------------------------------

## Starts a flight from `start` to `end` (world positions) after `delay`
## seconds, lasting `duration` seconds.
func launch(start: Vector3, end: Vector3, delay: float, duration: float) -> void:
	_jobs.append({
		"start": start, "end": end, "delay": delay, "duration": maxf(duration, 0.01),
		"age": 0.0, "landed": false, "landed_at": 0.0, "lit": {},
		"core": null, "trail": null, "burst": null, "lights": {},
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
	var core := MeshInstance3D.new()
	core.name = "SpiritStreak"
	var sphere := SphereMesh.new()
	sphere.radius = CORE_RADIUS
	sphere.height = CORE_RADIUS * 2.0
	core.mesh = sphere
	core.material_override = _glow(RoomViewScript.COLORS["fire_streak"], 5.0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	job["core"] = core

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
	var core: MeshInstance3D = job["core"]
	var pos := arc_position(job["start"], job["end"], t)
	var ahead := arc_position(job["start"], job["end"], minf(t + 0.03, 1.0))
	core.position = pos
	var heading := ahead - pos
	if heading.length() > 0.001 and core.is_inside_tree():
		core.look_at(pos + heading, Vector3.UP)
	core.scale = Vector3(1.0, 1.0, CORE_STRETCH)
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
		var core: MeshInstance3D = job["core"]
		core.position = Vector3(end.x, BASE_HEIGHT, end.z)
		core.visible = false
		(job["trail"] as CPUParticles3D).emitting = false
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
	for key in ["core", "trail", "burst"]:
		_free_node(job[key])
		job[key] = null
	for light in job["lights"].values():
		_free_node(light)
	job["lights"] = {}


func _free_node(node) -> void:
	if node != null and is_instance_valid(node):
		if node.is_inside_tree():
			node.queue_free()
		else:
			node.free()


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


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
