# core/: puzzle logic

Pure, deterministic game rules (PROJECT_CONTEXT.md sections 3, 6 and 11).
No Nodes, graphics, audio, input, time or randomness. Owner: Anosha.

**Always `preload` these scripts, never use their `class_name`.** Headless runs on
a fresh clone have no global class cache, so `GameState` as a global name fails there.

```gdscript
const LevelLoader := preload("res://core/level_loader.gd")
const LevelValidator := preload("res://core/level_validator.gd")
const TurnManager := preload("res://core/turn_manager.gd")
const GameSession := preload("res://core/game_session.gd")
```

## Files

| file | what it does |
|---|---|
| `game_state.gd` | plain data for one moment: terrain, objects, shadows, player, counter, status. `duplicate_deep()`, `hash_key()` |
| `level_loader.gd` | level JSON (6.1) to GameState plus meta. Format errors name the field |
| `level_validator.gd` | rule checks on a loaded level. Returns every problem at once |
| `walkability.gd` | terrain plus type table: can the player stand here? (no shadows) |
| `sun.gd` | sun index, passed hours, active shadows |
| `ash_transfer.gd` | burn checks, ash links, destroying adjacent shadows |
| `turn_manager.gd` | `apply_action`, `legal_actions`, `is_hour_passed`, `load_level` |
| `snapshot_stack.gd` | undo history (deep copies only) |
| `game_session.gd` | current state plus undo history; what the presentation layer holds |

## Load and validate a level

```gdscript
var loaded := LevelLoader.load_file("res://levels/data/L01_first_crate.json")
if loaded["error"] != "":
	push_error(loaded["error"])          # one line per problem
	return
var errors := LevelValidator.validate(loaded["state"])   # [] means valid
var meta: Dictionary = loaded["meta"]    # title, act, spirit_mood, mood_weights, par_actions, spirit_lines
```

`TurnManager.load_level(data)` is a shortcut that returns the GameState, or `null`
for bad data (no error text, no meta).

## Play a level (presentation layer)

```gdscript
var session := GameSession.new(loaded["state"])

var result := session.perform({"type": "move", "dir": "right"})
# result = { ok: bool, events: Array, state: GameState, reason: String }
for event in result["events"]:
	EventBus.emit_event(event)           # each event has a "type" key (6.3)

session.undo()        # { ok, events: [undo_done], state } or reason "nothing_to_undo"
session.restart()     # back to the start, history cleared
session.current_state()
```

Actions:

```gdscript
{"type": "move", "dir": "up"}        # dir: up, down, left, right (y grows downward)
{"type": "burn", "dir": "left"}      # burns the object next to the player
{"type": "interact"}                 # take the stair you stand on
{"type": "wait"}
```

States returned by `GameSession` and `SnapshotStack` are copies, so changing
them never affects the game.

## Rules of the API

- `TurnManager.apply_action(state, action)` **never modifies `state`**. A valid action
  returns a new deep copy. A rejected action returns the same input state.
- **Rejected actions are free:** no counter change, no sun, nothing pushed to undo.
  `events` is exactly `[{"type": "action_rejected", "reason": ...}]`.
- Rejection reasons:
  - `move`: `out_of_bounds`, `blocked_terrain`, `blocked_object`, `shadow_blocks`
  - `interact`: `not_on_stair`, `arrival_blocked`
  - `burn`: `nothing_to_burn`, `not_intact`, `not_flammable`, `ash_target_occupied`
  - any action: `shadow_wakes_on_you`, `level_over` (after a win or fail), `unknown_action`
- Event order for a valid action:
  1. `moved`, or `burned`, `ash_moved`, `shadow_destroyed`
  2. `sun_advanced`
  3. `hour_passed`
  4. `shadow_appeared`
  5. `action_applied`
  6. then `level_won` or `level_failed` if the level ended (win beats fail)
- `state.status` is `"playing"`, `"won"` or `"failed"`. Undo works out of a win or fail.

## For the solver (Mariam)

```gdscript
var state = TurnManager.load_level(data)
TurnManager.legal_actions(state)   # only valid actions, fixed order:
                                   # move u/d/l/r, burn u/d/l/r, interact, wait; [] once over
state.hash_key()                   # canonical string of the full state, for the visited set
TurnManager.apply_action(state, action)["state"]
```

`legal_actions` and `apply_action` never disagree: `legal_actions` is
`apply_action` filtered by `ok`.

## Tests

```
godot_console --headless -s tests/run_tests.gd
```

This runs every suite in `tests/`, then `tests/fixtures/sample_cases.json`, then
every `*.json` in `tests/cases/` (format 6.4, clarification 10). The exit code is 1
if anything fails.
