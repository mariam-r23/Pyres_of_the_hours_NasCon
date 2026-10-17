"""Tests for the seeded dialogue picker (pyre_ref/dialogue.py).

Run from reference/python:  python -m unittest discover -s tests -v
"""
import json
import os
import sys
import unittest

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, ".."))
from pyre_ref.dialogue import DialoguePicker, Rng, load_lines, seed_from_string  # noqa: E402

ROOT = os.path.join(HERE, "..", "..", "..")
LINES_PATH = os.path.join(ROOT, "dialogue", "lines.json")
CONFIG_PATH = os.path.join(ROOT, "dialogue", "picker_config.json")
CASES_PATH = os.path.join(ROOT, "dialogue", "tests", "picker_cases.json")

CONFIG = {"recent_window": 3, "allowed_moods": {
    "1": ["amused", "annoyed", "triumphant"], "2": ["amused", "annoyed", "menacing"],
    "3": ["menacing", "triumphant"]}}


def L(id_, act, trigger, mood):
    return {"id": id_, "act": act, "trigger": trigger, "mood": mood, "text": f"text {id_}"}


def ctx(act, mood, weights=None):
    c = {"act": act, "spirit_mood": mood}
    if weights:
        c["mood_weights"] = weights
    return c


class Seeds(unittest.TestCase):
    def test_fnv1a_known_values(self):
        self.assertEqual(seed_from_string(""), 2166136261)
        self.assertEqual(seed_from_string("a"), 0xE40C292C)
        self.assertEqual(seed_from_string("foobar"), 0xBF9CF968)

    def test_rng_is_deterministic_and_nonzero_seed_safe(self):
        a, b = Rng(0), Rng(0)
        self.assertEqual([a.next_u32() for _ in range(5)], [b.next_u32() for _ in range(5)])
        self.assertTrue(all(0 < v <= 0xFFFFFFFF for v in [Rng(0).next_u32()]))


class Moods(unittest.TestCase):
    def picker(self, lines=()):
        return DialoguePicker(list(lines), CONFIG, "L_test")

    def test_single_mood_without_weights_uses_spirit_mood(self):
        p = self.picker()
        self.assertEqual([p.choose_mood(ctx(1, "annoyed")) for _ in range(10)], ["annoyed"] * 10)

    def test_disallowed_moods_are_ignored(self):
        p = self.picker()
        moods = {p.choose_mood(ctx(1, "amused", {"menacing": 9.0, "annoyed": 1.0})) for _ in range(20)}
        self.assertEqual(moods, {"annoyed"})

    def test_everything_disallowed_falls_back_to_first_allowed(self):
        self.assertEqual(self.picker().choose_mood(ctx(3, "amused", {"amused": 1.0})), "menacing")

    def test_zero_weights_fall_back_to_first_allowed(self):
        self.assertEqual(self.picker().choose_mood(ctx(1, "x", {"amused": 0.0})), "amused")

    def test_weights_roughly_follow_the_distribution(self):
        counts = {"amused": 0, "annoyed": 0, "triumphant": 0}
        for i in range(600):
            p = DialoguePicker([], CONFIG, f"level{i}")
            counts[p.choose_mood(ctx(1, "amused", {"amused": 0.6, "annoyed": 0.2, "triumphant": 0.2}))] += 1
        self.assertGreater(counts["amused"], 300)
        self.assertLess(counts["amused"], 420)
        self.assertGreater(counts["annoyed"], 70)
        self.assertGreater(counts["triumphant"], 70)

    def test_act_three_weights_can_keep_menacing_dominant(self):
        counts = {"menacing": 0, "triumphant": 0}
        for i in range(300):
            p = DialoguePicker([], CONFIG, f"L9_{i}")
            counts[p.choose_mood(ctx(3, "menacing", {"menacing": 0.8, "triumphant": 0.2}))] += 1
        self.assertGreater(counts["menacing"], 200)


class Lines(unittest.TestCase):
    LINES = [L("a1_t_amu", 1, "t", "amused"), L("a1_t_ann", 1, "t", "annoyed"),
             L("a2_t_men", 2, "t", "menacing"), L("a3_t_men", 3, "t", "menacing")]

    def test_never_uses_a_later_act_line(self):
        p = DialoguePicker(self.LINES, CONFIG, "L1")
        for _ in range(30):
            r = p.say("t", ctx(1, "amused", {"amused": 1, "annoyed": 1}))
            self.assertLessEqual(r["line"]["act"], 1)

    def test_exact_tier_is_preferred(self):
        r = DialoguePicker(self.LINES, CONFIG, "L1").say("t", ctx(3, "menacing"))
        self.assertEqual((r["line"]["id"], r["tier"]), ("a3_t_men", 0))

    def test_same_act_any_mood_is_tier_one(self):
        r = DialoguePicker([L("a2_t_ann", 2, "t", "annoyed")], CONFIG, "L1").say("t", ctx(2, "amused"))
        self.assertEqual((r["line"]["id"], r["tier"]), ("a2_t_ann", 1))

    def test_earlier_act_same_mood_is_tier_two_and_any_mood_is_tier_three(self):
        lines = [L("a1_t_men", 1, "t", "menacing"), L("a1_t_amu", 1, "t", "amused")]
        r = DialoguePicker(lines, CONFIG, "L1").say("t", ctx(3, "menacing"))
        self.assertEqual((r["line"]["id"], r["tier"]), ("a1_t_men", 2))
        r = DialoguePicker([L("a1_t_amu", 1, "t", "amused")], CONFIG, "L1").say("t", ctx(3, "menacing"))
        self.assertEqual((r["line"]["id"], r["tier"]), ("a1_t_amu", 3))

    def test_unknown_trigger_gives_no_line_and_no_crash(self):
        r = DialoguePicker(self.LINES, CONFIG, "L1").say("nope", ctx(1, "amused"))
        self.assertEqual((r["line"], r["tier"]), ({}, -1))

    def test_recent_lines_are_not_repeated_while_fresh_ones_exist(self):
        lines = [L(f"a1_t_{i}", 1, "t", "amused") for i in range(5)]
        p = DialoguePicker(lines, CONFIG, "L1")
        spoken = [p.say("t", ctx(1, "amused"))["line"]["id"] for _ in range(4)]
        for i in range(len(spoken)):
            self.assertNotIn(spoken[i], spoken[max(0, i - 3):i])

    def test_when_exhausted_the_oldest_line_is_repeated_never_the_one_just_said(self):
        lines = [L("a1_t_a", 1, "t", "amused"), L("a1_t_b", 1, "t", "amused")]
        p = DialoguePicker(lines, CONFIG, "L1")
        ids = [p.say("t", ctx(1, "amused"))["line"]["id"] for _ in range(8)]
        for a, b in zip(ids, ids[1:]):
            self.assertNotEqual(a, b)

    def test_a_trigger_with_one_line_repeats_it(self):
        p = DialoguePicker([L("a1_solo", 1, "solo", "amused")], CONFIG, "L1")
        r = [p.say("solo", ctx(1, "amused")) for _ in range(3)]
        self.assertEqual([x["line"]["id"] for x in r], ["a1_solo"] * 3)
        self.assertTrue(r[1]["repeated"])

    def test_same_level_same_calls_same_result_and_different_levels_differ(self):
        def run(level):
            p = DialoguePicker(self.LINES, CONFIG, level)
            return [p.say("t", ctx(2, "amused", {"amused": 1, "annoyed": 1, "menacing": 1}))["mood"] for _ in range(12)]
        self.assertEqual(run("L1"), run("L1"))
        self.assertNotEqual(run("L1"), run("L2"))

    def test_recent_texts_maps_ids_and_keeps_ai_text(self):
        p = DialoguePicker(self.LINES, CONFIG, "L1")
        p.remember("a1_t_amu")
        p.remember("A freshly written line.")
        self.assertEqual(p.recent_texts(), ["text a1_t_amu", "A freshly written line."])

    def test_remember_keeps_only_the_window(self):
        p = DialoguePicker([], CONFIG, "L1")
        for i in range(10):
            p.remember(f"x{i}")
        self.assertEqual(p.recent, ["x7", "x8", "x9"])


class RealData(unittest.TestCase):
    """Properties of the shipped lines.json (so editing lines never silently breaks the picker)."""

    @classmethod
    def setUpClass(cls):
        cls.lines = load_lines(LINES_PATH)
        with open(CONFIG_PATH, encoding="utf-8") as f:
            cls.config = json.load(f)

    def test_every_line_is_well_formed(self):
        ids = set()
        for l in self.lines:
            self.assertEqual(set(l), {"id", "act", "trigger", "mood", "text"})
            self.assertNotIn(l["id"], ids)
            ids.add(l["id"])
            self.assertLessEqual(len(l["text"].split()), 15, l["id"])
            self.assertIn(l["mood"], self.config["allowed_moods"][str(l["act"])], f'{l["id"]}: mood not allowed in its own act')

    def test_picks_respect_act_mood_and_availability(self):
        triggers = sorted({l["trigger"] for l in self.lines})
        for act in (1, 2, 3):
            allowed = self.config["allowed_moods"][str(act)]
            for trig in triggers:
                available = [l for l in self.lines if l["trigger"] == trig and l["act"] <= act]
                for n in range(8):
                    p = DialoguePicker(self.lines, self.config, f"real{act}{trig}{n}")
                    for _ in range(5):
                        r = p.say(trig, ctx(act, allowed[0], {m: 1.0 for m in allowed}))
                        self.assertIn(r["mood"], allowed)
                        if available:
                            self.assertTrue(r["line"], f"act {act} {trig}: no line although {len(available)} exist")
                            self.assertLessEqual(r["line"]["act"], act)
                        else:
                            self.assertEqual(r["line"], {})


class SharedCases(unittest.TestCase):
    """Cases recorded for the GDScript twin (dialogue/tests/run_picker_tests.gd)."""

    def test_python_reproduces_every_recorded_case(self):
        with open(CASES_PATH, encoding="utf-8") as f:
            data = json.load(f)
        for c in data["seed_cases"]:
            self.assertEqual(seed_from_string(c["text"]), c["seed"], c["text"])
        for c in data["rng_cases"]:
            r = Rng(c["seed"])
            self.assertEqual([r.next_u32() for _ in range(5)], c["first5"], c["seed"])
        for c in data["picker_cases"]:
            p = DialoguePicker(c["lines"], c["config"], c["level_id"])
            for i, call in enumerate(c["calls"]):
                r = p.say(call["trigger"], call["ctx"])
                got = {"mood": r["mood"], "line_id": r["line"].get("id", ""), "tier": r["tier"], "repeated": r["repeated"]}
                self.assertEqual(got, c["expect"][i], f'{c["name"]} call {i}')


if __name__ == "__main__":
    unittest.main()
