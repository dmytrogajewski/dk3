# SPDX-License-Identifier: GPL-2.0-or-later
"""Focused authored Rockgat deployment/contact/restoration; not campaign evidence."""
import math
import re
import shutil
import time

from runtime_opening_route import actors
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Rockgat fixtures require diagnostic mode")

    def sample(predicate, description, seconds=8):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            driver.observe()
            rows = actors(driver)
            if predicate(rows):
                return rows
        raise TimeoutError(f"{description}: {rows.get(85)}")

    def capture(name):
        driver.issue(f"screenshotJPEG {name}")
        source = driver.home / f"dk3/screenshots/{name}.jpg"
        wait(driver.process, driver.log, lambda _: source.exists() and source.stat().st_size > 0, 5)
        shutil.copy2(source, report / source.name)

    original = driver.until(lambda s: s["map"] == "e1m1b" and s["skill"] == 3 and s["mode"] == "normal", description="bridge fixture connected")
    rows = actors(driver)
    assert rows[85]["class"] == rows[92]["class"] == "monster_rockgat"
    assert rows[85]["health"] == 500 and rows[92]["health"] == 1000
    assert rows[85]["gun"] == "passive" and rows[85]["gun_shots"] == "0"
    driver.issue("dk3_runtime_probe_health 1000")
    driver.until(lambda s: s["health"] == 1000, description="controlled target health")
    driver.diagnostics("dk3_runtime_face_target 85 160", "target=85")
    before = len(driver.text())
    sample(lambda rows: rows[85]["gun"] == "scanning" and rows[85]["gun_shots"] == "0", "Turret failed popup delay")
    save = driver.save("rockgat_raising")
    shutil.copy2(save, report / save.name)
    driver.load("rockgat_raising")
    assert actors(driver)[85]["gun"] == "scanning"
    text = wait(driver.process, driver.log, lambda text: re.search(r"dk3 rockgat: id=85 shot=\d+ contact=[1-9]\d*", text[before:]) is not None, 5)[before:]
    contact = re.search(r"dk3 rockgat: id=85 shot=\d+ contact=[1-9]\d*", text).group(0)
    driver.until(lambda s: s["health"] < 1000, description="confirmed turret damage")
    row = sample(lambda rows: int(rows[85]["gun_pending"]) > 0, "No live burst controller before save")[85]
    save = driver.save("rockgat_firing")
    shutil.copy2(save, report / save.name)
    prior_shots = int(row["gun_shots"])
    driver.load("rockgat_firing")
    assert int(actors(driver)[85]["gun_pending"]) > 0, "No restored burst controller"
    row = sample(lambda rows: int(rows[85]["gun_shots"]) > prior_shots, "Saved turret failed to resume firing")[85]
    player = driver.observe()
    delta = [row["aim"][i] - player["pos"][i] for i in range(3)]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
    capture("rockgat-firing-restored")
    driver.issue("dk3_runtime_place " + " ".join(map(str, original["pos"])))
    driver.until(lambda s: math.dist(s["pos"], original["pos"]) < 32, description="fixture returned outside turret range")
    lowered = sample(lambda rows: rows[85]["gun"] == "passive", "Passive turret did not lower")[85]
    driver.save("rockgat_lowered")
    driver.load("rockgat_lowered")
    assert actors(driver)[85]["gun"] == "passive"
    driver.load("rockgat_firing")
    driver.issue("dk3_runtime_equip 2")
    driver.ready(2)
    # The stationary authored turret is a controlled contact target, not a
    # synthetic monster. Diagnostic equipment is excluded from campaign evidence.
    contacts = []
    for _ in range(30):
        rows = actors(driver)
        if 85 not in rows:
            break
        target = rows[85]
        state = driver.ready(2)
        delta = [target["aim"][i] - state["pos"][i] for i in range(3)]
        delta[2] -= 22
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        prior = target["health"]
        driver.fire()
        rows = sample(lambda rows: 85 not in rows or rows[85]["health"] < prior, "No confirmed ion contact with turret", seconds=2)
        contacts.append({"before": prior, "after": rows.get(85, {}).get("health")})
    assert 85 not in actors(driver), "Turret did not disappear after lethal damage"
    driver.save("rockgat_destroyed")
    driver.load("rockgat_destroyed")
    assert 85 not in actors(driver), "Destroyed turret returned on load"
    capture("rockgat-destroyed-restored")
    return {"scope": "Authored Rockgat popup delay, real bullet contact, raising/firing/lowered restoration, passive return, ordinary ion contact and lethal removal/restoration. Diagnostic placement, equipment and health; no connected bridge encounter, toggle qualification or full reference presentation.", "contact": contact, "firing_restored": row, "lowered": lowered, "ion_contacts": contacts}
