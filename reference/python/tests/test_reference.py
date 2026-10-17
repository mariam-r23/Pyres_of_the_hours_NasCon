"""Run from reference/python/:   python -m unittest discover -s tests -v

1. Every shared JSON case in tests/cases/ (the cross-check with the GDScript implementation).
2. Python-only checks: purity, undo, determinism, hash_key, legal_actions, solver, loader errors.
"""
import copy
import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import run_cases  # noqa: E402
from pyre_ref import (  # noqa: E402
    Game, GameState, LevelError, apply_action, legal_actions, load_level,
    load_level_from_dict, solve,
)
from pyre_ref.model import WON  # noqa: E402

ROOT = run_cases.ROOT
LEVELS = os.path.join(ROOT, "levels", "data")
FIXTURES = os.path.join(ROOT, "tests", "cases", "fixtures")
L01_SOLUTION = [run_cases.parse_action(a) for a in
                "move:right burn:right move:right move:right move:right interact "
                "move:right move:right move:right move:right".split()]


def lv(name, folder=LEVELS):
    return load_level(os.path.join(folder, name + ".json"))


class SharedCases(unittest.TestCase):
    def test_every_json_case_passes(self):
        cases = run_cases.load_cases(os.path.join(ROOT, "tests", "cases"))
        self.assertGreaterEqual(len(cases), 40)
        for fn, c in cases:
            with self.subTest(file=fn, case=c["name"]):
                self.assertIsNone(run_cases.run_case(c, ROOT))


class Purity(unittest.TestCase):
    def test_apply_action_never_mutates_its_input(self):
        s = GameState.initial(lv("L01_first_crate"))
        before = s.hash_key()
        for a in legal_actions(s):
            apply_action(s, a)
        apply_action(s, {"type": "burn", "dir": "right"})
        self.assertEqual(s.hash_key(), before)

    def test_a_rejection_returns_the_same_state_object_and_an_action_rejected_event(self):
        s = GameState.initial(lv("L01_first_crate"))
        r = apply_action(s, {"type": "interact"})
        self.assertFalse(r["ok"])
        self.assertIs(r["state"], s)
        self.assertEqual(r["events"], [{"type": "action_rejected", "reason": "not_on_stair"}])

    def test_legal_actions_contains_only_valid_actions_and_all_of_them(self):
        s = GameState.initial(lv("L01_first_crate"))
        legal = legal_actions(s)
        self.assertEqual(legal, [{"type": "move", "dir": "up"}, {"type": "move", "dir": "down"},
                                 {"type": "move", "dir": "right"}, {"type": "wait"}])
        for a in legal:
            self.assertTrue(apply_action(s, a)["ok"])


class Events(unittest.TestCase):
    def test_burning_the_crate_in_l01_emits_the_section_6_3_events(self):
        s = GameState.initial(lv("L01_first_crate"))
        s = apply_action(s, {"type": "move", "dir": "right"})["state"]
        r = apply_action(s, {"type": "burn", "dir": "right"})
        types = [e["type"] for e in r["events"]]
        self.assertEqual(types[:2], ["burned", "ash_moved"])
        self.assertIn("action_applied", types)
        ash = next(e for e in r["events"] if e["type"] == "ash_moved")
        self.assertEqual((ash["from_hour"], ash["to_hour"], ash["to_slot"], ash["becomes"]),
                         (12, 2, [2, 2], "ash_path"))

    def test_sun_events_fire_when_an_hour_passes(self):
        s = GameState.initial(lv("L01_first_crate"))
        for _ in range(2):
            s = apply_action(s, {"type": "wait"})["state"]
        r = apply_action(s, {"type": "wait"})
        types = [e["type"] for e in r["events"]]
        self.assertIn("sun_advanced", types)
        self.assertIn({"type": "hour_passed", "hour": 12}, r["events"])
        self.assertTrue(r["state"].is_hour_passed(12))
        self.assertFalse(r["state"].is_hour_passed(2))

    def test_shadow_appeared_fires_for_a_shadow_whose_hour_passes(self):
        s = GameState.initial(lv("L02_wake_the_shadow"))
        seen = []
        for _ in range(6):
            r = apply_action(s, {"type": "wait"})
            seen += [e for e in r["events"] if e["type"] == "shadow_appeared"]
            s = r["state"]
        self.assertEqual(seen, [{"type": "shadow_appeared", "id": "sh_1", "hour": 2, "slot": [3, 1]}])

    def test_level_won_and_level_failed_events(self):
        g = Game(lv("L01_first_crate"))
        last = None
        for a in L01_SOLUTION:
            last = g.do(a)
        self.assertIn({"type": "level_won", "actions_used": 10}, last["events"])
        g2 = Game(lv("FX_day", FIXTURES))
        for _ in range(6):
            last = g2.do({"type": "wait"})
        self.assertIn({"type": "level_failed", "reason": "dial_complete"}, last["events"])

    def test_no_actions_after_the_level_is_over(self):
        s = GameState.initial(lv("FX_day", FIXTURES))
        for _ in range(6):
            s = apply_action(s, {"type": "wait"})["state"]
        self.assertEqual(apply_action(s, {"type": "wait"})["reason"], "level_over")


class UndoAndDeterminism(unittest.TestCase):
    def test_undo_restores_each_prior_state_for_free(self):
        g = Game(lv("L02_wake_the_shadow"))
        keys = [g.state.hash_key()]
        for a in [{"type": "move", "dir": "right"}, {"type": "move", "dir": "right"},
                  {"type": "burn", "dir": "up"}, {"type": "wait"}]:
            self.assertTrue(g.do(a)["ok"])
            keys.append(g.state.hash_key())
        for expected in reversed(keys[:-1]):
            self.assertTrue(g.undo()["ok"])
            self.assertEqual(g.state.hash_key(), expected)
        self.assertFalse(g.undo()["ok"])

    def test_undo_emits_undo_done(self):
        g = Game(lv("L01_first_crate"))
        g.do({"type": "wait"})
        self.assertEqual(g.undo()["events"], [{"type": "undo_done"}])

    def test_rejected_actions_are_not_snapshotted(self):
        g = Game(lv("L01_first_crate"))
        self.assertFalse(g.do({"type": "burn", "dir": "down"})["ok"])
        self.assertFalse(g.undo()["ok"])

    def test_restart_returns_to_the_initial_state(self):
        g = Game(lv("L01_first_crate"))
        start = g.state.hash_key()
        g.do({"type": "wait"})
        g.restart()
        self.assertEqual(g.state.hash_key(), start)

    def test_same_actions_give_the_same_result(self):
        def play():
            s = GameState.initial(lv("L01_first_crate"))
            for a in L01_SOLUTION:
                s = apply_action(s, a)["state"]
            return s
        a, b = play(), play()
        self.assertEqual(a.hash_key(), b.hash_key())
        self.assertEqual(a.status, WON)

    def test_hash_key_differs_when_state_differs(self):
        s = GameState.initial(lv("L01_first_crate"))
        keys = {s.hash_key()}
        for a in legal_actions(s):
            keys.add(apply_action(s, a)["state"].hash_key())
        self.assertEqual(len(keys), 1 + len(legal_actions(s)))


class Solver(unittest.TestCase):
    def test_l01_is_solved_in_ten(self):
        r = solve(lv("L01_first_crate"))
        self.assertTrue(r.solved)
        self.assertEqual(len(r.actions), 10)

    def test_l02_is_solved_in_fifteen_and_the_plan_wins(self):
        level = lv("L02_wake_the_shadow")
        r = solve(level)
        self.assertEqual(len(r.actions), 15)
        s = GameState.initial(level)
        for a in r.actions:
            s = apply_action(s, a)["state"]
        self.assertEqual(s.status, WON)

    def test_l02_shortest_solution_has_to_wait_for_the_sun(self):
        self.assertIn({"type": "wait"}, solve(lv("L02_wake_the_shadow")).actions)

    def test_l02_after_an_early_gate_burn_is_unsolvable(self):
        s = GameState.initial(lv("L02_wake_the_shadow"))
        for a in "move:right move:right burn:up interact move:right burn:right".split():
            s = apply_action(s, run_cases.parse_action(a))["state"]
        self.assertEqual(solve(s).status, "unsolvable")

    def test_wrong_ash_fixture_is_unsolvable(self):
        self.assertEqual(solve(lv("FX_wrong_ash_unsolvable", FIXTURES)).status, "unsolvable")

    def test_solver_reports_limit_when_capped(self):
        self.assertEqual(solve(lv("L02_wake_the_shadow"), max_states=10).status, "limit")

    def test_par_actions_match_the_solver_for_every_shipped_level(self):
        for fn in sorted(os.listdir(LEVELS)):
            if fn.endswith(".json"):
                level = load_level(os.path.join(LEVELS, fn))
                with self.subTest(level=level.id):
                    self.assertEqual(level.par_actions, len(solve(level).actions))


class Loader(unittest.TestCase):
    def base(self):
        return copy.deepcopy({
            "id": "T", "grid": {"w": 3, "h": 1},
            "player": {"hour": 12, "slot": [0, 0]},
            "objects": [{"id": "ex", "type": "exit", "hour": 12, "slot": [2, 0]}],
        })

    def assertErrorNames(self, data, field):
        with self.assertRaises(LevelError) as cm:
            load_level_from_dict(data)
        self.assertTrue(str(cm.exception).startswith(field), str(cm.exception))

    def test_minimal_level_loads_with_defaults(self):
        level = load_level_from_dict(self.base())
        self.assertEqual((level.act, level.spirit_mood, level.start_index, level.actions_per_hour),
                         (1, "amused", 0, 3))

    def test_bad_hour_names_the_field(self):
        d = self.base()
        d["objects"][0]["hour"] = 3
        self.assertErrorNames(d, "objects[0].hour")

    def test_unknown_object_type(self):
        d = self.base()
        d["objects"].append({"id": "a", "type": "banana", "hour": 12, "slot": [1, 0]})
        self.assertErrorNames(d, "objects[1].type")

    def test_duplicate_ids(self):
        d = self.base()
        d["objects"].append({"id": "ex", "type": "crate", "hour": 12, "slot": [1, 0]})
        self.assertErrorNames(d, "objects[1].id")

    def test_two_objects_in_one_slot(self):
        d = self.base()
        d["objects"].append({"id": "c", "type": "crate", "hour": 12, "slot": [2, 0]})
        self.assertErrorNames(d, "objects[1].slot")

    def test_slot_outside_the_grid(self):
        d = self.base()
        d["objects"][0]["slot"] = [3, 0]
        self.assertErrorNames(d, "objects[0].slot")

    def test_wrong_terrain_row_length(self):
        d = self.base()
        d["rooms"] = [{"hour": 12, "terrain": ["....."]}]
        self.assertErrorNames(d, "rooms[0].terrain[0]")

    def test_unknown_terrain_character(self):
        d = self.base()
        d["rooms"] = [{"hour": 12, "terrain": ["..E"]}]
        self.assertErrorNames(d, "rooms[0].terrain[0]")

    def test_missing_exit(self):
        d = self.base()
        d["objects"] = []
        self.assertErrorNames(d, "objects")

    def test_ash_link_into_a_wall(self):
        d = self.base()
        d["rooms"] = [{"hour": 2, "terrain": ["#.."]}]
        d["objects"].append({"id": "c", "type": "crate", "hour": 12, "slot": [1, 0],
                             "ash_link": {"hour": 2, "slot": [0, 0], "becomes": "ash_path"}})
        self.assertErrorNames(d, "objects[1].ash_link.slot")

    def test_ash_link_onto_an_existing_object(self):
        d = self.base()
        d["objects"].append({"id": "c", "type": "crate", "hour": 12, "slot": [1, 0],
                             "ash_link": {"hour": 12, "slot": [2, 0], "becomes": "ash_path"}})
        self.assertErrorNames(d, "objects[1].ash_link.slot")

    def test_stair_needs_links_to(self):
        d = self.base()
        d["objects"].append({"id": "s", "type": "stair", "hour": 12, "slot": [1, 0]})
        self.assertErrorNames(d, "objects[1].links_to")

    def test_player_on_a_wall(self):
        d = self.base()
        d["rooms"] = [{"hour": 12, "terrain": ["#.."]}]
        self.assertErrorNames(d, "player.slot")

    def test_shadow_on_a_wall(self):
        d = self.base()
        d["rooms"] = [{"hour": 12, "terrain": [".#."]}]
        d["shadows"] = [{"id": "s", "hour": 12, "slot": [1, 0]}]
        self.assertErrorNames(d, "shadows[0].slot")

    def test_unknown_mood(self):
        d = self.base()
        d["spirit_mood"] = "happy"
        self.assertErrorNames(d, "spirit_mood")

    def test_every_shipped_level_and_fixture_loads(self):
        for folder in (LEVELS, FIXTURES):
            for fn in sorted(os.listdir(folder)):
                if fn.endswith(".json"):
                    load_level(os.path.join(folder, fn))


if __name__ == "__main__":
    unittest.main()
