Create README.md at the repo root with exactly the content below (overwrite if it exists). Also hide the Credits button in the main menu and rename ui/fonts/OFL_Cinzel.txt.txt and OFL_Cormorant.txt.txt to .txt if not done yet. Run tests, commit, push on anosha/core. Stop.

# Pyre of the Hours

*A burnt clock-tower. Twelve hours of the same day. A fire spirit who wants to be let out.*

Pyre of the Hours is a turn-based puzzle crawler made for the NaSCon game jam (themes: **Fire, Shadow, Time**). Every room of the tower is a different hour of the same day, arranged around a giant clock. When you burn something in one hour, the fire spirit **Cinder** carries its ash into another hour, where it becomes something new: a crate's ash can become a path across a chasm hours later. But every action moves the sun forward, and the hours it has passed wake up with shadows.

Solve all ten levels, and at the end decide: **WIND** the clock and keep the day, or **LET IT BURN**.

## How to run

1. Install **Godot 4.4.1** (standard build, not .NET).
2. Open Godot → Import → select this folder's `project.godot`.
3. Press **Play** (F5), or run from a terminal:
```
   godot_console --path .
```

## Controls

| Key | Action |
|---|---|
| Arrow keys | Move |
| B, then an arrow | Burn the object in that direction |
| E | Use a stair |
| Space | Wait (let the sun move) |
| Z | Undo (unlimited) |
| R | Restart level |
| Esc | Cancel burn / pause menu |
| Any key during a camera shot | Skip it |

## How it plays

- **Ash travels in time.** Burnable objects (crates, doors, bridges) are linked to a tile in another hour. Burn one, and Cinder flies its ash there, turning it into a path or a new object.
- **The sun is your clock.** Every action uses time. Every few actions the sun moves to the next hour, and the hour it leaves behind turns darker and sootier.
- **Shadows wake in passed hours.** They block your way. Fire destroys any awake shadow next to the object you burn, but only once it has woken.
- **Run out of day and you fail.** Undo is free, so experiment.
- **Cinder talks.** She comments on what you do, with moods that change across the three acts.

## Team

- **Anosha Shams**: integration, core game logic, presentation (camera, ripple shot, rooms, shadows, menus, UI wiring), tests
- **Mariam**: level design (L01 to L10), Cinder's dialogue and picker, solver and validation tools
- **Noor**: art (hour paintings, Cinder portraits), voice lines and laughs

## How AI was used

- **Code:** written with Claude Code under our direction and review, in small tested steps (300+ automated tests).
- **Art and voice:** the hour paintings, Cinder's portraits and her voice lines were AI-generated and curated by Noor.
- **Dialogue:** drafted with AI help and edited by Mariam to fit Cinder's voice rules.
- **Puzzles:** designed by Mariam; every level is checked by a solver to be solvable at par.

## Project structure

```
core/          pure game rules (no nodes): state, turns, sun, ash, undo, level loader
presentation/  everything you see: rooms, camera, ripple shot, spirit, menus
ui/            HUD, sun dial, dialogue box, ending screen, fonts
dialogue/      Cinder's lines and the line picker
levels/data/   the 10 levels (JSON)
tools/         level validator and solver
reference/     Python reference implementation used to cross-check the rules
art/, audio/   paintings, portraits, voice lines
tests/         automated tests
```

## Running the tests

```
godot_console --headless -s tests/run_tests.gd
godot_console --headless --path . --script res://dialogue/tests/run_picker_tests.gd
```

## Credits and licenses

- Fonts: **Cinzel** and **Cormorant Garamond**, SIL Open Font License (see `ui/fonts/`).
- Engine: **Godot 4.4.1**, MIT license.
