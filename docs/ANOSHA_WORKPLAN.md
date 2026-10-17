# ANOSHA_WORKPLAN.md (v2)

**Role:** Core systems, presentation glue, ripple camera shot, menus, **integrator**.
**Branch:** `anosha/core` (PRs into `phase-1`)
**Folders you own:** `core/` (including `level_loader.gd` and `level_validator.gd`), `tests/` (runner and your cases), `presentation/` (including menus), plus the repo setup.
**Do not touch:** `tools/`, `reference/`, `tests/cases/`, `levels/data/`, `dialogue/`, `ui/`, `art/`, `vfx/`, `audio/`.

> Paste order for any AI session: `PROJECT_CONTEXT.md` → `DEVELOPMENT_FLOW.md` → this file → "I am on task X".

## What changed in v2
- The **solver and `validate_levels` moved to Mariam** (she consumes them most). You keep `core/level_validator.gd` because it encodes the rules.
- You now implement **terrain, the type table, direction-based burn, free invalid actions, and `actions_per_hour = 3`** exactly as in `PROJECT_CONTEXT.md` section 3.
- New events: `action_applied`. New API pieces Mariam needs: `legal_actions()` and `GameState.hash_key()`.
- You took over **menus** (main menu, level select, pause, credits) from Mariam.
- You must pass the JSON test cases in `tests/cases/` (Mariam exports them from her Python reference).

## Why this lane matters

Everything else depends on your logic and your event contract. Mariam's levels load through your loader, her solver calls your API, Noor's VFX and Mariam's UI react to your events. **Finish the logic early (Day 1 AM), keep the API stable, and everyone else can work in parallel.**

## Deliverables

### Phase 0: Setup (first hour)
- [ ] Create the GitHub repo, the Godot 4.4.1 project, `.gitignore`, folder skeleton
- [ ] Create all branches (see `DEVELOPMENT_FLOW.md` section 2) and protect `main` and `phase-1`
- [ ] Add `docs/` files and copy `PROJECT_CONTEXT.md` into `docs/`
- [ ] Find out the hackathon's judging criteria and submission format; post to the group

### Phase 1, Day 1: Headless logic (NO graphics)
Build in this order, one script per AI request, running tests after each.

1. [ ] `core/game_state.gd`: plain data for hours, terrain, objects, shadows, player, action counter, sun. Must have `duplicate_deep()` and **`hash_key()`** (canonical string of the whole state).
2. [ ] `core/level_loader.gd`: load the JSON format in `PROJECT_CONTEXT.md` 6.1 (including `rooms` terrain strings; unlisted rooms are all floor) into a `GameState`.
3. [ ] `core/level_validator.gd`: reject bad levels with readable errors: ash-link target is a wall, off the grid, or already holds an object; stair `links_to` slot is a wall or off the grid; missing exit; unknown type; shadow on the exit or on the player start; slot out of grid; two objects in one slot; duplicate ids.
4. [ ] **Walkability and blocking**, using the type table in section 3.2: terrain (`.` `#` `~`), INTACT vs ASH per type, bridge/ash_path making chasms passable, crate/door blocking until burned.
5. [ ] `core/turn_manager.gd`: `apply_action()` for `move`, `interact` (stairs only), `burn` (by direction), `wait`. **Invalid actions are rejected and free**: no state change, no sun advance, no snapshot, `action_rejected` with a reason.
6. [ ] `core/ash_transfer.gd`: on a valid burn: target → ASH, spawn the linked object (event order: `burned`, `ash_moved`), then destroy adjacent active shadows (`shadow_destroyed`). Reject with `ash_target_occupied` if the target holds the player or an active shadow.
7. [ ] **Sun marker:** `sun_index = start_index + floor(action_count / actions_per_hour)`, default `actions_per_hour = 3`. Emit `action_applied` after every valid action, `sun_advanced` and `hour_passed` when the index changes.
8. [ ] **Shadows:** dormant until their hour is passed, then active (`shadow_appeared`). They block movement (`shadow_blocks`). An action that would wake a shadow on the player's tile is rejected and free (`shadow_wakes_on_you`).
9. [ ] `core/snapshot_stack.gd`: push after every VALID action, `undo()` restores the previous state exactly (deep copy!), emit `undo_done`. Undo is free and does not advance the sun.
10. [ ] **Win and fail, in this order after every valid action:** player on exit → `level_won`; otherwise `sun_index >= 6` → `level_failed`. Reaching the exit on the final action still wins.
11. [ ] `legal_actions(state)`: returns only VALID actions. Mariam's solver depends on this and on `hash_key()`, so **post them in the group chat as soon as they work.**
12. [ ] `tests/run_tests.gd` + cases. Minimum: the L01 solution from `PROJECT_CONTEXT.md` 6.1 wins in exactly 10 actions; bridge burn reverts the chasm; ash_path makes a chasm walkable; crate ASH is walkable; a blocked move is rejected and free (sun unchanged); sun passing a room activates its shadows; burn next to an active shadow destroys it; burning next to a dormant shadow does not; shadow-wakes-on-you is rejected; undo restores exactly; dial completion fails; reaching the exit on the last action wins; same actions give the same result (determinism). Also make the runner load and pass every file in `tests/cases/*.json` (format in section 6.4).

**Done when:** `godot --headless -s tests/run_tests.gd` passes, and a short note in `core/README.md` shows how to call the API.
**Then:** open a PR into `phase-1` and **post in the group chat immediately** so Mariam and Noor can pull the API.

### Phase 1, Day 1 PM to Day 2 AM: Presentation glue
- [ ] `presentation/event_bus.gd`: an autoload singleton. Logic results go in, one signal comes out per event type (all of section 6.3, including `action_applied`).
- [ ] `presentation/game_controller.gd`: loads a level, reads input (arrows/WASD move, B then a direction to burn, E interact, Space wait, Z undo, R restart), calls `apply_action`, forwards events to the bus.
- [ ] `presentation/room_view.gd`: draws rooms and objects from `GameState`. Placeholders (colored squares) at first. When Noor's rooms land, **position objects using her `slot_<x>_<y>` Marker3D nodes** (section 6.5), not hard-coded numbers.
- [ ] Clock-face layout: 6 rooms around a circle, a sun marker that follows `sun_advanced`.
- [ ] Hook in Noor's laugh, VFX and Mariam's UI once they land. They only listen to the bus; you do not edit their folders.
- [ ] **Phase 1 demo-ready:** L01 playable with undo, placeholder art, laugh on burn.

### Phase 2: Ripple shot and integration
- [ ] **The ripple shot:** on `burned` followed by `ash_moved`, the camera glides from the burn hour to the target hour following the ash, then returns. Under about 1.5 seconds, skippable, input locked during it. This is a signature feature, **NEVER cut.**
- [ ] Shadow rendering: passed hours get a darker grade and more soot (Noor provides the grade and soot assets), shadows appear in view on `shadow_appeared`.
- [ ] Level progression: load next level on `level_won`, restart on `level_failed`.
- [ ] **Menus (moved from Mariam):** main menu, level select, pause, credits. Credits include AI tool credits and asset licenses (Mariam and Noor give you the text). Put these in `presentation/menus/`.
- [ ] Report any problem with a level's rules to Mariam right away; the solver is hers, but the rules are yours.
- [ ] Optional: BFS-based hint ("show next move"), using Mariam's solver.
- [ ] Act 3 ending logic (stop the clock vs let it burn) once the team decides.

### Phase 3: Ship
- [ ] Merge `phase-2` → `main`, tag `v1.0`
- [ ] Export the build and test it on a clean machine
- [ ] README: pitch, controls, team, AI summary, licenses

## Integrator duties (all phases)
- [ ] Review and merge PRs into `phase-1` / `phase-2` the same day they are opened
- [ ] Run the end-of-day build check and post a screenshot
- [ ] Merge the phase branch into `main` only when the build runs cleanly
- [ ] Keep `PROJECT_CONTEXT.md` in sync with any rule or API change

## Dependencies
- **You give Mariam:** loader, validator, `legal_actions()`, `hash_key()` (Day 1), `EventBus` (Day 1).
- **You give Noor:** the event contract and `event_bus` (Day 1). Tell her which events drive which VFX.
- **You need from Mariam:** levels and `tests/cases/*.json` to test against (Day 1 PM), the solver's findings.
- **You need from Noor:** laugh, VFX scenes, and rooms with `slot_x_y` markers (Day 2).

## Starter prompt for your AI session

```
[paste PROJECT_CONTEXT.md, DEVELOPMENT_FLOW.md, ANOSHA_WORKPLAN.md]

I am Anosha. I'm working in Godot 4.4.1 with GDScript on branch anosha/core.
Task: Phase 1 Day 1, step 1: core/game_state.gd.
Write original code. Core logic must not reference any Node, graphics, audio or UI.
Follow section 3 (terrain, type table, free invalid actions) and the event contract
exactly. If anything in the spec is ambiguous or conflicts, tell me instead of
guessing. Then show me how to test it.
```

## Watch out for
- Keep the logic **pure and deterministic**: no randomness, no time, no Nodes.
- Test undo carefully. Shallow copies are the classic bug: snapshots must be deep.
- "Invalid actions are free" means the action counter must NOT move on rejection. Test this explicitly.
- Check the bridge case: burning a bridge you are standing next to must make the chasm block again.
- If you change the API or events, update `PROJECT_CONTEXT.md` and tell everyone right away.
- If you are overloaded, drop optional items (hint system, level select polish) before slipping the logic.
