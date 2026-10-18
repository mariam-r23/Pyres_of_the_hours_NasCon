extends Node3D
## The ripple shot (the signature camera move) and the game camera itself.
##
## When the bus emits `burned` followed by `ash_moved` in the same action, the
## camera leaves the clock overview, eases to the burn hour's room, glides
## around the clock (the short way, never through the hub) to the target hour
## while the spirit's streak flies the same path (spirit_flash.gd), holds on
## the tile where the ash landed, and returns. Under 1.5 s in total. When the
## burn and the landing are in the same room it is only a small push-in.
##
## The arriving ash object is held back: its target slot is "hidden" (the
## views skip drawing it) until the ember lands, then slot_revealed fires so
## the view can pop it in. Only presentation is delayed; the state is not.
##
## While a shot plays every key is consumed: the first key press skips it
## (and reveals at once). cancel() (undo, restart, level load) stops it and
## clears the hidden set silently, so nothing ever stays hidden.
## No game rules here: it only reads events and positions.

const RoomViewScript := preload("res://presentation/room_view.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")
const SpiritFlashScript := preload("res://presentation/spirit_flash.gd")

signal ripple_started
signal ripple_finished
## The spirit takes off: world start and end of the flight, seconds until it
## leaves (the camera first settles on the burn) and how long it flies.
signal flight_started(start: Vector3, end: Vector3, delay: float, duration: float)
## A held-back slot is visible again (pop it in after the next redraw).
signal slot_revealed(hour: int, slot: Vector2i)
## The hidden set changed in any way (redraw needed).
signal hidden_slots_changed

## Why the last shot stopped: "finished", "skipped" or "cancelled".
const STOP_FINISHED := "finished"
const STOP_SKIPPED := "skipped"
const STOP_CANCELLED := "cancelled"

# --- Overview pose (where the camera rests) ---
## Framed so the ring of rooms fills about 87% of a 16:9 screen's height while
## staying out of the HUD zones (hud.gd reserved_rects); tests/test_layout.gd checks it.
const OVERVIEW_POSITION := Vector3(0, 28.05, 13.08)
const OVERVIEW_LOOK := Vector3(0, 0, 1.75)
const FOV := 40.0
## The aspect the framing is designed for. Narrower windows keep its width
## (more room above and below); wider ones keep its height (more at the sides).
const DESIGN_ASPECT := 16.0 / 9.0

# --- Close poses: the camera sits at focus + offset, looking at the focus ---
const ROOM_OFFSET := Vector3(0, 9.0, 6.0)      # framing one room
const LANDING_OFFSET := Vector3(0, 6.0, 4.0)   # closer, on the landing tile

# --- Timings (seconds). The flight itself is 0.55 to 0.9 s (spirit_flash.gd);
# the whole shot is at most 0.15 + 0.10 + 0.9 + 0.12 + 0.20 = 1.47 s. ---
const TO_ROOM_TIME := 0.15        # overview -> burn room (the burn flash plays)
const BEAT_TIME := 0.10           # a beat on the burning object before she leaves
const HOLD_TIME := 0.12           # rest on the landing tile (pop + puff)
const RETURN_TIME := 0.20         # back to the overview
const ARC_SAMPLES_PER_HOUR := 2   # keyframes per clock hour along the arc

## Same-room shots: only a small push-in toward the room.
const PUSH_IN_AMOUNT := 0.3
const SAME_ROOM_LAND_OFFSET := Vector3(0, 13.0, 9.0)

# --- Flashes (the streak itself is spirit_flash.gd) ---
const FLASH_TIME := 0.35          # burn flash / landing puff duration
const BURN_FLASH_SIZE := 1.1      # final radius of the burn flash
const LANDING_PUFF_SIZE := 0.6
const FLASH_ENERGY := 5.0

## Ease modes for a keyframe's segment.
const EASE_IN_OUT := "in_out"
const LINEAR := "linear"

## The bus to listen to (set before adding to the tree; main does this).
var bus: Node = null
## Grid size of the current level, for the landing tile position.
var grid_size := Vector2i(5, 5)

var camera: Camera3D
var _plan: Array = []
var _time := 0.0
var _duration := 0.0
var _playing := false
var _pending_burn := {}
var _flashes: Array = []  # live burn flash / landing puff nodes
## hour -> Array of slots whose arriving object is held back.
var _hidden := {}
var last_stop_reason := ""


func _init() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = FOV
	add_child(camera)


func _ready() -> void:
	camera.current = true
	_apply_pose(OVERVIEW_POSITION, OVERVIEW_LOOK)
	_apply_lens()
	get_viewport().size_changed.connect(_apply_lens)
	if bus != null:
		connect_bus(bus)


func _process(delta: float) -> void:
	if _playing:
		advance(delta)


## While a shot plays, every key event is consumed; a key press skips the shot.
func _input(event: InputEvent) -> void:
	if consume_input(event):
		get_viewport().set_input_as_handled()


## Lens for a viewport aspect: {keep_aspect, fov}. At 16:9 or wider the vertical
## field (FOV) is kept; narrower, the 16:9 horizontal field is kept instead, so
## the ring never grows toward the HUD at the sides.
static func lens_for_aspect(aspect: float) -> Dictionary:
	if aspect >= DESIGN_ASPECT - 0.001:
		return {"keep_aspect": Camera3D.KEEP_HEIGHT, "fov": FOV}
	var horizontal := 2.0 * rad_to_deg(atan(tan(deg_to_rad(FOV / 2.0)) * DESIGN_ASPECT))
	return {"keep_aspect": Camera3D.KEEP_WIDTH, "fov": horizontal}


func _apply_lens() -> void:
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	var lens := lens_for_aspect(size.x / size.y)
	camera.keep_aspect = lens["keep_aspect"]
	camera.fov = lens["fov"]


func is_playing() -> bool:
	return _playing


# --- Event pairing ---

## Listens to burned / ash_moved / action_applied on `new_bus` (once).
func connect_bus(new_bus: Node) -> void:
	bus = new_bus
	if not bus.burned.is_connected(on_burned):
		bus.burned.connect(on_burned)
		bus.ash_moved.connect(on_ash_moved)
		bus.action_applied.connect(_on_action_applied)


func _on_action_applied(_event: Dictionary) -> void:
	_pending_burn = {}


func on_burned(event: Dictionary) -> void:
	_pending_burn = event


## Plays the shot when this ash_moved belongs to the burn just seen.
## A burn without an ash link sends no ash_moved, so it plays nothing; the
## pending burn is dropped at the action's action_applied.
func on_ash_moved(event: Dictionary) -> void:
	if _pending_burn.is_empty() or _pending_burn["hour"] != event["from_hour"]:
		return
	var burn := _pending_burn
	_pending_burn = {}
	if _playing:
		skip()  # a new shot replaces the old one; reveal what it held
	_hide(event["to_hour"], event["to_slot"])
	var flight := flight_of(burn["hour"], event["to_hour"], event["to_slot"], grid_size, burn["slot"])
	play(plan_shot(burn["hour"], event["to_hour"], event["to_slot"], grid_size, burn["slot"]))
	flight_started.emit(flight["start"], flight["end"], flight["delay"], flight["duration"])


# --- Held-back (hidden) slots ---

## A copy of the hidden set: hour -> Array of slots. Views skip these.
func hidden_slots() -> Dictionary:
	return _hidden.duplicate(true)


func is_slot_hidden(hour: int, slot: Vector2i) -> bool:
	return _hidden.has(hour) and _hidden[hour].has(slot)


func _hide(hour: int, slot: Vector2i) -> void:
	if not _hidden.has(hour):
		_hidden[hour] = []
	if not _hidden[hour].has(slot):
		_hidden[hour].append(slot)
	hidden_slots_changed.emit()


## Clears the set first, then announces each slot so views pop it in.
func _reveal_all() -> void:
	if _hidden.is_empty():
		return
	var revealed := _hidden
	_hidden = {}
	hidden_slots_changed.emit()
	for hour in revealed:
		for slot in revealed[hour]:
			slot_revealed.emit(hour, slot)


# --- Shot planning (pure, testable) ---

## The spirit's flight for a burn at (from_hour, from_slot) and a landing at
## (to_hour, to_slot): {start, end, delay, duration} in world space. The delay is
## the time the camera needs to settle on the burn; the duration comes from the
## distance (spirit_flash.gd flight_duration).
static func flight_of(from_hour: int, to_hour: int, to_slot: Vector2i,
		grid: Vector2i = Vector2i(5, 5), from_slot: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	var start := ClockLayoutScript.hour_to_room_position(from_hour)
	if from_slot.x >= 0:
		start += RoomViewScript.grid_slot_position(from_slot, grid)
	var end := ClockLayoutScript.hour_to_room_position(to_hour) + RoomViewScript.grid_slot_position(to_slot, grid)
	var distance := Vector2(start.x - end.x, start.z - end.z).length()
	return {"start": start, "end": end, "delay": TO_ROOM_TIME + BEAT_TIME,
		"duration": SpiritFlashScript.flight_duration(distance)}


## Keyframes for one shot. Each is { position, look_at, duration, ease, phase }:
## the camera moves from the previous keyframe to this one in `duration`
## seconds. The first and last keyframes are the overview pose.
## Phases: "overview", "to_room", "beat", "glide", "land", "hold", "return".
## The glide keyframes sample the streak's ground path, so the camera focus
## rides with her; the last one ("land") tightens onto the landing tile.
## from_hour == to_hour gives a small push-in (no glide).
static func plan_shot(from_hour: int, to_hour: int, to_slot: Vector2i,
		grid: Vector2i = Vector2i(5, 5), from_slot: Vector2i = Vector2i(-1, -1)) -> Array:
	var flight := flight_of(from_hour, to_hour, to_slot, grid, from_slot)
	var start_focus: Vector3 = flight["start"]
	var landing: Vector3 = flight["end"]
	var flight_time: float = flight["duration"]

	var plan: Array = [_key(OVERVIEW_POSITION, OVERVIEW_LOOK, 0.0, LINEAR, "overview")]
	if from_hour == to_hour:
		var push_pos := OVERVIEW_POSITION.lerp(start_focus + ROOM_OFFSET, PUSH_IN_AMOUNT)
		var push_look := OVERVIEW_LOOK.lerp(start_focus, PUSH_IN_AMOUNT)
		plan.append(_key(push_pos, push_look, TO_ROOM_TIME, EASE_IN_OUT, "to_room"))
		plan.append(_key(push_pos, push_look, BEAT_TIME, LINEAR, "beat"))
		plan.append(_key(landing + SAME_ROOM_LAND_OFFSET, landing, flight_time, EASE_IN_OUT, "land"))
		plan.append(_key(landing + SAME_ROOM_LAND_OFFSET, landing, HOLD_TIME, LINEAR, "hold"))
		plan.append(_key(OVERVIEW_POSITION, OVERVIEW_LOOK, RETURN_TIME, EASE_IN_OUT, "return"))
		return plan

	plan.append(_key(start_focus + ROOM_OFFSET, start_focus, TO_ROOM_TIME, EASE_IN_OUT, "to_room"))
	plan.append(_key(start_focus + ROOM_OFFSET, start_focus, BEAT_TIME, LINEAR, "beat"))
	var a0 := ClockLayoutScript.hour_angle(from_hour)
	var turn := wrapf(ClockLayoutScript.hour_angle(to_hour) - a0, -PI, PI)
	var hours := absf(turn) / TAU * 12.0
	var samples := maxi(3, int(round(hours * ARC_SAMPLES_PER_HOUR)))
	# Equal steps along the path; easing is baked into the step times (sine
	# ease-in-out, the streak's own curve), so linear playback is smooth.
	var previous_time := 0.0
	for k in range(1, samples):
		var s := float(k) / samples
		var t := acos(1.0 - 2.0 * s) / PI * flight_time
		var focus := SpiritFlashScript.ground_position(start_focus, landing, s)
		plan.append(_key(focus + ROOM_OFFSET, focus, t - previous_time, LINEAR, "glide"))
		previous_time = t
	plan.append(_key(landing + LANDING_OFFSET, landing, flight_time - previous_time, LINEAR, "land"))
	plan.append(_key(landing + LANDING_OFFSET, landing, HOLD_TIME, LINEAR, "hold"))
	plan.append(_key(OVERVIEW_POSITION, OVERVIEW_LOOK, RETURN_TIME, EASE_IN_OUT, "return"))
	return plan


## The camera pose at `t` seconds into `plan`:
## { position, look_at, phase, u } where u is the eased 0..1 progress
## through the current keyframe's segment. Pure: used by playback and trail.
static func pose_at(plan: Array, t: float) -> Dictionary:
	var elapsed := 0.0
	for i in range(1, plan.size()):
		var key: Dictionary = plan[i]
		var d: float = key["duration"]
		if t < elapsed + d or i == plan.size() - 1:
			var u := 1.0 if d <= 0.0 else clampf((t - elapsed) / d, 0.0, 1.0)
			if key["ease"] == EASE_IN_OUT:
				u = ease_in_out(u)
			var prev: Dictionary = plan[i - 1]
			return {
				"position": prev["position"].lerp(key["position"], u),
				"look_at": prev["look_at"].lerp(key["look_at"], u),
				"phase": key["phase"],
				"u": u,
			}
		elapsed += d
	return {"position": plan[0]["position"], "look_at": plan[0]["look_at"], "phase": plan[0]["phase"], "u": 1.0}


static func total_duration(plan: Array) -> float:
	var total := 0.0
	for key in plan:
		total += key["duration"]
	return total


## Sine ease-in-out on 0..1.
static func ease_in_out(u: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(u, 0.0, 1.0))


static func _key(pos: Vector3, look: Vector3, duration: float, easing: String, phase: String) -> Dictionary:
	return {"position": pos, "look_at": look, "duration": duration, "ease": easing, "phase": phase}


# --- Playback ---

func play(plan: Array) -> void:
	if _playing:
		_stop(STOP_SKIPPED)
	_plan = plan
	_time = 0.0
	_duration = total_duration(plan)
	_playing = true
	if plan.size() > 1:
		_spawn_flash(plan[1]["look_at"], BURN_FLASH_SIZE)  # the burn, on its tile
	ripple_started.emit()
	advance(0.0)


## Steps the shot forward by `delta` seconds (called every frame; tests call
## it directly).
func advance(delta: float) -> void:
	if not _playing:
		return
	_time += delta
	if _time >= _duration:
		_reveal_all()
		_stop(STOP_FINISHED)
		return
	var pose := pose_at(_plan, _time)
	# The ember has landed once the landing move is done: show the arrival.
	if pose["phase"] in ["hold", "return"] and not _hidden.is_empty():
		_spawn_flash(pose["look_at"], LANDING_PUFF_SIZE)
		_reveal_all()
	_apply_pose(pose["position"], pose["look_at"])


## Skips the shot: overview pose at once, arrival revealed.
func skip() -> void:
	_reveal_all()
	if _playing:
		_stop(STOP_SKIPPED)


## Stops the shot because undo, restart or a level load made it stale: the
## hidden set is cleared (no pop) before anyone redraws.
func cancel() -> void:
	if not _hidden.is_empty():
		_hidden = {}
		hidden_slots_changed.emit()
	_pending_burn = {}
	if _playing:
		_stop(STOP_CANCELLED)


## True if the event was used by the shot (every key while playing; a key
## press also skips it). The caller marks the event handled.
func consume_input(event: InputEvent) -> bool:
	if not _playing or not event is InputEventKey:
		return false
	if event.is_pressed() and not event.is_echo():
		skip()
	return true


func _stop(reason: String) -> void:
	last_stop_reason = reason
	_playing = false
	_plan = []
	_remove_flashes()
	_apply_pose(OVERVIEW_POSITION, OVERVIEW_LOOK)
	ripple_finished.emit()


func _apply_pose(pos: Vector3, look: Vector3) -> void:
	camera.position = pos
	if camera.is_inside_tree():
		camera.look_at(look)


# --- Burn flash and landing puff ---

func _glow_material(alpha: float, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var fire: Color = RoomViewScript.COLORS["fire"]  # it IS fire
	mat.albedo_color = Color(fire, alpha)
	mat.emission_enabled = true
	mat.emission = fire
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _sphere_node(radius: float, mat: Material) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = mat
	add_child(node)
	return node


## A quick fire flash at `at` that grows to `size` and fades out.
func _spawn_flash(at: Vector3, size: float) -> void:
	if not is_inside_tree():
		return
	var mat := _glow_material(0.85, FLASH_ENERGY)
	var flash := _sphere_node(size, mat)
	flash.name = "Flash"
	flash.position = at + Vector3(0, 0.3, 0)
	flash.scale = Vector3.ONE * 0.2
	_flashes.append(flash)
	var tween := flash.create_tween().set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE, FLASH_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, FLASH_TIME)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, FLASH_TIME)
	tween.chain().tween_callback(func(): _free_flash(flash))


func _free_flash(flash: Node) -> void:
	_flashes.erase(flash)
	if is_instance_valid(flash):
		flash.queue_free()


func _remove_flashes() -> void:
	for node in _flashes:
		if node != null and is_instance_valid(node):
			if node.is_inside_tree():
				node.queue_free()
			else:
				node.free()
	_flashes = []
