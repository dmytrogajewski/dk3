#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Sampled dedicated-match evidence for the ten-level bot ladder and its view cone.

One cold match with only bots, walked through several skill levels by changing
`dk3_bot_skill` mid-match exactly as a host can. Reads the `developer 2`
`dk3 bot route` line at 1 Hz and reports per-level target acquisition, hurt-alert
turns and view movement. `--fov` overrides the cone (clamped 1..359 in the game
module) so a narrow and a see-everything cone can be compared at one level.

Sampled smoke only: unsupervised matches, no human at the keyboard, so the rates
are indicative and never a balance decision.
"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path

ROUTE_MARKER = 'dk3 bot route:'
PLAYER_MARKER = 'dk3 match player:'
FIELD = re.compile(r'(\w+)=(-?[\d.]+)')


def route_lines(text):
    """Telemetry lines, tolerant of the cursor junk the console sometimes prefixes them with."""
    for line in text.splitlines():
        position = line.find(ROUTE_MARKER)
        if position >= 0:
            yield line[position:]


def stage(build: Path, assets: Path, home: Path) -> None:
    (home / 'dk3/scripts').mkdir(parents=True)
    for name in ('qagame', 'cgame', 'ui'):
        shutil.copy2(build / 'lib/dk3' / f'{name}.so', home / 'dk3' / f'{name}.so')
    shutil.copy2(build / 'share/dk3/scripts/dk3-projectile-weather.shader',
                 home / 'dk3/scripts/dk3-projectile-weather.shader')
    assert (assets / 'dk3' / 'dk3-maps.pk3').exists(), f'map pack missing under {assets}'


def send(pipe: Path, text: str) -> bool:
    for _ in range(20):
        try:
            descriptor = os.open(pipe, os.O_WRONLY | os.O_NONBLOCK)
        except OSError:
            time.sleep(0.25)
            continue
        try:
            os.write(descriptor, text.encode())
            return True
        except OSError:
            pass
        finally:
            os.close(descriptor)
        time.sleep(0.25)
    return False


def run(args) -> dict:
    if not __debug__:
        raise RuntimeError('Evidence sampling requires assertions')
    if args.from_log is not None:
        return analyse(args.from_log.read_text(errors='replace'),
                       [(int(level), int(seconds)) for level, seconds in (p.split(':') for p in args.phases.split(','))],
                       args, args.from_log, launch=json.loads((args.report / 'inputs.json').read_text())
                       if (args.report / 'inputs.json').exists() else None)
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError('Evidence directory must be fresh (or pass --from-log to re-derive a summary)')
    args.report.mkdir(parents=True, exist_ok=True)
    phases = [(int(level), int(seconds)) for level, seconds in (p.split(':') for p in args.phases.split(','))]
    staging = tempfile.TemporaryDirectory(prefix='dk3-bot-skill-')
    home = Path(staging.name)
    stage(args.build, args.assets, home)
    settings = dict(net_enabled='0', fs_basepath=str(args.assets), fs_homepath=str(home),
                    fs_homedatapath=str(home), fs_homestatepath=str(home / 'state'), com_basegame='dk3',
                    com_pipefile='commands.fifo', vm_game='0', vm_cgame='0', vm_ui='0', dedicated='2',
                    net_port=args.port, g_gametype=args.gametype, dk3_runtime_probe='2', sv_pure='0',
                    dk3_public='0', sv_maxclients='8', bot_minplayers=args.bots,
                    dk3_bot_skill=str(phases[0][0]), developer='2', fraglimit='0', timelimit='0',
                    capturelimit='0', dk3_resume='0', g_doWarmup='0')
    if args.fov:
        settings['dk3_bot_fov'] = str(args.fov)
    seconds = sum(hold for _, hold in phases)
    command = [str(args.guard), '--mem', '2G', '--timeout', f'{seconds + 90}s', '--', str(args.build / 'bin/dk3ded')]
    for key, value in settings.items():
        command += ['+set', key, str(value)]
    command += ['+map', args.map]
    log = args.report / 'server.log'
    pipe = home / 'dk3/commands.fifo'
    with log.open('w') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            for _ in range(90):
                if pipe.exists() and process.poll() is None:
                    break
                time.sleep(0.5)
            else:
                raise RuntimeError('dedicated server never created its command pipe')
            started = time.monotonic()
            for index, (level, hold) in enumerate(phases):
                if int(settings['dk3_bot_skill']) != level and not send(pipe, f'set dk3_bot_skill {level}\n'):
                    raise RuntimeError(f'could not change dk3_bot_skill to {level}')
                deadline = started + sum(hold for _, hold in phases[:index + 1])
                while time.monotonic() < deadline:
                    send(pipe, 'dk3_runtime_match\n')
                    time.sleep(1.5)
        finally:
            process.send_signal(signal.SIGTERM)
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
            staging.cleanup()

    text = log.read_text(errors='replace')
    return analyse(text, phases, args, log, launch=dict(launch=command, settings=settings))


def analyse(text, phases, args, log, launch=None):
    rows = [dict(FIELD.findall(line)) for line in route_lines(text)]
    levels = {}
    for level, hold in phases:
        seen = [row for row in rows if row.get('skill') == str(level)]
        acquired = [row for row in seen if row['target'] not in ('0', '-1')]
        levels[str(level)] = dict(
            held_seconds=hold, samples=len(seen), acquiring_samples=len(acquired),
            per_slot={slot: sum(1 for row in acquired if row['slot'] == slot) for slot in sorted({r['slot'] for r in seen})},
            hurt_alert_samples=sum(1 for row in seen if row['alert'] != '0'),
            distinct_views=len({row['view'] for row in seen}),
            cone=seen[0]['fov'] if seen else None,
            sweep_headings=sorted({row['scan'] for row in seen}),
            blocked_samples=sum(1 for row in seen if row['blocked'] == '1'),
            waypoint_edges=len({row['waypoint'] for row in seen}),
        )
    scores = {}
    for line in text.splitlines():
        position = line.find(PLAYER_MARKER)
        if position < 0:
            continue
        row = dict(FIELD.findall(line[position:]))
        best = scores.setdefault(row['slot'], [0, 0])
        best[0] = max(best[0], int(float(row['score'])))
        best[1] = max(best[1], int(float(row['deaths'])))
    faults = [line for line in text.splitlines()
              if 'runtime failure' in line or 'Assert' in line or 'Bad game system' in line]
    result = dict(scope='Sampled bot-only match evidence for the skill ladder and view cone; '
                      'navigation and vision telemetry only, not level balance and not match acceptance.',
                  map=args.map, gametype=args.gametype, bots=args.bots, fov_override=args.fov,
                  analysed_from_log=str(log),
                  phases=args.phases, samples=len(rows), faults=len(faults),
                  peak_score_by_slot={slot: {'score': value[0], 'deaths': value[1]} for slot, value in sorted(scores.items())},
                  levels=levels)
    (args.report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    if launch is not None:
        (args.report / 'inputs.json').write_text(json.dumps(launch, indent=2) + '\n')
    for line in (f'map={args.map} gametype={args.gametype} fov_override={args.fov} samples={len(rows)} faults={len(faults)}',
                 *[f'skill={level}: {value["acquiring_samples"]}/{value["samples"]} samples acquiring, '
                   f'{value["hurt_alert_samples"]} hurt alerts, {value["distinct_views"]} distinct views, '
                   f'cone={value["cone"]}, blocked={value["blocked_samples"]}, edges={value["waypoint_edges"]}'
                   for level, value in levels.items()]):
        print(line)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', type=Path, default=Path('zig-out/native-dev'),
                        help='native build prefix supplying dk3ded and the three modules')
    parser.add_argument('--assets', type=Path, default=Path('zig-out/play/current/share'),
                        help='filesystem base path whose dk3 subdirectory holds the map packs')
    parser.add_argument('--guard', type=Path, default=Path('zig-out/bin/dkguard'))
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--map', default='e1dm2a')
    parser.add_argument('--gametype', default='0')
    parser.add_argument('--bots', type=int, default=4)
    parser.add_argument('--port', default='27991')
    parser.add_argument('--phases', default='10:22,5:22,1:22', help='level:seconds, changed live in order')
    parser.add_argument('--fov', type=int, default=0, help='cone override, 0 keeps the ladder value')
    parser.add_argument('--from-log', type=Path, help='re-derive result.json from an existing server.log instead of playing a match')
    args = parser.parse_args()
    args.build, args.assets, args.guard, args.report = (path.resolve() for path in (args.build, args.assets, args.guard, args.report))
    args.from_log = args.from_log.resolve() if args.from_log else None
    run(args)
