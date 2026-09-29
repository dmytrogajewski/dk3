#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Skeletal companions and boss in an isolated authored map; run under dkguard."""
import argparse
import math
from pathlib import Path
import re
import time

from runtime_bugfix_probe import run, aim_actor
from runtime_opening_route import actors
from runtime_probe import wait


def intro(driver, report, capture):
    driver.issue('con_notifytime 0')
    if args.face: driver.issue('developer 0')
    driver.until(lambda s: s['cinematic'] and s['mode'] == 'frozen', seconds=90, description='intro admitted')
    observed, captured, motion = set(), set(), []
    deadline = time.monotonic() + 300
    while time.monotonic() < deadline:
        state = driver.observe()
        assert state['map'] == 'intro' and state['cinematic'] and state['health'] > 0
        observed.add(state['shot'])
        wanted = state['shot'] in (2, 4, 7, 10, 14, 18, 22, 28, 34) or (args.face and 0 <= state['shot'] <= 14)
        if wanted and state['shot'] not in captured:
            driver.elapsed(350)
            capture(f'intro-shot-{state["shot"]:03}')
            captured.add(state['shot'])
            if args.face and state['shot'] == 14:
                for frame in range(6):
                    row = driver.elapsed(250)
                    if row['shot'] != state['shot']: break
                    image = f'face-shot-{state["shot"]:03}-{frame:03}'
                    capture(image)
                    motion.append(dict(image=image+'.jpg', state=row))
            if args.motion and state['shot'] in (2, 4, 7):
                for frame in range(12):
                    row = driver.elapsed(80)
                    image = f'intro-motion-{state["shot"]:03}-{frame:03}'
                    capture(image)
                    motion.append(dict(image=image+'.jpg', state=row))
        if state['shot'] >= args.until_shot: break
    else: raise TimeoutError('intro did not reach the converted Hiro/Usagi dialogue')
    for model in (('c_hiro_intr', 'c_usagi_intr') if args.until_shot >= 28 else ('c_hiro_intr',)):
        assert f'models/neural/{model}.iqm' in driver.text(), model
    saved = driver.save('neural_intro')
    restored = driver.load('neural_intro')
    assert restored['cinematic'] and restored['shot'] >= state['shot']
    driver.elapsed(350)
    capture('intro-restored')
    return dict(scope=f'Playback through intro shot {args.until_shot}, sampled poses/motion and actual mid-cinematic save restoration. Full intro and later cinematic performances remain outside this diagnostic.',
                observed=sorted(observed), motion=motion, saved=str(saved.name), restored=restored)


def scene(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 90)
    driver.until(lambda s: s['mode'] == 'normal')
    driver.issue('dk3_runtime_probe_health 1000')
    driver.until(lambda s: s['health'] == 1000, description='observer fixture health')
    driver.issue('con_notifytime 0')
    initial = driver.stop_forward(settle_vertical=True)
    for yaw in (90, 0, 180, 270):
        driver.aim(yaw, 0)
        driver.issue('+forward')
        try:
            driver.until(lambda s: math.dist(s['pos'][:2], initial['pos'][:2]) > 100,
                         seconds=2, description='clear actor placement')
            break
        except TimeoutError:
            pass
        finally:
            driver.stop_forward(settle_vertical=True)
    else:
        raise RuntimeError('No clear walking direction for actor placement')
    x, y, z = initial['pos']
    text = driver.diagnostics(f'dk3_runtime_actor_spawn {args.actor} {x} {y} {z + 8} 0 {args.start_map} 1 ground', 'dk3 actor fixture:')
    match = re.search(r'id=(\d+).*hull-clear=1.*grounded=1', text)
    assert match, text
    identity = int(match[1])
    driver.diagnostics(f'dk3_runtime_face_target {identity} 160', f'target={identity}')
    driver.stop_forward(settle_vertical=True)
    row = actors(driver)[identity]
    aim_actor(driver, dict(row, aim=(row['pos'][0], row['pos'][1], row['pos'][2]+3)))
    driver.elapsed(250)
    capture('skeletal-actor')
    driver.issue('cg_shadows 0')
    driver.elapsed(100)
    capture('shadows-off')
    driver.issue('cg_shadows 1')
    driver.elapsed(100)
    capture('shadows-on')
    driver.aim(90, 0)
    driver.issue('+forward')
    driver.elapsed(700)
    driver.stop_forward(settle_vertical=True)
    row = actors(driver)[identity]
    aim_actor(driver, row)
    driver.elapsed(500)
    capture('skeletal-moving')
    restored = False
    # Kage's scripted health drain can leave the observer at one HP before a
    # nearby guard fires. Death is valid combat behavior; boss rendering is a
    # separate case from the companion save/restore check.
    if args.actor != 'monster_kage':
        driver.save('neural_actor')
        driver.load('neural_actor')
        assert actors(driver)[identity]['health'] > 0
        capture('skeletal-restored')
        restored = True
    expected = {'mikiko': 'm_mikiko', 'superfly': 'm_superfly', 'mikikofly': 'm_mikikofly', 'monster_kage': 'm_kage'}[args.actor]
    assert f'models/neural/{expected}.iqm' in driver.text()
    assert not re.search(r'R_AddIQMSurfaces: no such frame|MissingAuthoredActorHardpoint|R_LoadIQM:', driver.text())
    return dict(actor=args.actor, id=identity, state=row, restored=restored,
                scope='Controlled, grounded live actor, rendered skeletal poses and shadow comparison, movement; companions also save/restore. Boss survival and save restoration are outside this rendering diagnostic. No authored campaign route or complete cinematic acceptance.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--actor', choices=('mikiko', 'superfly', 'mikikofly', 'monster_kage'), default='mikiko')
    parser.add_argument('--scene', choices=('actor', 'intro'), default='actor')
    parser.add_argument('--until-shot', type=int, default=35)
    parser.add_argument('--motion', action='store_true', help='capture timed motion bursts during Hiro practice shots')
    parser.add_argument('--face', action='store_true', help='capture every early intro angle for face texture review')
    parser.add_argument('--map', default='e1m3b', help='isolated actor fixture map')
    parser.add_argument('--renderer', default='opengl2')
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.start_map, args.scenario, args.developer = 'intro' if args.scene == 'intro' else args.map, 'neural', True
    args.cinematics = args.scene == 'intro'
    run(args, intro if args.scene == 'intro' else scene)
