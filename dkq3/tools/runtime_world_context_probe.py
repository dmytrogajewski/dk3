#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Map-owned gameplay/navigation preparation diagnostic, run under dkguard."""
import argparse
import math
from pathlib import Path
import re

from runtime_bugfix_probe import run
from runtime_probe import wait


def inspect(driver, name, point):
    text = driver.diagnostics(f'dk3_runtime_resident inspect {name} "{point}"',
                              "dk3 resident inspect:")
    match = re.search(r"map=(\w+) entities=(\d+) actors=(\d+) linked=(\d+) area=(\d+) state=([0-9a-f]+) contacts=(\d+)", text)
    assert match and match[1] == name, text
    result = dict(zip(("map", "entities", "actors", "linked", "area", "state", "contacts"), match.groups()))
    assert all(int(result[key]) > 0 for key in ("entities", "actors", "linked", "area", "contacts")), result
    return result


def contexts(driver, report, capture):
    before = driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal",
                          description="ordinary active map")
    driver.ready()
    driver.save("context_origin")
    points = {"e1m1b": "-600 -1392 524", "e1m1c": "-840 1600 760", "e1m2a": "512 1160 441"}
    start = len(driver.text())
    for name in points:
        driver.diagnostics(f"dk3_runtime_resident prepare-game {name}", "dk3 resident: requested")
    text = wait(driver.process, driver.log, lambda text: all(
        f"dk3 resident: map={name} stage=gameplay_prepared" in text[start:] for name in points), 30)[start:]
    assert "gameplay_failed" not in text and "Server Initialization" not in text
    prepared = [dict(zip(("map", "entities", "admission_ms"), row)) for row in re.findall(
        r"map=(\w+) stage=gameplay_prepared entities=(\d+) navigation=1 admission_ms=(\d+)", text)]
    assert len(prepared) == 3
    first = [inspect(driver, name, point) for name, point in points.items()]
    stationary = driver.observe()
    driver.issue("+moveright")
    moved = driver.until(lambda s: math.dist(s["pos"], stationary["pos"]) > 32,
                         seconds=5, description="normal movement with three retained game worlds")
    driver.issue("-moveright")
    assert moved["map"] == before["map"] and moved["player_id"] == before["player_id"]
    assert moved["processed"] and moved["health"] > 0
    second = [inspect(driver, name, point) for name, point in reversed(points.items())]
    assert {row["map"]: row for row in first} == {row["map"]: row for row in second}, "Dormant encounters changed"
    capture("active-with-resident-game-worlds")
    driver.load("context_origin")
    assert driver.observe()["map"] == "e1m1a"
    third = [inspect(driver, name, point) for name, point in points.items()]
    assert first == third
    driver.diagnostics("dk3_runtime_resident clear", "dk3 resident: cleared")
    after = driver.observe()
    assert after["map"] == "e1m1a" and after["processed"]
    return dict(scope="Map-owned entities, resource registration and navigation preparation with unchanged dormant encounters and active-map input/save restoration. No seamless crossing or region-save acceptance.",
                prepared=prepared, first=first, second=second, third=third, before=before, moved=moved, after=after)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = "world-contexts"
    run(args, contexts)
