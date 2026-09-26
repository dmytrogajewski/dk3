#!/usr/bin/python3
"""Launch the installed dk3 runtime with a separate per-user profile."""
import json
import os
from pathlib import Path
import sys


def main():
    root = Path(__file__).resolve().parents[3]
    data = root / 'usr/share/dk3'
    runtime = root / 'usr/lib64/dk3'
    profile = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share'))) / 'dk3'
    state = Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'dk3'
    (profile / 'dk3').mkdir(parents=True, exist_ok=True, mode=0o700)
    (state / 'dk3').mkdir(parents=True, exist_ok=True, mode=0o700)
    # Seed only a new profile. Later in-game settings remain authoritative.
    config = profile / 'dk3/dk3config.cfg'
    defaults = json.loads((data / 'online-defaults.json').read_text())
    ca = root / defaults['ca_file'].lstrip('/')
    try:
        fd = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        pass
    else:
        with os.fdopen(fd, 'w') as stream:
            for key, value in [('dk3_coordinator', defaults['coordinator']), ('dk3_ca_file', str(ca)),
                               ('model', 'hiro/0')]:
                if any(c in value for c in '\r\n";'):
                    raise ValueError('Invalid packaged online setting')
                stream.write(f'seta {key} "{value}"\n')
    command = [str(runtime / 'tools/dkguard'), '--mem', '8G', '--timeout', '43200', '--',
               str(runtime / 'bin/dk3'), '+set', 'fs_basepath', str(root / 'usr/share'),
               '+set', 'fs_homepath', str(profile), '+set', 'fs_homedatapath', str(profile),
               '+set', 'fs_homestatepath', str(state), '+set', 'com_basegame', 'dk3',
               '+set', 'vm_game', '0', '+set', 'vm_cgame', '0', '+set', 'vm_ui', '0',
               '+set', 'g_gametype', '2', *sys.argv[1:]]
    os.execv(command[0], command)


if __name__ == '__main__':
    main()
