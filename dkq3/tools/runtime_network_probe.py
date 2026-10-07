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
import math
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
                settings = client_settings(args.engine, home, args.renderer)
                if getattr(args,'capture_size',None):
                    width,height=args.capture_size
                    settings.update(r_customwidth=str(width),r_customheight=str(height))
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

            def animated(client, label):
                frames = []
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    client.check()
                    offset = client.log.stat().st_size
                    client.issue("dk3_runtime_presentation")
                    text = wait(client.process, client.log, lambda text:
                                "dk3 weapon presentation:" in text[offset:], 3)[offset:]
                    line = next(line for line in text.splitlines() if line.startswith("dk3 weapon presentation:"))
                    row = dict(re.findall(r"(\w+)=([^ ]+)", line))
                    if row["phase"] == "fire":
                        frames.append(row)
                        if len({frame["frame"] for frame in frames}) > 1 and any(0 < float(frame["backlerp"]) < 1 for frame in frames):
                            result.setdefault("animations", {})[label] = frames
                            return frames[-1]
                raise TimeoutError(f"{label}: no advancing, interpolated first-person attack: {frames}")

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
            if args.held_weapons:
                result['scope'] = 'Controlled remote sword, rifle and pistol grips, ready and attack poses over UDP.'
                result['setup'] = 'Two real clients; server equipment and facing fixtures.'
                clients[1].issue('con_notifytime 0')
                offset = server.log.stat().st_size
                server.issue(f'dk3_runtime_face_target {initial[1]["id"]} 120')
                wait(server.process, server.log, lambda text: 'dk3 zig combat: fixture player=' in text[offset:], 10)
                state = until(lambda p: all(p[i]['cmd'] > initial[i]['cmd']+600 for i in range(2)), 'weapon fixture ingested')
                delta = [state[0]['pos'][i]-state[1]['pos'][i] for i in range(3)]
                yaw = math.degrees(math.atan2(delta[1], delta[0]))
                clients[1].issue(f'dk3_look {yaw} 6')
                clients[0].issue(f'dk3_look {yaw+135} 0')
                result['held_weapons'] = []
                for weapon in (8, 2, 21):
                    server.issue(f'dk3_runtime_equip {weapon}')
                    start = sample()[0]['cmd']
                    until(lambda p: p[0]['cmd'] > start+600, 'held weapon ready')
                    clients[1].capture(args.report, f'held-{weapon}-ready')
                    clients[0].issue('+attack')
                    try:
                        for frame in range(8):
                            clients[1].capture(args.report, f'held-{weapon}-attack-{frame:03}')
                    finally:
                        clients[0].issue('-attack')
                    result['held_weapons'].append(dict(weapon=weapon, state=sample()))
                result['status'] = 'passed'
                return
            if args.neural:
                result['scope'] += ' Controlled facing fixture and five skeletal appearance changes, rendered remotely over UDP.'
                result['neural'] = []
                clients[0].issue('con_notifytime 0')
                for appearance_index, (selection, appearance) in enumerate([('hiro/0', 0), ('mikiko/1', 4), ('superfly/2', 8), ('mishima/3', 42), ('usagi/7', 51)]):
                    if args.ragdoll_character and selection.split('/')[0] != args.ragdoll_character: continue
                    if args.isolate_appearances and appearance_index:
                        # Qualify each cosmetic rig from the same authored
                        # spawn. Respawn otherwise rotates through stair/ledge
                        # starts and changes the physical fixture per model.
                        server_offset = server.log.stat().st_size
                        client_offsets = [client.log.stat().st_size for client in clients]
                        server.issue('map_restart 0')
                        wait(server.process, server.log, lambda text: 'dk3 zig: isolated bootstrap' in text[server_offset:], 20)
                        for client, offset in zip(clients, client_offsets):
                            wait(client.process, client.log, lambda text: 'dk3 zig client: restoration applied' in text[offset:], 15)
                        restarted = until(lambda p: len(p) == 2 and all(row['health'] > 0 and row['mode'] == 'normal' for row in p.values()), 'appearance fixture restart')
                        result.setdefault('appearance_restarts', []).append(dict(selection=selection, state=restarted))
                    clients[1].issue(f'model {selection}')
                    state = until(lambda p: p[1]['appearance'] == appearance, f'authoritative {selection}')
                    offset = len(server.log.read_text())
                    server.issue(f'dk3_runtime_face_target {state[1]["id"]} 160')
                    wait(server.process, server.log, lambda text: 'dk3 zig combat: fixture player=' in text[offset:], 10)
                    # Let both clients ingest the fixture's new view offsets
                    # before dk3_look derives the next command orientation.
                    until(lambda p: all(p[i]['cmd'] > state[i]['cmd'] + 500 for i in range(2)),
                          'remote placement snapshot ingested')
                    until(lambda p: sum((a-b)**2 for a,b in zip(p[0]['pos'], p[1]['pos'])) < 260**2,
                          'clear remote character view')
                    state = sample()
                    delta = [state[1]['pos'][i]-state[0]['pos'][i] for i in range(3)]
                    clients[0].issue(f'dk3_look {math.degrees(math.atan2(delta[1], delta[0]))} {-math.degrees(math.atan2(delta[2]-14, math.hypot(*delta[:2])))}')
                    delta = [state[0]['pos'][i]-state[1]['pos'][i] for i in range(3)]
                    clients[1].issue(f'dk3_look {math.degrees(math.atan2(delta[1], delta[0]))} 0')
                    # Wait on processed commands before sampling the posed model.
                    until(lambda p: all(p[i]['cmd'] > state[i]['cmd'] + 300 for i in range(2)),
                          'posed remote character')
                    clients[0].capture(args.report, 'neural-' + selection.replace('/', '-'))
                    text = clients[0].log.read_text()
                    expected = 'player_' + selection.split('/')[0] if appearance >= 36 else 'm_' + selection.split('/')[0]
                    assert f'models/neural/{expected}.iqm' in text, expected
                    result['neural'].append(dict(selection=selection, state=sample()))
                    if args.neural_motion or args.neural_walk:
                        if args.neural_walk:
                            clients[0].issue('+speed')
                            clients[1].issue('+speed')
                        rows, images = [], []
                        clients[1].issue('+forward')
                        clients[0].issue('+back')
                        try:
                            for frame in range(20):
                                offset = clients[0].log.stat().st_size
                                name = f'{"walk" if args.neural_walk else "motion"}-{selection.replace("/", "-")}-{frame:03}'
                                source = clients[0].home / f'dk3/screenshots/{name}.jpg'
                                # Capture and diagnostics in the same render iteration.
                                # Separate server polling doubled each sample's latency
                                # and let the players reach a wall before a full cycle.
                                clients[0].issue(f'dk3_runtime_presentation; screenshotJPEG {name}')
                                text = wait(clients[0].process, clients[0].log,
                                            lambda text: 'dk3 presentation:' in text[offset:] and
                                            source.exists() and source.stat().st_size > 0, 5)[offset:]
                                for line in text.splitlines():
                                    if line.startswith('dk3 skeletal presentation: entity=1 '):
                                        row = dict(re.findall(r'(\w+)=([^ ]+)', line))
                                        rows.append(row)
                                shutil.copy2(source, args.report / source.name)
                                images.append(name+'.jpg')
                        finally:
                            clients[1].issue('-forward')
                            clients[0].issue('-back')
                            if args.neural_walk:
                                clients[0].issue('-speed')
                                clients[1].issue('-speed')
                        gait_frames = 24 if args.neural_walk else 15
                        running = [r for r in rows if int(r['rate']) == 30 and
                                   int(r['clip_last'])-int(r['clip_first']) == gait_frames-1 and
                                   int(r['now'])-int(r['started']) > 150]
                        assert len(running) >= 4, (selection, rows)
                        for row in running:
                            phase = (int(row['now'])-int(row['started']))*.03 % gait_frames
                            assert abs((int(row['frame'])-int(row['clip_first']))-((math.floor(phase)+1) % gait_frames)) < .01, row
                        assert max(int(r['now']) for r in running)-min(int(r['now']) for r in running) >= 300
                        result.setdefault('skeletal_motion', {})[selection] = dict(samples=rows, images=images)
                    if args.neural_combat:
                        server.issue('dk3_runtime_probe_health 10000')
                        rows, physical = [], []
                        victim_identity = state[1]['id']
                        def combat_capture(label):
                            offset = clients[0].log.stat().st_size
                            source = clients[0].home / f'dk3/screenshots/{label}.jpg'
                            clients[0].issue(f'dk3_runtime_presentation; screenshotJPEG {label}')
                            text = wait(clients[0].process, clients[0].log,
                                        lambda text: 'dk3 presentation:' in text[offset:] and source.exists() and source.stat().st_size > 0, 5)[offset:]
                            for line in text.splitlines():
                                # Respawn moves the retained corpse into an
                                # ordinary entity slot; its identity persists.
                                if line.startswith('dk3 ragdoll: '):
                                    physical_row = dict(label=label, **dict(re.findall(r'(\w+)=([^ ]+)', line)))
                                    if int(physical_row['identity']) == victim_identity: physical.append(physical_row)
                                if line.startswith('dk3 skeletal presentation: entity=1 '):
                                    rows.append(dict(label=label, **dict(re.findall(r'(\w+)=([^ ]+)', line))))
                            shutil.copy2(source, args.report / source.name)
                        slug = selection.replace('/', '-')
                        for moving in (False, True):
                            clients[1].issue('+attack')
                            if moving:
                                # Retrace the gait path instead of continuing
                                # into the wall reached by the preceding run.
                                clients[1].issue('+back')
                                clients[0].issue('+forward')
                            try:
                                for frame in range(10): combat_capture(f'attack-{slug}-{int(moving)}-{frame:03}')
                            finally:
                                clients[1].issue('-attack;-forward;-back')
                                clients[0].issue('-back;-forward')
                        layered = [r for r in rows if int(r['attack_count']) > 0 and int(r['frame']) >= int(r['attack_first']) and int(r['fired']) > 0]
                        assert layered, (selection, rows)
                        clients[1].issue('kill')
                        until(lambda p: p[1]['health'] <= 0, 'remote death')
                        # Keep respawn requested throughout playback, reproducing
                        # the original premature-respawn failure (including bots).
                        clients[1].issue('+attack')
                        for frame in range(90):
                            combat_capture(f'death-{slug}-{frame:03}')
                            if frame > 3 and rows[-1]['frame'] == rows[-1]['clip_last']: break
                        dead = [r for r in rows if r['label'].startswith('death-')]
                        assert len(set(r['frame'] for r in dead)) > 3, dead
                        assert any(r['frame'] == r['clip_last'] for r in dead), dead
                        observer = until(lambda p: p[1]['health'] > 0, 'respawn after complete death')[0]
                        clients[1].issue('-attack')
                        result.setdefault('neural_combat', {})[selection] = rows
                        if args.ragdolls:
                            if physical:
                                point = [float(x) for x in physical[-1]['pelvis'].split(',')]
                                delta = [point[i]-observer['pos'][i] for i in range(3)]
                                clients[0].issue(f'dk3_look {math.degrees(math.atan2(delta[1], delta[0]))} {-math.degrees(math.atan2(delta[2]-14, math.hypot(*delta[:2])))}')
                            for frame in range(120):
                                combat_capture(f'physical-{slug}-{frame:03}')
                                if physical and physical[-1]['sleep'] == '1': break
                            assert physical, (selection, 'no live skeletal physics')
                            birth = max(int(p['born']) for p in physical)
                            physical = [p for p in physical if int(p['born']) == birth]
                            assert max(int(p['contacts']) for p in physical) > 0, physical
                            assert all(int(p['bones']) > 0 for p in physical), physical
                            assert physical[-1]['sleep'] == '1', (selection, 'body did not settle', physical[-1])
                            first = [float(x) for x in physical[0]['pelvis'].split(',')]
                            last = [float(x) for x in physical[-1]['pelvis'].split(',')]
                            assert first[2]-last[2] > 6, (selection, first, last)
                            delta = [last[i]-observer['pos'][i] for i in range(3)]
                            clients[0].issue(f'dk3_look {math.degrees(math.atan2(delta[1], delta[0]))} {-math.degrees(math.atan2(delta[2]-14, math.hypot(*delta[:2])))}')
                            command = sample()[0]['cmd']
                            until(lambda p: p[0]['cmd'] > command + 150, 'corpse inspection angle applied')
                            clients[0].capture(args.report, f'settled-{slug}')
                            result.setdefault('ragdolls', {})[selection] = physical
                if args.ragdolls:
                    command = sample()[0]['cmd']
                    clients[0].issue('set cg_ragdolls 0')
                    until(lambda p: p[0]['cmd'] > command + 200, 'ragdoll disable applied')
                    offset = clients[0].log.stat().st_size
                    clients[0].issue('dk3_runtime_presentation')
                    text = wait(clients[0].process, clients[0].log, lambda text: 'dk3 presentation:' in text[offset:], 5)[offset:]
                    assert 'dk3 ragdoll:' not in text, text
                    clients[0].issue('set cg_ragdolls 1')
                    result['ragdoll_disable_clears_retained_bodies'] = True
                clients[0].issue('cg_shadows 0')
                clients[0].capture(args.report, 'neural-shadows-off')
                clients[0].issue('cg_shadows 1')
                clients[0].capture(args.report, 'neural-shadows-on')
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
                    animated(client, f"client-{index}-initial")
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
                # The normal respawn guard requires attack release before a new shot.
                # Wait on actual processed input, not merely on the spawn event.
                until(lambda p: p[index]["respawned"] == 0 and p[index]["cmd"] > living["cmd"], "processed attack release after respawn")
                client.issue("+attack")
                try:
                    fired = until(lambda p: p[index]["event"] > living["event"] and p[index]["fire"] > living["fire"], f"client {index} actual post-respawn shot")[index]
                    frame = animated(client, f"client-{index}-respawn")
                    assert int(frame["incarnation"]) > int(result["animations"][f"client-{index}-initial"][-1]["incarnation"])
                    result["respawn"][index]["fired"] = fired
                finally:
                    client.issue("-attack")


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
    parser.add_argument('--neural', action='store_true', help='Exercise all five skeletal remote appearances using controlled facing')
    parser.add_argument('--neural-motion', action='store_true', help='Capture and verify actual remote skeletal gait cadence')
    parser.add_argument('--neural-walk', action='store_true', help='Use ordinary slow-movement input and verify distinct remote walk clips')
    parser.add_argument('--neural-combat', action='store_true', help='Capture moving attacks and complete remote deaths for all five appearances')
    parser.add_argument('--held-weapons', action='store_true', help='Isolated remote sword/rifle/pistol grip capture with equipment fixtures')
    parser.add_argument('--ragdolls', action='store_true')
    parser.add_argument('--ragdoll-character', choices=('hiro', 'mikiko', 'superfly', 'mishima', 'usagi'))
    parser.add_argument('--isolate-appearances', action='store_true', help='restart the authored map between appearance fixtures to use the same spawn for each rig')
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--capture-size',type=int,nargs=2,metavar=('WIDTH','HEIGHT'),help='explicit software-rendered capture dimensions for both UDP clients')
    args = parser.parse_args()
    if args.capture_size and any(value<=0 for value in args.capture_size):parser.error('--capture-size dimensions must be positive')
    if args.ragdolls: args.neural_combat = True
    if args.neural_motion or args.neural_walk or args.neural_combat: args.neural = True
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args)


if __name__ == "__main__":
    main()
