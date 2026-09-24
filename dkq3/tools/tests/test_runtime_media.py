"""Code-owned presentation updates preserve the gameplay asset identity."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
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
                (generation / 'packages' / f'dk3-{name}.pk3').write_bytes(b'synthetic package')
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
                target.write_text('// synthetic presentation v1\n')
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
