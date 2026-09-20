#!/usr/bin/env python3
"""Extract one member of a zip archive to an explicit output file.

`zig build assets-pak5` (build/assets.zig) runs it to unwrap `pak5.pak` from `<DK_DATA>/pak5.zip`
into the Zig cache. It writes the output file only, streaming, and zipfile verifies the CRC.
"""
import argparse
import shutil
import sys
import zipfile


def extract(archive, member, out):
    with zipfile.ZipFile(archive) as z:
        try:
            info = z.getinfo(member)
        except KeyError:
            raise SystemExit(f'dk_unzip: {archive} has no member {member!r}')
        with z.open(info) as src, open(out, 'wb') as dst:
            shutil.copyfileobj(src, dst)
    return info.file_size


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--zip', required=True, help='zip archive to read')
    ap.add_argument('--member', required=True, help='member name inside the archive')
    ap.add_argument('--out', required=True, help='output file to write')
    args = ap.parse_args(argv)
    size = extract(args.zip, args.member, args.out)
    print(f'dk_unzip: {args.member} -> {args.out} ({size} bytes)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
