# NOOR_WORKPLAN.md (v2)

**Role:** Art direction, style guide, rooms, VFX, audio, trailer.
**Branch:** `noor/art-audio` (PRs into `phase-1`)
**Folders you own:** `art/`, `vfx/`, `audio/`, `marketing/`, `docs/STYLE_GUIDE.md`.
**Do not touch:** `core/`, `tests/`, `tools/`, `reference/`, `presentation/`, `levels/data/`, `dialogue/`, `ui/`.

> Paste order for any AI session: `PROJECT_CONTEXT.md` → `DEVELOPMENT_FLOW.md` → this file → "I am on task X".

## What changed in v2
- Art direction is now a **burnt clock tower** (soot, scorch marks, charred beams, smoke), with rules so it does not break "one warm accent".
- **Gears are cold metal** (dark steel or cold bronze) and **tick once per action**. The dial ring is the sun marker.
- **Shadow creatures get ember-tip glow** (head and limbs) as their one glow effect.
- **Room contract:** one shared room shell, one scale and origin, 25 `slot_x_y` markers, `.glb` export, camera and lights rebuilt in Godot.
- Hackathon AI rules are confirmed, so no need to check them again (still do NOT imitate any real actress's voice).

## Why this lane matters

The pillar is "one warm accent on a cold world", so **the look and the laugh are what the judges remember**. Your work is front-loaded: the style must be frozen early so every other asset can match it. Audio and trailer are lighter early and heavier on Day 3.

## Notes on your Blender room (what to fix)

- The clock-tower read is strong: gears and pillars say "clock" instantly, and the gap between the two plinths is perfect for a bridge puzzle. Keep it.
- **Gears:** the brass and brown are warm and saturated, so they compete with the fire. Push them to dark steel or cold bronze. Flame must be the only warm color.
- **Dial ring behind the gears = the sun marker.** Make the gears rotate one tick per valid action (event `action_applied`; rotate back on `undo_done`).
- **Gameplay grid:** the room needs a 5x5 slot grid. Add the markers (below), and use one scale and origin (room center) for all six rooms.
- **Reuse one room shell** with a different color grade per hour. This saves a lot of time.

## Deliverables

### Phase 0 / Phase 1, Day 1 AM: Style guide (do this first)
- [ ] Generate **5 to 8 style options** with an image model. Starter prompt:
  ```
  Painted 2.5D game environment, the interior of a burnt-out clock tower, soot-darkened
  walls, charred beams, scorch marks, drifting smoke, dark steel gears, muted slate-blue
  and ash-gray palette, a single warm orange fire accent, soft fog, cinematic depth,
  no text, no characters, 16:9, wide establishing shot.
  ```
- [ ] Team picks one (group vote). Log all options, kept and rejected, in `docs/AI_LOG.md`.
- [ ] Freeze it as a one-page `docs/STYLE_GUIDE.md`: exact hex colors (cold palette, the warm accent, shadow black, the dimmer coal red-orange, gameplay-ash ember), lighting direction, the "one warm accent" rule, fog and bloom values, the 6 hour color grades (dawn to dusk) with soot level per hour, fonts (give Mariam the names), and **one reference image to attach to every art prompt**.
- [ ] Post the frozen guide in the group chat. Everyone's work matches this from now on.

**Burnt-tower rules to put in the guide:**
- The tower is a place where fire ALREADY happened. Do not make it burn: no ambient flames, no glowing wood everywhere.
- Decorative ash and rubble: gray, matte, no glow.
- Gameplay `ASH` objects (burned remains, ash_path): visible ember glow, so they never read as decoration.
- Passed hours get more soot and smoke (time running out, visible in the room).
- Brick is a texture swap on the shared shell, not a rebuild.

### Phase 1, Day 1: Pipeline test and room shell
Build one test room end to end to prove the 2.5D approach:
- [ ] The room shell: floor, plinths, chasm gap, pillars, cold-metal gears, dial ring. Textures AI-generated or hand-painted, soot-darkened.
- [ ] **25 `Marker3D` nodes under a `Slots` node, named `slot_0_0` ... `slot_4_4`** (`slot_<x>_<y>`, x to the right, y toward the viewer or downward per the top-down view), at the center of each cell. One scale, origin at the room center, identical in all six rooms.
- [ ] Placeholder character (a flat black silhouette billboard), a warm point light, fog, bloom (WorldEnvironment), a gentle camera move. **Rebuild camera and lights in Godot; Blender light values don't transfer.**
- [ ] Export the shell as **`.glb`** into `art/`.
- [ ] Team reviews it. **If it looks good, commit. If not, fall back to layered 2D** (parallax layers per hour) and update `PROJECT_CONTEXT.md` section 5. Decide by the end of Day 1.
- [ ] Save as `art/room_shell.tscn` (you own it, nobody else edits it). Tell Anosha the marker naming so `room_view.gd` can use it.

### Phase 1, Day 1 PM to Day 2 AM: First fire, gears and the laugh
- [ ] **Fire VFX (`vfx/`):** burn effect (flames on an object, about 1 second), ember particles, a bright ember-trail streak for the spirit's flash-past. Warm saturated orange only, the only saturated color in the world.
- [ ] **Gear tick:** `vfx/gear_spin.gd` listens to `EventBus.action_applied` and rotates the gears one tick (and back on `undo_done`). Edit scripts only; do the node wiring in the editor.
- [ ] **The laugh, v1 (`audio/`):** 3 laugh variants (amused, annoyed, triumphant). OGG format, e.g. `laugh_amused_01.ogg`. Do NOT imitate any real actress.
- [ ] **Audio hooks:** ticking sound, a bell, a fire crackle, a "shadow appears" sting. Placeholder quality is fine for Phase 1.
- [ ] Give Anosha the finished scenes and files with a one-paragraph note on how to trigger each (she connects them to `EventBus`; you don't edit `presentation/`).

### Phase 2: All 6 hours and the characters
- [ ] **6 hours from the one room shell:** same geometry, different color grade and soot level per hour (dawn to dusk). Reject and regenerate anything off-style.
- [ ] **Clock-face diorama:** the master image or scene showing all six rooms around the dial.
- [ ] **Fire spirit:** face and silhouette (original, playful, readable as a flat black shape), plus a few expressions or poses (amused, annoyed, triumphant, menacing). She is mostly light and VFX, with a face in dialogue.
- [ ] **Shadow creature:** ONE silhouette (ash-smoke figure, clock-face or hollow head). Build order: silhouette → shard-particle swirl → **ember-tip glow shader** → variants.
  - **Ember tips:** glowing ash at the ends of the head and limbs, like a coal you blow on: glowing but not on fire. This is the ONLY glow on the shadow (no separate core glow).
  - Color: dim deep red-orange, clearly less saturated and less bright than the spirit's fire.
  - Behavior: dormant shadows barely glow, active shadows glow brighter, slow pulse. Expose a `glow_level` parameter so Anosha's code can set dormant vs active.
  - 2 to 3 variants by tint and size only. Must not resemble any existing franchise's creatures.
- [ ] **Object models/sprites** (simple, readable): bridge, ash_path, crate, door, stair, exit. Each has an INTACT and an ASH look. ASH has a visible ember glow (see burnt-tower rules).
- [ ] **VFX polish:** floating embers, vignette, fog, soot and smoke that increase in passed hours, ash drifting between hours (this is what the ripple shot follows, so make it a visible glowing trail).
- [ ] **Audio, full:** laugh variants with pitch and reverb that hint at direction (higher or farther reverb for far hours), a ticking-clock motif, bells, a music loop with guzheng/erhu/dizi atmosphere in two layers (calm and tense) cross-faded as shadows increase, silence for big moments.
- [ ] Send Mariam the UI style (fonts, colors, button look) and help match the dial and dialogue box to the style guide.

### Phase 3: Trailer and polish
- [ ] **Trailer, 45 to 60 seconds:** hook (the laugh in the dark, one burn), the ripple shot, shadows closing in with their glowing tips, the spirit's tease, the reveal beat, title card. Record gameplay clips from the working build.
- [ ] Edit with captions and music. Use Mariam's lines for voiceover or on-screen text.
- [ ] At least 5 screenshots for the submission page, each recognizable at a glance.
- [ ] **Asset licenses list:** every external asset, font and sound with its license in `docs/ASSETS.md`. Give the credits text to Anosha.
- [ ] Compress oversized assets so the build stays small.

## Asset rules
- File names lowercase with underscores, prefixed by type or hour: `bg_hour_04.png`, `sfx_burn_01.ogg`, `vfx_ember_trail.tscn`.
- PNG for images, OGG for audio, `.glb` for models. Keep images under about 2048 px on the long side unless needed.
- Every AI-generated asset gets an entry in `docs/AI_LOG.md` (prompt, tool, kept or rejected).
- Never commit huge raw source files. Keep them in a shared drive.

## Dependencies
- **You give everyone:** the frozen style guide (Day 1 AM), fonts and color list.
- **You give Anosha:** the room shell with slot markers, VFX scenes and audio files with trigger notes (Day 1 PM, then Day 2).
- **You give Mariam:** UI style and moods for the laugh.
- **You need from Anosha:** the event list (in `PROJECT_CONTEXT.md` 6.3), and a runnable build for trailer clips (Day 2 PM onward).
- **You need from Mariam:** the line list with moods, intro text.

## Starter prompts for your AI session

**Style options:**
```
[paste PROJECT_CONTEXT.md, DEVELOPMENT_FLOW.md, NOOR_WORKPLAN.md]

I am Noor, I own art, VFX, audio and the trailer. Write me 8 different image
prompts for style options for Pyre of the Hours (section 5 of the context): a burnt
clock tower, cold-metal gears, one warm fire accent. Vary the technique (painted,
paper-cut, ink-wash, low-poly, etc). End each with "no text, no characters, 16:9".
Do not reference any specific existing game or film art style by name.
```

**VFX code:**
```
[paste the three files]

I am Noor, branch noor/art-audio. Task: a Godot shader for the shadow creature's
ember-tip glow (vfx/). It needs a glow_level parameter (dormant to active), a slow
pulse, and a dim deep red-orange color that is less saturated than the spirit's fire.
Edit scripts and shaders only. Tell me the exact nodes to create in the Godot
editor and how to attach it. Original code only. Tell me how to test it.
```

## Watch out for
- A frozen style only works if everyone uses it. Re-post the reference image if anyone's art drifts.
- Resist the urge to make the tower burn. Burnt, not burning.
- Don't over-polish one room while the other five have nothing. One shell, six grades first, then polish.
- Test every asset inside the game at its real size and in the fog and bloom. Art that looks great alone can vanish in the scene.
- If you are overloaded, cut in this order: extra shadow variants, secondary VFX, object variants. Never cut the style guide, the fire burn VFX, the laugh, the gear tick, or the ripple trail visuals.
