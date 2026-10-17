"""Load levels from JSON. Validation errors always name the offending field,
for example: "objects[1].ash_link.hour: must be an integer from 0 to 5, got 9".
"""
from __future__ import annotations

import json
from typing import Any, Dict, List, Tuple

from .model import (
    CHASM, EXIT, FLOOR, NUM_HOURS, TERRAIN_CHARS, WALL,
    AshLink, GameObject, Level, ObjState, Pos, Shadow, StateProps, TypeDef,
    default_types,
)


class LevelError(ValueError):
    """Raised when a level file is invalid. The message starts with the field path."""


def _fail(path: str, msg: str):
    raise LevelError(f"{path}: {msg}")


def _int(d: Dict[str, Any], key: str, path: str, lo: int, hi: int, default=None) -> int:
    if key not in d:
        if default is not None:
            return default
        _fail(f"{path}.{key}", "is required")
    v = d[key]
    if isinstance(v, bool) or not isinstance(v, int) or not lo <= v <= hi:
        _fail(f"{path}.{key}", f"must be an integer from {lo} to {hi}, got {v!r}")
    return v


def _dict(v: Any, path: str) -> Dict[str, Any]:
    if not isinstance(v, dict):
        _fail(path, f"must be an object, got {type(v).__name__}")
    return v


def _list(v: Any, path: str) -> List[Any]:
    if not isinstance(v, list):
        _fail(path, f"must be a list, got {type(v).__name__}")
    return v


def _pos(d: Dict[str, Any], path: str, w: int, h: int) -> Pos:
    d = _dict(d, path)
    return (
        _int(d, "hour", path, 0, NUM_HOURS - 1),
        _int(d, "x", path, 0, w - 1),
        _int(d, "y", path, 0, h - 1),
    )


def _parse_types(raw: Any) -> Dict[str, TypeDef]:
    types = default_types()
    if raw is None:
        return types
    for name, spec in _dict(raw, "types").items():
        p = f"types.{name}"
        spec = _dict(spec, p)
        base = types.get(name)
        td = TypeDef(name, flammable=bool(spec.get("flammable", base.flammable if base else False)),
                     props=dict(base.props) if base else {})
        for state in ObjState:
            if state.value in spec:
                sp = _dict(spec[state.value], f"{p}.{state.value}")
                td.props[state.value] = StateProps(
                    blocks_movement=bool(sp.get("blocks_movement", False)),
                    fills_chasm=bool(sp.get("fills_chasm", False)),
                )
        types[name] = td
    return types


def load_level_from_dict(data: Dict[str, Any]) -> Level:
    data = _dict(data, "level")
    name = str(data.get("name", "unnamed"))
    apH = _int(data, "actions_per_hour", "level", 1, 1000, default=3)
    w = _int(data, "width", "level", 1, 40)
    h = _int(data, "height", "level", 1, 40)
    types = _parse_types(data.get("types"))

    # --- terrain
    terrain: Dict[int, Tuple[str, ...]] = {
        i: tuple(FLOOR * w for _ in range(h)) for i in range(NUM_HOURS)
    }
    for key, rows in _dict(data.get("hours", {}), "hours").items():
        p = f"hours.{key}"
        if not (isinstance(key, str) and key.isdigit() and 0 <= int(key) < NUM_HOURS):
            _fail(p, f"hour index must be 0 to {NUM_HOURS - 1}")
        rows = _list(rows, p)
        if len(rows) != h:
            _fail(p, f"must have {h} rows, got {len(rows)}")
        for r, row in enumerate(rows):
            if not isinstance(row, str) or len(row) != w:
                _fail(f"{p}[{r}]", f"must be a string of {w} characters, got {row!r}")
            bad = [c for c in row if c not in TERRAIN_CHARS]
            if bad:
                _fail(f"{p}[{r}]", f"unknown terrain character {bad[0]!r} (use . # ~ E)")
        terrain[int(key)] = tuple(rows)
    if not any(EXIT in row for rows in terrain.values() for row in rows):
        _fail("hours", "level has no exit tile ('E')")

    def tile(pos: Pos) -> str:
        return terrain[pos[0]][pos[2]][pos[1]]

    # --- player
    player = _pos(data.get("player"), "player", w, h) if "player" in data else _fail("player", "is required")
    if tile(player) in (WALL, CHASM):
        _fail("player", "start tile must be walkable")

    # --- objects
    objects: List[GameObject] = []
    seen = set()
    for i, raw in enumerate(_list(data.get("objects", []), "objects")):
        p = f"objects[{i}]"
        raw = _dict(raw, p)
        oid = raw.get("id")
        if not isinstance(oid, str) or not oid:
            _fail(f"{p}.id", "must be a non-empty string")
        if oid in seen:
            _fail(f"{p}.id", f"duplicate id {oid!r}")
        seen.add(oid)
        otype = raw.get("type")
        if otype not in types:
            _fail(f"{p}.type", f"unknown type {otype!r} (known: {', '.join(sorted(types))})")
        hr, x, y = _pos(raw, p, w, h)
        state_raw = raw.get("state", ObjState.INTACT.value)
        if state_raw not in {s.value for s in ObjState}:
            _fail(f"{p}.state", f"must be one of INTACT, ASH, GONE, got {state_raw!r}")
        state = ObjState(state_raw)
        link = None
        if raw.get("ash_link") is not None:
            lp = f"{p}.ash_link"
            lraw = _dict(raw["ash_link"], lp)
            lh, lx, ly = _pos(lraw, lp, w, h)
            ntype = lraw.get("new_type")
            if ntype not in types:
                _fail(f"{lp}.new_type", f"unknown type {ntype!r} (known: {', '.join(sorted(types))})")
            if terrain[lh][ly][lx] == WALL:
                _fail(lp, "target tile is a wall")
            link = AshLink(lh, lx, ly, ntype)
        flammable = raw.get("flammable", types[otype].flammable)
        objects.append(GameObject(oid, otype, hr, x, y, state, bool(flammable), link))

    # --- shadows
    shadows: List[Shadow] = []
    sseen = set()
    for i, raw in enumerate(_list(data.get("shadows", []), "shadows")):
        p = f"shadows[{i}]"
        raw = _dict(raw, p)
        sid = raw.get("id", f"shadow{i}")
        if sid in sseen:
            _fail(f"{p}.id", f"duplicate id {sid!r}")
        sseen.add(sid)
        pos = _pos(raw, p, w, h)
        if tile(pos) == WALL:
            _fail(p, "shadow is placed on a wall")
        shadows.append(Shadow(sid, *pos))

    # --- doorways
    doorways: Dict[Pos, Pos] = {}
    for i, raw in enumerate(_list(data.get("doorways", []), "doorways")):
        p = f"doorways[{i}]"
        raw = _dict(raw, p)
        a = _pos(raw.get("a"), f"{p}.a", w, h) if "a" in raw else _fail(f"{p}.a", "is required")
        b = _pos(raw.get("b"), f"{p}.b", w, h) if "b" in raw else _fail(f"{p}.b", "is required")
        if a == b:
            _fail(p, "both ends are the same tile")
        for end, pos in (("a", a), ("b", b)):
            if tile(pos) != FLOOR:
                _fail(f"{p}.{end}", "doorway tiles must be plain floor ('.')")
            if pos in doorways:
                _fail(f"{p}.{end}", "tile is already part of another doorway")
        doorways[a] = b
        doorways[b] = a

    return Level(
        name=name, actions_per_hour=apH, width=w, height=h, terrain=terrain, types=types,
        player_start=player, objects=tuple(objects), shadows=tuple(shadows), doorways=doorways,
    )


def load_level(path: str) -> Level:
    with open(path, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise LevelError(f"{path}: invalid JSON ({e})") from e
    return load_level_from_dict(data)
