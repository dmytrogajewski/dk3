#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Guarded skill pickups, saved lift attachments and real UDP corpse combat.

Diagnostic placement/equipment and locally spawned pickups are recorded. Pickup
contact, button use, attacks and respawn use ordinary client input.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import tempfile
import time

from runtime_bugfix_probe import run as run_single
from runtime_input import record_identity
from runtime_match_probe import fields
from runtime_network_probe import Endpoint, reserve_ports
from runtime_probe import client_settings, stage_client_modules, wait
from runtime_saved_mover_probe import records


def vector(value):
    return list(map(float, value.split(',')))


def attributes(text, prefix):
    lines = [line for line in text.splitlines() if line.startswith(prefix)]
    assert lines, (prefix, text[-2000:])
    row = dict(re.findall(r'(\w+)=([^ ]+)', lines[-1]))
    return {key: list(map(int, row[key].split(','))) for key in ('base', 'effective')}


def single(driver, report, capture):
    driver.until(lambda s: s['mode'] == 'normal', seconds=120)
    driver.issue('dk3_runtime_probe_health 10000')
    if args.scenario == 'saved':
        driver.load('reported')
        driver.until(lambda s: s['map'] == 'e1m3b' and s['mode'] == 'normal', seconds=120)
        driver.issue('dk3_runtime_probe_health 10000')
        # Saved t478 lift and its authored parenttarget button, near the autosave.
        driver.issue('dk3_runtime_place -1420 1350 -28')
        driver.elapsed(500)
        state = driver.observe()
        centre = [-1364, 1398, 4]
        delta = [centre[i] - state['pos'][i] - (22 if i == 2 else 0) for i in range(3)]
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        capture('lift-button-before')
        driver.issue('use')
        frames = []
        for index in range(40):
            text = driver.diagnostics('dk3_runtime_presentation', 'dk3 presentation:')
            for line in text.splitlines():
                if line.startswith('dk3 attachment view: ') and 'id=117440686 ' in line:
                    row = dict(re.findall(r'(\w+)=([^ ]+)', line))
                    frames.append(row)
            if index == 8:
                capture('lift-button-moving')
        assert len(frames) >= 20, frames
        positions = [vector(row['pos']) for row in frames]
        offsets = [vector(row['relative']) for row in frames]
        motion = max(p[2] for p in positions) - min(p[2] for p in positions)
        assert motion > 30, ('Lift did not travel through ordinary use', frames)
        ranges = [max(p[i] for p in offsets) - min(p[i] for p in offsets) for i in range(3)]
        assert ranges[0] < 0.002 and ranges[2] < 0.002, ranges
        # Y is the button's own press/return travel, independent of the lift.
        assert ranges[1] <= 4.1, ranges
        driver.issue('dk3_runtime_place -1997 1684 -167')
        driver.elapsed(500)
        item_frames = []
        for _ in range(20):
            text = driver.diagnostics('dk3_runtime_presentation', 'dk3 presentation:')
            item_frames.extend(dict(re.findall(r'(\w+)=([^ ]+)', line)) for line in text.splitlines()
                               if line.startswith('dk3 item view: '))
        groups = {}
        for row in item_frames:
            if row['ground'] != '2047':
                groups.setdefault(row['id'], []).append(vector(row['pos']))
        stable = {identity: max(math.dist(points[0], p) for p in points)
                  for identity, points in groups.items() if len(points) >= 10}
        assert stable and max(stable.values()) < 0.002, stable
        capture('health-packs-stationary')
        saved = driver.save('physics_repaired')
        shutil.copy2(saved, report / saved.name)
        driver.load('physics_repaired')
        capture('saved-lift-reloaded')
        assert hashlib.sha256(args.save.read_bytes()).hexdigest() == args.source_hash
        return dict(lift=frames, lift_travel=motion, attachment_ranges=ranges, stationary_items=stable,
                    original_save_sha256=args.source_hash)

    origin = driver.until(lambda s: s['ground'] != 2047)['pos']
    driver.aim(0, 0)
    before = attributes(driver.diagnostics('dk3_runtime_character', 'zig character time='), 'zig character attributes ')
    acquired = []
    for index, name in enumerate(('power', 'attack', 'speed', 'acro', 'vita')):
        driver.stop_forward()
        driver.issue('dk3_runtime_place ' + ' '.join(map(str, origin)))
        driver.elapsed(200)
        driver.issue('dk3_runtime_spawn_item item_' + name + '_boost')
        driver.issue('+forward')
        deadline = time.monotonic() + 5
        try:
            while time.monotonic() < deadline:
                actual = attributes(driver.diagnostics('dk3_runtime_character', 'zig character time='), 'zig character attributes ')
                if actual['effective'][index] == 5:
                    break
            else:
                raise AssertionError(('Ordinary pickup contact failed', name, actual))
        finally:
            driver.issue('-forward')
        driver.elapsed(200)
        viewed = attributes(driver.diagnostics('dk3_runtime_presentation', 'dk3 presentation:'), 'dk3 character view: ')
        assert viewed['effective'][index] == 5 and viewed['base'] == before['base'], viewed
        acquired.append(dict(attribute=name, server=actual, client=viewed))
    capture('full-skill-bars')
    saved = driver.save('full_boosts')
    shutil.copy2(saved, report / saved.name)
    driver.load('full_boosts')
    restored = attributes(driver.diagnostics('dk3_runtime_character', 'zig character time='), 'zig character attributes ')
    assert restored['effective'] == [5] * 5 and restored['base'] == before['base'], restored
    driver.elapsed(31000)
    expired = attributes(driver.diagnostics('dk3_runtime_presentation', 'dk3 presentation:'), 'dk3 character view: ')
    assert expired['effective'] == before['base'], expired
    return dict(before=before, pickups=acquired, restored=restored, expired=expired)


def network():
    args.report.mkdir(parents=True, exist_ok=False)
    identity = record_identity(args.engine, args.engine, args.report, require_installation=True)
    inputs, endpoints, samples = [], [], []
    result = dict(identity=identity, setup='Two real UDP clients; diagnostic facing/equipment and pickup spawn; ordinary contact/attack/respawn.')
    ports = reserve_ports(3)
    with tempfile.TemporaryDirectory(prefix='dk3-physics-repair-') as temporary:
        root = Path(temporary)
        try:
            home = root / 'server'
            stage_client_modules(args.engine, home, installation=args.engine)
            settings = dict(fs_basepath=str(args.engine / 'share'), fs_homepath=str(home),
                            fs_homedatapath=str(home), fs_homestatepath=str(home / 'state'),
                            com_basegame='dk3', com_pipefile='commands.fifo', vm_game=0,
                            dk3_runtime_probe=2, net_enabled=1, net_ip='127.0.0.1', net_port=ports[0],
                            dedicated=1, g_gametype=0, sv_maxclients=4, bot_minplayers=0, sv_pure=0,
                            dk3_public=0, developer=1, fraglimit=0, timelimit=0, g_forcerespawn=0)
            server = Endpoint('server', args.engine / 'bin/dk3ded', settings, args.report, inputs, ['+map', 'e1dm1'])
            endpoints.append(server)
            wait(server.process, server.log, lambda text: server.pipe.exists() and 'isolated bootstrap' in text, 45)

            def diagnostic(endpoint, command, marker):
                offset = endpoint.log.stat().st_size
                endpoint.issue(command)
                return wait(endpoint.process, endpoint.log, lambda text: marker in text[offset:], 10)[offset:]

            def sample():
                text = diagnostic(server, 'dk3_runtime_match', 'dk3 match complete:')
                players = {row['slot']: row for row in (fields(line) for line in text.splitlines()
                           if line.startswith('dk3 match player:'))}
                samples.append(players)
                return players

            def until(predicate, description, seconds=12):
                deadline = time.monotonic() + seconds
                last = None
                while time.monotonic() < deadline:
                    last = sample()
                    if predicate(last):
                        return last
                raise TimeoutError((description, last))

            clients = []
            for index in range(2):
                home = root / f'client-{index}'
                stage_client_modules(args.engine, home, installation=args.engine)
                settings = client_settings(args.engine, home, args.renderer)
                settings.update(net_enabled=1, net_ip='127.0.0.1', net_port=ports[index + 1],
                                g_gametype=0, in_nograb=1, name=f'Physics{index}', cl_allowDownload=0, developer=1)
                client = Endpoint(f'client-{index}', args.engine / 'bin/dk3', settings, args.report, inputs)
                endpoints.append(client)
                clients.append(client)
                wait(client.process, client.log, lambda text: client.pipe.exists() and 'native menus initialized' in text, 30)
                client.issue(f'connect 127.0.0.1:{ports[0]}')
                client.snapshot()
                until(lambda p: index in p and p[index]['health'] > 0, 'Client admitted')

            for selection in ('hiro/0', 'mikiko/0', 'superfly/0', 'mishima/0', 'usagi/0'):
                clients[0].issue('model ' + selection)
                state = sample()
                until(lambda p: p[0]['cmd'] > state[0]['cmd'] + 300, 'Appearance applied')
                actual = attributes(diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:'), 'dk3 character view: ')
                assert actual['base'] == actual['effective'] == [0] * 5, (selection, actual)
                result.setdefault('starting_skills', {})[selection] = actual
            clients[0].issue('model hiro/0')
            # The fixture places player 0 in a clear lane, using real collision.
            state = sample()
            diagnostic(server, f'dk3_runtime_face_target {state[1]["id"]} 160', 'fixture player=')
            state = until(lambda p: p[0]['cmd'] > state[0]['cmd'] + 500, 'Fixture view ingested')

            def aim_at(point, vertical=0):
                player = sample()[0]
                delta = [point[i] - player['pos'][i] - (22 if i == 2 else 0) for i in range(3)]
                delta[2] += vertical
                clients[0].issue(f'dk3_look {math.degrees(math.atan2(delta[1], delta[0]))} {-math.degrees(math.atan2(delta[2], math.hypot(*delta[:2])))}')
                until(lambda p: p[0]['cmd'] > player['cmd'] + 150, 'Aim processed')

            # Actual world pickup in DM, with no grant to Character.
            diagnostic(server, 'dk3_runtime_spawn_item item_speed_boost', 'dk3 fixture item:')
            clients[0].issue('+forward')
            try:
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    actual = attributes(diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:'), 'dk3 character view: ')
                    if actual['effective'][2] == 5:
                        break
                else:
                    raise AssertionError(('DM pickup not acquired', actual))
            finally:
                clients[0].issue('-forward')
            assert actual['base'] == [0] * 5, actual
            result['dm_boost'] = actual
            clients[0].capture(args.report, 'dm-full-speed')

            server.issue('dk3_runtime_equip 21')
            until(lambda p: p[0]['weapon'] == 21, 'Glock equipped')
            victim = sample()[1]['id']
            diagnostic(server, f'dk3_runtime_probe_health 18 {victim}', 'health=18')
            diagnostic(server, 'dk3_runtime_probe_health 10000', 'health=10000')
            aim_at(sample()[1]['pos'])

            def fire(predicate, description):
                initial = sample()[0]
                clients[0].issue('+attack')
                try:
                    until(lambda p: p[0]['event'] > initial['event'], 'Weapon actually fired')
                finally:
                    clients[0].issue('-attack')
                return until(predicate, description)

            dead = fire(lambda p: p[1]['health'] <= 0, 'Glock killed player')
            assert dead[1]['health'] > -40, dead
            physical = []
            for index in range(70):
                text = diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:')
                rows = [dict(re.findall(r'(\w+)=([^ ]+)', line)) for line in text.splitlines()
                        if line.startswith('dk3 ragdoll: ') and f'identity={victim} ' in line]
                physical.extend(rows)
                if index in (0, 2, 5, 10):
                    clients[0].capture(args.report, f'fall-{index:02}')
                if rows and rows[-1]['sleep'] == '1':
                    break
            assert physical and physical[-1]['sleep'] == '1', physical[-1:] or 'No ragdoll'
            assert vector(physical[0]['pelvis'])[2] - vector(physical[-1]['pelvis'])[2] > 6
            result['fall'] = physical
            clients[1].issue('+attack')
            until(lambda p: p[1]['health'] > 0 and p[1]['id'] != victim, 'Respawn completed')
            clients[1].issue('-attack')
            corpses = diagnostic(server, 'dk3_runtime_corpses', 'dk3 corpses complete')
            corpse = next(dict(re.findall(r'(\w+)=([^ ]+)', line)) for line in corpses.splitlines()
                          if line.startswith('dk3 corpse: ') and f'id={victim} ' in line)
            assert corpse['retained'] == '1' and int(corpse['slot']) >= 64, corpse
            score = sample()[0]['score']
            aim_at(vector(corpse['pos']), -16)
            previous = sample()[0]
            clients[0].issue('+attack')
            until(lambda p: p[0]['event'] > previous['event'], 'Corpse shot fired')
            clients[0].issue('-attack')
            reacted = None
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                text = diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:')
                rows = [dict(re.findall(r'(\w+)=([^ ]+)', line)) for line in text.splitlines()
                        if line.startswith('dk3 ragdoll: ') and f'identity={victim} ' in line]
                if rows and int(rows[-1]['hits']) > 0:
                    reacted = rows[-1]
                    break
            assert reacted and reacted['sleep'] == '0', reacted
            assert sample()[0]['score'] == score, 'Corpse hit awarded another kill'
            response = [reacted]
            for _ in range(8):
                text = diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:')
                response.extend(dict(re.findall(r'(\w+)=([^ ]+)', line)) for line in text.splitlines()
                                if line.startswith('dk3 ragdoll: ') and f'identity={victim} ' in line)
            displacement = max(math.dist(vector(physical[-1]['pelvis']), vector(row['pelvis'])) for row in response)
            # Small handgun impulses can be arrested by floor friction; require
            # actual motion above the 0.01-unit diagnostic resolution, not a
            # prescribed metre-scale translation for every weapon.
            assert displacement > 0.1, ('Corpse woke without moving', response)
            result['post_respawn_hit'] = dict(frames=response, displacement=displacement)
            clients[0].capture(args.report, 'corpse-hit-reacts')
            server.issue('dk3_runtime_equip 5')
            until(lambda p: p[0]['weapon'] == 5, 'Sidewinder equipped')
            state = sample()
            until(lambda p: p[0]['cmd'] > state[0]['cmd'] + 500, 'Sidewinder raised')
            clients[0].issue('+attack')
            until(lambda p: p[0]['event'] > state[0]['event'], 'Sidewinder actually fired')
            clients[0].issue('-attack')
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                text = diagnostic(server, 'dk3_runtime_corpses', 'dk3 corpses complete')
                if re.search(rf'dk3 corpse: id={victim} .*gibbed=1', text):
                    break
            else:
                raise AssertionError(('Powerful corpse shot did not fragment', text))
            displayed = diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:')
            assert f'identity={victim} ' not in '\n'.join(line for line in displayed.splitlines() if line.startswith('dk3 ragdoll: '))
            assert re.search(r'dk3 presentation: .*gibs=[1-9]', displayed), displayed[-2000:]
            assert sample()[0]['score'] == score
            clients[0].capture(args.report, 'sidewinder-meat-fragments')
            result['gibbed_corpse'] = text
            # A living player also fragments on a powerful lethal weapon hit.
            state = sample()
            diagnostic(server, f'dk3_runtime_face_target {state[1]["id"]} 160', 'fixture player=')
            diagnostic(server, f'dk3_runtime_probe_health 30 {state[1]["id"]}', 'health=30')
            aim_at(sample()[1]['pos'])
            state = sample()
            until(lambda p: p[0]['cmd'] > state[0]['cmd'] + 500, 'Sidewinder ready again')
            living_id = sample()[1]['id']
            initial_score = sample()[0]['score']
            fire(lambda p: p[1]['health'] <= 0, 'Powerful living-player death')
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                text = diagnostic(server, 'dk3_runtime_corpses', 'dk3 corpses complete')
                if re.search(rf'dk3 corpse: id={living_id} .*gibbed=1', text):
                    break
            else:
                raise AssertionError(('Powerful living-player death did not fragment', text))
            assert sample()[0]['score'] == initial_score + 1
            clients[0].capture(args.report, 'powerful-player-death-fragments')
            result['powerful_player_death'] = text
            state = sample()
            until(lambda p: p[0]['cmd'] > state[0]['cmd'] + 31000, 'Boost expired', seconds=40)
            expired = attributes(diagnostic(clients[0], 'dk3_runtime_presentation', 'dk3 presentation:'), 'dk3 character view: ')
            assert expired['effective'] == [0] * 5, expired
            result['dm_boost_expired'] = expired
            result['status'] = 'passed'
        finally:
            for endpoint in reversed(endpoints):
                endpoint.close()
            (args.report / 'inputs.json').write_text(json.dumps(inputs, indent=2))
            (args.report / 'samples.json').write_text(json.dumps(samples, indent=2))
            (args.report / 'result.json').write_text(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--scenario', choices=('skills', 'saved', 'network'), required=True)
    parser.add_argument('--save', type=Path)
    parser.add_argument('--renderer', default='opengl2')
    args = parser.parse_args()
    assert __debug__
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    if args.scenario == 'network':
        network()
    else:
        args.start_map = 'e1m3b' if args.scenario == 'saved' else 'e1m1a'
        args.developer = True
        def setup(home, report):
            if args.save:
                args.source_hash = hashlib.sha256(args.save.read_bytes()).hexdigest()
                directory = home / 'state/dk3/saves'
                directory.mkdir(parents=True, exist_ok=True)
                shutil.copy2(args.save, directory / 'reported.sav')
                (report / 'source.json').write_text(json.dumps(dict(path=str(args.save), sha256=args.source_hash)))
        run_single(args, single, setup)
