#!/usr/bin/env python3
"""hd_brightness: match the HD texture overlay's brightness to the original textures.

The upscaled overlay drifts darker than the textures it replaces (median ~0.92x, some 0.3-0.6x),
which turned dimly lit surfaces black in the remaster. For every overlay image that has an
original, each colour channel is scaled so the overlay's mean matches the original's (gain
clamped to 0.7-2.5, applied only when it differs by more than 5%). Detail and hue variation
of the overlay are kept; only its overall level follows the original.

The untouched overlay is kept as `<name>.orig.pk3` and is always the input, so the tool can be
re-run. Usage:
  python3 dkq3/tools/hd_brightness.py --textures <dk3-textures.pk3> --hd zig-out/hd-textures/dkq3-textures_hd.pk3
"""
import argparse
import io
import shutil
import sys
import zipfile
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image


def channel_means(data):
    image = Image.open(io.BytesIO(data))
    rgb = np.asarray(image.convert('RGB'), dtype=np.float64)
    return image, rgb.reshape(-1, 3).mean(axis=0)


def correct(job):
    name, original, overlay = job
    try:
        _, target = channel_means(original)
        image, current = channel_means(overlay)
    except Exception:
        return name, overlay, None
    gain = np.clip(np.where(current > 1.0, target / np.maximum(current, 1e-6), 1.0), 0.7, 2.5)
    if np.all(np.abs(gain - 1.0) <= 0.05):
        return name, overlay, None
    has_alpha = image.mode in ('RGBA', 'LA') or (image.mode == 'P' and 'transparency' in image.info)
    pixels = np.asarray(image.convert('RGBA' if has_alpha else 'RGB'), dtype=np.float64)
    pixels[..., :3] = np.clip(pixels[..., :3] * gain, 0, 255)
    out = io.BytesIO()
    Image.fromarray(pixels.round().astype(np.uint8), 'RGBA' if has_alpha else 'RGB').save(out, 'PNG', compress_level=6)
    return name, out.getvalue(), gain.round(3).tolist()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--textures', type=Path, required=True, help='original converted textures pk3')
    parser.add_argument('--hd', type=Path, required=True, help='HD overlay pk3 (rewritten in place)')
    parser.add_argument('--jobs', type=int, default=8)
    args = parser.parse_args(argv)
    source = args.hd.with_suffix('.orig.pk3')
    if not source.exists():
        shutil.copy2(args.hd, source)
    with zipfile.ZipFile(args.textures) as originals_zip:
        originals = {name: originals_zip.read(name) for name in originals_zip.namelist() if name.lower().endswith('.png')}
    temporary = args.hd.with_suffix('.tmp.pk3')
    changed = 0
    total = 0
    with zipfile.ZipFile(source) as hd_zip, zipfile.ZipFile(temporary, 'w', zipfile.ZIP_STORED) as out:
        names = hd_zip.namelist()

        def jobs():
            for name in names:
                yield name, originals.get(name), hd_zip.read(name)

        with ProcessPoolExecutor(max_workers=args.jobs) as pool:
            pending = []
            for name, original, overlay in jobs():
                total += 1
                if original is None or not name.lower().endswith('.png'):
                    out.writestr(hd_zip.getinfo(name), overlay)
                    continue
                pending.append(pool.submit(correct, (name, original, overlay)))
                if len(pending) >= args.jobs * 4:
                    for future in pending:
                        result_name, data, gain = future.result()
                        out.writestr(zipfile.ZipInfo(result_name, date_time=(1980, 1, 1, 0, 0, 0)), data)
                        changed += gain is not None
                    pending = []
            for future in pending:
                result_name, data, gain = future.result()
                out.writestr(zipfile.ZipInfo(result_name, date_time=(1980, 1, 1, 0, 0, 0)), data)
                changed += gain is not None
    temporary.replace(args.hd)
    print(f'hd_brightness: {changed} of {total} overlay images matched to the originals -> {args.hd} (untouched: {source})')
    return 0


if __name__ == '__main__':
    sys.exit(main())
