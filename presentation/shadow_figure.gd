extends Node3D
## One shadow creature, built in code (Noor's paintings: an inky black-violet
## smoke figure, hunched, ragged drifting edges, thin tendrils trailing into
## the floor, two small ember eyes). A camera-facing billboard with a
## procedural smoke shader, plus a soft dark smoke pool on the floor.
##
## States: dormant (the hour has not passed: see-through, barely moving, eyes
## almost off), active (solid, eyes lit with a slow breathing pulse, smoke
## drifting faster), and dissolving (destroyed: the smoke breaks apart and
## fades, the eyes go out last, then the node frees itself).
##
## The node's origin is at the floor, so scaling it (the rise animation) grows
## the figure up out of the floor. Variety (size, tint, mirror, phase) comes
## from the shadow id, never from randomness. Colors live in room_view.gd COLORS
## (passed in by setup(), since room_view.gd builds the figures).

## Base billboard size (tiles): a bit wider than a body, about a tile tall.
const BASE_SIZE := Vector2(1.0, 1.0)
const POOL_SIZE := 1.05
## Per-variant scale and tint (mixed into the body color).
const VARIANTS := [
	{"scale": 0.88, "tint": Color(0.03, 0.015, 0.05)},
	{"scale": 1.0, "tint": Color(0.015, 0.012, 0.03)},
	{"scale": 1.08, "tint": Color(0.035, 0.012, 0.03)},
]
## glow_level, opacity and drift speed for each state.
const DORMANT := {"glow": 0.15, "opacity": 0.38, "speed": 0.15, "breathing": 0.0}
const ACTIVE := {"glow": 1.0, "opacity": 1.0, "speed": 0.6, "breathing": 1.0}
## Seconds the destroyed figure takes to break apart.
const DISSOLVE_TIME := 0.6

const FIGURE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec3 body_color : source_color = vec3(0.03, 0.02, 0.07);
uniform vec3 ember_color : source_color = vec3(0.45, 0.12, 0.05);
uniform vec3 rim_color : source_color = vec3(0.62, 0.72, 0.88);
uniform float rim_strength = 0.2;
uniform float glow_level = 1.0;
uniform float opacity = 1.0;
uniform float speed = 0.6;
uniform float breathing = 1.0;
uniform float dissolve = 0.0;
uniform float flip = 1.0;
uniform float phase = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
float blob(vec2 p, vec2 c, vec2 r) { vec2 d = (p - c) / r; return exp(-dot(d, d)); }

void vertex() {
	// Face the camera; keep the node's scale (the rise animation grows it from the floor).
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	VERTEX *= sc;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	// p: x centered (mirrored per variant), y up from the floor (0) to the top (1).
	vec2 p = vec2((UV.x - 0.5) * flip, 1.0 - UV.y);
	float t = TIME * speed + phase;
	// Ragged edges: the shape is pushed around by drifting noise.
	vec2 warp = vec2(fbm(p * 5.0 + vec2(0.0, -t)), fbm(p * 5.0 + vec2(3.1, -t * 1.3))) - 0.5;
	vec2 q = p + warp * 0.08;
	// A hunched figure (Noor's shadows): back and shoulders bent forward, a small
	// head pushed out low in front with two spiky tufts, long thin arms hanging.
	float f = blob(q, vec2(-0.03, 0.45), vec2(0.17, 0.2))
		+ blob(q, vec2(0.02, 0.6), vec2(0.19, 0.09))
		+ blob(q, vec2(0.15, 0.6), vec2(0.075, 0.07))
		+ 0.8 * blob(q, vec2(0.12, 0.69), vec2(0.016, 0.05))
		+ 0.8 * blob(q, vec2(0.185, 0.68), vec2(0.015, 0.045))
		+ 0.9 * blob(q, vec2(0.19, 0.4), vec2(0.024, 0.17))
		+ 0.9 * blob(q, vec2(-0.16, 0.42), vec2(0.024, 0.16))
		+ blob(q, vec2(0.0, 0.28), vec2(0.12, 0.12));
	// Streaky, ragged smoke at the edges (stretched noise reads as wisps, not lumps).
	f += (fbm(vec2(q.x * 14.0, q.y * 4.0 + t)) - 0.5) * 0.55;
	// Thin tendrils trailing down into the floor, swaying slowly.
	float tendrils = 0.0;
	for (int i = 0; i < 5; i++) {
		float fi = float(i);
		float x0 = -0.2 + fi * 0.1 + 0.03 * sin(t * 1.7 + fi * 2.3 + q.y * 6.0);
		float w = 0.018 + 0.012 * hash(vec2(fi, 3.0));
		float len = 0.12 + 0.18 * hash(vec2(fi, 7.0));
		tendrils += exp(-pow((q.x - x0) / w, 2.0)) * smoothstep(0.0, len, q.y);
	}
	f += tendrils * smoothstep(0.42, 0.18, q.y) * 0.9;
	// Breaking apart: noise eats the smoke from the edges inward.
	float grain = fbm(p * 9.0 + vec2(t * 0.5, 0.0));
	f -= dissolve * (1.2 - grain * 0.6);
	float body = smoothstep(0.42, 0.62, f);
	float edge = smoothstep(0.42, 0.48, f) - smoothstep(0.5, 0.6, f);  // a thin cold rim

	// Embers: two small eyes, faint cracks in the chest, dim tips on the tendrils.
	float pulse = mix(1.0, 0.72 + 0.28 * sin(TIME * 2.2 + phase), breathing);
	vec2 e = p - vec2(0.165, 0.605);
	float eyes = exp(-dot(e - vec2(-0.022, 0.0), e - vec2(-0.022, 0.0)) / 0.00015)
		+ exp(-dot(e - vec2(0.02, -0.003), e - vec2(0.02, -0.003)) / 0.00015);
	float cracks = smoothstep(0.93, 1.0, 1.0 - abs(noise(q * vec2(14.0, 22.0) + vec2(0.0, t * 0.2)) * 2.0 - 1.0))
		* blob(q, vec2(0.0, 0.45), vec2(0.13, 0.12)) * 0.12;
	float tips = tendrils * smoothstep(0.08, 0.0, q.y) * 0.4;
	float eye_out = 1.0 - smoothstep(0.75, 1.0, dissolve);  // the eyes go out last
	float ember = (eyes * eye_out + (cracks + tips) * (1.0 - dissolve)) * glow_level * pulse;

	vec3 col = body_color + rim_color * edge * rim_strength;
	ALBEDO = col + ember_color * ember * 2.2;
	ALPHA = clamp(body * opacity + eyes * eye_out * glow_level * opacity, 0.0, 1.0);
}
"""

const POOL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform vec3 pool_color : source_color = vec3(0.01, 0.01, 0.02);
uniform float opacity = 1.0;
uniform float speed = 0.6;
uniform float dissolve = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float n = noise(p * 3.0 + vec2(TIME * speed * 0.4, 0.0));
	float r = length(p) + (n - 0.5) * 0.25;
	ALBEDO = pool_color;
	ALPHA = (1.0 - smoothstep(0.25, 0.95, r)) * 0.7 * opacity * (1.0 - dissolve);
}
"""

static var _figure_shader: Shader = null
static var _pool_shader: Shader = null

var shadow_id := ""
var variant: Dictionary = {}
var active := false
var dissolving := false
## The ember glow (eyes, cracks, tips), 0..1.
var glow_level := 0.0:
	set(value):
		glow_level = clampf(value, 0.0, 1.0)
		if _body_mat != null:
			_body_mat.set_shader_parameter("glow_level", glow_level)

var body: MeshInstance3D
var pool: MeshInstance3D
var _body_mat: ShaderMaterial
var _pool_mat: ShaderMaterial
var _dissolve_age := 0.0


# --- Pure functions ----------------------------------------------------------------

## A stable 32-bit FNV-1a hash of the id (no global random state).
static func id_hash(id: String) -> int:
	var h := 2166136261
	for b in id.to_utf8_buffer():
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


## The look for a shadow id: {index, scale, tint, flip (1 or -1), phase}. Same id, same look.
static func variant_for(id: String) -> Dictionary:
	var h := id_hash(id)
	var index := h % VARIANTS.size()
	var v: Dictionary = VARIANTS[index]
	return {
		"index": index,
		"scale": v["scale"],
		"tint": v["tint"],
		"flip": 1.0 if (h >> 8) & 1 == 0 else -1.0,
		"phase": float((h >> 12) % 628) / 100.0,
	}


## The shader settings for a state: {glow, opacity, speed, breathing}.
static func state_look(is_active: bool) -> Dictionary:
	return (ACTIVE if is_active else DORMANT).duplicate()


## How far a destroyed figure has broken apart `age` seconds in (0..1).
static func dissolve_at(age: float) -> float:
	return clampf(age / DISSOLVE_TIME, 0.0, 1.0)


# --- Node --------------------------------------------------------------------------

## Builds the figure for shadow `id` in its dormant or active state. `colors`
## needs shadow_body, shadow_tip, shadow_rim and shadow_pool (room_view.gd COLORS).
func setup(id: String, is_active: bool, colors: Dictionary) -> void:
	shadow_id = id
	name = "ShadowFigure"
	variant = variant_for(id)
	var size: Vector2 = BASE_SIZE * float(variant["scale"])

	body = MeshInstance3D.new()
	body.name = "Body"
	var quad := QuadMesh.new()
	quad.size = size
	quad.center_offset = Vector3(0, size.y / 2.0 - 0.02, 0)  # feet (tendril ends) just under the floor
	body.mesh = quad
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.extra_cull_margin = size.y
	_body_mat = ShaderMaterial.new()
	_body_mat.shader = _shared(true)
	_body_mat.render_priority = 1  # over the floor pool
	var tint: Color = variant["tint"]
	_body_mat.set_shader_parameter("body_color", Color(colors["shadow_body"]).lerp(tint, 0.6))
	_body_mat.set_shader_parameter("ember_color", colors["shadow_tip"])
	_body_mat.set_shader_parameter("rim_color", colors["shadow_rim"])
	_body_mat.set_shader_parameter("flip", variant["flip"])
	_body_mat.set_shader_parameter("phase", variant["phase"])
	body.material_override = _body_mat
	add_child(body)

	pool = MeshInstance3D.new()
	pool.name = "Pool"
	var plane := PlaneMesh.new()
	plane.size = Vector2(POOL_SIZE, POOL_SIZE) * float(variant["scale"])
	pool.mesh = plane
	pool.position = Vector3(0, 0.006, 0)
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pool_mat = ShaderMaterial.new()
	_pool_mat.shader = _shared(false)
	_pool_mat.set_shader_parameter("pool_color", colors["shadow_pool"])
	pool.material_override = _pool_mat
	add_child(pool)

	set_active(is_active)


## Dormant or active (see DORMANT / ACTIVE).
func set_active(is_active: bool) -> void:
	active = is_active
	var look := state_look(is_active)
	glow_level = look["glow"]
	for mat in [_body_mat, _pool_mat]:
		mat.set_shader_parameter("opacity", look["opacity"])
		mat.set_shader_parameter("speed", look["speed"])
	_body_mat.set_shader_parameter("breathing", look["breathing"])


## Destroyed: break apart over DISSOLVE_TIME, then free this node. (Outside the
## tree nothing animates; room_view.gd frees such a ghost itself.)
func start_dissolve() -> void:
	dissolving = true
	_dissolve_age = 0.0


func _process(delta: float) -> void:
	if dissolving:
		advance_dissolve(delta)


## Steps the dissolve (called every frame; tests call it directly).
func advance_dissolve(delta: float) -> void:
	_dissolve_age += delta
	var d := dissolve_at(_dissolve_age)
	_body_mat.set_shader_parameter("dissolve", d)
	_pool_mat.set_shader_parameter("dissolve", d)
	if d >= 1.0:
		dissolving = false
		queue_free()


static func _shared(figure: bool) -> Shader:
	if figure:
		if _figure_shader == null:
			_figure_shader = Shader.new()
			_figure_shader.code = FIGURE_SHADER
		return _figure_shader
	if _pool_shader == null:
		_pool_shader = Shader.new()
		_pool_shader.code = POOL_SHADER
	return _pool_shader
