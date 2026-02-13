import argparse
import json
import os
import random
import re
import subprocess
import time
from datetime import datetime

if os.environ.get("DISPLAY") and not os.environ.get("XAUTHORITY"):
    for _xauth in [
        os.path.expanduser("~/.Xauthority"),
        f"/run/user/{os.getuid()}/gdm/Xauthority",
    ]:
        if os.path.exists(_xauth):
            os.environ["XAUTHORITY"] = _xauth
            break

import pyautogui

__version__ = "1.0.1"

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.1


def log(message):
    time_str = datetime.now().strftime("%H:%M:%S")
    print(f"[{time_str}] {message}")


_MUTTER_MONITORS_SCRIPT = """\
import json, gi
gi.require_version("GLib", "2.0")
from gi.repository import GLib, Gio
bus = Gio.bus_get_sync(Gio.BusType.SESSION)
res = bus.call_sync(
    "org.gnome.Mutter.DisplayConfig",
    "/org/gnome/Mutter/DisplayConfig",
    "org.gnome.Mutter.DisplayConfig",
    "GetCurrentState",
    None, None, Gio.DBusCallFlags.NONE, -1, None,
)
data = res.unpack()
physical, logical = data[1], data[2]
sizes = {}
for pm in physical:
    conn = pm[0][0]
    for mode in pm[1]:
        if mode[6].get("is-current", False):
            sizes[conn] = (mode[1], mode[2])
            break
out = []
for lm in logical:
    x, y, scale = lm[0], lm[1], lm[2]
    for assoc in lm[5]:
        conn = assoc[0]
        if conn in sizes:
            pw, ph = sizes[conn]
            out.append({"x": x, "y": y, "w": round(pw / scale), "h": round(ph / scale)})
            break
print(json.dumps(out))
"""


def _parse_monitors_mutter():
    """Parse monitors via Mutter D-Bus API (GNOME Wayland)."""
    output = subprocess.check_output(
        ["python3", "-c", _MUTTER_MONITORS_SCRIPT],
        text=True, stderr=subprocess.DEVNULL, timeout=5,
    )
    return [(m["x"], m["y"], m["w"], m["h"]) for m in json.loads(output)]


def _parse_monitors_kscreen():
    """Parse monitors from kscreen-doctor (KDE Wayland)."""
    output = subprocess.check_output(
        ["kscreen-doctor", "--outputs"],
        text=True, stderr=subprocess.DEVNULL, timeout=5,
    )
    monitors = []
    for block in re.split(r"(?=Output:)", output):
        if "enabled" not in block or "connected" not in block:
            continue
        geo = re.search(r"Geometry:\s*(\d+),(\d+)\s+(\d+)x(\d+)", block)
        if geo:
            ox, oy, w, h = (int(g) for g in geo.groups())
            monitors.append((ox, oy, w, h))
    return monitors


def _parse_monitors_xrandr():
    """Parse monitors from xrandr (X11 / XWayland)."""
    output = subprocess.check_output(
        ["xrandr", "--query"], text=True, stderr=subprocess.DEVNULL, timeout=5,
    )
    monitors = []
    for line in output.splitlines():
        if " connected " not in line:
            continue
        match = re.search(r"(\d+)x(\d+)\+(\d+)\+(\d+)", line)
        if match:
            w, h, ox, oy = (int(g) for g in match.groups())
            monitors.append((ox, oy, w, h))
    return monitors


def _get_monitors():
    """Detect all monitors, trying Wayland-native tools first."""
    desktop = os.environ.get("XDG_CURRENT_DESKTOP", "").lower()
    session = os.environ.get("XDG_SESSION_TYPE", "")

    if session == "wayland":
        if "kde" in desktop:
            try:
                monitors = _parse_monitors_kscreen()
                if monitors:
                    return monitors
            except Exception:
                pass
        if "gnome" in desktop or "ubuntu" in desktop:
            try:
                monitors = _parse_monitors_mutter()
                if monitors:
                    return monitors
            except Exception:
                pass

    try:
        monitors = _parse_monitors_xrandr()
        if monitors:
            return monitors
    except Exception:
        pass

    return []


def get_current_monitor():
    """Get the monitor containing the mouse cursor (offset + dimensions).

    Returns (offset_x, offset_y, width, height) for the monitor where
    the mouse currently sits. Falls back to (0, 0, *pyautogui.size())
    if detection fails.
    """
    mouse_x, mouse_y = pyautogui.position()
    for ox, oy, w, h in _get_monitors():
        if ox <= mouse_x < ox + w and oy <= mouse_y < oy + h:
            return ox, oy, w, h
    sw, sh = pyautogui.size()
    return 0, 0, sw, sh


def center_mouse():
    ox, oy, w, h = get_current_monitor()
    pyautogui.moveTo(ox + w // 2, oy + h // 2)
    log("🖱️  Mouse centered on screen")


TWEENS = [
    pyautogui.easeInOutQuad,
    pyautogui.easeInOutCubic,
    pyautogui.easeOutQuad,
    pyautogui.easeInOutSine,
]


def move_mouse():
    ox, oy, mw, mh = get_current_monitor()
    start_x, start_y = pyautogui.position()

    for _ in range(random.randint(2, 5)):
        tx = max(ox, min(start_x + random.randint(-300, 300), ox + mw - 1))
        ty = max(oy, min(start_y + random.randint(-200, 200), oy + mh - 1))
        pyautogui.moveTo(
            tx, ty, duration=random.uniform(0.2, 0.8), tween=random.choice(TWEENS)
        )
        time.sleep(random.uniform(0.05, 0.3))

    pyautogui.moveTo(
        start_x + random.randint(-3, 3),
        start_y + random.randint(-3, 3),
        duration=random.uniform(0.3, 0.7),
        tween=random.choice(TWEENS),
    )


MODIFIER_KEYS = ["shift", "ctrl", "alt"]


def press_key():
    key = random.choice(MODIFIER_KEYS)
    pyautogui.press(key)
    return key


def keep_alive(interval, mouse=True, key=True):
    log(f"🚀 Keep-alive started (interval: {interval}s)")
    if mouse and not key:
        log("🖱️  Mode: mouse only")
    elif key and not mouse:
        log("⌨️  Mode: keyboard only")
    else:
        log("🖱️⌨️  Mode: mouse + keyboard")
    log("Press Ctrl+C to stop.")

    if mouse:
        center_mouse()

    try:
        while True:
            if mouse:
                move_mouse()
                log("🖱️  Mouse moved")
            if key:
                pressed = press_key()
                log(f"⌨️  Key pressed ({pressed.capitalize()})")
            time.sleep(interval)
    except KeyboardInterrupt:
        log("\n👋 Keep-alive stopped.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Simulate activity to prevent idle status."
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=60,
        help="Seconds between each cycle (default: 60).",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--mouse-only",
        action="store_true",
        help="Mouse movements only (no keyboard).",
    )
    group.add_argument(
        "--key-only",
        action="store_true",
        help="Keyboard presses only (no mouse).",
    )
    parser.add_argument(
        "--version", action="version", version=f"%(prog)s {__version__}"
    )

    args = parser.parse_args()
    keep_alive(
        interval=args.interval,
        mouse=not args.key_only,
        key=not args.mouse_only,
    )
