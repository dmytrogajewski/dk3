# SPDX-License-Identifier: GPL-2.0-or-later
"""Opening route development through ordinary inputs; no fixture mutations."""
import json
import math
import re
import shutil
import time


def actors(driver):
    text = driver.diagnostics("dk3_runtime_actors", "dk3 zig actor states complete")
    return parse_actors(text)


def parse_actors(text):
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
        if row["health"] <= 0 or row.get("sight") != "1" or row.get("class") not in ("monster_slaughterskeet", "monster_froginator", "monster_crox"):
            continue
        separation = math.dist(state["pos"], row["pos"])
        if separation < distance and row.get("skeeter") != "hatching":
            candidates.append((separation, identity, row))
    return min(candidates, default=None)


def terminal_contact(text, identity):
    """A retired actor requires an actual terminal hit in this encounter's log."""
    for line in reversed(text.splitlines()):
        match = re.search(r"dk3 zig combat: target=(\d+) blood=(\d+) armor=(\d+) killed=([01])(?:\s|$)", line)
        if match and int(match[1]) == identity and int(match[2]) > 0 and match[4] == "1":
            return line
    return None


def fight(driver, capture, expected_map, target_id=None):
    state = driver.observe()
    if state["health"] <= 0:
        raise RuntimeError("Player died before the encounter")
    if target_id is None:
        target = nearest_hostile(driver, expected_map=expected_map)
    else:
        row = actors(driver).get(target_id)
        if row is None or row["health"] <= 0 or row.get("sight") != "1":
            return False
        target = (math.dist(state["pos"], row["pos"]), target_id, row)
    if target is None:
        return False
    _, identity, row = target
    driver.stop_forward(settle_vertical=True)
    state = driver.observe()
    close = math.dist(state["pos"], row["pos"]) < 64
    weapon = 1 if state["water"] >= 2 or (state["water"] == 1 and close) else 2
    if weapon == 1 and not close:
        return False
    state = driver.select(weapon) if state["weapon"] != weapon else driver.ready(weapon)
    if weapon == 2 and state["ammo"] <= 0:
        return False
    before, initial, previous = state, row.copy(), row.copy()
    fired = contacted = False
    encounter_start = len(driver.text())
    death_event = None
    lost_target = False
    deadline = time.monotonic() + 3
    held = False
    try:
        while time.monotonic() < deadline:
            state = driver.observe()
            if state["map"] != expected_map or state["health"] <= 0:
                raise RuntimeError("Combat interrupted by death or an unexpected map change")
            fired |= state["event"] != before["event"] and state["fire"] != before["fire"]
            row = actors(driver).get(identity)
            if row is None:
                death_event = terminal_contact(driver.text()[encounter_start:], identity)
                if death_event is not None:
                    contacted = True
                    break
                # This opportunistic encounter does not require a kill. An
                # actor can physically leave the active map after knockback.
                # Stop tracking it; absence establishes neither death nor hit.
                lost_target = True
                break
            contacted |= row["health"] < initial["health"]
            if row["health"] <= 0:
                break
            if row["sight"] != "1":
                break
            # Lead observed displacement, not an actor's desired velocity while
            # blocked against geometry. Keep tracking through short attack poses.
            elapsed = max(1, int(row["now"]) - int(previous["now"]))
            velocity = [(row["pos"][i] - previous["pos"][i]) * 1000 / elapsed for i in range(3)]
            lead = min(0.5, math.dist(row["aim"], state["pos"]) / 1800 + 0.05) if weapon == 2 else 0
            aim = (row["pos"][0], row["pos"][1], row["pos"][2] + 7) if row["class"] == "monster_crox" else row["aim"]
            point = [aim[i] + velocity[i] * lead for i in range(3)]
            delta = [point[i] - state["pos"][i] for i in range(3)]
            delta[2] -= 22
            yaw = math.degrees(math.atan2(delta[1], delta[0]))
            pitch = max(-87.890625, min(87.890625, -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2])))))
            if not held:
                driver.aim(yaw, pitch)
                if weapon == 2:
                    trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
                    first_hit = int(re.search(r"flight_target=(\d+)", trace)[1])
                    if first_hit not in (0, identity):
                        driver.inputs.append({"aim_obstruction": first_hit, "intended": identity})
                        break
                driver.issue("+attack")
                held = True
            else:
                driver.issue(f"dk3_look {yaw} {pitch}")
            previous = row.copy()
    finally:
        if held:
            driver.issue("-attack")
            released = driver.until(lambda s: not s["buttons"] & 1, description="processed combat release")
            fired |= released["event"] != before["event"] and released["fire"] != before["fire"]
        driver.inputs.append({"combat_target": identity, "fired": fired, "contacted": contacted,
                              "before": initial, "after": row, "death_event": death_event,
                              "lost_target": lost_target})
    if held and not fired:
        raise RuntimeError("Held attack produced no actual fire event")
    # A miss is a recorded gameplay outcome, not a target-contact pass. Continue
    # moving before trying again instead of spending another stationary window.
    return contacted


def walk(driver, point, capture, *, combat=False, tolerance=48, floor_limit=None, jump=True):
    deadline = time.monotonic() + 15
    last_progress = driver.forward_ms
    next_combat = 0
    best = float("inf")
    heading = None
    moving = False
    jumped = False
    swimming_up = False
    previous_motion = None
    pending_state = None
    expected_map = driver.observe()["map"]
    precise = tolerance <= 32
    if precise:
        driver.issue("+speed")
    try:
        while time.monotonic() < deadline:
            state = pending_state if pending_state is not None else driver.observe()
            pending_state = None
            if state["map"] != expected_map:
                raise RuntimeError(f"Unexpected map change during waypoint movement: {expected_map} -> {state['map']}")
            if state["health"] <= 0:
                raise RuntimeError("Player died during route movement")
            if floor_limit is not None and state["pos"][2] < floor_limit:
                driver.inputs.append({"waypoint_departure": {"point": point, "state": state}})
                return state  # Caller follows the connected lower route.
            surface = state["water"] >= 2 and len(point) == 3 and point[2] > state["pos"][2] + 8
            if surface and not swimming_up:
                driver.issue("+moveup")
                driver.until(lambda s: s["up"] > 0, description="processed swimming ascent")
                swimming_up = True
            elif swimming_up and not surface:
                driver.issue("-moveup")
                driver.until(lambda s: s["up"] == 0, description="processed swimming ascent release")
                swimming_up = False
            distance = math.dist(state["pos"][:2], point[:2])
            speed = 0
            if moving and previous_motion is not None and state["cmd"] > previous_motion["cmd"]:
                speed = min(320, 1000 * math.dist(state["pos"][:2], previous_motion["pos"][:2]) /
                            (state["cmd"] - previous_motion["cmd"]))
            previous_motion = state
            # Release ahead of the target using observed travel speed, then
            # acknowledge actual friction/position. Short approaches otherwise
            # alternate past the target before every release finishes.
            if distance < tolerance + speed * 0.10:
                state = driver.stop_forward()
                heading, moving = None, False
                if math.dist(state["pos"][:2], point[:2]) < tolerance:
                    return state
                continue
            if distance < best - 8:
                best, last_progress = distance, driver.forward_ms
            if driver.forward_ms - last_progress > 3000:
                capture("navigation-stalled")
                raise RuntimeError(f"No movement progress toward {point}; current {state['pos']}")
            if combat and state["water"] < 2 and time.monotonic() >= next_combat:
                # Actor/aim round trips are not movement ticks. Stop before
                # inspecting them so the player cannot run past the waypoint.
                inspection_started = time.monotonic()
                driver.stop_forward()
                heading, moving = None, False
                if fight(driver, capture, expected_map):
                    deadline = time.monotonic() + 15
                    last_progress = driver.forward_ms
                else:
                    # Deliberately stationary observations are not failed
                    # movement. Each diagnostic has its own bounded timeout.
                    stationary_time = time.monotonic() - inspection_started
                    deadline += stationary_time
                next_combat = time.monotonic() + 0.75
                state = driver.observe()
                if math.dist(state["pos"][:2], point[:2]) < tolerance:
                    return state
            yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
            if heading is None or abs((yaw - heading + 180) % 360 - 180) > 12:
                # Stop during angle/diagnostic round trips. Continuing at full speed
                # through several acknowledgements made the driver circle waypoints.
                driver.stop_forward()
                state = driver.observe()
                yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
                driver.aim(yaw, 0)
                heading, moving = yaw, False
            raised_goal = len(point) == 3 and point[2] - state["pos"][2] > 18 and distance < 100
            # A lip may be higher than the destination beyond it. Try one
            # ordinary jump after actual grounded forward input stops gaining
            # distance; do not infer a clear approach from waypoint height.
            blocked_approach = state["ground"] != 2047 and state["water"] <= 1 and driver.forward_ms - last_progress >= 750
            if jump and not swimming_up and not jumped and (raised_goal or blocked_approach):
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
                next_combat = time.monotonic() + 1.0  # Finish the jump before stopping for diagnostics.
            if not moving:
                driver.issue("+forward")
                # The acknowledgement already observes movement. Reuse it before
                # another diagnostic round trip can carry us past a close target.
                pending_state = driver.until(lambda s: 0 < s["forward"] <= (64 if precise else 127),
                                             description="processed forward input")
                moving = True
        raise TimeoutError(f"Route movement did not reach {point}")
    finally:
        try:
            driver.stop_forward()
        finally:
            if swimming_up:
                driver.issue("-moveup")
                driver.until(lambda s: s["up"] == 0, description="processed swimming ascent cleanup")
            if precise:
                driver.issue("-speed")


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
        return marsh_exit(driver, capture, report)
    except Exception as error:
        capture("opening-failure")
        (report / "opening-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise


def marsh_exit(driver, capture, report, start_index=0):
    state = driver.select(2)
    if state["map"] != "e1m1a" or state["health"] <= 0:
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
             (-768, -1416, 503))
    try:
        for index, point in enumerate(route):
            if index < start_index:
                continue
            if 12 <= index <= 20 and driver.observe()["pos"][2] < 340:
                # A fall into the authored lower pond connects through its own
                # supplied water/ground nodes; do not try to climb the tall rim.
                for lower in ((-560, -2008, 312), (-616, -1933, 318), (-768, -1920, 312), (-824, -1912, 320)):
                    walk(driver, lower, capture, combat=True)
                return marsh_exit(driver, capture, report, start_index=23)
            if 12 <= index <= 14 and driver.observe()["pos"][2] < 400:
                # The descending west ledge is above the pond. Once we land on
                # it, continue west instead of climbing back onto the upper rim.
                driver.inputs.append({"marsh_lower_ledge": driver.observe(), "resume_index": 15})
                return marsh_exit(driver, capture, report, start_index=15)
            walk(driver, point, capture, combat=True,
                 floor_limit=400 if 12 <= index <= 14 else 340 if 15 <= index <= 20 else None)
            if index in (1, 9):
                from runtime_bridge_route import checkpoint, resupply
                if index == 1:
                    detour = ((413, -2069, 488), (432, -2304, 536), (464, -2432, 592),
                              (592, -2528, 648), (608, -2464, 608), (608, -2424, 632),
                              (608, -2376, 654), (560, -2352, 664))
                    tree = 42
                else:
                    detour = ((-80, -1816, 584), (-64, -1870, 552), (-55, -1941, 585), (-64, -1948, 600))
                    tree = 40
                # Clear the visible defender before entering the narrow alcove.
                fight(driver, capture, "e1m1a")
                checkpoint(driver, capture, report, f"marsh_before_tree_{tree}")
                for supply in detour:
                    # Defenders can reach the alcove during the climb. A live
                    # mosquito above Hiro physically blocks a jump; continue
                    # observing/fighting instead of treating it as bad geometry.
                    walk(driver, supply, capture, combat=True, tolerance=20)
                uses = resupply(driver, tree)
                driver.inputs.append({"marsh_tree": tree, "uses": uses})
                checkpoint(driver, capture, report, f"marsh_tree_{tree}")
                for supply in reversed(detour[:-1]):
                    walk(driver, supply, capture, combat=True)
                walk(driver, point, capture, combat=True)
            if index in (8, 17, 26):
                checkpoint = driver.save(f"opening_marsh_{index}")
                shutil.copy2(checkpoint, report / checkpoint.name)
                capture(f"marsh-{index}")
        checkpoint = driver.save("opening_before_exit")
        shutil.copy2(checkpoint, report / checkpoint.name)
        driver.aim(0, 0)
        from runtime_campaign_restoration import travel
        state = travel(driver, "e1m1b")
        capture("e1m1b-authored-arrival")
        checkpoint = driver.save("opening_bridge_arrival")
        shutil.copy2(checkpoint, report / checkpoint.name)
        from runtime_bridge_route import bridge_route
        return {"scope": "Ordinary marsh route through the authored e1m1b exit; fresh status depends on the outer runner's starting point.", "state": driver.observe(), "bridge": bridge_route(driver, capture, report)}
    except Exception as error:
        capture("marsh-failure")
        (report / "opening-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise
