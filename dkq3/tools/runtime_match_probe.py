#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Native bot matches with ordinary bot input; run under dkguard, without --gpu."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

from runtime_input import engine_failure, record_identity
from runtime_probe import send, wait, stage_client_modules


def fields(line):
    result = {}
    for key, value in re.findall(r"(\w+)=([^ ]+)", line):
        result[key] = (tuple(map(float, value.split(","))) if key == "pos"
                       else value if key in ("team", "mode", "phase") else int(value))
    return result


def run(args):
    if not __debug__:
        raise RuntimeError("Match verification requires assertions")
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError("Match evidence requires a fresh report directory")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.prefix, args.report)
    dedicated = args.engine / "bin/dk3ded"
    executable = hashlib.sha256(dedicated.read_bytes()).hexdigest()
    scenario = {"dm": (0, "e1dm1"), "ctf": (4, "e1ctf1"), "deathtag": (8, "e1dt1")}[args.mode]
    log = args.report / "server.log"
    samples = []
    result = {"identity": identity, "dedicated_sha256": executable, "mode": args.mode,
              "map": args.map or scenario[1], "setup": "Fresh map, normal bot starting inventory; no placements or grants.",
              "scope": "Natural bot movement, pickup, combat and respawn; one contested capture for objective modes. No human network or complete mode acceptance."}
    with tempfile.TemporaryDirectory(prefix="dk3-native-match-") as temporary:
        home = Path(temporary)
        stage_client_modules(args.prefix, home)
        settings = {"net_enabled": "0", "fs_basepath": str(args.engine / "share"),
                    "fs_homepath": str(home), "fs_homedatapath": str(home),
                    "fs_homestatepath": str(home / "state"), "com_basegame": "dk3",
                    "com_pipefile": "commands.fifo", "vm_game": "0", "dk3_runtime_probe": "2",
                    "g_gametype": str(scenario[0]), "g_spSkill": "3", "sv_maxclients": "8",
                    "bot_minplayers": str(args.bots), "developer": "1", "fraglimit": "0",
                    "capturelimit": "0", "timelimit": "0", "dk3_public": "0"}
        command = [str(dedicated)]
        for key, value in settings.items():
            command += ["+set", key, value]
        command += ["+map", result["map"]]
        with log.open("w") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            pipe = home / "dk3/commands.fifo"
            initial = {}
            injured = set()
            fired = set()
            equipped = set()
            moved = set()
            lives = {}
            participant_ids = set()
            respawned = set()
            carriers = set()
            try:
                wait(process, log, lambda text: pipe.exists() and "dk3 zig: isolated bootstrap" in text, 45)
                deadline = time.monotonic() + args.seconds
                setup = False
                while time.monotonic() < deadline:
                    offset = log.stat().st_size
                    send(pipe, "dk3_runtime_match")
                    text = wait(process, log, lambda text: "dk3 match complete:" in text[offset:]
                                or engine_failure(text[offset:]), 5)[offset:]
                    if failure := engine_failure(text):
                        raise RuntimeError(failure)
                    players = [fields(line) for line in text.splitlines() if line.startswith("dk3 match player:")]
                    objectives = [fields(line) for line in text.splitlines() if line.startswith("dk3 match objective:")]
                    now = int(re.search(r"dk3 match complete: now=(\d+)", text)[1])
                    samples.append({"now": now, "players": players, "objectives": objectives})
                    if len(players) != args.bots:
                        if setup:
                            raise RuntimeError("Match lost an admitted participant")
                        if len(samples) > 120:
                            raise RuntimeError(f"Bot admission incomplete: {players}")
                        continue
                    if not setup:
                        if any(p["bot"] != 1 or p["health"] <= 0 for p in players):
                            raise RuntimeError(f"Invalid initial participants: {players}")
                        if args.mode != "dm" and ({p["team"] for p in players} != {"red", "blue"}
                                                  or {o["team"] for o in objectives} != {"red", "blue"}):
                            raise RuntimeError("Both teams and both objective controllers are required")
                        initial = {p["slot"]: p for p in players}
                        setup = True
                    participant_ids.update(p["id"] for p in players)
                    for player in players:
                        slot = player["slot"]
                        if player["fire"] >= 0:
                            fired.add(slot)
                        if player["inventory"] != initial[slot]["inventory"] and player["inventory"] != 0:
                            equipped.add(slot)
                        if sum((a - b) ** 2 for a, b in zip(player["pos"], initial[slot]["pos"])) > 128 ** 2:
                            moved.add(slot)
                        if player["hurt"] > 0 and player["source"] in participant_ids and player["source"] != player["id"] and player["hit_weapon"] > 0:
                            injured.add(slot)
                        prior = lives.get(slot)
                        if prior and player["id"] != prior["id"] and player["deaths"] > prior["deaths"] and player["health"] > 0:
                            respawned.add(slot)
                        # Keep the preceding life until the new body is observed.
                        if prior is None or player["id"] != prior["id"]:
                            lives[slot] = player
                    carriers.update(o["carrier"] for o in objectives if o["phase"] == "carried" and o["carrier"] != 0)
                    captures = sum(p["captures"] for p in players)
                    if fired and injured and equipped and moved and respawned and (args.mode == "dm" or (carriers and captures)):
                        result.update(status="passed", evidence={"fired": sorted(fired), "injured": sorted(injured),
                                      "picked_up": sorted(equipped), "moved": sorted(moved), "respawned": sorted(respawned),
                                      "carriers": sorted(carriers), "captures": captures})
                        break
                    # This controls observation load only. Success always requires
                    # the authoritative events/state above, never elapsed sleep.
                    time.sleep(0.2)
                else:
                    raise TimeoutError(f"Natural match requirements not met: fired={fired}, injured={injured}, pickups={equipped}, moved={moved}, respawned={respawned}, carriers={carriers}")
                send(pipe, "quit")
                if process.wait(timeout=15) != 0:
                    raise RuntimeError("Native match shutdown failed")
            except Exception as error:
                result.update(status="failed", error=str(error))
                if process.poll() is None:
                    try:
                        offset = log.stat().st_size
                        send(pipe, "dk3_runtime_movers")
                        send(pipe, "dk3_runtime_route_controls")
                        diagnosis = wait(process, log, lambda text: "dk3 route controls complete" in text[offset:]
                                         or engine_failure(text[offset:]), 5)[offset:]
                        (args.report / "failed-route-diagnostics.log").write_text(diagnosis)
                    except Exception as unavailable:
                        result["diagnostic_error"] = str(unavailable)
                raise
            finally:
                (args.report / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
                (args.report / "result.json").write_text(json.dumps(result, indent=2) + "\n")
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--prefix", type=Path, default=Path("zig-out/native-dev"))
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--mode", choices=("dm", "ctf", "deathtag"), required=True)
    parser.add_argument("--map")
    parser.add_argument("--bots", type=int, choices=range(2, 9), default=4)
    parser.add_argument("--seconds", type=int, default=300)
    args = parser.parse_args()
    args.engine, args.prefix, args.report = args.engine.resolve(), args.prefix.resolve(), args.report.resolve()
    run(args)


if __name__ == "__main__":
    main()
