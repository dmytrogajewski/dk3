#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Acknowledged destination definitions and actual client media/collision readiness."""
import argparse
import math
from pathlib import Path
import re

from runtime_bugfix_probe import run
from runtime_probe import wait


def admission(driver, report, capture):
    before = driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal",
                          description="ordinary active map")
    driver.ready()
    start = len(driver.text())
    for name in ("e1m1b", "e1m1c", "e1m2a"):
        driver.diagnostics(f"dk3_runtime_resident prepare-game {name}", "dk3 resident: requested")
    text = wait(driver.process, driver.log, lambda text: all(
        f"dk3 resident: map={name} stage=client_ready" in text[start:]
        for name in ("e1m1b", "e1m1c", "e1m2a")), 90)[start:]
    rows = [dict(zip(("map", "handle", "inline", "models", "sounds", "checksum"), row))
            for row in re.findall(r"dk3 world admission: map=(\w+) handle=(\d+) ready=1 inline=(\d+) models=(\d+) sounds=(\d+) checksum=(\d+)", text)]
    assert {row["map"] for row in rows} == {"e1m1b", "e1m1c", "e1m2a"}
    assert len({row["handle"] for row in rows}) == 3
    assert all(int(row[key]) > 0 for row in rows for key in ("inline", "models", "sounds", "checksum"))
    assert "client_failed=" not in text and "gameplay_failed=" not in text and "Server Initialization" not in text
    stationary = driver.observe()
    assert stationary["map"] == before["map"] and stationary["player_id"] == before["player_id"]
    assert stationary["health"] > 0 and stationary["processed"]
    driver.issue("+moveright")
    moved = driver.until(lambda s: math.dist(s["pos"], stationary["pos"]) > 24,
                         seconds=5, description="normal input after actual client readiness")
    driver.issue("-moveright")
    assert moved["map"] == "e1m1a" and moved["health"] > 0
    capture("active-with-ready-destinations")
    driver.diagnostics("dk3_runtime_render_world preview e1m1b \"-600 -1392 546\" \"0 0 0\"",
                       "dk3 render world: preview map=")
    capture("prepared-bridge-media")
    driver.diagnostics("dk3_runtime_render_world close", "dk3 render world: preview closed")
    driver.diagnostics("dk3_runtime_resident clear", "dk3 resident: cleared")
    after = driver.observe()
    assert after["map"] == "e1m1a" and after["processed"]
    return dict(scope="Acknowledged, digest-checked destination configstrings, exact BSP checksum and actual collision/model/sound/sky preparation while active input survives. No player transfer or continuous campaign claim.",
                worlds=rows, before=before, moved=moved, after=after)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = "world-admission"
    run(args, admission)
