"""pk3 entry paths as ioquake3 compares them, and the entry paths one package shares with other packages.

ioquake3 finds a name in a pk3 with FS_FilenameCompare (../ioq3/code/qcommon/files.c:984-1008; the lookups at :1139, :1203, :1755):
it puts the letters a-z in one case and reads `\\` and `:` as `/`. Two packages holding one path under such variants hold one file for
the engine, which serves whichever package it searches first.

FRD: specs/frds/FRD-019-sound-effects.md
"""
import os
import string
import zipfile

# FS_FilenameCompare folds only a-z (it subtracts 'a' - 'A' from 'a'..'z'); `\\` and `:` become `/`.
FS_FOLD = str.maketrans(string.ascii_uppercase + '\\:', string.ascii_lowercase + '//')


def fs_key(name):
    """-> `name` as FS_FilenameCompare compares it: the letters a-z in one case, `\\` and `:` as `/`."""
    return name.translate(FS_FOLD)


def collisions(package, others):
    """-> (shared lines, colliding lines) of every entry path the pk3 `package` shares with a pk3 of `others` under fs_key:
    `shared <entry> with <package>` when the bytes are equal, `<entry> collides with <other entry> in <package>` when they differ."""
    shared, colliding = [], []
    with zipfile.ZipFile(package) as ours:
        mine = {fs_key(name): name for name in ours.namelist()}
        for other in others:
            label = os.path.basename(other)
            with zipfile.ZipFile(other) as theirs:
                for name in (name for name in theirs.namelist() if fs_key(name) in mine):
                    own = mine[fs_key(name)]
                    if ours.read(own) == theirs.read(name):
                        shared.append(f'shared {own} with {label}')
                    else:
                        colliding.append(f'{own} collides with {name} in {label}')
    return shared, colliding
