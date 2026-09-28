#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled authored worker and pickup shadow comparisons; run through dkguard."""
import argparse
import math
from pathlib import Path
import re
import time

from runtime_bugfix_probe import run, aim_actor
from runtime_opening_route import actors
from runtime_probe import wait


def scenario(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 90)
    driver.until(lambda s: s['mode'] == 'normal', description='shadow fixture admitted')
    setting = driver.diagnostics('cg_shadows', '"cg_shadows"')
    assert re.search(r'is:\s*"1"', re.sub(r'\^\d', '', setting)), setting
    if args.scene == 'pickups':
        return pickups(driver, capture)
    driver.issue('dk3_runtime_probe_health 1000')
    identity = 10
    if args.scene == 'solid-floor':
        initial = driver.stop_forward(settle_vertical=True)
        driver.aim(90, 0)
        driver.issue('+forward')
        driver.until(lambda s: math.dist(s['pos'][:2], initial['pos'][:2]) > 90,
                     description='clear the grounded actor fixture position')
        driver.stop_forward(settle_vertical=True)
        x, y, z = initial['pos']
        text = driver.diagnostics(f'dk3_runtime_actor_spawn monster_skinnyworker {x} {y} {z + 8} 0 e1m3b 1 ground', 'dk3 actor fixture:')
        match = re.search(r'dk3 actor fixture: id=(\d+).*hull-clear=1.*grounded=1', text)
        assert match, text
        identity = int(match[1])
    driver.diagnostics(f'dk3_runtime_face_target {identity} 160', f'target={identity}')
    driver.stop_forward(settle_vertical=True)
    row = actors(driver)[identity]
    assert row['class'] in ('monster_fatworker', 'monster_skinnyworker') and row['health'] > 0
    # Look below the torso so the full body and receiving floor are in view.
    target = dict(row, aim=(row['pos'][0], row['pos'][1], row['pos'][2] - 8))
    aim_actor(driver, target)
    driver.elapsed(3000)
    driver.issue('developer 0')
    driver.issue('con_notifytime 0')
    capture('worker-default')
    for index, mode in enumerate((0, 1, 0, 1)):
        driver.issue(f'cg_shadows {mode}')
        driver.diagnostics('cg_shadows', '"cg_shadows"')
        time.sleep(.2)
        capture(f'worker-{index}-shadows-{mode}')
    # A texture-free receiver view makes projected silhouettes distinguishable
    # from authored dark texels. Keep the ordinary captures above as well.
    driver.issue('r_lightmap 1')
    for mode in (0, 1):
        driver.issue(f'cg_shadows {mode}')
        driver.diagnostics('cg_shadows', '"cg_shadows"')
        time.sleep(.2)
        capture(f'worker-lightmap-shadows-{mode}')
    driver.issue('r_lightmap 0')
    driver.save('shadows')
    driver.load('shadows')
    driver.elapsed(250)
    capture('worker-restored')
    return dict(scope='Authored e1m2a workers or a diagnostic e1m3b worker on solid floor; placement/health, shadow On/Off views, default setting and save restoration. Rendered captures require inspection; no campaign acceptance.', scene=args.scene, worker=row)


def pickups(driver, capture):
    from runtime_view_probe import place
    driver.issue('developer 0')
    driver.issue('con_notifytime 0')
    driver.issue('+movedown')
    driver.until(lambda s: s['up'] < 0, description='crouched alcove view')
    results = {}
    for name, point, vantage in [('armor', (-428, -1572, 550), (-500, -1560, 552)),
                                  ('ammo', (912, -2352, 412), (840, -2336, 428.125))]:
        state = place(driver, vantage)
        delta = [point[i] - state['pos'][i] for i in range(3)]
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        for mode in (0, 1):
            driver.issue(f'cg_shadows {mode}')
            driver.elapsed(150)
            capture(f'{name}-shadows-{mode}')
        results[name] = state
    return dict(scope='Controlled views of authored e1m1a armor and ammunition; shadows off/on. Visual inspection required; no route acceptance.', items=results)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--scene', choices=('workers', 'solid-floor', 'pickups'), default='workers')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.start_map = {'solid-floor': 'e1m3b', 'workers': 'e1m2a', 'pickups': 'e1m1a'}[args.scene]
    args.scenario, args.developer = 'shadows', True
    run(args, scenario)
