# Dialogue picker (Cinder)

Chooses WHICH MOOD and WHICH CACHED LINE the fire spirit uses. Dialogue only: never called from `core/`.
`dialogue_picker.gd` (game) and `reference/python/pyre_ref/dialogue.py` (reference) must agree on every case in
`tests/picker_cases.json`.

## Use
```gdscript
var lines: Array = JSON.parse_string(FileAccess.get_file_as_string("res://dialogue/lines.json"))["lines"]
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://dialogue/picker_config.json"))
var picker := DialoguePicker.new(lines, config, level_id)
var ctx := {"act": level["act"], "spirit_mood": level["spirit_mood"], "mood_weights": level.get("mood_weights", {})}

var r := picker.say("on_burn", ctx)     # {mood, line, tier, repeated}; line == {} if nothing fits
# AI path: pick the mood here, let the model write the line, then record it:
var mood := picker.choose_mood(ctx)
# ... prompt uses picker.recent_texts() as the "do not repeat" list ...
picker.remember(generated_text)
```
`class_name` is registered after the editor has imported the project once; the test runner uses `preload` so it needs no import.

## How it picks
- **Seed** = FNV-1a of `"<level_id>#<calls>"` (xorshift32). Same level + same sequence of calls = same result. No global random state.
- **Mood:** weighted pick from `mood_weights` (or the level's `spirit_mood`), keeping only moods the act allows
  (`picker_config.json`). Nothing allowed left: the act's first allowed mood.
- **Line, first tier with a fresh line wins:** 0 same act+trigger+mood, 1 same act+trigger, 2 same trigger+mood from an
  earlier act, 3 same trigger from an earlier act. A line from a LATER act is never used (spoiler-safe).
- **Repeats:** the last `recent_window` (3) lines are skipped. If everything was said recently, the line said longest
  ago repeats (never the one just spoken unless it is the only one) and `repeated` is `true`.
- `tier >= 2` or `repeated == true` means the authored lines have a gap there. Those are the lines to write next.

## Test
```
godot --headless --path . --script res://dialogue/tests/run_picker_tests.gd      # exit 0 = pass
cd reference/python && python -m unittest discover -s tests                      # 60 tests
python gen_dialogue_cases.py                                                      # regenerate tests/picker_cases.json
```

## Decisions to confirm (dialogue only, none change section 3)
1. `allowed_moods` per act in `picker_config.json`: act 1 amused/annoyed/triumphant, act 2 amused/annoyed/menacing,
   act 3 menacing/triumphant. This is what the current `lines.json` already uses.
2. `recent_window` = 3, shared across all triggers.
3. The seed uses the call counter, so the counter must advance once per `say()` / `choose_mood()` call.
4. Several triggers have only 1 to 3 lines today (on_undo, on_shadow_destroyed, on_reveal, on_choice, on_ending_*),
   so repeats and tier 2/3 picks are expected until more lines are written.
