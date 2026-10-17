# Python reference (section 3)

Second, independent implementation of `PROJECT_CONTEXT.md` section 3. No dependencies, Python 3.9+.
It is the team's safety net: Anosha's GDScript must agree with it on every shared case.

    cd reference/python
    python -m unittest discover -s tests -v      # 38 tests (includes all shared cases)
    python run_cases.py                          # just the shared JSON cases
    python validate_levels.py                    # id, valid, solvable, shortest, par (exit 1 on failure)
    python play.py ../../levels/data/L01_first_crate.json          # play in the terminal
    python play.py ../../levels/data/L01_first_crate.json --solve  # shortest solution
    python gen_cases.py                          # regenerate tests/cases/*.json + fixtures

API names mirror section 6.2: `load_level_from_dict`, `apply_action(state, action_dict)` returning
`{ok, events, state, reason}`, `legal_actions(state)`, `state.hash_key()`, `state.duplicate_deep()`,
`undo(stack)`, `is_hour_passed(state, hour)`. Events follow section 6.3.

## Decisions where section 3 is silent or ambiguous (team: confirm, then I add them to the bible)
1. **`rejected_at` is a 0-based index** into the case's `actions` list (6.4 does not say).
2. **`wait` and `shadow_wakes_on_you`.** 3.3 says wait is never rejected; 3.5 says any action that would wake a shadow
   on the player's tile is invalid. I apply 3.5 to `wait` too (there is no "caught" outcome any more, so a wake on
   the player has to be refused). Move away instead.
3. **Burn's "4-neighborhood"** means the four adjacent slots only, not the burned slot itself.
4. **Arriving on an `exit` by `interact`** counts as stepping onto it (win).
5. **A burned object stays in its slot as an `ASH` object**, so an ash link into that slot is "occupied".
6. **Shadow activity is derived**: active = its hour is passed and it is not destroyed. With `sun.start_index > 0`,
   earlier hours are passed (and their shadows active) from the first action.
7. **Fail reason** is `dial_complete`. Rejection reasons beyond section 3: `out_of_bounds wall chasm blocked
   shadow_blocks not_on_stair stair_blocked nothing_to_burn not_intact not_flammable level_over`.
8. Ids of objects created by ash links (`<source id>>ash`) are an implementation detail, not part of the contract.

## What was dropped from the old reference (and why)
Doorways (now stairs), terrain `E` (now an `exit` object), compass burn directions (now up/down/left/right),
custom object types, `plank/gate/stone/ash_bridge` (now `crate/door/bridge/ash_path`), the "caught" outcome, and
a 1-hour-per-3-actions rule that is now `sun_index = start_index + floor(actions / actions_per_hour)`.
