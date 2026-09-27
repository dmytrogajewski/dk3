#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Read-only AAS portal regression; execute under dkguard, without --gpu."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

from runtime_input import record_identity
from runtime_probe import stage_client_modules, send, wait


def run(args):
    if not __debug__:
        raise RuntimeError("Route regression requires assertions")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.prefix, args.report)
    result = {"identity": identity, "dedicated_sha256": hashlib.sha256((args.engine / "bin/dk3ded").read_bytes()).hexdigest(),
              "scope": "Read-only e1ctf1 AAS edge traversal; no actor placement or campaign/match acceptance.", "routes": []}
    log = args.report / "server.log"
    with tempfile.TemporaryDirectory(prefix="dk3-native-route-contract-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.prefix, home)
        settings = {"net_enabled": "0", "fs_basepath": str(args.engine / "share"), "fs_homepath": str(home),
                    "fs_homedatapath": str(home), "fs_homestatepath": str(home / "state"), "com_basegame": "dk3",
                    "com_pipefile": "commands.fifo", "vm_game": "0", "dk3_runtime_probe": "2", "g_gametype": "4",
                    "sv_maxclients": "8", "bot_minplayers": "0", "developer": "1", "dk3_public": "0"}
        command = [str(args.engine / "bin/dk3ded")]
        for key, value in settings.items():
            command += ["+set", key, value]
        command += ["+map", "e1ctf1"]
        result["command"] = command
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"
            try:
                wait(process, log, lambda text: pipe.exists() and "isolated bootstrap" in text, 45)
                # First three reproduce observed stuck bots. The adjacent-area
                # and non-portal starts retain unaffected routing coverage.
                for start, goal in ((39, 330), (4683, 4714), (1973, 5396), (39, 357), (357, 39), (6483, 1863)):
                    offset = log.stat().st_size
                    send(pipe, f"dk3_runtime_route {start} {goal}")
                    text = wait(process, log, lambda text: "dk3 route complete:" in text[offset:], 10)[offset:]
                    row = re.search(r"dk3 route complete: from=(\d+) goal=(\d+) end=(\d+) edges=(\d+) status=(\w+)", text)
                    if row is None or (int(row[1]), int(row[2])) != (start, goal):
                        raise RuntimeError("Route setup/response mismatch")
                    result["routes"].append(dict(start=start, goal=goal, end=int(row[3]), edges=int(row[4]), status=row[5]))
                send(pipe, "quit")
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("Route diagnostic shutdown failed")
                if any(row["status"] != "reached" or row["end"] != row["goal"] for row in result["routes"]):
                    raise AssertionError("AAS routes did not reach their destinations: " + str(result["routes"]))
                result["status"] = "passed"
            except Exception as error:
                result.update(status="failed", error=str(error))
                raise
            finally:
                (args.report / "result.json").write_text(json.dumps(result, indent=2) + "\n")
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, default=Path("zig-out/native-dev"))
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    args.engine, args.prefix, args.report = args.engine.resolve(), args.prefix.resolve(), args.report.resolve()
    run(args)


if __name__ == "__main__":
    main()
