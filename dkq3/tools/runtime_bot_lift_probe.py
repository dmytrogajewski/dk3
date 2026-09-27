#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated real-bot lift riding; diagnostic placement/equipment, not match acceptance."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
import time

from runtime_input import NativeInput, record_identity
from runtime_probe import stage_client_modules, wait


def run(args):
    if not __debug__ or (args.report.exists() and any(args.report.iterdir())):
        raise RuntimeError('Lift diagnosis requires assertions and a fresh report directory')
    args.report.mkdir(parents=True, exist_ok=True)
    identity = record_identity(args.engine, args.engine, args.report, require_installation=True)
    inputs, samples = [], []
    result = dict(identity=identity, phase=args.phase, scope='One actual red bot with diagnostic equipment, mover activation and placement. Approach/riding/landing/objective contact only; not ordinary deathtag acceptance.')
    with tempfile.TemporaryDirectory(prefix='dk3-bot-lift-') as temporary:
        home = Path(temporary)
        stage_client_modules(args.engine, home, installation=args.engine)
        settings = dict(net_enabled='0', fs_basepath=str(args.engine / 'share'), fs_homepath=str(home), fs_homedatapath=str(home),
                        fs_homestatepath=str(home / 'state'), com_basegame='dk3', com_pipefile='commands.fifo', vm_game='0',
                        dk3_runtime_probe='2', g_gametype='8', g_spSkill='3', sv_maxclients='8', bot_minplayers='1', developer='2',
                        fraglimit='0', capturelimit='0', timelimit='0', dk3_public='0')
        command = [str(args.engine / 'bin/dk3ded')]
        for key, value in settings.items():
            command += ['+set', key, value]
        command += ['+map', 'e1dt1']
        log = args.report / 'server.log'
        with log.open('w') as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT)
            driver = NativeInput(process, home / 'dk3/commands.fifo', log, home, inputs, diagnostic=True)
            try:
                wait(process, log, lambda text: driver.pipe.exists() and 'player entered isolated movement runtime' in text, 45)
                state = driver.observe()
                match = driver.diagnostics('dk3_runtime_match', 'dk3 match complete:')
                if 'slot=0' not in match or 'team=red' not in match or state['map'] != 'e1dt1':
                    raise RuntimeError('Expected one red bot on the authored deathtag map')
                driver.issue('dk3_runtime_equip 2')
                driver.until(lambda s: s['weapon'] == 2 and s['ammo'] > 0, description='diagnostic ranged loadout confirmed')
                mover = 337 if args.phase == 'ride' else 319
                endpoint = -98 if args.phase == 'ride' else -106
                driver.issue(f'dk3_runtime_activate {mover} player')
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    offset = len(driver.text())
                    driver.issue('dk3_runtime_movers')
                    driver.observe()
                    if re.search(rf'zig mover id={mover} .*state=open .*pos=0.0,0.0,{endpoint}.0', driver.text()[offset:]):
                        break
                else:
                    raise RuntimeError('Authored mover did not reach its open endpoint')
                driver.issue('dk3_runtime_place 632 1300 24.125' if args.phase == 'ride' else 'dk3_runtime_place 664 1375.133 24.125')
                lower = driver.until(lambda s: s['ground'] != 2047 and 15 < s['pos'][2] < 35 and 616 < s['pos'][0] < 712
                                     and (1264 < s['pos'][1] < 1344 if args.phase == 'ride' else 1344 < s['pos'][1] < 1390),
                                     description='bot standing at the declared lift fixture')
                raised, carried, departed = False, False, False
                pickup = None
                deadline = time.monotonic() + 22
                while time.monotonic() < deadline:
                    state = driver.observe()
                    samples.append(state)
                    driver.diagnostics('dk3_runtime_movers', 'zig mover id=547')
                    if state['health'] <= 0:
                        raise RuntimeError('Diagnostic bot died while riding')
                    raised |= state['pos'][2] >= 115
                    match = driver.diagnostics('dk3_runtime_match', 'dk3 match complete:')
                    if re.search(rf'id=37 team=red phase=carried carrier={state["player_id"]}\b', match):
                        carried = True
                        if pickup is None:
                            pickup = state
                            if args.phase == 'departure':
                                deadline = time.monotonic() + 20
                        # Reaching the objective is insufficient for departure:
                        # the previous carrier returned to the raised lift and
                        # waited forever. Observe it outside the south shaft.
                        departed = state['pos'][1] < 1200
                        if args.phase != 'departure' or departed:
                            break
                if not raised or not carried or (args.phase == 'departure' and not departed):
                    raise RuntimeError(f'Lift route incomplete: raised={raised}, carried={carried}, departed={departed}, last={state}')
                result.update(status='passed', lower=lower, pickup=pickup, final_state=state, carried=carried, departed=departed)
                driver.issue('quit')
                if process.wait(timeout=15) != 0:
                    raise RuntimeError('Diagnostic shutdown failed')
            except Exception as error:
                result.update(status='failed', error=str(error))
                raise
            finally:
                (args.report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
                (args.report / 'samples.json').write_text(json.dumps(samples, indent=2) + '\n')
                (args.report / 'inputs.json').write_text(json.dumps(dict(launch=command, inputs=inputs), indent=2) + '\n')
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--phase', choices=('ride', 'approach', 'departure'), default='ride')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    run(args)
