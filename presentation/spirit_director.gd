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
	if bus != null:
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


static func _load_dialogue() -> void:
	if _lines_cache.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(LINES_PATH))
		_lines_cache = data["lines"] if typeof(data) == TYPE_DICTIONARY else []
		var config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		_config_cache = config if typeof(config) == TYPE_DICTIONARY else {}
