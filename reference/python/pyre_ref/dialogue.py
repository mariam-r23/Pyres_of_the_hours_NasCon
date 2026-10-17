"""Seeded dialogue picker for the fire spirit (Cinder). Python twin of dialogue/dialogue_picker.gd.

Dialogue only: nothing here touches the game rules, and it never runs inside core/.
Both implementations MUST agree on every case in dialogue/tests/picker_cases.json.

How a call works (one call = one "trigger count" step):
  1. rng seed = FNV-1a 32 of "<level_id>#<calls>"   (reproducible demos, no hidden global state)
  2. mood: weighted pick from the level's mood_weights (or its spirit_mood), limited to the
     moods the act allows. Integer weights (per mille), so no float drift between languages.
  3. line: first non-empty tier wins, never repeating the last `recent_window` lines unless
     every tier is exhausted:
       tier 0  same act, same trigger, same mood
       tier 1  same act, same trigger, any mood
       tier 2  same trigger, same mood, earlier act
       tier 3  same trigger, any mood, earlier act
     A line from a LATER act is never used (it could spoil the reveal).
     If every candidate was said recently, the line said longest ago is repeated (never the
     line just spoken, unless it is the only one).
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Optional

MASK = 0xFFFFFFFF


def seed_from_string(text: str) -> int:
    h = 2166136261
    for b in text.encode("utf-8"):
        h = ((h ^ b) * 16777619) & MASK
    return h


class Rng:
    """xorshift32. Shifts and xors only, so it is identical in Python and GDScript."""

    def __init__(self, seed: int):
        self.s = seed & MASK
        if self.s == 0:
            self.s = 2463534242
        for _ in range(3):  # warm-up
            self.next_u32()

    def next_u32(self) -> int:
        x = self.s
        x ^= (x << 13) & MASK
        x ^= x >> 17
        x ^= (x << 5) & MASK
        self.s = x & MASK
        return self.s


def load_lines(path: str) -> List[Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data["lines"] if isinstance(data, dict) else data


class DialoguePicker:
    def __init__(self, lines: List[Dict[str, Any]], config: Dict[str, Any], level_id: str):
        self.lines = lines
        self.allowed_moods: Dict[str, List[str]] = config.get("allowed_moods", {})
        self.recent_window: int = int(config.get("recent_window", 3))
        self.level_id = level_id
        self.calls = 0
        self.recent: List[str] = []

    # ------------------------------------------------------------ public API
    def say(self, trigger: str, ctx: Dict[str, Any]) -> Dict[str, Any]:
        """Pick a mood and a cached line. result = {mood, line ({} if none), tier, repeated}."""
        rng = self._new_rng()
        mood = self._choose_mood(ctx, rng)
        picked = self._pick_line(trigger, ctx, mood, rng)
        self.calls += 1
        if picked["line"]:
            self.remember(picked["line"]["id"])
        return {"mood": mood, **picked}

    def choose_mood(self, ctx: Dict[str, Any]) -> str:
        """Mood only, for the live-AI path (the LLM writes the line, this picks the mood)."""
        rng = self._new_rng()
        mood = self._choose_mood(ctx, rng)
        self.calls += 1
        return mood

    def remember(self, entry: str) -> None:
        """Record a spoken line (a cached line id, or the text of an AI-written line)."""
        self.recent.append(entry)
        if self.recent_window <= 0:
            self.recent.clear()
        while len(self.recent) > self.recent_window:
            self.recent.pop(0)

    def recent_texts(self) -> List[str]:
        """Last lines as text, for the 'Do not repeat' part of the AI prompt."""
        by_id = {l["id"]: l["text"] for l in self.lines}
        return [by_id.get(e, e) for e in self.recent]

    # ------------------------------------------------------------ internals
    def _new_rng(self) -> Rng:
        return Rng(seed_from_string(f"{self.level_id}#{self.calls}"))

    def _choose_mood(self, ctx: Dict[str, Any], rng: Rng) -> str:
        act = int(ctx.get("act", 1))
        spirit_mood = str(ctx.get("spirit_mood", "amused"))
        weights = ctx.get("mood_weights") or {spirit_mood: 1.0}
        allowed = self.allowed_moods.get(str(act), [])
        picks = []
        total = 0
        for m in sorted(weights):
            if allowed and m not in allowed:
                continue
            w = int(float(weights[m]) * 1000.0 + 0.5)
            if w <= 0:
                continue
            picks.append((m, w))
            total += w
        r = rng.next_u32()  # always one draw, so the line draw is stable
        if not picks:
            return allowed[0] if allowed else spirit_mood
        t = r % total
        for m, w in picks:
            if t < w:
                return m
            t -= w
        return picks[-1][0]

    def _pick_line(self, trigger: str, ctx: Dict[str, Any], mood: str, rng: Rng) -> Dict[str, Any]:
        act = int(ctx.get("act", 1))
        tiers: List[List[Dict[str, Any]]] = [[], [], [], []]
        for l in self.lines:
            if l.get("trigger") != trigger:
                continue
            la = int(l.get("act", 1))
            if la > act:
                continue
            same_act = la == act
            same_mood = l.get("mood") == mood
            if same_act and same_mood:
                tiers[0].append(l)
            if same_act:
                tiers[1].append(l)
            if same_mood:
                tiers[2].append(l)
            tiers[3].append(l)
        first_nonempty: Optional[int] = None
        for t in range(4):
            cands = sorted(tiers[t], key=lambda l: l["id"])
            if not cands:
                continue
            if first_nonempty is None:
                first_nonempty = t
            fresh = [c for c in cands if c["id"] not in self.recent]
            if fresh:
                return {"line": fresh[rng.next_u32() % len(fresh)], "tier": t, "repeated": False}
        rng.next_u32()  # keep the draw count identical on every path
        if first_nonempty is None:
            return {"line": {}, "tier": -1, "repeated": False}
        # Everything was said recently. Repeat the line said longest ago, from the best tier that
        # offers anything other than the line just spoken.
        last = self.recent[-1] if self.recent else None
        for t in range(4):
            others = [c for c in sorted(tiers[t], key=lambda l: l["id"]) if c["id"] != last]
            if others:
                oldest = min(others, key=lambda c: self.recent.index(c["id"]) if c["id"] in self.recent else -1)
                return {"line": oldest, "tier": t, "repeated": True}
        only = sorted(tiers[first_nonempty], key=lambda l: l["id"])[0]
        return {"line": only, "tier": first_nonempty, "repeated": True}
