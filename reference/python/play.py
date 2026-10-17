"""Play or solve a level in the terminal.

    python play.py ../../levels/data/L01_first_crate.json
    python play.py ../../levels/data/L01_first_crate.json --solve

Keys: w a s d = move, b + w/a/s/d = burn (e.g. "b d"), e = interact, x = wait, u = undo, r = restart, q = quit
"""
import sys

from pyre_ref import Game, load_level, solve, action_str
from pyre_ref.model import CHASM, FLOOR, HOURS, INTACT, WALL, ASH

KEYS = {"w": "up", "a": "left", "s": "down", "d": "right"}
GLYPH = {"bridge": "B", "ash_path": "=", "crate": "C", "door": "D", "stair": "S", "exit": "E"}


def render(state) -> str:
    lv = state.level
    out = [f"{lv.id} '{lv.title}'  act {lv.act}  actions {state.action_count}  "
           f"sun_index {state.sun_index}/6  {state.status}"
           + (f" ({state.fail_reason})" if state.fail_reason else "")]
    for hour in HOURS:
        passed = "PASSED" if state.is_hour_passed(hour) else ""
        out.append(f"\n{hour:>2} o'clock {passed}")
        for y in range(lv.h):
            row = ""
            for x in range(lv.w):
                ch = lv.terrain_at(hour, x, y)
                for o in state.objects:
                    if (o.hour, o.x, o.y) == (hour, x, y):
                        ch = "," if o.state == ASH and o.type != "bridge" else (
                            ch if o.state == ASH else GLYPH[o.type])
                for s in lv.shadows:
                    if (s.hour, s.x, s.y) == (hour, x, y) and s.id not in state.destroyed:
                        ch = "X" if state.is_hour_passed(hour) else "x"
                if state.player == (hour, x, y):
                    ch = "@"
                row += ch
            out.append("  " + row)
    out.append("\n@ you  # wall  ~ chasm  C crate  D door  B bridge  = ash path  S stair  E exit  "
               ", rubble  X shadow  x sleeping shadow")
    return "\n".join(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    level = load_level(sys.argv[1])
    if "--solve" in sys.argv:
        r = solve(level)
        print(r.status, len(r.actions), ", ".join(action_str(a) for a in r.actions))
        return
    g = Game(level)
    while True:
        print(render(g.state))
        cmd = input("> ").strip().lower().split()
        if not cmd:
            continue
        c = cmd[0]
        if c == "q":
            return
        if c == "u":
            g.undo()
            continue
        if c == "r":
            g.restart()
            continue
        if c in KEYS:
            a = {"type": "move", "dir": KEYS[c]}
        elif c == "x":
            a = {"type": "wait"}
        elif c == "e":
            a = {"type": "interact"}
        elif c == "b" and len(cmd) > 1 and cmd[1] in KEYS:
            a = {"type": "burn", "dir": KEYS[cmd[1]]}
        else:
            print("?")
            continue
        r = g.do(a)
        if not r["ok"]:
            print("  can't:", r["reason"])


if __name__ == "__main__":
    main()
