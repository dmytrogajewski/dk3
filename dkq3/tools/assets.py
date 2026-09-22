#!/usr/bin/env python3
"""Convert explicitly supplied game data into a private, reproducible dk3 generation."""
import argparse
import ast
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

import asset_source
import dkpak
import pk3

FORMAT = 1
PROFILES = ('retail', '1.3')
REQUIRED_ARCHIVES = ('pak1.pak', 'pak2.pak', 'pak3.pak', 'pak4.pak')
REJECTED_IMAGES = ('fonts/statbar_font.bmp', 'pics/misc/we_mflash2.bmp', 'skins/colormap.wal')
MISSING_TEXTURES = ('textures/ctf1/navytrim10', 'textures/e1m7/blueglss',
                    'textures/e4m5\\labfloorshiny', 'textures/e4m9/subplate4', 'textures/protex\\region')
MISSING_AUDIO = ('music/dm1_riffy.mp3', 'music/dm2_forebode.mp3', 'sounds/voices/mikiko/e2m5_mk_10b.mp3')
TOOLS = Path(__file__).resolve().parent
STAGE_INPUTS = {'textures': ('images',), 'maps': ('images', 'textures'),
                'shaders': ('maps', 'images', 'textures'), 'models': ('images',),
                'sprites': ('images',), 'hud': ('images',), 'navigation': ('maps',)}


def converter_sources(script):
    """Find local Python imports; the script hash also covers changes to imports."""
    pending, found = [Path(script).name], set()
    while pending:
        name = pending.pop()
        if name in found or not (TOOLS / name).is_file():
            continue
        found.add(name)
        for node in ast.walk(ast.parse((TOOLS / name).read_text())):
            imports = [item.name for item in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) and node.module else []
            pending.extend(module.split('.')[0] + '.py' for module in imports)
    return sorted(found)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + '.partial')
    with temporary.open('w') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')
        out.flush()
        os.fsync(out.fileno())
    temporary.replace(path)


def inventory(root, profile):
    """Resolve profile inputs without modifying the supplied installation."""
    if not root.is_dir():
        raise ValueError(f'profile {profile}: data directory does not exist: {root}')
    top = {}
    for path in root.iterdir():
        if path.is_file():
            key = path.name.lower()
            if key in top:
                raise ValueError(f'profile {profile}: case-colliding input {path.name}')
            top[key] = path
    missing = [str(root / name) for name in REQUIRED_ARCHIVES if name not in top]
    if profile == '1.3':
        missing += [str(root / 'pak6.pak')] if 'pak6.pak' not in top else []
        if not any(name in top for name in ('pak5.pak', 'pak5.zip')):
            missing.append(str(root / 'pak5.pak') + ' or pak5.zip containing pak5.pak')
    if missing:
        raise ValueError(f'profile {profile}: missing required input: ' + '; '.join(missing))
    archives = [(f'pak{i}.pak', top[f'pak{i}.pak']) for i in range(10) if f'pak{i}.pak' in top]
    if profile == '1.3':
        archives = [(name, path) for name, path in archives if name != 'pak5.pak']
        archives.append(('pak5.pak', top.get('pak5.pak', top.get('pak5.zip'))))
    loose = asset_source.loose_files(root)
    records = [dict(name=name, source=str(path), sha256=digest(path)) for name, path in archives]
    records += [dict(name=name, source=str(path), sha256=digest(path)) for name, path in loose.items()]
    return archives, loose, records


def prepare(directory, archives, loose, profile):
    """A private input view gives every converter the same precedence and case rules."""
    directory.mkdir()
    for name, source in archives:
        target = directory / name
        if source.suffix.lower() == '.zip':
            with zipfile.ZipFile(source) as archive:
                matches = [entry for entry in archive.infolist() if entry.filename.lower() == 'pak5.pak']
                if len(matches) != 1:
                    raise ValueError(f'{source}: expected exactly one pak5.pak entry')
                with archive.open(matches[0]) as inp, target.open('wb') as out:
                    shutil.copyfileobj(inp, out)
        else:
            target.symlink_to(source)
        with contextlib.closing(dkpak.Pak(target)) as archive:
            for entry in archive.order:
                asset_source.asset_name(entry)
    for name, source in loose.items():
        target = directory / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(source)
    write_json(directory / asset_source.PROFILE_FILE,
               dict(format=FORMAT, profile=profile, archives=[name for name, _ in archives]))


class Pipeline:
    """Completed stages survive an interrupted later stage under one locked generation."""
    def __init__(self, root, arguments):
        self.root, self.args = root, arguments
        self.packages = root / 'packages'
        self.packages.mkdir(exist_ok=True)

    @staticmethod
    def stage_identity(root, name, command):
        inputs = json.loads((root / 'inputs.json').read_text())
        # The command records orchestration options. Navigation has no outputs
        # consumed by the other converters, so its compiler cannot invalidate them.
        inputs['converters'] = {file: inputs['converters'].get(file)
                                for file in converter_sources(command[2])}
        if name != 'navigation':
            inputs.pop('bspc', None)
        normalized = []
        for index, argument in enumerate(command):
            if index and command[index - 1] in ('--bspc', '--dkguard'):
                normalized.append(command[index - 1])
            elif index and command[index - 1] in ('--workers', '--jobs'):
                # Parallelism changes scheduling, not these deterministic products.
                # A resumed conversion may retain a different worker count in a
                # completed stage; do not rebuild maps/AAS because of that count.
                normalized.append('$WORKERS')
            else:
                normalized.append(argument.replace(str(root) + '/', '$GENERATION/'))
        dependencies = {}
        for stage in STAGE_INPUTS.get(name, ()):
            complete = (root / stage / 'complete.json').resolve()
            saved = json.loads(complete.read_text())
            dependencies[stage] = Pipeline.stage_identity(complete.parents[1], stage, saved['command'])
        return dict(inputs=inputs, command=normalized, dependencies=dependencies)

    def reuse(self, name, command):
        identity = self.stage_identity(self.root, name, command)
        for previous in sorted(self.root.parent.iterdir()):
            complete = previous / name / 'complete.json'
            if previous == self.root or previous.is_symlink() or not complete.is_file():
                continue
            previous = complete.resolve().parents[1]
            saved = json.loads(complete.read_text())
            if self.stage_identity(previous, name, saved['command']) != identity:
                continue
            packages = [Path(argument) for argument in saved['command']
                        if argument.startswith(str(previous / 'packages') + '/')]
            if any(not path.is_file() for path in packages):
                continue
            (self.root / name).symlink_to(previous / name, target_is_directory=True)
            for path in packages:
                target = self.packages / path.name
                target.unlink(missing_ok=True)
                target.symlink_to(path)
            print(f'assets: {name} (reused completed conversion)', flush=True)
            return True
        return False

    def run(self, name, script, arguments):
        directory = self.root / name
        complete = directory / 'complete.json'
        if complete.is_file():
            return directory
        command = [sys.executable, '-B', str(TOOLS / script), *map(str, arguments)]
        if not directory.exists() and self.reuse(name, command):
            return directory
        if directory.exists() and name != 'navigation':
            shutil.rmtree(directory)
        directory.mkdir(exist_ok=True)
        print(f'assets: {name}', flush=True)
        with (directory / 'console.log').open('wb') as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False)
        if result.returncode:
            tail = (directory / 'console.log').read_text(errors='replace').splitlines()[-40:]
            raise ValueError(f'{name} failed ({result.returncode}); {directory / "console.log"}\n' + '\n'.join(tail))
        write_json(complete, dict(command=command))
        return directory

    def report_args(self, stage):
        return ['--report', self.root / stage / 'report.json', '--summary', self.root / stage / 'summary.txt']

    def convert(self, sources):
        data = self.root / 'input'
        image_dir = self.root / 'images' / 'png'
        manifest = self.root / 'images' / 'manifest.json'
        textures = self.root / 'textures' / 'textures.json'
        self.run('base', 'basegame.py', [self.packages / 'dk3-base.pk3'])
        self.run('images', 'dk_extract.py', [*sources, data, '--out', image_dir, '--manifest', manifest,
                 '--summary', self.root / 'images' / 'summary.txt', '--workers', self.args.workers,
                 *['--rejected=' + name for name in REJECTED_IMAGES]])
        self.run('textures', 'pack_textures.py', [*sources, data, '--manifest', manifest, '--images', image_dir,
                 '--out', self.packages / 'dk3-textures.pk3', '--textures-manifest', textures,
                 '--summary', self.root / 'textures' / 'summary.txt', *['--missing=' + n for n in MISSING_TEXTURES]])
        import convert_all
        import dk2q3
        with dk2q3.GameDir(data) as game:
            maps = sorted(convert_all.discover(game))
        if not maps:
            raise ValueError(f'{data}: no maps/*.bsp assets found')
        maps_dir = self.root / 'maps' / 'converted'
        self.run('maps', 'convert_all.py', ['--data', data, '--manifest', manifest, '--textures', textures,
                 '--out-dir', maps_dir, '--pk3', self.packages / 'dk3-maps.pk3',
                 '--stock-pk3', self.root / 'maps' / 'stock-diagnostic.pk3', '--logs', 'scenario-logs',
                 '--workers', self.args.workers, *self.report_args('maps'), *['--map=' + n for n in maps]])
        self.run('shaders', 'shadergen.py', [*[maps_dir / 'shaders' / (name + '.json') for name in maps],
                 '--manifest', manifest, '--images', image_dir, '--textures', textures,
                 '--out', self.packages / 'dk3-shaders.pk3', '--summary', self.root / 'shaders' / 'summary.txt'])
        self.run('models', 'dkm2md3.py', ['--data', data, '--manifest', manifest, '--images', image_dir,
                 '--out-dir', self.root / 'models' / 'converted', '--pk3', self.packages / 'dk3-models.pk3',
                 '--workers', self.args.workers, *self.report_args('models')])
        self.run('sprites', 'sp2shaders.py', ['--data', data, '--images', image_dir,
                 '--pk3', self.packages / 'dk3-sprites.pk3', *self.report_args('sprites')])
        self.run('hud', 'dkf.py', ['--data', data, '--manifest', manifest, '--images', image_dir,
                 '--pk3', self.packages / 'dk3-hud.pk3', *self.report_args('hud')])
        encoder = ['--data', data, '--ffmpeg', self.args.ffmpeg, '--ffmpeg-major', self.args.ffmpeg_major,
                   '--dkguard', self.args.dkguard, '--jobs', min(self.args.workers, 4)]
        self.run('sound', 'media.py', [*encoder, '--pk3', self.packages / 'dk3-sound.pk3', *self.report_args('sound')])
        self.run('music', 'music_voice.py', [*encoder, '--music-pk3', self.packages / 'dk3-music.pk3',
                 '--voice-pk3', self.packages / 'dk3-voice.pk3', *self.report_args('music'),
                 *['--expected-missing=' + n for n in MISSING_AUDIO]])
        package_game_data(data, self.packages / 'dk3-data.pk3', self.args.profile, self.root.name)
        self.run('navigation', 'navigation.py', ['--maps', maps_dir / 'bsp', '--bspc', self.args.bspc,
                 '--dkguard', self.args.dkguard, '--out', self.root / 'navigation' / 'compiled',
                 '--pk3', self.packages / 'dk3-navigation.pk3'])
        return maps


def package_game_data(root, output, profile, generation):
    """Keep supplied scripts, tables, routes and subtitles; never scrape source/executables."""
    import dk2q3
    import tables
    import actions
    import cinematics
    import nodes
    import catalog
    import actor_events
    selected = {}
    with dk2q3.GameDir(root) as game:
        names = set(asset_source.loose_files(root))
        for _, archive in game.paks:
            names.update(archive.order)
        for name in sorted(names):
            suffix = Path(name).suffix.lower()
            if (name.startswith(('cin/', 'subtitles/', 'maps/nodes/')) or
                    suffix in ('.vsc', '.csv') or
                    suffix == '.json' and (name.startswith('tables/') or '/' not in name)):
                selected[asset_source.asset_name(name)] = game.find(name)[1]
        selected.update(tables.entries(game, profile))
        selected.update(actor_events.entries(game, profile))
        selected.update(actions.entries(game, names))
        selected.update(cinematics.entries(game, names))
        selected.update(nodes.entries(game, names))
        selected.update(catalog.entries(game, names))
    selected['dk3/asset-id.cfg'] = (generation + '\n').encode('ascii')
    pk3.write(output, sorted(selected.items()))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--data', type=Path, required=True)
    parser.add_argument('--profile', choices=PROFILES, default='retail')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--dkguard', required=True)
    parser.add_argument('--bspc', required=True)
    parser.add_argument('--ffmpeg', default='ffmpeg')
    parser.add_argument('--ffmpeg-major', type=int, default=7)
    parser.add_argument('--workers', type=int, choices=range(1, 13), default=4)
    args = parser.parse_args(argv)
    try:
        try:
            import numpy
        except ImportError as error:
            raise ValueError('numpy is missing; install dkq3/tools/requirements.txt with the selected Python') from error
        args.ffmpeg = shutil.which(args.ffmpeg)
        if not args.ffmpeg:
            raise ValueError(f'ffmpeg {args.ffmpeg_major} is missing from PATH')
        args.dkguard = str(Path(args.dkguard).resolve(strict=True))
        args.bspc = str(Path(args.bspc).resolve(strict=True))
        args.data, args.out = args.data.resolve(), args.out.resolve()
        if args.out == args.data or args.data in args.out.parents or args.out in args.data.parents:
            raise ValueError('--out and --data must be separate directories')
        archives, loose, records = inventory(args.data, args.profile)
        inputs = dict(format=FORMAT, profile=args.profile, files=records, numpy=numpy.__version__,
                      python=sys.version, ffmpeg=digest(args.ffmpeg), bspc=digest(args.bspc), ffmpeg_major=args.ffmpeg_major,
                      converters={p.name: digest(p) for p in sorted(TOOLS.glob('*.py'))})
        key = hashlib.sha256(json.dumps(inputs, sort_keys=True).encode()).hexdigest()
        args.out.mkdir(parents=True, exist_ok=True)
        with (args.out / '.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            root = args.out / key
            root.mkdir(exist_ok=True)
            if not (root / 'manifest.json').is_file():
                write_json(root / 'inputs.json', inputs)
                if not (root / 'input' / asset_source.PROFILE_FILE).is_file():
                    if (root / 'input').exists():
                        shutil.rmtree(root / 'input')
                    prepare(root / 'input', archives, loose, args.profile)
                maps = Pipeline(root, args).convert([root / 'input' / name for name, _ in archives])
                # Reject a mixed generation if the supplied input changed during conversion.
                if inventory(args.data, args.profile)[2] != records:
                    raise ValueError('input assets changed during conversion; rerun to create a consistent generation')
                packages = {p.name: dict(sha256=digest(p), bytes=p.stat().st_size)
                            for p in sorted((root / 'packages').glob('*.pk3'))}
                write_json(root / 'manifest.json', dict(format=FORMAT, profile=args.profile, key=key,
                                                       maps=maps, packages=packages, gameplay='incomplete'))
            current = args.out / 'current'
            temporary = args.out / 'current.partial'
            temporary.unlink(missing_ok=True)
            temporary.symlink_to(root.name, target_is_directory=True)
            temporary.replace(current)
            print(f'assets: generation {root}\nassets: {root / "manifest.json"}', flush=True)
        return 0
    except (OSError, ValueError, dkpak.PakError, zipfile.BadZipFile) as error:
        print(f'assets: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
