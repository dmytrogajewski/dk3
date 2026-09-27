#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Resident renderer isolation diagnostic. Run under dkguard; no travel claim."""
import argparse
from pathlib import Path
import re

from runtime_bugfix_probe import run
from runtime_probe import wait


def resident(driver, report, capture):
    before = driver.until(lambda s: s["map"] == "e1m1a" and s["mode"] == "normal",
                          description="ordinary active map")
    driver.ready()
    capture("active-before")
    offset = len(driver.text())
    for name in ("e1m1b", "e1m1c"):
        driver.diagnostics(f"dk3_runtime_render_world prepare {name}", "dk3 render world: requested")
    text = wait(driver.process, driver.log, lambda text: all(re.search(
        rf"dk3 render world: map={name} .* ready=1", text[offset:])
        for name in ("e1m1b", "e1m1c")), 30)[offset:]
    prepared = [dict(zip(("map", "handle", "admission_ms"), row)) for row in re.findall(
        r"dk3 render world: map=(\w+) handle=(\d+) ready=1 admission_ms=(\d+)", text)]
    assert len(prepared) == 2 and len({row["handle"] for row in prepared}) == 2
    assert "Server Initialization" not in text and "restoration applied" not in text
    models = []
    for name, pos, angles in (("e1m1b", "-600 -1392 546", "0 0 0"),
                              ("e1m1c", "-840 1600 782", "0 0 0")):
        result = driver.diagnostics(f'dk3_runtime_render_world preview {name} "{pos}" "{angles}"',
                                    "dk3 render world: preview map=")
        match = re.search(r"inline1=(\d+) active_inline1=(\d+)", result)
        assert match and int(match[1]) > 0 and int(match[2]) > 0 and match[1] != match[2], result
        models.append(dict(map=name, inline=int(match[1]), active_inline=int(match[2])))
        capture(name + "-resident")
        driver.diagnostics("dk3_runtime_render_world close", "dk3 render world: preview closed")
        capture("active-after-" + name)
    assert len({row["inline"] for row in models}) == 2
    assert len({row["active_inline"] for row in models}) == 1
    after = driver.observe()
    assert after["map"] == before["map"] and after["player_id"] == before["player_id"]
    assert after["processed"] and after["now"] > before["now"]
    return dict(scope="Static resident renderer contexts, scoped inline models and active-world restoration; no seamless crossing or frame-time acceptance",
                prepared=prepared, models=models, before=before, after=after)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--renderer", default="opengl1")
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = "resident-renderer"
    run(args, resident)
