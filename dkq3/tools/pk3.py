"""Deterministic pk3 writer: a zip archive ioquake3 loads (code/qcommon/files.c, unzip.c) whose bytes depend only on
the entries. Entries keep the given order and are stored uncompressed, so the output does not depend on the zlib
version; every entry has the same date and Unix mode, and the archive has no comment or extra fields.

usage: pk3.py OUT_PK3 NAME=FILE...    writes each FILE as entry NAME, in the given order

A NAME=DIR pair whose DIR is a directory adds every file below it instead, each named NAME + its path relative to DIR,
sorted by that entry name. One argument then carries a whole tree -- roadmap Step 37 packs pak1's 1,380
`subtitles/*.txt` this way -- and the order is a function of the names alone, so the archive stays deterministic.

FRD: specs/frds/FRD-010-standalone-dkq3-base-game-package.md
"""
import os
import sys
import zipfile

# The earliest date a zip header can hold.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
UNIX_SYSTEM = 3
FILE_MODE = 0o644
USAGE = "usage: pk3.py OUT_PK3 NAME=FILE...\n"


class Pk3Error(ValueError):
    """Entries that cannot form a deterministic pk3."""


def write(path, entries):
    """Writes `entries`, a sequence of (name, bytes), to the pk3 at `path` in that order."""
    _write(path, entries, lambda data: data)


def write_files(path, entries):
    """Writes `entries`, a sequence of (name, source file), to the pk3 at `path` in that order, reading one file at a time."""
    _write(path, entries, _read)


def _read(source):
    with open(source, "rb") as f:
        return f.read()


def _write(path, entries, load):
    names = [name for name, _ in entries]
    repeated = sorted({name for name in names if names.count(name) > 1})
    if repeated:
        raise Pk3Error(f"entry names appear more than once: {', '.join(repeated)}")
    with zipfile.ZipFile(path, "w", zipfile.ZIP_STORED) as archive:
        for name, data in entries:
            info = zipfile.ZipInfo(name, ZIP_EPOCH)
            info.compress_type, info.create_system, info.external_attr = zipfile.ZIP_STORED, UNIX_SYSTEM, FILE_MODE << 16
            archive.writestr(info, load(data))


def directory_entries(name, directory):
    """-> [(entry name, source file)] for every file below `directory`, each named `name` + its path relative to it,
    sorted by entry name so the archive never depends on the order the file system lists a directory in."""
    prefix = name if not name or name.endswith("/") else name + "/"
    found = []
    for root, _, files in os.walk(directory):
        for leaf in files:
            source = os.path.join(root, leaf)
            found.append((prefix + os.path.relpath(source, directory).replace(os.sep, "/"), source))
    return sorted(found)


def main(argv):
    if len(argv) < 3 or not all("=" in arg for arg in argv[2:]):
        sys.stderr.write(USAGE)
        return 2
    entries = []
    for name, source in (arg.split("=", 1) for arg in argv[2:]):
        for entry_name, path in (directory_entries(name, source) if os.path.isdir(source) else [(name, source)]):
            with open(path, "rb") as f:
                entries.append((entry_name, f.read()))
    write(argv[1], entries)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
