"""Undo support and a small convenience wrapper for the presentation layer.

`apply()` never mutates a state, so a snapshot is just a reference to a state.
"""
from __future__ import annotations

from typing import List, Optional

from .model import Action, GameState, Level
from .rules import Result, apply


class SnapshotStack:
    """History of states. The top is the current state; the bottom is the start."""

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

    def undo(self) -> Optional[GameState]:
        """Step back one valid action. Returns the restored state, or None at the start."""
        if not self.can_undo:
            return None
        self._stack.pop()
        return self._stack[-1]

    def reset(self) -> GameState:
        del self._stack[1:]
        return self._stack[0]

    def __len__(self) -> int:
        return len(self._stack)


class Game:
    """What a scene script holds: the current state, do(), undo() and restart()."""

    def __init__(self, level: Level):
        self.level = level
        self.history = SnapshotStack(GameState.initial(level))

    @property
    def state(self) -> GameState:
        return self.history.current

    def do(self, action: Action) -> Result:
        result = apply(self.state, action)
        if result.valid:
            self.history.push(result.state)
        return result

    def undo(self) -> bool:
        return self.history.undo() is not None

    def restart(self) -> None:
        self.history.reset()
