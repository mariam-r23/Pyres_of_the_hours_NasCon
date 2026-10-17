# DEVELOPMENT_FLOW.md: How we build Pyre of the Hours (v2)

> Paste this together with `PROJECT_CONTEXT.md` and your own workplan into every new AI session.

## What changed in v2
- `tools/` (solver and level validator) and `reference/python/` are now owned by **Mariam**. Menus moved to **Anosha**.
- Testing section updated: shared JSON test cases, Python reference cross-check.

## 1. Branch structure

```
main                      ← stable, always runs, only receives phase merges
 └── phase-1              ← integration branch for Phase 1 (playable vertical slice)
      ├── anosha/core         ← Anosha: logic, presentation glue, ripple camera, menus
      ├── mariam/puzzles-ui   ← Mariam: puzzles, dialogue, UI, solver/validator tools, Python reference
      └── noor/art-audio      ← Noor: art, VFX, audio, trailer
```

(Branch names are unchanged even though folder ownership moved. Don't rename branches mid-project.)

Later: when phase 1 is merged to `main`, create `phase-2` from `main` and repeat the same pattern.

**Flow of code:** person branch → Pull Request → `phase-1` → (when phase is done and tested) → `main`.

### Rules
1. **Nobody commits directly to `main` or `phase-1`.** Always a Pull Request.
2. **Integrator = Anosha.** She reviews and merges PRs into `phase-1`, and merges `phase-1` into `main` at the end of each phase. Mariam is backup integrator if Anosha is blocked.
3. Each person works ONLY on their own branch and in their own folders (ownership map in `PROJECT_CONTEXT.md` section 7).
4. **Never merge code you haven't run.** The project must open and run after every merge.
5. **One owner per scene file.** Never edit another person's `.tscn`. Ask them.
6. If you need a change in someone else's area, add it to `docs/REQUESTS.md`: `[date] [from] → [to]: request`.
7. Pull from `phase-1` into your branch at least twice a day: `git fetch && git merge origin/phase-1`.

## 2. One-time setup (Anosha, first 30 minutes)

```bash
# 1. Create the repo on GitHub: pyre-of-the-hours (add Mariam and Noor as collaborators)
git clone <repo-url> && cd pyre-of-the-hours

# 2. Create a Godot 4.4.1 project in this folder, then add:
#    .gitignore (Godot template: ignore .godot/, keep *.import, ignore export builds)
#    folder skeleton from PROJECT_CONTEXT.md section 7 (a .gitkeep in each empty folder)
#    docs/PROJECT_CONTEXT.md, docs/AI_LOG.md, docs/REQUESTS.md

git add . && git commit -m "chore: project skeleton"
git push origin main

# 3. Create the branches
git checkout -b phase-1 && git push -u origin phase-1
git checkout -b anosha/core phase-1 && git push -u origin anosha/core
git checkout -b mariam/puzzles-ui phase-1 && git push -u origin mariam/puzzles-ui
git checkout -b noor/art-audio phase-1 && git push -u origin noor/art-audio
```

Then in GitHub settings: protect `main` and `phase-1` (require a Pull Request).
Mariam and Noor: `git clone`, then `git checkout <your-branch>`.

**Large files (art, audio, .glb):** keep individual files small (compress PNGs, OGG not WAV). If the repo grows over about 500 MB, tell Anosha and set up Git LFS for `art/` and `audio/`.

## 3. Commit conventions

- Commit after EVERY working step, so you can roll back.
- Format: `type(scope): message`. Types: `feat`, `fix`, `art`, `audio`, `docs`, `chore`, `test`.
- Examples: `feat(core): add ash transfer`, `art(hour-4): background v2`, `fix(ui): undo button not disabling`.
- Push at least at the end of each work session.

## 4. Pull request checklist (copy into every PR)

- [ ] The project opens in Godot 4.4.1 with no errors in the output panel
- [ ] I ran the tests (`godot --headless -s tests/run_tests.gd`) and they pass
- [ ] If I added or changed a level: `godot --headless -s tools/validate_levels.gd` passes (valid and solvable)
- [ ] I only changed files in my own folders (or I listed the exceptions here)
- [ ] I did not hand-edit anyone else's scenes
- [ ] New assets match the style guide (and are logged in `docs/AI_LOG.md`)
- [ ] I listed any library or asset used, with its license

## 5. Phases and schedule

### Phase 0: Foundations (first 2 to 3 hours, all together)
- Everyone installs **Godot 4.4.1**. Same version, no exceptions.
- Anosha does the repo setup (section 2).
- Team reads `PROJECT_CONTEXT.md` v2 and confirms the open decisions table.
- Noor starts generating style options. Mariam starts the spirit's name and voice sheet.

### Phase 1: Vertical slice (Day 1 to Day 2 morning) → branch `phase-1`
Goal: **one playable level (L01), 2 hours linked by a stair, spirit laugh playing, undo working, placeholder art.**
- Day 1 AM: Anosha's headless logic and tests; Mariam's port of her Python levels to the JSON format plus exported test cases; Noor's style options and pipeline test room.
- Day 1 PM: Logic merged (**including `legal_actions` and `hash_key`**, which Mariam's solver needs). Presentation glue connects events to placeholders. Mariam's solver and HUD. Noor's first fire VFX and laugh draft.
- Day 2 AM: Phase 1 demo to the team. **Merge `phase-1` → `main`** once it runs cleanly.

### Phase 2: Full content (Day 2 PM to Day 3 midday) → branch `phase-2` (created from `main`)
Goal: **all 6 hours, shadows, 8 to 10 puzzles, real art, spirit lines, ripple shot.**
**FEATURE FREEZE at Day 3 midday.**

### Phase 3: Polish and ship (Day 3 afternoon) → straight into `main` via small PRs
Goal: spirit arc, bug fixes, trailer, build export, submission.
Only bug fixes and polish. No new features.

## 6. Daily rhythm

| When | What |
|---|---|
| Start of day (10 min) | Standup: what I finished, what I'm doing, what blocks me. |
| Midday | Everyone merges working work into the phase branch. |
| End of day (15 min) | **Build check:** Anosha pulls the phase branch, opens the project, plays a level, and confirms it runs. Post a screenshot in the group chat. |

If the build check fails, **fixing the build is everyone's top priority** before any new work.

## 7. Using AI tools well

| Tool type | Use for |
|---|---|
| Chat assistants (Claude, ChatGPT, Gemini) | Design, architecture, writing, puzzle ideas, debugging explanations, prompts for art tools |
| Agentic tools (Claude Code, Codex CLI, Gemini CLI, Antigravity) | Editing scripts inside the repo |
| Image generation | Backgrounds, textures, concept art, always with the style guide and reference image attached |

**Agent rules**
1. One agent per person, on that person's branch only.
2. Scripts only (`.gd`, `.json`). Scenes, resources and editor wiring are done by hand in the Godot editor.
3. Commit after every working step.
4. Give the agent small tasks and ask it how to test each one.
5. Read the code it writes. If you can't explain it, ask the agent to explain it before committing.

**Starting any AI session**
1. Paste `PROJECT_CONTEXT.md`.
2. Paste `DEVELOPMENT_FLOW.md`.
3. Paste your own `<NAME>_WORKPLAN.md`.
4. Say which task from the workplan you are on.

**Keep the bible current.** If a rule changes, edit `PROJECT_CONTEXT.md`, tell the group, and re-paste it. AI sessions forget.

## 8. AI log (`docs/AI_LOG.md`)

Everyone adds entries as they go. This is also material for the submission and the trailer.

```
### [date] [name] [what you made]
Tool: ...
Prompt: ...
Result: kept / rejected
Why: ...
(attach before/after images when relevant)
```

## 9. Testing

- **Logic tests (Anosha):** `godot --headless -s tests/run_tests.gd` runs plain GDScript test cases (no addons). It also runs every JSON case in `tests/cases/`. Every bug in core logic gets a new test.
- **Shared test cases (Mariam):** Mariam exports cases from her Python reference into `tests/cases/*.json` (format in `PROJECT_CONTEXT.md` 6.4). Anosha's GDScript must pass all of them. If the two implementations disagree, section 3 of the context file decides, and the wrong one is fixed.
- **Level check (Mariam):** `godot --headless -s tools/validate_levels.gd` loads every level in `levels/data/`, validates the format (using Anosha's `core/level_validator.gd`), runs the solver, and prints: id, valid, solvable, shortest solution length, and `par_actions`. Any level that fails does not get merged.
- **Playtest:** at least one person who did not build a level plays it before it is merged.

## 10. Definition of done

A task is done when:
1. It works, and you ran it.
2. Tests pass (if it touches logic or levels).
3. It is committed and pushed on your branch.
4. A PR is open (or merged) with the checklist ticked.
5. Anything others need to know is written in the PR or in `docs/REQUESTS.md`.

## 11. Cut order (if we run short)

Keys/torches (already cut) → extra puzzles → secondary VFX → extra shadow variants → in-game AI features.
**Never cut:** core logic, undo, the ripple shot.

## 12. Submission checklist (Day 3 end)

- [ ] Exported build runs on a clean machine (or a browser link, depending on the rules)
- [ ] 45 to 60 second trailer exported
- [ ] README with the pitch, controls, team, AI usage summary and asset licenses
- [ ] `docs/AI_LOG.md` is up to date
- [ ] Tagged release: `git tag v1.0 && git push --tags`
