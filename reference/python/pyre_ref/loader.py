"""Load levels (section 6.1 format). Errors always start with the offending field path,
for example: "objects[1].ash_link.slot: ..." so a level author can fix them fast.
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Tuple

from .model import (
    CHASM, FLOOR, HOURS, INTACT, NUM_HOURS, OBJ_STATES, TERRAIN_CHARS, TYPES, WALL,
    AshLink, GameObject, Level, Shadow, StairLink,
)

MOODS = ("amused", "annoyed", "triumphant", "menacing")


class LevelError(ValueError):
    """Raised for an invalid level file; the message starts with the field path."""


def _fail(path: str, msg: str):
    raise LevelError(f"{path}: {msg}")


def _dict(v: Any, path: str) -> Dict[str, Any]:
    if not isinstance(v, dict):
        _fail(path, f"must be an object, got {type(v).__name__}")
    return v


def _list(v: Any, path: str) -> List[Any]:
    if not isinstance(v, list):
        _fail(path, f"must be a list, got {type(v).__name__}")
    return v


def _int(d: Dict[str, Any], key: str, path: str, lo: int, hi: int, default=None) -> int:
    if key not in d:
        if default is not None:
            return default
        _fail(f"{path}.{key}", "is required")
    v = d[key]
    if isinstance(v, bool) or not isinstance(v, int) or not lo <= v <= hi:
        _fail(f"{path}.{key}", f"must be an integer from {lo} to {hi}, got {v!r}")
    return v


def _hour(d: Dict[str, Any], path: str) -> int:
    if "hour" not in d:
        _fail(f"{path}.hour", "is required")
    v = d["hour"]
    if isinstance(v, bool) or v not in HOURS:
        _fail(f"{path}.hour", f"must be one of {list(HOURS)}, got {v!r}")
    return v


def _slot(d: Dict[str, Any], path: str, w: int, h: int) -> Tuple[int, int]:
    if "slot" not in d:
        _fail(f"{path}.slot", "is required")
    s = d["slot"]
    ok = (isinstance(s, list) and len(s) == 2
          and all(isinstance(n, int) and not isinstance(n, bool) for n in s))
    if not ok:
        _fail(f"{path}.slot", f"must be [x, y] integers, got {s!r}")
    if not (0 <= s[0] < w and 0 <= s[1] < h):
        _fail(f"{path}.slot", f"{s!r} is outside the {w}x{h} grid")
    return s[0], s[1]


def load_level_from_dict(data: Dict[str, Any]) -> Level:
    data = _dict(data, "level")
    lid = data.get("id")
    if not isinstance(lid, str) or not lid:
        _fail("id", "must be a non-empty string")
    title = str(data.get("title", lid))
    act = _int(data, "act", "level", 1, 3, default=1)
    mood = data.get("spirit_mood", "amused")
    if mood not in MOODS:
        _fail("spirit_mood", f"must be one of {list(MOODS)}, got {mood!r}")
    weights = data.get("mood_weights")
    if weights is not None:
        weights = _dict(weights, "mood_weights")
        for k, v in weights.items():
            if k not in MOODS or not isinstance(v, (int, float)) or v < 0:
                _fail(f"mood_weights.{k}", "unknown mood or negative weight")

    grid = _dict(data.get("grid", {"w": 5, "h": 5}), "grid")
    w = _int(grid, "w", "grid", 1, 40, default=5)
    h = _int(grid, "h", "grid", 1, 40, default=5)
    sun = _dict(data.get("sun", {}), "sun")
    start_index = _int(sun, "start_index", "sun", 0, NUM_HOURS - 1, default=0)
    apH = _int(sun, "actions_per_hour", "sun", 1, 1000, default=3)

    # --- terrain (rooms not listed are all floor)
    terrain = {hr: tuple(FLOOR * w for _ in range(h)) for hr in HOURS}
    seen_rooms = set()
    for i, room in enumerate(_list(data.get("rooms", []), "rooms")):
        p = f"rooms[{i}]"
        room = _dict(room, p)
        hr = _hour(room, p)
        if hr in seen_rooms:
            _fail(f"{p}.hour", f"room {hr} is listed twice")
        seen_rooms.add(hr)
        rows = _list(room.get("terrain"), f"{p}.terrain")
        if len(rows) != h:
            _fail(f"{p}.terrain", f"must have {h} rows, got {len(rows)}")
        for r, row in enumerate(rows):
            if not isinstance(row, str) or len(row) != w:
                _fail(f"{p}.terrain[{r}]", f"must be a string of {w} characters, got {row!r}")
            bad = [c for c in row if c not in TERRAIN_CHARS]
            if bad:
                _fail(f"{p}.terrain[{r}]", f"unknown terrain character {bad[0]!r} (use . # ~)")
        terrain[hr] = tuple(rows)

    # --- objects
    objects: List[GameObject] = []
    ids, slots = set(), {}
    for i, raw in enumerate(_list(data.get("objects", []), "objects")):
        p = f"objects[{i}]"
        raw = _dict(raw, p)
        oid = raw.get("id")
        if not isinstance(oid, str) or not oid:
            _fail(f"{p}.id", "must be a non-empty string")
        if oid in ids:
            _fail(f"{p}.id", f"duplicate id {oid!r}")
        ids.add(oid)
        otype = raw.get("type")
        if otype not in TYPES:
            _fail(f"{p}.type", f"unknown type {otype!r} (known: {', '.join(sorted(TYPES))})")
        hr = _hour(raw, p)
        x, y = _slot(raw, p, w, h)
        if (hr, x, y) in slots:
            _fail(f"{p}.slot", f"slot already holds object {slots[(hr, x, y)]!r} (one object per slot)")
        slots[(hr, x, y)] = oid
        tile = terrain[hr][y][x]
        if tile == WALL:
            _fail(f"{p}.slot", "object is placed on a wall")
        if tile == CHASM and otype not in ("bridge", "ash_path"):
            _fail(f"{p}.slot", f"{otype} placed on a chasm (only a bridge or ash_path may sit on a chasm)")
        state = raw.get("state", INTACT)
        if state not in OBJ_STATES:
            _fail(f"{p}.state", f"must be one of {list(OBJ_STATES)}, got {state!r}")
        if "flammable" not in raw:
            _fail(f"{p}.flammable", "is required (true or false)")
        flammable = raw["flammable"]
        if not isinstance(flammable, bool):
            _fail(f"{p}.flammable", "must be true or false")
        objects.append(GameObject(oid, otype, hr, x, y, state, flammable))

    for i, (raw, obj) in enumerate(zip(data.get("objects", []), objects)):
        p = f"objects[{i}]"
        if raw.get("ash_link") is not None:
            lp = f"{p}.ash_link"
            lraw = _dict(raw["ash_link"], lp)
            lh, (lx, ly) = _hour(lraw, lp), _slot(lraw, lp, w, h)
            becomes = lraw.get("becomes")
            if becomes not in TYPES:
                _fail(f"{lp}.becomes", f"unknown type {becomes!r} (known: {', '.join(sorted(TYPES))})")
            if terrain[lh][ly][lx] == WALL:
                _fail(f"{lp}.slot", "target is a wall")
            if (lh, lx, ly) in slots:
                _fail(f"{lp}.slot", f"target already holds object {slots[(lh, lx, ly)]!r}")
            obj.ash_link = AshLink(lh, lx, ly, becomes)
        if obj.type == "stair":
            if raw.get("links_to") is None:
                _fail(f"{p}.links_to", "a stair needs links_to")
            lp = f"{p}.links_to"
            lraw = _dict(raw["links_to"], lp)
            lh, (lx, ly) = _hour(lraw, lp), _slot(lraw, lp, w, h)
            if terrain[lh][ly][lx] == WALL:
                _fail(f"{lp}.slot", "arrival slot is a wall")
            obj.links_to = StairLink(lh, lx, ly)
        elif raw.get("links_to") is not None:
            _fail(f"{p}.links_to", "only stairs have links_to")

    exits = [o.id for o in objects if o.type == "exit"]
    if not exits:
        _fail("objects", "level has no exit object (exactly one is required)")
    if len(exits) > 1:
        _fail("objects", f"{len(exits)} exit objects ({', '.join(exits)}), exactly one is required")
    for o in objects:
        if o.ash_link is not None and f"{o.id}_ash" in ids:
            _fail("objects", f"id {o.id + '_ash'!r} clashes with the object {o.id!r} creates when burned")

    # --- player
    praw = _dict(data.get("player"), "player") if "player" in data else _fail("player", "is required")
    ph = _hour(praw, "player")
    px, py = _slot(praw, "player", w, h)
    if terrain[ph][py][px] == WALL:
        _fail("player.slot", "start tile is a wall")
    here = slots.get((ph, px, py))
    if terrain[ph][py][px] == CHASM and not (
            here and next(o for o in objects if o.id == here).type in ("bridge", "ash_path")):
        _fail("player.slot", "start tile is a chasm")

    if here is not None:
        hobj = next(o for o in objects if o.id == here)
        if hobj.state == INTACT and hobj.type in ("crate", "door"):
            _fail("player.slot", f"start tile holds INTACT {hobj.type} {hobj.id!r}, which blocks")

    # --- shadows
    shadows: List[Shadow] = []
    sids = set()
    for i, raw in enumerate(_list(data.get("shadows", []), "shadows")):
        p = f"shadows[{i}]"
        raw = _dict(raw, p)
        sid = raw.get("id", f"sh{i}")
        if sid in sids:
            _fail(f"{p}.id", f"duplicate id {sid!r}")
        sids.add(sid)
        sh = _hour(raw, p)
        sx, sy = _slot(raw, p, w, h)
        if sid in ids:
            _fail(f"{p}.id", f"id {sid!r} is also used by an object")
        if terrain[sh][sy][sx] == WALL:
            _fail(f"{p}.slot", "shadow is placed on a wall")
        there = slots.get((sh, sx, sy))
        if there and next(o for o in objects if o.id == there).type == "exit":
            _fail(f"{p}.slot", "shadow is placed on the exit")
        if (sh, sx, sy) == (ph, px, py):
            _fail(f"{p}.slot", "shadow is placed on the player start")
        shadows.append(Shadow(sid, sh, sx, sy))

    par = data.get("par_actions")
    if par is not None and (isinstance(par, bool) or not isinstance(par, int) or par < 1):
        _fail("par_actions", f"must be a positive integer, got {par!r}")

    return Level(lid, title, act, mood, weights, w, h, start_index, apH, terrain,
                 (ph, px, py), tuple(objects), tuple(shadows), par)


def load_level(path: str) -> Level:
    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise LevelError(f"{path}: invalid JSON ({e})") from e
    return load_level_from_dict(data)
