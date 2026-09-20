"""dkpak: decoder semantics of files.cpp FS_LoadFile, named errors, deterministic writer.

Every stream and archive is built here from named constants; no game data is read. Expected bytes
are computed by hand from reference/dk-gold/base/qcommon/files.cpp:910-966.

FRD: specs/frds/FRD-004-pak-reader-matches-files-cpp-codes-254-255.md
"""
import os
import tempfile
import unittest

import dkpak
from tests import synthetic_pak

FILE = "synthetic.pak"
ENTRY = "textures/synthetic.wal"

# dpackheader_t field offsets (qfiles.h:30-35), dpackfile_t size (qfiles.h:22-28), entry limit (qfiles.h:38).
IDENT_OFFSET, DIROFS_OFFSET, DIRLEN_OFFSET = 0, 4, 8
IDENT_SIZE = 4
HEADER_SIZE = 12
ENTRY_SIZE = 72
NAME_SIZE = 56
NAME_CHAR = b"n"
NEGATIVE_FILEPOS = -1
# Writer names: no room for the NUL in name[56]; names Pak reads back lower-cased with '/'.
UNTERMINATED_NAME = NAME_CHAR.decode() * NAME_SIZE
MIXED_CASE_NAME = "Textures/Synthetic.wal"
BACKSLASH_NAME = "textures\\synthetic.wal"
MAX_FILES_IN_PACK = 20480
WRONG_IDENT = b"IBSP"
HEADER_ENTRY = "<header>"

# files.cpp:916-964 code ranges, written out independently of dkpak's constants.
LITERAL_MIN, LITERAL_MAX = 0, 63
ZERO_RUN_MIN, ZERO_RUN_MAX = 64, 127
REPEAT_MIN, REPEAT_MAX = 128, 191
BACK_REFERENCE_MIN, BACK_REFERENCE_MAX = 192, 253
CODE_SKIP = 254
CODE_END = 255
# Run lengths at the ends of each range: zero run code-62, repeat code-126, back-reference code-190.
SHORTEST_RUN, LONGEST_RUN = 2, 65
LONGEST_BACK_REFERENCE = 63
# Back-reference distance = offset byte + 2 (files.cpp:962).
OFFSET_FOR_DISTANCE_2, OFFSET_FOR_DISTANCE_3 = 0, 1
FILL = b"x"

PAYLOAD = b"abc"
LONGEST_LITERAL = bytes(range(LITERAL_MAX + 1))
# Writer inputs: insertion order differs from name order; the runs compress, the short literal does not.
WRITTEN_FILES = {
    "textures/zeros.wal": bytes(LONGEST_RUN),
    "maps/runs.bsp": FILL * LONGEST_RUN + PAYLOAD,
    "sound/short.wav": PAYLOAD,
}


def decode(stream, outlen):
    return dkpak.decompress(stream, outlen, FILE, ENTRY)


class LiteralRunTest(unittest.TestCase):
    def test_literal_code_copies_code_plus_one_bytes_and_stops_at_the_terminator(self):
        for code, literal in ((LITERAL_MIN, PAYLOAD[:1]), (LITERAL_MAX, LONGEST_LITERAL)):
            with self.subTest(code=code):
                stream = bytes([code]) + literal + bytes([CODE_END])
                self.assertEqual((literal, len(stream)), decode(stream, len(literal)))


class ZeroRunTest(unittest.TestCase):
    def test_zero_run_code_emits_code_minus_62_zero_bytes(self):
        for code, length in ((ZERO_RUN_MIN, SHORTEST_RUN), (ZERO_RUN_MAX, LONGEST_RUN)):
            with self.subTest(code=code):
                stream = bytes([code, CODE_END])
                self.assertEqual((bytes(length), len(stream)), decode(stream, length))


class RepeatTest(unittest.TestCase):
    def test_repeat_code_emits_the_next_byte_code_minus_126_times(self):
        for code, length in ((REPEAT_MIN, SHORTEST_RUN), (REPEAT_MAX, LONGEST_RUN)):
            with self.subTest(code=code):
                stream = bytes([code]) + FILL + bytes([CODE_END])
                self.assertEqual((FILL * length, len(stream)), decode(stream, length))


class BackReferenceTest(unittest.TestCase):
    def test_back_reference_copies_code_minus_190_bytes_from_offset_plus_2_back(self):
        prefix = bytes([len(PAYLOAD) - 1]) + PAYLOAD
        stream = prefix + bytes([BACK_REFERENCE_MIN, OFFSET_FOR_DISTANCE_3, CODE_END])
        self.assertEqual((b"abcab", len(stream)), decode(stream, len(PAYLOAD) + SHORTEST_RUN))

    def test_overlapping_back_reference_repeats_bytes_it_has_just_written(self):
        stream = bytes([1]) + PAYLOAD[:2] + bytes([BACK_REFERENCE_MAX, OFFSET_FOR_DISTANCE_2, CODE_END])
        expected = (PAYLOAD[:2] * LONGEST_RUN)[:2 + LONGEST_BACK_REFERENCE]
        self.assertEqual((expected, len(stream)), decode(stream, len(expected)))


class TerminatorTest(unittest.TestCase):
    def test_code_255_ends_decoding_and_later_bytes_are_not_read(self):
        head = bytes([LITERAL_MIN]) + PAYLOAD[:1] + bytes([CODE_END])
        stream = head + bytes([LITERAL_MIN]) + PAYLOAD[1:2]
        self.assertEqual((PAYLOAD[:1], len(head)), decode(stream, 1))


class SkipCodeTest(unittest.TestCase):
    def test_code_254_consumes_only_its_code_byte_and_emits_nothing(self):
        # files.cpp:951 excludes 254 from the back-reference branch; no other branch matches it.
        stream = bytes([LITERAL_MIN]) + PAYLOAD[:1] + bytes([CODE_SKIP, LITERAL_MIN]) \
            + PAYLOAD[1:2] + bytes([CODE_END])
        self.assertEqual((PAYLOAD[:2], len(stream)), decode(stream, 2))


class NamedErrorAssertions:
    def assertNamed(self, error, offset, file=FILE, entry=ENTRY):
        self.assertEqual((file, entry, offset), (error.file, error.entry, error.offset))
        self.assertIn(f"{file}: {entry}: offset {offset}:", str(error))


class CodeObserverTest(unittest.TestCase):
    def test_on_code_sees_every_code_with_its_stream_offset(self):
        stream = bytes([LITERAL_MIN]) + PAYLOAD[:1] + bytes([CODE_SKIP, REPEAT_MIN]) + FILL + bytes([CODE_END])
        seen = []
        dkpak.decompress(stream, 1 + SHORTEST_RUN, FILE, ENTRY,
                         on_code=lambda offset, code: seen.append((offset, code)))
        self.assertEqual([(0, LITERAL_MIN), (2, CODE_SKIP), (3, REPEAT_MIN), (5, CODE_END)], seen)


class TruncatedStreamTest(NamedErrorAssertions, unittest.TestCase):
    def test_stream_without_terminator_raises_at_its_end(self):
        stream = bytes([LITERAL_MIN]) + PAYLOAD[:1]
        with self.assertRaises(dkpak.TruncatedStream) as caught:
            decode(stream, 1)
        self.assertNamed(caught.exception, len(stream))

    def test_code_whose_bytes_pass_the_stream_end_raises_at_the_code(self):
        prefix = bytes([LITERAL_MIN]) + PAYLOAD[:1]
        cut = {"literal": bytes([len(PAYLOAD)]) + PAYLOAD, "repeat parameter": bytes([REPEAT_MIN]),
               "back-reference parameter": bytes([BACK_REFERENCE_MIN])}
        for name, tail in cut.items():
            with self.subTest(name):
                with self.assertRaises(dkpak.TruncatedStream) as caught:
                    decode(prefix + tail, len(PAYLOAD) + 2)
                self.assertNamed(caught.exception, len(prefix))


class BackReferenceBeforeStartTest(NamedErrorAssertions, unittest.TestCase):
    def test_distance_beyond_the_output_so_far_raises_at_the_code(self):
        # One byte of output, then a distance of 2: files.cpp:962 would read before dst_data.
        prefix = bytes([LITERAL_MIN]) + PAYLOAD[:1]
        stream = prefix + bytes([BACK_REFERENCE_MIN, OFFSET_FOR_DISTANCE_2, CODE_END])
        with self.assertRaises(dkpak.BackReferenceBeforeStart) as caught:
            decode(stream, 1 + SHORTEST_RUN)
        self.assertNamed(caught.exception, len(prefix))


class OutputLengthTest(NamedErrorAssertions, unittest.TestCase):
    def test_output_passing_the_declared_length_raises_at_the_code(self):
        # files.cpp:905 allocates filelen bytes; a longer output would write past them.
        prefix = bytes([LITERAL_MIN]) + PAYLOAD[:1]
        stream = prefix + bytes([ZERO_RUN_MAX, CODE_END])
        with self.assertRaises(dkpak.OutputOverrun) as caught:
            decode(stream, SHORTEST_RUN)
        self.assertNamed(caught.exception, len(prefix))

    def test_terminator_before_the_declared_length_raises_at_the_terminator(self):
        # files.cpp:969-970 would return filelen bytes with an uninitialized tail.
        prefix = bytes([LITERAL_MIN]) + PAYLOAD[:1]
        with self.assertRaises(dkpak.LengthMismatch) as caught:
            decode(prefix + bytes([CODE_END]), len(PAYLOAD))
        self.assertNamed(caught.exception, len(prefix))


class ArchiveTestCase(NamedErrorAssertions, unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = os.path.join(self.tmp.name, FILE)

    def open(self, blob):
        pak = dkpak.Pak(synthetic_pak.write(self.path, blob))
        self.addCleanup(pak.close)
        return pak


class ArchiveHeaderTest(ArchiveTestCase):
    def test_malformed_header_raises_bad_header_at_the_field_offset(self):
        # qfiles.h:30-38, files.cpp:1036-1066.
        cases = {
            "short file": (synthetic_pak.MAGIC[:IDENT_SIZE - 1], IDENT_OFFSET),
            "wrong ident": (synthetic_pak.archive([], magic=WRONG_IDENT), IDENT_OFFSET),
            "negative dirlen": (synthetic_pak.archive([], dirlen=-ENTRY_SIZE), DIRLEN_OFFSET),
            "partial entry": (synthetic_pak.archive([], dirlen=ENTRY_SIZE - 1), DIRLEN_OFFSET),
            "too many entries": (synthetic_pak.archive([], dirlen=(MAX_FILES_IN_PACK + 1) * ENTRY_SIZE),
                                 DIRLEN_OFFSET),
            "directory past end": (synthetic_pak.archive([], dirlen=ENTRY_SIZE), DIROFS_OFFSET),
        }
        for name, (blob, offset) in cases.items():
            with self.subTest(name):
                with self.assertRaises(dkpak.BadHeader) as caught:
                    self.open(blob)
                self.assertNamed(caught.exception, offset, file=self.path, entry=HEADER_ENTRY)


class DirectoryEntryTest(ArchiveTestCase):
    def test_name_without_nul_raises_bad_entry_name_at_the_directory_entry(self):
        # qfiles.h:24 name[56]; files.cpp:1104 strcpy would read on into filepos.
        unterminated = NAME_CHAR * NAME_SIZE
        blob = synthetic_pak.archive([synthetic_pak.Entry(unterminated, PAYLOAD)])
        with self.assertRaises(dkpak.BadEntryName) as caught:
            self.open(blob)
        self.assertNamed(caught.exception, HEADER_SIZE + len(PAYLOAD), file=self.path,
                         entry=unterminated.decode("latin1"))


class EntryBoundsTest(ArchiveTestCase):
    def test_entry_past_the_archive_end_raises_at_its_filepos(self):
        # files.cpp:831-847: FS_Read stops with ERR_FATAL when the archive ends before the entry.
        size = HEADER_SIZE + len(PAYLOAD) + ENTRY_SIZE
        name = ENTRY.encode("latin1")
        cases = {
            "stored": synthetic_pak.Entry(name, PAYLOAD, filepos=size - 1),
            "compressed": synthetic_pak.Entry(name, PAYLOAD, len(PAYLOAD), synthetic_pak.COMPRESSED,
                                              compresslen=size - HEADER_SIZE + 1),
            "negative filepos": synthetic_pak.Entry(name, PAYLOAD, filepos=NEGATIVE_FILEPOS),
        }
        for case, entry in cases.items():
            pak = self.open(synthetic_pak.archive([entry]))
            for read in (pak.stored, pak.read):
                with self.subTest(case=case, read=read.__name__):
                    with self.assertRaises(dkpak.EntryPastArchiveEnd) as caught:
                        read(ENTRY)
                    offset = HEADER_SIZE if entry.filepos is None else entry.filepos
                    self.assertNamed(caught.exception, offset, file=self.path)


class WriterTest(ArchiveTestCase):
    def write(self, label, files, compress_data):
        path = os.path.join(self.tmp.name, f"{label}-{compress_data}.pak")
        dkpak.write_pak(path, files, compress_data)
        return path

    def test_written_archive_reads_back_every_entry(self):
        for compress_data in (False, True):
            with self.subTest(compress_data=compress_data):
                pak = dkpak.Pak(self.write("round-trip", WRITTEN_FILES, compress_data))
                self.addCleanup(pak.close)
                self.assertEqual(WRITTEN_FILES, {name: pak.read(name) for name in pak.order})

    def test_two_writes_of_the_same_files_are_byte_identical_whatever_the_insertion_order(self):
        reordered = dict(reversed(list(WRITTEN_FILES.items())))
        for compress_data in (False, True):
            with self.subTest(compress_data=compress_data):
                first = self.write("first", WRITTEN_FILES, compress_data)
                second = self.write("second", reordered, compress_data)
                with open(first, "rb") as a, open(second, "rb") as b:
                    self.assertEqual(a.read(), b.read())

    def test_names_that_do_not_fit_or_would_read_back_differently_are_rejected_before_writing(self):
        path = os.path.join(self.tmp.name, "rejected.pak")
        for name in (UNTERMINATED_NAME, MIXED_CASE_NAME, BACKSLASH_NAME):
            with self.subTest(name=name):
                with self.assertRaises(ValueError) as caught:
                    dkpak.write_pak(path, {name: PAYLOAD})
                self.assertIn(name, str(caught.exception))
                self.assertFalse(os.path.exists(path))


if __name__ == "__main__":
    unittest.main()
