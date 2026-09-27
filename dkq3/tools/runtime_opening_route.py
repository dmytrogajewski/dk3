# SPDX-License-Identifier: GPL-2.0-or-later
"""Opening route development through ordinary inputs; no fixture mutations."""
import json
import math
import re
import shutil
import time


def actors(driver):
    text = driver.diagnostics("dk3_runtime_actors", "dk3 zig actor:")
    result = {}
    for line in text.splitlines():
        if "dk3 zig actor:" not in line:
            continue
        row = dict(re.findall(r"(\w+)=([^ ]*)", line))
        row["pos"] = tuple(map(float, row["pos"].split(",")))
        row["health"] = int(row["health"])
        result[int(row["id"])] = row
    return result


def nearest_hostile(driver, distance=500):
    state = driver.observe()
    candidates = []
    for identity, row in actors(driver).items():
        if row["health"] <= 0 or row.get("class") not in ("monster_slaughterskeet", "monster_froginator"):
            continue
        separation = math.dist(state["pos"], row["pos"])
        if separation < distance:
            candidates.append((separation, identity, row))
    return min(candidates, default=None)


def fight(driver, capture):
    target = nearest_hostile(driver)
    if target is None:
        return
    driver.issue("-forward")
    driver.until(lambda s: not s["forward"], description="stop to aim")
    _, identity, row = target
    for shot in range(10):
        state = driver.ready(2)
        if state["health"] < 25:
            raise RuntimeError("Route development reached low health; stop and choose resupply or an earlier legitimate checkpoint")
        if row["health"] <= 0:
            return
        delta = [row["pos"][i] - state["pos"][i] for i in range(3)]
        delta[2] -= 22
        yaw = math.degrees(math.atan2(delta[1], delta[0]))
        pitch = -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2])))
        driver.aim(yaw, pitch)
        driver.fire()
        deadline = time.monotonic() + 2
        previous = row["health"]
        while time.monotonic() < deadline:
            row = actors(driver).get(identity)
            if row is None or row["health"] < previous:
                break
            if driver.observe()["health"] <= 0:
                raise RuntimeError("Player died; route checkpoint failed")
        else:
            capture(f"aim-no-contact-{identity}-{shot}")
            raise RuntimeError(f"No confirmed target contact for {identity}; revise aim/navigation instead of repeating shots")
        if row is None or row["health"] <= 0:
            capture(f"encounter-{identity}-cleared")
            return
    raise RuntimeError(f"Combat budget reached for {identity}; inspect evidence")


def walk(driver, point, capture, *, combat=False):
    deadline = time.monotonic() + 12
    last_progress = time.monotonic()
    best = float("inf")
    try:
        while time.monotonic() < deadline:
            state = driver.observe()
            if state["health"] <= 0:
                raise RuntimeError("Player died during route movement")
            distance = math.dist(state["pos"][:2], point[:2])
            if distance < 22:
                return state
            if distance < best - 8:
                best, last_progress = distance, time.monotonic()
            if time.monotonic() - last_progress > 2:
                capture("navigation-stalled")
                raise RuntimeError(f"No movement progress toward {point}; current {state['pos']}")
            if combat and nearest_hostile(driver, 430):
                fight(driver, capture)
                deadline = time.monotonic() + 12
                last_progress = time.monotonic()
            yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
            driver.aim(yaw, 0)
            driver.issue("+forward")
            driver.until(lambda s: s["forward"] > 0, description="processed forward input")
        raise TimeoutError(f"Route movement did not reach {point}")
    finally:
        driver.issue("-forward")
        driver.until(lambda s: s["forward"] == 0, description="processed forward release")


def opening_route(driver, capture, report):
    state = driver.observe()
    if state["map"] != "e1m1a" or state["health"] != 100 or state["weapon"] != 1:
        raise RuntimeError(f"Opening setup is not ordinary arrival: {state}")
    try:
        walk(driver, (1584, -2424), capture)
        state = driver.select(2)
        if state["ammo"] <= 0:
            raise RuntimeError("Ion pickup did not supply ammunition")
        capture("ordinary-ion-pickup")
        checkpoint = driver.save("opening_ion")
        shutil.copy2(checkpoint, report / checkpoint.name)
        for waypoint in ((1320, -2340), (1100, -2240), (880, -2200)):
            walk(driver, waypoint, capture, combat=True)
        capture("opening-first-encounter")
        checkpoint = driver.save("opening_first_encounter")
        shutil.copy2(checkpoint, report / checkpoint.name)
        return {"scope": "Ordinary Ion pickup and first approach; not full map traversal", "state": driver.observe()}
    except Exception as error:
        capture("opening-failure")
        (report / "opening-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise
