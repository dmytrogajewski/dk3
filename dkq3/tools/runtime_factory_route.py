# SPDX-License-Identifier: GPL-2.0-or-later
"""Ordinary-input e1m1c progression, using its authored gates and outside path."""
import json
import re
import time

from runtime_bridge_route import aim_at, checkpoint, resupply, shoot_control
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
        if phase != "factory-yard":
            # The switch is on the upper pipe, not the lamp above the lower
            # locked doorway. Climb the supplied sloping pipe approach first.
            for point in ((461, 2510, 403), (425, 2469, 376), (406, 2256, 408),
                          (406, 2184, 444), (406, 2144, 464), (480, 2144, 456),
                          (530, 2144, 528), (530, 2281, 529), (424, 2424, 584),
                          (488, 2568, 664)):
                if point == (406, 2144, 464):
                    driver.issue("+movedown")
                    driver.until(lambda state: state["up"] < 0, description="processed crouch on the low pipe")
                walk(driver, point, capture, combat=False, tolerance=8, jump=point == (530, 2144, 528))
                if point == (480, 2144, 456):
                    driver.issue("-movedown")
                    driver.until(lambda state: state["up"] == 0, description="processed crouch release")
                capture(f"pipe-{point[0]}-{point[1]}")
            if driver.observe()["pos"][2] < 640:
                raise RuntimeError("Gate firing position did not reach the upper pipe")
            checkpoint(driver, capture, report, "factory_upper_control")
            # The overhead breakable starts the supplied delayed gate sequence.
            shoot_control(driver, capture, 130)
            await_open(driver, 132)
            for point in ((480, 2656, 664), (555, 2748, 408)):
                walk(driver, point, capture, combat=True, tolerance=20)
            for point in ((504, 2656, 408), (408, 2736, 424), (408, 2768, 424), (555, 2748, 408)):
                walk(driver, point, capture, combat=True, tolerance=20)
            checkpoint(driver, capture, report, "factory_gate_passed")
        for index, point in enumerate(((787, 2765, 408), (969, 2701, 411),
                (1139, 2565, 481), (1260, 2526, 522), (1412, 2473, 568),
                (1562, 2480, 613), (1721, 2479, 660), (1911, 2463, 708),
                (2112, 2373, 744), (2208, 2178, 777), (2202, 2037, 792),
                (2215, 1900, 824), (2030, 1789, 800), (1992, 1624, 816), (2056, 1472, 800))):
            walk(driver, point, capture, combat=True)
            if index in (6, 11):
                checkpoint(driver, capture, report, f"factory_yard_{index}")
        worker = next((row for row in actors(driver).values() if row["unique"] == "WRKRdick"), None)
        if worker is None:
            raise RuntimeError("Authored yard worker is missing")
        shoot_control(driver, capture, 113, 124)
        await_open(driver, 114)
        checkpoint(driver, capture, report, "factory_yard_control")
        return {"scope": "Ordinary e1m1c outer gate and yard turret control only; interior/lift/e1m2a exit remain unverified.",
                "state": driver.observe(), "worker": worker}
    except Exception as error:
        capture("factory-failure")
        (report / "factory-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(),
                                                               "actors": actors(driver)}, indent=2) + "\n")
        raise
