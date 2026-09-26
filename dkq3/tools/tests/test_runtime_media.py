"""Code-owned presentation updates preserve the gameplay asset identity."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch

import play


class RuntimeMediaTest(unittest.TestCase):
    def test_shader_update_is_installed_verified_and_keeps_asset_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            prefix, assets = root / 'build', root / 'assets'
            generation = assets / 'fixture'
            (generation / 'packages').mkdir(parents=True)
            (assets / 'current').symlink_to('fixture', target_is_directory=True)
            for name in play.PACKAGES:
                with zipfile.ZipFile(generation / 'packages' / f'dk3-{name}.pk3', 'w') as archive:
                    archive.writestr(f'{name}/fixture.cfg', 'synthetic package')
            for name in play.BINARIES:
                target = prefix / 'bin' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'synthetic binary')
            for name in play.MODULES:
                target = prefix / 'lib' / 'dk3' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'synthetic module')
            for name in play.RUNTIME_MEDIA:
                target = prefix / 'share' / 'dk3' / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('{}' if name == 'rules.json' else '// synthetic presentation v1\n')
            target = prefix / 'share/dk3' / play.LEGACY_RUNTIME_MEDIA[0]
            manifest = dict(format=1, key='unchanged-gameplay', profile='retail')
            with patch('play.checked_assets', return_value=manifest), contextlib.redirect_stdout(io.StringIO()):
                play.install(prefix, assets)
                first = (prefix / 'play/current').resolve()
                target.write_text('// synthetic presentation v2\n')
                play.install(prefix, assets)
                second = (prefix / 'play/current').resolve()
            self.assertNotEqual(first, second)
            installed = second / 'share/dk3' / play.RUNTIME_MEDIA[0]
            self.assertEqual(installed.read_text(), target.read_text())
            self.assertEqual(json.loads((second / 'installation.json').read_text())['asset_generation'],
                             'unchanged-gameplay')
            installed.write_text('// damaged installation\n')
            with self.assertRaisesRegex(ValueError, 'installed product changed'):
                play.launch(prefix, '/not-invoked', [])

    def test_launch_preserved_and_online_installations(self):
        with tempfile.TemporaryDirectory() as temporary:
            prefix = Path(temporary)
            directory = prefix / 'play/fixture'
            directory.mkdir(parents=True)
            (prefix / 'play/current').symlink_to('fixture', target_is_directory=True)
            guard = prefix / 'dkguard'
            guard.touch()
            records = {}
            for name in [*[f'bin/{n}' for n in play.BINARIES],
                         *[f'share/dk3/{n}' for n in (*play.MODULES, *play.LEGACY_RUNTIME_MEDIA)]]:
                path = directory / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'preserved build')
                records[name] = play.digest(path)
            def manifest(version):
                (directory / 'installation.json').write_text(json.dumps(dict(format=version, files=records)))

            manifest(1)
            with patch('play.os.execv') as execute, contextlib.redirect_stdout(io.StringIO()):
                play.launch(prefix, guard, ['+quit'])
            self.assertEqual(execute.call_args.args[1][6], str(directory / 'bin/dk3'))
            for version in (1, 2):
                for name in play.ONLINE_METADATA:
                    path = directory / 'share/dk3' / name
                    path.write_text('{}')
                    records[f'share/dk3/{name}'] = play.digest(path)
                manifest(version)
                with patch('play.os.execv') as execute, contextlib.redirect_stdout(io.StringIO()):
                    play.launch(prefix, guard, [])
                    execute.assert_called_once()
                path.write_text('{"tampered":true}')
                with self.assertRaisesRegex(ValueError, 'installed product changed: .*compatibility.json'):
                    play.launch(prefix, guard, [])
                path.unlink()
                with self.assertRaisesRegex(ValueError, 'installed product missing: .*compatibility.json'):
                    play.launch(prefix, guard, [])
            records.pop('share/dk3/rules.json')
            records.pop('share/dk3/compatibility.json')
            manifest(2)
            with self.assertRaisesRegex(ValueError, 'installed product missing: .*rules.json'):
                play.launch(prefix, guard, [])
