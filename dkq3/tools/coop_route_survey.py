#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Summarise a converted map for co-op bot route authoring.

Lists what a route usually has to deal with: starts and exits, key items and
locks, named doors/platforms and their controls, scripted triggers, companions
and hostile encounters. Input is the local converted map package; output is
plain text (or JSON) derived from authored entities, never a route by itself.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import struct
import sys
import zipfile

import entities

ROOT = Path(__file__).resolve().parents[2]
CONTROLS = ('func_button', 'trigger_once', 'trigger_multiple', 'trigger_counter', 'trigger_relay', 'func_door',
            'func_door_rotate', 'func_plat', 'func_train', 'func_elevator', 'func_explosive', 'trigger_script',
            'func_wall_explode', 'func_door_secret', 'func_rotate', 'trigger_use', 'target_script')


def bsp_entities(data):
    if len(data) < 144 or struct.unpack_from('<4si', data) != (b'IBSP', 46):
        raise ValueError('invalid converted BSP')
    offset, length = struct.unpack_from('<ii', data, 8)
    model_offset, model_length = struct.unpack_from('<ii', data, 8 + 7 * 8)
    models = list(struct.iter_unpack('<6f4i', data[model_offset:model_offset + model_length]))
    rows = []
    for index, pairs in enumerate(entities.parse(data[offset:offset + length])):
        row = {key: value for key, value in pairs}
        row['index'] = index + 1
        model = row.get('model', '')
        if re.fullmatch(r'\*\d+', model) and int(model[1:]) < len(models):
            bounds = models[int(model[1:])][:6]
            origin = [float(v) for v in row.get('origin', '0 0 0').split()]
            row['bounds'] = [round(bounds[i] + origin[i % 3]) for i in range(6)]
        rows.append(row)
    return rows


def survey(rows):
    by_class = collections.Counter(row.get('classname', '') for row in rows)
    named = {row['targetname']: row for row in rows if row.get('targetname')}
    result = dict(
        world=next((row.get('mapname', '') for row in rows if row.get('classname') == 'worldspawn'), ''),
        starts=[pick(row, 'targetname', 'origin', 'angle', 'spawnflags') for row in rows if row.get('classname') == 'info_player_start'],
        exits=[pick(row, 'map', 'target', 'targetname', 'cinematic', 'spawnflags', 'bounds', 'keyname', 'companions') for row in rows
               if row.get('classname') == 'trigger_changelevel'],
        keys=[pick(row, 'classname', 'origin', 'targetname') for row in rows
              if re.search(r'key|card|crypt|rune|horn|crystal|talisman|stone', row.get('classname', '')) and
              row.get('classname', '').startswith(('item_', 'key_'))],
        locks=[pick(row, 'classname', 'targetname', 'keyname', 'bounds', 'origin') for row in rows if row.get('keyname')],
        controls=[pick(row, 'classname', 'targetname', 'target', 'spawnflags', 'health', 'bounds', 'origin', 'message')
                  for row in rows if row.get('classname') in CONTROLS],
        companions=[pick(row, 'classname', 'origin', 'targetname') for row in rows
                    if row.get('classname') in ('mikiko', 'superfly', 'mikikofly') or 'sidekick' in row.get('classname', '')],
        weapons=[pick(row, 'classname', 'origin') for row in rows if row.get('classname', '').startswith('weapon_')],
        monsters=dict(sorted((name, count) for name, count in by_class.items() if name.startswith('monster_'))),
        cinematics=sorted({row[key] for row in rows for key in ('cinematic', 'cinematic_intro', 'cinetrigger') if row.get(key)}),
    )
    for control in result['controls']:
        target = control.get('target')
        if target and target in named:
            control['targets'] = named[target].get('classname')
    return result


def pick(row, *keys):
    return {key: row[key] for key in ('index',) + keys if key in row}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('maps', nargs='+')
    parser.add_argument('--package', type=Path, default=ROOT / 'zig-out/native-dev/play/current/share/dk3/dk3-maps.pk3')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args(argv)
    with zipfile.ZipFile(args.package) as package:
        for name in args.maps:
            result = survey(bsp_entities(package.read(f'maps/{name}.bsp')))
            if args.json:
                print(json.dumps({name: result}, indent=1))
                continue
            print(f'== {name}: {result["world"]}')
            for key in ('starts', 'exits', 'keys', 'locks', 'companions', 'weapons', 'controls'):
                for row in result[key]:
                    print(f'  {key[:-1]:9} ' + ' '.join(f'{k}={v}' for k, v in row.items()))
            print(f'  monsters  ' + ' '.join(f'{k[8:]}={v}' for k, v in result['monsters'].items()))
            if result['cinematics']:
                print(f'  cinematic ' + ' '.join(result['cinematics']))
    return 0


if __name__ == '__main__':
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
