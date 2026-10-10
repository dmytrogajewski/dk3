#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Guarded native menu scenario using XTest mouse/keyboard events and an isolated profile."""
import argparse
import ctypes
import ctypes.util
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

from runtime_probe import client_settings, send, stage_client_modules, wait
from runtime_input import NativeInput, engine_failure, record_identity


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
        self.focus()

    def focus(self, center=True):
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
        if center:
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

    def align_menu(self):
        # The UI owns a relative cursor; renderer recreation resets that cursor
        # independently of X's absolute pointer. Sweep beyond its bounds, then
        # land at the letterboxed origin so both coordinate spaces agree.
        self.records.append({"align_menu": "bottom-right then letterbox origin"})
        for x, y in ((959, 539), (120, 0)):
            self.t.XTestFakeMotionEvent(self.display, -1, x, y, 0)
            self.x.XFlush(self.display)
            time.sleep(0.2)

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


def saves_scenario(driver, issue, capture, process, log, home, observer):
    issue("devmap e1m3a", 0.1)
    wait(process, log, lambda text: "first snapshot applied" in text or engine_failure(text))
    observer.until(lambda s: s["map"] == "e1m3a" and s["mode"] == "normal" and s["input"] > 0,
                   description="save-menu fixture has actual connected input")
    driver.focus()
    issue("dk3_runtime_place 818.916 -479.481 -823.875", 0.4)
    setup = observer.observe()
    if setup["health"] <= 0 or sum((a - b) ** 2 for a, b in zip(setup["pos"], (818.916, -479.481, -823.875))) > 64:
        raise RuntimeError(f"Save fixture did not reach the expected living location: {setup}")
    driver.key("Escape")
    # This is a controlled UI fixture, not campaign progression. Establish
    # its health while the real pause menu holds ordinary simulation.
    issue("dk3_runtime_probe_health 100")
    if observer.observe()["health"] != 100:
        raise RuntimeError("Paused save-menu fixture did not establish its health")
    driver.align_menu()
    driver.click(530, 156)  # Save category.
    driver.click(155, 175)  # Save1, below quick.
    capture("save-slot-selected")
    driver.click(330, 343)
    save = home / "state/dk3/saves/save1.sav"
    wait(process, log, lambda _: save.exists())
    issue("dk3_runtime_damage 30")
    corrupted = bytearray(save.read_bytes())
    corrupted[-1] ^= 1
    (save.parent / "bad.sav").write_bytes(corrupted)
    driver.key("Escape")
    driver.align_menu()
    driver.click(530, 128)  # Load category, sorted bad then save1.
    driver.click(330, 343)  # Corruption must leave menu and current game intact.
    capture("corrupt-save-refused")
    driver.click(155, 175)
    capture("load-slot-selected")
    driver.click(330, 343)
    wait(process, log, lambda text: "saved world restored" in text)
    issue("dk3_runtime_inventory")
    health = re.findall(r"zig inventory .*health=(-?\d+)", log.read_text(errors="replace"))
    if not health or health[-1] != "100":
        raise RuntimeError("mouse-selected save failed to restore health")
    capture("mouse-load-restored")
    issue("disconnect", 0.8)
    driver.focus(center=False)
    driver.align_menu()
    driver.click(530, 128)
    driver.click(155, 175)
    capture("main-menu-save-selected")
    before = len(log.read_text(errors="replace"))
    driver.click(330, 343)
    wait(process, log, lambda text: "saved world restored" in text[before:])
    text = log.read_text(errors="replace")[before:]
    maps = re.findall(r"^Server: ([^\n]+)", text, re.M)
    if maps != ["e1m3a"]:
        raise RuntimeError(f"menu load started unexpected maps: {maps}")
    issue("dk3_runtime_inventory")
    if re.findall(r"zig inventory .*health=(-?\d+)", log.read_text(errors="replace"))[-1] != "100":
        raise RuntimeError("main-menu load lost saved player state")
    capture("direct-map-restored")
    return {"maps_started_by_load": maps, "setup": "Diagnostic placement and 100 health in e1m3a; explicit 30 damage after the save. Not a campaign scenario.",
            "scope": "XTest select save1 then click Save/Load; corrupt slot rejection; in-game restoration and direct main-menu saved-map restoration without a marsh detour; native schema only"}


def menu_scenario(driver, issue, capture, process, log):
    capture("new-game")
    driver.click(530, 323)
    capture("options")
    driver.click(210, 190)
    issue("cg_shinyWeapons")
    if '"cg_shinyWeapons" is:"2' not in log.read_text(errors="replace"):
        raise RuntimeError("mouse setting click did not change weapon shine")
    capture("options-enhanced")
    driver.key("Tab")
    driver.key("Up")
    driver.key("Up")
    driver.key("Return")
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
    return {"scope": "native menu artwork, XTest mouse/keyboard settings, binding conflict cancel/replace and difficulty start; pause/resume has its separate synchronized presentation scenario; saves, multiplayer and full UI parity remain open"}


def maps_scenario(driver, issue, capture, process, log, observer):
    def variable(name):
        offset = log.stat().st_size
        issue(name, 0)
        pattern = rf'"{re.escape(name)}" is:"([^"\n]*)'
        text = wait(process, log, lambda text: re.search(pattern, text[offset:]) is not None, 5)
        return re.search(pattern, text[offset:])[1].split('^')[0]

    driver.align_menu()
    driver.click(530, 100)  # Multiplayer category.
    driver.click(220, 105)  # Internet create page, without submitting a room.
    assert variable('ui_roomMap') == 'e1dm1'
    driver.click(230, 140)
    capture('deathmatch-map-picker')
    driver.click(370, 370)  # Second page of installed deathmatch maps.
    capture('deathmatch-next-page')
    driver.key('Page_Up')
    driver.key('Down')
    driver.key('Down')  # Keyboard selection of the third row, e1dm1a.
    driver.key('Return')
    assert variable('ui_roomMap') == 'e1dm1a'
    # Real selection changes the same cvar consumed by Internet room creation.
    driver.click(230, 140)
    driver.click(230, 288)  # Fifth row: e1dm2a.
    assert variable('ui_roomMap') == 'e1dm2a'
    capture('internet-map-selected')
    driver.click(230, 170)  # CTF must replace an incompatible DM-only map.
    assert variable('ui_roomMode') == '1'
    assert variable('ui_roomMap') == 'e1ctf1'
    driver.click(230, 140)
    capture('ctf-map-picker')
    driver.click(230, 198)  # Second CTF map, e2ctf1.
    assert variable('ui_roomMap') == 'e2ctf1'
    driver.click(230, 170)  # Deathtag has its own authored course.
    assert variable('ui_roomMode') == '2'
    assert variable('ui_roomMap') == 'e1dt1'
    driver.click(230, 140)
    capture('deathtag-map-picker')
    driver.key('Escape')
    # Escape cancels only the picker and retains the Create page and selection.
    driver.click(230, 170)
    assert variable('ui_roomMode') == '0'
    driver.click(390, 105)  # LAN shares the picker and persistent choice.
    assert variable('ui_roomMap') == 'e1dt1'
    driver.click(230, 140)
    driver.click(230, 198)  # e1dm1 is second in the installed DM list.
    assert variable('ui_roomMap') == 'e1dm1'
    capture('lan-map-selected')
    before = log.stat().st_size
    driver.click(175, 295)
    wait(process, log, lambda text: 'first snapshot applied' in text[before:], 60)
    state = observer.until(lambda s: s['map'] == 'e1dm1' and s['mode'] == 'normal' and s['input'] > 0,
                           seconds=30, description='selected LAN map accepts normal player input')
    assert variable('g_gametype') == '0'
    capture('selected-lan-map-running')
    return {'scope': 'Real XTest map picker clicks and keyboard selection/paging/cancel; mode-specific choices and Internet/LAN selection retention; LAN launch into e1dm1 with processed player input. No Internet room creation or public service mutation.', 'lan': state}


def video_scenario(driver, issue, capture, process, log):
    driver.align_menu()
    driver.click(530, 212)  # Video category.
    capture("video-1")
    for page in range(2, 8):
        driver.click(397, 391)  # Next >.
        capture(f"video-{page}")
    driver.click(397, 391)  # Wraps back to the first page.
    capture("video-wrap")
    return {"scope": "Real XTest clicks through the paged Video settings (display and Vulkan remaster pages). Captures only; settings values are not asserted."}


def run(args):
    if not __debug__ or (args.report.exists() and any(args.report.iterdir())):
        raise RuntimeError("Native menu evidence requires assertions and a fresh directory")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.prefix, args.report, require_installation=True)
    log = args.report / "client.log"
    inputs = []
    with tempfile.TemporaryDirectory(prefix="dk3-native-ui-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.prefix, home, installation=args.engine)
        command = [str(args.engine / "bin/dk3")]
        for name, value in client_settings(args.engine, home, args.renderer).items():
            command += ["+set", name, value]
        command += ["+set", "in_nograb", "1", "+set", "g_spSkill", "3"]
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"
            driver = None
            observer = NativeInput(process, pipe, log, home, inputs, diagnostic=True)

            def issue(value, delay=0.2):
                if failure := engine_failure(log.read_text(errors="replace")):
                    raise RuntimeError(failure)
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
                if args.scenario == "saves":
                    result = saves_scenario(driver, issue, capture, process, log, home, observer)
                elif args.scenario == "maps":
                    result = maps_scenario(driver, issue, capture, process, log, observer)
                elif args.scenario == "video":
                    result = video_scenario(driver, issue, capture, process, log)
                else:
                    result = menu_scenario(driver, issue, capture, process, log)
                issue("quit", 0)
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("native menu shutdown failed")
                (args.report / "result.json").write_text(json.dumps({"identity": identity, "status": "passed", "renderer": args.renderer, **result}, indent=2) + "\n")
            except Exception as error:
                (args.report / "result.json").write_text(json.dumps({"identity": identity, "status": "failed", "error": str(error)}, indent=2) + "\n")
                raise
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
    parser.add_argument("--guard", type=Path, default=Path("zig-out/native-dev/bin/dkguard"))
    parser.add_argument("--report", type=Path, default=Path("zig-out/reports/runtime-zig-229/ui"))
    parser.add_argument("--renderer", choices=("opengl1", "opengl2", "vulkan"), default="opengl1")
    parser.add_argument("--scenario", choices=("menus", "saves", "maps", "video"), default="menus")
    parser.add_argument("--under-guard", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    if not args.under_guard:
        command = [str(args.guard), "--headless", "--screen", "960x540", "--timeout", "150s" if args.scenario == "maps" else "90s", "--mem", "8G", "--",
                   sys.executable, str(Path(__file__).resolve()), *sys.argv[1:], "--under-guard"]
        raise SystemExit(subprocess.call(command))
    run(args)
    print(f"Native UI scenario passed. Inspect captures in {args.report}.")


if __name__ == "__main__":
    main()
