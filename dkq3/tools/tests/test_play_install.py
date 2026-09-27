"""Development installation publishes complete builds and preserves player state."""
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

import play


class PlayInstallTest(unittest.TestCase):
    def fixture(self, root):
        prefix, assets = root / 'native', root / 'assets'
        source = assets / 'generation'
        (source / 'packages').mkdir(parents=True)
        (assets / 'current').symlink_to(source.name)
        records = {}
        for index, name in enumerate(play.PACKAGES):
            path = source / 'packages' / f'dk3-{name}.pk3'
            with zipfile.ZipFile(path, 'w') as archive:
                for entry in play.REQUIRED_ENTRIES if index == 0 else (f'fixture/{name}',):
                    archive.writestr(entry, 'fixture')
            records[path.name] = {'sha256': play.digest(path)}
        (source / 'manifest.json').write_text(json.dumps(dict(
            format=1, profile='retail', key='fixture', packages=records)))
        for name in (*[f'bin/{name}' for name in play.BINARIES],
                     *[f'lib/dk3/{name}' for name in play.MODULES],
                     *[f'share/dk3/{name}' for name in play.RUNTIME_MEDIA]):
            path = prefix / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'{}' if name.endswith('.json') else b'first build')
        return prefix, assets

    def test_new_code_publishes_separately_and_keeps_saves(self):
        with tempfile.TemporaryDirectory() as temporary:
            prefix, assets = self.fixture(Path(temporary))
            play.install(prefix, assets)
            original = (prefix / 'play/current').resolve()
            save = prefix / 'play/state/dk3/saves/user.sav'
            save.parent.mkdir(parents=True)
            save.write_bytes(b'user save')
            (prefix / 'lib/dk3/qagame.so').write_bytes(b'second build')
            play.install(prefix, assets)
            published = (prefix / 'play/current').resolve()
            self.assertNotEqual(original, published)
            self.assertEqual((original / 'share/dk3/qagame.so').read_bytes(), b'first build')
            self.assertEqual((published / 'share/dk3/qagame.so').read_bytes(), b'second build')
            self.assertEqual(save.read_bytes(), b'user save')

    def test_incomplete_build_and_corrupt_assets_keep_current_generation(self):
        with tempfile.TemporaryDirectory() as temporary:
            prefix, assets = self.fixture(Path(temporary))
            play.install(prefix, assets)
            original = (prefix / 'play/current').resolve()
            (prefix / 'lib/dk3/qagame.so').unlink()
            with self.assertRaisesRegex(ValueError, 'missing independent build product'):
                play.install(prefix, assets)
            self.assertEqual((prefix / 'play/current').resolve(), original)
            (assets / 'current/packages/dk3-base.pk3').write_bytes(b'corrupt')
            with self.assertRaisesRegex(ValueError, 'changed or corrupt package'):
                play.install(prefix, assets)
            self.assertEqual((prefix / 'play/current').resolve(), original)

    def test_first_run_explains_asset_setup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with self.assertRaisesRegex(ValueError, 'zig build assets'):
                play.install(root, root / 'absent')
