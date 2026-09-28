#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Real menu and death recovery from an untouched copy of a supplied native save."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import time

from runtime_bugfix_probe import run
from runtime_input import engine_failure
from runtime_opening_route import actors
from runtime_probe import wait
from runtime_ui_probe import Input


def setup(home, report):
    saves = home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.save, saves / 'reported.sav')
    (report / 'source.json').write_text(json.dumps(dict(path=str(args.save), sha256=hashlib.sha256(args.save.read_bytes()).hexdigest())))


def restored(driver, offset, started):
    text = wait(driver.process, driver.log, lambda text:
                ('dk3 zig client: restoration applied' in text[offset:] and
                 'dk3 region: initial admission committed' in text[offset:]) or engine_failure(text[offset:]), 60)
    if failure := engine_failure(text[offset:]):
        raise RuntimeError(failure)
    state = driver.until(lambda s: s['mode'] == 'normal', description='restored normal input')
    return dict(seconds=time.monotonic() - started, state=state)


def exercise(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 60)
    driver.until(lambda s: s['mode'] == 'normal')
    ui = Input(driver.inputs)
    results = {}
    try:
        for context in ('pause-menu', 'main-menu'):
            if context == 'main-menu':
                driver.issue('disconnect')
                wait(driver.process, driver.log, lambda text: 'Server Shutdown' in text, 10)
                ui.focus(center=False)
            else:
                ui.key('Escape')
                paused = driver.diagnostics('cl_paused', '"cl_paused"').replace('^7', '').replace('^2', '')
                assert re.search(r'is:\s*"1"', paused), 'Pause input did not reach the test window: ' + paused
            ui.align_menu()
            ui.click(530, 128)
            names = sorted(p.stem for p in (driver.home / 'state/dk3/saves').glob('*.sav') if not p.stem.startswith('dk3-'))
            index = names.index('reported')
            assert index < 8, names
            ui.click(155, 150 + 27 * index)
            capture(context + '-selected')
            offset, started = len(driver.text()), time.monotonic()
            ui.click(330, 343)
            # Observe real resource completion, then capture the actual loading bar.
            wait(driver.process, driver.log, lambda text: 'dk3 world admission:' in text[offset:] or engine_failure(text[offset:]), 45)
            progress = driver.diagnostics('dk3_loading_progress', '"dk3_loading_progress"')
            values = re.findall(r'is:\s*"([\d.]+)', progress.replace('^7', '').replace('^2', ''))
            assert values and 0 < float(values[-1]) <= 1, progress
            capture(context + '-progress')
            results[context] = restored(driver, offset, started)
            results[context]['progress'] = float(values[-1])
            capture(context + '-restored')
            rows = actors(driver)
            results[context]['dead'] = sorted(i for i, row in rows.items() if row['health'] <= 0)
        assert results['pause-menu']['state']['map'] == results['main-menu']['state']['map']
        assert results['pause-menu']['dead'] == results['main-menu']['dead']
        baseline = results['main-menu']['state']
        driver.issue('dk3_runtime_damage 2000')
        dead = driver.until(lambda s: s['mode'] == 'dead' and s['health'] <= 0, description='actual death')
        offset, started = len(driver.text()), time.monotonic()
        driver.issue('+attack')
        wait(driver.process, driver.log, lambda text: 'dk3 checkpoint: restoring after death' in text[offset:] or engine_failure(text[offset:]), 12)
        driver.issue('-attack')
        results['death'] = restored(driver, offset, started)
        recovered = results['death']['state']
        assert recovered['map'] == baseline['map'] and recovered['player_id'] == baseline['player_id']
        assert recovered['health'] > 0 and recovered['weapon'] == baseline['weapon']
        assert sorted(i for i, row in actors(driver).items() if row['health'] <= 0) == results['main-menu']['dead']
        results['death']['dead_state'] = dead
        capture('death-restored')
    finally:
        ui.close()
    return dict(scope='Untouched supplied save copied to isolated profile; actual mouse selection/Load from paused and disconnected menus, observed admission progress and processed input, diagnostic death followed by normal restart input. Not continuous campaign acceptance.', paths=results)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--save', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    args = parser.parse_args()
    args.engine, args.report, args.save = args.engine.resolve(), args.report.resolve(), args.save.resolve()
    args.scenario = 'restore-ui'
    args.start_map = 'e1m1a'
    args.ui_input = True
    run(args, exercise, setup)
