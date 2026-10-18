extends Node
## Decides WHEN the fire spirit speaks and hands the line to the bus
## (EventBus.spirit_said). WHICH line is chosen is dialogue/dialogue_picker.gd's
## job (used exactly as dialogue/README.md documents). No game rules here.
##
## Per action at most ONE line: all triggers raised by one action's events are
## collected and the highest-priority one is said when the action's events are
## done (flush(), deferred to the end of the frame). If the ripple shot is
## playing, the line waits for the shot to finish. Undo, restart and level
## load drop a waiting line.

const Picker := preload("res://dialogue/dialogue_picker.gd")  # preload, not class_name

const LINES_PATH := "res://dialogue/lines.json"
const CONFIG_PATH := "res://dialogue/picker_config.json"

## Bus event -> spirit trigger.
const EVENT_TRIGGERS := {
	"burned": "on_burn",
	"ash_moved": "on_ash_moved",
	"undo_done": "on_undo",
	"level_won": "on_solve",
	"level_failed": "on_fail",
	"shadow_appeared": "on_shadow_appeared",
	"shadow_destroyed": "on_shadow_destroyed",
}
## When one action raises several triggers, the first in this list is said.
## (on_choice / on_reveal replace on_solve on their levels, so they rank with it.)
const TRIGGER_PRIORITY := [
	"on_choice", "on_reveal", "on_solve", "on_fail", "on_shadow_destroyed", "on_shadow_appeared",
	"on_burn", "on_ash_moved", "on_undo",
]

## When a trigger has both voiced lines (audio/voice/cinder_<id>.mp3) and
## unvoiced ones for the current act and mood, a voiced one is chosen this
## percent of the time (a seeded draw, so it is reproducible).
const VOICED_PERCENT := 85
const VOICE_DIR := "res://audio/voice/"

## Seconds without input (while playing) before the spirit says on_idle once.
const IDLE_SECONDS := 20.0

## The last level: winning it asks for the ending choice instead of "press N".
const ENDING_LEVEL_ID := "L10_center_of_the_dial"
const ENDING_TRIGGERS := {"wind": "on_ending_wind", "burn": "on_ending_burn"}
## The reveal level ("The Fuel"): its FIRST win this game session says
## on_reveal instead of on_solve; later wins say on_solve.
const REVEAL_LEVEL_ID := "L09_the_fuel"

## Lines come only from dialogue/lines.json (decided with Mariam): a trigger
## with no fitting line says nothing.

## Every decision, for diagnostics and tests:
## {trigger, mood, line_mood, text, tier, repeated, source}: mood is the
## picker's chosen mood, line_mood the mood the line was written in (they
## differ on tier 1 / 3 picks). source is "lines" (a line from lines.json)
## or "none" (nothing fits, nothing is said).
signal line_picked(result: Dictionary)

var bus: Node = null
## Object with is_playing() and last_stop_reason (the ripple camera), or null.
var ripple: Object = null

var level_id := ""
var ctx := {}
var picker = null
## True while the ending choice is on screen (won the ending level, no choice yet).
var ending_pending := false
## True while a menu or the pause screen is open: idle time does not count.
var suspended := false
## True once the reveal has been said this game session. Survives level loads
## and restarts, and is not undone by undo.
var reveal_played := false

var _batch: Array = []        # triggers raised by the current action
var _flush_queued := false
var _pending := {}            # a line waiting for the ripple shot: {trigger, mood, text}
var _level_over := false
var _idle_time := 0.0
var _idle_said := false

## Something with line_wait() -> float (spirit_laugh.gd): a line waits for her laugh.
var laugh: Object = null

var _deliver_token := 0
static var _voiced_cache: Dictionary = {}
static var _lines_cache: Array = []
static var _config_cache: Dictionary = {}


## Listens to the bus (call once; main does this before adding the node).
func connect_bus(new_bus: Node) -> void:
	bus = new_bus
	for event_name in EVENT_TRIGGERS:
		var trigger: String = EVENT_TRIGGERS[event_name]
		bus.connect(event_name, func(_event): _on_trigger_event(trigger))
	bus.level_won.connect(func(_event): _level_over = true)
	bus.level_failed.connect(func(_event): _level_over = true)
	bus.undo_done.connect(func(_event): _on_reset())
	bus.level_restarted.connect(_on_reset)
	bus.action_applied.connect(func(_event): note_activity())
	bus.ending_chosen.connect(choose_ending)


## Also listens to the ripple camera so a waiting line is said after the shot.
func connect_ripple(new_ripple: Object) -> void:
	ripple = new_ripple
	ripple.ripple_finished.connect(_on_ripple_finished)


## A fresh picker for a newly loaded level. meta comes from the level loader;
## any of act / spirit_mood / mood_weights it lacks is read from the level
## JSON at `path`.
func start_level(new_level_id: String, meta: Dictionary, path: String = "") -> void:
	level_id = new_level_id
	var info := meta.duplicate()
	for key in ["act", "spirit_mood", "mood_weights"]:
		if not info.has(key) and path != "":
			var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(raw) == TYPE_DICTIONARY and raw.has(key):
				info[key] = raw[key]
	ctx = {
		"act": int(info.get("act", 1)),
		"spirit_mood": str(info.get("spirit_mood", "amused")),
		"mood_weights": info.get("mood_weights", {}),
	}
	_load_dialogue()
	picker = Picker.new(_lines_cache, _config_cache, level_id)
	_on_reset()
	_level_over = false


func _process(delta: float) -> void:
	if _batch.is_empty():
		advance_idle(delta)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		note_activity()


# --- One line per action -----------------------------------------------------

func _on_trigger_event(trigger: String) -> void:
	if trigger == "on_solve" and level_id == ENDING_LEVEL_ID:
		# The last level: ask for the ending instead of the usual win line.
		ending_pending = true
		bus.ending_choice_requested.emit(level_id)
		trigger = "on_choice"
	elif trigger == "on_solve" and level_id == REVEAL_LEVEL_ID and not reveal_played:
		# The first win of "The Fuel" carries the reveal.
		reveal_played = true
		trigger = "on_reveal"
	_raise(trigger)


func _raise(trigger: String) -> void:
	_batch.append(trigger)
	if not _flush_queued:
		_flush_queued = true
		flush.call_deferred()


## Says the highest-priority trigger raised since the last flush (if any).
## Runs at the end of the frame; tests call it directly.
func flush() -> void:
	_flush_queued = false
	if _batch.is_empty():
		return
	var best: String = _batch[0]
	for trigger in _batch:
		if TRIGGER_PRIORITY.find(trigger) < TRIGGER_PRIORITY.find(best):
			best = trigger
	_batch = []
	say(best)


## Picks a line for `trigger` and delivers it (now, or after the ripple shot).
func say(trigger: String) -> Dictionary:
	if picker == null:
		return {}
	var r: Dictionary = picker.say(trigger, ctx)
	r = prefer_voiced(r, trigger)
	var result := {"trigger": trigger, "mood": r["mood"], "line_mood": "", "text": "",
		"tier": r["tier"], "repeated": r["repeated"], "source": "none"}
	if not (r["line"] as Dictionary).is_empty():
		result["text"] = str(r["line"]["text"])
		result["line_mood"] = str(r["line"].get("mood", r["mood"]))
		result["source"] = "lines"
	line_picked.emit(result)
	if result["text"] != "":
		if ripple != null and ripple.is_playing():
			_pending = result
		else:
			_deliver(result)
	return result


func _deliver(result: Dictionary) -> void:
	if bus == null:
		return
	# A line never starts on top of her laugh: it waits until the laugh is over.
	var wait: float = laugh.line_wait() if laugh != null else 0.0
	if wait > 0.0 and is_inside_tree():
		var token := _deliver_token
		get_tree().create_timer(wait).timeout.connect(func():
			if token == _deliver_token:
				_emit_said(result))
		return
	_emit_said(result)


func _emit_said(result: Dictionary) -> void:
	# The line's own mood, so the tag always matches how the line reads.
	bus.spirit_said.emit(result["trigger"], result["line_mood"], result["text"])


func _on_ripple_finished() -> void:
	if _pending.is_empty():
		return
	var line := _pending
	_pending = {}
	# A cancelled shot (undo, restart, level load) drops the line.
	if ripple.last_stop_reason != "cancelled":
		_deliver(line)


## Undo, restart and level load: drop the waiting line and the ending prompt.
func _on_reset() -> void:
	_pending = {}
	_deliver_token += 1
	_level_over = false
	ending_pending = false
	note_activity()


func has_pending_line() -> bool:
	return not _pending.is_empty()


# --- Idle --------------------------------------------------------------------

## Counts idle time; says on_idle once after IDLE_SECONDS while the level is
## being played (never during the ripple shot, a win, a fail, the ending,
## or while paused / in a menu).
func advance_idle(delta: float) -> void:
	if picker == null or suspended or _level_over or ending_pending or _idle_said:
		return
	if ripple != null and ripple.is_playing():
		return
	_idle_time += delta
	if _idle_time >= IDLE_SECONDS:
		_idle_said = true
		say("on_idle")


## The player did something: restart the idle clock and allow on_idle again.
func note_activity() -> void:
	_idle_time = 0.0
	_idle_said = false


# --- Ending ------------------------------------------------------------------

## "wind" or "burn". Ignored unless the ending choice is pending.
func choose_ending(choice: String) -> void:
	if not ending_pending or not ENDING_TRIGGERS.has(choice):
		return
	ending_pending = false
	say(ENDING_TRIGGERS[choice])


# --- Voiced lines preferred ---------------------------------------------------

## True if audio/voice/cinder_<line id>.mp3 exists.
static func is_voiced(line_id: String) -> bool:
	if not _voiced_cache.has(line_id):
		_voiced_cache[line_id] = ResourceLoader.exists("%scinder_%s.mp3" % [VOICE_DIR, line_id])
	return _voiced_cache[line_id]


## The picker chose `r` (a say() result). With VOICED_PERCENT chance we want a
## voiced line, otherwise an unvoiced one; if the choice is the other kind and
## a fresh line of the wanted kind exists for the same trigger, act and mood,
## it replaces it. The draw is seeded from the level and the picker's call
## count, so it is reproducible. The picker's no-repeat memory is updated, and
## a line said recently is never swapped in.
func prefer_voiced(r: Dictionary, trigger: String) -> Dictionary:
	var line: Dictionary = r["line"]
	if line.is_empty():
		return r
	var rng = Picker.Rng.new(Picker.seed_from_string("%s#voice#%d" % [level_id, picker.calls]))
	var roll: int = rng.next_u32()
	var want_voiced: bool = roll % 100 < VOICED_PERCENT
	if is_voiced(str(line["id"])) == want_voiced:
		return r
	var pool: Array = []
	for l in picker.lines:
		if l.get("trigger") == trigger and int(l.get("act", 1)) == int(ctx["act"]) \
				and l.get("mood") == r["mood"] and is_voiced(str(l["id"])) == want_voiced \
				and not (l["id"] in picker.recent):
			pool.append(l)
	if pool.is_empty():
		return r
	pool.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	var pick: Dictionary = pool[(roll / 100) % pool.size()]
	if not picker.recent.is_empty() and picker.recent[picker.recent.size() - 1] == line["id"]:
		picker.recent[picker.recent.size() - 1] = pick["id"]
	return {"mood": r["mood"], "line": pick, "tier": 0, "repeated": false}


static func _load_dialogue() -> void:
	if _lines_cache.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		_lines_cache = data["lines"] if typeof(data) == TYPE_DICTIONARY else []
		var config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config_cache = config if typeof(config) == TYPE_DICTIONARY else {}
