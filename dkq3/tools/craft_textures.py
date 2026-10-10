# SPDX-License-Identifier: GPL-2.0-or-later
"""Structured albedos, emissive signage and the dusk sky of japanDM.

Why this module sits next to `neural_textures.py`
-------------------------------------------------
`neural_textures.py` asks SDXL to paint every material from a prompt, steered by
a tile ControlNet built from a procedural height field.  Measured on the images
that went into the build the owner screenshotted, that pipeline is what made the
arena look wrong rather than merely old:

  * the model does not obey a colour instruction given as words.  The "very dark
    wet rain asphalt, low contrast charcoal" recipe came back with a mean albedo
    of 0.497; "dark tinted safety glass, near transparent" came back as an opaque
    light-blue woven fabric; "diamond anti-slip ribs" came back as a blue tartan;
    `crate` came back leaf-green.  Eighteen structural surfaces therefore sat
    within a factor of two of middle grey, which is the single biggest reason the
    arena reads as one milky room;
  * where the recipe asked for structure -- a window grid, a perforated grate, an
    LED strip, kanji strokes -- the model produced isotropic mush, and on a
    surface lit only by `q3map_skyLight` mush is all there is to see;
  * the emissive sets were also cropped wrongly: `neon_a` is authored at 256
    world units per tile while its faces are 56-72 units across, so every sign
    displayed a 22 % window of the image.  That is the pink confetti.

So the labour is divided by what each tool is actually for: structure is drawn,
grain is borrowed.  This module paints the real geometry of every material --
plate layout, perforation pitch, window grid with its lit-window set, glyph
strokes, ballast stones -- at the texel size the shader samples, grades it
against a measured colour target, and hands it to the same tangent-space normal,
specular and glow derivation `neural_textures.py` already used.  Diffusion keeps
the one job it wins, organic weathering, imported through
`dkq3/tools/qwen_studio.py` as relative detail (detail divided by its own mean)
so the model's microstructure reaches the albedo and its palette never does, with
the grade running afterwards regardless.

Two invariants the whole module is built around:

* every field is band-limited to whole-image frequencies (`periodic_noise`) or is
  stamped through the wrap seam (`Mask`), so a tile needs no seam repair pass and
  `--check-seams` can prove it numerically instead of by eye;
* colour is a declared target, not an outcome: `grade()` moves an albedo onto the
  luminance the light rig was tuned for, and no generator, procedural or learned,
  is allowed to overrule that number.
"""

from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random
import sys
import time

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dkimg                                          # noqa: E402
import neural_textures as nt                          # noqa: E402

LUMA = np.array([0.2126, 0.7152, 0.0722], np.float32)


#: The whole material set costs ~240 MB resident.  A build that wants gigabytes is
#: by definition a bug, and the bug is not harmless: the first full build of this
#: map reached 46.7 GB resident, the kernel OOM killer picked it, and because the
#: process was running in the desktop compositor's own cgroup the kill took the
#: session down with it.  Asking the kernel politely, at a number far above any
#: legitimate build, converts that class of mistake into a MemoryError with a
#: traceback pointing at the line that caused it.
DEFAULT_MEMORY_MIB = 6144


def apply_memory_cap(memory_mib):
    """-> the (soft, hard) address-space ceiling now in force, for the log line.

    Address space, not resident bytes: this module is numpy and PIL only, so the
    two track each other, and RLIMIT_AS fails immediately at the offending
    allocation instead of after the page cache has been squeezed.
    """
    import resource
    limit = int(memory_mib) * 1024 * 1024
    previous = resource.getrlimit(resource.RLIMIT_AS)
    ceiling = limit if previous[1] in (resource.RLIM_INFINITY, -1) else min(limit, previous[1])
    resource.setrlimit(resource.RLIMIT_AS, (ceiling, ceiling))
    return ceiling, previous

# --------------------------------------------------------------------------- #
# fields, colour, and the wrap-aware stamp
# --------------------------------------------------------------------------- #
def rng_for(name, salt=0):
    """-> a seeded RNG, so a named material paints the same way on every machine."""
    digest = hashlib.sha256(('%s:%d' % (name, salt)).encode()).hexdigest()
    return random.Random(int(digest[:8], 16))

def fbm(size, octaves=6, base=6, seed=0, aniso=1.0, decay=2.3):
    """-> periodic fractal noise in 0..1, whole-image frequencies only, so it wraps."""
    return nt.periodic_noise(size, size, octaves, base, seed, decay, aniso)

def cell_random(rows, columns, seed=0):
    """-> (rows, columns) independent values in 0..1 for per-tile decisions."""
    return np.random.default_rng(seed).random((rows, columns)).astype(np.float32)

def axes(size):
    """-> (x, y) coordinate maps, x right and y down the stored image."""
    y, x = np.mgrid[0:size, 0:size]
    return x.astype(np.float32), y.astype(np.float32)

def band_field(size, centre, half, along='y'):
    """-> a soft band centred on `centre`, measured with the distance that wraps.

    `1 - abs(y - centre) / half` is the obvious way to write a band and it is wrong
    at the border: a band centred on the seam -- which is exactly where a crate's
    steel band lands once the band count divides the tile -- then exists only on the
    near side of the wrap.  The tile carries a full-width bright stripe along one
    border and nothing along the other, which is the 41-unit-of-255 row jump the
    first crate tile measured against a 6-unit interior step.  Periodic distance
    puts the other half where the repeating texture needs it.
    """
    coordinate = np.arange(size, dtype=np.float32) + 0.5
    delta = np.abs(coordinate - float(centre))
    delta = np.minimum(delta, size - delta)
    profile = np.clip(1.0 - delta / float(half), 0.0, 1.0) ** 0.6
    if along == 'y':
        return np.repeat(profile[:, None], size, axis=1)
    return np.repeat(profile[None, :], size, axis=0)


def periodic_sweep(size, x, y, cycles_y=2):
    """-> a 0..1 reflection sweep with no seam, in place of a linear gradient.

    Two painters lit their surface with `(x/size)*a + (y/size)*b`, which walks from
    0 to 1 across the tile and then jumps back to 0 at the wrap -- glass scored 4.42
    vertical / 2.98 horizontal and the tower facade 5.28 / 3.42 with that one
    expression each, and the specular stage inherits it, so the error shipped twice.
    Cosines of whole cycles keep the same mean and the same reading -- a broad
    reflection sweeping across the pane -- and close on themselves at the border.
    """
    u, v = x / float(size), y / float(size)
    across = 0.5 - 0.5 * np.cos(u * 2.0 * math.pi)
    down = 0.5 - 0.5 * np.cos(v * 2.0 * math.pi * int(cycles_y))
    return 0.45 * across + 0.55 * down


def ramp(values, stops):
    """-> the piecewise-linear colour of ((position, (r, g, b)), ...) at `values`.

    A dusk sky is specified by naming its colour at four elevations; the
    interpolation is the code's job.  A magic exponent in a gradient is the same
    bug as a magic number in a light, rediscovered on every regrade.

    This function was rewritten twice, and the reason for the second rewrite is the
    reason it stays flat and stays checked:

    * The version it replaces interpolated a (rows, columns, 1) weight against a
      three-element colour on one line -- the obvious numpy.  On this machine that
      line modified its own input: instrumented, `value` read back as 0.0623 on the
      first segment and as 0.0623 - 0.44, then - 0.488, then - 0.5 on each segment
      after, as though `value - low` had been written back into `value`.  Every
      segment above the first therefore saw a position that had already been
      shifted down by all the previous stops, which is why the top 40 % of the sky
      came back as the zenith colour and the panorama below it came back negative --
      `np.clip(colour, 0, 1)` then turned it into the black sheet that this map has
      been lit by for three builds, while the identical arithmetic typed into a
      scratch script returned the right answer every time.
    * So: no 3-D broadcasting at all.  One flat array of positions, one flat weight
      per segment, one explicit column axis, one reshape at the end.
    * And the answer is checked against a scalar interpolation of the same stops.
      If the vector path ever disagrees with plain Python again, the texture build
      stops here rather than shipping a sky that is quietly black -- and a black sky
      is not a quiet failure here, because q3map_skyLight integrates these faces
      into the arena's only fill light.
    """
    positions = [float(stop[0]) for stop in stops]
    colours = np.array([stop[1] for stop in stops], np.float32)
    if len(positions) < 2 or colours.ndim != 2:
        raise ValueError('ramp needs at least two (position, rgb) stops, got %r' % (stops,))
    if positions != sorted(positions):
        raise ValueError('ramp stops must ascend, got %r' % (positions,))
    shape = np.asarray(values).shape
    query = np.ravel(np.array(values, np.float64, copy=True))
    np.clip(query, positions[0], positions[-1], out=query)
    channels = int(colours.shape[1])
    out = np.empty((query.size, channels), np.float64)
    out[:] = colours[0]
    for index in range(len(positions) - 1):
        low, high = positions[index], positions[index + 1]
        weight = query - low
        weight /= max(high - low, 1e-9)
        np.clip(weight, 0.0, 1.0, out=weight)
        low_close = colours[index] * (1.0 - weight[:, None])
        high_close = colours[index + 1] * weight[:, None]
        inside = (query >= low) & ((query <= high) if index == len(positions) - 2
                                   else (query < high))
        out = np.where(inside[:, None], low_close + high_close, out)

    def scalar(at):
        for index in range(len(positions) - 1):
            low, high = positions[index], positions[index + 1]
            if at <= high or index == len(positions) - 2:
                weight = min(max((at - low) / max(high - low, 1e-9), 0.0), 1.0)
                return colours[index] * (1.0 - weight) + colours[index + 1] * weight
        return colours[-1]

    probe = np.unique(np.concatenate((np.linspace(positions[0], positions[-1], 17),
                                      np.array(positions, np.float64))))
    for at in (float(position) for position in probe):
        row = int(np.argmin(np.abs(query - at)))
        want, got = scalar(float(query[row])), out[row]
        if np.max(np.abs(want - got)) > 1e-4:
            raise AssertionError('ramp disagrees with itself at p=%r: vector gave %s, '
                                 'scalar interpolation gave %s' % (at, got, want))
    return out.reshape(shape + (channels,)).astype(np.float32)
def grade(albedo, mean, std=None):
    """-> `albedo` re-centred on a target luminance, optionally spread to `std`.

    Hue is carried through and the spread is rescaled around the target, so
    darkening a surface keeps its detail instead of crushing it into black.
    """
    luminance = albedo @ LUMA
    pivot = float(luminance.mean()) or 1e-3
    out = albedo - luminance[..., None] + np.clip(luminance[..., None] * (float(mean) / pivot), 0.0, None)
    out = np.clip(out, 0.0, None)
    if std:
        current = out @ LUMA
        centre, spread = float(current.mean()), float(current.std()) or 1e-3
        out = centre + (out - centre) * (float(std) / spread)
    return np.clip(out, 0.0, 1.0).astype(np.float32)

def multiply(albedo, factor):
    """-> `albedo` scaled by a scalar, a (HxW) field, or a per-channel factor.

    The shape check is not decoration.  NumPy right-aligns axes, so an expression
    that mixes a flat field with a channel-added one -- `1.0 + 0.2 * grain[...,
    None] + 0.06 * dust`, where `grain` and `dust` are both (HxW) -- evaluates
    (1,H,W) against (H,W,1) and silently produces an (HxWxW) temporary.  At a
    1024-texel tile that is 4 GB per intermediate, and the arena build reached
    46.7 GB of resident memory and was killed by the kernel OOM killer -- inside
    the desktop's own cgroup, which took the compositor down with it.  A factor of
    the wrong shape now says so at the line that caused it, at the cost of nothing.
    """
    factor = np.asarray(factor, np.float32)
    if factor.ndim == 0 or (factor.ndim == 2 and factor.shape != albedo.shape[:2]) \
            or (factor.ndim >= 3 and factor.shape[:2] != albedo.shape[:2]):
        raise ValueError('multiply: factor of shape %s cannot scale an albedo of %s'
                         % (factor.shape, albedo.shape))
    scaled = albedo * (factor[..., None] if factor.ndim == 2 else factor)
    if scaled.shape != albedo.shape:
        raise ValueError('multiply: factor of shape %s broadcast an albedo of %s up to %s'
                         % (factor.shape, albedo.shape, scaled.shape))
    return np.clip(scaled, 0.0, 1.0)

def put(albedo, weight, colour):
    """-> `albedo` blended towards a flat `colour` by a coverage mask.

    `weight` is a (HxW) coverage field; a trailing singleton is tolerated because
    painters reach for one when a mask came off `field()`.  Any other rank is
    rejected for the same reason `multiply` rejects it: an (HxWx1) weight here
    becomes (HxWx1x1), and the product against an (HxWx3) albedo is
    (HxWxWx3) -- 13 GB for one 1024-texel call, and the reason the first full
    build of this map was OOM-killed with the desktop session.
    """
    weight = np.asarray(weight, np.float32)
    if weight.ndim == 3 and weight.shape[2] == 1:
        weight = weight[..., 0]
    if weight.ndim != 2 or weight.shape != albedo.shape[:2]:
        raise ValueError('put: weight of shape %s does not cover an albedo of %s'
                         % (weight.shape, albedo.shape))
    weight = np.clip(weight, 0.0, 1.0)[..., None]
    blended = albedo * (1.0 - weight) + np.array(colour, np.float32)[None, None, :] * weight
    if blended.shape != albedo.shape:
        raise ValueError('put: weight of shape %s broadcast an albedo of %s up to %s'
                         % (weight.shape, albedo.shape, blended.shape))
    return blended

def shade(albedo, height, gain=1.0, ambient=0.62):
    """-> `albedo` multiplied by a wrap-aware Lambert term off a softened `height`.

    Shading derived from a height field must use periodic derivatives, or the tile
    edge is lit differently from its wrap partner and the seam shows up as a
    bright line down every wall in the arena.
    """
    dhdx, dhdy = nt.slopes(gaussian_filter(height, 1.5, mode='wrap'))
    lambert = np.clip(1.0 + (dhdx * -0.45 + dhdy * -0.55) * gain * 8.0, 0.0, 2.0)
    return multiply(albedo, ambient + (1.0 - ambient) * lambert)

class Mask:
    """A PIL mask front-end that paints every stamp through the wrap seam.

    A stamp touching an edge has to be repeated on the far side or the tile shows
    a cut line.  `offsets` works that out from the stamp's own extent, so a stamp
    in the middle of the tile is drawn once and a stamp on the border is drawn as
    many times as the seam needs.
    """

    def __init__(self, size, fill=0):
        self.size = size
        self.image = Image.new('L', (size, size), int(fill))
        self.pen = ImageDraw.Draw(self.image)

    def offsets(self, box, pad=0.0):
        """-> the (dx, dy) shifts that repeat a stamp across both seams.

        A stamp clipped by a tile border has to reappear on the far side, and it
        can be clipped by the vertical seam, the horizontal seam, or a corner.
        This used to return a flat list of x shifts that callers added to the x
        coordinates only, while the *decision* tested `min(box[0], box[1])` and
        `max(box[2], box[3])` -- mixing the two axes in the test and ignoring the
        y result in the answer.  So a stamp clipped by the top or bottom edge was
        never repeated, and when it was the y extent that tripped the test, the
        stamp was duplicated sideways instead of up or down.  That is the whole
        reason the drawn materials failed their vertical seam metric several times
        harder than their horizontal one (`crate` 3.56 vs 0.37, `grate` 4.50 vs
        0.21): every hole, plank end and stone touching a horizontal border was
        cut in half, and the shipped tiles carried a grid of hard lines.
        """
        reach = pad + max(box[2] - box[0], box[3] - box[1])
        across, down = [0], [0]
        if min(box[0], box[2]) < reach:
            across.append(self.size)
        if max(box[0], box[2]) > self.size - reach:
            across.append(-self.size)
        if min(box[1], box[3]) < reach:
            down.append(self.size)
        if max(box[1], box[3]) > self.size - reach:
            down.append(-self.size)
        return [(dx, dy) for dx in across for dy in down]

    def box(self, kind, box, value=255, width=0, pad=0.0):
        for dx, dy in self.offsets(box, pad):
            moved = (box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy)
            if kind == 'ellipse':
                self.pen.ellipse(moved, fill=value)
            else:
                self.pen.rectangle(moved, fill=value)
        return self

    def polygon(self, points, value=255, pad=0.0):
        """Filled stamp that is not axis-aligned, drawn through the seam as well.

        Deck plating needs this: `box` only knows axis-aligned rectangles, so a
        skewed plate crossing a tile edge would leave a hard cut line.
        """
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        box = (min(xs), min(ys), max(xs), max(ys))
        for dx, dy in self.offsets(box, pad):
            self.pen.polygon([(x + dx, y + dy) for x, y in points], fill=value)
        return self

    def stroke(self, points, value=255, width=1, wrap=True):
        """Polyline stamp; a line that leaves the tile is drawn again on the far side."""
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        steps = self.offsets((min(xs), min(ys), max(xs), max(ys)), width) if wrap else [(0, 0)]
        for dx, dy in steps:
            self.pen.line([(x + dx, y + dy) for x, y in points], fill=value, width=width,
                          joint='curve')
        return self

    def field(self):
        """-> the mask as (HxWx1) float32 in 0..1, ready to blend against an albedo."""
        return np.asarray(self.image, np.float32)[..., None] / 255.0

    def plane(self):
        """-> the mask as (HxW) float32 in 0..1."""
        return np.asarray(self.image, np.float32) / 255.0

def pebbles(size, count, radii, seed=0, angular=1.0):
    """-> (coverage, tone, facet) of `count` wrapped stones.

    Ballast and gravel come from here.  The first version drew every stone as a
    disc and then Gaussian'd the coverage into a `crown`, which is what made
    `roof_gravel` read as rounded blue-grey foam rather than as crushed rock:
    real ballast is angular, with flat facets and sharp shoulders, and a
    Gaussian crown is the one thing that guarantees the opposite look however
    good the tone pass is.

    So each stone is now an irregular convex polygon with jittered vertices, and
    each carries its own grey level (`tone`) and its own facet tilt (`facet`)
    instead of a smoothed crown.  Height is built from those two by the caller,
    so a stone has flat faces and a hard edge.

    `angular` is the fraction of stones drawn as polygons; the remainder stay
    discs, because a heap of crushed rock always contains some worn pieces.
    """
    rng = random.Random(seed)
    cover, tone, facet = Mask(size), Mask(size), Mask(size)
    for _ in range(count):
        radius = rng.uniform(*radii)
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        grey = int(46 + 190 * rng.random())
        tilt = int(255 * rng.random())
        if rng.random() < angular:
            sides = rng.randint(5, 7)
            spin = rng.uniform(0.0, math.tau)
            points = []
            for index in range(sides):
                angle = spin + math.tau * index / sides + rng.uniform(-0.16, 0.16) * math.tau / sides
                reach = radius * rng.uniform(0.70, 1.08)
                points.append((cx + reach * math.cos(angle), cy + reach * math.sin(angle) * 1.12))
            cover.polygon(points, 255, pad=radius)
            tone.polygon(points, grey, pad=radius)
            facet.polygon(points, tilt, pad=radius)
        else:
            box = (cx - radius, cy - radius * 1.12, cx + radius, cy + radius * 1.12)
            cover.box('ellipse', box, 255, pad=radius)
            tone.box('ellipse', box, grey, pad=radius)
            facet.box('ellipse', box, tilt, pad=radius)
    coverage = cover.plane()
    return coverage, tone.plane() * coverage, facet.plane() * coverage

# --------------------------------------------------------------------------- #
# structural painters
#
# Every painter returns `(albedo, height, extras)` at the stored texel size.
# `height` is what the tangent-space normal is derived from, so anything a
# painter wants to feel raised has to be raised there as well as lit here.
# `extras` carries what albedo luminance alone cannot decide: a per-texel
# specular weight (`spec`) for wet-versus-matte, and an explicit `glow` image for
# the surfaces whose light is a designed set of windows rather than "whatever is
# bright".
# --------------------------------------------------------------------------- #
def paint_asphalt(size, spec, seed):
    grit = fbm(size, 7, 40, seed, 1.0, 2.9)
    patch = fbm(size, 3, 2, seed + 1, 1.0, 1.5)
    tar = fbm(size, 4, 5, seed + 2, 1.0, 1.8)
    albedo = np.repeat((0.26 + 0.30 * grit)[..., None], 3, axis=2)
    albedo = put(albedo, np.clip((patch - 0.58) * 2.6, 0.0, 1.0) * 0.55, (0.10, 0.105, 0.115))
    oil = np.clip((tar - 0.60) * 2.8, 0.0, 1.0) * np.clip((patch - 0.40) * 2.0, 0.0, 1.0)
    albedo = put(albedo, oil * 0.75, (0.052, 0.058, 0.082))
    height = 0.42 + 0.58 * grit - 0.30 * oil
    cracks = Mask(size)
    rng = rng_for('asphalt', seed)
    for _ in range(int(spec.get('cracks', 5))):
        x = rng.uniform(0, size)
        points = [(x + rng.uniform(-size * 0.04, size * 0.04), y)
                  for y in range(-size // 8, size + size // 8, size // 20)]
        cracks.stroke(points, 255, width=max(2, size // 340))
    seam = cracks.plane()
    albedo = put(albedo, seam * 0.8, (0.038, 0.038, 0.042))
    height = height - 0.35 * seam
    # `wet` scales the rain film: `asphalt` carries a damp sheen in its shaded
    # patches, and `asphalt_wet` is the same tarmac after rain with the low ground
    # under a mirror -- the difference is one number, not another painter.
    wet = np.clip((patch - 0.52) * 2.2, 0.0, 1.0) * float(spec.get('wet', 1.0))
    albedo = put(albedo, np.clip(wet - 1.0, 0.0, 1.0) * 0.35, (0.028, 0.032, 0.046))
    return albedo, np.clip(height, 0.0, 1.0), {'spec': wet}

def paint_plaza_stone(size, spec, seed):
    cells, mortar = int(spec.get('cells', 4)), float(spec.get('mortar', 0.05))
    tones = cell_random(cells, cells, seed)
    step = size / float(cells)
    x, y = axes(size)
    row = np.floor(y / step)
    stagger = np.where(row % 2 == 1, step * 0.5, 0.0)
    column = np.floor(((x - stagger) % size) / step).astype(int) % cells
    tone = tones[(np.floor(y / step).astype(int) % cells), column]
    grain = fbm(size, 6, 26, seed, 1.0, 2.7)
    mineral = fbm(size, 5, 110, seed + 3, 1.0, 3.3)
    slabs = np.repeat((0.40 + 0.30 * tone + 0.16 * (grain - 0.5))[..., None], 3, axis=2)
    # One weathered swath across the whole panel: `cell_random` varies a slab against
    # its neighbour, which is what a 30-unit tile looks like up close, and nothing at
    # all varies a 128-unit tile against the tile beside it -- which is what the plaza
    # is actually seen as, and why 800 000 square units of it read as one grey sheet.
    swath = fbm(size, 2, 2, seed + 21, 1.0, 1.8)
    slabs = multiply(slabs, 0.92 + 0.18 * mineral)
    slabs = multiply(slabs, 0.80 + 0.44 * swath)
    u, v = (x - stagger) % step, y % step
    joint = np.clip(1.0 - np.minimum(np.minimum(u, step - u), np.minimum(v, step - v))
                    / (step * mortar), 0.0, 1.0) ** 1.4
    albedo = put(slabs, joint * 0.85, (0.055, 0.055, 0.058))
    wet = np.clip((fbm(size, 3, 2, seed + 6, 1.0, 1.6) - 0.46) * 2.2, 0.0, 1.0)
    albedo = put(albedo, wet * 0.35, (0.030, 0.034, 0.048))
    height = np.clip(0.70 * (1.0 - joint ** 0.7) + 0.14 * tone + 0.10 * grain, 0.0, 1.0)
    return albedo, height, {'spec': wet * (1.0 - joint)}

def paint_concrete_panel(size, spec, seed):
    cells = int(spec.get('cells', 2))
    tones = cell_random(cells, cells, seed)
    step = size / float(cells)
    x, y = axes(size)
    tone = tones[(y // step).astype(int) % cells, (x // step).astype(int) % cells]
    grain = fbm(size, 7, 34, seed, 1.0, 2.8)
    streak = fbm(size, 5, 10, seed + 3, 24.0, 2.1)          # vertical rain wash
    albedo = np.repeat((0.42 + 0.20 * tone + 0.22 * (grain - 0.5))[..., None], 3, axis=2)
    albedo = multiply(albedo, 0.90 + 0.20 * streak[..., None])
    u, v = x % step, y % step
    joint = np.clip(1.0 - np.minimum(np.minimum(u, step - u), np.minimum(v, step - v))
                    / (step * float(spec.get('mortar', 0.035))), 0.0, 1.0) ** 1.2
    albedo = put(albedo, joint * 0.72, (0.070, 0.070, 0.072))
    height = np.clip(0.72 * (1.0 - joint ** 0.8) + 0.26 * grain, 0.0, 1.0)
    holes = Mask(size)
    drips = Mask(size)
    for j in range(cells):
        for i in range(cells):
            cx, cy = (i + 0.5) * step, (j + 0.5) * step
            radius = step * 0.032
            holes.box('ellipse', (cx - radius, cy - radius, cx + radius, cy + radius), 255, pad=radius * 2)
            drips.box('rect', (cx - radius * 0.4, cy, cx + radius * 0.4, cy + step * 0.42), 165,
                      pad=step * 0.45)
    rust = holes.plane() * 0.75 + drips.plane() * 0.55
    albedo = put(albedo, np.clip(rust, 0.0, 1.0), (0.085, 0.052, 0.038))
    height = np.clip(height - 0.55 * holes.plane(), 0.0, 1.0)
    grime = np.clip((fbm(size, 3, 3, seed + 8, 14.0, 1.6) - 0.56) * 2.6, 0.0, 1.0)
    albedo = put(albedo, grime * 0.45, (0.052, 0.052, 0.050))
    # Storeys.  `concrete_panel` is the largest lit surface in the map after the sky
    # (16.4 million square units over 1225 faces), and a two-panel tile with four tie
    # holes on it reads at 128 units as one blank grey sheet from floor to ceiling --
    # which is what every wall in the capture set was.  A cast wall has a horizontal
    # joint every storey, a drip line under it, and the panel below that joint is
    # dirtier than the panel above it, because that is where the water runs.
    storeys = max(1, int(spec.get('storeys', cells)))
    storey = size / float(storeys)
    v = y % storey
    sill = np.clip(1.0 - np.abs(v - storey * 0.06) / (storey * 0.030), 0.0, 1.0)
    albedo = put(albedo, sill * 0.80, (0.062, 0.062, 0.064))
    height = np.clip(height - 0.30 * sill, 0.0, 1.0)
    wash = np.clip((v - storey * 0.06) / (storey * 0.55), 0.0, 1.0) ** 1.4
    albedo = multiply(albedo, 1.0 - 0.20 * wash)
    streaks = np.clip((fbm(size, 4, 22, seed + 11, 30.0, 2.2) - 0.55) * 2.4, 0.0, 1.0)
    albedo = put(albedo, streaks * wash * 0.55, (0.048, 0.046, 0.043))
    return albedo, height, {'spec': -0.4 * grime - 0.5 * wash}

def paint_grate(size, spec, seed):
    """Perforated steel with a rolled rim and rust blooming along the holes."""
    cells = int(spec.get('cells', 8))
    step, radius = size / float(cells), size / float(cells) * float(spec.get('radius', 0.30))
    # The holes were meant to sit 0.87 as far apart vertically as horizontally, and
    # `cy = j * step * 0.87` writes that as a pitch which does not divide the tile:
    # after a whole row count the pattern is short of the border, so every hole
    # straddling the wrap is misplaced by the remainder and the rows visibly bunch
    # along one line.  Choosing the row count instead keeps the intended squash and
    # divides the tile exactly.
    rows = max(1, int(round(cells / 0.87)))
    step_y = size / float(rows)
    holes = Mask(size, fill=255)
    for j in range(rows + 1):
        for i in range(cells + 1):
            cx = i * step + (0.5 * step if j % 2 else 0.0)
            cy = j * step_y
            holes.box('ellipse', (cx - radius, cy - radius, cx + radius, cy + radius), 0, pad=radius * 2)
    hole = 1.0 - holes.plane()
    # A punched grid is a comb and a step-function edge is the richest source of
    # harmonics a texture can have; seen at a grazing angle with no anisotropic filter
    # -- which is what this engine has -- those harmonics are the fish-scale the owner
    # kept photographing on the north ramp, where this grating is 78.5 % of the frame
    # at 49-75 units.  Softening the edge by 15 % of the pitch (11 texels of a 512
    # tile) removes everything above a tenth of the bar frequency and leaves a hole
    # that still reads as a hole at a metre.
    hole = gaussian_filter(hole, step * 0.15, mode='wrap')
    rim = np.clip((gaussian_filter(hole, step * 0.18, mode='wrap') - 0.45) * 2.2, 0.0, 1.0) * (1.0 - hole)
    dirt = fbm(size, 6, 34, seed, 1.0, 2.8)
    grit = fbm(size, 5, 90, seed + 2, 1.0, 3.1)
    albedo = np.repeat((0.32 + 0.16 * dirt + 0.07 * (grit - 0.5))[..., None], 3, axis=2)
    albedo = put(albedo, hole * 0.34, (0.160, 0.170, 0.185))
    albedo = put(albedo, rim * 0.22, (0.40, 0.41, 0.44))
    rust = np.clip((fbm(size, 4, 6, seed + 5, 1.0, 1.7) - 0.58) * 3.2, 0.0, 1.0) * (0.30 + 0.70 * rim)
    albedo = put(albedo, rust * 0.7, (0.145, 0.062, 0.038))
    # The height follows the softened field, so the relief is a depression and not a
    # cliff edge, and the recipe's bump comes down with it: under a lamp a hard
    # perforation is a chain of bright arcs, and the arcs were the complaint.
    height = np.clip(0.82 - 0.70 * hole + 0.12 * rim + 0.06 * dirt, 0.0, 1.0)
    return albedo, height, {'spec': -0.45 * hole + 0.22 * rim}

def paint_cloth(size, spec, seed):
    """A shop noren: vertical panels, slits between them, cream type and a mon.

    This material covers every awning, stall front and valance in the market -- 594
    faces and 2.26 million square units -- and the version that shipped drew three
    brown bars with dots in them, because its cream rule was modulo in the wrong
    axis and its indigo was dark enough that `grade` left only the crimson visible.
    So the whole market's soft furnishing read as plywood.  A noren is a very
    specific object and it is drawn as one here: `panels` vertical strips separated
    by a slit you can see daylight through, an indigo ground with one panel in three
    dyed crimson, a cream band across the upper third carrying two blocks of type, a
    family crest on the alternate panels, a stitched hem, and fade where the sun has
    had it longest.
    """
    x, y = axes(size)
    rng = rng_for('cloth', seed)
    thread = int(spec.get('weave', 96))
    weave = 0.5 * np.sin(x / size * thread * 2.0 * math.pi) ** 2 \
        + 0.5 * np.sin(y / size * thread * 2.0 * math.pi) ** 2
    fuzz = fbm(size, 5, 70, seed, 1.0, 2.9)
    fade = fbm(size, 3, 3, seed + 1, 20.0, 1.6)
    # The indigo has to survive the grade, and the cream has to not swallow it.
    # At 0.070 the ground of the cloth was 3.4x darker than the mean the grader was
    # aiming at, so the whole 594-face soft-furnishing set came back as a white band
    # above a black hole -- which is the "textures used wrong way" the owner saw on
    # every awning in the market.
    indigo = np.array([0.100, 0.132, 0.330], np.float32)
    crimson = np.array([0.300, 0.072, 0.082], np.float32)
    cream = np.array([0.335, 0.318, 0.275], np.float32)
    ink = np.array([0.030, 0.034, 0.060], np.float32)
    panels = max(2, int(spec.get('panels', 4)))
    step = size / float(panels)
    index = (x // step).astype(int) % panels
    albedo = np.repeat(indigo[None, None, :], size * size, axis=0).reshape(size, size, 3)
    for panel in range(panels):
        if panel % 3 == 1:                       # one panel in three is dyed crimson
            albedo[:, int(panel * step):int((panel + 1) * step)] = crimson
    # The slits: a noren is cut into panels, and the gap between them is shadow.
    u = x % step
    slit = np.clip(1.0 - np.minimum(u, step - u) / (step * 0.055), 0.0, 1.0) ** 1.2
    albedo = put(albedo, slit * 0.92, ink)
    # Cream band across the top third, with two blocks of "type" in it -- the reading
    # is a shop name, and at 64 units nobody can quote what it says.
    # 18 % of the tile carrying the only bright thing on it is a composition the
    # grader cannot land: to reach its mean it pushes the band out of the image.
    band_top, band_bottom = size * 0.20, size * 0.285
    band = np.zeros((size, size), np.float32)
    band[int(band_top):int(band_bottom), :] = 1.0
    albedo = put(albedo, band * 0.94, cream)
    for panel in range(panels):
        left = panel * step + step * 0.14
        for row in range(2):
            top = band_top + size * 0.030 + row * size * 0.062
            rule = Mask(size).box('rect', (left, top, left + step * rng.uniform(0.30, 0.62),
                                           top + size * 0.030), 255, pad=step).plane()
            albedo = put(albedo, rule * (1.0 - slit) * 0.9, indigo * 0.55 + ink)
        if panel % 2 == 0:                                  # the crest, on alternate panels
            cx, cy, radius = panel * step + step * 0.5, size * 0.58, step * 0.22
            mon = Mask(size).box('ellipse', (cx - radius, cy - radius, cx + radius,
                                             cy + radius), 255, pad=radius * 1.6).plane()
            inner = radius * 0.52
            core = Mask(size).box('ellipse', (cx - inner, cy - inner, cx + inner,
                                              cy + inner), 255, pad=inner * 1.6).plane()
            albedo = put(albedo, (mon - core) * (1.0 - slit) * 0.92, cream)
    hem = np.clip(1.0 - np.abs(y - size * 0.94) / (size * 0.022), 0.0, 1.0)
    albedo = put(albedo, hem * (1.0 - slit) * 0.85, cream * 0.72)
    stitch = np.clip(1.0 - np.abs((x % (size // 32)) - size / 64.0) / (size * 0.0035), 0.0, 1.0)
    albedo = put(albedo, stitch * hem * 0.7, ink)
    # Sun fade: the top of a hanging cloth has seen the most weather.
    albedo = multiply(albedo, 1.0 + 0.18 * np.clip((y / float(size) - 0.5), -0.5, 0.5))
    albedo = multiply(albedo, 0.80 + 0.30 * weave + 0.16 * (fuzz - 0.5) + 0.12 * (fade - 0.5))
    height = np.clip(0.42 + 0.36 * weave + 0.22 * fuzz - 0.30 * slit, 0.0, 1.0)
    return albedo, height, {}

def paint_crate(size, spec, seed):
    """Cargo crate: composite panel, two bolted steel bands, stencilled blocks, wear."""
    grain = fbm(size, 6, 22, seed, 12.0, 2.5)
    x, y = axes(size)
    albedo = np.repeat(np.array([0.105, 0.115, 0.088], np.float32)[None, None, :], size * size,
                       axis=0).reshape(size, size, 3)
    albedo = multiply(albedo, 0.78 + 0.42 * grain)
    height = 0.52 + 0.22 * grain
    bands = int(spec.get('bands', 2))
    for b in range(bands):
        centre, half = (b + 1) * size / (bands + 1.0), size * 0.055
        band = band_field(size, centre, half)
    # The bands are painted steel, and the bolts are stamped into them: at 0.48 the
    # bolt heads were the brightest thing on the panel, and seven of them in a row
    # at 48-unit spacing is exactly what a dash-dot road marking looks like.
        albedo = put(albedo, band, (0.165, 0.175, 0.190))
        height = height + 0.16 * band
        bolts = Mask(size)
        for i in range(7):
            cx, radius = (i + 0.5) * size / 7.0, size * 0.013
            bolts.box('ellipse', (cx - radius, centre - radius, cx + radius, centre + radius), 255,
                      pad=radius * 3)
        albedo = put(albedo, bolts.plane(), (0.285, 0.295, 0.315))
        height = height + 0.08 * bolts.plane()
    rng = rng_for('crate', seed)
    # A crate carries a stencilled destination block: two lines of characters and a
    # hazard placard, off-centre and partly worn away.  Three bars stacked at 4.8 %
    # of the tile is not a marking a shipping crate ever wears; it is a pedestrian
    # crossing seen from a helicopter, and that is what the sheet showed.
    stencil = np.zeros((size, size), np.float32)
    left, line = size * 0.10, size * 0.058
    for row in range(2):
        glyphs = rng.randint(3, 5)
        cursor = left
        for _ in range(glyphs):
            cell = size * rng.uniform(0.038, 0.052)
            box = (cursor, size * 0.62 + row * line * 1.5, cursor + cell,
                   size * 0.62 + row * line * 1.5 + cell)
            stencil += Mask(size).box('rect', box, 255, pad=size * 0.12).plane()
            cursor += cell * 1.35
    placard = Mask(size)
    cx, cy, half = size * 0.74, size * 0.30, size * 0.085
    placard.polygon([(cx, cy - half), (cx + half, cy), (cx, cy + half), (cx - half, cy)],
                    255, pad=half * 2)
    stencil = np.clip(stencil, 0.0, 1.0)
    albedo = put(albedo, stencil * rng.uniform(0.34, 0.52), (0.360, 0.345, 0.300))
    albedo = put(albedo, placard.plane() * 0.62, (0.310, 0.090, 0.062))
    wear = np.clip((fbm(size, 4, 8, seed + 7, 1.0, 1.9) - 0.60) * 3.2, 0.0, 1.0)
    albedo = put(albedo, wear * 0.55, (0.185, 0.175, 0.155))
    scuffed = np.clip((fbm(size, 3, 3, seed + 9, 20.0, 1.5) - 0.64) * 3.4, 0.0, 1.0)
    albedo = put(albedo, scuffed * 0.35, (0.30, 0.29, 0.27))
    return albedo, np.clip(height, 0.0, 1.0), {'spec': 0.25 * scuffed + 0.2 * wear}

def paint_roof_gravel(size, spec, seed):
    """Ballast set in a tar membrane: per-stone tone, per-facet shading, grit.

    Height comes from each stone's own facet plus a barely-blurred coverage, so
    the edges stay hard; the Gaussian crown it used to use is exactly what made
    the tile read as foam.  Stones are small and numerous -- at 420 pieces of up
    to 24 texels the tar between them opened into black cells the size of a hand
    and the whole roof looked like a waffle rather than a surface.
    """
    coverage, tone, facet = pebbles(size, int(spec.get('count', 1500)),
                                    (size * 0.011, size * 0.027), seed)
    membrane = np.repeat(np.array([0.054, 0.052, 0.052], np.float32)[None, None, :], size * size,
                         axis=0).reshape(size, size, 3)
    # Granite, not blue foam: a slightly warm flint and a slightly cool flint in
    # near-equal measure, with the facet tilt deciding how much sky each face
    # catches, which is what gives crushed rock its sparkle.
    luma = 0.30 + 0.36 * tone + 0.18 * (facet - 0.5)
    tint = np.where((tone > 0.62)[..., None], np.array([1.05, 1.00, 0.94], np.float32),
                    np.array([0.94, 0.98, 1.05], np.float32))
    stones = luma[..., None] * tint
    albedo = membrane * (1.0 - coverage[..., None]) + stones * coverage[..., None]
    grit = fbm(size, 6, 80, seed + 3, 1.0, 3.0)
    albedo = multiply(albedo, 0.84 + 0.32 * grit)
    shoulders = gaussian_filter(coverage, 1.2, mode='wrap')
    height = np.clip(0.10 + 0.74 * shoulders * (0.45 + 0.55 * facet) + 0.14 * tone * coverage,
                     0.0, 1.0)
    albedo = shade(albedo, height, 0.34, 0.66)
    return albedo, height, {'spec': 0.30 * coverage * (0.4 + 0.6 * tone)}

def paint_lacquer_red(size, spec, seed):
    """Torii lacquer: black body, vermillion band, gold pinstripe, mirror gloss."""
    x, y = axes(size)
    brushing = fbm(size, 5, 12, seed, 30.0, 2.2)
    dust = fbm(size, 4, 60, seed + 1, 1.0, 3.0)
    body, red, gold = np.array([0.040, 0.016, 0.018], np.float32), \
        np.array([0.225, 0.035, 0.028], np.float32), np.array([0.40, 0.285, 0.105], np.float32)
    albedo = np.zeros((size, size, 3), np.float32) + body
    band = np.clip(1.0 - np.abs((y % (size / 2.0)) - size * 0.25) / (size * 0.155), 0.0, 1.0) ** 0.7
    albedo = put(albedo, band, red)
    stripe = np.clip(1.0 - np.abs((y % (size / 2.0)) - size * 0.055) / (size * 0.009), 0.0, 1.0)
    albedo = put(albedo, stripe, gold)
    albedo = multiply(albedo, 0.90 + 0.22 * brushing + 0.06 * (dust - 0.5))
    scratches = np.clip((fbm(size, 3, 40, seed + 5, 90.0, 1.8) - 0.70) * 4.2, 0.0, 1.0)
    albedo = put(albedo, scratches * 0.3, (0.14, 0.125, 0.115))
    height = np.clip(0.58 + 0.10 * brushing + 0.10 * band - 0.05 * stripe, 0.0, 1.0)
    return albedo, height, {'spec': 0.55 * (1.0 - dust) + 0.25 * gold_luma(albedo)}

def gold_luma(albedo):
    return np.clip(albedo @ np.array([0.35, 0.35, 0.30], np.float32), 0.0, 1.0)

def paint_glass(size, spec, seed):
    """Tinted safety glass: near-black body, one soft reflection ramp, rain streaks.

    The old image was a light-blue woven fabric at 0.45 mean, which is why 480
    balustrade faces read as cloth panes.  Glass in a dusk-lit street is mostly
    what it reflects, so the body stays dark and the sheen does the work.
    """
    x, y = axes(size)
    sheen = np.clip(0.18 + 0.55 * periodic_sweep(size, x, y), 0.0, 1.0)
    albedo = np.repeat(np.array([0.030, 0.038, 0.055], np.float32)[None, None, :], size * size,
                       axis=0).reshape(size, size, 3)
    albedo = albedo + np.array([0.10, 0.125, 0.155], np.float32) * sheen[..., None] ** 2.0
    rng = rng_for('glass', seed)
    streaks = np.zeros((size, size), np.float32)
    for _ in range(int(spec.get('streaks', 26))):
        cx = rng.uniform(0, size)
        width = rng.uniform(1.0, 3.0)
        points = [(cx + rng.uniform(-3, 3), yy) for yy in range(0, size + 4, size // 12)]
        streaks += Mask(size).stroke(points, 255, width=int(width)).plane()
    streaks = np.clip(streaks, 0.0, 1.0) * 0.35
    albedo = albedo + np.array([0.075, 0.085, 0.10], np.float32) * streaks[..., None]
    dust = np.clip((fbm(size, 5, 60, seed + 4, 1.0, 3.0) - 0.68) * 3.0, 0.0, 1.0)
    albedo = albedo + np.array([0.045, 0.048, 0.052], np.float32) * dust[..., None]
    height = np.clip(0.5 + 0.10 * streaks, 0.0, 1.0)
    return albedo, height, {'spec': 0.5 + 0.45 * sheen, 'alpha': 1.0 - 0.35 * streaks}

class Paint:
    """A PIL RGB front-end with the same wrap discipline as `Mask`.

    Where a material is built from hundreds of opaque dabs -- leaves, chipped
    paint, aggregate -- compositing every dab against the canvas costs a full
    1024^2 pass each time, so the dabs go straight into an RGB image instead and
    the wrap offsets are handled here once.
    """

    def __init__(self, size, colour=(0.0, 0.0, 0.0)):
        self.size = size
        self.image = Image.new('RGB', (size, size),
                               tuple(int(round(value * 255.0)) for value in colour))
        self.pen = ImageDraw.Draw(self.image)

    def ellipse(self, box, colour, pad=0.0):
        fill = tuple(int(round(value * 255.0)) for value in np.clip(colour, 0.0, 1.0))
        for dx, dy in Mask(self.size).offsets(box, pad):
            self.pen.ellipse((box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy), fill=fill)
        return self

    def polygon(self, points, colour, pad=0.0):
        """A rotated stamp -- a leaf is an ellipse turned to the light."""
        fill = tuple(int(round(value * 255.0)) for value in np.clip(colour, 0.0, 1.0))
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        box = (min(xs), min(ys), max(xs), max(ys))
        for dx, dy in Mask(self.size).offsets(box, pad):
            self.pen.polygon([(x + dx, y + dy) for x, y in points], fill=fill)
        return self

    def polygon(self, points, colour, pad=0.0):
        """A rotated stamp -- a leaf is an ellipse turned to the light."""
        fill = tuple(int(round(value * 255.0)) for value in np.clip(colour, 0.0, 1.0))
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        box = (min(xs), min(ys), max(xs), max(ys))
        for dx, dy in Mask(self.size).offsets(box, pad):
            self.pen.polygon([(x + dx, y + dy) for x, y in points], fill=fill)
        return self

    def polygon(self, points, colour, pad=0.0):
        """A rotated stamp -- a leaf is an ellipse turned to the light."""
        fill = tuple(int(round(value * 255.0)) for value in np.clip(colour, 0.0, 1.0))
        xs = [point[0] for point in points]
        ys = [point[1] for point in points]
        box = (min(xs), min(ys), max(xs), max(ys))
        for dx, dy in Mask(self.size).offsets(box, pad):
            self.pen.polygon([(x + dx, y + dy) for x, y in points], fill=fill)
        return self

    def array(self):
        return np.asarray(self.image, np.float32)[..., :3] / 255.0

def paint_metal_column(size, spec, seed):
    """Brushed stainless: vertical grain, hairline marks, deeper scratches, rivet line."""
    # Anisotropy is squeezed vertical frequency, and squeezed vertical frequency *is*
    # a comb of vertical bands: `aniso 34` and `aniso 90` here were a 1-D field before a
    # single stroke was drawn.  The decomposition says the fields were never the
    # dangerous part (x swing 0.003), so they keep a vertical pull -- 20 and 30 instead
    # of 34 and 90 -- and give up a little amplitude.
    grain = fbm(size, 5, 8, seed, 20.0, 2.0)
    fine = fbm(size, 3, 18, seed + 1, 30.0, 2.6)
    sheen = fbm(size, 3, 2, seed + 2, 60.0, 1.4)
    albedo = np.repeat((0.40 + 0.12 * grain + 0.06 * fine + 0.14 * (sheen - 0.5))[..., None], 3, axis=2)
    albedo = multiply(albedo, np.array([0.965, 0.975, 1.02], np.float32))
    rng = rng_for('column', seed)
    dark, light, deep = Mask(size), Mask(size), Mask(size)
    # 1.5 strokes per texel, 1-2 texels wide, between 0.235 and 0.70: a line every
    # 0.67 texels, above the tile's own Nyquist limit, and one third of the answer to
    # "why does the north ramp look like fish scales".  0.30 strokes per texel at 3-6
    # texels keeps the brush -- the streak is a half to a full world unit wide at the
    # cladding's 48-unit repeat -- and the alpha and colour targets come down to what a
    # photographed panel actually shows: 6% marks around one base tone, not two colours.
    for _ in range(int(size * 0.30)):
        x, width = int(rng.uniform(0, size)), int(rng.choice([3, 4, 5, 6]))
        grey = int(255 * rng.uniform(0.05, 0.11))
        (dark if rng.random() < 0.55 else light).stroke([(x, 0), (x, size)], grey, width=width, wrap=False)
    # Four full-height 3-texel marks at 0.45 weight were worth more x-swing than all
    # 150 strokes together: a line that spans the tile is a delta function in exactly
    # the direction a grazing view compresses.  Real brushed steel has scratches, so
    # three stay -- wider, and at a weight that survives a metre and not a kilometre.
    for _ in range(3):
        x = rng.uniform(0, size)
        deep.stroke([(x, 0), (x + rng.uniform(-10, 10), size)], 255, width=5, wrap=False)
    albedo = put(albedo, dark.plane(), (0.360, 0.365, 0.390))
    albedo = put(albedo, light.plane(), (0.485, 0.495, 0.520))
    albedo = put(albedo, deep.plane() * 0.14, (0.30, 0.30, 0.32))
    rivets = Mask(size)
    step = size / float(spec.get('rivets', 8))
    for j in range(int(spec.get('rivets', 8))):
        radius = step * 0.13
        cx, cy = step * 0.16, (j + 0.5) * step
        rivets.box('ellipse', (cx - radius, cy - radius, cx + radius, cy + radius), 255, pad=radius * 2)
    albedo = put(albedo, rivets.plane(), (0.47, 0.48, 0.51))
    # With the albedo contrast cut, the brush has to live where a groove physically
    # is -- in the relief and in the glint -- or the panel goes flat blue-grey, which
    # is the failure this material shipped with at repeat 128.  Signed (light - dark)
    # is the same field the albedo was blended with, at a tenth of its weight.
    brush_relief = light.plane() - dark.plane()
    height = np.clip(0.50 + 0.16 * fine + 0.14 * grain + 0.16 * rivets.plane()
                     + 0.10 * brush_relief, 0.0, 1.0)
    return albedo, height, {'spec': 0.18 * (sheen - 0.5) + 0.20 * rivets.plane()
                            + 0.10 * brush_relief}

def paint_metal_deck(size, spec, seed):
    """Diamond plate: interleaved rows of raised lozenges, worn tips, dirty valleys."""
    cells = int(spec.get('cells', 4))
    step = size / float(cells)
    plate = Mask(size)
    for j in range(cells + 1):
        for i in range(cells + 1):
            for parity, slant in ((0.0, 1.0), (0.5, -1.0)):
                cx = (i + 0.30 + parity) * step + (0.5 * step if j % 2 else 0.0)
                cy = (j + 0.30 + parity) * step
                angle = math.radians(45.0 * slant)
                long_axis, short_axis = step * 0.42, step * 0.15
                corners = []
                for corner in ((1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)):
                    corners.append((cx + corner[0] * long_axis * math.cos(angle)
                                    - corner[1] * short_axis * math.sin(angle),
                                    cy + corner[0] * long_axis * math.sin(angle)
                                    + corner[1] * short_axis * math.cos(angle)))
                plate.polygon(corners, 255, pad=step)
    crown = gaussian_filter(plate.plane(), step * 0.12, mode='wrap')
    dirt = fbm(size, 6, 30, seed, 1.0, 2.7)
    albedo = np.repeat((0.27 + 0.10 * dirt)[..., None], 3, axis=2)
    albedo = multiply(albedo, np.array([0.90, 0.95, 1.06], np.float32))
    valley = np.clip((0.40 - crown) * 2.6, 0.0, 1.0) * (0.55 + 0.45 * dirt)
    albedo = put(albedo, valley * 0.30, (0.115, 0.118, 0.125))
    tip = np.clip((crown - 0.60) * 3.4, 0.0, 1.0)
    albedo = put(albedo, tip * 0.34, (0.360, 0.375, 0.400))
    bolts = Mask(size)
    rows = int(spec.get('bolts', 3))
    for j in range(rows):
        for i in range(rows):
            radius = step * 0.11
            cx, cy = (i + 0.5) * size / rows, (j + 0.5) * size / rows
            bolts.box('ellipse', (cx - radius, cy - radius, cx + radius, cy + radius), 255, pad=radius * 2)
    albedo = put(albedo, bolts.plane(), (0.385, 0.395, 0.420))
    height = np.clip(0.26 + 0.60 * crown + 0.10 * dirt + 0.14 * bolts.plane(), 0.0, 1.0)
    return albedo, height, {'spec': 0.35 * tip + 0.45 * bolts.plane() - 0.45 * valley}

def paint_tower_front(size, spec, seed):
    """Future high-rise: a mullioned window grid with a designed set of lit windows.

    The lit set is explicit rather than "threshold whatever is bright": a facade
    that is 80 % dark glass and 20 % lit windows tells the player which parts of
    the city are occupied, and it gives the additive `_g` stage real content.
    """
    bays, floors = int(spec.get('bays', 12)), int(spec.get('floors', 8))
    x, y = axes(size)
    bay, floor = size / float(bays), size / float(floors)
    rng = rng_for('tower', seed)
    albedo = np.zeros((size, size, 3), np.float32) + np.array([0.155, 0.155, 0.150], np.float32)
    height = np.full((size, size), 0.60, np.float32)
    lit = np.zeros((size, size), np.float32)
    inset = bay * float(spec.get('inset', 0.15))
    for j in range(floors):
        for i in range(bays):
            x0, y0 = int(i * bay + inset), int(j * floor + inset * 1.4)
            x1, y1 = int((i + 1) * bay - inset), int((j + 1) * floor - inset * 1.4)
            roll = rng.random()
            warm, cool = float(spec.get('lit_warm', 0.12)), float(spec.get('lit_cool', 0.08))
            if roll < warm:
                window = np.array([0.68, 0.48, 0.25], np.float32) * rng.uniform(0.50, 1.0)
            elif roll < warm + cool:
                window = np.array([0.32, 0.55, 0.66], np.float32) * rng.uniform(0.40, 0.85)
            else:
                window = np.array([0.040, 0.050, 0.070], np.float32)
            albedo[y0:y1, x0:x1] = window
            height[y0:y1, x0:x1] = 0.22
            if roll < warm + cool:
                lit[y0:y1, x0:x1] = 1.0
    spandrel = np.clip(1.0 - np.abs((y % floor) - floor * 0.07) / (floor * 0.10), 0.0, 1.0)
    albedo = put(albedo, spandrel * 0.9, (0.130, 0.130, 0.126))
    height = np.clip(height + 0.22 * spandrel, 0.0, 1.0)
    # A balcony rail and a sill drip on every storey.  Without them a floor is a row
    # of floating rectangles; with them the facade says how tall a storey is, which
    # is the one thing a player needs to read a 500-unit wall as a building.
    rail = np.clip(1.0 - np.abs((y % floor) - floor * 0.30) / (floor * 0.055), 0.0, 1.0)
    albedo = put(albedo, rail * 0.85, (0.215, 0.215, 0.208))
    height = np.clip(height + 0.16 * rail, 0.0, 1.0)
    drip = np.clip((fbm(size, 4, 26, seed + 12, 26.0, 2.2) - 0.52) * 2.2, 0.0, 1.0)
    below = np.clip(((y % floor) - floor * 0.90) / (floor * 0.30), 0.0, 1.0)
    albedo = put(albedo, drip * below * 0.5, (0.062, 0.052, 0.044))
    # One bay in eight carries a lit sign band at street-facing height, so the
    # facade is not lit only by random offices.
    sign_bays = np.clip(np.abs(((x // bay).astype(int) % 8) - 3.5) - 3.0, 0.0, 1.0)
    band_row = np.clip(1.0 - np.abs((y % (floor * 2.0)) - floor * 0.35) / (floor * 0.16), 0.0, 1.0)
    sign = np.clip(sign_bays * band_row, 0.0, 1.0)
    # Sodium-and-mercury signage, not magenta: this band repeats on every eighth bay
    # of four whole facade walls, so its colour is the colour of the skyline.
    albedo = put(albedo, sign * 0.9, (0.82, 0.50, 0.20))
    lit = np.clip(lit + sign * 0.8, 0.0, 1.0)
    # A balcony rail and a sill drip on every storey.  Without them a floor is a row
    # of floating rectangles; with them the facade says how tall a storey is, which
    # is the one thing a player needs to read a 500-unit wall as a building.
    rail = np.clip(1.0 - np.abs((y % floor) - floor * 0.30) / (floor * 0.055), 0.0, 1.0)
    albedo = put(albedo, rail * 0.85, (0.215, 0.215, 0.208))
    height = np.clip(height + 0.16 * rail, 0.0, 1.0)
    drip = np.clip((fbm(size, 4, 26, seed + 12, 26.0, 2.2) - 0.52) * 2.2, 0.0, 1.0)
    below = np.clip(((y % floor) - floor * 0.90) / (floor * 0.30), 0.0, 1.0)
    albedo = put(albedo, drip * below * 0.5, (0.062, 0.052, 0.044))
    # One bay in eight carries a lit sign band at street-facing height, so the
    # facade is not lit only by random offices.
    sign_bays = np.clip(np.abs(((x // bay).astype(int) % 8) - 3.5) - 3.0, 0.0, 1.0)
    band_row = np.clip(1.0 - np.abs((y % (floor * 2.0)) - floor * 0.35) / (floor * 0.16), 0.0, 1.0)
    sign = np.clip(sign_bays * band_row, 0.0, 1.0)
    # Sodium-and-mercury signage, not magenta: this band repeats on every eighth bay
    # of four whole facade walls, so its colour is the colour of the skyline.
    albedo = put(albedo, sign * 0.9, (0.82, 0.50, 0.20))
    lit = np.clip(lit + sign * 0.8, 0.0, 1.0)
    # A balcony rail and a sill drip on every storey.  Without them a floor is a row
    # of floating rectangles; with them the facade says how tall a storey is, which
    # is the one thing a player needs to read a 500-unit wall as a building.
    rail = np.clip(1.0 - np.abs((y % floor) - floor * 0.30) / (floor * 0.055), 0.0, 1.0)
    albedo = put(albedo, rail * 0.85, (0.215, 0.215, 0.208))
    height = np.clip(height + 0.16 * rail, 0.0, 1.0)
    drip = np.clip((fbm(size, 4, 26, seed + 12, 26.0, 2.2) - 0.52) * 2.2, 0.0, 1.0)
    below = np.clip(((y % floor) - floor * 0.90) / (floor * 0.30), 0.0, 1.0)
    albedo = put(albedo, drip * below * 0.5, (0.062, 0.052, 0.044))
    # One bay in eight carries a lit sign band at street-facing height, so the
    # facade is not lit only by random offices.
    sign_bays = np.clip(np.abs(((x // bay).astype(int) % 8) - 3.5) - 3.0, 0.0, 1.0)
    band_row = np.clip(1.0 - np.abs((y % (floor * 2.0)) - floor * 0.35) / (floor * 0.16), 0.0, 1.0)
    sign = np.clip(sign_bays * band_row, 0.0, 1.0)
    albedo = put(albedo, sign * 0.9, (0.86, 0.30, 0.52))
    lit = np.clip(lit + sign * 0.8, 0.0, 1.0)
    reflection = np.clip(0.20 + 0.60 * periodic_sweep(size, x, y), 0.0, 1.0)
    grit = fbm(size, 6, 40, seed + 5, 1.0, 2.9)
    weathered = multiply(albedo, (0.86 + 0.26 * grit) * (1.0 + 0.75 * reflection))
    albedo = np.where(lit[..., None] > 0, albedo, weathered)
    height = np.clip(height + 0.06 * (1.0 - lit), 0.0, 1.0)
    glow = albedo * lit[..., None] + np.clip(gaussian_filter(lit, size * 0.004, mode='wrap'), 0.0, 1.0)[..., None] \
        * albedo * 0.5
    return albedo, height, {'spec': 0.45 * reflection * (1.0 - lit) + 0.25 * lit,
                            'glow': np.clip(glow, 0.0, 1.0)}

def paint_plant(size, spec, seed):
    """A clipped hedge: leaf plates, two and three deep, until the tile is covered.

    The first cut scattered a few hundred small ellipses on a near-black canopy and
    let `grade` drag the mean upward, so what shipped was black television static
    with green sparkles -- and every planter, bed and roof hedge in the arena read
    as a bag of rubble.  A hedge is *covered*: the dark value belongs in the shadow
    between leaves rather than in the base coat, so the mean is made of leaf and not
    of void.  Leaves are 2-5 % of the tile across (a 3-7 cm leaf on a 1 m tile), each
    one a rotated plate with a lighter midrib, drawn in five greens.
    """
    rng = rng_for('plant', seed)
    shadow, mature, bright, young, dry = (
        np.array([0.038, 0.072, 0.034], np.float32),
        np.array([0.140, 0.245, 0.098], np.float32),
        np.array([0.225, 0.350, 0.140], np.float32),
        np.array([0.300, 0.430, 0.165], np.float32),
        np.array([0.330, 0.360, 0.140], np.float32))
    canopy = Paint(size, shadow)
    height = np.full((size, size), 0.16, np.float32)
    picks = (mature, mature, mature, bright, bright, young, dry)
    for _ in range(int(size * size / 900.0)):                      # ~1160 leaves at 1024
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        long_axis = rng.uniform(size * 0.020, size * 0.052)
        short_axis = long_axis * rng.uniform(0.40, 0.60)
        angle = rng.uniform(0.0, math.pi)
        colour = picks[rng.randrange(len(picks))] * rng.uniform(0.80, 1.22)
        corners = []
        for step in range(10):
            theta = step * math.pi / 5.0
            corners.append((cx + long_axis * math.cos(theta) * math.cos(angle)
                            - short_axis * math.sin(theta) * math.sin(angle),
                            cy + long_axis * math.cos(theta) * math.sin(angle)
                            + short_axis * math.sin(theta) * math.cos(angle)))
        canopy.polygon(corners, colour, pad=long_axis * 1.2)
        leaf = Mask(size).polygon(corners, 255, pad=long_axis * 1.2).plane()
        height = np.clip(height + 0.18 * leaf, 0.0, 1.0)
    albedo = canopy.array()
    # The midrib pass, done as a field so it can be lighter than its own leaf: the
    # stamps above are opaque, and a vein is a highlight, not a second colour.
    vein = np.clip(fbm(size, 5, 90, seed + 4, 1.0, 2.6) - 0.60, 0.0, 1.0) * 2.2
    albedo = put(albedo, vein * 0.35, np.array([0.36, 0.48, 0.22], np.float32))
    depth = 0.62 + 0.38 * fbm(size, 5, 5, seed + 1, 1.0, 1.8)
    albedo = multiply(albedo, depth * (0.86 + 0.28 * fbm(size, 5, 26, seed + 2, 1.0, 2.4)))
    return albedo, np.clip(height, 0.0, 1.0), {}

# --------------------------------------------------------------------------- #
# emissive signage
#
# `neon_a`/`neon_b`/`ad_board`/`light_strip`/`holo_pool` are `nolightmap`
# surfaces: the diffuse stage is what the player sees and the additive `_g` stage
# is the bloom, so their albedo has to be a designed composition at the size a
# face actually shows.  Their faces measure 56-72 world units against the old
# 256-unit tile, which is why the shipped ones showed a 22 % window of speckle.
# --------------------------------------------------------------------------- #
#: Katakana as polylines in a unit box.  The set is deliberately small and the
#: reading is "signage", not copy: at 60 world units a stroke reads as a sign and
#: nobody can quote the arena back something it did not say.
KANA = {
    'ka': [[(0.08, 0.16), (0.92, 0.16)], [(0.78, 0.10), (0.24, 0.92)]],
    'ku': [[(0.10, 0.14), (0.90, 0.14)], [(0.86, 0.14), (0.22, 0.86), (0.62, 0.92)]],
    'shi': [[(0.14, 0.12), (0.32, 0.46)], [(0.44, 0.10), (0.62, 0.44)],
            [(0.74, 0.10), (0.92, 0.44)], [(0.52, 0.62), (0.86, 0.94)]],
    'to': [[(0.08, 0.14), (0.92, 0.14)], [(0.50, 0.14), (0.50, 0.78)], [(0.14, 0.80), (0.86, 0.80)]],
    'n': [[(0.20, 0.10), (0.44, 0.46)], [(0.44, 0.46), (0.28, 0.92)], [(0.60, 0.18), (0.88, 0.90)]],
    'ma': [[(0.18, 0.10), (0.18, 0.90)], [(0.18, 0.10), (0.82, 0.10)],
           [(0.82, 0.10), (0.82, 0.90)], [(0.18, 0.52), (0.82, 0.52)]],
    'ki': [[(0.14, 0.14), (0.86, 0.14)], [(0.50, 0.14), (0.50, 0.60)],
           [(0.20, 0.62), (0.50, 0.62), (0.80, 0.92)]],
    'ra': [[(0.18, 0.12), (0.30, 0.90)], [(0.24, 0.44), (0.80, 0.12)], [(0.80, 0.12), (0.72, 0.90)]],
    'me': [[(0.12, 0.22), (0.88, 0.14)], [(0.50, 0.10), (0.50, 0.92)],
           [(0.16, 0.50), (0.36, 0.86)], [(0.84, 0.42), (0.64, 0.86)]],
    'tsu': [[(0.14, 0.14), (0.86, 0.14)], [(0.30, 0.14), (0.22, 0.56)],
            [(0.62, 0.14), (0.70, 0.90), (0.40, 0.90)]],
    'ha': [[(0.14, 0.14), (0.20, 0.56)], [(0.86, 0.14), (0.80, 0.90)], [(0.20, 0.42), (0.86, 0.42)]],
    'yo': [[(0.18, 0.12), (0.18, 0.90)], [(0.18, 0.12), (0.84, 0.12)],
           [(0.84, 0.12), (0.84, 0.52), (0.46, 0.52)]],
}

def kana_plane(size, glyph, stroke=0.10):
    """-> the (HxW) stroke mask of one glyph drawn across the whole tile."""
    mask = Mask(size)
    width = max(2, int(size * stroke))
    for points in KANA[glyph]:
        mask.stroke([(x * size, y * size) for x, y in points], 255, width=width)
    return mask.plane()

def tube_field(size, glyph, core=0.004, halo=0.020):
    """-> (tube, halo) of one glyph's neon: a hard stroke and its own spill."""
    strokes = gaussian_filter(kana_plane(size, glyph), size * core, mode='constant')
    return strokes, np.clip(gaussian_filter(strokes, size * halo, mode='constant'), 0.0, 1.0)

def inset_plane(plane, inset):
    """"-> the plane with its content shrunk toward the centre by `inset` of the tile.

    A neon sign is a tube inside a housing, and the housing is the black that makes
    the tube legible.  Drawn edge to edge, a 60-unit sign face shows one fat stroke
    from corner to corner and the eye reads it as a coloured panel; the same strokes
    at 0.82 of the cell read as lettering with a margin around them.
    """
    if inset <= 0.0:
        return plane
    side = int(round(plane.shape[0] * (1.0 - 2.0 * inset)))
    image = Image.fromarray((np.clip(plane, 0.0, 1.0) * 255.0).astype(np.uint8))
    image = image.resize((max(1, side), max(1, side)), Image.BILINEAR)
    image = image.resize(plane.shape, Image.BILINEAR)
    return np.asarray(image, np.float32) / 255.0


def paint_neon(size, spec, seed):
    """A vertical column of kana tubes on black, framed, with a housing behind."""
    rng = rng_for('neon', seed)
    glyphs = spec.get('glyphs') or rng.sample(sorted(KANA), 2)
    colours = [np.array(colour, np.float32) for colour in spec['colours']]
    albedo = np.zeros((size, size, 3), np.float32)
    glow = np.zeros((size, size, 3), np.float32)
    height = np.full((size, size), 0.28, np.float32)
    rows = len(glyphs)
    for index, glyph in enumerate(glyphs):
        top = int(size * (0.05 + index * (0.90 / rows)))
        window = np.zeros((size, size), np.float32)
        window[top:top + int(size * 0.90 / rows), :] = 1.0
        tube, halo = tube_field(size, glyph)
        inset = float(spec.get('inset', 0.0))
        tube = np.clip(inset_plane(tube, inset) * window, 0.0, 1.0)
        halo = inset_plane(halo, inset)
        colour = colours[index % len(colours)] * float(spec.get('tube', 1.0))
        albedo = put(albedo, tube, colour)
        albedo = albedo + colour * (halo * 0.30)[..., None]
        glow = np.clip(glow + colour * np.clip(tube + halo * 0.85, 0.0, 1.0)[..., None], 0.0, 1.0)
        height = height + 0.50 * tube
    frame = Mask(size)
    frame.box('rect', (size * 0.015, size * 0.015, size * 0.985, size * 0.985), 255)
    frame.box('rect', (size * 0.045, size * 0.045, size * 0.955, size * 0.955), 0)
    albedo = put(albedo, frame.plane() * 0.9, (0.050, 0.046, 0.056))
    grime = np.clip((fbm(size, 4, 6, seed + 3, 1.0, 1.9) - 0.62) * 3.0, 0.0, 1.0)
    albedo = put(albedo, grime * 0.30, (0.028, 0.026, 0.030))
    return albedo, np.clip(height, 0.0, 1.0), {'glow': glow}

def paint_vend_face(size, spec, seed):
    """A vending machine's front: a glass cabinet of lit products in a painted body.

    This material is the face of every `vend_*` box on the two covered lanes and the
    plaza, and it used to be the neon painter's kana -- coloured strokes where a real
    machine has a *cabinet*, and the reason `vend_e` (mean 0.130 in `probe-352`) read
    as a dark corridor with a glitch in it rather than as the row of glowing boxes
    that makes a Japanese street at 2 a.m. look like a Japanese street at 2 a.m.
    """
    rng = rng_for('vend_face', seed)
    albedo = np.repeat(np.array([0.085, 0.100, 0.140], np.float32)[None, None, :],
                       size * size, axis=0).reshape(size, size, 3)
    height = np.full((size, size), 0.34, np.float32)
    glow = np.zeros((size, size, 3), np.float32)
    # The cabinet occupies the upper two thirds; below it is the machine's belly,
    # its coin slot and the shelf of things that have already been sold.
    glass = (int(size * 0.085), int(size * 0.055), int(size * 0.915), int(size * 0.70))
    albedo[glass[1]:glass[3], glass[0]:glass[2]] = (0.030, 0.034, 0.042)
    height[glass[1]:glass[3], glass[0]:glass[2]] = 0.16
    # Two tubes along the top of the glass: this is the light the cabinet throws on
    # the pavement, and it is the brightest thing on the tile.
    for tube in (0.10, 0.26):
        top = int(size * tube)
        albedo[top:top + int(size * 0.030), glass[0]:glass[2]] = (0.80, 0.83, 0.90)
        glow[top:top + int(size * 0.030), glass[0]:glass[2]] = (0.86, 0.88, 0.94)
    columns, rows = int(spec.get('columns', 4)), int(spec.get('rows', 5))
    left, right = glass[0] + size * 0.030, glass[2] - size * 0.030
    head, foot = glass[1] + size * 0.135, glass[3] - size * 0.030
    step_x, step_y = (right - left) / float(columns), (foot - head) / float(rows)
    drinks = ((0.52, 0.09, 0.10), (0.60, 0.34, 0.08), (0.14, 0.34, 0.16),
              (0.12, 0.22, 0.42), (0.52, 0.50, 0.46), (0.30, 0.12, 0.30),
              (0.62, 0.48, 0.20), (0.10, 0.30, 0.30))
    for row in range(rows):
        # The shelf under each row of cans, and the strip of light it catches.
        shelf_y = int(head + (row + 1) * step_y - size * 0.012)
        albedo[shelf_y:shelf_y + int(size * 0.012), int(left):int(right)] = (0.20, 0.21, 0.23)
        glow[shelf_y:shelf_y + int(size * 0.012), int(left):int(right)] = (0.30, 0.32, 0.36)
        for column in range(columns):
            if rng.random() < float(spec.get('sold_out', 0.12)):
                continue                          # an empty slot, and a dark one
            tone = np.array(drinks[rng.randrange(len(drinks))], np.float32)
            tone = tone * rng.uniform(0.62, 1.18) + 0.05
            x0 = int(left + column * step_x + step_x * 0.13)
            x1 = int(left + (column + 1) * step_x - step_x * 0.13)
            y0 = int(head + row * step_y + step_y * 0.14)
            y1 = int(head + (row + 1) * step_y - step_y * 0.16)
            albedo[y0:y1, x0:x1] = tone
            albedo[y0:y1, x0:x0 + max(1, (x1 - x0) // 4)] = tone * 1.45   # the can's highlight
            glow[y0:y1, x0:x1] = np.clip(tone * 1.35, 0.0, 1.0)
            height[y0:y1, x0:x1] = 0.52
    # The belly: a pick panel, a coin slot, and the machine's own brand stripe.
    band_y = int(size * 0.76)
    albedo[band_y:band_y + int(size * 0.055), int(size * 0.10):int(size * 0.90)] = \
        np.array(spec.get('brand', (0.34, 0.06, 0.07)), np.float32)
    for slot in (0.22, 0.50, 0.78):
        x0 = int(size * slot)
        albedo[int(size * 0.86):int(size * 0.94), x0:x0 + int(size * 0.10)] = (0.024, 0.026, 0.030)
        height[int(size * 0.86):int(size * 0.94), x0:x0 + int(size * 0.10)] = 0.10
    dust = np.clip((fbm(size, 4, 26, seed, 1.0, 2.3) - 0.62) * 2.6, 0.0, 1.0)
    albedo = put(albedo, dust * 0.40, (0.030, 0.032, 0.036))
    return albedo, np.clip(height, 0.0, 1.0), {'glow': glow}


def paint_ad_board(size, spec, seed):
    """A light box that carries *posters*: two panels side by side, each a design.

    The previous composition was one white ring on black with three bars beside it,
    and because a median `ad_board` face is 124 units against a 256-unit tile, every
    board in the arena displayed a crop of that ring -- a giant blank disc, floating
    in black, in the middle of a night market.  Two problems, two fixes: the tile is
    now a row of self-contained panels (so any crop still shows a whole poster
    somewhere), and each panel is filled -- a colour field, a headline rule, a glyph
    column, a logo block and a frame -- so there is no black left to look blank.

    Flat vector on purpose: at the density a 600-unit board is displayed at,
    photographic noise reads as grey while hard geometry stays legible.
    """
    rng = rng_for('ad_board', seed)
    x, y = axes(size)
    ink = np.array([0.055, 0.058, 0.070], np.float32)
    ice = np.array([0.92, 0.94, 0.99], np.float32)
    frames = (np.array([0.98, 0.36, 0.66], np.float32),      # magenta tube
              np.array([0.34, 0.86, 1.00], np.float32),      # cyan tube
              np.array([1.00, 0.72, 0.22], np.float32),      # sodium tube
              np.array([0.58, 0.98, 0.52], np.float32))      # green tube
    grounds = (np.array([0.115, 0.045, 0.150], np.float32),  # deep violet
               np.array([0.150, 0.055, 0.048], np.float32),  # dark vermilion
               np.array([0.030, 0.105, 0.140], np.float32),  # petrol
               np.array([0.125, 0.110, 0.040], np.float32))  # mustard shadow
    albedo = np.zeros((size, size, 3), np.float32) + ink
    columns = max(1, int(spec.get('panels', 2)))
    step = size / float(columns)
    gutter = step * 0.055
    for index in range(columns):
        ground, tube = grounds[index % len(grounds)], frames[index % len(frames)]
        x0, x1 = index * step + gutter, (index + 1) * step - gutter
        y0, y1 = size * 0.045, size * 0.955
        panel = Mask(size).box('rect', (x0, y0, x1, y1), 255, pad=step * 0.6).plane()
        albedo = put(albedo, panel, ground)
        # A gradient in the panel's own bottom third: a poster is a photograph of
        # something, and a photograph has a horizon.
        band = np.zeros((size, size), np.float32)
        band[int(y1 - (y1 - y0) * 0.46):int(y1), int(x0):int(x1)] = 1.0
        # A colour that varies across the panel cannot go through `put`, which blends
        # against one flat colour, so the horizon of the poster is blended by hand.
        field = 0.42 + 0.58 * np.clip((y - y0) / float(y1 - y0), 0.0, 1.0)
        weight = (band * 0.55)[..., None]
        albedo = albedo * (1.0 - weight) + (tube[None, None, :] * field[..., None]) * weight
        # Frame: a thin tube round the panel, brightest at the corners.
        edge = panel - Mask(size).box('rect', (x0 + step * 0.018, y0 + step * 0.018,
                                               x1 - step * 0.018, y1 - step * 0.018),
                                      255, pad=step * 0.6).plane()
        albedo = put(albedo, np.clip(edge, 0.0, 1.0) * 0.95, ice * 0.75 + tube * 0.25)
        # Headline rules and a logo block: the typography of a poster, not letters.
        for row in range(3):
            rule_top = y1 - (y1 - y0) * (0.14 + row * 0.075)
            rule = Mask(size).box('rect', (x0 + step * 0.10, rule_top,
                                           x0 + step * (0.30 + 0.55 * rng.random()),
                                           rule_top + size * 0.016), 255,
                                  pad=step * 0.6).plane()
            albedo = put(albedo, rule, ice if row == 0 else tube * 0.85)
        block = Mask(size).box('rect', (x0 + step * 0.08, y0 + size * 0.045,
                                        x0 + step * 0.30, y0 + size * 0.135), 255,
                               pad=step * 0.6).plane()
        albedo = put(albedo, block, tube)
        # The glyph column a Japanese signboard actually has: one glyph, big, on the
        # right third, drawn as neon tube with its own halo.
        glyph = (spec.get('glyphs') or sorted(KANA))[index % len(KANA)]
        tube_of, halo_of = tube_field(size, glyph, core=0.0035, halo=0.011)
        column_mask = np.zeros((size, size), np.float32)
        left, right = int(x1 - step * 0.44), int(x1 - step * 0.08)
        top, bottom = int(y0 + size * 0.10), int(y1 - size * 0.30)
        column_mask[top:bottom, left:right] = 1.0
        lit = np.clip((tube_of + halo_of * 0.55) * column_mask, 0.0, 1.0)
        albedo = put(albedo, lit * 0.98, ice * 0.55 + tube * 0.45)
    # Gutter structure between the panels, and a scanline over the whole box: a
    # light box is a diffuser in front of a lamp array, and that grid is visible.
    scan = np.clip(1.0 - np.abs((y % max(2, size // 96)) - size / 192.0) / (size * 0.0022),
                   0.0, 1.0) * 0.10
    albedo = multiply(albedo, 1.0 - scan[..., None])
    albedo = multiply(albedo, 0.94 + 0.10 * fbm(size, 4, 4, seed + 6, 1.0, 1.8))
    dirt = np.clip((fbm(size, 4, 7, seed + 9, 3.0, 1.9) - 0.66) * 2.6, 0.0, 1.0)
    albedo = put(albedo, dirt * 0.35, np.array([0.070, 0.066, 0.058], np.float32))
    return np.clip(albedo, 0.0, 0.95), np.full((size, size), 0.52, np.float32), \
        {'glow': np.clip(albedo * 1.12, 0.0, 1.0)}

def paint_light_strip(size, spec, seed):
    """An LED strip: one continuous bright core in a dark housing.

    The generated set came back as a grid of white blobs, which on a 136-unit
    ceiling edge reads as egg cartons.  A strip only has to survive being cropped
    along its length, which a horizontal band does and a grid does not.
    """
    x, y = axes(size)
    # sigma 0.115 put 46 % of the tile within one standard deviation of full white,
    # which on anything seen face-on is a plank of light rather than a strip of it.
    core = np.exp(-((y - size * 0.5) / (size * 0.062)) ** 2)
    housing = np.clip(1.0 - core, 0.0, 1.0)
    albedo = np.repeat(np.array([0.028, 0.030, 0.036], np.float32)[None, None, :], size * size,
                       axis=0).reshape(size, size, 3)
    albedo = albedo + np.array([0.80, 0.85, 0.95], np.float32) * core[..., None]
    albedo = albedo + np.array([0.26, 0.42, 0.60], np.float32) * (core ** 0.35 * 0.22)[..., None]
    ribs = np.clip(1.0 - np.abs((x % (size // 4)) - size // 8) / (size * 0.005), 0.0, 1.0)
    albedo = put(albedo, ribs * housing * 0.8, (0.045, 0.046, 0.050))
    dust = np.clip((fbm(size, 4, 30, seed, 1.0, 2.4) - 0.60) * 2.6, 0.0, 1.0)
    albedo = put(albedo, dust * housing * 0.45, (0.070, 0.073, 0.078))
    height = np.clip(0.28 + 0.58 * core - 0.16 * ribs * housing, 0.0, 1.0)
    return albedo, height, {'glow': albedo.copy()}

def paint_holo_pool(size, spec, seed):
    """Pool water at night: a deep body, caustic ripples, the street reflected in it.

    This surface used to be a lamp wearing a floor -- a black base, a saturated cyan
    grid at full value and `q3map_surfacelight 320` beneath it -- and the plaza's
    koi pool read as an overexposed screen, washing the whole plaza cyan.  It is a
    *pool*: almost all of it is deep water with almost no light in it, and the light
    it shows is the sky and the signage above it, broken up by ripples.  The grid
    that stays is the tile joint of the pool floor, seen through 40 units of water,
    so it is a quarter as bright as the ripples and half as frequent.

    Every term is a cosine of a whole number of cycles: a radial field has no period,
    and tiled 2x2 the old radial version became a starburst with black corners.
    """
    x, y = axes(size)
    u, v = x / float(size), y / float(size)
    ripples = (np.sin(u * 2.0 * math.pi * 9 + 1.7) + np.sin(v * 2.0 * math.pi * 11 + 0.4)
               + np.sin((u + v) * 2.0 * math.pi * 7 + 2.1)
               + np.sin((u - v) * 2.0 * math.pi * 5 + 0.9)) / 4.0
    caustic = np.clip((ripples - 0.42) * 2.6, 0.0, 1.0) ** 1.6
    swirl = np.clip((fbm(size, 5, 7, seed, 1.0, 1.9) - 0.45) * 2.0, 0.0, 1.0)
    cycles = max(2, int(spec.get('cycles', 6)))
    joint_u = np.clip(1.0 - np.abs((x % (size // cycles)) - size / float(2 * cycles))
                      / (size * 0.0045), 0.0, 1.0)
    joint_v = np.clip(1.0 - np.abs((y % (size // cycles)) - size / float(2 * cycles))
                      / (size * 0.0045), 0.0, 1.0)
    floor = np.clip(np.maximum(joint_u, joint_v) * 0.22, 0.0, 1.0)
    deep = np.array([0.012, 0.040, 0.049], np.float32)
    albedo = np.repeat(deep[None, None, :], size * size, axis=0).reshape(size, size, 3)
    sky_here = 0.55 + 0.45 * np.clip(np.sin(v * 2.0 * math.pi * 2 + 0.3), 0.0, 1.0)
    albedo = put(albedo, caustic * 0.85 * sky_here, np.array([0.26, 0.66, 0.72], np.float32))
    albedo = put(albedo, swirl * 0.30, np.array([0.055, 0.115, 0.130], np.float32))
    albedo = put(albedo, floor * (0.5 + 0.5 * swirl), np.array([0.055, 0.130, 0.140], np.float32))
    flecks = np.clip((fbm(size, 6, 130, seed + 3, 1.0, 3.0) - 0.72) * 3.4, 0.0, 1.0)
    albedo = put(albedo, flecks * 0.75, np.array([0.55, 0.88, 0.92], np.float32))
    height = np.clip(0.30 + 0.55 * caustic + 0.25 * swirl - 0.10 * floor, 0.0, 1.0)
    # A pool gives back a little of what it is given; it is not one of the lamps.
    return albedo, height, {'glow': np.clip(albedo * 0.35, 0.0, 1.0)}

# --------------------------------------------------------------------------- #
# the sky
#
# `q3map_skyLight` integrates the six faces into the arena's ambient light, so the
# sky is not decoration: the shipped set was a flat magenta void with a pinwheel on
# `dn`, and that magenta was every surface's base colour.  The panorama is built in
# elevation bands, which is the coordinate the cube reprojection samples, and both
# poles are forced azimuthally uniform -- a cube's `up`/`dn` face magnifies the last
# rows of an equirect without limit, so any structure there becomes a smudge at the
# zenith, which is exactly what the previous build showed.
# --------------------------------------------------------------------------- #
def dusk_panorama(width, height, spec):
    """-> the equirect dusk sky in 0..1, row 0 at the zenith.

    Row order follows `neural_textures.cube_face`: elevation = (0.5 - row / height)
    * pi, so row 0 is +90 degrees and the last row is the nadir.
    """
    rows = (np.arange(height) + 0.5) / height
    degrees = (0.5 - rows) * 180.0
    columns = (np.arange(width) + 0.5) / width
    azimuth = (columns * 2.0 - 1.0) * math.pi
    position = np.repeat(np.clip(rows, 0.0, 1.0)[:, None], width, axis=1)
    colour = ramp(position, [(0.0, np.array(spec['zenith'], np.float32)),
                             (0.5 - 0.06, np.array(spec['mid'], np.float32)),
                             (0.5 - 0.012, np.array(spec['upper_horizon'], np.float32)),
                             (0.5, np.array(spec['horizon'], np.float32)),
                             (0.5 + 0.02, np.array(spec['ground_near'], np.float32)),
                             (1.0, np.array(spec['nadir'], np.float32))])

    # The city's light dome: a dominant hotspot and a weaker one opposite, strongest
    # at the horizon and gone by 25 degrees.  Without it the horizon is a uniform
    # stripe, which is the most synthetic thing a skybox does.
    extinction = np.clip(degrees / 45.0, 0.0, 1.0) ** 0.8
    for index, (centre, strength, tint) in enumerate(spec['glow']):
        spread = math.radians(spec['glow_spread'][index])
        dome = np.exp(-(((azimuth - centre) / spread) ** 2))
        band = np.exp(-((degrees / spec['glow_width'][index]) ** 2))
        colour = colour + ((dome[None, :, None] * band[:, None, None] * strength * extinction[:, None, None])
                           * np.array(tint, np.float32)[None, None, :])

    # Cirrus: stretched periodic noise between 4 and 42 degrees, tinted by the light
    # it silhouettes against instead of painted white.
    square = fbm(min(width, height), 5, 4, spec.get('seed', 0) + 3, 9.0, 2.4)
    clouds = np.asarray(Image.fromarray((square * 255).astype(np.uint8)).resize((width, height),
                                                                               Image.BILINEAR),
                        np.float32) / 255.0
    band = np.clip((degrees - 4.0) / 10.0, 0.0, 1.0) * np.clip((42.0 - degrees) / 18.0, 0.0, 1.0)
    cloud = np.clip((clouds - 0.52) * 2.6, 0.0, 1.0) * band[:, None] * float(spec.get('clouds', 0.5))
    tint = np.array(spec.get('cloud_tint', (1.12, 1.04, 1.00)), np.float32)
    colour = colour * (1.0 - cloud[..., None]) + multiply(colour, tint) * cloud[..., None]

    # Stars: above 12 degrees only, thinned by extinction, brightness cubed so most
    # stay faint.  Drawn in panorama space, which compresses them towards the
    # horizon -- the correct behaviour for a 2:1 equirect.
    rng = np.random.default_rng(spec.get('seed', 0) + 7)
    chance = np.clip((degrees - 12.0) / 78.0, 0.0, 1.0)
    span = max(1, int(height * 0.0012))
    for _ in range(int(spec.get('stars', 1200))):
        row = int(rng.integers(0, height))
        if chance[row] <= 0.01 or float(rng.random()) > chance[row]:
            continue
        column = int(rng.integers(0, width))
        brightness = float(rng.random()) ** 3 * float(spec.get('star_gain', 0.80))
        window = colour[max(0, row - span):row + span + 1, max(0, column - span):column + span + 1]
        colour[max(0, row - span):row + span + 1, max(0, column - span):column + span + 1] = \
            np.maximum(window, brightness * np.array([0.90, 0.93, 1.00], np.float32))
    colour = city_band(colour, width, height, degrees, spec)

    # Poles: the last rows become their own azimuthal mean, so neither the zenith
    # nor the nadir can resolve structure and the cube's top and bottom faces are
    # guaranteed gradient-only.
    for rows_to_flat, at_end in ((int(height * 0.055), False), (int(height * 0.075), True)):
        flat = colour.mean(axis=1, keepdims=True)
        weight = np.linspace(0.0, 1.0, rows_to_flat)[:, None, None]
        if at_end:
            colour[-rows_to_flat:] = colour[-rows_to_flat:] * weight[::-1] + \
                flat[-rows_to_flat:] * (1.0 - weight[::-1])
        else:
            colour[:rows_to_flat] = colour[:rows_to_flat] * weight + flat[:rows_to_flat] * (1.0 - weight)
    return np.clip(colour, 0.0, 1.0).astype(np.float32)

def city_band(colour, width, height, degrees, spec):
    """-> the panorama with a wrap-exact layered skyline sitting on the horizon.

    Towers are drawn column-by-column rather than from the equirect's own grid, so
    the 360-degree join cannot cut a building in half, and every window is a solid
    block: a cube face at 1024 samples 1024 columns of a 4096-wide panorama, so a
    one-pixel window would vanish half the time.
    """
    horizon = int(np.argmin(np.abs(degrees)))
    city = spec['city']
    rng = np.random.default_rng(spec.get('seed', 0) + 11)
    layers = city['layers']
    for layer_index, layer in enumerate(layers):
        depth = (layer_index + 1) / float(len(layers))
        body = np.array(layer['body'], np.float32)
        for _ in range(int(layer['count'])):
            half_width = rng.uniform(*layer['width']) * width
            tower = rng.uniform(*layer['height']) * height
            column = int(rng.uniform(0, width))
            top = max(0, horizon - int(tower))
            left, right = int(column - half_width) % width, int(column + half_width) % width
            bands = [(left, right)] if left < right else [(left, width), (0, right)]
            for span_left, span_right in bands:
                if span_right <= span_left:
                    continue
                colour[top:horizon, span_left:span_right] = \
                    colour[top:horizon, span_left:span_right] * (1.0 - depth) + body * depth
                windows, floors = int(layer.get('windows', 0)), int(layer.get('floors', 14))
                if not windows or top >= horizon:
                    continue
                step_x = max(2, (span_right - span_left) // windows)
                step_y = max(3, (horizon - top) // floors)
                columns = (span_right - span_left - step_x) // step_x
                rows_count = (horizon - top - step_y) // step_y
                if columns < 1 or rows_count < 1:
                    continue
                lit = rng.random((rows_count, columns)) < float(layer.get('lit', 0.15))
                warm = rng.random((rows_count, columns)) < float(layer.get('warm_share', 0.8))
                gain = rng.uniform(0.30, 1.0, (rows_count, columns))
                warm_tone = np.array(layer.get('warm', (1.0, 0.80, 0.52)), np.float32)
                cool_tone = np.array(layer.get('cool', (0.45, 0.80, 0.95)), np.float32)
                for row_index in range(rows_count):
                    row_y = top + (row_index + 1) * step_y
                    for column_index in range(columns):
                        if not lit[row_index, column_index]:
                            continue
                        column_x = span_left + (column_index + 1) * step_x - step_x // 2
                        tone = (warm_tone if warm[row_index, column_index] else cool_tone) * gain[
                            row_index, column_index]
                        colour[row_y:row_y + max(1, step_y // 2),
                               column_x:column_x + max(1, step_x // 2)] = tone
    # (rows, 1, 1): the haze is a function of elevation only, and the colour it
    # sits on is (rows, columns, rgb).
    haze = np.exp(-((degrees / float(city.get('haze_band', 6.0))) ** 2))[:, None, None]
    strength = float(city.get('haze', 0.45))
    colour = colour * (1.0 - strength * haze) + np.array(city.get('haze_tint', (0.30, 0.26, 0.38)),
                                                         np.float32) * (strength * haze)
    ground = np.clip((-degrees - 1.0) / 12.0, 0.0, 1.0)[:, None, None]   # rgb on top
    colour = colour * (1.0 - ground) + np.array(city.get('ground', (0.010, 0.011, 0.017)),
                                                np.float32) * ground
    return colour

def sky_cube(panorama, size, supersample=2):
    """-> the six cube faces, sampled without ever wrapping across a pole.

    `neural_textures.panorama_face` samples rows with `grid-wrap`, which folds the
    nadir onto the zenith and is what smeared the skyline into a pinwheel on `dn`.
    Padding the panorama with its own edges horizontally and clamping vertically
    keeps the ring seamless and the poles stable.
    """
    from scipy.ndimage import map_coordinates
    height, width = panorama.shape[:2]
    pad = 4
    padded = np.concatenate([panorama[:, -pad:], panorama, panorama[:, :pad]], axis=1)
    padded = np.pad(padded, ((pad, pad), (0, 0), (0, 0)), mode='edge')
    faces = {}
    for side in nt.CUBE_SIDES:
        elevation, azimuth = nt.cube_face(side, size * supersample)
        rows = (0.5 - elevation / math.pi) * height + pad
        columns = (azimuth / (2.0 * math.pi) + 0.5) * width + pad
        face = np.empty((size * supersample, size * supersample, 3), np.float32)
        for channel in range(3):
            face[..., channel] = map_coordinates(padded[..., channel], [rows, columns], order=1,
                                                mode='nearest')
        faces[side] = nt.resample((np.clip(face, 0.0, 1.0) * 255.0).round().astype(np.uint8), size)
    return faces

def sky_ambient(panorama):
    """-> the cos-weighted mean colour, i.e. what `q3map_skyLight` integrates.

    Printed by `--sky` and quoted in PROVENANCE.md: the arena's ambient colour is a
    consequence of this image, so it has to be checkable without a rebuild.
    """
    height = panorama.shape[0]
    rows = (np.arange(height) + 0.5) / height
    # (rows, 1, 1) so the elevation weight reaches every column and every
    # channel; the divisor then collapses to the one scalar it was meant to be.
    weight = (np.cos((0.5 - rows) * math.pi) ** 2)[:, None, None]
    # `weight` is (rows, 1, 1): it never reaches the columns, so the divisor for a
    # sum over (rows, columns) is the row weight summed once per column.  Without
    # the width factor the printed ambient was the true one times the panorama
    # width, which is why the hint beside it read as nonsense (0.008 for a sky
    # whose real cos-weighted mean luminance was 0.03).
    divisor = float(weight.sum(axis=(0, 1))[0]) * panorama.shape[1]
    return ((panorama * weight).sum(axis=(0, 1)) / divisor).astype(np.float32)


# --------------------------------------------------------------------------- #
# the street kit: what a 2017 night street is actually surfaced with
# --------------------------------------------------------------------------- #
# Every long wall in this arena used to wear one of two materials --
# `concrete_panel`, whose motif is a 128-unit panel with four tie holes and is
# therefore three storeys of wall per repeat, or `tower_front`, whose motif is a
# whole curtain-wall bay at 512 units per repeat.  Neither of those is a surface a
# pedestrian can reach out and touch: a shopfront is tile, plaster, timber slats,
# a corrugated shutter and a painted board, and the eye that walks past them reads
# the *pitch* of the pattern, not its grain.  These eight painters exist to give
# the level's kit parts a pitch at hand scale, and they are built the same way the
# first twenty are: draw the structure, derive the height from it, and let the
# specular stage inherit the painter's own statement about which parts are wet.
#
# One rule is specific to this block and is worth keeping: a coordinate array is
# fetched and used in the same breath, and fetched again for the next block.  C++
# reason given in `_image_pair`: the numpy this map is painted with has been seen
# to hand a live array's buffer to a temporary derived from it, and a painter that
# keeps `x` across half a page then computes its grout from whatever `x` now holds.

def _image_pair(name, albedo, height):
    """-> the (albedo, height) pair, having refused anything that is not an image.

    A painter's failure mode is not an exception: a mask that lost a fight with a
    temporary is still a float array, and it ships as a tile that is either flat or
    made of somebody else's numbers.  Two cheap facts are enough to catch that --
    an albedo that is *finite* and *not flat* (every material in this file draws a
    grain, a joint or a stroke, so a spread under 0.01 is a field that got
    overwritten rather than a deliberately plain surface), and a height field that
    actually spans a tenth of its range.  The names are reported, not the numbers,
    because the numbers are what `--check-seams` and the contact sheet are for.
    """
    for label, field in (('albedo', albedo), ('height', height)):
        if not np.isfinite(field).all():
            raise ValueError('paint_%s: %s is not finite' % (name, label))
    spread = float((albedo @ LUMA).std())
    if spread < 0.010:
        raise ValueError('paint_%s: albedo luma spread %.4f -- a field was '
                         'overwritten, not painted' % (name, spread))
    if float(height.max()) - float(height.min()) < 0.10:
        raise ValueError('paint_%s: height spans %.4f, which draws no relief at all'
                         % (name, float(height.max()) - float(height.min())))
    return albedo, height


def _glyph_cell(size, glyph, box, stroke=0.10):
    """-> one glyph's stroke mask, scaled into `box` (tile fractions) on a full canvas.

    `kana_plane` draws one glyph across the whole tile, which is right for a
    single-sign tile and useless for a row of them: squeezing the canvas horizontally
    and then resizing it back restores the original.  So the glyph is resampled to the
    cell's own pixel box and pasted where the cell sits, which is also what keeps the
    lettering inside the plate's margin instead of running under the frame.
    """
    x0, y0, x1, y1 = (max(0, min(size - 1, int(size * f))) for f in box)
    width, height = max(1, x1 - x0), max(1, y1 - y0)
    plane = kana_plane(size, glyph, stroke)
    image = Image.fromarray((np.clip(plane, 0.0, 1.0) * 255.0).astype(np.uint8))
    image = image.resize((width, height), Image.BILINEAR)
    canvas = Image.new('L', (size, size), 0)
    canvas.paste(image, (x0, y0))
    return np.asarray(canvas, np.float32) / 255.0


def _divisor_count(size, wanted, label='cells'):
    """-> the nearest divisor of `size` to `wanted`, so the grid wraps.

    A pitch that does not divide the tile cannot be seamless, whatever the
    painter does around it: `pitch = size / cells` puts the last cell of every row
    at a fraction of a cell from the border, so the grout line that closes the
    row on the far side is a different width from the one that opens it on this
    side, and the per-cell tone lookup lands on a different cell across the seam.
    `tile_cream` measured a wrap step nine times its interior gradient for exactly
    this reason at cells=8, rows=10 on a 512 tile -- 10 does not divide 512.
    Snapping the count is one integer, and it keeps the *pitch* within a few
    percent of what the recipe asked for instead of silently redrawing the motif.
    """
    wanted = max(1, int(wanted))
    best, cost = 1, None
    for candidate in range(1, size + 1):
        if size % candidate:
            continue
        here = abs(candidate - wanted) / float(wanted)
        if cost is None or here < cost:
            best, cost = candidate, here
    return best


def _joint_field(size, pitch_x, pitch_y, width):
    """-> the grout/mortar mask of a `pitch_x` by `pitch_y` grid, fetched fresh.

    Shared because four of these painters need the same thing and each of them had to
    be written against a live `x`/`y`: the coordinates are created here and die here.
    """
    x, y = axes(size)
    u = np.minimum(x % pitch_x, pitch_x - x % pitch_x)
    v = np.minimum(y % pitch_y, pitch_y - y % pitch_y)
    del x, y
    return np.clip(1.0 - np.minimum(u, v) / (min(pitch_x, pitch_y) * width), 0.0, 1.0) ** 1.25


def paint_plaster(size, spec, seed):
    """Lime plaster over blockwork: sand, trowel swirls, thin patches, sill staining.

    Plaster has no panel joints at all, so nothing in this tile may march on a
    straight grid except the one thing that genuinely does: the drip line under every
    sill course, keyed to `y % course` so the tile wraps and the staining arrives once
    per storey instead of once per tile height.
    """
    courses = max(1, int(spec.get('courses', 2)))
    sand = fbm(size, 6, 48, seed, 1.0, 3.1)
    trowel = fbm(size, 4, 7, seed + 1, 4.0, 2.0)
    swath = fbm(size, 2, 2, seed + 7, 1.0, 1.8)
    albedo = np.repeat((0.52 + 0.14 * (sand - 0.5) + 0.17 * (trowel - 0.5))[..., None], 3, axis=2)
    albedo = multiply(albedo, 0.84 + 0.32 * swath)
    thin = np.clip((fbm(size, 5, 90, seed + 2, 1.0, 3.4) - 0.63) * 4.0, 0.0, 1.0)
    albedo = put(albedo, thin * 0.55, (0.30, 0.275, 0.245))      # aggregate through the coat
    height = np.clip(0.58 + 0.20 * sand, 0.0, 1.0)
    rng = rng_for('plaster', seed)
    patches = Mask(size)
    for _ in range(int(spec.get('patches', 2))):
        width, depth = size * rng.uniform(0.14, 0.30), size * rng.uniform(0.10, 0.22)
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        patches.polygon([(cx - width / 2, cy - depth / 2), (cx + width / 2, cy - depth * 0.44),
                         (cx + width * 0.46, cy + depth / 2), (cx - width / 2, cy + depth * 0.47)],
                        255, pad=max(width, depth))
    albedo = put(albedo, patches.plane() * 0.70, (0.60, 0.565, 0.505))
    cracks = Mask(size)
    for _ in range(int(spec.get('cracks', 3))):
        anchor = rng.uniform(0, size)
        points = [(anchor + rng.uniform(-size * 0.03, size * 0.03), row)
                  for row in range(-size // 12, size + size // 12, max(1, size // 24))]
        cracks.stroke(points, 255, width=max(1, size // 512))
    crack = cracks.plane()
    albedo = put(albedo, crack * 0.70, (0.24, 0.22, 0.20))
    height = np.clip(height - 0.34 * crack, 0.0, 1.0)
    x, y = axes(size)                                            # used once, then dropped
    course = size / float(courses)
    v = y % course
    drip = np.clip(1.0 - np.abs(v - course * 0.05) / (course * 0.024), 0.0, 1.0)
    del x, y
    fans = np.clip((fbm(size, 4, 26, seed + 11, 40.0, 2.2) - 0.50) * 2.4, 0.0, 1.0)
    # A hump, not a ramp.  `v / (course * 0.5)` is bright at the sill and dark
    # half a course below it, and since the courses divide the tile the sill sits on
    # the wrap: the tile therefore closed with a hard step from stained to clean,
    # which the eye reads as a bar every storey.  Weathering starts *at* the drip,
    # is worst mid-course, and is washed clean again by the next sill.
    wash = np.clip(np.sin(np.pi * v / course), 0.0, 1.0) ** 1.3
    albedo = multiply(albedo, 1.0 - 0.22 * wash)
    albedo = put(albedo, np.clip(drip + fans * wash, 0.0, 1.0) * 0.50, (0.205, 0.175, 0.150))
    height = np.clip(height - 0.16 * drip, 0.0, 1.0)
    return *_image_pair('plaster', albedo, height), {'spec': -0.5 * wash - 0.35 * thin}


def paint_tile(size, spec, seed):
    """Ceramic wall tiles on grey grout, with the odd chipped corner and a glaze sweep.

    `brick_deep` is this same painter with the grid turned to 2:1 and a rust tint:
    facing brick and facing tile are the same wall system read at two pitches.
    """
    cells = _divisor_count(size, spec.get('cells', 8))
    rows = _divisor_count(size, spec.get('rows', 10))
    pitch_x, pitch_y = size / float(cells), size / float(rows)
    tones = cell_random(rows, cells, seed)
    xg, yg = axes(size)
    tone = tones[(np.floor(yg / pitch_y).astype(int)) % rows,
                 (np.floor(xg / pitch_x).astype(int)) % cells]
    del xg, yg
    glaze = fbm(size, 5, 90, seed, 1.0, 3.2)
    xs, ys = axes(size)
    sweep = periodic_sweep(size, xs, ys, cycles_y=2)
    del xs, ys
    face = 0.55 + 0.14 * (tone - 0.5) + 0.12 * (glaze - 0.5) + 0.10 * (sweep - 0.5)
    albedo = np.repeat(face[..., None], 3, axis=2)
    joint = _joint_field(size, pitch_x, pitch_y, float(spec.get('grout', 0.06)))
    albedo = put(albedo, joint * 0.90, (0.155, 0.150, 0.148))
    rng = rng_for('tile', seed)
    chips = Mask(size)
    for _ in range(int(spec.get('chip', 6))):
        radius = min(pitch_x, pitch_y) * rng.uniform(0.12, 0.30)
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        chips.box('ellipse', (cx - radius, cy - radius, cx + radius, cy + radius), 255,
                  pad=radius * 2)
    chip = np.clip(chips.plane() * np.clip((fbm(size, 5, 60, seed + 5, 1.0, 2.4) - 0.45) * 2.6,
                                           0.0, 1.0), 0.0, 1.0)
    albedo = put(albedo, chip * 0.80, (0.235, 0.220, 0.200))
    height = np.clip(0.72 * (1.0 - joint ** 0.7) + 0.12 * tone + 0.08 * glaze - 0.28 * chip,
                     0.0, 1.0)
    return *_image_pair('tile', albedo, height), \
        {'spec': 0.55 * (1.0 - joint) * (0.4 + 0.6 * sweep) - 0.5 * chip}


def paint_slat(size, spec, seed):
    """Timber slats and louvres: a board, the open shadow reveal under it, knots, bow."""
    slats = _divisor_count(size, spec.get('slats', 8))
    pitch = size / float(slats)
    grain = fbm(size, 6, 14, seed, 34.0, 2.4)                   # stretched along x, like grain
    fine = fbm(size, 5, 70, seed + 2, 60.0, 3.0)
    _, yv = axes(size)
    index = np.floor(yv / pitch).astype(int) % slats
    del yv
    board = 0.46 + 0.20 * (grain - 0.5) + 0.10 * (fine - 0.5)
    albedo = np.repeat(board[..., None], 3, axis=2)
    albedo = multiply(albedo, 0.86 + 0.28 * cell_random(slats, 1, seed)[:, 0][index])
    _, yv = axes(size)
    # The shadow reveal is drawn as a *distance to the nearest board line*, not as
    # a ramp down from it: `1 - (y % pitch) / gap` exists only below the line, so a
    # line on the tile border -- which is what a dividing slat count puts it at --
    # arrives as a hard step from board to shadow across the wrap (measured 4.4x the
    # interior gradient on `slat_timber`).  Measured to the nearest line, half the
    # reveal sits either side of it, which is also what an open joint actually is.
    to_line = np.minimum(yv % pitch, pitch - yv % pitch)
    reveal = np.clip(1.0 - to_line / (pitch * float(spec.get('gap', 0.18)) * 0.5),
                     0.0, 1.0) ** 0.8
    del yv
    albedo = put(albedo, reveal * 0.92, (0.040, 0.031, 0.023))
    rng = rng_for('slat', seed)
    knots = Mask(size)
    for _ in range(int(spec.get('knots', 5))):
        radius = pitch * rng.uniform(0.10, 0.22)
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        knots.box('ellipse', (cx - radius * 1.7, cy - radius, cx + radius * 1.7, cy + radius),
                  255, pad=radius * 3)
    albedo = put(albedo, knots.plane() * 0.75, (0.185, 0.125, 0.080))
    weather = np.clip((fbm(size, 3, 3, seed + 8, 1.0, 1.9) - 0.58) * 2.6, 0.0, 1.0)
    albedo = put(albedo, weather * 0.30, (0.150, 0.135, 0.120))
    height = np.clip(0.62 + 0.16 * grain + 0.06 * fine - 0.55 * reveal, 0.0, 1.0)
    return *_image_pair('slat', albedo, height), \
        {'spec': 0.30 * (1.0 - reveal) * (1.0 - weather) - 0.25 * weather}


def paint_shutter(size, spec, seed):
    """A roller shutter: corrugated laths, a rust belt, a tag, and a lock band.

    The closed shopfront is the most common wall on a Japanese shopping street after
    twenty hours, and it is the one surface here that is *ribbed*: its specular is a
    saw of bright lines every lath, which is what a flat placeholder panel cannot fake
    and what makes a lane read as shops rather than as a car park.
    """
    bands = _divisor_count(size, spec.get('bands', 16))
    pitch = size / float(bands)
    dirt = fbm(size, 4, 8, seed, 20.0, 2.0)
    _, yv = axes(size)
    ridge = np.sin(np.pi * ((yv % pitch) / pitch)) ** 0.7
    albedo = np.repeat((0.34 + 0.24 * ridge + 0.12 * (dirt - 0.5))[..., None], 3, axis=2)
    joint = np.clip(1.0 - np.minimum(yv % pitch, pitch - yv % pitch) / (pitch * 0.055),
                    0.0, 1.0) ** 1.2
    del yv
    albedo = put(albedo, joint * 0.88, (0.055, 0.058, 0.066))
    rust = np.clip(band_field(size, size * 0.5, size * float(spec.get('rust', 0.24)), 'y')
                   * np.clip((fbm(size, 5, 24, seed + 3, 1.0, 2.6) - 0.45) * 2.6, 0.0, 1.0),
                   0.0, 1.0)
    albedo = put(albedo, rust * 0.85, (0.155, 0.072, 0.044))
    rng = rng_for('shutter', seed)
    tag = Mask(size)
    origin_x, origin_y = rng.uniform(0, size), rng.uniform(0, size)
    tag.stroke([(origin_x + step * size * 0.055,
                 origin_y + size * 0.06 * math.sin(step * 1.7) * rng.uniform(0.6, 1.4))
                for step in range(9)], 255, width=max(2, int(size * 0.016)))
    tag_colour = np.array(spec.get('tag', (0.42, 0.10, 0.44)), np.float32)
    albedo = put(albedo, tag.plane() * 0.70, tag_colour)
    grime = np.clip((fbm(size, 4, 5, seed + 9, 1.0, 1.9) - 0.60) * 2.8, 0.0, 1.0)
    albedo = put(albedo, grime * 0.35, (0.060, 0.060, 0.062))
    height = np.clip(0.44 + 0.50 * ridge - 0.42 * joint - 0.14 * rust, 0.0, 1.0)
    return *_image_pair('shutter', albedo, height), \
        {'spec': 0.55 * ridge * (1.0 - rust) - 0.45 * rust - 0.2 * grime}


def paint_sign(size, spec, seed):
    """A sign face: a plate, a frame, lettering that survives being cropped, and wear.

    Signage in this arena was a flat emissive quad, tiled edge to edge, which is how a
    kanji composition arrives as pink confetti (DESIGN.md section 5).  Three things fix
    it without a diffusion model: an inset (the letters keep a margin), one glyph per
    cell (so a crop shows one letter and not half of three), and a frame with screws in
    it, because a plate is bolted to something and the eye looks for the bolts.
    `weave` turns the same plate into a cloth banner and `arrow` puts a chevron on it
    for the transit wayfinding plates.
    """
    glyphs = list(spec.get('glyphs') or ('ka', 'shi'))
    orient = spec.get('orient', 'h')
    face = np.array(spec.get('face', (0.88, 0.30, 0.44)), np.float32)
    border = np.array(spec.get('border', (0.72, 0.66, 0.30)), np.float32)
    background = np.array(spec.get('bg', (0.050, 0.022, 0.032)), np.float32)
    albedo = np.zeros((size, size, 3), np.float32) + background
    glow = np.zeros((size, size, 3), np.float32)
    height = np.full((size, size), 0.30, np.float32)
    weave = int(spec.get('weave', 0))
    if weave:
        xw, yw = axes(size)
        cloth = 0.5 * (0.5 + 0.5 * np.sin(xw / float(size) * 2.0 * math.pi * weave)) \
            + 0.5 * (0.5 + 0.5 * np.sin(yw / float(size) * 2.0 * math.pi * weave))
        del xw, yw
        albedo = multiply(albedo, 0.84 + 0.24 * cloth)
        height = np.clip(height + 0.06 * (2.0 * cloth - 1.0), 0.0, 1.0)
    albedo = multiply(albedo, 0.90 + 0.20 * fbm(size, 4, 4, seed, 1.0, 2.0))
    inset = float(spec.get('inset', 0.14))
    count = max(1, len(glyphs))
    span = 0.90 / count
    for index, glyph in enumerate(glyphs):
        start, pad = 0.05 + index * span, span * inset
        if orient == 'v':
            box = (0.10 + pad, start + pad, 0.90 - pad, start + span - pad)
        else:
            box = (start + pad, 0.10 + pad, start + span - pad, 0.90 - pad)
        strokes = np.clip(gaussian_filter(_glyph_cell(size, glyph, box,
                                                      stroke=float(spec.get('stroke', 0.10))),
                                          max(1.0, size * 0.0035), mode='wrap'), 0.0, 1.0)
        albedo = put(albedo, strokes, face)
        glow = np.clip(glow + strokes[..., None] * face * float(spec.get('lum', 1.0)), 0.0, 1.0)
        height = np.clip(height + 0.28 * strokes, 0.0, 1.0)
    if spec.get('arrow'):
        chevron = Mask(size)
        for step in range(3):
            base = size * (0.12 + step * 0.16)
            chevron.polygon([(base, size * 0.34), (base + size * 0.10, size * 0.50),
                             (base, size * 0.66), (base + size * 0.035, size * 0.66),
                             (base + size * 0.135, size * 0.50), (base + size * 0.035, size * 0.34)],
                            255, pad=size * 0.15)
        albedo = put(albedo, chevron.plane() * 0.92, face)
        glow = np.clip(glow + chevron.plane()[..., None] * face * 0.9, 0.0, 1.0)
    rng = rng_for('sign-rule', seed)
    rule = Mask(size)
    for step in range(int(spec.get('rules', 3))):
        row = size * (0.80 + step * 0.055)
        rule.stroke([(size * rng.uniform(0.08, 0.20), row), (size * rng.uniform(0.62, 0.92), row)],
                    255, width=max(1, int(size * 0.010)))
    albedo = put(albedo, rule.plane() * 0.80, face * 0.72)
    glow = np.clip(glow + rule.plane()[..., None] * face * 0.55, 0.0, 1.0)
    frame = Mask(size)
    frame.box('rect', (size * 0.015, size * 0.015, size * 0.985, size * 0.985), 255)
    frame.box('rect', (size * 0.048, size * 0.048, size * 0.952, size * 0.952), 0)
    albedo = put(albedo, frame.plane() * 0.92, border)
    glow = np.clip(glow + frame.plane()[..., None] * border * 0.25, 0.0, 1.0)
    height = np.clip(height + 0.20 * frame.plane(), 0.0, 1.0)
    screws = Mask(size)
    for cx, cy in ((0.075, 0.075), (0.925, 0.075), (0.075, 0.925), (0.925, 0.925)):
        radius = size * 0.016
        screws.box('ellipse', (cx * size - radius, cy * size - radius,
                               cx * size + radius, cy * size + radius), 255, pad=radius * 2)
    albedo = put(albedo, screws.plane() * 0.9, border * 0.55)
    scratches = np.clip((fbm(size, 4, 60, seed + 5, 40.0, 2.3) - 0.72) * 4.0, 0.0, 1.0)
    albedo = put(albedo, scratches * 0.25, (0.10, 0.09, 0.095))
    return *_image_pair('sign', albedo, height), {'glow': glow, 'spec': 0.30 * (1.0 - scratches)}


def paint_poster(size, spec, seed):
    """A wall papered over: overlapping flyers, tape, and print that resolves as tone.

    One material that reads as *many* posters, because the kit puts it on a recessed
    bay and a bay cannot carry twelve brushes.  Every sheet is a quadrilateral drawn
    through the wrap seam, and each carries a headline bar over three to six thin bars:
    at the distance a poster wall is actually seen, print is a band of dark tone, and a
    sheet without that band is a blank card.
    """
    paper = fbm(size, 5, 60, seed, 1.0, 2.9)
    albedo = np.repeat((0.40 + 0.14 * (paper - 0.5))[..., None], 3, axis=2)
    height = np.full((size, size), 0.30, np.float32)
    rng = rng_for('poster', seed)
    for _ in range(int(spec.get('sheets', 7))):
        width = size * rng.uniform(0.18, 0.42)
        depth = size * rng.uniform(0.24, 0.50)
        cx, cy = rng.uniform(0, size), rng.uniform(0, size)
        skew = rng.uniform(-0.12, 0.12)
        corners = [(cx - width / 2, cy - depth / 2), (cx + width / 2, cy - depth / 2 * (1 + skew)),
                   (cx + width / 2 * (1 - skew), cy + depth / 2), (cx - width / 2, cy + depth / 2)]
        sheet = Mask(size)
        sheet.polygon(corners, 255, pad=max(width, depth))
        cover = sheet.plane()
        tone = rng.uniform(0.36, 0.68)
        tint = np.array([tone * rng.uniform(0.86, 1.06), tone * rng.uniform(0.84, 1.02),
                         tone * rng.uniform(0.74, 0.98)], np.float32)
        albedo = put(albedo, cover * 0.90, tint)
        height = np.clip(height + 0.10 * cover, 0.0, 1.0)
        print_mask = Mask(size)
        print_mask.stroke([(cx - width * 0.34, cy - depth * 0.30),
                           (cx + width * rng.uniform(0.10, 0.36), cy - depth * 0.30)], 255,
                          width=max(2, int(size * rng.uniform(0.030, 0.055))))
        for line in range(3 + int(rng.random() > 0.5)):
            row = cy - depth * 0.12 + line * depth * 0.13
            print_mask.stroke([(cx - width * 0.34, row),
                               (cx + width * rng.uniform(-0.05, 0.36), row)], 255,
                              width=max(1, int(size * 0.011)))
        albedo = put(albedo, np.clip(print_mask.plane() * cover, 0.0, 1.0) * 0.85, tint * 0.22)
        tape = Mask(size)
        for corner_x, corner_y in (corners[0], corners[2]):
            tape.polygon([(corner_x - size * 0.035, corner_y - size * 0.012),
                          (corner_x + size * 0.035, corner_y - size * 0.020),
                          (corner_x + size * 0.035, corner_y + size * 0.012),
                          (corner_x - size * 0.035, corner_y + size * 0.020)], 255,
                         pad=size * 0.05)
        albedo = put(albedo, np.clip(tape.plane() * cover, 0.0, 1.0) * 0.65, (0.62, 0.60, 0.52))
    sunfade = np.clip((fbm(size, 3, 3, seed + 12, 1.0, 1.8) - 0.40) * 1.8, 0.0, 1.0)
    albedo = multiply(albedo, 1.0 - 0.22 * sunfade)
    tears = np.clip((fbm(size, 5, 80, seed + 6, 6.0, 2.4) - 0.74) * 4.2, 0.0, 1.0)
    albedo = put(albedo, tears * 0.50, (0.20, 0.185, 0.170))
    height = np.clip(height - 0.20 * tears, 0.0, 1.0)
    return *_image_pair('poster', albedo, height), {'spec': -0.4 * sunfade + 0.2 * (1.0 - paper)}


def paint_sett(size, spec, seed):
    """Court setts and tactile pavers: square units, wide joints, broom finish, domes.

    `plaza_stone` staggers its courses and was chosen for the plaza's big sawn slabs.
    A court is the opposite -- small squares on a true grid, a wide swept joint, and a
    directional broom finish that runs one way across the whole field.  `dots` adds the
    truncated domes of a tactile strip, worn brighter on their crowns because that is
    where boots take the paint off.
    """
    cells = _divisor_count(size, spec.get('cells', 6))
    rows = _divisor_count(size, spec.get('rows', cells))
    pitch_x, pitch_y = size / float(cells), size / float(rows)
    tones = cell_random(rows, cells, seed)
    xg, yg = axes(size)
    tone = tones[(np.floor(yg / pitch_y).astype(int)) % rows,
                 (np.floor(xg / pitch_x).astype(int)) % cells]
    broom = np.clip((fbm(size, 5, 12, seed + 4, 60.0, 2.6) - 0.5) * 1.4, -1.0, 1.0)
    del xg, yg
    grit = fbm(size, 6, 90, seed, 1.0, 3.3)
    swath = fbm(size, 2, 2, seed + 21, 1.0, 1.8)
    face = 0.44 + 0.22 * (tone - 0.5) + 0.14 * (grit - 0.5) + 0.10 * broom
    albedo = np.repeat(face[..., None], 3, axis=2)
    albedo = multiply(albedo, 0.84 + 0.32 * swath)
    joint = _joint_field(size, pitch_x, pitch_y, float(spec.get('mortar', 0.07)))
    albedo = put(albedo, joint * 0.88, (0.062, 0.062, 0.066))
    height = np.clip(0.70 * (1.0 - joint ** 0.7) + 0.14 * tone + 0.10 * grit, 0.0, 1.0)
    if int(spec.get('dots', 0)):
        xd, yd = axes(size)
        cx, cy = (xd % pitch_x) - pitch_x * 0.5, (yd % pitch_y) - pitch_y * 0.5
        del xd, yd
        step = min(pitch_x, pitch_y) / float(spec['dots'])
        radius = step * float(spec.get('dot_radius', 0.34))
        gx = np.abs(cx % step) - step * 0.5
        gy = np.abs(cy % step) - step * 0.5
        dome = np.clip(1.0 - (gx * gx + gy * gy) / (radius * radius), 0.0, 1.0)
        dome = np.where((np.abs(cx) < pitch_x * 0.42) & (np.abs(cy) < pitch_y * 0.42), dome, 0.0)
        crown = np.clip(dome ** 0.55, 0.0, 1.0) * (1.0 - joint)
        albedo = put(albedo, crown * 0.45, (0.72, 0.70, 0.66))
        height = np.clip(height + 0.30 * crown, 0.0, 1.0)
    wear = np.clip((fbm(size, 4, 20, seed + 9, 1.0, 2.1) - 0.62) * 3.0, 0.0, 1.0)
    albedo = put(albedo, wear * 0.30, (0.115, 0.115, 0.118))
    wet = np.clip((fbm(size, 3, 2, seed + 6, 1.0, 1.6) - 0.46) * 2.2, 0.0, 1.0)
    albedo = put(albedo, wet * 0.30, (0.030, 0.034, 0.048))
    height = np.clip(height, 0.0, 1.0)
    return *_image_pair('sett', albedo, height), {'spec': wet * (1.0 - joint) - 0.3 * wear}


def paint_road_paint(size, spec, seed):
    """Thermoplastic road paint on asphalt: a bright field, chipped edges, glass beads.

    A painted line in this map used to be `light_strip`, i.e. an emissive bar, which is
    why the crossings read as light boxes bolted to the tarmac.  Real paint is a
    *worn* film: it goes off in flakes where the tyres drag, it is embedded with beads
    that throw the headlight back, and the asphalt still owns the gaps.
    """
    grit = fbm(size, 7, 40, seed, 1.0, 2.9)
    patch = fbm(size, 3, 2, seed + 1, 1.0, 1.5)
    base = np.repeat((0.19 + 0.28 * grit)[..., None], 3, axis=2)
    base = put(base, np.clip((patch - 0.58) * 2.6, 0.0, 1.0) * 0.50, (0.075, 0.078, 0.086))
    field = spec.get('field', (0.04, 0.06, 0.96, 0.94))
    plate = Mask(size)
    plate.box('rect', (field[0] * size, field[1] * size, field[2] * size, field[3] * size), 255,
              pad=size * 0.12)
    cover = plate.plane()
    edge = np.clip(1.0 - cover * 3.0, 0.0, 1.0)              # the chipped border band
    wear = np.clip((fbm(size, 6, 26, seed + 4, 1.0, 2.4) - (0.50 - 0.30 * edge)) * 3.4, 0.0, 1.0)
    paint = np.array(spec.get('line', (0.62, 0.62, 0.58)), np.float32)
    albedo = put(base, np.clip(cover - wear, 0.0, 1.0) * 0.95, paint)
    beads = np.clip((fbm(size, 5, 150, seed + 6, 1.0, 3.4) - 0.74) * 4.4, 0.0, 1.0) * cover
    albedo = put(albedo, beads * 0.45, paint * 1.30)
    scuff = np.clip((fbm(size, 4, 20, seed + 7, 30.0, 2.1) - 0.68) * 3.4, 0.0, 1.0)
    albedo = put(albedo, scuff * cover * 0.55, (0.070, 0.070, 0.076))
    height = np.clip(0.42 + 0.52 * grit + 0.10 * (cover - wear) - 0.12 * wear, 0.0, 1.0)
    wet = np.clip((patch - 0.52) * 2.2, 0.0, 1.0)
    return *_image_pair('road_paint', albedo, np.clip(height, 0.0, 1.0)), \
        {'spec': 0.45 * beads + 0.35 * wet - 0.35 * wear}

PAINTERS = {
    'asphalt': paint_asphalt,
    'plaza_stone': paint_plaza_stone,
    'concrete_panel': paint_concrete_panel,
    'tower_front': paint_tower_front,
    'metal_deck': paint_metal_deck,
    'metal_column': paint_metal_column,
    'grate': paint_grate,
    'cloth': paint_cloth,
    'crate': paint_crate,
    'roof_gravel': paint_roof_gravel,
    'plant': paint_plant,
    'lacquer_red': paint_lacquer_red,
    'glass': paint_glass,
    'neon': paint_neon,
    'ad_board': paint_ad_board,
    'light_strip': paint_light_strip,
    'holo_pool': paint_holo_pool,
    'vend_face': paint_vend_face,
    'plaster': paint_plaster,
    'tile': paint_tile,
    'slat': paint_slat,
    'shutter': paint_shutter,
    'sign': paint_sign,
    'poster': paint_poster,
    'sett': paint_sett,
    'road_paint': paint_road_paint,
}

# --------------------------------------------------------------------------- #
# derivation: albedo + height -> the maps a shader stage can use
# --------------------------------------------------------------------------- #
def spec_map(albedo, spec, extra=None):
    """-> the specular level from albedo luminance plus a painter-supplied weight.

    `neural_textures.specular_map` decides from luminance alone, which cannot say
    "this slate is wet and this one is not" or "the hole is matte, the rim is
    polished".  The extra field is where a painter says it, in -1..1.
    """
    luminance = albedo @ LUMA
    level = float(spec.get('base', 0.10)) + float(spec.get('gain', 0.20)) * (
        1.0 - luminance) ** float(spec.get('power', 1.5))
    if extra is not None:
        level = np.clip(level + np.clip(extra, -1.0, 1.0) * float(spec.get('extra_gain', 0.30)), 0.0, 1.2)
    tint = np.array(spec.get('tint', (0.6, 0.6, 0.6)), np.float32)
    return (np.clip(level[..., None] * tint[None, None, :], 0.0, 1.0) * 255.0).astype(np.uint8)

def glow_map(albedo, glow, extras):
    """-> the additive glow: the painter's own light image if it has one, else a bright pass.

    A facade's lit windows are a designed set, so they carry their own glow image;
    a weathered wall just gets whatever clears a threshold, as before.
    """
    if extras.get('glow') is not None:
        image = extras['glow'] * float(glow.get('gain', 1.0))
        if glow.get('blur'):
            image = gaussian_filter(np.clip(image, 0.0, 1.0), glow['blur'], mode='wrap')
        return (np.clip(image, 0.0, 1.0) * 255.0).astype(np.uint8)
    return nt.glow_map((albedo * 255.0).round().astype(np.uint8), glow)

def borrow_detail(albedo, plate, amount, band=0.045):
    """-> `albedo` with a model plate's *relative microstructure* multiplied in.

    Dividing the plate by its own mean only removes its DC term, and a diffusion
    plate is never flat: it carries slow luminance swings of its own -- a bright
    quarter, a dark bloom in the middle -- which came through the division
    untouched and got painted onto the material at tile scale.  That is what the
    tiled views showed as a light column down one join and a soft vignette mid
    tile on `plaza_stone` and `asphalt`, and the seam metric could not see it,
    because a slow bright band is perfectly continuous across the wrap: it is a
    visible grid line every repeat with no discontinuity at all.

    So the plate is divided by a wrap-blurred copy of itself instead -- a
    high-pass.  Structure coarser than `band` (as a fraction of the tile) is
    removed rather than borrowed, the microstructure below it survives intact,
    and because the blur wraps, the ratio is periodic by construction.  The
    plate contributes grain and nothing else: no exposure, no palette, no
    low-frequency shape.

    This is the only place a diffusion model touches a shipped albedo.
    """
    source = plate @ LUMA
    if band:
        coarse = gaussian_filter(source, max(1.0, float(band) * source.shape[0]), mode='wrap')
        detail = source / np.clip(coarse, 1e-3, None)
    else:
        detail = source / max(float(source.mean()), 1e-3)
    detail = detail - float(detail.mean()) + 1.0
    return np.clip(albedo * (1.0 - float(amount) + float(amount) * detail[..., None]), 0.0, 1.0)

def seam_breakdown(image):
    """-> (vertical-edge, horizontal-edge) discontinuity, each over the interior.

    One number says "there is a seam" but not why, and the two causes need
    different fixes.  A material that fails only across its top/bottom rows is
    baking a gradient into a texture that wraps vertically -- a `linspace` down
    the wall is the usual culprit.  A material that fails on both axes is drawing
    features near the border without repeating them across it, so every bolt,
    plank end or leaf that touches an edge is cut in half.
    """
    sample = image.astype(np.float32)
    rows = float(np.abs(np.diff(sample, axis=0)).mean())
    cols = float(np.abs(np.diff(sample, axis=1)).mean())
    interior = max(rows + cols, 1e-6)
    vertical = float(np.abs(sample[0] - sample[-1]).mean()) / interior
    horizontal = float(np.abs(sample[:, 0] - sample[:, -1]).mean()) / interior
    return vertical, horizontal


def seam_metric(image):
    """-> the wrap discontinuity of a tile over its own interior gradient.

    Below ~1.0 means the tile edge is calmer than the average step inside the
    tile, i.e. no visible seam.  This replaces "it looks fine in the viewer".
    """
    edge = np.abs(image[0] - image[-1]).mean() + np.abs(image[:, 0] - image[:, -1]).mean()
    interior = np.abs(np.diff(image, axis=0)).mean() + np.abs(np.diff(image, axis=1)).mean()
    return float(edge / max(float(interior), 1e-6))

def build(name, recipe, seed=0, plate=None):
    """-> the suffix-keyed image set one shader needs, as uint8 arrays.

    Keys are '' for the diffuse (RGBA when the recipe asks for alpha), `_n`, `_s`
    and `_g`, exactly the names `maps/japanDM/materials.py` stages.
    """
    size = int(recipe.get('size', 512))
    albedo, height, extras = PAINTERS[recipe['paint']](size, recipe, seed)
    if plate is not None and recipe.get('plate_use') == 'content':
        # A light box's albedo IS its artwork: the plate replaces the drawn
        # composition, keeps the painter's height (a light box is still flat
        # behind the same frame), and carries its own glow, because a poster
        # lit from behind glows exactly where it is bright.
        albedo = plate[..., :3].astype(np.float32)
        extras['glow'] = np.clip(albedo * 1.10, 0.0, 1.0)
    elif plate is not None and recipe.get('grade'):
        albedo = borrow_detail(albedo, plate, float(recipe.get('grain', 0.4)))
    if recipe.get('grade'):
        albedo = grade(albedo, *recipe['grade'])
    if recipe.get('colorize') is not None:
        # Painted furniture: the painter draws an honest grey object (brushed
        # steel, woven tarp, lacquered board) and `colorize` decides which painted
        # object this material is -- a vending machine's cyan panel, a stall's red
        # shutter.  Multiplying would drop the surface back below its declared
        # albedo, so the grade is re-centred afterwards: the hue is the recipe's,
        # the brightness stays the number `grade` promised.
        # Multiplying by a tint does not change a hue, it changes a brightness:
        # `lacquer_red`'s red times `prop_paint_cyan`'s cyan is a darker red, and the
        # level shipped a salmon "cyan" and a pastel "red" for two builds.  Keep the
        # painting's luminance -- that is where its bands, bolts and scuffs live --
        # and impose the target's chroma on top of it, normalised so the material
        # arrives at the brightness the grade was asked for rather than the tint's.
        tint = np.asarray(recipe['colorize'], np.float32)
        luminance = albedo @ LUMA
        albedo = luminance[..., None] * (tint / max(float(tint @ LUMA), 1e-3))[None, None, :]
        if recipe.get('grade'):
            albedo = grade(albedo, *recipe['grade'])
    images = {'': (np.clip(albedo, 0.0, 1.0) * 255.0).round().astype(np.uint8)}
    if recipe.get('normal'):
        images['_n'] = nt.normal_map(height, float(recipe['normal']))
    if recipe.get('spec'):
        images['_s'] = spec_map(albedo, recipe['spec'], extras.get('spec'))
    if recipe.get('glow'):
        images['_g'] = glow_map(albedo, recipe['glow'], extras)
    if recipe.get('alpha'):
        level = nt.alpha_channel((size, size), recipe['alpha'], height, seed).astype(np.float32)
        if extras.get('alpha') is not None:
            level = level * np.clip(extras['alpha'], 0.0, 1.5)
        coverage = np.clip(level, 0.0, 255).round().astype(np.uint8)
        images[''] = np.concatenate([images[''], coverage[..., None]], axis=2)
    return images

# --------------------------------------------------------------------------- #
# command line
# --------------------------------------------------------------------------- #
def recipes_of(path):
    """-> the (albedo set, sky set, licences) declared by a map's `textures.py`."""
    spec = importlib.util.spec_from_file_location('dk3_map_textures', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    merged = {}
    for name, craft in module.CRAFT.items():
        base = dict(getattr(module, 'TEXTURES', {}).get(name, {}))
        base.update(craft)
        merged[name] = base
    return merged, getattr(module, 'CRAFT_SKY', None) or module.SKY, getattr(module, 'LICENCES', {})

def preview(names, images_of, path, cell=256, columns=4):
    """-> a contact sheet, because the only way to judge eighteen tiles is side by side."""
    sheet = Image.new('RGB', (columns * cell, ((len(names) + columns - 1) // columns) * (cell + 18)),
                     (18, 18, 22))
    pen = ImageDraw.Draw(sheet)
    for index, name in enumerate(names):
        image = images_of[name]['']
        tile = Image.fromarray(image[..., :3]).resize((cell, cell), Image.NEAREST)
        x, y = (index % columns) * cell, (index // columns) * (cell + 18)
        sheet.paste(tile, (x, y))
        pen.text((x + 4, y + cell + 3), name, fill=(255, 236, 120))
    sheet.save(path)
    return path

def main():
    import argparse
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--recipes', type=Path, required=True, help='map textures.py holding CRAFT/SKY')
    parser.add_argument('--out', type=Path, required=True, help='image root the map build reads')
    parser.add_argument('--dir', default=None, help='shader directory below --out (default: recipes dir name)')
    parser.add_argument('--only', default=None, help='comma list of material names')
    parser.add_argument('--sky', action='store_true', help='write the env/ cube as well')
    parser.add_argument('--force', action='store_true', help='overwrite images that already exist')
    parser.add_argument('--plate-dir', type=Path, default=None,
                        help='diffusion detail plates (see qwen_studio.py) named <material>.png')
    parser.add_argument('--check-seams', action='store_true', help='report the wrap metric and exit')
    parser.add_argument('--preview', type=Path, default=None, help='write a contact sheet as well')
    parser.add_argument('--memory-mib', type=int, default=DEFAULT_MEMORY_MIB,
                        help='address-space ceiling for the whole run (default %d; 0 keeps the '
                             'inherited limit)' % DEFAULT_MEMORY_MIB)
    arguments = parser.parse_args()
    if arguments.memory_mib:
        ceiling, _ = apply_memory_cap(arguments.memory_mib)
        print('craft-textures: address space capped at %.1f GiB' % (ceiling / 1024.0 ** 3))
    materials, sky, licences = recipes_of(arguments.recipes)
    directory = arguments.dir or arguments.recipes.parent.name.lower()
    root = arguments.out / directory
    root.mkdir(parents=True, exist_ok=True)
    wanted = [name for name in sorted(materials) if not arguments.only or name in arguments.only.split(',')]
    built, started = {}, time.time()
    for name in wanted:
        recipe = materials[name]
        plate = None
        if arguments.plate_dir is not None and (recipe.get('grade')
                                                or recipe.get('plate_use') == 'content'):
            candidate = arguments.plate_dir / ('%s.png' % name)
            if candidate.is_file():
                plate = np.asarray(Image.open(candidate).convert('RGB'), np.float32) / 255.0
                plate = np.asarray(Image.fromarray((plate * 255).astype(np.uint8)).resize(
                    (int(recipe.get('size', 512)),) * 2, Image.LANCZOS), np.float32) / 255.0
        images = build(name, recipe, seed=0, plate=plate)
        built[name] = images
    # The report flags are additive, not exclusive: a contact sheet and a seam
    # number are how a material gets judged, and judging used to mean not writing
    # the images -- so an iterating session that asked for `--check-seams` silently
    # wrote nothing and the build quietly kept shipping the previous tiles.
    if arguments.check_seams:
        print('%-16s %-7s %-7s %-7s %s' % ('material', 'seam', 'up/down', 'l/r', 'mean lum'))
        for name in wanted:
            image = built[name][''].astype(np.float32)
            vertical, horizontal = seam_breakdown(image)
            verdict = ('gradient' if max(vertical, horizontal) > 1.0
                       and min(vertical, horizontal) < 0.5 else
                       'features' if max(vertical, horizontal) > 1.0 else 'ok')
            print('%-16s %-7.3f %-7.3f %-7.3f %-8.3f %s'
                  % (name, seam_metric(image), vertical, horizontal,
                     float((image[..., :3] @ LUMA / 255.0).mean()), verdict))
    if arguments.preview:
        preview(wanted, built, arguments.preview)
        print('craft-textures: contact sheet %s' % arguments.preview)
    manifest_path = arguments.out / 'craft-textures.json'
    manifest = json.loads(manifest_path.read_text()) if manifest_path.is_file() else dict(images={})
    manifest.setdefault('derivation', dict(
        structure='drawn per material by dkq3/tools/craft_textures.py',
        normal='tangent space, Fourier derivatives of the painted height field',
        specular='albedo luminance plus the painter\u0027s per-texel wetness/scratch weight',
        licences=licences))
    for name in wanted:
        recipe = materials[name]
        for suffix, image in built[name].items():
            path = root / ('%s%s.tga' % (name, suffix))
            path.parent.mkdir(parents=True, exist_ok=True)
            dkimg.write_tga(path, np.ascontiguousarray(image))
        record = dict(paint=recipe['paint'], size=int(recipe.get('size', 512)),
                      maps=sorted(suffix or 'diffuse' for suffix in built[name]),
                      grade=recipe.get('grade'), normal=recipe.get('normal'),
                      spec=bool(recipe.get('spec')), glow=bool(recipe.get('glow')),
                      alpha=bool(recipe.get('alpha')),
                      seam={suffix or 'diffuse': round(seam_metric(built[name][suffix].astype(np.float32)), 3)
                            for suffix in built[name]},
                      sha256={suffix or 'diffuse': hashlib.sha256(image.tobytes()).hexdigest()[:16]
                              for suffix, image in built[name].items()})
        manifest['images']['%s/%s' % (directory, name)] = record
        print('craft: %-16s %s' % (name, ' '.join(sorted(suffix or 'diffuse' for suffix in built[name]))),
              flush=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')

    if arguments.sky:
        size = int(sky.get('size', 1024))
        # `panorama` is a (width, height) pair in every recipe that ships, and the
        # `int()` around it meant `--sky` had never once run: the sky cube in the
        # installed package predates this file.  A bare size still means a square.
        spec = sky.get('panorama', (4096, 2048))
        width, height = ([int(spec)] * 2 if isinstance(spec, int)
                         else [int(value) for value in spec])
        panorama = dusk_panorama(width, height, sky)
        env = arguments.out / 'env'
        env.mkdir(parents=True, exist_ok=True)
        faces = sky_cube(panorama, size)
        for side, face in faces.items():
            dkimg.write_tga(env / ('%s_%s.tga' % (directory, side)), np.ascontiguousarray(face))
        if sky.get('save_panorama'):
            dkimg.write_tga(env / ('%s_panorama.tga' % directory),
                            (np.clip(panorama, 0.0, 1.0) * 255.0).round().astype(np.uint8))
        ambient = sky_ambient(panorama)
        manifest['sky'] = dict(panorama=[width, height], size=size, sides=list(nt.CUBE_SIDES),
                               ambient=[round(float(value), 4) for value in ambient],
                               sky_light_hint=round(float(1.0 / max(ambient @ LUMA, 1e-3)), 2),
                               sha256={side: hashlib.sha256(face.tobytes()).hexdigest()[:16]
                                       for side, face in faces.items()})
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        print('craft: sky faces %d^2, ambient rgb=%s (luminance %.3f)'
              % (size, [round(float(value), 3) for value in ambient], float(ambient @ LUMA)))
    print('craft-textures: %d materials in %.0f s' % (len(wanted), time.time() - started))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
