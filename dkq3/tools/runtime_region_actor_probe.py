#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Real class-owned perception, attacks and pursuit across a reviewed seam.

Controlled placement, spawned actors and health are setup, not campaign acceptance.
A failed setup, absent attack/contact or ownership boundary invalidates the case.
"""
import argparse
import math
from pathlib import Path
import re

from runtime_bugfix_probe import run, sample
from runtime_region_progression_probe import event


def actors(driver):
    text = driver.diagnostics('dk3_runtime_region_actors', 'dk3 region actors complete')
    rows = {}
    for line in text.splitlines():
        if not line.startswith('dk3 region actor: '):
            continue
        row = dict(re.findall(r'(\w+)=([^ ]+)', line))
        for key in ('id', 'health', 'threat', 'step', 'owner'):
            row[key] = int(row[key])
        row['pos'] = tuple(map(float, row['pos'].split(',')))
        assert row['id'] not in rows, f'Duplicate actor identity: {row}'
        rows[row['id']] = row
    return rows


def scenario(driver, report, capture, kind):
    event(driver, 'dk3 region: initial admission committed')
    hero = driver.until(lambda s: s['map'] == 'e1m1a' and s['mode'] == 'normal')
    assert 'map=e1m1b stage=client_ready' in driver.text()
    start = len(driver.text())
    driver.issue('dk3_runtime_place -752 -1392 525')
    driver.until(lambda s: math.dist(s['pos'], (-752, -1392, 525)) < 40,
                 description='controlled source-side approach accepted')
    driver.until(lambda s: s['ground'] != 2047, description='source player actually grounded')
    driver.stop_forward(settle_vertical=True)
    driver.issue('dk3_runtime_probe_health 1000')
    before = driver.until(lambda s: s['health'] == 1000)
    driver.aim(0, -10)
    classname = {'sentry': 'monster_rockgat', 'spit': 'monster_froginator',
                 'pursuit': 'monster_slaughterskeet', 'companion': 'superfly'}[kind]
    mark = len(driver.text())
    fixture = ' 1 ground' if kind == 'spit' else ''
    driver.issue(f'dk3_runtime_actor_spawn {classname} -480 -1392 560 180 e1m1b{fixture}')
    setup = event(driver, 'dk3 actor fixture:', mark, seconds=10)
    match = re.search(r'dk3 actor fixture: id=(\d+) class=(\S+) map=(\S+) hull-clear=1', setup)
    assert match and match[2] == classname and match[3] == 'e1m1b', setup
    if kind == 'spit':
        assert 'seed=1 grounded=1 water=0' in setup, setup
    identity = int(match[1])
    spawned = sample(driver, lambda: actors(driver), lambda rows: identity in rows,
                     'real actor exists in region')[identity]
    assert spawned['class'] == classname and spawned['health'] > 0 and spawned['map'] == 'e1m1b'
    if kind == 'companion':
        driver.issue('sidekick all follow')
        acquired = sample(driver, lambda: actors(driver),
                          lambda rows: identity in rows and rows[identity]['owner'] == hero['player_id'],
                          'companion receives normal follow order across seam')[identity]
    else:
        acquired = sample(driver, lambda: actors(driver),
                          lambda rows: identity in rows and rows[identity]['threat'] == hero['player_id'],
                          'class perception acquires player in another world', seconds=10)[identity]
    assert acquired['step'] >= 0, acquired
    if kind in ('sentry', 'spit'):
        marker = f'contact={hero["player_id"]}'
        expected = (rf'dk3 rockgat: id={identity} shot=\d+ {marker}' if kind == 'sentry'
                    else rf'dk3 frog: spit=\d+ {marker}')
        event(driver, marker, mark, seconds=20)
        assert re.search(expected, driver.text()[mark:]), driver.text()[mark:][-8000:]
        if kind == 'spit':
            launched = re.search(rf'dk3 frog: id={identity} spit=(\d+)', driver.text()[mark:])
            assert launched and f'dk3 frog: spit={launched[1]} {marker}' in driver.text()[mark:]
        result = driver.until(lambda s: 0 < s['health'] < before['health'],
                              description='actual foreign attack damages source player')
    else:
        crossed = sample(driver, lambda: actors(driver),
                         lambda rows: identity in rows and rows[identity]['map'] == 'e1m1a',
                         'real class movement transfers the same actor through seam', seconds=20)[identity]
        assert crossed['home'] == 'e1m1b' and crossed['step'] > acquired['step'], crossed
        if kind == 'companion':
            assert crossed['owner'] == hero['player_id']
        else:
            assert crossed['threat'] == hero['player_id']
        boundary = driver.text()[start:]
        assert 'Server Initialization' not in boundary and 'ClientBegin' not in boundary
        assert 'restoration committed' not in boundary
        saved = driver.save('crossed_actor')
        (report / saved.name).write_bytes(saved.read_bytes())
        restored = driver.load('crossed_actor')
        assert restored['player_id'] == hero['player_id'] and restored['map'] == 'e1m1a'
        loaded = actors(driver)[identity]
        assert loaded['map'] == 'e1m1a' and loaded['class'] == classname and loaded['home'] == 'e1m1b'
        assert loaded['health'] == crossed['health'] and loaded['owner'] == crossed['owner']
        result = dict(crossed=crossed, restored=loaded, hero=restored)
    final = driver.observe()
    assert final['map'] == 'e1m1a' and final['player_id'] == hero['player_id'] and final['health'] > 0
    text = driver.text()[start:]
    # Save restoration is explicitly allowed for pursuit; the crossing itself
    # precedes that load and must not restart the connection.
    if kind in ('sentry', 'spit'):
        assert 'Server Initialization' not in text and 'ClientBegin' not in text
    capture(f'{kind}-cross-world')
    return dict(scope='Controlled real class fixture across the BSP-qualified A/B seam; not authored encounter or continuous campaign acceptance.',
                kind=kind, initial=before, actor=spawned, acquired=acquired, result=result, final=final)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--scenario', choices=('sentry', 'spit', 'pursuit', 'companion'), default='sentry')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args, lambda driver, report, capture: scenario(driver, report, capture, args.scenario))
