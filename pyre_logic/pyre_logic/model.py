"""Core data model for the Pyre of the Hours logic layer.

Pure Python. No graphics, audio, input, timing or engine dependencies.
Everything here is deterministic and cheap to copy, so it can be unit tested,
solved by search, and later ported to GDScript or C# almost line by line.
"""
from __future__ import annotations

from dataclasses import dataclass, field, replace
from enum import Enum
from typing import Dict, List, Optional, Tuple

NUM_HOURS = 6
CLOCK_POSITIONS = (12, 2, 4, 6, 8, 10)  # hour index -> position on the clock face

# Terrain characters used in level files.
FLOOR, WALL, CHASM, EXIT = ".", "#", "~", "E"
TERRAIN_CHARS = (FLOOR, WALL, CHASM, EXIT)

# Screen-style grid: y grows downward, so N is y-1.
DIRS: Dict[str, Tuple[int, int]] = {"N": (0, -1), "E": (1, 0), "S": (0, 1), "W": (-1, 0)}

Pos = Tuple[int, int, int]  # (hour, x, y)


class ObjState(str, Enum):
    INTACT = "INTACT"
    ASH = "ASH"
    GONE = "GONE"  # reserved: no built-in action produces it yet


class ShadowState(str, Enum):
    INACTIVE = "INACTIVE"
    ACTIVE = "ACTIVE"
    DESTROYED = "DESTROYED"


class Status(str, Enum):
    PLAYING = "PLAYING"
    WON = "WON"
    FAILED = "FAILED"


# ---------------------------------------------------------------- actions
MOVE, BURN, WAIT = "move", "burn", "wait"


@dataclass(frozen=True)
class Action:
    kind: str
    dir: Optional[str] = None

    @staticmethod
    def move(d: str) -> "Action":
        return Action(MOVE, d)

    @staticmethod
    def burn(d: str) -> "Action":
        return Action(BURN, d)

    @staticmethod
    def wait() -> "Action":
        return Action(WAIT)

    def __str__(self) -> str:
        return self.kind if self.dir is None else f"{self.kind} {self.dir}"


ALL_ACTIONS: Tuple[Action, ...] = tuple(
    [Action.move(d) for d in DIRS] + [Action.burn(d) for d in DIRS] + [Action.wait()]
)


# ---------------------------------------------------------------- object types
@dataclass
class StateProps:
    blocks_movement: bool = False
    fills_chasm: bool = False


_NO_PROPS = StateProps()


@dataclass
class TypeDef:
    """What an object type does in each of its states."""

    name: str
    flammable: bool = False
    props: Dict[str, StateProps] = field(default_factory=dict)  # keyed by ObjState value

    def props_for(self, state: ObjState) -> StateProps:
        return self.props.get(state.value, _NO_PROPS)


def default_types() -> Dict[str, TypeDef]:
    """Built-in object types. Levels may add or override types in their JSON."""
    I = ObjState.INTACT.value
    return {
        # Lying on the floor; only useful as something to burn.
        "plank": TypeDef("plank", flammable=True),
        # Bridges and gates are the classic ash-transfer pieces.
        "bridge": TypeDef("bridge", True, {I: StateProps(fills_chasm=True)}),
        "gate": TypeDef("gate", True, {I: StateProps(blocks_movement=True)}),
        "crate": TypeDef("crate", True, {I: StateProps(blocks_movement=True)}),
        "stone": TypeDef("stone", False, {I: StateProps(blocks_movement=True)}),
        # What ash turns into on the far side of an ash link.
        "ash_bridge": TypeDef("ash_bridge", False, {I: StateProps(fills_chasm=True)}),
        "ash_path": TypeDef("ash_path", False, {I: StateProps(fills_chasm=True)}),
    }


# ---------------------------------------------------------------- level content
@dataclass(frozen=True)
class AshLink:
    hour: int
    x: int
    y: int
    new_type: str


@dataclass
class GameObject:
    id: str
    type: str
    hour: int
    x: int
    y: int
    state: ObjState = ObjState.INTACT
    flammable: bool = True
    ash_link: Optional[AshLink] = None


@dataclass
class Shadow:
    id: str
    hour: int
    x: int
    y: int
    state: ShadowState = ShadowState.INACTIVE


@dataclass
class Level:
    """Static, never-mutated description of a level."""

    name: str
    actions_per_hour: int
    width: int
    height: int
    terrain: Dict[int, Tuple[str, ...]]  # hour -> rows (height strings of width chars)
    types: Dict[str, TypeDef]
    player_start: Pos
    objects: Tuple[GameObject, ...]
    shadows: Tuple[Shadow, ...]
    doorways: Dict[Pos, Pos]  # both directions are stored

    def in_bounds(self, x: int, y: int) -> bool:
        return 0 <= x < self.width and 0 <= y < self.height

    def terrain_at(self, hour: int, x: int, y: int) -> str:
        return self.terrain[hour][y][x]


# ---------------------------------------------------------------- game state
@dataclass
class GameState:
    """Dynamic state. `apply()` never mutates a state it is given; it returns a copy."""

    level: Level
    player: Pos
    objects: List[GameObject]
    shadows: List[Shadow]
    action_count: int = 0
    status: Status = Status.PLAYING
    fail_reason: Optional[str] = None

    @staticmethod
    def initial(level: Level) -> "GameState":
        return GameState(
            level=level,
            player=level.player_start,
            objects=[replace(o) for o in level.objects],
            shadows=[replace(s) for s in level.shadows],
        )

    @property
    def sun_hour(self) -> int:
        """Number of hours the sun has passed (0..6)."""
        return min(self.action_count // self.level.actions_per_hour, NUM_HOURS)

    def hour_passed(self, hour: int) -> bool:
        return hour < self.sun_hour

    def clone(self) -> "GameState":
        return GameState(
            level=self.level,  # shared, immutable
            player=self.player,
            objects=[replace(o) for o in self.objects],
            shadows=[replace(s) for s in self.shadows],
            action_count=self.action_count,
            status=self.status,
            fail_reason=self.fail_reason,
        )

    def key(self) -> tuple:
        """Hashable fingerprint of the full state, used by the solver and tests."""
        return (
            self.player,
            self.action_count,
            self.status.value,
            tuple(sorted((o.id, o.state.value) for o in self.objects)),
            tuple(sorted((s.id, s.state.value) for s in self.shadows)),
        )
