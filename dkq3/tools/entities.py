"""The Daikatana entity text of a map: the bytes every loader reads, the entities Gold's game parser builds from them, and
their census counts (specs/assets/ASSET-entities.md).

FRD: specs/frds/FRD-015-entity-census-verbatim-preservation-and-stock-module-projection.md
"""
import collections
import re
from typing import NamedTuple

import dkbsp

NUL = b'\0'
OPEN, CLOSE, CLASSNAME = '{', '}', 'classname'
MAX_PAIRS = 100              # Sent_EpairEdict's tpair[100] (dk_sent.cpp:207, 231-234)


class EntityTextError(ValueError):
    """Entity text Gold's SpawnEntities stops on with gi.Error or Sys_Error (dk_sent.cpp:219-260, 1101-1104)."""


def text(raw):
    """-> the entity text of a lump or `.ent` file: its bytes before the first NUL, the C string ioquake3 (`R_LoadEntities`
    strcpy, botlib strlen), Gold (`map_entitystring`, cmodel.cpp:67, 646-656) and 1.3 (`Hunk_Alloc(length + 1)`) read."""
    return raw.split(NUL, 1)[0]


def lump(raw):
    """-> the converted BSP's entity lump: the text and one terminating NUL, inside the lump length."""
    return text(raw) + NUL


def parse(raw):
    """-> every entity of the text as its (key, value) pairs in text order, read like Gold's SpawnEntities: COM_Parse
    tokens (dk_shared.cpp:546), a `{` opens an entity, Sent_EpairEdict pairs keys and values with trailing key spaces
    trimmed. Keys are kept as written (Gold also drops `_` keys but `_color` and renames `light`; the census counts the text)."""
    source, found, at = text(raw).decode('latin1'), [], 0
    while True:
        token, at = dkbsp.com_parse(source, at)
        if at is None:
            return found
        if not token.startswith(OPEN):
            raise EntityTextError(f"entity {len(found)}: found {token!r}, expected '{OPEN}'")
        pairs, at = _pairs(source, at, len(found))
        found.append(pairs)


def _pairs(source, at, index):
    pairs = []
    while True:
        key, at = dkbsp.com_parse(source, at)
        if key.startswith(CLOSE):
            return pairs, at
        if at is None:
            raise EntityTextError(f'entity {index}: EOF without closing brace')
        if len(pairs) >= MAX_PAIRS:
            raise EntityTextError(f'entity {index}: more than {MAX_PAIRS} pairs')
        data, at = dkbsp.com_parse(source, at)
        if at is None:
            raise EntityTextError(f'entity {index}: EOF without closing brace')
        if data.startswith(CLOSE):
            raise EntityTextError(f'entity {index}: closing brace without data')
        pairs.append((key.rstrip(' '), data))


def value(pairs, key):
    """Sent_GetValue (dk_sent.cpp:307-319): the value of the first pair whose key matches ignoring case, else None."""
    return next((data for name, data in pairs if name.lower() == key.lower()), None)


def census(parsed):
    """-> (entities per classname, occurrences per key) of parsed entities; an entity without a classname is an
    EntityTextError, as SpawnEntities stops with gi.Error("Entity %i has no classname") (dk_sent.cpp:1131-1133)."""
    classnames, keys = collections.Counter(), collections.Counter()
    for index, pairs in enumerate(parsed):
        classname = value(pairs, CLASSNAME)
        if classname is None:
            raise EntityTextError(f'entity {index}: no classname')
        classnames[classname] += 1
        keys.update(key for key, _ in pairs)
    return classnames, keys


# ------------------------------------------------------------------------------------------------------ stock projection
# Limits of the stock game module a projection must stay within (code/qcommon/q_shared.h:1082-1097, code/game/g_local.h:34).
MAX_SOUNDS, ENTITYNUM_MAX_NORMAL, MAX_CLIENTS, BODY_QUEUE_SIZE = 256, 1022, 64, 8
SOUND_LIMIT = MAX_SOUNDS - 1          # G_FindConfigstringIndex hands out 1..MAX_SOUNDS-1, else G_Error (g_utils.c:107)
LIVE_LIMIT = ENTITYNUM_MAX_NORMAL - MAX_CLIENTS - BODY_QUEUE_SIZE   # G_Spawn starts at MAX_CLIENTS (g_utils.c:389-421)
SUBMODEL = re.compile(r'\*(\d+)$')    # SV_SetBrushModel needs '*' (sv_game.c:111-120), CM_InlineModel a model (cm_load.c:703-705)
# Stock sound names are game paths; Gold loads a sound as "sounds/%s" (reference/dk-gold/base/Audio/DkAudioEngine_Miles/
# S_Calls.cpp:292), and every corpus WAV is below sounds/ (specs/bugs/BUG-projected-speakers-name-sound-instead-of-sounds.md).
SOUND_DIR = 'sounds/'
INITIAL = ('spawnflags', '1')         # SelectInitialSpawnPoint takes the first spot with spawnflags 1 (g_client.c:308-330)
SPAWN_TARGET = 'info_player_deathmatch'
# Gold's single-player start (com_SelectSpawnPoint, com_sub.cpp:3183-3232), then the other player spots in this order.
START, FALLBACK_ORDER = 'info_player_start', ('info_player_deathmatch', 'info_player_coop', 'info_player_team1',
                                              'info_player_team2')
# Sounds the stock spawn functions register for a projected class (g_mover.c, g_trigger.c G_SoundIndex literals).
STOCK_SOUNDS = {'func_door': ('sound/movers/doors/dr1_strt.wav', 'sound/movers/doors/dr1_end.wav'),
                'func_plat': ('sound/movers/plats/pt1_strt.wav', 'sound/movers/plats/pt1_end.wav'),
                'func_button': ('sound/movers/switches/butn2.wav',), 'trigger_hurt': ('sound/world/electro.wav',),
                'trigger_teleport': ('sound/world/jumppad.wav',)}
FREED = ('light', 'info_null')        # SP_light and SP_info_null free themselves at spawn (g_misc.c:44-45, 65-66)


class UnknownClassname(ValueError):
    """A classname without a projection rule: every classname is projected or dropped with a recorded reason."""


class StockLimitError(ValueError):
    """A projection the stock game module cannot spawn: more sounds or live entities than its limits."""


class Mapped(NamedTuple):
    """A Daikatana class projected to stock `target`: `keys` copied when present; `defaults` written from the text or,
    when absent, the Daikatana default; `positive` likewise when absent or not positive; `fixed` always written; `flags`
    (Daikatana bit, stock bit) pairs and `set_flags` form spawnflags; `needs` is 'model', 'sound', 'destination' or
    'origin'; `text` names the stock semantics."""
    target: str
    keys: tuple = ()
    defaults: tuple = ()
    positive: tuple = ()
    fixed: tuple = ()
    flags: tuple = ()
    set_flags: int = 0
    needs: str = ''
    text: str = ''


class Loss(NamedTuple):
    """A Daikatana class the stock projection drops: `reason` names it in reports, `text` gives the gameplay impact and owner."""
    reason: str
    text: str


class Projection(NamedTuple):
    """The stock projection of one entity text: the lump, entities projected per classname, entities dropped per
    (classname, reason), the initial spot (classname, entity index, origin; classname and index None for the fallback),
    and the sounds and live entities the stock game module would allocate."""
    lump: bytes
    mapped: collections.Counter
    dropped: collections.Counter
    spawn: tuple
    sounds: int
    live: int


SPOT = Mapped(SPAWN_TARGET, keys=('origin', 'angle'), needs='origin',
              text='stock player spot (SP_info_player_deathmatch, g_client.c:37-56); the Gold single-player start is the one '
                   'initial spot')
LIGHT = Mapped('light', keys=('origin', 'light', '_color'),
               text='stock light, freed at spawn (SP_light, g_misc.c:65-66); a compile-time light in Quake III')
SPEAKER = dict(keys=('origin', 'targetname'), needs='sound')
RULES = {
    'worldspawn': Mapped('worldspawn', keys=('message', 'gridsize'),
                         text='SP_worldspawn reads message (g_spawn.c:564-585); R_LoadEntities reads gridsize (tr_bsp.c:1759)'),
    START: SPOT, 'info_player_deathmatch': SPOT, 'info_player_coop': SPOT, 'info_player_team1': SPOT,
    'info_player_team2': SPOT,
    'info_player_intermission': Mapped('info_player_intermission', keys=('origin', 'angle'), needs='origin',
                                       text='stock intermission point (g_client.c); its target view is dropped'),
    'light': LIGHT, 'light_e1': LIGHT, 'light_e2': LIGHT, 'light_e3': LIGHT, 'light_e4': LIGHT, 'light_flame': LIGHT,
    'light_flare': LIGHT, 'light_spot': LIGHT, 'light_strobe': LIGHT, 'light_walltorch': LIGHT,
    'info_null': Mapped('info_null', keys=('origin', 'targetname'), text='stock info_null (g_misc.c:44-45)'),
    'info_not_null': Mapped('info_notnull', keys=('origin', 'targetname'), text='stock info_notnull (g_misc.c:53-56)'),
    'func_door': Mapped('func_door', keys=('model', 'angle', 'target', 'targetname', 'team', 'lip', 'dmg', 'health'),
                        defaults=(('speed', '100'), ('wait', '3')), flags=((1, 1),), needs='model',
                        text='stock func_door (SP_func_door, g_mover.c:932-1000); START_OPEN 1 is stock START_OPEN 1'),
    'func_plat': Mapped('func_plat', keys=('model', 'targetname', 'height', 'dmg'), defaults=(('speed', '100'),),
                        needs='model', text='stock func_plat (SP_func_plat, g_mover.c:1118-1160)'),
    'func_button': Mapped('func_button', keys=('model', 'angle', 'target', 'speed', 'wait', 'lip', 'health'),
                          needs='model', text='stock func_button (SP_func_button, g_mover.c:1200-1240)'),
    'trigger_multiple': Mapped('trigger_multiple', keys=('model', 'target', 'targetname'), positive=(('wait', '0.2'),),
                               needs='model', text='stock trigger_multiple (g_trigger.c:94-101)'),
    'trigger_once': Mapped('trigger_multiple', keys=('model', 'target', 'targetname'), fixed=(('wait', '-1'),),
                           needs='model', text='stock trigger_multiple that fires once (multi_trigger, g_trigger.c:45-75)'),
    'trigger_hurt': Mapped('trigger_hurt', keys=('model', 'targetname', 'dmg'), flags=((1, 2), (2, 1)), needs='model',
                           text='stock trigger_hurt (g_trigger.c:334, 383-400): ALLOW_TOGGLE 1 is TOGGLE 2, START_DISABLED 2 '
                                'is START_OFF 1'),
    'trigger_teleport': Mapped('trigger_teleport', keys=('model', 'target'), needs='destination',
                               text='stock trigger_teleport (g_trigger.c:271-320) aimed at a projected destination'),
    'info_teleport_destination': Mapped('misc_teleporter_dest', keys=('origin', 'angle', 'targetname'),
                                        text='stock misc_teleporter_dest, a teleport target (g_misc.c)'),
    'target_speaker': Mapped('target_speaker', flags=((1, 1), (2, 2)), text='stock target_speaker (g_target.c:169, 198-240) '
                             'with noise sounds/<sound or sound1>; LOOPED_ON 1 and LOOPED_OFF 2 kept', **SPEAKER),
    'sound_ambient': Mapped('target_speaker', set_flags=1, text='stock looped-on target_speaker (g_target.c:169, 198-240) '
                            'with noise sounds/<sound or sound1>', **SPEAKER),
}
EXACT_LOSSES = {
    'trigger_push': Loss('push', 'stock trigger_push aims at a target and prints "G_PickTarget called with NULL targetname" '
                                 'without one (AimAtTarget, g_trigger.c); Daikatana pushes along angle and speed. No push in '
                                 'acceptance runs (Step 27)'),
}
PREFIX_LOSSES = (
    ('monster_', Loss('monster', 'Daikatana AI creature; the stock module has no monsters. No enemies in acceptance runs '
                                 '(Steps 33, 34, 43)')),
    ('item_', Loss('pickup', 'Daikatana pickup; stock bg_itemlist names other items. No pickups (Steps 31, 32, 42)')),
    ('weapon_', Loss('pickup', 'Daikatana weapon pickup; stock bg_itemlist names other items (Steps 31, 42)')),
    ('ammo_', Loss('pickup', 'Daikatana ammunition; stock bg_itemlist names other items (Steps 31, 42)')),
    ('fish_', Loss('critter', 'ambient creature with AI (Steps 33, 44)')),
    ('e_', Loss('critter', 'ambient creature with AI (Steps 33, 44)')),
    ('deco_', Loss('decoration', 'decoinfo model; not drawn in acceptance runs (Step 26)')),
    ('effect_', Loss('effect', 'particle or weather effect; not drawn (Step 30)')),
    ('sfx_', Loss('effect', 'particle effect; not drawn (Step 30)')),
    ('misc_', Loss('misc', 'Daikatana prop with game logic (drug box, health tree, fountain, portal) (Steps 26, 32)')),
    ('func_', Loss('brush', 'Daikatana brush entity without a stock counterpart; its brush model is neither drawn nor solid '
                            'in acceptance runs (Step 26)')),
    ('trigger_', Loss('trigger', 'Daikatana game-logic trigger (level change, script, sidekick, secret, counter) '
                                 '(Steps 26, 36, 39)')),
    ('target_', Loss('target', 'Daikatana target (effect, earthquake, monster spawner, laser, light ramp) (Steps 26, 30)')),
    ('info_', Loss('info', 'AI script, camera or sidekick start point (Steps 33, 35, 36)')),
    ('path_', Loss('path', 'train path corner (Step 26)')),
    ('NPC', Loss('sidekick', 'sidekick navigation marker or trigger (Step 35)')),
    ('node_', Loss('node', 'AI path node (Step 33)')),
    ('view', Loss('debug', 'editor debugging entity (viewthing, view_rotate); no gameplay')),
)


def rule(classname):
    """-> the Mapped rule or Loss of a classname; UnknownClassname when neither exists."""
    found = RULES.get(classname) or EXACT_LOSSES.get(classname)
    found = found or next((loss for prefix, loss in PREFIX_LOSSES if classname.startswith(prefix)), None)
    if found is None:
        raise UnknownClassname(f'{classname}: no projection rule')
    return found


def _origin(pairs):
    """-> True when the origin is three numbers, as G_ParseField's sscanf "%f %f %f" needs (g_spawn.c)."""
    try:
        return len([float(v) for v in (value(pairs, 'origin') or '').split()]) == 3
    except ValueError:
        return False


def initial_spawn(parsed):
    """-> (classname, index, origin) of the spot the projection marks initial, or None: Gold's single-player start (the
    first info_player_start without a targetname, else the first), then the first spot of FALLBACK_ORDER."""
    usable = [(i, pairs) for i, pairs in enumerate(parsed) if _origin(pairs)]
    named = lambda name: [(i, p) for i, p in usable if (value(p, CLASSNAME) or '').lower() == name]  # noqa: E731
    starts = named(START)
    groups = ([s for s in starts if value(s[1], 'targetname') is None], starts, *map(named, FALLBACK_ORDER))
    i, pairs = next((group[0] for group in groups if group), (None, None))
    return None if i is None else (value(pairs, CLASSNAME), i, value(pairs, 'origin'))


def _flags(pairs, mapped):
    try:
        dk = int(value(pairs, 'spawnflags') or 0)
    except ValueError:
        dk = 0
    return mapped.set_flags | sum(stock for bit, stock in mapped.flags if dk & bit)


def _translate(pairs, mapped, context):
    """-> the stock pairs of one entity, or the drop reason of an unmet need."""
    submodels, destinations = context
    model = SUBMODEL.match(value(pairs, 'model') or '')
    sound = value(pairs, 'sound') or value(pairs, 'sound1')
    unmet = {'model': not (model and 1 <= int(model.group(1)) < submodels), 'sound': not sound, 'origin': not _origin(pairs),
             'destination': value(pairs, 'target') not in destinations or not (model and 1 <= int(model.group(1)) < submodels)}
    if mapped.needs and unmet[mapped.needs]:
        return 'model' if mapped.needs == 'destination' and value(pairs, 'target') in destinations else mapped.needs
    out = [(CLASSNAME, mapped.target)] + [(k, value(pairs, k)) for k in mapped.keys if value(pairs, k) is not None]
    if mapped.needs == 'sound':
        out.append(('noise', SOUND_DIR + sound.replace('\\', '/').lstrip('/')))
    out += list(mapped.fixed) + [(k, value(pairs, k) or v) for k, v in mapped.defaults]
    out += [(k, value(pairs, k) if _positive(value(pairs, k)) else v) for k, v in mapped.positive]
    flags = _flags(pairs, mapped)
    return out + [('spawnflags', str(flags))] if flags else out


def _positive(text):
    try:
        return float(text) > 0
    except (TypeError, ValueError):
        return False


def project(verbatim, submodels, fallback):
    """-> the Projection of a preserved entity lump for a map with `submodels` models (world included); `fallback` is the
    origin of the initial spot when the text has no usable player spot. Raises UnknownClassname or StockLimitError."""
    parsed, out = parse(verbatim), []
    census(parsed)
    destinations = {value(p, 'targetname') for p in parsed if value(p, CLASSNAME) == 'info_teleport_destination'}
    spawn, mapped, dropped = initial_spawn(parsed), collections.Counter(), collections.Counter()
    for index, pairs in enumerate(parsed):
        classname = value(pairs, CLASSNAME)
        try:
            found = rule(classname) if index or classname == 'worldspawn' else Loss('worldspawn', '')
        except UnknownClassname as error:
            raise UnknownClassname(f'entity {index}: {error}') from None
        result = found.reason if isinstance(found, Loss) else _translate(pairs, found, (submodels, destinations))
        if classname == 'worldspawn' and index:
            result = 'worldspawn'
        if isinstance(result, str):
            dropped[(classname, result)] += 1
            continue
        mapped[classname] += 1
        out.append(result + [INITIAL] if spawn and index == spawn[1] else result)
    if spawn is None:
        spawn = (None, None, ' '.join(f'{v:g}' for v in fallback))
        out.append([(CLASSNAME, SPAWN_TARGET), ('origin', spawn[2]), INITIAL])
    return _checked(out, mapped, dropped, spawn)


def _checked(out, mapped, dropped, spawn):
    stock = [dict(pairs) for pairs in out[1:]]
    sounds = {e['noise'] for e in stock if 'noise' in e} | {s for e in stock for s in STOCK_SOUNDS.get(e[CLASSNAME], ())}
    auto = sum(1 for e in stock if e[CLASSNAME] in ('func_door', 'func_plat') and 'targetname' not in e)
    live = sum(1 for e in stock if e[CLASSNAME] not in FREED) + auto
    if len(sounds) > SOUND_LIMIT:
        raise StockLimitError(f'{len(sounds)} sounds, the stock game module registers at most {SOUND_LIMIT}')
    if live > LIVE_LIMIT:
        raise StockLimitError(f'{live} live entities, the stock game module spawns at most {LIVE_LIMIT}')
    body = ''.join('{\n' + ''.join(f'"{k}" "{v}"\n' for k, v in pairs) + '}\n' for pairs in out)
    return Projection(body.encode('latin1') + NUL, mapped, dropped, spawn, len(sounds), live)


def lumps(raw, submodels, fallback):
    """-> (verbatim lump, Projection) in one pass: the projection is made from the preserved lump, never from `raw`."""
    verbatim = lump(raw)
    return verbatim, project(verbatim, submodels, fallback)
