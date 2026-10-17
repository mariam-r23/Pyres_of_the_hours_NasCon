"""Data model for the Pyre of the Hours reference implementation.

Pure Python, no graphics/audio/UI. Follows PROJECT_CONTEXT.md section 3 (the source of truth)
and the API names of section 6.2 so the GDScript port can mirror it line by line.

Hours are the clock labels used in level files: 12, 2, 4, 6, 8, 10.
A position is (hour, x, y). A slot is [x, y] with [0, 0] top-left.
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Dict, FrozenSet, List, Optional, Tuple

HOURS = (12, 2, 4, 6, 8, 10)  # sun order; an hour's order index is its position here
NUM_HOURS = len(HOURS)

FLOOR, WALL, CHASM = ".", "#", "~"
TERRAIN_CHARS = (FLOOR, WALL, CHASM)

DIRS: Dict[str, Tuple[int, int]] = {
    "up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0),
}

INTACT, ASH, GONE = "INTACT", "ASH", "GONE"
OBJ_STATES = (INTACT, ASH, GONE)
PLAYING, WON, FAILED = "playing", "won", "failed"  # section 11 item 15

Pos = Tuple[int, int, int]  # (hour, x, y)


def order_index(hour: int) -> int:
    return HOURS.index(hour)


@dataclass(frozen=True)
class TypeDef:
    """What an object type does (section 3.2)."""
    flammable: bool
    blocks: FrozenSet[str]  # states in which the object blocks movement
    fills: FrozenSet[str]   # states in which it makes a chasm tile passable


# Section 3.2. key and torch are cut from the default scope; shadows are not objects.
TYPES: Dict[str, TypeDef] = {
    "bridge":   TypeDef(True,  frozenset(),        frozenset({INTACT})),
    "ash_path": TypeDef(False, frozenset(),        frozenset({INTACT})),
    "crate":    TypeDef(True,  frozenset({INTACT}), frozenset()),
    "door":     TypeDef(True,  frozenset({INTACT}), frozenset()),
    "stair":    TypeDef(False, frozenset(),        frozenset()),
    "exit":     TypeDef(False, frozenset(),        frozenset()),
}


@dataclass(frozen=True)
class AshLink:
    hour: int
    x: int
    y: int
    becomes: str


@dataclass(frozen=True)
class StairLink:
    hour: int
    x: int
    y: int


@dataclass
class GameObject:
    id: str
    type: str
    hour: int
    x: int
    y: int
    state: str = INTACT
    flammable: bool = False
    ash_link: Optional[AshLink] = None
    links_to: Optional[StairLink] = None


@dataclass(frozen=True)
class Shadow:
    id: str
    hour: int
    x: int
    y: int


@dataclass(frozen=True)
class Level:
    """Static, never mutated."""
    id: str
    title: str
    act: int
    spirit_mood: str
    mood_weights: Optional[Dict[str, float]]
    w: int
    h: int
    start_index: int
    actions_per_hour: int
    terrain: Dict[int, Tuple[str, ...]]  # hour -> rows
    player_start: Pos
    objects: Tuple[GameObject, ...]
    shadows: Tuple[Shadow, ...]
    par_actions: Optional[int]

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    def terrain_at(self, hour: int, x: int, y: int) -> str:
        return self.terrain[hour][y][x]


class GameState:
    """Dynamic state. apply_action never mutates a state it is given."""

    def __init__(self, level: Level, player: Pos, objects: List[GameObject],
                 destroyed: FrozenSet[str] = frozenset(), action_count: int = 0,
                 status: str = PLAYING, fail_reason: Optional[str] = None):
        self.level = level
        self.player = player
        self.objects = objects
        self.destroyed = destroyed
        self.action_count = action_count
        self.status = status
        self.fail_reason = fail_reason

    @staticmethod
    def initial(level: Level) -> "GameState":
        return GameState(level, level.player_start, [replace(o) for o in level.objects])

    @property
    def sun_index(self) -> int:
        """sun_index = start_index + floor(action_count / actions_per_hour)  (section 3.5)."""
        return self.level.start_index + self.action_count // self.level.actions_per_hour

    def is_hour_passed(self, hour: int) -> bool:
        return order_index(hour) < self.sun_index

    def shadow_active(self, s: Shadow) -> bool:
        return s.id not in self.destroyed and self.is_hour_passed(s.hour)

    def duplicate_deep(self) -> "GameState":
        return GameState(self.level, self.player, [replace(o) for o in self.objects],
                         self.destroyed, self.action_count, self.status, self.fail_reason)

    def hash_key(self) -> str:
        """Canonical string of the full state, used by the solver."""
        objs = ";".join(sorted(
            f"{o.id}:{o.type}:{o.hour}:{o.x}:{o.y}:{o.state}" for o in self.objects))
        dead = ",".join(sorted(self.destroyed))
        return f"{self.player}|{self.action_count}|{self.status}|{objs}|{dead}"
