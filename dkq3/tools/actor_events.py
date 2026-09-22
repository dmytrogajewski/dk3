"""Convert supplied actor frame tables; no executable or source-code input."""
import csv
import io
import json
import math
import re

import tables


def field_name(key):
    return tables.field_name(key.replace('%', ' percent'))


def records(data, name):
    if len(data) > tables.LIMIT:
        raise ValueError(f'{name}: actor frame table exceeds size limit')
    if name.endswith('.json'):
        rows = json.loads(data)
        if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            raise ValueError(f'{name}: expected frame records')
        return [{field_name(key): value for key, value in row.items()} for row in rows]
    if name.endswith('.vsc'):
        if data[:4] != b'CVSC':
            raise ValueError(f'{name}: missing CVSC signature')
        data = bytes(byte ^ 0x96 for byte in data[4:])
    reader = csv.reader(io.StringIO(data.decode('latin1')), skipinitialspace=True)
    headings = next(reader, None)
    if not headings:
        raise ValueError(f'{name}: empty frame table')
    headings[0] = 'framename'
    keys = [field_name(key) for key in headings]
    return [dict(zip(keys, (value.strip() for value in row))) for row in reader
            if row and row[0].strip() and not row[0].lstrip().startswith(('//', ';'))]


def number(row, key, default, name):
    value = row.get(key, '')
    if value in ('', None):
        return default
    try:
        value = float(value)
    except (ValueError, TypeError) as error:
        raise ValueError(f'{name}: {row.get("framename")}: invalid {key}') from error
    if not math.isfinite(value) or value != int(value) or not 0 <= value <= 65535:
        raise ValueError(f'{name}: {row.get("framename")}: invalid {key} {value}')
    return int(value)


def entries(game, profile):
    extensions = ('.json', '.csv', '.vsc') if profile == '1.3' else ('.csv', '.vsc', '.json')
    source = next((('aidata' + ext, game.find('aidata' + ext)) for ext in extensions
                   if game.find('aidata' + ext)), None)
    if source is None:
        raise ValueError('actor frame tables require supplied aidata')
    actors = tables.read(source[1][1], source[0], 'aidata')
    output, missing = ['dk3_table 1'], []
    for actor in actors:
        path = str(actor.get('csv_file_name', '')).replace('\\', '/').lower()
        if not path:
            continue
        stem = path.rsplit('.', 1)[0]
        if not re.fullmatch(r'[a-z0-9_/.-]+', stem) or '..' in stem.split('/'):
            raise ValueError(f'actor {actor["classname"]}: invalid frame table path {path!r}')
        source = next(((stem + ext, game.find(stem + ext)) for ext in extensions
                       if game.find(stem + ext)), None)
        if source is None:
            missing.append({'classname': actor['classname'], 'path': path})
            continue
        name, (_, data) = source
        for row in records(data, name):
            animation = str(row.get('framename', '')).strip().lower()
            if not animation or animation.startswith(('//', ';')):
                continue
            normalized = {'classname': actor['classname'], 'animation': animation}
            for index in (1, 2):
                normalized[f'sound{index}'] = str(row.get(f'sound{index}', '') or '').strip()
                normalized[f'frame{index}'] = number(row, f'frame{index}', 1, name)
            normalized['strike1'] = next((number(row, key, 0, name) for key in
                                          ('attack_seq_1', 'attack_seq1', 'attack_seq') if key in row), 0)
            normalized['strike2'] = next((number(row, key, 0, name) for key in
                                          ('attack_seq_2', 'attack_seq2') if key in row), 0)
            normalized['weight'] = number(row, 'anim_percent', 100, name)
            normalized['sound2_chance'] = min(100, number(row, 'sound2_percent', 100, name))
            output.append('{')
            output.extend(tables.quoted(key) + ' ' + tables.quoted(value)
                          for key, value in sorted(normalized.items()))
            output.append('}')
    return [('dk3/tables/actor_events.cfg', ('\n'.join(output) + '\n').encode('utf-8')),
            ('dk3/reports/actor-events.json', (json.dumps({'missing_optional_tables': missing},
              indent=2, sort_keys=True) + '\n').encode('utf-8'))]
