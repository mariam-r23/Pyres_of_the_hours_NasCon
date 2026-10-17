"""Undo (SnapshotStack) and a small wrapper. States are never mutated, so a snapshot is a reference."""
from __future__ import annotations

from typing import Dict, List

from .model import GameState, Level
from .rules import Action, apply_action


class SnapshotStack:
    def __init__(self, initial: GameState):
        self._stack: List[GameState] = [initial]

    @property
    def current(self) -> GameState:
        return self._stack[-1]

    @property
    def can_undo(self) -> bool:
        return len(self._stack) > 1

    def push(self, state: GameState) -> None:
        self._stack.append(state)

    def undo(self) -> GameState:
        if self.can_undo:
            self._stack.pop()
        return self._stack[-1]

    def reset(self) -> GameState:
        del self._stack[1:]
        return self._stack[0]


def undo(stack: SnapshotStack) -> GameState:
    """Section 6.2: restores the previous snapshot. Free and unlimited; the sun does not advance."""
    return stack.undo()


class Game:
    def __init__(self, level: Level):
        self.history = SnapshotStack(GameState.initial(level))

    @property
    def state(self) -> GameState:
        return self.history.current

    def do(self, action: Action) -> Dict[str, object]:
        result = apply_action(self.state, action)
        if result["ok"]:
            self.history.push(result["state"])
        return result

    def undo(self) -> Dict[str, object]:
        """Always allowed, even out of a won or failed state. Emits only undo_done (no action_applied)."""
        if not self.history.can_undo:
            return {"ok": False, "reason": "nothing_to_undo", "state": self.state,
                    "events": [{"type": "action_rejected", "reason": "nothing_to_undo"}]}
        self.history.undo()
        return {"ok": True, "reason": "", "events": [{"type": "undo_done"}], "state": self.state}

    def restart(self) -> GameState:
        return self.history.reset()
