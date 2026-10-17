extends Node
## Autoload singleton "EventBus": logic results go in, one signal per event
## type comes out (PROJECT_CONTEXT.md 6.3). VFX, audio, UI and the camera only
## listen to these signals; they never call core/ directly.
##
##   EventBus.burned.connect(_on_burned)       # func _on_burned(event: Dictionary)
##
## Every core signal carries the event Dictionary exactly as core/ emitted it.

# --- Core events (6.3) ---
signal moved(event: Dictionary)
signal burned(event: Dictionary)
signal ash_moved(event: Dictionary)
signal shadow_appeared(event: Dictionary)
signal shadow_destroyed(event: Dictionary)
signal action_applied(event: Dictionary)
signal sun_advanced(event: Dictionary)
signal hour_passed(event: Dictionary)
signal action_rejected(event: Dictionary)
signal undo_done(event: Dictionary)
signal level_won(event: Dictionary)
signal level_failed(event: Dictionary)

# --- Presentation-only (not core events) ---
signal level_loaded(meta: Dictionary)
signal level_load_failed(errors: Array)
signal level_restarted

## Event types emit_events() routes; each is also a signal name above.
const CORE_EVENT_TYPES := [
	"moved", "burned", "ash_moved", "shadow_appeared", "shadow_destroyed",
	"action_applied", "sun_advanced", "hour_passed", "action_rejected",
	"undo_done", "level_won", "level_failed",
]


## Emits each event on the signal matching its "type", in order.
func emit_events(events: Array) -> void:
	for event in events:
		emit_event(event)


## Emits one event. An unknown or malformed event prints a warning and is skipped.
func emit_event(event: Variant) -> void:
	if typeof(event) != TYPE_DICTIONARY or not CORE_EVENT_TYPES.has(event.get("type")):
		push_warning("EventBus: ignoring unknown event %s" % str(event))
		return
	emit_signal(event["type"], event)
