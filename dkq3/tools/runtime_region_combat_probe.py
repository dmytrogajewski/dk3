#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled foreign-world targets, real attack input and checked collision owners.

Placement/equipment/targets are explicit diagnostics, never campaign acceptance.
"""
import argparse
import math
import re
from pathlib import Path

from runtime_bugfix_probe import run, sample
from runtime_region_progression_probe import event


def targets(driver):
    text = driver.diagnostics('dk3_runtime_targets', 'dk3 region targets complete')
    return {int(identity): dict(health=int(health), map=name, slot=int(slot),
                               pos=tuple(map(float, position.split(','))))
            for identity, health, name, slot, position in re.findall(
                r'dk3 zig combat: target=(\d+) health=(-?\d+) map=(\w+) slot=(\d+) pos=([-\d.,]+)', text)}


def aim(driver, target):
    player = driver.observe()
    delta = [target['pos'][i] - player['pos'][i] for i in range(3)]
    delta[2] -= 22
    driver.aim(math.degrees(math.atan2(delta[1], delta[0])),
               -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))


def exercise(driver, report, capture):
    event(driver, 'dk3 region: initial admission committed')
    initial = driver.until(lambda row: row['map'] == 'e1m1a' and row['mode'] == 'normal')
    for name in ('e1m1b', 'e1m1c'):
        assert f'map={name} stage=client_ready' in driver.text()
    driver.issue('dk3_runtime_enter_world e1m1b')
    driver.until(lambda row: row['map'] == 'e1m1b')
    driver.issue('dk3_runtime_place -544 -1392 533')
    driver.until(lambda row: math.dist(row['pos'], (-544, -1392, 533)) < 20)
    driver.aim(0, 0)
    driver.diagnostics('dk3_runtime_target', 'target fixture created')
    fixture = targets(driver)
    assert len(fixture) == 1
    identity, target = next(iter(fixture.items()))
    assert target['map'] == 'e1m1b' and target['health'] == 100
    driver.issue('dk3_runtime_probe_health 1000 ' + str(identity))
    driver.issue('dk3_runtime_enter_world initial')
    driver.until(lambda row: row['map'] == 'e1m1a')
    driver.issue('dk3_runtime_place -752 -1392 525')
    driver.until(lambda row: math.dist(row['pos'], (-752, -1392, 525)) < 20)
    driver.until(lambda row: row['ground'] != 2047, description='controlled firing position reaches actual ground')
    driver.stop_forward(settle_vertical=True)
    aim(driver, target)
    traced = driver.diagnostics('dk3_runtime_region_trace', 'dk3 region trace:')
    assert f'map=e1m1b target={identity} ' in traced and 'solid=0' in traced, traced
    presented = sample(driver, lambda: driver.diagnostics('dk3_runtime_presentation', 'dk3 presentation:'),
                       lambda text: f'dk3 foreign presentation: identity={identity} ' in text,
                       'confirmed foreign target is submitted with its owning renderer and model registry')
    update_start = len(driver.text())
    updated = driver.diagnostics(f'dk3_runtime_target_model {identity} models/e2/a_disk.dkm', 'dk3 region target model:')
    assert 'added=1' in updated, updated
    resource = re.search(r'model=(\d+) added=1 world=(\d+)', updated)
    assert resource
    event(driver, f'dk3 world config: owner={resource[2]} index={32 + int(resource[1])} applied', update_start)
    sample(driver, lambda: driver.diagnostics('dk3_runtime_presentation', 'dk3 presentation:'),
           lambda text: f'dk3 foreign presentation: identity={identity} ' in text,
           'foreign model registered after initial admission is presented')
    capture('aperture-normal')
    driver.issue('r_portalOnly 1')
    driver.observe()
    capture('aperture-destination-only')
    driver.issue('r_portalOnly 0')
    driver.observe()
    marker = len(driver.text())
    shots = []
    for weapon in (21, 2, 5):
        driver.issue(f'dk3_runtime_equip {weapon}')
        driver.ready(weapon)
        aim(driver, target)
        before = targets(driver)[identity]['health']
        fired = driver.fire()
        after = sample(driver, lambda: targets(driver),
                       lambda rows: rows[identity]['health'] < before,
                       f'weapon {weapon} contacts the confirmed foreign target')[identity]
        assert driver.observe()['map'] == 'e1m1a'
        shots.append(dict(weapon=weapon, before=before, after=after['health'], fire=fired))
    capture('attacks-through-authored-aperture')
    text = driver.text()[marker:]
    assert 'Server Initialization' not in text and 'ClientBegin' not in text
    assert 'dk3 world presentation: entered=' not in text
    return dict(scope='Controlled target in resident B, player in A, confirmed qualified ray and ordinary attack events from Glock, Ion and Sidewinder. Foreign target submitted through its owning registry and late resource definition applied; screenshots require inspection. No campaign or reference-presentation acceptance.',
                initial=initial, target=target, target_id=identity, trace=traced, presentation=presented, shots=shots)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl1')
    parser.add_argument('--developer', action='store_true', help='Record renderer admission phase timings and engine diagnostics')
    parser.add_argument('--debugger', action='store_true')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.scenario = 'region-combat'
    run(args, exercise)
