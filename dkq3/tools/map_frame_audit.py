#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Per-frame gate numbers: how bright, how dark, and which material owns the screen.

A screenshot can be argued with; these three numbers cannot:

    mean luma       the average gray of the capture the engine drew.  Below ~0.20 a
                    night street stops being legible.  The formula is asked of
                    ImageMagick inside `map_view_probe` itself (`%[fx:mean]` on a
                    Gray-reduced copy), so the two tools cannot disagree about what
                    "dark" means -- a numpy re-implementation differs by ~0.001 on
                    the same JPEG and that is 0.4 pp of a gate.
    dark fraction   the share of pixels under 0.10 gray (`-threshold 10%`), i.e.
                    black rather than merely shadowed.  A frame can average 0.25 and
                    still be half black.  The threshold is 0.10 because that is the
                    convention this map's history was measured in: the recorded pair
                    for `lane_view_e` before/after the relight is 52 % / 34 %, and
                    this definition reproduces it as 56 % / 37 %.
    material share  which shader covers the frame, weighted by solid angle.  This
                    is the number behind "that wall is one texture from edge to
                    edge", and it can only come from geometry: a JPEG says the
                    bottom right is fish-scaled, the frustum says which surface the
                    pixels came from.  `frame_materials` in this map's patch history
                    named the wrong surface twice before it was written down.

    python3 -B dkq3/tools/map_frame_audit.py --map japanDM --report zig-out/map-dev/japanDM/probe-360
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
from pathlib import Path
import sys

import subprocess

sys.path.insert(0, str(Path(__file__).resolve().parent))
import map_sightlines
import quake_map

#: What the gate compares against.  Both numbers come from measured frames of this
#: map, not from a convention: 0.20 is where the legible captures stopped, and 0.55
#: is where `up_n` (78.5 % `grate`) and `spawn_roof_n_e` (90 % `prop_concrete`) were.
MIN_MEAN_LUMA = 0.20
MAX_DARK_FRACTION = 0.35
MAX_MATERIAL_SHARE = 0.55
#: Gray under which a pixel counts as black rather than merely shadowed, as the
#: percentage `-threshold` takes.  See the docstring for why 10 and not 5.
DARK_PERCENT = 10.0
#: The camera's eye above the placed body origin, in units.  `dk3_runtime_place`
#: reports the origin the hull stands on (24 above the floor), and the view height
#: this engine draws from is 22 above that.
EYE_ABOVE_ORIGIN = 22.0


def _fx(capture, expression, threshold=None):
    """-> one ImageMagick `fx` statistic over the capture's gray channel."""
    command = ['magick', str(capture), '-colorspace', 'Gray']
    if threshold is not None:
        command += ['-threshold', '%g%%' % threshold]
    command += ['-format', expression, 'info:']
    outcome = subprocess.run(command, capture_output=True, text=True, check=True)
    return float(outcome.stdout.split()[0])


def photometrics(capture):
    """-> (mean, standard deviation, dark fraction) of one capture over 0..1.

    Two `magick` calls rather than one decode in numpy: the mean must be the *same
    number* `map_view_probe` reports in its own `views.json`, and the only way to
    guarantee that is to ask the same program the same question.
    """
    mean, spread = (_fx(capture, '%%[fx:%s]' % statistic)
                    for statistic in ('mean', 'standard_deviation'))
    dark = _fx(capture, '%[fx:1-mean]', threshold=DARK_PERCENT)
    return mean, spread, dark


class Caster:
    """The exported brushes, once, so a hundred views do not re-read a 2 MB .map."""

    def __init__(self, path, skip):
        doc = map_sightlines.read_map(path)
        self.brushes = [brush for brush in doc.brushes()
                        if not (set(brush.shaders()) & skip)]

    def view(self, origin, yaw, columns=16, rows=9, reach=6000.0):
        """-> [(shader, distance, solid-angle weight)], one entry per ray that hit.

        16 x 9 rays over yaw +-45 deg and pitch -25..+25 deg, weighted by the ray's
        solid angle.  That is ~1 % of the screen's rays but the same ranking to
        within a couple of points, and the ranking is the claim being made; a full
        1280x720 cast against 2200 brushes costs minutes per frame.
        """
        hits = []
        for row in range(rows):
            pitch = math.radians(-25.0 + 50.0 * row / (rows - 1))
            for column in range(columns):
                heading = math.radians(yaw) + math.radians(-45.0 + 90.0 * column / (columns - 1))
                direction = (math.cos(pitch) * math.cos(heading),
                             math.cos(pitch) * math.sin(heading), math.sin(pitch))
                end = tuple(origin[axis] + direction[axis] * reach for axis in range(3))
                best, best_t = None, 1.0
                for brush in self.brushes:
                    crossed = quake_map.span(brush, origin, end)
                    if crossed is None or crossed[0] < 0.0 or crossed[0] >= best_t:
                        continue
                    best, best_t = brush, crossed[0]
                if best is None:
                    continue
                shaders = sorted(set(best.shaders()) - skip_cache)
                weight = math.cos(pitch) / math.hypot(*direction[:2]) ** 2
                hits.append(((shaders[0] if shaders else '?'), best_t * reach, weight))
        return hits

    def shares(self, origin, yaw):
        """-> [(shader, share, nearest, median)] ranked by screen area."""
        hits = self.view(origin, yaw)
        total = sum(hit[2] for hit in hits) or 1.0
        weight, distances = {}, {}
        for shader, distance, hit_weight in hits:
            weight[shader] = weight.get(shader, 0.0) + hit_weight
            distances.setdefault(shader, []).append(distance)
        rows = []
        for shader, hit_weight in weight.items():
            ordered = sorted(distances[shader])
            rows.append((shader.rpartition('/')[2], hit_weight / total, ordered[0],
                         ordered[len(ordered) // 2]))
        return sorted(rows, key=lambda row: -row[1])


skip_cache = set()


def audit(report, map_path, materials, minimum_mean=MIN_MEAN_LUMA,
          maximum_dark=MAX_DARK_FRACTION, maximum_share=MAX_MATERIAL_SHARE, top=3):
    """-> one row per capture the probe took, with all three gate numbers."""
    evidence = json.loads((report / 'views.json').read_text())
    global skip_cache
    # Everything a ray may pass through, plus the surfaces the player cannot see:
    # a clip ring or a nodraw face that wins a ray makes the census report a
    # material nobody is looking at as the owner of the frame.
    skip_cache = set(map_sightlines.non_solid_shaders(materials)) | {'japandm/nodraw',
                                                                     'japandm/clip',
                                                                     'japandm/trigger'}
    caster = Caster(map_path, skip_cache)
    rows = []
    for view in evidence['views']:
        capture = report / view['image']
        if not capture.is_file():
            continue
        mean, spread, dark = photometrics(capture)
        x, y, z = view['placed']
        shares = caster.shares((x, y, z + EYE_ABOVE_ORIGIN), view['angle'][1])
        rows.append(dict(frame=view['start'], mean=round(mean, 4), spread=round(spread, 4),
                         dark=round(dark, 4),
                         dominant=shares[0][0] if shares else None,
                         dominant_share=round(shares[0][1], 4) if shares else 0.0,
                         top=[dict(material=name, share=round(share, 4))
                              for name, share, _near, _median in shares[:top]],
                         failure=(('dark mean %.3f < %.2f' % (mean, minimum_mean))
                                  if mean < minimum_mean else '')
                                 + ((' dark %.0f%% > %.0f%%' % (100 * dark, 100 * maximum_dark))
                                    if dark > maximum_dark else '')
                                 + ((' %s owns %.0f%% of the frame > %.0f%%'
                                     % (shares[0][0], 100 * shares[0][1],
                                        100 * maximum_share))
                                    if shares and shares[0][1] > maximum_share else '')))
    return dict(map=evidence['identity']['map'], renderer=evidence.get('renderer'),
                minimum_mean=minimum_mean, maximum_dark=maximum_dark,
                maximum_share=maximum_share, frames=rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', default='japanDM')
    parser.add_argument('--report', type=Path, required=True,
                        help='a map_view_probe report directory (holds views.json and the JPEGs)')
    parser.add_argument('--work', type=Path, default=None,
                        help='build-product root (default: the report\'s grandparent)')
    parser.add_argument('--materials', type=Path, default=None,
                        help='the map\'s materials.py, for which shaders a ray may see through '
                             '(default: maps/<map>/materials.py)')
    parser.add_argument('--min-mean', type=float, default=MIN_MEAN_LUMA)
    parser.add_argument('--max-dark', type=float, default=MAX_DARK_FRACTION)
    parser.add_argument('--max-share', type=float, default=MAX_MATERIAL_SHARE)
    parser.add_argument('--json', action='store_true')
    arguments = parser.parse_args()

    work = arguments.work or arguments.report.parent
    materials = arguments.materials or Path('maps/%s/materials.py' % arguments.map)
    result = audit(arguments.report, work / ('%s.map' % arguments.map), materials,
                   arguments.min_mean, arguments.max_dark, arguments.max_share)
    if arguments.json:
        print(json.dumps(result, indent=1))
        return 0
    print('%-18s %7s %7s %6s   %-16s %6s  %s'
          % ('frame', 'mean', 'spread', 'dark', 'dominant material', 'share', 'gate'))
    for row in result['frames']:
        print('%-18s %7.3f %7.3f %5.0f%%   %-16s %5.0f%%  %s'
              % (row['frame'], row['mean'], row['spread'], 100 * row['dark'],
                 row['dominant'], 100 * row['dominant_share'],
                 row['failure'] or 'ok'))
    failures = [row for row in result['frames'] if row['failure']]
    print('\n%d frames, %d failing: mean >= %.2f, dark (under %.0f%% gray) <= %.0f%%, '
          'one material <= %.0f%%'
          % (len(result['frames']), len(failures), result['minimum_mean'], DARK_PERCENT,
             100 * result['maximum_dark'], 100 * result['maximum_share']))
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(main())
