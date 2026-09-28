# SPDX-License-Identifier: GPL-2.0-or-later
"""Ordinary-input bridge route; authored waypoints, no placement or grants."""
import json
import math
import re
import shutil
import time

from runtime_opening_route import actors, fight, walk
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


def authored_id(driver, local_id):
    """Resolve an authored map index using stationary exits in the active world.

    Birth namespaces survive restoration and need not follow admission order.
    Never infer this from the player or an actor that may have crossed a seam.
    """
    exits = world_rows(driver, "exit")
    namespaces = {identity & 0xff000000 for identity in exits}
    if len(namespaces) != 1 or not 0 < local_id <= 0xffffff:
        raise RuntimeError(f"Cannot resolve authored index {local_id} from active exits: {exits}")
    return next(iter(namespaces)) | local_id


def items(driver):
    before = len(driver.text())
    driver.issue("dk3_runtime_items")
    driver.observe()
    rows = {}
    for line in driver.text()[before:].splitlines():
        if "zig item id=" in line:
            row = dict(re.findall(r"(\w+)=([^ ]*)", line))
            row["pos"] = tuple(map(float, row["pos"].split(",")))
            rows[int(row["id"])] = row
    driver.inputs.append({"items": rows})
    return rows


def collect_boss_drop(driver, capture, report):
    drops = [(identity, row) for identity, row in items(driver).items() if row["class"] == "item_megashield"]
    if len(drops) != 1:
        raise RuntimeError("Boss death did not leave its single authored Megashield")
    identity, drop = drops[0]
    if drop["visible"] != "1":
        if driver.observe()["armor"] <= 0:
            raise RuntimeError("Consumed boss drop without observed player armor")
        return
    before = driver.observe()["armor"]
    if drop["ground"] == "null" and drop["pos"][2] > driver.observe()["pos"][2] + 32:
        # The real reward is still falling. Move under it on the current bank;
        # its airborne model height is not a walkable player destination.
        walk(driver, (*drop["pos"][:2], driver.observe()["pos"][2]), capture, tolerance=16)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            state = driver.observe()
            drop = items(driver)[identity]
            if state["health"] <= 0:
                raise RuntimeError("Player died approaching the falling boss reward")
            if state["armor"] > before:
                if drop["visible"] != "0":
                    raise RuntimeError("Armor increase did not consume the observed boss reward")
                checkpoint(driver, capture, report, "bridge_boss_reward")
                return
            if drop["ground"] != "null":
                break
        else:
            raise TimeoutError("Boss reward neither landed nor contacted the player")
    if driver.observe()["pos"][2] > 900 and drop["pos"][2] < 800:
        cross_drop(driver, (drop["pos"][0], drop["pos"][1], drop["pos"][2] + 24))
    walk(driver, (drop["pos"][0], drop["pos"][1], drop["pos"][2] + 24), capture, tolerance=16)
    driver.issue("+movedown")
    try:
        state = driver.until(lambda s: s["health"] <= 0 or s["armor"] > before, seconds=6,
                             description="ordinary touch of the boss Megashield")
        if state["health"] <= 0 or items(driver)[identity]["visible"] != "0":
            raise RuntimeError("Boss drop contact did not leave a living armored player")
    finally:
        driver.issue("-movedown")
        driver.until(lambda s: s["up"] >= 0, description="processed dive release")
    checkpoint(driver, capture, report, "bridge_boss_reward")


def aim_at(driver, point):
    state = driver.observe()
    delta = [point[i] - state["pos"][i] for i in range(3)]
    delta[2] -= 22
    return driver.aim(math.degrees(math.atan2(delta[1], delta[0])),
                      -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))


def resupply(driver, identity):
    identity = authored_id(driver, identity)
    uses = []
    while driver.observe()["health"] < 100:
        tree = world_rows(driver, "tree")[identity]
        if int(tree["fruit"]) == 0:
            break
        state = aim_at(driver, tree["pos"])
        eye = (state["pos"][0], state["pos"][1], state["pos"][2] + 22)
        if math.dist(eye, tree["pos"]) > 96:
            raise RuntimeError(f"Tree {identity} is outside the observed use reach: {tree['pos']}")
        trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
        if int(re.search(r"dk3 ion aimtrace: [^\n]*?\btarget=(\d+)", trace)[1]) != identity:
            raise RuntimeError(f"Tree {identity} use line is obstructed: {trace}")
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


def clear_close_attackers(driver, capture):
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        state = driver.observe()
        nearby = [row for row in actors(driver).values()
                  if row["class"] == "monster_slaughterskeet" and row["health"] > 0
                  and row["threat"] != "0" and math.dist(row["pos"], state["pos"]) < 220]
        if not nearby:
            return
        if state["health"] < 25:
            raise RuntimeError("Insufficient health to stop at the control with active close attackers")
        fight(driver, capture, "e1m1b")
    raise TimeoutError("Close skeets remain at the authored control; inspect the combat driver")


def shoot_control(driver, capture, identity, removed_actor=None):
    identity = authored_id(driver, identity)
    if removed_actor is not None:
        removed_actor = (identity & 0xff000000) | removed_actor
        assert removed_actor in actors(driver), "Linked turret setup is missing"
    target = world_rows(driver, "destructible")[identity]
    if target["broken"] != "0" or int(target["health"]) <= 0:
        raise RuntimeError("Control setup is already broken")
    for _ in range(8):
        driver.ready(2)
        aim_at(driver, target["center"])
        trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
        match = re.search(r"dk3 ion aimtrace: [^\n]*?\btarget=(\d+)", trace)
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
            if removed_actor is not None:
                assert removed_actor not in actors(driver), "Control broke but linked turret remained"
            capture(f"control-{identity}-destroyed")
            return
    raise RuntimeError(f"Control {identity} did not break within the observed shot budget")


def clear_ford(driver, capture, report, identities=(387, 419), label="bridge"):
    namespace = authored_id(driver, 1) & 0xff000000
    identities = tuple(namespace | identity for identity in identities)
    if driver.observe()["water"] != 0:
        raise RuntimeError("Ford firing position is not on dry land")
    checkpoint(driver, capture, report, f"{label}_ford_bank")
    contacts = []
    observed = actors(driver)
    position = driver.observe()["pos"]
    for identity in sorted(identities, key=lambda identity: math.dist(observed[identity]["pos"], position)):
        row = actors(driver)[identity]
        if row["health"] > 0 and math.dist(row["pos"], driver.observe()["pos"]) < 200:
            for _ in range(3):
                previous = actors(driver)[identity]["health"]
                if previous <= 0:
                    break
                contacted = fight(driver, capture, driver.observe()["map"], target_id=identity)
                after = actors(driver)[identity]
                contacts.append({"target": identity, "before": previous, "after": after["health"], "water": after["crox_water"], "tracking": True})
                if not contacted:
                    raise RuntimeError(f"Close Crox {identity} received no tracked fire; inspect its lane")
            if actors(driver)[identity]["health"] > 0:
                raise RuntimeError(f"Close Crox {identity} survived the tracked engagement")
            checkpoint(driver, capture, report, f"{label}_crox_{identity}_cleared")
            continue
        for shot in range(18):
            row = actors(driver)[identity]
            if row["health"] <= 0:
                break
            state = driver.ready(2)
            if state["ammo"] <= 0 or state["health"] <= 0:
                raise RuntimeError("Ford engagement exhausted ordinary supplies")
            deadline = time.monotonic() + 6
            while math.hypot(*row["velocity"][:2]) > 10 or (row["ground"] == "2047" and abs(row["velocity"][2]) > 10):
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"Crox {identity} did not present a stable shot from the bank")
                row = actors(driver)[identity]
            # Supplied Crox hull ends eight units above its origin. Aim at the
            # visible upper body so the water-surface blast remains near it.
            aim_at(driver, (row["pos"][0], row["pos"][1], row["pos"][2] + 7))
            trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
            match = re.search(r"dk3 ion aimtrace: [^\n]*?\btarget=(\d+)", trace)
            if not match or int(match[1]) != identity:
                raise RuntimeError(f"Crox {identity} firing lane changed before the shot: {trace}")
            previous = row
            driver.fire()
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                row = actors(driver)[identity]
                if row["health"] < previous["health"]:
                    break
            else:
                capture(f"ford-no-contact-{identity}-{shot}")
                raise RuntimeError(f"No observed Ion damage to Crox {identity}; inspect water contact")
            contacts.append({"target": identity, "before": previous["health"], "after": row["health"], "water": previous["crox_water"]})
        if actors(driver)[identity]["health"] > 0:
            raise RuntimeError(f"Crox {identity} survived the ford engagement budget")
        checkpoint(driver, capture, report, f"{label}_crox_{identity}_cleared")
    driver.inputs.append({"ford_contacts": contacts})


def pond_ammunition(driver, capture, report):
    before = driver.select(2)["ammo"]
    for point in ((-624, -648, 664), (-398, -649, 633), (-192, -704, 640), (-112, -624, 640)):
        walk(driver, point, capture, combat=True, tolerance=20)
    if driver.select(2)["ammo"] <= before:
        raise RuntimeError("First turret pond ammunition was not collected")
    checkpoint(driver, capture, report, "bridge_pond_ammo")
    for point in ((-192, -704, 640), (-398, -649, 633), (-624, -648, 664), (-720, -580, 664)):
        walk(driver, point, capture, combat=True)


def bridge_route(driver, capture, report, phase="bridge-arrival"):
    state = driver.select(2)
    if state["map"] != "e1m1b" or state["skill"] != 3 or state["health"] <= 0:
        raise RuntimeError(f"Invalid ordinary bridge checkpoint: {state}")
    try:
        if phase == "bridge-climb":
            clear_ford(driver, capture, report, identities=(425,))
            return bridge_climb(driver, capture, report, start_index=5)
        if phase == "bridge-supplies":
            return bridge_span(driver, capture, report)
        if phase == "bridge-crossing":
            return bridge_crossing(driver, capture, report)
        if phase == "bridge-cleared":
            return bridge_exit(driver, capture, report)
        if phase == "bridge-boss":
            return bridge_battle(driver, capture, report)
        if phase == "bridge-health":
            pond_ammunition(driver, capture, report)
        # Supplied ground-node route around the river; player movement still has
        # to negotiate every ledge and collision in the running authored map.
        for index, point in enumerate(((-445, -1430, 536), (-302, -1314, 581),
                (-232, -1176, 624), (-232, -968, 648), (-432, -880, 664),
                (-660, -810, 664), (-797, -627, 664), (-944, -616, 637),
                (-1158, -624, 572), (-1328, -688, 520), (-1342, -858, 497),
                (-1406, -914, 474), (-1510, -914, 424), (-1640, -904, 408),
                (-1768, -888, 411), (-1904, -808, 408), (-2040, -680, 415),
                (-2072, -520, 470), (-2080, -464, 496))):
            if index < {"bridge-arrival": 0, "bridge-control": 2, "bridge-river": 5, "bridge-health": 6, "bridge-ford": 11}[phase]:
                continue
            walk(driver, point, capture, combat=True)
            if index == 11:
                clear_ford(driver, capture, report)
            if index == 5:
                before_health = driver.observe()["health"]
                walk(driver, (-720, -580, 664), capture, combat=True, tolerance=20)
                state = driver.observe()
                if state["health"] < min(100, before_health + 25):
                    raise RuntimeError("Health pickup was not confirmed; inspect concurrent combat and touch")
                checkpoint(driver, capture, report, "bridge_health_pickup")
                pond_ammunition(driver, capture, report)
            if index == 2:
                clear_close_attackers(driver, capture)
                checkpoint(driver, capture, report, "bridge_first_control")
                shoot_control(driver, capture, 91, 92)
            if index in (4, 10, 17):
                checkpoint(driver, capture, report, f"bridge_river_{index}")
        uses = resupply(driver, 110)
        checkpoint(driver, capture, report, "bridge_tree")
        before_ammo = driver.select(2)["ammo"]
        for point in ((-2253, -612, 489), (-2341, -419, 526), (-2272, -328, 496), (-2224, -328, 496)):
            walk(driver, point, capture, combat=True, tolerance=20)
        state = driver.select(2)
        if state["ammo"] <= before_ammo:
            raise RuntimeError("Ordinary route did not collect authored Ion ammunition")
        checkpoint(driver, capture, report, "bridge_supplies")
        return {"scope": "Ordinary bridge arrival through river approach, health-tree use and ammo pickup.", "health_tree": uses, "state": state, "span": bridge_span(driver, capture, report)}
    except Exception as error:
        capture("bridge-failure")
        (report / "bridge-failure.json").write_text(json.dumps({"error": str(error), "state": driver.observe(), "actors": actors(driver)}, indent=2) + "\n")
        raise


def bridge_span(driver, capture, report):
    control_id = authored_id(driver, 86)
    control_visible = False
    for point in ((-2240, -256, 496), (-2184, -92, 479), (-2288, 48, 472), (-2411, 148, 472)):
        walk(driver, point, capture, combat=True)
        control = world_rows(driver, "destructible")[control_id]
        aim_at(driver, control["center"])
        trace = driver.diagnostics("dk3_runtime_ion_aim", "dk3 ion aimtrace:")
        match = re.search(r"dk3 ion aimtrace: [^\n]*?\btarget=(\d+)", trace)
        if match and int(match[1]) == control_id:
            control_visible = True
            shoot_control(driver, capture, 86, 85)
            checkpoint(driver, capture, report, "bridge_west_control")
            break
    if not control_visible:
        raise RuntimeError("West turret control has no confirmed firing lane from the approach")
    return bridge_climb(driver, capture, report)


def bridge_climb(driver, capture, report, start_index=0):
    for index, point in enumerate(((-2487, 360, 472), (-2640, 463, 490), (-2687, 607, 532),
            (-2679, 743, 528), (-2608, 944, 528), (-2384, 864, 472), (-2272, 836, 472),
            (-2120, 784, 472), (-1972, 712, 472), (-1973, 581, 471), (-1969, 396, 517),
            (-1973, 294, 557), (-1953, 198, 604), (-1834, 5, 705), (-1800, -84, 774),
            (-1775, -174, 823), (-1659, -218, 824), (-1591, -51, 863), (-1568, 159, 899),
            (-1705, 306, 961), (-1798, 463, 980), (-1751, 665, 986))):
        if index < start_index:
            continue
        walk(driver, point, capture, combat=True)
        if index == 4:
            # This dry bank overlooks the second pool. The previous driver
            # ignored its authored Crox and entered the water within bite range.
            clear_ford(driver, capture, report, identities=(425,))
        if index in (4, 12, 17):
            checkpoint(driver, capture, report, f"bridge_climb_{index}")
    for point in ((-1648, 816, 984), (-1616, 752, 984)):
        walk(driver, point, capture, combat=True, tolerance=20)
    checkpoint(driver, capture, report, "bridge_before_span")
    return bridge_crossing(driver, capture, report)


def bridge_crossing(driver, capture, report):
    walk(driver, (-1548, 800, 984), capture, tolerance=16)
    clear_ford(driver, capture, report, identities=(431,))
    for point in ((-1563, 622, 988), (-1420, 640, 984), (-1280, 640, 984),
                  (-1120, 640, 984), (-1010, 640, 984), (-930, 640, 984)):
        walk(driver, point, capture, combat=True)
    namespace = authored_id(driver, 1) & 0xff000000
    sequence = world_rows(driver, "sequence")[namespace | 70]
    if int(sequence["start"]) <= 0 or int(sequence["cursor"].split("/")[0]) == 0:
        raise RuntimeError("Ordinary bridge crossing did not activate its authored timeline")
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        state = driver.observe()
        if state["health"] <= 0:
            raise RuntimeError("Player died during bridge destruction and actor entrance")
        rows = actors(driver)
        boss = next((row for row in rows.values() if row["unique"] == "tskeet"), None)
        pieces = world_rows(driver, "destructible")
        if boss and all(pieces[namespace | identity]["broken"] == "1" for identity in (80, 81, 82)):
            break
        # Engage the visible wave during its authored entrance instead of
        # standing idle until all ten actors and the boss have arrived.
        fight(driver, capture, "e1m1b")
    else:
        raise RuntimeError("Bridge destruction or authored boss creation did not complete")
    checkpoint(driver, capture, report, "bridge_boss_arrival")
    return {"scope": "Ordinary west turret control, climb and bridge timeline activation.",
            "arrival": driver.observe(), "battle": bridge_battle(driver, capture, report)}


def bridge_battle(driver, capture, report):
    driver.select(2)
    state = driver.observe()
    from runtime_arena_combat import battle
    contacts, waves = battle(driver, capture)
    collect_boss_drop(driver, capture, report)
    checkpoint(driver, capture, report, "bridge_boss_defeated")
    driver.load("bridge_boss_defeated")
    restored = next(row for row in actors(driver).values() if row["unique"] == "tskeet")
    if restored["health"] > 0:
        raise RuntimeError("Boss death did not survive save/load")
    from runtime_campaign_restoration import death_reload
    death_reload(driver, capture, report)
    return {"contacts": contacts, "waves": sorted(waves), "exit": bridge_exit(driver, capture, report)}


def bridge_exit(driver, capture, report):
    restored = next(row for row in actors(driver).values() if row["unique"] == "tskeet")
    if restored["health"] > 0:
        raise RuntimeError("Bridge exit requires the defeated authored boss")
    collect_boss_drop(driver, capture, report)
    if driver.observe()["pos"][2] > 900:
        cross_drop(driver, (-1283, 908, 520))
    cross_drop(driver, (-1322, 1242, 520))
    # The death target opens the authored north door. Walking through its actual
    # collision and touching the exit establishes more than a dispatched event.
    for point in ((-1333, 1347, 509),
                  (-1331, 1415, 543), (-1314, 1510, 591), (-1314, 1578, 625),
                  (-1270, 1700, 661), (-1047, 1676, 664), (-900, 1600, 664)):
        walk(driver, point, capture, combat=True)
        if point == (-1270, 1700, 661) and driver.observe()["health"] < 100:
            # Supplied ground nodes 49 -> 70 -> 4 lead to the north health
            # tree after the boss opens this gate. Resupply before entering the
            # next encounter instead of repeatedly replaying a four-health save.
            bank = ((-1432, 1696, 664), (-1616, 1712, 664), (-1668, 1664, 664))
            for supply in bank:
                walk(driver, supply, capture, combat=False, tolerance=16)
            uses = resupply(driver, 106)
            if not uses or driver.observe()["health"] <= 0:
                raise RuntimeError("North exit tree did not provide actual living resupply")
            driver.inputs.append({"bridge_exit_tree": 106, "uses": uses})
            checkpoint(driver, capture, report, "bridge_exit_resupplied")
            for supply in (*reversed(bank[:-1]), point):
                walk(driver, supply, capture, combat=True)
    from runtime_campaign_restoration import bridge_progress, travel, visited_bridge
    progress = bridge_progress(driver)
    checkpoint(driver, capture, report, "bridge_before_exit")
    aim_at(driver, (-760, 1600, 686))
    arrival = travel(driver, "e1m1c")
    checkpoint(driver, capture, report, "factory_arrival")
    visit = visited_bridge(driver, capture, report, progress)
    from runtime_factory_route import factory_route
    return {"visited": visit, "scope": "Bridge boss damage/death restoration and ordinary traversal through its death-opened door into e1m1c.",
            "state": arrival, "factory": factory_route(driver, capture, report)}


def cross_drop(driver, point):
    """Pass a waypoint during a fall/swim without waiting for air friction."""
    deadline = time.monotonic() + 10
    heading = None
    ascending = False
    try:
        while time.monotonic() < deadline:
            state = driver.observe()
            if state["health"] <= 0 or state["map"] != "e1m1b":
                raise RuntimeError("Arena descent interrupted")
            if math.dist(state["pos"][:2], point[:2]) < 64:
                return state
            yaw = math.degrees(math.atan2(point[1] - state["pos"][1], point[0] - state["pos"][0]))
            if heading is None or abs((yaw - heading + 180) % 360 - 180) > 10:
                driver.aim(yaw, 0)
                heading = yaw
            upward = state["water"] >= 2 and state["pos"][2] < point[2]
            if upward != ascending:
                driver.issue("+moveup" if upward else "-moveup")
                ascending = upward
            if state["forward"] == 0:
                driver.issue("+forward")
                driver.until(lambda s: s["forward"] > 0, description="processed descent steering")
        raise TimeoutError(f"Did not pass arena descent waypoint {point}")
    finally:
        driver.issue("-forward")
        driver.issue("-moveup")
        driver.until(lambda s: s["forward"] == 0 and s["up"] == 0, description="processed descent input release")
