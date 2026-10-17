# PROJECT_CONTEXT.md: Pyre of the Hours (v2)

> Paste this file into EVERY new AI session, before anything else.
> Then paste `DEVELOPMENT_FLOW.md` and your own `<NAME>_WORKPLAN.md`.
> Items marked **(default)** are decided-for-now and can be changed by the team. Items marked **(TBD)** are still open.

## What changed in v2 (everyone re-paste this file)

1. Added **terrain and a type table** (section 3): what blocks, what is walkable, what a bridge does.
2. **`actions_per_hour` now defaults to 3** (an 18-action day). Stairs cost actions like everything else.
3. **Invalid actions are free.** A rejected action changes nothing and does not advance the sun. The old "contact with a shadow ends your turn" rule is removed.
4. `burn` now targets a **direction**, not an id.
5. The example level in 6.1 is replaced by one that is **actually solvable** (with its solution and a test case).
6. **Keys and torches are cut from the default scope.** `interact` is for stairs only.
7. Ownership change: **`tools/` (solver and level validator) moved to Mariam.** Menus moved to Anosha. A Python reference implementation lives in `reference/python/`.
8. Art direction: **burnt clock tower**, cold-metal gears, ember-tip shadows, gears tick once per action.
9. AI dialogue: **per-level personality** (`spirit_mood`, optional `mood_weights`), stateless calls.
10. Hackathon AI rules are confirmed (AI use is allowed).

## 0. Rules for AI assistants (read first)

1. Section 3 (core rules) is the source of truth. If a request conflicts with it, SAY SO. Never silently change rules.
2. Write original code from this spec. Do not copy existing source code verbatim. List any library or asset used, with its license.
3. Work in small units: one script or one asset per request, and say how to test it.
4. Edit SCRIPTS ONLY (`.gd`, `.json`, `.md`). Do not hand-edit `.tscn`, `.tres`, `project.godot` or other editor-generated files. If a scene change is needed, give the human exact click-by-click editor steps instead.
5. Stay inside your owner's folders (section 7). If you need a change in someone else's folder, write it as a request in `docs/REQUESTS.md`.
6. Core logic must never import or reference graphics, audio or UI.
7. Run tests before declaring anything done. Never claim something works without running it.
8. If the GDScript logic and `reference/python/` disagree, section 3 wins. Fix whichever is wrong and add a test case that would have caught it.

## 1. Pitch

You are trapped in a giant, burnt-out clock-tower dungeon called **the Pyre**. Every room is a different hour of the same day, all running at once. Burn something in one hour and a laughing fire spirit carries its ash into a linked hour, where it becomes something new. But every action you take moves the sun forward, and in the hours the sun has already passed, shadows crawl out.

It is a puzzle crawler where one action ripples across the whole map.

- **Jam themes:** Fire, Shadow, Time (all three are core mechanics, not decoration).
- **Hackathon:** AI game development. AI is used throughout the making and inside the game. Hackathon AI-content rules are confirmed (AI use is allowed).
- **Team:** Anosha, Mariam, Noor. **Timeline:** 3 days.

## 2. Design pillars

1. **One rule, many consequences.** The core rule is small and deterministic. Surprise comes from combining it.
2. **Readable ripples.** The player must always see and hear what an action changed, including in rooms that are off screen.
3. **Fire is a character.** The mechanic has a face, a voice and a laugh.
4. **One warm accent on a cold world.** Every screenshot is recognizable at a glance.
5. **Polish over quantity.** Cut puzzles before cutting polish.

## 3. Core rules (SOURCE OF TRUTH)

### 3.1 World

**Hours.** 6 hours placed on a clock face at 12, 2, 4, 6, 8, 10. Sun order is `[12, 2, 4, 6, 8, 10]`; an hour's *order index* is its position in that list (12 → 0, 2 → 1, ... 10 → 5).

**Rooms.** Each hour is one room: a **5x5 grid (default)** of slots `[x, y]`, with `[0,0]` at the top-left, x to the right, y downward.

**Terrain.** Every slot has a terrain tile. Level files write each room as 5 strings of 5 characters (row = y, character = x):

| char | terrain | rule |
|---|---|---|
| `.` | floor | walkable |
| `#` | wall | blocks everything, always |
| `~` | chasm | blocks, UNLESS a walkable object (INTACT bridge, or ash_path) sits on it |

A room that is not listed in the level file is all floor.

**Objects.** Every object has: `id`, `type`, `hour`, `slot`, `state`, `flammable`, optional `ash_link`, optional `links_to` (stairs). One object per slot at most.
- States: `INTACT`, `ASH` (burned remains), `GONE` (removed; behaves like an empty slot; reserved, not used by the default types).

### 3.2 Type table (what each object does)

| type | INTACT | ASH | flammable | notes |
|---|---|---|---|---|
| `bridge` | **walkable**, makes a chasm tile passable | tile reverts to its terrain (a chasm blocks again) | yes | the classic puzzle piece: burning it removes your path |
| `ash_path` | **walkable**, makes a chasm tile passable | n/a | no | created by ash links, usually onto a chasm |
| `crate` | **blocks** | rubble: **walkable** | yes | burn it to clear the way |
| `door` | **blocks** (a wooden gate) | burned open: **walkable** | yes | opened only by burning (no keys) |
| `stair` | walkable; `interact` while standing on it travels to `links_to` | n/a | no | one-way unless the level also defines a return stair |
| `exit` | walkable; **stepping onto it wins** | n/a | no | |
| (shadow) | **blocks** | n/a | n/a | not an object, see 3.5 |

**Cut from default scope (add only if time remains):** `key`, `torch`.

### 3.3 Actions

Four actions. Direction is one of `up`, `down`, `left`, `right`.

| action | does | rejected (invalid) when |
|---|---|---|
| `move(dir)` | move one slot | target is outside the grid, a wall, a blocking chasm, a blocking object, or an active shadow |
| `interact` | use the stair you are standing on | you are not standing on a stair, or its arrival slot is blocked or occupied by an active shadow |
| `burn(dir)` | ignite the object in the adjacent slot in that direction | the slot has no object, or it is not INTACT, or it is not flammable, or its ash-link target is occupied (see 3.4) |
| `wait` | do nothing | never |

**INVALID ACTIONS ARE FREE.** An invalid action is rejected, changes nothing, does NOT advance the sun, is NOT snapshotted, and emits `action_rejected` with a `reason`. (Undo is also free: it restores a snapshot and does not advance the sun.)

**Every VALID action advances the action counter by one.**

### 3.4 Burning and ash links

When a valid `burn` succeeds, in this order:
1. The target object becomes `ASH` (event `burned`).
2. If it has an `ash_link`, a new object of type `becomes` appears INTACT at `ash_link.hour` / `ash_link.slot` (event `ash_moved`). **Ash links are fixed data, never random.**
3. Every active shadow in the same room, in the 4-neighborhood of the burned object's slot, is destroyed (event `shadow_destroyed`). Destroyed shadows stay destroyed.

The ash-link target slot must contain no object, no player and no active shadow. At level-load time the validator rejects a link whose target is a wall, off the grid, or already holds an object. At run time, if the target holds the player or an active shadow, the `burn` is invalid (reason `ash_target_occupied`).

### 3.5 Sun marker and shadows

**Sun.** `sun_index = sun.start_index + floor(action_count / actions_per_hour)`.
- **`actions_per_hour` defaults to 3**, so a day is 18 actions (6 hours x 3). Each level sets its own value; tune it per puzzle. Typical solutions are 8 to 15 actions. Stairs and waiting cost actions like any other.
- It is turn-based and never real time.
- **Passed hour:** an hour is passed when its order index is less than `sun_index`.
- **Dial complete:** `sun_index >= 6`. If the dial completes before the player reaches the exit, the level fails. **(default)**
- **Order of checks after every valid action:** (1) did the player step onto the exit? → win. (2) Otherwise, did the dial complete? → fail. So reaching the exit on the very last action still wins.

**Shadows.** Placed by fixed level data (never random, never moving). A shadow is **dormant** while its hour is not passed, and **active** once its hour is passed.
- An active shadow blocks its tile. Moving into it is an invalid, free action (`reason: shadow_blocks`).
- If a valid action would cause a shadow to wake on the player's own tile, that action is invalid and free (`reason: shadow_wakes_on_you`). The player must act differently.
- Fire destroys an active shadow (3.4, step 3).
- Dormant shadows cannot be destroyed. Burning "too early" can leave you stuck, and that is intended puzzle design: burn the thing next to a shadow before it wakes, and you may have nothing left to burn when it does.

### 3.6 Undo, win, determinism

- **Undo.** The whole game state is snapshotted after every valid action. Undo restores the previous snapshot and is unlimited and free.
- **Win.** Step onto the final room's `exit`. The final act decides whether the player stops the clock or lets it burn **(TBD)**.
- **Determinism.** Same level + same action list = same result, always. This is required for the solver, the unit tests, and the Python reference cross-check. Randomness (like dialogue mood) lives only in presentation and dialogue code, never in `core/`.

## 4. Characters

### The fire spirit
- **Name: TBD** (candidates: Cinder, Vesper, Ember).
- **Rules role:** she carries ash between hours. Her behavior is deterministic and follows ash links exactly. Her personality lives ONLY in presentation and dialogue.
- **The laugh:** plays whenever she moves something. Pitch, direction or reverb hints at which hour the ash landed in. Silence means she is far away.
- **Entrance:** announced by sound before sight. She flashes past as a streak of light with an ember trail and briefly lights the room.
- **Personality:** playful, mischievous, dangerous, in the spirit of a classic trickster villain. She teases the player when a puzzle is solved. Her mood changes per level (see section 8).
- **Arc:** Act 1 she helps. Act 2 the player realizes the shadows come from the hours she burned. Act 3 she is not escaping the clock, she is finishing it. **(default)** She is an ally who slowly turns.

### The shadow creatures
- **Concept:** burnt-out hours. Drifting ash-smoke figures with a hollow or a clock face where a head would be.
- **Their glow:** **glowing ash at the tips of the head and limbs, like a coal that glows when you blow on it but is not on fire.** This is their ONE glow effect (there is no separate core glow).
  - Color: dim, deep red-orange, clearly LESS saturated and less bright than the spirit's fire. Fire stays the only strongly saturated warm color.
  - Readable signal: dormant shadows barely glow, active shadows glow brighter, with a slow pulse.
- **Build:** one silhouette sprite or mesh, plus a shard-particle swirl and the ember-tip emissive shader, reused 2 to 3 times with different tints and sizes. Must look ORIGINAL and not like any existing franchise's creatures.
- **Build order:** silhouette, then shard swirl, then ember-tip glow, then extra variants.
- **Story link:** they are what fire leaves behind, so the villain and the monsters are one story.

## 5. Visual and audio direction

- **Format:** 2.5D. A 3D lit environment, a controlled camera, billboard or silhouette characters. Fire and shadows are VFX (ribbons, particles, shaders), not frame-animated characters. **Fallback if the pipeline test fails: layered 2D.**
- **Setting: a burnt clock tower.** One giant clock-face diorama with six rooms around it. The tower is a place where fire already happened: soot-darkened walls, scorch marks, charred beams, drifting smoke. Brick is a texture swap on the shared room shell, not a rebuild.
  - **Do not make the world burn.** No ambient flames or glowing wood everywhere. That breaks "one warm accent on a cold world" and hides which puzzle objects are flammable.
  - **Decorative ash** (rubble, dust lying around): gray, matte, no glow.
  - **Gameplay `ASH` state** (burned remains and ash_path): a visible ember glow, so players never confuse it with decoration.
  - **Time made visible:** hours the sun has already passed show more soot and smoke, so the room itself shows time running out.
- **Color:** cold muted world (slate blue, ash gray). Fire is the ONLY strongly saturated warm color. **Gears and metalwork are dark steel or cold bronze, never warm brass or brown,** so they do not compete with the flame. Each hour has its own color grade from dawn to dusk. Exact hex codes: TBD, frozen after the style test and recorded in `docs/STYLE_GUIDE.md`.
- **The gears are the clock.** The dial ring behind the gears is the sun marker. **The gears rotate one tick per valid action** (listening to the `action_applied` event), so time is visible in the room itself.
- **Silhouette first:** every character reads as a flat black shape.
- **Atmosphere:** fog, parallax layers, floating embers, vignette, bloom.
- **Signature camera moment: the ripple shot.** When one burn changes several rooms, the camera follows the ash from hour to hour in one quick move. NEVER cut.
- **Camera language:** wide establishing shots, medium action shots, a low angle for her entrance, brief letterbox bars for cinematic moments.
- **Audio:** a recurring laugh motif that changes with her mood (amused, annoyed, triumphant); ticking clock and bells; traditional-instrument atmosphere (guzheng, erhu, dizi) under a loop that intensifies as shadows increase; silence before big moments. Do NOT imitate any real actress's voice.

## 6. Technical architecture

**Engine: Godot 4.4.1 stable, GDScript. Renderer: Forward+ for the 2.5D look (if a laptop struggles, switch that person to Compatibility locally, but never commit the project setting).**

The puzzle logic knows nothing about graphics.

```
DATA          GameState: hours, terrain, objects (id, type, state, flammable, ash_link, links_to), shadows, player, counters
SYSTEMS       TurnManager   (validates and applies an action, advances the sun, activates shadows)
              AshTransfer   (applies ash links)
              SnapshotStack (undo)
              LevelLoader / LevelValidator   (core/, Anosha)
              Solver (BFS) / validate_levels (tools/, Mariam)
PRESENTATION  listens to events from the logic, plays animation, sound and VFX
```

### 6.1 Level data format (`levels/data/*.json`): working example

This level is solvable. **Copy this structure for new levels.**

```json
{
  "id": "L01_first_crate",
  "title": "Something Warm",
  "act": 1,
  "spirit_mood": "amused",
  "mood_weights": { "amused": 0.6, "annoyed": 0.2, "triumphant": 0.2 },
  "grid": { "w": 5, "h": 5 },
  "sun": { "start_index": 0, "actions_per_hour": 3 },
  "rooms": [
    { "hour": 12, "terrain": [".....", ".....", ".....", ".....", "....."] },
    { "hour": 2,  "terrain": ["..~..", "..~..", "..~..", "..~..", "..~.."] }
  ],
  "player": { "hour": 12, "slot": [0, 2] },
  "objects": [
    {
      "id": "crate_a", "type": "crate", "hour": 12, "slot": [2, 2],
      "state": "INTACT", "flammable": true,
      "ash_link": { "hour": 2, "slot": [2, 2], "becomes": "ash_path" }
    },
    {
      "id": "stair_12", "type": "stair", "hour": 12, "slot": [4, 2],
      "state": "INTACT", "flammable": false,
      "links_to": { "hour": 2, "slot": [0, 2] }
    },
    { "id": "exit_1", "type": "exit", "hour": 2, "slot": [4, 2], "state": "INTACT", "flammable": false }
  ],
  "shadows": [],
  "par_actions": 10,
  "spirit_lines": { "on_burn": "Oh, that was fun.", "on_solve": "You're no fun when you win." }
}
```

**Solution (10 actions):** `move:right, burn:right, move:right, move:right, move:right, interact, move:right, move:right, move:right, move:right`.
Why it works: in hour 12 you burn the crate, which turns to rubble (walkable) and drops an `ash_path` onto the chasm at `[2,2]` in hour 2. You walk through the rubble, take the stair, then cross the chasm on the ash path to the exit.

Field notes:
- `shadows` entries look like `{ "id": "sh_1", "hour": 2, "slot": [3, 1] }`.
- `spirit_mood` is the level's base mood; `mood_weights` and `act` are used only by dialogue code (section 8). Both are optional (default: mood `amused`, act `1`).
- `par_actions` should come from the solver's shortest solution.
- Rooms not listed in `rooms` are all floor.

### 6.2 Logic API contract (`core/`, owner: Anosha)

Everyone codes against these names. Changes need team agreement and an update to this file.

```gdscript
# core/game_state.gd  (RefCounted, plain data, deep-copyable)
#   func duplicate_deep() -> GameState
#   func hash_key() -> String          # canonical string of the full state, used by the solver
# core/turn_manager.gd
func load_level(data: Dictionary) -> GameState
func apply_action(state: GameState, action: Dictionary) -> Dictionary
# action examples:
#   {"type": "move", "dir": "up"|"down"|"left"|"right"}
#   {"type": "interact"}
#   {"type": "burn", "dir": "up"|"down"|"left"|"right"}
#   {"type": "wait"}
# returns: {"ok": bool, "events": Array[Dictionary], "state": GameState, "reason": String}
#   ok == false means the action was invalid and FREE: state is unchanged.
func undo(stack) -> GameState
func is_hour_passed(state, hour: int) -> bool
func legal_actions(state) -> Array      # only VALID actions (never invalid ones)
```

### 6.3 Event contract (logic → presentation, UI, audio)

Each event is a Dictionary with a `"type"` key. Presentation, UI and audio ONLY react to these.

| type | extra fields | used by |
|---|---|---|
| `moved` | `from_hour`, `from_slot`, `to_hour`, `to_slot` | presentation |
| `burned` | `id`, `hour`, `slot` | VFX, audio, ripple camera |
| `ash_moved` | `from_hour`, `to_hour`, `to_slot`, `becomes` | ripple shot, laugh direction |
| `shadow_appeared` | `id`, `hour`, `slot` | VFX, audio |
| `shadow_destroyed` | `id`, `hour` | VFX, audio |
| `action_applied` | `actions_used` | gear tick, ticking audio |
| `sun_advanced` | `from_index`, `to_index` | UI dial, color grade |
| `hour_passed` | `hour` | shadowing, soot level, music intensity |
| `action_rejected` | `reason` | UI feedback |
| `undo_done` | none | UI, gears tick back |
| `level_won` | `actions_used` | spirit tease, UI |
| `level_failed` | `reason` | UI |

### 6.4 Test case format (`tests/cases/*.json`)

Shared by Anosha's GDScript tests and Mariam's Python reference, so both implementations are checked against the same cases.

```json
{
  "name": "L01 solution wins in 10",
  "level": "L01_first_crate",
  "actions": ["move:right","burn:right","move:right","move:right","move:right","interact","move:right","move:right","move:right","move:right"],
  "expect": { "won": true, "failed": false, "actions_used": 10 }
}
```

Action shorthand (test files only): `move:<dir>`, `burn:<dir>`, `interact`, `wait`. For rejection tests use `"expect": { "rejected_at": 3, "reason": "shadow_blocks" }`.

### 6.5 Room scene contract (Noor's rooms ↔ Anosha's room view)

- All six rooms share ONE scale and ONE origin (the room center), built from one reusable room shell.
- Each room has a `Slots` node containing 25 `Marker3D` children named `slot_0_0` ... `slot_4_4` (`slot_<x>_<y>`), placed at the center of each grid cell. Anosha's `room_view.gd` positions objects by reading these markers.
- Models are exported as `.glb`. Camera and lights are rebuilt in Godot (Blender light values do not transfer).

## 7. Repository layout and ownership

```
pyre-of-the-hours/
├── project.godot
├── docs/                     STYLE_GUIDE.md (Noor), REQUESTS.md, AI_LOG.md, PROJECT_CONTEXT.md
├── core/                     [ANOSHA]  pure logic, no Node/graphics (includes level_loader, level_validator)
├── tests/                    [ANOSHA]  run_tests.gd and Anosha's cases
│   └── cases/                [MARIAM]  shared JSON test cases (exported from the Python reference)
├── tools/                    [MARIAM]  solver.gd, validate_levels.gd
├── reference/python/         [MARIAM]  Python reference implementation (read-only for others)
├── presentation/             [ANOSHA]  event bus, game controller, room view, ripple camera, menus
├── levels/data/              [MARIAM]  puzzle JSON files
├── dialogue/                 [MARIAM]  spirit lines, dialogue picker, AI generation
├── ui/                       [MARIAM]  HUD, dial, undo button, dialogue box
├── art/                      [NOOR]    room shell, backgrounds, textures, models (.glb), concept
├── vfx/                      [NOOR]    fire, ash, smoke, shadow shaders, gear spin
├── audio/                    [NOOR]    laugh, ticking, bells, music
└── marketing/                [NOOR]    trailer assets, screenshots
```

**One owner per scene file.** Never edit another person's `.tscn`. Ask them.

## 8. AI use

- **In the process:** AI for code, art, voice, music, writing, trailer. Hackathon AI-content rules are confirmed.
- **In the game (default = A):**
  - **A. The fire spirit's lines**, generated within a fixed personality, with cached fallback lines.
  - B. AI-proposed puzzles validated by the solver (only if A is done and time remains).
- **Log from day 1** in `docs/AI_LOG.md`: key prompts, before and after images, what was rejected and why.
- **Style discipline:** freeze the style guide, attach one reference image to every art prompt, reject and regenerate off-style output.
- **Originality:** no verbatim source code. Designs are original, inspired by references and not copied.

### 8.1 Spirit dialogue design (per-level personality)

Models drift into whatever mood they started in. To stop her getting stuck in one personality:

- **Every call is stateless.** No chat history. Each call sends: a fixed system prompt, the variables below, a one-line game state, and the last 3 lines she said (to avoid repeats).
- **Each level has a base personality:** the level JSON `spirit_mood` field, hardcoded per level.
- **Optional variety:** `mood_weights` (for example act 1 = 60% amused, 20% annoyed, 20% triumphant). The mood is picked **only in `dialogue/` code, never in `core/`**, with a **seeded** random pick (seed from level id + trigger count) so demos are reproducible.
- **The story arc stays fixed:** act 3 is mostly menacing no matter what the dice say. Act sets the allowed moods; weights only vary inside them.
- **Cached fallback lines use the same mood tags,** so a fallback still matches the mood.

System prompt shape:

```
You are the fire spirit. Voice sheet: {voice_sheet}
Act: {act}. Mood for this line: {mood}. Trigger: {trigger}. Game: {one_line_state}.
Examples for this mood: {3_example_lines}
Rules: max 15 words, stay in character, never mention being an AI, no real-world references.
Do not repeat: {last_3_lines}
```

## 9. Scope and cut order

**Target:** 6 hours, 8 to 10 puzzles, one fire character, one shadow design reused 2 to 3 times, about 15 to 20 lines for her, an intro, a 45 to 60 second trailer.

**Cut in this order if time runs short:** keys/torches (already cut) → extra puzzles → secondary VFX → extra shadow variants → in-game AI features.
**NEVER cut:** core logic, undo, the ripple shot.

## 10. Open decisions

| # | Decision | Default for now | Owner |
|---|---|---|---|
| 1 | Engine and version | Godot 4.4.1 | Done (confirm all install it) |
| 2 | Spirit's name, ally-who-turns vs rival | Name TBD, ally who turns | Mariam proposes, team votes |
| 3 | Exact palette and frozen style | After style test | Noor |
| 4 | Sun end condition | Fail on completing dial (decided) | Done |
| 5 | In-game AI feature | A (spirit dialogue) | Mariam |
| 6 | Judging criteria and submission format | Find out from organizers | Anosha |
| 7 | Final act: stop the clock or let it burn | Two endings if time, else one | Team |

## 11. Clarifications (decided by Anosha, part of the spec)

1. The Python reference is `pyre_logic/` (not `reference/python/`). The rejection reasons are listed in item 11 below. Do not edit anything in `pyre_logic/`.
2. Undo emits only `undo_done` (NOT `action_applied`). Undo is always allowed, including out of a won or failed state, and is free.
3. After `level_won` or `level_failed`, every action (including `wait`) is rejected with reason `level_over`. Undo still works.
4. `wait` is rejected if it would wake a shadow on the player's tile (same rule as any other action).
5. A burn's 4-neighborhood excludes the burned slot itself.
6. `level_failed` has reason `dial_complete`.
7. `GONE` is reserved and unused: treat it as an empty slot.
8. The validator rejects a shadow placed on a wall. A shadow on a chasm is allowed.
9. Test command on Anosha's machine: `godot_console --headless -s tests/run_tests.gd`
10. Shared cases (`tests/cases/*.json`) arrive later through `phase-1`. The runner accepts a file containing a LIST of cases (a single object is also fine); resolves `level` as an id by looking in `levels/data/<id>.json`, then `tests/cases/fixtures/<id>.json`, then `tests/fixtures/<id>.json`; treats `rejected_at` as a 0-based index into `actions`; and matches rejection `reason` strings exactly.
11. Rejection reasons (agreed; the GDScript core and `pyre_logic/` use these exact strings):
    - `move`: `out_of_bounds`, `blocked_terrain`, `blocked_object`, `shadow_blocks`
    - `interact`: `not_on_stair`, `arrival_blocked`
    - `burn`: `nothing_to_burn`, `not_flammable`, `not_intact`, `ash_target_occupied`
    - any action: `shadow_wakes_on_you`
    - after win or fail: `level_over`
    - malformed action (unknown type or direction): `unknown_action`
12. `apply_action(state, action)` never modifies the state passed in. On success it returns a NEW deep copy with the action applied, the action counter +1, and `action_applied` as the LAST event. On rejection it returns `ok = false`, the original state unchanged, a `reason`, and `events` containing only `{"type": "action_rejected", "reason": ...}`.
