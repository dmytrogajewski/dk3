#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated native client/movement probe; does not certify campaign acceptance."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time

from runtime_probe import send, wait


def run(args):
    args.report.mkdir(parents=True, exist_ok=True)
    log = args.report / "client.log"
    inputs = []
    with tempfile.TemporaryDirectory(prefix="dk3-runtime-client-") as temporary:
        home = Path(temporary)
        (home / "dk3").mkdir()
        for module in ("qagame", "cgame", "ui"):
            shutil.copy2(args.prefix / f"lib/dk3/{module}.so", home / f"dk3/{module}.so")
        command = [str(args.guard), "--headless", "--screen", "960x540",
                   "--timeout", "90s", "--mem", "8G", "--", str(args.engine / "bin/dk3")]
        settings = {"net_enabled": "0", "fs_basepath": str(args.engine / "share"),
                    "fs_homepath": str(home), "fs_homedatapath": str(home),
                    "fs_homestatepath": str(home / "state"), "com_basegame": "dk3",
                    "com_pipefile": "commands.fifo", "vm_game": "0", "vm_cgame": "0",
                    "vm_ui": "0", "g_gametype": "2", "dk3_runtime_probe": "2",
                    "dk3_jobs": str(args.workers), "com_maxfps": "60",
                    "cl_renderer": args.renderer, "r_fullscreen": "0", "r_mode": "-1",
                    "r_customwidth": "960", "r_customheight": "540", "s_useOpenAL": "0"}
        for name, value in settings.items():
            command += ["+set", name, value]
        command += ["+devmap", args.map]
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"

            def issue(value, delay=0.15):
                inputs.append({"command": value, "settle_seconds": delay})
                send(pipe, value)
                time.sleep(delay)

            def capture(name):
                issue(f"screenshotJPEG {name}")
                source = home / f"dk3/screenshots/{name}.jpg"
                wait(process, log, lambda _: source.exists(), 10)
                shutil.copy2(source, args.report / f"{name}.jpg")

            try:
                wait(process, log, lambda text: "player entered isolated movement runtime" in text)
                issue("viewpos")
                capture("standing")
                issue("+forward", 1)
                issue("-forward")
                issue("viewpos")
                issue("+movedown", 0.5)
                capture("crouching")
                issue("-movedown")
                issue("+moveup", 0.3)
                issue("-moveup", 1)
                issue("viewpos")
                if args.mover is not None:
                    issue(f"dk3_runtime_activate {args.mover}", 0.25)
                    issue("dk3_runtime_movers", 0.05)
                    issue(f"dk3_runtime_activate {args.mover}", 0.25)
                    issue("dk3_runtime_movers", 2)
                    issue("dk3_runtime_movers", 4)
                    issue("dk3_runtime_movers")
                text = log.read_text(errors="replace")
                positions = re.findall(r"zig viewpos: ([^\n]+)", text)
                if len(positions) != 3:
                    raise RuntimeError(f"missing movement diagnostics: {log}")
                if args.mover is not None:
                    states = re.findall(rf"zig mover id={args.mover} .*state=(\w+)", text)
                    if len(states) != 4 or states[:2] != ["opening", "opening"] or states[-1] != "open":
                        raise RuntimeError(f"unexpected repeated activation/delayed arrival: {states}")
                issue("quit", 0)
                if process.wait(timeout=15) != 0:
                    raise RuntimeError(f"engine shutdown failed: {log}")
                (args.report / "result.json").write_text(json.dumps({
                    "positions": positions, "workers": args.workers,
                    "scope": "native connection and movement diagnostics; authored gameplay unqualified",
                }, indent=2) + "\n")
            finally:
                (args.report / "inputs.json").write_text(json.dumps({"launch": command, "inputs": inputs}, indent=2) + "\n")
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
    print(f"Native client probe passed. Inspect captures in {args.report}; gameplay acceptance remains open.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--guard", type=Path, default=Path("zig-out/bin/dkguard"))
    parser.add_argument("--report", type=Path, default=Path("zig-out/reports/runtime-zig-218/client"))
    parser.add_argument("--map", default="e1m3b")
    parser.add_argument("--workers", type=int, choices=range(9), default=4)
    parser.add_argument("--renderer", choices=("opengl1", "opengl2"), default="opengl1")
    parser.add_argument("--mover", type=int, help="optional known delayed-door persistent ID; e1m3b uses 255")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_]+", args.map):
        parser.error("map must be a simple map name")
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    run(args)


if __name__ == "__main__":
    main()
