#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Headless end-to-end campaign run driven by the scripted co-op bot.

A dedicated server runs the real native campaign; the bot is its single-player
client and plays a Lua route (dkq3/coop) with ordinary user commands. Simulation
uses exact 50 ms frames (`fixedtime 50`) without waiting for the wall clock
(`timedemo 1`), so everything inside is the normal game, only faster.

Evidence is the `dk3 coop:` event stream in server.log, summarised in result.json.
Run under dkguard (no --headless/--gpu needed: the dedicated server renders nothing).
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
EVENT = re.compile(r'dk3 coop: (.*)')
FIELD = re.compile(r'(\w+)=("([^"]*)"|\S+)')


def parse_event(line):
    """`dk3 coop: t=1 event=x key=value detail="text"` → dict, tolerant of console prefixes."""
    match = EVENT.search(line)
    if not match:
        return None
    return {key: quoted if quoted or raw.startswith('"') else raw for key, raw, quoted in FIELD.findall(match.group(1))}


def summarise(events, *, wall_seconds=None, exit_code=None):
    levels, failures, deaths, actions, done = [], [], [], 0, 0
    outcome, last_status, last_time = 'incomplete', None, 0
    for event in events:
        kind = event.get('event')
        if 't' in event:
            try:
                last_time = max(last_time, int(event['t']))
            except ValueError:
                pass
        if kind == 'level':
            levels.append(dict(detail_fields(event.get('detail', '')), t=event.get('t')))
        elif kind == 'action':
            actions += 1
        elif kind == 'done':
            done += 1
        elif kind in ('failed', 'fail', 'script_error'):
            failures.append(event)
            if kind == 'fail':
                outcome = 'failed'
        elif kind == 'death':
            deaths.append(event)
        elif kind == 'status':
            last_status = event
        elif kind == 'finish':
            outcome = 'finished' if outcome != 'failed' else outcome
    result = dict(outcome=outcome, levels=levels, maps=[level.get('map') for level in levels],
                  actions_started=actions, actions_done=done, failures=failures, deaths=deaths,
                  last_status=last_status, game_ms=last_time, exit_code=exit_code)
    if wall_seconds:
        result['wall_seconds'] = round(wall_seconds, 1)
        result['speedup'] = round(last_time / 1000 / wall_seconds, 1) if wall_seconds > 0 else None
    return result


def detail_fields(text):
    return {key: value for key, value in (pair.split('=', 1) for pair in text.split() if '=' in pair)}


def digest(path):
    with open(path, 'rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def stage(args, home):
    (home / 'dk3').mkdir(parents=True)
    shutil.copy2(args.modules / 'qagame.so', home / 'dk3/qagame.so')
    shutil.copytree(args.routes, home / 'dk3/coop')
    for number, overlay in enumerate(args.overlay):
        shutil.copy2(overlay, home / f'dk3/zzzz-overlay-{number}.pk3')
    if args.load:
        (home / 'state/dk3/saves').mkdir(parents=True)
        shutil.copy2(args.load, home / 'state/dk3/saves/coop-resume.sav')
    assert (args.assets / 'dk3' / 'dk3-maps.pk3').exists(), f'map pack missing under {args.assets}'
    assert (args.assets / 'dk3' / 'dk3/campaign-regions.cfg').exists() or (args.assets / 'dk3' / 'campaign-regions.cfg').exists(), \
        f'campaign region manifest missing under {args.assets}'


def settings(args, home):
    values = dict(dedicated='1', net_enabled='0', fs_basepath=str(args.assets), fs_homepath=str(home),
                  fs_homedatapath=str(home), fs_homestatepath=str(home / 'state'), com_basegame='dk3',
                  com_pipefile='commands.fifo', vm_game='0', sv_pure='0', g_gametype='2',
                  dk3_runtime_probe='2', g_spSkill=str(args.skill), dk3_cinematics=str(args.cinematics),
                  dk3_jobs=str(args.jobs), dk3_resume='0', dk3_travel_pending='0', sv_fps='20',
                  dk3_coop_script=f'coop/{args.script}', dk3_coop_skill=str(args.bot_skill),
                  dk3_coop_quit='1', dk3_coop_status_ms=str(args.status_ms), developer=str(args.developer))
    if not args.realtime:
        values.update(fixedtime='50', timedemo='1')
    if args.load:
        values['dk3_coop_load'] = 'coop-resume'
        if args.stage:
            # Treat the loaded save as a restoration inside that stage of the map.
            values['dk3_coop_level'] = args.map
            values['dk3_coop_checkpoint'] = f'{args.map} {args.stage}'
            # Restored again after a companion loss: the same stage.
            values['dk3_coop_resume_checkpoint'] = f'{args.map} {args.stage}'
    return values


def run(args):
    if not __debug__:
        raise RuntimeError('Evidence requires Python assertions')
    if args.report.exists() and any(args.report.iterdir()):
        raise RuntimeError('Evidence directory must be fresh')
    args.report.mkdir(parents=True, exist_ok=True)
    staging = tempfile.TemporaryDirectory(prefix='dk3-coop-bot-')
    home = Path(staging.name)
    stage(args, home)
    values = settings(args, home)
    command = [str(args.guard), '--mem', args.mem, '--timeout', f'{args.timeout + 30}s', '--', str(args.engine / 'bin/dk3ded')]
    for key, value in values.items():
        command += ['+set', key, value]
    command += ['+map', args.map]
    inputs = dict(launch=command, settings=values, script=args.script,
                  overlays={str(path): digest(path) for path in args.overlay},
                  identity={'qagame.so': digest(args.modules / 'qagame.so'), 'dk3ded': digest(args.engine / 'bin/dk3ded'),
                            **{f'coop/{p.relative_to(args.routes)}': digest(p) for p in sorted(args.routes.rglob('*.lua'))}})
    (args.report / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    log = args.report / 'server.log'
    events = []
    started = time.monotonic()
    exit_code = None
    with log.open('w') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            offset = 0
            deadline = started + args.timeout
            while time.monotonic() < deadline:
                text = log.read_text(errors='replace')
                complete, _, _ = text[offset:].rpartition('\n')
                for line in complete.splitlines():
                    event = parse_event(line)
                    if event is None:
                        if line.startswith('ERROR: ') or 'fatal crashed' in line or 'Zig runtime:' in line:
                            events.append(dict(event='fail', reason=line.strip()))
                            print(line, flush=True)
                        continue
                    events.append(event)
                    if event.get('event') != 'status' or args.verbose:
                        print(line[line.find('dk3 coop:'):], flush=True)
                offset += len(complete) + (1 if complete else 0)
                if any(e.get('event') in ('finish', 'fail') for e in events):
                    break
                if process.poll() is not None:
                    break
                time.sleep(0.2)
            else:
                events.append(dict(event='fail', reason=f'wall-clock timeout after {args.timeout} s'))
            try:
                exit_code = process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                pass
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    exit_code = process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    exit_code = process.wait(timeout=10)
            saves = home / 'state/dk3/saves'
            if saves.is_dir():
                shutil.copytree(saves, args.report / "saves", dirs_exist_ok=True)
            staging.cleanup()
    # Re-read once more so trailing lines written during shutdown are included.
    events = [e for e in (parse_event(line) for line in log.read_text(errors='replace').splitlines()) if e] + \
             [e for e in events if 'reason' in e and e.get('event') == 'fail' and 't' not in e]
    result = summarise(events, wall_seconds=time.monotonic() - started, exit_code=exit_code)
    result['scope'] = ('Headless dedicated-server campaign run by the scripted co-op bot: authoritative '
                       'gameplay, travel, saves and region admission. Client rendering, audio and '
                       'prediction are not exercised.')
    (args.report / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f"coop bot: outcome={result['outcome']} maps={'>'.join(m or '?' for m in result['maps'])} "
          f"actions={result['actions_done']}/{result['actions_started']} deaths={len(result['deaths'])} "
          f"game={result['game_ms'] / 1000:.0f}s wall={result.get('wall_seconds')}s speedup={result.get('speedup')}x")
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--engine', type=Path, default=ROOT / 'zig-out/native-dev', help='prefix supplying bin/dk3ded')
    parser.add_argument('--modules', type=Path, help='directory with qagame.so (default <engine>/lib/dk3)')
    parser.add_argument('--assets', type=Path, default=ROOT / 'zig-out/native-dev/play/current/share',
                        help='fs_basepath whose dk3 directory holds the packages and campaign-regions.cfg')
    parser.add_argument('--guard', type=Path, default=ROOT / 'zig-out/bin/dkguard')
    parser.add_argument('--routes', type=Path, default=ROOT / 'dkq3/coop', help='route scripts staged as coop/')
    parser.add_argument('--script', default='campaign.lua', help='entry route inside --routes')
    parser.add_argument('--map', default='intro', help='first map; New Game starts at intro')
    parser.add_argument('--load', type=Path, help='ordinary .sav to resume from (use with --map set to its map)')
    parser.add_argument('--stage', type=int, help='with --load: resume the level body at this stage index')
    parser.add_argument('--skill', type=int, default=3, choices=(1, 3, 5), help='g_spSkill: Ronin 1, Samurai 3, Shogun 5')
    parser.add_argument('--bot-skill', type=int, default=10, help='co-op bot perception/handling ladder 1..10')
    parser.add_argument('--cinematics', type=int, default=1, choices=(0, 1), help='1 plays authored cinematics in full')
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--developer', type=int, default=0)
    parser.add_argument('--status-ms', type=int, default=1000, help='interval of status lines (route authoring traces)')
    parser.add_argument('--realtime', action='store_true', help='wall-clock pacing instead of fast simulation')
    parser.add_argument('--timeout', type=int, default=3600, help='wall-clock seconds')
    parser.add_argument('--mem', default='8G')
    parser.add_argument('--verbose', action='store_true', help='also echo 1 Hz status lines')
    parser.add_argument('--overlay', type=Path, action='append', default=[],
                        help='package staged ahead of the installed ones (e.g. recompiled navigation under test)')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args(argv)
    args.overlay = [path.resolve() for path in args.overlay]
    args.engine, args.assets, args.guard, args.routes, args.report = (
        path.resolve() for path in (args.engine, args.assets, args.guard, args.routes, args.report))
    args.modules = (args.modules or args.engine / 'lib/dk3').resolve()
    args.load = args.load.resolve() if args.load else None
    result = run(args)
    return 0 if result['outcome'] == 'finished' else 1


if __name__ == '__main__':
    sys.exit(main())
