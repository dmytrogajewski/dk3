# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused opening camera/resupply diagnostics, using fresh authored entities."""
import json
import math
import re
import shutil
import time

from runtime_opening_route import actors
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Actor diagnostics require fixture mode")

    def capture(name):
        driver.issue(f"screenshotJPEG {name}")
        source = driver.home / f"dk3/screenshots/{name}.jpg"
        wait(driver.process, driver.log, lambda _: source.exists() and source.stat().st_size > 0, 5)
        shutil.copy2(source, report / source.name)

    def tree():
        text = driver.diagnostics("dk3_runtime_world", "world states complete")
        match = re.search(r"tree: id=39 fruit=(\d+) maximum=(\d+) ready=(-?\d+) pos=([\d.,-]+)", text)
        if not match:
            raise RuntimeError("Authored health tree 39 is missing")
        return {"fruit": int(match[1]), "maximum": int(match[2]), "ready": int(match[3]), "pos": tuple(map(float, match[4].split(',')))}

    driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal", description="fresh opening diagnostic connected")
    cameras = actors(driver)
    assert cameras[9]["class"] == cameras[10]["class"] == "monster_cambot"
    assert cameras[9]["ignore"] == "0" and cameras[10]["ignore"] == "1"
    assert cameras[9]["camera_alarm"] == "0"
    driver.save("fresh_opening_fixture")
    camera = cameras[9]
    yaw = math.radians(camera["angles"][1])
    point = (camera["pos"][0] + 96 * math.cos(yaw), camera["pos"][1] + 96 * math.sin(yaw), camera["pos"][2] - 40)
    driver.issue("dk3_runtime_place " + " ".join(map(str, point)))
    driver.until(lambda s: math.dist(s["pos"], point) < 40, seconds=2, description="camera sight fixture accepted")
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        rows = actors(driver)
        if rows[9]["camera_seen"] == "1" and rows[9]["camera_alarm"] != "0":
            break
        driver.observe()
    else:
        raise RuntimeError("Cambot failed acquisition setup; no alarm acceptance")
    driver.save("camera_alert")
    driver.load("camera_alert")
    restored = actors(driver)[9]
    assert restored["camera_seen"] == "1" and restored["camera_alarm"] == rows[9]["camera_alarm"]
    state = driver.observe()
    delta = [restored["pos"][i] - state["pos"][i] for i in range(3)]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
    capture("camera-alert-restored")
    driver.load("fresh_opening_fixture")
    assert tree()["fruit"] == tree()["maximum"] == 4
    driver.diagnostics("dk3_runtime_face_target 39 64", "target=39")
    driver.issue("dk3_runtime_damage 50")
    driver.until(lambda s: s["health"] == 50, description="controlled resupply need")
    state = driver.observe()
    point = tree()["pos"]
    delta = [point[i] - state["pos"][i] for i in range(3)]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
    fruit = []
    for remaining in (3, 2, 1, 0):
        due = tree()["ready"]
        driver.until(lambda s: s["now"] >= due, description="tree cooldown deadline")
        before_health = driver.observe()["health"]
        before = len(driver.text())
        driver.issue("use")
        used = wait(driver.process, driver.log, lambda text: f"tree: id=39 fruit={remaining}" in text[before:], 3)[before:]
        healed = int(re.search(rf"tree: id=39 fruit={remaining} player=\d+ health=(\d+)", used)[1])
        assert healed == before_health + 10, "Concurrent damage or incorrect heal invalidates this sample"
        driver.observe()
        actual = tree()
        assert actual["fruit"] == remaining
        fruit.append({"before": before_health, "after_use": healed, "fruit": remaining})
        if remaining == 2:
            driver.save("tree_partial")
            driver.load("tree_partial")
            assert tree()["fruit"] == 2
    assert len(fruit) == 4 and fruit[-1]["fruit"] == 0
    capture("tree-exhausted")
    driver.save("tree_empty")
    driver.load("tree_empty")
    assert tree()["fruit"] == 0
    return {"scope": "Fresh-map Cambot acquisition/alarm state restoration and finite authored health-tree use/partial/empty save restoration. Diagnostic placement and player damage; no connected campaign or full camera interaction acceptance.", "camera": restored, "health_after_fruit": fruit}
