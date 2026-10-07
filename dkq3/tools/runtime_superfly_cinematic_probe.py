#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Superfly encounter: ordinary trigger contact, supplied camera and local props.

Run under dkguard --headless. Uses a copied native save and diagnostic placement
outside the encounter trigger; ordinary forward input enters the trigger.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import time
import zipfile

from runtime_bugfix_probe import run
from runtime_input import cinematic_shots
from runtime_probe import wait
from runtime_saved_mover_probe import records


PROP = 'models/e1/d1_supertorture.dkm'


def setup(home, report):
    directory = home / 'state/dk3/saves'
    directory.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.save, directory / 'reported.sav')
    (report / 'source.json').write_text(json.dumps(dict(path=str(args.save), sha256=args.source_hash)))


def exercise(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 60)
    if getattr(args, 'active_save', False):
        return restored_encounter(driver, report, capture)
    driver.load('reported')
    driver.until(lambda s: s['map'] == 'e1m3b' and s['mode'] == 'normal' and not s['cinematic'], seconds=120)
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 60)
    with zipfile.ZipFile(args.engine / 'share/dk3/dk3-models.pk3') as archive:
        converted = archive.read(PROP + '.md3')
    with zipfile.ZipFile(args.engine / 'share/dk3/zz-dk3-neural.pk3') as archive:
        replacements = dict(line.split() for line in archive.read('dk3/neural-models.cfg').decode().splitlines() if line.strip())
        override = replacements.get(PROP)
        bounds = None
        if override:
            iqm = archive.read(override)
            header = struct.unpack_from('<27I', iqm, 16)
            bounds = struct.unpack_from('<8f', iqm, header[22])[:6]
    assert bool(override) == args.expect_old
    if args.expect_old:
        assert bounds[5] - bounds[2] > 400
    result = dict(prop=dict(source=PROP, override=override, override_bounds=bounds,
                            converted_sha256=hashlib.sha256(converted).hexdigest()))
    driver.issue('dk3_runtime_place -1820 810 24')
    driver.aim(-90, 0)
    driver.issue('+forward')
    start = driver.until(lambda s: s['cinematic'] and s['mode'] == 'frozen', description='ordinary encounter trigger contact')
    driver.issue('-forward')
    assert start['shot'] == 0
    for elapsed in (1500, 6000):
        driver.until(lambda s: s['now'] >= start['now'] + elapsed and s['shot'] == 0,
                     description='first authored camera shot')
        capture(f'encounter-first-{elapsed}')
    if args.face_closeup:
        state=driver.until(lambda s:s['now']>=start['now']+9000,
                           description='additional native face inspection')
        if state['shot']==0:capture('encounter-face-closeup')
    active_save = driver.save('encounter_active')
    shutil.copy2(active_save, report / active_save.name)
    entities = [(identity, fields) for name, identity, fields in records(active_save.read_bytes()) if name == 'native_entity']
    objects = [json.loads(fields['map_object']) for _, fields in entities if 'map_object' in fields]
    assert not any(obj.get('targetname') == 'superdeco' for obj in objects), 'Encounter contact failed to remove the first decorative stand-in'
    assert any(obj.get('targetname') == 'torturerack' for obj in objects), 'Authored torture apparatus disappeared'
    result['active_entities'] = [dict(id=identity, **{key: json.loads(fields[key]) for key in ('performer', 'transform')})
                                 for identity, fields in entities if 'performer' in fields]
    if args.expect_old:
        result['scope'] = 'Expected prop-substitution defect; ordinary encounter trigger contact and first authored shot only.'
    else:
        restored = driver.load('encounter_active')
        assert restored['cinematic'] and restored['mode'] == 'frozen'
        capture('encounter-active-restored')
        deadline = time.monotonic() + 150
        captured = {0}
        while time.monotonic() < deadline:
            state = driver.observe()
            assert state['map'] == 'e1m3b' and state['health'] > 0
            if state['cinematic']:
                assert state['mode'] == 'frozen'
                if state['shot'] not in captured:
                    capture(f'encounter-shot-{state["shot"]:02}')
                    captured.add(state['shot'])
            else:
                assert state['mode'] == 'normal'
                break
        else:
            raise TimeoutError('Superfly encounter did not release player control')
        shots = cinematic_shots(driver.text(), driver.inputs, 'e1m3b', 'e1m3_cinemid', 13)
        assert shots == set(range(13)), shots
        final_save = driver.save('encounter_finished')
        shutil.copy2(final_save, report / final_save.name)
        final = driver.load('encounter_finished')
        assert final['mode'] == 'normal' and not final['cinematic']
        capture('encounter-finished-restored')
        result.update(shots=sorted(shots), restored_active=restored, restored_finished=final,
                      scope='Copied autosave, diagnostic placement, ordinary forward contact into trigger 50. All 13 authored encounter shots, prop retained, active/completed scene save/load and player control release. Software rendering; not full rescue/campaign or hardware qualification.')
    assert hashlib.sha256(args.save.read_bytes()).hexdigest() == args.source_hash
    return result


def restored_encounter(driver, report, capture):
    """Complete the exact copied historical scene rather than altering its state."""
    restored = driver.load('reported')
    assert restored['map'] == 'e1m3b' and restored['cinematic'] and restored['mode'] == 'frozen'
    captured, shots = set(), set()
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        state = driver.observe()
        assert state['map'] == 'e1m3b' and state['health'] > 0
        if not state['cinematic']:
            assert state['mode'] == 'normal'
            break
        assert state['mode'] == 'frozen'
        shots.add(state['shot'])
        if state['shot'] not in captured:
            capture(f'encounter-shot-{state["shot"]:02}')
            captured.add(state['shot'])
        time.sleep(0.1)
    else:
        raise TimeoutError('Restored Superfly encounter did not release player control')
    shots |= cinematic_shots(driver.text(), driver.inputs, 'e1m3b', 'e1m3_cinemid', 13)
    assert set(range(restored['shot'], 13)).issubset(shots), shots
    save = driver.save('encounter_finished')
    shutil.copy2(save, report / save.name)
    finished = driver.load('encounter_finished')
    assert finished['map'] == 'e1m3b' and finished['mode'] == 'normal' and not finished['cinematic']
    capture('encounter-finished-restored')
    assert hashlib.sha256(args.save.read_bytes()).hexdigest() == args.source_hash
    return dict(restored_active=restored, restored_finished=finished, shots=sorted(shots),
                scope='Copied historical active encounter save. Every remaining authored shot from the restored cursor, scene teardown, completed save/load and player control release. Does not qualify prior shots, trigger entry or current owner save.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--save', type=Path, required=True)
    parser.add_argument('--expect-old', action='store_true')
    parser.add_argument('--active-save', action='store_true', help='Complete a copied historical active encounter without diagnostic placement')
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--debugger', action='store_true', help='retain a native stack trace if the isolated engine traps')
    parser.add_argument('--face-closeup',action='store_true',help='capture an additional close face view during the first authored shot')
    args = parser.parse_args()
    args.engine, args.report, args.save = args.engine.resolve(), args.report.resolve(), args.save.resolve()
    args.source_hash = hashlib.sha256(args.save.read_bytes()).hexdigest()
    args.start_map, args.scenario, args.developer, args.cinematics = 'e1m3b', 'superfly-encounter', True, True
    run(args, exercise, setup)
