#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Guarded native menu scenario using XTest mouse/keyboard events and an isolated profile."""
import argparse
import ctypes
import ctypes.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from runtime_probe import client_settings, send, stage_client_modules, wait


class Input:
    def __init__(self, records):
        self.records = records
        self.x = ctypes.CDLL(ctypes.util.find_library("X11"))
        self.t = ctypes.CDLL(ctypes.util.find_library("Xtst"))
        pointer = ctypes.c_void_p
        self.x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self.x.XOpenDisplay.restype = pointer
        self.x.XFlush.argtypes = [pointer]
        self.x.XCloseDisplay.argtypes = [pointer]
        self.x.XStringToKeysym.argtypes = [ctypes.c_char_p]
        self.x.XStringToKeysym.restype = ctypes.c_ulong
        self.x.XKeysymToKeycode.argtypes = [pointer, ctypes.c_ulong]
        self.x.XKeysymToKeycode.restype = ctypes.c_uint
        self.t.XTestFakeKeyEvent.argtypes = [pointer, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.t.XTestFakeButtonEvent.argtypes = [pointer, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.t.XTestFakeMotionEvent.argtypes = [pointer, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_ulong]
        self.display = self.x.XOpenDisplay(None)
        if not self.display:
            raise RuntimeError("guarded X display unavailable")
        self.x.XDefaultRootWindow.argtypes = [pointer]
        self.x.XDefaultRootWindow.restype = ctypes.c_ulong
        self.x.XQueryTree.argtypes = [pointer, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                     ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                                     ctypes.POINTER(ctypes.c_uint)]
        self.x.XFetchName.argtypes = [pointer, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
        self.x.XFree.argtypes = [pointer]
        self.x.XSetInputFocus.argtypes = [pointer, ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        self.x.XRaiseWindow.argtypes = [pointer, ctypes.c_ulong]
        root = self.x.XDefaultRootWindow(self.display)
        root_out, parent = ctypes.c_ulong(), ctypes.c_ulong()
        children, count = ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
        self.x.XQueryTree(self.display, root, ctypes.byref(root_out), ctypes.byref(parent),
                          ctypes.byref(children), ctypes.byref(count))
        window = None
        try:
            for index in range(count.value):
                name = ctypes.c_char_p()
                if self.x.XFetchName(self.display, children[index], ctypes.byref(name)) and name.value:
                    title = name.value.decode(errors="replace")
                    self.x.XFree(name)
                    self.records.append({"window_title": title})
                    if any(part in title.lower() for part in ("dk3", "daikatana", "quake")):
                        window = children[index]
                        self.records.append({"focus_window": title})
                        break
        finally:
            self.x.XFree(children)
        if window is None:
            raise RuntimeError("native engine window not found on guarded display")
        self.x.XRaiseWindow(self.display, window)
        self.x.XSetInputFocus(self.display, window, 2, 0)
        self.t.XTestFakeMotionEvent(self.display, -1, 480, 270, 0)
        self.x.XFlush(self.display)
        time.sleep(0.3)

    def key(self, name):
        self.records.append({"key": name})
        code = self.x.XKeysymToKeycode(self.display, self.x.XStringToKeysym(name.encode()))
        if not code:
            raise ValueError(f"unknown key: {name}")
        self.t.XTestFakeKeyEvent(self.display, code, 1, 0)
        self.x.XFlush(self.display)
        time.sleep(0.06)
        self.t.XTestFakeKeyEvent(self.display, code, 0, 0)
        self.x.XFlush(self.display)
        time.sleep(0.3)

    def click(self, x, y):
        self.records.append({"click_virtual": [x, y]})
        # Letterboxed 640x480 layout on the runner's 960x540 display.
        self.t.XTestFakeMotionEvent(self.display, -1, round(120 + x * 1.125), round(y * 1.125), 0)
        self.x.XFlush(self.display)
        time.sleep(0.15)
        self.t.XTestFakeButtonEvent(self.display, 1, 1, 0)
        self.x.XFlush(self.display)
        time.sleep(0.06)
        self.t.XTestFakeButtonEvent(self.display, 1, 0, 0)
        self.x.XFlush(self.display)
        time.sleep(0.4)

    def close(self):
        self.x.XCloseDisplay(self.display)


def run(args):
    args.report.mkdir(parents=True, exist_ok=True)
    log = args.report / "client.log"
    inputs = []
    with tempfile.TemporaryDirectory(prefix="dk3-native-ui-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.prefix, home)
        command = [str(args.engine / "bin/dk3")]
        for name, value in client_settings(args.engine, home, args.renderer).items():
            command += ["+set", name, value]
        command += ["+set", "in_nograb", "1"]
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"
            driver = None

            def issue(value, delay=0.2):
                inputs.append({"command": value})
                send(pipe, value)
                time.sleep(delay)

            def capture(name):
                issue(f"screenshotJPEG {name}")
                source = home / f"dk3/screenshots/{name}.jpg"
                wait(process, log, lambda _: source.exists(), 10)
                shutil.copy2(source, args.report / f"{name}.jpg")

            try:
                wait(process, log, lambda text: "native menus initialized" in text and pipe.exists())
                time.sleep(1)
                driver = Input(inputs)
                capture("new-game")
                driver.click(530, 323)  # Options plate.
                capture("options")
                driver.click(210, 190)  # Shiny weapons: Original -> Enhanced.
                issue("cg_shinyWeapons")
                if '"cg_shinyWeapons" is:"2' not in log.read_text(errors="replace"):
                    raise RuntimeError("mouse setting click did not change weapon shine")
                capture("options-enhanced")
                driver.key("Tab")
                driver.key("Up")
                driver.key("Up")
                driver.key("Return")  # Keyboard plate via keyboard navigation.
                issue('bind k "+back"')
                driver.click(200, 143)
                driver.key("k")
                capture("binding-conflict")
                driver.key("Escape")
                issue("bind k")
                if '"k" = "+back"' not in log.read_text(errors="replace"):
                    raise RuntimeError("cancelling key conflict changed its old binding")
                driver.click(200, 143)
                driver.key("k")
                driver.key("Return")
                issue("bind k")
                if '"k" = "+forward"' not in log.read_text(errors="replace"):
                    raise RuntimeError("confirmed key conflict did not rebind forward")
                capture("binding-replaced")
                driver.click(530, 72)
                driver.click(123, 349)
                wait(process, log, lambda text: "player entered isolated movement runtime" in text)
                issue("g_spSkill")
                if '"g_spSkill" is:"1' not in log.read_text(errors="replace"):
                    raise RuntimeError("Ronin selection did not start at easy difficulty")
                capture("campaign-start")
                driver.key("Escape")
                capture("paused")
                driver.key("Escape")
                capture("resumed")
                issue("quit", 0)
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("native menu shutdown failed")
                (args.report / "result.json").write_text(json.dumps({"renderer": args.renderer,
                    "scope": "native menu artwork, XTest mouse/keyboard settings, binding conflict cancel/replace, difficulty start and pause/resume; saves, multiplayer and full UI parity remain open"}, indent=2) + "\n")
            finally:
                (args.report / "inputs.json").write_text(json.dumps({"launch": command, "inputs": inputs}, indent=2) + "\n")
                if driver:
                    driver.close()
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--guard", type=Path, default=Path("zig-out/bin/dkguard"))
    parser.add_argument("--report", type=Path, default=Path("zig-out/reports/runtime-zig-229/ui"))
    parser.add_argument("--renderer", choices=("opengl1", "opengl2"), default="opengl1")
    parser.add_argument("--under-guard", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    if not args.under_guard:
        command = [str(args.guard), "--headless", "--screen", "960x540", "--timeout", "90s", "--mem", "8G", "--",
                   sys.executable, str(Path(__file__).resolve()), *sys.argv[1:], "--under-guard"]
        raise SystemExit(subprocess.call(command))
    run(args)
    print(f"Native UI scenario passed. Inspect captures in {args.report}.")


if __name__ == "__main__":
    main()
