"""Pyre of the Hours: Python reference implementation of PROJECT_CONTEXT.md section 3."""
from .model import GameState, Level
from .loader import LevelError, load_level, load_level_from_dict
from .rules import apply_action, legal_actions, is_hour_passed
from .game import Game, SnapshotStack, undo
from .solver import SolveResult, solve, action_str

__all__ = [
    "GameState", "Level", "LevelError", "load_level", "load_level_from_dict",
    "apply_action", "legal_actions", "is_hour_passed", "Game", "SnapshotStack", "undo",
    "SolveResult", "solve", "action_str",
]
