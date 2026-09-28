#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Campaign save restoration after a local multiplayer session, using real menu input."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import time

from runtime_bugfix_probe import run
from runtime_input import engine_failure
from runtime_probe import wait
from runtime_restore_ui_probe import restored
from runtime_ui_probe import Input


def setup(home, report):
    if args.config:
        shutil.copy2(args.config, home / 'dk3/dk3config.cfg')
    saves = home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.save, saves / 'reported.sav')
    shutil.copy2(saves / 'reported.sav', report / 'source.sav')
    (report / 'source.json').write_text(json.dumps(dict(path=str(args.save), sha256=hashlib.sha256((report / 'source.sav').read_bytes()).hexdigest())))


def exercise(driver, report, capture):
    driver.until(lambda s: s['mode'] == 'normal')
    ui = None if args.console else Input(driver.inputs)
    results = {}
    try:
        offset = len(driver.text())
        driver.issue('disconnect')
        wait(driver.process, driver.log, lambda text: 'Server Shutdown' in text[offset:], 10)
        if ui:
            ui.focus(center=False)
            ui.align_menu()
            ui.click(530, 100)
            ui.click(390, 105)
            driver.issue('set ui_roomMap e2dm2')
            driver.issue('set ui_roomSlots 15')
            driver.issue('set ui_roomBots 13')
            ui.click(175, 295)
        else:
            driver.issue('set g_gametype 0; set sv_maxclients 15; set bot_minplayers 14; map e2dm2')
        wait(driver.process, driver.log, lambda text: 'first snapshot applied' in text[offset:] or engine_failure(text[offset:]), 60)
        results['multiplayer'] = driver.until(lambda s: s['map'] == 'e2dm2' and s['mode'] == 'normal')
        driver.until(lambda s: s['now'] > results['multiplayer']['now'] + 16000, seconds=60)
        mode = driver.diagnostics('g_gametype', '"g_gametype"').replace('^7', '').replace('^2', '')
        assert re.search(r'is:\s*"0"', mode), mode
        capture('multiplayer')
        offset = len(driver.text())
        if args.direct:
            if not ui:
                raise ValueError('Direct Load requires actual menu input')
            ui.key('Escape')
        else:
            driver.issue('disconnect')
            wait(driver.process, driver.log, lambda text: 'Server Shutdown' in text[offset:], 10)
        if ui:
            ui.focus(center=False)
            ui.align_menu()
            ui.click(530, 128)
            names = sorted(p.stem for p in (driver.home / 'state/dk3/saves').glob('*.sav') if not p.stem.startswith('dk3-'))
            index = names.index('reported')
            assert index < 8, names
            ui.click(155, 150 + 27 * index)
            capture('save-selected')
        offset, started = len(driver.text()), time.monotonic()
        if ui:
            ui.click(330, 343)
        else:
            driver.issue('dk3_loadmenu reported')
        if args.watch_loading:
            wait(driver.process, driver.log, lambda text: 'first snapshot applied' in text[offset:] or engine_failure(text[offset:]), 60)
            for index in range(60):
                capture(f'loading-{index:02}')
                if 'dk3 region: initial admission committed' in driver.text()[offset:]:
                    break
                time.sleep(0.5)
        results['restored'] = restored(driver, offset, started)
        mode = driver.diagnostics('g_gametype', '"g_gametype"').replace('^7', '').replace('^2', '')
        assert re.search(r'is:\s*"2"', mode), mode
        capture('campaign-restored')
        for index in range(args.watch):
            time.sleep(2)
            capture(f'background-{index:02}')
        driver.issue('cg_shadows 0')
        driver.observe()
        capture('campaign-no-shadows')
        driver.issue('cg_shadows 1')
        capture('campaign-shadows')
    finally:
        if ui:
            ui.close()
    return dict(scope='Isolated copied save; local e2dm2 hosting with 13 bots, then campaign restoration. '
                + ('Actual menu hosting and Load clicks. ' if ui else 'Console commands without desktop input injection. ')
                + 'Screenshots cover the requested loading/background interval; not continuous campaign acceptance.', **results)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--save', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--console', action='store_true', help='Use engine commands without desktop input injection')
    parser.add_argument('--config', type=Path)
    parser.add_argument('--watch', type=int, default=0, help='Capture background preparation every two seconds')
    parser.add_argument('--watch-loading', action='store_true')
    parser.add_argument('--direct', action='store_true', help='Load from the hosted match pause menu')
    args = parser.parse_args()
    args.engine, args.report, args.save = args.engine.resolve(), args.report.resolve(), args.save.resolve()
    args.scenario, args.start_map, args.ui_input = 'mode-restore', 'e1m1a', True
    run(args, exercise, setup)
