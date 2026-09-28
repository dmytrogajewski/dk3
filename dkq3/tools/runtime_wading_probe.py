#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Restore a real encounter and require its authored sludgeminion to pursue."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import shutil
import time

from runtime_bugfix_probe import run, aim_actor
from runtime_opening_route import actors
from runtime_probe import wait


def setup(home, report):
    saves = home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.save, saves / 'reported.sav')
    (report / 'source.json').write_text(json.dumps(dict(path=str(args.save), sha256=hashlib.sha256(args.save.read_bytes()).hexdigest())))


def exercise(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 60)
    player = driver.load('reported')
    before = actors(driver)[args.actor]
    assert before['class'] == 'monster_sludgeminion' and before['health'] > 0 and before['state'] == 'chase', before
    route = driver.diagnostics(f'dk3_runtime_actor_motion {args.actor}', 'dk3 actor motion complete')
    travel = {int(water): int(cost) for water, cost in re.findall(r'dk3 actor route: water=(\d).*? travel=(\d+)', route)}
    assert travel.get(0) == 0 and travel.get(1, 0) > 0, route
    samples = [before]
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        driver.observe()
        row = actors(driver)[args.actor]
        assert row['health'] > 0 and row['state'] == 'chase', row
        samples.append(row)
        if math.dist(before['pos'][:2], row['pos'][:2]) > 24:
            break
    else:
        raise AssertionError(f'Sludgeminion did not move from supported wet floor: {samples[-1]}')
    assert math.hypot(*row['velocity'][:2]) > 0, row
    (report / 'samples.json').write_text(json.dumps(samples, indent=2))
    after = driver.observe()
    assert math.dist(player['pos'], after['pos']) < 1, 'The test must not reposition the player during pursuit'
    driver.diagnostics(f'dk3_runtime_face_target {args.actor} 160', f'target={args.actor}')
    aim_actor(driver, actors(driver)[args.actor])
    capture('sludgeminion-after-pursuit')
    return dict(scope='Untouched player save restored; authored robot, ordinary AI and unchanged player position during measured pursuit. Diagnostic camera placement only after movement acceptance; not fresh campaign traversal.', player=player, before=before, after=row, travel=travel, displacement=math.dist(before['pos'][:2], row['pos'][:2]))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--save', type=Path, required=True)
    parser.add_argument('--actor', type=int, required=True)
    parser.add_argument('--renderer', default='opengl2')
    args = parser.parse_args()
    args.engine, args.report, args.save = args.engine.resolve(), args.report.resolve(), args.save.resolve()
    args.scenario = 'wading'
    args.start_map = 'e1m1a'
    run(args, exercise, setup)
