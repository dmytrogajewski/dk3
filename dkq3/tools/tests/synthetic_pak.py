"""Synthetic PAK archives for the dkpak and sweep tests, built from named constants.

Layout from reference/dk-gold/user/qfiles.h:20-38: a 12-byte `dpackheader_t` ('PACK', dirofs,
dirlen), the entries' stored bytes, then the directory of 72-byte `dpackfile_t` records. Every
field can be overridden, so tests can build malformed archives too. No game data is used.

FRD: specs/frds/FRD-004-pak-reader-matches-files-cpp-codes-254-255.md
"""
import collections
import struct

MAGIC = b"PACK"
HEADER = struct.Struct("<4sii")
DIRECTORY_ENTRY = struct.Struct("<56siiii")
STORED, COMPRESSED = 0, 1

Entry = collections.namedtuple("Entry", "name data filelen compresstype filepos compresslen",
                               defaults=(None, STORED, None, None))
"""`name` is raw bytes (NUL padding is added by struct); `data` the stored bytes. `filelen`
defaults to len(data); `filepos` and `compresslen` default to the real layout."""


def archive(entries, magic=MAGIC, dirofs=None, dirlen=None):
    """-> archive bytes: header, stored bytes in entry order, directory."""
    body, records, pos = bytearray(), bytearray(), HEADER.size
    for e in entries:
        filelen = len(e.data) if e.filelen is None else e.filelen
        compresslen = len(e.data) if e.compresslen is None else e.compresslen
        filepos = pos if e.filepos is None else e.filepos
        records += DIRECTORY_ENTRY.pack(e.name, filepos, filelen, compresslen, e.compresstype)
        body += e.data
        pos += len(e.data)
    offset = HEADER.size + len(body) if dirofs is None else dirofs
    length = len(records) if dirlen is None else dirlen
    return HEADER.pack(magic, offset, length) + bytes(body) + bytes(records)


def write(path, blob):
    with open(path, "wb") as f:
        f.write(blob)
    return path
