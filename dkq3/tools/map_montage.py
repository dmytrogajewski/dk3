# SPDX-License-Identifier: GPL-2.0-or-later
"""Tile a photo report into one sheet the reviewer can actually look at.

`map_view_probe` writes one JPEG per vantage point, and a directory of twenty
frames is not a thing anybody can judge in one glance -- the question the owner
asks is "what does the map look like", and that is a question about all of them at
once.  This flattens a report directory into a labelled contact sheet, and prints
each frame's mean and dark-pixel share next to its name, because "too dark" and
"nothing there" are the two failures a thumbnail hides.

Uses the interpreter that has Pillow; the build tools run on plain `python3`.
"""
import argparse
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def luminance(image):
    """-> (mean brightness, share of near-black pixels) from the grey histogram."""
    grey = image.convert('L').resize((image.width // 2 or 1, image.height // 2 or 1))
    hist = grey.histogram()
    total = sum(hist)
    mean = sum(value * count for value, count in enumerate(hist)) / float(total) / 255.0
    dark = sum(hist[:24]) / float(total)
    return mean, dark


def font(size=15):
    try:
        return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', size)
    except OSError:
        return ImageFont.load_default()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('report', type=Path, help='a map_view_probe report directory')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--cols', type=int, default=4)
    parser.add_argument('--tile', default='480x270')
    parser.add_argument('--pattern', default='*.jpg')
    parser.add_argument('--only', action='append', default=[])
    parser.add_argument('--label', default='bottom', choices=('bottom', 'none'))
    args = parser.parse_args()

    width, height = (int(part) for part in args.tile.lower().split('x'))
    frames = sorted(p for p in args.report.glob(args.pattern)
                    if not args.only or any(o in p.name for o in args.only))
    if not frames:
        raise SystemExit('no frames under %s' % args.report)
    pad, bar = 6, (18 if args.label != 'none' else 0)
    sheet = Image.new('RGB', (args.cols * (width + pad) + pad,
                              ((len(frames) + args.cols - 1) // args.cols)
                              * (height + bar + pad) + pad), (24, 24, 26))
    pen = ImageDraw.Draw(sheet)
    typeface = font()
    print('%-28s %6s %6s' % ('frame', 'mean', 'dark'))
    for index, path in enumerate(frames):
        with Image.open(path) as source:
            mean, dark = luminance(source)
            tile = source.convert('RGB').resize((width, height), Image.LANCZOS)
        left = pad + (index % args.cols) * (width + pad)
        top = pad + (index // args.cols) * (height + bar + pad)
        sheet.paste(tile, (left, top))
        if args.label != 'none':
            flag = ' DARK' if mean < 0.16 else (' FLAT' if dark > 0.55 else '')
            pen.rectangle((left, top + height, left + width, top + height + bar),
                          fill=(12, 12, 14))
            pen.text((left + 4, top + height + 2), '%s  %.3f  %.0f%%%s'
                     % (path.stem, mean, 100 * dark, flag), fill=(230, 230, 230),
                     font=typeface)
        print('%-28s %6.4f %5.0f%%' % (path.stem, mean, 100 * dark))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.out, quality=88)
    print('wrote %s (%d frames, %dx%d)' % (args.out, len(frames), sheet.width, sheet.height))


if __name__ == '__main__':
    sys.exit(main())
