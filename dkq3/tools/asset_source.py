"""Explicit local asset profiles and safe, case-insensitive loose-file inputs."""
import json
import os
from pathlib import Path

import dkpak

PROFILE_FILE = '.dk3-profile.json'
ASSET_SUFFIXES = frozenset(('.bsp', '.ent', '.wal', '.bmp', '.tga', '.pcx', '.dkm',
                            '.sp2', '.dkf', '.wav', '.mp3', '.ogg', '.vsc', '.csv',
                            '.json', '.script', '.sca', '.nod', '.npg', '.txt', '.seq'))
ASSET_DIRS = frozenset(('maps', 'textures', 'skins', 'models', 'sprites', 'sounds',
                       'music', 'fonts', 'pics', 'env', 'cin', 'subtitles', 'tables'))


def asset_name(name):
    """Normalize an engine path; reject paths escaping the supplied data directory."""
    name = name.replace('\\', '/').lower()
    parts = name.split('/')
    if not name or any(p in ('', '.', '..') for p in parts) or ':' in name or '\0' in name:
        raise ValueError(f'unsafe asset name: {name!r}')
    return '/'.join(parts)


def loose_files(root):
    """Inventory only game asset kinds, excluding executables, source and saves."""
    found = {}
    root = Path(root)
    for parent, directories, files in os.walk(root):
        if Path(parent) == root:
            directories[:] = sorted(d for d in directories if d.lower() in ASSET_DIRS)
        else:
            directories[:] = sorted(d for d in directories if not d.startswith('.'))
        for leaf in sorted(files):
            path = Path(parent, leaf)
            if leaf.startswith('.') or path.suffix.lower() not in ASSET_SUFFIXES:
                continue
            relative = path.relative_to(root).as_posix()
            if '/' not in relative and path.suffix.lower() not in ('.vsc', '.csv', '.json'):
                continue
            name = asset_name(relative)
            if name in found:
                raise ValueError(f'case-colliding assets: {found[name]} and {path}')
            found[name] = path
    return dict(sorted(found.items()))


class Directory:
    """The small read-only archive surface used by image converters."""
    def __init__(self, root):
        self.entries = loose_files(root)
        self.order = list(self.entries)

    def read(self, name):
        return self.entries[asset_name(name)].read_bytes()

    def close(self):
        pass


def open_source(path):
    return Directory(path) if os.path.isdir(path) else dkpak.Pak(path)


def archive_order(root):
    """Return highest-priority archives first, using the prepared profile if present."""
    manifest = Path(root, PROFILE_FILE)
    if manifest.is_file():
        names = json.loads(manifest.read_text())['archives']
        if any('/' in name or asset_name(name) != name for name in names):
            raise ValueError(f'{manifest}: invalid archive path')
        return list(reversed(names))
    return [f'pak{i}.pak' for i in range(9, -1, -1)]
