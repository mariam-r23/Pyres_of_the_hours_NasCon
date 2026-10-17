"""Play or solve a level in the terminal. No graphics needed.

    python play.py levels/level1_first_spark.json            # play
    python play.py levels/level2_wake_the_shadow.json --solve  # print the shortest solution

Controls:  w a s d = move,  b + direction = burn (e.g. "b d"),  x = wait,  u = undo,  r = restart,  q = quit
"""
import sys

from pyre_logic import Action, Game, GameState, ObjState, ShadowState, Status, load_level, solve
from pyre_logic.model import CLOCK_POSITIONS, NUM_HOURS

KEYS = {"w": "N", "a": "W", "s": "S", "d": "E"}
GLYPH = {"plank": "P", "bridge": "B", "gate": "G", "crate": "C", "stone": "O",
         "ash_bridge": "=", "ash_path": "="}


def render(state: GameState) -> str:
    lv = state.level
    lines = [f"{lv.name}   actions: {state.action_count}   sun has passed {state.sun_hour}/{NUM_HOURS} hours"
             f"   status: {state.status.value}" + (f" ({state.fail_reason})" if state.fail_reason else "")]
    for hour in range(NUM_HOURS):
        tag = "PASSED" if state.hour_passed(hour) else "      "
        lines.append(f"\nHour {hour} ({CLOCK_POSITIONS[hour]:>2} o'clock) {tag}")
        for y in range(lv.height):
            row = ""
            for x in range(lv.width):
                ch = lv.terrain_at(hour, x, y)
                if (hour, x, y) in lv.doorways:
                    ch = "D"
                for o in state.objects:
                    if (o.hour, o.x, o.y) == (hour, x, y) and o.state != ObjState.GONE:
                        g = GLYPH.get(o.type, o.type[0].upper())
                        ch = "," if o.state == ObjState.ASH and ch != "~" else (g if ch != "~" or g == "=" else ch)
                for s in state.shadows:
                    if (s.hour, s.x, s.y) == (hour, x, y):
                        if s.state == ShadowState.ACTIVE:
                            ch = "X"
                        elif s.state == ShadowState.INACTIVE:
                            ch = "x"
                if state.player == (hour, x, y):
                    ch = "@"
                row += ch
            lines.append("  " + row)
    lines.append("\n@ you  D doorway  E exit  # wall  ~ chasm  = ash bridge  , ash  X shadow  x sleeping shadow")
    return "\n".join(lines)


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        return
    level = load_level(sys.argv[1])
    if "--solve" in sys.argv:
        print(solve(level))
        return
    game = Game(level)
    while True:
        print(render(game.state))
        if game.state.status != Status.PLAYING:
            print("\nLevel over. Type u to undo, r to restart or q to quit.")
        cmd = input("> ").strip().lower().split()
        if not cmd:
            continue
        if cmd[0] == "q":
            return
        if cmd[0] == "u":
            game.undo()
        elif cmd[0] == "r":
            game.restart()
        elif cmd[0] in KEYS:
            r = game.do(Action.move(KEYS[cmd[0]]))
        elif cmd[0] == "x":
            r = game.do(Action.wait())
        elif cmd[0] == "b" and len(cmd) > 1 and cmd[1] in KEYS:
            r = game.do(Action.burn(KEYS[cmd[1]]))
        else:
            print("?")
            continue
        if cmd[0] in KEYS or cmd[0] == "x" or cmd[0] == "b":
            if not r.valid:
                print(f"  can't: {r.reason}")
            else:
                for e in r.events:
                    print(f"  {e}")


if __name__ == "__main__":
    main()
