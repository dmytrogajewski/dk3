"""dk_unzip: extracts one member to the given output file and writes nothing else.

FRD: specs/frds/FRD-003-converter-tooling-contract-paths-as-arguments-pinned-runtime.md
"""
import os
import tempfile
import unittest
import zipfile

from tests import support

SCRIPT = os.path.join(support.TOOLS_DIR, "dk_unzip.py")
MEMBER = "pak5.pak"
PAYLOAD = b"PACK" + bytes(range(256)) * 4


def tree(root):
    return sorted(os.path.relpath(os.path.join(d, f), root)
                  for d, _, files in os.walk(root) for f in files)


class DkUnzipTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.zip = os.path.join(self.root, "data", "pak5.zip")
        os.makedirs(os.path.dirname(self.zip))
        with zipfile.ZipFile(self.zip, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr(MEMBER, PAYLOAD)
        os.makedirs(os.path.join(self.root, "cwd"))

    def tearDown(self):
        self.tmp.cleanup()

    def extract(self, member, out):
        return support.run_python([SCRIPT, "--zip", self.zip, "--member", member, "--out", out],
                                  os.path.join(self.root, "cwd"))

    def test_extracts_member_bytes_to_out_and_nothing_else(self):
        out = os.path.join(self.root, "cache", "o", "h", MEMBER)
        os.makedirs(os.path.dirname(out))
        proc = self.extract(MEMBER, out)
        self.assertEqual(0, proc.returncode, proc.stderr)
        with open(out, "rb") as f:
            self.assertEqual(PAYLOAD, f.read())
        self.assertEqual(["cache/o/h/pak5.pak", "data/pak5.zip"], tree(self.root))

    def test_missing_member_fails_naming_it(self):
        out = os.path.join(self.root, MEMBER)
        proc = self.extract("pak9.pak", out)
        self.assertNotEqual(0, proc.returncode)
        self.assertIn("pak9.pak", proc.stderr)
        self.assertFalse(os.path.exists(out))


if __name__ == "__main__":
    unittest.main()
