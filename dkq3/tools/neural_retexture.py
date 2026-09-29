# SPDX-License-Identifier: GPL-2.0-or-later
"""Replace one local character atlas and colors without reconverting motion."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from neural_assets import CHARACTERS, texture_files
from neural_package import validate_package


def replace(package, base, character, texture, output):
    document = validate_package(package, base)
    updates = texture_files(character, texture)
    if not set(updates) <= set(document['files']):
        raise ValueError('Character textures are absent from this package')
    provenance = document['inputs'][character]
    provenance['texture_sha256'] = hashlib.sha256(texture.read_bytes()).hexdigest()
    face = texture.with_suffix('.face.json')
    if face.exists():
        provenance['face_repair'] = json.loads(face.read_text())
        if 'mesh' in provenance: provenance['mesh']['face_repair'] = provenance['face_repair']
    document['files'].update({name: hashlib.sha256(data).hexdigest() for name, data in updates.items()})
    updates['dk3/neural-assets.json'] = json.dumps(document, sort_keys=True, indent=2).encode()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.partial')
    with zipfile.ZipFile(package) as source, zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
        for name in sorted(source.namelist()):
            data = updates[name] if name in updates else source.read(name)
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, data)
    validate_package(temporary, base)
    temporary.replace(output)
    output.with_suffix('.json').write_text(json.dumps(document, indent=2, sort_keys=True)+'\n')
    print('Retextured', character, hashlib.sha256(output.read_bytes()).hexdigest())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('package', 'base', 'texture', 'out'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--character', choices=CHARACTERS, required=True)
    args = parser.parse_args()
    replace(args.package, args.base, args.character, args.texture, args.out)
