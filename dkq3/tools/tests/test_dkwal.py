"""dkwal: miptex_t and miptexOld_t headers read field by field at their C offsets, layout selection by
GL_LoadWal's version test, and named errors for malformed or engine-rejected files.

Every file is built from named constants (tests/synthetic_wal.py); no game data is read. Every field
gets a distinct non-zero value, so a shifted read fails.

FRD: specs/frds/FRD-005-wal-parser-matches-miptex-t.md
"""
import unittest

import dkwal
from tests import synthetic_wal as sw

WIDTH, HEIGHT = 4, 2
NAME = b"e1m1/wall"
ANIMNAME = b"e1m1/+1wall"
FLAGS = 0x00080000       # SURF_MIDTEXTURE (dk_shared.h:350), the non-zero flag the corpus uses
CONTENTS = 0x00000020    # CONTENTS_WATER
VALUE = 0x1234
PALETTE = bytes(range(256)) * 3
ENTRY = "textures/synthetic.wal"
FULL_NAME_CHAR = b"n"
NEGATIVE_FLAGS, NEGATIVE_CONTENTS, NEGATIVE_VALUE = -2, -3, -4
# GL_LoadWal (gl_image.cpp:1690-1698) reads the first byte as a signed char: above 0x20 is a Quake II
# name, 3 is MIPTEX_VERSION, anything else is ERR_DROP.
SPACE = 0x20
FIRST_NAME_BYTE = SPACE + 1
VERSION_2 = 2
NEGATIVE_CHAR = -0x80     # byte 0x80


class NamedErrorAssertions:
    def assertNamed(self, error, offset, entry=ENTRY):
        self.assertIsInstance(error, dkwal.WalError)
        self.assertEqual((entry, offset), (error.entry, error.offset))
        self.assertIn(f"{entry}: offset {offset}:", str(error))


class LayoutSelectionTest(NamedErrorAssertions, unittest.TestCase):
    def test_first_byte_above_0x20_selects_the_quake_ii_layout(self):
        raw = sw.miptex_old(name=bytes([FIRST_NAME_BYTE]) + NAME)
        self.assertEqual(dkwal.LAYOUT_MIPTEX_OLD, dkwal.parse_wal(raw, ENTRY).layout)

    def test_other_versions_raise_unsupported_version_like_gl_loadwal(self):
        for version in (SPACE, VERSION_2, NEGATIVE_CHAR):
            with self.subTest(version=version), self.assertRaises(dkwal.UnsupportedVersion) as caught:
                dkwal.parse_wal(sw.miptex(version=version), ENTRY)
            self.assertNamed(caught.exception, 0)
            self.assertIn(f"version {version}", str(caught.exception))


class MiptexLayoutTest(unittest.TestCase):
    def test_every_miptex_t_field_is_read_at_its_c_offset(self):
        raw = sw.miptex(WIDTH, HEIGHT, name=NAME, animname=ANIMNAME, flags=FLAGS,
                        contents=CONTENTS, palette=PALETTE, value=VALUE)
        offsets, _ = sw.chain(WIDTH, HEIGHT, sw.MIPLEVELS, sw.MIPTEX_SIZE)
        t = dkwal.parse_wal(raw)
        self.assertEqual(
            (dkwal.LAYOUT_MIPTEX, sw.MIPTEX_VERSION, NAME.decode(), WIDTH, HEIGHT, tuple(offsets),
             ANIMNAME.decode(), FLAGS, CONTENTS, PALETTE, VALUE, sw.MIPTEX_SIZE),
            (t.layout, t.version, t.name, t.width, t.height, t.offsets,
             t.animname, t.flags, t.contents, t.palette, t.value, t.header_size))

    def test_alignment_padding_after_name_is_ignored(self):
        raw = bytearray(sw.miptex(WIDTH, HEIGHT, name=NAME))
        raw[sw.PADDING_AT:sw.PADDING_AT + sw.PADDING_SIZE] = b"\xff" * sw.PADDING_SIZE
        t = dkwal.parse_wal(bytes(raw))
        self.assertEqual((NAME.decode(), WIDTH, HEIGHT), (t.name, t.width, t.height))


class MiptexOldLayoutTest(unittest.TestCase):
    def test_every_miptexold_t_field_is_read_at_its_c_offset(self):
        raw = sw.miptex_old(WIDTH, HEIGHT, name=NAME, animname=ANIMNAME, flags=FLAGS,
                            contents=CONTENTS, value=VALUE)
        offsets, _ = sw.chain(WIDTH, HEIGHT, sw.MIPLEVELS_OLD, sw.MIPTEX_OLD_SIZE)
        t = dkwal.parse_wal(raw)
        self.assertEqual(
            (dkwal.LAYOUT_MIPTEX_OLD, None, NAME.decode(), WIDTH, HEIGHT, tuple(offsets),
             ANIMNAME.decode(), FLAGS, CONTENTS, None, VALUE, sw.MIPTEX_OLD_SIZE),
            (t.layout, t.version, t.name, t.width, t.height, t.offsets,
             t.animname, t.flags, t.contents, t.palette, t.value, t.header_size))


class FieldEncodingTest(unittest.TestCase):
    def test_names_without_nul_keep_32_bytes_and_integers_are_signed(self):
        full = FULL_NAME_CHAR * sw.NAME_SIZE
        for raw in (sw.miptex(name=full, animname=full, flags=NEGATIVE_FLAGS, contents=NEGATIVE_CONTENTS,
                              value=NEGATIVE_VALUE),
                    sw.miptex_old(name=full, animname=full, flags=NEGATIVE_FLAGS,
                                  contents=NEGATIVE_CONTENTS, value=NEGATIVE_VALUE)):
            t = dkwal.parse_wal(raw)
            with self.subTest(layout=t.layout):
                self.assertEqual((full.decode(), full.decode(), NEGATIVE_FLAGS, NEGATIVE_CONTENTS, NEGATIVE_VALUE),
                                 (t.name, t.animname, t.flags, t.contents, t.value))


class HeaderErrorTest(NamedErrorAssertions, unittest.TestCase):
    def test_file_shorter_than_its_layout_header_raises_truncated_header_at_its_end(self):
        cases = {"empty": b"", "miptex_t": sw.miptex()[:sw.MIPTEX_SIZE - 1],
                 "miptexOld_t": sw.miptex_old()[:sw.MIPTEX_OLD_SIZE - 1]}
        for label, raw in cases.items():
            with self.subTest(label), self.assertRaises(dkwal.TruncatedHeader) as caught:
                dkwal.parse_wal(raw, ENTRY)
            self.assertNamed(caught.exception, len(raw))

    def test_zero_width_or_height_raises_zero_dimension_at_the_field(self):
        # GL_LoadPic (gl_image.cpp:1547-1548) stops with ERR_FATAL on a 0 width or height.
        cases = {("miptex_t", "width"): (sw.miptex(0, HEIGHT), sw.WIDTH_AT),
                 ("miptex_t", "height"): (sw.miptex(WIDTH, 0), sw.HEIGHT_AT),
                 ("miptexOld_t", "width"): (sw.miptex_old(0, HEIGHT), sw.OLD_WIDTH_AT),
                 ("miptexOld_t", "height"): (sw.miptex_old(WIDTH, 0), sw.OLD_HEIGHT_AT)}
        for label, (raw, offset) in cases.items():
            with self.subTest(label), self.assertRaises(dkwal.ZeroDimension) as caught:
                dkwal.parse_wal(raw, ENTRY)
            self.assertNamed(caught.exception, offset)


class MipBoundsTest(NamedErrorAssertions, unittest.TestCase):
    def test_mip_0_inside_the_header_or_past_the_file_end_raises_mip_past_end(self):
        # GL_LoadWal hands offsets[0] and width*height texels to GL_LoadPic unchecked (gl_image.cpp:1703-1715).
        inside = sw.MIPTEX_SIZE - 1
        cases = {"miptex_t past end": (sw.miptex(WIDTH, HEIGHT, body=b""), sw.MIPTEX_SIZE),
                 "miptex_t inside header": (sw.miptex(offsets=[inside] + [0] * (sw.MIPLEVELS - 1)), inside),
                 "miptexOld_t past end": (sw.miptex_old(WIDTH, HEIGHT, body=b""), sw.MIPTEX_OLD_SIZE)}
        for label, (raw, offset) in cases.items():
            with self.subTest(label), self.assertRaises(dkwal.MipPastEnd) as caught:
                dkwal.parse_wal(raw, ENTRY)
            self.assertNamed(caught.exception, offset)

    def test_mip_level_dimensions_halve_down_to_1_and_its_texels_are_returned(self):
        raw = sw.miptex(WIDTH, HEIGHT)
        offsets, _ = sw.chain(WIDTH, HEIGHT, sw.MIPLEVELS, sw.MIPTEX_SIZE)
        t = dkwal.parse_wal(raw, ENTRY)
        for level, (width, height) in ((1, (WIDTH // 2, HEIGHT // 2)), (2, (1, 1)), (sw.MIPLEVELS - 1, (1, 1))):
            with self.subTest(level=level):
                texels = raw[offsets[level]:offsets[level] + width * height]
                self.assertEqual((width, height, texels), t.mip(level))

    def test_unused_mip_level_raises_mip_past_end(self):
        t = dkwal.parse_wal(sw.miptex(WIDTH, HEIGHT, levels=1), ENTRY)
        with self.assertRaises(dkwal.MipPastEnd) as caught:
            t.mip(1)
        self.assertNamed(caught.exception, 0)


if __name__ == "__main__":
    unittest.main()
