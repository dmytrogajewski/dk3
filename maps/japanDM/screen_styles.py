# SPDX-License-Identifier: GPL-2.0-or-later
"""Every street prop on japanDM is a style: one body brush plus the small
finishes that make it read as a market stall, a hauler or a container rather than
as a box.  The layout lives here, outside Blender, because the same numbers have
to answer two masters -- build_blender.py builds the scene from them, and the
offline cover planner has to know how far a style reaches beyond its footprint
before it proposes one.  A part named after TRIM (`_plinth`, `_lid`, `_glass`,
`_glow`, `_flange`) is a lining of its own body and so exempt from the pair
rules in `verify`; a part with any other name is a rival object and must clear
every neighbour on its own.
"""

from __future__ import annotations

# What a body brush is made of, per style.
BODY = {
    'planter': 'plaza_stone',
    'hauler': 'metal_column',
    'barrier': 'concrete_panel',
    'market': 'crate',
    'screen': 'plaza_stone',
    'cabinet': 'metal_column',
    'duct': 'metal_column',
    'crates': 'crate',
    'container': 'metal_column',
    'bulkhead': 'concrete_panel',
}

# How far each style reaches outside its rect, so a placement test can reject a
# proposal before building every one of its parts.
BLEED = {
    'planter': (0, 0, 0, 0, 0),
    'hauler': (8, 48, 2, 2, 6),
    'barrier': (0, 8, 0, 8, 12),
    'market': (32, 16, 0, 16, 12),
    'screen': (0, 12, 0, 8, 16),
    'cabinet': (6, 4, 4, 4, 8),
    'duct': (8, 0, 0, 0, 6),
    'crates': (8, 0, 0, 0, 48),
    'container': (8, 0, 8, 8, 0),
    'bulkhead': (8, 4, 4, 4, 6),
}

STYLES = tuple(sorted(BODY))


def parts(style, name, rect, floor, height):
    """ -> every brush one prop is made of, as
    (part name, low corner, high corner, material key, is detail).
    
    """

    if style not in BODY:
        raise KeyError('unknown screen style %s' % style)
    x0, y0, x1, y1 = rect
    mid = (y0 + y1) / 2.0
    made = []
    if style == 'planter':
        made.append((name, (x0, y0, floor), (x1, y1, floor + 64), BODY[style], False))
        made.append(('%s_hedge' % name, (x0 + 8, y0 + 8, floor + 64),
                     (x1 - 8, y1 - 8, floor + height), 'plant', True))
        return made
    made.append((name, (x0, y0, floor), (x1, y1, floor + height), BODY[style], False))
    if style == 'hauler':                            # a parked autonomous hauler
        made.append(('%s_livery' % name, (x0 - 8, y0 + 16, floor + 32),
                     (x0, y1 - 16, floor + 96), 'neon_b', True))
        made.append(('%s_cap' % name, (x0 - 2, y0 - 2, floor + height),
                     (x1 + 2, y1 + 2, floor + height + 6), 'light_strip', True))
        made.append(('%s_cab' % name, (x0, y0 - 40, floor),
                     (x1, y0, floor + 88), 'metal_column', True))
        made.append(('%s_cab_glass' % name, (x0 + 8, y0 - 48, floor + 40),
                     (x1 - 8, y0, floor + 80), 'glass', True))
    elif style == 'barrier':                         # interlocking roadworks panels
        for index in range(3):
            made.append(('%s_chevron_%d' % (name, index),
                         (x0 + 4 + index * 44, y1, floor + 24),
                         (x0 + 36 + index * 44, y1 + 8, floor + 72), 'neon_a', True))
        made.append(('%s_light' % name, (x0, y0 - 8, floor + height),
                     (x1, y0, floor + height + 12), 'light_strip', True))
    elif style == 'market':                          # a stall row's back wall
        made.append(('%s_awning' % name, (x0 - 28, y0 - 16, floor + height),
                     (x0, y1 + 16, floor + height + 12), 'cloth', True))
        made.append(('%s_strip' % name, (x0 - 8, y0 + 8, floor + height - 24),
                     (x0, y1 - 8, floor + height), 'light_strip', True))
        made.append(('%s_post' % name, (x0 - 32, y0 + 8, floor),
                     (x0 - 24, y0 + 16, floor + height), 'metal_column', True))
    elif style == 'screen':                          # a platform screen door wall
        made.append(('%s_glass' % name, (x1, y0 + 8, floor + 24),
                     (x1 + 8, y1 - 8, floor + height - 8), 'glass', True))
        for index, y in enumerate((y0 + 8, mid - 4, y1 - 16)):
            made.append(('%s_mullion_%d' % (name, index), (x1, y, floor),
                         (x1 + 12, y + 8, floor + height), 'metal_column', True))
        made.append(('%s_sign' % name, (x1, y0, floor + height),
                     (x1 + 8, y1, floor + height + 16), 'neon_a', True))
    elif style == 'cabinet':                         # a transformer / signal cabinet
        for index in range(2):
            made.append(('%s_vent_%d' % (name, index), (x0 - 6, y0 + 12 + index * 40, floor + 16),
                         (x0, y0 + 36 + index * 40, floor + height - 24), 'grate', True))
        made.append(('%s_cap' % name, (x0 - 4, y0 - 4, floor + height),
                     (x1 + 4, y1 + 4, floor + height + 8), 'metal_column', True))
    elif style == 'duct':                            # a service duct run on the deck
        # Both names end in `_flange`, which is what makes a collar a lining
        # rather than a rival object standing inside its duct.
        made.append(('%s_near_flange' % name, (x0 - 6, y0 + 64, floor - 2),
                     (x1 + 6, y0 + 80, floor + height + 6), 'metal_column', True))
        made.append(('%s_far_flange' % name, (x0 - 6, y1 - 80, floor - 2),
                     (x1 + 6, y1 - 64, floor + height + 6), 'metal_column', True))
        made.append(('%s_strip' % name, (x0 - 8, y0, floor + height - 12),
                     (x0, y1, floor + height), 'light_strip', True))
    elif style == 'crates':                          # a pallet stack on the dock
        made.append(('%s_top' % name, (x0 + 12, y0 + 12, floor + height),
                     (x1 - 12, y1 - 12, floor + height + 48), 'crate', True))
        made.append(('%s_strap' % name, (x0 - 8, y0 + 12, floor + height - 40),
                     (x0, y1 - 12, floor + height - 16), 'neon_b', True))
    elif style == 'container':                       # a shipped goods container
        # The ribs are `_flange`-named collars: a rib welded into the door
        # face of its own container is a lining, not a rival object.
        for index, y in enumerate((y0 + 8, y1 - 16)):
            made.append(('%s_rib_%d_flange' % (name, index), (x0 - 6, y, floor),
                         (x1 + 6, y + 8, floor + height), 'metal_column', True))
        made.append(('%s_door' % name, (x1, mid - 40, floor + 8),
                     (x1 + 8, mid + 40, floor + height - 8), 'grate', True))
        made.append(('%s_livery' % name, (x0 - 8, y0 + 16, floor + 24),
                     (x0, y1 - 16, floor + height - 24), 'neon_b', True))
    elif style == 'bulkhead':                        # the stair enclosure on the roof
        made.append(('%s_door' % name, (x0 - 8, mid - 32, floor),
                     (x0, mid + 32, floor + 128), 'metal_deck', True))
        made.append(('%s_cap' % name, (x0 - 4, y0 - 4, floor + height),
                     (x1 + 4, y1 + 4, floor + height + 6), 'light_strip', True))
    return made


def envelope(style, rect, floor, height):
    """ -> the extent a style really occupies, part for part.
    
    """

    near_x, near_y, far_x, far_y, above = BLEED[style]
    x0, y0, x1, y1 = rect
    return ((x0 - near_x, y0 - near_y, floor - 2), (x1 + far_x, y1 + far_y, floor + height + above))
