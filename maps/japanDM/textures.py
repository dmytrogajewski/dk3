# SPDX-License-Identifier: GPL-2.0-or-later
"""Generation recipes for japanDM's images.

Two recipe sets live here because the map went through two image pipelines, and
the second one only exists as a correction of the first:

* ``CRAFT`` -- what ships.  Read by ``dkq3/tools/craft_textures.py``, which draws
  every material's structure itself and lets a diffusion model contribute grain
  only.  ``paint`` names the painter, ``grade`` is the albedo level the surface
  must land on, ``repeat`` is the world distance one tile spans, and the
  companion maps (normal, specular, glow, alpha) are derived from the same painted
  height field, so albedo and normal agree by construction.
* ``TEXTURES`` / ``SKY`` -- the superseded SDXL-tile recipes.  Kept because
  ``dkq3/tools/neural_textures.py`` still consumes them and the measured failure
  they produced is the argument for ``CRAFT`` (see DESIGN.md section 10 and
  PROVENANCE.md): the model would not obey a colour given as words, so eighteen
  structural surfaces came back within a factor of two of middle grey, and every
  request for structure -- a window grid, a grate, an LED strip -- came back as
  isotropic mush.

Both sets stay parseable so either pipeline can be re-run; only ``CRAFT`` and
``CRAFT_SKY`` describe the images that are installed with the map.

`repeat` is the number that decides whether a material reads at all, and it was
the second thing wrong with the first build: a face's extent was never compared
against the tile it was textured with.  The shipped set put `neon_a` on a repeat
of 256 world units while the median `neon_a` face measures 56 units across, so
every sign showed a 22 % crop of a kanji composition -- which is exactly the pink
confetti the arena read as.  Every `repeat` below is chosen against the measured
face survey of this map (see DESIGN.md section 5), not against what looked right
in a texture viewer.
in a texture viewer.

`repeat` is constrained from two directions, and the two disagree for flat
surfaces, which is how this table and `materials.py` came to drift apart in both
directions at once.  Feature scale wants a tile as large as the pattern it draws:
a kanji sign, a curtain-wall bay grid, a whole light-box poster must not be
cropped, which pushes `repeat` up.  Texel density wants it small: DESIGN.md
section 8 measured the capture at 1280 px across a 90-degree view, about 14
pixels per world unit, so a 1024-texel image over 256 units is 4 texels per unit
and every close surface is displayed several times larger than the art in it --
the stucco the first build showed in the lane, which is why asphalt, plaza stone,
concrete panel, roof gravel and lacquer were brought to 128.  Graphic surfaces
whose content is one large discrete feature (tower facade, signage, light box,
holo panel) take the feature-scale number; the fine-grit ground surfaces take the
density number.  Both numbers now live here, because `materials.py` defers to
this file rather than keeping a second copy of its own.
"""

import math

NEGATIVE = ('text, watermark, signature, logo lettering mistakes, photograph vignette, '
            'hard shadows, direct sunlight, specular highlight bloom, lens flare, '
            'depth of field, blur, jpeg artifacts, seam, border frame')

FLAT = ('seamless tileable texture, game asset albedo map, flat even ambient light, '
        'orthographic top-down view, no directional shading, no cast shadows, ')

TEXTURES = {
    # --- street level -------------------------------------------------------
    'asphalt': dict(
        prompt=FLAT + 'very dark wet rain asphalt road, low contrast charcoal albedo, '
                     'faint faded white road markings, large dark tire-wear bands and wide '
                     'oil sheen stains, a few long thin cracks, fine aggregate only in '
                     'close-up, no bright speckle, no mottled noise',
        control=dict(kind='grit', grit=0.45, veins=6, blur=2.4),
        size=1024, normal=1.0, spec=dict(base=0.10, gain=0.30, tint=(0.55, 0.60, 0.68), power=1.4),
        repeat=256),
    'plaza_stone': dict(
        prompt=FLAT + 'large grey granite paving slabs with narrow dark grout lines, '
                     'wet polished surface, subtle mineral speckle',
        control=dict(kind='slabs', cells=4, mortar=0.10, grit=0.35, blur=1.2),
        size=1024, normal=2.0, spec=dict(base=0.14, gain=0.26, tint=(0.6, 0.62, 0.66), power=1.3),
        repeat=256),
    'tower_front': dict(
        prompt=FLAT + 'dark modern high-rise facade panel with rows of dim lit windows, '
                     'black metal mullions, concrete bands, future tokyo building',
        control=dict(kind='slabs', cells=6, mortar=0.16, grit=0.30, blur=1.0),
        size=1024, normal=1.4, spec=dict(base=0.20, gain=0.35, tint=(0.5, 0.55, 0.7), power=1.6),
        glow=dict(threshold=0.62, gain=1.15), repeat=512),
    'concrete_panel': dict(
        prompt=FLAT + 'dark grey prefab concrete wall panel, low contrast matte albedo, '
                     'recessed seams, long soft rain streaks and wide dark grime gradients, '
                     'rust bleed from embedded bolts, a few formwork tie holes, soot in the '
                     'lower half, no bright speckle, no mottled noise',
        control=dict(kind='panels', cells=2, mortar=0.13, grit=0.28, bolts=0.35, blur=2.2),
        size=1024, normal=1.3, spec=dict(base=0.06, gain=0.22, tint=(0.5, 0.5, 0.5), power=1.2),
        repeat=256),
    # --- market deck --------------------------------------------------------
    'metal_deck': dict(
        prompt=FLAT + 'industrial steel floor plate with diamond anti-slip ribs, '
                     'worn metallic blue-grey paint, scratched edges, bolt heads',
        control=dict(kind='ribs', cells=8, grit=0.65, bolts=0.5, blur=0.8),
        size=512, normal=2.6, spec=dict(base=0.30, gain=0.30, tint=(0.62, 0.65, 0.70), power=1.8),
        repeat=128),
    'metal_column': dict(
        prompt=FLAT + 'brushed stainless steel panel with vertical grain, hairline '
                     'scratches, faint heat tint, rivet line along one edge',
        control=dict(kind='brushed', grit=0.35, blur=0.6),
        size=512, normal=1.2, spec=dict(base=0.42, gain=0.24, tint=(0.72, 0.74, 0.78), power=2.2),
        repeat=128),
    'grate': dict(
        prompt=FLAT + 'heavy steel bar grating grid seen from above, dark gaps between '
                     'bars, galvanized worn edges',
        control=dict(kind='grid', cells=6, mortar=0.30, grit=0.5, blur=0.7),
        size=512, normal=2.4, spec=dict(base=0.28, gain=0.24, tint=(0.6, 0.62, 0.66), power=1.8),
        repeat=128),
    'cloth': dict(
        prompt=FLAT + 'indigo and crimson striped market awning canvas, woven thread '
                     'visible, sun-faded seams, japanese noren fabric',
        control=dict(kind='weave', cells=48, grit=0.55, blur=0.5),
        size=512, normal=1.6, spec=dict(base=0.03, gain=0.10, tint=(0.35, 0.35, 0.38), power=1.0),
        repeat=128),
    'crate': dict(
        prompt=FLAT + 'weathered plywood shipping crate panel with stencil frame, '
                     'splintered edges, dark green lacquer bars',
        control=dict(kind='panels', cells=3, mortar=0.09, grit=0.45, bolts=0.2, blur=1.1),
        size=512, normal=1.8, spec=dict(base=0.05, gain=0.16, tint=(0.4, 0.36, 0.3), power=1.1),
        repeat=128),
    # --- roof ---------------------------------------------------------------
    'roof_gravel': dict(
        prompt=FLAT + 'flat rooftop ballast of coarse dark stones set in a dark '
                     'waterproofing membrane, low contrast charcoal and brown albedo, wide '
                     'dried rain stains and pooled dirt patches, stones clustered in bands '
                     'rather than sprinkled evenly, no bright speckle',
        control=dict(kind='grit', grit=0.55, veins=4, blur=2.0),
        size=512, normal=1.4, spec=dict(base=0.05, gain=0.18, tint=(0.45, 0.45, 0.48), power=1.2),
        repeat=192),
    'plant': dict(
        prompt=FLAT + 'dense trimmed green rooftop hedge foliage, small glossy leaves, '
                     'deep shadow between leaves',
        control=dict(kind='grit', grit=0.8, veins=30, blur=1.8),
        size=512, normal=2.4, spec=dict(base=0.04, gain=0.16, tint=(0.3, 0.4, 0.28), power=1.1),
        repeat=128),
    'lacquer_red': dict(
        prompt=FLAT + 'vermilion lacquered timber torii surface, glossy worn red varnish, '
                     'black iron fittings, subtle wood grain through paint',
        control=dict(kind='planks', cells=4, grit=0.35, blur=1.2),
        size=512, normal=1.3, spec=dict(base=0.34, gain=0.22, tint=(0.7, 0.42, 0.32), power=2.4),
        repeat=192),
    # --- light-carrying surfaces --------------------------------------------
    'neon_a': dict(
        prompt='glowing japanese neon sign kanji strokes on a black panel, magenta and '
               'cyan tubing, clean vector edges, emissive light box, no text errors',
        control=dict(kind='blocks', cells=5, grit=0.2, blur=2.2),
        size=512, normal=0.0, glow=dict(threshold=0.30, gain=1.6), repeat=256),
    'neon_b': dict(
        prompt='glowing japanese neon sign katakana strokes and arrow glyphs on a dark '
               'panel, amber and green tubing, emissive light box, high contrast',
        control=dict(kind='blocks', cells=4, grit=0.2, blur=2.4),
        size=512, normal=0.0, glow=dict(threshold=0.30, gain=1.6), repeat=256),
    'ad_board': dict(
        prompt='bright future tokyo billboard advertisement light box, abstract product '
               'graphic shapes, no readable lettering, cool white and orange light',
        control=dict(kind='blocks', cells=3, grit=0.15, blur=3.0),
        size=1024, normal=0.0, glow=dict(threshold=0.42, gain=1.25), repeat=512),
    'light_strip': dict(
        prompt='seamless emissive LED light strip, bright white core with cool blue '
               'edges, dark housing lines, uniform along one axis',
        control=dict(kind='ribs', cells=3, grit=0.15, bolts=0.0, blur=1.0),
        size=256, normal=0.0, glow=dict(threshold=0.35, gain=1.8), repeat=128),
    'holo_pool': dict(
        prompt='glowing cyan holographic data grid on a black pool floor, concentric '
               'wave ripples of light, faint scanlines, emissive floor',
        control=dict(kind='ripple', cells=6, grit=0.3, blur=2.0),
        size=512, normal=0.0, glow=dict(threshold=0.22, gain=1.7), repeat=512),
    'glass': dict(
        prompt=FLAT + 'dark tinted safety glass panel with faint rain streaks and a '
                     'subtle blue reflection gradient, near transparent',
        control=dict(kind='brushed', grit=0.12, blur=2.6),
        size=512, normal=0.6, spec=dict(base=0.55, gain=0.30, tint=(0.7, 0.8, 0.9), power=3.0),
        alpha=dict(base=64, variation=26), repeat=256),
}

# The sky is one 2:1 dusk panorama at 4096x2048: the model paints only the sky
# above the horizon, the city in front of it is drawn in layers so that its
# horizon lands exactly where the cube reprojection puts elevation zero, its
# 360-degree join tiles, and its window lights stay crisp at the 1:1 rate a 1024
# cube face samples it at. The cube faces are then supersampled at 2x.
SKY = dict(
    panorama=dict(
        prompt='dusk sky above a city, deep blue violet gradient with thin stretched '
               'cirrus clouds, no ground, no buildings, no horizon line, soft '
               'atmospheric gradient, cinematic, high dynamic range',
        negative='sun disc, stars, moon, watermark, text, buildings, ground, horizon, '
                 'clouds with hard edges, vignette, blur',
        generate=(1344, 768), work=(4096, 2048),
        steps=34, guidance=7.0, seed=4411,
    ),
    city=dict(
        horizon=0.5,
        haze=0.50, haze_tint=(0.30, 0.26, 0.42),
        ground=(0.020, 0.022, 0.036), ground_lights=0.00016,
        far_body=(0.105, 0.115, 0.180), near_body=(0.022, 0.024, 0.040),
        far_lights=(0.55, 0.57, 0.74), near_lights=(1.00, 0.84, 0.60),
        neon=((0.18, 0.92, 1.00), (1.00, 0.22, 0.72), (0.42, 1.00, 0.55)),
        bloom_sigma=6.0, bloom_gain=0.85,
        spires=9, spire_width=(0.024, 0.052), spire_height=(0.150, 0.245),
        stars=900, star_band=0.86,
        layers=(
            dict(width=(0.006, 0.018), height=(0.012, 0.038), sink=0.000,
                 window=(4, 4), lit=0.24, accent=0.010),
            dict(width=(0.012, 0.034), height=(0.022, 0.072), sink=0.010,
                 window=(7, 6), lit=0.19, accent=0.030),
            dict(width=(0.020, 0.058), height=(0.040, 0.125), sink=0.022,
                 window=(11, 9), lit=0.14, accent=0.050),
        ),
    ),
    size=1024,
    horizon=dict(band=0.055, blend=0.10),
)


# --------------------------------------------------------------------------- #
# what ships: the drawn materials
#
# One entry per material, keyed by the same name `materials.py` uses.  Keys:
#   paint    the painter in `dkq3/tools/craft_textures.py` (defaults to the name)
#   size     stored texel edge
#   grade    (mean, std) the albedo luminance is re-centred and spread onto
#   normal   normal-map strength, derived from the painter's own height field
#   spec     specular level, `base + gain * (1 - luminance) ** power`, tinted,
#            plus the painter's per-texel wetness/scratch weight via `extra_gain`
#   glow     additive `_g` stage: `gain`, optional `blur` sigma in texels
#   alpha    RGBA coverage for `trans` kinds: `base` and `variation` out of 255
#   repeat   world units one tile spans -- see the docstring, this is a design
#            number taken from the face survey, not a texture-resolution number
#   grain    how much of a diffusion plate's *relative* microstructure to
#            multiply in (0 = none, 1 = all); never touches the albedo level
#   plate_use 'content' for a light box, where the plate is the artwork itself
# --------------------------------------------------------------------------- #
CRAFT = {

    # --- street level -------------------------------------------------------
    # The street is 24 faces of ~896 units; at 256-unit tiles the aggregate is
    # ~4 texels per world unit, so grit survives a 72-unit-tall viewport.
    'asphalt': dict(
        paint='asphalt', size=1024, grade=(0.190,), normal=1.0, cracks=6,
        spec=dict(base=0.06, gain=0.32, tint=(0.52, 0.58, 0.68), power=1.35, extra_gain=0.34),
        repeat=128, grain=0.6),
    'plaza_stone': dict(
        paint='plaza_stone', size=1024, grade=(0.250,), normal=1.7, cells=4, mortar=0.075,
        spec=dict(base=0.12, gain=0.30, tint=(0.58, 0.61, 0.66), power=1.3, extra_gain=0.30),
        repeat=128, grain=0.75),
    # Median `tower_front` face is 544 units, p90 is 736: at a 512-unit tile the
    # grid is never cropped to a stub, a bay is 64 units (~2 m of glass) and a
    # floor 128 units (~4 m), which is the only facade pitch that reads as a
    # building rather than as wallpaper.  ~20 % of the windows are lit, and they
    # light themselves through `_g` rather than through the lightmap, so the
    # diffuse can stay at 0.10 and still show an occupied city.
    'tower_front': dict(
        paint='tower_front', size=1024, grade=(0.170,), normal=1.3,
        bays=8, floors=4, inset=0.13, lit_warm=0.22, lit_cool=0.10,
        spec=dict(base=0.16, gain=0.34, tint=(0.48, 0.54, 0.68), power=1.7, extra_gain=0.28),
        glow=dict(gain=1.45, blur=3.5), repeat=512),
    'concrete_panel': dict(
        paint='concrete_panel', size=1024, grade=(0.250,), normal=1.4, cells=3,
        storeys=4, mortar=0.045,
        spec=dict(base=0.05, gain=0.22, tint=(0.50, 0.51, 0.54), power=1.2, extra_gain=0.26),
        repeat=128, grain=0.65),
    # --- market deck --------------------------------------------------------
    # `repeat` is chosen by the size of the *motif*, not by texel density, and the
    # two are different constraints.  Density says a 1024-texel image may span
    # 128 units and still be sharper than the display; motif says a tile whose
    # composition contains one panel, two bolts and a seam must not span 128
    # units, because then a 1-metre window onto the deck shows a quarter of a
    # panel and the owner sees -- correctly -- an oversized metal texture.  Each
    # number below was read off a rendered 1-metre window at the capture's 14
    # display pixels per unit, which is the only test that answers the question.
    # Diamond plate: 14 cells over a 32-unit tile is a 2.3-unit (7 cm) emboss and
    # a plate joint every metre, which is what factory grating actually is.
    # Nine cells over a 32-unit tile is a 3.6-unit (11 cm) emboss -- finer than a
    # boot, coarser than the screen.  Fourteen was a 2.3-unit emboss, which is
    # above the display's Nyquist limit beyond about three metres and came back as
    # the scalloping in `deck_ring` and `up_e`: not an oversized texture, an
    # undersampled one.  The glint is halved over the same distance, because the
    # scallops were the tip specular smeared along a grazing view vector, and the
    # renderer this map ships into has no anisotropic filter to thank for it.
    'metal_deck': dict(
        paint='metal_deck', size=1024, grade=(0.250,), normal=0.70, cells=9, bolts=2,
        spec=dict(base=0.10, gain=0.10, tint=(0.58, 0.62, 0.68), power=1.8, extra_gain=0.10),
        repeat=32, grain=0.7),
    # Cladding: 1654 of 4876 faces authored, 5228 compiled -- the single most-seeded
    # surface in the map and the one the owner called out twice.  The history of this
    # tile is two failures in opposite directions.  At 128 units a handrail 12 units
    # thick showed an eighth of a tile and read as flat blue-grey plastic, so the
    # repeat went to 32 -- and 32 put 32 texels on every world unit of the largest lit
    # wall in the arena, where `paint_metal_column`'s above-Nyquist brush field (see
    # `e40_column_moire`) beat against the grazing view vector of the north service
    # ramp and arrived as fish-scale.  48 units at 512 texels is 10.7 texels per world
    # unit: a handrail still shows a third of a tile and keeps its rivet line, while
    # the finest thing the tile draws is a ~0.3-unit streak, which a player two metres
    # away can resolve and a player twenty metres away can only average.
    'metal_column': dict(
        paint='metal_column', size=512, grade=(0.300,), normal=0.55, rivets=5,
        spec=dict(base=0.24, gain=0.18, tint=(0.72, 0.75, 0.80), power=2.2, extra_gain=0.16),
        repeat=48),
    # Ten cells is a 4.8-unit bar pitch: a drain grating, and at that pitch the
    # perforation stops reading as a hole in the floor and starts reading as steel
    # with water under it.  (The stair treads no longer wear this at all -- see
    # `flight`.)
    'grate': dict(
        # 7 cells over 48 units is a 6.9-unit bar, and `normal 0.9` -- see
        # `e39_bump_scale`: the scallops on `up_n` were the bump field beating
        # against a grazing view vector, and a perforation drawn at 4.8 units under
        # a 1.7 bump is a moire generator wearing a tread plate.
        # 8 cells over 48 units is a 6-unit bar, and with e42's softened edge a
        # modulation depth of 0.0067 x 0.0104 -- asphalt's band, on the surface that
        # is 78 % of the north ramp's frame.  `normal 0.40`, because a drainage
        # pattern is not a relief to be read at night under a lamp.
        paint='grate', size=512, grade=(0.255,), normal=0.40, cells=8, radius=0.28,
        spec=dict(base=0.24, gain=0.26, tint=(0.60, 0.63, 0.68), power=1.8, extra_gain=0.34),
        # 8 cells over 24 units is a 3-unit (10 cm) bar pitch -- the size a
        # pedestrian drainage grating is actually cut at.  `frame_materials` found
        # this surface covering 78.5 % of the `up_n` frame with its nearest hit 49
        # units away, and at repeat 48 that is a 19 cm perforation drawn ~100 px
        # wide: fish scales, not tread plate.  Its modulation depth was already
        # 0.0069, inside asphalt's band, so the complaint was never aliasing --
        # e41 and e42 spent two rounds tuning the wrong axis.
        repeat=24, grain=0.7),
    'cloth': dict(
        paint='cloth', size=512, grade=(0.165,), normal=1.5, weave=64, panels=4,
        spec=dict(base=0.03, gain=0.10, tint=(0.36, 0.36, 0.40), power=1.0, extra_gain=0.14),
        # Six awning panels over 64 units is a 10-unit (35 cm) panel, which is the
        # width a noren is actually cut at; at 128 the same cloth read as one
        # unbroken sheet with a fold in it.
        repeat=64, grain=0.55),
    'crate': dict(
        paint='crate', size=512, grade=(0.245,), normal=1.7, bands=2,
        spec=dict(base=0.05, gain=0.17, tint=(0.42, 0.38, 0.32), power=1.15, extra_gain=0.22),
        # A shipping crate ply panel is a metre across, not three: at 96 the crate
        # at `spawn_station` (26 % of `lane_view_e`) read as a sheet of plywood
        # with a stencil on it rather than as a box a man can lift.
        repeat=32, grain=0.6),
    # --- roof ---------------------------------------------------------------
    # Ballast on a 602-unit p90 roof: 192-unit tiles keep the stone size legible
    # while letting the dried-rain staining run over several tiles.
    'roof_gravel': dict(
        paint='roof_gravel', size=512, grade=(0.225,), normal=1.5, count=1500,
        spec=dict(base=0.05, gain=0.18, tint=(0.45, 0.46, 0.50), power=1.2, extra_gain=0.24),
        # Ballast is 2-4 cm of chipped stone, and `count=1500` stones in a tile is
        # only legible if a tile is about the size of a rooftop bay: at 128 units a
        # stone is a fist and the whole roof reads as a scree slope, which is what
        # the owner saw on every soffit and ceiling in the arena.  48 units is a
        # 1.5 m bay of coarse chippings -- and the roof plates' own sides, which
        # wear the same ballast, stop reading as walls of boulders.
        repeat=48, grain=0.7),
    'plant': dict(
        paint='plant', size=512, grade=(0.185,), normal=1.8,
        spec=dict(base=0.04, gain=0.16, tint=(0.30, 0.42, 0.28), power=1.1, extra_gain=0.18),
        repeat=96, grain=0.7),
    'lacquer_red': dict(
        paint='lacquer_red', size=512, grade=(0.200,), normal=1.2,
        spec=dict(base=0.32, gain=0.24, tint=(0.70, 0.42, 0.32), power=2.4, extra_gain=0.26),
        repeat=128),
    # 480 faces of curtain wall.  The first build shipped an opaque light-blue
    # woven fabric here; tinted safety glass is dark, hard and only slightly
    # reflective, and the `trans` kind means coverage comes from the alpha stage.
    'glass': dict(
        paint='glass', size=512, grade=(0.090,), normal=0.4, streaks=26,
        spec=dict(base=0.55, gain=0.30, tint=(0.70, 0.80, 0.90), power=3.0, extra_gain=0.20),
        alpha=dict(base=70, variation=18), repeat=256, grain=0.55),
    # --- market furniture: the materials props wear -------------------------
    # Every prop in this arena arrived as a generated mesh whose own baked colour
    # is a *lit product shot* (mean display 0.3-0.6), while japanDM's structural
    # albedos are night albedos (0.15-0.26).  Chroma-matching one onto the other
    # therefore dressed a red vending machine in asphalt and a wooden cart in
    # concrete: 5228 of the compiled faces came out `metal_column`, and the owner's
    # verdict was "I don't see any of those objects on the map".  These materials are
    # the answer -- the same painters painted up to the brightness a lit object
    # actually shows, and tiled to the size of the *object* rather than the size of a
    # wall: a 96-unit cart wearing a 128-unit tile shows a third of a plank, which is
    # the difference between a prop and a grey lump.
    'prop_steel': dict(
        paint='metal_column', size=512, grade=(0.46,), normal=0.8, rivets=4,
        colorize=(0.80, 0.84, 0.92),
        spec=dict(base=0.34, gain=0.26, tint=(0.74, 0.77, 0.82), power=2.2, extra_gain=0.30),
        # A condenser housing is 64-96 units across; at a 16-unit tile its panel
        # seams and rivet line land where a player two metres away can resolve them.
        repeat=16, grain=0.55),
    'prop_rubber': dict(
        paint='asphalt', size=512, grade=(0.20,), normal=0.9, cracks=2,
        colorize=(0.42, 0.43, 0.47),
        spec=dict(base=0.05, gain=0.10, tint=(0.40, 0.42, 0.46), power=1.2, extra_gain=0.12),
        repeat=16, grain=0.5),
    'prop_wood': dict(
        paint='crate', size=512, grade=(0.38,), normal=1.6, bands=1,
        colorize=(0.94, 0.72, 0.46),
        spec=dict(base=0.06, gain=0.16, tint=(0.46, 0.40, 0.33), power=1.15, extra_gain=0.20),
        repeat=32, grain=0.6),
    'prop_canvas': dict(
        paint='cloth', size=512, grade=(0.40,), normal=1.4, weave=64, panels=4,
        colorize=(0.98, 0.84, 0.58),
        spec=dict(base=0.03, gain=0.10, tint=(0.40, 0.38, 0.34), power=1.0, extra_gain=0.14),
        repeat=24, grain=0.5),
    'prop_paint_red': dict(
        paint='lacquer_red', size=512, grade=(0.44,), normal=1.1,
        colorize=(1.00, 0.40, 0.30),
        spec=dict(base=0.34, gain=0.24, tint=(0.72, 0.44, 0.34), power=2.4, extra_gain=0.26),
        repeat=32),
    'prop_paint_cyan': dict(
        paint='lacquer_red', size=512, grade=(0.42,), normal=1.1,
        colorize=(0.34, 0.86, 0.98),
        spec=dict(base=0.34, gain=0.24, tint=(0.44, 0.66, 0.74), power=2.4, extra_gain=0.26),
        repeat=32),
    'prop_concrete': dict(
        paint='concrete_panel', size=512, grade=(0.44,), normal=1.2, cells=1, mortar=0.05,
        colorize=(0.96, 0.94, 0.90),
        spec=dict(base=0.05, gain=0.18, tint=(0.52, 0.52, 0.55), power=1.2, extra_gain=0.20),
        repeat=48, grain=0.6),
    # A hedge at night is dark, and it is dark because the alternative is the green
    # confetti `spawn_garden` and `roof_level` were showing: leaves colourised at
    # full green and graded to a luminance the wet brickwork does not even reach.
    'foliage': dict(
        paint='plant', size=512, grade=(0.215,), normal=1.8,
        colorize=(0.38, 0.80, 0.42),
        spec=dict(base=0.04, gain=0.16, tint=(0.32, 0.44, 0.30), power=1.1, extra_gain=0.18),
        # The painter composes leaves for a 96-unit tile.  Tiled at 24 it put four
        # times the leaf density in the same window, which is where the green static
        # in `spawn_garden` came from; 56 is a leaf clump of about 5 units (16 cm),
        # which is the size a privet hedge is actually made of.
        repeat=56, grain=0.6),
    # --- light-carrying surfaces --------------------------------------------
    # These are `nolightmap`: the diffuse stage IS what the player sees, so there
    # is no `grade` to land on -- the composition decides its own contrast, and
    # the `_g` stage is the bloom on top of it.  `repeat` is set so the median
    # face shows the whole sign rather than a crop of it.
    'neon_a': dict(
        paint='neon', size=512, glyphs=('ka', 'shi', 'ma'), tube=0.80, inset=0.11,
        colours=((0.74, 0.26, 0.50), (0.26, 0.60, 0.74), (0.74, 0.30, 0.52)),
        glow=dict(gain=1.15, blur=2.6), repeat=72),
    'neon_b': dict(
        paint='neon', size=512, glyphs=('to', 'ku'), tube=0.80, inset=0.11,
        colours=((0.86, 0.58, 0.24), (0.36, 0.72, 0.46)),
        glow=dict(gain=1.15, blur=2.6), repeat=84),
    # A light box's albedo is artwork, so this one takes the rendered plate
    # outright instead of borrowing its grain (see qwen_studio.py).  Unmirrored:
    # a billboard that tiles as a mirror image of itself reads as a defect.
    'ad_board': dict(
        paint='ad_board', size=1024, panels=2, plate_use='content',
        glow=dict(gain=1.05, blur=2.0), repeat=192),
    # A strip only has to survive being cropped along its length, which one
    # continuous band does and a grid of blobs does not.
    'light_strip': dict(
        paint='light_strip', size=256, glow=dict(gain=1.75), repeat=128),
    'holo_pool': dict(
        paint='holo_pool', size=1024, cycles=6, glow=dict(gain=0.62, blur=1.6), repeat=96),
    # A vending machine is the one prop in a night market that is *itself* a lamp.
    # Its front is a lit product panel, so it wears the neon painter's glyphs at a
    # tile small enough to survive a 64-unit face, and it emits: `q3map_surfacelight
    # 130` puts a small coloured pool on the pavement in front of it, which is what
    # makes a machine findable from the end of a dark lane.
    'vend_face': dict(
        paint='vend_face', size=512, columns=4, rows=5, sold_out=0.14,
        brand=(0.34, 0.06, 0.07),
        glow=dict(gain=1.30, blur=2.2), repeat=72),
}

# The dusk sky, as the keys `craft_textures.dusk_panorama` actually reads.  The
# first build shipped a flat violet void whose `up` face was a magenta smudge and
# whose `dn` face was a radial pinwheel, and because `q3map_skyLight` integrates
# these six faces into the arena's ambient, that violet WAS every surface's base
# colour.  Both poles are therefore forced azimuthally uniform here, and the
# horizon is authored in elevation degrees -- the coordinate the cube
# reprojection samples -- rather than in panorama pixels.
CRAFT_SKY = dict(
    # Measured, not styled: the first shipped sky had a panorama mean luminance of
    # 0.012, which is a black sheet with a few dots on it. Two things followed. The
    # visible sky from any open deck was a starfield with no city on the horizon, so
    # the arena read as a rooftop in space rather than a street in a city; and
    # q3map_skyLight integrates these faces into the arena's ambient, so the map's
    # only fill light was a black fill and every surface a capped lamp missed came
    # out of -light as pure black (four spawn frames measured 0.03-0.06 mean). The
    # stops below are the same four elevations, authored as the DISPLAY values a dusk
    # city actually shows: a deep indigo zenith, a violet mid, and a wide sodium band
    # at the horizon where the street lighting of a city piles up. --sky prints the
    # cos-weighted mean it integrates to, and q3map_skyLight was retuned against that
    # number so the fill light did not jump when the sky stopped being black.
    size=1024, panorama=(4096, 2048), save_panorama=True, seed=4411,
    zenith=(0.034, 0.046, 0.104),
    mid=(0.078, 0.090, 0.176),
    upper_horizon=(0.200, 0.156, 0.236),
    horizon=(0.420, 0.280, 0.216),
    ground_near=(0.052, 0.044, 0.058),
    nadir=(0.020, 0.020, 0.030),
    glow=((math.radians(-40.0), 0.400, (0.86, 0.26, 0.62)),
          (math.radians(95.0), 0.300, (0.30, 0.72, 0.92)),
          (math.radians(168.0), 0.380, (0.95, 0.60, 0.28))),
    glow_width=(15.0, 18.0, 22.0),
    glow_spread=(38.0, 52.0, 60.0),
    # Clouds are what makes a night sky look inhabited: they catch the street
    # lighting from below. Doubled in coverage and lifted in tint, because at the old
    # values the cloud field was invisible against a black sky.
    clouds=0.55, cloud_tint=(1.70, 1.38, 1.16),
    stars=700, star_gain=0.42,
    city=dict(
        haze=0.55, haze_band=7.0, haze_tint=(0.30, 0.24, 0.34),
        ground=(0.014, 0.015, 0.024),
        layers=(
            dict(count=260, width=(0.004, 0.014), height=(0.010, 0.040),
                 body=(0.120, 0.128, 0.196), windows=4, floors=10, lit=0.30,
                 warm_share=0.75, warm=(0.95, 0.75, 0.45), cool=(0.40, 0.75, 0.92)),
            dict(count=150, width=(0.010, 0.030), height=(0.030, 0.085),
                 body=(0.058, 0.062, 0.104), windows=7, floors=14, lit=0.26,
                 warm_share=0.70, warm=(0.98, 0.78, 0.48), cool=(0.42, 0.80, 0.95)),
            dict(count=70, width=(0.018, 0.055), height=(0.055, 0.150),
                 body=(0.026, 0.028, 0.048), windows=10, floors=18, lit=0.20,
                 warm_share=0.60, warm=(1.00, 0.80, 0.50), cool=(0.35, 0.85, 1.00)),
        ),
    ),
)


LICENCES = dict(
    generator='Stable Diffusion XL base 1.0 (CreativeML Open RAIL++-M) and '
              'xinsir controlnet-tile-sdxl-1.0 (same licence), both loaded from '
              '~/dk_models; madebyollin sdxl-vae-fp16-fix (MIT) for decoding',
    avoided='FLUX.1-dev is licensed for research/non-commercial use only, so it is '
            'not used for anything shipped with this map',
    generator_2='ComfyUI 0.38 + ComfyUI-GGUF driving abenzerps/Qwen-Image-2.1-Uncensored-GGUF '
               '(Q8_0 single-file diffusion model, Qwen3-VL-8B int8 text encoder, bf16 VAE), '
               'sampled euler/simple at cfg 1 -- the uncensored variant is the owner\'s personal '
               'copy, used for personal work on the owner\'s instruction; the base model is '
               'Apache-2.0, and no weight is shipped with the map',
    role_2='renders detail plates and the ad-board artwork only; every albedo LEVEL is still '
           'set by craft_textures.grade(), and structural materials take only the plate\'s '
           'relative microstructure',
    derivation='structure drawn per material by craft_textures.py; height/normal from the '
               'painted periodic height field; specular from albedo luminance plus the '
               'painter\'s per-texel weight; glow from the painter\'s own light image; sky '
               'cube faces reprojected from an elevation-authored panorama',
    machine='RTX 5090, python3.14, numpy 1.26 / scipy / PIL 11.3; ComfyUI 0.38 venv',
)
