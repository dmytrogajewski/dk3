#!/usr/bin/env python3
"""Daikatana music and voice MP3s as Ogg Vorbis files ioquake3 finds under the names Daikatana asks for, with the music tables,
every reference to a converted name and the voice-to-subtitle linkage (specs/assets/ASSET-music-voice.md).

FRD: specs/frds/FRD-020-music-and-voice.md
"""
import argparse
import collections
import concurrent.futures
import json
import os
import struct
import sys
from dataclasses import dataclass

import convert_all
import dk2q3
import dkbsp
import dkm2md3
import dkpak
import entities
import media
import pk3
import pk3_paths

# ---------------------------------------------------------------------------------------------------------------------
# The music tables: Gold's `.vsc` and `.csv` (reference/dk-gold/user/csv.cpp, Lzari.cpp) and 1.3's `.json`.

# ENCRYPT_IsFileEncrypted requires these 4 bytes in a `.vsc` (user/Lzari.cpp:484-503), and ENCRYPT_DecodeToBuffer skips them and XORs
# every later byte with 0x96 (:349-383). The LZARI decoder of the same file serves only names without `.vsc`.
VSC_SIGNATURE, VSC_KEY = b'CVSC', 0x96
LINE_ENDS, SEPARATOR = (b'\n', b'\r'), b','


class VscError(ValueError):
    """A `.vsc` table without the `CVSC` signature: ENCRYPT_IsFileEncrypted refuses it."""


def read_vsc(data, name):
    """-> the CSV text of a `.vsc` table."""
    if data[:len(VSC_SIGNATURE)] != VSC_SIGNATURE:
        raise VscError(f'{name}: offset 0: expected {VSC_SIGNATURE!r}, found {data[:len(VSC_SIGNATURE)]!r}')
    return bytes(byte ^ VSC_KEY for byte in data[len(VSC_SIGNATURE):])


def csv_rows(text):
    """-> (first element, second element) of every line as Gold reads a table: CCSVFile::GetNextLine skips a line starting with a line
    end (csv.cpp:223-242), GetFirstElement reads up to a comma or a line end (:256-292), and GetNextElement skips one comma and reads the
    next (:294-315). Nothing is trimmed."""
    rows = []
    for line in text.splitlines(keepends=True):
        if line[:1] in LINE_ENDS or not line:
            continue
        body = line.rstrip(b'\r\n')
        first, _, rest = body.partition(SEPARATOR)
        rows.append((first.decode('latin1'), rest.partition(SEPARATOR)[0].decode('latin1')))
    return rows


# The fields 1.3's CL_StartMapMusic reads from each JSON row with CSV_GetSpecificElement (install/daikatana 0x546548, 0x5465ca:
# `.rodata` 0x8bc46e "mapname", 0x8c3fd0 "song").
JSON_MAP, JSON_SONG = 'mapname', 'song'


def json_rows(data):
    """-> (mapname, song) of every object of a 1.3 JSON table."""
    return [(str(row.get(JSON_MAP, '')), str(row.get(JSON_SONG, ''))) for row in json.loads(data)]


def map_song(rows, mapname):
    """-> the song of the first row whose first element equals the map name ignoring case (`_stricmp`, cl_view.cpp:750-761), or None."""
    return next((song for first, song in rows if first.lower() == mapname.lower()), None)


# ---------------------------------------------------------------------------------------------------------------------
# MPEG audio and Ogg Vorbis headers.

ID3V2 = struct.Struct('>3sBBB4s')          # "ID3", version, revision, flags, synchsafe size
ID3V2_FOOTER_FLAG, ID3V2_FOOTER_BYTES = 0x10, 10
MPEG_HEADER = struct.Struct('>I')
MPEG_SYNC, MPEG_SYNC_MASK = 0xFFE00000, 0xFFE00000
# Version bits 00, 10, 11: MPEG 2.5, 2 and 1; 01 is reserved. Layer bits 01 are Layer III.
MPEG_VERSIONS = {0: 25, 2: 2, 3: 1}
MPEG_LAYER3_BITS = 1
MPEG1_RATES, MONO_MODE = (44100, 48000, 32000), 3
MPEG_RATE_DIVISOR = {1: 1, 2: 2, 25: 4}
# Layer III bitrates in kbps by bitrate index, 1..14 (0 is free format, 15 is reserved), for MPEG 1 and for MPEG 2 and 2.5.
MPEG1_L3_BITRATES = (32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
MPEG2_L3_BITRATES = (8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160)


class NoFrame(ValueError):
    """An MP3 without an MPEG audio Layer III frame header after its ID3v2 tag or at the start of its WAVE `data` chunk."""


# Three corpus `.mp3` files are RIFF/WAVE containers of WAVE_FORMAT_MPEGLAYER3 (format tag 0x55, a 30-byte `fmt `, `fact`) whose `data`
# chunk holds the frames; ffmpeg reads them with its wav demuxer (specs/assets/ASSET-music-voice.md, "Source Layout").
MP3_CONTAINER, WAV_CONTAINER, WAVE_MPEGLAYER3 = 'mp3', 'wav', 0x55


@dataclass(frozen=True)
class MpegHeader:
    container: str      # mp3 (frames, optionally after ID3v2) or wav (frames in a WAVE_FORMAT_MPEGLAYER3 `data` chunk)
    version: int        # 1, 2 or 25 (MPEG 2.5)
    layer: int
    bitrate: int        # kbps
    rate: int
    channels: int
    offset: int         # of the first frame header


def _id3v2_bytes(data):
    """-> the bytes an ID3v2 tag at the start takes: header, synchsafe body and footer; 0 without a tag."""
    if len(data) < ID3V2.size or data[:3] != b'ID3':
        return 0
    _, _, _, flags, size = ID3V2.unpack_from(data)
    body = sum((byte & 0x7F) << (7 * (3 - i)) for i, byte in enumerate(size))
    return ID3V2.size + body + (ID3V2_FOOTER_BYTES if flags & ID3V2_FOOTER_FLAG else 0)


def _mpeg_fields(word):
    """-> the MpegHeader fields of a 32-bit frame header word, or None when it is not a Layer III header with valid indexes."""
    version = MPEG_VERSIONS.get((word >> 19) & 3)
    bitrate_index, rate_index = (word >> 12) & 15, (word >> 10) & 3
    if (word & MPEG_SYNC_MASK) != MPEG_SYNC or version is None or (word >> 17) & 3 != MPEG_LAYER3_BITS:
        return None
    if not 1 <= bitrate_index <= len(MPEG1_L3_BITRATES) or rate_index >= len(MPEG1_RATES):
        return None
    bitrates = MPEG1_L3_BITRATES if version == 1 else MPEG2_L3_BITRATES
    channels = 1 if (word >> 6) & 3 == MONO_MODE else 2
    return version, 3, bitrates[bitrate_index - 1], MPEG1_RATES[rate_index] // MPEG_RATE_DIVISOR[version], channels


def read_mpeg(data, name):
    """-> the MpegHeader of the first frame header: right after an ID3v2 tag (or at the start without one), or at the start of the `data`
    chunk of a RIFF/WAVE container of format tag 0x55."""
    container, offset = MP3_CONTAINER, _id3v2_bytes(data)
    if data[:4] == media.RIFF:
        try:
            wav = media.read_wav(data, name)
        except media.WavError as error:
            raise NoFrame(str(error)) from error
        if wav.format != WAVE_MPEGLAYER3:
            raise NoFrame(f'{name}: offset 0: a WAVE container of format tag {wav.format}, not MPEG Layer III ({WAVE_MPEGLAYER3})')
        container, offset = WAV_CONTAINER, wav.data_offset
    fields = _mpeg_fields(MPEG_HEADER.unpack_from(data, offset)[0]) if offset + MPEG_HEADER.size <= len(data) else None
    if fields is None:
        raise NoFrame(f'{name}: offset {offset}: no MPEG audio Layer III frame header')
    return MpegHeader(container, *fields, offset)


OGG_CAPTURE, OGG_PAGE_HEADER = b'OggS', 27        # the page header's last byte is the segment count
VORBIS_ID = struct.Struct('<B6sIBI')               # packet type 1, "vorbis", version, channels, rate


class NotOggVorbis(ValueError):
    """Bytes whose first Ogg page does not start with a Vorbis identification header."""


def read_vorbis(data, name):
    """-> (channels, rate) of the Vorbis identification header in the first Ogg page (the header ov_info reads, snd_codec_ogg.c:296-315)."""
    if data[:4] != OGG_CAPTURE or len(data) < OGG_PAGE_HEADER:
        raise NotOggVorbis(f'{name}: offset 0: no Ogg page')
    packet = OGG_PAGE_HEADER + data[OGG_PAGE_HEADER - 1]
    if len(data) < packet + VORBIS_ID.size:
        raise NotOggVorbis(f'{name}: offset {packet}: the first page ends before the identification header')
    kind, magic, _, channels, rate = VORBIS_ID.unpack_from(data, packet)
    if kind != 1 or magic != b'vorbis':
        raise NotOggVorbis(f'{name}: offset {packet}: not a Vorbis identification header')
    return channels, rate


OGG_GRANULE = struct.Struct('<q')                   # a page's granule position, at byte 6 of its header
OGG_GRANULE_AT, OGG_NO_GRANULE = 6, -1             # -1: no packet ends on the page


def ogg_frames(data, name):
    """-> the granule position of the last page on which a packet ends: the sample frames of a Vorbis stream that starts at 0, which
    ov_pcm_total returns and S_OGG_CodecOpenStream stores as the sample count (code/client/snd_codec_ogg.c:305-316)."""
    pos, frames = 0, None
    while pos + OGG_PAGE_HEADER <= len(data):
        if data[pos:pos + 4] != OGG_CAPTURE:
            raise NotOggVorbis(f'{name}: offset {pos}: no Ogg page')
        segments = data[pos + OGG_PAGE_HEADER - 1]
        granule = OGG_GRANULE.unpack_from(data, pos + OGG_GRANULE_AT)[0]
        frames = frames if granule == OGG_NO_GRANULE else granule
        pos += OGG_PAGE_HEADER + segments + sum(data[pos + OGG_PAGE_HEADER:pos + OGG_PAGE_HEADER + segments])
    if frames is None:
        raise NotOggVorbis(f'{name}: offset 0: no Ogg page with a granule position')
    return frames


# ---------------------------------------------------------------------------------------------------------------------
# Names: the package entry of a converted file and what ioquake3 finds for a requested name.

OGG_EXTENSION = '.ogg'
MUSIC_DIR = 'music/'
# code/qcommon/q_shared.h: every name buffer of the codec lookup holds MAX_QPATH bytes with its terminator.
MAX_QPATH = 64
# S_CodecInit registers Opus, Vorbis, then WAV, and S_CodecRegister pushes each on the head of the list (code/client/snd_codec.c:130-160),
# so S_CodecGetSound tries them in this order.
CODEC_ORDER = ('wav', 'ogg', 'opus')


def package_name(path):
    """-> the entry of a converted MP3: its corpus path in lower case with `.ogg` appended, so the codec lookup of the name Daikatana
    asks for (`<path>.mp3`) finds it (specs/assets/ASSET-music-voice.md, "Names")."""
    return path.lower() + OGG_EXTENSION


@dataclass(frozen=True)
class Lookup:
    entry: str          # the folded entry ioquake3 opens
    notice: bool        # S_CodecGetSound printed "WARNING: <name> not present, using <entry> instead"


def _extension(name):
    """COM_GetExtension (code/qcommon/q_shared.c:83-90): the text after the last dot when no `/` follows it."""
    dot, slash = name.rfind('.'), name.rfind('/')
    return name[dot + 1:] if dot >= 0 and slash < dot else ''


def ioq3_lookup(requested, entries):
    """-> the Lookup S_CodecGetSound (code/client/snd_codec.c:36-116) makes of `requested` against the folded package `entries`, or
    None when it prints "Failed to load/open sound". A name of MAX_QPATH or more is refused (S_FindName, snd_dma.c:268-271), and a
    fallback name is cut to MAX_QPATH - 1 characters by Com_sprintf."""
    if len(requested) >= MAX_QPATH:
        return None
    local, ext, skipped = requested, _extension(requested).lower(), None
    if ext in CODEC_ORDER:
        if pk3_paths.fs_key(local) in entries:
            return Lookup(pk3_paths.fs_key(local), False)
        local, skipped = requested[:requested.rfind('.')], ext
    for codec in (codec for codec in CODEC_ORDER if codec != skipped):
        alternative = f'{local}.{codec}'[:MAX_QPATH - 1]
        if pk3_paths.fs_key(alternative) in entries:
            return Lookup(pk3_paths.fs_key(alternative), skipped is not None)
    return None


# ---------------------------------------------------------------------------------------------------------------------
# References: every place a table, map or engine names a converted file, with the names Gold asks the file system for.

@dataclass(frozen=True)
class Reference:
    kind: str           # table, entity or engine
    source: str         # where the name is written
    key: str            # the table column, entity key or constant
    value: str          # as written
    candidates: tuple   # the names asked for, in order


MUSIC_NAME = 'music/{}.mp3'         # S_StartMusic (reference/dk-gold/base/Audio/DkAudioEngine_Miles/S_Calls.cpp:1192); 1.3 `music/%s.mp3`
SOUNDS_DIR = 'sounds/'              # S_LoadSound's prefix (S_Calls.cpp:292); 1.3's PlaySidekickMP3 also tries it (install/changes.txt:399-402)
MP3_EXTENSION = '.mp3'
# Entity keys whose value is started as an MP3 (S_StartMP3 opens `data/<value>`, S_Calls.cpp:1145-1148): trigger_changemusic's `path`
# (dlls/world/Triggers.cpp:5485, :5441) as written, and a trigger's `mp3` (:627, :456-466), which PlaySidekickMP3 plays for sidekick
# names and 1.3 also looks for below `sounds/`.
PATH_KEY, MP3_KEY = 'path', 'mp3'
# The worldspawn key 1.3 plays for a map without a table row (install/changes.txt:51; CL_StartMapMusic, install/daikatana 0x5464b8).
MUSICTRACK_KEY = 'musictrack'
# Keys a trigger or speaker registers as a WAV sound under `sounds/` (Triggers.cpp:617, :1058; gstate->SoundIndex); a value ending in
# `.mp3` names a voice line the stock projection asks for as `sounds/<value>.wav`.
SOUND_KEYS = ('sound', 'sound1')
# Names the engine code starts, each with its source.
ENGINE_REFERENCES = (
    ('reference/dk-gold/base/dk_/dk_menu.cpp:27,972', MUSIC_NAME.format('menu_01')),
    ('reference/dk-gold/base/dk_/dk_menu.cpp:28,974', MUSIC_NAME.format('menu_02')),
    ('reference/dk-gold/base/dk_/dk_menu_sound.cpp:26,290', MUSIC_NAME.format('DM2_Titans')),
    ('install/daikatana .rodata "music/e2d.mp3"', 'music/e2d.mp3'),
    ('install/daikatana .rodata "music/deadly.mp3"', 'music/deadly.mp3'),
    ('reference/dk-gold/dlls/world/Triggers.cpp:2470', 'sounds/voices/hiro/sid_h_01b.mp3'),
    ('reference/dk-gold/dlls/world/Triggers.cpp:2479', 'sounds/voices/hiro/sid_h_02c.mp3'),
    ('reference/dk-gold/dlls/world/Triggers.cpp:2488,2839', 'sounds/voices/hiro/sid_h_03b.mp3'),
    ('reference/dk-gold/dlls/world/Triggers.cpp:2827', 'sounds/voices/mikiko/sid_m_27.mp3'),
    ('reference/dk-gold/dlls/world/Triggers.cpp:2833', 'sounds/voices/superfly/sid_s_27.mp3'),
)


def table_references(label, rows):
    """-> a reference per table row: the song as S_StartMusic asks for it."""
    return [Reference('table', f'{label}:{mapname}', 'song', song, (MUSIC_NAME.format(song),)) for mapname, song in rows]


def entity_references(label, parsed):
    """-> the references of one entity text (entities.parse): `musictrack`, MP3 keys (as written, then under `sounds/`) and sound keys
    ending in `.mp3` (under `sounds/`)."""
    found = []
    for pairs in parsed:
        source = f"{label}:{entities.value(pairs, 'classname')}"
        for key, value in pairs:
            name = key.lower()
            if name == MUSICTRACK_KEY:
                found.append(Reference('entity', source, key, value, (MUSIC_NAME.format(value),)))
            elif name in (PATH_KEY, MP3_KEY):
                prefixed = () if name == PATH_KEY or pk3_paths.fs_key(value).startswith(SOUNDS_DIR) else (value, SOUNDS_DIR + value)
                found.append(Reference('entity', source, key, value, (value,) + prefixed))
            elif name in SOUND_KEYS and value.lower().endswith(MP3_EXTENSION):
                found.append(Reference('entity', source, key, value, (value, SOUNDS_DIR + value)))
    return found


def engine_references():
    return [Reference('engine', source, 'constant', name, (name,)) for source, name in ENGINE_REFERENCES]


def resolve(reference, entries):
    """-> (the candidate name, the entry) of the first candidate ioquake3 finds among the folded `entries`, or None."""
    for candidate in reference.candidates:
        found = ioq3_lookup(candidate, entries)
        if found is not None:
            return candidate, found.entry
    return None


# ---------------------------------------------------------------------------------------------------------------------
# ffmpeg: one encode per MP3 and one decode per file of the sweep, stdin to stdout, with fixed settings
# (specs/assets/ASSET-music-voice.md, "ffmpeg").

FFMPEG_INPUT = ('-nostdin', '-hide_banner', '-loglevel', 'error', '-threads', '1')
MP3_DECODER = 'mp3float'
VORBIS_ENCODER, VORBIS_QUALITY, OGG_FORMAT = 'libvorbis', '4', 'ogg'
# No stream metadata; `-fflags +bitexact` makes the Ogg muxer number the stream 0 instead of a random serial and drops the version
# from the vendor strings, `-flags:a +bitexact` does the same for the encoder.
ENCODE_OUTPUT = ('-map', '0:a:0', '-map_metadata', '-1', '-fflags', '+bitexact', '-flags:a', '+bitexact', '-c:a', VORBIS_ENCODER,
                 '-q:a', VORBIS_QUALITY)
DECODE_OUTPUT = ('-map', '0:a:0', '-f', 's16le', '-c:a', 'pcm_s16le')
STDIN, STDOUT = 'pipe:0', 'pipe:1'


def encode_command(program, container, channels, rate):
    """-> the argv encoding an MP3 in `container` (mp3 or wav) on stdin, decoded with the forced `mp3float`, to Ogg Vorbis of `channels` at
    `rate` on stdout."""
    return [program, *FFMPEG_INPUT, '-f', container, '-c:a', MP3_DECODER, '-i', STDIN, *ENCODE_OUTPUT, '-ac', str(channels),
            '-ar', str(rate), '-f', OGG_FORMAT, STDOUT]


def decode_command(program, container, decoder):
    """-> the argv decoding `container` on stdin with the forced `decoder` to raw signed 16-bit little-endian PCM on stdout."""
    return [program, *FFMPEG_INPUT, '-f', container, '-c:a', decoder, '-i', STDIN, *DECODE_OUTPUT, STDOUT]


# ---------------------------------------------------------------------------------------------------------------------
# Subtitles: S_CheckForMP3Text (S_Calls.cpp:1303-1321) opens `subtitles/<name after the last '/'>.txt` for every started MP3.

SUBTITLES_DIR, SUBTITLE_SUFFIX = 'subtitles/', '.txt'


def subtitle_name(started):
    """-> the subtitle file of a started MP3 name: the text after its last `/`, `.mp3` included, below `subtitles/` with `.txt`."""
    return f"{SUBTITLES_DIR}{started[started.rfind('/') + 1:]}{SUBTITLE_SUFFIX}"


@dataclass(frozen=True)
class Linkage:
    voices_with: list       # voice files whose subtitle exists
    voices_without: list    # voice files without one
    orphans: list           # subtitles no voice file's name leads to
    shared: dict            # a basename (folded) several voice files have -> those files, which share one subtitle


def link_subtitles(voices, subtitles):
    """-> the Linkage of voice file paths and subtitle entries, names compared as the file system compares them."""
    present = {pk3_paths.fs_key(name) for name in subtitles}
    wanted = {pk3_paths.fs_key(subtitle_name(voice)) for voice in voices}
    by_base = collections.defaultdict(list)
    for voice in voices:
        by_base[pk3_paths.fs_key(voice[voice.rfind('/') + 1:])].append(voice)
    return Linkage([v for v in voices if pk3_paths.fs_key(subtitle_name(v)) in present], [v for v in voices if pk3_paths.fs_key(subtitle_name(v)) not in present],
                   sorted(name for name in subtitles if pk3_paths.fs_key(name) not in wanted),
                   {base: files for base, files in sorted(by_base.items()) if len(files) > 1})


# ---------------------------------------------------------------------------------------------------------------------
# Corpus driver: `zig build assets-music-voice`.

PREFIX = 'music-voice:'
MAX_JOBS = 4                        # spec R7: at most 4 ffmpeg jobs
# The dkguard caps of one ffmpeg run: the longest corpus track (music/e4e.mp3, 371 s of 44.1 kHz stereo) is the largest encode
# (specs/assets/ASSET-music-voice.md, "Corpus Statistics").
FFMPEG_JOB_MEM, FFMPEG_JOB_TIMEOUT = '512M', '300'
MUSIC, VOICE = 'music', 'voice'
CONVERTED, OVERRIDDEN, FAILED, LOST = media.CONVERTED, media.OVERRIDDEN, media.FAILED, media.LOST
# The longest requested name whose `.ogg` fallback still fits MAX_QPATH with its terminator (ioq3_lookup).
MAX_NAME = MAX_QPATH - len(OGG_EXTENSION)
# The tables 1.3's CCSVFile::OpenFile tries for `music/music.csv`, in order: `.json` (install/daikatana 0x890039-0x8900a7), `.vsc`
# (0x890121-0x890130), then the name itself. Gold tries `.vsc`, then `.csv` (reference/dk-gold/user/csv.cpp:87-138).
TABLES = (('json', 'music/music.json'), ('vsc', 'music/music.vsc'), ('csv', 'music/music.csv'))
MAPS_DIR, BSP, ENT = 'maps/', '.bsp', '.ent'


def kind_of(name):
    return MUSIC if pk3_paths.fs_key(name).startswith(MUSIC_DIR) else VOICE


def convert_copy(name, origin, data, program, run):
    """-> (report row, the Ogg bytes or None) of one copy: its header, its encode and the check of the Ogg it gave. An MP3 without a
    frame header is lost; every other error is a failed row."""
    row = dict(name=name, archive=origin, kind=kind_of(name), entry=package_name(name))
    try:
        header = read_mpeg(data, name)
        row['source'] = dict(bytes=len(data), container=header.container, version=header.version, layer=header.layer, bitrate=header.bitrate, rate=header.rate,
                             channels=header.channels, offset=header.offset)
        if len(name) >= MAX_NAME:
            raise ValueError(f'{name}: {len(name)} characters; ioquake3 finds names of at most {MAX_NAME - 1} under their `.ogg`')
        ogg = run(encode_command(program, header.container, header.channels, header.rate), data)
        channels, rate = read_vorbis(ogg, row['entry'])
        if (channels, rate) != (header.channels, header.rate):
            raise NotOggVorbis(f"{row['entry']}: {channels} channels at {rate} Hz, the source has {header.channels} at {header.rate}")
    except NoFrame as error:
        return dict(row, status=LOST, error=str(error)), None
    except Exception as error:  # every per-file error is reported by name; none may stop the other files unreported
        return dict(row, status=FAILED, error=f'{type(error).__name__}: {error}'), None
    return dict(row, status=CONVERTED, ogg=dict(bytes=len(ogg), channels=channels, rate=rate)), ogg


def find_copy(root, archives, name):
    """-> (origin, bytes) of the first copy of `name` in the 1.3 search order: the loose file, then each archive; or None."""
    if os.path.isfile(os.path.join(root, name)):
        return name, media.read_copy(root, archives, name, name)
    return next(((archive, pak.read(name)) for archive, pak in archives if name in pak.entries), None)


def read_tables(root, archives):
    """-> {json, vsc, csv: {origin, rows} or None} and the name 1.3 reads, the first present of TABLES."""
    readers = dict(json=json_rows, vsc=lambda data, name: csv_rows(read_vsc(data, name)), csv=lambda data, name: csv_rows(data))
    tables = {}
    for key, name in TABLES:
        found = find_copy(root, archives, name)
        rows = None if found is None else (readers[key](found[1]) if key == 'json' else readers[key](found[1], name))
        tables[key] = None if found is None else dict(origin=found[0], rows=[list(row) for row in rows])
    used = next((name for key, name in TABLES if tables[key] is not None), None)
    return tables, used


def table_differences(tables):
    """-> (rows only the JSON table has, rows only the VSC table has, [map, VSC song, JSON song] of a map both name differently)."""
    json_table, vsc_table = [[tuple(row) for row in (tables[key] or dict(rows=[]))['rows']] for key in ('json', 'vsc')]
    only = lambda ours, theirs: [list(row) for row in ours if map_song(theirs, row[0]) is None]  # noqa: E731
    differ = [[m, map_song(vsc_table, m), s] for m, s in json_table if map_song(vsc_table, m) not in (None, s)]
    return only(json_table, vsc_table), only(vsc_table, json_table), differ


def map_references(game):
    """-> the entity references of every map in the 1.3 search order: its first `maps/<name>.bsp` and its `.ent` override."""
    found = []
    for name in sorted(convert_all.discover(game)):
        origin, data = game.find(f'{MAPS_DIR}{name}{BSP}')
        text, source = dk2q3.entity_text(dkbsp.Bsp(data, origin).raw('entities'), game.find(f'{MAPS_DIR}{name}{ENT}'))
        found += entity_references(origin if source == 'lump' else source, entities.parse(text))
    return found


def references(game, tables, entries):
    """-> the report rows of every reference, resolved against the folded package `entries`: each table's rows, the maps, the engine."""
    refs = [ref for key, name in TABLES if tables[key] for ref in table_references(name, tables[key]['rows'])]
    refs += map_references(game) + engine_references()
    rows = []
    for ref in refs:
        resolved = resolve(ref, entries)
        rows.append(dict(kind=ref.kind, source=ref.source, key=ref.key, value=ref.value, candidates=list(ref.candidates),
                         resolved=resolved[0] if resolved else None, entry=resolved[1] if resolved else None))
    return rows


def subtitle_entries(root, archives):
    """-> every subtitle file name: loose files below `subtitles/` and archive entries, sorted and unique."""
    loose = os.path.join(root, SUBTITLES_DIR)
    names = {SUBTITLES_DIR + name for name in os.listdir(loose)} if os.path.isdir(loose) else set()
    return sorted(names | {entry for _, pak in archives for entry in pak.entries if pk3_paths.fs_key(entry).startswith(SUBTITLES_DIR)})


def document(rows, version, tables, used, reference_rows, linkage, subtitles, expected):
    """-> the report: ffmpeg, settings, totals, every file, both tables and their differences, references and subtitles."""
    status = collections.Counter(row['status'] for row in rows)
    packaged = collections.Counter(row['kind'] for row in rows if row['status'] == CONVERTED)
    only_json, only_vsc, differ = table_differences(tables)
    unresolved = sorted({row['candidates'][0] for row in reference_rows if row['entry'] is None})
    longest = max((row['name'] for row in rows), key=len, default='')
    return dict(ffmpeg=version, encode=encode_command('ffmpeg', '<container>', '<channels>', '<rate>'), entries=len(rows),
                packaged=dict(music=packaged[MUSIC], voice=packaged[VOICE]), converted=status[CONVERTED] + status[OVERRIDDEN],
                overridden=status[OVERRIDDEN], lost=sorted(r['name'] for r in rows if r['status'] == LOST),
                failed=sorted(r['name'] for r in rows if r['status'] == FAILED), files=rows, longest_name=dict(name=longest, length=len(longest)),
                tables=dict(tables, used=used, only_json=only_json, only_vsc=only_vsc, differ=differ),
                references=dict(total=len(reference_rows), resolved=len(reference_rows) - sum(r['entry'] is None for r in reference_rows),
                                unresolved=unresolved, expected_missing=sorted(expected), rows=reference_rows),
                subtitles=dict(entries=len(subtitles), voices_with=len(linkage.voices_with), voices_without=len(linkage.voices_without),
                               orphans=linkage.orphans, shared=linkage.shared, voices_without_subtitle=linkage.voices_without))


def summary(report):
    """-> the lines printed and written as the text report."""
    lines = [f"{PREFIX} {r['name']} ({r['archive']}): {r['status']}, {r['kind']} {r['entry']}"
             + (f": {r['error']}" if 'error' in r else f": {r['source']['rate']} Hz, {r['source']['channels']} ch, {r['source']['bitrate']} kbps")
             for r in report['files']]
    tables, refs, subs = report['tables'], report['references'], report['subtitles']
    counts = ', '.join(f"{key} {len(tables[key]['rows']) if tables[key] else 'absent'}" for key, _ in TABLES)
    lines.append(f"{PREFIX} table {tables['used']} read by 1.3; rows {counts}; only json {len(tables['only_json'])}, "
                 f"only vsc {len(tables['only_vsc'])}, differ {len(tables['differ'])}")
    lines.append(f"{PREFIX} references {refs['total']}, resolved {refs['resolved']}, unresolved {len(refs['unresolved'])}: "
                 + ', '.join(refs['unresolved']))
    lines.append(f"{PREFIX} subtitles {subs['entries']}: {subs['voices_with']} voice files with a subtitle, {subs['voices_without']} without, "
                 f"{len(subs['orphans'])} orphan subtitles, {len(subs['shared'])} shared basenames")
    lines.append(f"{PREFIX} longest name {report['longest_name']['name']} ({report['longest_name']['length']} characters)")
    lines.append(f"{PREFIX} {report['ffmpeg']}")
    lines.append(f"{PREFIX} encode {' '.join(report['encode'])}")
    lines.append(f"{PREFIX} total: {report['entries']} entries, {report['packaged']['music']} music and {report['packaged']['voice']} voice "
                 f"files packaged, {report['converted']} converted ({report['overridden']} overridden), {len(report['lost'])} lost, "
                 f"{len(report['failed'])} failed")
    return lines


def failures(report, expected_orphans):
    """-> the failure lines: failed and lost files, unexpected or unmet missing references, a different orphan count."""
    found = [f"{r['name']} ({r['archive']}): {r['error']}" for r in report['files'] if r['status'] in (FAILED, LOST)]
    refs = report['references']
    found += [f'unresolved reference {name}' for name in refs['unresolved'] if name not in refs['expected_missing']]

    orphans = len(report['subtitles']['orphans'])
    return found + ([f'{orphans} orphan subtitles, expected {expected_orphans}'] if expected_orphans is not None and orphans != expected_orphans else [])


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--data', required=True, help='game directory (zig build -DDK_DATA): loose files and pak0.pak-pak9.pak')
    ap.add_argument('--pak5', help='pak5.pak extracted from pak5.zip, searched before the numbered archives')
    ap.add_argument('--ffmpeg', required=True, help='the ffmpeg program that encodes every MP3')
    ap.add_argument('--ffmpeg-major', required=True, type=int, help='the recorded ffmpeg major version')
    ap.add_argument('--dkguard', required=True, help='dkguard, which runs every ffmpeg under its caps')
    ap.add_argument('--jobs', required=True, type=int, choices=range(1, MAX_JOBS + 1), metavar=f'1-{MAX_JOBS}', help='ffmpeg runs at once')
    ap.add_argument('--music-pk3', required=True, help='pk3 to write: every converted music/ file')
    ap.add_argument('--voice-pk3', required=True, help='pk3 to write: every other converted file')
    ap.add_argument('--report', required=True, help='JSON report to write')
    ap.add_argument('--summary', required=True, help='text report to write: the lines printed on stdout')
    ap.add_argument('--expected-missing', action='append', default=[], metavar='NAME',
                    help='a referenced name no converted file resolves, reported as a loss; repeatable')
    ap.add_argument('--expected-orphan-subtitles', type=int, help='the subtitles no voice file name leads to')
    return ap.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    pak5 = dkpak.Pak(args.pak5) if args.pak5 else None
    run = media.guarded_runner(args.dkguard, FFMPEG_JOB_MEM, FFMPEG_JOB_TIMEOUT)
    try:
        answers = [run([args.ffmpeg, *query], b'').decode('utf-8', 'replace') for query in media.FFMPEG_QUERIES]
        version = media.check_ffmpeg(*answers, args.ffmpeg_major, {MP3_DECODER}, encoder=VORBIS_ENCODER)
    except media.FfmpegError as error:
        print(f'{PREFIX} FAIL {error}', file=sys.stderr)
        return 1
    with dk2q3.GameDir(args.data) as game:
        archives = dkm2md3.search_order(game, pak5)
        copies = dkm2md3.discover(game.root, archives, suffix=MP3_EXTENSION)
        keys = [(name, origin) for name, origins in sorted(copies.items()) for origin in origins]
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            results = list(pool.map(lambda key: convert_copy(*key, media.read_copy(game.root, archives, *key), args.ffmpeg, run), keys))
        rows = media.table(copies, [row for row, _ in results])
        packaged = {row['entry']: ogg for row, (_, ogg) in zip(rows, results) if row['status'] == CONVERTED}
        tables, used = read_tables(game.root, archives)
        reference_rows = references(game, tables, set(packaged))
        subtitles = subtitle_entries(game.root, archives)
    voices = [row['name'] for row in rows if row['status'] == CONVERTED and row['kind'] == VOICE]
    report = document(rows, version, tables, used, reference_rows, link_subtitles(voices, subtitles), subtitles, set(args.expected_missing))
    lines = summary(report)
    for path, text in ((args.report, json.dumps(report, indent=1, sort_keys=True) + '\n'), (args.summary, ''.join(line + '\n' for line in lines))):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            f.write(text)
    print('\n'.join(lines))
    failed = failures(report, args.expected_orphan_subtitles)
    for line in failed:
        print(f'{PREFIX} FAIL {line}', file=sys.stderr)
    if failed:
        return 1
    for kind, path in ((MUSIC, args.music_pk3), (VOICE, args.voice_pk3)):
        pk3.write(path, sorted((entry, ogg) for entry, ogg in packaged.items() if kind_of(entry) == kind))
    return 0


if __name__ == '__main__':
    sys.exit(main())
