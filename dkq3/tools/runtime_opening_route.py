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


def nearest_hostile(driver, distance=500, expected_map=None):
    state = driver.observe()
    if expected_map is not None and state["map"] != expected_map:
        raise RuntimeError(f"Unexpected map while choosing encounter: {expected_map} -> {state['map']}")
    candidates = []
    for identity, row in actors(driver).items():
        if row["health"] <= 0 or row.get("threat") == "0" or row.get("class") not in ("monster_slaughterskeet", "monster_froginator"):
            continue
        separation = math.dist(state["pos"], row["pos"])
        if separation < distance:
            candidates.append((separation, identity, row))
    return min(candidates, default=None)


def fight(driver, capture, expected_map):
    target = nearest_hostile(driver, expected_map=expected_map)
    if target is None:
        return
    driver.issue("-forward")
    driver.until(lambda s: not s["forward"], description="stop to aim")
    _, identity, row = target
    for shot in range(10):
        state = driver.ready(2)
        if state["map"] != expected_map:
            raise RuntimeError("Unexpected map change during combat")
        if state["health"] < 25:
            raise RuntimeError("Route development reached low health; stop and choose resupply or an earlier legitimate checkpoint")
        if row["health"] <= 0:
            return
        # The frog can leap across the sight line while view commands are in flight.
        # Observe a grounded/settled firing opportunity instead of aiming at an old
        # pre-jump coordinate and repeating misses.
        deadline = time.monotonic() + 6
        while True:
            previous_row = row
            row = actors(driver).get(identity)
            state = driver.observe()
            if row is None or row["health"] <= 0:
                return
            if state["health"] < 25:
                raise RuntimeError("Low health while waiting for a firing opportunity")
            if row["class"] != "monster_froginator" or math.dist(previous_row["pos"], row["pos"]) < 2:
                break
            if time.monotonic() >= deadline:
                capture(f"no-firing-opportunity-{identity}")
                raise RuntimeError(f"Target {identity} did not settle; revise engagement position")
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
    deadline = time.monotonic() + 15
    last_progress = time.monotonic()
    next_combat = 0
    best = float("inf")
    heading = None
    moving = False
    jumped = False
    expected_map = driver.observe()["map"]
    try:
        while time.monotonic() < deadline:
            state = driver.observe()
            if state["map"] != expected_map:
                raise RuntimeError(f"Unexpected map change during waypoint movement: {expected_map} -> {state['map']}")
            if state["health"] <= 0:
                raise RuntimeError("Player died during route movement")
            distance = math.dist(state["pos"][:2], point[:2])
            if distance < 32:
                return state
            if distance < best - 8:
                best, last_progress = distance, time.monotonic()
            if time.monotonic() - last_progress > 3:
                capture("navigation-stalled")
                raise RuntimeError(f"No movement progress toward {point}; current {state['pos']}")
            if combat and time.monotonic() >= next_combat:
                if nearest_hostile(driver, 430, expected_map):
                    fight(driver, capture, expected_map)
                    deadline = time.monotonic() + 15
                    last_progress = time.monotonic()
                    heading, moving = None, False
                next_combat = time.monotonic() + 0.75
                state = driver.observe()
            yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
            if heading is None or abs((yaw - heading + 180) % 360 - 180) > 12:
                # Stop during angle/diagnostic round trips. Continuing at full speed
                # through several acknowledgements made the driver circle waypoints.
                driver.issue("-forward")
                driver.until(lambda s: s["forward"] == 0, description="stop before steering")
                state = driver.observe()
                yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
                driver.aim(yaw, 0)
                heading, moving = yaw, False
            if not jumped and len(point) == 3 and point[2] - state["pos"][2] > 18 and distance < 100:
                start_z = state["pos"][2]
                driver.issue("+forward")
                driver.issue("+moveup")
                try:
                    driver.until(lambda s: s["up"] > 0 and s["pos"][2] > start_z + 8,
                                 seconds=2, description="ordinary jump gains height")
                finally:
                    driver.issue("-moveup")
                    driver.until(lambda s: s["up"] == 0, description="processed jump release")
                jumped, moving = True, True
            if not moving:
                driver.issue("+forward")
                driver.until(lambda s: s["forward"] > 0, description="processed forward input")
                moving = True
        raise TimeoutError(f"Route movement did not reach {point}")
    finally:
        driver.issue("-forward")
        driver.until(lambda s: s["forward"] == 0, description="processed forward release")


def opening_route(driver, capture, report, phase="arrival"):
    if phase == "first-encounter":
        return marsh_exit(driver, capture, report)
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
        for waypoint in ((1536, -2312, 528), (1606, -2157, 494), (1784, -2168, 504), (1824, -2128, 460), (1696, -1912, 408), (1504, -1904, 400), (1352, -1880, 392), (1320, -1920, 424), (1165, -1943, 402), (976, -2103, 373)):
            walk(driver, waypoint, capture, combat=True)
        capture("opening-first-encounter")
        checkpoint = driver.save("opening_first_encounter")
        shutil.copy2(checkpoint, report / checkpoint.name)
        return {"scope": "Ordinary Ion pickup and first approach; not full map traversal", "state": driver.observe()}
    except Exception as error:
        capture("opening-failure")
        (report / "opening-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise


def marsh_exit(driver, capture, report):
    state = driver.observe()
    if state["map"] != "e1m1a" or state["health"] <= 0 or state["weapon"] != 2:
        raise RuntimeError(f"First-encounter checkpoint setup invalid: {state}")
    route = ((730, -2081, 392), (499, -2047, 485), (393, -1854, 488),
             (430, -1618, 488), (374, -1538, 488), (240, -1528, 488),
             (160, -1544, 492), (72, -1632, 504), (-10, -1716, 532),
             (-64, -1772, 545), (-227, -1897, 517), (-291, -2004, 494),
             (-382, -2212, 474), (-462, -2276, 466), (-528, -2304, 416),
             (-607, -2303, 368), (-696, -2304, 344), (-819, -2268, 340),
             (-896, -2224, 328), (-872, -2160, 328), (-864, -2133, 302),
             (-848, -2053, 302), (-824, -1912, 296), (-823, -1868, 329),
             (-855, -1689, 393), (-880, -1560, 425), (-866, -1438, 474),
             (-648, -1416, 503))
    try:
        for index, point in enumerate(route):
            walk(driver, point, capture, combat=True)
            if index in (8, 17, 26):
                checkpoint = driver.save(f"opening_marsh_{index}")
                shutil.copy2(checkpoint, report / checkpoint.name)
                capture(f"marsh-{index}")
        checkpoint = driver.save("opening_before_exit")
        shutil.copy2(checkpoint, report / checkpoint.name)
        driver.aim(0, 0)
        driver.issue("+forward")
        try:
            state = driver.until(lambda s: s["map"] == "e1m1b" and s["mode"] == "normal", seconds=30, description="ordinary touch of authored e1m1b exit")
        finally:
            driver.issue("-forward")
            driver.until(lambda s: s["forward"] == 0, description="release after authored travel")
        capture("e1m1b-authored-arrival")
        checkpoint = driver.save("opening_bridge_arrival")
        shutil.copy2(checkpoint, report / checkpoint.name)
        return {"scope": "First marsh encounter checkpoint through authored e1m1b exit, ordinary inventory/input. Development replay, not fresh campaign acceptance.", "state": state}
    except Exception as error:
        capture("marsh-failure")
        (report / "opening-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise
