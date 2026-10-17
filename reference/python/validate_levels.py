"""Python mirror of tools/validate_levels.gd: load, solve, and compare to par_actions.

    python validate_levels.py [path/to/levels/data]

Prints id, valid, solvable, shortest solution, par. Exit code 1 if any level fails.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from pyre_ref import LevelError, load_level, solve  # noqa: E402


def main():
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "..", "levels", "data")
    bad = 0
    print(f"{'id':32} {'valid':6} {'solvable':9} {'shortest':9} par")
    for fn in sorted(f for f in os.listdir(d) if f.endswith(".json")):
        try:
            lv = load_level(os.path.join(d, fn))
        except LevelError as e:
            print(f"{fn:32} no     -         -         -    ({e})")
            bad += 1
            continue
        r = solve(lv)
        ok = r.solved and lv.par_actions == len(r.actions)
        bad += 0 if ok else 1
        print(f"{lv.id:32} {'yes':6} {'yes' if r.solved else r.status:9} "
              f"{len(r.actions) if r.solved else '-':<9} {lv.par_actions}"
              + ("" if ok else "   <-- FAIL"))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
