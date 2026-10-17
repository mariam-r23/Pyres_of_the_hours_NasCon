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

# --- Timings (seconds). Worst case (a 180-degree glide) totals 1.37 s. ---
const TO_ROOM_TIME := 0.25        # overview -> burn room
const GLIDE_TIME_PER_HOUR := 0.08 # per clock hour travelled (60 degrees = 2 hours)
const LAND_TIME := 0.12           # target room -> landing tile
const HOLD_TIME := 0.22           # rest on the landing tile (mote fades)
const RETURN_TIME := 0.30         # back to the overview
const ARC_SAMPLES_PER_HOUR := 2   # keyframes per clock hour along the arc

# --- Ember mote (placeholder for Noor's VFX) ---
const MOTE_RADIUS := 0.12
const MOTE_HEIGHT := 0.6
const MOTE_ENERGY := 3.0

## Ease modes for a keyframe's segment.
const EASE_IN_OUT := "in_out"
const LINEAR := "linear"

## The bus to listen to (set before adding to the tree; main does this).
var bus: Node = null
## Grid size of the current level, for the landing tile position.
var grid_size := Vector2i(5, 5)

var camera: Camera3D
var _plan: Array = []
var _segment := 0
var _segment_time := 0.0
var _playing := false
var _pending_burn := {}
var _mote: MeshInstance3D = null
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
	_segment = 1
	_segment_time = 0.0
	_playing = true
	_spawn_mote()
	ripple_started.emit()
	advance(0.0)


## Steps the shot forward by `delta` seconds (called every frame; tests call
## it directly).
func advance(delta: float) -> void:
	if not _playing:
		return
	_segment_time += delta
	while _segment < _plan.size() and _segment_time >= _plan[_segment]["duration"]:
		_segment_time -= _plan[_segment]["duration"]
		_segment += 1
	if _segment >= _plan.size():
		_reveal_all()
		_stop(STOP_FINISHED)
		return
	var from: Dictionary = _plan[_segment - 1]
	var to: Dictionary = _plan[_segment]
	# The ember has landed once the landing move is done: show the arrival.
	if to["phase"] in ["hold", "return"]:
		_reveal_all()
	var u: float = _segment_time / to["duration"] if to["duration"] > 0.0 else 1.0
	if to["ease"] == EASE_IN_OUT:
		u = ease_in_out(u)
	var look: Vector3 = from["look_at"].lerp(to["look_at"], u)
	_apply_pose(from["position"].lerp(to["position"], u), look)
	_update_mote(to["phase"], look, u)


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


# --- Ember mote (placeholder; Noor's VFX replaces this function) ---

func _spawn_mote() -> void:
	_remove_mote()
	var sphere := SphereMesh.new()
	sphere.radius = MOTE_RADIUS
	sphere.height = MOTE_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	var fire: Color = RoomViewScript.COLORS["fire"]  # it IS fire
	mat.albedo_color = fire
	mat.emission_enabled = true
	mat.emission = fire
	mat.emission_energy_multiplier = MOTE_ENERGY
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mote = MeshInstance3D.new()
	_mote.name = "AshMote"
	_mote.mesh = sphere
	_mote.material_override = mat
	_mote.visible = false
	add_child(_mote)


## The mote rides the camera's focus from the burn room to the landing tile,
## then fades out during the hold.
func _update_mote(phase: String, focus: Vector3, u: float) -> void:
	if _mote == null:
		return
	_mote.visible = phase in ["glide", "land", "hold"]
	_mote.position = focus + Vector3(0, MOTE_HEIGHT, 0)
	var mat: StandardMaterial3D = _mote.material_override
	var alpha := 1.0 - u if phase == "hold" else 1.0
	mat.albedo_color.a = alpha
	mat.emission_energy_multiplier = MOTE_ENERGY * alpha
	if phase == "return":
		_mote.visible = false


func _remove_mote() -> void:
	if _mote != null:
		if _mote.is_inside_tree():
			_mote.queue_free()
		else:
			_mote.free()
		_mote = null
