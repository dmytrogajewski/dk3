# SPDX-License-Identifier: GPL-2.0-or-later
"""Opening route development through ordinary inputs; no fixture mutations."""
import json
import math
import re
import shutil
import time


def actors(driver):
    text = driver.diagnostics("dk3_runtime_actors", "dk3 zig actor states complete")
    result = {}
    for line in text.splitlines():
        if "dk3 zig actor:" not in line:
            continue
        row = dict(re.findall(r"(\w+)=([^ ]*)", line))
        for key in ("pos", "aim", "velocity", "angles"):
            if key in row:
                row[key] = tuple(map(float, row[key].split(",")))
        row["health"] = int(row["health"])
        result[int(row["id"])] = row
    return result


def nearest_hostile(driver, distance=500, expected_map=None):
    state = driver.observe()
    if expected_map is not None and state["map"] != expected_map:
        raise RuntimeError(f"Unexpected map while choosing encounter: {expected_map} -> {state['map']}")
    candidates = []
    for identity, row in actors(driver).items():
        if row["health"] <= 0 or row.get("sight") != "1" or row.get("threat") == "0" or row.get("class") not in ("monster_slaughterskeet", "monster_froginator"):
            continue
        separation = math.dist(state["pos"], row["pos"])
        if separation < distance:
            candidates.append((separation, identity, row))
    return min(candidates, default=None)


def firing_pause(row):
    if int(row["attack_left"]) < 600:
        return False  # Allow the acknowledged aim/fire commands and projectile flight.
    if row["class"] == "monster_froginator":
        return row.get("frog") in ("bite", "spit") and math.hypot(*row["velocity"][:2]) < 1 and row.get("ground") != "2047"
    return row.get("skeeter") == "attack" and math.dist(row["velocity"], (0, 0, 0)) < 1


def fight(driver, capture, expected_map):
    if driver.observe()["health"] < 25:
        driver.inputs.append({"engagement_deferred": "low health; continue toward authored resupply"})
        return False
    target = nearest_hostile(driver, expected_map=expected_map)
    if target is None:
        return False
    if not firing_pause(target[2]):
        return False
    driver.stop_forward()
    _, identity, row = target
    checkpoint = driver.save(f"encounter_{identity}")
    shutil.copy2(checkpoint, driver.log.parent / checkpoint.name)
    for window in range(3):
        state = driver.ready(2)
        if state["map"] != expected_map:
            raise RuntimeError("Unexpected map change during combat")
        if state["health"] < 25:
            driver.inputs.append({"engagement_deferred": identity, "reason": "continue toward authored resupply"})
            return True
        deadline = time.monotonic() + 2
        while True:
            row = actors(driver).get(identity)
            state = driver.observe()
            if row is None or row["health"] <= 0:
                return True
            if state["health"] < 25:
                return True
            if firing_pause(row):
                break
            if time.monotonic() >= deadline:
                driver.inputs.append({"engagement_deferred": identity, "reason": "no firing window; continue approach", "actor": row})
                return True
        if row.get("sight") != "1":
            return True
        point = row.get("aim", row["pos"])
        delta = [point[i] - state["pos"][i] for i in range(3)]
        delta[2] -= 22
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])),
                   -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
        previous = row.copy()
        before = driver.ready(2)
        fired = contacted = False
        deadline = time.monotonic() + 2
        driver.issue("+attack")
        try:
            # Hold ordinary automatic fire across a real attack pause. Releasing
            # and re-acknowledging every shot consumed most of a skeet's window.
            while time.monotonic() < deadline:
                state = driver.observe()
                fired |= state["event"] != before["event"] and state["fire"] != before["fire"]
                if state["map"] != expected_map or state["health"] <= 0:
                    raise RuntimeError("Combat interrupted by death or an unexpected map change")
                row = actors(driver).get(identity)
                contacted |= row is None or row["health"] < previous["health"]
                if row is None or row["health"] <= 0:
                    break
                if row["state"] != "attack" or int(row["attack_left"]) < 150 or math.dist(row["pos"], previous["pos"]) > 4:
                    break
        finally:
            driver.issue("-attack")
            driver.until(lambda s: not s["buttons"] & 1, description="processed burst release")
        if not fired:
            raise RuntimeError("No actual fire event in the observed attack window")
        if not contacted:
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                row = actors(driver).get(identity)
                if row is None or row["health"] < previous["health"]:
                    contacted = True
                    break
        driver.inputs.append({"combat_window": window, "target": identity, "fired": fired,
                              "contacted": contacted, "before": previous, "after": row})
        if not contacted:
            capture(f"aim-no-contact-{identity}-{window}")
            raise RuntimeError(f"No confirmed target contact for {identity}; inspect attack window and trace")
        if row is None or row["health"] <= 0:
            capture(f"encounter-{identity}-cleared")
            return True
    raise RuntimeError(f"Combat windows exhausted for {identity}; inspect evidence")


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
            if distance < 48:
                return state
            if distance < best - 8:
                best, last_progress = distance, time.monotonic()
            if time.monotonic() - last_progress > 3:
                capture("navigation-stalled")
                raise RuntimeError(f"No movement progress toward {point}; current {state['pos']}")
            if combat and time.monotonic() >= next_combat:
                if nearest_hostile(driver, 430, expected_map) and fight(driver, capture, expected_map):
                    deadline = time.monotonic() + 15
                    last_progress = time.monotonic()
                    heading, moving = None, False
                next_combat = time.monotonic() + 0.75
                state = driver.observe()
            yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
            if heading is None or abs((yaw - heading + 180) % 360 - 180) > 12:
                # Stop during angle/diagnostic round trips. Continuing at full speed
                # through several acknowledgements made the driver circle waypoints.
                driver.stop_forward()
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
        driver.stop_forward()


def opening_route(driver, capture, report, phase="arrival"):
    if phase in ("first-encounter", "marsh-middle", "marsh-late", "marsh-exit"):
        return marsh_exit(driver, capture, report, start_index=27 if phase == "marsh-exit" else 18 if phase == "marsh-late" else 9 if phase == "marsh-middle" else 0)
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


def marsh_exit(driver, capture, report, start_index=0):
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
             (-696, -1416, 503))
    try:
        for index, point in enumerate(route):
            if index < start_index:
                continue
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
