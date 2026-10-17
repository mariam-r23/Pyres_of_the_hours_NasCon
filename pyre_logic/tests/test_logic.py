"""Unit tests. Run from the project root with:  python -m unittest discover -s tests -v

These tests are the executable spec of the rules. When porting to GDScript or C#,
port the tests first and make them pass.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from pyre_logic import (  # noqa: E402
    Action, Game, GameState, LevelError, ObjState, ShadowState, Status,
    apply, load_level, load_level_from_dict, solve,
)

LEVELS = os.path.join(os.path.dirname(__file__), "..", "levels")
E, N, S, W = "E", "N", "S", "W"


def make(hours=None, player=(0, 0, 0), objects=(), shadows=(), doorways=(), apH=3, w=5, h=3, types=None):
    """Build a small level from compact arguments. Hour 5 gets an exit unless given."""
    hours = dict(hours or {})
    if "5" not in hours and 5 not in hours:
        hours["5"] = [("." * w)] * (h - 1) + ["." * (w - 1) + "E"]
    data = {
        "name": "t", "actions_per_hour": apH, "width": w, "height": h,
        "hours": {str(k): v for k, v in hours.items()},
        "player": {"hour": player[0], "x": player[1], "y": player[2]},
        "objects": list(objects), "shadows": list(shadows), "doorways": list(doorways),
    }
    if types:
        data["types"] = types
    return load_level_from_dict(data)


def run(state, *actions):
    for a in actions:
        r = apply(state, a)
        assert r.valid, f"{a} was invalid: {r.reason}"
        state = r.state
    return state


def pos(hour, x, y):
    return {"hour": hour, "x": x, "y": y}


class BurnAndAsh(unittest.TestCase):
    def setUp(self):
        self.lv = make(
            objects=[{"id": "p", "type": "plank", "hour": 0, "x": 1, "y": 0,
                      "ash_link": {"hour": 4, "x": 3, "y": 2, "new_type": "ash_bridge"}}],
            player=(0, 0, 0),
        )
        self.s0 = GameState.initial(self.lv)

    def test_burn_makes_ash_and_creates_linked_object_in_the_right_hour_and_tile(self):
        r = apply(self.s0, Action.burn(E))
        self.assertTrue(r.valid)
        objs = {o.id: o for o in r.state.objects}
        self.assertEqual(objs["p"].state, ObjState.ASH)
        new = objs["p>ash"]
        self.assertEqual((new.type, new.hour, new.x, new.y, new.state),
                         ("ash_bridge", 4, 3, 2, ObjState.INTACT))
        kinds = [e.kind for e in r.events]
        self.assertIn("Burned", kinds)
        self.assertIn("AshMoved", kinds)

    def test_invalid_burn_changes_nothing_and_consumes_nothing(self):
        r = apply(self.s0, Action.burn(S))  # nothing to burn there
        self.assertFalse(r.valid)
        self.assertIs(r.state, self.s0)
        self.assertEqual(r.state.action_count, 0)
        self.assertEqual(r.events, [])

    def test_cannot_burn_twice(self):
        s1 = run(self.s0, Action.burn(E))
        self.assertFalse(apply(s1, Action.burn(E)).valid)

    def test_apply_never_mutates_its_input(self):
        before = self.s0.key()
        apply(self.s0, Action.burn(E))
        apply(self.s0, Action.move(S))
        self.assertEqual(self.s0.key(), before)

    def test_object_without_ash_link_still_burns(self):
        lv = make(objects=[{"id": "c", "type": "crate", "hour": 0, "x": 1, "y": 0}])
        r = apply(GameState.initial(lv), Action.burn(E))
        self.assertTrue(r.valid)
        self.assertEqual(len(r.state.objects), 1)

    def test_non_flammable_objects_cannot_be_burned(self):
        lv = make(objects=[{"id": "s", "type": "stone", "hour": 0, "x": 1, "y": 0}])
        self.assertFalse(apply(GameState.initial(lv), Action.burn(E)).valid)


class SunAndShadows(unittest.TestCase):
    def test_sun_advances_every_actions_per_hour_valid_actions(self):
        s = GameState.initial(make(apH=2))
        s = run(s, Action.wait())
        self.assertEqual(s.sun_hour, 0)
        r = apply(s, Action.wait())
        self.assertEqual(r.state.sun_hour, 1)
        self.assertIn("HourPassed", [e.kind for e in r.events])

    def test_invalid_actions_do_not_advance_the_sun(self):
        s = GameState.initial(make(apH=1))
        r = apply(s, Action.move(N))  # out of bounds from y=0
        self.assertFalse(r.valid)
        self.assertEqual(r.state.sun_hour, 0)

    def test_shadow_activates_only_when_its_hour_is_passed(self):
        lv = make(apH=1, shadows=[{"id": "a", "hour": 1, "x": 4, "y": 2}], player=(0, 0, 0))
        s = GameState.initial(lv)
        s = run(s, Action.wait())  # hour 0 passed
        self.assertEqual(s.shadows[0].state, ShadowState.INACTIVE)
        r = apply(s, Action.wait())  # hour 1 passed
        self.assertEqual(r.state.shadows[0].state, ShadowState.ACTIVE)
        self.assertIn("ShadowActivated", [e.kind for e in r.events])

    def test_active_shadow_blocks_movement_and_inactive_does_not(self):
        lv = make(apH=1, shadows=[{"id": "a", "hour": 0, "x": 2, "y": 0}], player=(0, 1, 0))
        s0 = GameState.initial(lv)
        self.assertTrue(apply(s0, Action.move(E)).valid)  # still inactive
        s1 = run(s0, Action.wait())  # hour 0 passed, shadow active
        r = apply(s1, Action.move(E))
        self.assertFalse(r.valid)
        self.assertEqual(r.reason, "shadow")

    def test_adjacent_burn_destroys_active_shadow(self):
        lv = make(
            apH=1, player=(0, 0, 0),
            objects=[{"id": "c", "type": "crate", "hour": 0, "x": 1, "y": 0}],
            shadows=[{"id": "a", "hour": 0, "x": 2, "y": 0}],
        )
        s = run(GameState.initial(lv), Action.wait())  # shadow now active
        r = apply(s, Action.burn(E))
        self.assertEqual(r.state.shadows[0].state, ShadowState.DESTROYED)
        self.assertIn("ShadowDestroyed", [e.kind for e in r.events])

    def test_burn_only_destroys_shadows_that_are_active_and_nearby(self):
        lv = make(
            apH=2, player=(0, 0, 0),
            objects=[{"id": "c", "type": "crate", "hour": 0, "x": 1, "y": 0}],
            shadows=[{"id": "near_inactive", "hour": 0, "x": 2, "y": 0},
                     {"id": "far", "hour": 1, "x": 4, "y": 2}],
        )
        s = run(GameState.initial(lv), Action.wait(), Action.wait())  # sun passes hour 0 only
        r = apply(s, Action.burn(E))
        by_id = {x.id: x.state for x in r.state.shadows}
        # 'near_inactive' woke up when hour 0 passed, so it is destroyed; 'far' (hour 1) is still asleep.
        self.assertEqual(by_id["near_inactive"], ShadowState.DESTROYED)
        self.assertEqual(by_id["far"], ShadowState.INACTIVE)

    def test_burning_before_the_shadow_wakes_does_not_destroy_it(self):
        lv = make(
            apH=5, player=(0, 0, 0),
            objects=[{"id": "c", "type": "crate", "hour": 0, "x": 1, "y": 0}],
            shadows=[{"id": "a", "hour": 0, "x": 2, "y": 0}],
        )
        r = apply(GameState.initial(lv), Action.burn(E))
        self.assertEqual(r.state.shadows[0].state, ShadowState.INACTIVE)

    def test_shadow_activating_on_the_player_catches_them(self):
        lv = make(apH=1, shadows=[{"id": "a", "hour": 0, "x": 0, "y": 0}], player=(0, 0, 0))
        r = apply(GameState.initial(lv), Action.wait())
        self.assertEqual(r.state.status, Status.FAILED)
        self.assertEqual(r.state.fail_reason, "caught")

    def test_day_ends_when_the_sun_passes_all_six_hours(self):
        s = GameState.initial(make(apH=1))
        for _ in range(5):
            s = run(s, Action.wait())
            self.assertEqual(s.status, Status.PLAYING)
        s = run(s, Action.wait())
        self.assertEqual(s.status, Status.FAILED)
        self.assertEqual(s.fail_reason, "day_ended")

    def test_no_actions_after_the_level_is_over(self):
        s = GameState.initial(make(apH=1))
        for _ in range(6):
            s = run(s, Action.wait())
        r = apply(s, Action.wait())
        self.assertFalse(r.valid)
        self.assertEqual(r.reason, "level_over")


class Outcomes(unittest.TestCase):
    def test_stepping_on_exit_wins(self):
        lv = make(hours={0: ["...E.", ".....", "....."]}, player=(0, 2, 0))
        r = apply(GameState.initial(lv), Action.move(E))
        self.assertEqual(r.state.status, Status.WON)
        self.assertIn("LevelWon", [e.kind for e in r.events])

    def test_win_beats_caught_on_the_same_action(self):
        lv = make(
            hours={0: ["...E.", ".....", "....."]}, apH=1, player=(0, 2, 0),
            shadows=[{"id": "a", "hour": 0, "x": 3, "y": 0}],
        )
        r = apply(GameState.initial(lv), Action.move(E))  # hour 0 passes as we step on the exit
        self.assertEqual(r.state.shadows[0].state, ShadowState.ACTIVE)
        self.assertEqual(r.state.status, Status.WON)

    def test_win_beats_day_ended_on_the_same_action(self):
        lv = make(hours={0: ["...E.", ".....", "....."]}, apH=1, player=(0, 2, 0))
        s = GameState.initial(lv)
        s.action_count = 5  # the next valid action ends the day
        r = apply(s, Action.move(E))
        self.assertEqual(r.state.sun_hour, 6)
        self.assertEqual(r.state.status, Status.WON)


class DoorwaysAndChasms(unittest.TestCase):
    def doorway_level(self, **kw):
        return make(
            hours={1: [".....", ".....", "....."]}, player=(0, 3, 1),
            doorways=[{"a": pos(0, 4, 1), "b": pos(1, 0, 1)}], **kw,
        )

    def test_doorway_teleports_to_partner_and_back(self):
        s = GameState.initial(self.doorway_level())
        r = apply(s, Action.move(E))
        self.assertEqual(r.state.player, (1, 0, 1))
        self.assertIn("DoorwayTraversed", [e.kind for e in r.events])
        # stepping from hour 1 (1,1) west onto the partner tile sends us back
        s2 = run(r.state, Action.move(E), Action.move(W))
        self.assertEqual(s2.player, (0, 4, 1))

    def test_doorway_is_blocked_if_the_partner_tile_is_blocked(self):
        lv = self.doorway_level(objects=[{"id": "r", "type": "stone", "hour": 1, "x": 0, "y": 1}])
        r = apply(GameState.initial(lv), Action.move(E))
        self.assertFalse(r.valid)
        self.assertEqual(r.reason, "doorway_blocked")

    def chasm_level(self, with_bridge):
        objs = [{"id": "b", "type": "bridge", "hour": 0, "x": 2, "y": 1}] if with_bridge else []
        return make(hours={0: ["..#..", "..~..", "..#.."]}, player=(0, 1, 1), objects=objs)

    def test_chasm_is_not_walkable_without_a_filler(self):
        r = apply(GameState.initial(self.chasm_level(False)), Action.move(E))
        self.assertFalse(r.valid)
        self.assertEqual(r.reason, "chasm")

    def test_chasm_is_walkable_with_an_intact_bridge(self):
        r = apply(GameState.initial(self.chasm_level(True)), Action.move(E))
        self.assertTrue(r.valid)

    def test_burning_the_bridge_makes_the_chasm_impassable_again(self):
        s = GameState.initial(self.chasm_level(True))
        r = apply(s, Action.burn(E))
        self.assertTrue(r.valid)
        self.assertFalse(apply(r.state, Action.move(E)).valid)

    def test_walls_and_gates_block(self):
        lv = make(hours={0: [".#...", ".....", "....."]}, player=(0, 0, 0),
                  objects=[{"id": "g", "type": "gate", "hour": 0, "x": 0, "y": 1}])
        s = GameState.initial(lv)
        self.assertEqual(apply(s, Action.move(E)).reason, "wall")
        self.assertEqual(apply(s, Action.move(S)).reason, "blocked")
        s2 = run(s, Action.burn(S))
        self.assertTrue(apply(s2, Action.move(S)).valid)  # an ash gate no longer blocks


class UndoAndDeterminism(unittest.TestCase):
    def test_undo_restores_the_exact_prior_state(self):
        g = Game(load_level(os.path.join(LEVELS, "level2_wake_the_shadow.json")))
        keys = [g.state.key()]
        for a in [Action.move(E), Action.move(E), Action.burn(N), Action.wait()]:
            self.assertTrue(g.do(a).valid)
            keys.append(g.state.key())
        for expected in reversed(keys[:-1]):
            self.assertTrue(g.undo())
            self.assertEqual(g.state.key(), expected)
        self.assertFalse(g.undo())  # nothing left to undo

    def test_invalid_actions_are_not_recorded_in_history(self):
        g = Game(load_level(os.path.join(LEVELS, "level1_first_spark.json")))
        self.assertFalse(g.do(Action.burn(S)).valid)
        self.assertFalse(g.undo())

    def test_restart_returns_to_the_initial_state(self):
        g = Game(load_level(os.path.join(LEVELS, "level1_first_spark.json")))
        start = g.state.key()
        g.do(Action.move(E))
        g.restart()
        self.assertEqual(g.state.key(), start)

    def test_same_actions_give_the_same_result(self):
        lv = load_level(os.path.join(LEVELS, "level2_wake_the_shadow.json"))
        plan = solve(lv).actions
        a = run(GameState.initial(lv), *plan)
        b = run(GameState.initial(lv), *plan)
        self.assertEqual(a.key(), b.key())
        self.assertEqual(a.status, Status.WON)


class Solver(unittest.TestCase):
    def load(self, name):
        return load_level(os.path.join(LEVELS, name))

    def test_level1_is_solved_in_nine_actions(self):
        r = solve(self.load("level1_first_spark.json"))
        self.assertTrue(r.solved)
        self.assertEqual(len(r.actions), 9)

    def test_level2_is_solved_and_the_plan_really_wins(self):
        lv = self.load("level2_wake_the_shadow.json")
        r = solve(lv)
        self.assertTrue(r.solved)
        self.assertEqual(len(r.actions), 14)
        self.assertEqual(run(GameState.initial(lv), *r.actions).status, Status.WON)

    def test_level2_burning_the_gate_before_the_shadow_wakes_makes_it_unsolvable(self):
        lv = self.load("level2_wake_the_shadow.json")
        # E,E,E,E (through doorway), E (to 1,1), then burn the gate at action 6 while the shadow sleeps.
        s = run(GameState.initial(lv), *[Action.move(E)] * 5, Action.burn(E))
        self.assertEqual(s.shadows[0].state, ShadowState.ACTIVE)  # it woke right after the burn
        self.assertEqual(solve(s).status, "unsolvable")

    def test_level3_is_unsolvable(self):
        self.assertEqual(solve(self.load("level3_wrong_ash.json")).status, "unsolvable")

    def test_solver_reports_limit_when_capped(self):
        self.assertEqual(solve(self.load("level2_wake_the_shadow.json"), max_states=10).status, "limit")


class Loader(unittest.TestCase):
    def base(self):
        return {
            "width": 3, "height": 1,
            "hours": {"0": ["..E"]},
            "player": {"hour": 0, "x": 0, "y": 0},
        }

    def assertErrorNames(self, data, field):
        with self.assertRaises(LevelError) as cm:
            load_level_from_dict(data)
        self.assertTrue(str(cm.exception).startswith(field), str(cm.exception))

    def test_valid_minimal_level_loads(self):
        load_level_from_dict(self.base())

    def test_bad_ash_link_hour_names_the_field(self):
        d = self.base()
        d["objects"] = [{"id": "a", "type": "plank", "hour": 0, "x": 1, "y": 0,
                         "ash_link": {"hour": 9, "x": 0, "y": 0, "new_type": "ash_bridge"}}]
        self.assertErrorNames(d, "objects[0].ash_link.hour")

    def test_unknown_object_type_names_the_field(self):
        d = self.base()
        d["objects"] = [{"id": "a", "type": "banana", "hour": 0, "x": 1, "y": 0}]
        self.assertErrorNames(d, "objects[0].type")

    def test_duplicate_object_ids_are_rejected(self):
        d = self.base()
        o = {"id": "a", "type": "plank", "hour": 0, "x": 1, "y": 0}
        d["objects"] = [o, dict(o)]
        self.assertErrorNames(d, "objects[1].id")

    def test_wrong_row_length_names_the_row(self):
        d = self.base()
        d["hours"]["0"] = ["..E."]
        self.assertErrorNames(d, "hours.0[0]")

    def test_unknown_terrain_character(self):
        d = self.base()
        d["hours"]["0"] = ["..Z"]
        self.assertErrorNames(d, "hours.0[0]")

    def test_missing_exit_is_rejected(self):
        d = self.base()
        d["hours"]["0"] = ["..."]
        self.assertErrorNames(d, "hours")

    def test_player_out_of_bounds_names_the_field(self):
        d = self.base()
        d["player"]["x"] = 7
        self.assertErrorNames(d, "player.x")

    def test_doorway_on_a_wall_is_rejected(self):
        d = self.base()
        d["hours"]["1"] = ["#.."]
        d["doorways"] = [{"a": pos(0, 1, 0), "b": pos(1, 0, 0)}]
        self.assertErrorNames(d, "doorways[0].b")

    def test_ash_link_into_a_wall_is_rejected(self):
        d = self.base()
        d["hours"]["1"] = ["#.."]
        d["objects"] = [{"id": "a", "type": "plank", "hour": 0, "x": 1, "y": 0,
                         "ash_link": {"hour": 1, "x": 0, "y": 0, "new_type": "ash_bridge"}}]
        self.assertErrorNames(d, "objects[0].ash_link")

    def test_custom_types_can_be_added_in_the_level_file(self):
        d = self.base()
        d["types"] = {"torch": {"flammable": True, "INTACT": {"blocks_movement": True}}}
        d["objects"] = [{"id": "t", "type": "torch", "hour": 0, "x": 1, "y": 0}]
        lv = load_level_from_dict(d)
        self.assertFalse(apply(GameState.initial(lv), Action.move(E)).valid)

    def test_shipped_levels_all_load(self):
        for f in sorted(os.listdir(LEVELS)):
            if f.endswith(".json"):
                load_level(os.path.join(LEVELS, f))


if __name__ == "__main__":
    unittest.main()
