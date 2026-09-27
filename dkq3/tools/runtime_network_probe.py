#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Two real native UDP clients; run under dkguard --headless, without --gpu.

Normal client commands only. This qualifies LAN connection/input/lifecycle, not
combat contact, authenticated Internet rooms or restored room identity.
"""
import argparse
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import re
import shutil
import socket
import subprocess
import tempfile
import time

from runtime_input import engine_failure, record_identity
from runtime_match_probe import fields
from runtime_probe import client_settings, send, stage_client_modules, wait


def reserve_ports(count):
    # Keep all reservations until every port has been selected. The engine then
    # binds them itself; startup/status checks reject a conflicting admission.
    with ExitStack() as stack:
        sockets = [stack.enter_context(socket.socket(socket.AF_INET, socket.SOCK_DGRAM))
                   for _ in range(count)]
        for stream in sockets:
            stream.bind(("127.0.0.1", 0))
        return [stream.getsockname()[1] for stream in sockets]


class Endpoint:
    def __init__(self, name, executable, settings, report, inputs, extra=()):
        self.name, self.inputs = name, inputs
        self.home = Path(settings["fs_homepath"])
        self.pipe = self.home / "dk3/commands.fifo"
        self.log = report / f"{name}.log"
        self.command = [str(executable)]
        for key, value in settings.items():
            self.command += ["+set", key, str(value)]
        self.command += extra
        # Com_ParseCommandLine reserves its first line before the first '+'.
        if len(settings) + sum(arg.startswith("+") for arg in extra) > 31:
            raise ValueError("Engine accepts at most 31 '+' startup commands; later commands would be discarded")
        self.output = self.log.open("w")
        self.process = subprocess.Popen(self.command, stdout=self.output, stderr=subprocess.STDOUT)
        self.inputs.append({"endpoint": name, "launch": self.command})

    def issue(self, command):
        self.inputs.append({"endpoint": self.name, "command": command})
        send(self.pipe, command)

    def check(self):
        text = self.log.read_text(errors="replace")
        # A requested disconnect is an expected lifecycle event; ERROR is not.
        errors = [line for line in text.splitlines() if line.startswith("ERROR:")]
        if errors or self.process.poll() is not None:
            raise RuntimeError(f"{self.name}: {errors or self.process.returncode}")

    def snapshot(self, offset=0):
        text = wait(self.process, self.log, lambda text:
                    "dk3 zig client: first snapshot applied" in text[offset:]
                    or engine_failure(text[offset:]), 45)[offset:]
        if failure := engine_failure(text):
            raise RuntimeError(failure)

    def capture(self, report, name):
        source = self.home / f"dk3/screenshots/{name}.jpg"
        self.issue(f"screenshotJPEG {name}")
        wait(self.process, self.log, lambda _: source.exists() and source.stat().st_size > 0, 10)
        shutil.copy2(source, report / source.name)

    def close(self):
        if self.process.poll() is None:
            try:
                self.issue("quit")
                self.process.wait(timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                self.process.terminate()
                try:
                    self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait()
        self.output.close()


def run(args):
    if not __debug__:
        raise RuntimeError("Network verification requires assertions")
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError("Network evidence requires a fresh report directory")
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.engine, args.report, require_installation=True)
    dedicated = args.engine / "bin/dk3ded"
    result = {"identity": identity, "dedicated_sha256": hashlib.sha256(dedicated.read_bytes()).hexdigest(),
              "map": "e1dm1", "setup": "Two real UDP clients, fresh DM, ordinary inventory, no bots/placements/grants.",
              "scope": "LAN admission, movement, fire events, commanded death/respawn, spectator/rejoin, disconnect/reconnect and map restart. No target contact or public room acceptance."}
    inputs, samples, endpoints = [], [], []
    ports = reserve_ports(3)
    result["ports"] = ports
    with tempfile.TemporaryDirectory(prefix="dk3-native-network-") as temporary:
        root = Path(temporary)
        try:
            server_home = root / "server"
            stage_client_modules(args.engine, server_home, installation=args.engine)
            settings = {"fs_basepath": str(args.engine / "share"), "fs_homepath": str(server_home),
                        "fs_homedatapath": str(server_home), "fs_homestatepath": str(server_home / "state"),
                        "com_basegame": "dk3", "com_pipefile": "commands.fifo", "vm_game": 0,
                        "dk3_runtime_probe": 2, "net_enabled": 1, "net_ip": "127.0.0.1",
                        "net_port": ports[0], "dedicated": 1, "g_gametype": 0, "sv_maxclients": 4,
                        "bot_minplayers": 0, "sv_pure": 0, "dk3_public": 0, "developer": 1,
                        "fraglimit": 0, "timelimit": 0, "g_forcerespawn": 0}
            server = Endpoint("server", dedicated, settings, args.report, inputs, ["+map", "e1dm1"])
            endpoints.append(server)
            wait(server.process, server.log, lambda text: server.pipe.exists()
                 and "dk3 zig: isolated bootstrap" in text, 45)

            def sample():
                for endpoint in endpoints:
                    endpoint.check()
                offset = server.log.stat().st_size
                server.issue("dk3_runtime_match")
                text = wait(server.process, server.log, lambda text:
                            "dk3 match complete:" in text[offset:], 5)[offset:]
                state = {"now": int(re.search(r"dk3 match complete: now=(\d+)", text)[1]),
                         "players": [fields(line) for line in text.splitlines()
                                     if line.startswith("dk3 match player:")]}
                samples.append(state)
                return {p["slot"]: p for p in state["players"]}

            def until(predicate, description, seconds=15):
                deadline, last = time.monotonic() + seconds, None
                while time.monotonic() < deadline:
                    last = sample()
                    if predicate(last):
                        return last
                raise TimeoutError(f"{description}: {last}")

            clients = []
            for index in range(2):
                home = root / f"client-{index}"
                stage_client_modules(args.engine, home, installation=args.engine)
                settings = client_settings(args.engine, home)
                settings.update(net_enabled=1, net_ip="127.0.0.1", net_port=ports[index + 1],
                                g_gametype=0, in_nograb=1, name=f"NativeLAN{index}",
                                cl_allowDownload=0, developer=1)
                client = Endpoint(f"client-{index}", args.engine / "bin/dk3", settings, args.report, inputs)
                endpoints.append(client)
                clients.append(client)
                wait(client.process, client.log, lambda text: client.pipe.exists()
                     and "native menus initialized" in text, 30)
                client.issue(f"connect 127.0.0.1:{ports[0]}")
                client.snapshot()
                until(lambda p: len(p) == index + 1 and p[index]["health"] > 0 and p[index]["bot"] == 0,
                      f"client {index} authoritative admission")

            initial = until(lambda p: len(p) == 2 and all(row["mode"] == "normal" for row in p.values()), "both clients active")
            offset = server.log.stat().st_size
            server.issue("status")
            status = wait(server.process, server.log, lambda text: all(
                re.search(rf"NativeLAN{index}\s+\^7127\.0\.0\.1\s", text[offset:]) for index in range(2)), 5)[offset:]
            for index, endpoint in enumerate(endpoints):
                if f"Opening IP socket: 127.0.0.1:{ports[index]}" not in endpoint.log.read_text():
                    raise RuntimeError(f"Unexpected UDP binding for {endpoint.name}")
            (args.report / "admitted-status.log").write_text(status)
            result["initial"] = initial
            result["movement"] = {}
            for index, client in enumerate(clients):
                start = sample()[index]
                # Try ordinary orthogonal headings if the authored spawn faces a wall.
                for yaw in (0, 90, 180, 270):
                    client.issue(f"dk3_look {yaw} 0")
                    client.issue("+forward")
                    try:
                        moved = until(lambda p: p[index]["health"] > 0 and sum(
                            (a - b) ** 2 for a, b in zip(p[index]["pos"], start["pos"])) > 48 ** 2,
                            f"client {index} movement", 2)[index]
                        result["movement"][index] = moved
                        break
                    except TimeoutError:
                        pass
                    finally:
                        client.issue("-forward")
                else:
                    raise RuntimeError(f"Client {index} failed ordinary movement")
                prior = sample()[index]
                client.issue("+attack")
                try:
                    result.setdefault("fire", {})[index] = until(lambda p:
                        p[index]["fire"] > prior["fire"] and p[index]["event"] != prior["event"],
                        f"client {index} authoritative attack")[index]
                finally:
                    client.issue("-attack")
                client.capture(args.report, f"client-{index}-playing")

            for index, client in enumerate(clients):
                prior = sample()[index]
                client.issue("kill")
                dead = until(lambda p: p[index]["mode"] == "dead" and p[index]["health"] <= 0,
                             f"client {index} death")[index]
                client.issue("+attack")
                try:
                    living = until(lambda p: p[index]["id"] != prior["id"] and p[index]["health"] > 0
                                   and p[index]["deaths"] > prior["deaths"], f"client {index} respawn")[index]
                finally:
                    client.issue("-attack")
                result.setdefault("respawn", {})[index] = {"dead": dead, "living": living}

            clients[1].issue("team spectator")
            result["spectator"] = until(lambda p: p[1]["team"] == "spectator"
                                         and p[1]["mode"] == "spectator", "spectator transition")[1]
            # Native LAN retains the engine's one-second reliable text-command
            # throttle. Wait for actual server time after the acknowledged team
            # change; do not disable protection or assume a wall-clock delay.
            reliable_at = samples[-1]["now"] + 1000
            until(lambda _: samples[-1]["now"] >= reliable_at, "reliable command throttle elapsed")
            clients[1].issue("team free")
            result["rejoined"] = until(lambda p: p[1]["team"] == "free" and p[1]["mode"] == "normal"
                                        and p[1]["health"] > 0, "return from spectator")[1]
            before = sample()
            clients[1].issue("disconnect")
            result["disconnected"] = until(lambda p: set(p) == {0}, "server disconnect acknowledgement")
            offset = clients[1].log.stat().st_size
            clients[1].issue("reconnect")
            clients[1].snapshot(offset)
            result["reconnected"] = until(lambda p: len(p) == 2 and p[1]["id"] != before[1]["id"]
                                            and p[1]["health"] > 0, "LAN reconnect")
            offsets = [client.log.stat().st_size for client in clients]
            server_offset = server.log.stat().st_size
            server.issue("map_restart 0")
            text = wait(server.process, server.log, lambda text:
                        "dk3 zig: isolated bootstrap" in text[server_offset:]
                        or engine_failure(text[server_offset:]), 20)[server_offset:]
            if failure := engine_failure(text):
                raise RuntimeError(failure)
            for client, offset in zip(clients, offsets):
                text = wait(client.process, client.log, lambda text:
                            "dk3 zig client: restoration applied" in text[offset:]
                            or engine_failure(text[offset:]), 15)[offset:]
                if failure := engine_failure(text):
                    raise RuntimeError(failure)
            result["restarted"] = until(lambda p: len(p) == 2 and all(row["health"] > 0
                                          and row["mode"] == "normal" for row in p.values()), "restart admission")
            for index, client in enumerate(clients):
                client.capture(args.report, f"client-{index}-restarted")
            result["status"] = "passed"
        except Exception as error:
            result.update(status="failed", error=str(error))
            raise
        finally:
            for endpoint in reversed(endpoints):
                endpoint.close()
            (args.report / "inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
            (args.report / "samples.json").write_text(json.dumps(samples, indent=2) + "\n")
            (args.report / "result.json").write_text(json.dumps(result, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args)


if __name__ == "__main__":
    main()
