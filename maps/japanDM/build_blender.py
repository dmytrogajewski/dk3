# SPDX-License-Identifier: GPL-2.0-or-later
"""japanDM: a future-Japan deathmatch arena, modelled as the brushes it compiles to.

Run inside Blender (`blender -b --python build_blender.py`), or through
`dkq3/tools/map_build.py --map japanDM`, which rebuilds this scene whenever the
script is newer than the `.blend`. One Blender unit is one Quake unit.

The level is a city block in four tiers, after the pattern research in DESIGN.md:

    T0    0   open plaza with a holo pool, and a covered street ring behind it
              that runs under the market deck, cut by four open alleys
    T1  256   the market deck: a ring of roof over that street, railed at the
              plaza edge, looking down on the pool
    T2  512   the roofs -- a roof garden over the west and north arms, a torii
              plaza over the east arm, and a glazed skybridge across the plaza
    704       a monorail viaduct over the north roof, two ramps, one escape each

Every dimension here comes from a measured number: 16-unit treads against the
engine's 18-unit step-up, 25-degree ramps, no gap under 89 or over 160 that
matters, spawn origins 24 above a real floor, and a sealed shell (sky ring inside
a nodraw ring) so the compiler never finds a leak. Nothing moves, nothing breaks,
nothing teleports: v1 is static geometry, which is also all the bot compiler can
navigate (`func_*` brushes are excluded from the AAS brush set).
"""
import math
import os
import re
from pathlib import Path
import sys

sys.path.insert(0, '/home/dmitriy/sources/dk3/dkq3/tools')
import map_blender

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import screen_styles


def _table():
    import importlib.util
    spec = importlib.util.spec_from_file_location('japandm_materials', str(HERE / 'materials.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TABLE = _table()
M = TABLE.MATERIALS


def _props_table():
    import importlib.util
    spec = importlib.util.spec_from_file_location('japandm_props', str(HERE / 'props.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PROPS = _props_table()

# An empty scene first, because it purges every datablock: creating the materials
# before it leaves handles to removed StructRNAs, and the first brush then dies on
# `materials.append`. The scene also owns the worldspawn epairs, so it comes first.
scene = map_blender.new_scene()
# The shipped episode-4 arenas carry episode/palette/sky plus a fog triple and a
# _color; japanDM keeps that convention and puts its rain haze on the same keys.
map_blender.world(scene, **TABLE.WORLD)

# --- dimensions -------------------------------------------------------------
FOOT = 1152          # the plaza-to-shell half width: the block is 2304 across
SHELL = 1280         # inner face of the sky ring
OUTER = 1408         # inner face of the nodraw ring that seals the sky ring
LID = 1408           # sky lid floor, nodraw lid above it
PLAZA = 448          # the open plaza reaches this, in every direction
LANE = 96            # half width of the four alleys that cut the deck ring
# The tower fronts are 128 thick and stand *inside* the block limit, so nothing
# a player can walk on may cross this line: the street reads as a trench with a
# wall on its outer side, and a stair that runs past it arrives buried in that
# wall with its first free tread a 48-unit step.
FACE = FOOT - 128
T0, T1, T2, VIA = 0, 256, 512, 704
# The engine's step-up is 18 units (`slide.Context.step` traces 18 up and 18
# back down), and a player climbing a stair never *stands* on a tread -- they
# stream up it.  That is why 8 up / 8 deep is the canonical Quake stair: at a
# 16-unit rise every footfall is a shove against a 16-high wall, the 26-unit
# tread is shallower than the 32-unit hull, and the flight reads as the "stairs
# too big to be real" the owner saw.  At a 8-unit rise a 416-unit flight gets 32
# treads of 13 units -- steeper in profile than deep, which is what a real
# Japanese public stair is, and every one of them inside the step the engine and
# the bot compiler both take.
TREAD = 8            # the ceiling on one step's rise, not its depth
#: How deep a tread has to be.  The player's hull is 32 wide, so anything shallower
#: than 16 leaves the box hanging over the next riser on every second footfall, and
#: whether that stops the climb is then decided by the player's starting coordinate
#: to within a unit.  `stair_roof_w` walked and `stair_roof_e` did not, built the
#: same way: that is not a level, it is a coin toss.
TREAD_DEPTH = 16.0
#: The step the engine is willing to take, repeated here for the same reason as
#: `ENGINE_STEP` further down: `flight` lays treads long before the audit tables.
MAX_STEP = 16.0
DECK = 32            # slab thickness
# How much of the deck ring is left clear against the block's own face, so a
# running line past the stalls exists at all: 64 is two player boxes wide. The
# plinth stands 16 proud of the facade, so the deck's walkable stretch starts 16
# inside the block band at FOOT - FACADE_THICK - 16.
DECK_FACADE_LANE = 64
HEAD = 224           # clear storey under a T2 slab that sits on the T1 deck

MADE, BOXES = {}, []
#: Authored objects that end up inside a player's or an item's volume.  Filled by
#: the yield pass and charged as a defect by `verify`.
BODY_CLASHES = []
#: Generated props whose only legal spot turned out to be somebody's spawn.
PROP_SWALLOWS = []


def record(name, low, high, kind):
    BOXES.append((name, low, high, kind))


def mat(key, **override):
    return map_blender.material(M, 'japandm/%s' % key, **override)


ASPHALT = mat('asphalt')
PLAZA_STONE = mat('plaza_stone')
TOWER = mat('tower_front')
CONCRETE = mat('concrete_panel')
DECK_METAL = mat('metal_deck')
COLUMN = mat('metal_column')
GRATE = mat('grate')
CLOTH = mat('cloth')
CRATE = mat('crate')
ROOF = mat('roof_gravel')
PLANT = mat('plant')
# A hedge wearing `plant` measured a linear albedo of 0.009 -- a black lump with a
# green cast, and the reason every planter box in the arena read as rubble.  Hedges
# and planter beds are the only greenery a player walks *past*, so they wear the
# crafted `foliage` (0.09 linear, four times the leaf) and `plant` stays what it
# always was: the dark ground cover under it.
FOLIAGE = mat('foliage')
LACQUER = mat('lacquer_red')
NEON_A = mat('neon_a')
NEON_B = mat('neon_b')
ADBOARD = mat('ad_board')
STRIP = mat('light_strip')
HOLO = mat('holo_pool')
GLASS = mat('glass')
NODRAW = mat('nodraw')
TRIGGER = mat('trigger')
SKY = mat('sky')



# --- shape helpers ----------------------------------------------------------
#: The hull the game fills wherever it puts a player: `multiplayer.PLAYER_MINS`
#: is +-16 in XY and -24 in Z, and the body is 56 tall.  Anything that intrudes
#: into that box more than a step at the spot the game chose does not merely
#: crowd the player -- it swallows them, and the engine then reports a body with
#: no ground that cannot move.  Items get a slightly larger volume because a
#: player has to be able to *reach* one.
BODY_HALF, BODY_TALL, ITEM_HALF, ITEM_TALL = 16.0, 56.0, 24.0, 48.0
#: A third of a player body: the resolution the level is drawn on and the step an
#: item is allowed to look for a gap in.
STEP_THIRD = 16.0
_BODY_KEEPS = None
#: Where each item finally stands, written by `items()` when it has to slide.
_ITEM_SPOTS = {}


def item_spot(name, authored):
    """-> where the item called `name` finally stands: its authored place until
    `items()` says otherwise.  Kept in one place so the hull list and the entity
    list cannot disagree about where a reward is.
    """
    return _ITEM_SPOTS.get(name, authored)


def entity_hulls():
    """-> [(name, low, high)] the volume the game fills at every start and item.

    Built lazily and once: the spawn and pickup tables are module data, but this
    is called from inside `box`, which runs before those tables are read by
    anybody, and an import-time list would have to be maintained by hand.
    """
    global _BODY_KEEPS
    if _BODY_KEEPS is None:
        keeps = []
        for name, location, _angle in SPAWNS:
            x, y, floor = location
            keeps.append(('spawn_' + name,
                          (x - BODY_HALF, y - BODY_HALF, floor),
                          (x + BODY_HALF, y + BODY_HALF, floor + BODY_TALL)))
        for name, _classname, location in PICKUPS:
            x, y, floor = item_spot(name, location)
            keeps.append(('pickup_' + name,
                          (x - ITEM_HALF, y - ITEM_HALF, floor),
                          (x + ITEM_HALF, y + ITEM_HALF, floor + ITEM_TALL)))
        _BODY_KEEPS = keeps
    return _BODY_KEEPS


def body_clear(low, high, spawns_only=False):
    """-> the name of the entity whose hull this box would occupy, or None.

    `spawns_only` is the difference between the two promises: the geometry pass asks
    about starts only, because the item pass runs after it and moves the item, while
    the prop pass asks about both and slides itself.  The final charge is neither --
    `verify` asks about the finished arrangement, with both settled.

    A thing shorter than the engine's step-up is not swallowed by: a road marking,
    a kick plate or a kerb is something a player walks *over*, and charging those
    would strip the paint off every street in the arena.
    """
    for name, elo, ehi in entity_hulls():
        if spawns_only and not name.startswith('spawn_'):
            continue
        if (low[0] < ehi[0] and high[0] > elo[0]
                and low[1] < ehi[1] and high[1] > elo[1]
                and low[2] < ehi[2] and high[2] > elo[2]
                and min(high[2], ehi[2]) - elo[2] > STEP_UP):
            return name
    return None


def box(name, mins, maxs, material, detail=False, source='box', kind='prop',
        soffit=None, crown=None, where=None):
    """One brush from a pair of opposite corners, in whichever order they came.

    `mins`/`maxs` are a corner pair, not a directed extent: a strip written from
    the far kerb to the near one describes the same box, and map_blender rejects a
    reversed axis rather than silently inverting it.

    `soffit` and `crown` are the two horizontal faces of that box, painted
    separately.  They exist because a material used to be assigned to the whole
    object, so a roof slab showed its ballast to the street below it and a deck
    plate showed its tread plate as a ceiling -- the wrongness the owner saw.  A
    Quake 3 brush already carries one shader per plane, so this costs nothing the
    format was not already doing.
    """
    low = tuple(min(a, b) for a, b in zip(mins, maxs))
    high = tuple(max(a, b) for a, b in zip(mins, maxs))
    # --- the two promises a piece of scenery has to keep --------------------
    # A climb is a promise this level cannot trade away, so scenery that stands in
    # one *moves*, and if it cannot move it does not exist.  A lane is a promise with
    # a market in it: the lines say you can get from one end of a street to the other,
    # and a stall that narrows one to 90 units of the 30-unit body is still a street --
    # it is also what the owner means when they say the bazaar is empty.  So a lane
    # intruder is moved if a move exists and *kept* if it does not, loudly, in
    # `ROUTE_KEPT`, rather than deleted to make an audit line tidy.
    scenery = name.startswith(YIELD_TO_ROUTES)
    # Occupying a player's own volume is never acceptable, scenery or not, so it
    # triggers the same slide that a blocked climb does -- and unlike a lane, there
    # is no version of this one that the level is allowed to keep.
    must_body = body_clear(low, high, spawns_only=True)
    # A flight of steps is a run of treads and nothing else.  `climb_required_clear`
    # forgives anything a player could step over, which is right about a crate on a
    # street and wrong about a crate on the fourth step: `e_cond02_flange` was slid
    # off its own wall to clear a lane, landed in the east roof stair, passed every
    # body test in this file, and cost that flight 208 of its 256 units of climb.
    in_flight = scenery and climb_band_intrudes(low, high)
    if (scenery and not climb_required_clear(low, high)
            or in_flight
            or scenery and not lane_route_clear(low, high) or must_body):
        # Scenery slides along its own longest axis, which is the axis it was laid
        # out on: a sign bank moves down its wall, a crate stack along the lane it was
        # parked across.  Only then does it try the other axis, because moving a wall
        # mount away from its wall would leave it standing on nothing.
        forward = (64.0, -64.0, 128.0, -128.0, 192.0, -192.0, 256.0, -256.0)
        sideways = (32.0, -32.0, 64.0, -64.0)
        along_x = (high[0] - low[0]) >= (high[1] - low[1])
        tries = ([(d, 0.0) for d in forward] if along_x else [(0.0, d) for d in forward])
        tries += ([(0.0, d) for d in sideways] if along_x else [(d, 0.0) for d in sideways])
        must_climb = not climb_required_clear(low, high)
        must_lane = not lane_route_clear(low, high)
        placed = False
        for dx, dy in tries:
            moved = (low[0] + dx, low[1] + dy, low[2]), (high[0] + dx, high[1] + dy, high[2])
            # Sliding onto a clear line is only a fix if the new place is a place:
            # the first yield pass pushed twelve crates, rims and flanges across the
            # tower-front line into the wall they were supposed to stand in front of,
            # and dropped others inside a counter they now overlapped by a half.
            if max(abs(moved[0][0]), abs(moved[1][0]),
                   abs(moved[0][1]), abs(moved[1][1])) > FACE - 4.0:
                continue
            if not _stand_clear(*moved, name=name):
                continue
            # ...and the place it slides to may not be another player's body: the
            # pass that swallowed `spawn_torii` moved scenery out of a lane and into
            # a start, which is exactly the trade this rule refuses.
            if body_clear(*moved) is not None:
                continue
            if must_climb and not climb_required_clear(*moved):
                continue
            if climb_band_intrudes(*moved):
                # Unconditional, and not `in_flight and ...`: `e_sign05_glow` was
                # slid 128 down its wall to clear a lane, landed in the east roof
                # stair, and was only caught afterwards by the audit -- by which
                # point the move had already been made.  Where a box came from is a
                # reason to move it; where it lands is the only thing that matters.
                continue
            if must_lane and not lane_route_clear(*moved):
                continue
            ROUTE_YIELDS.append('%s moved %g,%g to clear %s'
                                % (name, dx, dy, 'a climb' if must_climb else 'a lane'))
            low, high = moved
            placed = True
            break
        if not placed:
            if must_body:
                # Scenery that cannot get off a start has nowhere to be, and neither
                # has a trim piece: a plinth, a kick plate or a flange is a band
                # painted onto a wall that stopped being allowed there, and a player
                # is not negotiable against a base course.  Structure that cannot
                # move is a different thing -- a layout bug -- and `verify` charges
                # it below rather than letting the level compile around it.
                if scenery or name.endswith(TRIM):
                    ROUTE_DROPS.append('%s (on %s)' % (name, must_body))
                    return None
                BODY_CLASHES.append('%s stands in %s and cannot move' % (name, must_body))
            if must_climb:
                ROUTE_DROPS.append('%s (in a climb)' % name)
                return None
            if in_flight:
                ROUTE_DROPS.append('%s (on the steps)' % name)
                return None
            ROUTE_KEPT.append('%s narrows a lane at %d,%d' % (name, low[0], low[1]))
    record(name, low, high, 'detail' if detail else kind)
    if where is not None:
        where.append((name, low, high))
    made = map_blender.box(name, low, high, material, source=source)
    caps = {index: value for index, value in ((0, soffit), (1, crown)) if value is not None}
    if caps:
        map_blender.paint(made, caps)
    return map_blender.decorate(made) if detail else made


def loose(name, made, kind='loose'):
    """Record a non-axis-aligned brush (a ramp, a turned wall, a prism) by extent.

    Rotated brushes are left out of `verify`'s overlap arithmetic on purpose: a
    ramp's bounding box covers the wedge it is not, so it would report clashes
    that a sightline or a navigation walk would disprove.
    """
    del kind                                        # recorded here, not in BOXES
    return made


def slab(name, mins, maxs, material, soffit=None):
    """A floor plate whose top face is the walking surface at maxs.z.

    `soffit` is what the plate looks like from underneath, which for a deck over
    a street is the face a player actually spends time looking at.
    """
    return box(name, mins, maxs, material, source='slab', kind='slab', soffit=soffit)


def flight(name, start, end, width, material, tread=TREAD, bulk=None):
    """Solid steps: each tread is a box from the flight's own base to its top.

    `map_blender.stairs` gives one thin slab per tread, which leaves a stepped
    void under the staircase; bot navigation does not care and neither does a
    player, but the compiler then lights the underside of every tread and the
    stair reads as a floating ladder. Solid treads cost the same brush count.

    `bulk` caps that depth, and where a flight passes over another walkway it has
    to be: solid to the base, a T1-to-T2 stair is a wall from the deck slab up,
    and japanDM's west and east roof stairs stood in the same corridor as the
    T0-to-T1 climbs, so the climb underneath lost its standing headroom the moment
    its own surface reached 168 and a player walking up it was crushed under the
    stairs overhead. Treads 48 thick follow the slope instead: the clearance under
    a roof stair stays above 200 units from its foot to its top.
    """
    x_run = abs(end[0] - start[0]) > abs(end[1] - start[1])
    rise = abs(end[2] - start[2])
    # Depth first, rise second: enough steps to keep every one of them inside the
    # engine's step, and deep enough that a 32-wide hull sits on one tread rather
    # than across a riser.
    run = abs((end[0] - start[0]) if x_run else (end[1] - start[1]))
    steps = max(2, int(round(run / TREAD_DEPTH)))
    while steps * MAX_STEP < rise:
        steps += 1
    # Each tread reaches 64 below its own top rather than all the way to the
    # flight's base.  At an 8-unit tread a flight is 32 brushes, and a solid-from-
    # base flight buries its first four treads wholly inside the street slab and
    # its own foundation -- which `verify` is right to call a buried object and
    # wrong to fail the level over, because a stair that rises out of a floor must
    # start inside it.  64 keeps the bottom treads fused to the ground they rise
    # from, and the profile a player sees is unchanged.
    if bulk is None:
        bulk = 64.0
    base = min(start[2], end[2])
    along_start, along_end = ((start[0], end[0]) if x_run else (start[1], end[1]))
    across = end[1] if x_run else end[0]
    made = []
    for index in range(steps):
        near = along_start + (along_end - along_start) * index / float(steps)
        far = along_start + (along_end - along_start) * (index + 1) / float(steps)
        top = start[2] + rise * (index + 1) / float(steps)
        # ...but never below the flight's own foot.  `dock_step` is a 32-unit kerb
        # climb standing on a NODRAW floor clip that starts 32 below the street,
        # and an unclamped 64-deep first tread reached into it and reported
        # itself as a prop buried in a shell.
        bottom = max(top - bulk, base)
        if x_run:
            mins = (min(near, far), across - width / 2.0, bottom)
            maxs = (max(near, far), across + width / 2.0, top)
        else:
            mins = (across - width / 2.0, min(near, far), bottom)
            maxs = (across + width / 2.0, max(near, far), top)
        # The tread's own top face wears the grip plate: a stair that is one
        # material from riser to nosing reads as a sloped wall at night, and this
        # costs no brush because a Quake brush already carries one shader per plane.
        made.append(box('%s_%02d' % (name, index), mins, maxs, material, source='stairs',
                        kind='stair', crown=mat('deck_timber')))
    return made


def rail_posts(name, axis, a0, a1, at, z0, height, thickness, every):
    """-> the uprights of an openwork balustrade, one every `every` units.

    `axis` is the axis the line runs along; `at` is the coordinate across it.
    """
    made = []
    count = max(2, int(round(abs(a1 - a0) / max(every, 8.0))))
    for index in range(count + 1):
        along = a0 + (a1 - a0) * index / float(count)
        if axis == 'x':
            mins, maxs = (along - 5, at - 5, z0 + 8), (along + 5, at + 5, z0 + height - 8)
        else:
            mins, maxs = (at - 5, along - 5, z0 + 8), (at + 5, along + 5, z0 + height - 8)
        made.append(box('%s_%02d' % (name, index), mins, maxs, COLUMN, kind='rail'))
    return made


def stair_light(name, start, end, width, height=None):
    """A lit kerb down each flank of a flight, so the treads read at night.

    Every dark frame in the capture set was a stairwell, and it was dark for two
    reasons at once: the lamp stands above the *middle* of the flight, and the
    tread crown is `grate`, a 0.05 albedo.  A strip on the flanks is two brushes
    per flight, it follows the slope exactly (one `turned` box per side, the same
    trick `sided_ramp` uses for its barriers), and because `light_strip` is a
    surfacelight it also puts light into the well instead of only wearing it.
    """
    dx, dy, dz = end[0] - start[0], end[1] - start[1], end[2] - start[2]
    length = math.hypot(dx, dy)
    if length < 1.0:
        return []
    yaw = math.degrees(math.atan2(dy, dx))
    pitch = -math.degrees(math.atan2(dz, length))
    px, py = -dy / length, dx / length
    ux, uy = dx / length, dy / length
    offset = width / 2.0 + 9.0
    height = 10.0 if height is None else height
    made = []
    for side, tag in ((-1.0, 'l'), (1.0, 'r')):
        made.append(map_blender.turned(
            '%s_kerb%s' % (name, tag),
            (start[0] + ux * length / 2.0 + px * offset * side,
             start[1] + uy * length / 2.0 + py * offset * side,
             (start[2] + end[2]) / 2.0 + height / 2.0 + 2.0),
            (length + 16.0, 6.0, height), (0.0, pitch, yaw), STRIP, source='turned'))
    return made


def rail(name, p0, p1, height, solid_top=True, glazed=True, post_at=72.0):
    """A walkway edge: a kick plate, a glazed panel and a metal cap rail.

    Edges are where a deathmatch map loses players, so the barrier is solid and
    48 units up -- above eye height, which makes it cover rather than a window
    you can be shot through while standing at it.
    """
    # `glazed` is the default because a deck edge wants a barrier a slug stops at.
    # A stairwell is not a deck edge: a 192-unit climb between two 48-high glass
    # panels is a slot, and the owner's read of it -- "stairs too big and close to
    # walls" -- was correct about the slot even though the treads themselves are
    # inside the engine's step.  Openwork keeps the fall protection and gives the
    # flight its flanks back: the eye reads the space beside the stair as part of
    # the stair.
    x_run = abs(p1[0] - p0[0]) > abs(p1[1] - p0[1])
    thickness = 12.0
    made = []
    kind = 'rail'
    if x_run:
        x0, x1 = sorted((p0[0], p1[0]))
        y = p0[1]
        made.append(box('%s_kick' % name, (x0, y - thickness / 2, p0[2]),
                        (x1, y + thickness / 2, p0[2] + 8), COLUMN, kind=kind))
        if glazed:
            made.append(box('%s_glass' % name, (x0, y - 4, p0[2] + 8),
                            (x1, y + 4, p0[2] + height - 8), GLASS, kind=kind))
        else:
            made.extend(rail_posts('%s_post' % name, 'x', x0, x1, y, p0[2], height,
                                   thickness, post_at))
        made.append(box('%s_cap' % name, (x0, y - thickness / 2, p0[2] + height - 8),
                        (x1, y + thickness / 2, p0[2] + height), mat('metal_brass'), kind=kind))
    else:
        y0, y1 = sorted((p0[1], p1[1]))
        x = p0[0]
        made.append(box('%s_kick' % name, (x - thickness / 2, y0, p0[2]),
                        (x + thickness / 2, y1, p0[2] + 8), COLUMN, kind=kind))
        if glazed:
            made.append(box('%s_glass' % name, (x - 4, y0, p0[2] + 8),
                            (x + 4, y1, p0[2] + height - 8), GLASS, kind=kind))
        else:
            made.extend(rail_posts('%s_post' % name, 'y', y0, y1, x, p0[2], height,
                                   thickness, post_at))
        made.append(box('%s_cap' % name, (x - thickness / 2, y0, p0[2] + height - 8),
                        (x + thickness / 2, y1, p0[2] + height), mat('metal_brass'), kind=kind))
    return made


def post_row(name, centre, radius, count, height, material, size=24.0, sides=6,
             base=0.0):
    """`count` prisms of `height` standing on `base`.

    The height used to be measured from z 0 always, which is right for a street
    bollard and wrong for a rooftop tank: the first cut's roof tanks were built
    from the street floor up and then painted at T2, which is a tank buried to its
    own top and a lid standing 512 units in the air.
    """
    made = []
    for index in range(count):
        angle = 2.0 * math.pi * index / float(count)
        x = centre[0] + radius * math.cos(angle)
        y = centre[1] + radius * math.sin(angle)
        made.append(map_blender.prism('%s_%02d' % (name, index),
                                      map_blender.polygon_ring((x, y), size / 2.0, sides=sides),
                                      base, base + height, material, source='prism'))
    return made


# --- the ground: an open plaza and a covered street ring --------------------
def ground():
    slab('floor_plaza', (-PLAZA, -PLAZA, -DECK), (PLAZA, PLAZA, T0), PLAZA_STONE,
         soffit=CONCRETE)
    slab('floor_west', (-FOOT, -FOOT, -DECK), (-PLAZA, FOOT, T0), ASPHALT)
    slab('floor_east', (PLAZA, -FOOT, -DECK), (FOOT, FOOT, T0), ASPHALT)
    slab('floor_south', (-PLAZA, -FOOT, -DECK), (PLAZA, -PLAZA, T0), ASPHALT)
    slab('floor_north', (-PLAZA, PLAZA, -DECK), (PLAZA, FOOT, T0), ASPHALT)
    # The holo pool: a glowing floor panel you can stand on, 2 units proud of
    # the paving, ringed by four benches that leave the centre empty on purpose.
    slab('pool_holo', (-160, -160, T0), (160, 160, T0 + 2), HOLO)
    slab('pool_frame_n', (-176, 160, T0), (176, 176, T0 + 4), COLUMN)
    slab('pool_frame_s', (-176, -176, T0), (176, -160, T0 + 4), COLUMN)
    slab('pool_frame_e', (160, -176, T0), (176, 176, T0 + 4), COLUMN)
    slab('pool_frame_w', (-176, -176, T0), (-160, 176, T0 + 4), COLUMN)
    for index, (x, y) in enumerate(((-288, -288), (288, -288), (288, 288), (-288, 288))):
        box('bench_%d' % index, (x - 64, y - 20, T0), (x + 64, y + 20, T0 + 32), PLAZA_STONE)
        box('bench_top_%d' % index, (x - 68, y - 24, T0 + 32), (x + 68, y + 24, T0 + 40), LACQUER,
            detail=True)
    # Grated service covers in the street ring: texture change, no gameplay cost.
    for index, (x, y, wide) in enumerate(((-800, 300, True), (800, -300, True),
                                          (300, 800, False), (-300, -800, False))):
        if wide:
            slab('grate_%d' % index, (x - 128, y - 64, T0), (x + 128, y + 64, T0 + 1), GRATE)
        else:
            slab('grate_%d' % index, (x - 64, y - 128, T0), (x + 64, y + 128, T0 + 1), GRATE)


# --- T1: the market deck ring ----------------------------------------------
def deck():
    """Eight slabs: the annulus between the plaza and the block, minus four alleys.

    The annulus is one connected ring because each alley cuts the middle of one
    arm only; the corners keep the ring joined, so no single fight can cut the
    deck in half.
    """
    for name, (x0, y0), (x1, y1) in DECK_PIECES:
        # The deck ring is a plate over a street: 76 of its exported faces point
        # down, and they were showing an anti-slip tread plate as a ceiling.
        slab_with_voids(name, (x0, y0, x1, y1), T1 - DECK, T1, DECK_HOLES.get(name, []),
                        DECK_METAL, soffit=COLUMN)
    # Grated light wells set into the deck over the street, flush with the walk.
    # x -920, not -680: the first well stood dead centre in the service ramp's
    # opening, so the "grating set flush with the walk" was a grate over a staircase.
    for index, (x, y) in enumerate(((-920, 620), (800, 800), (800, -800), (-880, -800))):
        slab('deck_grate_%d' % index, (x - 96, y - 96, T1), (x + 96, y + 96, T1 + 2), GRATE)


def deck_parapets():
    """Rails on every deck edge: the plaza edge and the four alley sides."""
    edges = []
    for sign in (-1, 1):
        edges.append(('rail_plaza_w_%d' % sign, (-PLAZA, LANE), (-PLAZA, PLAZA)))
        edges.append(('rail_plaza_w2_%d' % sign, (-PLAZA, -PLAZA), (-PLAZA, -LANE)))
        edges.append(('rail_plaza_e_%d' % sign, (PLAZA, LANE), (PLAZA, PLAZA)))
        edges.append(('rail_plaza_e2_%d' % sign, (PLAZA, -PLAZA), (PLAZA, -LANE)))
        edges.append(('rail_plaza_n_%d' % sign, (-PLAZA, PLAZA), (-LANE, PLAZA)))
        edges.append(('rail_plaza_n2_%d' % sign, (LANE, PLAZA), (PLAZA, PLAZA)))
        edges.append(('rail_plaza_s_%d' % sign, (-PLAZA, -PLAZA), (-LANE, -PLAZA)))
        edges.append(('rail_plaza_s2_%d' % sign, (LANE, -PLAZA), (PLAZA, -PLAZA)))
    for name, (x0, y0), (x1, y1) in edges:
        if 'w_' in name or 'w2_' in name:
            rail(name, (x0 - 20, y0, T1), (x0 - 20, y1, T1), 48)
        elif 'e_' in name or 'e2_' in name:
            rail(name, (x0 + 20, y0, T1), (x0 + 20, y1, T1), 48)
        elif 'n_' in name or 'n2_' in name:
            rail(name, (x0, y0 + 20, T1), (x1, y0 + 20, T1), 48)
        else:
            rail(name, (x0, y0 - 20, T1), (x1, y0 - 20, T1), 48)
    # One guard line down each side of each canyon, broken where a footbridge
    # crosses so that the bridge's own rails continue the barrier instead of a
    # rail standing in the middle of its deck.
    canyons = (('y', -LANE, PLAZA, FACE, (BRIDGE_IN, FACE)),
               ('y', LANE, PLAZA, FACE, (BRIDGE_IN, FACE)),
               ('y', -LANE, -FACE, -PLAZA, (-FACE, -BRIDGE_IN)),
               ('y', LANE, -FACE, -PLAZA, (-FACE, -BRIDGE_IN)),
               ('x', -LANE, -FACE, -PLAZA, (-FACE, -BRIDGE_IN)),
               ('x', LANE, -FACE, -PLAZA, (-FACE, -BRIDGE_IN)),
               ('x', -LANE, PLAZA, FACE, (BRIDGE_IN, FACE)),
               ('x', LANE, PLAZA, FACE, (BRIDGE_IN, FACE)))
    for index, (axis, coord, a0, a1, gap) in enumerate(canyons):
        rail_line('rail_canyon_%02d' % index, axis, coord, a0, a1, T1, 48, gaps=(gap,))


# --- rectangle arithmetic: floors with stairwell voids ----------------------
def rect_minus(rect, holes):
    """-> rectangles covering `rect` minus each hole, which must lie inside it.

    A flight from one tier to the next has to arrive *through* the slab above it,
    so the slab needs a hole the size of the flight. Cutting the hole out of the
    slab as four bands around it keeps every brush a box, which is what the
    exporter and the bot compiler both want.
    """
    parts = [tuple(float(value) for value in rect)]
    for hole in holes:
        hx0, hy0, hx1, hy1 = (float(value) for value in hole)
        replaced = []
        for part in parts:
            px0, py0, px1, py1 = part
            if hx0 <= px0 and hy0 <= py0 and hx1 >= px1 and hy1 >= py1:
                continue                                   # the hole eats the whole part
            if hx1 <= px0 or hx0 >= px1 or hy1 <= py0 or hy0 >= py1:
                replaced.append(part)                      # untouched
                continue
            # Flush with the slab's edge is allowed -- each roof well's stair runs
            # right to the line where its roof meets a tower front -- and the
            # zero-width band that leaves is dropped by the filter below.
            inside = hx0 >= px0 and hx1 <= px1 and hy0 >= py0 and hy1 <= py1
            if not inside:
                raise ValueError('hole %s must sit inside %s, one hole per part' % (hole, part))
            replaced += [(px0, py0, hx0, py1), (hx1, py0, px1, py1),
                         (hx0, py0, hx1, hy0), (hx0, hy1, hx1, py1)]
            replaced = [candidate for candidate in replaced
                        if candidate[2] - candidate[0] > 1.0 and candidate[3] - candidate[1] > 1.0]
        parts = replaced
    return parts


def slab_with_voids(name, rect, z0, z1, holes, material, soffit=None):
    made = []
    for index, (x0, y0, x1, y1) in enumerate(rect_minus(rect, holes)):
        made.append(slab('%s_%02d' % (name, index), (x0, y0, z0), (x1, y1, z1), material,
                         soffit=soffit))
    return made


def spans(a0, a1, gaps=(), piece=8.0):
    """-> the intervals of [a0, a1] left when each gap is cut out of it."""
    pieces, cursor = [], a0
    for gap in sorted(gaps):
        if gap[0] > cursor:
            pieces.append((cursor, min(gap[0], a1)))
        cursor = max(cursor, gap[1])
    if cursor < a1:
        pieces.append((cursor, a1))
    return [piece_range for piece_range in pieces if piece_range[1] - piece_range[0] >= piece]


def rail_line(name, axis, coord, a0, a1, z, height=48.0, gaps=(), glazed=True):
    """A barrier along one axis-aligned walkway edge, broken where a route passes."""
    made = []
    for index, (p0, p1) in enumerate(spans(a0, a1, gaps)):
        if axis == 'x':
            made.append(rail('%s_%02d' % (name, index), (p0, coord, z), (p1, coord, z), height,
                             glazed=glazed))
        else:
            made.append(rail('%s_%02d' % (name, index), (coord, p0, z), (coord, p1, z), height,
                             glazed=glazed))
    return made


def sided_ramp(name, start, end, width, material, height=48.0):
    """An inclined walkway with a solid side barrier on both flanks."""
    dx, dy = end[0] - start[0], end[1] - start[1]
    length = math.hypot(dx, dy)
    px, py = -dy / length, dx / length                      # unit vector across the run
    # One slab of one material across the full 192 is what made `up_n` 78 % `grate`:
    # the eye had nothing beside the pattern to measure it against, so the repeat
    # read as decoration instead of as a route.  An exterior steel ramp in Japan is
    # laid as a raised tread plate between two drainage kerbs, so that is what is
    # built here -- the middle half in the climb's own material, the flanks a quarter
    # each in deck plate and 2 units lower.  The 2 is not a stylistic choice: it
    # keeps the two top planes from being coplanar, which would z-fight; it runs each
    # flank 2 under the tread so the seam is inside a solid and cannot be seen; and it
    # is a tenth of `ENGINE_STEP`, so the player walks over it and reads shadow.
    made = [map_blender.ramp(name, start, end, width * 0.5, DECK, material, source='ramp')]
    for flank_side in (-1.0, 1.0):
        flank_off = (width * 0.375 - 1.0) * flank_side
        made.append(map_blender.ramp(
            '%s_flank%s' % (name, 'l' if flank_side < 0 else 'r'),
            (start[0] + px * flank_off, start[1] + py * flank_off, start[2] - 2.0),
            (end[0] + px * flank_off, end[1] + py * flank_off, end[2] - 2.0),
            # `DECK - 2`, not `DECK`: the flank's walking surface is 2 lower, so a
            # 32-thick slab would bury its underside 4 below the tread's, and the
            # ramp's own bounding volume would grow.  `climb_band_intrudes` asks
            # every piece of scenery whether it stands in a climb, and the first
            # version of this change cost `dock_crates_00` its place to stand at the
            # foot of the north ramp -- which then cascaded into eight placement
            # defects in crates, planters and lanterns nowhere near a ramp.  At 30
            # thick the flank's underside lies on the tread's underside exactly, so
            # the three boxes together occupy the volume the one slab used to and no
            # keep-out moves.
            width * 0.25 + 2.0, DECK - 2.0, DECK_METAL, source='ramp'))
    yaw = math.degrees(math.atan2(dy, dx))
    pitch = -math.degrees(math.atan2(end[2] - start[2], length))
    px, py = -dy / length, dx / length                      # unit vector across the run
    ux, uy = dx / length, dy / length                       # unit vector along the run
    # The barrier runs between two distances along the run, and it starts where
    # the walkway stands 24 above the floor it leaves. Before that the surface is
    # less than one step-up off that floor, and a barrier there is a kerb taller
    # than the step it protects: japanDM's market ramp was walled into its own
    # foot, so the street could not walk onto it anywhere and the climb had no
    # bottom door -- a ramp you can only descend is a slide, not a route.
    foot = 24.0 * length / max(abs(end[2] - start[2]), 1.0)
    middle = (foot + length + 16.0) / 2.0                   # 16 of overshoot, at the top
    surface = start[2] + (end[2] - start[2]) * middle / length
    for side in (-1.0, 1.0):
        offset = (width / 2.0 + 8.0) * side
        made.append(map_blender.turned('%s_side%s' % (name, 'l' if side < 0 else 'r'),
                                       (start[0] + ux * middle + px * offset,
                                        start[1] + uy * middle + py * offset,
                                        surface + (height - DECK) / 2.0),
                                       (length - foot + 32.0, 16.0, height + DECK),
                                       (0.0, pitch, yaw), COLUMN, source='turned'))
    return made


# --- the four alleys and the four climbs ------------------------------------
# Each alley is a 192-unit slot through the deck ring, so the street below gets
# daylight and the deck above is broken: a footbridge closes each break, and the
# ring keeps both directions of travel, which is what stops any one fight from
# cutting a tier in half.
# Each bridge runs from the tower-front line inward, because that is as far as
# the deck is walkable: the outer 128 of every arm is the front itself, and the
# segment across a canyon mouth is only 192 tall. Measured from the block limit
# instead (1000..1128, the first cut) each bridge landed on top of that low
# segment, 64 above it, and arrived with nothing to step onto: the reach probe
# found two eye cells per bridge and no link from either to any floor, so all
# four crossings were islands and the deck ring was joined only at its corners.
BRIDGE_IN = FACE - 144
BRIDGES = (('bridge_n', (-LANE, BRIDGE_IN), (LANE, FACE)),
           ('bridge_s', (-LANE, -FACE), (LANE, -BRIDGE_IN)),
           ('bridge_w', (-FACE, -LANE), (-BRIDGE_IN, LANE)),
           ('bridge_e', (BRIDGE_IN, -LANE), (FACE, LANE)))

# Each climb starts exactly at the wall face it is measured from and ends
# exactly at the hole edge in the slab above it, so its first surface is flush
# with the floor it leaves and its last is flush with the floor it joins. The
# stairs give a 16-unit rise per tread however steep the flight; the two ramps
# are 30 degrees, inside the 45 degrees both the player and the bot compiler
# count as walkable.
CLIMB_S = ('stair_s', (-304, -FACE, T0), (-304, -608, T1), 192)
CLIMB_N = ('ramp_n', (-680, FACE, T0), (-680, 580, T1), 192)
CLIMB_W = ('ramp_w', (-FACE, -272, T0), (-608, -272, T1), 192)
CLIMB_E = ('stair_e', (FACE, -272, T0), (608, -272, T1), 192)

# 160 wide, not 192: a flight exactly as wide as its own opening left nowhere for the
# balustrade around that opening to stand, and the audit caught the rail posts of
# `well_04` and `well_05` inside the climb.  160 is still wider than two players
# abreast, and it leaves 16 units of roof plate on each flank for the rail's kick
# plate to bolt to -- which is what a real stairwell edge is.
ROOF_CLIMB_W = ('stair_roof_w', (-FACE, -250, T1), (-628, -250, T2), 160)
ROOF_CLIMB_N = ('ramp_roof_n', (-250, FACE, T1), (-250, 580, T2), 192)
ROOF_CLIMB_E = ('stair_roof_e', (FACE, -280, T1), (620, -280, T2), 160)

VOID_W, VOID_N, VOID_S, VOID_E = 264.0, 620.0, 512.0, 512.0

# A flight only needs the slab taken away where it stops fitting under it.  A body
# on a tread occupies 56 units above the surface it stands on (`BODY_TOP`), so under
# a slab whose underside is at 224 a climb is clear until its own surface reaches
# 168 - on a 416-unit run, the last 148 units of the flight.  The first cut voided
# each flight's WHOLE run, and that is what made this map unwalkable where the owner
# pointed: `deck_s_w` lost a 544 x 264 piece, which cuts the bazaar street in half at
# x -436..-172 (a player walking the market at y -750 fell 256 into the stairwell),
# and `deck_e_s` lost the whole outer walking lane at x 756..1024, so the deck ring
# could only be walked inboard of its own stair.  Each pit is now the opening the
# flight actually needs, padded 8 at the foot-side lip where the headroom test is
# exactly satisfied and not one unit more.
# The foot-side pad is 16 and not 8: at the exact headroom boundary the tread's
# surface plus a 56-tall body equals the slab's underside to the unit, and the audit
# found the lip of `deck_s_w` biting 1 unit into a body on the tread below it.

# --- the air a climb owns ----------------------------------------------------
#: How much air a climbing body owes itself above its head, over and above its own
#: 56 units and the 18 it is lifting itself by.  Without this margin the answer is
#: "exactly none", which is what left four of this level's seven climbs un-walkable:
#: see the head at 224 against the market deck's underside at 224.
CLIMB_AIR = 10.0
#: The engine's own step-up, repeated here because the wells below are computed at
#: import time and `STEP_UP` is introduced further down with the route audits.
ENGINE_STEP = 18.0


def climb_axis(climb):
    """-> (axis, start coordinate, end coordinate) for the axis a climb runs along."""
    _name, start, end, _width = climb
    axis = 0 if abs(end[0] - start[0]) > abs(end[1] - start[1]) else 1
    return axis, start[axis], end[axis]


def climb_surface(climb, at):
    """-> the walking height of a climb at `at`, measured along its own run."""
    _name, start, end, _width = climb
    axis, a0, a1 = climb_axis(climb)
    if a1 == a0:
        return start[2]
    return start[2] + (end[2] - start[2]) * (at - a0) / float(a1 - a0)


def climb_open_edge(climb, soffit, air=CLIMB_AIR):
    """-> how far down a climb a slab whose underside is at `soffit` may reach.

    The answer is the coordinate where the flight passes `soffit` - 56 - 18 - `air`,
    pushed further from the top by the body's own half-width and a little more: a
    body 32 wide straddles two treads while it passes under the edge of an opening,
    and it is the trailing end that is on the lower one.
    """
    _name, start, end, _width = climb
    axis, a0, a1 = climb_axis(climb)
    rise, run = end[2] - start[2], a1 - a0
    if not rise or not run:
        return a1
    limit = soffit - BODY_TALL - ENGINE_STEP - air
    at = a0 + (limit - start[2]) / float(rise) * run
    return at - math.copysign(BODY_HALF + 8.0, run)


def climb_well_rect(climb, rect, soffit, lateral_pad=36.0):
    """-> the opening a climb needs in the slab it arrives through, inside `rect`.

    Across the flight it is the flight plus `lateral_pad` on each side, because the
    balustrade around a stairwell stands on the slab and not on the steps.  Along the
    flight it runs from the opening's far end out to whichever reaches further down:
    the well this table used to carry, or the air rule.  A well already cut flush with
    a facade is left flush -- opening the question again would only chew the floor.
    """
    _name, start, end, width = climb
    axis, a0, a1 = climb_axis(climb)
    across = 1 - axis
    half = width / 2.0 + lateral_pad
    c0, c1 = sorted((end[across] - half, end[across] + half))
    edge = min(climb_open_edge(climb, soffit), a1) if a1 >= a0 \
        else max(climb_open_edge(climb, soffit), a1)
    lo, hi = sorted((edge, a1))
    x0, y0, x1, y1 = rect
    if axis == 0:
        return (max(lo, x0), max(c0, y0), min(hi, x1), min(c1, y1))
    return (max(c0, x0), max(lo, y0), min(c1, x1), min(hi, y1))


#: How far a box may stand above the lowest tread it touches without being a step
#: nobody can take.  Half the engine's own step-over: a stair rises out of a floor,
#: and the floor it rises out of inevitably graze-sits at the bottom of the band.
#: Without this the north service dock -- a platform whose top is 2 units above the
#: surface of the ramp that starts on it -- is charged for being a floor.
BURIED_GRAZE = ENGINE_STEP / 2.0


def climb_band_intrudes(low, high, air=CLIMB_AIR):
    """-> whether a box stands *inside* a flight, rather than under or over it.

    Every other body test in this file asks whether a box is in the way of a body at
    a sampled footfall, and answers "no" for anything a player could step over.  That
    is the right answer about a crate on a street and the wrong answer about a crate
    on a staircase: a player coming up an 8-unit tread onto a pedestal in mid-flight
    stops, and the map reports as unwalkable by someone who has never seen the
    pedestal.  A flight is a run of treads and nothing else, so a box inside its band
    must either be buried under the treads or be entirely above the walking envelope.
    """
    for climb in CLIMBS_ALL:
        _name, start, end, width = climb
        axis, a0, a1 = climb_axis(climb)
        across = 1 - axis
        lo, hi = sorted((a0, a1))
        # Along the run: buried under the lowest tread it touches, or clear above the
        # highest, is allowed; anything in between stands in the steps.
        if high[axis] <= lo or low[axis] >= hi:
            continue
        surface_low = climb_surface(climb, max(lo, low[axis]))
        surface_high = climb_surface(climb, min(hi, high[axis]))
        buried = high[2] <= min(surface_low, surface_high) + BURIED_GRAZE
        over = low[2] >= max(surface_low, surface_high) + BODY_TALL + ENGINE_STEP + air
        if buried or over:
            continue
        # Across the run: only the flight's own width counts, plus the body that
        # enters it from the side.
        c0 = min(start[across], end[across]) - width / 2.0
        c1 = max(start[across], end[across]) + width / 2.0
        if high[across] <= c0 or low[across] >= c1:
            continue
        return True
    return False


#: Which climb arrives through which slab, so its opening can be computed from the
#: flight rather than remembered.  The four numbers this replaces were typed against
#: the top of each flight, which is why three of the four wells stopped 158 units
#: short of the air the body climbing through them needs.
DECK_PIECES = (('deck_n_w', (-FOOT, PLAZA), (-LANE, FOOT)),
               ('deck_n_e', (LANE, PLAZA), (FOOT, FOOT)),
               ('deck_s_w', (-FOOT, -FOOT), (-LANE, -PLAZA)),
               ('deck_s_e', (LANE, -FOOT), (FOOT, -PLAZA)),
               ('deck_w_n', (-FOOT, LANE), (-PLAZA, PLAZA)),
               ('deck_w_s', (-FOOT, -PLAZA), (-PLAZA, -LANE)),
               ('deck_e_n', (PLAZA, LANE), (FOOT, PLAZA)),
               ('deck_e_s', (PLAZA, -PLAZA), (FOOT, -LANE)))
DECK_WELLS = (('deck_n_w', CLIMB_N), ('deck_s_w', CLIMB_S), ('deck_w_s', CLIMB_W),
              ('deck_e_s', CLIMB_E))
DECK_PIECE_RECTS = {name: (a[0], a[1], b[0], b[1]) for name, a, b in DECK_PIECES}
DECK_HOLES = {piece: [climb_well_rect(climb, DECK_PIECE_RECTS[piece], T1 - DECK)]
              for piece, climb in DECK_WELLS}
# One guard rail across the foot-side lip of each pit: without it a walking line that
# passes the opening runs into a hole whose floor is a staircase 256 below.  Each
# guard stands 8 back from the lip so its own kick plate is on solid slab, and it
# spans exactly the opening, so the way past it is open at both ends - which is how
# a railed stairwell reads, and how it walks.
def _lip(well, climb):
    """-> the rail line that closes the foot-side lip of one stairwell opening.

    Those four coordinates used to be typed, and every one of them drifted the first
    time a well moved.  It is derived now: 8 outside the opening, on the side the
    flight arrives from, spanning exactly the gap.
    """
    axis, a0, a1 = climb_axis(climb)
    x0, y0, x1, y1 = well
    up = a1 > a0                                   # which way the flight runs
    if axis == 1:                                  # flight along y: the lip runs along x
        return ('lip_%s' % climb[0][5:], 'x', (y0 if up else y1) + (-8.0 if up else 8.0),
                x0, x1, T1)
    return ('lip_%s' % climb[0][5:], 'y', (x0 if up else x1) + (-8.0 if up else 8.0),
            y0, y1, T1)


PIT_LIPS = [_lip(DECK_HOLES[piece][0], climb) for piece, climb in DECK_WELLS]
#: Every opening cut in the market deck, flat, for anything laid on that floor.
DECK_VOIDS = [rect for rects in DECK_HOLES.values() for rect in rects]
# The roofs end at the tower fronts, not at the block limit. Run out to FOOT, a
# roof meets the front it is supposed to sit behind: its outer 128 units bury
# themselves in the wall, its top face lies exactly on the wall's own top face
# wherever the front is 512 tall (two materials fighting for one pixel), and the
# buried part is a walkable balcony 108 deep round the outside of the block that
# the parapet above it was only ever meant to close.
ROOFS = {'roof_w': (-FACE, -PLAZA, -PLAZA, PLAZA),
         'roof_n': (-768, PLAZA, 768, FACE),
         'roof_e': (PLAZA, -PLAZA, FACE, PLAZA)}

ROOF_WELLS = (('roof_w', ROOF_CLIMB_W), ('roof_n', ROOF_CLIMB_N), ('roof_e', ROOF_CLIMB_E))
ROOF_HOLES = {key: [climb_well_rect(climb, ROOFS[key], T2 - DECK, lateral_pad=16.0)]
              for key, climb in ROOF_WELLS}
def climbs():
    """T0 to T1 on four sides, T1 to T2 on three: no tier is owned by one stair."""
    name, start, end, width = CLIMB_S
    flight(name, start, end, width, CONCRETE)
    name, start, end, width = CLIMB_E
    flight(name, start, end, width, CONCRETE)
    for climb in (CLIMB_N, CLIMB_W):
        name, start, end, width = climb
        sided_ramp(name, start, end, width, mat('deck_timber'))
    for climb in (ROOF_CLIMB_W, ROOF_CLIMB_E):    # these two cross a T0-to-T1
        name, start, end, width = climb                     # climb in the same
        flight(name, start, end, width, DECK_METAL, bulk=48)  # corridor: see flight()
    name, start, end, width = ROOF_CLIMB_N
    sided_ramp(name, start, end, width, mat('deck_timber'))
    for climb in (CLIMB_S, CLIMB_E, ROOF_CLIMB_W, ROOF_CLIMB_E, ROOF_CLIMB_N, CLIMB_N, CLIMB_W):
        stair_light(climb[0], climb[1], climb[2], climb[3])
    # Every stairwell is a 256-unit hole in a walkway, so it gets a balustrade
    # on both flanks and across the top of the flight's foot.
    # The four T0-to-T1 pits and the two roof trenches, each at its own extent.  The
    # balustrades used to be written against the OLD full-length voids, which would
    # now run 400 units of rail down the middle of the bazaar street; and the two
    # ramps, whose pits were never railed at all, left their openings bare-edged at
    # walking height.
    wells = [DECK_HOLES[piece][0] + (climb_axis(climb)[0],) for piece, climb in DECK_WELLS]
    wells += [ROOF_HOLES[key][0] + (0,) for key in ('roof_w', 'roof_e')]
    for index, (x0, y0, x1, y1, axis) in enumerate(wells):
        z = T1 if index < len(DECK_WELLS) else T2
        run = 'y' if axis == 1 else 'x'
        # 14 and not 6: a kick plate is 12 thick and centred on its line, so a
        # balustrade 6 off the hole edge lay along the first 12 units of the flight
        # and narrowed a 192-wide climb to 168 right where a player enters it.
        if run == 'y':
            rail_line('well_%02d_a' % index, 'y', x0 + 14, y0, y1, z, 48, glazed=False)
            rail_line('well_%02d_b' % index, 'y', x1 - 14, y0, y1, z, 48, glazed=False)
        else:
            rail_line('well_%02d_a' % index, 'x', y0 + 14, x0, x1, z, 48, glazed=False)
            rail_line('well_%02d_b' % index, 'x', y1 - 14, x0, x1, z, 48, glazed=False)
    for name, axis, coord, a0, a1, level in PIT_LIPS:
        rail_line('pit_%s' % name, axis, coord, a0, a1, level, 48, glazed=False)


def bridges():
    # The corridor's piers come here from `arcade`, because they are the load the
    # corridor carries and not the street's furniture: they must exist before the
    # landmarks ask where the plaza has the air, and a shaft that is placed after
    # them stands through a lantern post that was only ever told to move for routes.
    skybridge_piers()
    for name, (x0, y0), (x1, y1) in BRIDGES:
        slab(name, (x0, y0, T1 - DECK), (x1, y1, T1), DECK_METAL)
        if x1 - x0 < y1 - y0:                              # spans in y: rail the y edges
            rail_line('%s_a' % name, 'y', x0 + 8, y0, y1, T1, 48)
            rail_line('%s_b' % name, 'y', x1 - 8, y0, y1, T1, 48)
        else:
            rail_line('%s_a' % name, 'x', y0 + 8, x0, x1, T1, 48)
            rail_line('%s_b' % name, 'x', y1 - 8, x0, x1, T1, 48)


# --- T2: the roofs, the torii and the skybridge -----------------------------
def roofs():
    for name, rect in ROOFS.items():
        # The soffit of a roof is the ceiling of the street; 38 exported faces
        # pointed down wearing roof ballast, and that lump is the dark ceiling in
        # the owner's screenshot.
        slab_with_voids(name, rect, T2 - DECK, T2, ROOF_HOLES.get(name, []),
                        mat('roof_membrane'),
                        soffit=CONCRETE)
    # Rails on the roof edges that overlook the plaza or a 256-unit drop. A roof
    # edge is only an edge where the floor next to it is lower: the north roof
    # meets the west and east roofs along y 448 as one plane at 512, and the first
    # cut ran a 44-unit parapet along that join anyway, which walled off a quarter
    # of the roof line from a player walking on it. Only the frontage over the
    # plaza void is an edge there.
    rail_line('roofw_plaza', 'y', -PLAZA - 24, -PLAZA, PLAZA, T2, 44,
              gaps=((-256, -128),))          # the skybridge lands here
    rail_line('roofw_north', 'x', PLAZA - 24, -FACE, -768, T2, 44)
    rail_line('roofw_south', 'x', -PLAZA + 24, -FACE, -PLAZA, T2, 44)
    rail_line('roofe_plaza', 'y', PLAZA + 24, -PLAZA, PLAZA, T2, 44,
              gaps=((-256, -128),))          # ...and here
    rail_line('roofe_south', 'x', -PLAZA + 24, PLAZA, FACE, T2, 44)
    rail_line('roofe_north', 'x', PLAZA - 24, 768, FACE, T2, 44)
    rail_line('roofn_west', 'y', -768 + 24, PLAZA, FACE, T2, 44)
    rail_line('roofn_east', 'y', 768 - 24, PLAZA, FACE, T2, 44)
    rail_line('roofn_front_mid', 'x', PLAZA - 24, -PLAZA, PLAZA, T2, 44)
    # The torii: a raised pad, two posts, a lintel and a shimenawa-style beam.
    slab('torii_pad', (720, -176, T2), (FACE, 176, T2 + 16), LACQUER)
    for index, y in enumerate((-128, 128)):
        map_blender.prism('torii_post_%d' % index,
                          map_blender.polygon_ring((880, y), 34, sides=8), T2 + 16, T2 + 320, LACQUER,
                          source='prism')
    box('torii_kasagi', (820, -224, T2 + 320), (940, 224, T2 + 352), LACQUER)
    box('torii_shimaki', (832, -196, T2 + 288), (928, 196, T2 + 320), COLUMN, detail=True)
    box('torii_nuki', (844, -160, T2 + 232), (916, 160, T2 + 264), LACQUER)


def skybridge():
    """The spine: a glazed corridor from the roof garden to the torii plaza.

    It is 128 wide with 24-unit rails -- low enough that a player standing at the
    header line can trade shots with the two roofs it joins, and the rails run the
    bridge's own length, so the deck is not a firing platform over the decks below.
    It crosses the whole plaza in full view of both high grounds, which is the
    point: it is a 60-second boost run, not a shortcut.
    """
    slab('skybridge_deck', (-PLAZA, -256, T2 - DECK), (PLAZA, -128, T2), DECK_METAL)
    rail_line('skybridge_n', 'x', -136, -PLAZA, PLAZA, T2, 24)
    rail_line('skybridge_s', 'x', -248, -PLAZA, PLAZA, T2, 24)
    # The glazing posts, one frame every 128. A post used to be one 16-wide,
    # 40-tall panel across the whole span between the rails, which reads as a
    # window frame and walks as a wall: the engine steps up 18, so a player and a
    # bot both stop dead at the first post and the spine over the plaza connected
    # the roof garden to nothing -- the probe found nine eye cells on the deck and
    # one of them reachable. Each frame is now a pair of 12-deep piers standing in
    # the rail lines, hard against the rails so no overlap is shared with them,
    # leaving 76 of clear deck down the middle, plus a header over head height
    # (569) so the frame still reads as a frame when you walk under it.
    for index in range(-3, 4):
        for south in (True, False):
            y0 = -242 if south else -154
            box('skybridge_pier_%d_%s' % (index, 's' if south else 'n'),
                (index * 128 - 8, y0, T2), (index * 128 + 8, y0 + 12, T2 + 40), COLUMN,
                detail=True)
        # T2+72 and not T2+64: a body on the bridge deck reaches 512+56=568 and the
        # header's underside was at 576, which is 8 of clearance on a route the whole
        # arena is balanced on.  The frame still reads as a frame at 584.
        box('skybridge_header_%d' % index, (index * 128 - 8, -256, T2 + 72),
            (index * 128 + 8, -128, T2 + 112), COLUMN, detail=True)
    slab('skybridge_strip_n', (-PLAZA, -144, T2), (PLAZA, -136, T2 + 3),
         mat('light_strip_cyan'))
    slab('skybridge_strip_s', (-PLAZA, -248, T2), (PLAZA, -240, T2 + 3),
         mat('light_strip_warm'))
    for index in range(4):                           # conduit hung under the deck
        box('skybridge_conduit_%d' % index, (-384 + index * 224, -208, T2 - 64),
            (-320 + index * 224, -176, T2 - DECK), COLUMN, detail=True)


# --- the viaduct ------------------------------------------------------------
VIA_RECT = (-FACE, 704, FACE, 928)
VIADUCT_CROSSINGS = ((-648, -552), (552, 648))   # lined up with the two stair heads


def viaduct():
    """A monorail deck 192 above the north roof: two stairs, no lift.

    Holding the roof line buys the high ground over the whole plaza, and the
    guide beam down its middle splits it into two lanes so that the reward is a
    fighting position rather than an untouchable perch.
    """
    # Asphalt, not roof ballast: this is an elevated road and a player walks its
    # whole 2048 units, and the 32-unit plate's own side is a 224-unit-tall wall to
    # anyone standing under it.  Ballast read there as a cliff of boulders, which
    # is one of the two frames the walk probe photographed as a wall of rubble.
    slab_with_voids('viaduct_deck', VIA_RECT, VIA - DECK, VIA, [], ASPHALT,
                    soffit=CONCRETE)
    rail_line('viaduct_s', 'x', VIA_RECT[1] + 8, -FACE, FACE, VIA, 44,
              gaps=((-664, -536), (536, 664)))          # the two stairs arrive here
    rail_line('viaduct_n', 'x', VIA_RECT[3] - 8, -FACE, FACE, VIA, 44)
    # The guide beam is 40 tall, which is more than a step up, so a spine down
    # the whole deck divides it into two lanes that no walk connects -- and the
    # kineticore and its ammo stand in the far lane, and nothing spawns on it.
    # Two
    # 96-unit crossings, lined up with the two stairs that arrive at x +-536..664,
    # keep the beam as fighting cover and give each lane two ways in and out.
    for index, (b0, b1) in enumerate(spans(-FACE, FACE, VIADUCT_CROSSINGS, piece=16.0)):
        box('viaduct_beam_%02d' % index, (b0, 796, VIA), (b1, 836, VIA + 40), COLUMN,
            detail=True)
    # Trackside equipment, and it has to be 16 tall.  Each lane here is 84 deep,
    # a player's body is 30 wide and the walkability model samples the floor on a
    # 48 grid, so a standing prop in either lane seals it -- the probe then reads
    # the far lane, where the kineticore stands, as a pocket no player can walk to.
    # These two ducts keep the platform dressed and are stepped over: 16 is under
    # the engine's 18-unit step-up, and both lanes stay open end to end.
    for index, (x0, x1, y0, y1) in enumerate(((-496, -432, 828, 924),
                                              (-140, -76, 848, 912))):
        box('viaduct_duct_%d' % index, (x0, y0, VIA), (x1, y1, VIA + 12), COLUMN,
            detail=True)
        box('viaduct_duct_%d_plate' % index, (x0 - 6, y0 - 6, VIA + 12),
            (x1 + 6, y1 + 6, VIA + 16), GRATE, detail=True)
    # Same reason, seen from the other end: a flight wearing 4-metre ballast is a
    # staircase of loose rocks, and its risers fill the frame of anyone climbing
    # onto the deck.  Tarmac stairs read as what they are -- a road's own ramp.
    for name, foot, top, width in VIADUCT_CLIMBS:
        flight(name, foot, top, width, ASPHALT)
    for index in range(-3, 4):
        map_blender.prism('viaduct_pylon_%d' % index,
                          map_blender.polygon_ring((index * 256, 816), 40, sides=6),
                          T2, VIA - DECK, COLUMN, source='prism')
    for index, x in enumerate((-664, -536, 536, 664)):
        rail_line('viaduct_stair_rail_%d' % index, 'y', x, 472, VIA_RECT[1], T2, 44)

# --- the block's four tower fronts -------------------------------------------
# A 128-thick band standing *inside* the sky ring, so the ring's inner face is
# never seen from the street: what the player reads as "the city beyond" is the
# skybox through the gaps between the fronts. Each side is a row of segments of
# measured height; the segment in front of a canyon mouth is 192 tall on purpose
# so the street, which is otherwise a covered trench, ends on a skyline.
#
# Heights are chosen against the tiers, not by eye: 512 is flush with the T2
# surface, so a front behind a roof reads as a wall rising out of the floor you
# stand on, and 704 is flush with the viaduct, so the four corner towers are the
# only things that break the roofline.
FACADE_THICK = 128
# Where a T0-to-T1 climb stands against a front, its mouth is cut out of that
# front's plinth: the west and east climbs are 192 wide at y -368..-176, the
# station stair is 192 wide at x -400..-208 and the service ramp is 192 wide at
# x -776..-584, each with 8 of clearance so the paving reaches the wall face.
PLINTH_GAPS = {'n': ((-784, -576),), 's': ((-408, -200),),
               'w': ((-376, -168),), 'e': ((-376, -168),)}
FACADES = {
    'n': dict(axis='x', segments=((-FOOT, -PLAZA, 704), (-PLAZA, -LANE, 512), (-LANE, LANE, 192),
                                   (LANE, PLAZA, 512), (PLAZA, FOOT, 704))),
    # The south arm has no roof over its deck, so its front is the level's
    # silhouette seen from the plaza: the tallest faces, and the big ad boards.
    's': dict(axis='x', segments=((-FOOT, -PLAZA, 768), (-PLAZA, -LANE, 640), (-LANE, LANE, 192),
                                  (LANE, PLAZA, 640), (PLAZA, FOOT, 768))),
    'w': dict(axis='y', segments=((-FOOT, -PLAZA, 704), (-PLAZA, -LANE, 512), (-LANE, LANE, 192),
                                  (LANE, PLAZA, 512), (PLAZA, FOOT, 704))),
    'e': dict(axis='y', segments=((-FOOT, -PLAZA, 704), (-PLAZA, -LANE, 512), (-LANE, LANE, 192),
                                  (LANE, PLAZA, 512), (PLAZA, FOOT, 704))),
}


def facade_rect(side, a0, a1, depth_in=None, depth_out=None):
    """-> (mins, maxs) xy box for one segment of one front, `-64` to `height`."""
    inner = FOOT - FACADE_THICK if depth_in is None else depth_in
    outer = FOOT if depth_out is None else depth_out
    if side == 'n':
        return (a0, inner), (a1, outer)
    if side == 's':
        return (a0, -outer), (a1, -inner)
    if side == 'w':
        return (-outer, a0), (-inner, a1)
    return (inner, a0), (outer, a1)


def facades():
    for side in sorted(FACADES):
        for index, (a0, a1, height) in enumerate(FACADES[side]['segments']):
            (x0, y0), (x1, y1) = facade_rect(side, a0, a1)
            box('facade_%s_%02d' % (side, index), (x0, y0, -DECK), (x1, y1, height), TOWER)
            # A 64-tall plinth courses the whole block and gives the street a
            # surface to sit against; it is 16 proud of the face, which is under
            # the 15-unit player radius plus 8, so nothing catches on it.
            # A 64-tall plinth courses the whole block and gives the street a
            # surface to sit against; it is 16 proud of the face, which is under
            # the 15-unit player radius plus 8, so nothing catches on it. It stops
            # short of every climb's mouth, though: a climb starts flush with the
            # wall face, so its first tread stands inside that 16-unit band, and
            # the plinth in front of it is a 64-unit wall -- the reach probe found
            # all four T0-to-T1 climbs unenterable from the street at their own
            # foot, and a player walking up to the first step found a kerb taller
            # than a step-up with the step itself behind it.
            for gap_index, (g0, g1) in enumerate(spans(a0 + 24, a1 - 24,
                                                       PLINTH_GAPS[side], piece=16.0)):
                (px0, py0), (px1, py1) = facade_rect(side, g0, g1,
                                                     depth_in=FOOT - FACADE_THICK - 16)
                box('facade_%s_%02d_%02d_plinth' % (side, index, gap_index),
                    (px0, py0, -DECK), (px1, py1, 64), CONCRETE, detail=True)
            if height >= 640:                        # a setback top storey: the
                (cx0, cy0), (cx1, cy1) = facade_rect(side, a0 + 96, a1 - 96,     # skyline
                                                     depth_in=FOOT - 64)
                box('facade_%s_%02d_crown' % (side, index), (cx0, cy0, height),
                    (cx1, cy1, height + 128), CONCRETE, detail=True)
                box('facade_%s_%02d_beacon' % (side, index), (cx0, cy0, height + 128),
                    (cx1, cy1, height + 132), mat('light_strip_warm'),
                    detail=True)   # aircraft warning line


# The front heights are measured against the tiers -- 512 is flush with the
# roofs, 704 with the monorail -- and a flat top you can step onto from a flush
# floor is a floor. The probe found shooters standing on the fronts, 192 above
# the roof line, and every roof spawn in the level opened up: the north roof
# start had nine exposing vantages, all of them at y 1040..1136, which is the
# front's own top. A parapet the height of the deck rails along the roof-facing
# edge puts the skyline back where it was meant to be.
FACADE_RAIL_MIN = 512


def facade_parapets():
    for side in sorted(FACADES):
        inner = FOOT - FACADE_THICK
        sign = 1 if side in ('n', 'e') else -1
        coord = sign * (inner + 6)                  # the rail stands on the top,
        for index, (a0, a1, height) in enumerate(FACADES[side]['segments']):
            if height < FACADE_RAIL_MIN:            # flush with its inner face
                continue
            rail_line('facade_rail_%s_%02d' % (side, index), FACADES[side]['axis'], coord,
                      a0 + 24, a1 - 24, height, 48)


# --- the street kit: bays, relief, foot detail, landmarks -------------------
# The census that opened this round counted 24 materials doing the work of a city
# block and named the four most-used: `metal_column`, `concrete_panel`,
# `tower_front`, `prop_concrete`.  Three of those four draw a motif a *storey*
# tall -- `concrete_panel`'s is a 128-unit panel with four tie holes, so a wall
# wears three panels to the roofline and the eye finds nothing to measure itself
# against.  This is the pass that answers that, and it answers it in the one way
# a brush format allows: the surfaces a pedestrian can reach are *rebuilt* out of
# the materials a shopfront is actually made of -- tile, plaster, slat, shutter,
# painted board -- at the pitch of those materials, and the parts of the block a
# player cannot walk up to are given a service course and a sign instead of a
# curtain of one tile.
#
# Four rules run through every section below, and each one is here because of a
# specific way this file has failed before:
#
# * nothing crosses the tower-front line.  The street reads as a wall at |coord| =
#   1024, so every kit part starts *on* that plane and stands into the street.
#   Sinking 8 into the wall to "make sure it touches" would put the box 8 past
#   `FACE` and `verify` would charge it as crossing, which is what the first draft
#   of this pass did;
# * every part is named `facade_*`, because that is what it is: the block's own
#   finish, in the same exemption class as the plinth course that already runs the
#   block.  `verify`'s crossing rule is axis-symmetric and does not know which
#   front a brush belongs to, so a bay at the corner of the north front -- 1136 in
#   x, 1024 in y -- reads to it as a brush crossing the *east* front's line.  The
#   climb audit is not exempted, and should not be: a kit part in a flight of
#   steps is a defect whatever it is called;
# * nothing stands inside a flight of steps.  Both bands are cut at every climb's
#   own mouth, and the mouths are *derived* from the climbs rather than retyped,
#   because a stair owns the air above its treads up to the floor it arrives at and
#   the table that remembers that has drifted twice;
# * nothing narrows a lane.  The fitout stands 12 proud of a wall 148 units from
#   the nearest walking line and the relief 32 proud of the same wall, which leaves
#   100 units of a 30-unit body's clearance unspent.  The four alley mouths are cut
#   out of the deck band, because that is where a footbridge lands.
KIT_WALLS = ('plaster_warm', 'tile_cream', 'stucco_pale', 'shutter_steel', 'brick_deep',
             'slat_timber', 'panel_blue', 'tile_dark', 'corrugated_rust', 'tile_sage',
             'shutter_green', 'plaster_slate', 'slat_dark', 'concrete_rough')
#: The materials a *closed* bay wears: a board, a hoarding, a wall papered over.
KIT_PANELS = ('poster_wall', 'slat_dark', 'brick_deep', 'panel_blue', 'corrugated_rust',
              'tile_dark', 'plaster_slate', 'stucco_pale', 'tile_sage', 'plaster_warm')
#: Every sign face in the arena, in the order the bays take them.  A run of three
#: boards on one facade is three pictures, not one picture repeated three times --
#: which is the failure `neon_a` tiled at a 256 repeat produced (DESIGN.md 5).
KIT_SIGNS = ('sign_band_a', 'sign_vertical', 'sign_band_b', 'sign_menu', 'banner_red',
             'sign_vertical_b', 'wayfinding_blue', 'neon_c', 'vend_face_b', 'banner_white',
             'vend_face_c', 'ad_board_b', 'sign_band_a', 'sign_vertical_b')
#: The three finishes a locked shutter is painted in, and the two hazard colours a
#: kerb, an A-frame board and a planter rim are striped with.
KIT_SHUTTERS = ('shutter_steel', 'shutter_green', 'corrugated_rust')
KIT_HAZARD = ('prop_paint_yellow', 'prop_paint_green')
#: How far apart two pilasters stand, and how far each kit part reaches into the
#: street.  192 is the pitch the colonnade already uses, so the new rhythm does not
#: argue with the old one; 12 proud is a shopfront's face and 40 proud is a sign you
#: can read from three sides.
FITOUT_PITCH, FITOUT_PROUD, RELIEF_PROUD = 192.0, 12.0, 32.0
#: The two walk-up bands.  A: the street's shopfront row, standing on the block's
#: own 64-tall plinth course.  B: the same row at deck level, standing on the deck
#: itself.  Both are 152 tall, which is a storey's worth of glass and board under a
#: 224-unit clear storey, and both stop short of the roof over their own tier.
FITOUT_BANDS = ((64.0, 216.0), (float(T1), float(T1) + 152.0))
#: Where the sign goes above a band, and how tall it is.
FITOUT_SIGN_LIP, FITOUT_SIGN_TALL = 4.0, 56.0
#: Where a front stops being a face anybody can see.  The four fronts are authored as
#: four full strips and so overlap in the four corner squares: at x 1100 the north
#: front's face exists on paper, but it is buried inside the *east* wall, which runs
#: the whole y extent.  Kit laid there is invisible geometry inside a solid, so every
#: run on every front is clipped to the perpendicular front's own face line.
KIT_LIMIT = FACE - 8.0


def _clip(a0, a1):
    """-> the stretch of one front a kit part may actually be seen on."""
    return max(a0, -KIT_LIMIT), min(a1, KIT_LIMIT)


def _chunks(a0, a1, gaps, size, piece=None):
    """-> the clear spans of a front, cut by `gaps` and then chopped to `size`.

    `spans` alone returns the whole remaining run as one interval, so one crate
    parked in a painted strip costs the entire strip and one shopfront is written
    350 units wide under a sign meant for a 192 pitch.  Chopping first keeps a piece
    the size of the thing it wears and keeps a refusal local to one bay.
    """
    out = []
    for r0, r1 in spans(a0, a1, gaps, piece=piece if piece is not None else size):
        count = max(1, int(round((r1 - r0) / float(size))))
        step = (r1 - r0) / float(count)
        for index in range(count):
            out.append((r0 + step * index, r0 + step * (index + 1)))
    return out
#: The courses nobody walks up to but everybody looks at.  Both sit above 568 --
#: a body on a roof is 512 plus its own 56 -- because a condenser hood standing
#: where a roof walk line passes is not relief, it is an obstacle at shin height.
RELIEF_BANDS = ((584.0, 614.0), (656.0, 686.0))
RELIEF_HOOD_LIP, RELIEF_HOOD_TALL = 10.0, 22.0


def _climb_front_gaps(climbs):
    """-> {side: [(along0, along1), ...]}, the strip each climb owns on a front.

    A climb is authored from the face it is measured from, so the front it stands
    against and the strip it occupies are both readable from its own start, end and
    width -- which is the only reason this list survives the next time a stair is
    re-cut.  8 units of clearance, the same the plinth uses.
    """
    out = {'n': [], 's': [], 'w': [], 'e': []}
    for _name, start, end, width in climbs:
        run = 0 if abs(end[0] - start[0]) > abs(end[1] - start[1]) else 1
        across = 1 - run
        c0 = min(start[across], end[across]) - width / 2.0 - 8.0
        c1 = max(start[across], end[across]) + width / 2.0 + 8.0
        touch = start[run] if abs(start[run]) > abs(end[run]) else end[run]
        side = ('e' if touch > 0 else 'w') if run == 0 else ('n' if touch > 0 else 's')
        out[side].append((c0, c1))
    return dict((side, tuple(ranges)) for side, ranges in out.items())


#: The four T0-to-T1 mouths.  Derived, then checked against the plinth's own table:
#: the two must agree or one of them is wrong about where a stair stands, and a
#: silent disagreement between two tables of the same fact is how the plinth ended up
#: walling off four climbs in the first place.
FITOUT_GAPS_GROUND = _climb_front_gaps((CLIMB_S, CLIMB_N, CLIMB_W, CLIMB_E))
for _side in ('n', 's', 'w', 'e'):
    _derived = [tuple(float(v) for v in one) for one in FITOUT_GAPS_GROUND[_side]]
    _course = [tuple(float(v) for v in one) for one in PLINTH_GAPS[_side]]
    if _derived != _course:
        print('japanDM: fitout and plinth disagree about %s: %s vs %s'
              % (_side, _derived, _course))
#: The three T1-to-T2 mouths, which the deck band owes the roof climbs.
FITOUT_GAPS_DECK = _climb_front_gaps((ROOF_CLIMB_W, ROOF_CLIMB_N, ROOF_CLIMB_E))
#: Where a footbridge lands on the deck band, so the fitout stops at the canyon.
ALLEY_GAPS = ((-(LANE + 8.0), LANE + 8.0),)


def _face_box(name, side, a0, a1, proud, z0, z1, material, detail=True):
    """-> one kit part standing `proud` into the street off one tower front.

    The box starts exactly on the face plane rather than inside the wall: `FACE`
    is the line `verify` refuses to let anything cross, and the face plane *is*
    that line, so a part that touches it and stands into the street is legal and a
    part that is sunk 8 into the wall to make sure it touches is a defect.
    """
    inner = FOOT - FACADE_THICK
    if side == 'n':
        return box(name, (a0, inner - proud, z0), (a1, inner, z1), material, detail=detail)
    if side == 's':
        return box(name, (a0, -inner + proud, z0), (a1, -inner, z1), material, detail=detail)
    if side == 'w':
        return box(name, (-inner + proud, a0, z0), (-inner, a1, z1), material, detail=detail)
    return box(name, (inner - proud, a0, z0), (inner, a1, z1), material, detail=detail)


def _front_gaps(side, band):
    """-> the mouths cut out of one front's band, derived from the level's climbs."""
    gaps = FITOUT_GAPS_GROUND[side]
    if band:
        gaps = FITOUT_GAPS_GROUND[side] + FITOUT_GAPS_DECK.get(side, ()) + ALLEY_GAPS
    return gaps


def facade_fitout():
    """Re-surface the two bands a player walks up to, one bay at a time.

    A bay is a pilaster, then one of four shopfronts -- glazed, shuttered, boarded
    or an open entry -- and then either a fascia board flat on the wall or a blade
    sign projecting over the street.  Which one a bay gets is decided by its own
    address rather than by a random draw, so the level builds the same way twice and
    a reviewer can stand in the same place in two rounds and compare them.
    """
    made = []
    for side in sorted(FACADES):
        for index, (a0, a1, height) in enumerate(FACADES[side]['segments']):
            for band, (z0, z1) in enumerate(FITOUT_BANDS):
                if z1 > height - 8.0:                # the band would stand outside
                    continue                          # the wall it is built onto
                for run_index, (r0, r1) in enumerate(_chunks(*_clip(a0 + 16, a1 - 16),
                                                              _front_gaps(side, band),
                                                              size=320.0, piece=128.0)):
                    pitch = int((r0 + r1) / 2.0 / FITOUT_PITCH) + index * 7 + band * 3
                    made += _bay('facade_%s%02d_%02d_%d' % (side, index, run_index, band),
                                 side, r0, r1, z0, z1, height, pitch, band)
    print('japanDM: facade fitout laid %d pieces on the two walk-up bands' % len(made))
    return made


def _bay(name, side, r0, r1, z0, z1, height, pitch, band):
    """-> the kit parts for one stretch of one band of one front."""
    made = []
    # The pilaster first: it is what a bay is, and everything else is measured from
    # its inner edge.  32 proud on a 192 pitch is the column rhythm a shopping
    # street's ground floor is built on, and it is the one part of this pass that
    # reads at the far end of a lane as well as at arm's length.  It is not `detail`:
    # it is the piece that casts the shadow the relief is supposed to read as.
    wall = mat(KIT_WALLS[pitch % len(KIT_WALLS)])
    made.append(_face_box('%s_pil_plinth' % name, side, r0, r0 + 32.0, RELIEF_PROUD, z0, z1,
                          mat(KIT_WALLS[(pitch + 5) % len(KIT_WALLS)]), detail=False))
    a0, a1 = r0 + 44.0, r1 - 8.0
    if a1 - a0 < 48.0:
        return made
    kind = pitch % 4
    if kind == 0:                                    # a glazed shopfront
        made.append(_face_box('%s_jamb_lo_flange' % name, side, a0, a0 + 14.0, FITOUT_PROUD,
                              z0, z1, wall))
        made.append(_face_box('%s_jamb_hi_flange' % name, side, a1 - 14.0, a1, FITOUT_PROUD,
                              z0, z1, wall))
        made.append(_face_box('%s_lintel_flange' % name, side, a0, a1, FITOUT_PROUD,
                              z1 - 28.0, z1, wall))
        # The glass sits 8 behind the frame rather than in it, which is what makes
        # the bay read as recessed: a brush cannot be hollow, so depth in this
        # format is a shadow gap and a normal map, and nothing else.
        made.append(_face_box('%s_glass' % name, side, a0 + 14.0, a1 - 14.0, FITOUT_PROUD - 8.0,
                              z0, z1 - 28.0, GLASS))
    elif kind == 1:                                  # a shutter, down and locked
        made.append(_face_box('%s_shutter_flange' % name, side, a0 + 6.0, a1 - 6.0,
                              FITOUT_PROUD, z0 + 4.0, z1 - 4.0,
                              mat(KIT_SHUTTERS[pitch % len(KIT_SHUTTERS)])))
        made.append(_face_box('%s_lintel_flange' % name, side, a0, a1, FITOUT_PROUD,
                              z1 - 20.0, z1, wall))
    elif kind == 2:                                  # a boarded hoarding or a poster wall
        made.append(_face_box('%s_board_flange' % name, side, a0, a1, FITOUT_PROUD, z0,
                              z1 - 20.0, mat(KIT_PANELS[pitch % len(KIT_PANELS)])))
        made.append(_face_box('%s_rail_flange' % name, side, a0, a1, FITOUT_PROUD + 6.0,
                              z1 - 20.0, z1, mat('slat_timber')))
    else:                                            # a recessed entry, open to the wall
        made.append(_face_box('%s_pier_lo_flange' % name, side, a0, a0 + 20.0, FITOUT_PROUD,
                              z0, z1, wall))
        made.append(_face_box('%s_pier_hi_flange' % name, side, a1 - 20.0, a1, FITOUT_PROUD,
                              z0, z1, wall))
        made.append(_face_box('%s_head_flange' % name, side, a0 + 20.0, a1 - 20.0,
                              FITOUT_PROUD - 8.0, z1 - 24.0, z1, mat('concrete_rough')))
    # The sign, and this is the whole argument of the pass: a plate with a margin
    # and one glyph in it, at the size the brush that wears it actually is.  At
    # street level it is a fascia across the head of the shopfront, because the
    # market deck's own slab crosses this band 8 units above its top -- an overhead
    # board there would be a sign buried in a floor.
    sign = mat(KIT_SIGNS[pitch % len(KIT_SIGNS)])
    blade = kind == 3
    if band == 0:
        s0, s1 = z1 - 40.0, z1
    else:
        s0, s1 = z1 + FITOUT_SIGN_LIP, z1 + FITOUT_SIGN_LIP + FITOUT_SIGN_TALL
        blade = blade or s1 > height - 4.0
    if not blade:
        made.append(_face_box('%s_band_glow' % name, side, a0, a1, FITOUT_PROUD + 4.0, s0, s1,
                              sign))
    else:
        # A blade sign is the other half of a Japanese street's silhouette, and it
        # is the only part of this pass that reaches far enough into the street to be
        # read from the opposite pavement.  It hangs in the air a bay leaves between
        # its own head and whatever is over it, so it can never share a bay's volume.
        b0, b1 = (z0 + 80.0, z1 - 8.0) if band == 0 else (z1 + 2.0, z1 + 42.0)
        made.append(_face_box('%s_blade_glow' % name, side, a0 + 20.0, a0 + 48.0,
                              RELIEF_PROUD + 8.0, b0, b1, sign))
    return made


def wall_relief():
    """The courses nobody walks up to, but everybody looks at.

    Above the deck the block is 512 to 768 tall and it used to be one curtain-wall
    tile from the roofline to the parapet.  A service duct on a bracket course and a
    row of condenser hoods are what a facade between windows actually carries, they
    are all 16-40 units proud, and at a 192-unit pitch they give a 700-unit wall the
    same rhythm the ground floor has.
    """
    made = []
    for side in sorted(FACADES):
        for index, (a0, a1, height) in enumerate(FACADES[side]['segments']):
            for band_index, (z0, z1) in enumerate(RELIEF_BANDS):
                if z1 + RELIEF_HOOD_LIP + RELIEF_HOOD_TALL > height - 12.0:
                    continue
                for run_index, (r0, r1) in enumerate(_chunks(*_clip(a0 + 32, a1 - 32),
                                                              _front_gaps(side, band_index),
                                                              size=320.0, piece=160.0)):
                    tag = 'facade_%s%02d_r%02d_b%d' % (side, index, run_index, band_index)
                    pitch = int(r0 / FITOUT_PITCH) + index * 5 + band_index
                    # The duct: a continuous run, broken only at a bay line, so it
                    # reads as one conduit crossing the block rather than as a row of
                    # boxes, and it is the one part of the upper wall a player can
                    # identify as made by hand rather than by a texture.
                    made.append(_face_box('%s_duct_flange' % tag, side, r0, r1, 20.0, z0, z1,
                                          mat('corrugated_rust'), detail=False))
                    for step in range(int((r1 - r0) / FITOUT_PITCH) + 1):
                        b0 = r0 + step * FITOUT_PITCH
                        if b0 + 28.0 > r1:
                            continue
                        made.append(_face_box('%s_brk%02d_flange' % (tag, step), side, b0,
                                              b0 + 28.0, RELIEF_PROUD, z0, z1,
                                              mat('metal_column')))
                        if b0 + 128.0 <= r1:
                            made.append(_face_box('%s_hood%02d_flange' % (tag, step), side,
                                                  b0 + 40.0, b0 + 120.0, 24.0,
                                                  z1 + RELIEF_HOOD_LIP,
                                                  z1 + RELIEF_HOOD_LIP + RELIEF_HOOD_TALL,
                                                  mat(KIT_PANELS[(pitch + step)
                                                                % len(KIT_PANELS)])))
            # One wayfinding plate per tall segment, at the course above the roof
            # line: a network sign rather than a shop sign, which is what makes a
            # row of boards read as a street with a system instead of a pile.
            if height >= 640:
                for run_index, (r0, r1) in enumerate(spans(*_clip(a0 + 160, a1 - 160),
                                                           _front_gaps(side, 1), piece=200.0)):
                    if run_index:
                        continue
                    made.append(_face_box('facade_%s%02d_way_glow' % (side, index), side,
                                          r0, r0 + 180.0, 18.0, RELIEF_BANDS[0][0] - 40.0,
                                          RELIEF_BANDS[0][0] + 8.0, mat('wayfinding_blue')))
    print('japanDM: wall relief laid %d pieces above the walk-up bands' % len(made))
    return made


def _rect_clear(low, high, why=None):
    """-> whether a rect from `low` to `high` has the storey to itself.

    The square footprint `_site_clear` tests is right for a column and wrong for a
    building: the deck's colonnade is a lattice on a 256 pitch with a 296-unit strip
    between its rows, and the only way to find the strip is to ask about the rect the
    thing actually has.  With `why` the reason is printed, because a landmark that
    silently never got built is the failure this file keeps having.
    """
    for rect in VOID_KEEPOUT.get(int(low[2]), ()):
        if (rect[0] < high[0] and rect[2] > low[0] and rect[1] < high[1]
                and rect[3] > low[1]):
            if why is not None:
                print('japanDM: %s: a stairwell is open under it' % why)
            return False
    if not route_clear(low, high):
        if why is not None:
            # Which promise, said out loud: a climb and a street lane need opposite
            # remedies -- one moves the landmark, the other only needs it off the
            # centre line -- and a refusal that does not say which has cost this file
            # a build cycle per guess.
            which = 'a climbing route' if not climb_route_clear(low, high) else \
                    'a street lane'
            print('japanDM: %s: %s runs through it' % (why, which))
        return False
    for name, other_low, other_high, kind in BOXES:
        if kind in ('detail', 'rail', 'trigger', 'loose') or name.startswith(SHELLS):
            continue
        if high[2] <= other_low[2] + 2.0 or low[2] >= other_high[2] - 2.0:
            continue
        if (other_low[0] < high[0] and other_high[0] > low[0]
                and other_low[1] < high[1] and other_high[1] > low[1]):
            if why is not None:
                print('japanDM: %s: %s already stands there' % (why, name))
            return False
    for _name, place, _angle in SPAWNS:
        if (place[0] - 88.0 < high[0] and place[0] + 88.0 > low[0]
                and place[1] - 88.0 < high[1] and place[1] + 88.0 > low[1]
                and abs(place[2] - low[2]) < 64.0):
            if why is not None:
                print('japanDM: %s: it is a player\'s own start' % why)
            return False
    return True


def _lm_frame(axis, front, rect):
    """-> (u0, u1, v0, v1, to_world, to_point) for a landmark built along one street.

    `u` runs along the street, `v` crosses it, and `v` grows toward `front`, which is
    the side the shop's own stair stands on.  A landmark written in this frame is
    placed on any arm of the deck by naming the arm and the facing; written in world
    corners it is one arm's geometry with a rotation bolted on, and that is exactly
    how the first vendor grew steps that only ever pointed +y -- correct on the north
    arm and buried in the tower's own face on the other three.
    """
    (x0, y0, _z0), (x1, y1, _z1) = rect
    if axis == 'x':
        u0, u1 = x0, x1
        v0, v1 = sorted((front * y0, front * y1))
    else:
        u0, u1 = y0, y1
        v0, v1 = sorted((front * x0, front * x1))

    def to_world(ua, va, ub, vb, za, zb):
        """-> world mins/maxs for a box given in the landmark's own frame."""
        if axis == 'x':
            along, across = (ua, ub), (front * va, front * vb)
        else:
            along, across = (front * va, front * vb), (ua, ub)
        return ((min(along), min(across), min(za, zb)),
                (max(along), max(across), max(za, zb)))

    def to_point(ua, va, za):
        return to_world(ua, va, ua, va, za, za)[0]

    return u0, u1, v0, v1, to_world, to_point


def _landmark_vendor(name, axis, front, rect, seed=0):
    """-> the T1 landmark: a vendor block with its own stair, awning and sign band.

    A shop, not a crate with an awning on it: the block stands on its own deck plate,
    its door sits under its own landing, its noren hangs under its own awning, and its
    sign band is the picture a player steers by from the far end of the deck.  Every
    piece is authored in the block's own frame (`_lm_frame`) and every one stands
    inside the storey `landmarks` tested clear, so a block that fits on the south arm
    fits on the east arm without a second geometry.

    The storeys are not a preference.  `landmarks` tests 216 units of air from the
    deck floor and nothing may cross `FACE`, so the tallest thing here -- the blade
    sign -- stops below the parapet ring, and the parapet a player can reach from the
    landing stops 56 above it rather than offering a ledge onto the deck's own roof.
    """
    u0, u1, v0, v1, W, P = _lm_frame(axis, front, rect)

    def part(tag, ua, va, ub, vb, za, zb, material, **kw):
        low, high = W(ua, va, ub, vb, za, zb)
        return box('%s_%s' % (name, tag), low, high, material, **kw)

    face = v1 - 8.0                            # the body's own street-facing wall
    uc = (u0 + u1) / 2.0                       # the door sits on the block's axis
    band_lo, top = T1 + 144.0, T1 + 168.0
    made = [part('deck', u0, v0, u1, v1, T1, T1 + 16.0, mat('deck_timber'),
                 source='slab', kind='slab', soffit=CONCRETE)]
    made.append(part('body', u0 + 8.0, v0 + 8.0, u1 - 8.0, face, T1 + 16.0, top,
                     mat(KIT_WALLS[seed % len(KIT_WALLS)])))
    # Two sign bands, on the two long faces, in two different plates of the kit and
    # stopped short of the corners: one picture repeated on both faces is the `neon_a`
    # failure DESIGN.md 5 already records, and a band that runs to the corner leaves
    # nothing for the blade signs to stand on.
    made.append(part('band_a_glow', u0 + 56.0, v0 + 2.0, u1 - 56.0, v0 + 10.0, band_lo,
                     top, mat(KIT_SIGNS[seed % len(KIT_SIGNS)]), detail=True))
    made.append(part('band_b_glow', u0 + 56.0, v1 - 10.0, u1 - 56.0, v1 - 2.0, band_lo,
                     top, mat(KIT_SIGNS[(seed + 5) % len(KIT_SIGNS)]), detail=True))
    # A parapet is a ring, not a lid: one box across the whole footprint would hover
    # 24 over the block's own roof, and a floating slab is the read this whole pass
    # exists to kill.  Four pieces, each standing on the wall it belongs to.
    for index, (pa0, pa1, pb0, pb1) in enumerate((
            (u0 + 6.0, u1 - 6.0, v1 - 18.0, v1 - 6.0),
            (u0 + 6.0, u1 - 6.0, v0 + 6.0, v0 + 18.0),
            (u0 + 6.0, u0 + 18.0, v0 + 6.0, v1 - 6.0),
            (u1 - 18.0, u1 - 6.0, v0 + 6.0, v1 - 6.0))):
        made.append(part('parapet%02d' % index, pa0, pb0, pa1, pb1, top, top + 8.0,
                         mat('slat_timber'), detail=True))
    # The stair, its landing and the door it exists for.  `flight` sizes its treads
    # off the *run* and then adds steps until every rise fits the engine's step, so a
    # 64-unit lift across an 80-unit run gives five treads 16 deep and 12.8 up -- one
    # footfall per tread for a 32-unit hull.  The old block asked for a 96 lift in the
    # same air and got a flight whose treads were shallower than the player climbing
    # them, which is the "stairs too big to be real" the owner named.
    made.append(part('landing', uc - 52.0, v1 - 8.0, uc + 52.0, v1 + 8.0, T1 + 56.0,
                     T1 + 64.0, mat('deck_timber'), source='slab', kind='slab',
                     soffit=CONCRETE))
    made += flight('%s_steps' % name, P(uc, v1 + 88.0, float(T1)),
                   P(uc, v1 + 8.0, T1 + 64.0), 88.0, mat('deck_timber'))
    # The two shoulders beside the steps, built as cheeks rather than as rails:
    # `rail`/`rail_line` build axis-aligned boxes and plant a post at each end of the
    # run, so a rail along a 16-deep landing put its post *inside* the block's own wall
    # and its glass across the mouth the steps walk through.  A cheek is the thing a
    # real external stair has, it carries the landing's shadow, and it stops the
    # landing reading as a ledge onto the roof.
    for side, su in ((0, uc - 52.0), (1, uc + 44.0)):
        made.append(part('cheek%d' % side, su, v1 - 8.0, su + 8.0, v1 + 8.0, T1 + 64.0,
                         T1 + 104.0, mat(KIT_WALLS[(seed + 3) % len(KIT_WALLS)])))
    # The door under the landing and its head board above it, both on the block's own
    # face: a stair that arrives at a wall is a defect wearing the silhouette this
    # pass was asked for, so the glass and the lintel are built here, not assumed.
    made.append(part('door_glass', uc - 36.0, v1 - 16.0, uc + 36.0, v1 - 8.0, T1 + 16.0,
                     T1 + 56.0, GLASS, detail=True))
    made.append(part('door_glow', uc - 32.0, v1 - 14.0, uc + 32.0, v1 - 10.0, T1 + 20.0,
                     T1 + 52.0, mat('light_strip_warm'), detail=True))
    made.append(part('head_glow', uc - 44.0, v1 - 16.0, uc + 44.0, v1 - 8.0, T1 + 64.0,
                     T1 + 80.0, mat(KIT_SIGNS[(seed + 2) % len(KIT_SIGNS)]), detail=True))
    # The awning over the steps, and the noren hung at its outer edge: the pair a
    # customer ducks under, and the only cloth in the level at the scale a street is
    # read at.  48 of clearance over the top tread is the awning's own headroom; below
    # it the noren marks the door without closing it.
    made.append(part('awning_flange', uc - 60.0, v1 - 8.0, uc + 60.0, v1 + 64.0,
                     T1 + 112.0, T1 + 132.0, CLOTH, detail=True))
    panel = 104.0 / 3.0
    for index in range(3):
        made.append(part('noren%d_glow' % index, uc - 52.0 + index * panel, v1 + 56.0,
                         uc - 52.0 + index * panel + panel - 10.0, v1 + 64.0, T1 + 72.0,
                         T1 + 112.0, mat('noren_strip'), detail=True))
    # One vertical blade per corner, readable from both ends of the arm because they
    # face along the street rather than across it.
    for index, bu in enumerate((u0 + 10.0, u1 - 26.0)):
        made.append(part('blade%d_glow' % index, bu, v1 - 8.0, bu + 16.0, v1 + 30.0,
                         T1 + 32.0, T1 + 164.0,
                         mat(KIT_SIGNS[(seed + 8 + index) % len(KIT_SIGNS)]), detail=True))
    return made


def landmarks():
    """One thing per tier you can navigate by, chosen by the level's own geometry.

    The census of sightlines found the arena's three tiers hold together as *space*
    and not as *places*: every direction looks like the same colonnade, because
    nothing in it is unique.  A lantern court, a vendor block and a mast are three
    unique things, each standing where the level's own checks say nothing else
    needs the air, and each candidate is printed whether it was taken or refused --
    a landmark that quietly failed to place is the failure this file keeps having.
    """
    made = []
    # --- T0: the lantern court, a ring of paving and four posts round the pool ----
    ring, ring_z = 64.0, 8.0
    inner, outer = 176.0, 176.0 + ring
    for index, (low, high) in enumerate((
            ((-inner, inner, T0), (inner, outer, T0 + ring_z)),
            ((-inner, -outer, T0), (inner, -inner, T0 + ring_z)),
            ((inner, -outer, T0), (outer, outer, T0 + ring_z)),
            ((-outer, -outer, T0), (-inner, outer, T0 + ring_z)))):
        made.append(box('lantern_court_ring%d_plinth' % index, low, high, mat('paving_court'),
                        detail=True))
    # The four sites `map_site_probe` found against the scene as it stands before the
    # landmarks are built: the earlier pair at +-224 sat on the two bridge plinths, and
    # a landmark that is refused by a pier is a landmark that silently does not exist.
    # +-384 is out past the arcade's first column row, so the court is the first thing
    # a player walking any of the four lanes into the plaza meets.
    for index, (px, py) in enumerate(((-384, -224), (384, -224), (384, 224), (-384, 224))):
        if not _rect_clear((px - 20.0, py - 20.0, float(T0)), (px + 20.0, py + 20.0, T0 + 288.0),
                           'lantern post %d' % index):
            continue
        if _rect_clear((px - 30.0, py - 30.0, float(T0)), (px + 30.0, py + 30.0,
                                                           float(T0) + 4.0),
                       'lantern post %d footring' % index):
            made.append(box('lantern_court_foot%d_plinth' % index, (px - 30.0, py - 30.0, T0),
                            (px + 30.0, py + 30.0, T0 + 4.0), mat('paving_court'),
                            detail=True))
        made.append(box('lantern_court_post%d' % index, (px - 20.0, py - 20.0, T0),
                        (px + 20.0, py + 20.0, T0 + 288.0), mat('slat_timber')))
        made.append(box('lantern_court_lantern%d_glow' % index, (px - 32.0, py - 32.0, T0 + 200.0),
                        (px + 32.0, py + 32.0, T0 + 272.0),
                        mat(('banner_red', 'banner_white')[index % 2]), detail=True))
        made.append(box('lantern_court_cap%d_cap' % index, (px - 26.0, py - 26.0, T0 + 288.0),
                        (px + 26.0, py + 26.0, T0 + 300.0), mat('metal_brass'), detail=True))
    # --- T1: the vendor block, on the arm whose strip the probe found clear --------
    # Each candidate is an arm, a facing and the body's own footprint, which is what
    # `_lm_frame` needs and what the probe searched with -- so the site a search
    # offered and the site that gets built are the same statement, not a translation
    # of one.  The keep-out asked about is the block *plus* its stair and awning*, so
    # a site that answers here is a site the whole building fits.
    taken = 0
    for (tag, axis, front, body, seed) in (
            ('vendor_s', 'x', +1, ((100.0, -700.0), (340.0, -560.0)), 0),
            ('vendor_e', 'y', -1, ((680.0, -728.0), (820.0, -488.0)), 1),
            ('vendor_n', 'x', -1, ((100.0, 680.0), (340.0, 820.0)), 2)):
        if taken >= 2:
            break
        u0, u1, v0, v1, W, _P = _lm_frame(axis, front, (body[0] + (float(T1),),
                                                        body[1] + (float(T1),)))
        low, high = W(u0 - 8.0, v0 - 8.0, u1 + 8.0, v1 + 104.0, float(T1), T1 + 216.0)
        if not _rect_clear(low, high, tag):
            continue
        print('japanDM: %s takes arm %s facing %+d, %d,%d to %d,%d'
              % (tag, axis, front, body[0][0], body[0][1], body[1][0], body[1][1]))
        made += _landmark_vendor(tag, axis, front, (body[0] + (float(T1),),
                                                    body[1] + (float(T1),)), seed)
        taken += 1
    # --- T2: the mast, a plinth and a column you can set a bearing on -------------
    # The one roof site `map_site_probe` found inside the view cone of *two* starts
    # (`garden` and `roof_e`), which is the whole point of a landmark: the census wants
    # a thing identifiable from two different starts per tier, and a mast nobody's
    # spawn is aimed at is scenery for nobody.
    for index, (mx, my) in enumerate(((-580.0, 140.0), (-540.0, 100.0), (860.0, -300.0),
                                      (-540.0, -300.0))):
        if not _rect_clear((mx - 60.0, my - 60.0, float(T2)), (mx + 60.0, my + 60.0,
                                                               T2 + 384.0),
                           'roof mast %d' % index):
            continue
        print('japanDM: roof mast %d stands at %d,%d' % (index, mx, my))
        if _rect_clear((mx - 96.0, my - 96.0, float(T2)), (mx + 96.0, my + 96.0,
                                                           float(T2) + 4.0),
                       'roof mast %d apron' % index):
            made.append(box('roof_mast%d_apron_plinth' % index, (mx - 96.0, my - 96.0, T2),
                            (mx + 96.0, my + 96.0, T2 + 2.0), mat('paving_court'),
                            detail=True))
        made.append(box('roof_mast%d_plinth' % index, (mx - 48.0, my - 48.0, T2),
                        (mx + 48.0, my + 48.0, T2 + 16.0), mat('concrete_rough')))
        made.append(box('roof_mast%d_column' % index, (mx - 20.0, my - 20.0, T2 + 16.0),
                        (mx + 20.0, my + 20.0, T2 + 384.0), COLUMN))
        made.append(box('roof_mast%d_panel_glow' % index, (mx - 28.0, my - 8.0, T2 + 200.0),
                        (mx + 28.0, my + 8.0, T2 + 340.0), mat('sign_vertical'), detail=True))
        made.append(box('roof_mast%d_cap_glow' % index, (mx - 30.0, my - 30.0, T2 + 352.0),
                        (mx + 30.0, my + 30.0, T2 + 368.0), mat('neon_c'), detail=True))
        made += post_row('roof_mast%d_stay_post' % index, (mx, my), 88.0, 4, 40.0,
                         mat('metal_brass'), size=12.0, sides=4, base=T2)
        break
    print('japanDM: landmarks laid %d pieces' % len(made))
    return made


def foot_detail():
    """The two-unit pass on the floor a player actually walks on.

    A night street is painted, drained and kerbed before it is anything else, and
    the eye looks *down* when it moves: the ground is where the scale of a level is
    measured.  Nothing here stands more than 3 units proud of the floor it lies on,
    which is a sixth of the engine's step -- the player walks over all of it and
    reads shadow where a 1999 arena reads a plate.  Every piece asks the same
    question `surface_marks` asks, and this section runs after the props for the
    same reason: a painted line across a bin, or floating over a stairwell, is the
    exact defect this pass exists to prevent.
    """
    def clear(low, high, on_z):
        """-> whether a band sits on floor and has nothing standing in it."""
        standing = False
        for name, other_low, other_high, kind in BOXES:
            if kind in ('rail', 'trigger', 'loose', 'hint') or name.startswith(SHELLS):
                continue
            if not (other_low[0] < high[0] and other_high[0] > low[0]
                    and other_low[1] < high[1] and other_high[1] > low[1]):
                continue
            if abs(other_high[2] - on_z) <= 3.0 and other_low[2] < on_z:
                standing = True                     # the plate this paint lies on
            elif other_low[2] < high[2] and other_high[2] > low[2]:
                return False                        # something else lives here
        return standing

    def paint(name, low, high, on_z, material):
        return box(name, low, high, material, detail=True) if clear(low, high, on_z) else None

    made = []
    # --- the pavement in front of the shopfronts, and its two edges --------------
    # Gutter, kerb, tactile strip, carriageway: four bands of a 128-unit stretch of
    # the block front, which is the width the eye has to cross before it reaches the
    # arcade across the street, and the reason a lane stopped reading as a section.
    for side in sorted(FACADES):
        along_x = side in ('n', 's')
        for index, (a0, a1, _height) in enumerate(FACADES[side]['segments']):
            for step, (s0, s1) in enumerate(_chunks(*_clip(a0 + 16, a1 - 16),
                                                     _front_gaps(side, 0),
                                                     size=160.0, piece=64.0)):
                # `s0`/`s1` are the along-street extent of one stretch of front;
                # `across` is measured from the wall face toward the middle of the
                # street, and `rect` turns that into world coordinates for whichever
                # front is being walked.  The inner `spans` this loop used to carry
                # had no gaps and so returned the outer span whole -- the same span,
                # counted twice, for a name that changed and geometry that did not.
                def rect(at0, at1, across0, across1, z0, z1, s0=s0, s1=s1):
                    if along_x:
                        return ((s0, across0, z0), (s1, across1, z1)) if side == 'n' \
                            else ((s0, -across1, z0), (s1, -across0, z1))
                    return ((-across1, s0, z0), (-across0, s1, z1)) if side == 'w' \
                        else ((across0, s0, z0), (across1, s1, z1))
                tag = 'foot_%s%02d_%02d' % (side, index, step)
                face = FOOT - FACADE_THICK
                for piece in (
                        # The apron stops at the plinth's own street face, not at the
                        # wall behind it.  The plinth stands 16 proud of the facade
                        # and `clear()` never sees it, because it is a shell -- so
                        # paving laid to `face` is paving 16 deep inside the plinth,
                        # and the audit charges the paving for it.
                        ('apron', mat('paving_lane'), face - 96.0, face - 16.0, 0.0, 2.0),
                        ('grate', mat('grate_drain'), face - 64.0, face - 32.0, 0.0, 3.0),
                        ('kerb', mat('kerb_granite'), face - 100.0, face - 96.0, 0.0, 6.0),
                        ('tactile', mat('tactile_yellow'), face - 128.0, face - 104.0,
                         0.0, 2.0),
                        # The yellow line lies inboard of the outer colonnade row
                        # (|800| plus half its own section) and outboard of the
                        # t0_*_860 walking line's hull, so it reads as the edge of the
                        # carriageway and not as a stripe under a player's feet.
                        ('line', mat('paint_line_yellow'), face - 260.0, face - 252.0,
                         0.0, 2.0)):
                    low, high = rect(s0, s1, *piece[2:])
                    low = (low[0], low[1], low[2] + T0)
                    high = (high[0], high[1], high[2] + T0)
                    made.append(paint('%s_%s_flange' % (tag, piece[0]), low, high,
                                      float(T0), piece[1]))
    # --- the carriageway: wet patches, and the two lines that cross an arm --------
    for index, (cx, cy, wide) in enumerate(((-800, 600, True), (760, -600, True),
                                            (-600, -800, False), (600, 780, False),
                                            (-760, -160, True), (200, 880, False))):
        low, high = ((cx - 120, cy - 80, T0), (cx + 120, cy + 80, T0 + 2)) if wide else \
                    ((cx - 80, cy - 120, T0), (cx + 80, cy + 120, T0 + 2))
        made.append(paint('wet%02d_flange' % index, low, high, float(T0), mat('asphalt_wet')))
    # A crossing laid along the wrong axis is worse than no crossing: the two loops
    # this replaces put 112-unit bars at y -560..-448 in the south arm, whose
    # carriageway runs along x at y -700 and -860, so the "zebra" was a row of
    # rectangles marching down the middle of the road.  A zebra stack therefore runs
    # *along* the street -- bars elongated across it, stacked along it -- in the outer
    # half of the covered arm, between the outer colonnade row at |800| and the
    # shopfronts at |1024|: the pedestrian half of the section, and the only half with
    # no column standing inside the stack.  A station is taken whole or not at all,
    # and two stations per arm is the cap.
    for side in sorted(FACADES):
        along_x = side in ('n', 's')
        near, far = 824.0, 1008.0
        accepted = 0
        for centre in (608.0, 864.0, -608.0, -864.0):
            if accepted >= 2:
                break
            bars = []
            for bar in range(4):
                b0 = centre - 60.0 + bar * 40.0
                b1 = b0 + 24.0
                if along_x:
                    low = (min(b0, b1), near if side == 'n' else -far, T0)
                    high = (max(b0, b1), far if side == 'n' else -near, T0 + 2)
                else:
                    low = (near if side == 'e' else -far, min(b0, b1), T0)
                    high = (far if side == 'e' else -near, max(b0, b1), T0 + 2)
                bars.append(paint('crossing_%s%02d_%02d_flange' % (side, accepted, bar),
                                  low, high, float(T0), mat('paint_line_white')))
            if len([one for one in bars if one is not None]) < 4:
                continue                        # a half-crossing is an obstacle
            made += bars
            accepted += 1
        print('japanDM: the %s arm took %d crossings' % (side, accepted))
    # --- hazard chevrons: the two colours nothing else in the level wears ---------
    for index, (hx, hy, wide) in enumerate(((-600, -448, True), (600, 448, True),
                                            (-448, 620, False), (448, -620, False))):
        low, high = ((hx - 64, hy - 12, T0), (hx + 64, hy + 12, T0 + 3)) if wide else \
                    ((hx - 12, hy - 64, T0), (hx + 12, hy + 64, T0 + 3))
        made.append(paint('chevron%02d_flange' % index, low, high, float(T0),
                          mat(KIT_HAZARD[index % 2])))
    made = [one for one in made if one is not None]
    print('japanDM: foot detail laid %d pieces of paint, kerb and drain' % len(made))
    return made


def shell():
    """A sky room inside a nodraw room, so neither the compiler nor the player
    can find the outside.

    The inner ring carries the sky surface and its inner faces sit exactly at the
    block limit (+/-1152), which is why every tower front stops there: standing in
    a street, the sky face 128 units away renders the cubemap, and because the
    panorama's horizon is at elevation zero the view reads as a city on the
    skyline rather than a wall. The outer ring is `nodraw`, which q3map2 keeps
    solid for the leak test but never draws, so a sky face that somehow fails to
    seal still cannot leak the map. The whole shell is below the lowest floor and
    above the tallest brush, so nothing walkable touches it.
    """
    ring = ((-SHELL, FOOT, SHELL, SHELL),            # north, spanning the corners
            (-SHELL, -SHELL, SHELL, -FOOT),          # south
            (-SHELL, -FOOT, -FOOT, FOOT),            # west, between the two
            (FOOT, -FOOT, SHELL, FOOT))              # east
    for index, (x0, y0, x1, y1) in enumerate(ring):
        box('sky_ring_%d' % index, (x0, y0, -128), (x1, y1, LID), SKY)
    box('sky_lid', (-SHELL, -SHELL, LID), (SHELL, SHELL, LID + DECK * 4), SKY)
    outer = ((-OUTER, SHELL, OUTER, OUTER), (-OUTER, -OUTER, OUTER, -SHELL),
             (-OUTER, -SHELL, -SHELL, SHELL), (SHELL, -SHELL, OUTER, SHELL))
    for index, (x0, y0, x1, y1) in enumerate(outer):
        box('clip_ring_%d' % index, (x0, y0, -128), (x1, y1, LID), NODRAW)
    box('clip_lid', (-OUTER, -OUTER, LID), (OUTER, OUTER, LID + DECK * 4), NODRAW)
    box('clip_floor', (-OUTER, -OUTER, -DECK * 2), (OUTER, OUTER, -DECK), NODRAW)


# --- dressing: the four streets, the deck and the signage --------------------
# Nothing here is decoration alone. Every counter, crate stack, machine and
# hedge is a box whose top sits between 40 and 96 units above the floor it
# stands on, which is the band that separates "crouch cover" from "standing
# cover" against an eye height of 46, and they are placed to break the lanes
# into 250-600 unit approaches rather than to fill space. Signage is `detail`
# (no shadows, no vis splits); the counters and crates are not, so they block
# bullets and the bot compiler can see them.
COVER_LOW, COVER_MID, COVER_TALL = 40.0, 64.0, 96.0


def stall_row(name, x0, x1, y, material_body=CRATE):
    """A market counter with an awning: the level's close-range cover unit."""
    made = [box('%s_counter' % name, (x0, y - 32, T0), (x1, y + 32, T0 + COVER_MID),
                material_body)]
    made.append(box('%s_awning' % name, (x0 - 12, y - 52, T0 + 152), (x1 + 12, y + 52, T0 + 164),
                    CLOTH, detail=True))
    for index, x in enumerate((x0 + 8, x1 - 8)):
        made.append(box('%s_post%d' % (name, index), (x - 6, y - 6, T0 + COVER_MID),
                        (x + 6, y + 6, T0 + 152), COLUMN, detail=True))
    made.append(box('%s_strip' % name, (x0, y - 34, T0 + COVER_MID), (x1, y - 26, T0 + 68),
                    STRIP, detail=True))
    return made


def crate_stack(name, x, y, pattern, base=T0):
    """A stack whose `pattern` is (width, depth, height, dx, dy) from the floor up.

    `base` is the floor it stands on: the loading dock and the station platform
    are both raised 32, and a crate sunk into one reads as a crate that is not
    there at all.
    """
    made, z = [], base
    for index, (w, d, height, dx, dy) in enumerate(pattern):
        made.append(box('%s_%02d' % (name, index), (x + dx - w / 2.0, y + dy - d / 2.0, z),
                        (x + dx + w / 2.0, y + dy + d / 2.0, z + height), CRATE))
        z += height
    return made


def market_alley():
    """T0 west: two covered lanes of stalls and a crate-choked canyon between."""
    for index, y in enumerate((152, 248, 344)):
        stall_row('stall_n%02d' % index, -1000 + index * 96, -744 + index * 96, y)
    stall_row('stall_n3', -560, -448, 248)
    stall_row('stall_s0', -1000, -880, -432)         # beside the market ramp's foot
    stall_row('stall_s1', -520, -448, -300)
    # The two canyon-mouth stacks leave a 48-unit gap between them: 30 is the
    # player box, so the alley stays passable but a fight slows down here.
    crate_stack('crates_w0', -968, -72, ((96, 96, COVER_MID, 0, 0),
                                         (80, 80, COVER_MID, 8, 8)))
    crate_stack('crates_w1', -968, 72, ((96, 96, COVER_TALL, 0, 0),))
    crate_stack('crates_w2', -840, 0, ((128, 96, COVER_MID, 0, 0),
                                       (96, 96, COVER_MID, 16, 0)))
    crate_stack('crates_w3', -520, -104, ((96, 96, COVER_LOW, 0, 0),))
    # A glowing line on the deck's canyon-facing fascia keeps the walkway edge
    # legible in a street the sun never reaches.
    for side in (-1, 1):     # a flush inlay on the deck lip, not a buried fascia
        box('lane_strip_w_%d' % side, (-FACE, side * (LANE + 4), T1),
            (-PLAZA - 8, side * (LANE + 12), T1 + 2), STRIP, detail=True)


def vending_alley():
    """T0 east: a machine wall, and the level's only truly dark street."""
    wall = FACE - 8                                  # the machine backs sink in
    for index in range(6):
        y = 128 + index * 104
        box('vend_%02d' % index, (wall - 64, y, T0), (wall, y + 88, T0 + 160), COLUMN)
        box('vend_%02d_front' % index, (wall - 72, y + 8, T0 + 40),
            (wall - 64, y + 80, T0 + 140), NEON_B, detail=True)
    box('vend_board', (wall - 72, 128, T0 + 176), (wall - 64, 736, T0 + 216), ADBOARD,
        detail=True)
    # The vending stair now fills x 608..1024 between y -368 and -176, so the
    # stacks stand north and south of that band rather than under it: three
    # corners in front of the machine wall, none of them a step nobody asked for.
    for index, y in enumerate((-64, -400, -520)):
        box('vend_crates_%02d' % index, (FOOT - 320, y, T0), (FOOT - 448, y - 96,
                                                             T0 + COVER_MID * (1 + index % 2)),
            CRATE)
    # The bench keeps the west side of the stair mouth, clear of the flight and
    # of its balustrade, where it is cover rather than a buried block of stone.
    box('bench_e', (FACE - 440, -288, T0), (FACE - 568, -240, T0 + 32), PLAZA_STONE)
    for side in (-1, 1):
        box('lane_strip_e_%d' % side, (PLAZA + 8, side * (LANE + 4), T1),
            (FACE, side * (LANE + 12), T1 + 2), STRIP, detail=True)


def service_drive():
    """T0 north: a loading dock, conduit runs, and the coolant chute between."""
    # 16, as at the station platform: the service ramp's foot stands on the dock, and
    # a 32-high dock face is a ledge the climb cannot walk onto.
    slab('dock', (-FOOT + 128, 520, -DECK), (-FOOT + 512, 1000, 16), CONCRETE)
    flight('dock_step', (-880, 468, T0), (-880, 520, 16), 192, DECK_METAL)
    crate_stack('dock_crates', -740, 900, ((128, 128, COVER_TALL, 0, 0),
                                           (96, 96, COVER_MID, 0, 0)), base=32)
    crate_stack('dock_crates2', -720, 640, ((128, 96, COVER_MID, 0, 0),), base=16)
    for index, x in enumerate((-FOOT + 160, FOOT - 160)):
        box('service_conduit_%d' % index, (x - 16, 480, 152), (x + 16, FACE - 8, 184), COLUMN,
            detail=True)
        for rung in range(4):
            box('service_hanger_%d_%d' % (index, rung), (x - 8, 520 + rung * 144, 184),
                (x + 8, 536 + rung * 144, 196), COLUMN, detail=True)
    # The chute itself: kerbs to read the edge, a glowing floor panel, and one
    # trigger_hurt volume that `hazard()` fills in.
    for side in (-1, 1):
        box('chute_kerb_%d' % side, (side * 64 - 8, 552, T0), (side * 64 + 8, 904, T0 + 32),
            CONCRETE)
    slab('chute_plate', (-56, 560, T0), (56, 900, T0 + 2), HOLO)
    box('chute_sign_n', (-56, 904, T0 + 96), (56, 912, T0 + 176), NEON_A, detail=True)
    box('chute_sign_s', (-56, 544, T0 + 96), (56, 552, T0 + 176), NEON_A, detail=True)


def station_mouth():
    """T0 south: a raised platform edge, containers, and the open station box."""
    # 16, not 32: the platform's top face was two step-ups off the street, so the
    # covered street stopped dead at a ledge nobody could climb without jumping, and
    # the audit found it on two of the four street lines.  A station platform edge is
    # a kerb you step onto, and the engine steps 18.
    slab('platform', (PLAZA + 64, -FACE, -DECK), (FACE, -PLAZA - 192, 16), PLAZA_STONE)
    # Two runs of 16-unit steps bring the street up to the platform from the west
    # and the plaza side; the third side is the tower front itself.
    flight('platform_step_w', (PLAZA + 32, -900, T0), (PLAZA + 64, -900, 16), 192, DECK_METAL)
    # The run stands north of the platform's edge at y -640. Written one flight
    # further south it landed inside the platform's own footprint, both treads 32
    # below a finished floor nobody could see or walk on.
    # x 600, not 700: at 700 the 192-wide flight reached x 796 and ran straight
    # into `vend_crates_02` (x 704..832, y -616..-520), which is a crate stack
    # standing on the top three treads -- the "stairs too big and close to
    # things" the owner saw, caught here as a 48 % overlap report.
    flight('platform_step_n', (600, -PLAZA - 128, T0), (600, -PLAZA - 192, 16), 192,
           DECK_METAL)
    for index, (x, y) in enumerate(((600, -960), (860, -880), (600, -700))):
        crate_stack('container_%02d' % index, x, y, ((192, 96, COVER_TALL, 0, 0),
                                                     (96, 96, COVER_MID, 48, 0)), base=16)
    # The kiosk used to stand where a container stood; it now anchors the covered
    # street between the platform and the plaza edge, out of the loading yard.
    box('kiosk', (PLAZA + 96, -560, T0), (PLAZA + 224, -432, T0 + 192), CONCRETE)
    box('kiosk_glass', (PLAZA + 88, -552, T0 + 64), (PLAZA + 104, -440, T0 + 160), GLASS,
        detail=True)
    box('kiosk_sign', (PLAZA + 88, -560, T0 + 192), (PLAZA + 232, -432, T0 + 224), NEON_A,
        detail=True)
    for index in range(6):
        post_row('bollard_%02d' % index, (-320 + index * 128, -FACE + 40), 0, 1, 72, COLUMN,
                 size=20)
    # The south lane was a 1300-unit firing line between the station platform and
    # the west street; this stack is the only thing in the middle of it. It
    # straddles the alley lip, so the street keeps a 60-unit passage past it.
    crate_stack('container_03', -60, -620, ((192, 96, COVER_TALL, 0, 0),
                                           (96, 96, COVER_MID, 64, 0)))


def deck_furniture():
    """T1: counters, planters and billboard frames on the market deck ring.

    A stall row may not be wider than the deck it stands on minus a lane to run
    past it. The north-west slab is 196 deep between the plinth face (x -1008)
    and the service-ramp void (x -812): a 192-wide counter and a 224-wide planter
    planted there filled that stretch from wall to void and sealed a pocket that
    no player can enter or leave, which the reach probe found as 28 standing
    spots with no route at all. So the row on that stretch is 128 wide and pulls
    off the facade by a lane a player can run.
    """
    # The row's own centre, one lane and one half-width in from where the deck
    # becomes walkable past the plinth: -1008 + 64 + 64.
    west = -(FOOT - FACADE_THICK - 16) + DECK_FACADE_LANE + 64.0
    for index, (x, y, half) in enumerate(((-916, 160, 96), (-700, 350, 96), (-560, 190, 96),
                                          (west, 430, 64), (west, 620, 64), (west, 900, 64))):
        box('deck_counter_w%02d' % index, (x - half, y - 32, T1), (x + half, y + 32, T1 + COVER_MID),
            DECK_METAL)
        box('deck_counter_top%02d' % index, (x - half - 4, y - 36, T1 + COVER_MID),
            (x + half + 4, y + 36, T1 + COVER_MID + 8), CLOTH, detail=True)
    for index, (x, y) in enumerate(((900, 220), (700, 360), (580, 140), (580, 280),
                                    (600, -140), (860, -140))):
        box('deck_counter_e%02d' % index, (x - 96, y - 32, T1), (x + 96, y + 32, T1 + COVER_MID),
            DECK_METAL)
        box('deck_counter_top%02d' % index, (x - 100, y - 36, T1 + COVER_MID),
            (x + 100, y + 36, T1 + COVER_MID + 8), CLOTH, detail=True)
    for index, (x, y, half) in enumerate(((-560, 940, 72), (west, 780, 64), (400, 940, 112),
                                          (700, 820, 112), (-620, -700, 112), (420, -780, 112))):
        box('deck_planter_%02d' % index, (x - half, y - 48, T1), (x + half, y + 48, T1 + COVER_MID),
            PLAZA_STONE)
        # The greenery stands on the rim's top face, exactly as the roof planters
        # do. The first cut asked for `COVER_LOW + 16` as its ceiling, which is 8
        # units *below* its own floor, and `box` normalises corner pairs: the bed
        # held a slab of shrubery hidden inside the stonework.
        box('deck_hedge_%02d' % index, (x - half + 12, y - 36, T1 + COVER_MID),
            (x + half - 12, y + 36, T1 + COVER_MID + 36), FOLIAGE, detail=True)


def billboards():
    """Sign faces on the block's arms: the skyline a plaza fight is lit by.

    Three arms carry a roof at 512, which is exactly `T1 + 256`, so a framed
    deck-level board there stands its panel on the roof surface and runs its legs
    up through the roof slab. The roofed arms therefore get a legless sign
    planted on the roof -- the Shinjuku rooftop board, readable from the plaza
    and from both roofs -- and only the south arm, which has no roof and the two
    tallest faces, keeps a framed board on legs over the street. There are five
    faces because that is how many arms can hold one: the north roof is taken by
    the viaduct and its stairs.
    """
    frames = (('bb_w', 'y', -FOOT + 208, (-320, -128), T2, NEON_A),
              ('bb_e', 'y', FOOT - 208, (-320, -128), T2, ADBOARD),
              ('bb_e2', 'y', FOOT - 208, (128, 320), T2, NEON_B),
              ('bb_s', 'x', -FOOT + 208, (-320, -160), T1, NEON_B),
              ('bb_s2', 'x', -FOOT + 208, (200, 392), T1, mat('ad_board_b')))
    for name, axis, band, (a0, a1), base, material in frames:
        legs = base == T1                            # a roofless arm gets legs
        z0 = base + 256 if legs else base            # framed: above the legs
        posts = (a0 + 16, a1 - 16) if legs else ()
        if axis == 'y':                              # a face normal to x
            box('%s_board' % name, (band - 8, a0, z0), (band, a1, z0 + 160), material,
                detail=True)
            for index, y in enumerate(posts):
                box('%s_post%d' % (name, index), (band - 20, y - 8, base),
                    (band - 8, y + 8, base + 256), COLUMN, detail=True)
        else:
            box('%s_board' % name, (a0, band - 8, z0), (a1, band, z0 + 160), material,
                detail=True)
            for index, x in enumerate(posts):
                box('%s_post%d' % (name, index), (x - 8, band - 20, base),
                    (x + 8, band - 8, base + 256), COLUMN, detail=True)


# --- sightline screens ------------------------------------------------------
# A spawn a rifle can reach from 2000 units is not a spawn. `map_sightlines`
# named the ones that were: the east lane (136 vantages, the worst 2213 units
# away), the west lane (73 at 2066) and the station (21 at 1656) each sit in a
# street trench that the open plaza turns into a window, and four high spawns
# could be hit straight down a roof or a viaduct lane. What each one was missing
# is a piece of city, set where the measured shot actually passes and at the
# height that shot actually travels at: 128 across a T0 lane under the deck, 128
# across the deck, 192 across a roof. Every screen is the greedy answer to one
# question -- which single box on that floor cuts the most exposing lines -- and
# every one is a thing a future market street would have anyway.
SCREENS = (
    ('hauler', 'hauler', (720, 70, 816, 294), T0, 128),  # east lane
    ('barrier', 'roadworks', (766, 400, 894, 432), T0, 128),
    ('market', 'market_wall0', (-561, -423, -529, -199), T0, 128),        # west lane
    ('market', 'market_wall1', (-660, -598, -628, -406), T0, 128),
    ('screen', 'platform_screen', (318, -701, 350, -477), T0, 128),  # station
    ('cabinet', 'transformer', (380, -888, 476, -792), T0, 128),
    # Two monorail-platform rects used to stand in this table as 80- and 128-tall
    # cabinets.  They are gone on purpose: they were proposed to shield the start
    # that used to sit on the viaduct, that start has been withdrawn (no point on
    # the deck clears its own rails at eye height), and the deck is too shallow for
    # a standing prop in any case.  The deck now carries 16-tall ducts inside
    # `viaduct()` instead; without the start, the probe reports no long line to
    # break there, so nothing was lost but the sealed lane.
    ('planter', 'deck_planter_06', (862, 343, 958, 439), T1, 128),   # deck ring
    ('duct', 'duct_bank', (-398, 644, -366, 868), T1, 128),
    ('bulkhead', 'stair_house_n', (-83, 860, -51, 988), T2, 192),     # north roof
    ('planter', 'planter_torii_0', (508, -252, 572, -156), T2, 80),  # torii plaza: planted terrace
    ('crates', 'crates_dock_0', (-968, 832, -872, 896), T0 + 32, 80),  # loading drive: pallet stack
    ('planter', 'planter_deck_s_0', (552, -836, 648, -772), T1, 80),  # south deck: planted terrace
    ('market', 'stall_deck_s_1', (416, -892, 512, -828), T1, 80),  # south deck: stall back
    ('market', 'stall_deck_e_0', (784, 220, 848, 316), T1, 96),  # east deck: stall back
    ('market', 'stall_deck_n_0', (-504, 548, -440, 644), T1, 80),  # north deck: stall back
    ('market', 'stall_lane_w_n_0', (-588, 268, -492, 332), T0, 128),  # west street north: stall back
    ('crates', 'crates_deck_w_0', (-916, 312, -788, 376), T1, 80),  # west deck: pallet stack
    ('market', 'stall_deck_w_1', (-992, 380, -928, 476), T1, 80),  # west deck: stall back
    ('market', 'stall_lane_w_s_1', (-836, -500, -740, -436), T0, 80),  # west street south: stall back
    ('cabinet', 'cabinet_lane_e_0', (404, 504, 468, 600), T0, 80),  # east street: services cabinet
    ('crates', 'crates_roof_n_e_0', (416, 952, 512, 1016), T2, 80),  # north roof east: pallet stack
    ('planter', 'planter_torii_1', (548, -156, 612, -60), T2, 80),  # torii plaza: planted terrace
    ('crates', 'crates_torii_2', (416, -212, 512, -148), T2, 80),  # torii plaza: pallet stack
    ('planter', 'planter_dock_1', (-892, 812, -828, 908), T0 + 16, 80),  # loading drive: terrace
    ('planter', 'planter_deck_s_2', (488, -976, 584, -912), T1, 80),  # south deck: planted terrace
    ('crates', 'crates_lane_w_s_2', (-736, -352, -640, -288), T0, 80),  # west street south: pallet stack
    ('market', 'stall_lane_w_s_3', (-788, -552, -692, -488), T0, 80),  # west street south: stall back
    ('market', 'stall_deck_s_3', (288, -932, 384, -868), T1, 80),  # south deck: stall back
    ('crates', 'crates_deck_w_2', (-920, 188, -856, 284), T1, 80),  # west deck: pallet stack
    ('crates', 'crates_roof_n_w_0', (-504, 912, -440, 1008), T2, 80),  # north roof west: pallet stack
)

def screens():
    """The sightline screens, dressed as street furniture.

    The exposure probe asked for every rect in `SCREENS`; `screen_styles` decides
    what each rect looks like and, because the offline planner reads the same table,
    how far a prop reaches past its own footprint before it is proposed.
    """
    made = []
    for style, name, rect, floor, height in SCREENS:
        for part, low, high, key, detail in screen_styles.parts(
                style, name, rect, floor, height):
            made.append(box(part, low, high, mat(key), detail=detail))
    return made



# T2 is where a deathmatch game on this level is decided, so its dressing is
# laid out as sightline screens first and scenery second. Each house blocks one
# of the long roof lines `map_author.audit` measures; the planters between them
# are 40-unit crouch cover. Every entry is clear of the roof voids, the rail
# lines and the tower-front line, and `verify` fails the build if one stops being
# so -- a planter inside a roof house is cover no player will ever see.
ROOF_HOUSES = (
    ('w0', (-900, 120), (160, 112), 128),        # the garden's long axis
    ('w1', (-580, 60), (160, 112), 96),
    ('e0', (760, 320), (256, 160), 128),         # closes the torii plaza
    ('n0', (240, 600), (256, 192), 128),
    ('nw', (-596, 856), (256, 128), 96),         # cover for the west roof start,
    # kept a hundred units clear of the front band it shelters behind
    # ('nw', (-596, 880), (256, 192), 96),      # the first cut left that start a
    # 48-unit strip between this house and the tower front behind it)
    ('n1', (160, 946), (256, 144), 128),         # the 1160-unit line along y 1000
)
# The two north beds stand in the one free band on that roof: y 472..704, which
# is south of the viaduct deck and its rails at y 704..720 and north of the roof
# edge, and between the stair flights at x +-536..664, the lamp posts and the two
# houses. The first cut put them at x -600 and 560, i.e. inside the two stair
# flights, and `verify` found them sunk into tread 11 and tread 8.
ROOF_PLANTERS = ((-900, -80, 192), (-620, -80, 192), (-740, 90, 128), (-620, 316, 192),
                 (-16, 560, 192), (448, 560, 128))
KOI_POOL = (-888, 316)                            # 192x128 plate in a 24-wide rim
PERGOLA = (-1000, 4, 128)                         # first slat, count, pitch


def roof_dressing():
    """The roof line: sightline screens, crouch cover and the garden."""
    for name, (x, y), (w, d), height in ROOF_HOUSES:
        box('roof_house_%s' % name, (x - w / 2.0, y - d / 2.0, T2 - DECK),
            (x + w / 2.0, y + d / 2.0, T2 + height), CONCRETE)
        box('roof_house_%s_strip' % name, (x - w / 2.0 - 4, y - d / 2.0 - 4, T2 + height),
            (x + w / 2.0 + 4, y + d / 2.0 + 4, T2 + height + 6),
            mat('light_strip_warm'), detail=True)
    for index, (x, y, w) in enumerate(ROOF_PLANTERS):
        box('planter_%02d' % index, (x - w / 2.0, y - 48, T2), (x + w / 2.0, y + 48, T2 + 40),
            PLAZA_STONE)
        box('hedge_%02d' % index, (x - w / 2.0 + 12, y - 36, T2 + 40),
            (x + w / 2.0 - 12, y + 36, T2 + 76), FOLIAGE, detail=True)
    koi_pool(*KOI_POOL)
    first, count, pitch = PERGOLA
    for index in range(count):
        box('pergola_%02d' % index, (first + index * pitch, -410, T2 + 80),
            (first + index * pitch + 64, -350, T2 + 96), COLUMN, detail=True)
    # y +/-144 and x 760, not +/-192 and x 700: at the old coordinates a lantern
    # stood on nothing, 128 units of stone hanging over the mouth of the east roof
    # stair.  On the pad it is a lamp beside the torii, which is what it is meant to
    # be, and it is clear of the well the flight arrives through.
    for index, y in enumerate((-144, 144)):
        box('torii_lantern_%d' % index, (760, y - 24, T2), (800, y + 24, T2 + 128), COLUMN)
        box('torii_lantern_%d_light' % index, (752, y - 32, T2 + 128), (808, y + 32, T2 + 168),
            LACQUER)
        box('torii_lantern_%d_glow' % index, (756, y - 28, T2 + 132), (804, y + 28, T2 + 164),
            NEON_A, detail=True)
    # A 24-unit kerb band, not a plate: the roofs are already edged with rails.
    # The bands stop at the tower-front line: the first cut ran them to `-FOOT +
    # 24`, which buried their outer 104 units in the facade wall standing there.
    for name, rect in (('roof_kerb_w_n', (-FACE, PLAZA - 48, -PLAZA - 8, PLAZA - 24)),
                       ('roof_kerb_w_s', (-FACE, -PLAZA + 24, -PLAZA - 8, -PLAZA + 48)),
                       ('roof_kerb_e_n', (PLAZA + 8, PLAZA - 48, FACE, PLAZA - 24)),
                       ('roof_kerb_e_s', (PLAZA + 8, -PLAZA + 24, FACE, -PLAZA + 48))):
        box(name, (rect[0], rect[1], T2), (rect[2], rect[3], T2 + 8), ROOF, detail=True)


def koi_pool(x, y):
    """A glowing basin in a stone rim, 24 units proud of the roof.

    Four rim boxes rather than an octagonal prism: the exporter records boxes, so
    `verify` can prove the basin is standing on the roof and not inside a house.
    """
    made = [box('koi_plate', (x - 96, y - 64, T2), (x + 96, y + 64, T2 + 12), HOLO)]
    made.append(box('koi_rim_e', (x + 96, y - 96, T2), (x + 128, y + 96, T2 + 24), PLAZA_STONE))
    made.append(box('koi_rim_w', (x - 128, y - 96, T2), (x - 96, y + 96, T2 + 24), PLAZA_STONE))
    made.append(box('koi_rim_n', (x - 96, y + 64, T2), (x + 96, y + 96, T2 + 24), PLAZA_STONE))
    made.append(box('koi_rim_s', (x - 96, y - 96, T2), (x + 96, y - 64, T2 + 24), PLAZA_STONE))
    return made


# --- the two metres: the small stuff a street is actually made of ------------
# The level was authored at the resolution of cover: counters, containers, crates,
# each one a box sized to stop a bullet.  That is why the frames read as an empty
# hangar rather than a bazaar.  A real street in Japan is cluttered at arm's
# length, and almost none of that clutter is cover: it is conduit, condensers,
# sign faces, awning frames, ducting, tanks, kerbs, paint and cable, mounted on
# surfaces that were already there.  Everything in this section is `detail` (no
# lightmap, no vis split, no shadow), stands within 40 units of the wall or floor
# it belongs to, and keeps out of every running line by at least 64.
#
# The trade is real and is paid where it is stated: `detail` takes no baked light,
# so a piece here is lit only by the light grid.  That is why the ones that must be
# seen at all are emissive (`light_strip`, `neon_*`), and why the rest are set
# under an awning strip or against a lit machine -- which is where a real city puts
# them too.
SIGN_LADDER = (NEON_A, NEON_B, ADBOARD)


def wall_item(axis, wall, face, along, base, height, depth, across=40.0):
    """-> (low, high) for a box mounted on a street wall at world height `base`.

    `axis` is the street the wall runs along, `wall` is |its coordinate|, `face`
    is the direction the wall looks (+1 for the west wall at -wall, -1 for the
    east wall at +wall), `along` walks the wall and `across` measures the mount.
    The back of the mount is sunk 8 into the wall so the join has no seam.
    """
    inner = -wall + 8 if face > 0 else wall - 8
    outer = inner + depth * (1 if face > 0 else -1)
    a0, a1 = sorted((inner, outer))
    if axis == 'y':
        return (a0, along, base), (a1, along + across, base + height)
    return (along, a0, base), (along + across, a1, base + height)


def wall_clutter():
    """The four street walls, dressed: signs, brackets, condensers, drop pipes.

    Clearances are not guessed.  The west wall is bare between y -400 and 120 and
    again north of y 376 because that is where its stall rows stand; the east
    wall's machine bank already owns y 128..736 up to z 160, so its boards stand
    over the machines, which is exactly how a machine corner looks at night.
    """
    made = []
    bands = (('w', 'y', +1, ((-820, 128, 120), (-640, 96, 224), (420, 120, 152),
                             (600, 120, 288), (880, 120, 176))),
             ('e', 'y', -1, ((160, 72, 200), (300, 72, 200), (450, 72, 200),
                             (600, 72, 200), (-560, 96, 128), (-120, 96, 240))),
             ('n', 'x', -1, ((-380, 96, 168), (-60, 96, 168), (300, 96, 260),
                             (700, 96, 200))),
             ('s', 'x', +1, ((-880, 96, 128), (-420, 96, 176), (40, 96, 176),
                             (760, 96, 128))))
    for side, axis, face, band in bands:
        for index, (along, width, base) in enumerate(band):
            low, high = wall_item(axis, FACE, face, along, T0 + base,
                                  200 + 56 * (index % 3), 24, width)
            made.append(box('%s_sign%02d_glow' % (side, index), low, high,
                            SIGN_LADDER[index % 3], detail=True))
            low, high = wall_item(axis, FACE, face, along - 6, T0 + base - 10,
                                  24, 16, width + 12)
            made.append(box('%s_sign%02d_bracket_flange' % (side, index), low, high,
                            COLUMN, detail=True))
    for index, (side, axis, face, along) in enumerate((
            ('w', 'y', +1, -520), ('w', 'y', +1, 760), ('e', 'y', -1, -320),
            ('e', 'y', -1, 820), ('n', 'x', -1, 120), ('s', 'x', +1, -160))):
        low, high = wall_item(axis, FACE, face, along, T0 + 232, 56, 40)
        made.append(box('%s_cond%02d_flange' % (side, index), low, high, COLUMN,
                        detail=True))
        low, high = wall_item(axis, FACE, face, along + 56, T0, 16, 12, 14)
        made.append(box('%s_cond%02d_pipe_flange' % (side, index),
                        (low[0], low[1], T0), (high[0], high[1], T0 + 260), COLUMN,
                        detail=True))
    return made


def awning(name, x0, x1, y, lintel, depth, face):
    """-> an awning slab, its lit underside, two posts and three noren panels.

    `face` is the side of the counter the awning reaches over: -1 toward -y, +1
    toward +y.  The lintel is 128 over the walk it covers, which is head room
    (56) plus a jump, so no awning in this level can take a route away; the noren
    hangs in the last 40 units above the lintel's own ceiling line, over the
    counter and not over the lane, because a full-length curtain is a solid sheet
    across a street to this brush format.
    """
    near, far = (y - 36 - depth, y - 36) if face < 0 else (y + 36, y + 36 + depth)
    a0, a1 = sorted((near, far))
    made = [box('%s_flange' % name, (x0 - 8, a0, lintel), (x1 + 8, a1, lintel + 12),
                CLOTH, detail=True)]
    made.append(box('%s_glow' % name, (x0, a0 + 4, lintel - 4), (x1, a1 - 4, lintel),
                    STRIP, detail=True))
    for index, post_x in enumerate((x0 + 10, x1 - 10)):
        made.append(box('%s_post%d_flange' % (name, index), (post_x - 4, a1 - 10 if face > 0
                                                             else a0 + 2, lintel - 8),
                        (post_x + 4, a1 + 6 if face > 0 else a0 - 6, lintel + 12),
                        COLUMN, detail=True))
    panel = (x1 - x0 - 40) / 3.0
    for index in range(3):
        x = x0 + 12 + index * panel
        front = a0 + 2 if face < 0 else a1 - 8
        made.append(box('%s_noren%d_glow' % (name, index), (x, front, lintel - 44),
                        (x + panel - 8, front + 6, lintel - 4), mat('noren_strip'),
                        detail=True))
    return made


def hangs_clear(low, high, stem_top):
    """-> whether a lantern has the air its string hangs in to itself.

    A festival string is strung across a street that also carries billboard posts,
    hanging sign brackets and its own awning hoods, and every one of them reaches
    above a head.  A lantern placed without measuring that air arrives inside a
    post -- which is 100 % inside another brush to the auditor and "a box that
    should not be there" to a player.  The cable it hangs from is allowed, being
    the thing it hangs from.
    """
    for name, other_low, other_high, kind in BOXES:
        if kind in ('rail', 'trigger', 'loose', 'hint') or name.startswith(SHELLS):
            continue
        if name.startswith('lantern_cable'):
            continue
        if (other_low[0] < high[0] and other_high[0] > low[0]
                and other_low[1] < high[1] and other_high[1] > low[1]
                and other_low[2] < stem_top and other_high[2] > low[2]):
            return False
    return True


def deck_bazaar():
    """T1: the market deck as a covered row of pitches rather than an empty plate.

    The counters have existed since the first cut; what was missing is everything
    a pitch is made of.  The counters are read back out of the scene's own record
    rather than re-typed, so an awning can never drift off the counter it covers.
    West rows face the plaza edge (-y) and east rows face the block (+y): the two
    runs are mirror images around the ring, and a pitch whose awning looks into
    the wall it stands against reads as a mistake at the first glance.
    """
    made = []
    for name, low, high, _kind in BOXES:
        if not name.startswith('deck_counter_') or not name[-2:].isdigit():
            continue
        face = -1 if name.startswith('deck_counter_w') else 1
        made += awning('awn_%s' % name, low[0] + 4, high[0] - 4, (low[1] + high[1]) / 2.0,
                       T1 + 128, 56, face)
    return made


def lantern_strings():
    """The festival strings, hung last: see `hangs_clear`.

    The string crosses a street that every other dressing pass furnishes, and
    the market's own hanging signs (`bazaar_hang*`) arrive after the awnings
    beside them, so this is the one pass that has to run after the market
    rather than among the counters its lanterns light.
    """
    made = []
    # One cable per arm at y or x = +-300 and a paper lantern on it every 96
    # units, hung 148 to 176 above the walk -- below a jump, above a crouch, so
    # a string can never take a route away from anyone.  The centre of each
    # cable lies over the open plaza, which is where a festival string belongs
    # anyway, and the four alleys are left clear so nothing hangs over a bridge.
    for axis in ('x', 'y'):
        for arm in (-1, 1):
            across = arm * 300
            low, high = ([-1004, across - 4, T1 + 176], [1004, across + 4, T1 + 180]) \
                if axis == 'x' else ([across - 4, -1004, T1 + 176],
                                     [across + 4, 1004, T1 + 180])
            made.append(box('lantern_cable_%s%d_flange' % (axis, arm), low, high, COLUMN,
                            detail=True))
            for step in range(1, 11):
                for direction in (-1, 1):
                    along = direction * step * 96.0
                    if step <= 1:                 # the four alleys cut the ring
                        continue
                    # A cube of dark red paint hanging in mid-air is what the
                    # owner saw and called flying.  A lantern reads as a lantern
                    # when three things are true: it hangs FROM something (a stem
                    # from the cable, not a 4-unit gap), it is taller than it is
                    # wide, and the paper is the brightest thing on the string.
                    # So: a stem, a lacquer housing with a shoulder, and a lit
                    # core inside it -- the same emissive-inside-a-housing pattern
                    # the awning noren use, and the reason the string now lights
                    # the street instead of staining it brown.
                    body = ([along - 11, across - 11, T1 + 138],
                            [along + 11, across + 11, T1 + 172]) if axis == 'x' else \
                           ([across - 11, along - 11, T1 + 138],
                            [across + 11, along + 11, T1 + 172])
                    stem = ([along - 2, across - 2, T1 + 172],
                            [along + 2, across + 2, T1 + 176]) if axis == 'x' else \
                           ([across - 2, along - 2, T1 + 172],
                            [across + 2, along + 2, T1 + 176])
                    if not hangs_clear(body[0], body[1], stem[1][2]):
                        continue
                    made.append(box('lantern_strung_%s%d_%02d_stem' % (axis, arm, step),
                                    stem[0], stem[1], COLUMN, detail=True))
                    made.append(box('lantern_strung_%s%d_%02d' % (axis, arm, step),
                                    body[0], body[1], LACQUER, detail=True))
                    made.append(box('lantern_strung_%s%d_%02d_glow' % (axis, arm, step),
                                    (body[0][0] + 4, body[0][1] + 4, body[0][2] + 5),
                                    (body[1][0] - 4, body[1][1] - 4, body[1][2] - 5),
                                    NEON_A, detail=True))
    return made

def skybridge_piers():
    """The corridor across the plaza stops flying: two piers under its mid-span.

    An 896 x 128 plate at z 512 with nothing beneath it is the arena's second
    "that part is flying", and it hangs over the one floor a player spends the
    most time crossing.  An elevated walkway in Japan lands on a shaft every few
    spans, and a shaft with a flared capital is also the cheapest cover the plaza
    has -- 64 across, 96 at its plinth, standing 224 off the centre line the holo
    pool occupies, so it narrows the plaza without taking a route away.
    """
    made = []
    for index, x in enumerate((-224.0, 224.0)):
        made.append(box('bridge_pier_%02d_plinth' % index, (x - 48, -240, T0),
                        (x + 48, -144, T0 + 24), CONCRETE))
        made.append(box('bridge_pier_%02d_shaft' % index, (x - 32, -224, T0 + 24),
                        (x + 32, -160, T2 - DECK - 24), COLUMN))
        made.append(box('bridge_pier_%02d_cap_flange' % index, (x - 48, -240, T2 - DECK - 24),
                        (x + 48, -144, T2 - DECK), CONCRETE))
        made.append(box('bridge_pier_%02d_strip_glow' % index,
                        (x - 34, -216, T0 + 96), (x - 30, -168, T0 + 300),
                        mat('light_strip_cyan'), detail=True))
    return made


def surface_marks():
    """The two marks that tell a player a floor is a street rather than a plate.

    A Japanese street at night is painted, not paved-and-forgotten: a broken
    centre line down the traffic lane and a border round the pedestrian plaza.
    Both are 2-unit proud strips wearing the map's own surfacelight, so they hand
    the counters' glow back as a line on the ground -- which is what makes a 1999
    grey plate pass for a 2017 street at a glance, at six brushes a piece.

    Every mark is measured against the scene's own record, and this section runs
    after the props for that reason: the aisle's centre line crosses two stair
    voids, a drain grating, a deck planter and the two vending machines parked at
    its ends, and a painted dash lying across any of them -- or floating over a
    hole -- is the exact defect this pass exists to prevent.
    """
    def clear(low, high, on_z):
        """-> whether a paint band sits on floor and has nothing standing in it."""
        standing = False
        for name, other_low, other_high, kind in BOXES:
            if kind in ('rail', 'trigger', 'loose', 'hint') or name.startswith(SHELLS):
                continue
            if not (other_low[0] < high[0] and other_high[0] > low[0]
                    and other_low[1] < high[1] and other_high[1] > low[1]):
                continue
            if abs(other_high[2] - on_z) <= 1.0 and other_low[2] < on_z:
                standing = True                     # the plate this paint lies on
            elif other_low[2] < high[2] and other_high[2] > low[2]:
                return False                        # something else lives here
        return standing

    made = []
    for index, x in enumerate(range(-940, 941, 168)):
        low, high = (x - 32, -756, T1), (x + 32, -748, T1 + 2)
        if clear(low, high, float(T1)):
            made.append(box('road_dash_%02d' % index, low, high,
                            mat('paint_line_white'), detail=True))
    # The plaza's border ring, inset 28 from the four edges it looks out over.
    # Each of its four sides is cut at the two places a walkway reaches the plaza
    # so the line does not march across an entrance, and the corners butt rather
    # than overlap: two strips sharing a corner is a 98 % overlap report.
    inset, thick = PLAZA - 28.0, 10.0
    runs = []
    for sign in (-1, 1):
        runs.append(((sign * inset - thick / 2.0, -PLAZA + inset, sign * inset + thick / 2.0,
                      -256.0), 'y'))
        runs.append(((sign * inset - thick / 2.0, -128.0, sign * inset + thick / 2.0,
                      PLAZA - inset), 'y'))
        runs.append(((-PLAZA + inset, sign * inset - thick / 2.0, sign * inset - thick / 2.0,
                      sign * inset + thick / 2.0), 'x'))
        runs.append(((sign * inset + thick / 2.0, sign * inset - thick / 2.0, PLAZA - inset,
                      sign * inset + thick / 2.0), 'x'))
    for index, ((x0, y0, x1, y1), _axis) in enumerate(runs):
        low, high = (min(x0, x1), min(y0, y1), T0), (max(x0, x1), max(y0, y1), T0 + 2)
        if clear(low, high, float(T0)):
            made.append(box('plaza_border_%02d' % index, low, high,
                            mat('paint_line_yellow'), detail=True))
    return made

def viaduct_piers():
    """The viaduct stops flying: five piers from the street up to its deck.

    A 2048 x 224 slab at z 704 with nothing under it is the level's single
    biggest "that part is flying", and an elevated road in Japan is supported
    every 400 units or so by a shaft with a flared capital.  Each pier stands
    mid-street, 96 across, in a street 704 wide, so it is cover with a lane
    either side rather than an obstruction; the west one stands on the loading
    dock, which is 32 high, and therefore starts there.
    """
    # y 775 and 64 across, not y 816 and 96 across.  A 96-wide shaft centred on the
    # deck's own centre line stood *inside* three walking lines at once: the street's
    # outer lane (y 860), the deck's outer lane (y 850) and the street's inner lane at
    # y 700 all ran into solid concrete, which is why the audit reported `pier_00` and
    # friends on four routes.  64 across at y 775 keeps 28 units clear of the inner
    # street lane and 43 of both outer lanes -- still cover, still under the deck, and
    # the capital simply leans 41 units east of the shaft, which is exactly how a
    # cantilevered elevated-road pier looks in the city this one is meant to be.
    # The plinth is 16 tall, so it is stepped over rather than walked into.
    made = []
    # -816 and 816, not -800 and 800: the west shaft's flange reached x -768, which
    # is 8 units inside the service ramp's own flank at x -776, and an elevated pier
    # leaning into a staircase is not what a cantilever means.
    for index, x in enumerate((-816, -400, 0, 400, 816)):
        base = 16 if x == -800 else T0
        made.append(box('pier_%02d_plinth' % index, (x - 80, 736, base),
                        (x + 80, 896, base + 16), CONCRETE))
        made.append(box('pier_%02d_flange' % index, (x - 32, 743, base + 16),
                        (x + 32, 807, 640), CONCRETE))
        made.append(box('pier_%02d_cap_flange' % index, (x - 64, 695, 640),
                        (x + 64, 855, 672), CONCRETE))
        made.append(box('pier_%02d_strip_glow' % index, (x - 36, 739, base + 96),
                        (x + 36, 811, base + 104), mat('light_strip_cyan'),
                        detail=True))
    return made


def roof_hardware():
    """T2: tanks, ducts, risers and a washing line, so a roof is a roof."""
    made = []
    for index, (x, y) in enumerate(((-900, -300), (-520, 240), (-600, 800),
                                    (-60, 850), (560, 200))):
        made += post_row('tank_%02d_flange' % index, (x, y), 0, 1, 96, COLUMN,
                         size=88, sides=8, base=T2)
        # 16: at 24 the flange was a knee-taller plinth that no route could cross,
     # and it is the ring *around* a tank, not the tank.
        made.append(box('tank_%02d_base_flange' % index, (x - 56, y - 56, T2),
                        (x + 56, y + 56, T2 + 16), COLUMN, detail=True))
        made.append(box('tank_%02d_lid_flange' % index, (x - 52, y - 52, T2 + 96),
                        (x + 52, y + 52, T2 + 108), CONCRETE, detail=True))
    for index, (x, y, wide) in enumerate(((-700, -120, True), (-400, 800, False),
                                          (530, 320, True), (520, -300, False),
                                          (-540, 380, True))):
        low, high = ((x - 80, y - 40, T2), (x + 80, y + 40, T2 + 56)) if wide else \
                    ((x - 40, y - 80, T2), (x + 40, y + 80, T2 + 56))
        made.append(box('hvac_%02d_flange' % index, low, high, DECK_METAL, detail=True))
        grill = ((x - 72, y + 30, T2 + 8), (x + 72, y + 41, T2 + 40)) if wide else \
                ((x + 30, y - 72, T2 + 8), (x + 41, y + 72, T2 + 40))
        made.append(box('hvac_%02d_glow' % index, grill[0], grill[1],
                        mat('grate_drain'), detail=True))
    for index, (x, y) in enumerate(((-900, -420), (620, -420), (-500, 900), (760, 320))):
        for step in range(3):
            made.append(box('vent_%02d_%d_flange' % (index, step),
                            (x + step * 44 - 16, y - 16, T2),
                            (x + step * 44 + 16, y + 16, T2 + 40 + step * 12),
                            COLUMN, detail=True))
    for index, y in enumerate((880, 992)):
        made.append(box('laundry_post%d_flange' % index, (-566, y - 6, T2),
                        (-554, y + 6, T2 + 128), COLUMN, detail=True))
    made.append(box('laundry_line_glow', (-562, 886, T2 + 112), (-558, 992, T2 + 118),
                    CLOTH, detail=True))
    return made


def street_markings():
    """Paint, kerbs and drains: the flat things that give a street its scale."""
    made = []
    for step in range(6):
        offset = -250 + step * 100
        for rim in (-1, 1):
            made.append(box('cross_x%02d_%d_flange' % (step, rim), (offset, rim * 224 -
                                                                    (168 if rim < 0 else 0),
                                                                    T0),
                            (offset + 56, rim * 224 + (0 if rim < 0 else 168), T0 + 2),
                            mat('kerb_granite'), detail=True))
            made.append(box('cross_y%02d_%d_flange' % (step, rim),
                            (rim * 224 - (168 if rim < 0 else 0), offset, T0),
                            (rim * 224 + (0 if rim < 0 else 168), offset + 56, T0 + 2),
                            mat('kerb_granite'), detail=True))
    for rim in (-1, 1):
        # Six units, not twelve, and in the plaza's own stone: a 12-unit concrete
        # kerb is a shadow cast across the whole approach at a grazing eye, which
        # is what the crossing photographed as two black bars.
        made.append(box('kerb_w%d_flange' % rim, (-PLAZA - 14, -PLAZA, T0),
                        (-PLAZA - 4, PLAZA, T0 + 6), mat('kerb_granite'), detail=True))
        made.append(box('kerb_e%d_flange' % rim, (PLAZA + 4, -PLAZA, T0),
                        (PLAZA + 14, PLAZA, T0 + 6), mat('kerb_granite'), detail=True))
        made.append(box('kerb_n%d_flange' % rim, (-PLAZA, PLAZA + 4, T0),
                        (PLAZA, PLAZA + 14, T0 + 6), mat('kerb_granite'), detail=True))
        made.append(box('kerb_s%d_flange' % rim, (-PLAZA, -PLAZA - 14, T0),
                        (PLAZA, -PLAZA - 4, T0 + 6), mat('kerb_granite'), detail=True))
    for index, (x, y) in enumerate(((-700, 200), (700, -200), (200, 700), (-200, -700),
                                    (-900, -200), (900, 200))):
        if abs(x) > abs(y):
            made.append(box('drain%02d_flange' % index, (x - 48, y - 24, T0),
                            (x + 48, y + 24, T0 + 2), mat('grate_drain'), detail=True))
        else:
            made.append(box('drain%02d_flange' % index, (x - 24, y - 48, T0),
                            (x + 24, y + 48, T0 + 2), mat('grate_drain'), detail=True))
    return made


def street_furniture():
    """A banner across the plaza, and bollards at its posts."""
    made = []
    for index, x in enumerate((-380, 380)):
        made += post_row('banner_post%d_flange' % index, (x, 0), 0, 1, 340, COLUMN,
                         size=20, sides=8)
    made.append(box('banner_glow', (-380, -10, 296), (380, 10, 340), NEON_B, detail=True))
    made.append(box('banner_valance_glow', (-380, -14, 280), (380, 14, 296), LACQUER,
                    detail=True))
    for index, (x, y) in enumerate(((-420, -330), (420, -330), (420, 330), (-420, 330))):
        made += post_row('corner_bollard%d_flange' % index, (x, y), 0, 1, 64, COLUMN,
                         size=18, sides=6)
    return made


def micro_details():
    """The whole two-metre pass, with a count on the record."""
    made = []
    for section in (wall_clutter, deck_bazaar, viaduct_piers, roof_hardware,
                    street_markings, street_furniture):
        made += [one for one in section() if one is not None]
    print('japanDM: %d small-detail pieces' % len(made))
    return made


def dressing():
    market_alley()
    vending_alley()
    service_drive()
    station_mouth()
    deck_furniture()
    billboards()
    screens()
    roof_dressing()
    micro_details()


# --- the hazard --------------------------------------------------------------
def hazard():
    """One `trigger_hurt`: the coolant chute in the service drive.

    The runtime reads `wait` in seconds and floors the interval at 50 ms
    (`server/world_actions.zig`, `properties.milliseconds`), so `damage 20` with
    `wait 0.5` is 40 damage a second standing in it. Crossing 344 units at 320
    u/s costs about 43 damage and the best ammunition in the level is on the far
    side, which is the trade the DESIGN asks for: it is survivable from full
    health and suicidal at half.
    """
    return map_blender.brush_entity('chute_hurt', 'trigger_hurt', (-56, 560, T0), (56, 900,
                                                                                  T0 + 64),
                                   TRIGGER, keys={'damage': '20', 'wait': '0.5'})


# --- light entities ----------------------------------------------------------
# The shipped episode-4 arenas are 60-70 % lights (e4dm1: 158 of 272 entities)
# and this level follows them, because a dusk city with light *on* it is the
# whole presentation. Every radius is small (256-600) and every colour is
# saturated: one lamp should pool on one surface, not wash the district. The
# emissive signage carries the rest with `nolightmap`, so a neon sign is bright
# inside a shadowed street without spending an entity on it.
# One octave down from a neon's own photograph.  These are the values a surface is
# lit *by*, not the values a tube is photographed at, and the difference is the
# difference between a night street and a light-bulb catalogue: a red paper lantern
# puts (0.98, 0.36, 0.30) on a wall, not (1.00, 0.42, 0.58), and a privet hedge
# under a street lamp is a pale sage, not the (0.46, 1.00, 0.62) that painted this
# level's north ramp green and its roof garden green and its plaza south-east green.
LAMP_PINK, LAMP_CYAN = '0.98 0.36 0.30', '0.32 0.68 0.92'
LAMP_GREEN, LAMP_AMBER = '0.62 0.84 0.66', '1.00 0.74 0.52'
LAMP_WHITE, LAMP_HOLO = '0.88 0.90 0.94', '0.40 0.72 0.90'
#: The sky's own contribution on a tier with no roof over it.  Not a lamp colour --
#: nothing on a street is this blue -- which is exactly why the open tiers need it:
#: the warm lamps then read as warm by comparison instead of as weather.
LAMP_MOON = '0.58 0.68 0.86'


# `cap` is the brightest value a lamp may put on a surface, and the first rig set
# it at 60-120 -- below what `q3map_skyLight 260` delivers on its own.  Every
# capture then came back the sky's single hue: the roofs measured a mean luminance
# of 0.15 with no pool anywhere on them, because the lamps were capped out of
# existence and only the sky was allowed to reach full strength.  Raising the cap
# is what turns a flat night into pools of amber, cyan and green on the streets.
CAP_GAIN = 2.25


def lamp(name, location, radius, colour, cap=None):
    keys = {'light': '%g' % radius, '_color': colour}
    if cap is not None:
        keys['cap'] = '%g' % (cap * CAP_GAIN)          # cap = the brightest value
    return map_blender.entity('light_%s' % name, 'light', location, keys)


LIGHTS_RAW = (
    # A lamp hangs 24 below the deck overhead, which is what pools light on one
    # street rather than on one tier -- and which buries a lamp in a slab the
    # moment a climb is re-cut underneath it. q3map2 cannot place an entity origin
    # in a solid leaf, and the message it has for that is `Entity leaked`: three
    # lamps here were a "hole in the world" until `map_author.audit` started
    # refusing a light inside geometry. Every entry below is clear of the climbs.
    # the covered street lanes, one pool per stall row
    ('lane_w_0', (-900, 200, 200), 420, LAMP_AMBER, 110), ('lane_w_1', (-660, 300, 200), 380,
                                                           LAMP_AMBER, 90),
    ('lane_w_2', (-900, -200, 200), 420, LAMP_PINK, 110), ('lane_w_3', (-700, -500, 200), 380,
                                                           LAMP_PINK, 90),
    ('lane_e_0', (900, 300, 200), 420, LAMP_CYAN, 110), ('lane_e_1', (660, 200, 200), 380,
                                                         LAMP_CYAN, 90),
    ('lane_e_2', (900, -260, 200), 420, LAMP_GREEN, 110), ('lane_e_3', (700, -500, 200), 380,
                                                           LAMP_GREEN, 90),
    # the four canyons, lit from the chute / platform side so the walk reads
    # The bazaar street: one pool per two pitches, hung below the hoods.  The x
    # positions are all 60 or more off the colonnade's lateral lines at |576| and
    # |800|, because a lamp inside a lintel is what q3map2 calls a leak -- the
    # compiler's only message for a hole in the world, for a map that has none.
    ('bazaar_0', (-930, -750, 205), 300, LAMP_AMBER, 120),
    ('bazaar_1', (-690, -750, 205), 300, LAMP_PINK, 120),
    ('bazaar_2', (-450, -750, 205), 300, LAMP_WHITE, 120),
    ('bazaar_3', (-210, -750, 205), 300, LAMP_AMBER, 120),
    ('bazaar_4', (30, -750, 205), 300, LAMP_PINK, 120),
    ('bazaar_5', (270, -750, 205), 300, LAMP_GREEN, 120),
    ('bazaar_6', (660, -750, 205), 300, LAMP_AMBER, 120),
    ('bazaar_7', (930, -660, 205), 260, LAMP_CYAN, 100),
    ('bazaar_n', (460, 700, 205), 300, LAMP_GREEN, 110),
    # the roofs were the four darkest frames in the capture set
    ('roof_w', (-760, 0, T2 + 70), 460, LAMP_WHITE, 90),
    ('roof_n', (-100, 760, T2 + 70), 460, LAMP_AMBER, 90),
    ('roof_e', (700, -100, T2 + 70), 460, LAMP_CYAN, 90),
    ('roof_ne', (620, 700, T2 + 70), 420, LAMP_PINK, 80),
    # the viaduct lane read as a tunnel from the street
    ('via_w', (-700, 816, VIA + 60), 420, LAMP_HOLO, 90),
    ('via_e', (700, 816, VIA + 60), 420, LAMP_HOLO, 90),
    ('canyon_w', (-840, 0, 150), 460, LAMP_PINK, 80), ('canyon_e', (840, 0, 150), 460, LAMP_CYAN,
                                                        80),
    ('canyon_n', (0, 760, 150), 520, LAMP_HOLO, 70), ('canyon_s', (0, -760, 150), 520, LAMP_WHITE,
                                                       70),
    # the plaza: the pool itself plus four corner lamps and the two approaches
    ('pool', (0, 0, 60), 380, LAMP_HOLO, 90), ('plaza_ne', (300, 300, 150), 420, LAMP_WHITE, 90),
    ('plaza_nw', (-300, 300, 150), 420, LAMP_AMBER, 90), ('plaza_sw', (-300, -300, 150), 420,
                                                          LAMP_PINK, 90),
    ('plaza_se', (300, -300, 150), 420, LAMP_GREEN, 90), ('plaza_n', (0, 380, 180), 360,
                                                          LAMP_WHITE, 70),
    ('plaza_s', (0, -380, 180), 360, LAMP_WHITE, 70),
    # the market deck: a lamp per stall cluster and one per bridge mouth
    ('deck_w_0', (-900, 240, 340), 380, LAMP_AMBER, 90), ('deck_w_1', (-900, -380, 340), 380,
                                                          LAMP_PINK, 90),
    ('deck_e_0', (900, 260, 340), 380, LAMP_CYAN, 90), ('deck_e_1', (900, -500, 340), 380,
                                                        LAMP_GREEN, 90),
    ('deck_n_0', (-560, 900, 340), 380, LAMP_WHITE, 90), ('deck_n_1', (560, 900, 340), 380,
                                                          LAMP_AMBER, 90),
    ('deck_s_0', (-560, -900, 340), 380, LAMP_PINK, 90), ('deck_s_1', (560, -900, 340), 380,
                                                          LAMP_WHITE, 90),
    # The market deck's own interior.  The eight lamps above stand on the deck's
    # outer ring at |x|=900, while the stalls, counters and hoods of `deck_bazaar`
    # sit between |x| 200 and 700 -- so the darkest two frames in `probe-350`
    # (`deck_props` 0.071, `deck_level` 0.093) were both standing in the market.
    # A lamp per stall cluster per arm, hung above the hoods rather than beside them.
    ('bazaar_deck_s_0', (-560, -756, 430), 420, LAMP_AMBER, 120),
    ('bazaar_deck_s_1', (0, -756, 430), 420, LAMP_WHITE, 120),
    ('bazaar_deck_s_2', (560, -756, 430), 420, LAMP_PINK, 120),
    ('bazaar_deck_n_0', (-560, 776, 430), 420, LAMP_CYAN, 120),
    ('bazaar_deck_n_1', (0, 776, 430), 420, LAMP_WHITE, 120),
    ('bazaar_deck_n_2', (560, 776, 430), 420, LAMP_AMBER, 120),
    # The two covered arms under the roofs, whose lamps were only ever in the street.
    ('deck_arm_w', (-760, 0, 400), 400, LAMP_WHITE, 110),
    ('deck_arm_e', (760, 0, 400), 400, LAMP_WHITE, 110),
    ('bridge_n', (0, 952, 320), 300, LAMP_CYAN, 60), ('bridge_s', (0, -840, 300), 300,
                                                        LAMP_CYAN, 60),
    ('bridge_w', (-952, 0, 320), 300, LAMP_AMBER, 60), ('bridge_e', (952, 0, 320), 300,
                                                         LAMP_AMBER, 60),
    ('deck_stair_s', (-304, -700, 340), 320, LAMP_WHITE, 70),
    ('deck_stair_e', (900, 272, 340), 320, LAMP_WHITE, 70),
    ('deck_ramp_w', (-900, 272, 340), 320, LAMP_AMBER, 70),
    ('deck_ramp_n', (-680, 900, 340), 320, LAMP_GREEN, 70),
    # the roofs
    ('garden_0', (-900, 200, 600), 460, LAMP_GREEN, 100), ('garden_1', (-620, -260, 600), 420,
                                                           LAMP_GREEN, 90),
    ('koi', (-888, 316, 560), 300, LAMP_HOLO, 70), ('torii_0', (880, 0, 620), 520, LAMP_PINK, 120),
    ('torii_1', (720, 0, 580), 380, LAMP_AMBER, 90), ('roof_n_0', (-400, 900, 600), 460,
                                                       LAMP_WHITE, 90),
    ('roof_n_1', (400, 900, 600), 460, LAMP_CYAN, 90), ('roof_stair_w', (-900, -250, 580), 340,
                                                         LAMP_WHITE, 70),
    # the viaduct and the spine over the plaza
    ('via_w', (-600, 816, 780), 420, LAMP_CYAN, 90), ('via_e', (600, 816, 780), 420, LAMP_CYAN, 90),
    ('via_mid', (0, 816, 780), 460, LAMP_WHITE, 100), ('via_soul', (0, 1000, 580), 340, LAMP_HOLO,
                                                        70),
    # 152 off the centre: the walkway's own piers now stand at 224 with a 96-unit
    # capital, a service conduit runs under its deck at x 64..128, and a lamp in
    # either is what q3map2 calls a leak -- the compiler's only word for a hole in
    # the world, for a world that has none.
    ('bridge_span_0', (-152, -192, 470), 360, LAMP_WHITE, 80),
    ('bridge_span_1', (152, -192, 470), 360, LAMP_WHITE, 80),
    # the districts that need their own colour so a fight reads from a distance
    # Three places measured black in `probe-353` and they are black for the same
    # reason: they are under something.  `spawn_dock` (0.050) is under the viaduct's
    # span, `spawn_w_lane_s` (0.064) is under the market deck's south arm, and the
    # north service ramp (`up_n`, 0.037) is a 444-unit climb with one lamp at its
    # head.  `q3map_skyLight` cannot reach under a plate -- that is what the plate is
    # for -- and a capped lamp 400 units away is a suggestion.  Each gets its own
    # row of warm lamps, hung where a loading yard, a rear street and a fire escape
    # would have them.
    ('dock', (-830, 760, 190), 420, LAMP_AMBER, 90),
    ('dock_1', (-980, 640, 170), 360, LAMP_AMBER, 120),
    ('dock_2', (-700, 880, 170), 340, LAMP_AMBER, 110),
    ('lane_s_w', (-520, -1000, 150), 400, LAMP_AMBER, 120),
    ('lane_s_w2', (-900, -1000, 150), 380, LAMP_AMBER, 110),
    ('ramp_n_0', (-680, 900, 150), 340, LAMP_AMBER, 130),
    ('ramp_n_1', (-680, 700, 200), 340, LAMP_AMBER, 120),
    ('ramp_n_2', (-680, 520, 250), 320, LAMP_AMBER, 110),
    # `spawn_w_lane_s` (-700,-424) measured 0.066 with a lamp 76 units away at r=380,
    # because that lamp is hung to pool on a stall row and the spawn is looking down
    # an empty 200-unit stretch of the rear street.  One lamp per stretch.
    ('lane_w_s0', (-700, -260, 150), 340, LAMP_AMBER, 110), ('station', (700, -860, 190), 460, LAMP_WHITE,
                                                       100),
    ('kiosk', (580, -640, 200), 300, LAMP_PINK, 70), ('chute_n', (0, 940, 120), 260, LAMP_HOLO, 60),
)


#: Above this radius a lamp is not a wash from one machine, it is the weather of a
#: district -- and a district may only have two weathers here: tungsten and moon.
# 320, not 360.  `up_n` measured 0.037 mean luminance after the first retune: a
# player walking the north service ramp was walking through a black tunnel lit by
# one sage lamp at r=320, which the 360 threshold had just enough room to spare.
# The lamp was not the problem -- a lamp is not sage -- the threshold was.
BIG_WASH = 320.0
#: The hues that are allowed to be loud, and where they are allowed to be loud.
COOL_SATURATED = (LAMP_CYAN, LAMP_HOLO, LAMP_GREEN)
WARM_SATURATED = (LAMP_PINK,)


def palette_policy(entry):
    """-> the entry with a big lamp wearing a colour a big lamp is allowed to wear.

    Written as a function over the table rather than as 76 hand-chosen colours,
    because the table is edited by hand and it keeps making the same beautiful
    mistake: a cyan lamp at r=460, which is not a machine, it is a weather front.
    """
    name, location, radius, colour, cap = entry[:5]
    if radius >= BIG_WASH and colour in COOL_SATURATED + WARM_SATURATED:
        colour = LAMP_MOON if colour in COOL_SATURATED else LAMP_AMBER
    return (name, location, radius, colour, cap) if len(entry) == 5 else entry


def _climb_lamps():
    """-> lamps hung along each ramp, at heights interpolated from the ramp.

    `up_n` measured 0.120 mean luma and `ramp_w_view` 0.212: the two ramps were the
    two darkest places a player can stand and still be on a route.  Their flanking
    `stair_light` kerbs hug the barrier and light the tread from the side, which
    leaves the middle of a 444-unit run in its own shadow.  These hang on the run's
    own centre line, 56 above the surface at the point they stand over -- derived
    from `CLIMB_N`/`CLIMB_W` rather than typed, because a ramp that is re-cut moves
    its lamps with it and a typed coordinate does not.
    """
    out = []
    for climb in (CLIMB_N, CLIMB_W):
        cname, cstart, cend = climb[0], climb[1], climb[2]
        for index, t in enumerate((0.20, 0.46, 0.72)):
            out.append(('climb_%s_%d' % (cname[-1], index),
                        (cstart[0] + (cend[0] - cstart[0]) * t,
                         cstart[1] + (cend[1] - cstart[1]) * t,
                         cstart[2] + (cend[2] - cstart[2]) * t + 56.0),
                        260, LAMP_WHITE, 90))
    return tuple(out)


def _start_fill():
    """-> lamps for the deathmatch starts that measured darkest in the capture set.

    A spawn frame is the first image a player gets of the arena and the first
    thing they do in it is look for cover.  Four starts measured between 73 % and
    52 % black -- `roof_n_w`, `w_lane_s`, `dock`, and the east street's south run
    as seen from `lane_view_e` -- and in each case the level had put its light
    somewhere *near* the start rather than on it: the roofs were washed by lamps
    hung 400 units away, and the west start sat in the shadow of its own viaduct.
    These hang 72 above the start's own floor tile -- above a head, not inside one
    -- at a radius that lights the tile and the two beside it, so the player can
    read the room they spawn into without the lamp bleeding into the next one.
    """
    want = {'w_lane_s': (320, LAMP_WHITE, 110), 'dock': (320, LAMP_AMBER, 110),
            'roof_n_w': (420, LAMP_WHITE, 110), 'roof_e': (380, LAMP_AMBER, 100)}
    out = [('fill_%s' % name, (x, y, z + 72.0), spec[0], spec[1], spec[2])
           for name, (x, y, z), _angle in SPAWNS if name in want for spec in (want[name],)]
    out.append(('fill_lane_e_s', (880.0, -620.0, 200.0), 360, LAMP_WHITE, 110))
    return tuple(out)


# `LIGHTS` is deliberately not assembled here: `_start_fill` hangs lamps over the
# deathmatch starts, and `SPAWNS` is defined further down this module.  Reading it
# from here raised a NameError inside Blender, where a script that dies at import
# prints nothing and leaves the `.blend` untouched -- so the table is built below
# `SPAWNS` instead, and `lights()` is only called at the end of the build.


def buried(x, y, z, margin=4.0):
    """-> the name of the geometry a point stands inside, or None.

    q3map2 has one message for an entity origin in a solid leaf -- `Entity leaked`
    -- and it is the same word it uses for a hole in the world, which is how three
    lamps sitting in lintels read for two builds as a leak the level did not have.
    Checking the number here, against the scene's own record, turns that message
    into a line in the author log that names the brush.
    """
    for name, low, high, kind in BOXES:
        if kind == 'trigger':
            continue
        if (low[0] - margin < x < high[0] + margin and low[1] - margin < y < high[1] + margin
                and low[2] - margin < z < high[2] + margin):
            return name
    return None


def lights():
    """Every lamp the level hangs, each one measured to hang in air.

    A lamp table is a list of coordinates and the level it lights keeps moving:
    a pier raised under a walkway, a conduit added to its underside, a lintel slid
    along its row, and a lamp that was clear on the day it was typed is inside a
    solid by Thursday.  So each entry is tried at its own point first and then at
    four offsets along its row -- 32, 64 and 96 either way -- and only a lamp that
    cannot be moved out of geometry anywhere near its pool is reported.
    """
    for name, location, radius, colour, cap in LIGHTS:
        x, y, z = location
        if buried(x, y, z) is None:
            lamp(name, location, radius, colour, cap)
            continue
        found = None
        for step in (32.0, 64.0, 96.0, 128.0):
            for dx, dy in ((step, 0.0), (-step, 0.0), (0.0, step), (0.0, -step)):
                if buried(x + dx, y + dy, z) is None:
                    found = (x + dx, y + dy, z)
                    break
            if found:
                break
        if found is None:
            PROP_PROBLEMS.append('light %s at %g,%g,%g is inside %s and cannot be moved'
                                 % (name, x, y, z, buried(x, y, z)))
            continue
        print('japanDM: light %s moved %g,%g,%g -> %g,%g,%g to clear %s'
              % (name, x, y, z, found[0], found[1], found[2], buried(x, y, z)))
        lamp(name, found, radius, colour, cap)


# --- spawns and items --------------------------------------------------------
def spawn(name, location, angle):
    """`location` is the floor point; the origin sits 24 above it (PLAYER_MINS)."""
    x, y, floor = location
    return map_blender.entity('spawn_%s' % name, 'info_player_deathmatch', (x, y, floor + 24),
                              angle=angle)


# Fourteen starts, none in the open centre of the plaza, each with a solid within
# about 200 units so a spawn is never a firing position.  They sit on three tiers
# -- street, market deck, roof -- and the monorail viaduct holds none of them.
# Its rails are 44 tall and its guide beam 40, both above the 22-unit eye height,
# so every point on that deck looks out of a trench: `map_spawn_aim.py` measured
# 85 degrees of clear cone for a start that faced straight down the far lane, and
# its scan of the walkable map finds no legal start anywhere on the viaduct.  The
# deck is therefore the reward and not a spawn, which is what it was built to be:
# the kineticore and its ammo stand in its far lane, 192 above the roof, reached
# by two stairs that nobody spawns beside.
#
# The angle is as deliberate as the position, and for the opposite reason.  A
# start needs cover near it and must not be LOOKING at that cover: the first
# half-second of a life is spent reading the fight, and a crate 45 units in
# front of the eye is a texture test, not a place.  The old numbers were chosen
# by eye and got that wrong eleven times out of fourteen -- `map_spawn_aim.py`
# measured nine start frames whose whole view was one surface.  Every angle here
# is the facing that tool solved for the finished geometry: the most open
# straight-ahead line and the widest +-25 degree cone, with cover still inside
# 40..240 units behind the shoulders.
#
# Position is bounded by TWO other rules as well, and the eastern deck start has
# now been moved three times by them pulling against each other.  (940, 300) was
# unexposed but looked at a stall.  (920, 536) looked down 1400 units of open deck
# and, for that same reason, could be shot along it from the west canopy walk 1900
# units away -- 57 vantages -- which is what `map_sightlines.py` exists to catch.
# (1016, -168) satisfied both and then turned out to be unseatable: it sits 8 units
# from a glass balustrade, and eight units is legal for a FOOT (the sampling model's
# margin) and impossible for a BODY (30 x 30 x 56 around the origin), so the engine
# spent 20 seconds of a capture refusing to put a player down there.  That rule is
# now measured too -- `body_box` in `map_spawn_aim.py` -- and with all three rules
# applied, the eastern deck has no legal spot left at all: the deck's 42 remaining
# legal starts are on the street, the west deck and the roof.
#
# So the fourth deck start is where the deck permits, and the fourth gate is the
# one that found this spot: (-520, 296) passed the first three and then the
# sightline probe reported `deck_w <-> deck_plaza` as a pair with no cover, because
# 420 units of straight ring walkway is one firing line between two spawns.  A
# proposed spot therefore also may not SEE an existing start.  With all four rules
# the deck has three legal spots left and (-472, -760) is the best: 609 units down
# the ring's south-west leg, a 345-unit cone and cover at 38, with the nearest
# start 406 units away.  The eastern deck stays without a start on purpose -- its
# legal options there look at 300 units of stall front, and `e_lane` already owns
# that district 306 units below them.
SPAWNS = (
    ('w_lane_n', (-860, 300, T0), 125), ('w_lane_s', (-700, -424, T0), 145),
    ('e_lane', (860, 260, T0), 280),     ('dock', (-940, 960, 16), 5),
    ('station', (620, -840, 16), 160),
    ('deck_w', (-940, 300, T1), 235), ('deck_sw', (-472, -760, T1), 205),
    ('deck_n', (-460, 700, T1), 180), ('deck_s', (560, -900, T1), 10),
    ('garden', (-960, 20, T2), 355), ('torii', (580, -300, T2), 355),
    ('roof_n_w', (-600, 1000, T2), 210), ('roof_n_e', (560, 980, T2), 295),
    ('roof_e', (488, 680, T2), 170),
)

# Assembled here, after `SPAWNS`: see the note where `LIGHTS_RAW` is opened.
LIGHTS_RAW = LIGHTS_RAW + _climb_lamps() + _start_fill()
LIGHTS = tuple(palette_policy(entry) for entry in LIGHTS_RAW)


def spawns():
    for name, location, angle in SPAWNS:
        spawn(name, location, angle)


# Weapon and reward placement follows risk: small arms and small health on the
# exposed T0 ring, the mid-tier weapons and both armours on the market deck, the
# metamaser at the torii and the kineticore on the viaduct, and the cordite
# behind the chute that costs health to reach. The three boosts and the soul are
# 60-second controls (domain/items.zig:respawnDelay) and none of them sits on the
# direct line between the two high grounds.
PICKUPS = (
    ('glock_w', 'weapon_glock', (-968, 200, T0)), ('glock_e', 'weapon_glock', (640, 260, T0)),
    ('ripgun_s', 'weapon_ripgun', (880, -700, 16)),
    ('slugger_w', 'weapon_slugger', (-760, 300, T1)),
    ('novabeam_e', 'weapon_novabeam', (760, 300, T1)),
    ('metamaser', 'weapon_metamaser', (880, 0, T2 + 16)),
    ('kineticore', 'weapon_kineticore', (-200, 880, VIA)),
    ('cordite', 'weapon_cordite', (0, 946, T0)),
    ('bullets_w', 'ammo_bullets', (-968, 344, T0)), ('bullets_e', 'ammo_bullets', (700, 420, T0)),
    ('rockets_s', 'ammo_ripgun', (740, -800, 32)),
    ('slugger_ammo', 'ammo_slugger', (-700, 200, T1)),
    ('novabeam_ammo', 'ammo_novabeam', (700, 200, T1)),
    ('metamaser_ammo', 'ammo_metamaser', (1000, -120, T2 + 16)),
    ('kineticore_ammo', 'ammo_kineticore', (200, 880, VIA)),
    ('cordite_ammo', 'ammo_cordite', (-40, 986, T0)),
    ('health_w', 'item_health_25', (-600, -424, T0)), ('health_e', 'item_health_25', (760, 300,
                                                                                        T0)),
    ('health_s', 'item_health_25', (0, -790, T0)),
    # One health per footbridge, mid-span: the crossings are the deck's four
    # choke points, so the reward for holding one is the means to stay on it.
    ('health_bridge_n', 'item_health_25', (0, BRIDGE_IN + 72, T1)),
    ('health_bridge_s', 'item_health_50', (0, -BRIDGE_IN - 72, T1)),
    ('health_deck_s', 'item_health_50', (200, -900, T1)),
    ('kevlar', 'item_kevlar_armor', (-500, 700, T1)), ('ebonite', 'item_ebonite_armor',
                                                       (200, 940, T1)),
    ('speed', 'item_speed_boost', (64, -192, T2)), ('attack', 'item_attack_boost', (760, -120,
                                                                                    T2 + 16)),
    ('acro', 'item_acro_boost', (0, 770, VIA)), ('soul', 'item_goldensoul', (0, 1000, T2)),
    ('orb', 'item_wraithorb', (-990, 780, 32)),
)


#: How far an item will slide looking for a place it can be picked up from: two
#: player bodies, no further, because an item that moves a screen away is no longer
#: the reward the level's risk curve promised.  It searches in third-body steps
#: (`STEP_THIRD`) ordered by how far the reward travels, straight along an aisle
#: before diagonally across one, so the item keeps its place in the map's risk
#: curve and only the counter it was standing inside moves out of the way.
ITEM_SLIDE = tuple(sorted(
    ((dx * STEP_THIRD, dy * STEP_THIRD)
     for dx in range(-7, 8) for dy in range(-7, 8)
     if dx * dx + dy * dy <= 49),
    key=lambda step: (round((step[0] ** 2 + step[1] ** 2) ** 0.5, 3),
                      min(abs(step[0]), abs(step[1])), step[0] ** 2 + step[1] ** 2,
                      step)))
ITEM_SHIFTS = []


def occupant_of(x, y, floor, half=ITEM_HALF, tall=ITEM_TALL):
    """-> the authored object filling the volume an item needs at this point.

    Asked of the finished furniture list rather than of the pickup table, because
    the furniture moves: stalls, counters and planters have all been slid since the
    item table was typed, and the item table cannot follow them by itself.
    """
    low = (x - half, y - half, floor)
    high = (x + half, y + half, floor + tall)
    for name, blow, bhigh, kind in BOXES:
        if kind not in ('prop', 'stair', 'slab', 'rail'):
            continue
        if (blow[0] < high[0] and bhigh[0] > low[0]
                and blow[1] < high[1] and bhigh[1] > low[1]
                and blow[2] < high[2] and bhigh[2] > low[2]
                and min(bhigh[2], high[2]) - floor > STEP_UP):
            return name
    return None


def items():
    """Place every item, each one where a player can actually reach it."""
    global _BODY_KEEPS
    # Whatever the geometry pass cached about item volumes is about to be wrong.
    _BODY_KEEPS = None
    for name, classname, (x, y, floor) in PICKUPS:
        spot, moved = (x, y), None
        for dx, dy in ITEM_SLIDE:
            spot = (x + dx, y + dy)
            if max(abs(spot[0]), abs(spot[1])) > FACE - 24.0:
                continue
            if occupant_of(spot[0], spot[1], floor) is None:
                moved = (dx, dy)
                break
        if moved is None:
            PROP_PROBLEMS.append('pickup %s at %g,%g,%g is inside %s and cannot be '
                                 'moved out of it'
                                 % (name, x, y, floor, occupant_of(x, y, floor)))
            spot = (x, y)
        elif moved != (0.0, 0.0):
            ITEM_SHIFTS.append('%s moved %g,%g to be reachable' % (name, *moved))
        _ITEM_SPOTS[name] = (spot[0], spot[1], floor)
        map_blender.entity('pickup_%s' % name, classname, (spot[0], spot[1], floor + 24))
    # ...and every question asked after this one is asked of where the rewards really stand.
    _BODY_KEEPS = None



# --- generated props ---------------------------------------------------------
# The last two metres.  Everything above this line is authored with the level's
# own helpers, and that is exactly why the street stopped being convincing at
# close range: a real market floor is bins, carts, lanterns, condensers and
# machines, none of which is a box.  They arrive as generated meshes, are
# decomposed into convex brushes by `dkq3/tools/map_prop_brushes.py`, and are
# placed and dressed by `props.py`.  One object per placement, because
# `map_author.loose_parts` splits disconnected islands into separate brushes
# anyway and 60 placements makes 60 objects rather than 300.
#
# Every prop is `detail`: no vis splits and no shadows.  The first is what keeps
# an 807-brush arena from becoming a 1100-brush compile; the second is the price,
# and it is why the placement table sits props against lit surfaces (under an
# awning strip, beside a machine, along a roof edge) instead of freestanding in
# the middle of a light pool where a missing shadow would be the only thing
# anyone saw.
PROP_PROBLEMS = []
#: Placements that could not be stood on a walking line even after sliding, printed
#: by `verify` as a report.  A lost bin is a thinner street, not a broken level; a
#: bin that stays where it blocks a route is both.
PROP_ROUTE_DROPS, PROP_SHIFTS_LOG, PROP_KEPT = [], [], []
PROP_SHIFTS = ((0.0, 0.0), (48.0, 0.0), (-48.0, 0.0), (0.0, 48.0), (0.0, -48.0),
               (96.0, 0.0), (-96.0, 0.0), (0.0, 96.0), (0.0, -96.0),
               (48.0, 48.0), (-48.0, -48.0), (48.0, -48.0), (-48.0, 48.0))


def prop_scatter():
    """Place the generated props, each wearing this map's own materials.

    A prop that cannot be built is recorded as a placement defect rather than
    skipped quietly: a bazaar that silently loses its carts back at 1999 prop
    density is the failure this pass exists to prevent, and a build that reports
    it is how it stays prevented.
    """
    table = PROPS.palette()
    if not table:
        PROP_PROBLEMS.append('no measured material palette: run map_prop_palette.py')
        return
    # (`PROPS.placements` has already dropped what cannot stand here; the count is
    # printed after the loop below, because a pass that quietly loses carts back
    # to 1999 density is the failure this file argues with the level about.)
    
    floors = {'T0': float(T0), 'T1': float(T1), 'T2': float(T2)}
    recipes, placed, brushes = {}, 0, 0
    # 64, not 24: a slug spawns as a 32-square body and then stands up, and a
    # vending machine parked over a spawn origin reads to the exporter as a spawn
    # standing 5 units inside a floor.  Every spawn in the level gets that much
    # air, whichever anchor the prop pass would otherwise have chosen.
    # 24: a spawn's body is a 32 square, so this is the spawn's own footprint and
    # not a zone around it.  The design wants cover *near* a start -- within about
    # 200 units -- and a 64-unit keep-out took the market's own bins and lanterns
    # away from eleven starts, which dresses the arena like a car park.
    no_go = [tuple(place[1]) for place in SPAWNS]  # (x, y, floor): the keep-out is per storey
    wanted = PROPS.placements(BOXES, floors, face=float(FACE), plaza_half=float(PLAZA),
                              foot=float(FOOT), lane=float(LANE),
                              no_go=[(spot, 24.0) for spot in no_go])
    for index, place in enumerate(wanted):
        # A prop is the one class of object that arrived *after* the routes were
        # drawn, and the first walk audit found bins, barriers and carts standing on
        # five named lanes and inside two stair mouths.  Ask the same question `box`
        # asks, and slide the placement along the wall it leans against rather than
        # losing it.
        spec = recipes.get(place['prop'])
        if spec is None:
            spec = PROPS.recipe(place['prop'])
            recipes[place['prop']] = spec
        if spec is None:
            PROP_PROBLEMS.append('prop %s has no brushes.json: run map_prop_brushes.py on '
                                 'maps/japanDM/props/%s' % (place['prop'], place['prop']))
            continue
        # Ask the question of the body the prop will actually build, not of a
        # footprint guessed from its name: the first version of this pass tested a
        # 112-square box around the placement point, and the planter that stood on the
        # station stair's third tread was wider than that on one side.
        body_blocked = None
        for dx, dy in PROP_SHIFTS:
            spot = (place['x'] + dx, place['y'] + dy)
            if max(abs(spot[0]), abs(spot[1])) > FACE - 40.0:
                continue
            built = PROPS.world_pieces(spec, spot[0], spot[1], place['z'], yaw=place['yaw'],
                                       scale=place['scale'])
            if not built:
                PROP_PROBLEMS.append('prop %s produced no pieces' % place['prop'])
                break
            low = [min(point[axis] for piece in built for point in piece[0])
                   for axis in range(3)]
            high = [max(point[axis] for piece in built for point in piece[0])
                    for axis in range(3)]
            # ...and the same question the scenery pass asks: a cart, bin or planter
            # parked on a deathmatch start does not decorate it, it swallows the
            # player the game puts there.  Sliding along the wall is tried before the
            # prop is lost, and a prop lost to a start is reported, not hidden.
            if body_clear((low[0], low[1], low[2]), (high[0], high[1], high[2])) is not None:
                # Remember who blocked the authored spot, but charge nothing yet: the
                # next candidate may be perfectly clear, and a prop that slid out of a
                # player's way is the rule working, not a defect.
                if body_blocked is None:
                    body_blocked = body_clear((low[0], low[1], low[2]),
                                              (high[0], high[1], high[2]))
                continue
            # The box is the prop's body plus a body standing beside it on the floor
            # below: a planter on a deck lip is harmless until a staircase arrives at
            # that lip, and a climber's head is 56 above a surface 256 lower.
            if not climb_required_clear((low[0], low[1], low[2] - 64.0),
                                        (high[0], high[1], high[2] + 8.0)):
                continue
            # ...and the stricter question, which `climb_required_clear` is built to
            # forgive: a cart whose top is below a climber's step-over height is not
            # in his way on a street and *is* in his way on the fourth step.
            # `prop_pushcart_26` and `prop_planter_85` both passed every test this
            # file used to have, one of them while standing on the flight at all.
            if climb_band_intrudes((low[0], low[1], low[2] - 64.0),
                                   (high[0], high[1], high[2] + 8.0)):
                continue
            if not lane_route_clear((low[0], low[1], low[2]), (high[0], high[1], high[2])):
                if dx == 0.0 and dy == 0.0:
                    PROP_KEPT.append(place['prop'])       # narrows a lane; keep it
                    break
                continue
            if dx or dy:
                PROP_SHIFTS_LOG.append('%s slid %g,%g off a walking line'
                                       % (place['prop'], dx, dy))
            place = dict(place, x=spot[0], y=spot[1])
            break
        else:
            # Nothing anywhere nearby was free.  If the reason was a player's own
            # volume, that is the one class of loss the arena cannot play around.
            if body_blocked is not None:
                PROP_SWALLOWS.append('%s at %g,%g has no place that is not %s'
                                     % (place['prop'], place['x'], place['y'], body_blocked))
            else:
                PROP_ROUTE_DROPS.append('%s at %g,%g' % (place['prop'], place['x'],
                                                         place['y']))
            continue
        if not built:
            continue
        spec = PROPS.PROPS[place['prop']]
        pieces = built
        brightest = max(PROPS.luminance(piece[2]) for piece in pieces) or 1e-6
        points, polygons, worn = [], [], []
        for piece_points, piece_polygons, colour in pieces:
            lit = bool(spec['glow']) and PROPS.luminance(colour) >= spec['glow_at'] * brightest
            shader = PROPS.material_for(colour, place['prop'], table, glow=lit)
            base = len(points)
            points.extend(piece_points)
            polygons.extend(tuple(base + offset for offset in polygon)
                            for polygon in piece_polygons)
            worn.extend([shader] * len(piece_polygons))
        name = 'prop_%s_%02d' % (place['prop'], index)
        first = mat(worn[0].split('/')[-1])
        try:
            made = map_blender._shell(name, points, polygons, first)
        except ValueError as error:
            PROP_PROBLEMS.append('%s: %s' % (name, error))
            continue
        # Slots first, indices second: `materials.append` on a mesh whose polygons
        # already carry indices leaves those indices pointing at the old slot 0.
        worn_index = {worn[0].split('/')[-1]: 0}
        for shader in worn:
            key = shader.split('/')[-1]
            if key not in worn_index:
                made.data.materials.append(mat(key))
                worn_index[key] = len(made.data.materials) - 1
        for position, shader in enumerate(worn):
            made.data.polygons[position].material_index = worn_index[shader.split('/')[-1]]
        low = tuple(min(point[axis] for point in points) for axis in range(3))
        high = tuple(max(point[axis] for point in points) for axis in range(3))
        record(name, low, high, 'prop')
        map_blender.decorate(made)
        placed += 1
        brushes += sum(1 for _ in pieces)
    print('japanDM: %d generated props, ~%d brushes, %d placements unusable'
          % (placed, brushes, len(PROP_PROBLEMS)))
    gone = PROPS.dropped()
    if gone:
        print('japanDM: %d placements had nowhere to stand and were dropped: %s'
              % (len(gone), ', '.join(gone)))


# --- the body that has to fit through the level ------------------------------
# Everything in this section restates what the engine already believes about a
# player, read from `src/runtime/domain/player_move.zig`: `Parameters.mins` is
# (-15,-15,-24) and `maxs` is (15,15,32) with the origin 24 above the ground, so a
# body is 30 units square and 56 tall above the surface it stands on, and
# `slide.Context` steps up 18.  A route is therefore a line of 30 x 56 boxes, and
# the one question worth asking of authored geometry is whether any of them is
# occupied.  `verify` compares dressings against dressings and exempts `slab`
# entirely, which is how the level could ship a lintel through a stair and a crate
# in a bridge mouth and call both clean.
HULL_HALF = 15.0
BODY_TOP = 56.0
STEP_UP = 18.0
#: The shell and its clips bound the world rather than dress it; the sky is in the
#: way of nothing.
WALK_SHELLS = ('facade_', 'sky_ring', 'sky_lid', 'clip_', 'sky_')

VIADUCT_CLIMBS = (('viaduct_stair_w', (-600, 472, T2), (-600, VIA, VIA), 128),
                  ('viaduct_stair_e', (600, 472, T2), (600, VIA, VIA), 128))
#: Every way up in the level as one table, because they all have the same shape and
#: a rule that only checks the four famous stairs is a rule that misses a flight.
CLIMBS_ALL = (CLIMB_S, CLIMB_E, CLIMB_N, CLIMB_W,
              ROOF_CLIMB_W, ROOF_CLIMB_E, ROOF_CLIMB_N) + VIADUCT_CLIMBS

_STATIONS = {}


def climb_stations(climb, every=10.0):
    """-> the (x, y, surface) footfalls of one climb, from its foot to its top.

    Sampled along the run, so `surface` is the height under a body at that moment and
    the body that matters is (x +/- 15, y +/- 15, surface .. surface + 56).  The foot
    and the top are always sampled: that is where a flight meets a floor, and a mouth
    that meets none is the "stairs too big and close to the walls" the owner saw.
    """
    key = climb[0]
    if key not in _STATIONS:
        _name, start, end, _width = climb
        run = math.hypot(end[0] - start[0], end[1] - start[1])
        steps = max(2, int(run / every) + 1)
        _STATIONS[key] = [(start[0] + (end[0] - start[0]) * index / float(steps),
                           start[1] + (end[1] - start[1]) * index / float(steps),
                           start[2] + (end[2] - start[2]) * index / float(steps))
                          for index in range(steps + 1)]
    return _STATIONS[key]


def climb_clear(low, high, clearance=8.0):
    """-> whether a solid box leaves every climbing body in the level its own air.

    Asked of the centre line and the doors only, because this rule decides whether a
    lintel is built at all: a colonnade that must clear five lanes across a 192-unit
    flight loses every span it has, and the arcade that holds the deck up is the
    reason the owner called the level flying.
    """
    for x, y, surface in _climb_required_points():
        if (low[0] < x + HULL_HALF and high[0] > x - HULL_HALF
                and low[1] < y + HULL_HALF and high[1] > y - HULL_HALF
                and low[2] < surface + BODY_TOP + clearance and high[2] > surface):
            return False
    return True


#: Which prefixes in this scene are scenery: they exist to make a surface read as
#: a street, and not one of them is worth a route.  Structural geometry - slabs,
#: stairs, counters, rails, the level's own stall rows - is deliberately absent: those
#: define the lanes, and the lanes in `WALK_LINES` are drawn to fit them.  The screen
#: names are here because a sightline screen is a crate stack, a planter or a wall, and
#: the greedy planner that proposed it never asked whether a player could still pass.
YIELD_TO_ROUTES = ('tank_', 'hvac_', 'vent_', 'laundry_', 'bb_', 'roof_house_', 'koi_',
                   'pergola_', 'planter_', 'deck_planter_', 'crates_', 'cabinet_',
                   'duct_bank', 'roadworks', 'hauler', 'market_wall', 'platform_screen',
                   'transformer', 'stair_house_', 'stall_deck_', 'stall_lane_',
                   'dock_crates', 'kiosk_', 'container_',
                   'w_sign', 'e_sign', 'n_sign', 's_sign', 'w_cond', 'e_cond',
                   'n_cond', 's_cond', 'w_pipe', 'e_pipe', 'n_pipe', 's_pipe',
                   'w_meter', 'e_meter', 'n_meter', 's_meter', 'w_awning', 'e_awning',
                   'n_awning', 's_awning', 'banner_', 'corner_bollard',
                   # Strung lanterns hang in the air a staircase needs, and a hedge is
                   # the one planter that was never in the list: both appeared in the
                   # first audit standing in a stair's mouth or under its flight.
                   'lantern_', 'hedge', 'deck_hedge', 'laundry_', 'screen_')
#: Scenery that yielded to a walking line, moved or dropped, printed by `verify`.
#: `ROUTE_KEPT` is the third answer: it stands where it stands and narrows a lane.
ROUTE_YIELDS, ROUTE_DROPS, ROUTE_KEPT = [], [], []
_ROUTE_POINTS = []


def _family(name):
    """-> the object a brush belongs to, with its part number and finish removed.

    A crate stack is four brushes and a stall is five, so an audit that asks whether
    a crate stack overlaps `anything` answers "yes -- itself" every time.  That is how
    the first yield pass concluded that a stack of dock crates had nowhere to stand.
    """
    return re.sub(r'(_[0-9]+)+(_[a-z]+)?$', '', name)


def _stand_clear(low, high, share=0.30, name=''):
    """-> whether a scenery box has room to stand where it was put.

    Scenery is allowed to touch things -- an awning overlaps its counter by design --
    so the test is the one `verify` uses for a pair of rival objects: a quarter of the
    smaller volume, halved again to leave the deliberate trims alone.
    """
    volume = _volume(low, high)
    mine = _family(name)
    for other, other_low, other_high, other_kind in BOXES:
        # A wall's own finish is not a rival object: an awning shares its lintel's
        # volume, a sign shares its bracket's, a livery shares its vehicle's, and a
        # test that counted those refused every move a wall mount could make and then
        # deleted the sign.
        if (other_kind not in ('prop', 'stair', 'rail') or other.endswith(TRIM)
                or other.startswith(SHELLS) or _family(other) == mine):
            continue
        if _shared(low, high, other_low, other_high) >= share * min(volume, _volume(other_low,
                                                                                    other_high)):
            return False
    return True


def route_points():
    """-> every (x, y, floor) a protected route passes through, sampled once.

    The climbs and the named lines, because those are the two kinds of promise this
    level makes: a way up, and a way along.  Sampled once and cached - `box` asks this
    question hundreds of times an author run.
    """
    if not _ROUTE_POINTS:
        for climb in CLIMBS_ALL:
            _ROUTE_POINTS.extend(climb_stations(climb))
        for _label, path in WALK_LINES:
            for (x0, y0, z0), (x1, y1, z1) in zip(path, path[1:]):
                steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 10.0))
                for index in range(steps + 1):
                    t = index / float(steps)
                    _ROUTE_POINTS.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t,
                                          z0 + (z1 - z0) * t))
    return _ROUTE_POINTS


def _box_on_body(low, high, x, y, feet, half=HULL_HALF, clearance=6.0):
    """-> whether `low,high` occupies the 30 x 56 body standing at x,y on `feet`.

    Anything that stands no higher than a step-up is not in anybody's way: the engine
    steps 18, and a 16-unit duct or a 2-unit paving joint is walked over, not around.
    """
    return (low[0] < x + half and high[0] > x - half
            and low[1] < y + half and high[1] > y - half
            and low[2] < feet + BODY_TOP + clearance and high[2] > feet + STEP_UP)


_CLIMB_POINTS, _LANE_POINTS, _CLIMB_REQUIRED = [], [], []


def _climb_points():
    """-> every sampled lane of every climb, at 10-unit spacing (the audit's body)."""
    if not _CLIMB_POINTS:
        for climb in CLIMBS_ALL:
            for _label, path in climb_lines(climb):
                for (x0, y0, z0), (x1, y1, z1) in zip(path, path[1:]):
                    steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 10.0))
                    for index in range(steps + 1):
                        t = index / float(steps)
                        _CLIMB_POINTS.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t,
                                              z0 + (z1 - z0) * t))
    return _CLIMB_POINTS


def _climb_required_points():
    """-> the centre line and the two doors of every climb: the non-negotiable set."""
    if not _CLIMB_REQUIRED:
        for climb in CLIMBS_ALL:
            for label, path in climb_lines(climb):
                if not label.endswith(('/run+0', '/mouth', '/approach')):
                    continue
                for (x0, y0, z0), (x1, y1, z1) in zip(path, path[1:]):
                    steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 10.0))
                    for index in range(steps + 1):
                        t = index / float(steps)
                        _CLIMB_REQUIRED.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t,
                                                z0 + (z1 - z0) * t))
    return _CLIMB_REQUIRED


def _lane_points():
    if not _LANE_POINTS:
        for _label, path in WALK_LINES:
            for (x0, y0, z0), (x1, y1, z1) in zip(path, path[1:]):
                steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 10.0))
                for index in range(steps + 1):
                    t = index / float(steps)
                    _LANE_POINTS.append((x0 + (x1 - x0) * t, y0 + (y1 - y0) * t,
                                         z0 + (z1 - z0) * t))
    return _LANE_POINTS


def climb_route_clear(low, high, clearance=6.0):
    """-> whether a box leaves every sampled lane of every climb alone.

    This is the *audit's* question, and it is deliberately stricter than the question
    a builder asks: five lanes per flight, so a report can say which third of a
    staircase something took and how many are left.
    """
    for x, y, surface in _climb_points():
        if _box_on_body(low, high, x, y, surface, clearance=clearance):
            return False
    return True


def climb_required_clear(low, high, clearance=6.0):
    """-> whether a box leaves a climb's centre line and its two doors free.

    This is the promise a builder has to keep, and it is the one the owner's
    complaint is about: a tier you cannot reach is not a slightly worse tier, and a
    staircase you cannot enter is the same defect wearing a different hat.  The outer
    lanes are judged by `walk_audit` in company, because a stair that still has a
    clear line up it is a stair -- and the thing standing in the other third of it is
    the market furniture the arena was asked to have more of.
    """
    for x, y, surface in _climb_required_points():
        if _box_on_body(low, high, x, y, surface, clearance=clearance):
            return False
    return True


def lane_route_clear(low, high, clearance=6.0):
    """-> whether a box leaves the named street lanes alone.

    Also true of a lane a stall stands beside: the lines are the level's promise that
    you can get from one end of a street to the other, and furniture narrows them --
    that is what a market is.  Judgement, not deletion; see `box`.
    """
    for x, y, feet in _lane_points():
        if _box_on_body(low, high, x, y, feet, clearance=clearance):
            return False
    return True


def route_clear(low, high, clearance=6.0, half=HULL_HALF):
    """-> whether a box leaves every route this level promises its body."""
    return climb_route_clear(low, high, clearance) and lane_route_clear(low, high,
                                                                       clearance)


def climb_lines(climb, stand_off=40.0, back=128.0):
    """-> the walking lines a climb owes its players: the run, its mouth, its door.

    Three lines down a flight, because a flight is 192 wide and a crate parked
    against one wall still seals the stair.  One line approaching the foot and one
    swept across the mouth, because a flight that arrives in a dead-end corner is not
    a route however walkable its treads are - which is what `stair_e` and
    `stair_roof_e` both were, standing with their feet against the tower front.
    """
    name, start, end, width = climb
    along = 0 if abs(end[0] - start[0]) > abs(end[1] - start[1]) else 1
    across = 1 - along
    sign = 1.0 if end[along] > start[along] else -1.0
    offset = max(24.0, width / 2.0 - 24.0)
    lines = []
    # Five lines across the flight, because a 192-unit staircase is not one line: a
    # crate parked against its west wall leaves two thirds of it walkable, and an
    # audit that called that a broken stair deleted the market's furniture to fix it.
    # The centre line and the two doors stay non-negotiable -- see `walk_audit`.
    laterals = [0.0]
    if width >= 128.0:
        laterals += [width / 4.0, -width / 4.0]
    if width - 48.0 > offset:
        laterals += [offset, -offset]
    for lateral in laterals:
        foot, top = list(start), list(end)
        foot[across] += lateral
        top[across] += lateral
        lines.append(('%s/run%+d' % (name, lateral), [tuple(foot), tuple(top)]))
    door = [list(start), list(start)]
    door[0][along] -= sign * back
    door[1][along] -= sign * 16.0
    lines.append(('%s/approach' % name, [tuple(door[0]), tuple(door[1])]))
    mouth = [list(start), list(start)]
    for one in mouth:
        one[along] -= sign * stand_off
        one[across] -= width / 2.0 + 16.0
    mouth[1][across] += width + 32.0
    lines.append(('%s/mouth' % name, [tuple(mouth[0]), tuple(mouth[1])]))
    return lines


# --- the arcade: what holds a plate up ---------------------------------------
# The owner's "some parts of map is flying (e.g. on 3 level)" is not a bug in the
# geometry the way a hole is: `map_support` proves every plate reaches the ground
# through the tower fronts it is built into.  It is a bug in what a player can
# *see*.  A 2300-unit plate 256 above a street, with nothing under it between one
# wall and the other, is a raft; a 2017 city puts a column under a deck every few
# metres, because that is what stops a deck falling down, and a player reads the
# column in one glance and stops reading the ceiling as a lie.
#
# So the covered street gets a two-deep colonnade down every lane and the three
# roofed arms get the same two lines one storey up.  Each column stands on the
# floor it carries, meets a lintel that meets the soffit, and is rejected (or slid
# along its row) wherever the level already put something solid.  Columns are
# `slab`-kind so `map_support` charges them with holding the deck up and the
# support chain becomes something the tool can check instead of something the
# author claims.
ARCADE_SPACING = 256.0
ARCADE_LATERALS = (PLAZA + 128.0, PLAZA + 352.0)
ARCADE_SECTION = 44.0
ARCADE_LINTEL = 48.0
#: How far along a row a column may be pushed to miss a crate it would otherwise
#: stand inside, before the position is abandoned altogether.
ARCADE_NUDGES = (0.0, 64.0, -64.0, 128.0, -128.0)
#: Which lintel spans were given up to a stair, printed by `arcade()`: a colonnade
#: that quietly loses a span has lost the thing that made it read as structure, and
#: the level should say out loud when it trades that for a route.
BEAM_OPENINGS = []
# Where a roof's colonnade stands across its arm: inset from the plaza edge rather
# than on the deck's own lateral lines, because a roof is a shallower plate than the
# deck it sits above and rows that suit the deck stand beside the roof, not under it.
ROOF_ARCADE_LATERAL = PLAZA / 2.0


#: Which rects have no floor at a given storey.  A column may not stand in a hole:
#: `_site_clear` compares against solids that *exist*, and a stair pit is the
#: absence of a slab, so the first audit found `arcade_t2_col_04_00` planted inside
#: the service ramp's opening with nothing around it to object.
#: Keyed by the floor a column *stands on*: the deck's own openings at T1, the
#: roof's at T2.  The first cut keyed these by the ceiling instead and left
#: `arcade_t2_col_04_00` standing on thin air inside the service ramp's mouth.
VOID_KEEPOUT = {int(T1): DECK_VOIDS,
                int(T2): [rect for rects in ROOF_HOLES.values() for rect in rects]}


def _site_clear(x, y, half, z0, z1, clearance=4.0):
    """-> whether a column of `half`-radius at x,y has the storey to itself."""
    for rect in VOID_KEEPOUT.get(int(z0), ()):
        if (rect[0] - half < x + half and rect[2] + half > x - half
                and rect[1] - half < y + half and rect[3] + half > y - half):
            return False
    if not route_clear((x - half, y - half, z0), (x + half, y + half, z1)):
        return False        # a nudge that lands a column on a lane is no nudge at all
    for name, low, high, kind in BOXES:
        if kind in ('detail', 'rail', 'trigger', 'loose') or name.startswith(SHELLS):
            continue
        if high[2] <= z0 + 2.0 or low[2] >= z1 - 2.0:
            continue
        if (low[0] - clearance < x + half and high[0] + clearance > x - half
                and low[1] - clearance < y + half and high[1] + clearance > y - half):
            return False
    for _name, place, _angle in SPAWNS:
        if abs(place[0] - x) < 88.0 and abs(place[1] - y) < 88.0:
            return False
    return True


def colonnade(prefix, rows, floor, ceiling, taken, section=None):
    """-> the columns, lintels and plinths for a set of rows.

    A row is `(axis, lateral, run_lo, run_hi)`: `axis` is the coordinate held
    constant (0 = x, so the row marches along y), `lateral` is that coordinate,
    and the run is the stretch of lane it stands in.  One beam spans the whole
    row and every column reaches it: the beam is what a player reads as the thing
    the deck sits on, and the columns are what the beam sits on.
    """
    made = []
    for index, (axis, lateral, run_lo, run_hi) in enumerate(rows):
        count = max(2, int(round((run_hi - run_lo) / ARCADE_SPACING)) + 1)
        step = (run_hi - run_lo) / float(count - 1)
        # A column one storey tall and a column two storeys tall cannot share a
        # section: at 44 units the plaza row reads as eight poles, and the eye
        # that reads a plate as "flying" is the same eye that reads a slender pole
        # as scaffolding rather than as the thing the roof sits on.
        half = (ARCADE_SECTION if section is None else section) / 2.0
        seats = []
        for step_index in range(count):
            along = run_lo + step * step_index
            for nudge in ARCADE_NUDGES:
                position = along + nudge
                if position < run_lo - 8.0 or position > run_hi + 8.0:
                    continue
                x, y = (lateral, position) if axis == 0 else (position, lateral)
                key = (round(x), round(y))
                if key in taken or not _site_clear(x, y, half + 10.0, floor, ceiling):
                    continue
                taken.add(key)
                seats.append((x, y))
                break
        if not seats:
            continue
        # A beam used to be ONE brush spanning the row from its first column to its
        # last, and that single lintel is what sliced the station stair in half:
        # `arcade_t1_beam_05` ran unbroken from x -864 to x 306 at z 176..224 straight
        # across y -800, the stair crosses y -800 with its surface at 138, and a body
        # on a tread reaches 194 -- so the climb stopped dead 56 units off the street,
        # which is the report "stairs too big and close to walls".  A real colonnade
        # has a lintel BETWEEN each pair of columns, which is both what the thing looks
        # like and what leaves an opening where a street passes through: each span is
        # its own brush now, and a span that a climb needs the air for is not built.
        # Where a row lost every span its columns reach the soffit themselves, as they
        # did when a row was reduced to one seat.
        lintels = []
        for seat in range(len(seats) - 1):
            a0, a1 = sorted((seats[seat][1 - axis], seats[seat + 1][1 - axis]))
            if a1 - a0 < ARCADE_SPACING / 2.0:
                continue                    # two columns shoulder to shoulder: no span
            if axis == 0:
                low, high = (lateral - half - 2.0, a0, ceiling - ARCADE_LINTEL), \
                            (lateral + half + 2.0, a1, ceiling)
            else:
                low, high = (a0, lateral - half - 2.0, ceiling - ARCADE_LINTEL), \
                            (a1, lateral + half + 2.0, ceiling)
            if not climb_clear(low, high):
                BEAM_OPENINGS.append('%s row %d span %g..%g: a climb needs the air'
                                     % (prefix, index, a0, a1))
                continue
            lintels.append((low, high))
        for seat, (low, high) in enumerate(lintels):
            made.append(box('%s_beam_%02d_%02d' % (prefix, index, seat), low, high,
                            CONCRETE, kind='slab'))
        for seat, (x, y) in enumerate(seats):
            top = (ceiling if not lintels else ceiling - ARCADE_LINTEL)
            made.append(box('%s_col_%02d_%02d' % (prefix, index, seat),
                            (x - half, y - half, floor), (x + half, y + half, top),
                            COLUMN, kind='slab'))
            # A plinth is what tells a column from a pole, and it is the one piece
            # of this that may sit inside the floor it stands on.
            made.append(box('%s_plinth_%02d_%02d_flange' % (prefix, index, seat),
                            (x - half - 8, y - half - 8, floor),
                            (x + half + 8, y + half + 8, floor + 14), CONCRETE, detail=True))
    return made


def arcade():
    """The colonnade under the market deck and under the three roofed arms."""
    taken = set()
    made = []
    rows = []
    for lateral in ARCADE_LATERALS:
        for sign in (-1, 1):
            rows.append((0, sign * lateral, -FACE + 160, FACE - 160))
            rows.append((1, sign * lateral, -FACE + 160, FACE - 160))
    made += colonnade('arcade_t1', rows, T0, T1 - DECK, taken)
    # Each roof is colonnaded under its own span and on the floor that is actually
    # under it.  The first cut reused the deck's lateral lines at |576| and |800|,
    # and those lines are not under the roofs at all: `roof_w` and `roof_e` reach
    # from the tower front to the plaza edge in x and no further than +/-448 in y,
    # so the rows marched through open air beside a plate while the plate itself was
    # held up only by the facade it is fused into.  `map_support` cannot see that as
    # a fault -- a slab welded to a wall is supported as far as a graph is concerned
    # -- which is why it reported zero floating slabs while the owner was looking at
    # a third tier with nothing under it.  What was missing was never load-bearing
    # structure; it was the row of columns a player's eye looks for under a soffit.
    #    * west and east roofs: one row either side of the arm's centre line, one
    #      storey up on the deck.
    #    * the west roof carries on over the plaza, where there is no deck at all,
    #      so its plaza half stands on the plaza floor and is two storeys to the
    #      soffit -- and is the only thing in the arena that explains where the roof
    #      over the bazaar comes from.
    #    * north roof: two rows across its 1536, one storey up on the deck.
    arm_rows = []
    for lateral in (-ROOF_ARCADE_LATERAL, ROOF_ARCADE_LATERAL):
        arm_rows.append((1, lateral, -FACE + 96.0, -PLAZA - 64.0))    # west arm
        arm_rows.append((1, lateral, PLAZA + 64.0, FACE - 96.0))      # east arm
    for lateral in (ARCADE_LATERALS[0], ARCADE_LATERALS[1]):
        arm_rows.append((1, lateral, -704.0, 704.0))                  # north roof
    made += colonnade('arcade_t2', arm_rows, T1, T2 - DECK, taken)
    print('japanDM: arcade of %d pieces on %d column sites'
          % (len(made), len(taken)))
    for opening in BEAM_OPENINGS:
        print('japanDM: arcade opening: %s' % opening)
    return made


# --- the bazaar: what a plate is supposed to be ------------------------------
# The plan view of the market deck was the second half of the owner's complaint:
# the south arm is a 2000 x 576 plate with one planter on it, and `spawn_deck_s`
# opens by staring down 800 units of empty grey.  A Japanese street market is not
# an empty floor with a few boxes-- it is a *street*: two unbroken rows of pitches
# with a clear way between them, each pitch a counter, a cloth hood, a lit lip and
# something for sale on the top.  Building it as bays on a lattice rather than as
# individual set pieces is what makes the row read as continuous, which is the
# property the eye actually tests.
BAY_PITCH = 168.0
BAY_WIDTH = 148.0
STALL_DEPTH = 80.0
STALL_LIP = COVER_MID
STALL_HOOD = 152.0


def market_bay(name, x0, back, faces, index):
    """One pitch opening onto the aisle.

    `faces` is +1 when the pitch opens toward +y (its back is the smaller-y face)
    and -1 when it opens toward -y.  Everything above the counter lip is `detail`:
    hoods, posters and lamps are not cover and must not split a vis cluster, and
    the counter itself stays solid so it stops a slug the way a stall should.
    """
    x1 = x0 + BAY_WIDTH
    y0, y1 = sorted((back, back + faces * STALL_DEPTH))
    # The top overhangs the aisle side only: the back is the tower-front line, and
    # a lacquer lip 4 proud of it is a lip inside a wall.
    ty0, ty1 = sorted((back + faces * 6, back + faces * (STALL_DEPTH + 8)))
    made = [box('%s_%02d_counter' % (name, index), (x0, y0, T1), (x1, y1, T1 + STALL_LIP),
                CRATE)]
    made.append(box('%s_%02d_top' % (name, index), (x0 - 4, ty0, T1 + STALL_LIP),
                    (x1 + 4, ty1, T1 + STALL_LIP + 8), LACQUER, detail=True))
    # Goods on the counter: three low blocks, uneven, because a stall with nothing
    # on it is a wall and not a stall.
    for slot, (px, pw) in enumerate(((0.14, 34.0), (0.44, 26.0), (0.74, 40.0))):
        cx = x0 + (x1 - x0) * px
        made.append(box('%s_%02d_goods%d_flange' % (name, index, slot),
                        (cx - pw / 2.0, y0 + 18, T1 + STALL_LIP + 8),
                        (cx + pw / 2.0, y0 + 18 + pw + 8, T1 + STALL_LIP + 30),
                        PLANT if slot == 2 else CLOTH, detail=True))
    # `front`, not `y1`: with the row facing -y the aisle edge is the *smaller*
    # y, and a hood or a post written off `y1` stood with its back to the way it
    # was supposed to open onto -- and 8 units inside a tower front.
    front = back + faces * STALL_DEPTH
    hood_y0, hood_y1 = sorted((front - faces * 24, front + faces * 60))
    made.append(box('%s_%02d_hood' % (name, index), (x0 - 10, hood_y0, T1 + STALL_HOOD),
                    (x1 + 10, hood_y1, T1 + STALL_HOOD + 12), CLOTH, detail=True))
    post_y = sorted((front - 8, front + 8))
    for post, cx in enumerate((x0 + 10, x1 - 10)):
        made.append(box('%s_%02d_post%d_flange' % (name, index, post),
                        (cx - 6, post_y[0], T1 + STALL_LIP), (cx + 6, post_y[1],
                                                              T1 + STALL_HOOD),
                        COLUMN, detail=True))
    made.append(box('%s_%02d_lip_flange' % (name, index),
                    (x0 - 10, sorted((front + faces * 52, front + faces * 60))[0],
                     T1 + STALL_HOOD - 12),
                    (x1 + 10, sorted((front + faces * 52, front + faces * 60))[1],
                     T1 + STALL_HOOD), STRIP, detail=True))
    # The menu board stands on the counter at its back, above the lip, so it neither
    # crosses the front line nor shares a cubic with the counter it leans on.
    board_y = sorted((back + faces * 6, back + faces * 18))
    made.append(box('%s_%02d_board_flange' % (name, index),
                    (x0 + 12, board_y[0], T1 + STALL_LIP + 8),
                    (x1 - 12, board_y[1], T1 + STALL_HOOD - 8), ADBOARD, detail=True))
    return made


def _bay_free(x0, back, faces):
    """-> whether a pitch's footprint is clear of what the deck already holds.

    A skip, not a nudge: a market row reads as continuous because the *hoods* run
    unbroken, and a pitch that was slid half a bay to miss a planter would put its
    hood out of line with its neighbours.  Where the deck already has something --
    a planter, a billboard's legs -- the row leaves a doorway, which is the way a
    real arcade has doorways anyway.
    """
    y0, y1 = sorted((back, back + faces * (STALL_DEPTH + 84)))
    area = BAY_WIDTH * abs(y1 - y0)
    for name, low, high, kind in BOXES:
        if kind in ('detail', 'rail', 'trigger', 'loose') or name.startswith(SHELLS):
            continue
        if high[2] <= T1 + 2.0 or low[2] >= T1 + 210.0:
            continue
        span_x = min(x0 + BAY_WIDTH, high[0]) - max(x0, low[0])
        span_y = min(y1, high[1]) - max(y0, low[1])
        if span_x > 4.0 and span_y > 4.0 and span_x * span_y > 0.03 * area:
            return False
    return True


def market_row(name, segments, back, faces, aisles=()):
    """-> every pitch in a row, with the cross-ways left as gaps."""
    made, skipped = [], 0
    for seg, (x0, x1) in enumerate(segments):
        index, x = 0, x0
        while x + BAY_WIDTH <= x1:
            centre = x + BAY_WIDTH / 2.0
            if any(lo <= centre <= hi for lo, hi in aisles) or not _bay_free(x, back, faces):
                skipped += 1
                x += BAY_PITCH
                continue
            made += market_bay('%s_s%d' % (name, seg), x, back, faces, index)
            index += 1
            x += BAY_PITCH
    if skipped:
        print('japanDM: %s left %d doorway(s) for furniture already on the deck'
              % (name, skipped))
    return made


def paving(name, rect, spacing=192.0, along=0, holes=()):
    """Joint lines in a bare floor: the cheapest scale a large plate can get.

    One direction only.  Two directions cross, and two crossing strips are one
    box inside another -- an audit finding nobody would defend -- so the grid is
    drawn as unbroken stripes along the long axis of the rectangle, which is also
    how a paving crew actually lays a street.

    `holes` are the voids cut in the floor this paving lies on.  A joint line is 2
    units proud of the plate, so an unbroken stripe across a stairwell was a
    floating ribbon over a 256-unit drop -- one of the "parts that are flying" the
    owner reported, invisible to every support check because a 2-unit trim carries
    nothing.  Each stripe is now laid in segments around each void that crosses it.
    """
    x0, y0, x1, y1 = rect
    made = []
    if along:
        start, end, other_from, other_to = y0 + spacing / 2.0, y1, x0, x1
    else:
        start, end, other_from, other_to = x0 + spacing / 2.0, x1, y0, y1
    for index, line in enumerate(_lattice(start, end, spacing)):
        gaps = []
        for h0, h1, h2, h3 in holes:
            if along and h1 - 8 <= line <= h3 + 8:
                gaps.append((max(h0 - 8, other_from), min(h2 + 8, other_to)))
            elif not along and h0 - 8 <= line <= h2 + 8:
                gaps.append((max(h1 - 8, other_from), min(h3 + 8, other_to)))
        for piece, (a0, a1) in enumerate(spans(other_from, other_to, gaps, piece=24.0)):
            if along:
                made.append(box('%s_%02d_%d_flange' % (name, index, piece),
                                (a0, line - 4, T1), (a1, line + 4, T1 + 2), CONCRETE,
                                detail=True))
            else:
                made.append(box('%s_%02d_%d_flange' % (name, index, piece),
                                (line - 4, a0, T1), (line + 4, a1, T1 + 2), CONCRETE,
                                detail=True))
    return made


def _lattice(start, end, step):
    value = start
    while value < end:
        yield value
        value += step


def deck_market():
    """The bazaar street on the south arm, and the two rows the north arm lacks."""
    made = []
    # --- the south arm: one market street the whole length of the block --------
    # Backs against the tower front, one row each side of a 384-unit way, and the
    # two stairwell voids and the grated light well kept clear of pitches.
    south_west = (-1008, -540)
    south_east = (-150, 1000)
    made += market_row('bazaar_a', (south_west, south_east), -1024, +1,
                       aisles=((704 - 20, 896 + 20),))
    made += market_row('bazaar_b', (south_west, south_east), -480, -1,
                       aisles=((704 - 20, 896 + 20),))
    # The way itself: joint lines along its length, and a lit kerb along each
    # row's front so the walking line is legible from the plaza end.
    made += paving('pave_s', (-1008, -944, 1000, -560), spacing=168.0, along=1,
                   holes=DECK_VOIDS)
    for side, y in ((-1, -944), (1, -560)):
        made.append(box('bazaar_kerb_%d_flange' % side, (-1008, y - (10 if side < 0 else -4), T1),
                        (1000, y + (4 if side < 0 else 10), T1 + 3), STRIP, detail=True))
    # A valance over the way, hung between the two hoods: what makes a market
    # street read as enclosed rather than as two queues of furniture.
    made.append(box('bazaar_banner', (-1008, -780, T1 + 196), (1000, -756, T1 + 212), CLOTH,
                    detail=True))
    made.append(box('bazaar_banner_glow', (-1008, -776, T1 + 188), (1000, -760, T1 + 196),
                    NEON_B, detail=True))
    for index, x in enumerate((-900, -500, -100, 300, 700)):
        made.append(box('bazaar_hang%02d_flange' % index, (x - 4, -780, T1 + 172),
                        (x + 4, -756, T1 + 196), COLUMN, detail=True))
    # --- the north arm: the same street, one row, facing the ramp head ---------
    made += market_row('bazaar_n', ((140, 1000),), 1024, -1)
    made += paving('pave_n', (140, 470, 1000, 900), spacing=168.0, along=1,
                   holes=DECK_VOIDS)
    # --- the two empty corners get the deck's own paving ----------------------
    made += paving('pave_se', (140, -1024, 1000, -480), spacing=256.0, along=0,
                   holes=DECK_VOIDS)
    print('japanDM: bazaar of %d pieces' % len(made))
    return made


# --- scene audit -------------------------------------------------------------
# Anything the level would swallow is a modelling mistake, not a compile error:
# q3map2 happily lights a crate that the tower front is standing on, and the
# player's only feedback is cover that is not there. These rules are pairs of
# axis-aligned boxes, which is every brush this file makes except the ramps and
# prisms `loose()` leaves out of BOXES.
SHELLS = ('facade_', 'sky_ring', 'sky_lid', 'clip_')
STANDING = ('prop_', 'crates_', 'container_', 'dock_crates', 'planter_', 'koi_', 'deck_counter_',
            'deck_planter_', 'kiosk', 'stall_', 'bench_', 'torii_lantern', 'cabinet_')
GLOW = ('_glow',)
# Linings, exempt from the two pair rules: a plinth is proud of its own wall by
# 16 on purpose, the two lids are the same box twice because that duplication is
# what makes a leak impossible, a glazing panel sits inside its frame, an
# emissive shell sits inside its housing and a flange is a collar round the duct
# it belongs to. In each pair the second brush is the first one's finish, not a
# rival object; the "no floor" and crossing rules still apply to every one of
# them.
# Names ending in these are things bolted onto a surface that already exists --
# a sign on a wall, an awning over a counter, a kerb along a rim.  They are exempt
# from the overlap audit on purpose: their whole job is to share space with their
# host, and an audit that flags them would be arguing about the mounting rather
# than about the thing being mounted.
TRIM = ('_plinth', '_lid', '_glass', '_glow', '_flange', '_noren1', '_noren2',
        '_bracket_flange', '_legs_flange', '_cap_flange',
        # A livery is the paint on its vehicle, a cap sits on its post, a kick plate
        # is the bottom of its balustrade and a strip is the light in its housing:
        # each one is *supposed* to share its host's volume, and the audit that
        # reports them is arguing about the mounting rather than the object.
        '_livery', '_post', '_kick', '_cap', '_strip')


def _volume(low, high):
    out = 1.0
    for axis in range(3):
        out *= max(high[axis] - low[axis], 1e-9)
    return out


def _shared(low, high, other_low, other_high):
    out = 1.0
    for axis in range(3):
        span = min(high[axis], other_high[axis]) - max(low[axis], other_low[axis])
        if span <= 0.5:
            return 0.0
        out *= span
    return out


def flight_band_audit():
    """-> every authored object standing inside a flight of steps.

    Structure is charged here and not silently moved, because a slab that reaches
    into a climb is a layout decision and not a stray prop: the market deck's own
    underside is what froze four of this level's seven climbs, and a build that
    quietly ate that brush would have taken the arcade down with it.
    """
    bad = []
    for name, low, high, kind in BOXES:
        if kind in ('stair', 'rail') or 'nodraw' in name:
            continue
        if climb_band_intrudes(low, high):
            bad.append('%s [%s] %s..%s' % (name, kind,
                                           tuple(round(v) for v in low),
                                           tuple(round(v) for v in high)))
    return bad


def verify():
    """-> every way this scene's dressing has stopped meaning what it says.

    * crossing the tower-front line, where the street is a wall -- a flight's
      foot and a wall-lining strip may touch that line, nothing may cross it;
    * 80 % or more inside another brush, which makes it invisible cover;
    * a quarter or more of the smaller of two props, which makes both of them
      neither one thing nor the other;
    * standing on nothing, or sunk into the slab it stands on.
    """
    boxes = [entry for entry in BOXES if entry[3] != 'loose']
    defects = []
    # A climb is this level's promise that a tier can be reached, and three separate
    # rounds of work each found that promise broken by a brush `verify` had never
    # looked at: an arcade lintel across the station stair, the market deck's own
    # underside at the height of a head, a condenser slid off its wall onto the
    # steps.  Charged first, because a build that compiles a staircase nobody can
    # walk up has not compiled a level.
    for entry in flight_band_audit():
        defects.append('stands in a flight of steps: %s' % entry)
    # The two *pair* rules are judgement calls about dressing; the crossing, "no
    # floor" and "sunk" rules below them are facts about the world.  While the
    # furniture is being moved about, a pair report must not be able to stop a
    # build -- the owner cannot look at a level that never compiled.
    nesting = []
    for name, low, high, kind in boxes:
        if kind not in ('prop', 'detail', 'stair') or name.startswith(SHELLS):
            continue
        for axis in (0, 1):
            if max(abs(low[axis]), abs(high[axis])) > FACE + 0.5:
                defects.append('%s crosses the tower-front line at %d' % (name, FACE))
                break
    for name, low, high, kind in boxes:
        if kind not in ('prop', 'detail', 'stair') or name.endswith(TRIM):
            continue
        volume = _volume(low, high)
        for other, other_low, other_high, _ in boxes:
            if other == name:
                continue
            shared = _shared(low, high, other_low, other_high)
            if shared >= 0.8 * volume:
                nesting.append('%s is %.0f%% inside %s' % (name, 100 * shared / volume, other))
                break
    for index, (name, low, high, kind) in enumerate(boxes):
        if kind not in ('prop', 'detail'):
            continue
        if name.startswith(SHELLS):
            continue        # the outer shell and its clips are boundaries, not dressing
        small = _volume(low, high)
        for other, other_low, other_high, other_kind in boxes[index + 1:]:
            if other == name or (other_kind, kind) == ('rail', 'rail') \
                    or name.endswith(TRIM) or other.endswith(TRIM):
                continue
            shared = _shared(low, high, other_low, other_high)
            if shared >= 0.25 * min(small, _volume(other_low, other_high)):
                nesting.append('%s and %s overlap by %.0f%% of the smaller'
                               % (name, other, 100 * shared / min(small, _volume(other_low,
                                                                                    other_high))))
                break
    for name, low, high, kind in boxes:
        if kind != 'prop' or not name.startswith(STANDING):
            continue
        centre = ((low[0] + high[0]) / 2.0, (low[1] + high[1]) / 2.0)
        tops, sunk = [], []
        for other, other_low, other_high, other_kind in boxes:
            if other == name or other_kind == 'rail':
                continue
            if not (other_low[0] <= centre[0] <= other_high[0]
                    and other_low[1] <= centre[1] <= other_high[1]):
                continue
            if other_high[2] <= low[2] + 2.0:
                tops.append(other_high[2])
            elif other_kind in ('slab', 'stair') and other_low[2] < low[2] - 2.0 \
                    < other_high[2] - 2.0:
                sunk.append(other)
        if not tops:
            defects.append('%s has no floor under it' % name)
        elif sunk:
            defects.append('%s is sunk into %s' % (name, sunk[0]))
    if os.environ.get('DK3_VERIFY_STRICT', '1') == '0':
        for note in nesting:
            print('japanDM: pair report (not enforced): %s' % note)
    else:
        defects.extend(nesting)
    defects.extend(PROP_PROBLEMS)
    for swallowed in PROP_SWALLOWS:
        defects.append('prop ' + swallowed)
    for clash in BODY_CLASHES:
        defects.append('scenery ' + clash)
    # The last sweep charges *structure* as well: a wall, a counter or a flight
    # authored over a start is a level the game cannot populate, and it is the one
    # class of defect a screenshot cannot show, because the player never exists to
    # take it.
    for name, low, high, kind in boxes:
        if kind not in ('prop', 'stair', 'slab', 'rail') or name.startswith(SHELLS):
            continue
        occupied = body_clear(low, high)
        if occupied is not None:
            defects.append('%s (%s) stands inside the hull of %s' % (name, kind, occupied))
    for slid in PROP_SHIFTS_LOG:
        print('japanDM: prop slid: %s' % slid)
    if PROP_KEPT:
        print('japanDM: %d props stand on a lane and stay: %s'
              % (len(PROP_KEPT), ', '.join(PROP_KEPT[:10])))
    if PROP_ROUTE_DROPS:
        print('japanDM: %d props had no clear place beside a route: %s'
              % (len(PROP_ROUTE_DROPS), ', '.join(PROP_ROUTE_DROPS[:12])))
    for moved in ROUTE_YIELDS:
        print('japanDM: scenery moved: %s' % moved)
    for slid in ITEM_SHIFTS:
        print('japanDM: item placed elsewhere: %s' % slid)
    for missing in ROUTE_DROPS:
        print('japanDM: scenery refused: %s had no clear place to stand' % missing)
    if ROUTE_KEPT:
        print('japanDM: %d pieces narrow a lane but stand: %s'
              % (len(ROUTE_KEPT), ', '.join(ROUTE_KEPT[:10])))
    return defects


#: The named walking lines: the two lanes of each of the four streets, the two lanes
#: of each deck arm that a stair pit does not stand in, the market's own way, the four
#: bridges, the roof arms, the spine and the two viaduct lanes.  Each is a line a
#: player would actually run, taken from the level's own geometry rather than from a
#: guess, and each is sampled with the 30 x 56 hull a body has.
WALK_LINES = (
    # --- T0: the four covered streets, one line either side of each colonnade
    ('t0_w_700', [(-700, -1000, T0), (-700, 1000, T0)]),
    ('t0_w_860', [(-860, 1000, T0), (-860, -1000, T0)]),
    ('t0_e_700', [(700, 1000, T0), (700, -1000, T0)]),
    ('t0_e_860', [(860, -1000, T0), (860, 1000, T0)]),
    ('t0_s_700', [(1000, -700, T0), (-1000, -700, T0)]),
    ('t0_s_860', [(-1000, -860, T0), (1000, -860, T0)]),
    ('t0_n_700', [(-1000, 700, T0), (1000, 700, T0)]),
    ('t0_n_860', [(1000, 860, T0), (-1000, 860, T0)]),
    # --- T1: the deck ring, inboard and outboard of each arm's colonnade
    # Each arm's inboard line stops at the alley that cuts the ring: those 192-unit
    # slots are gaps in the deck on purpose, and the only way across one is the
    # footbridge over it, which is why the south and north lines bend onto theirs.
    ('t1_w_520n', [(-520, 120, T1), (-520, 960, T1)]),
    ('t1_w_520s', [(-520, -120, T1), (-520, -960, T1)]),
    ('t1_w_900', [(-900, -960, T1), (-900, 960, T1)]),
    ('t1_e_520n', [(520, 120, T1), (520, 960, T1)]),
    ('t1_e_520s', [(520, -120, T1), (520, -960, T1)]),
    ('t1_e_880', [(880, 960, T1), (880, -960, T1)]),
    ('t1_s_aisle', [(-1000, -850, T1), (-170, -850, T1), (-170, -915, T1),
                    (170, -915, T1), (170, -850, T1), (1000, -850, T1)]),
    ('t1_n_520w', [(-120, 520, T1), (-1000, 520, T1)]),
    ('t1_n_520e', [(120, 520, T1), (1000, 520, T1)]),
    ('t1_n_850', [(-1000, 850, T1), (-170, 850, T1), (-170, 950, T1),
                  (170, 950, T1), (170, 850, T1), (1000, 850, T1)]),
    ('bridge_s', [(0, -1010, T1), (0, -890, T1)]),
    ('bridge_n', [(0, 890, T1), (0, 1010, T1)]),
    ('bridge_w', [(-1010, 0, T1), (-890, 0, T1)]),
    ('bridge_e', [(1010, 0, T1), (890, 0, T1)]),
    # --- T2: the three roof arms, the spine, and the ground at each end of it
    ('roof_w_400', [(-1000, -400, T2), (-460, -400, T2)]),
    ('roof_w_0', [(-1000, 0, T2), (-460, 0, T2)]),
    ('roof_w_250', [(-1000, 250, T2), (-460, 250, T2)]),
    ('roof_w_400n', [(-1000, 400, T2), (-460, 400, T2)]),
    ('roof_e_400', [(460, -400, T2), (1000, -400, T2)]),
    ('roof_e_0', [(460, 0, T2), (1000, 0, T2)]),
    ('roof_e_250', [(460, 250, T2), (1000, 250, T2)]),
    ('roof_e_400n', [(460, 400, T2), (1000, 400, T2)]),
    # y 460 is the one north-roof line that misses the two monorail stair flights,
    # whose feet stand at y 472; the roof between the flights and the deck edge is
    # where a player actually runs.
    ('roof_n_460', [(-740, 460, T2), (740, 460, T2)]),
    ('skybridge', [(-440, -192, T2), (440, -192, T2)]),
    # Each end of the spine has one apron before it reaches its roof trench, and one
    # line that runs past the trench on the roof side of it.  Both are routes: the
    # apron is where a boost run lands, and the walk is how it leaves.
    ('torii_apron', [(460, -192, T2), (600, -192, T2)]),
    ('torii_walk', [(460, -100, T2), (1000, -100, T2)]),
    ('garden_apron', [(-455, -192, T2), (-620, -192, T2)]),
    ('garden_walk', [(-455, -100, T2), (-1000, -100, T2)]),
    # --- the viaduct: two lanes, and the two crossings that join them
    ('via_s_lane', [(-1000, 760, VIA), (1000, 760, VIA)]),
    ('via_n_lane', [(1000, 880, VIA), (-1000, 880, VIA)]),
    ('via_cross_w', [(-600, 720, VIA), (-600, 912, VIA)]),
    ('via_cross_e', [(600, 912, VIA), (600, 720, VIA)]),
)

_GRID = {}
_GRID_EDGE = 128.0


def _walk_solids():
    """-> the scene's solids, bucketed into a 128 grid so a sweep is not O(boxes)."""
    _GRID.clear()
    solids = []
    for name, low, high, kind in BOXES:
        if kind in ('trigger', 'loose', 'hint') or name.startswith(WALK_SHELLS):
            continue
        index = len(solids)
        solids.append((name, low, high, kind))
        x = int(low[0] // _GRID_EDGE)
        while x <= int(high[0] // _GRID_EDGE):
            y = int(low[1] // _GRID_EDGE)
            while y <= int(high[1] // _GRID_EDGE):
                _GRID.setdefault((x, y), []).append(index)
                y += 1
            x += 1
    return solids


def _surface_at(solids, x, y, ref):
    """-> the height a body would be standing on at x,y, or None where there is none.

    The highest slab or tread top at or just under the reference height, raised by
    anything steppable on top of it: a 2-unit paving joint and a 7-unit deck lip are
    floor, not obstruction, and they are what the feet actually touch.
    """
    floor, near = None, ref - 40.0
    for index in _GRID.get((int(x // _GRID_EDGE), int(y // _GRID_EDGE)), ()):
        _name, low, high, kind = solids[index]
        if not (low[0] <= x <= high[0] and low[1] <= y <= high[1]):
            continue
        if kind in ('rail', 'detail'):
            continue
        if near <= high[2] <= ref + 12.0 and (floor is None or high[2] > floor):
            floor = high[2]
    if floor is None:
        return None
    for index in _GRID.get((int(x // _GRID_EDGE), int(y // _GRID_EDGE)), ()):
        _name, low, high, kind = solids[index]
        if not (low[0] - HULL_HALF < x + HULL_HALF and high[0] + HULL_HALF > x - HULL_HALF
                and low[1] - HULL_HALF < y + HULL_HALF and high[1] + HULL_HALF > y - HULL_HALF):
            continue
        if floor <= high[2] <= floor + STEP_UP and high[2] > floor:
            floor = high[2]
    return floor


def walk_route(label, points, skip=(), every=10.0, measure_floor=True, critical=False):
    """-> what stands in the way of one held-forward run, and where it first bites.

    `skip` names the brushes the route owns - a flight does not obstruct itself.
    Anything whose top is above a step-up and whose underside is below a standing
    body's head is a blocker: the engine steps 18 and a body is 56 tall, and the two
    numbers between them are the difference between a level you can run and one you
    have to look at.
    """
    solids = _GRID_SOLIDS
    hits, holes = {}, []
    for (x0, y0, z0), (x1, y1, z1) in zip(points, points[1:]):
        steps = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / every))
        for index in range(steps + 1):
            t = index / float(steps)
            x, y, ref = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, z0 + (z1 - z0) * t
            floor = _surface_at(solids, x, y, ref) if measure_floor else ref
            if measure_floor and floor is None:
                if not holes or holes[-1][0] != 'hole':
                    holes.append(('hole', round(x), round(y), round(ref)))
                continue
            feet = floor if floor is not None else ref
            for other in _GRID.get((int(x // _GRID_EDGE), int(y // _GRID_EDGE)), ()):
                name, low, high, kind = solids[other]
                if any(name.startswith(prefix) for prefix in skip):
                    continue
                if kind == 'rail' and not critical:
                    continue        # a balustrade beside a walkway is the level being polite
                if high[2] <= feet + STEP_UP or low[2] >= feet + BODY_TOP:
                    continue
                if not (low[0] < x + HULL_HALF and high[0] > x - HULL_HALF
                        and low[1] < y + HULL_HALF and high[1] > y - HULL_HALF):
                    continue
                record_hit = hits.setdefault(name, [None, None, 0, 0.0, kind])
                if record_hit[0] is None:
                    record_hit[0] = (round(x), round(y), round(feet))
                record_hit[1] = tuple(round(value) for value in low + high)
                record_hit[2] += 1
                depth = min(high[2], feet + BODY_TOP) - max(low[2], feet)
                record_hit[3] = max(record_hit[3], depth)
    return label, hits, holes, critical


_GRID_SOLIDS = []


def walk_audit():
    """-> (the routes a body cannot walk, and the report that explains them).

    A blocked *climb* is a defect: a tier you cannot reach is not a slightly worse
    tier, and every one of this level's route complaints has been a blocked climb.
    An obstruction on a named street line is reported and judged - a screen put on a
    lane on purpose is cover, and the line bends around it - but a *hole* in a line
    the level promises is a defect too, because a walking line that falls into a
    stairwell is how the bazaar street was severed for three sequences.
    """
    global _GRID_SOLIDS
    _GRID_SOLIDS = _walk_solids()
    lines = []
    lanes = {}
    for climb in CLIMBS_ALL:
        for label, points in climb_lines(climb):
            # A flight may not obstruct itself, and it has no floor to find while it
            # is being climbed: the surface under its own feet is the interpolation.
            lanes.setdefault(climb[0], []).append(label)
            lines.append((label, points, (climb[0],), 'run' not in label, True))
    for label, points in WALK_LINES:
        lines.append((label, points, (), True, False))
    report, defects = [], []
    blocked = {}
    for label, points, skip, floors, critical in lines:
        _name, hits, holes, _flag = walk_route(label, points, skip=skip, measure_floor=floors,
                                              critical=critical)
        if not hits and not holes:
            continue
        worst = sorted(hits.items(), key=lambda entry: -entry[1][3])[:4]
        # A graze of the last 8 units of a body's headroom by a cable or a kick plate
        # is not a blocked route; a 30-unit barrier is.
        hits = dict((name, found) for name, found in hits.items()
                    if not (found[4] == 'detail' and found[3] <= 8.0))
        if not hits and not holes:
            continue
        parts = ['%s[%s] depth %g at %s is %s' % (name, found[4], found[3], found[0],
                                                  found[1]) for name, found in worst]
        if holes:
            parts.insert(0, 'no floor at %s (%d samples)' % (holes[0][1:], len(holes)))
        detail = '; '.join(parts)
        report.append('%-22s %s%s' % (label, detail, '  [ROUTE]' if critical else ''))
        if critical:
            climb, _sep, lane = label.partition('/')
            blocked.setdefault(climb, set()).add(lane)
        if holes and not critical:
            defects.append('walk: %s does not walk (%s)' % (label, detail))
    # One clear lane up a flight is a flight. Zero is the defect, and so is a door
    # that will not open -- which is the distinction the level kept getting wrong in
    # both directions, deleting a stall to free an outer lane while a sign stayed in
    # front of a staircase's mouth.
    for climb, names in lanes.items():
        taken = blocked.get(climb, set())
        runs = [name for name in names if name.startswith(climb + '/run')]
        doors = [name for name in names if not name.startswith(climb + '/run')]
        free = [name for name in runs if name not in taken]
        if len(runs) and not free:
            defects.append('walk: %s has no clear lane left up it (%d of %d blocked)'
                           % (climb, len(taken), len(runs)))
        elif taken:
            print('japanDM: climb %s keeps %d of %d lanes (%s blocked)'
                  % (climb, len(free), len(runs), ', '.join(sorted(taken))))
        for door in doors:
            if door in taken:
                defects.append('walk: %s has a blocked door (%s)' % (climb, door))
    return defects, report


# `deck_market` runs before `arcade` so a pitch that would stand where a column
# goes is recorded first and pushes the column along its row, which is the order
# a builder would work in: fit out the street, then stand the structure that holds
# the floor over it.
# The kit goes on after the structure that carries it and before the props that
# have to stand clear of it: the fitout and the relief are laid once the fronts,
# the deck and the parapets exist, and the foot detail is laid last of the geometry
# because paint must not run across a bin or a stair -- the same reason
# `surface_marks` already runs after `prop_scatter`.
#    The landmarks stand between the structure and the furniture, not at the end.
#    A landmark is a *place*, so it is sited while only the loads exist: the deck
#    that carries it, the piers that hold the corridor, the rooftop plant it must
#    not stand through.  Everything laid after it -- the bazaar's pitches, the
#    colonnade, every prop -- already asks `_site_clear` and walks around what is
#    there, which is the way a street grows round a building.  Run any later than
#    this and the landmark spends its whole budget dodging market stalls, which is
#    how this level ended up with no landmark at all on two of its three tiers.
for section in (ground, deck, deck_parapets, climbs, bridges, roofs, skybridge, viaduct, facades,
                facade_parapets, facade_fitout, wall_relief, shell, dressing, landmarks,
                deck_market, lantern_strings, arcade, prop_scatter, surface_marks, foot_detail,
                hazard, lights, spawns, items):
    section()

problems = verify()
walk_problems, walk_report = walk_audit()
print('japanDM: walk audit found %d obstructed routes, %d of them failures'
      % (len(walk_report), len(walk_problems)))
for line in walk_report:
    print('japanDM: walk %s' % line)
if os.environ.get('DK3_WALK_STRICT', '1') == '0':
    print('japanDM: %d walk failures reported and not enforced (DK3_WALK_STRICT=0)'
          % len(walk_problems))
else:
    problems += walk_problems
manifest = os.environ.get('DK3_BOXES_JSON')
if manifest:
    import json
    with open(manifest, 'w') as handle:
        json.dump([{'name': name, 'low': list(low), 'high': list(high), 'kind': kind}
                   for name, low, high, kind in BOXES], handle)
if problems:
    for problem in problems:
        print('japanDM: %s' % problem)
    raise SystemExit('japanDM: the authored scene has %d placement defects' % len(problems))


path = map_blender.save(HERE / 'japanDM.blend')
print('japanDM: %d objects, %d lights, %d spawns, %d pickups -> %s'
      % (len(scene.objects), len(LIGHTS), len(SPAWNS), len(PICKUPS), path))
