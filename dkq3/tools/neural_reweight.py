# SPDX-License-Identifier: GPL-2.0-or-later
"""Localize existing skeletal weights without changing motion, faces or topology."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import iqm
import skeletal_iqm as sk
from neural_rig import localize_weights
from neural_package import validate_package


def patch_weights(data):
    model = sk.read(data)
    before = (model.arrays[5] > 0).sum(axis=1)
    localize_weights(model)
    header = dict(zip((k for k, _ in iqm.HEADER_FIELDS), iqm.HEADER.unpack_from(data)))
    output = bytearray(data)
    # Patch only weights/indices and the conservative per-frame bounds. Writing
    # a new IQM outright would unnecessarily requantize the existing motion.
    for i in range(header['num_vertexarrays']):
        kind, flags, fmt, size, offset = iqm.VERTEX_ARRAY.unpack_from(data, header['ofs_vertexarrays']+i*iqm.VERTEX_ARRAY.size)
        if kind not in (4, 5): continue
        assert not flags and fmt == 1 and size == 4
        replacement = model.arrays[kind].astype('u1').tobytes()
        output[offset:offset+len(replacement)] = replacement
    rebuilt = sk.write(model)
    fresh = dict(zip((k for k, _ in iqm.HEADER_FIELDS), iqm.HEADER.unpack_from(rebuilt)))
    size = header['num_frames']*iqm.BOUNDS.size
    if not header['ofs_bounds']: raise ValueError('Expected animated model bounds')
    output[header['ofs_bounds']:header['ofs_bounds']+size] = rebuilt[fresh['ofs_bounds']:fresh['ofs_bounds']+size]
    after = (model.arrays[5] > 0).sum(axis=1)
    return bytes(output), dict(vertices=len(before), rigid_before=int((before == 1).sum()),
                               rigid_after=int((after == 1).sum()), blended_after=int((after > 1).sum()),
                               max_influences=int(after.max()))


def replace(package, base, output):
    if package.resolve() == output.resolve(): raise ValueError('Stage a separate package for review')
    document = validate_package(package, base)
    updates, report = {}, {}
    with zipfile.ZipFile(package) as source:
        for name in sorted(source.namelist()):
            if not name.endswith('.iqm'): continue
            updates[name], report[name] = patch_weights(source.read(name))
            print(name, report[name], flush=True)
        document['geometry_repair'] = dict(source_package_sha256=hashlib.sha256(package.read_bytes()).hexdigest(),
                                           method='Rigid segment targets, connected joint bands with welded-surface relaxation; motion/UVs/topology/textures unchanged',
                                           models=report)
        document['files'].update({name: hashlib.sha256(data).hexdigest() for name, data in updates.items()})
        updates['dk3/neural-assets.json'] = json.dumps(document, sort_keys=True, indent=2).encode()
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_suffix('.partial')
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as target:
            for name in sorted(source.namelist()):
                info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                target.writestr(info, updates[name] if name in updates else source.read(name))
    validate_package(temporary, base)
    temporary.replace(output)
    output.with_suffix('.json').write_text(json.dumps(document, sort_keys=True, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('package', 'base', 'out'): parser.add_argument('--'+name, type=Path, required=True)
    args = parser.parse_args()
    replace(args.package, args.base, args.out)
