#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Console-driven save load: loading-bar samples, load time, entities withheld
for configstring publication, and a load after a companion's death."""
import argparse
import json
import re
import shutil
import time
from pathlib import Path

from runtime_bugfix_probe import run
from runtime_input import engine_failure
from runtime_probe import wait


def setup(home, report):
    saves = home / 'state/dk3/saves'
    saves.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.save, saves / 'reported.sav')
    info = args.save.with_suffix('.info')
    if info.exists():
        shutil.copy2(info, saves / 'reported.info')


def cvar(driver, name):
    try:
        text = driver.diagnostics(name, f'"{name}"', seconds=3)
    except Exception:
        return None
    values = re.findall(r'is:\s*"([\d.]+)', text.replace('^7', '').replace('^2', ''))
    return float(values[-1]) if values else None


def load(driver):
    offset, started = len(driver.text()), time.monotonic()
    driver.issue('load reported')
    samples = []
    while True:
        text = driver.text()[offset:]
        if failure := engine_failure(text):
            raise RuntimeError(failure)
        done = 'dk3 region: initial admission committed' in text or 'restoration committed' in text
        value = cvar(driver, 'dk3_loading_progress')
        if value is not None:
            samples.append((round(time.monotonic() - started, 2), value))
        if done:
            break
        if time.monotonic() - started > 180:
            raise RuntimeError('load did not finish')
    seconds = time.monotonic() - started
    state = driver.until(lambda s: s['mode'] == 'normal', seconds=60, description='restored normal input')
    values = [value for _, value in samples]
    # The previous session's completed bar shows until the map change resets
    # it; count from that reset. A refill: the bar falls back after rising.
    reset = next((index for index, value in enumerate(values) if value <= 0.05), 0)
    peak, refills = 0.0, 0
    for value in values[reset:]:
        if value < peak - 0.05:
            refills += 1
        peak = max(peak, value)
    return dict(seconds=round(seconds, 2), samples=samples, refills=refills, map=state['map'], offset=offset)


def pending(driver):
    try:
        text = driver.diagnostics('dk3_runtime_config_pending', 'dk3 config pending:', seconds=3)
    except Exception:
        return None
    match = re.search(r'entities=(\d+) indices=(\d+)', text)
    return dict(entities=int(match.group(1)), indices=int(match.group(2))) if match else None


def after(driver, result, settle=8):
    # Published patches after the load mean entities were withheld meanwhile.
    samples = []
    for _ in range(settle):
        samples.append(pending(driver))
        time.sleep(1)
    patches = driver.text()[result['offset']:].count('dk3 world config: owner=0')
    result.update(pending=samples, patches_after_load=patches)
    return result


def audits(text):
    """Actor id -> health per map, as each world's restoration audit printed it."""
    result = {}
    for map_name, actor, health in re.findall(r'dk3 restore actor: map=(\S+) id=(\d+) health=(-?\d+)', text):
        result.setdefault(map_name, {})[int(actor)] = int(health)
    return result


def wake(driver, name):
    offset = len(driver.text())
    driver.issue(f'dk3_runtime_resident prepare-game {name}')
    wait(driver.process, driver.log, lambda text: f'dk3 restore actors complete: map={name}' in text[offset:] or engine_failure(text[offset:]), 60)
    return audits(driver.text()[offset:]).get(name, {})


def residents(driver, report, results):
    text = driver.text()[results['load']['offset']:]
    restored = sorted(set(re.findall(r'dk3 restore actors complete: map=(\S+)', text)))
    dormant = re.findall(r'dk3 resident: map=(\S+) dormant=restore', text)
    found = dict(restored=restored, dormant=dormant, audits=audits(text))
    if args.wake:
        name = args.wake
        found['woken'] = wake(driver, name)
        # Outside the region and the next exits: released again shortly.
        offset = len(driver.text())
        wait(driver.process, driver.log, lambda text: f'dk3 resident: map={name} dormant=left-region' in text[offset:], 15)
        found['demoted'] = True
        driver.issue('save probe-roundtrip')
        wait(driver.process, driver.log, lambda text: 'dk3 zig: world saved' in text[offset:], 15)
        load_offset = len(driver.text())
        driver.issue('load probe-roundtrip')
        wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text[load_offset:] or 'restoration committed' in text[load_offset:], 120)
        driver.until(lambda s: s['mode'] == 'normal', seconds=60)
        found['roundtrip_dormant'] = re.findall(r'dk3 resident: map=(\S+) dormant=restore', driver.text()[load_offset:])
        found['woken_after_roundtrip'] = wake(driver, name)
    return found


def exercise(driver, report, capture):
    wait(driver.process, driver.log, lambda text: 'dk3 region: initial admission committed' in text, 90)
    driver.until(lambda s: s['mode'] == 'normal', seconds=60)
    results = {}
    results['load'] = after(driver, load(driver))
    capture('loaded')
    if args.residents:
        results['residents'] = residents(driver, report, results)
    if args.companion_death:
        driver.issue('dk3_runtime_damage 1000 superfly')
        time.sleep(8)
        capture('companion-dead')
        results['load_after_companion_death'] = after(driver, load(driver))
        capture('reloaded')
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--save', type=Path, required=True)
    parser.add_argument('--renderer', default='opengl2')
    parser.add_argument('--companion-death', action='store_true')
    parser.add_argument('--residents', action='store_true', help='record restored/dormant maps and restoration audits')
    parser.add_argument('--wake', help='with --residents: wake this dormant map, check demotion and a save/load round trip')
    args = parser.parse_args()
    args.engine, args.report, args.save = args.engine.resolve(), args.report.resolve(), args.save.resolve()
    args.scenario = 'loading'
    args.start_map = 'e1m1a'
    args.developer = True
    args.restore_audit = args.residents
    run(args, exercise, setup)
    print(json.dumps(json.loads((args.report / 'passed.json').read_text())['result'], indent=1)[:4000])
