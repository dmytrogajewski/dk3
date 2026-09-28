#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Automatic admission/crossing diagnostic with explicit controlled placement.

This exercises real authored exit touches, not a continuous campaign playthrough.
"""
import argparse
import math
import hashlib
import json
import shutil
from pathlib import Path

from runtime_bugfix_probe import run
from runtime_input import engine_failure
from runtime_probe import wait


def event(driver, marker, start=0, seconds=120):
    text = wait(driver.process, driver.log, lambda text: marker in text[start:] or engine_failure(text[start:]), seconds)
    if failure := engine_failure(text):
        raise RuntimeError(failure)
    return text[start:]


def progression(driver, report, capture):
    event(driver, 'dk3 region: initial admission committed')
    before = driver.until(lambda s: s['map'] == 'e1m1a' and s['mode'] == 'normal')
    for name in ('e1m1b', 'e1m1c'):
        assert f'map={name} stage=client_ready' in driver.text()
    start = len(driver.text())
    driver.issue('dk3_runtime_place -752 -1400 525')
    driver.until(lambda s: math.dist(s['pos'], (-752, -1400, 525)) < 40,
                 description='controlled approach to the authored A exit')
    driver.aim(0, 0)
    source = driver.observe()
    driver.issue('+forward')
    try:
        entered = driver.until(lambda s: s['map'] == 'e1m1b', seconds=10,
                               description='automatic authored A to B touch')
        moved = driver.until(lambda s: s['pos'][0] > -544, seconds=5,
                             description='retained movement after handoff')
    finally:
        driver.issue('-forward')
    assert entered['player_id'] == source['player_id'] == before['player_id']
    assert moved['health'] == source['health'] > 0
    assert moved['cmd'] > source['cmd']
    # The actual authored departure, not a console transfer, must produce an
    # arrival autosave after the resident handoff becomes playable.
    arrival = driver.home / 'state/dk3/saves/autosave-arrival.info'
    wait(driver.process, driver.log, lambda _: arrival.exists() and 'map "e1m1b"' in arrival.read_text(), 10)
    shutil.copy2(arrival, report / 'arrival-b.info')
    shutil.copy2(arrival.with_suffix('.sav'), report / 'arrival-b.sav')
    capture('b-after-authored-touch')
    driver.aim(180, 0)
    driver.issue('+forward')
    try:
        returned = driver.until(lambda s: s['map'] == 'e1m1a', seconds=10,
                                description='automatic reciprocal B to A touch')
    finally:
        driver.issue('-forward')
    driver.until(lambda s: s['forward'] == 0)
    assert returned['player_id'] == before['player_id'] and returned['health'] > 0
    text = driver.text()[start:]
    assert text.count('kind=identity connection=retained') == 2, text[-5000:]
    assert 'Server Initialization' not in text and 'ClientBegin' not in text
    assert 'initial admission committed' not in text and 'restoration committed' not in text
    assert not any('dk3_runtime_enter_world' in row.get('command', '') for row in driver.inputs)
    capture('a-after-authored-return')
    saved = driver.save('automatic_region')
    (report / saved.name).write_bytes(saved.read_bytes())
    return dict(scope='Controlled approach followed by ordinary movement through both authored reciprocal brushes. Automatic region admission, stable identity/input/health, no connection restart. Not fresh campaign or portal combat acceptance.',
                initial=before, approach=source, entered=entered, continued=moved, returned=returned)


def cuts(driver, report, capture):
    event(driver, 'dk3 region: initial admission committed')
    intro = driver.until(lambda s: s['map'] == 'intro' and s['cinematic'] and s['mode'] == 'frozen')
    start = len(driver.text())
    driver.issue('cin_skip')
    event(driver, 'dk3 region: authored departure map=e1m1a', start)
    # The authored arrival has its own short cinematic after the full intro.
    # A normal-mode sample in the handoff frame precedes its actual start.
    event(driver, 'shot=7/7 name=e1m1_cinestart', start)
    arrived = driver.until(lambda s: s['map'] == 'e1m1a' and s['mode'] == 'normal' and not s['cinematic'], seconds=90)
    assert arrived['health'] == 100 and arrived['weapon'] == 1 and arrived['player_id'] == intro['player_id']
    capture('authored-intro-arrival')
    # The next region must be admitted through the ordinary prefetch path. The
    # remaining setup skips traversal solely to focus on the authored cut.
    for name in ('e1m2a', 'e1m2b'):
        event(driver, f'map={name} stage=client_ready')
    driver.issue('dk3_runtime_enter_world e1m1c')
    driver.until(lambda s: s['map'] == 'e1m1c')
    # The normal approach is protected by the factory's authored locked door.
    # This focused cut test explicitly places within the supplied exit brush;
    # unlocking and traversing that door belongs to the ordinary campaign route.
    driver.issue('dk3_runtime_place 1548 672 500')
    destination = driver.until(lambda s: s['map'] == 'e1m2a', seconds=10,
                               description='controlled overlap invokes the authored factory cut')
    assert destination['health'] > 0 and destination['player_id'] == intro['player_id']
    text = driver.text()[start:]
    assert 'kind=cut connection=retained' in text
    assert 'Server Initialization' not in text and 'ClientBegin' not in text
    capture('factory-cut-arrival')
    saved = driver.save('cut_region')
    (report / saved.name).write_bytes(saved.read_bytes())
    restored = driver.load('cut_region')
    assert restored['map'] == 'e1m2a' and restored['player_id'] == intro['player_id']
    assert restored['health'] == driver.observe()['health'] > 0
    capture('cut-region-restored')
    return dict(scope='Skipped intro uses its authored exit; controlled placement inside the factory exit brush invokes its chapter cut. Both enter automatically admitted worlds with a retained connection, then the resident region actually saves and reloads. Factory door unlocking and full intro/campaign traversal are not exercised.',
                intro=intro, arrived=arrived, destination=destination, restored=restored)


def restoration(driver, report, capture, fixture):
    saves = driver.home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fixture, saves / 'admission_window.sav')
    source = dict(path=str(fixture), sha256=hashlib.sha256(fixture.read_bytes()).hexdigest())
    (report / 'source.json').write_text(json.dumps(source, indent=2) + '\n')
    # A load request may cancel an initial preparation. Actual completion, not a
    # delay or the filename, controls the next input.
    start = len(driver.text())
    restored = driver.load('admission_window')
    text = driver.text()[start:]
    assert restored['map'] == 'e1m2a' and restored['health'] == 100
    assert restored['player_id'] == 433
    assert 'dk3 region: restoration committed' in text
    for name in ('intro', 'e1m1a', 'e1m1b', 'e1m1c', 'e1m2b'):
        assert f'map={name} stage=client_ready' in text, name
    if restored['cinematic']:
        advanced = driver.until(lambda s: s['shot'] != restored['shot'] or not s['cinematic'],
                                seconds=60, description='restored arrival cinematic advances')
        driver.inputs.append({'restored_cinematic_advanced': advanced})
    playable = driver.until(lambda s: s['mode'] == 'normal' and not s['cinematic'],
                            seconds=120, description='authored arrival returns control after restoration')
    driver.issue('+moveright')
    try:
        moved = driver.until(lambda s: math.dist(s['pos'], playable['pos']) > 8,
                             seconds=3, description='ordinary movement after six-world restore')
    finally:
        driver.issue('-moveright')
    driver.until(lambda s: s['right'] == 0)
    capture('six-world-restored')
    saved = driver.save('restored_region')
    (report / saved.name).write_bytes(saved.read_bytes())
    return dict(scope='Replay of an immutable controlled six-world native save; all five resident members reach actual client readiness, saved arrival cinematic advances and completes, ordinary movement resumes and saving succeeds. Includes cancellation of initial preparation. No campaign traversal acceptance.', source=source, restored=restored, playable=playable, moved=moved)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl1')
    parser.add_argument('--developer', action='store_true', help='Record renderer admission phase timings and engine diagnostics')
    parser.add_argument('--cuts', action='store_true')
    parser.add_argument('--restore-from', type=Path)
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = 'region-progression'
    if args.cuts:
        args.start_map = 'intro'
        args.cinematics = True
    if args.restore_from:
        args.start_map = 'e1m2a'
        args.cinematics = True
        run(args, lambda driver, report, capture: restoration(driver, report, capture, args.restore_from.resolve()))
    else:
        run(args, cuts if args.cuts else progression)
