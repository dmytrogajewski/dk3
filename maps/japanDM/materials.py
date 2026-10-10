
# SPDX-License-Identifier: GPL-2.0-or-later
"""japanDM's material table: 18 generated surfaces plus the three tool ones.

Keys are shader paths under `textures/`, so a key is also where its images live:
`japandm/asphalt` compiles to `textures/japandm/asphalt` and reads
`textures/japandm/asphalt{,_n,_s}.tga`. `texwidth` is the pixel size the image
was actually generated at, which is what makes `repeat` a statement in world
units rather than an accident of image resolution (see dkq3/tools/map_materials.py).

`kind` chooses the stage layout:
  * `lit`          lightmapped; renderergl2 finds `_n`/`_s` by name on its own;
  * `emissive_full` identity diffuse + additive `_g`, and `nolightmap` so the
                    surface ignores baked light entirely -- neon stays neon in a
                    shadowed street without spending a light entity on it;
  * `lit` + glow   lightmapped with an additive `_g` stage on top: lit windows in
                    a facade that still takes the street's light pools;
  * `trans`        RGBA alpha diffuse, then the lightmap multiplied over it.
"""

# Generated image sizes, repeated here on purpose: the shader must declare the
# size q3map2 measures and the exporter must divide `repeat` by the same number.
_SIZES = dict(asphalt=1024, plaza_stone=1024, tower_front=1024, concrete_panel=1024,
              metal_deck=512, metal_column=512, grate=512, cloth=512, crate=512,
              roof_gravel=512, plant=512, lacquer_red=512, neon_a=512, neon_b=512,
              ad_board=1024, light_strip=256, holo_pool=512, glass=512,
              prop_steel=512, prop_rubber=512, prop_wood=512, prop_canvas=512,
              prop_paint_red=512, prop_paint_cyan=512, prop_concrete=512, foliage=512,
              vend_face=512)

_SIZES.update(dict(                                     # the street kit, see textures.py
    plaster_warm=512, stucco_pale=512, plaster_slate=512, tile_cream=512, tile_dark=512,
    tile_sage=512, brick_deep=512, slat_timber=512, slat_dark=512, shutter_steel=512,
    shutter_green=512, corrugated_rust=512, panel_blue=512, concrete_rough=1024,
    kerb_granite=512, tactile_yellow=512, paving_court=512, paving_lane=512,
    paint_line_white=512, paint_line_yellow=512, asphalt_wet=1024, grate_drain=512,
    sign_band_a=512, sign_band_b=512, sign_menu=512, sign_vertical=512,
    sign_vertical_b=512, wayfinding_blue=512, banner_red=512, banner_white=512,
    noren_strip=512, poster_wall=512, ad_board_b=1024, vend_face_b=512, vend_face_c=512,
    neon_c=512, light_strip_warm=256, light_strip_cyan=256, roof_membrane=1024,
    deck_timber=512, prop_paint_yellow=512, prop_paint_green=512, metal_brass=512))

SKY = dict(
    kind='sky', shader='japandm/sky', skybox='env/japandm', cloudheight=512,
    diffuse=False,
    # `q3map_skyLight` is a SHADER epair in q3map2 2.5.17, not a worldspawn key:
    # it sits in the compiler's shader-keyword table between `q3map_bounceScale`
    # and `q3map_surfacelight` (verified with `strings` on the binary).  Written on
    # worldspawn it is read by nobody and `-light` reports `0 sun/sky lights`; on
    # the sky surface it turns japanDM's sky ring into an area light.  That is the
    # difference between an open plaza that reads as night and one that reads as
    # dusk: without it the only light in the map is 53 capped lamps, every surface
    # they miss comes out of `-light` as pure black (measured mean luminance 0.035
    # on the north roof), and the engine cannot tell a dark map from an unlit one.
    # Intensity is in the compiler's light units, samples are per luxel; the pair
    # is tuned against measured frames, not guessed (see DESIGN.md).
    # 400, not 260.  Twenty measured frames from the installed build put the mean
    # luminance of the four covered streets between 0.06 and 0.15 -- a night street
    # you can read, but the market, the stalls and the goods the arena is *about*
    # disappeared into it, and six of the twenty captures came back near black.
    # The sky ring is the only broad light source the map has; the lamps are capped.
    q3map=['q3map_skyLight 560 10'],
)

MATERIALS = {
    # --- street level -------------------------------------------------------
    'japandm/asphalt': dict(
        kind='lit', shader='japandm/asphalt', repeat=128, texwidth=_SIZES['asphalt'],
        normal=True, specular=True),
    'japandm/plaza_stone': dict(
        kind='lit', shader='japandm/plaza_stone', repeat=128, texwidth=_SIZES['plaza_stone'],
        normal=True, specular=True),
    'japandm/tower_front': dict(      # dim windows carry their own light
        kind='lit', shader='japandm/tower_front', repeat=512, texwidth=_SIZES['tower_front'],
        normal=True, specular=True, glow=True),
    'japandm/concrete_panel': dict(
        kind='lit', shader='japandm/concrete_panel', repeat=128, texwidth=_SIZES['concrete_panel'],
        normal=True, specular=True),
    # --- market deck --------------------------------------------------------
    'japandm/metal_deck': dict(
        kind='lit', shader='japandm/metal_deck', repeat=128, texwidth=_SIZES['metal_deck'],
        normal=True, specular=True, surfaceparm=('metalsteps',)),
    'japandm/metal_column': dict(
        kind='lit', shader='japandm/metal_column', repeat=128, texwidth=_SIZES['metal_column'],
        normal=True, specular=True, surfaceparm=('metalsteps',)),
    'japandm/grate': dict(
        kind='lit', shader='japandm/grate', repeat=128, texwidth=_SIZES['grate'],
        normal=True, specular=True, surfaceparm=('metalsteps',)),
    'japandm/cloth': dict(
        kind='lit', shader='japandm/cloth', repeat=128, texwidth=_SIZES['cloth'],
        normal=True, specular=True),
    'japandm/crate': dict(
        kind='lit', shader='japandm/crate', repeat=128, texwidth=_SIZES['crate'],
        normal=True, specular=True),
    # --- roof ---------------------------------------------------------------
    'japandm/roof_gravel': dict(
        kind='lit', shader='japandm/roof_gravel', repeat=128, texwidth=_SIZES['roof_gravel'],
        normal=True, specular=True),
    'japandm/plant': dict(
        kind='lit', shader='japandm/plant', repeat=128, texwidth=_SIZES['plant'],
        normal=True, specular=True),
    'japandm/lacquer_red': dict(
        kind='lit', shader='japandm/lacquer_red', repeat=128, texwidth=_SIZES['lacquer_red'],
        normal=True, specular=True),
    # --- light-carrying surfaces: no lightmap, identity diffuse, additive glow,
    # AND the map's whole light rig -------------------------------------------
    # These surfaces are not decals, they are the lamps.  `q3map_surfacelight` is
    # a shader epair, so a `nolightmap` surface still emits: q3map2 takes the
    # colour from the face's own texture and subdivides the face by
    # `q3map_lightsubdivide`.  A signage-lit street needs exactly that -- the
    # light pools then come from the same rectangles the player sees glowing, in
    # the same hues, instead of from 53 invisible lamps that agree with nothing on
    # screen.  Intensity is per kind, tuned against measured frames
    # (maps/japanDM/DESIGN.md); subdivision is what keeps the light count, and so
    # the running time of `-light`, under control.
    'japandm/neon_a': dict(
        kind='emissive_full', shader='japandm/neon_a', repeat=256, texwidth=_SIZES['neon_a'],
        glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 205', 'q3map_lightsubdivide 128']),
    'japandm/neon_b': dict(
        kind='emissive_full', shader='japandm/neon_b', repeat=256, texwidth=_SIZES['neon_b'],
        glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 205', 'q3map_lightsubdivide 128']),
    'japandm/ad_board': dict(
        kind='emissive_full', shader='japandm/ad_board', repeat=512, texwidth=_SIZES['ad_board'],
        glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 330', 'q3map_lightsubdivide 256']),
    'japandm/light_strip': dict(
        kind='emissive_full', shader='japandm/light_strip', repeat=128, texwidth=_SIZES['light_strip'],
        glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 150', 'q3map_lightsubdivide 64']),
    'japandm/vend_face': dict(
        kind='emissive_full', shader='japandm/vend_face', repeat=256,
        texwidth=_SIZES['vend_face'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 130', 'q3map_lightsubdivide 64']),
    'japandm/holo_pool': dict(
        kind='emissive_full', shader='japandm/holo_pool', repeat=512, texwidth=_SIZES['holo_pool'],
        glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 150', 'q3map_lightsubdivide 256']),
    # --- market furniture ----------------------------------------------------
    # Props are small, close, and the only things in the arena a player reads at
    # arm's length, so they get their own materials rather than borrowing the
    # street's: see the note in `textures.py`.  The repeats are the objects' own
    # dimensions, not the tile's resolution.
    'japandm/prop_steel': dict(
        kind='lit', shader='japandm/prop_steel', repeat=16, texwidth=_SIZES['prop_steel'],
        normal=True, specular=True, surfaceparm=('metalsteps',)),
    'japandm/prop_rubber': dict(
        kind='lit', shader='japandm/prop_rubber', repeat=16, texwidth=_SIZES['prop_rubber'],
        normal=True, specular=True),
    'japandm/prop_wood': dict(
        kind='lit', shader='japandm/prop_wood', repeat=32, texwidth=_SIZES['prop_wood'],
        normal=True, specular=True),
    'japandm/prop_canvas': dict(
        kind='lit', shader='japandm/prop_canvas', repeat=24, texwidth=_SIZES['prop_canvas'],
        normal=True, specular=True),
    'japandm/prop_paint_red': dict(
        kind='lit', shader='japandm/prop_paint_red', repeat=32, texwidth=_SIZES['prop_paint_red'],
        normal=True, specular=True),
    'japandm/prop_paint_cyan': dict(
        kind='lit', shader='japandm/prop_paint_cyan', repeat=32,
        texwidth=_SIZES['prop_paint_cyan'], normal=True, specular=True),
    'japandm/prop_concrete': dict(
        kind='lit', shader='japandm/prop_concrete', repeat=48, texwidth=_SIZES['prop_concrete'],
        normal=True, specular=True),
    'japandm/foliage': dict(
        kind='lit', shader='japandm/foliage', repeat=24, texwidth=_SIZES['foliage'],
        normal=True, specular=True),
    'japandm/glass': dict(
        kind='trans', shader='japandm/glass', repeat=256, texwidth=_SIZES['glass'],
        normal=True, specular=True, transparency=0.22),
    # --- the kit walls ------------------------------------------------------
    # Fourteen surfaces for the parts a facade is actually built from, because a
    # `metal_column` handrail, a `concrete_panel` spandrel and a shopfront's tile
    # are three different pitches and the arena used to give them one.  All of
    # these are `lit`: they are masonry and board, and they must take the street's
    # light pools or a lane with a lamp in it will read as a lane with nothing in
    # it.  `kind='lit'` + `glow` is only used where the surface genuinely carries
    # its own light (see the signage block below).
    'japandm/plaster_warm': dict(
        kind='lit', shader='japandm/plaster_warm', repeat=128,
        texwidth=_SIZES['plaster_warm'], normal=True, specular=True),
    'japandm/stucco_pale': dict(
        kind='lit', shader='japandm/stucco_pale', repeat=128,
        texwidth=_SIZES['stucco_pale'], normal=True, specular=True),
    'japandm/plaster_slate': dict(
        kind='lit', shader='japandm/plaster_slate', repeat=128,
        texwidth=_SIZES['plaster_slate'], normal=True, specular=True),
    'japandm/tile_cream': dict(
        kind='lit', shader='japandm/tile_cream', repeat=96,
        texwidth=_SIZES['tile_cream'], normal=True, specular=True),
    'japandm/tile_dark': dict(
        kind='lit', shader='japandm/tile_dark', repeat=128,
        texwidth=_SIZES['tile_dark'], normal=True, specular=True),
    'japandm/tile_sage': dict(
        kind='lit', shader='japandm/tile_sage', repeat=96,
        texwidth=_SIZES['tile_sage'], normal=True, specular=True),
    'japandm/brick_deep': dict(
        kind='lit', shader='japandm/brick_deep', repeat=128,
        texwidth=_SIZES['brick_deep'], normal=True, specular=True),
    'japandm/slat_timber': dict(
        kind='lit', shader='japandm/slat_timber', repeat=128,
        texwidth=_SIZES['slat_timber'], normal=True, specular=True),
    'japandm/slat_dark': dict(
        kind='lit', shader='japandm/slat_dark', repeat=128,
        texwidth=_SIZES['slat_dark'], normal=True, specular=True),
    'japandm/shutter_steel': dict(
        kind='lit', shader='japandm/shutter_steel', repeat=128,
        texwidth=_SIZES['shutter_steel'], normal=True, specular=True),
    'japandm/shutter_green': dict(
        kind='lit', shader='japandm/shutter_green', repeat=128,
        texwidth=_SIZES['shutter_green'], normal=True, specular=True),
    'japandm/corrugated_rust': dict(
        kind='lit', shader='japandm/corrugated_rust', repeat=96,
        texwidth=_SIZES['corrugated_rust'], normal=True, specular=True),
    'japandm/panel_blue': dict(
        kind='lit', shader='japandm/panel_blue', repeat=96,
        texwidth=_SIZES['panel_blue'], normal=True, specular=True),
    'japandm/concrete_rough': dict(
        kind='lit', shader='japandm/concrete_rough', repeat=192,
        texwidth=_SIZES['concrete_rough'], normal=True, specular=True),
    # --- foot-level ground --------------------------------------------------
    # Everything here is laid 2 units proud of the surface it decorates, so none
    # of it is a step; the walk audit does not care, and neither does a boot.
    'japandm/kerb_granite': dict(
        kind='lit', shader='japandm/kerb_granite', repeat=64,
        texwidth=_SIZES['kerb_granite'], normal=True, specular=True),
    'japandm/tactile_yellow': dict(
        kind='lit', shader='japandm/tactile_yellow', repeat=96,
        texwidth=_SIZES['tactile_yellow'], normal=True, specular=True),
    'japandm/paving_court': dict(
        kind='lit', shader='japandm/paving_court', repeat=128,
        texwidth=_SIZES['paving_court'], normal=True, specular=True),
    'japandm/paving_lane': dict(
        kind='lit', shader='japandm/paving_lane', repeat=128,
        texwidth=_SIZES['paving_lane'], normal=True, specular=True),
    'japandm/paint_line_white': dict(
        kind='lit', shader='japandm/paint_line_white', repeat=96,
        texwidth=_SIZES['paint_line_white'], normal=True, specular=True),
    'japandm/paint_line_yellow': dict(
        kind='lit', shader='japandm/paint_line_yellow', repeat=96,
        texwidth=_SIZES['paint_line_yellow'], normal=True, specular=True),
    # The wet tarmac is the map's mirror: `extra_gain 0.9` on a specular stage that
    # already reads the painter's own rain film is what returns a sign to the
    # street it stands over, which no light entity can do.
    'japandm/asphalt_wet': dict(
        kind='lit', shader='japandm/asphalt_wet', repeat=128,
        texwidth=_SIZES['asphalt_wet'], normal=True, specular=True),
    'japandm/grate_drain': dict(
        kind='lit', shader='japandm/grate_drain', repeat=64,
        texwidth=_SIZES['grate_drain'], normal=True, specular=True,
        surfaceparm=('metalsteps',)),
    # --- signage ------------------------------------------------------------
    # `emissive_full`, so the plate is its own light and the street's darkness is
    # not asked to reveal it.  Each carries a small `q3map_surfacelight`: this is
    # how a night market's street is lit at all -- by its own shopfronts -- and
    # WP4's district lighting is built on these rather than on bare points.  The
    # values are deliberately a fraction of `ad_board`'s 330: a lane lined with
    # twelve 300-unit sign faces is a football pitch, not a shopping street.
    'japandm/sign_band_a': dict(
        kind='emissive_full', shader='japandm/sign_band_a', repeat=192,
        texwidth=_SIZES['sign_band_a'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 150', 'q3map_lightsubdivide 128']),
    'japandm/sign_band_b': dict(
        kind='emissive_full', shader='japandm/sign_band_b', repeat=160,
        texwidth=_SIZES['sign_band_b'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 140', 'q3map_lightsubdivide 128']),
    'japandm/sign_menu': dict(
        kind='emissive_full', shader='japandm/sign_menu', repeat=96,
        texwidth=_SIZES['sign_menu'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 70', 'q3map_lightsubdivide 64']),
    'japandm/sign_vertical': dict(
        kind='emissive_full', shader='japandm/sign_vertical', repeat=160,
        texwidth=_SIZES['sign_vertical'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 150', 'q3map_lightsubdivide 128']),
    'japandm/sign_vertical_b': dict(
        kind='emissive_full', shader='japandm/sign_vertical_b', repeat=192,
        texwidth=_SIZES['sign_vertical_b'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 150', 'q3map_lightsubdivide 128']),
    'japandm/wayfinding_blue': dict(
        kind='emissive_full', shader='japandm/wayfinding_blue', repeat=192,
        texwidth=_SIZES['wayfinding_blue'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 110', 'q3map_lightsubdivide 128']),
    'japandm/banner_red': dict(
        kind='emissive_full', shader='japandm/banner_red', repeat=128,
        texwidth=_SIZES['banner_red'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 55', 'q3map_lightsubdivide 96']),
    'japandm/banner_white': dict(
        kind='emissive_full', shader='japandm/banner_white', repeat=128,
        texwidth=_SIZES['banner_white'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 60', 'q3map_lightsubdivide 96']),
    'japandm/noren_strip': dict(
        kind='emissive_full', shader='japandm/noren_strip', repeat=64,
        texwidth=_SIZES['noren_strip'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 30', 'q3map_lightsubdivide 48']),
    # Paper does not light itself.  A poster wall is a lit wall, and the only
    # reason it is in this block is that it belongs to the same kit.
    'japandm/poster_wall': dict(
        kind='lit', shader='japandm/poster_wall', repeat=128,
        texwidth=_SIZES['poster_wall'], normal=True, specular=True),
    'japandm/ad_board_b': dict(
        kind='emissive_full', shader='japandm/ad_board_b', repeat=256,
        texwidth=_SIZES['ad_board_b'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 300', 'q3map_lightsubdivide 256']),
    'japandm/vend_face_b': dict(
        kind='emissive_full', shader='japandm/vend_face_b', repeat=64,
        texwidth=_SIZES['vend_face_b'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 120', 'q3map_lightsubdivide 64']),
    'japandm/vend_face_c': dict(
        kind='emissive_full', shader='japandm/vend_face_c', repeat=84,
        texwidth=_SIZES['vend_face_c'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 130', 'q3map_lightsubdivide 64']),
    'japandm/neon_c': dict(
        kind='emissive_full', shader='japandm/neon_c', repeat=96,
        texwidth=_SIZES['neon_c'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 190', 'q3map_lightsubdivide 96']),
    'japandm/light_strip_warm': dict(
        kind='emissive_full', shader='japandm/light_strip_warm', repeat=128,
        texwidth=_SIZES['light_strip_warm'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 120', 'q3map_lightsubdivide 64']),
    'japandm/light_strip_cyan': dict(
        kind='emissive_full', shader='japandm/light_strip_cyan', repeat=96,
        texwidth=_SIZES['light_strip_cyan'], glow=True, surfaceparm=('nolightmap',),
        q3map=['q3map_surfacelight 110', 'q3map_lightsubdivide 64']),
    # --- roof and deck, re-scaled ------------------------------------------
    'japandm/roof_membrane': dict(
        kind='lit', shader='japandm/roof_membrane', repeat=256,
        texwidth=_SIZES['roof_membrane'], normal=True, specular=True),
    'japandm/deck_timber': dict(
        kind='lit', shader='japandm/deck_timber', repeat=96,
        texwidth=_SIZES['deck_timber'], normal=True, specular=True),
    # --- painted fixtures ---------------------------------------------------
    'japandm/prop_paint_yellow': dict(
        kind='lit', shader='japandm/prop_paint_yellow', repeat=32,
        texwidth=_SIZES['prop_paint_yellow'], normal=True, specular=True),
    'japandm/prop_paint_green': dict(
        kind='lit', shader='japandm/prop_paint_green', repeat=32,
        texwidth=_SIZES['prop_paint_green'], normal=True, specular=True),
    'japandm/metal_brass': dict(
        kind='lit', shader='japandm/metal_brass', repeat=48,
        texwidth=_SIZES['metal_brass'], normal=True, specular=True),
    # --- the sky and the brushes nobody sees --------------------------------
    'japandm/sky': SKY,
    'japandm/nodraw': dict(kind='nodraw', shader='common/nodraw', diffuse=False),
    'japandm/trigger': dict(kind='trigger', shader='common/trigger', diffuse=False),
    'japandm/clip': dict(kind='clip', shader='common/clip', diffuse=False),
}

# How the world reads at load: the shipped episode-4 arenas carry `episode`,
# `palette`, `sky`, a fog triple and a `_color` (read back out of e4dm1/e4dm2).
#
# No lighting keyword belongs here.  A first attempt at the ambient pass put
# `q3map_skyLight '45 8'` on worldspawn because that is where the sun keys live in
# some engines; this compiler only reads it off the sky surface, so the key was
# decoration and `-light` kept reporting `0 sun/sky lights`.  The sky light is now
# declared on `SKY` above, where the compiler actually looks.  What stays here is
# what worldspawn genuinely owns: the episode/palette/sky identity, the fog that
# fades the city into its own haze, and the `_color` tint over the baked light.
WORLD = dict(
    message='japanDM', episode='4', palette='japandm', sky='japandm/sky',
    fog_value='0.10', fog_start='-1', fog_end='2600', fog_skyend='5200',
    _color='0.92 0.90 0.94',
)

# Shaders a ray may see through for the purposes of the sightline probe.
NON_SOLID = ('japandm/trigger', 'japandm/sky')


def non_solid():
    """-> the shader paths that are not painted occluders, from the kinds."""
    from map_materials import KINDS  # noqa: F401  (documents the kind vocabulary)
    return sorted(name for name, entry in MATERIALS.items()
                  if entry['kind'] in ('trigger', 'hint', 'sky', 'clip') or name in NON_SOLID)


def _sync_from_craft():
    """-> `MATERIALS` with `texwidth` and `repeat` taken from `textures.py`.

    This closes a real drift, not a style problem.  The world scale of one tile
    is `repeat / texwidth` (`map_author` divides the authored repeat by the texel
    width to get a UV scale), and `repeat` was hand-maintained in this file while
    the number that decides it -- the measured face survey for this map -- lives in
    `textures.py`.  The two had diverged on twelve of eighteen materials, and the
    shipped map therefore textured surfaces at sizes nobody had chosen:
    `neon_a` carried `repeat=256` against the survey's 64, which is precisely the
    22 % crop of a kanji composition that made the arena read as pink confetti,
    and `asphalt`/`plaza_stone` tiled at 128 against a designed 256, doubling the
    apparent scale of the street.  `_SIZES` was wrong in the same way for
    `metal_deck`, `metal_column` and `holo_pool`, which are stored at 1024 texels
    but declared at 512, so `q3map_textureSize` lied to the compiler about three
    quarters of their pixels.

    One recipe, two consumers: `textures.py` is the source and this table defers
    to it.  Anything the generator does not know about is left alone -- those are
    the tool materials (sky, clip, trigger), which own their own scale.
    """
    import importlib.util
    from pathlib import Path

    spec = importlib.util.spec_from_file_location('japandm_textures', Path(__file__).with_name('textures.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    craft = module.CRAFT
    sizes = {name: int(entry.get('size', 512)) for name, entry in craft.items()}
    _SIZES.update(sizes)
    for path, entry in MATERIALS.items():
        recipe = craft.get(path.rsplit('/', 1)[-1])
        if recipe is None:
            continue
        entry['texwidth'] = sizes[path.rsplit('/', 1)[-1]]
        if recipe.get('repeat') is not None:
            entry['repeat'] = float(recipe['repeat'])
    return MATERIALS


_sync_from_craft()
