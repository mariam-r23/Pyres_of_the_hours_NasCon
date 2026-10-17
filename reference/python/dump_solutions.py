"""Writes tools/expected_solutions.json: the Python solver's shortest plan for every level in levels/data.

    python dump_solutions.py            # from reference/python/

tools/test_solver.gd compares the GDScript solver against this file. Regenerate after any level or rule change.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from pyre_ref import load_level, solve  # noqa: E402
from pyre_ref.solver import action_str  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
LEVELS = os.path.join(ROOT, "levels", "data")
OUT = os.path.join(ROOT, "tools", "expected_solutions.json")


def main():
    out = {}
    for fn in sorted(f for f in os.listdir(LEVELS) if f.endswith(".json")):
        level = load_level(os.path.join(LEVELS, fn))
        r = solve(level)
        if not r.solved:
            sys.exit(f"{level.id} is not solvable; fix the level before dumping")
        out[level.id] = {"length": len(r.actions), "actions": [action_str(a) for a in r.actions]}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print(f"wrote {OUT} ({len(out)} levels)")


if __name__ == "__main__":
    main()
