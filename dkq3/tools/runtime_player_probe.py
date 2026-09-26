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


def special_scenario(args, issue, capture, log):
    identity = 43 if args.scenario == "secret" else 72

    def sample():
        issue("dk3_runtime_special", 0.4)
        values = re.findall(rf"zig special id={identity} phase=(\w+) pos=([^\n]+) angles=([^\n]+)", log.read_text(errors="replace"))
        if not values:
            raise RuntimeError("special mover diagnostics missing")
        return values[-1]

    if args.scenario == "secret":
        issue(f"dk3_runtime_activate {identity}")
        phases = []
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            phases.append(sample()[0])
            if "open" in phases and phases[-1] == "closed":
                break
        if not all(phase in phases for phase in ("waiting_first", "open", "waiting_return")) or phases[-1] != "closed":
            raise RuntimeError(f"incomplete secret-door cycle: {phases}")
        return {"phases": phases, "scope": "e3dm1 secret-door cycle; diagnostic activation, shoot activation unqualified"}
    first, second = sample(), sample()
    if first[0] != "rotating" or second[0] != "rotating" or first[2] == second[2]:
        raise RuntimeError("authored rotation did not start")
    issue(f"dk3_runtime_activate {identity}")
    stopped, held = sample(), sample()
    if stopped != held or stopped[0] != "stopped":
        raise RuntimeError("rotation failed to remain stopped")
    issue(f"dk3_runtime_activate {identity}")
    resumed, moving = sample(), sample()
    if resumed[0] != "rotating" or moving[0] != "rotating" or resumed[2] == moving[2]:
        raise RuntimeError("rotation did not resume")
    return {"samples": [first, second, stopped, held, resumed, moving],
            "scope": "e1m3b rotating brush start, toggle and resume; rotating riders unqualified"}


def inventory_scenario(issue, capture, log):
    def mover_state(identity):
        issue("dk3_runtime_movers")
        states = re.findall(rf"zig mover id={identity} .*state=(\w+)", log.read_text(errors="replace"))
        if not states:
            raise RuntimeError(f"missing mover {identity}")
        return states[-1]

    issue("dk3_runtime_activate 85 player", 0.5)
    if mover_state(85) != "closed":
        raise RuntimeError("key-locked button opened without key")
    issue("dk3_runtime_items")
    text = log.read_text(errors="replace")
    values = re.findall(r"zig item id=2 class=item_control_card_blue visible=(\d) ground=(\w+) pos=([^\n]+)", text)
    if not values or values[-1][0] != "1" or values[-1][1] == "null":
        raise RuntimeError("key did not settle on the floor")
    x, y, z = map(float, values[-1][2].split(","))
    issue(f"dk3_runtime_place {x + 80} {y} {z + 24}", 0.2)
    issue("dk3_look 180 15")
    capture("key-before")
    issue(f"dk3_runtime_place {x} {y} {z + 24}", 0.5)
    issue("dk3_runtime_inventory")
    issue("dk3_runtime_items")
    text = log.read_text(errors="replace")
    keys = re.findall(r"zig inventory keys=([0-9a-f]+)", text)
    if not keys or int(keys[-1], 16) & (1 << 0) == 0:
        raise RuntimeError("touch failed to collect blue keycard")
    if not re.search(r"zig item id=2 class=item_control_card_blue visible=0", text):
        raise RuntimeError("collected key remained visible")
    issue("dk3_runtime_activate 85 player", 0.3)
    state = mover_state(85)
    if state not in ("opening", "open"):
        raise RuntimeError("collected key did not unlock button")
    issue("dk3_runtime_items", 1)
    if mover_state(82) not in ("opening", "open"):
        raise RuntimeError("button arrival failed to activate four-way door")
    capture("key-collected")
    return {"keys": keys[-1], "button_state": state,
            "scope": "e1m6a key floor settlement, touch pickup and locked button target; diagnostic positioning, full authored progression unqualified"}


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
                if args.scenario == "lift":
                    result = lift_scenario(issue, capture, log)
                elif args.scenario == "inventory":
                    result = inventory_scenario(issue, capture, log)
                elif args.scenario in ("secret", "rotation", "inventory"):
                    result = special_scenario(args, issue, capture, log)
                else:
                    result = movement_scenario(args, issue, capture, log)
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
    parser.add_argument("--scenario", choices=("movement", "lift", "secret", "rotation", "inventory"), default="movement")
    parser.add_argument("--workers", type=int, choices=range(9), default=4)
    parser.add_argument("--renderer", choices=("opengl1", "opengl2"), default="opengl1")
    parser.add_argument("--mover", type=int, help="optional known delayed-door persistent ID; e1m3b uses 255")
    args = parser.parse_args()
    if args.map is None:
        args.map = {"lift": "e1m3a", "secret": "e3dm1", "inventory": "e1m6a"}.get(args.scenario, "e1m3b")
    if args.report is None:
        args.report = Path("zig-out/reports/runtime-zig-219/lift" if args.scenario == "lift" else "zig-out/reports/runtime-zig-218/client")
    if args.scenario in ("secret", "rotation", "inventory"):
        expected_map = {"secret": "e3dm1", "inventory": "e1m6a"}.get(args.scenario, "e1m3b")
        if args.map != expected_map or args.mover is not None:
            parser.error(f"{args.scenario} scenario uses {expected_map}; omit --mover")
        if args.report == Path("zig-out/reports/runtime-zig-218/client"):
            args.report = Path(f"zig-out/reports/runtime-zig-{221 if args.scenario == 'inventory' else 220}/{args.scenario}")
    if args.scenario == "lift" and (args.map != "e1m3a" or args.mover is not None):
        parser.error("lift scenario uses e1m3a's bigplat; omit --mover")
    if not re.fullmatch(r"[a-zA-Z0-9_]+", args.map):
        parser.error("map must be a simple map name")
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    run(args)


if __name__ == "__main__":
    main()
