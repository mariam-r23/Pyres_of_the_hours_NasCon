"""Which (act, trigger) combinations have too few cached lines?

    python dialogue_coverage.py            # from reference/python/

A frequent trigger needs at least recent_window (3) lines per act so the picker can avoid repeats; the one-shot story
triggers need at least 1 (2 is better, for replays). Exit code 1 if anything is below its minimum.
"""
import json
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
DIALOGUE = os.path.join(HERE, "..", "..", "dialogue")
FREQUENT = ["on_burn", "on_ash_moved", "on_undo", "on_idle", "on_solve", "on_fail",
            "on_shadow_appeared", "on_shadow_destroyed"]
ONE_SHOT = {3: ["on_reveal", "on_choice", "on_ending_wind", "on_ending_burn"]}


def main():
    lines = json.load(open(os.path.join(DIALOGUE, "lines.json"), encoding="utf-8"))["lines"]
    window = json.load(open(os.path.join(DIALOGUE, "picker_config.json")))["recent_window"]
    count = defaultdict(list)
    for l in lines:
        count[(l["act"], l["trigger"])].append(l["mood"])
    bad = 0
    print(f"{'trigger':22} {'act 1':>7} {'act 2':>7} {'act 3':>7}   (minimum {window} per act; one-shot 1)")
    for trig in FREQUENT + ONE_SHOT[3]:
        cells = []
        for act in (1, 2, 3):
            n = len(count[(act, trig)])
            need = 0 if (trig in ONE_SHOT[3] and act != 3) else (1 if trig in ONE_SHOT[3] else window)
            flag = "!" if n < need else ""
            bad += 1 if n < need else 0
            cells.append(f"{n}{flag}".rjust(7))
        print(f"{trig:22} {''.join(cells)}")
    print(f"\n{len(lines)} lines, {bad} gaps")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
