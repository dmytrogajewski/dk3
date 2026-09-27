# SPDX-License-Identifier: GPL-2.0-or-later
"""Ordinary-input bridge route; authored waypoints, no placement or grants."""
import json
import math
import re
import shutil
import time

from runtime_opening_route import actors, walk
from runtime_probe import wait


def world_rows(driver, kind):
    text = driver.diagnostics("dk3_runtime_world", "dk3 zig world states complete")
    rows = {}
    for line in text.splitlines():
        if f"dk3 zig {kind}:" not in line:
            continue
        row = dict(re.findall(r"(\w+)=([^ ]+)", line))
        for key in ("pos", "center"):
            if key in row:
                row[key] = tuple(map(float, row[key].split(",")))
        rows[int(row["id"])] = row
    return rows


def aim_at(driver, point):
    state = driver.observe()
    delta = [point[i] - state["pos"][i] for i in range(3)]
    delta[2] -= 22
    return driver.aim(math.degrees(math.atan2(delta[1], delta[0])),
                      -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))


def resupply(driver, identity):
    uses = []
    while driver.observe()["health"] < 100:
        tree = world_rows(driver, "tree")[identity]
        if int(tree["fruit"]) == 0:
            break
        aim_at(driver, tree["pos"])
        driver.until(lambda s: s["now"] >= int(tree["ready"]), description="health tree ready for use")
        before_health = driver.observe()["health"]
        before = len(driver.text())
        driver.issue("use")
        text = wait(driver.process, driver.log, lambda text: f"dk3 tree: id={identity} " in text[before:], 3)[before:]
        match = re.search(rf"dk3 tree: id={identity} fruit=(\d+) player=\d+ health=(\d+)", text)
        if not match or int(match[1]) != int(tree["fruit"]) - 1:
            raise RuntimeError("Tree use did not consume the observed fruit")
        after = int(match[2])
        if after != min(100, before_health + 10):
            raise RuntimeError("Concurrent damage or incorrect heal invalidates the resupply sample")
        uses.append({"before": before_health, "after": after, "fruit": int(match[1])})
    return uses


def checkpoint(driver, capture, report, name):
    save = driver.save(name)
    shutil.copy2(save, report / save.name)
    capture(name)


def shoot_control(driver, capture, identity, removed_actor):
    target = world_rows(driver, "destructible")[identity]
    if target["broken"] != "0" or int(target["health"]) <= 0:
        raise RuntimeError("Control setup is already broken")
    for _ in range(8):
        driver.ready(2)
        aim_at(driver, target["center"])
        trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
        match = re.search(r"target=(\d+)", trace)
        if not match or int(match[1]) != identity:
            capture("control-obstructed")
            raise RuntimeError(f"Control {identity} is not under the crosshair: {trace}")
        previous = int(target["health"])
        driver.fire()
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            target = world_rows(driver, "destructible")[identity]
            if int(target["health"]) < previous:
                break
        else:
            raise RuntimeError(f"No confirmed damage to authored control {identity}")
        if target["broken"] == "1":
            assert removed_actor not in actors(driver), "Control broke but linked turret remained"
            capture(f"control-{identity}-destroyed")
            return
    raise RuntimeError(f"Control {identity} did not break within the observed shot budget")


def bridge_route(driver, capture, report, phase="bridge-arrival"):
    state = driver.ready(2)
    if state["map"] != "e1m1b" or state["skill"] != 3 or state["health"] <= 0:
        raise RuntimeError(f"Invalid ordinary bridge checkpoint: {state}")
    try:
        # Supplied ground-node route around the river; player movement still has
        # to negotiate every ledge and collision in the running authored map.
        for index, point in enumerate(((-445, -1430, 536), (-302, -1314, 581),
                (-232, -1176, 624), (-232, -968, 648), (-432, -880, 664),
                (-660, -810, 664), (-797, -627, 664), (-944, -616, 637),
                (-1158, -624, 572), (-1328, -688, 520), (-1342, -858, 497),
                (-1406, -914, 474), (-1510, -914, 424), (-1640, -904, 408),
                (-1768, -888, 411), (-1904, -808, 408), (-2040, -680, 415),
                (-2072, -520, 470), (-2080, -464, 496))):
            if index < {"bridge-arrival": 0, "bridge-control": 2, "bridge-river": 5, "bridge-ford": 11}[phase]:
                continue
            walk(driver, point, capture, combat=True)
            if index == 5:
                before_health = driver.observe()["health"]
                walk(driver, (-720, -580, 688), capture, combat=True)
                state = driver.observe()
                if state["health"] < min(100, before_health + 25):
                    raise RuntimeError("Health pickup was not confirmed; inspect concurrent combat and touch")
                checkpoint(driver, capture, report, "bridge_health_pickup")
            if index == 2:
                checkpoint(driver, capture, report, "bridge_first_control")
                shoot_control(driver, capture, 91, 92)
                for supply_point in ((-119, -1044, 646), (-187, -881, 664), (40, -848, 664), (147, -690, 664)):
                    walk(driver, supply_point, capture, combat=True)
                resupply(driver, 139)
                checkpoint(driver, capture, report, "bridge_east_tree")
                before_ammo = driver.observe()["ammo"]
                walk(driver, (-112, -624, 664), capture, combat=True)
                if driver.observe()["ammo"] <= before_ammo:
                    raise RuntimeError("First turret room ammunition pickup was not confirmed")
                for supply_point in ((-192, -704, 640), (-350, -777, 633), (-432, -880, 664)):
                    walk(driver, supply_point, capture, combat=True)
                checkpoint(driver, capture, report, "bridge_east_supplies")
            if index in (4, 10, 17):
                checkpoint(driver, capture, report, f"bridge_river_{index}")
        uses = resupply(driver, 110)
        checkpoint(driver, capture, report, "bridge_tree")
        before_ammo = driver.observe()["ammo"]
        for point in ((-2253, -612, 489), (-2341, -419, 526), (-2272, -328, 496), (-2224, -328, 496)):
            walk(driver, point, capture, combat=True)
        state = driver.observe()
        if state["ammo"] <= before_ammo:
            raise RuntimeError("Ordinary route did not collect authored Ion ammunition")
        checkpoint(driver, capture, report, "bridge_supplies")
        return {"scope": "Ordinary bridge arrival through river approach, health-tree use and ammo pickup. Bridge encounter and later traversal remain unverified.", "health_tree": uses, "state": state}
    except Exception as error:
        capture("bridge-failure")
        (report / "bridge-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise
