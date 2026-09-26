"""Keep native simulation independent of engine/private gameplay headers."""
from pathlib import Path
import re
import unittest

from tests.support import REPO_ROOT


class RuntimeArchitectureTest(unittest.TestCase):
    def test_pure_layers_do_not_import_runtime_adapters(self):
        root = Path(REPO_ROOT)
        layers = ('src/runtime/domain', 'src/runtime/ecs', 'src/weapons', 'src/items', 'src/actors')
        allowed = tuple((root / path).resolve() for path in layers)
        named = {'std', 'inventory_rules', 'weapon_catalog', 'item_catalog', 'actor_catalog'}
        for layer in allowed:
            for path in layer.rglob('*.zig'):
                text = path.read_text()
                self.assertNotIn('@cImport', text, str(path))
                for dependency in re.findall(r'@import\("([^"]+)"\)', text):
                    if dependency in named:
                        continue
                    resolved = (path.parent / dependency).resolve()
                    self.assertTrue(any(resolved.is_relative_to(directory) for directory in allowed),
                                    f'{path}: forbidden dependency {dependency}')
                    self.assertTrue(resolved.is_file(), f'{path}: missing {dependency}')

    def test_native_runtime_uses_only_public_engine_headers(self):
        root = Path(REPO_ROOT) / 'src/runtime'
        forbidden = {'g_local.h', 'cg_local.h', 'ui_local.h'}
        for path in root.rglob('*.zig'):
            for header in re.findall(r'@cInclude\("([^"]+)"\)', path.read_text()):
                self.assertNotIn(Path(header).name, forbidden, str(path))
