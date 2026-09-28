#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Controlled pickup, first-person movement and item/weapon presentation regressions."""
import argparse
import math
from pathlib import Path
import re
import time

from runtime_bugfix_probe import run
from runtime_probe import wait


def admitted(driver):
    # An initial snapshot may briefly process input before connected-region
    # admission holds it again. Wait for the actual final admission boundary.
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 90)
    return driver.until(lambda s: s['mode'] == 'normal', description='native fixture ready')


def view(driver):
    text = driver.diagnostics("dk3_runtime_presentation", "dk3 presentation:")
    match = re.search(r"dk3 view motion: now=(\d+) height=([-\d.]+) offset=([-\d.]+) steps=(\d+) pos=([^\n]+)", text)
    assert match, "Missing actual camera sample"
    return dict(now=int(match[1]), height=float(match[2]), offset=float(match[3]),
                steps=int(match[4]), pos=tuple(map(float, match[5].split(','))))


def place(driver, point):
    driver.issue("dk3_runtime_place " + " ".join(map(str, point)))
    driver.until(lambda s: math.dist(s['pos'], point) < 32, description="placement acknowledged")
    state = driver.stop_forward(settle_vertical=True)
    assert state['ground'] != 2047, f"Placement did not reach walkable ground: {state}"
    return state


def pickup(driver, report, capture):
    admitted(driver)
    driver.issue("dk3_runtime_probe_health 1000")
    driver.until(lambda s: s['health'] == 1000, description="controlled fixture health")
    items = driver.diagnostics("dk3_runtime_items", "zig item id=81 ")
    assert re.search(r"id=81 class=weapon_ionblaster visible=1", items)
    assert driver.observe()['weapon'] != 2
    place(driver, (1648, -2424, 552))
    driver.aim(180, 0)
    before = len(driver.text())
    driver.issue('+forward')
    acquired = driver.until(lambda s: s['weapon'] == 2, description="ordinary Ion pickup contact")
    driver.stop_forward(settle_vertical=True)
    driver.ready(2)
    driver.until(lambda s: s['now'] > acquired['now'] + 2000, description="pickup presentation completed")
    transitions = re.findall(r"dk3 zig view: weapon=(\d+) phase=(\w+) pose=(\w+)", driver.text()[before:])
    count = sum(weapon == '2' and phase == 'ready' for weapon, phase, _ in transitions)
    capture('ion-picked-up')
    assert count == args.expected_draws, f"Expected {args.expected_draws} Ion draw, observed {count}: {transitions}"
    return dict(acquired=acquired, transitions=transitions, draws=count)


def scenario(driver, report, capture):
    result = pickup(driver, report, capture)
    if args.pickup_only:
        return result
    # All view sampling uses observed rendered times; command dispatch isn't acceptance.
    baseline = view(driver)
    driver.issue('+movedown')
    crouch = []
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        row = view(driver)
        crouch.append(row)
        if row['height'] < 0 and row['offset'] == 0:
            break
    assert any(row['height'] < 0 and 0 < row['offset'] < 24 for row in crouch), crouch
    assert crouch[-1]['height'] < 0 and crouch[-1]['offset'] == 0
    assert abs(crouch[-1]['pos'][2] - baseline['pos'][2] + 24) < .1
    capture('crouched')
    driver.issue('-movedown')
    standing = []
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        row = view(driver)
        standing.append(row)
        if row['height'] == 22 and row['offset'] == 0:
            break
    assert any(row['height'] == 22 and -24 < row['offset'] < 0 for row in standing), standing
    result.update(crouch=crouch, standing=standing)
    # Restore crosses a real snapshot/incarnation boundary and must not draw twice.
    driver.save('view_ready')
    before = len(driver.text())
    driver.load('view_ready')
    driver.ready(2)
    driver.elapsed(1500)
    restored = re.findall(r"dk3 zig view: weapon=2 phase=(\w+) pose=(\w+)", driver.text()[before:])
    assert sum(phase == 'ready' for phase, _ in restored) <= 1, restored
    result['restored'] = restored
    # Authored pickup models: fixed camera, distinct observed render times.
    # These pickups occupy low rock alcoves; use their normal crouched approach.
    driver.issue('+movedown')
    driver.until(lambda s: s['up'] < 0, description='crouch input processed')
    for name, point, vantage in [('armor', (-428, -1572, 550), (-500, -1560, 552)),
                                  ('ammo', (912, -2352, 412), (840, -2336, 428.125))]:
        state = place(driver, vantage)
        delta = [point[i] - state['pos'][i] for i in range(3)]
        delta[2] -= 22
        driver.aim(math.degrees(math.atan2(delta[1], delta[0])), -math.degrees(math.atan2(delta[2], math.hypot(*delta[:2]))))
        capture(name + '-first')
        first = view(driver)
        driver.until(lambda s: s['now'] >= first['now'] + 600, description="pickup rotation render interval")
        second = view(driver)
        assert math.dist(first['pos'], second['pos']) < .01, "Moving camera invalidates item comparison"
        capture(name + '-second')
        result[name] = dict(first=first, second=second)
    place(driver, (1648, -2424, 552))
    driver.issue('-movedown')
    driver.until(lambda s: s['up'] == 0, description='crouch release processed')
    driver.aim(180, 0)
    for effect in range(3):
        driver.issue(f'cg_shinyWeapons {effect}')
        driver.elapsed(150)
        capture(f'shine-{effect}')
    result['scope'] = 'Controlled authored pickup contacts, camera transitions/restoration and rendered item/weapon effects; diagnostic placement/health, no connected campaign acceptance.'
    return result


def stair_scenario(driver, report, capture):
    admitted(driver)
    # Supplied e1m1c has successive 144/160/176/192-unit floor tops here.
    # Ascend these real authored steps without jumping or changing collision.
    stairs = []
    for start, end in [((1480, -980, 170), (1350, -980, 216))]:
        place(driver, start)
        driver.aim(math.degrees(math.atan2(end[1] - start[1], end[0] - start[0])), 0)
        initial = view(driver)
        driver.issue('+forward')
        deadline = time.monotonic() + .65
        while time.monotonic() < deadline:
            stairs.append(view(driver))
        driver.stop_forward(settle_vertical=True)
        if any(row['steps'] > initial['steps'] and row['offset'] < 0 for row in stairs):
            break
    assert any(row['steps'] > 0 and row['offset'] < 0 for row in stairs), 'No actual smoothed stair ascent observed'
    capture('stairs')
    return dict(stairs=stairs, scope='Diagnostic placement followed by normal walking up authored e1m1c steps; no route acceptance.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl1')
    parser.add_argument('--pickup-only', action='store_true')
    parser.add_argument('--stairs-only', action='store_true')
    parser.add_argument('--expected-draws', type=int, default=1)
    args = parser.parse_args()
    args.engine, args.report = args.engine.resolve(), args.report.resolve()
    args.start_map, args.scenario, args.developer = 'e1m1c' if args.stairs_only else 'e1m1a', 'view', True
    run(args, stair_scenario if args.stairs_only else scenario)
