"""Compile AAS locally from converted maps with the bundled, pinned GPL bspc."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys

import entities
import pk3

MODES = ('dm', 'easy', 'normal', 'hard', 'ctf', 'deathtag')
# Converted collision brushes retain sides that need not match a rendered face.
# Omitting those sides as BSP splitters extends solid regions beyond the actual
# brush, creating phantom floors and unreachable barrier jumps in AAS.
COMPILER_OPTIONS = ('-threads', '1', '-forcesidesvisible', '-optimize')
# Brush classes considered by BSPC AAS_ValidEntity. Weather, scenery and breakables
# do not create static AAS brushes, so their spawn flags cannot require a variant.
NAVIGATION_BRUSHES = frozenset(('func_wall', 'func_static', 'func_door', 'func_door_rotating',
                              'trigger_hurt', 'trigger_push', 'trigger_multiple', 'trigger_teleport'))


def navigation_variants(source):
    """Group modes whose authored brush entities have identical spawn eligibility."""
    data = source.read_bytes()
    if len(data) < 144 or data[:8] != b'IBSP\x2e\0\0\0':
        raise ValueError(f'{source}: expected a converted IBSP 46 map')
    offset, length = struct.unpack_from('<ii', data, 8)
    if offset < 144 or length < 1 or offset + length > len(data):
        raise ValueError(f'{source}: invalid entity lump')
    parsed = [dict(entity) for entity in entities.parse(data[offset:offset + length])]
    brushes = [(index, entity) for index, entity in enumerate(parsed)
               if entity.get('model', '').startswith('*') and entity.get('classname') in NAVIGATION_BRUSHES]
    groups, selected = {}, {}
    for mode in MODES:
        excluded = {'easy': 0x1000, 'normal': 0x2000, 'hard': 0x4000}.get(mode, 0x8000)
        enabled = dict(coop=False, ctf=mode == 'ctf', deathtag=mode == 'deathtag')
        signature = tuple(index for index, entity in brushes
                          if not (int(entity.get('spawnflags') or '0') & excluded)
                          and all(key not in entity or (int(entity[key] or '0') != 0) == value
                                  for key, value in enabled.items()))
        if signature not in groups:
            groups[signature] = (source.stem if mode == 'dm' else source.stem + '-' + mode, mode)
        selected[mode] = groups[signature][0]
    return list(groups.values()), selected


def inspect_aas(path):
    """Validate the compiler output before it can be admitted to a package."""
    data = path.read_bytes()
    if len(data) < 124 or data[:4] != b'EAAS' or struct.unpack_from('<i', data, 4)[0] != 5:
        raise ValueError(f'{path}: unsupported or truncated AAS header')
    header = bytearray(data[:124])
    for index in range(116):
        header[index + 8] ^= (index * 119) & 255
    sizes = (32, 12, 20, 8, 4, 24, 4, 48, 28, 44, 12, 20, 4, 16)
    counts = []
    for index, size in enumerate(sizes):
        offset, length = struct.unpack_from('<ii', header, 12 + index * 8)
        if offset < 124 or length < 0 or offset + length > len(data) or length % size:
            raise ValueError(f'{path}: invalid AAS lump {index}: offset={offset}, length={length}')
        counts.append(length // size)
    if counts[7] != counts[8] or counts[7] < 2 or counts[9] < 2 or counts[13] < 2:
        raise ValueError(f'{path}: no usable navigation: areas={counts[7]}, '
                         f'settings={counts[8]}, reachabilities={counts[9]}, clusters={counts[13]}')
    return dict(areas=counts[7], reachabilities=counts[9], clusters=counts[13])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--maps', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--pk3', type=Path, required=True)
    parser.add_argument('--bspc', required=True)
    parser.add_argument('--dkguard', required=True)
    args = parser.parse_args(argv)
    try:
        args.out.mkdir(parents=True, exist_ok=True)
        maps = sorted(args.maps.glob('*.bsp'))
        if not maps:
            raise ValueError(f'{args.maps}: no converted maps')
        entries = []
        compiler_hash = hashlib.sha256(Path(args.bspc).read_bytes()).hexdigest()
        for source in maps:
            variants, selected = navigation_variants(source)
            source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            for stem, mode in variants:
                target = args.out / (stem + '.aas')
                log = args.out / (stem + '.log')
                record = args.out / (stem + '.json')
                identity = dict(bspc=compiler_hash, source=source_hash, mode=mode,
                                options=list(COMPILER_OPTIONS))
                if record.is_file() and target.is_file():
                    previous = json.loads(record.read_text())
                    if previous.get('inputs') == identity and previous.get('sha256') == hashlib.sha256(target.read_bytes()).hexdigest():
                        inspect_aas(target)
                        entries.append(('maps/' + target.name, str(target)))
                        print(f'navigation: {stem} (resumed)', flush=True)
                        continue
                work = args.out / ('.work-' + stem)
                work.mkdir(exist_ok=True)
                product = work / (source.stem + '.aas')
                product.unlink(missing_ok=True)
                command = [args.dkguard, '--mem', '6G', '--timeout', '1800', '--', args.bspc,
                           *COMPILER_OPTIONS, '-dk3-mode', mode, '-bsp2aas', str(source.resolve()),
                           '-output', str(work.resolve())]
                with log.open('wb') as output:
                    result = subprocess.run(command, cwd=work, stdout=output, stderr=subprocess.STDOUT, check=False)
                if result.returncode or not product.is_file():
                    raise ValueError(f'{source.name} ({mode}): bspc failed ({result.returncode}); see {log}')
                counts = inspect_aas(product)
                product.replace(target)
                temporary = record.with_suffix('.partial')
                temporary.write_text(json.dumps(dict(inputs=identity, counts=counts,
                                     sha256=hashlib.sha256(target.read_bytes()).hexdigest()), sort_keys=True) + '\n')
                temporary.replace(record)
                entries.append(('maps/' + target.name, str(target)))
                print(f'navigation: {stem}: {counts}', flush=True)
            selection = args.out / (source.stem + '.cfg')
            selection.write_text('dk3_navigation 1\n' + ''.join(f'{mode} {selected[mode]}\n' for mode in MODES))
            entries.append(('dk3/navigation/' + selection.name, str(selection)))
        pk3.write_files(args.pk3, entries)
        return 0
    except (OSError, ValueError) as error:
        print(f'navigation: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
