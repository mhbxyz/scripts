import argparse
import ctypes
import ctypes.util
import math
import json
import os
import random
import re
import struct
import subprocess
import sys
import time
from datetime import datetime

__version__ = "1.1.0"


def log(message):
    time_str = datetime.now().strftime("%H:%M:%S")
    print(f"[{time_str}] {message}")


# ---------------------------------------------------------------------------
# Easing functions (pure Python replacements for pyautogui tweens)
# ---------------------------------------------------------------------------


def ease_in_out_quad(t):
    if t < 0.5:
        return 2 * t * t
    return -1 + (4 - 2 * t) * t


def ease_in_out_cubic(t):
    if t < 0.5:
        return 4 * t * t * t
    return (t - 1) * (2 * t - 2) * (2 * t - 2) + 1


def ease_out_quad(t):
    return t * (2 - t)


def ease_in_out_sine(t):
    return -(math.cos(math.pi * t) - 1) / 2


TWEENS = [ease_in_out_quad, ease_in_out_cubic, ease_out_quad, ease_in_out_sine]


# ---------------------------------------------------------------------------
# Backend: X11 (libX11 + libXtst) — works on X11 and XWayland
# ---------------------------------------------------------------------------


class XlibBackend:
    # X11 keycodes for modifier keys
    KEYCODES = {"shift": 50, "ctrl": 37, "alt": 64}

    def __init__(self):
        self._xlib = ctypes.cdll.LoadLibrary("libX11.so.6")
        self._xtst = ctypes.cdll.LoadLibrary("libXtst.so.6")

        self._xlib.XOpenDisplay.restype = ctypes.c_void_p
        self._xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self._display = self._xlib.XOpenDisplay(None)
        if not self._display:
            raise RuntimeError("Cannot open X display")

        self._root = self._xlib.XDefaultRootWindow(self._display)

    def get_position(self):
        root_ret = ctypes.c_ulong()
        child_ret = ctypes.c_ulong()
        rx, ry, wx, wy = (ctypes.c_int() for _ in range(4))
        mask = ctypes.c_uint()
        self._xlib.XQueryPointer(
            self._display,
            self._root,
            ctypes.byref(root_ret),
            ctypes.byref(child_ret),
            ctypes.byref(rx),
            ctypes.byref(ry),
            ctypes.byref(wx),
            ctypes.byref(wy),
            ctypes.byref(mask),
        )
        return rx.value, ry.value

    def move_to(self, x, y):
        self._xlib.XWarpPointer(
            self._display, 0, self._root, 0, 0, 0, 0, int(x), int(y)
        )
        self._xlib.XFlush(self._display)

    def press_key(self, key_name):
        keycode = self.KEYCODES.get(key_name)
        if keycode is None:
            return
        self._xtst.XTestFakeKeyEvent(self._display, keycode, True, 0)
        self._xtst.XTestFakeKeyEvent(self._display, keycode, False, 0)
        self._xlib.XFlush(self._display)

    def screen_size(self):
        w = self._xlib.XDisplayWidth(self._display, 0)
        h = self._xlib.XDisplayHeight(self._display, 0)
        return w, h

    def close(self):
        pass


# ---------------------------------------------------------------------------
# Backend: uinput (/dev/uinput) — native Wayland without X
# ---------------------------------------------------------------------------

# ioctl / input-event constants (Linux)
_UI_SET_EVBIT = 0x40045564
_UI_SET_KEYBIT = 0x40045565
_UI_SET_RELBIT = 0x40045566
_UI_DEV_SETUP = 0x405C5503
_UI_DEV_CREATE = 0x5501
_UI_DEV_DESTROY = 0x5502

_EV_SYN = 0x00
_EV_KEY = 0x01
_EV_REL = 0x02
_SYN_REPORT = 0x00
_REL_X = 0x00
_REL_Y = 0x01

_BUS_USB = 0x03

# Linux keycodes for modifier keys
_KEY_LEFTSHIFT = 42
_KEY_LEFTCTRL = 29
_KEY_LEFTALT = 56

# struct input_event: time (16 bytes on 64-bit), type (u16), code (u16), value (i32)
_INPUT_EVENT_FMT = "llHHi"
_INPUT_EVENT_SIZE = struct.calcsize(_INPUT_EVENT_FMT)

# struct uinput_setup: id (bustype u16, vendor u16, product u16, version u16),
#                      name (80 bytes), ff_effects_max (u32)
_UINPUT_SETUP_FMT = "4H80sI"


class UinputBackend:
    KEYCODES = {
        "shift": _KEY_LEFTSHIFT,
        "ctrl": _KEY_LEFTCTRL,
        "alt": _KEY_LEFTALT,
    }

    def __init__(self):
        self._fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)

        # Enable event types
        import fcntl

        self._fcntl = fcntl
        fcntl.ioctl(self._fd, _UI_SET_EVBIT, _EV_KEY)
        fcntl.ioctl(self._fd, _UI_SET_EVBIT, _EV_REL)

        # Enable relative axes
        fcntl.ioctl(self._fd, _UI_SET_RELBIT, _REL_X)
        fcntl.ioctl(self._fd, _UI_SET_RELBIT, _REL_Y)

        # Enable modifier keys
        for kc in self.KEYCODES.values():
            fcntl.ioctl(self._fd, _UI_SET_KEYBIT, kc)

        # Setup device
        name = b"keep-alive-virtual-input"
        setup = struct.pack(
            _UINPUT_SETUP_FMT,
            _BUS_USB,
            0x1234,
            0x5678,
            1,
            name.ljust(80, b"\x00"),
            0,
        )
        fcntl.ioctl(self._fd, _UI_DEV_SETUP, setup)
        fcntl.ioctl(self._fd, _UI_DEV_CREATE)
        time.sleep(0.2)  # let the device settle

    def _write_event(self, ev_type, code, value):
        now = time.time()
        sec = int(now)
        usec = int((now - sec) * 1_000_000)
        data = struct.pack(_INPUT_EVENT_FMT, sec, usec, ev_type, code, value)
        os.write(self._fd, data)

    def _syn(self):
        self._write_event(_EV_SYN, _SYN_REPORT, 0)

    def move_relative(self, dx, dy):
        if dx:
            self._write_event(_EV_REL, _REL_X, int(dx))
        if dy:
            self._write_event(_EV_REL, _REL_Y, int(dy))
        self._syn()

    def press_key(self, key_name):
        keycode = self.KEYCODES.get(key_name)
        if keycode is None:
            return
        self._write_event(_EV_KEY, keycode, 1)  # press
        self._syn()
        self._write_event(_EV_KEY, keycode, 0)  # release
        self._syn()

    def close(self):
        try:
            self._fcntl.ioctl(self._fd, _UI_DEV_DESTROY)
        except Exception:
            pass
        os.close(self._fd)


# ---------------------------------------------------------------------------
# Backend selection
# ---------------------------------------------------------------------------


def _select_backend():
    session = os.environ.get("XDG_SESSION_TYPE", "")

    # On native Wayland, try uinput first
    if session == "wayland":
        try:
            backend = UinputBackend()
            log("Backend: uinput (Wayland)")
            return backend
        except Exception:
            pass

    # Try X11 (works for X11 and XWayland)
    if os.environ.get("DISPLAY") and not os.environ.get("XAUTHORITY"):
        for _xauth in [
            os.path.expanduser("~/.Xauthority"),
            f"/run/user/{os.getuid()}/gdm/Xauthority",
        ]:
            if os.path.exists(_xauth):
                os.environ["XAUTHORITY"] = _xauth
                break

    try:
        backend = XlibBackend()
        log("Backend: X11 (libX11 + libXtst)")
        return backend
    except Exception:
        pass

    raise RuntimeError(
        "No input backend available. "
        "X11: ensure DISPLAY is set and libX11/libXtst are installed. "
        "Wayland: ensure /dev/uinput is accessible (group 'input')."
    )


# ---------------------------------------------------------------------------
# Monitor detection (unchanged)
# ---------------------------------------------------------------------------

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
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )
    return [(m["x"], m["y"], m["w"], m["h"]) for m in json.loads(output)]


def _parse_monitors_kscreen():
    """Parse monitors from kscreen-doctor (KDE Wayland)."""
    output = subprocess.check_output(
        ["kscreen-doctor", "--outputs"],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=5,
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
        ["xrandr", "--query"],
        text=True,
        stderr=subprocess.DEVNULL,
        timeout=5,
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


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

MODIFIER_KEYS = ["shift", "ctrl", "alt"]


def get_current_monitor(backend):
    """Get the monitor containing the mouse cursor.

    Returns (offset_x, offset_y, width, height). Only works with XlibBackend.
    Falls back to screen_size() or (0, 0, 1920, 1080).
    """
    if isinstance(backend, XlibBackend):
        mouse_x, mouse_y = backend.get_position()
        for ox, oy, w, h in _get_monitors():
            if ox <= mouse_x < ox + w and oy <= mouse_y < oy + h:
                return ox, oy, w, h
        sw, sh = backend.screen_size()
        return 0, 0, sw, sh

    # uinput: no position info, try to get monitor size from detection
    monitors = _get_monitors()
    if monitors:
        return monitors[0]
    return 0, 0, 1920, 1080


def center_mouse(backend):
    if isinstance(backend, XlibBackend):
        ox, oy, w, h = get_current_monitor(backend)
        backend.move_to(ox + w // 2, oy + h // 2)
        log("🖱️  Mouse centered on screen")
    else:
        log("🖱️  Mouse centering not available on Wayland/uinput (skipped)")


def _smooth_move_to(backend, target_x, target_y, duration, tween):
    """Smoothly move mouse to absolute position (X11 only)."""
    start_x, start_y = backend.get_position()
    steps = max(int(duration / 0.01), 5)
    for i in range(1, steps + 1):
        t = tween(i / steps)
        ix = int(start_x + (target_x - start_x) * t)
        iy = int(start_y + (target_y - start_y) * t)
        backend.move_to(ix, iy)
        time.sleep(duration / steps)


def _smooth_move_relative(backend, total_dx, total_dy, duration, tween):
    """Smoothly move mouse by relative offset (uinput)."""
    steps = max(int(duration / 0.01), 5)
    moved_x, moved_y = 0.0, 0.0
    for i in range(1, steps + 1):
        t = tween(i / steps)
        target_x = total_dx * t
        target_y = total_dy * t
        dx = target_x - moved_x
        dy = target_y - moved_y
        if abs(dx) >= 1 or abs(dy) >= 1:
            backend.move_relative(int(dx), int(dy))
            moved_x += int(dx)
            moved_y += int(dy)
        time.sleep(duration / steps)


def move_mouse(backend):
    if isinstance(backend, XlibBackend):
        ox, oy, mw, mh = get_current_monitor(backend)
        start_x, start_y = backend.get_position()

        for _ in range(random.randint(2, 5)):
            tx = max(ox, min(start_x + random.randint(-300, 300), ox + mw - 1))
            ty = max(oy, min(start_y + random.randint(-200, 200), oy + mh - 1))
            _smooth_move_to(
                backend,
                tx,
                ty,
                duration=random.uniform(0.2, 0.8),
                tween=random.choice(TWEENS),
            )
            time.sleep(random.uniform(0.05, 0.3))

        _smooth_move_to(
            backend,
            start_x + random.randint(-3, 3),
            start_y + random.randint(-3, 3),
            duration=random.uniform(0.3, 0.7),
            tween=random.choice(TWEENS),
        )
    else:
        # uinput: relative movements
        for _ in range(random.randint(2, 5)):
            dx = random.randint(-300, 300)
            dy = random.randint(-200, 200)
            _smooth_move_relative(
                backend,
                dx,
                dy,
                duration=random.uniform(0.2, 0.8),
                tween=random.choice(TWEENS),
            )
            time.sleep(random.uniform(0.05, 0.3))

        # Small return movement
        _smooth_move_relative(
            backend,
            random.randint(-3, 3),
            random.randint(-3, 3),
            duration=random.uniform(0.3, 0.7),
            tween=random.choice(TWEENS),
        )


def press_key(backend):
    key = random.choice(MODIFIER_KEYS)
    backend.press_key(key)
    return key


def keep_alive(backend, interval, mouse=True, key=True):
    log(f"🚀 Keep-alive started (interval: {interval}s)")
    if mouse and not key:
        log("🖱️  Mode: mouse only")
    elif key and not mouse:
        log("⌨️  Mode: keyboard only")
    else:
        log("🖱️⌨️  Mode: mouse + keyboard")
    log("Press Ctrl+C to stop.")

    if mouse:
        center_mouse(backend)

    try:
        while True:
            if mouse:
                move_mouse(backend)
                log("🖱️  Mouse moved")
            if key:
                pressed = press_key(backend)
                log(f"⌨️  Key pressed ({pressed.capitalize()})")
            time.sleep(interval)
    except KeyboardInterrupt:
        log("\n👋 Keep-alive stopped.")
    finally:
        if isinstance(backend, UinputBackend):
            backend.close()


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

    if len(sys.argv) > 1 and sys.argv[1] == "help":
        parser.print_help()
        raise SystemExit(0)

    args = parser.parse_args()
    backend = _select_backend()
    keep_alive(
        backend,
        interval=args.interval,
        mouse=not args.key_only,
        key=not args.mouse_only,
    )
