#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the isolated replacement ABI and worker barriers, not gameplay acceptance."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


def wait(process, log, predicate, seconds=45):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        text = log.read_text(errors="replace")
        if predicate(text):
            return text
        if process.poll() is not None:
            raise RuntimeError(f"engine exited {process.returncode}: {log}")
        time.sleep(0.05)
    raise TimeoutError(str(log))


def send(pipe, command):
    fd = os.open(pipe, os.O_WRONLY | os.O_NONBLOCK)
    try:
        os.write(fd, (command + "\n").encode())
    finally:
        os.close(fd)


def run(args, workers):
    log = args.report / f"workers-{workers}.log"
    with tempfile.TemporaryDirectory(prefix="dk3-runtime-probe-") as temporary:
        home = Path(temporary)
        (home / "dk3").mkdir()
        shutil.copy2(args.prefix / "lib/dk3/qagame.so", home / "dk3/qagame.so")
        command = [str(args.guard), "--timeout", "90s", "--mem", "8G", "--",
                   str(args.engine / "bin/dk3ded")]
        settings = {"net_enabled": "0", "fs_basepath": str(args.engine / "share"),
                    "fs_homepath": str(home), "fs_homedatapath": str(home),
                    "fs_homestatepath": str(home / "state"), "com_basegame": "dk3",
                    "com_pipefile": "commands.fifo", "vm_game": "0", "g_gametype": "2",
                    "dk3_runtime_probe": "1", "dk3_jobs": str(workers)}
        for name, value in settings.items():
            command += ["+set", name, value]
        command += ["+map", args.map]
        inputs = ["dk3_runtime_probe_motion", "map_restart 0", "dk3_runtime_probe_motion", "quit"]
        (args.report / f"workers-{workers}-inputs.json").write_text(
            json.dumps({"command": command, "inputs": inputs}, indent=2) + "\n")
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"
            try:
                wait(process, log, lambda text: "isolated bootstrap" in text and pipe.exists())
                send(pipe, inputs[0])
                wait(process, log, lambda text: "motion probe:" in text)
                send(pipe, inputs[1])
                wait(process, log, lambda text: text.count("isolated bootstrap") == 2)
                send(pipe, inputs[2])
                text = wait(process, log, lambda text: text.count("motion probe:") == 2)
                hashes = re.findall(r"motion probe: .*hash=([0-9a-f]+)", text)
                send(pipe, "quit")
                if process.wait(timeout=15) != 0:
                    raise RuntimeError(f"engine shutdown failed: {log}")
                return {"workers": workers, "hashes": hashes}
            finally:
                if process.poll() is None:
                    # dkguard owns process-group cleanup when its timeout/signal fires.
                    process.terminate()
                    process.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True, help="existing local installation generation")
    parser.add_argument("--prefix", type=Path, required=True, help="isolated Zig replacement build prefix")
    parser.add_argument("--guard", type=Path, default=Path("zig-out/bin/dkguard"))
    parser.add_argument("--report", type=Path, default=Path("zig-out/reports/runtime-zig-217"))
    parser.add_argument("--map", default="e1m3b")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-zA-Z0-9_]+", args.map):
        parser.error("map must be a simple map name")
    for name in ("engine", "prefix", "guard", "report"):
        setattr(args, name, getattr(args, name).resolve())
    args.report.mkdir(parents=True, exist_ok=True)
    results = [run(args, workers) for workers in (0, 1, 4)]
    if any(len(row["hashes"]) != 2 for row in results) or len({value for row in results for value in row["hashes"]}) != 1:
        raise RuntimeError(f"worker/restart mismatch: {results}")
    (args.report / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print("Native bootstrap, collision barriers and restart equivalence passed (0, 1, 4 workers).")
    print("Gameplay acceptance remains unqualified.")


if __name__ == "__main__":
    main()
