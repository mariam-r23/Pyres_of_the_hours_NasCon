"""Breadth-first solver: shortest winning action list, a proof of unsolvable, or a cap hit.

Uses only apply_action, legal_actions and hash_key (same API the GDScript solver will use).
The state space is finite because the dial completes after (6 - start_index) * actions_per_hour actions.
"""
from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Deque, Dict, List, Optional, Tuple, Union

from .model import FAILED, WON, GameState, Level
from .rules import Action, apply_action, legal_actions


@dataclass
class SolveResult:
    status: str  # "solved" | "unsolvable" | "limit"
    actions: List[Action] = field(default_factory=list)
    states_explored: int = 0

    @property
    def solved(self) -> bool:
        return self.status == "solved"


def action_str(a: Action) -> str:
    return a["type"] if "dir" not in a else f"{a['type']}:{a['dir']}"


def solve(start: Union[Level, GameState], max_states: int = 500_000) -> SolveResult:
    if isinstance(start, Level):
        start = GameState.initial(start)
    if start.status == WON:
        return SolveResult("solved", [], 1)
    if start.status == FAILED:
        return SolveResult("unsolvable", [], 1)
    k0 = start.hash_key()
    parent: Dict[str, Optional[Tuple[str, Action]]] = {k0: None}
    queue: Deque[Tuple[GameState, str]] = deque([(start, k0)])
    while queue:
        state, key = queue.popleft()
        for action in legal_actions(state):
            nxt = apply_action(state, action)["state"]
            if nxt.status == FAILED:
                continue
            nk = nxt.hash_key()
            if nk in parent:
                continue
            parent[nk] = (key, action)
            if nxt.status == WON:
                return SolveResult("solved", _path(parent, nk), len(parent))
            if len(parent) >= max_states:
                return SolveResult("limit", [], len(parent))
            queue.append((nxt, nk))
    return SolveResult("unsolvable", [], len(parent))


def _path(parent, key) -> List[Action]:
    out: List[Action] = []
    while parent[key] is not None:
        key, action = parent[key]
        out.append(action)
    out.reverse()
    return out
