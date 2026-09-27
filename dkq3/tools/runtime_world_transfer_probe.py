#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Resident ownership transfer diagnostic; not an authored seam playthrough."""
import argparse
import math
from pathlib import Path
import re

from runtime_bugfix_probe import run
from runtime_probe import wait


def transfer(driver, report, capture):
    driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal")
    driver.ready()
    start = len(driver.text())
    driver.diagnostics("dk3_runtime_resident prepare-game e1m1b", "dk3 resident: requested")
    wait(driver.process, driver.log, lambda text: "map=e1m1b stage=client_ready" in text[start:], 90)
    driver.issue("dk3_runtime_place -640 -1392 540")
    driver.issue("dk3_look 0 0")
    before = driver.until(lambda s: math.dist(s["pos"], (-640, -1392, 540)) < 40,
                          description="controlled shared-corridor setup")
    capture("before-transfer")
    timeline = []
    for name, expected in (("e1m1b", "e1m1b"), ("initial", "e1m1a"), ("e1m1b", "e1m1b")):
        previous = driver.observe()
        offset = len(driver.text())
        text = driver.diagnostics(f"dk3_runtime_enter_world {name}", "dk3 world transfer:")
        assert "failed=" not in text, text
        row = re.search(r"map=(\w+) world=(\d+) player=(\d+) position=([^ ]+) command=(\d+)", text)
        assert row and row[1] == expected and int(row[3]) == before["player_id"], text
        wait(driver.process, driver.log, lambda text: f"dk3 world presentation: entered={row[2]} " in text[offset:], 10)
        entered = driver.until(lambda s: s["map"] == expected, description="transferred player processes input")
        assert entered["health"] == previous["health"] > 0
        assert entered["player_id"] == before["player_id"]
        assert entered["weapon"] == previous["weapon"] and entered["ammo"] == previous["ammo"]
        assert math.dist(entered["pos"], previous["pos"]) < 40, (previous, entered)
        assert entered["cmd"] >= previous["cmd"]
        timeline.append(dict(previous=previous, transfer=row.group(0), entered=entered))
        capture(f"entered-{len(timeline)}-{expected}")
    stationary = driver.observe()
    driver.issue("dk3_look 90 0")
    driver.issue("+forward")
    moved = driver.until(lambda s: math.dist(s["pos"], stationary["pos"]) > 24,
                         seconds=5, description="ordinary movement in retained destination")
    driver.issue("-forward")
    assert moved["map"] == "e1m1b" and moved["health"] > 0
    text = driver.text()[start:]
    assert "Server Initialization" not in text and "ClientBegin" not in text
    return dict(scope="Controlled, position-preserving player transfer, exact identity, health, ammunition, continuous command time, client prediction and reverse transfer. No automatic seam, cross-world combat or region-save acceptance.",
                before=before, transfers=timeline, moved=moved)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = "world-transfer"
    run(args, transfer)
