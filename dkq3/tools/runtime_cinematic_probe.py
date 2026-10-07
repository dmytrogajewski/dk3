#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Authored cinematic admission/playback diagnostics; execute under dkguard --headless."""
import argparse
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time
import zipfile

import entities
from runtime_input import NativeInput, cinematic_shots, engine_failure, record_identity
from runtime_probe import client_settings, stage_client_modules, wait


def run(args):
    if not __debug__:
        raise RuntimeError('Cinematic diagnostics require assertions')
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError('Cinematic evidence requires a fresh report directory')
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.engine, args.report, require_installation=True)
    with zipfile.ZipFile(args.engine / 'share/dk3/dk3-maps.pk3') as archive:
        bsp = archive.read(f'maps/{args.map}.bsp')
    start, size = struct.unpack_from('<ii', bsp, 8)
    authored = [dict(row) for row in entities.parse(bsp[start:start + size])]
    intro = authored[0].get('cinematic_intro', '')
    program = args.program or intro
    with zipfile.ZipFile(args.engine / 'share/dk3/dk3-data.pk3') as archive:
        path = f'dk3/cinematics/{program}.cfg'
        expected = int(archive.read(path).split()[2]) if program and path in archive.namelist() else 0
    destination = getattr(args, 'destination', None) or args.map
    destination_program, destination_expected = '', 0
    if destination != args.map:
        with zipfile.ZipFile(args.engine / 'share/dk3/dk3-maps.pk3') as archive:
            target_bsp = archive.read(f'maps/{destination}.bsp')
        target_start, target_size = struct.unpack_from('<ii', target_bsp, 8)
        destination_program = dict(entities.parse(target_bsp[target_start:target_start + target_size])[0]).get('cinematic_intro', '')
        with zipfile.ZipFile(args.engine / 'share/dk3/dk3-data.pk3') as archive:
            target_path = f'dk3/cinematics/{destination_program}.cfg'
            destination_expected = int(archive.read(target_path).split()[2]) if target_path in archive.namelist() else 0
    result = dict(identity=identity, map=args.map, destination=destination, program=program, expected_shots=expected,
                  capture_delay_ms=getattr(args, 'capture_delay_ms', 0),
                  scope='Explicit map admission and optional diagnostic trigger activation. Authored playback and restoration only; not connected campaign acceptance.')
    inputs, shots = [], set()
    with tempfile.TemporaryDirectory(prefix='dk3-native-cinematic-') as temporary:
        home = Path(temporary)
        stage_client_modules(args.engine, home, installation=args.engine)
        settings = client_settings(args.engine, home, getattr(args, 'renderer', 'opengl2'))
        settings.update(dk3_cinematics='1', g_spSkill='3', developer='1')
        command = [str(args.engine / 'bin/dk3')]
        for key, value in settings.items():
            command += ['+set', key, value]
        command += ['+map', args.map]
        log = args.report / 'client.log'
        with log.open('w') as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            driver = NativeInput(process, home / 'dk3/commands.fifo', log, home, inputs, diagnostic=True)
            try:
                wait(process, log, lambda text: engine_failure(text) or (driver.pipe.exists() and 'first snapshot applied' in text), 45)
                state = driver.observe()
                if state['map'] != args.map or state['skill'] != 3:
                    raise RuntimeError(f'Incorrect cinematic setup: {state}')
                if args.program:
                    driver.until(lambda s: s['mode'] == 'normal' and not s['cinematic'], seconds=args.seconds,
                                 description='arrival playback released before diagnostic activation')
                    matches = [i for i, obj in enumerate(authored, 1) if obj.get('cinescript') == program]
                    if len(matches) != 1 or expected == 0:
                        raise RuntimeError(f'Expected one authored trigger and an available program: {matches}')
                    driver.issue(f'dk3_runtime_activate {matches[0]} player')
                    driver.until(lambda s: s['cinematic'] and s['mode'] == 'frozen', description='actual cinematic start')
                elif expected:
                    driver.until(lambda s: s['cinematic'] and s['mode'] == 'frozen', seconds=90,
                                 description='region admission and actual arrival cinematic start')
                deadline = time.monotonic() + args.seconds
                captured = set()
                capture_starts = {}
                while time.monotonic() < deadline:
                    state = driver.observe()
                    if state['map'] not in (args.map, destination) or state['health'] <= 0:
                        raise RuntimeError(f'Cinematic unexpectedly changed map or killed its viewer: {state}')
                    if state['map'] != args.map:
                        shots |= cinematic_shots(driver.text(), inputs, args.map, program, expected)
                        if not expected or not set(range(expected)).issubset(shots):
                            raise RuntimeError(f'Premature cinematic handoff: {sorted(shots)}/{expected}')
                    if state['cinematic']:
                        if state['mode'] != 'frozen':
                            raise RuntimeError('Active cinematic did not own player control')
                        shots.add(state['shot'])
                        capture_starts.setdefault(state['shot'], state['now'])
                        if (state['shot'] in args.capture_shots and state['shot'] not in captured
                                and state['now'] - capture_starts[state['shot']] >= getattr(args, 'capture_delay_ms', 0)):
                            driver.diagnostics('dk3_runtime_performers', 'dk3 performers:')
                            name = f'cinematic-shot-{state["shot"]:03}'
                            driver.issue(f'screenshotJPEG {name}')
                            screenshot = home / f'dk3/screenshots/{name}.jpg'
                            wait(process, log, lambda _: screenshot.is_file() and screenshot.stat().st_size > 0, 5)
                            shutil.copy2(screenshot, args.report / screenshot.name)
                            captured.add(state['shot'])
                        if destination != args.map and state['shot'] == expected - 1 and 'last_shot_save' not in result:
                            saved = driver.save('cinematic_last_shot')
                            shutil.copy2(saved, args.report / saved.name)
                            result['last_shot_save'] = saved.name
                    elif state['mode'] == 'normal':
                        shots |= cinematic_shots(driver.text(), inputs, args.map, program, expected)
                        if expected and not set(range(expected)).issubset(shots):
                            raise RuntimeError(f'Incomplete authored playback: {sorted(shots)}/{expected}')
                        if state['map'] != destination:
                            state = driver.until(lambda s: s['map'] == destination and s['mode'] == 'normal' and not s['cinematic'],
                                                 seconds=90, description='authored completion target and map handoff')
                            if state['health'] <= 0:
                                raise RuntimeError('Cinematic handoff killed its viewer')
                        break
                    time.sleep(0.1)
                else:
                    raise TimeoutError('Authored cinematic did not release control')
                if destination != args.map:
                    # The new world can report normal input at the handoff
                    # boundary before starting its own authored arrival scene.
                    driver.elapsed(1000)
                    state = driver.until(lambda s: s['map'] == destination and s['mode'] == 'normal' and not s['cinematic'],
                                         seconds=args.seconds, description='destination arrival playback released')
                    arrival_shots = cinematic_shots(driver.text(), inputs, destination, destination_program, destination_expected)
                    if not set(range(destination_expected)).issubset(arrival_shots):
                        raise RuntimeError(f'Incomplete destination arrival playback: {sorted(arrival_shots)}/{destination_expected}')
                    result.update(destination_program=destination_program, destination_observed_shots=sorted(arrival_shots))
                save = driver.save('cinematic_finished')
                restored = driver.load('cinematic_finished')
                if restored['map'] != destination or restored['mode'] != 'normal' or restored['cinematic']:
                    raise RuntimeError('Completed cinematic restarted or trapped control after restoration')
                shutil.copy2(save, args.report / save.name)
                driver.issue('screenshotJPEG cinematic-finished')
                screenshot = home / 'dk3/screenshots/cinematic-finished.jpg'
                wait(process, log, lambda _: screenshot.is_file() and screenshot.stat().st_size > 0, 5)
                shutil.copy2(screenshot, args.report / screenshot.name)
                result.update(status='passed', observed_shots=sorted(shots), final_state=state, restored=restored,
                              diagnostics=[line for line in driver.text().splitlines() if line.startswith('dk3 cinematic: unavailable') or 'absent recipient' in line or 'control carrier has no media' in line])
                driver.issue('quit')
                if process.wait(timeout=15) != 0:
                    raise RuntimeError('Cinematic client shutdown failed')
            except Exception as error:
                result.update(status='failed', error=str(error), observed_shots=sorted(shots), last_state=driver._activity_sample)
                raise
            finally:
                (args.report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
                (args.report / 'inputs.json').write_text(json.dumps(dict(launch=command, inputs=inputs), indent=2) + '\n')
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--map', required=True)
    parser.add_argument('--program', help='Activate this map-authored cinematic trigger as an isolated diagnostic')
    parser.add_argument('--destination', help='Expected authored handoff map after every shot has entered')
    parser.add_argument('--seconds', type=int, default=240)
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--capture-shots', type=lambda text: set(map(int, text.split(','))), default=set())
    parser.add_argument('--capture-delay-ms', type=int, default=0,
                        help='Wait this far into an observed shot before its diagnostic capture')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args)
