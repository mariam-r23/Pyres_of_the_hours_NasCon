"""Run the shared JSON test cases (tests/cases/*.json) against this reference.

    python run_cases.py                # from reference/python/, uses ../../tests/cases
    python run_cases.py path/to/cases

A case file holds a list of cases (a single case object is also accepted). Format = section 6.4.
Level resolution: <id>.json in levels/data/, then in tests/cases/fixtures/.
Runner semantics (the GDScript runner must match):
  * apply `actions` in order; an action string is move:<dir>, burn:<dir>, interact, wait.
  * if expect has rejected_at: stop at the first rejected action; its 0-BASED index in `actions`
    and its reason must match. Any other rejection is a test failure.
  * otherwise any rejection fails the test; after the last action compare won/failed/actions_used.
  * actions_used = state.action_count (rejected actions never count).
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from pyre_ref import GameState, apply_action, load_level  # noqa: E402
from pyre_ref.model import FAILED, WON  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def parse_action(s):
    if ":" in s:
        kind, d = s.split(":", 1)
        return {"type": kind, "dir": d}
    return {"type": s}


def find_level(root, lid):
    for sub in (("levels", "data"), ("tests", "cases", "fixtures")):
        p = os.path.join(root, *sub, lid + ".json")
        if os.path.exists(p):
            return p
    raise FileNotFoundError(f"level {lid!r} not found in levels/data or tests/cases/fixtures")


def run_case(case, root=ROOT):
    """Returns None if the case passes, else a failure message."""
    level = load_level(find_level(root, case["level"]))
    state = GameState.initial(level)
    exp = case["expect"]
    for i, a in enumerate(case["actions"]):
        r = apply_action(state, parse_action(a))
        if not r["ok"]:
            if "rejected_at" not in exp:
                return f"action {i} ({a}) unexpectedly rejected: {r['reason']}"
            if i != exp["rejected_at"]:
                return f"rejected at {i}, expected {exp['rejected_at']} ({r['reason']})"
            if "reason" in exp and r["reason"] != exp["reason"]:
                return f"rejected with {r['reason']!r}, expected {exp['reason']!r}"
            if "actions_used" in exp and state.action_count != exp["actions_used"]:
                return f"actions_used {state.action_count}, expected {exp['actions_used']}"
            return None
        state = r["state"]
    if "rejected_at" in exp:
        return f"expected a rejection at {exp['rejected_at']} but every action was valid"
    for key, got in (("won", state.status == WON), ("failed", state.status == FAILED),
                     ("actions_used", state.action_count)):
        if key in exp and exp[key] != got:
            return f"{key}: got {got!r}, expected {exp[key]!r}"
    return None


def load_cases(cases_dir):
    out = []
    for fn in sorted(os.listdir(cases_dir)):
        if fn.endswith(".json"):
            with open(os.path.join(cases_dir, fn), encoding="utf-8") as f:
                data = json.load(f)
            for c in (data if isinstance(data, list) else [data]):
                out.append((fn, c))
    return out


def main():
    cases_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "tests", "cases")
    root = os.path.abspath(os.path.join(cases_dir, "..", ".."))
    cases = load_cases(cases_dir)
    bad = 0
    for fn, c in cases:
        err = run_case(c, root)
        if err:
            bad += 1
            print(f"FAIL [{fn}] {c['name']}: {err}")
    print(f"{len(cases) - bad}/{len(cases)} cases pass")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
