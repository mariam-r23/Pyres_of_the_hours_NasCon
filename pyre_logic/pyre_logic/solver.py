"""Breadth-first solver.

Returns the shortest list of actions that wins, or proves the level unsolvable
(the state space is finite because the day ends after 6 * actions_per_hour actions).

Wait is included on purpose: waiting can help, because a shadow must be ACTIVE
for fire to destroy it, and a shadow left inactive will wake up later and block you.
The state key includes action_count, so the search is exact (no dominance pruning).
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Deque, Dict, List, Optional, Tuple, Union

from .model import ALL_ACTIONS, Action, GameState, Level, Status
from .rules import apply


@dataclass
class SolveResult:
    status: str  # "solved" | "unsolvable" | "limit"
    actions: List[Action] = field(default_factory=list)
    states_explored: int = 0

    @property
    def solved(self) -> bool:
        return self.status == "solved"

    def __str__(self) -> str:
        if self.solved:
            return f"solved in {len(self.actions)} actions: " + ", ".join(map(str, self.actions))
        return f"{self.status} ({self.states_explored} states explored)"


def solve(start: Union[Level, GameState], max_states: int = 200_000) -> SolveResult:
    if isinstance(start, Level):
        start = GameState.initial(start)
    if start.status == Status.WON:
        return SolveResult("solved", [], 1)
    if start.status == Status.FAILED:
        return SolveResult("unsolvable", [], 1)

    start_key = start.key()
    parent: Dict[tuple, Optional[Tuple[tuple, Action]]] = {start_key: None}
    queue: Deque[Tuple[GameState, tuple]] = deque([(start, start_key)])

    while queue:
        state, key = queue.popleft()
        for action in ALL_ACTIONS:
            result = apply(state, action)
            if not result.valid:
                continue
            nxt = result.state
            if nxt.status == Status.FAILED:
                continue
            nkey = nxt.key()
            if nkey in parent:
                continue
            parent[nkey] = (key, action)
            if nxt.status == Status.WON:
                return SolveResult("solved", _path(parent, nkey), len(parent))
            if len(parent) >= max_states:
                return SolveResult("limit", [], len(parent))
            queue.append((nxt, nkey))
    return SolveResult("unsolvable", [], len(parent))


def _path(parent, key) -> List[Action]:
    actions: List[Action] = []
    while parent[key] is not None:
        key, action = parent[key]
        actions.append(action)
    actions.reverse()
    return actions
