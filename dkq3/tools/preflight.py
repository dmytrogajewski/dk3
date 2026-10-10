#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Report the leaks a long agent session leaves behind, and delete nothing.

Why this exists
---------------
`run_capped.py` bounds what *one* run can allocate.  It cannot bound what the
machine already lost: the crash record in that tool's docstring is a machine that
arrived at 7/7 G swap and 100 %-full `/home` not through one big run but through
*accumulated residue* -- ten `dk3ded` servers still resident hours after the probes
that started them, each holding a RAM-backed `/tmp/dk3-*` homepath, plus one
multi-gigabyte `zig-out/native-dev/play/<hash>` installation per session that ever
installed a build.  That is tens of gigabytes of the filesystem and of tmpfs in
this checkout right now, and nothing reclaims any of it.

Why it only *reports*: a leaked-looking install is not necessarily dead.  These
directories are shared by concurrent agent sessions on this box, and a peer's
running server holds one open right now.  Deleting another session's installation
or killing another session's server is a data-destroying act performed on somebody
else's work, so this tool's job ends at naming the facts -- age, resident set, size,
who references what -- and letting the owner decide.  There is deliberately no
`--kill` and no `--prune`.

Usage
-----
    python3 dkq3/tools/preflight.py                       # human report
    python3 dkq3/tools/preflight.py --stale-minutes 45    # the recorded threshold
    python3 dkq3/tools/preflight.py --json | jq .         # machine-readable
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

#: What the engine and the compilers are called once the launcher has run them.
RESIDENT = ('dk3ded', 'dk3', 'q3map2', 'bspc')


def clock_ticks():
    try:
        return int(os.sysconf('SC_CLK_TCK'))
    except (ValueError, OSError):
        return 100


def processes():
    """-> [{pid, name, age_s, rss_kib, cmdline, cwd, files}] for every readable process.

    `age_s` is wall-clock life, derived from the task's own start time in clock
    ticks against the kernel's uptime; `ps -o etimes` is a subprocess per batch and
    disagrees about the run queue.  `cwd` and `files` matter because a process that
    *opened* an install without naming it in argv still holds it -- which is exactly
    what an install under a live server looks like.
    """
    ticks, up = clock_ticks(), float(Path('/proc/uptime').read_text().split()[0])
    page = os.sysconf('SC_PAGE_SIZE')
    found = []
    for entry in Path('/proc').iterdir():
        if not entry.name.isdigit():
            continue
        try:
            cmdline = entry.joinpath('cmdline').read_bytes().replace(b'\0', b' ').decode(
                'utf-8', 'replace').strip()
            stat = entry.joinpath('stat').read_text()
            # comm is `(name)` and may itself contain spaces: everything after the
            # last `)` is field 3 onwards, so starttime is index 19 and rss index 21.
            tail = stat[stat.rindex(')') + 2:].split()
            start_ticks, rss_pages = int(tail[19]), int(tail[21])
            name = stat[stat.index('(') + 1:stat.rindex(')')]
        except (OSError, ValueError, IndexError):
            continue                                     # kernel threads and exits
        try:
            cwd = os.readlink(entry / 'cwd')
        except OSError:
            cwd = ''
        files = []
        try:
            for descriptor in (entry / 'fd').iterdir():
                try:
                    files.append(os.readlink(descriptor))
                except OSError:
                    pass
        except OSError:
            pass
        found.append(dict(pid=int(entry.name), name=name,
                          age_s=max(0.0, up - start_ticks / float(ticks or 100)),
                          rss_kib=rss_pages * page // 1024, cmdline=cmdline, cwd=cwd,
                          files=files))
    return found


def gpu_state():
    """-> (used MiB, total MiB, [(pid, MiB)]) or None where there is no NVIDIA card."""
    if shutil.which('nvidia-smi') is None:
        return None
    total = subprocess.run(['nvidia-smi', '--query-gpu=memory.used,memory.total',
                            '--format=csv,noheader,nounits'],
                           capture_output=True, text=True, check=False)
    apps = subprocess.run(['nvidia-smi', '--query-compute-apps=pid,used_memory',
                           '--format=csv,noheader,nounits'],
                          capture_output=True, text=True, check=False)
    if total.returncode:
        return None
    used, size = (int(value) for value in total.stdout.strip().splitlines()[0].split(','))
    residents = []
    for line in (apps.stdout.splitlines() if apps.returncode == 0 else []):
        if line.strip():
            pid, _, memory = line.partition(',')
            residents.append((int(pid), int(memory.strip())))
    return used, size, residents


def directory_gib(path):
    """-> (GiB, file count) under `path`, metadata only -- no content is read."""
    total, count = 0, 0
    for root, _dirs, names in os.walk(path):
        for name in names:
            try:
                total += os.lstat(Path(root) / name).st_size
                count += 1
            except OSError:
                pass
    return total / 1024 ** 3, count


def audit(prefix, stale_minutes):
    """-> the report: machine state, engine processes, orphan installs, orphan tmpfs."""
    prefix = Path(prefix).resolve()
    procs = processes()
    now = time.time()
    haystack = []
    for proc in procs:
        haystack.append(proc['cmdline'])
        haystack.append(proc['cwd'])
        haystack.extend(proc['files'])
    haystack = [text for text in haystack if text]

    engine = []
    for proc in procs:
        if proc['name'] not in RESIDENT:
            continue
        home = next((token for token in proc['cmdline'].split()
                     if token.startswith('/tmp/dk3-')), '')
        engine.append(dict(pid=proc['pid'], name=proc['name'],
                           age_min=round(proc['age_s'] / 60.0, 1),
                           rss_mib=round(proc['rss_kib'] / 1024.0, 1), tmpfs_home=home,
                           stale=proc['age_s'] > stale_minutes * 60.0,
                           cmdline=proc['cmdline'][:400]))
    # A `dkguard` whose engine child is gone is a leak in its own right; one still
    # supervising something is not.  The guard carries its child's argv in its own.
    for proc in procs:
        if proc['name'] != 'dkguard':
            continue
        guarded = any(child['name'] in RESIDENT
                      and proc['cmdline'][:60] in child['cmdline'][:120] for child in procs)
        if guarded:
            continue
        engine.append(dict(pid=proc['pid'], name='dkguard',
                           age_min=round(proc['age_s'] / 60.0, 1),
                           rss_mib=round(proc['rss_kib'] / 1024.0, 1), tmpfs_home='',
                           stale=proc['age_s'] > stale_minutes * 60.0,
                           cmdline=proc['cmdline'][:400]))

    play = prefix / 'play'
    installs = sorted(one for one in play.glob('*') if one.is_dir()) if play.is_dir() else []
    try:
        current = os.path.realpath(play / 'current')
    except OSError:
        current = ''
    orphans = []
    for install in installs:
        if any(str(install) in needle or install.name in needle for needle in haystack):
            continue
        if os.path.realpath(install) == current:      # the install the next probe will use
            continue
        gib, files = directory_gib(install)
        orphans.append(dict(path=str(install), gib=round(gib, 2), files=files,
                            age_days=round((now - install.stat().st_mtime) / 86400.0, 2)))

    tmpfs = []
    for home in sorted(Path('/tmp').glob('dk3-*')):
        if any(home.name in needle for needle in haystack):
            continue
        gib, files = directory_gib(home)
        if not files and gib < 0.001:
            continue
        tmpfs.append(dict(path=str(home), gib=round(gib, 3), files=files,
                          age_days=round((now - home.stat().st_mtime) / 86400.0, 2)))

    fields = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, _, rest = line.partition(':')
        fields[key] = int(rest.split()[0]) // 1024
    swap_total = fields.get('SwapTotal', 0)
    disk = os.statvfs(prefix)
    return dict(
        machine=dict(mem_available_mib=fields['MemAvailable'], mem_total_mib=fields['MemTotal'],
                     swap_used_mib=swap_total - fields.get('SwapFree', 0),
                     swap_total_mib=swap_total,
                     disk_free_gib=round(disk.f_bavail * disk.f_frsize / 1024 ** 3, 1),
                     disk_path=str(prefix), gpu=gpu_state()),
        stale_minutes=stale_minutes, engine_processes=engine,
        orphan_installs=orphans, orphan_tmpfs=tmpfs,
        totals=dict(engine_count=len(engine),
                    stale_count=sum(1 for row in engine if row['stale']),
                    stale_rss_mib=round(sum(row['rss_mib'] for row in engine if row['stale']), 1),
                    orphan_install_gib=round(sum(row['gib'] for row in orphans), 1),
                    orphan_tmpfs_gib=round(sum(row['gib'] for row in tmpfs), 2)))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--prefix', default='zig-out/native-dev',
                        help='the development installation whose play/ tree holds the installs')
    parser.add_argument('--stale-minutes', type=float, default=45.0,
                        help='an engine process older than this is reported as a suspected leak')
    parser.add_argument('--json', action='store_true', help='emit the report as JSON')
    arguments = parser.parse_args()

    report = audit(arguments.prefix, arguments.stale_minutes)
    if arguments.json:
        print(json.dumps(report, indent=1))
        return 0

    machine = report['machine']
    print('machine: %d MiB available of %d MiB, swap %d/%d MiB used, %.1f GiB free under %s'
          % (machine['mem_available_mib'], machine['mem_total_mib'], machine['swap_used_mib'],
             machine['swap_total_mib'], machine['disk_free_gib'], machine['disk_path']))
    if machine['gpu'] is None:
        print('gpu: no nvidia-smi')
    else:
        used, size, residents = machine['gpu']
        print('gpu: %d/%d MiB used; compute residents: %s'
              % (used, size,
                 ', '.join('pid %d (%d MiB)' % pair for pair in residents) or 'none'))

    totals = report['totals']
    print('\nengine processes: %d running, %d older than %.0f min, %.0f MiB resident between '
          'the stale ones' % (totals['engine_count'], totals['stale_count'],
                              report['stale_minutes'], totals['stale_rss_mib']))
    for row in sorted(report['engine_processes'], key=lambda one: -one['age_min']):
        if not row['stale']:
            continue
        print('  pid %-8s %-7s %7.0f min %8.0f MiB  tmpfs %s'
              % (row['pid'], row['name'], row['age_min'], row['rss_mib'], row['tmpfs_home'] or '-'))
        print('      %s' % row['cmdline'][:150])
    fresh = sum(1 for row in report['engine_processes'] if not row['stale'])
    if fresh:
        print('  (plus %d engine processes younger than the threshold, not reported)' % fresh)

    print('\nplay/ installs referenced by no live process: %d (%.1f GiB reclaimable)'
          % (len(report['orphan_installs']), totals['orphan_install_gib']))
    for row in sorted(report['orphan_installs'], key=lambda one: -one['gib']):
        print('  %8.2f GiB %6d files %6.1f d old  %s'
              % (row['gib'], row['files'], row['age_days'], row['path']))

    print('\n/tmp/dk3-* homepaths referenced by no live process: %d (%.2f GiB of tmpfs)'
          % (len(report['orphan_tmpfs']), totals['orphan_tmpfs_gib']))
    for row in sorted(report['orphan_tmpfs'], key=lambda one: -one['gib']):
        print('  %8.3f GiB %6d files %6.1f d old  %s'
              % (row['gib'], row['files'], row['age_days'], row['path']))

    print('\nNothing was killed and nothing was deleted. These directories are shared with '
          'concurrent sessions, and an install that looks orphaned may belong to a peer '
          'that is mid-run; review the list and remove what is yours.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
