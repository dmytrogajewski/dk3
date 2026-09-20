"""Daikatana PAK reader and writer, matching the engine loader (specs/assets/ASSET-pak.md).

Header (`dpackheader_t`, 12 bytes): 'PACK', int32 dirofs, int32 dirlen.
Directory entry (`dpackfile_t`, 72 bytes): char name[56]; int32 filepos, filelen, compresslen,
compresstype. A non-zero compresstype marks a compressed stream, decoded like
reference/dk-gold/base/qcommon/files.cpp FS_LoadFile, one code byte at a time:
  0-63     literal run: the next code+1 stream bytes
  64-127   zero run: code-62 zero bytes
  128-191  repeat: the next stream byte, code-126 times
  192-253  back-reference: code-190 bytes, each copied from (next stream byte + 2) bytes back
  254      no output; only the code byte is consumed
  255      terminator
Malformed input raises a PakError subclass naming the archive file, the entry and the offset.
"""
import os
import struct

# dpackheader_t (qfiles.h:30-35), dpackfile_t (qfiles.h:22-28) and the entry limit (qfiles.h:38).
HEADER = struct.Struct('<4sii')
MAGIC = b'PACK'
IDENT_OFFSET, DIROFS_OFFSET, DIRLEN_OFFSET = 0, 4, 8
HEADER_ENTRY = '<header>'
ENTRY_SIZE = 72
NAME_SIZE = 56
DIRECTORY_FIELDS = struct.Struct('<iiii')  # filepos, filelen, compresslen, compresstype
MAX_FILES_IN_PACK = 20480

# Code ranges and biases, files.cpp:916-964.
LITERAL_MAX, LITERAL_BIAS = 63, 1
ZERO_RUN_MAX, ZERO_RUN_BIAS = 127, 62
REPEAT_MAX, REPEAT_BIAS = 191, 126
BACK_REFERENCE_MAX, BACK_REFERENCE_BIAS = 253, 190
DISTANCE_BIAS = 2
CODE_SKIP = 254
CODE_END = 255
# Encoder limits derived from the table: the longest literal and the longest zero or repeat run.
LONGEST_LITERAL = LITERAL_MAX + LITERAL_BIAS
LONGEST_RUN = ZERO_RUN_MAX - ZERO_RUN_BIAS
SHORTEST_ENCODED_RUN = 3  # a run of 2 costs as much as a literal


class PakError(ValueError):
    """Malformed PAK data. Names the archive file, the entry and the byte offset of the fault."""

    def __init__(self, file, entry, offset, detail):
        super().__init__(f'{file}: {entry}: offset {offset}: {detail}')
        self.file, self.entry, self.offset = file, entry, offset


class TruncatedStream(PakError):
    """The compressed stream ends before a byte a code needs, or before the terminator."""


class BackReferenceBeforeStart(PakError):
    """A back-reference distance reaches before the first output byte."""


class OutputOverrun(PakError):
    """The decoded output passes the entry's declared length."""


class LengthMismatch(PakError):
    """The terminator arrives before the output reaches the entry's declared length."""


class BadHeader(PakError):
    """The header is short, has the wrong ident, or describes a directory the file cannot hold."""


class BadEntryName(PakError):
    """A directory entry's name has no NUL terminator within its 56 bytes."""


class EntryPastArchiveEnd(PakError):
    """An entry's stored bytes start before the file or end after it."""


def _require(src, start, pos, count, file, entry):
    """Raises TruncatedStream at the code offset `start` unless `count` bytes follow `pos`."""
    if pos + count > len(src):
        raise TruncatedStream(file, entry, start,
                              f'code needs {count} bytes at {pos}; the stream ends at {len(src)}')


def decompress(src, outlen, file, entry, on_code=None):
    """Decodes one compressed entry like files.cpp FS_LoadFile -> (bytes, stream bytes consumed).

    Decoding stops at code 255; later stream bytes are not read. `file` and `entry` name the fault
    in the PakError raised for malformed streams. `on_code(offset, code)`, when given, sees every
    code byte read, so checks can histogram codes without a second parser."""
    out = bytearray(); pos = 0
    while True:
        if pos >= len(src):
            raise TruncatedStream(file, entry, pos, f'stream ends before the terminator code {CODE_END}')
        start, code = pos, src[pos]; pos += 1
        if on_code is not None:
            on_code(start, code)
        if code == CODE_END:
            break
        if code <= LITERAL_MAX:
            count = code + LITERAL_BIAS
            _require(src, start, pos, count, file, entry); out += src[pos:pos + count]; pos += count
        elif code <= ZERO_RUN_MAX:
            out += bytes(code - ZERO_RUN_BIAS)
        elif code <= REPEAT_MAX:
            _require(src, start, pos, 1, file, entry); out += src[pos:pos + 1] * (code - REPEAT_BIAS); pos += 1
        elif code <= BACK_REFERENCE_MAX:
            _require(src, start, pos, 1, file, entry)
            distance = src[pos] + DISTANCE_BIAS; pos += 1
            if distance > len(out):
                raise BackReferenceBeforeStart(file, entry, start,
                                               f'distance {distance} with {len(out)} bytes of output')
            for _ in range(code - BACK_REFERENCE_BIAS):  # byte by byte: a copy may overlap its output
                out.append(out[-distance])
        if len(out) > outlen:
            raise OutputOverrun(file, entry, start, f'output reaches {len(out)} bytes; the entry declares {outlen}')
    if len(out) != outlen:
        raise LengthMismatch(file, entry, start, f'terminator after {len(out)} bytes; the entry declares {outlen}')
    return bytes(out), pos


def compress(data):
    """Conservative encoder: literal runs and zero/repeat runs, no back-references, terminated by
    code 255. Valid for FS_LoadFile; about 1:1 for noise."""
    out = bytearray(); i = 0; n = len(data); lit = bytearray()

    def flush():
        nonlocal lit, out
        while lit:
            k = min(LONGEST_LITERAL, len(lit)); out.append(k - LITERAL_BIAS); out += lit[:k]; del lit[:k]
    while i < n:
        b = data[i]; j = i
        while j < n and data[j] == b and j - i < LONGEST_RUN: j += 1
        run = j - i
        if run >= SHORTEST_ENCODED_RUN:
            flush()
            if b == 0: out.append(run + ZERO_RUN_BIAS)
            else: out.append(run + REPEAT_BIAS); out.append(b)
            i = j
        else:
            lit.append(b); i += 1
    flush()
    out.append(CODE_END)  # FS_LoadFile reads codes until the terminator (files.cpp:916-917)
    return bytes(out)


class Pak:
    """One archive. `entries` maps lower-case '/' names to (filepos, filelen, compresslen,
    compresstype); `order` lists names in directory order."""

    def __init__(self, path):
        self.path = path
        self.f = open(path, 'rb')
        try:
            self._read_directory()
        except BaseException:
            self.f.close()
            raise

    def _read_directory(self):
        self.size = os.fstat(self.f.fileno()).st_size
        head = self.f.read(HEADER.size)
        if len(head) < HEADER.size or head[:len(MAGIC)] != MAGIC:
            raise BadHeader(self.path, HEADER_ENTRY, IDENT_OFFSET, f'expected {MAGIC!r} in a {HEADER.size}-byte header')
        _, off, ln = HEADER.unpack(head)
        if ln < 0 or ln % ENTRY_SIZE or ln // ENTRY_SIZE > MAX_FILES_IN_PACK:
            raise BadHeader(self.path, HEADER_ENTRY, DIRLEN_OFFSET,
                            f'dirlen {ln} is not {ENTRY_SIZE} bytes per entry for at most {MAX_FILES_IN_PACK} entries')
        if off < 0 or off + ln > self.size:
            raise BadHeader(self.path, HEADER_ENTRY, DIROFS_OFFSET,
                            f'directory of {ln} bytes at {off} passes the archive end at {self.size}')
        self.f.seek(off); d = self.f.read(ln); self.entries = {}; self.order = []
        for i in range(ln // ENTRY_SIZE):
            e = d[i * ENTRY_SIZE:(i + 1) * ENTRY_SIZE]
            if b'\0' not in e[:NAME_SIZE]:
                raise BadEntryName(self.path, e[:NAME_SIZE].decode('latin1'), off + i * ENTRY_SIZE,
                                   f'name has no NUL within its {NAME_SIZE} bytes')
            nm = e[:NAME_SIZE].split(b'\0')[0].decode('latin1').replace('\\', '/').lower()
            self.entries[nm] = DIRECTORY_FIELDS.unpack(e[NAME_SIZE:]); self.order.append(nm)

    def close(self):
        self.f.close()

    def stored(self, name):
        """The entry's stored bytes: `compresslen` bytes when compressed, `filelen` otherwise."""
        pos, ln, pln, comp = self.entries[name]
        length = pln if comp else ln
        if pos < 0 or length < 0 or pos + length > self.size:
            raise EntryPastArchiveEnd(self.path, name, pos,
                                      f'{length} stored bytes at {pos} pass the archive end at {self.size}')
        self.f.seek(pos)
        return self.f.read(length)

    def read(self, name):
        """The entry's decoded bytes."""
        _, ln, _, comp = self.entries[name]
        raw = self.stored(name)
        return decompress(raw, ln, self.path, name)[0] if comp else raw


def write_pak(path, files, compress_data=False):
    """Writes `files` (name -> bytes) as an archive with entries in name order, so equal inputs give
    equal bytes. With `compress_data`, an entry is stored compressed when that is smaller. A name
    that does not fit name[56] with its NUL, or that Pak would read back differently (upper case or
    '\\'), raises ValueError before the file is created."""
    for name in files:
        if len(name.encode('latin1')) >= NAME_SIZE or name != name.lower().replace('\\', '/'):
            raise ValueError(f'{path}: entry name {name} must be shorter than {NAME_SIZE} bytes, '
                             f'lower case, with / separators')
    with open(path, 'wb') as f:
        f.write(HEADER.pack(MAGIC, 0, 0))
        dirents = []
        for name, data in sorted(files.items()):  # name order: equal inputs give equal bytes
            pos = f.tell()
            if compress_data:
                packed = compress(data)
                if len(packed) < len(data):
                    f.write(packed); dirents.append((name, pos, len(data), len(packed), 1)); continue
            f.write(data); dirents.append((name, pos, len(data), len(data), 0))
        dirofs = f.tell()
        for name, pos, ln, pln, comp in dirents:
            f.write(struct.pack(f'<{NAME_SIZE}s', name.encode('latin1')) + DIRECTORY_FIELDS.pack(pos, ln, pln, comp))
        dirlen = f.tell() - dirofs
        f.seek(DIROFS_OFFSET)
        f.write(struct.pack('<ii', dirofs, dirlen))
