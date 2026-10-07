#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Prop *concepts* for japanDM: one object, one transparent image.

`neural_monster_trellis.py` refuses an input whose alpha is uniformly opaque
(`AlphaInput` deliberately replaces upstream background removal), so a concept
has to arrive with a real matte rather than a rendered rectangle.  Qwen-Image is
good at "one object on a seamless white sweep", so this renders that and then
*keys* the sweep away: the matte is measured from the image, not assumed.

The tiling machinery in `qwen_studio.finish_plate` is deliberately not reused:
a prop is one object, not a surface that has to wrap.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import qwen_studio


#: One entry per prop.  `size` is the authored footprint in engine units
#: (1 unit = 2 cm), which is what the decomposition step scales the mesh to: a
#: 54-unit bin has to come back as a bin and not as a wall.
PROPS = {
    'lantern': dict(
        size=40, prompt='a single red Japanese paper chochin lantern with black '
                        'lacquered top and bottom rings and a small dark tassel, '
                        'glowing warm from inside, faint vertical ribs, weathered '
                        'paper, photographed straight on as a product shot'),
    'vending': dict(
        size=96, prompt='a single tall Japanese drinks vending machine as a product '
                        'shot, brushed steel body, dark glass front revealing rows '
                        'of small drink cans, a bright cyan light panel above, '
                        'worn and slightly dented, three-quarter view'),
    'ac_condenser': dict(
        size=64, prompt='a single outdoor air-conditioning condenser unit as a '
                        'product shot, dirty off-white metal box, round fan grille '
                        'on one face, horizontal fins on the side, rust stains and '
                        'a short pipe stub, three-quarter view'),
    'pushcart': dict(
        size=110, prompt='a single Japanese market pushcart as a product shot, dark '
                         'wood and steel frame, two large spoked wheels, a folded '
                         'striped canopy above, crates stacked on the shelf, '
                         'weathered, three-quarter view'),
    'trashbin': dict(
        size=54, prompt='a single large wheeled plastic rubbish bin with a closed '
                        'lid as a product shot, faded dark green, ribbed front, two '
                        'small wheels, grimy, three-quarter view'),
    'planter': dict(
        size=48, prompt='a single cylindrical concrete street planter with dark '
                        'green shrubbery and one small pink blossom growing out of '
                        'it as a product shot, stained weathered concrete, front view'),
    'utility_box': dict(
        size=44, prompt='a single roadside steel electrical utility cabinet as a '
                        'product shot, pale grey painted metal, latched door, '
                        'ventilation slots, a small stencilled warning panel, rust '
                        'at the base, three-quarter view'),
    'barrier': dict(
        size=72, prompt='a single plastic traffic barrier section with two feet and '
                        'a hollow beam as a product shot, faded orange and white '
                        'reflective bands, scuffed, front three-quarter view'),
}

# A prop concept is the opposite of a surface plate: it *must* be lit, because
# TRELLIS reads shading as shape, and it *may* carry lettering, because signage
# is what makes a vending machine read as a vending machine.
OBJECT_AVOID = ('Flat lighting, no ground shadow, no cast shadow, no reflection on '
                'the floor, no floor visible, no table edge, no second object, no '
                'person, no hand, no cropped edges, no watermark, no collage, no '
                'multiple views, no text overlay outside the object.')

#: Appended to every prompt.  The first batch learned this the hard way: an AC
#: condenser came back on a violet dusk backdrop (corner median RGB 150, 71, 186),
#: which is a fine photograph and an unusable matte -- keying a coloured room
#: makes the whole frame foreground.  The sweep is not a stylistic preference, it
#: is the substrate the alpha is measured against.
SWEEP = ('Isolated on a seamless pure white studio sweep, product catalogue '
         'photograph, the whole object inside the frame with clear empty margin, '
         'single object, nothing else in frame.')


def sweep_is_pale(image):
    """-> (whether the frame border is a usable sweep, the sampled colour).

    A sweep must be bright and near-neutral: `key_background` thresholds the
    distance from this colour, and against a saturated backdrop every pixel of
    both the object and the room reads as "far" from it.
    """
    rgb = np.asarray(image.convert('RGB'), dtype=np.int16)
    edge = np.concatenate([rgb[0:3].reshape(-1, 3), rgb[-3:].reshape(-1, 3),
                           rgb[:, 0:3].reshape(-1, 3), rgb[:, -3:].reshape(-1, 3)])
    base = np.median(edge, axis=0)
    return bool(base.min() >= 168 and base.max() - base.min() <= 42), base


def key_background(image, tolerance=34, feather=2):
    """-> (RGBA copy with a measured matte, boolean mask).

    Sampling the four corners instead of assuming white matters: Qwen drifts to a
    pale grey sweep, and a fixed 255-threshold leaves a halo on every side that
    TRELLIS would model as a shell around the object.  The largest connected
    component wins, so a cast shadow or a stray blob cannot join the matte.
    """
    from scipy import ndimage
    rgb = np.asarray(image.convert('RGB'), dtype=np.int16)
    edge = np.concatenate([rgb[0:3].reshape(-1, 3), rgb[-3:].reshape(-1, 3),
                           rgb[:, 0:3].reshape(-1, 3), rgb[:, -3:].reshape(-1, 3)])
    base = np.median(edge, axis=0)
    mask = np.abs(rgb - base).sum(axis=2) > tolerance
    if not mask.any():
        raise ValueError('the whole image matches its own background; nothing to key')
    labels, count = ndimage.label(mask)
    if count > 1:
        sizes = np.bincount(labels.ravel())
        sizes[0] = 0
        mask = labels == int(sizes.argmax())
    mask = ndimage.binary_fill_holes(ndimage.binary_closing(mask, np.ones((5, 5))))
    if feather:
        soft = ndimage.gaussian_filter(mask.astype(np.float32), feather)
        alpha = np.clip((soft - 0.28) / 0.44, 0.0, 1.0)
    else:
        alpha = mask.astype(np.float32)
    # Anything well inside the object stays fully opaque, or a matte that bled
    # inward reads to TRELLIS as an inflated silhouette.
    alpha[ndimage.binary_erosion(mask, np.ones((7, 7)))] = 1.0
    out = np.dstack([np.asarray(image.convert('RGB')), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(out, mode='RGBA'), mask


def crop_matted(image, mask, margin=0.05):
    """-> the object trimmed, recentred on a square field, at 1024 px."""
    rows, cols = np.nonzero(mask)
    box = (int(cols.min()), int(rows.min()), int(cols.max()) + 1, int(rows.max()) + 1)
    width, height = box[2] - box[0], box[3] - box[1]
    side = max(width, height) * (1.0 + 2 * margin)
    centre = ((box[0] + box[2]) / 2.0, (box[1] + box[3]) / 2.0)
    scale = min(image.width, image.height) / side
    scaled = image.crop(box).resize((max(1, int(round(width * scale))),
                                     max(1, int(round(height * scale)))), Image.LANCZOS)
    canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    canvas.alpha_composite(scaled, (int(round(512 - scaled.width / 2)),
                                    int(round(512 - scaled.height / 2))))
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--props', default=','.join(sorted(PROPS)), help='comma list')
    parser.add_argument('--out', type=Path, default=Path('maps/japanDM/props'))
    parser.add_argument('--server', default=qwen_studio.DEFAULT_SERVER)
    parser.add_argument('--seed', type=int, default=6107)
    parser.add_argument('--force', action='store_true', help='re-render an existing concept')
    arguments = parser.parse_args()
    rows = []
    for offset, name in enumerate(sorted(n for n in arguments.props.split(',') if n)):
        spec = PROPS[name]
        actor = arguments.out / name
        actor.mkdir(parents=True, exist_ok=True)
        concept = actor / 'concept.png'
        (actor / 'prompt.txt').write_text('%s\n%s\n' % (spec['prompt'], OBJECT_AVOID))
        (actor / 'spec.json').write_text(json.dumps(dict(spec, name=name), indent=2) + '\n')
        if concept.is_file() and not arguments.force:
            rows.append(dict(name=name, concept=str(concept), reused=True))
            print('concept: %-15s kept existing %s' % (name, concept), flush=True)
            continue
        started = time.time()
        for attempt in range(3):
            seed = arguments.seed + offset * 13 + attempt * 7919
            raw = actor / ('raw-%05d.png' % seed)
            source = qwen_studio.render(arguments.server, 'prop-%s' % name,
                                        dict(spec, prompt='%s %s' % (spec['prompt'], SWEEP),
                                             size=(1024, 1024), steps=30, cfg=1.0,
                                             avoid=OBJECT_AVOID), raw, seed)
            if not source.is_file():
                raise RuntimeError('%s: the server returned no image (%s)' % (name, source))
            pale, base = sweep_is_pale(Image.open(source))
            if pale:
                break
            print('concept: %-15s seed %d backdrop is not a sweep (median RGB %s), retrying'
                  % (name, seed, np.round(base).tolist()), flush=True)
        else:
            raise RuntimeError('%s: three seeds in a row arrived on a coloured backdrop' % name)
        matted, mask = key_background(Image.open(source))
        crop_matted(matted, mask).save(concept)
        coverage = float(mask.mean())
        extrema = Image.open(concept).getextrema()[3]
        rows.append(dict(name=name, concept=str(concept), raw=source.name,
                         coverage=round(coverage, 4), alpha_range=list(extrema),
                         seconds=round(time.time() - started, 1),
                         raw_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                         concept_sha256=hashlib.sha256(concept.read_bytes()).hexdigest()))
        print('concept: %-15s %-16s coverage %.3f alpha %s %.0f s'
              % (name, source.name, coverage, extrema, time.time() - started), flush=True)
        if not 0.02 < coverage < 0.85:
            raise RuntimeError('%s: keyed matte covers %.3f of the frame; the concept '
                               'is not a single isolated object' % (name, coverage))
    (arguments.out / 'concepts.json').write_text(json.dumps(rows, indent=2) + '\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
