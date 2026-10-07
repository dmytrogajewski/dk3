# SPDX-License-Identifier: GPL-2.0-or-later
"""Run a heavy asset/dev step inside its own memory-capped cgroup.

Why this exists
---------------
Building japanDM's images killed this machine's desktop session three times.  The
kernel log is exact about it::

    Out of memory: Killed process 1557333 (python3.14) total-vm:60115796kB,
                                            anon-rss:50802100kB
    app-niri-foot-1521783.scope: Consumed 1m32s CPU, 48.6G memory peak, 2.2G swap peak

Two separate faults are visible there, and only one of them is a bug in the tool
being run:

1. the tool allocated ~47 GB for work that legitimately needs ~240 MB (a NumPy
   broadcast bug, since fixed and guarded); and
2. **the tool was running in the wrong cgroup.**  Anything started from a
   terminal on this desktop is a child of the compositor, so its memory is
   charged to `niri.service`.  When the limit ran out the kernel picked the
   biggest process -- my python -- and systemd then marked the *compositor's*
   unit as failed by oom-kill, which is why the screen died instead of a build
   failing.

A cap inside the process (`RLIMIT_AS`) fixes the first but not the second: an
uncaught native allocation, or a process that outruns its own limit, still dies in
the compositor's cgroup.  What actually protects the session is a **cgroup ceiling
owned by the run itself**, which is what `systemd-run --scope` gives: the kernel
then reports `CONSTRAINT_MEMCG` and kills inside that scope, so the worst case a
mistake can cause is a failed build.

That is the whole job here: ask for the ceiling, verify the machine can afford the
run before starting it, and report what the run actually peaked at afterwards so
the number is on the record rather than inferred from a crash.

Usage
-----
    python3 dkq3/tools/run_capped.py --memory-gib 8 -- python3.14 -B \\
        dkq3/tools/craft_textures.py --recipes maps/japanDM/textures.py --out ...
    python3 dkq3/tools/run_capped.py --memory-gib 12 --need-vram-mib 18000 -- \\
        python3.14 -B dkq3/tools/qwen_studio.py --out ...
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile

#: Refuse to start below this much available RAM.  Chosen so that a run which then
#: misbehaves still leaves the desktop's own working set untouched rather than
#: trading a failed build for a lost session.
RAM_FLOOR_MIB = 6000
VRAM_FLOOR_MIB = 2000


def memory_available():
    """-> (available MiB, free MiB, swap free MiB) from the kernel's own counts."""
    fields = {}
    for line in Path('/proc/meminfo').read_text().splitlines():
        key, _, rest = line.partition(':')
        fields[key] = int(rest.split()[0]) // 1024
    return (fields['MemAvailable'], fields['MemFree'], fields.get('SwapFree', 0))


def vram_free():
    """-> (free MiB, total MiB) on the first NVIDIA GPU, or None where there is none."""
    if shutil.which('nvidia-smi') is None:
        return None
    probe = subprocess.run(['nvidia-smi', '--query-gpu=memory.used,memory.total',
                            '--format=csv,noheader,nounits'],
                           capture_output=True, text=True, check=False)
    if probe.returncode != 0:
        return None
    used, total = (int(value) for value in probe.stdout.strip().splitlines()[0].split(','))
    return total - used, total


def self_reporting_scope(command, ceiling_mib, allow_swap, report_path):
    """-> argv that runs `command` in a capped scope and records its peak on exit.

    The peak has to be read from *inside* the scope.  A scope's cgroup directory is
    removed the moment its last process exits, so asking systemd afterwards -- via
    `systemctl show -p MemoryPeak`, or by opening /sys/fs/cgroup/.../memory.peak --
    races a unit that is already gone and usually reports nothing.  The wrapper
    shell is still inside the cgroup when the command returns, so it can cat its own
    `memory.peak` while the numbers are alive and hand them back in a file.
    """
    inner = '%s\nrc=$?\n' \
            'cg=$(awk -F: \'$1=="0"||$1=="memory"{print $3; exit}\' /proc/self/cgroup)\n' \
            '{ cat /sys/fs/cgroup$cg/memory.peak 2>/dev/null || echo -1;\n' \
            '  cat /sys/fs/cgroup$cg/memory.swap.peak 2>/dev/null || echo -1; } > %s\n' \
            'exit $rc' % (shlex.join(command), shlex.quote(str(report_path)))
    return ['systemd-run', '--user', '--scope',
            '-p', 'MemoryMax=%dM' % ceiling_mib,
            '-p', 'MemoryLow=%dM' % min(ceiling_mib // 4, 1024),
            '-p', 'MemorySwapMax=%s' % ('infinity' if allow_swap else '0'),
            '-p', 'TasksMax=4096',
            '/bin/sh', '-c', inner]


def unit_peak(unit):
    """-> (memory peak MiB, swap peak MiB) the scope reached, best effort."""
    answer = subprocess.run(['systemctl', 'show', unit, '--property=MemoryPeak,MemorySwapPeak',
                             '--value'], capture_output=True, text=True, check=False)
    values = [line.strip() for line in answer.stdout.splitlines()]
    def to_mib(text):
        try:
            return int(text) // 1024 // 1024
        except ValueError:
            return -1
    return [to_mib(values[0]) if values else -1, to_mib(values[1]) if len(values) > 1 else -1]


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--memory-gib', type=float, default=8.0,
                        help='hard cgroup ceiling for the command and everything it forks')
    parser.add_argument('--need-ram-mib', type=int, default=0,
                        help='refuse to start unless this much RAM is available, on top of the floor')
    parser.add_argument('--need-vram-mib', type=int, default=0,
                        help='refuse to start unless this much GPU memory is free (no-op without nvidia-smi)')
    parser.add_argument('--allow-swap', action='store_true',
                        help='let the run spill into swap (default: off, so a runaway is killed '
                             'quickly instead of freezing the machine for minutes)')
    parser.add_argument('--force', action='store_true', help='start even if the preflight objects')
    parser.add_argument('command', nargs=argparse.REMAINDER, help='the command to cap (after --)')
    arguments = parser.parse_args()

    command = arguments.command
    if command and command[0] == '--':
        command = command[1:]
    if not command:
        parser.error('nothing to run; pass the command after --')

    available, _, swap_free = memory_available()
    ceiling = int(arguments.memory_gib * 1024)
    complaints = []
    if available < RAM_FLOOR_MIB + arguments.need_ram_mib:
        complaints.append('only %d MiB available, this run wants %d MiB free'
                          % (available, RAM_FLOOR_MIB + arguments.need_ram_mib))
    if arguments.need_vram_mib:
        probe = vram_free()
        if probe is not None and probe[0] < arguments.need_vram_mib:
            complaints.append('only %d MiB of %d MiB GPU memory free, this run wants %d MiB'
                              % (probe[0], probe[1], arguments.need_vram_mib))
    if complaints and not arguments.force:
        for complaint in complaints:
            print('run-capped: refusing -- %s' % complaint, file=sys.stderr)
        print('run-capped: close something down, or pass --force if you accept the risk',
              file=sys.stderr)
        return 3

    report = Path(tempfile.gettempdir()) / ('run-capped-peak-%d.txt' % os.getpid())
    scope = self_reporting_scope(command, ceiling, arguments.allow_swap, report)
    print('run-capped: ceiling %d MiB, %d MiB RAM available, command: %s'
          % (ceiling, available, ' '.join(command[:4]) + (' ...' if len(command) > 4 else '')))

    started = subprocess.Popen(scope, stderr=subprocess.PIPE, text=True)
    unit = None
    for line in started.stderr:
        # systemd-run prints `Running as unit: run-<n>-<i>.scope; invocation ID: <uuid>`
        # on stderr -- the unit is the first token after the label, not the whole tail.
        if line.startswith('Running as unit:'):
            unit = line.split(':', 1)[1].split()[0].strip(';')
            # Stop a capped run by its unit, never with `pkill -f <its argument`:
            # the wrapper shell and this supervisor both carry the command text in
            # their own argv, so pattern-killing takes them down too.  That loses
            # the peak reading printed here and, because the invoking terminal
            # matches the same pattern, it can kill the session that asked.
            print('run-capped: to stop this run cleanly: systemctl --user stop %s' % unit,
                  flush=True)
        sys.stderr.write(line)
        sys.stderr.flush()
    status = started.wait()
    inside = []
    try:
        inside = [int(line) for line in report.read_text().split()[:2]]
    except (OSError, ValueError):
        pass
    finally:
        report.unlink(missing_ok=True)
    if unit or inside:
        peak, swap_peak = unit_peak(unit) if unit else [-1, -1]
        if inside:
            peak = inside[0] // 1024 // 1024
            swap_peak = inside[1] // 1024 // 1024 if len(inside) > 1 else -1
        print('run-capped: %s peak %s MiB memory%s (ceiling %d MiB)'
              % (unit, peak if peak >= 0 else 'unknown',
                 ' / %s MiB swap' % swap_peak if swap_peak >= 0 else '', ceiling))
        if status != 0 and peak >= 0 and peak >= ceiling - max(64, ceiling // 50):
            print('run-capped: the run died at its ceiling -- the cgroup absorbed it, which is '
                  'the point: the session it was launched from is still alive.', file=sys.stderr)
    return status


if __name__ == '__main__':
    raise SystemExit(main())
