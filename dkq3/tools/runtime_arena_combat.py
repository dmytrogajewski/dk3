# SPDX-License-Identifier: GPL-2.0-or-later
"""Normal keyboard movement and held Ion fire on the authored bridge arena bank."""
import math
import re
import time

from runtime_opening_route import actors


def spend_earned_power(driver):
    def character():
        text = driver.diagnostics("dk3_runtime_character", "zig character ")
        return {key: int(value) for key, value in re.findall(r"(level|points)=(\d+)", text)}
    before = character()
    current = before
    for _ in range(min(5, before["points"])):
        driver.issue("attribute power")
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            after = character()
            if after["points"] == current["points"] - 1 and after["level"] == current["level"]:
                current = after
                break
        else:
            raise RuntimeError("Earned power allocation did not consume exactly one existing point")
    driver.inputs.append({"earned_power": {"before": before, "after": current}})


def incoming(driver, floor):
    text = driver.diagnostics("dk3_runtime_projectiles", "dk3 zig projectile states complete")
    result, active = [], 0
    for line in text.splitlines():
        if "dk3 thunder spray state:" not in line:
            continue
        active += 1
        fields = dict(re.findall(r"(\w+)=([^ ]+)", line))
        position = tuple(map(float, fields["position"].split(",")))
        velocity = tuple(map(float, fields["velocity"].split(",")))
        if velocity[2] >= 0:
            continue
        eta = (floor - position[2]) / velocity[2]
        if 0 <= eta <= 3:
            result.append((eta, tuple(position[i] + velocity[i] * eta for i in range(2))))
    return result, active


def evade(position, candidates, threats):
    """Choose reachable separation from observed descending splash projectiles."""
    def score(destination):
        distance = math.dist(position[:2], destination)
        values = []
        for eta, impact in threats:
            fraction = min(1, max(0, eta - 0.15) * 260 / max(1, distance))
            arrival = tuple(position[i] + (destination[i] - position[i]) * fraction for i in range(2))
            values.append(math.dist(arrival, impact))
        return min(values), -distance
    return max(candidates, key=score)


def battle(driver, capture):
    spend_earned_power(driver)
    held = set()
    waypoint = 0
    deadline = time.monotonic() + 90
    initial = driver.select(2)
    # Stay on the open east plateau. The former northwest corner sent Hiro
    # against the cliff at (-911, 460), where the boss has no firing line.
    # The east barrier is an authored 5000-damage brush at x=-623..-619.
    # Leave steering/knockback clearance from it as well as the west cliff.
    patrol = ((-720, 520), (-720, 800), (-860, 800), (-860, 520)) if initial["pos"][2] > 900 else ((-1510, 730), (-1510, 850))
    contacts, waves = [], set()
    previous_health = None
    observed_shots = False
    last_contact = time.monotonic()
    next_threats, threats, active_sprays = 0, [], None
    observed_health = {}

    def buttons(wanted):
        nonlocal held
        for key in sorted(held - wanted):
            driver.issue("-" + key)
        for key in sorted(wanted - held):
            driver.issue("+" + key)
        held = wanted

    try:
        while time.monotonic() < deadline:
            state = driver.observe()
            if state["health"] <= 0 or state["map"] != "e1m1b":
                raise RuntimeError("Arena battle ended in death or an unexpected transition")
            observed_shots |= state["event"] != initial["event"] and state["fire"] != initial["fire"]
            rows = actors(driver)
            for identity, row in rows.items():
                if identity in observed_health and row["health"] < observed_health[identity]:
                    last_contact = time.monotonic()
                observed_health[identity] = row["health"]
            bosses = [(identity, row) for identity, row in rows.items() if row["unique"] == "tskeet"]
            if len(bosses) != 1:
                raise RuntimeError("Arena battle requires exactly one authored Thunderskeet")
            identity, boss = bosses[0]
            waves.update(row["unique"].lower() for row in rows.values()
                         if row["unique"].lower() in {f"skeet{i}{side}" for i in range(1, 6) for side in "ab"})
            if previous_health is not None and boss["health"] < previous_health:
                contacts.append({"before": previous_health, "after": boss["health"], "fire": state["fire"]})
                last_contact = time.monotonic()
            previous_health = boss["health"]
            if boss["health"] <= 0:
                if not observed_shots or not contacts or len(waves) != 10:
                    raise RuntimeError("Boss death lacks observed fire/contact or all ten authored wave actors")
                # The authored shield is available now. Return for its actual
                # pickup instead of patrolling unarmored under lingering spray.
                return contacts, waves
            if state["ammo"] <= 0:
                raise RuntimeError("Arena combat exhausted the collected Ion ammunition")
            if boss["health"] > 0 and time.monotonic() - last_contact > 12:
                raise RuntimeError("No boss contact during the bounded firing window; inspect the actual sight line")
            target = boss
            survivors = [row for row in rows.values() if row["class"] == "monster_slaughterskeet"
                         and row["health"] > 0 and row["sight"] == "1" and row["threat"] != "0"]
            if survivors:
                closest = min(survivors, key=lambda row: math.dist(row["pos"], state["pos"]))
                if boss["health"] <= 0 or math.dist(closest["pos"], state["pos"]) < 200:
                    target = closest
            # Submit view and movement together before waiting for another state.
            # Waiting for aim acknowledgement with the old keys still held turned
            # a short bank patrol into large sideways excursions.
            flight = min(0.7, math.dist(target["aim"], state["pos"]) / 1800 + 0.08)
            delta = [target["aim"][i] + target["velocity"][i] * flight - state["pos"][i] for i in range(3)]
            delta[2] -= 22
            aim_yaw = math.degrees(math.atan2(delta[1], delta[0]))
            pitch = max(-87.890625, min(87.890625, -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2])))))
            destination = patrol[waypoint]
            if math.dist(state["pos"][:2], destination) < 40:
                waypoint = (waypoint + 1) % len(patrol)
                destination = patrol[waypoint]
            if state["cmd"] >= next_threats:
                threats, active_sprays = incoming(driver, 960 if initial["pos"][2] > 900 else 512)
                next_threats = state["cmd"] + 300
            if threats:
                destination = evade(state["pos"], patrol, threats)
                driver.inputs.append({"arena_dodge": {"threats": threats, "destination": destination}})
            dx, dy = destination[0] - state["pos"][0], destination[1] - state["pos"][1]
            length = max(1, math.hypot(dx, dy))
            yaw = math.radians(aim_yaw)
            forward = (dx * math.cos(yaw) + dy * math.sin(yaw)) / length
            right = (dx * math.sin(yaw) - dy * math.cos(yaw)) / length
            wanted = {"speed"} if length < 90 and not threats else set()
            if abs(forward) > 0.38:
                wanted.add("forward" if forward > 0 else "back")
            if abs(right) > 0.38:
                wanted.add("moveright" if right > 0 else "moveleft")
            if state["water"] > 0:
                wanted.add("moveup")
            if state["water"] < 2 and target["health"] > 0 and target["sight"] == "1":
                wanted.add("attack")
            driver.issue(f"dk3_look {aim_yaw} {pitch}")
            buttons(wanted)
            driver.inputs.append({"arena_track": target["id"], "boss_health": boss["health"],
                                  "movement": sorted(wanted), "position": state["pos"]})
        raise TimeoutError("Boss survived the bounded moving-fire encounter")
    finally:
        buttons(set())
        driver.until(lambda s: not s["buttons"] & 1 and s["forward"] == 0 and s["right"] == 0 and s["up"] == 0,
                     description="processed arena input release")
        driver.inputs.append({"arena_contacts": contacts, "actual_fire": observed_shots, "waves": sorted(waves)})
