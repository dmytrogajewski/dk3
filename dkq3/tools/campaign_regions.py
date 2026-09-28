# SPDX-License-Identifier: GPL-2.0-or-later
"""Local admission manifest; geometry reviews are pinned to both exact BSPs.

Unreviewed corridors retain authored landing travel. They are prefetched but never
silently promoted to continuous seams. This file contains no reference runtime.
"""
import campaign_connections

# Sequence 298, seam-vertex-evidence.json: shared corridor geometry and authored
# reciprocal brushes. Identity is a measured transform, not a spawn-name fallback.
REVIEWED = {
    'e1m1a': '2273864c32923737cbdadbe4bd9f2c875d8aac5f098f12b2cc0fde9a24665688',
    'e1m1b': '049d13238b73a0a85cd7116ffc98e6887b6f4fec054ac91818e90e3f183c51b4',
    'e1m1c': '5ffdd31e7f3d9304c2f4a3517e0bf8c2dafc19d5d9dfd84ae6eb38ab469ed7db',
}
SEAMS = {('e1m1a', 25): ('e1m1b', 449),
         ('e1m1b', 449): ('e1m1a', 25),
         ('e1m1b', 97): ('e1m1c', 410),
         ('e1m1c', 410): ('e1m1b', 97),
         ('e1m1b', 105): ('e1m1c', 411),
         ('e1m1c', 411): ('e1m1b', 105)}


def encode(document):
    rows = ['dk3_table 1']
    for name, entry in sorted(document['maps'].items()):
        rows.append(f'{{ map "{name}" sha256 "{entry["sha256"]}" }}')
    for edge in document['connections']:
        if edge['status'] == 'invalid':
            raise ValueError(f"invalid campaign exit: {edge['source']}:{edge['entity']}")
        source, destination = edge['source'], edge['destination']
        kind = 'cut' if edge['status'] == 'authored_cut' else 'landing'
        reviewed = SEAMS.get((source, edge['entity']))
        reciprocal = 0
        if reviewed and reviewed[0] == destination and all(
                document['maps'][name]['sha256'] == REVIEWED.get(name)
                for name in (source, destination)):
            reciprocal = reviewed[1]
            if reciprocal not in edge['return_exit_candidates']:
                raise ValueError('reviewed seam lost its reciprocal exit')
            kind = 'identity'
        rows.append(f'{{ source "{source}" destination "{destination}" exit "{edge["entity"]}" '
                    f'kind "{kind}" reciprocal "{reciprocal}" }}')
    return '\n'.join(rows) + '\n'


def build(package):
    return encode(campaign_connections.build(package))
