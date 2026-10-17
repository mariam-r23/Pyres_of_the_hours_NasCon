extends Node
## Loads a level, reads keyboard input, forwards actions to core/ and sends
## the resulting events through EventBus. Holds NO game rules: every decision
## is made by core/game_session.gd and core/turn_manager.gd.
##
## Keys (read from InputEventKey directly, so project.godot needs no input map):
##   arrows / WASD  move            B  burn mode: the next direction burns
##   E  interact    Space  wait     (B again or Escape cancels burn mode)
##   Z  undo        R  restart
##
## The real work is in plain methods (load_level, perform, undo, restart,
## handle_key, key_to_action) so tests can call them without a window.

const LevelLoader := preload("res://core/level_loader.gd")
const LevelValidator := preload("res://core/level_validator.gd")
const GameSession := preload("res://core/game_session.gd")
const EventBusScript := preload("res://presentation/event_bus.gd")

signal burn_mode_changed(active: bool)

const DIRECTION_KEYS := {
	KEY_UP: "up", KEY_W: "up",
	KEY_DOWN: "down", KEY_S: "down",
	KEY_LEFT: "left", KEY_A: "left",
	KEY_RIGHT: "right", KEY_D: "right",
}

## The bus events go to. Left null, it is the EventBus autoload; tests set
## it to their own event_bus.gd instance before calling anything.
var bus = null
## The current play-through, or null before the first successful load.
var session: GameSession = null
var burn_mode := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if handle_key(event.keycode) != null:
			get_viewport().set_input_as_handled()


## Loads and validates a level file. On success starts a new session and
## emits level_loaded(meta). On failure emits level_load_failed(errors) and
## keeps the previous session. Returns the error list ([] on success).
func load_level(path: String) -> Array:
	var loaded := LevelLoader.load_file(path)
	var errors: Array = []
	if loaded["state"] == null:
		errors.assign(loaded["error"].split("\n"))
	else:
		errors.assign(LevelValidator.validate(loaded["state"]))
	if not errors.is_empty():
		_get_bus().level_load_failed.emit(errors)
		return errors
	session = GameSession.new(loaded["state"])
	_set_burn_mode(false)
	_get_bus().level_loaded.emit(loaded["meta"])
	return errors


## Forwards one action to the session and its events to the bus.
func perform(action: Dictionary) -> Dictionary:
	if session == null:
		return _no_level()
	var result := session.perform(action)
	_get_bus().emit_events(result["events"])
	return result


## Undoes the last valid action (or forwards the nothing_to_undo rejection).
func undo() -> Dictionary:
	if session == null:
		return _no_level()
	var result := session.undo()
	_get_bus().emit_events(result["events"])
	return result


## Back to the level's start with the undo history cleared.
func restart() -> void:
	if session == null:
		return
	session.restart()
	_set_burn_mode(false)
	_get_bus().level_restarted.emit()


## The current GameState (a copy), or null before a level is loaded.
func current_state():
	return null if session == null else session.current_state()


## Handles one key press. Returns the perform/undo result, {} for a key that
## only changed burn mode or restarted, or null for a key we do not use.
func handle_key(keycode: Key) -> Variant:
	match keycode:
		KEY_B:
			_set_burn_mode(not burn_mode)
			return {}
		KEY_ESCAPE:
			if not burn_mode:
				return null
			_set_burn_mode(false)
			return {}
		KEY_Z:
			_set_burn_mode(false)
			return undo()
		KEY_R:
			restart()
			return {}
	var action := key_to_action(keycode, burn_mode)
	if action.is_empty():
		return null
	# Any action key ends burn mode: a direction burned, anything else cancels it.
	_set_burn_mode(false)
	return perform(action)


## The action a key stands for: a direction moves (or burns in burn mode),
## E interacts, Space waits. {} for any other key.
static func key_to_action(keycode: Key, in_burn_mode: bool) -> Dictionary:
	if DIRECTION_KEYS.has(keycode):
		return {"type": "burn" if in_burn_mode else "move", "dir": DIRECTION_KEYS[keycode]}
	match keycode:
		KEY_E:
			return {"type": "interact"}
		KEY_SPACE:
			return {"type": "wait"}
	return {}


func _set_burn_mode(active: bool) -> void:
	if burn_mode == active:
		return
	burn_mode = active
	burn_mode_changed.emit(active)


## The injected bus, else the EventBus autoload, else a private bus (with a
## warning) so the game still runs before the autoload is registered.
func _get_bus():
	if bus == null and is_inside_tree():
		bus = get_node_or_null("/root/EventBus")
	if bus == null:
		push_warning("GameController: no EventBus autoload found; using a private bus")
		bus = EventBusScript.new()
		add_child(bus)
	return bus


func _no_level() -> Dictionary:
	push_warning("GameController: no level loaded")
	return {"ok": false, "events": [], "state": null, "reason": "no_level_loaded"}
