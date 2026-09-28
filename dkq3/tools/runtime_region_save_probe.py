#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Actual multi-map save/death restoration after controlled resident transfers."""
import argparse
import math
from pathlib import Path
import shutil

from runtime_bugfix_probe import run
from runtime_opening_route import actors
from runtime_input import engine_failure
from runtime_probe import wait
from runtime_region_progression_probe import event


def enter(driver, name, parks):
    offset = len(driver.text())
    point = " ".join(map(str, parks[name]))
    text = driver.diagnostics(f"dk3_runtime_enter_world {name}; dk3_runtime_place {point}", "dk3 world transfer:")
    assert "failed=" not in text, text
    wait(driver.process, driver.log, lambda text: "dk3 world presentation: entered=" in text[offset:], 10)
    return driver.until(lambda s: s["map"] == name, description=f"input in resident {name}")


def health(driver, target, value):
    driver.issue(f"dk3_runtime_probe_health {value} {target}")
    driver.observe()
    row = actors(driver)[target]
    assert row["health"] == value, row
    return row


def restored(driver, offset):
    text = wait(driver.process, driver.log, lambda text:
         ("dk3 region: restoration committed" in text[offset:]
          and "dk3 zig client: restoration applied" in text[offset:])
         or engine_failure(text[offset:]), 90)[offset:]
    if failure := engine_failure(text):
        raise RuntimeError(failure)
    return driver.until(lambda s: s["map"] == "e1m1b" and s["health"] == 73,
                        description="restored region admits actual input")


def region_save(driver, report, capture):
    event(driver, 'dk3 region: initial admission committed')
    assert 'map=e1m1b stage=client_ready' in driver.text()
    initial = driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal")
    parks = dict(e1m1a=initial["pos"], e1m1b=(-600, -1392, 533))
    driver.ready()
    a = next(i for i, row in actors(driver).items() if row["health"] > 0)
    health(driver, a, 37)
    driver.issue("dk3_runtime_place -752 -1392 525")
    placed = driver.until(lambda s: math.dist(s["pos"], (-752, -1392, 525)) < 40,
                          description="controlled shared corridor")
    entered = enter(driver, "e1m1b", parks)
    assert entered["player_id"] == placed["player_id"]
    b = next(i for i, row in actors(driver).items() if row["health"] > 0)
    assert b >= 0x1000000 and a < 0x1000000
    health(driver, b, 53)
    driver.issue("dk3_runtime_probe_health 73")
    saved_state = driver.until(lambda s: s["health"] == 73)
    path = driver.save("resident_region")
    shutil.copy2(path, report / path.name)
    health(driver, b, 7)
    enter(driver, "e1m1a", parks)
    health(driver, a, 9)
    driver.issue("dk3_runtime_probe_health 91")
    driver.until(lambda s: s["health"] == 91)
    offset = len(driver.text())
    driver.issue("load resident_region")
    loaded = restored(driver, offset)
    assert loaded["player_id"] == saved_state["player_id"]
    assert loaded["weapon"] == saved_state["weapon"] and loaded["ammo"] == saved_state["ammo"]
    assert actors(driver)[b]["health"] == 53
    enter(driver, "e1m1a", parks)
    assert actors(driver)[a]["health"] == 37
    capture("restored-source-map")
    offset = len(driver.text())
    driver.issue("dk3_runtime_damage 2000")
    dead = driver.until(lambda s: s["mode"] == "dead" and s["health"] <= 0,
                        description="actual death outside saved active map")
    driver.issue("+attack")
    recovered = restored(driver, offset)
    driver.issue("-attack")
    assert recovered["player_id"] == saved_state["player_id"]
    assert actors(driver)[b]["health"] == 53
    enter(driver, "e1m1a", parks)
    assert actors(driver)[a]["health"] == 37
    final = driver.observe()
    assert final["health"] == 73 and final["processed"]
    capture("source-after-region-death-restore")
    return dict(scope="Actual atomic region save/load and death checkpoint restore, including transferred player identity and independently changed authored actor health in both maps. Controlled placement, health and transfer commands; not connected campaign acceptance.",
                actors=dict(e1m1a=a, e1m1b=b), saved=saved_state, loaded=loaded,
                dead=dead, recovered=recovered, final=final)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = "region-save"
    run(args, region_save)
