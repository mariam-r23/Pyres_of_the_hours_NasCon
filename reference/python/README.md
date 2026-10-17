# Python reference (section 3)

Second, independent implementation of `PROJECT_CONTEXT.md` section 3. No dependencies, Python 3.9+.
It is the team's safety net: Anosha's GDScript must agree with it on every shared case.

    cd reference/python
    python -m unittest discover -s tests -v      # 76 tests (includes all shared cases)
    python run_cases.py                          # just the shared JSON cases
    python validate_levels.py                    # id, valid, solvable, shortest, par (exit 1 on failure)
    python play.py ../../levels/data/L01_first_crate.json          # play in the terminal
    python play.py ../../levels/data/L01_first_crate.json --solve  # shortest solution
    python gen_cases.py                          # regenerate tests/cases/*.json + fixtures

API names mirror section 6.2: `load_level_from_dict`, `apply_action(state, action_dict)` returning
`{ok, events, state, reason}`, `legal_actions(state)`, `state.hash_key()`, `state.duplicate_deep()`,
`undo(stack)`, `is_hour_passed(state, hour)`. Events follow section 6.3.

## Section 11 compliance (Anosha's clarifications are part of the spec)
Matches `docs/PROJECT_CONTEXT.md` section 11: exact rejection reasons (item 11), event order (item 14),
`<source id>_ash` ids and default `flammable` table (item 13), lowercase `playing/won/failed` (item 15),
`level_over` for every action after a win or fail including `wait`, `legal_actions` empty then (item 3, 15),
undo is free, allowed out of a won or failed state, emits only `undo_done`, and `nothing_to_undo` otherwise
(items 2, 17), `GONE` counts as an empty slot (item 7), shadow on a wall rejected by the loader (item 8),
`wait` rejected when it would wake a shadow on the player (item 4), burn's neighbourhood excludes the burned slot
(item 5), `dial_complete` (item 6). The loader mirrors `core/level_loader.gd` and `core/level_validator.gd`
(`flammable` required on every object, exactly one exit, only a bridge or ash_path on a chasm, no shadow on the
exit or the player start, ids unique across objects and shadows, no object named like a created `<id>_ash`).

## Choices where the spec is silent (not in section 11; confirm if you disagree)
1. Arriving on the `exit` by `interact` counts as stepping onto it (win).
2. Burning off the grid returns `nothing_to_burn`.
3. Walkability reasons are checked in the same order as `core/walkability.gd`: bounds, wall, bare chasm
   (both `blocked_terrain`), then `blocked_object`.

## Rejection reasons (use these exact strings)
- move: `out_of_bounds`, `blocked_terrain`, `blocked_object`, `shadow_blocks`
- interact: `not_on_stair`, `arrival_blocked`
- burn: `nothing_to_burn`, `not_flammable`, `not_intact`, `ash_target_occupied`
- any action: `shadow_wakes_on_you`
- after a win or fail: `level_over`
- malformed action: `unknown_action` (the Python also uses `bad_direction` for a bad `dir`; use `unknown_action` in
  anything compared against GDScript)

## What was dropped from the old reference (and why)
Doorways (now stairs), terrain `E` (now an `exit` object), compass burn directions (now up/down/left/right),
custom object types, `plank/gate/stone/ash_bridge` (now `crate/door/bridge/ash_path`), the "caught" outcome, and
a 1-hour-per-3-actions rule that is now `sun_index = start_index + floor(actions / actions_per_hour)`.
