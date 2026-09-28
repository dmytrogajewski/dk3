"""Development installation publishes complete builds and preserves player state."""
import json
import struct
from pathlib import Path
import tempfile
import unittest
import zipfile
from unittest.mock import patch

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
                if name == 'maps':
                    # Installation now derives the campaign graph from real BSP
                    # authoring, so provide a valid empty map rather than text.
                    bsp = bytearray(144)
                    struct.pack_into('<4si', bsp, 0, b'IBSP', 46)
                    archive.writestr('maps/e1m1a.bsp', bsp)
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

    def test_shared_hd_default_preserves_gameplay_and_local_overrides(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            prefix, assets = self.fixture(root)
            shared = root / 'hd-textures/dkq3-textures_hd.pk3'
            local = prefix / 'hd-textures/dkq3-textures_hd.pk3'
            explicit = root / 'custom.pk3'

            def publish():
                play.install(prefix, assets, hd_textures_fallback=shared)
                return (prefix / 'play/current').resolve()

            stock = publish()  # A checkout without optional HD assets still works.
            gameplay = json.loads((stock / 'share/dk3/compatibility.json').read_text())['gameplay']
            overlay = 'share/dk3/zz-dk3-textures-hd.pk3'
            self.assertFalse((stock / overlay).exists())
            for source in (shared, local, explicit):
                source.parent.mkdir(parents=True, exist_ok=True)
                with zipfile.ZipFile(source, 'w') as archive:
                    archive.writestr('textures/fixture/wall.png', str(source))
                if source == explicit:
                    play.install(prefix, assets, explicit, hd_textures_fallback=shared)
                    installed = (prefix / 'play/current').resolve()
                else:
                    installed = publish()
                self.assertEqual((installed / overlay).read_bytes(), source.read_bytes())
                compatibility = json.loads((installed / 'share/dk3/compatibility.json').read_text())
                self.assertEqual(compatibility['gameplay'], gameplay)
                self.assertEqual(compatibility['cosmetic'], 'hd-textures-v1')
            guard = root / 'dkguard'
            guard.touch()
            with patch('play.os.execv') as execute:
                play.launch(prefix, guard, [])
            self.assertEqual(execute.call_args.args[1][-3:], ['+set', 'r_picmip', '0'])
