# SPDX-License-Identifier: GPL-2.0-or-later
"""Build face tint protection on a regenerated character's own UV atlas."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
import skeletal_iqm as sk


def tint_mask(actor):
    model=sk.read((actor/'model.iqm').read_bytes())
    size=Image.open(actor/'body.png').size
    protected={model.names.index(name) for name in ('head','neck')}
    amount=np.sum(np.where(np.isin(model.arrays[4],list(protected)),model.arrays[5],0),axis=1)/255
    mask=Image.new('L',size,0)
    draw=ImageDraw.Draw(mask)
    uv=model.arrays[1]*np.asarray(size)
    for _, material, _, _, first, count in model.meshes:
        if material.endswith('/head'):
            continue
        for tri in model.triangles[first:first + count]:
            strength=float(amount[tri].max())
            if strength>.2:
                draw.polygon([tuple(p) for p in uv[tri]],fill=255)
    destination=actor/'body.face-mask.png'
    mask.convert('RGBA').save(destination)
    return destination
