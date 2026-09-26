# SPDX-License-Identifier: GPL-2.0-or-later
"""Package the reviewed multiplayer catalog's body skins and MD3 bindings."""
import csv
import json
import os
from pathlib import Path


def catalog():
    path = Path(__file__).resolve().parents[2] / 'src/multiplayer/appearances.csv'
    with path.open(encoding='utf-8', newline='') as stream:
        return list(csv.reader(stream))


def package(args, rows, entries, variants):
    # Import lazily: this function is called by the model packager itself.
    import dkm2md3 as models
    models._start_worker(args.data, args.pak5, args.manifest, args.images, args.out_dir)
    admitted = {row['name']: row for row in rows if row['status'] == models.CONVERTED}
    try:
        for selection, model, binding, source, _label in catalog():
            if model not in admitted:
                raise ValueError(f'appearance {selection}: missing model {model}')
            skin, resolution = models.resolve_skin(source)
            if resolution not in (models.STEP6, models.DECODED):
                raise ValueError(f'appearance {selection}: unavailable body skin {source}')
            base = args.images if resolution == models.STEP6 else os.path.join(args.out_dir, models.IMAGES_DIR)
            entries[skin.image] = os.path.join(base, skin.image)
            with open(entries[skin.image], 'rb') as stream:
                variants.add((skin.shader, skin.image, models.png_has_alpha(stream.read(32))))
            row = admitted[model]
            with open(entries[row['sidecar']], encoding='utf-8') as stream:
                metadata = json.load(stream)
            lines = []
            for surface in metadata['surfaces']:
                if not surface['target_surfaces']:
                    continue
                # Preserve head materials and invisible hardpoints. Gold changes
                # the body skin; MD3 skinNum selects render effects, not colors.
                shader = surface['shader']
                if '_bod_' in shader:
                    shader = skin.shader
                name = surface['name'].lower()
                if len(name) > 2 and name[-2] == '_':
                    name = name[:-2]  # MD3 loader removes exporter suffixes.
                lines.append(f'{name},{shader}')
            output = os.path.join(args.out_dir, binding)
            models._write(output, ('\n'.join(lines) + '\n').encode('ascii'))
            entries[binding] = output
    finally:
        models._worker['game'].__exit__()
