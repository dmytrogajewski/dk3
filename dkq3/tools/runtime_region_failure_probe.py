#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled corrupt-prefetch fixture; original assets and saves stay untouched."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import zipfile

from runtime_bugfix_probe import run, sample
from runtime_region_progression_probe import event


RESOURCE = 'textures/e1m2/sepiemaster6.png'
CORRUPT = b'\x89PNG\r\n\x1a\ntruncated-prefetch-fixture'


def setup(home, report):
    override = home / 'dk3' / RESOURCE
    override.parent.mkdir(parents=True, exist_ok=True)
    override.write_bytes(CORRUPT)
    (report / 'setup.json').write_text(json.dumps(dict(
        scope='Temporary loose PNG override for future factory material only; controlled failure diagnostic.',
        resource=RESOURCE, sha256=hashlib.sha256(CORRUPT).hexdigest()), indent=2) + '\n')


def exercise(driver, report, capture):
    event(driver, 'dk3 region: initial admission committed')
    initial = driver.until(lambda s: s['map'] == 'e1m1a' and s['mode'] == 'normal')
    driver.issue('dk3_runtime_probe_health 1000')
    driver.until(lambda s: s['health'] == 1000, description='controlled isolation from encounter damage')
    text = sample(driver, driver.text,
                  lambda text: f'Resident PNG preparation failed: {RESOURCE}' in text
                  and re.search(r'dk3 render world: map=e1m2[ab] handle=\d+ ready=0', text),
                  'future factory renderer explicitly rejects the corrupt PNG', seconds=50)
    match = re.search(r'dk3 render world: map=(e1m2[ab]) handle=(\d+) ready=0', text)
    assert match
    announcement = re.search(r'dk3_world_begin 1 (\d+) ' + match[1] + r' ', text)
    assert announcement and f'handle={announcement[1]} failed=RenderWorldUnavailable' in driver.text()
    before = driver.observe()
    boundary = len(driver.text())
    driver.aim(0, 0)
    driver.issue('+forward')
    try:
        moved = driver.until(lambda s: s['forward'] > 0 and s['processed'] and math.dist(s['pos'], before['pos']) > 8,
                             seconds=3, description='actual processed movement after failed future admission')
    finally:
        driver.issue('-forward')
    released = driver.until(lambda s: s['forward'] == 0 and s['processed'], description='processed movement release')
    assert released['map'] == initial['map'] and released['player_id'] == initial['player_id']
    assert released['health'] > 0 and released['mode'] == 'normal'
    assert 'Server Initialization' not in driver.text()[boundary:] and 'ClientBegin' not in driver.text()[boundary:]
    capture('current-world-survives-prefetch-failure')
    save = driver.save('prefetch_failure')
    (report / save.name).write_bytes(save.read_bytes())
    restore_boundary = len(driver.text())
    restored = driver.load('prefetch_failure')
    assert restored['map'] == initial['map'] and restored['player_id'] == initial['player_id']
    assert restored['health'] > 0 and restored['mode'] == 'normal'
    # The bad future resource is still installed in the isolated profile.
    # Restoration must not require a never-exposed failed preparation.
    sample(driver, driver.text, lambda value: f'Resident PNG preparation failed: {RESOURCE}' in value[restore_boundary:],
           'future preload fails again after current-world restoration', seconds=50)
    # Use the existing controlled factory-exit fixture to attempt entry into
    # the failed region. This is explicitly placed, not campaign traversal.
    driver.issue('dk3_runtime_enter_world e1m1c')
    factory = driver.until(lambda s: s['map'] == 'e1m1c' and s['mode'] == 'normal')
    boundary = len(driver.text())
    driver.issue('dk3_runtime_place 1548 672 500')
    event(driver, 'refused: RegionPreparationFailed', boundary)
    refused = driver.observe()
    assert refused['map'] == 'e1m1c' and refused['player_id'] == initial['player_id']
    assert refused['health'] > 0 and refused['mode'] == 'normal'
    driver.issue('+back')
    try:
        backed = driver.until(lambda s: s['forward'] < 0 and s['processed'] and math.dist(s['pos'], refused['pos']) > 8,
                              seconds=3, description='ordinary control survives refused authored exit')
    finally:
        driver.issue('-back')
    driver.until(lambda s: s['forward'] == 0 and s['processed'], description='processed refusal input release')
    assert 'authored departure map=e1m2a' not in driver.text()[boundary:]
    assert 'Server Initialization' not in driver.text()[boundary:] and 'ClientBegin' not in driver.text()[boundary:]
    capture('failed-destination-refused')
    return dict(scope='Corrupt future-world PNG is rejected; existing world identity, connection and ordinary processed movement survive. Controlled developer map and health fixture, never campaign acceptance.',
                failed_map=match[1], failed_renderer_handle=int(match[2]), failed_server_handle=int(announcement[1]), initial=initial, before=before, moved=moved, released=released,
                restored=restored, controlled_factory=factory, refused=refused, backed=backed)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    with zipfile.ZipFile(args.engine / 'share/dk3/zz-dk3-textures-hd.pk3') as package:
        assert RESOURCE in package.namelist(), 'The overridden HD input must actually exist'
    args.scenario, args.developer = 'prefetch-failure', True
    run(args, exercise, setup)
