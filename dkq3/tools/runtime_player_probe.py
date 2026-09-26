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


def movement_scenario(args, issue, capture, log):
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
    return {"positions": positions, "scope": "native connection and movement diagnostics; authored gameplay unqualified"}


def lift_scenario(issue, capture, log):
    # Valid standing position from the existing recorded lift regression; no save is modified.
    issue("dk3_runtime_place 818.916 -479.481 -823.875", 0.5)
    issue("viewpos")
    capture("lift-bottom")
    issue("dk3_runtime_activate 3", 0.25)
    issue("dk3_runtime_activate 3", 0.25)
    samples = []
    top_captured = False
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        issue("dk3_runtime_trains", 0.05)
        issue("viewpos", 0.05)
        issue("dk3_runtime_status", 0.2)
        text = log.read_text(errors="replace")
        lines = re.findall(r"zig train id=3 name=bigplat ([^\n]+)", text)
        if not lines:
            raise RuntimeError("bigplat diagnostics missing")
        fields = dict(re.findall(r"(\w+)=([^ ]+)", lines[-1]))
        positions = re.findall(r"zig viewpos: ([^,]+),", text)
        times = re.findall(r"dk3 zig: entities=\d+ frames=\d+ time=(\d+)", text)
        sample = {"phase": fields["phase"], "wait": int(fields["wait"]),
                  "due": None if fields["due"] == "null" else int(fields["due"]),
                  "train_z": float(fields["pos"].split(",")[2]),
                  "player_z": float(positions[-1].split()[2]), "time": int(times[-1])}
        samples.append(sample)
        if sample["phase"] == "dwelling" and not top_captured:
            capture("lift-top")
            top_captured = True
        if top_captured and sample["phase"] == "paused":
            break
    (log.parent / "lift-samples.json").write_text(json.dumps(samples, indent=2) + "\n")
    top = [sample for sample in samples if sample["phase"] == "dwelling"]
    if not top or any(abs(sample["train_z"] + 274) > 0.01 or sample["wait"] != 10000 for sample in top):
        raise RuntimeError("lift did not reach the authored upper dwell")
    if len({sample["due"] for sample in top}) != 1 or top[-1]["time"] - top[0]["time"] < 9000:
        raise RuntimeError("lift returned before its ten-second dwell")
    if samples[-1]["phase"] != "paused" or abs(samples[-1]["train_z"] + 902) > 0.01:
        raise RuntimeError("lift did not return to trigger-only lower rest")
    if max(sample["player_z"] for sample in samples) - samples[-1]["player_z"] < 500:
        raise RuntimeError("rider was not carried to the upper stop")
    capture("lift-returned")
    return {"samples": len(samples), "scope": "e1m3a lift ride, departure dwell and return; diagnostic activation, not full campaign acceptance"}


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
                result = lift_scenario(issue, capture, log) if args.scenario == "lift" else movement_scenario(args, issue, capture, log)
                issue("quit", 0)
                if process.wait(timeout=15) != 0:
                    raise RuntimeError(f"engine shutdown failed: {log}")
                (args.report / "result.json").write_text(json.dumps({**result, "workers": args.workers}, indent=2) + "\n")
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
    parser.add_argument("--report", type=Path, default=None)
    parser.add_argument("--map")
    parser.add_argument("--scenario", choices=("movement", "lift"), default="movement")
    parser.add_argument("--workers", type=int, choices=range(9), default=4)
    parser.add_argument("--renderer", choices=("opengl1", "opengl2"), default="opengl1")
    parser.add_argument("--mover", type=int, help="optional known delayed-door persistent ID; e1m3b uses 255")
    args = parser.parse_args()
    if args.map is None:
        args.map = "e1m3a" if args.scenario == "lift" else "e1m3b"
    if args.report is None:
        args.report = Path("zig-out/reports/runtime-zig-219/lift" if args.scenario == "lift" else "zig-out/reports/runtime-zig-218/client")
    if args.scenario == "lift" and (args.map != "e1m3a" or args.mover is not None):
        parser.error("lift scenario uses e1m3a's bigplat; omit --mover")
    if not re.fullmatch(r"[a-zA-Z0-9_]+", args.map):
        parser.error("map must be a simple map name")
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    run(args)


if __name__ == "__main__":
    main()
