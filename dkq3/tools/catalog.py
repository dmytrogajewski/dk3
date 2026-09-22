"""Build menu metadata from the supplied maps, with no baked campaign text."""
import re
from pathlib import PurePosixPath

import dkbsp
import entities
from tables import quoted


def entries(game, names):
    records = ['dk3_maps 1']
    for name in sorted(n for n in names if n.startswith('maps/') and n.endswith('.bsp')):
        mapname = PurePosixPath(name).stem
        if not re.fullmatch('[a-z0-9_-]{1,40}', mapname):
            raise ValueError(f'{name}: unsupported map identifier')
        override = game.find(name[:-4] + '.ent')
        raw = override[1] if override else dkbsp.Bsp(game.find(name)[1]).entities().encode('latin1')
        parsed = [dict(entity) for entity in entities.parse(raw)]
        classes = {entity.get('classname', '') for entity in parsed}
        world = next((entity for entity in parsed if entity.get('classname') == 'worldspawn'), {})
        label = ' '.join(world.get('message', world.get('mapname', mapname)).replace('"', "'").split())[:96]
        modes = 1 if 'info_player_deathmatch' in classes or 'info_player_team1' in classes else 0
        if {'info_player_team1', 'info_player_team2', 'item_flag_team1', 'item_flag_team2', 'trigger_capture'} <= classes:
            # Retail CTF and deathtag deliberately share objective classnames.
            # The supplied episode/dt filename identifies the authored bomb
            # course; advertising every CTF arena as deathtag picks the wrong
            # map in the host menu despite having valid capture brushes.
            modes |= 4 if re.fullmatch(r'e[1-4]dt[0-9]+', mapname) else 2
        records.append(f'{quoted(mapname)} {modes} {quoted(label or mapname)}')
    return [('dk3/maps.cfg', ('\n'.join(records) + '\n').encode('utf-8'))]
