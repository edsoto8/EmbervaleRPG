"""Regenerates project.godot's [input] section deterministically. Run: python3 tools/gen_project.py"""
import pathlib, re

KEYS = {
    "W": 87, "A": 65, "S": 83, "D": 68, "E": 69, "I": 73, "K": 75, "1": 49, "2": 50, "3": 51,
    "SPACE": 32, "SHIFT": 4194325, "ESC": 4194305, "ENTER": 4194309, "KP_ENTER": 4194310,
    "LEFT": 4194319, "UP": 4194320, "RIGHT": 4194321, "DOWN": 4194322,
}
MOUSE = {"LMB": 1, "RMB": 2, "MMB": 3, "WHEEL_UP": 4, "WHEEL_DOWN": 5}

ACTIONS = {
    "move_forward": ["W"], "move_back": ["S"], "move_left": ["A"], "move_right": ["D"],
    "run": ["SHIFT"], "interact": ["E"], "inventory": ["I"], "skills": ["K"],
    "camera_left": ["LEFT"], "camera_right": ["RIGHT"], "camera_up": ["UP"], "camera_down": ["DOWN"],
    "pause": ["ESC"], "dialogue_continue": ["SPACE", "E", "ENTER", "KP_ENTER"],
    "skip": ["SPACE", "ESC", "ENTER", "KP_ENTER"],
    "choice_1": ["1"], "choice_2": ["2"], "choice_3": ["3"],
    "click": ["LMB"], "camera_drag": ["MMB"], "zoom_in": ["WHEEL_UP"], "zoom_out": ["WHEEL_DOWN"],
}

def event(name):
    if name in MOUSE:
        return 'Object(InputEventMouseButton,"device":-1,"button_index":%d,"pressed":false)' % MOUSE[name]
    return 'Object(InputEventKey,"device":-1,"physical_keycode":%d,"keycode":0,"pressed":false,"echo":false)' % KEYS[name]

lines = ["[input]", ""]
for action, evs in ACTIONS.items():
    lines.append("%s={" % action)
    lines.append('"deadzone": 0.2,')
    lines.append('"events": [%s]' % ", ".join(event(e) for e in evs))
    lines.append("}")
section = "\n".join(lines) + "\n"

path = pathlib.Path(__file__).resolve().parent.parent / "project.godot"
text = path.read_text()
text = re.sub(r"\[input\]\n.*?(?=\n\[|\Z)", section.rstrip("\n"), text, flags=re.S)
path.write_text(text)
