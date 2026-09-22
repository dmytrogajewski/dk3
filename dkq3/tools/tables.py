"""Normalize supplied JSON/CSV/VSC data into quoted, versioned runtime records."""
import csv
import io
import json
import re

TABLES = ('weapons', 'aidata', 'monstersounds', 'sidekickambient', 'music',
          'e1decoinfo', 'e2decoinfo', 'e3decoinfo', 'e4decoinfo')
LIMIT = 4 * 1024 * 1024


def field_name(value):
    return re.sub('[^a-z0-9]+', '_', value.lower()).strip('_')


def csv_fields(headings, table):
    """Give repeated actor weapon columns their explicit group name."""
    result, weapon = [], None
    for index, heading in enumerate(headings):
        if index == 0:
            result.append('modelname' if table.endswith('decoinfo') else 'classname')
            continue
        match = re.fullmatch(r'([XYZ]) weapon([123])Offset', heading, re.IGNORECASE)
        if match:
            weapon = match[2]
            name = f'weapon{weapon}_offset_{match[1].lower()}'
        elif weapon and heading.lower() in ('base damage', 'random damage', 'spread x', 'spread z', 'speed', 'distance'):
            name = f'weapon{weapon}_{field_name(heading)}'
        else:
            name = field_name(heading)
        if not name or name in result:
            raise ValueError(f'{table}: duplicate or empty column {heading!r}')
        result.append(name)
    return result


def read(data, name, table):
    if len(data) > LIMIT:
        raise ValueError(f'{name}: exceeds {LIMIT} bytes')
    if name.endswith('.json'):
        rows = json.loads(data)
        if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
            raise ValueError(f'{name}: expected an array of records')
        return [{field_name(key): value for key, value in row.items()} for row in rows]
    if name.endswith('.vsc'):
        if data[:4] != b'CVSC':
            raise ValueError(f'{name}: missing CVSC signature')
        data = bytes(byte ^ 0x96 for byte in data[4:])
    reader = csv.reader(io.StringIO(data.decode('latin1')), skipinitialspace=True)
    if table == 'music':
        return [{'mapname': row[0].strip(), 'song': row[1].strip()} for row in reader
                if len(row) >= 2 and row[0].strip() and not row[0].lstrip().startswith(('//', ';'))]
    headings = next(reader, None)
    if not headings:
        raise ValueError(f'{name}: empty table')
    while headings and not headings[-1].strip():
        headings.pop()
    keys = csv_fields(headings, table)
    rows = []
    for index, row in enumerate(reader, 2):
        if not row or not row[0].strip() or row[0].lstrip().startswith(('//', ';')):
            continue
        padding = ('', '0') if table.endswith('decoinfo') else ('',)
        if len(row) > len(keys) and any(value.strip() not in padding for value in row[len(keys):]):
            raise ValueError(f'{name}: row {index} has more fields than the heading')
        rows.append(dict(zip(keys, (value.strip() for value in row))))
    return rows


def quoted(value):
    text = str(value)
    if any(c in text for c in ('"', '\n', '\r', '\0')):
        raise ValueError('runtime table field contains a quote, newline or NUL')
    return '"' + text.replace('\\', '/') + '"'


def entries(game, profile):
    """No source code or executable input; precedence is explicit per asset profile."""
    found = []
    required = {'weapons', 'aidata', 'music', 'e1decoinfo', 'e2decoinfo', 'e3decoinfo', 'e4decoinfo'}
    extensions = ('.json', '.csv', '.vsc') if profile == '1.3' else ('.csv', '.vsc', '.json')
    for table in TABLES:
        stem = 'music/music' if table == 'music' else f'models/{table[:2]}/{table}' if table.endswith('decoinfo') else table
        source = next(((stem + ext, game.find(stem + ext)) for ext in extensions if game.find(stem + ext)), None)
        if source is None:
            if table in required:
                raise ValueError(f'profile {profile}: missing {table}' + '/'.join(extensions))
            continue
        name, (_, data) = source
        rows = read(data, name, table)
        output = ['dk3_table 1']
        for row in rows:
            if table.endswith('decoinfo') and 'modelname' not in row:
                continue
            output.append('{')
            for key, value in sorted(row.items()):
                if value is not None:
                    output.append(quoted(key) + ' ' + quoted(value))
            output.append('}')
        found.append((f'dk3/tables/{table}.cfg', ('\n'.join(output) + '\n').encode('utf-8')))
    return found
