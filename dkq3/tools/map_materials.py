# SPDX-License-Identifier: GPL-2.0-or-later
"""Turn a map's material table into a shader script and an image manifest.

A map's `materials.py` holds one table entry per shader:

    'neo_concrete': dict(kind='lit', repeat=256, normal=True, specular=True,
                         surfaceparm=('metalsteps',))

`kind` picks the stage layout. `lit` is the Quake III lightmapped form. A normal
or specular map is not found by a suffix search here: this emitter names the
stages, because renderergl2/tr_shader.c tries `<name>_n` / `<name>_s` only in the
`else if ((lightmap || useLightVector || useLightVertex) && ...)` branch of
`CollapseStagesToLightall`, while an explicit stage takes the unconditional
`if (normal)` one. `stage <type>` is a ParseStage keyword, so it sits inside the
stage's braces and before `map` -- `map` loads the image immediately, and the type
picks the flags it loads with (IMGTYPE_NORMAL for a normal map). The stage pair
`$lightmap` then diffuse is what the map is authored as: tr_shader.c
`R_CollapseStages` swaps a lightmap-first pair into native form itself, so this
order is not what would keep the deluxemap unused.
`emissive` adds an additive glow stage, which stays bright in shadow without a
light entity. `trans` draws the diffuse with its alpha and multiplies the lightmap
afterwards. `sky`, `nodraw`, `hint` and `trigger` carry no image at all, only
surface parameters.

`q3map_textureSize` is written explicitly so a texture repeat in world units
never depends on which image resolution happens to be cached: the compiler
measures the declared size, and `map_author.py` divides the authored repeat by
that same number.
"""
from __future__ import annotations

EXTENSION = '.tga'
SKY_SIDES = ('rt', 'bk', 'lf', 'ft', 'up', 'dn')
KINDS = ('lit', 'emissive', 'emissive_full', 'trans', 'sky', 'nodraw', 'hint', 'trigger', 'clip')
# Kinds that own no image, so a second shader name for them is free.
NO_IMAGE_KINDS = ('nodraw', 'hint', 'trigger', 'clip')


def stem(name):
    """The image base name for a table key: keys are shader paths, images are not."""
    return name.rpartition('/')[2]


def image_paths(name, entry):
    """-> [(shader-relative suffix, image file name)] this material needs."""
    if not entry.get('diffuse', entry['kind'] in ('lit', 'emissive', 'emissive_full', 'trans')):
        return []
    files = []
    if entry.get('diffuse', True):
        files.append(('', entry.get('diffuse_name') or stem(name)))
    if entry.get('normal'):
        files.append(('_n', entry.get('normal_name') or stem(name)))
    if entry.get('specular'):
        files.append(('_s', entry.get('specular_name') or stem(name)))
    if entry.get('glow'):
        files.append(('_g', entry.get('glow_name') or stem(name)))
    return files


def surface_parms(entry):
    """-> the surfaceparms this material's shader will carry, as bare names.

    Ask this instead of re-deriving it: a tool that must know whether a brush is
    empty space to the compiler -- the leak test, the visibility probe -- has to
    read the same function that writes the shader, or the two drift apart and the
    map leaks for a reason no tool can see.
    """
    parms = list(entry.get('surfaceparm', ()))
    if entry['kind'] == 'sky':
        # `sky` and `noimpact` only, deliberately: the sky surface stays solid.
        # A nonsolid sky surface is empty space to q3map2, so a sky room built
        # with it stops sealing the world and the compile leaks -- which is why
        # the shipped game's own sky shaders (textures/dkq3/sky/*) carry no
        # surfaceparm at all. `nolightmap` is unnecessary: q3map2 skips the
        # lightmaps of a SURF_SKY surface by itself.
        parms += ['sky', 'noimpact']
    elif entry['kind'] == 'nodraw':
        parms += ['nodraw']
    elif entry['kind'] == 'hint':
        parms += ['hint', 'nonsolid', 'nodraw', 'nolightmap']
    elif entry['kind'] == 'trigger':
        parms += ['trigger', 'nodraw']
    elif entry['kind'] == 'clip':
        parms += ['nodraw', 'nolightmap']
    elif entry['kind'] == 'trans':
        parms += ['trans']
    return parms




# The surfaceparms that make a brush empty space: `nonsolid` and `trigger` clear
# CONTENTS_SOLID and `hint` is see-through by definition. A `sky` surface is
# solid unless a tool said otherwise, which is what keeps a sky room leak-proof
# (see `surface_parms`), so it is NOT in this list.
NON_SOLID_PARMS = ('nonsolid', 'trigger', 'hint')


def non_solid_names(materials, parms=NON_SOLID_PARMS):
    """-> the sorted shader NAMES whose own surfaceparms make a brush empty space.

    Both spellings come back -- the table key and any `shader` path the entry
    declares -- because a `.map` face carries the key while a shader block may be
    filed under either, and a tool that answers for only one of them disagrees
    with the map or with the compiler. Ask this instead of reading `kind`: `kind`
    chooses the stage layout, the surfaceparms choose the contents.
    """
    out = set()
    for name, entry in sorted(materials.items()):
        entry = dict(entry, kind=entry.get('kind', 'lit'))
        if any(parm in surface_parms(entry) for parm in parms):
            out.add(name)
            out.add(entry.get('shader', name))
    return sorted(out)


def surface_lines(name, entry):
    return ['\tsurfaceparm %s' % value for value in surface_parms(entry)]


def shader_block(name, entry, extension=EXTENSION):
    kind = entry['kind']
    shader = entry.get('shader', name)
    # A shader name q3map2 cannot resolve is not "no shader": it becomes a
    # default opaque, lightmapped, SOLID brush.  japanDM files its imageless
    # materials under the traditional `common/` names, wrote its faces with the
    # table key, and got an invisible 64-tall wall across a street where a
    # `trigger_hurt` volume was meant to be.  So the block is named for the key
    # the map writes, `path` still names where the images are, and
    # `alias_blocks` gives the declared path the same definition.
    path = 'textures/%s' % shader
    lines = ['textures/%s' % name, '{']
    if kind != 'sky':
        lines.append('\tq3map_textureSize %g %g' % (entry.get('texwidth', 512), entry.get('texheight',
                                                                                          entry.get('texwidth', 512))))
    lines += surface_lines(name, entry)
    if entry.get('q3map'):
        lines += ['\t%s' % line for line in entry['q3map']]
    if kind == 'sky':
        lines.append('\tskyParms %s %g -' % (entry['skybox'], entry.get('cloudheight', 512)))
    elif kind == 'emissive_full':
        lines += ['\t{', '\t\tmap %s' % path, '\t\trgbGen identity', '\t}']
        if entry.get('glow'):
            lines += ['\t{', '\t\tmap %s_g' % path, '\t\tblendFunc GL_ONE GL_ONE', '\t}']
    elif kind == 'trans':
        lines += ['\tqer_trans %.2f' % entry.get('transparency', 0.4), '\t{',
                  '\t\tmap %s' % path, '\t\tblendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA',
                  '\t\trgbGen identity', '\t}', '\t{', '\t\tmap $lightmap',
                  '\t\tblendFunc GL_DST_COLOR GL_ZERO', '\t}']
        if entry.get('normal'):
            lines += ['\t{', '\t\tstage normalMap', '\t\tmap %s_n' % path, '\t}']
    elif kind in NO_IMAGE_KINDS:
        pass
    else:
        lines += ['\t{', '\t\tmap $lightmap', '\t\trgbGen identity', '\t}', '\t{',
                  '\t\tmap %s' % path, '\t\tblendFunc GL_DST_COLOR GL_ZERO', '\t}']
        # `stage <type>` is a ParseStage keyword, so it belongs inside the braces;
        # and it must precede `map`, because `map` loads the image straight away
        # with the flags the type selects (IMGTYPE_NORMAL for a normal map).
        if entry.get('normal'):
            lines += ['\t{', '\t\tstage normalMap', '\t\tmap %s_n' % path, '\t}']
        if entry.get('specular'):
            lines += ['\t{', '\t\tstage specularMap', '\t\tmap %s_s' % path,
                      '\t\tspecularScale %.2f %.2f %.2f %.2f' % entry.get('specular_scale',
                                                                           (1, 1, 1, 0.6)), '\t}']
        if entry.get('glow'):
            lines += ['\t{', '\t\tmap %s_g' % path, '\t\tblendFunc GL_ONE GL_ONE', '\t}']
    lines.append('}')
    return '\n'.join(lines)


def alias_blocks(materials):
    """-> [(name, entry)] the extra shader names a table needs a block for.

    An entry may declare a `shader` path of its own to say where its images
    live. For the imageless kinds that path is only the traditional name
    (`common/trigger`), so both names get one identical block and a face
    written either way keeps its surfaceparms. A drawn material is not
    aliased: its stages name one image path, and a second name would claim
    images it does not have.
    """
    out = []
    for name, entry in sorted(materials.items()):
        entry = dict(entry, kind=entry.get('kind', 'lit'))
        other = entry.get('shader', name)
        if other != name and entry['kind'] in NO_IMAGE_KINDS:
            out.append((other, entry))
    return out


def shader_text(materials, comment=''):
    blocks = ['// %s' % line for line in comment.splitlines()] if comment else []
    blocks += [shader_block(name, dict(entry, kind=entry.get('kind', 'lit')))
               for name, entry in sorted(materials.items())]
    blocks += [shader_block(other, entry) for other, entry in alias_blocks(materials)]
    return '\n\n'.join(blocks) + '\n'


def images(materials):
    """-> [(VFS target, image file name)] every material image the compiler needs."""
    found = []
    for name, entry in sorted(materials.items()):
        entry = dict(entry, kind=entry.get('kind', 'lit'))
        directory, _, _ = entry.get('shader', name).rpartition('/')
        for suffix, stem in image_paths(name, entry):
            target = 'textures/%s%s%s' % (entry.get('shader', name), suffix, entry.get('extension', EXTENSION))
            found.append((target, '%s/%s%s%s' % (directory or '.', stem, suffix, entry.get('extension', EXTENSION))))
    return found


def sky_images(sky):
    """-> [(VFS target, image file name)] for the six faces named by `skybox`.

    `skybox` is the full prefix the renderer concatenates, so `env/japandm`
    loads `env/japandm_rt.tga` and friends (renderergl2/tr_shader.c
    `ParseSkyParms` appends only `_<side>.tga`).
    """
    return [('%s_%s%s' % (sky['skybox'], side, sky.get('extension', EXTENSION)),
             '%s_%s%s' % (sky['skybox'], side, sky.get('extension', EXTENSION))) for side in SKY_SIDES]
