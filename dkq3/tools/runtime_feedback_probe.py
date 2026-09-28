#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled regression fixtures, not continuous campaign acceptance. Use dkguard."""
import argparse
import json
import math
from pathlib import Path
import re
import shutil
import time

from runtime_bugfix_probe import run, sample, presentation, aim_actor
from runtime_opening_route import actors, terminal_contact


def monitor(driver, report, capture):
    driver.until(lambda s: s['mode'] == 'normal' and s['map'] == 'e1m1c', seconds=40, description='monitor world ready')
    driver.issue('dk3_runtime_probe_health 1000')
    # The authored button operates monitor 177 and the original delayed door targets.
    text = driver.diagnostics('dk3_runtime_movers', 'zig mover id=216 ')
    (report / 'movers-before.log').write_text(text)
    driver.issue('dk3_runtime_place 2408 1632 832')
    player = driver.until(lambda s: math.dist(s['pos'], (2408, 1632, 832)) < 20, description='clear standing position at authored button')
    driver.stop_forward(settle_vertical=True)
    player = driver.observe()
    delta = [2446 - player['pos'][0], 1632 - player['pos'][1], 848 - player['pos'][2] - 22]
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
    capture('monitor-button-before')
    driver.issue('use')
    active = driver.until(lambda s: s['mode'] == 'frozen', description='authored monitor owns viewer')
    state = sample(driver, lambda: presentation(driver), lambda s: s['camera'] == 2, 'monitor camera survives snapshot wire')
    capture('monitor-view')
    world = driver.diagnostics('dk3_runtime_world', 'dk3 zig world states complete')
    (report / 'monitor-active.log').write_text(world)
    assert re.search(r'dk3 zig monitor: id=177 viewer=[1-9]\d* .*camera=211 target=196', world)
    released = driver.until(lambda s: s['mode'] == 'normal', seconds=12, description='monitor releases viewer')
    assert released['now'] >= active['now'] + 7000
    sample(driver, lambda: presentation(driver), lambda s: s['camera'] == 0, 'normal view restored')
    driver.issue('+back')
    try:
        moved = driver.until(lambda s: math.dist(s['pos'], released['pos']) > 8, description='normal movement after monitor')
    finally:
        driver.issue('-back')
    saved = driver.save('monitor-finished')
    shutil.copy2(saved, report / saved.name)
    restored = driver.load('monitor-finished')
    assert restored['mode'] == 'normal'
    return dict(scope='Diagnostic placement then ordinary use of actual e1m1c button 216; camera transport, release, input and restoration. Not route acceptance.', active=active, camera=state, released=released, moved=moved, restored=restored)


def workers(driver, report, capture):
    driver.until(lambda s: s['mode'] == 'normal' and s['map'] == 'e1m2a', seconds=40, description='workers world ready')
    driver.issue('dk3_runtime_probe_health 1000')
    before = actors(driver)
    assert all(before[i]['class'] in ('monster_skinnyworker', 'monster_fatworker') and before[i]['health'] > 0 for i in (9, 10))
    driver.issue('dk3_runtime_face_target 10')
    driver.issue('dk3_runtime_equip 21')
    driver.ready(21)
    capture('workers-before')
    observations = []
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        rows = actors(driver)
        observations.append({i: rows.get(i) for i in (9, 10)})
        if 10 not in rows:
            assert terminal_contact(driver.text(), 10), 'Missing actor without a confirmed terminal hit'
            break
        if rows[10]['health'] <= 0:
            break
        aim_actor(driver, rows[10])
        driver.fire()
    else:
        raise TimeoutError('Actual worker kill not achieved')
    after = actors(driver)
    assert after[9]['health'] > 0 and int(after[9]['witness']) > 0
    # Either reach cover or exhaust a blocked route, then visibly stop running.
    cower = sample(driver, lambda: actors(driver), lambda r: r[9]['worker'] == 'cower', 'witness settles into authored cower pose', seconds=14)[9]
    assert cower['state'] == 'idle' and math.hypot(*cower['velocity'][:2]) < 1
    capture('worker-cowering')
    saved = driver.save('worker-fear')
    shutil.copy2(saved, report / saved.name)
    driver.load('worker-fear')
    restored = actors(driver)[9]
    assert restored['worker'] == 'cower'
    (report / 'worker-samples.json').write_text(json.dumps(observations, indent=2))
    sounds = [line for line in driver.text().splitlines() if 'dk3 worker: fear voice' in line]
    assert sounds, 'No actual fear vocal dispatched in this fixture'
    assert 'WARNING: could not find sound' not in driver.text()
    return dict(scope='Diagnostic placement/equipment; ordinary Glock shots injure/kill authored worker, witness reacts and reaches a cower pose; actual save/load retains fear state.', before={i: before[i] for i in (9, 10)}, after={i: after.get(i) for i in (9, 10)}, cower=cower, restored=restored, voices=sounds)


def ground(driver, report, capture):
    driver.until(lambda s: s['mode'] == 'normal' and s['map'] == 'e1m3b', seconds=40, description='authored guard world ready')
    initial = actors(driver)
    assert initial[166]['class'] == 'monster_mishimaguard' and initial[166]['health'] > 0
    driver.diagnostics('dk3_runtime_actor_ground 166', 'dk3 actor ground:')
    fixture = driver.diagnostics('dk3_runtime_chase 166', 'dk3 zig navigation fixture:')
    match = re.search(r'actor=166 start=([\d.,-]+) goal=([\d.,-]+) travel=(\d+) occluded=1', fixture)
    assert match, 'Occluded reachable authored navigation setup did not complete'
    origin = tuple(map(float, match[1].split(',')))
    observed = []
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        driver.observe()
        row = actors(driver)[166]
        observed.append(row)
        if math.dist(origin, row['pos']) > 24 and 'guard: id=166 fired' in driver.text():
            break
    else:
        raise TimeoutError(f'Ground guard failed actual occluded pursuit and firing: {observed[-1]}')
    aim_actor(driver, row)
    capture('ground-guard-pursuit')
    (report / 'ground-samples.json').write_text(json.dumps(observed, indent=2))
    return dict(scope='Authored guard 166 in e1m3b, diagnostic last-seen goal and player placement, actual collision-driven pursuit around occlusion and subsequent fire. No route traversal claim.', fixture=fixture, displacement=max(math.dist(origin, r['pos']) for r in observed), final=row)


def lighting(driver, report, capture):
    driver.until(lambda s: s['mode'] == 'normal' and s['map'] == 'e1m1a', seconds=40, description='Cambot world ready')
    driver.issue('dk3_runtime_probe_health 1000')
    camera = actors(driver)[9]
    assert camera['class'] == 'monster_cambot' and camera['health'] > 0
    yaw = math.radians(camera['angles'][1])
    point = (camera['pos'][0] + 96 * math.cos(yaw), camera['pos'][1] + 96 * math.sin(yaw), camera['pos'][2] - 40)
    driver.issue('dk3_runtime_place ' + ' '.join(map(str, point)))
    driver.until(lambda s: math.dist(s['pos'], point) < 40, description='Cambot fixture placement')
    camera = sample(driver, lambda: actors(driver), lambda rows: rows[9]['camera_seen'] == '1', 'actual Cambot acquisition')[9]
    aim_actor(driver, camera)
    lamp = sample(driver, lambda: presentation(driver), lambda row: row['lamps'] > 0, 'actual searchlight submission')
    capture('cambot-natural-light')
    driver.issue('+back')
    before = driver.observe()
    try:
        driver.until(lambda state: math.dist(state['pos'], before['pos']) > 80, seconds=3, description='ordinary movement to inspect lamp at a wider distance')
    finally:
        driver.issue('-back')
    aim_actor(driver, actors(driver)[9])
    capture('cambot-wide-light')
    return dict(scope='Diagnostic player placement; actual Cambot acquisition and rendered dynamic surface lighting. No shadow-mapped spotlight or full reference parity claim.', camera=camera, lamp=lamp)


def autosaves(driver, report, capture):
    start = driver.until(lambda s: s['mode'] == 'normal', seconds=40, description='playable arrival')
    saves = driver.home / 'state/dk3/saves'
    sample(driver, lambda: (saves / 'autosave-arrival.sav').exists(), bool, 'completed arrival autosave')
    arrival = (saves / 'autosave-arrival.sav').read_bytes()
    driver.issue('dk3_runtime_probe_health 90')
    low = driver.until(lambda s: s['health'] == 90, description='ninety percent boundary fixture')
    driver.until(lambda s: s['now'] >= start['now'] + 61000, seconds=70, description='minute elapsed at ineligible health')
    assert not (saves / 'autosave.sav').exists(), 'Exactly ninety percent must not replace periodic save'
    driver.issue('dk3_runtime_probe_health 91')
    driver.until(lambda s: s['health'] == 91, description='strictly above ninety percent')
    sample(driver, lambda: (saves / 'autosave.sav').exists(), bool, 'completed healthy periodic autosave')
    periodic = (saves / 'autosave.sav').read_bytes()
    assert arrival != periodic
    shutil.copy2(saves / 'autosave.sav', report / 'autosave.sav')
    shutil.copy2(saves / 'autosave-arrival.sav', report / 'autosave-arrival.sav')
    driver.issue('dk3_runtime_damage 20')
    driver.until(lambda s: s['health'] == 71, description='post-save damage')
    restored = driver.load('autosave')
    assert restored['health'] == 91 and restored['map'] == start['map']
    capture('autosave-restored')
    return dict(scope='Fresh isolated map arrival and real 60-second eligibility boundary, actual periodic save restoration; controlled health setup. Companion eligibility covered separately.', start=start, low=low, restored=restored)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--scenario', choices=('monitor', 'workers', 'autosaves', 'ground', 'lighting'), required=True)
    parser.add_argument('--renderer', default='opengl1')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.start_map = {'monitor': 'e1m1c', 'workers': 'e1m2a', 'autosaves': 'e1m1a', 'ground': 'e1m3b', 'lighting': 'e1m1a'}[args.scenario]
    args.developer = True
    run(args, scenario={'monitor': monitor, 'workers': workers, 'autosaves': autosaves, 'ground': ground, 'lighting': lighting}[args.scenario])
