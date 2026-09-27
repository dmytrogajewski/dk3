# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled bridge script/controller diagnostics; never continuous campaign acceptance."""
import re
import shutil
import time

from runtime_opening_route import actors
from runtime_probe import wait


def scenario(driver, report):
    if not driver.diagnostic:
        raise ValueError("Bridge diagnostics require explicit fixture mode")

    def await_actors(predicate, description, seconds=6):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            driver.observe()  # Fatal/runtime setup failures invalidate the scenario.
            rows = actors(driver)
            if predicate(rows):
                return rows
        raise TimeoutError(f"{description}: {rows}")

    def use(identity):
        driver.issue(f"dk3_runtime_activate {identity} player")
        driver.observe()

    driver.until(lambda s: s["map"] == "e1m1b" and s["mode"] == "normal", description="bridge fixture connected")
    driver.issue("dk3_runtime_probe_health 10000")
    driver.until(lambda s: s["health"] == 10000, description="diagnostic health set")
    use(64)
    rows = await_actors(lambda rows: sum(r.get("unique") == "tskeet" for r in rows.values()) == 1, "authored Thunderskeet exists")
    thunder = next(identity for identity, row in rows.items() if row.get("unique") == "tskeet")
    assert rows[thunder]["health"] == 600 and rows[thunder]["ignore"] == "1"
    use(64)
    assert sum(r.get("unique") == "tskeet" for r in actors(driver).values()) == 1
    use(508)
    await_actors(lambda rows: int(rows[thunder]["path"]) != 0, "Thunderskeet authored path attached")

    waves = []
    for number, trigger, path in ((1, 71, 502), (2, 489, 503), (3, 490, 504), (4, 491, 505), (5, 492, 506)):
        use(trigger)
        names = {f"skeet{number}{suffix}" for suffix in "ab"}
        rows = await_actors(lambda rows: names <= {r.get("unique", "").lower() for r in rows.values()}, f"wave {number} actors spawned")
        use(path)
        rows = await_actors(lambda rows: all(int(r["path"]) != 0 and r["ignore"] == "1" for r in rows.values() if r.get("unique", "").lower() in names), f"wave {number} paths active")
        waves += [identity for identity, row in rows.items() if row.get("unique", "").lower() in names]
    assert len(set(waves)) == 10
    save = driver.save("bridge_paths")
    shutil.copy2(save, report / save.name)
    before = len(driver.text())
    driver.issue("devmap e1m1b")
    wait(driver.process, driver.log, lambda text: "player entered isolated movement runtime" in text[before:], 30)
    driver.load("bridge_paths")
    rows = actors(driver)
    assert all(identity in rows for identity in waves + [thunder])
    assert rows[thunder]["class"] == "monster_thunderskeet"
    for trigger in (2, 575, 576, 577, 578):
        use(trigger)
    rows = await_actors(lambda rows: all(rows[i]["ignore"] == "0" for i in waves + [thunder]), "aggressive scripts release all eleven actors")
    driver.issue("screenshotJPEG bridge-restored")
    source = driver.home / "dk3/screenshots/bridge-restored.jpg"
    wait(driver.process, driver.log, lambda _: source.exists() and source.stat().st_size > 0, 5)
    shutil.copy2(source, report / source.name)
    return {"scope": "Controlled authored bridge spawn/path/aggressive programs, one-shot Thunderskeet and fresh-map save restoration. Diagnostic activation and health; combat/death output and connected bridge traversal remain unverified.", "thunder": thunder, "waves": waves, "restored": rows}
