# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused authored Crox contact and water-state restoration; not campaign evidence."""
import json
import math
import re
import shutil
import time

from runtime_opening_route import actors
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Crox fixtures require diagnostic mode")

    def sample(predicate, description, seconds=8):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            driver.observe()
            rows = actors(driver)
            if predicate(rows):
                return rows
        (report / "failed-actors.json").write_text(json.dumps(rows, indent=2))
        raise TimeoutError(description)

    def capture(name):
        driver.issue(f"screenshotJPEG {name}")
        source = driver.home / f"dk3/screenshots/{name}.jpg"
        wait(driver.process, driver.log, lambda _: source.exists() and source.stat().st_size > 0, 5)
        shutil.copy2(source, report / source.name)

    driver.until(lambda s: s["map"] == "e1m1b" and s["skill"] == 3 and s["mode"] == "normal", description="normal bridge fixture connected")
    driver.issue("dk3_runtime_probe_health 1000")
    driver.until(lambda s: s["health"] == 1000, description="controlled combat health")
    rows = actors(driver)
    crocs = {i: r for i, r in rows.items() if r["class"] == "monster_crox"}
    assert {387, 425, 431} <= crocs.keys(), "Normal authored Crox were not admitted"
    assert all(r["health"] == 150 for r in crocs.values())
    wet = sample(lambda rows: any(r["class"] == "monster_crox" and r["crox_water"] == "3" and r["crox_swim"] == "1" for r in rows.values()), "No actually submerged swimming Crox; water setup failed")
    submerged = next(i for i, r in wet.items() if r["class"] == "monster_crox" and r["crox_water"] == "3" and r["crox_swim"] == "1")
    save = driver.save("crox_swimming")
    shutil.copy2(save, report / save.name)
    driver.load("crox_swimming")
    restored = actors(driver)[submerged]
    assert restored["crox_swim"] == "1" and restored["crox_water"] == "3"
    initial = restored["pos"]
    moved = sample(lambda rows: math.dist(rows[submerged]["pos"], initial) > 4, "Swimming Crox did not move")
    target = 425
    driver.diagnostics(f"dk3_runtime_face_target {target} 40", f"target={target}")
    before = len(driver.text())
    pending = sample(lambda rows: rows[target]["state"] == "attack" and rows[target]["crox_struck"] == "0", "Crox did not begin a real melee attack")
    assert pending[target]["crox_water"] != "3" and pending[target]["crox_pose"] in ("2", "3")
    save = driver.save("crox_melee_pending")
    shutil.copy2(save, report / save.name)
    driver.load("crox_melee_pending")
    state = actors(driver)[target]
    assert state["state"] == "attack" and state["crox_struck"] == "0"
    before = len(driver.text())
    text = wait(driver.process, driver.log, lambda text: f"dk3 crox: id={target} contact=" in text[before:], 5)[before:]
    contact = re.search(rf"dk3 crox: id={target} contact=(\d+) damage=([\d.]+)", text)
    assert contact and 15 <= float(contact[2]) < 35
    driver.until(lambda s: s["health"] < 1000, description="actual Crox health loss")
    row = actors(driver)[target]
    player = driver.observe()
    delta = [row["aim"][i] - player["pos"][i] for i in range(3)]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
    capture("crox-contact-restored")
    return {"scope": "Focused authored Crox admission, observed full submersion/swimming movement and saved pending melee contact. Diagnostic placement and health; no connected bridge traversal or complete amphibious/reference parity.", "submerged": submerged, "swim_restored": restored, "swim_moved": moved[submerged], "attack_restored": state, "contact": contact.group(0)}
