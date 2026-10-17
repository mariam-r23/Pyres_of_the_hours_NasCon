extends Node3D
## The ripple shot (the signature camera move) and the game camera itself.
##
## When the bus emits `burned` followed by `ash_moved` in the same action, the
## camera leaves the clock overview, eases to the burn hour's room, glides
## around the clock (the short way, never through the hub) to the target hour,
## holds on the tile where the ash landed, and returns. A small ember mote
## rides along with the camera's focus. Under 1.5 s in total.
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

signal ripple_started
signal ripple_finished
## A held-back slot is visible again (pop it in after the next redraw).
signal slot_revealed(hour: int, slot: Vector2i)
## The hidden set changed in any way (redraw needed).
signal hidden_slots_changed

## Why the last shot stopped: "finished", "skipped" or "cancelled".
const STOP_FINISHED := "finished"
const STOP_SKIPPED := "skipped"
const STOP_CANCELLED := "cancelled"

# --- Overview pose (where the camera rests) ---
const OVERVIEW_POSITION := Vector3(0, 30, 17)
const OVERVIEW_LOOK := Vector3(0, 0, 1.2)
const FOV := 40.0

# --- Close poses: the camera sits at focus + offset, looking at the focus ---
const ROOM_OFFSET := Vector3(0, 9.0, 6.0)      # framing one room
const LANDING_OFFSET := Vector3(0, 6.0, 4.0)   # closer, on the landing tile

# --- Timings (seconds). Worst case (a 180-degree glide) totals 1.54 s. ---
const TO_ROOM_TIME := 0.25        # overview -> burn room (the burn flash plays)
const BEAT_TIME := 0.15           # a beat on the burning object before leaving
const GLIDE_TIME_PER_HOUR := 0.07 # per clock hour travelled (60 degrees = 2 hours)
const LAND_TIME := 0.12           # target room -> landing tile
const HOLD_TIME := 0.30           # rest on the landing tile (pop + puff, mote fades)
const RETURN_TIME := 0.30         # back to the overview
const ARC_SAMPLES_PER_HOUR := 2   # keyframes per clock hour along the arc

# --- Ember mote, trail and flashes (placeholders for Noor's VFX) ---
const MOTE_RADIUS := 0.2
const MOTE_HEIGHT := 0.6
const MOTE_ENERGY := 5.0
const TRAIL_COUNT := 6            # fading copies behind the ember
const TRAIL_SPACING := 0.03       # seconds of path between trail copies
const FLASH_TIME := 0.35          # burn flash / landing puff duration
const BURN_FLASH_SIZE := 1.1      # final radius of the burn flash
const LANDING_PUFF_SIZE := 0.6

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
var _mote: MeshInstance3D = null
var _trail: Array = []    # MeshInstance3D copies behind the mote
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
	if bus != null:
		connect_bus(bus)


func _process(delta: float) -> void:
	if _playing:
		advance(delta)


## While a shot plays, every key event is consumed; a key press skips the shot.
func _input(event: InputEvent) -> void:
	if consume_input(event):
		get_viewport().set_input_as_handled()


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
	play(plan_shot(burn["hour"], event["to_hour"], event["to_slot"], grid_size, burn["slot"]))


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

## Keyframes for one shot. Each is { position, look_at, duration, ease, phase }:
## the camera moves from the previous keyframe to this one in `duration`
## seconds. The first and last keyframes are the overview pose.
## Phases: "overview", "to_room", "glide", "land", "hold", "return".
## from_hour == to_hour gives a push-in (no glide).
static func plan_shot(from_hour: int, to_hour: int, to_slot: Vector2i,
		grid: Vector2i = Vector2i(5, 5), from_slot: Vector2i = Vector2i(-1, -1)) -> Array:
	var start_focus := ClockLayoutScript.hour_to_room_position(from_hour)
	if from_slot.x >= 0:
		start_focus += RoomViewScript.grid_slot_position(from_slot, grid)
	var target_room := ClockLayoutScript.hour_to_room_position(to_hour)
	var landing := target_room + RoomViewScript.grid_slot_position(to_slot, grid)

	var plan: Array = [_key(OVERVIEW_POSITION, OVERVIEW_LOOK, 0.0, LINEAR, "overview")]
	plan.append(_key(start_focus + ROOM_OFFSET, start_focus, TO_ROOM_TIME, EASE_IN_OUT, "to_room"))
	plan.append(_key(start_focus + ROOM_OFFSET, start_focus, BEAT_TIME, LINEAR, "beat"))

	if from_hour != to_hour:
		var a0 := ClockLayoutScript.hour_angle(from_hour)
		# Shortest signed turn; exactly opposite hours go clockwise.
		var turn := wrapf(ClockLayoutScript.hour_angle(to_hour) - a0, -PI, PI)
		if is_equal_approx(absf(turn), PI):
			turn = PI
		var hours := absf(turn) / TAU * 12.0
		var glide_time := hours * GLIDE_TIME_PER_HOUR
		var samples := maxi(2, int(round(hours * ARC_SAMPLES_PER_HOUR)))
		# Equal angle steps; easing is baked into the step times (sine
		# ease-in-out), so linear playback between them is smooth.
		var previous_time := 0.0
		var radius := start_focus.length()
		var end_radius := ClockLayoutScript.RADIUS
		for k in range(1, samples + 1):
			var s := float(k) / samples
			var t := acos(1.0 - 2.0 * s) / PI * glide_time
			var angle := a0 + turn * s
			var r := lerpf(radius, end_radius, s)
			var focus := Vector3(r * sin(angle), 0.0, -r * cos(angle))
			plan.append(_key(focus + ROOM_OFFSET, focus, t - previous_time, LINEAR, "glide"))
			previous_time = t

	plan.append(_key(landing + LANDING_OFFSET, landing, LAND_TIME, EASE_IN_OUT, "land"))
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
	_spawn_mote()
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
	_update_mote(pose)


## Skips the shot: overview pose at once, mote removed, arrival revealed.
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
	_remove_mote()
	_apply_pose(OVERVIEW_POSITION, OVERVIEW_LOOK)
	ripple_finished.emit()


func _apply_pose(pos: Vector3, look: Vector3) -> void:
	camera.position = pos
	if camera.is_inside_tree():
		camera.look_at(look)


# --- Ember mote, trail and flashes (placeholders; Noor's VFX replaces these) ---

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


func _spawn_mote() -> void:
	_remove_mote()
	_mote = _sphere_node(MOTE_RADIUS, _glow_material(1.0, MOTE_ENERGY))
	_mote.name = "AshMote"
	_mote.visible = false
	for i in TRAIL_COUNT:
		var fade := 1.0 - float(i + 1) / (TRAIL_COUNT + 1)
		var ghost := _sphere_node(MOTE_RADIUS * (0.4 + 0.5 * fade), _glow_material(0.6 * fade, MOTE_ENERGY * fade))
		ghost.visible = false
		_trail.append(ghost)


## The mote rises off the burning tile during the beat, rides the camera's
## focus to the landing tile with a trail behind it, then fades in the hold.
func _update_mote(pose: Dictionary) -> void:
	if _mote == null:
		return
	var phase: String = pose["phase"]
	var u: float = pose["u"]
	_mote.visible = phase in ["beat", "glide", "land", "hold"]
	var lift := MOTE_HEIGHT * u if phase == "beat" else MOTE_HEIGHT
	_mote.position = pose["look_at"] + Vector3(0, lift, 0)
	var alpha := 1.0 - u if phase == "hold" else 1.0
	var mat: StandardMaterial3D = _mote.material_override
	mat.albedo_color.a = alpha
	mat.emission_energy_multiplier = MOTE_ENERGY * alpha
	# Trail: where the ember was a moment ago, only while it travels.
	var travelling := phase in ["glide", "land"]
	for i in _trail.size():
		var past := pose_at(_plan, _time - (i + 1) * TRAIL_SPACING)
		_trail[i].visible = travelling and past["phase"] in ["beat", "glide", "land"]
		_trail[i].position = past["look_at"] + Vector3(0, MOTE_HEIGHT, 0)


## A quick fire flash at `at` that grows to `size` and fades out.
func _spawn_flash(at: Vector3, size: float) -> void:
	if not is_inside_tree():
		return
	var mat := _glow_material(0.85, MOTE_ENERGY)
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


func _remove_mote() -> void:
	for node in [_mote] + _trail + _flashes:
		if node != null and is_instance_valid(node):
			if node.is_inside_tree():
				node.queue_free()
			else:
				node.free()
	_mote = null
	_trail = []
	_flashes = []
