#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused Wisp/Nightmare/Metamaser diagnostics, explicitly outside campaign acceptance."""
import math
import re
import shutil
import time

from runtime_input import NativeInput
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Controller diagnostics require fixture authorization")

    def capture(name):
        source = driver.home / f"dk3/screenshots/{name}.jpg"
        driver.issue(f"screenshotJPEG {name}")
        wait(driver.process, driver.log, lambda _: source.exists() and source.stat().st_size > 0, 5)
        shutil.copy2(source, report / f"{name}.jpg")

    def inspect(kind="projectiles"):
        return driver.diagnostics(f"dk3_runtime_{kind}", f"{kind[:-1] if kind == 'beams' else 'projectile'} states complete")

    def controller(pattern, *, kind="projectiles", seconds=8):
        deadline = time.monotonic() + seconds
        last = ""
        while time.monotonic() < deadline:
            last = inspect(kind)
            match = re.search(pattern, last)
            if match:
                return match
        raise RuntimeError(f"Controller setup/state not reached: {pattern}; last={last}")

    def equip(weapon):
        driver.issue(f"dk3_runtime_equip {weapon}")
        driver.select(weapon)

    def face():
        text = driver.diagnostics("dk3_runtime_face_target 9 128", "target=9")
        position = tuple(map(float, re.search(r"fixture player=([\d.,-]+)", text)[1].split(',')))
        dx, dy, dz = 288 - position[0], -152 - position[1], -64 - position[2] - 22
        driver.aim(math.degrees(math.atan2(dy, dx)), -math.degrees(math.atan2(dz, math.hypot(dx, dy))))

    driver.issue("developer 1")
    driver.issue("dk3_runtime_probe_health 10000")
    driver.until(lambda s: s["health"] == 10000, description="diagnostic health setup")
    face()
    driver.save("controller_base")

    equip(19)
    before = len(driver.text())
    driver.fire()
    first = controller(r"wyndrax state: id=(\d+) phase=active enemy=([1-9]\d*) targets=([1-9][\d,]+)")
    driver.save("wisp_active")
    driver.load("wisp_active")
    controller(rf"wyndrax state: id={first[1]} phase=active")
    capture("wisp-restored")
    wait(driver.process, driver.log, lambda text: re.search(r"combat: target=(9|10) blood=[1-9]", text[before:]) is not None, 6)
    controller(rf"wyndrax state: id={first[1]} phase=fading")
    capture("wisp-fading")

    driver.load("controller_base")
    equip(20)
    driver.fire()
    casting = controller(r"nightmare state: id=(\d+) phase=casting", kind="beams")
    driver.save("nightmare_cast")
    driver.load("nightmare_cast")
    controller(rf"nightmare state: id={casting[1]} phase=casting", kind="beams")
    reap = controller(rf"nightmare state: id={casting[1]} phase=reaping targets=(\d+) cursor=1 victim=(9|10)", kind="beams")
    if int(reap[1]) < 2:
        raise RuntimeError("Nightmare setup did not mark both authored workers")
    driver.save("nightmare_reaping")
    driver.load("nightmare_reaping")
    controller(rf"nightmare state: id={casting[1]} phase=reaping .*victim={reap[2]}", kind="beams")
    capture("nightmare-restored")
    before = len(driver.text())
    wait(driver.process, driver.log, lambda text: all(re.search(rf"combat: target={target} .*killed=1", text[before:]) for target in (9, 10)), 14)
    driver.until(lambda s: s["ready"], seconds=5, description="ritual completion releases weapon")
    if "nightmare state:" in inspect("beams"):
        raise RuntimeError("Completed ritual left a controller")
    capture("nightmare-complete")

    driver.load("controller_base")
    equip(26)
    driver.aim(driver.observe()["angles"][1], 60)
    driver.fire()
    arm = controller(r"metamaser state: id=(\d+) phase=arming health=300 charges=30\b")
    driver.save("metamaser_arming")
    driver.load("metamaser_arming")
    controller(rf"metamaser state: id={arm[1]} phase=arming")
    controller(rf"metamaser state: id={arm[1]} phase=tracking .*charges=(?:[0-9]|[12][0-9])\b locks=[\d,]*[1-9]")
    driver.save("metamaser_tracking")
    driver.load("metamaser_tracking")
    controller(rf"metamaser state: id={arm[1]} phase=tracking")
    capture("metamaser-restored")
    controller(rf"metamaser state: id={arm[1]} phase=dying .*bursts=[1-9]", seconds=23)
    driver.save("metamaser_dying")
    driver.load("metamaser_dying")
    controller(rf"metamaser state: id={arm[1]} phase=dying")
    capture("metamaser-dying-restored")
    driver.elapsed(7500)
    if "metamaser state:" in inspect():
        raise RuntimeError("Metamaser survived its destruction deadline")
    return {"scope": "Focused diagnostics: Wisp saved homing/target links and damage; Nightmare saved casting/reaping, two workers killed and completion; Metamaser supplied setup, arming/tracking/destruction saves and expiry. Diagnostic placement, equipment and health. No connected campaign or full weapon interaction acceptance."}
