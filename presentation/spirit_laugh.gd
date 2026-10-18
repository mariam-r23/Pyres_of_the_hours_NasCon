extends Node3D
## Her laugh, every time she carries ash: on every ash_moved it plays
## audio/voice/cinder_laugh_act<N>_01.mp3 for the level's act from the
## LANDING room's position (AudioStreamPlayer3D), so its direction hints which
## hour the ash landed in. Pitch rises a little with the hour (0.92 at 12 up to
## 1.12 at 10) and the laugh is quieter and a bit lower when the landing room is
## far from the room the player is in. A line chosen for the same action waits
## until the laugh is over (line_wait()). A missing file is simply no laugh.
## The choices are in static functions so tests need no audio.

const RoomViewScript := preload("res://presentation/room_view.gd")
const ClockLayoutScript := preload("res://presentation/clock_layout.gd")

const VOICE_DIR := "res://audio/voice/"
const HOUR_ORDER := [12, 2, 4, 6, 8, 10]
const MIN_PITCH := 0.92   # hour 12
const MAX_PITCH := 1.12   # hour 10
## Per room step (0 to 3 around the six rooms) between the landing room and the player's room.
const DB_PER_STEP := -3.0
const PITCH_DROP_PER_STEP := 0.015
## Quiet moment between the end of the laugh and the line.
const LINE_GAP := 0.25

var bus: Node = null
var act := 1
## Callable() -> state (or null): where the player is, for the distance choices.
var state_provider: Callable = Callable()

var player: AudioStreamPlayer3D
var last_pitch := 1.0
var last_volume_db := 0.0
var _ends_at := -100.0
var _stream_cache: Dictionary = {}


func _init() -> void:
	player = AudioStreamPlayer3D.new()
	player.name = "LaughPlayer"
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # distance is chosen below
	add_child(player)


func setup(new_bus: Node, new_state_provider: Callable) -> void:
	bus = new_bus
	state_provider = new_state_provider
	bus.ash_moved.connect(on_ash_moved)
	bus.level_loaded.connect(func(meta):
		act = int(meta.get("act", 1))
		stop())
	bus.level_restarted.connect(stop)


# --- Pure functions ----------------------------------------------------------------

static func laugh_path(for_act: int) -> String:
	return "%scinder_laugh_act%d_01.mp3" % [VOICE_DIR, clampi(for_act, 1, 3)]


## 0.92 for hour 12 rising evenly to 1.12 for hour 10 (the sun's order).
static func pitch_for_hour(hour: int) -> float:
	var index := maxi(HOUR_ORDER.find(hour), 0)
	return lerpf(MIN_PITCH, MAX_PITCH, float(index) / (HOUR_ORDER.size() - 1))


## How many rooms apart two hours are around the clock: 0 (same room) to 3 (opposite).
static func room_steps(hour_a: int, hour_b: int) -> int:
	var d := absi(HOUR_ORDER.find(hour_a) - HOUR_ORDER.find(hour_b))
	return mini(d, HOUR_ORDER.size() - d)


## Quieter the farther the landing room is from the player's room.
static func volume_db_for_steps(steps: int) -> float:
	return DB_PER_STEP * steps


## The hour's pitch, a bit lower when far.
static func pitch_scale_for(target_hour: int, steps: int) -> float:
	return pitch_for_hour(target_hour) * (1.0 - PITCH_DROP_PER_STEP * steps)


## How long a line must wait after a laugh that started `elapsed` seconds ago and
## lasts `laugh_length`: the rest of the laugh plus a small gap, 0 once it is over.
static func line_delay(laugh_length: float, elapsed: float) -> float:
	var remaining := laugh_length - elapsed
	return remaining + LINE_GAP if remaining > 0.0 else 0.0


# --- Playing ------------------------------------------------------------------------

## Plays the laugh for this ash_moved. Returns true if one started.
func on_ash_moved(event: Dictionary) -> bool:
	var stream := _stream(laugh_path(act))
	if stream == null:
		return false
	var to_hour: int = int(event["to_hour"])
	var state = state_provider.call() if state_provider.is_valid() else null
	var player_hour: int = int(state.player_hour) if state != null else to_hour
	var grid := Vector2i(state.grid_w, state.grid_h) if state != null else Vector2i(5, 5)
	var steps := room_steps(to_hour, player_hour)
	last_volume_db = volume_db_for_steps(steps)
	last_pitch = pitch_scale_for(to_hour, steps)
	player.stream = stream
	player.volume_db = last_volume_db
	player.pitch_scale = last_pitch
	player.position = ClockLayoutScript.hour_to_room_position(to_hour) \
		+ RoomViewScript.grid_slot_position(event["to_slot"], grid)
	player.play()
	_ends_at = _now() + stream.get_length() / last_pitch
	return true


## Seconds a line chosen for this action must wait (0 when no laugh is playing).
func line_wait() -> float:
	var remaining := _ends_at - _now()
	return remaining + LINE_GAP if remaining > 0.0 else 0.0


func stop() -> void:
	player.stop()
	_ends_at = -100.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _stream(path: String) -> AudioStream:
	if _stream_cache.has(path):
		return _stream_cache[path]
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is AudioStream:
			stream = res
	_stream_cache[path] = stream
	return stream
