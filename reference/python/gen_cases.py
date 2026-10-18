"""Generates the shared test cases (tests/cases/*.json) and their fixture levels.

The JSON files are the artifact other people use; this script is how they are authored and
kept readable. Run from reference/python/:   python gen_cases.py
Then check them:                              python run_cases.py
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.abspath(os.path.join(HERE, "..", "..", "tests", "cases"))
FIX = os.path.join(OUT, "fixtures")

TYPE_FLAMMABLE = {"bridge": True, "crate": True, "door": True,
                  "ash_path": False, "stair": False, "exit": False}
fixtures = {}


def obj(id, type, hour, x, y, state="INTACT", ash=None, to=None):
    o = {"id": id, "type": type, "hour": hour, "slot": [x, y], "state": state,
         "flammable": TYPE_FLAMMABLE[type]}
    if ash:
        o["ash_link"] = {"hour": ash[0], "slot": [ash[1], ash[2]], "becomes": ash[3]}
    if to:
        o["links_to"] = {"hour": to[0], "slot": [to[1], to[2]]}
    return o


def fx(name, objects, player=(12, 0, 1), rooms=None, shadows=(), apH=3, start=0):
    """5x3 fixture. Rooms not given are all floor. An exit object must be in `objects`."""
    d = {
        "id": name, "title": name, "act": 1, "spirit_mood": "amused",
        "grid": {"w": 5, "h": 3}, "sun": {"start_index": start, "actions_per_hour": apH},
        "rooms": [{"hour": h, "terrain": rows} for h, rows in (rooms or {}).items()],
        "player": {"hour": player[0], "slot": [player[1], player[2]]},
        "objects": list(objects),
        "shadows": [{"id": s[0], "hour": s[1], "slot": [s[2], s[3]]} for s in shadows],
    }
    fixtures[name] = d
    return name


def far_exit():
    return obj("exit_far", "exit", 10, 4, 2)


def case(name, level, actions, **expect):
    return {"name": name, "level": level, "actions": actions, "expect": expect}


R, L, U, D = "move:right", "move:left", "move:up", "move:down"
W = "wait"
files = {}

# ------------------------------------------------------------------ movement and terrain
mv = []
f = fx("FX_wall", [far_exit()], player=(12, 1, 0), rooms={12: ["..#..", ".....", "....."]})
mv.append(case("wall blocks and the rejection is free", f, [R], rejected_at=0, reason="blocked_terrain", actions_used=0))
f = fx("FX_edge", [far_exit()], player=(12, 0, 0))
mv.append(case("moving off the grid is rejected", f, [U], rejected_at=0, reason="out_of_bounds", actions_used=0))
mv.append(case("a rejected action does not count (one valid wait, then a rejection)", f, [W, U],
               rejected_at=1, reason="out_of_bounds", actions_used=1))
f = fx("FX_chasm", [far_exit()], player=(12, 1, 0), rooms={12: ["..~..", ".....", "....."]})
mv.append(case("a chasm blocks without a filler", f, [R], rejected_at=0, reason="blocked_terrain", actions_used=0))
f = fx("FX_bridge", [obj("br", "bridge", 12, 2, 0), obj("ex", "exit", 12, 3, 0)], player=(12, 1, 0),
       rooms={12: ["..~..", ".....", "....."]})
mv.append(case("an INTACT bridge makes a chasm walkable", f, [R, R], won=True, failed=False, actions_used=2))
f = fx("FX_bridge_burn", [obj("br", "bridge", 12, 2, 0), far_exit()], player=(12, 2, 1),
       rooms={12: ["..~..", ".....", "....."]})
mv.append(case("burning the bridge makes the chasm block again", f, ["burn:up", U],
               rejected_at=1, reason="blocked_terrain", actions_used=1))
f = fx("FX_ash_path", [obj("ap", "ash_path", 12, 2, 0), obj("ex", "exit", 12, 3, 0)], player=(12, 1, 0),
       rooms={12: ["..~..", ".....", "....."]})
mv.append(case("an ash_path is walkable on a chasm", f, [R, R], won=True, actions_used=2))
f = fx("FX_crate", [obj("cr", "crate", 12, 2, 1), obj("ex", "exit", 12, 3, 1)], player=(12, 1, 1))
mv.append(case("an INTACT crate blocks", f, [R], rejected_at=0, reason="blocked_object", actions_used=0))
mv.append(case("burning a crate leaves walkable rubble", f, ["burn:right", R, R], won=True, actions_used=3))
f = fx("FX_door", [obj("dr", "door", 12, 2, 1), obj("ex", "exit", 12, 3, 1)], player=(12, 1, 1))
mv.append(case("an INTACT door blocks", f, [R], rejected_at=0, reason="blocked_object", actions_used=0))
mv.append(case("a burned door is open", f, ["burn:right", R, R], won=True, actions_used=3))
f = fx("FX_exit", [obj("ex", "exit", 12, 1, 1)], player=(12, 0, 1))
mv.append(case("stepping onto the exit wins", f, [R], won=True, failed=False, actions_used=1))
files["rules_movement.json"] = mv

# ------------------------------------------------------------------ stairs
st = []
f = fx("FX_stair", [obj("s", "stair", 12, 3, 1, to=(2, 0, 1)), obj("ex", "exit", 2, 1, 1)], player=(12, 2, 1))
st.append(case("interact on a stair travels to its arrival slot (interact costs an action)", f,
               [R, "interact", R], won=True, failed=False, actions_used=3))
f = fx("FX_stair_walk", [obj("s", "stair", 12, 2, 1, to=(2, 0, 1)), obj("ex", "exit", 12, 3, 1)], player=(12, 1, 1))
st.append(case("walking onto a stair does not travel", f, [R, R], won=True, actions_used=2))
st.append(case("interact off a stair is rejected", f, ["interact"], rejected_at=0, reason="not_on_stair", actions_used=0))
f = fx("FX_stair_oneway", [obj("s", "stair", 12, 0, 1, to=(2, 0, 1)), far_exit()], player=(12, 0, 1))
st.append(case("stairs are one way unless a return stair exists", f, ["interact", "interact"],
               rejected_at=1, reason="not_on_stair", actions_used=1))
f = fx("FX_stair_blocked", [obj("s", "stair", 12, 0, 1, to=(2, 1, 1)), obj("c", "crate", 2, 1, 1), far_exit()],
       player=(12, 0, 1))
st.append(case("a blocked arrival slot rejects interact", f, ["interact"], rejected_at=0, reason="arrival_blocked", actions_used=0))
f = fx("FX_stair_shadow", [obj("s", "stair", 12, 0, 1, to=(2, 1, 1)), far_exit()], player=(12, 0, 1),
       shadows=[("sh", 2, 1, 1)], apH=1)
st.append(case("an ACTIVE shadow on the arrival slot rejects interact", f, [W, W, "interact"],
               rejected_at=2, reason="arrival_blocked", actions_used=2))
st.append(case("a DORMANT shadow on the arrival slot does not block interact", f, ["interact"],
               won=False, failed=False, actions_used=1))
files["rules_stairs.json"] = st

# ------------------------------------------------------------------ burning and ash links
bn = []
f = fx("FX_burn_basic", [obj("cr", "crate", 12, 1, 1), far_exit()], player=(12, 0, 1))
bn.append(case("burning an empty slot is rejected", f, ["burn:up"], rejected_at=0, reason="nothing_to_burn", actions_used=0))
bn.append(case("burning twice is rejected (not INTACT)", f, ["burn:right", "burn:right"],
               rejected_at=1, reason="not_intact", actions_used=1))
bn.append(case("burning off the grid finds nothing to burn", f, ["burn:left"], rejected_at=0, reason="nothing_to_burn", actions_used=0))
bn.append(case("an object without an ash link still burns", f, ["burn:right"], won=False, failed=False, actions_used=1))
f = fx("FX_burn_stair", [obj("s", "stair", 12, 1, 1, to=(2, 0, 1)), far_exit()], player=(12, 0, 1))
bn.append(case("a non-flammable object cannot be burned", f, ["burn:right"], rejected_at=0, reason="not_flammable", actions_used=0))
f = fx("FX_ash_here", [obj("cr", "crate", 12, 1, 1, ash=(12, 0, 1, "ash_path")), far_exit()], player=(12, 0, 1))
bn.append(case("ash target holding the player makes the burn invalid", f, ["burn:right"],
               rejected_at=0, reason="ash_target_occupied", actions_used=0))
f = fx("FX_ash_shadow", [obj("cr", "crate", 12, 1, 1, ash=(2, 3, 1, "ash_path")), far_exit()], player=(12, 0, 1),
       shadows=[("sh", 2, 3, 1)], apH=1)
bn.append(case("ash target holding an ACTIVE shadow makes the burn invalid", f, [W, W, "burn:right"],
               rejected_at=2, reason="ash_target_occupied", actions_used=2))
bn.append(case("ash target holding a DORMANT shadow is allowed", f, ["burn:right"],
               won=False, failed=False, actions_used=1))
f = fx("FX_chain", [obj("a", "crate", 12, 1, 1, ash=(2, 1, 1, "crate")), obj("s", "stair", 12, 0, 0, to=(2, 0, 1)),
                    far_exit()], player=(12, 0, 1))
bn.append(case("an ash link may create a flammable object that burns again", f,
               ["burn:right", U, "interact", "burn:right"], won=False, failed=False, actions_used=4))
files["rules_burn.json"] = bn

# ------------------------------------------------------------------ shadows
sh = []
corridor = dict(objects=[obj("cr", "crate", 12, 2, 1), obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1))
f = fx("FX_shadow_dormant", [obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1), shadows=[("sh", 12, 2, 1)])
sh.append(case("a DORMANT shadow does not block", f, [R], won=False, failed=False, actions_used=1))
f = fx("FX_shadow_active", [obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1), shadows=[("sh", 12, 2, 1)])
sh.append(case("an ACTIVE shadow blocks (hour passes after 3 actions)", f, [W, W, W, R],
               rejected_at=3, reason="shadow_blocks", actions_used=3))
f = fx("FX_shadow_kill", [obj("cr", "crate", 12, 2, 1), obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1),
       shadows=[("sh", 12, 3, 1)], apH=1)
sh.append(case("burning next to an ACTIVE shadow destroys it", f, [W, "burn:right", R, R, R],
               won=True, failed=False, actions_used=5))
f = fx("FX_shadow_early", [obj("cr", "crate", 12, 2, 1), obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1),
       shadows=[("sh", 12, 3, 1)], apH=3)
sh.append(case("burning before the shadow wakes does not destroy it", f, ["burn:right", R, W, R],
               rejected_at=3, reason="shadow_blocks", actions_used=3))
f = fx("FX_shadow_diag", [obj("cr", "crate", 12, 2, 1), obj("ex", "exit", 12, 4, 2)], player=(12, 1, 1),
       shadows=[("sh", 12, 3, 2)], apH=1)
sh.append(case("a diagonal shadow is not in the 4-neighborhood", f, [W, "burn:right", R, D, R],
               rejected_at=4, reason="shadow_blocks", actions_used=4))
f = fx("FX_shadow_room", [obj("cr", "crate", 12, 1, 1), obj("s", "stair", 12, 2, 0, to=(2, 1, 1)),
                          obj("ex", "exit", 2, 4, 1)], player=(12, 1, 0),
       shadows=[("sh", 2, 2, 1)], apH=1)
sh.append(case("a shadow in another room is not destroyed", f, ["burn:down", W, R, "interact", R],
               rejected_at=4, reason="shadow_blocks", actions_used=4))
f = fx("FX_wake_self", [obj("ex", "exit", 10, 4, 2)], player=(12, 0, 1), shadows=[("sh", 12, 1, 1)], apH=2)
sh.append(case("a dormant shadow can be stood on; waiting as its hour passes is rejected and free", f, [R, W],
               rejected_at=1, reason="shadow_wakes_on_you", actions_used=1))
sh.append(case("moving off the shadow's tile lets it wake harmlessly", f, [R, R], won=False, failed=False, actions_used=2))
f = fx("FX_wake_move", [obj("ex", "exit", 10, 4, 2)], player=(12, 0, 1), shadows=[("sh", 12, 1, 1)], apH=1)
sh.append(case("moving onto a tile where a shadow wakes is rejected and free", f, [R],
               rejected_at=0, reason="shadow_wakes_on_you", actions_used=0))
f = fx("FX_wake_stair", [obj("s", "stair", 12, 0, 1, to=(2, 0, 1)), far_exit()], player=(12, 0, 1),
       shadows=[("sh", 2, 0, 1)], apH=1)
sh.append(case("arriving by stair on a tile where a shadow wakes is rejected", f, [W, "interact"],
               rejected_at=1, reason="shadow_wakes_on_you", actions_used=1))
f = fx("FX_start_index", [obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1), shadows=[("sh", 12, 2, 1)], start=1)
sh.append(case("with sun.start_index 1 hour 12 is already passed, so its shadow starts active", f, [R],
               rejected_at=0, reason="shadow_blocks", actions_used=0))
files["rules_shadows.json"] = sh

# ------------------------------------------------------------------ sun, win and fail
su = []
f = fx("FX_sun_apH2", [obj("ex", "exit", 12, 4, 1)], player=(12, 1, 1), shadows=[("sh", 12, 2, 1)], apH=2)
su.append(case("actions_per_hour 2: the hour passes after 2 actions", f, [W, W, R],
               rejected_at=2, reason="shadow_blocks", actions_used=2))
f = fx("FX_day", [far_exit()], player=(12, 0, 1), apH=1)
su.append(case("dial complete before the exit fails the level", f, [W] * 6, won=False, failed=True, actions_used=6))
su.append(case("one action before the dial completes is still playing", f, [W] * 5, won=False, failed=False, actions_used=5))
f = fx("FX_day_default", [far_exit()], player=(12, 0, 1), apH=3)
su.append(case("default day is 18 actions", f, [W] * 18, failed=True, actions_used=18))
su.append(case("17 actions is still playing", f, [W] * 17, failed=False, actions_used=17))
f = fx("FX_win_last", [obj("ex", "exit", 12, 1, 0)], player=(12, 0, 0), apH=1)
su.append(case("reaching the exit on the very last action still wins", f, [W] * 5 + [R],
               won=True, failed=False, actions_used=6))
f = fx("FX_start4", [far_exit()], player=(12, 0, 1), apH=1, start=4)
su.append(case("sun.start_index 4: the dial completes after 2 actions", f, [W, W], failed=True, actions_used=2))
files["rules_sun_outcome.json"] = su

# ------------------------------------------------------------------ real levels
lv = []
lv.append(case("L01 solution wins in 10", "L01_first_crate",
               [R, "burn:right", R, R, R, "interact", R, R, R, R], won=True, failed=False, actions_used=10))
lv.append(case("L02 solution wins in 15", "L02_wake_the_shadow",
               [R, R, "burn:up", "interact", R, W, "burn:right", R, R, R, "interact", R, R, R, R],
               won=True, failed=False, actions_used=15))
lv.append(case("L02 burning the gate too early leaves the shadow in the way", "L02_wake_the_shadow",
               [R, R, "burn:up", "interact", R, "burn:right", R, R],
               rejected_at=7, reason="shadow_blocks", actions_used=7))
# Every other shipped level gets an automatic "solution wins" case from the Python solver.
sys.path.insert(0, HERE)
from pyre_ref import load_level, solve  # noqa: E402
from pyre_ref.solver import action_str  # noqa: E402

LEVELS_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "levels", "data"))
HAND_WRITTEN = {"L01_first_crate", "L02_wake_the_shadow"}
for fn in sorted(os.listdir(LEVELS_DIR)):
    if fn.endswith(".json") and fn[:-5] not in HAND_WRITTEN:
        level = load_level(os.path.join(LEVELS_DIR, fn))
        plan = solve(level)
        assert plan.solved, f"{level.id} is not solvable"
        lv.append(case(f"{level.id} solution wins in {len(plan.actions)}", level.id,
                       [action_str(a) for a in plan.actions], won=True, failed=False,
                       actions_used=len(plan.actions)))
files["levels_shipped.json"] = lv

# ------------------------------------------------------------------ fixture that must be unsolvable
fx("FX_wrong_ash_unsolvable",
   [obj("cr", "crate", 12, 2, 0, ash=(6, 1, 1, "ash_path")), obj("s", "stair", 12, 4, 1, to=(6, 0, 1)),
    obj("ex", "exit", 6, 4, 1)],
   rooms={6: ["..#..", "..~..", "..#.."]})


def main():
    os.makedirs(FIX, exist_ok=True)
    for fn in os.listdir(FIX):
        os.remove(os.path.join(FIX, fn))
    for fn in os.listdir(OUT):
        if fn.endswith(".json"):
            os.remove(os.path.join(OUT, fn))
    for name, d in fixtures.items():
        with open(os.path.join(FIX, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(d, f, indent=1)
    total = 0
    for fn, cases in files.items():
        with open(os.path.join(OUT, fn), "w", encoding="utf-8") as f:
            json.dump(cases, f, indent=1)
        total += len(cases)
    print(f"wrote {total} cases in {len(files)} files and {len(fixtures)} fixtures")


if __name__ == "__main__":
    main()
