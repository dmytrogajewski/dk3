#!/usr/bin/env python3
"""Assemble and launch the independent game; never discover or invoke legacy binaries."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import zipfile

from assets import digest, write_json

BINARIES = ('dk3', 'dk3ded', 'renderer_opengl1.so', 'renderer_opengl2.so')
MODULES = ('qagame.so', 'cgame.so', 'ui.so')
PACKAGES = ('base', 'textures', 'maps', 'shaders', 'models', 'sprites', 'hud', 'sound', 'music', 'voice', 'data', 'navigation')
REQUIRED_ENTRIES = ('default.cfg', 'fonts/con_font.dkf', 'fonts/con_font.tga', 'maps/e1m1a.bsp',
                    'dk3/navigation/e1m1a.cfg')


def checked_assets(directory):
    manifest = json.loads((directory / 'manifest.json').read_text())
    if manifest.get('format') != 1:
        raise ValueError(f'{directory}: unsupported asset manifest format')
    entries = set()
    for name in PACKAGES:
        filename = f'dk3-{name}.pk3'
        path = directory / 'packages' / filename
        record = manifest['packages'].get(filename)
        if not record or not path.is_file():
            raise ValueError(f'missing converted package: {path}')
        if digest(path) != record['sha256']:
            raise ValueError(f'changed or corrupt package: {path}; regenerate this asset generation')
        with zipfile.ZipFile(path) as archive:
            invalid = archive.testzip()
            if invalid:
                raise ValueError(f'{path}: corrupt entry {invalid}')
            entries.update(archive.namelist())
    missing = set(REQUIRED_ENTRIES) - entries
    if missing:
        raise ValueError('installation lacks required assets: ' + ', '.join(sorted(missing)))
    return manifest


def install(prefix, assets, hd_textures=None):
    source = (assets / 'current').resolve(strict=True)
    manifest = checked_assets(source)
    files = {f'bin/{name}': prefix / 'bin' / name for name in BINARIES}
    files.update({f'share/dk3/{name}': prefix / 'lib' / 'dk3' / name for name in MODULES})
    for name in PACKAGES:
        filename = f'dk3-{name}.pk3'
        files[f'share/dk3/{filename}'] = source / 'packages' / filename
    # Previously produced artwork is optional local input. Keep it outside the
    # gameplay asset identity so changing texture resolution preserves saves.
    hd = hd_textures or prefix / 'hd-textures' / 'dkq3-textures_hd.pk3'
    if hd_textures or hd.is_file():
        with zipfile.ZipFile(hd) as archive:
            names = archive.namelist()
            if not names or any(not name.startswith('textures/') or
                                not name.endswith(('.png', '.tga', '.jpg')) or
                                '..' in name.split('/') for name in names):
                raise ValueError(f'{hd}: HD overlay must contain texture images only')
            invalid = archive.testzip()
            if invalid:
                raise ValueError(f'{hd}: corrupt texture {invalid}')
        files['share/dk3/zz-dk3-textures-hd.pk3'] = hd
    records = {}
    for name, path in files.items():
        if not path.is_file():
            raise ValueError(f'missing independent build product: {path}; run zig build')
        records[name] = digest(path)
    key = hashlib.sha256(json.dumps(records, sort_keys=True).encode()).hexdigest()
    root = prefix / 'play'
    root.mkdir(exist_ok=True)
    with (root / '.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        destination = root / key
        if not (destination / 'installation.json').is_file():
            if destination.exists():
                shutil.rmtree(destination)
            for name, path in files.items():
                target = destination / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
                target.chmod(0o755 if name.startswith('bin/') else 0o644)
                if digest(target) != records[name]:
                    raise ValueError(f'{path} changed while installing; rerun play-install')
            write_json(destination / 'installation.json', dict(format=1, files=records,
                       asset_profile=manifest['profile'], asset_generation=manifest['key'], gameplay='incomplete'))
        current, temporary = root / 'current', root / 'current.partial'
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(destination.name, target_is_directory=True)
        temporary.replace(current)
        (root / 'home').mkdir(exist_ok=True)
    print(f'play-install: {destination}\nplay-install: independent runtime; campaign gameplay incomplete')
    if 'share/dk3/zz-dk3-textures-hd.pk3' in records:
        print(f'play-install: HD textures enabled from {hd}')


def launch(prefix, guard, extra):
    directory = (prefix / 'play' / 'current').resolve(strict=True)
    manifest = json.loads((directory / 'installation.json').read_text())
    if manifest.get('format') != 1:
        raise ValueError('unsupported installation manifest')
    for name in [*[f'bin/{n}' for n in BINARIES], *[f'share/dk3/{n}' for n in MODULES]]:
        if digest(directory / name) != manifest['files'][name]:
            raise ValueError(f'installed product changed: {name}; rerun play-install')
    print('play: independent dk3 development runtime; campaign implementation and verification incomplete', flush=True)
    command = [str(Path(guard).resolve(strict=True)), '--mem', '8G', '--timeout', '43200', '--',
               str(directory / 'bin' / 'dk3'), '+set', 'fs_basepath', str(directory / 'share'),
               '+set', 'fs_homepath', str(prefix / 'play' / 'home'), '+set', 'com_basegame', 'dk3',
               '+set', 'fs_homedatapath', str(prefix / 'play' / 'home'),
               '+set', 'fs_homestatepath', str(prefix / 'play' / 'state'),
               '+set', 'vm_game', '0', '+set', 'vm_cgame', '0', '+set', 'vm_ui', '0',
               '+set', 'g_gametype', '2',
               *(['+set', 'r_picmip', '0'] if 'share/dk3/zz-dk3-textures-hd.pk3' in manifest['files'] else []), *extra]
    os.execv(command[0], command)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    prepare = sub.add_parser('install')
    prepare.add_argument('--prefix', type=Path, required=True)
    prepare.add_argument('--assets', type=Path, required=True)
    prepare.add_argument('--hd-textures', type=Path, help='optional image-only HD texture package')
    run = sub.add_parser('launch')
    run.add_argument('--prefix', type=Path, required=True)
    run.add_argument('--dkguard', required=True)
    arguments, extra = parser.parse_known_args(argv)
    try:
        prefix = arguments.prefix.resolve(strict=True)
        if arguments.command == 'install':
            if extra: parser.error('unexpected installation arguments: ' + ' '.join(extra))
            install(prefix, arguments.assets.resolve(strict=True), arguments.hd_textures)
        else:
            launch(prefix, arguments.dkguard, extra[1:] if extra[:1] == ['--'] else extra)
        return 0
    except (OSError, ValueError, KeyError, zipfile.BadZipFile) as error:
        print(f'play: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
