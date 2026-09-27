#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Resident collision / asynchronous read diagnostic. Run under dkguard.

This verifies preparation alongside an active native map, not seamless travel.
"""
import argparse
import math
from pathlib import Path
import re

from runtime_bugfix_probe import run
from runtime_probe import wait


def resident(driver, report, capture):
    before = driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal",
                          description="ordinary native map running")
    driver.ready()
    driver.save("resident_origin")
    start = len(driver.text())
    for name in ("e1m1a", "e1m1b", "e1m1c", "e1m2a"):
        driver.diagnostics(f"dk3_runtime_resident prepare {name}", "dk3 resident: requested")
    names = ("e1m1a", "e1m1b", "e1m1c", "e1m2a")
    text = wait(driver.process, driver.log,
                lambda text: all(re.search(rf"dk3 resident: map={name} .* stage=collision_ready", text[start:])
                                 for name in names), 15)[start:]
    prepared = [dict(zip(("map", "handle", "bytes", "admission_ms"), values)) for values in
                re.findall(r"dk3 resident: map=(\w+) handle=(\d+) stage=collision_ready bytes=(\d+) admission_ms=(\d+)", text)]
    assert len(prepared) == 4 and all(int(row["bytes"]) > 0 for row in prepared)
    assert len({row["handle"] for row in prepared}) == 4
    after = driver.observe()
    assert after["map"] == before["map"] and after["player_id"] == before["player_id"]
    assert after["now"] > before["now"] and after["processed"]
    assert "Server Initialization" not in text and "restoration applied" not in text
    traces = []
    for name, origin in (("e1m1a", (1608, -2592, 552)), ("e1m1b", (-600, -1392, 524)),
                         ("e1m1c", (-840, 1600, 760)), ("e1m2a", (512, 1160, 440))):
        x, y, z = origin
        result = driver.diagnostics(f'dk3_runtime_resident trace {name} "{x} {y} {z}" "{x} {y} {z-512}"',
                                    "dk3 resident trace:")
        match = re.search(r"fraction=([\d.]+) startsolid=(\d+) end=([-\d.]+),([-\d.]+),([-\d.]+)", result)
        assert match and 0 < float(match[1]) < 1 and match[2] == "0", result
        assert math.isclose(float(match[3]), x, abs_tol=.01) and math.isclose(float(match[4]), y, abs_tol=.01)
        traces.append(dict(map=name, fraction=float(match[1]), end=tuple(map(float, match.group(3, 4, 5)))))
    # Normal user commands still run against the active world's collision tree.
    driver.issue("+moveright")
    moved = driver.until(lambda s: math.dist(s["pos"], after["pos"]) > 24,
                         seconds=5, description="normal movement with four prepared worlds")
    driver.issue("-moveright")
    assert moved["map"] == "e1m1a" and moved["health"] > 0
    capture("resident-active-world")
    driver.load("resident_origin")
    assert driver.observe()["map"] == "e1m1a"
    driver.diagnostics("dk3_runtime_resident clear", "dk3 resident: cleared")
    # Release while a read may still be pending, then reuse slots with a new
    # generation. Cancellation timing is intentionally not claimed as forced.
    driver.diagnostics("dk3_runtime_resident prepare e1m1b", "dk3 resident: requested")
    driver.diagnostics("dk3_runtime_resident clear", "dk3 resident: cleared")
    offset = len(driver.text())
    driver.diagnostics("dk3_runtime_resident prepare e1m1b", "dk3 resident: requested")
    text = wait(driver.process, driver.log, lambda text: re.search(
        r"dk3 resident: map=e1m1b .* stage=collision_ready", text[offset:]), 15)[offset:]
    handle = re.search(r"dk3 resident: map=e1m1b handle=(\d+)", text)[1]
    assert handle not in {row["handle"] for row in prepared}
    driver.diagnostics("dk3_runtime_resident clear", "dk3 resident: cleared")
    return dict(scope="Resident collision only; no seamless crossing or frame-time acceptance",
                prepared=prepared, traces=traces, before=before, after=after, moved=moved, reused_handle=handle)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = "resident"
    run(args, resident)
