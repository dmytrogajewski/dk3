
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
