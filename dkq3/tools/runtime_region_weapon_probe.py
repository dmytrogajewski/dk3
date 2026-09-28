#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled class-owned weapon interactions across the reviewed A/B aperture.

Real attacks, target contact, physical ownership and restoration are observed.
Placement, class spawn, health and equipment are diagnostic setup, not campaign play.
"""
import argparse
import math
from pathlib import Path
import re
import shutil

from runtime_bugfix_probe import run, sample
from runtime_region_actor_probe import actors
from runtime_region_combat_probe import aim
from runtime_region_progression_probe import event

WEAPONS = dict(wyndrax=19, nightmare=20, metamaser=26, zeus=14,
               trident=13, ballista=18, discus=9, c4=3, sunflare=10, stavros=17, shockwave=6)


def controllers(driver):
    text = driver.diagnostics('dk3_runtime_region_weapons', 'dk3 region weapons complete')
    rows = {}
    for line in text.splitlines():
        if not line.startswith('dk3 region weapon: '):
            continue
        row = dict(re.findall(r'(\w+)=([^ ]+)', line))
        row['id'], row['owner'] = int(row['id']), int(row['owner'])
        row['pos'] = tuple(map(float, row['pos'].split(',')))
        assert row['id'] not in rows, f'Duplicate physical controller: {row}'
        rows[row['id']] = row
    return rows


def scenario(driver, report, capture, kind):
    event(driver, 'dk3 region: initial admission committed')
    hero = driver.until(lambda s: s['map'] == 'e1m1a' and s['mode'] == 'normal')
    driver.issue('developer 1')
    assert 'map=e1m1b stage=client_ready' in driver.text()
    driver.issue('dk3_runtime_place -752 -1392 525')
    driver.until(lambda s: math.dist(s['pos'], (-752, -1392, 525)) < 40)
    driver.until(lambda s: s['ground'] != 2047)
    driver.stop_forward(settle_vertical=True)
    driver.issue('dk3_runtime_probe_health 10000')
    driver.until(lambda s: s['health'] == 10000)
    mark = len(driver.text())
    driver.issue('dk3_runtime_actor_spawn monster_fatworker -480 -1392 560 180 e1m1b 1 ground')
    setup = event(driver, 'dk3 actor fixture:', mark, seconds=10)
    match = re.search(r'id=(\d+) class=monster_fatworker map=e1m1b hull-clear=1 seed=1 grounded=1 water=0', setup)
    assert match, setup
    target_id = int(match[1])
    assigned = driver.diagnostics(f'dk3_runtime_probe_health 2000 {target_id}', 'dk3 probe health:')
    assert f'id={target_id} health=2000' in assigned, assigned
    target = sample(driver, lambda: actors(driver), lambda rows: target_id in rows and rows[target_id]['health'] == 2000,
                    'real target health and owner')[target_id]
    assert target['map'] == 'e1m1b'
    aim(driver, target)
    traced = driver.diagnostics('dk3_runtime_region_trace', 'dk3 region trace:')
    assert f'map=e1m1b target={target_id} ' in traced and 'solid=0' in traced, traced
    weapon = WEAPONS[kind]
    driver.issue(f'dk3_runtime_equip {weapon}')
    driver.ready(weapon)
    marker = len(driver.text())
    fired = driver.fire()
    assert fired['weapon'] == weapon and fired['map'] == 'e1m1a'
    saved = None
    observed = []

    def active(predicate, description, seconds=15):
        found = sample(driver, lambda: controllers(driver),
                       lambda rows: any(row['kind'] == kind and predicate(row) for row in rows.values()),
                       description, seconds=seconds)
        row = next(row for row in found.values() if row['kind'] == kind and predicate(row))
        assert row['owner'] == hero['player_id'], row
        observed.append(row)
        return row

    if kind == 'nightmare':
        ritual = active(lambda row: row.get('phase') == 'reaping' and row.get('victim') == str(target_id),
                        'ritual captures actual foreign victim', seconds=45)
        assert ritual['map'] == 'e1m1b' and ritual['freeze'] == str(ritual['id']), ritual
        saved = driver.save('foreign_reaper')
        shutil.copy2(saved, report / saved.name)
        driver.load('foreign_reaper')
        restored = active(lambda row: row['id'] == ritual['id'] and row.get('phase') == 'reaping',
                          'same saved ritual restored in victim world')
        assert restored['map'] == 'e1m1b' and restored['victim'] == str(target_id) and restored['freeze'] == str(ritual['id'])
        marker = len(driver.text())
    elif kind == 'wyndrax':
        wisp = active(lambda row: str(target_id) in row.get('targets', '').split(','),
                      'wisp acquired the actual foreign target')
        saved = driver.save('foreign_wisp')
        shutil.copy2(saved, report / saved.name)
        driver.load('foreign_wisp')
        active(lambda row: row['id'] == wisp['id'], 'same saved wisp restored')
        marker = len(driver.text())
    elif kind == 'metamaser':
        cube = active(lambda row: row.get('phase') == 'tracking' and str(target_id) in row.get('locks', '').split(','),
                      'cube acquired actual foreign target', seconds=20)
        saved = driver.save('foreign_cube')
        shutil.copy2(saved, report / saved.name)
        driver.load('foreign_cube')
        active(lambda row: row['id'] == cube['id'] and row.get('phase') == 'tracking', 'same tracking cube restored')
        marker = len(driver.text())
    elif kind == 'zeus':
        chain = active(lambda row: row.get('phase') == 'pending', 'real delayed Zeus controller')
        saved = driver.save('foreign_zeus')
        shutil.copy2(saved, report / saved.name)
        driver.load('foreign_zeus')
        active(lambda row: row['id'] == chain['id'], 'same Zeus chain restored')
        marker = len(driver.text())

    event(driver, f'dk3 zig combat: target={target_id} blood=', marker, seconds=20)
    contact = re.search(rf'dk3 zig combat: target={target_id} blood=([1-9]\d*)', driver.text()[marker:])
    assert contact, 'No actual positive damage to the required target'
    after = actors(driver)[target_id]
    assert 0 < after['health'] < target['health'], after
    if kind == 'trident':
        assert re.search(r'dk3 zig trident: leader=\d+ tips=3', driver.text()[marker:]), 'Three-tip setup not reached'
    if kind == 'nightmare':
        driver.ready(weapon)
        assert not any(row['kind'] == kind for row in controllers(driver).values()), 'Completed ritual controller survived'
    current = driver.observe()
    assert current['player_id'] == hero['player_id'] and current['map'] == 'e1m1a' and current['health'] > 0
    capture(kind + '-foreign-contact')
    return dict(scope='Controlled actor/equipment/health and grounded placement. Real normal-input attack, qualified target ray, positive damage and the stated controller restoration only; no fresh campaign or full class interaction acceptance.',
                weapon=weapon, target_id=target_id, before=target, after=after,
                trace=traced, fired=fired, controllers=observed, saved=saved.name if saved else None)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl1')
    parser.add_argument('--scenario', choices=tuple(WEAPONS), required=True)
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args, lambda driver, report, capture: scenario(driver, report, capture, args.scenario))
