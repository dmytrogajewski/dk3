# SPDX-License-Identifier: GPL-2.0-or-later
"""The small objects: generated props, and where the level puts them.

Why a table and not coordinates in `build_blender.py`
-----------------------------------------------------
The 1999 read this map is accused of is not mainly about the big shapes -- it is
about the *last two metres*. A 2017 street has a bin under the counter, a
cart parked at the stall lip, a row of condensers bolted to the roof edge, a
vending machine glowing at the end of a dark lane. Those objects are not boxes,
so they cannot be authored with the level's own shape helpers; each one arrives
as a generated mesh that `dkq3/tools/map_prop_brushes.py` decomposes into the
convex brushes a `.map` can hold. This module is the other half of that: the
measurement that turns a generated blob into "one bin, here, facing that way,
wearing this map's own plastic".

Three decisions live here, and each could be wrong in a different way:

1. **Which material a piece wears.** A generated piece carries one number -- the
   mean colour baked into its own texture -- and japanDM's crafted albedos are
   *night* albedos: the brightest structural surface in the map is a linear
   0.05.  The generator's colours come from a lit product shot, where the same
   grey reads as 0.50.  Matching those two by raw distance therefore maps every
   prop onto asphalt and the bazaar fills with black holes.  So the match is
   made on **chroma** (the colour with its brightness divided out) with only a
   weak pull toward the right brightness, and emissive/transparent materials are
   reachable only by the pieces that genuinely glow -- a lantern's paper, a
   machine's light box.

2. **Where a prop may stand.** Every prop here is solid, so one bad coordinate
   can seal a route the navigation compiler will then report as unreachable
   standing area.  Most placements are therefore *anchored* to a piece of
   furniture the level already recorded: the prop is put outside that box's
   footprint, against its face, near one end of it.  Only the open plaza gets
   free coordinates, because the plaza is the one floor where a prop cannot
   corner anyone off.

3. **How many brushes it may cost.** Each prop is 4-9 brushes and every brush
   costs compile time and draw calls, so the counts below are chosen against the
   measured 807 brushes this map already has, and every prop is exported as
   `detail`: the vis clusters stay put and the props stay cheap.  The trade is
   that props cast no shadows, which is why they are placed against lit
   surfaces -- under an awning strip, beside a machine -- rather than freestanding
   in the middle of a light pool.
"""

from __future__ import annotations

import json
import math
from fnmatch import fnmatch
from pathlib import Path

HERE = Path(__file__).resolve().parent

#: Where the decomposed recipes and the measured palette live.
ASSETS = HERE / 'assets'

#: prop -> how it may be dressed.  `palette` is the set of materials a piece of
#: this prop is allowed to wear; `glow` names the materials reserved for the
#: pieces that are lit *by the prop itself*, and `glow_at` is how bright a piece
#: must be, relative to the brightest piece of that prop, to qualify.
# Each palette is the set of *painted* materials this object can wear, chosen from
# what the object is made of in a Japanese street market, and deliberately drawn
# from `japandm/prop_*` / `foliage` rather than the structural materials: see the
# note at the head of this table's module docstring and the note in `textures.py`.
# A vendor's machine is steel, cyan plastic and a lit front; a cart is wood, canvas
# and steel tyres; a planter is pale concrete and foliage.  Brightness is what makes
# them findable at night, distinct chroma is what makes them read as *things*.
PROPS = {
    'lantern': dict(palette=('prop_paint_red', 'prop_canvas', 'prop_steel', 'prop_wood'),
                    glow=('neon_a', 'vend_face'), glow_at=0.62),
    'vending': dict(palette=('prop_steel', 'prop_paint_cyan', 'prop_paint_red', 'prop_rubber'),
                    glow=('vend_face', 'light_strip'), glow_at=0.72),
    'ac_condenser': dict(palette=('prop_steel', 'prop_rubber', 'prop_concrete'),
                         glow=(), glow_at=1.1),
    'pushcart': dict(palette=('prop_wood', 'prop_canvas', 'prop_steel', 'prop_paint_red'),
                     glow=(), glow_at=1.1),
    'trashbin': dict(palette=('prop_paint_cyan', 'prop_steel', 'prop_rubber'),
                     glow=(), glow_at=1.1),
    'planter': dict(palette=('prop_concrete', 'prop_steel', 'foliage'),
                    glow=(), glow_at=1.1),
    'utility_box': dict(palette=('prop_steel', 'prop_rubber', 'prop_concrete'),
                        glow=('light_strip', 'vend_face'), glow_at=0.85),
    'barrier': dict(palette=('prop_steel', 'prop_paint_red', 'light_strip'),
                    glow=(), glow_at=1.1),
}


# --------------------------------------------------------------------------- #
# recipes and palette
# --------------------------------------------------------------------------- #
def recipe(prop):
    """-> the decomposed brush recipe for one prop, or None if it was never made."""
    path = HERE / 'props' / prop / 'brushes.json'
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding='utf-8'))


def palette():
    """-> {shader: entry} as measured from the crafted images by map_prop_palette."""
    path = ASSETS / 'material_colour.json'
    return json.loads(path.read_text(encoding='utf-8'))['palette']


def _chroma(colour):
    total = sum(colour) or 1.0
    return [value / total for value in colour]


def _luminance(colour):
    return 0.2126 * colour[0] + 0.7152 * colour[1] + 0.0722 * colour[2]


def luminance(colour):
    """-> scene-referred luma of one linear triple, for the glow decision."""
    return _luminance(colour)


def material_for(colour, prop, table, glow=False):
    """-> the shader key one piece should wear, as a `japandm/<key>` string.

    Chroma distance dominates; brightness only nudges within a tint.  `glow`
    swaps the candidate set to the prop's emissive materials, which is how a
    lantern's paper and a machine's light box stay readable at night instead of
    arriving as the same dark grey as their housings.
    """
    spec = PROPS[prop]
    wanted = spec['glow'] if glow else spec['palette']
    candidates = []
    for key in wanted:
        shader = 'japandm/%s' % key
        if shader in table:
            candidates.append((shader, table[shader]))
    if not candidates:
        candidates = [(shader, entry) for shader, entry in table.items()
                      if not entry['emissive'] and not entry['transparent']]
    target = _chroma(colour)
    best, best_cost = None, None
    for shader, entry in candidates:
        tint = _chroma(entry['colour'])
        cost = math.dist(target, tint)
        # A weak brightness pull, in octaves, so a bright object still prefers a
        # bright material when two tints tie -- but never prefers asphalt just
        # because everything in a night map is dark.
        cost += 0.08 * abs(math.log2((_luminance(colour) + 1e-3)
                                     / (_luminance(entry['colour']) + 1e-3)))
        if best_cost is None or cost < best_cost:
            best, best_cost = shader, cost
    return best


# --------------------------------------------------------------------------- #
# geometry: recipe pieces -> world-space shells
# --------------------------------------------------------------------------- #
def world_pieces(spec, x, y, z, yaw=0.0, scale=1.0):
    """-> [(points, polygons, colour)] for one placement, in world units.

    The generator leaves a mesh in the positive octant with its base at z=0, so
    the placement recentres it on its own footprint first: a prop rotated by yaw
    then turns about the point the player sees it stand on, not about a corner.
    """
    points = [point for piece in spec['pieces'] for point in piece['points']]
    if not points:
        return []
    centre_x = 0.5 * (min(p[0] for p in points) + max(p[0] for p in points))
    centre_y = 0.5 * (min(p[1] for p in points) + max(p[1] for p in points))
    cosine, sine = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    made = []
    for piece in spec['pieces']:
        moved = []
        for px, py, pz in piece['points']:
            px = (px - centre_x) * scale
            py = (py - centre_y) * scale
            moved.append((x + px * cosine - py * sine,
                          y + px * sine + py * cosine,
                          z + pz * scale))
        made.append((moved, [list(polygon) for polygon in piece['polygons']], piece['colour']))
    return made


def footprint(spec, scale=1.0):
    """-> (width, depth) of one recipe at a scale, used to seat props against walls."""
    points = [point for piece in spec['pieces'] for point in piece['points']]
    if not points:
        return (32.0 * scale, 32.0 * scale)
    return (max(p[0] for p in points) - min(p[0] for p in points)) * scale, \
           (max(p[1] for p in points) - min(p[1] for p in points)) * scale


# --------------------------------------------------------------------------- #
# placement
# --------------------------------------------------------------------------- #
#: Anchor patterns that found no furniture.  `build_blender.prop_scatter` fails
#: the build on these: a prop pass that quietly places nothing is how the market
#: deck lost every one of its props for two builds.
_MISSES = []


def misses():
    """-> the anchor patterns that matched no furniture this pass."""
    return list(_MISSES)


def _anchors(boxes, pattern):
    """-> recorded furniture matching one glob, in build order, one entry per name.

    The glob is not cosmetic.  Asking for everything called ``stall_*`` returns a
    stall's counter *and* its awning, its two posts and its light strip -- six
    anchors where one was meant -- and the first cut of this file answered that
    by putting 264 props down at 1565 brushes, several of them inside each other.
    Callers name the piece of furniture they mean: ``stall_*_counter``.
    """
    seen, found = set(), []
    for name, low, high, kind in boxes:
        if name in seen or kind in ('trigger', 'loose') or not fnmatch(name, pattern):
            continue
        seen.add(name)
        found.append((name, low, high))
    return found


def anchored(prop, boxes, pattern, face, along=0.85, gap=6.0, scale=1.0, every=1,
             offset=0.0, lift=0.0, yaw=None, only=None):
    """Seat `prop` against the furniture matching `pattern`.

    `face` is the side of the anchor the prop stands off: `-y` puts the prop
    outside the anchor's smaller-y face with its back to it, which is where a bin
    or a cart actually ends up in a market -- against something, never in the
    walking line.  `along` walks it from one end of that face toward the other,
    defaulting near the end so the prop hugs a corner instead of standing proud
    of the middle of a counter.

    `lift` raises the prop off the anchor's own floor, which is how a prop gets
    onto a raised platform or a counter top; `offset` slides it along the face.

    `only` names the anchor *indices* to use instead of the `every` stride.  A
    stride cannot express "the two counters whose backs open onto a service
    aisle": on the deck's east run, counters e02 and e03 face each other across a
    76-unit gap that the awning over e02 already owns, so a cart parked off e03's
    back stands in the middle of e02's customers.  Naming the two counters that
    have somewhere to stand is both the honest fix and the readable one.
    """
    spec = recipe(prop)
    width, depth = footprint(spec, scale)
    made = []
    for index, (name, low, high) in enumerate(_anchors(boxes, pattern)):
        if only is not None:
            if index not in only:
                continue
        elif index % every:
            continue
        x = low[0] + (high[0] - low[0]) * along
        y = low[1] + (high[1] - low[1]) * along
        z = low[2] + lift
        if face == '-y':
            y, yaw_default = low[1] - gap - depth / 2.0, 180.0
            x += offset
        elif face == '+y':
            y, yaw_default = high[1] + gap + depth / 2.0, 0.0
            x += offset
        elif face == '-x':
            x, yaw_default = low[0] - gap - width / 2.0, 270.0
            y += offset
        else:
            x, yaw_default = high[0] + gap + width / 2.0, 90.0
            y += offset
        made.append(dict(prop=prop, x=x, y=y, z=z,
                         yaw=yaw if yaw is not None else yaw_default, scale=scale,
                         anchor=name))
    return made


def on_floor(prop, spots, floors, scale=1.0, yaw=0.0, lift=0.0):
    """Free coordinates on a named floor.

    Only the open floors get these: the plaza and the roof ring are the two
    places where a prop standing in space cannot corner a player off behind it.
    Every one is still checked by `build_blender.verify`, which fails the build
    when such a spot turns out to have no slab under it.
    """
    return [dict(prop=prop, x=float(x), y=float(y), z=floors[floor] + lift, yaw=yaw,
                 scale=scale, anchor='%s %s' % (prop, floor))
            for x, y, floor in spots]


#: Placements the clearance pass removed, so a build can say how many -- a prop
#: pass that quietly loses a third of its objects is the same silence this file
#: has been arguing with the level about since the first cut.
_DROPPED = []


def dropped():
    """-> the placements removed by the clearance pass on the last call."""
    return list(_DROPPED)


def _extent(spec, scale, yaw):
    """-> (width, depth, height) of one placement's axis-aligned box, in world units.

    The recipe is built in its own frame and turned by `yaw` about the point it
    stands on, so a cart parked at 14 degrees is a little wider than the cart and
    a machine turned to face a wall is deeper than it is wide.  Measuring the
    turned box rather than the unturned one is what keeps a skewed cart from being
    cleared against the space it does not actually occupy.
    """
    points = [point for piece in spec['pieces'] for point in piece['points']]
    if not points:
        return (32.0, 32.0, 32.0)
    width = (max(p[0] for p in points) - min(p[0] for p in points)) * scale
    depth = (max(p[1] for p in points) - min(p[1] for p in points)) * scale
    height = (max(p[2] for p in points) - min(p[2] for p in points)) * scale
    cosine, sine = abs(math.cos(math.radians(yaw))), abs(math.sin(math.radians(yaw)))
    return (width * cosine + depth * sine, width * sine + depth * cosine, height)


def clear_pass(out, boxes, no_go=(), margin=2.0):
    """-> the placements that have somewhere to stand, in the order they were asked for.

    Every anchor in this file was chosen by reading one piece of furniture, and no
    anchor knows what the other nine anchors did.  Two prop kinds sharing a pitch,
    a bin landing on a light well, a condenser parked against a column that
    already has a barrier at its base -- all of them read to `verify` as an
    overlap and to a player as one object inside another.  So the pass measures
    each placement's turned box, and drops it if anything the level already
    recorded occupies the same air at the same height, or if an earlier placement
    took that air first.  The floor a prop stands on is never in the way: a
    blocker only counts where it overlaps the body, not where it meets its feet.
    """
    global _DROPPED
    _DROPPED = []
    shells = ('facade_', 'sky_ring', 'sky_lid', 'clip_')
    solids = [(name, low, high) for name, low, high, kind in boxes
              if kind not in ('rail', 'trigger', 'loose', 'hint')
              and not name.startswith(shells)]
    taken = []
    kept = []
    for place in out:
        spec = recipe(place['prop'])
        if spec is None:
            kept.append(place)
            continue
        width, depth, height = _extent(spec, place['scale'], place.get('yaw', 0.0))
        half_w, half_d = width / 2.0 + margin, depth / 2.0 + margin
        x, y, z = place['x'], place['y'], place['z']
        box = (x - half_w, y - half_d, z + 4.0, x + half_w, y + half_d, z + height - 4.0)
        clash = None
        for spot, limit in no_go:
            # A keep-out is a cylinder around the start, not a wall that runs the
            # whole height of the block: `deck_s` on the market deck may not rob a
            # bin of its spot on the street 256 units below it.  The earlier test
            # compared the start's y against the *top* of the prop's box, which is
            # how a spawn at y 20 was refusing a machine at y -750.
            if spot[0] - limit < box[3] and spot[0] + limit > box[0]:
                if not (spot[1] - limit < box[4] and spot[1] + limit > box[1]):
                    continue
                if len(spot) > 2 and (spot[2] + 128.0 <= box[2] or spot[2] >= box[5]):
                    continue
                clash = '%s spawn origin' % ('nearby' if len(spot) > 2 else 'same-floor')
                break
        for name, low, high in solids:
            if clash is not None:
                break
            if high[2] - low[2] <= 8.0:
                continue            # paint, kerbs and joint lines: nothing can
                                    # stand inside a stripe on the floor
            if (low[0] < box[3] and high[0] > box[0] and low[1] < box[4]
                    and high[1] > box[1] and low[2] < box[5] and high[2] > box[2]):
                clash = name
                break
        if clash is None:
            for other, other_box in taken:
                if (other_box[0] < box[3] and other_box[3] > box[0]
                        and other_box[1] < box[4] and other_box[4] > box[1]
                        and other_box[2] < box[5] and other_box[5] > box[2]):
                    clash = other
                    break
        if clash is not None:
            _DROPPED.append('%s at %g,%g (%s)' % (place['prop'], x, y, clash))
            continue
        taken.append((place['prop'], box))
        kept.append(place)
    return kept


def placements(boxes, floors, face=1024.0, plaza_half=448.0, foot=1152.0, lane=96.0,
               no_go=()):
    """-> every prop the level should contain, as placement dicts.

    Density is the thing to argue about here.  Each entry below is a prop a
    player can walk up to and read, so the count is set by what the eye can hold
    in one sightline -- roughly one small object per stall, per counter run and
    per roof stretch -- and not by how many meshes exist.  Order is deliberate:
    furniture first, because the anchors only exist after the dressing pass has
    recorded them, then the open floors.
    """
    band = 0.5 * (plaza_half + face)              # mid-depth of a roof ring
    out = []

    # --- west market alley: every stall gets the clutter of a working pitch ---
    # The north rows face south and the south rows face north, so the two sets
    # need opposite faces: `stall_n*` takes its clutter on `-y`, `stall_s*` on
    # `+y`.  Written as one rule over `stall_*_counter` it put the south stalls'
    # bins behind them and the north stalls' bins into the row behind, which is
    # what `verify`'s 39 % overlap report was for.
    # Only every other north row gets a bin in front of it.  The four north rows
    # run diagonally, one counter-length apart in x and 32 units apart in y, so a
    # 40-unit-deep bin in front of one row stands inside the row in front of it --
    # which is exactly what the 28 % overlap report said twice.
    # `along=0.62` put the bin in front of `stall_n02_counter` at x -649, which is
    # inside `stall_n01_counter` (x -904..-648, y 216..280): the rows run
    # diagonally, one counter-length apart in x and 96 apart in y, so the aisle in
    # front of one row is crossed by the row behind it.  0.80 clears it by 20 in x.
    # Not on the `-y` face: the north rows run diagonally 96 apart in both axes,
    # so the aisle in front of one row is crossed by the row behind it (`along`
    # 0.62 put a bin inside `stall_n01_counter`, 0.80 put it through the lane
    # stall's awning post).  The rows' east ends are the only open ground, and
    # that is where a market actually puts its bins.
    out += anchored('trashbin', boxes, 'stall_n*_counter', '+x', along=0.90, gap=6.0,
                    every=2)
    out += anchored('trashbin', boxes, 'stall_s*_counter', '+y', along=0.9, gap=8.0)
    out += anchored('lantern', boxes, 'stall_n*_counter', '-y', along=0.42, scale=0.9, gap=8.0)
    out += anchored('lantern', boxes, 'stall_s*_counter', '+y', along=0.42, scale=0.9, gap=8.0)
    # No cart on either stall run: a cart is 63 units deep, a stall front is 120
    # to 256 long and its bin and lantern already stand on it, and the west lane
    # kerb (`stall_lane_w_n_0`) fills what is left over.  The carts go where the
    # ground is genuinely open instead -- the plaza, the platform and one pulled
    # up in the alley mouth between two crate stacks.
    out += on_floor('pushcart', ((-680.0, -150.0, 'T0'),), floors, scale=0.9, yaw=-24)

    # --- T1 deck: the counter runs get service clutter, not decoration -------
    # `deck_counter_w?` was the first spelling of these patterns, and `?` is one
    # character: the anchors are named `deck_counter_w00`...`w11`, so every one of
    # these four calls matched nothing and the market deck -- the tier the player
    # actually fights on -- shipped with no generated props at all.  Two `?`, and
    # the pass says out loud when a pattern finds no anchor, because a silent zero
    # is what hid this for two builds.
    deck_rows = ('deck_counter_w??', 'deck_counter_e??')
    for pattern in deck_rows:
        if not _anchors(boxes, pattern):
            _MISSES.append('no anchor matches %s' % pattern)
    # Each west row's `along` is read off its own x span, so the four pitches on
    # that side of the aisle -- lantern, bin, cart, condenser -- stand four
    # abreast instead of on top of each other, and none of them lands on the two
    # crate stacks that share the deck (`crates_deck_w_0` at y 312..376 and
    # `crates_deck_w_2` at y 188..284).  Every number here survived a pass of
    # `dkq3/tools/map_prop_clear.py`, which is what `verify` will fail the build
    # on otherwise.
    # `along` 0.10 -> 0.35: at 0.10 the west deck's first hanging lantern
    # stood over the north corner of `crates_deck_w_2` and clipped it by 13 units,
    # which `verify` fails the build on.  The gap is the wrong knob here -- it
    # pushes the lantern further south, deeper into the stack -- so the lantern
    # moves along its own counter instead, into the gap between the two crate
    # stacks that share this deck, where it lights the aisle it already faces.
    out += anchored('lantern', boxes, deck_rows[0], '-y', along=0.35, gap=10.0, scale=1.35)
    out += anchored('trashbin', boxes, deck_rows[0], '-y', along=0.90, every=2, scale=1.0,
                    gap=10.0)
    out += anchored('ac_condenser', boxes, deck_rows[0], '+y', along=0.15, every=3,
                    scale=1.0)
    # The east run's awnings were built over its `+y` faces, so `+y` is the
    # customer side and `-y` is the service side -- the west run is mirrored about
    # the ring.  A pitch's lantern and bin belong under its own awning; a cart and
    # a utility box belong behind it, which is where the goods come in.  Putting
    # the bin and the lantern on the back side as well stacked three props in one
    # 64-unit-wide aisle and put the cart inside the bin.
    # e03 is the one counter on this run that has no customer side: `+y` puts it
    # 16 units into `deck_counter_e01`, and `-y` puts it in e02's aisle.
    out += anchored('lantern', boxes, deck_rows[1], '+y', along=0.45, only=(0, 1, 2, 4, 5),
                    scale=1.35, gap=10.0)
    out += anchored('trashbin', boxes, deck_rows[1], '+y', along=0.30, only=(2, 4),
                    scale=1.0, gap=8.0)
    # `stall_deck_e_0` (x 784..848, y 220..316) stands on the deck over the north
    # face of `deck_counter_e00`, so that run's service box stands at its far end
    # rather than under the stall it cannot see.
    out += anchored('utility_box', boxes, deck_rows[1], '+y', along=0.62, only=(2, 4),
                    scale=1.15)
    out += anchored('utility_box', boxes, deck_rows[1], '+y', along=0.92, only=(0,),
                    scale=1.15)
    # Two carts, and only where the back opens onto a real aisle: e00 backs onto
    # the open deck south of it, e04 backs onto the service lane at y -210.  e03's
    # back is the aisle e02 sells into, and e05's back is where the roof stair
    # (x 898..910) lands on the deck.
    out += anchored('pushcart', boxes, deck_rows[1], '-y', along=0.30, only=(0, 4),
                    scale=0.95, gap=14.0, yaw=18)
    # The deck planters' barriers face the plaza edge (`-y`): on `+y` the north
    # arm's planters sit 84 units from the tower-front line and a 74-unit barrier
    # hung over it into the facade.
    out += anchored('barrier', boxes, 'deck_planter_??', '-y', along=0.9, every=2, scale=1.0,
                    yaw=0)
    # The roof ramps' feet and the skybridge mouth, so the third tier is not bare
    # concrete between a condenser row and a railing.
    # The west roof's first free spot was x -880, y 300 -- dead centre on the koi
    # basin plate (x -984..-792, y 252..380); x -620, y 300 was inside a planter.
    # x -880, y -200 is the sweep-clean lane under the west billboard.
    out += on_floor('utility_box', ((-880.0, -200.0, 'T2'), (300.0, 880.0, 'T2')), floors,
                    scale=1.2, yaw=90)
    out += on_floor('barrier', ((-700.0, 960.0, 'T2'), (620.0, 300.0, 'T2')), floors,
                    scale=1.0, yaw=0)
    out += on_floor('lantern', ((-460.0, 640.0, 'T2'), (460.0, 640.0, 'T2')), floors,
                    scale=1.35, yaw=0)
    out += on_floor('trashbin', ((-620.0, -640.0, 'T2'),), floors, scale=1.0)
    # --- T2 roofs: the condenser row every rooftop actually has --------------
    # Free coordinates rather than anchors: a roof is authored as several
    # rectangles once a void is cut, so anchoring per rectangle clumps four
    # condensers on one slab and none on the next.  These sit mid-depth in the
    # ring, where the roof slab is under them and the plaza is in front -- clear
    # of the koi basin rim (x -1016..-760, y 220..412), the torii lanterns
    # (x 700..740, y +/-.160..224) and every roof spawn origin.
    # Nothing on the viaduct piers' x line (-800, -400, 0, 400, 800): a condenser
    # bolted to the roof at the same x as an elevated-road pier ends up inside the
    # pier's own flared flange, which runs from the street all the way up past the
    # roof it passes.  The two north spots moved off 400 to 560 for that reason.
    roof_spots = ((band, -band * 0.55, 'T2'), (band, band * 0.78, 'T2'),
                  (-band, -band * 0.5, 'T2'), (-700.0, band * 0.6, 'T2'),
                  (-560.0, band, 'T2'), (560.0, band, 'T2'),
                  (-band * 0.55, -band, 'T2'), (band * 0.5, -band, 'T2'))
    out += on_floor('ac_condenser', roof_spots, floors, scale=1.15, yaw=90)
    # The east roof's centre line is the torii pad (x 720..1024, y -176..176) and
    # its house is at y 240..400, so the east service clutter sits south of the
    # pad and north of the house rather than on top of either.
    out += on_floor('utility_box', ((band, -band * 0.8, 'T2'), (-band, 0.0, 'T2')), floors,
                    scale=1.2, yaw=180)
    out += on_floor('barrier', ((band, band * 0.64, 'T2'), (-band * 0.35, -band, 'T2')),
                    floors, scale=1.0, yaw=90)
    out += on_floor('trashbin', ((band, -plaza_half - 60.0, 'T2'),), floors, scale=1.0)

    # --- T0 south: the loading yard and the kiosk ---------------------------
    # The vending machine sits at the far end of the kiosk's east face, where the
    # yard's crate stacks are not.  At 0.2 it landed on `vend_crates_02`.
    out += anchored('vending', boxes, 'kiosk', '+y', along=0.2, scale=1.05, gap=10.0, yaw=0)
    out += anchored('lantern', boxes, 'kiosk', '-x', along=0.75, scale=0.95, gap=8.0, yaw=270)
    # One cart on the platform, away from the three container stacks.  Anchoring
    # it to the stair flight put it 20 units past the south tower-front line and
    # 32 below the street, so it is placed on the platform floor instead.
    out += on_floor('pushcart', ((940.0, -700.0, 'T0'),), floors, scale=0.9, lift=32.0, yaw=8)

    # --- the plaza: the bazaar floor proper ---------------------------------
    # The four plaza corners already carry benches (x +/-.220..356, y +/-.264..312),
    # so the planters that used to stand on them move in to the inner diagonal and
    # the rest of the dressing keeps its distance from them.
    # Nothing stands inside the holo pool (|x|,|y| <= 176, `pool_holo` at z 2):
    # a cart parked in a hologram reads as a bug, not as dressing.
    out += on_floor('pushcart', ((-240, 60, 'T0'), (120, -260, 'T0'), (-40, -330, 'T0')),
                    floors, scale=1.0, yaw=18)
    out += on_floor('planter', ((-300, 170, 'T0'), (300, 170, 'T0'), (-300, -170, 'T0'),
                                (300, -170, 'T0'), (0, 360, 'T0')), floors, scale=1.15)
    # (266,-190) is where a bridge pier's plinth now stands: the walkway across
    # the plaza has stopped flying, and the bin moves outside its 96-unit base.
    # Off the planters' diagonal and outside the new pier plinths, or the bin
    # stands inside a planter it was meant to sit beside.
    out += on_floor('trashbin', ((-356, 262, 'T0'), (330, -236, 'T0')), floors, scale=1.05)
    out += on_floor('lantern', ((-120, 258, 'T0'), (250, -90, 'T0'), (330, 96, 'T0'),
                                (-336, -60, 'T0')), floors, scale=1.0)
    out += on_floor('barrier', ((-360, 40, 'T0'), (-360, 128, 'T0')), floors, scale=1.0, yaw=90)
    # The plaza is the largest floor in the arena and the one every sightline
    # crosses, and it was the emptiest: a pool, five planters, four benches and two
    # machines over 896 x 896.  A 2017 street is never empty at that scale -- it is
    # a pavement with things parked on it.  So the south half takes a parked row of
    # carts and bins the way a market parks them across a plaza, the north edge
    # takes two machines with their backs to the kerb, and four planters stand on
    # the lateral centre line where a planter belongs and where they double as the
    # crouch cover a wide open floor has no other reason to have.
    out += on_floor('pushcart', ((-320.0, -300.0, 'T0'), (320.0, -300.0, 'T0'),
                                 (240.0, -384.0, 'T0'), (-240.0, -384.0, 'T0')),
                    floors, scale=1.2, yaw=18)
    out += on_floor('trashbin', ((-262.0, -362.0, 'T0'), (262.0, -362.0, 'T0'),
                                 (-380.0, -300.0, 'T0')), floors, scale=1.2)
    out += on_floor('vending', ((-120.0, 392.0, 'T0'), (120.0, 392.0, 'T0')), floors,
                    scale=1.3, yaw=180)
    out += on_floor('lantern', ((-180.0, -250.0, 'T0'), (180.0, -250.0, 'T0')), floors,
                    scale=1.2)
    out += on_floor('planter', ((-380.0, 120.0, 'T0'), (-380.0, -120.0, 'T0'),
                                (380.0, 120.0, 'T0'), (380.0, -120.0, 'T0')), floors,
                    scale=1.35, yaw=90)
    # The lit boxes the dark lanes were promised, at plaza level, where a
    # machine's own glow has somewhere to fall.
    out += on_floor('vending', ((-404, 404, 'T0'), (404, -404, 'T0')), floors, yaw=225)

    # --- T1: the bazaar street, bay by bay -----------------------------------
    # The rows are the one place in the arena where the level already builds
    # furniture in an unbroken line, which is the condition that makes generated
    # props read at all: a bin and a cart against a wall with a hood over them are
    # a market, and the same two objects dropped on an open plate are a prop
    # test.  Everything stands on the *aisle* face -- `+y` for the row whose back
    # is the smaller y, `-y` for the row that faces it -- and at `along` values
    # that keep clear of the hood posts at each end of a pitch (x0+10 and x1-10).
    # Scales are 1.15 and up, against 0.9 in the old placements: the owner's
    # complaint was not that the props were missing but that they were invisible,
    # and a 40-unit bin seen from 600 units away on a 0.9 scale is four pixels.
    # A stride cannot separate two kinds: `every=2` for a bin and `every=3` for a
    # cart share index 6, and at `along` 0.30/0.68 on a 148-unit counter the two
    # landed 56 units apart -- inside each other, which is what the 32-defect
    # report was.  A counter is 148 long and a loaded cart is 125, so the street
    # can hold exactly ONE dressed object per pitch.  The rows are therefore
    # partitioned: every pitch index belongs to one kind or to none, and the
    # empty pitches are the ones the level already dressed with its own goods.
    for row, face in (('a', '+y'), ('b', '-y'), ('n', '-y')):
        pattern = 'bazaar_%s_s*_counter' % row
        seats = range(len(_anchors(boxes, pattern)))
        kinds = (('trashbin', 0, 8.0, 1.2), ('lantern', 1, 20.0, 1.3),
                 ('vending', 4, 12.0, 1.2), ('pushcart', 5, 14.0, 1.25),
                 ('barrier', 2, 12.0, 1.2))
        for prop, phase, gap, scale in kinds:
            out += anchored(prop, boxes, pattern, face, along=0.5, gap=gap,
                            scale=scale, only={i for i in seats if i % 8 == phase},
                            yaw=14 if prop == 'pushcart' else None)
    # The lit kerbs at the aisle edge want something standing behind them, or the
    # two kerb lines read as the only thing on the street.
    # The aisle between the two rows is 384 wide and the row props hug its two
    # walls at y -909 and -595, so what is left is a clear 200-unit walking line
    # down y -750.  Three islands stand in it: a planter is the one object a
    # market aisle has in the middle, and in a deathmatch it is the crouch-cover
    # the street was missing.  Chosen from the scene's own record -- (-700,-750)
    # and (300,-752) are deck planters already, and y -912/-592 is where the
    # counters' own bins now stand.
    out += on_floor('planter', ((0.0, -760.0, 'T1'), (-400.0, -700.0, 'T1'),
                                (760.0, -520.0, 'T1')), floors, scale=1.3, yaw=180)
    out += on_floor('vending', ((-960.0, -750.0, 'T1'), (960.0, -620.0, 'T1')),
                    floors, scale=1.25, yaw=90)
    out += on_floor('trashbin', ((900.0, -750.0, 'T1'),), floors, scale=1.15)

    # --- the colonnade: a column base is where a street puts its clutter ------
    # The two-storey hall columns over the plaza are the newest furniture in the
    # level and the only large verticals a player walks between, so a condenser or
    # a utility box against one both dresses the base and says that the column is
    # structural rather than scenery.
    # The roof colonnade's columns are the only large verticals on the market
    # deck, and a condenser or a meter box against a base both dresses the column
    # and says it is structural rather than scenery.  (`arcade_hall_col_*` was the
    # first anchor here: that colonnade was never built -- every plaza site its
    # rows proposed is already occupied by the market it was meant to stand in --
    # so the pattern matched nothing and the pass quietly placed nothing, which is
    # the failure this file has been bitten by twice.)
    out += anchored('utility_box', boxes, 'arcade_t2_col_*', '-y', along=0.5,
                    gap=8.0, scale=1.3, every=3, yaw=0)
    out += anchored('ac_condenser', boxes, 'arcade_t2_col_*', '+x', along=0.5,
                    gap=8.0, scale=1.25, every=4, yaw=90)
    return clear_pass(out, boxes, no_go=no_go)
