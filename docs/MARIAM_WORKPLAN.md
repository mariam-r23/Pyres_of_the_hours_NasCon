# MARIAM_WORKPLAN.md (v2)

**Role:** Puzzles and level data, solver and level-check tools, the Python reference, the fire spirit's writing and in-game AI dialogue, UI.
**Branch:** `mariam/puzzles-ui` (PRs into `phase-1`)
**Folders you own:** `levels/data/`, `tools/`, `reference/python/`, `tests/cases/`, `dialogue/`, `ui/`.
**Do not touch:** `core/`, `tests/run_tests.gd`, `presentation/`, `art/`, `vfx/`, `audio/`.
**Backup integrator** if Anosha is blocked.

> Paste order for any AI session: `PROJECT_CONTEXT.md` → `DEVELOPMENT_FLOW.md` → this file → "I am on task X".

## What changed in v2
- You now own **`tools/` (solver and `validate_levels`)** and the **Python reference** in `reference/python/`.
- Menus moved to Anosha, so your UI list is shorter.
- The rules changed to match your reference: **terrain tiles, `actions_per_hour = 3`, burn by direction, free invalid actions.** The one remaining difference is **stairs** (the spec uses `stair` objects with `links_to`; your reference used paired doorways). Update the reference to stairs.
- Dialogue now uses **per-level personality**: `spirit_mood`, optional `mood_weights`, stateless calls.

## Why this lane matters

You decide whether the game is actually fun. The rules are small, so **the puzzles are the game**, and the spirit's voice is what makes it memorable. Your Python reference is also the team's safety net: it is a second, independent implementation that catches rule bugs.

## Deliverables

### Phase 0
- [ ] Propose the fire spirit's name (3 options, one line each) and ally-who-turns vs rival. The team votes within the first day.
- [ ] Write her **voice sheet** (half a page): how she speaks, her verbal tics, what she never says, one example line per mood (amused, annoyed, triumphant, menacing). Save as `dialogue/voice_sheet.md`. It feeds the AI system prompt.

### Phase 1, Day 1 AM: Reference and levels (you do not need Anosha's code for this)
- [ ] Move your Python code to `reference/python/` and update it to match `PROJECT_CONTEXT.md` section 3 exactly: stairs instead of paired doorways, burn by direction, 3 actions per hour, terrain `. # ~`, invalid actions free, win-before-fail ordering, `shadow_wakes_on_you`.
- [ ] Make the L01 example from section 6.1 pass in your Python (10 actions, wins).
- [ ] **Export your 46 tests as JSON** into `tests/cases/*.json` using the format in section 6.4. Anosha's GDScript must pass all of them.
- [ ] Convert your three solved levels into the JSON level format in `levels/data/` (`L01_...json`, `L02_...json`, `L03_...json`). L01 can be the example from section 6.1.
- [ ] Post in the group chat when the cases are pushed, so Anosha can run them.

### Phase 1, Day 1 PM: Solver and level-check tools (GDScript)
- [ ] `tools/solver.gd`: BFS over game states using Anosha's `legal_actions(state)`, `apply_action()` and `state.hash_key()`. Cap depth and visited states so it can't hang. Return the shortest action list or "unsolvable".
- [ ] `tools/validate_levels.gd`: loops over `levels/data/*.json`, runs Anosha's `level_validator`, runs the solver, and prints: id, valid yes/no, solvable yes/no, shortest solution length, and `par_actions`. Exit code non-zero if any level fails.
- [ ] Cross-check: the solver's answer for L01 must be 10 actions. Python and GDScript solver results should match for your three levels.
- [ ] Tell the team the one-line command: `godot --headless -s tools/validate_levels.gd`. **A level is not merged until it passes.**
- [ ] Dependency: needs `legal_actions()` and `hash_key()` from Anosha. If she is late, port your Python solver structure first so you only have to swap the API calls.

### Phase 1, Day 1 PM to Day 2 AM: First UI (functional first, placeholder style)
Build UI scenes by hand in the Godot editor. Your AI agent writes the scripts and gives click-by-click steps for the scene.
- [ ] `ui/hud.tscn` + script: sun dial (6 hours, current hour highlighted, 3 ticks per hour), actions used vs par, level title.
- [ ] Undo button (Z) and restart button (R).
- [ ] Listen ONLY to `EventBus` signals (Anosha's `presentation/event_bus.gd`). Never call core logic directly.
- [ ] Reactions: `action_rejected` (small shake or message), `level_won` / `level_failed` (overlay with Next / Retry).

### Phase 1, Day 2 AM: Dialogue system v1 (cached lines only)
- [ ] `dialogue/lines.json`: all her lines with `mood` and `trigger` tags. Triggers: `on_burn`, `on_ash_moved`, `on_shadow_appeared`, `on_shadow_destroyed`, `on_undo`, `on_solve`, `on_fail`, `on_idle`, plus story beats. Moods: `amused`, `annoyed`, `triumphant`, `menacing`.
- [ ] `dialogue/spirit_dialogue.gd`: picks a line by trigger + mood + act, avoids repeating the last 3 lines, never blocks the game. Fully works with **cached lines only** (this is the fallback).
- [ ] **Mood picking (see `PROJECT_CONTEXT.md` section 8.1):** the base mood comes from the level's `spirit_mood`. If `mood_weights` is present, do a **seeded** weighted pick (seed from level id + trigger count) so demos are reproducible. Act 3 is mostly menacing regardless of weights; the act limits which moods are allowed. This logic lives ONLY in `dialogue/`, never in `core/`.
- [ ] `ui/dialogue_box.tscn`: small speech bubble with typewriter text, auto-hides, never covers the clock dial.
- [ ] Write the first 8 lines (act 1: charming and funny). Total target is **15 to 20 lines**.

### Phase 2: Full content
- [ ] **Puzzles 4 to 10** (target 8 to 10 total), escalating. Use the solver on every one. Suggested sequence:
  - **L01 Something Warm** (the example): burn, ash lands in another hour.
  - **L02 Wake the Shadow:** a shadow sleeps beside a gate in a room the sun has not passed yet. Burn the gate before the shadow wakes and you have nothing left to burn when it does, so you are stuck. Teaches: wait for the sun, then burn. (Your existing level 2 idea. Needs about 14 actions with 3 per hour.)
  - Shadow timing: wait for the sun to pass a room, or burn a shadow away.
  - Transfer: you need a bridge at one hour AND its wood at another, so order matters.
  - Ripple: one burn changes two other rooms, and ashing something too early blocks the solution.
  - Final two levels combine everything and set up act 3.
- [ ] Set `par_actions` from the solver's shortest solution. Set each level's `spirit_mood`, `act` and optional `mood_weights`.
- [ ] Tune `actions_per_hour` per level so the day is tight but fair (default 3; solutions around 8 to 15 actions).
- [ ] Playtest each level with someone who has NOT seen it. Note where they got stuck in `docs/AI_LOG.md`.
- [ ] Write the remaining lines for acts 2 and 3: her laugh starts to sound different, the reveal ("I'm not escaping the clock, I'm finishing it"), and the final choice.
- [ ] Intro text (3 to 4 lines on screen over Noor's art).
- [ ] Give Anosha the credits text (AI tools used, asset licenses) for the credits menu.

### Phase 2: In-game AI feature (default = A, the spirit's dialogue)
Build this AFTER cached dialogue works. Cut it last.
- [ ] `dialogue/ai_dialogue.gd`: **stateless** call. Send the fixed system prompt (shape in section 8.1), with `{voice_sheet}`, `{act}`, `{mood}`, `{trigger}`, a one-line game state, 3 example lines for that mood, and the last 3 lines she said. No chat history.
- [ ] **Always fall back** to cached lines (same mood tag) on timeout (about 2 seconds), error, or empty or too-long output.
- [ ] Output filter (max 15 words, banned words, no mention of being an AI). No API key in the repo: read it from an environment variable or a local ignored file.
- [ ] Decide with the team: live API during judging, or pre-generated lines. **Recommended:** pre-generate about 5 variants per trigger and mood with AI, curate by hand, ship them as cached lines, and keep live generation as an optional bonus.
- [ ] Optional alternative (B): AI proposes puzzle JSON, your solver validates it. Only if A is done and time remains.

### Phase 3: Ship
- [ ] Final text pass on every line and every UI string, no typos
- [ ] Run `validate_levels` and the test cases once more after any rule change
- [ ] Help Noor with trailer captions, and collect AI-use notes for the README

## Dependencies
- **You need from Anosha:** `legal_actions()`, `hash_key()`, loader and validator (Day 1), `EventBus` (Day 1).
- **You need from Noor:** UI style direction and fonts once the style is frozen (Day 1 PM), the laugh files to match lines to moods.
- **You give Anosha:** levels (JSON), `tests/cases/*.json`, solver findings, credits text.
- **You give Noor:** the line list and moods for the laugh variants, intro text for the trailer.

## Starter prompts for your AI session

**Puzzles:**
```
[paste PROJECT_CONTEXT.md, DEVELOPMENT_FLOW.md, MARIAM_WORKPLAN.md]

I am Mariam, I own puzzles, tools and dialogue. Help me design puzzle L02 "Wake the
Shadow": it teaches that burning a gate before its shadow wakes leaves you stuck.
Use only the rules in section 3 (terrain, type table, 3 actions per hour). Give me:
a 5x5 terrain sketch per room, objects and ash links, the intended solution as an
action list in the section 6.4 shorthand, how many actions it takes, and the level
JSON in the 6.1 format. Flag any ambiguity instead of guessing.
```

**Solver:**
```
[paste the three files]

I am Mariam, branch mariam/puzzles-ui. Task: tools/solver.gd, a BFS over game
states in GDScript. It must use only apply_action, legal_actions and
state.hash_key from section 6.2. Cap depth and visited states. Original code only.
Tell me how to test it against level L01 (expected shortest solution: 10 actions).
```

## Watch out for
- Puzzles that are secretly unsolvable, or solvable by an unintended shortcut. The solver catches both, so run it every time.
- Keep Python and GDScript agreeing. Any disagreement becomes a new test case, and section 3 decides who is wrong.
- Teach one idea per tutorial level. Do not explain with walls of text, let the level teach.
- Her lines: short, punchy, in character. Fifteen great lines beat forty average ones.
- Your lane is full. If you are overloaded, drop the optional puzzle generator (B) and extra UI polish first, never the first 8 puzzles, the solver, or the cached dialogue.
