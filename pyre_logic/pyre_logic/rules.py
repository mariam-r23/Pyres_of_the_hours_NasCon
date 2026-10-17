"""The rules of Pyre of the Hours as one pure function: apply(state, action).

Order of resolution for every VALID action:
  1. The action itself (move / burn / wait).
  2. action_count += 1.
  3. The sun may advance; hours it passes activate their shadows.
  4. Outcome: win beats caught beats day-ended.

Invalid actions change nothing and consume nothing.
The returned events are what a presentation layer (animation, sound, camera)
listens to. The logic itself never plays anything.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

from .model import (
    BURN, CHASM, DIRS, EXIT, MOVE, NUM_HOURS, WAIT, WALL,
    Action, GameObject, GameState, ObjState, Pos, ShadowState, Status,
)


@dataclass
class Event:
    kind: str
    data: Dict[str, object] = field(default_factory=dict)

    def __repr__(self) -> str:
        return f"{self.kind}({', '.join(f'{k}={v}' for k, v in self.data.items())})"


@dataclass
class Result:
    valid: bool
    state: GameState  # the new state if valid, otherwise the untouched input state
    events: List[Event]
    reason: Optional[str] = None  # why an action was invalid


# ---------------------------------------------------------------- queries
def objects_at(state: GameState, hour: int, x: int, y: int) -> List[GameObject]:
    return [o for o in state.objects if (o.hour, o.x, o.y) == (hour, x, y)]


def active_shadow_at(state: GameState, hour: int, x: int, y: int) -> bool:
    return any(
        s.state == ShadowState.ACTIVE and (s.hour, s.x, s.y) == (hour, x, y)
        for s in state.shadows
    )


def blocked_reason(state: GameState, hour: int, x: int, y: int) -> Optional[str]:
    """None if the player may stand on this tile, otherwise a short reason."""
    lv = state.level
    if not lv.in_bounds(x, y):
        return "out_of_bounds"
    terrain = lv.terrain_at(hour, x, y)
    if terrain == WALL:
        return "wall"
    objs = objects_at(state, hour, x, y)
    if any(lv.types[o.type].props_for(o.state).blocks_movement for o in objs):
        return "blocked"
    if terrain == CHASM and not any(
        lv.types[o.type].props_for(o.state).fills_chasm for o in objs
    ):
        return "chasm"
    if active_shadow_at(state, hour, x, y):
        return "shadow"
    return None


# ---------------------------------------------------------------- apply
def apply(state: GameState, action: Action) -> Result:
    if state.status != Status.PLAYING:
        return Result(False, state, [], "level_over")

    new = state.clone()
    events: List[Event] = []
    reached_exit = False

    if action.kind == WAIT:
        pass
    elif action.kind == MOVE:
        reason = _do_move(new, action, events)
        if reason:
            return Result(False, state, [], reason)
        reached_exit = new.level.terrain_at(*new.player) == EXIT
    elif action.kind == BURN:
        reason = _do_burn(new, action, events)
        if reason:
            return Result(False, state, [], reason)
    else:
        return Result(False, state, [], "unknown_action")

    before = new.sun_hour
    new.action_count += 1
    _advance_sun(new, before, events)
    _resolve_outcome(new, reached_exit, events)
    return Result(True, new, events)


def _do_move(new: GameState, action: Action, events: List[Event]) -> Optional[str]:
    if action.dir not in DIRS:
        return "bad_direction"
    hour, x, y = new.player
    dx, dy = DIRS[action.dir]
    dest: Pos = (hour, x + dx, y + dy)

    reason = blocked_reason(new, *dest)
    if reason:
        return reason

    final = dest
    partner = new.level.doorways.get(dest)
    if partner is not None:
        if blocked_reason(new, *partner):
            return "doorway_blocked"
        final = partner

    events.append(Event("Moved", {"from": new.player, "to": dest}))
    if partner is not None:
        events.append(Event("DoorwayTraversed", {"from": dest, "to": partner}))
    new.player = final
    return None


def _do_burn(new: GameState, action: Action, events: List[Event]) -> Optional[str]:
    if action.dir not in DIRS:
        return "bad_direction"
    lv = new.level
    hour, x, y = new.player
    dx, dy = DIRS[action.dir]
    tx, ty = x + dx, y + dy
    if not lv.in_bounds(tx, ty):
        return "out_of_bounds"

    targets = [
        o for o in new.objects
        if (o.hour, o.x, o.y) == (hour, tx, ty) and o.state == ObjState.INTACT and o.flammable
    ]
    if not targets:
        return "nothing_to_burn"

    for obj in sorted(targets, key=lambda o: o.id):
        obj.state = ObjState.ASH
        events.append(Event("Burned", {"id": obj.id, "at": (hour, tx, ty)}))
        link = obj.ash_link
        if link is not None:
            created = GameObject(
                id=f"{obj.id}>ash",
                type=link.new_type,
                hour=link.hour, x=link.x, y=link.y,
                state=ObjState.INTACT,
                flammable=lv.types[link.new_type].flammable,
            )
            new.objects.append(created)
            events.append(Event("AshMoved", {
                "from": (hour, tx, ty),
                "to": (link.hour, link.x, link.y),
                "new_id": created.id,
                "new_type": link.new_type,
            }))

    # Fire destroys every ACTIVE shadow on or next to the burned tile.
    for s in new.shadows:
        if (
            s.state == ShadowState.ACTIVE
            and s.hour == hour
            and abs(s.x - tx) + abs(s.y - ty) <= 1
        ):
            s.state = ShadowState.DESTROYED
            events.append(Event("ShadowDestroyed", {"id": s.id, "at": (s.hour, s.x, s.y)}))
    return None


def _advance_sun(new: GameState, before: int, events: List[Event]) -> None:
    after = new.sun_hour
    if after == before:
        return
    events.append(Event("SunAdvanced", {"from": before, "to": after}))
    for hour in range(before, after):
        events.append(Event("HourPassed", {"hour": hour}))
        for s in new.shadows:
            if s.hour == hour and s.state == ShadowState.INACTIVE:
                s.state = ShadowState.ACTIVE
                events.append(Event("ShadowActivated", {"id": s.id, "at": (s.hour, s.x, s.y)}))


def _resolve_outcome(new: GameState, reached_exit: bool, events: List[Event]) -> None:
    if reached_exit:
        new.status = Status.WON
        events.append(Event("LevelWon", {"actions": new.action_count}))
    elif active_shadow_at(new, *new.player):
        new.status = Status.FAILED
        new.fail_reason = "caught"
        events.append(Event("LevelFailed", {"reason": "caught"}))
    elif new.sun_hour >= NUM_HOURS:
        new.status = Status.FAILED
        new.fail_reason = "day_ended"
        events.append(Event("LevelFailed", {"reason": "day_ended"}))
