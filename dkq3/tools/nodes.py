"""Read authored node graphs and emit bounded, versioned dk3 route data.

The binary layout is documented in docs/navigation.md. Stored path tables are
validated but routing is recomputed from links, including changes to world collision.
"""
import json
import math
from pathlib import PurePosixPath
import struct

from tables import quoted

LIMIT = 4096


class Reader:
    def __init__(self, name, data):
        self.name, self.data, self.at = name, data, 0

    def fail(self, message):
        raise ValueError(f'{self.name}: byte {self.at}: {message}')

    def take(self, size):
        if size < 0 or size > len(self.data) - self.at:
            self.fail(f'truncated record ({size} bytes requested)')
        result = self.data[self.at:self.at + size]
        self.at += size
        return result

    def unpack(self, format):
        return struct.unpack('<' + format, self.take(struct.calcsize('<' + format)))

    def integer(self):
        return self.unpack('i')[0]

    def signature(self):
        end = self.data.find(b'\0', self.at, self.at + 80)
        if end < 0:
            self.fail('missing chunk signature terminator')
        return self.take(end - self.at + 1)[:-1].decode('ascii').lower()

    def text(self):
        length = self.integer()
        if length <= 0:
            return ''
        if length > 255:
            self.fail('target name exceeds 255 bytes')
        text = self.take(length).rstrip(b'\0')
        if b'\0' in text or any(byte < 32 for byte in text):
            self.fail('invalid target name')
        return text.decode('latin1')

    def vector(self):
        vector = self.unpack('3f')
        if not all(math.isfinite(value) and abs(value) <= 1048576 for value in vector):
            self.fail('nonfinite or out-of-range node coordinate')
        return vector


def parse(name, data):
    reader = Reader(name, data)
    if reader.signature() != 'nodes:' or reader.integer() != 0:
        reader.fail('unsupported node file header')
    graphs, tables = {}, {}
    while reader.at < len(data):
        signature = reader.signature()
        kind = next((kind for kind in ('ground', 'air', 'track') if signature.startswith(kind)), None)
        if kind is None or signature not in (kind + 'nodes:', kind + 'pathtable:'):
            reader.fail(f'unsupported chunk {signature!r}')
        if reader.integer() != 0:
            reader.fail('unsupported chunk version')
        count = reader.integer()
        if not 0 <= count <= LIMIT:
            reader.fail(f'node count outside 0..{LIMIT}')
        if signature.endswith('pathtable:'):
            if kind not in graphs or kind in tables or count != len(graphs[kind]):
                reader.fail('path table must match its preceding graph')
            table = reader.unpack(f'{count * count}h')
            if any(value < -1 or value >= count for value in table):
                reader.fail('path table references a missing node')
            tables[kind] = table
            continue
        if kind in graphs or reader.integer() < count:
            reader.fail('duplicate graph or invalid allocated count')
        nodes = []
        for _ in range(count):
            index, position = reader.integer(), reader.vector()
            flags, version = reader.unpack('2i')
            if version == 0:
                payload = {'legacy_data': reader.take(32).hex()}
            elif version == 1:
                payload = {'data': reader.vector()}
            else:
                reader.fail(f'unsupported node data version {version}')
            target, targetname = reader.text(), reader.text()
            links = reader.integer()
            if not 0 <= links <= 6:
                reader.fail('node has more than six links or a negative link count')
            nodes.append(dict(index=index, position=position, flags=flags, version=version,
                              target=target, targetname=targetname,
                              links=[reader.unpack('2h') for _ in range(links)], **payload))
        indices = {node['index'] for node in nodes}
        if len(indices) != count or any(index < 0 or index >= LIMIT for index in indices):
            reader.fail('duplicate or invalid node index')
        for node in nodes:
            if any(index not in indices for _, index in node['links']):
                reader.fail(f'node {node["index"]} links to a missing node')
        graphs[kind] = nodes
    if sum(map(len, graphs.values())) > LIMIT:
        reader.fail(f'combined graphs exceed {LIMIT} nodes')
    return graphs


def entries(game, names):
    output = []
    maps = set()
    for name in sorted(n for n in names if n.startswith('maps/nodes/') and n.endswith('.nod')):
        mapname = PurePosixPath(name).stem
        if mapname in maps:
            raise ValueError(f'{name}: duplicate node map name {mapname}')
        maps.add(mapname)
        graphs = parse(name, game.find(name)[1])
        text = ['dk3_routes 1']
        for kind, nodes in graphs.items():
            text.append(f'graph {kind} {len(nodes)}')
            for node in nodes:
                position = ' '.join(format(v, '.9g') for v in node['position'])
                links = ' '.join(str(index) for _, index in node['links'])
                text.append(f'node {node["index"]} {node["flags"]} {position} '
                            f'{quoted(node["target"])} {quoted(node["targetname"])} {len(node["links"])} {links}')
        output.append((f'dk3/routes/{mapname}.cfg', ('\n'.join(text) + '\n').encode('utf-8')))
        output.append((f'dk3/routes/{mapname}.json', (json.dumps(graphs, sort_keys=True, indent=2) + '\n').encode()))
    return output
