# SPDX-License-Identifier: GPL-2.0-or-later
"""Normal-input death and visited-world boundaries on the opening campaign route."""
import json

from runtime_probe import wait
from runtime_opening_route import actors, walk


def death_reload(driver, capture, report):
    from runtime_bridge_route import checkpoint
    before = driver.observe()
    if before["map"] != "e1m1b" or before["pos"][2] < 950 or before["health"] <= 0:
        raise RuntimeError("Death/reload requires the actual living player on the bridge platform")
    if next(row for row in actors(driver).values() if row["unique"] == "tskeet")["health"] > 0:
        raise RuntimeError("Death/reload setup has not defeated the bridge boss")
    checkpoint(driver, capture, report, "bridge_death_checkpoint")
    walk(driver, (-720, 640, 984), capture, tolerance=24)
    driver.aim(0, 0)
    driver.issue("+forward")
    try:
        dead = driver.until(lambda s: s["health"] <= 0, seconds=5,
                            description="actual contact with authored eastern death volume")
    finally:
        driver.issue("-forward")
        driver.until(lambda s: s["forward"] == 0, description="processed death input release")
    capture("bridge-authored-death")
    restored = driver.load("bridge_death_checkpoint")
    for key in ("health", "armor", "weapon", "ammo"):
        if restored[key] != before[key]:
            raise RuntimeError(f"Death reload did not restore {key}")
    if restored["mode"] != "normal" or next(row for row in actors(driver).values() if row["unique"] == "tskeet")["health"] > 0:
        raise RuntimeError("Death reload lost living control or the defeated boss")
    capture("bridge-death-restored")
    (report / "connected-death-reload.json").write_text(json.dumps({
        "before": before, "death": dead, "restored": restored,
        "scope": "Normal movement into an authored hazard and acknowledged native reload; no health or placement fixture."}, indent=2) + "\n")


def bridge_progress(driver):
    from runtime_bridge_route import authored_id, items, world_rows
    namespace = authored_id(driver, 1) & 0xff000000
    boss = next(row for row in actors(driver).values() if row["unique"] == "tskeet")
    controls = world_rows(driver, "destructible")
    trees = world_rows(driver, "tree")
    drops = [row for row in items(driver).values() if row["class"] == "item_megashield"]
    if boss["health"] > 0 or len(drops) != 1 or drops[0]["visible"] != "0":
        raise RuntimeError("Visited-world setup requires the defeated boss and collected reward")
    return {"boss_health": boss["health"], "controls": {str(i): controls[namespace | i]["broken"] for i in (91, 86, 80, 81, 82)},
            "tree_fruit": trees[namespace | 110]["fruit"], "boss_reward_visible": drops[0]["visible"]}


def travel(driver, destination):
    offset = len(driver.text())
    before = driver.observe()
    driver.issue("+forward")
    try:
        state = driver.until(lambda s: s["map"] == destination and s["mode"] == "normal", seconds=20,
                             description=f"ordinary authored transition to {destination}")
    finally:
        driver.issue("-forward")
        driver.until(lambda s: s["forward"] == 0, description="processed arrival release")
    wait(driver.process, driver.log, lambda text: "kind=identity connection=retained" in text[offset:], 5)
    text = driver.text()[offset:]
    if state["player_id"] != before["player_id"] or "Server Initialization" in text or "ClientBegin" in text:
        raise RuntimeError("Resident round trip restarted the connection or changed player identity")
    driver.inputs.append({"connected_crossing": {"from": before, "to": state, "connection_retained": True}})
    return state


def visited_bridge(driver, capture, report, expected):
    from runtime_bridge_route import aim_at, checkpoint
    if driver.observe()["map"] != "e1m1c":
        raise RuntimeError("Visited bridge round trip must begin at actual factory arrival")
    checkpoint(driver, capture, report, "factory_visit_checkpoint")
    driver.load("factory_visit_checkpoint")  # The archived bridge must survive a disk save too.
    walk(driver, (-1024, 1664, 664), capture, tolerance=32)
    aim_at(driver, (-1260, 1664, 686))
    returned = travel(driver, "e1m1b")
    observed = bridge_progress(driver)
    if observed != expected:
        raise RuntimeError(f"Visited bridge state changed: {expected} -> {observed}")
    capture("bridge-visited-restored")
    walk(driver, (-900, 1600, 664), capture, tolerance=32)
    aim_at(driver, (-760, 1600, 686))
    arrival = travel(driver, "e1m1c")
    checkpoint(driver, capture, report, "factory_visited_return")
    evidence = {"before": expected, "after": observed, "bridge_arrival": returned, "factory_return": arrival,
                "scope": "Authored C→B→C round trip after disk save/load; actual boss, controls, fruit and consumed reward retained."}
    (report / "visited-world-roundtrip.json").write_text(json.dumps(evidence, indent=2) + "\n")
    return evidence
