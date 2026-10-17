"""The rules of section 3 as pure functions: apply_action, legal_actions, undo helpers.

Every VALID action: effect -> action_count += 1 -> sun may advance -> outcome
(win first, then dial complete). INVALID actions are free: nothing changes, the sun does not
advance, no snapshot is taken, and an action_rejected event carries the reason.

Events follow section 6.3 (Dictionaries with a "type" key).
"""
from __future__ import annotations

from typing import Dict, List, Optional

from .model import (
    ASH, CHASM, DIRS, FAILED, GONE, HOURS, INTACT, NUM_HOURS, PLAYING, TYPES, WALL, WON,
    GameObject, GameState, Shadow,
)

Action = Dict[str, str]
Event = Dict[str, object]

ACTION_ORDER = (
    [{"type": "move", "dir": d} for d in DIRS]
    + [{"type": "burn", "dir": d} for d in DIRS]
    + [{"type": "interact"}, {"type": "wait"}]
)


# ---------------------------------------------------------------- queries
def object_at(state: GameState, hour: int, x: int, y: int) -> Optional[GameObject]:
    """The object in a slot. GONE counts as an empty slot (section 11 item 7)."""
    for o in state.objects:
        if o.hour == hour and o.x == x and o.y == y and o.state != GONE:
            return o
    return None


def active_shadow_at(state: GameState, hour: int, x: int, y: int) -> Optional[Shadow]:
    for s in state.level.shadows:
        if (s.hour, s.x, s.y) == (hour, x, y) and state.shadow_active(s):
            return s
    return None


def tile_block_reason(state: GameState, hour: int, x: int, y: int) -> Optional[str]:
    """None if the player may stand here, else a short reason."""
    lv = state.level
    if not lv.in_bounds(x, y):
        return "out_of_bounds"
    terrain = lv.terrain_at(hour, x, y)
    if terrain == WALL:
        return "blocked_terrain"
    obj = object_at(state, hour, x, y)
    td = TYPES[obj.type] if obj else None
    if terrain == CHASM and not (obj and obj.state in td.fills):
        return "blocked_terrain"
    if obj and obj.state in td.blocks:
        return "blocked_object"
    if active_shadow_at(state, hour, x, y):
        return "shadow_blocks"
    return None


def is_hour_passed(state: GameState, hour: int) -> bool:
    return state.is_hour_passed(hour)


# ---------------------------------------------------------------- apply
def apply_action(state: GameState, action: Action) -> Dict[str, object]:
    """Returns {"ok", "events", "state", "reason"}. ok == False means invalid and FREE."""
    def reject(reason: str) -> Dict[str, object]:
        return {"ok": False, "events": [{"type": "action_rejected", "reason": reason}],
                "state": state, "reason": reason}

    if state.status != PLAYING:
        return reject("level_over")

    new = state.duplicate_deep()
    events: List[Event] = []
    kind = action.get("type")
    if kind == "move":
        reason = _move(new, action, events)
    elif kind == "burn":
        reason = _burn(new, action, events)
    elif kind == "interact":
        reason = _interact(new, events)
    elif kind == "wait":
        reason = None
    else:
        reason = "unknown_action"
    if reason:
        return reject(reason)

    old_sun = state.sun_index
    new.action_count += 1
    new_sun = new.sun_index

    # Hours passed by this action, as order indexes (capped to the 6 real hours).
    newly = range(min(old_sun, NUM_HOURS), min(new_sun, NUM_HOURS))
    newly_hours = [HOURS[i] for i in newly]

    # A shadow waking on the player's own tile makes the whole action invalid and free.
    for s in new.level.shadows:
        if (s.id not in new.destroyed and s.hour in newly_hours
                and (s.hour, s.x, s.y) == new.player):
            return reject("shadow_wakes_on_you")

    # Event order (section 11 item 14): the action's own events, sun_advanced, hour_passed,
    # shadow_appeared (sorted by id), then action_applied, then level_won / level_failed.
    if new_sun != old_sun:
        events.append({"type": "sun_advanced", "from_index": old_sun, "to_index": new_sun})
    for hour in newly_hours:
        events.append({"type": "hour_passed", "hour": hour})
    for s in sorted((s for s in new.level.shadows
                     if s.hour in newly_hours and s.id not in new.destroyed), key=lambda s: s.id):
        events.append({"type": "shadow_appeared", "id": s.id, "hour": s.hour, "slot": [s.x, s.y]})
    events.append({"type": "action_applied", "actions_used": new.action_count})

    # Terminal events come after action_applied. Order of checks: (1) exit -> win, (2) otherwise dial complete -> fail.
    here = object_at(new, *new.player)
    if here is not None and here.type == "exit":
        new.status = WON
        events.append({"type": "level_won", "actions_used": new.action_count})
    elif new_sun >= NUM_HOURS:
        new.status = FAILED
        new.fail_reason = "dial_complete"
        events.append({"type": "level_failed", "reason": "dial_complete"})
    return {"ok": True, "events": events, "state": new, "reason": ""}


def _move(new: GameState, action: Action, events: List[Event]) -> Optional[str]:
    d = action.get("dir")
    if d not in DIRS:
        return "unknown_action"
    hour, x, y = new.player
    dx, dy = DIRS[d]
    reason = tile_block_reason(new, hour, x + dx, y + dy)
    if reason:
        return reason
    events.append({"type": "moved", "from_hour": hour, "from_slot": [x, y],
                   "to_hour": hour, "to_slot": [x + dx, y + dy]})
    new.player = (hour, x + dx, y + dy)
    return None


def _interact(new: GameState, events: List[Event]) -> Optional[str]:
    hour, x, y = new.player
    obj = object_at(new, hour, x, y)
    if obj is None or obj.type != "stair" or obj.state != INTACT or obj.links_to is None:
        return "not_on_stair"
    to = obj.links_to
    if tile_block_reason(new, to.hour, to.x, to.y):
        return "arrival_blocked"
    events.append({"type": "moved", "from_hour": hour, "from_slot": [x, y],
                   "to_hour": to.hour, "to_slot": [to.x, to.y]})
    new.player = (to.hour, to.x, to.y)
    return None


def _burn(new: GameState, action: Action, events: List[Event]) -> Optional[str]:
    d = action.get("dir")
    if d not in DIRS:
        return "unknown_action"
    lv = new.level
    hour, x, y = new.player
    dx, dy = DIRS[d]
    tx, ty = x + dx, y + dy
    obj = object_at(new, hour, tx, ty) if lv.in_bounds(tx, ty) else None
    if obj is None:
        return "nothing_to_burn"  # also covers burning off the grid
    if obj.state != INTACT:
        return "not_intact"
    if not obj.flammable:
        return "not_flammable"

    link = obj.ash_link
    if link is not None:
        target = (link.hour, link.x, link.y)
        if (target == new.player or object_at(new, *target) is not None
                or active_shadow_at(new, *target) is not None):
            return "ash_target_occupied"

    # 1. the target becomes ASH
    obj.state = ASH
    events.append({"type": "burned", "id": obj.id, "hour": hour, "slot": [tx, ty]})
    # 2. its ash link creates a new INTACT object elsewhere (fixed data, never random)
    if link is not None:
        new.objects.append(GameObject(
            id=f"{obj.id}_ash", type=link.becomes, hour=link.hour, x=link.x, y=link.y,
            state=INTACT, flammable=TYPES[link.becomes].flammable))
        events.append({"type": "ash_moved", "from_hour": hour, "to_hour": link.hour,
                       "to_slot": [link.x, link.y], "becomes": link.becomes})
    # 3. every ACTIVE shadow in the same room, in the 4-neighborhood of the burned slot, dies
    dead = set(new.destroyed)
    for ox, oy in ((0, -1), (0, 1), (-1, 0), (1, 0)):  # up, down, left, right
        for s in lv.shadows:
            if (s.hour, s.x, s.y) == (hour, tx + ox, ty + oy) and new.shadow_active(s):
                dead.add(s.id)
                events.append({"type": "shadow_destroyed", "id": s.id, "hour": s.hour})
    new.destroyed = frozenset(dead)
    return None


# ---------------------------------------------------------------- legal actions
def legal_actions(state: GameState) -> List[Action]:
    """Only VALID actions (never invalid ones), in a fixed deterministic order."""
    return [a for a in ACTION_ORDER if apply_action(state, a)["ok"]]
