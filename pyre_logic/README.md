# Pyre of the Hours: logic layer

Headless, deterministic game logic: rules, level loader, undo and a solver.
No graphics, audio, input, timing or engine code. Python 3.9+, no dependencies.

    python -m unittest discover -s tests -v        # run the 46 tests
    python play.py levels/level1_first_spark.json   # play in the terminal
    python play.py levels/level2_wake_the_shadow.json --solve

## Files
- `pyre_logic/model.py`   data model: Level (static), GameState (dynamic), objects, shadows, actions, type table
- `pyre_logic/rules.py`   `apply(state, action) -> Result(valid, state, events, reason)`; never mutates its input
- `pyre_logic/loader.py`  JSON loading; errors name the field, e.g. `objects[1].ash_link.hour: ...`
- `pyre_logic/game.py`    `SnapshotStack` (undo) and `Game` (what a scene script holds)
- `pyre_logic/solver.py`  BFS: shortest solution, or proof of unsolvable
- `levels/`               1 tutorial, 2 ripple + shadow, 3 intentionally unsolvable
- `tests/test_logic.py`   the executable spec

## Rules as implemented
- 6 hours (index 0-5 = 12, 2, 4, 6, 8, 10 o'clock). Each level has one grid size (width x height) shared by all hours.
- Terrain: `.` floor, `#` wall, `~` chasm, `E` exit. A chasm is walkable only if a non-blocking object with `fills_chasm` is on it.
- Objects have a type, a state (INTACT / ASH / GONE) and an optional ash link. The type table says, per state, whether it blocks movement or fills a chasm. Add or override types in the level JSON under `"types"`.
- Actions: move (N/E/S/W), burn (N/E/S/W), wait. Invalid actions change nothing and cost nothing.
- Burn: the adjacent tile must hold an INTACT flammable object. It becomes ASH; its ash link creates a new INTACT object (id `<source id>>ash`) at the link target. Every ACTIVE shadow on or next to the burned tile is destroyed.
- Sun: `sun_hour = min(action_count // actions_per_hour, 6)`. Hour i is passed when i < sun_hour. Shadows in an hour activate the moment it is passed.
- Shadows block the tile they stand on while ACTIVE.
- Doorways are paired floor tiles. Stepping onto one puts the player on its partner (both ends must be enterable).
- Outcome order after each valid action: win (stepped onto exit) > caught (a shadow woke on your tile) > day ended (sun_hour reaches 6).

## Decisions I made where the bible was silent (please confirm)
1. The sun advances one hour every `actions_per_hour` actions (default 3), not every action. One hour per action would leave only 6 actions per level.
2. Doorways link two tiles; the player moves between hours only through them.
3. Fire destroys active shadows on the burned tile too, not only the 4 neighbours.
4. Shadows only die while ACTIVE. Burn before a shadow wakes and it will wake later and block you, so waiting can be the right move (level 2 teaches this). That is why the solver includes `wait`.
5. `GONE` exists but no built-in action produces it yet.
6. Burn only works on the tile next to you, in your own hour.

## Presentation hook
`apply()` returns events for the future animation/sound/camera layer to listen to:
Moved, DoorwayTraversed, Burned, AshMoved, SunAdvanced, HourPassed, ShadowActivated, ShadowDestroyed, LevelWon, LevelFailed.
`AshMoved` is the ripple shot and the laugh trigger.

## Porting to Unity (C#) or Godot (GDScript)
Port the tests first, then make them pass. Keep `apply()` pure (clone the state, return the new one). Keep the level JSON format as is; both engines can read it.
