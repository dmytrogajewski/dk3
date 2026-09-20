"""Deterministic pk3 writer (pk3.py): entries in the given order, stored, with a fixed date and mode, and
byte-identical archives for identical entries. Archives go to temporary directories.

FRD: specs/frds/FRD-010-standalone-dkq3-base-game-package.md
"""
import os
import tempfile
import unittest
import zipfile

import pk3
from tests import support

SCRIPT = os.path.join(support.TOOLS_DIR, "pk3.py")

ENTRIES = (("default.cfg", b"bind ESCAPE togglemenu\n"), ("models/a/b.md3", b"IDP3"), ("sound/c.wav", b"RIFF"))
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
UNIX_SYSTEM = 3
FILE_MODE = 0o644


class Pk3WriterTest(unittest.TestCase):
    def write(self, directory, entries=ENTRIES):
        path = os.path.join(directory, "out.pk3")
        pk3.write(path, entries)
        return path

    def test_entries_keep_their_order_and_bytes_stored_with_a_fixed_date_and_mode(self):
        with tempfile.TemporaryDirectory() as out:
            with zipfile.ZipFile(self.write(out)) as archive:
                self.assertEqual([name for name, _ in ENTRIES], archive.namelist())
                for info, (name, data) in zip(archive.infolist(), ENTRIES):
                    self.assertEqual(data, archive.read(name))
                    self.assertEqual((ZIP_EPOCH, zipfile.ZIP_STORED, UNIX_SYSTEM, FILE_MODE << 16, b""),
                                     (info.date_time, info.compress_type, info.create_system, info.external_attr,
                                      info.extra))
                self.assertEqual(b"", archive.comment)

    def test_entries_read_from_files_give_the_archive_of_the_same_bytes(self):
        # FRD-016: the maps packages read one BSP at a time instead of holding every map in memory
        with tempfile.TemporaryDirectory() as out:
            files = []
            for index, (name, data) in enumerate(ENTRIES):
                files.append((name, os.path.join(out, f"entry{index}")))
                with open(files[-1][1], "wb") as f:
                    f.write(data)
            target = os.path.join(out, "files.pk3")
            pk3.write_files(target, files)
            with open(target, "rb") as a, open(self.write(out), "rb") as b:
                self.assertEqual(b.read(), a.read())

    def test_identical_entries_give_byte_identical_archives(self):
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            with open(self.write(first), "rb") as a, open(self.write(second), "rb") as b:
                self.assertEqual(a.read(), b.read())

    def test_a_repeated_entry_name_is_refused_before_anything_is_written(self):
        with tempfile.TemporaryDirectory() as out:
            with self.assertRaisesRegex(pk3.Pk3Error, "default.cfg"):
                self.write(out, ENTRIES + (("default.cfg", b""),))
            self.assertEqual([], os.listdir(out))

    def test_a_directory_argument_adds_every_file_below_it_sorted_by_entry_name(self):
        # Roadmap Step 37 packs pak1's 1,380 subtitles/*.txt as one `subtitles/=DIR` argument.
        with tempfile.TemporaryDirectory() as out:
            tree = os.path.join(out, "tree")
            os.makedirs(os.path.join(tree, "deep"))
            for leaf, data in (("b.txt", b"bee"), ("a.txt", b"ay"), (os.path.join("deep", "c.txt"), b"cee")):
                with open(os.path.join(tree, leaf), "wb") as f:
                    f.write(data)
            target = os.path.join(out, "dir.pk3")
            proc = support.run_python([SCRIPT, target, f"subtitles/={tree}"], out)
            self.assertEqual(0, proc.returncode, proc.stderr)
            with zipfile.ZipFile(target) as archive:
                self.assertEqual(["subtitles/a.txt", "subtitles/b.txt", "subtitles/deep/c.txt"], archive.namelist())
                self.assertEqual(b"cee", archive.read("subtitles/deep/c.txt"))
            # The order is a function of the entry names, not of the order the file system lists the directory in, and a
            # name without a trailing slash still separates from what it prefixes.
            self.assertEqual(["subtitles/a.txt", "subtitles/b.txt", "subtitles/deep/c.txt"],
                             [name for name, _ in pk3.directory_entries("subtitles", tree)])

    def test_the_command_line_writes_each_name_from_its_file_in_the_given_order(self):
        with tempfile.TemporaryDirectory() as out:
            sources = []
            for name, data in ENTRIES:
                sources.append(os.path.join(out, os.path.basename(name)))
                with open(sources[-1], "wb") as f:
                    f.write(data)
            target = os.path.join(out, "cli.pk3")
            args = [f"{name}={source}" for (name, _), source in zip(ENTRIES, sources)]
            proc = support.run_python([SCRIPT, target, *args], out)
            self.assertEqual(0, proc.returncode, proc.stderr)
            with open(target, "rb") as a, open(self.write(out), "rb") as b:
                self.assertEqual(b.read(), a.read())


if __name__ == "__main__":
    unittest.main()
