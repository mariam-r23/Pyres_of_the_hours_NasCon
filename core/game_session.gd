extends RefCounted
## One play-through of a level: the current state plus its undo history.
## This is what the presentation layer calls. No Nodes, graphics, audio or UI.
##
##   var session = GameSession.new(state)   # state from level_loader / load_level
##   session.perform({"type": "move", "dir": "right"})
##   session.undo()
##   session.restart()
##
## Every result has the apply_action shape { ok, events, state, reason }.
## Returned states are copies: changing them never affects the session.

const GameStateScript := preload("res://core/game_state.gd")
const TurnManager := preload("res://core/turn_manager.gd")
const SnapshotStack := preload("res://core/snapshot_stack.gd")

var _initial: GameStateScript
var _state: GameStateScript
var _stack: SnapshotStack


func _init(initial_state: GameStateScript) -> void:
	_initial = initial_state.duplicate_deep()
	restart()


## Applies one action. Only a valid action changes the state and is pushed.
func perform(action: Variant) -> Dictionary:
	var result := TurnManager.apply_action(_state, action)
	if result["ok"]:
		_state = result["state"]
		_stack.push(_state)
	result["state"] = _state.duplicate_deep()
	return result


## Steps back one valid action (free; event undo_done), or rejects with
## nothing_to_undo.
func undo() -> Dictionary:
	var result := _stack.undo()
	if result["ok"]:
		_state = result["state"]
	result["state"] = _state.duplicate_deep()
	return result


## Back to the level's initial state with an empty history.
func restart() -> void:
	_state = _initial.duplicate_deep()
	_stack = SnapshotStack.new(_state)


func current_state() -> GameStateScript:
	return _state.duplicate_deep()


func can_undo() -> bool:
	return _stack.can_undo()
