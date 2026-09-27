# SPDX-License-Identifier: GPL-2.0-or-later
"""Ordinary-input e1m1c progression, using its authored gates and outside path."""
import json
import math
import re
import time

from runtime_bridge_route import aim_at, checkpoint, resupply, shoot_control, world_rows
from runtime_opening_route import actors, walk


def movers(driver):
    before = len(driver.text())
    driver.issue("dk3_runtime_movers")
    driver.observe()  # FIFO observation completes after the whole synchronous dump.
    text = driver.text()[before:]
    rows = {}
    for line in text.splitlines():
        if "zig mover id=" in line:
            row = dict(re.findall(r"(\w+)=([^ ]*)", line))
            rows[int(row["id"])] = row
    driver.inputs.append({"movers": rows})
    return rows


def await_open(driver, identity, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        state = driver.observe()
        if state["health"] <= 0:
            raise RuntimeError("Player died waiting for the authored door")
        row = movers(driver).get(identity)
        if row is None:
            raise RuntimeError(f"Authored door controller {identity} is missing")
        if row["state"] == "open":
            return row
    raise TimeoutError(f"Authored door {identity} did not open: {row}")


def factory_route(driver, capture, report, phase="factory-arrival"):
    state = driver.select(2)
    if state["map"] != "e1m1c" or state["skill"] != 3 or state["health"] <= 0:
        raise RuntimeError("Factory route requires a legitimate normal-difficulty arrival")
    try:
        if phase == "factory-exit":
            return factory_exit(driver, capture, report)
        if phase == "factory-departure":
            return factory_departure(driver, capture, report)
        if phase in ("factory-interior", "factory-switch"):
            return factory_interior(driver, capture, report, phase)
        if phase in ("factory-arrival", "factory-outside"):
            for index, point in enumerate(((-814, 1574, 664), (-566, 1587, 641),
                    (-502, 1831, 633), (-413, 2069, 632), (-217, 2027, 536),
                    (-134, 2003, 495), (-48, 1971, 445), (121, 2101, 408),
                    (194, 2173, 408), (414, 2256, 408), (425, 2469, 376), (461, 2510, 403))):
                if phase == "factory-outside" and index <= 3:
                    continue
                walk(driver, point, capture, combat=True)
                if index == 6:
                    for supply in ((46, 1863, 412), (128, 1800, 408)):
                        walk(driver, supply, capture, combat=True, tolerance=20)
                    uses = resupply(driver, 195)
                    driver.inputs.append({"factory_tree": 195, "uses": uses})
                    checkpoint(driver, capture, report, "factory_tree_195")
                    for supply in ((46, 1863, 412), point):
                        walk(driver, supply, capture, combat=True)
                if index in (3, 9):
                    checkpoint(driver, capture, report, f"factory_outside_{index}")
            walk(driver, (480, 2576, 408), capture, combat=True, tolerance=20)
            checkpoint(driver, capture, report, "factory_before_gate")
        if phase not in ("factory-yard", "factory-yard-turn"):
            if phase != "factory-passage":
                if phase != "factory-upper":
                    # The switch is on the upper pipe, not the lamp above the lower
                    # locked doorway. Climb the supplied sloping pipe approach first.
                    for index, point in enumerate(((461, 2510, 403), (425, 2469, 376), (406, 2256, 408),
                                  (406, 2184, 444), (406, 2144, 464), (480, 2144, 456), (494, 2136, 456),
                                  (530, 2144, 528), (530, 2281, 529))):
                        if phase == "factory-pipe" and index < 6:
                            continue
                        if point == (406, 2144, 464):
                            driver.issue("+movedown")
                            driver.until(lambda state: state["up"] < 0, description="processed crouch on the low pipe")
                        # The safe takeoff is a small region, not one coordinate.
                        # Reversing across the sloped edge to correct an 8-unit
                        # overshoot can slide the player off the lower pipe.
                        tolerance = 12 if point == (494, 2136, 456) else 20 if point in ((530, 2144, 528), (530, 2281, 529), (461, 2510, 403), (425, 2469, 376)) else 8
                        walk(driver, point, capture, combat=False, tolerance=tolerance, jump=point == (530, 2144, 528))
                        if point == (530, 2281, 529):
                            # This is a straight approach segment, not the jump
                            # takeoff. Require the actual pipe height and ground;
                            # reversing to hit its exact centre adds no coverage.
                            crossing = driver.observe()
                            if crossing["ground"] == 2047 or not (527 <= crossing["pos"][2] <= 530):
                                raise RuntimeError(f"Pipe approach left the supported upper surface: {crossing}")
                        if point == (494, 2136, 456):
                            launch = driver.observe()["pos"]
                            if not (480 < launch[0] < 500 and 2120 < launch[1] < 2150 and launch[2] >= 456):
                                raise RuntimeError(f"Pipe takeoff is outside the actual upper edge: {launch}")
                        if point == (480, 2144, 456):
                            driver.issue("-movedown")
                            driver.until(lambda state: state["up"] == 0, description="processed crouch release")
                            checkpoint(driver, capture, report, "factory_pipe_launch")
                        capture(f"pipe-{point[0]}-{point[1]}")
                    walk(driver, (548, 2330, 528), capture, tolerance=8, jump=False)
                    checkpoint(driver, capture, report, "factory_pipe_crossing")
                    pipe_jump(driver, capture, (424, 2424, 584))
                    checkpoint(driver, capture, report, "factory_pipe_upper")
                    for point in ((424, 2464, 600), (424, 2504, 624), (480, 2544, 648), (488, 2568, 664)):
                        walk(driver, point, capture, tolerance=12, jump=False)
                    if driver.observe()["pos"][2] < 640:
                        raise RuntimeError("Gate firing position did not reach the upper pipe")
                    checkpoint(driver, capture, report, "factory_upper_control")
                # The overhead breakable starts the supplied delayed gate sequence.
                shoot_control(driver, capture, 130)
                await_open(driver, 132)
                checkpoint(driver, capture, report, "factory_gate_open")
                for point in ((370, 2460, 376), (425, 2469, 376), (461, 2510, 403), (480, 2576, 408)):
                    walk(driver, point, capture, combat=False, tolerance=20)
                if driver.observe()["pos"][2] > 440:
                    raise RuntimeError("Gate approach did not return to the lower passage")
                checkpoint(driver, capture, report, "factory_lower_approach")
            for point in ((504, 2656, 408), (504, 2748, 408), (555, 2748, 408)):
                walk(driver, point, capture, combat=True, tolerance=20)
            checkpoint(driver, capture, report, "factory_gate_passed")
        for index, point in enumerate(((787, 2765, 408), (969, 2701, 411),
                (1139, 2565, 481), (1260, 2526, 522), (1412, 2473, 568),
                (1562, 2480, 613), (1721, 2479, 660), (1911, 2463, 708),
                (2112, 2373, 744), (2208, 2178, 777), (2202, 2037, 792),
                (2072, 1976, 792), (1944, 1920, 792), (1888, 1768, 792), (1855, 1570, 792), (1794, 1441, 785))):
            if phase == "factory-yard-turn" and index < 11:
                continue
            walk(driver, point, capture, combat=True)
            if index in (6, 11):
                checkpoint(driver, capture, report, f"factory_yard_{index}")
        worker = next((row for row in actors(driver).values() if row["unique"] == "WRKRdick"), None)
        if worker is None:
            raise RuntimeError("Authored yard worker is missing")
        shoot_control(driver, capture, 113, 124)
        await_open(driver, 114)
        walk(driver, (1744, 1440, 792), capture, tolerance=20)
        resupply(driver, 122)
        checkpoint(driver, capture, report, "factory_yard_control")
        return {"yard_worker": worker, "interior": factory_interior(driver, capture, report)}
    except Exception as error:
        failure = {"error": str(error), "last_observed_state": driver._activity_sample}
        try:
            capture("factory-failure")
            failure.update(state=driver.observe(), actors=actors(driver))
        except Exception as unavailable:
            failure["observation_error"] = str(unavailable)
        (report / "factory-failure.json").write_text(json.dumps(failure, indent=2) + "\n")
        raise


def use_button(driver, identity, point):
    state = aim_at(driver, point)
    if sum((point[i] - state["pos"][i] - (22 if i == 2 else 0)) ** 2 for i in range(3)) > 96 ** 2:
        raise RuntimeError(f"Button {identity} is outside actual use reach")
    trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
    if int(re.search(r"dk3 ion aimtrace: [^\n]*?\btarget=(\d+)", trace)[1]) != identity:
        raise RuntimeError(f"Button {identity} use line is obstructed: {trace}")
    if identity not in movers(driver):
        raise RuntimeError(f"Button controller {identity} is missing")
    driver.issue("use")
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        if movers(driver)[identity]["state"] != "closed":
            return
    raise TimeoutError(f"Button {identity} never activated")


def factory_interior(driver, capture, report, phase="factory-interior"):
    for point in ((1794, 1441, 785), (1855, 1570, 792), (1888, 1768, 792),
                  (1944, 1920, 792), (2072, 1976, 792), (2202, 2037, 792),
                  (2215, 1900, 824), (2401, 1737, 806)):
        if phase != "factory-switch":
            walk(driver, point, capture, combat=True, tolerance=20)
    if phase != "factory-switch":
        # Operate the inset panel from in front of the console. Its button is
        # within use reach across the counter; walking to its Y enters solid art.
        walk(driver, (2398, 1698, 816), capture, tolerance=12)
    checkpoint(driver, capture, report, "factory_before_switch")
    use_button(driver, 216, (2446, 1632, 848))
    verify_monitor(driver, capture, report)
    # These are three real door controllers driven by separate delayed relays.
    for identity in (313, 214, 215):
        await_open(driver, identity)
    checkpoint(driver, capture, report, "factory_exit_unlocked")
    return factory_departure(driver, capture, report)


def factory_departure(driver, capture, report):
    # Supplied ground nodes stop at the two lifts. Boarding and vertical travel
    # must be demonstrated by ordinary movement and the authoritative player pose.
    # Ground nodes 123 (console) and 125 (platform approach) both connect through
    # node 122. Their apparent direct shortcut crosses the solid console divider.
    for point in ((2401, 1737, 806), (2215, 1900, 824), (2214, 1696, 849), (2206, 1560, 849),
                  (2208, 1478, 852), (2208, 1416, 852)):
        walk(driver, point, capture, combat=True, tolerance=16)
    if 219 not in movers(driver):
        raise RuntimeError("Factory platform controller 219 is missing")
    risen = driver.until(lambda s: s["health"] <= 0 or s["pos"][2] >= 960,
                         seconds=10, description="ordinary platform contact raises the player")
    if risen["health"] <= 0 or not (2100 < risen["pos"][0] < 2312 and 1328 < risen["pos"][1] < 1472):
        raise RuntimeError("Factory ascent did not leave a living player on the platform")
    checkpoint(driver, capture, report, "factory_platform_raised")
    # The authored connection crosses a low guard rail (top at player-origin
    # height 992). Use an ordinary jump before turning into the upper passage.
    for point in ((2177, 1394, 964), (2096, 1472, 992), (2032, 1496, 960), (1984, 1600, 960),
                  (1824, 1632, 984), (1728, 1660, 968)):
        walk(driver, point, capture, combat=True, tolerance=20)
    checkpoint(driver, capture, report, "factory_upper_lift")
    use_button(driver, 118, (1696, 1718, 990))
    lowered = driver.until(lambda s: s["health"] <= 0 or s["pos"][2] <= 690,
                           seconds=8, description="authored liftmaster control lowers the player")
    if lowered["health"] <= 0 or not (1648 < lowered["pos"][0] < 1808 and 1520 < lowered["pos"][1] < 1744):
        raise RuntimeError("Factory descent did not leave a living player on the lift")
    # Leave before its authored return. No wait, damage or puzzle timing changes.
    walk(driver, (1653, 1596, 680), capture, tolerance=20)
    checkpoint(driver, capture, report, "factory_lower_lift")
    for point in ((1592, 1384, 680), (1574, 1286, 664), (1511, 1232, 581),
                  (1748, 1202, 537), (1824, 981, 495), (1710, 973, 511),
                  (1783, 769, 472), (1645, 672, 472)):
        walk(driver, point, capture, combat=True, tolerance=24)
    checkpoint(driver, capture, report, "factory_before_authored_exit")
    return {"scope": "Platform ascent, upper passage, liftmaster descent and lower route to the exit.",
            "arrival": factory_exit(driver, capture, report)}


def factory_exit(driver, capture, report):
    aim_at(driver, (1520, 672, driver.observe()["pos"][2] + 22))
    driver.issue("+forward")
    try:
        driver.until(lambda s: s["map"] == "e1m2a",
                     seconds=45, description="ordinary contact with the authored e1m2a exit")
    finally:
        driver.issue("-forward")
        driver.until(lambda s: s["forward"] == 0, description="processed e1m2a arrival release")
    arrival = driver.until(lambda s: s["map"] == "e1m2a" and s["mode"] == "normal",
                           seconds=90, description="e1m2a arrival cinematic releases player control")
    if arrival["health"] <= 0 or arrival["skill"] != 3:
        raise RuntimeError("Factory exit did not retain a living normal-difficulty player")
    checkpoint(driver, capture, report, "e1m2a_authored_arrival")
    return {"scope": "Normal-input contact with the authored e1m2a exit and complete arrival cinematic.",
            "state": driver.observe()}


def pipe_jump(driver, capture, destination):
    state = driver.stop_forward()
    start = state["pos"]
    aim_at(driver, (destination[0], destination[1], start[2] + 22))
    driver.issue("-speed")
    driver.issue("+forward")
    try:
        state = driver.until(lambda s: s["forward"] == 127 and math.dist(s["pos"][:2], start[:2]) >= 6,
                             seconds=2, description="running takeoff on the pipe")
        launch_height = state["pos"][2]
        driver.issue("+moveup")
        try:
            driver.until(lambda s: s["up"] > 0 and s["pos"][2] > launch_height + 8,
                         seconds=2, description="actual running pipe jump")
        finally:
            driver.issue("-moveup")
        driver.until(lambda s: math.dist(s["pos"][:2], destination[:2]) < 32 and s["pos"][2] > destination[2] - 32,
                     seconds=3, description="airborne crossing reaches the upper pipe")
    finally:
        state = driver.stop_forward(settle_vertical=True)
    if state["pos"][2] < destination[2] - 32:
        capture("pipe-jump-failed")
        raise RuntimeError("Pipe jump landed below the authored upper route")


def verify_monitor(driver, capture, report):
    started = driver.until(lambda state: state["mode"] == "frozen", seconds=3,
                           description="authored monitor freezes the real player")
    monitor = world_rows(driver, "monitor").get(177)
    if monitor is None or int(monitor["viewer"]) == 0 or int(monitor["camera"]) != 211:
        raise RuntimeError("Factory monitor did not resolve its authored viewer and camera")
    driver.until(lambda state: state["now"] >= started["now"] + 2500 and state["mode"] == "frozen",
                 seconds=5, description="actual partial monitor playback before saving")
    before = world_rows(driver, "monitor")[177]
    remaining = int(before["until"]) - driver.observe()["now"]
    checkpoint(driver, capture, report, "factory_monitor_active")
    restored = driver.load("factory_monitor_active")
    after = world_rows(driver, "monitor")[177]
    if restored["mode"] != "frozen" or after["camera"] != before["camera"] or after["pos"] != before["pos"] or after["angles"] != before["angles"]:
        raise RuntimeError("Monitor restore lost its camera or frozen control")
    if not 0 < int(after["until"]) - restored["now"] <= remaining + 500:
        raise RuntimeError("Monitor duration restarted or expired across save/load")
    capture("factory-monitor-restored")
    finished = driver.until(lambda state: state["mode"] == "normal", seconds=10,
                            description="authored monitor releases player control")
    if int(world_rows(driver, "monitor")[177]["viewer"]) != 0:
        raise RuntimeError("Monitor retained its viewer after release")
    (report / "monitor-restoration.json").write_text(json.dumps({"before": before, "after": after,
        "remaining_before": remaining, "restored_player": restored, "released_player": finished}, indent=2) + "\n")
