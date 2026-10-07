#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Saved button travel and frame-complete lift presentation in isolated profiles.

Invoke through dkguard --headless. Placement is a diagnostic fixture; button
activation uses ordinary use, and platform activation uses actual rider contact.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import struct
import time

from runtime_bugfix_probe import run
from runtime_probe import wait


def records(data):
    assert data[:8] == b'DK3SAVE\0'
    offset = 24
    while offset < len(data):
        size, identity, count, length, _ = struct.unpack_from('<IIHBB', data, offset)
        name = data[offset + 12:offset + 12 + length].decode()
        cursor, fields = offset + 12 + length, {}
        for _ in range(count):
            kind, length, _, count = struct.unpack_from('<BBHI', data, cursor)
            key = data[cursor + 8:cursor + 8 + length].decode()
            end = cursor + 8 + length + count * (4 if kind in (1, 2) else 1)
            fields[key] = data[cursor + 8 + length:end]
            cursor = end
        assert cursor == offset + size
        yield name, identity, fields
        offset += size


def saved_world(path):
    rows, map_name = {}, None
    for name, identity, fields in records(path.read_bytes()):
        if name == 'campaign':
            map_name = fields['map'].decode()
        if name == 'native_entity' and 'mover' in fields:
            rows[identity] = {k: json.loads(fields[k]) for k in ('map_object', 'mover', 'body', 'transform')}
    return map_name, rows


def movers(driver):
    rows = {}
    for identity, cls, state, pos, end in re.findall(
            r'zig mover id=(\d+).*class=(\S+).*state=(\S+) pos=([\d.,-]+) end=([\d.,-]+)',
            driver.diagnostics('dk3_runtime_movers', 'zig mover id=')):
        rows[int(identity)] = dict(cls=cls, state=state, pos=list(map(float, pos.split(','))), end=list(map(float, end.split(','))))
    return rows


def authored(row):
    obj, body = row['map_object'], row['body']
    props = {p['key']: p['value'] for p in obj['properties']}
    yaw = float(props.get('angle', 0))
    angles = list(map(float, props.get('angles', f'0 {yaw} 0').split()))
    pitch, yaw = map(math.radians, angles[:2])
    direction = [0, 0, 1] if props.get('angle') == '-1' else [0, 0, -1] if props.get('angle') == '-2' else [math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch)]
    size = [b - a - 2 for a, b in zip(body['mins'], body['maxs'])]
    distance = sum(abs(a) * b for a, b in zip(direction, size)) - float(props.get('lip', 4))
    return direction, [a * distance for a in direction]


def setup(home, report):
    if args.save:
        directory = home / 'state/dk3/saves'
        directory.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.save, directory / 'reported.sav')
        (report / 'source.json').write_text(json.dumps(dict(path=str(args.save), sha256=args.source_hash)))


def lift_frames(text):
    frames = []
    for line in text.splitlines():
        if line.startswith('dk3 mover view:'):
            fields = {k: float(v) for k, v in re.findall(r'(\w+)=([-\d.]+)', line)}
            if not frames or fields['now'] != frames[-1]['now']:
                frames.append(fields)
    return frames


def lift_result(frames, ground):
    riding = [f for f in frames if f['ground'] == ground and f['authoritative_ground'] == ground]
    assert len(riding) > 100, 'Missing frame-complete rider evidence'
    gaps = [f['feet'] - f['brush'] for f in riding]
    camera_gaps = [f['camera'] - f['brush'] for f in riding]
    deltas = [b['brush'] - a['brush'] for a, b in zip(riding, riding[1:])]
    return dict(frames=len(frames), riding=len(riding), gap_range=max(gaps) - min(gaps),
                camera_gap_range=max(camera_gaps) - min(camera_gaps),
                up_frames=sum(d > 0.01 for d in deltas), down_frames=sum(d < -0.01 for d in deltas),
                clock_before_snapshot=sum(f['now'] < f['snapshot'] for f in riding),
                lost_ground=sum(f['authoritative_ground'] == ground and f['ground'] != ground for f in frames))


def exercise(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 60)
    result = {}
    if args.save:
        driver.load('reported')
        wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 60)
        driver.until(lambda s: s['map'] == args.start_map and s['mode'] == 'normal', seconds=120)
        live = movers(driver)
        checks = []
        for identity, row in args.saved.items():
            if row['map_object']['classname'] != 'func_button':
                continue
            _, delta = authored(row)
            expected = [a + b for a, b in zip(row['mover']['closed'], delta)]
            assert identity in live, f'Lost saved button {identity}'
            checks.append(dict(id=identity, expected=expected, actual=live[identity]['end'],
                               matches=math.dist(expected, live[identity]['end']) < 0.11))
        result['travel'] = checks
        assert checks
        assert any(not row['matches'] for row in checks) if args.expect_old else all(row['matches'] for row in checks)
        # Default e1m3a flush panel 101 has permanent wait and was two units
        # behind its wall in the old save; e1m3b uses its corresponding panel.
        identity = next(i for i, row in args.saved.items() if i & 0xffffff == args.button)
        row = args.saved[identity]
        direction, _ = authored(row)
        centre = [(a + b) / 2 for a, b in zip(row['body']['mins'], row['body']['maxs'])]
        point = [a - b * 28 for a, b in zip(centre, direction)]
        point[2] -= 22
        driver.issue('dk3_runtime_place ' + ' '.join(map(str, point)))
        driver.elapsed(300)
        state = driver.observe()
        delta = [centre[i] - state['pos'][i] - (22 if i == 2 else 0) for i in range(3)]
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        capture('button-before')
        before = len(driver.text())
        driver.issue('set s_show 2')
        driver.issue('use')
        pressed = None
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            pressed = movers(driver)[identity]
            if pressed['state'] == 'open':
                break
        assert pressed['state'] == 'open', 'Ordinary use did not press the panel'
        # Some panels start an authored remote camera. Skip the scene through
        # normal input before judging the panel from the original viewpoint.
        driver.issue('cin_skip')
        driver.until(lambda s: s['mode'] == 'normal' and not s['cinematic'], seconds=20, description='panel camera returned')
        capture('button-pressed')
        driver.elapsed(300)
        driver.issue('set s_show 0')
        text = driver.text()[before:]
        sound = next(p['value'] for p in row['map_object']['properties'] if p['key'] == 'sound_use').replace('\\', '/')
        audible = any(max(int(a), int(b)) > 0 and sound in name for a, b, name in re.findall(r'^\s*(\d+) (\d+) (\S+)$', text, re.M))
        mixer_available = 's_show is cheat protected' not in text
        result['button'] = dict(id=identity, pressed=pressed, sound=sound, audible=audible if mixer_available else None,
                                mixer_available=mixer_available, sound_dispatched='snapshot sound dispatched' in text)
        if args.expect_old and mixer_available:
            assert not audible
        elif args.audible:
            assert mixer_available, 'Save restoration clears cheats, disabling s_show channel inspection'
            assert audible, 'No audible button channel at the listener'
        if not args.expect_old:
            saved = driver.save('repaired')
            shutil.copy2(saved, report / saved.name)
            _, saved_rows = saved_world(saved)
            assert saved_rows[identity]['mover']['use_sound'] > 0
            result['button']['saved_sound_index'] = saved_rows[identity]['mover']['use_sound']
            driver.load('repaired')
            again = movers(driver)[identity]
            assert again['end'] == pressed['end']
            if row['mover']['wait_ms'] < 0:
                assert again['state'] == 'open'
            capture('button-reloaded')
        assert hashlib.sha256(args.save.read_bytes()).hexdigest() == args.source_hash
    if args.lift:
        if not args.save:
            driver.issue('dk3_runtime_probe_health 10000')
            driver.until(lambda s: s['health'] == 10000 and s['mode'] == 'normal', description='living fresh lift observation fixture')
        driver.issue('set com_maxfps 85')
        driver.issue('set cg_debugMover 1')
        before = len(driver.text())
        driver.issue('dk3_runtime_place 1608 448 -28')
        driver.aim(90, 15)
        driver.elapsed(9000)
        driver.issue('set cg_debugMover 0')
        text = driver.text()[before:]
        frames = lift_frames(text)
        (report / 'lift-frames.json').write_text(json.dumps(frames, indent=2))
        result['lift'] = lift_result(frames, 71)
        assert result['lift']['up_frames'] > 10
        # Living rider contact renews this platform's upper dwell. The train
        # scenario supplies an ordinary-use ascent and descent with a rider.
        assert result['lift']['gap_range'] < 0.25 and result['lift']['camera_gap_range'] < 0.25 and result['lift']['lost_ground'] == 0, result['lift']
        assert driver.observe()['mode'] == 'normal', 'Combat killed the lift observation fixture'
        capture('lift-riding')
    if args.big_lift:
        driver.issue('set com_maxfps 85')
        # Clear the raised button's hull before landing on the deck. Keep the
        # living rider observable through the nearby Inmater's ordinary attacks.
        driver.issue('dk3_runtime_probe_health 10000')
        driver.until(lambda s: s['health'] == 10000 and s['mode'] == 'normal', description='living lift observation fixture')
        driver.issue('dk3_runtime_place 870 -484 -858')
        state = driver.until(lambda s: s['ground'] == 65, description='standing on bigplat')
        delta = [832 - state['pos'][0], -464 - state['pos'][1], -852 - state['pos'][2] - 22]
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        driver.issue('set cg_debugMover 1')
        before = len(driver.text())
        driver.issue('use')
        driver.elapsed(33000)
        driver.issue('set cg_debugMover 0')
        frames = lift_frames(driver.text()[before:])
        (report / 'big-lift-frames.json').write_text(json.dumps(frames, indent=2))
        result['big_lift'] = lift_result(frames, 65)
        assert result['big_lift']['up_frames'] > 100 and result['big_lift']['down_frames'] > 100, result['big_lift']
        assert result['big_lift']['gap_range'] < 0.25 and result['big_lift']['camera_gap_range'] < 0.25 and result['big_lift']['lost_ground'] == 0, result['big_lift']
        assert driver.observe()['mode'] == 'normal', 'Combat killed the large lift observation fixture'
        capture('big-lift-returned')
    result['scope'] = 'Ordinary panel use, restored sound binding and saved used latch when a copied native save is supplied. Mixer inspection is explicitly unavailable when normal load disables s_show. Diagnostic player placement; elevated health for fresh and large lift observation amid combat. Per-rendered-frame camera/deck comparison on rider-activated platform/train. No original saves changed; not campaign or hardware qualification.'
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--save', type=Path)
    parser.add_argument('--button', type=int, default=101)
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--expect-old', action='store_true')
    parser.add_argument('--audible', action='store_true', help='Require a nonzero mixer channel; remote-camera panels can move the listener out of range')
    parser.add_argument('--lift', action='store_true')
    parser.add_argument('--big-lift', action='store_true')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.start_map, args.saved = saved_world(args.save) if args.save else ('e1m3a', {})
    args.source_hash = hashlib.sha256(args.save.read_bytes()).hexdigest() if args.save else None
    args.scenario = 'saved-movers'
    args.developer = True
    run(args, exercise, setup)
