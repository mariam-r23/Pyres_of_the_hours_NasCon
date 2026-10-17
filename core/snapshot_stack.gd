extends RefCounted
## Undo history (PROJECT_CONTEXT.md 3.6). No Nodes, graphics, audio or UI.
##
## Holds deep copies only: push() stores a copy and undo() hands out a copy,
## so no caller can change a stored snapshot afterwards.
## Push only after a VALID action; rejected actions are never pushed.
##
## Undo is free: it restores the earlier state exactly (counter, sun, status,
## objects, shadows) and advances nothing. It works out of a won or failed
## state. Its only event is undo_done.

const GameStateScript := preload("res://core/game_state.gd")

const REASON_NOTHING_TO_UNDO := "nothing_to_undo"

## Oldest first; the last entry is the current state.
var _states: Array = []


func _init(initial_state: GameStateScript) -> void:
	_states = [initial_state.duplicate_deep()]


## Records `state` as the new current state (stores a copy).
func push(state: GameStateScript) -> void:
	_states.append(state.duplicate_deep())


func can_undo() -> bool:
	return _states.size() > 1


## Number of undo steps available (pushes not yet undone).
func depth() -> int:
	return _states.size() - 1


## Steps back one state. Returns { ok, state, events, reason }; state is a copy.
func undo() -> Dictionary:
	if not can_undo():
		return {
			"ok": false,
			"state": _states.back().duplicate_deep(),
			"events": [{"type": "action_rejected", "reason": REASON_NOTHING_TO_UNDO}],
			"reason": REASON_NOTHING_TO_UNDO,
		}
	_states.pop_back()
	return {
		"ok": true,
		"state": _states.back().duplicate_deep(),
		"events": [{"type": "undo_done"}],
		"reason": "",
	}
