#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Navigation coverage report: does the compiled AAS know where a player can go?

For each map a dedicated server loads the map alone and runs
`dk3_runtime_navigation_coverage`: a flood of the space reachable from the
player starts over static geometry with the native hulls and moves (standing
step, crouched step or crawl, standing jump of the given height, any drop),
checking every floor reached for an AAS area and for an AAS route from the
start whose flood reached it. Regions of floors without an area ("uncovered"), routed only
through a damaging volume ("gated": compiled as no-entry, though many such
lasers and force fields switch off) or without any route ("unrouted") are
listed largest first. Brush entities are treated as
open, as BSPC treats doors. Diagnostic evidence only: no actor moves.

  runtime_navigation_coverage.py --report DIR [--maps e1m3a e1m3b] [--overlay nav.pk3]

`--overlay` stages packages into the private home ahead of the installed ones
(for instance a recompiled navigation package under test).
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile

from runtime_probe import send, wait

ROOT = Path(__file__).resolve().parents[2]
SUMMARY = re.compile(r'dk3 navcover: seeds=(\d+) nodes=(\d+) routed=(\d+) gated=(\d+) uncovered=(\d+) unrouted=(\d+) crouch=(\d+) jump=(\d+) '
                     r'start_area=(\d+) step=(\d+) jump_height=(\d+) truncated=(\d)')
GAP = re.compile(r'dk3 navcover: gap class=(\w+) floors=(\d+) crouch=(\d+) jump=(\d+) box=([-\d,]+)\.\.([-\d,]+) at=([-\d,]+)')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def coverage(args, name, report):
    with tempfile.TemporaryDirectory(prefix='dk3-navcover-') as staging:
        home = Path(staging)
        (home / 'dk3').mkdir(parents=True)
        shutil.copy2(args.modules / 'qagame.so', home / 'dk3/qagame.so')
        for number, overlay in enumerate(args.overlay):
            shutil.copy2(overlay, home / f'dk3/zzzz-overlay-{number}.pk3')
        values = dict(dedicated='1', net_enabled='0', fs_basepath=str(args.assets), fs_homepath=str(home),
                      fs_homedatapath=str(home), fs_homestatepath=str(home / 'state'), com_basegame='dk3',
                      com_pipefile='commands.fifo', vm_game='0', sv_pure='0', g_gametype=str(args.gametype),
                      dk3_runtime_probe='2', g_spSkill=str(args.skill), dk3_cinematics='0', developer='0')
        command = [str(args.guard), '--mem', '8G', '--timeout', f'{args.timeout}s', '--', str(args.engine / 'bin/dk3ded')]
        for key, value in values.items():
            command += ['+set', key, value]
        command += ['+map', name]
        log = report / f'{name}.log'
        result = dict(map=name, command=command)
        with log.open('w') as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            pipe = home / 'dk3/commands.fifo'
            try:
                wait(process, log, lambda text: pipe.exists() and 'isolated bootstrap' in text, 120)
                offset = log.stat().st_size
                send(pipe, f'dk3_runtime_navigation_coverage {args.step} {args.jump}')
                text = wait(process, log, lambda text: re.search(r'dk3 navcover: (regions=\d+ complete|failed)', text[offset:]) is not None,
                            args.timeout)[offset:]
                failed = re.search(r'dk3 navcover: failed (\w+)', text)
                if failed:
                    raise RuntimeError(f'coverage failed: {failed[1]}')
                summary = SUMMARY.search(text)
                keys = ('seeds', 'floors', 'routed', 'gated', 'uncovered', 'unrouted', 'crouch', 'jump', 'start_area', 'step', 'jump_height', 'truncated')
                result.update({key: int(value) for key, value in zip(keys, summary.groups())})
                result['gaps'] = [dict(kind=row[1], floors=int(row[2]), crouch=int(row[3]), jump=int(row[4]),
                                       low=[int(v) for v in row[5].split(',')], high=[int(v) for v in row[6].split(',')],
                                       at=[int(v) for v in row[7].split(',')]) for row in GAP.finditer(text)]
                send(pipe, 'quit')
                process.wait(timeout=30)
                result['status'] = 'reported'
            except Exception as error:
                result.update(status='failed', error=str(error))
            finally:
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=15)
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--engine', type=Path, default=ROOT / 'zig-out/native-dev', help='prefix supplying bin/dk3ded')
    parser.add_argument('--modules', type=Path, help='directory with qagame.so (default <engine>/lib/dk3)')
    parser.add_argument('--assets', type=Path, default=ROOT / 'zig-out/native-dev/play/current/share',
                        help='fs_basepath whose dk3 directory holds the packages')
    parser.add_argument('--guard', type=Path, default=ROOT / 'zig-out/bin/dkguard')
    parser.add_argument('--overlay', type=Path, action='append', default=[], help='package staged ahead of the installed ones')
    parser.add_argument('--maps', nargs='*', help='map names (default: every map in dk3-maps.pk3)')
    parser.add_argument('--gametype', type=int, default=2, help='2 selects the campaign navigation for --skill')
    parser.add_argument('--skill', type=int, default=3, choices=(1, 3, 5))
    parser.add_argument('--step', type=int, default=16, help='flood grid in world units')
    parser.add_argument('--jump', type=int, default=33, help='standing jump height the flood may climb')
    parser.add_argument('--timeout', type=int, default=600, help='seconds per map')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(argv)
    args.engine, args.assets, args.guard, args.report = (p.resolve() for p in (args.engine, args.assets, args.guard, args.report))
    args.modules = (args.modules or args.engine / 'lib/dk3').resolve()
    args.overlay = [p.resolve() for p in args.overlay]
    if args.report.exists() and any(args.report.iterdir()):
        parser.error('the report directory must be fresh')
    args.report.mkdir(parents=True, exist_ok=True)
    if not args.maps:
        with zipfile.ZipFile(args.assets / 'dk3/dk3-maps.pk3') as package:
            args.maps = sorted(Path(name).stem for name in package.namelist() if name.startswith('maps/') and name.endswith('.bsp'))
    inputs = dict(dk3ded=digest(args.engine / 'bin/dk3ded'), qagame=digest(args.modules / 'qagame.so'),
                  overlays={str(p): digest(p) for p in args.overlay}, skill=args.skill, gametype=args.gametype,
                  step=args.step, jump=args.jump)
    rows = []
    for name in args.maps:
        row = coverage(args, name, args.report)
        rows.append(row)
        if row['status'] == 'reported':
            print(f"{name}: floors={row['floors']} gated={row['gated']} uncovered={row['uncovered']} unrouted={row['unrouted']} "
                  f"crouch={row['crouch']} jump={row['jump']} gaps={len(row['gaps'])}", flush=True)
        else:
            print(f"{name}: {row['status']} {row.get('error', '')}", flush=True)
        (args.report / 'coverage.json').write_text(json.dumps(dict(inputs=inputs, maps=rows), indent=1) + '\n')
    return 0 if all(row['status'] == 'reported' for row in rows) else 1


if __name__ == '__main__':
    raise SystemExit(main())
