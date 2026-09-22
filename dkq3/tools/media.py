#!/usr/bin/env python3
"""Daikatana sound effects as WAV files ioquake3 reads, with their loop points and a sidecar per sound
(specs/assets/ASSET-sound.md).

FRD: specs/frds/FRD-019-sound-effects.md
"""
import argparse
import collections
import concurrent.futures
import json
import os
import re
import struct
import subprocess
import sys
from dataclasses import asdict, dataclass

import dk2q3
import dkm2md3
import dkpak
import pk3

RIFF, WAVE = b'RIFF', b'WAVE'
RIFF_HEADER = struct.Struct('<4sI4s')
CHUNK_HEADER = struct.Struct('<4sI')
FMT_FIELDS = struct.Struct('<HHIIHH')      # format tag, channels, rate, byte rate, block align, bits (WAVEFORMAT)
FMT_EXTENSION = struct.Struct('<HH')       # cbSize, then an IMA ADPCM fmt's samples per block
FACT = struct.Struct('<I')                 # the decoded length in sample frames
SAMPLES_PER_BLOCK_BYTES = 2                # cbSize counts the bytes after it: an IMA ADPCM fmt holds wSamplesPerBlock
CUE_COUNT = struct.Struct('<I')
CUE_POINT = struct.Struct('<IIIIII')       # dwName, dwPosition, fccChunk, dwChunkStart, dwBlockStart, dwSampleOffset
ADTL, LIST_TYPE_BYTES = b'adtl', 4         # a `LIST` chunk's type, then its sub-chunks
LTXT = struct.Struct('<II4s')              # an `ltxt` sub-chunk's cue id, sample length and purpose
SMPL_HEADER = struct.Struct('<IIIIIIIII')  # manufacturer, product, period, MIDI note, pitch, SMPTE format and offset, loops, extra
SMPL_LOOP = struct.Struct('<IIIIII')       # cue id, type, start, end, fraction, play count
SMPL_LOOP_COUNT = 7                        # the index of the loop count in SMPL_HEADER


class WavError(ValueError):
    """A sound no loader can read. Names the sound and the byte offset of the fault."""

    def __init__(self, name, offset, detail):
        super().__init__(f'{name}: offset {offset}: {detail}')


class NotRiffWave(WavError):
    """The first 12 bytes are not `RIFF`, a size and `WAVE`."""


class MissingChunk(WavError):
    """No `fmt ` or no `data` chunk: GetWavinfo prints "Missing fmt chunk"/"Missing data chunk" (snd_mem.cpp:245-249, :288-292),
    ioquake3 `Couldn't find "fmt"`/`"data"` (snd_codec_wav.c:143, :174)."""


class ShortFmt(WavError):
    """A `fmt ` chunk shorter than the 16 bytes of WAVEFORMAT: both loaders read its fields past the chunk."""


class NegativeChunkLength(WavError):
    """A chunk length of 2^31 or more before `fmt ` and `data` are found: ioquake3 reads it as a negative int, warns "Negative chunk
    length" and stops (snd_codec_wav.c:67-72); GetWavinfo's FindNextChunk stops too (snd_mem.cpp:191-196)."""


NEGATIVE = 1 << 31


@dataclass(frozen=True)
class CuePoint:
    """One point of a `cue ` chunk. GetWavinfo takes the first point's sample offset as loopstart (snd_mem.cpp:263-268)."""
    ident: int
    position: int
    chunk: str
    chunk_start: int
    block_start: int
    sample_offset: int


@dataclass(frozen=True)
class Region:
    """An `ltxt` entry of a `LIST adtl` chunk. GetWavinfo reads a `mark` purpose as the loop length (snd_mem.cpp:269-279)."""
    cue_id: int
    sample_length: int
    purpose: str


@dataclass(frozen=True)
class SmplLoop:
    """A loop of a `smpl` chunk. No Gold loader reads it; the sidecar keeps it."""
    cue_id: int
    type: int
    start: int
    end: int
    fraction: int
    play_count: int


@dataclass(frozen=True)
class Chunk:
    ident: str
    offset: int         # of the chunk header in the file
    length: int         # the header's length field


@dataclass(frozen=True)
class Wav:
    chunks: tuple
    format: int
    channels: int
    rate: int
    byte_rate: int
    block_align: int
    bits: int
    data_offset: int
    data_length: int    # as the chunk header declares it
    data_available: int     # the data bytes the file holds, at most data_length
    samples_per_block: int = None   # from a `fmt ` extension whose cbSize holds it (IMA ADPCM)
    fact_frames: int = None         # from the first `fact` chunk
    cue_points: tuple = ()          # CuePoints of the first `cue ` chunk
    regions: tuple = ()             # Regions of every `LIST adtl` chunk, in file order
    smpl_loops: tuple = ()          # SmplLoops of the first `smpl` chunk


def read_wav(data, name):
    """-> the Wav of a RIFF/WAVE file: every chunk in order, the `fmt ` fields and the `data` span."""
    if len(data) < RIFF_HEADER.size or data[:4] != RIFF or data[8:12] != WAVE:
        raise NotRiffWave(name, 0, f'expected {RIFF!r}, a size and {WAVE!r} in the first {RIFF_HEADER.size} bytes')
    chunks, pos = [], RIFF_HEADER.size
    while pos + CHUNK_HEADER.size <= len(data):
        ident, length = CHUNK_HEADER.unpack_from(data, pos)
        if length >= NEGATIVE and not {'fmt ', 'data'} <= {c.ident for c in chunks}:
            raise NegativeChunkLength(name, pos, f'{ident!r} length {length} is negative as a signed int')
        chunks.append(Chunk(ident.decode('latin1'), pos, length))
        pos += CHUNK_HEADER.size + length + (length & 1)
    fmt = _first(chunks, 'fmt ', name, len(data))
    if fmt.length < FMT_FIELDS.size:
        raise ShortFmt(name, fmt.offset, f"'fmt ' chunk of {fmt.length} bytes; WAVEFORMAT needs {FMT_FIELDS.size}")
    body = _first(chunks, 'data', name, len(data))
    fields = FMT_FIELDS.unpack_from(data, fmt.offset + CHUNK_HEADER.size)
    data_offset = body.offset + CHUNK_HEADER.size
    extended = fmt.length >= FMT_FIELDS.size + FMT_EXTENSION.size
    cb_size, per_block = FMT_EXTENSION.unpack_from(data, fmt.offset + CHUNK_HEADER.size + FMT_FIELDS.size) if extended else (0, None)
    fact = next((c for c in chunks if c.ident == 'fact' and c.length >= FACT.size), None)
    return Wav(tuple(chunks), *fields, data_offset, body.length, max(0, min(body.length, len(data) - data_offset)),
               per_block if cb_size >= SAMPLES_PER_BLOCK_BYTES else None,
               FACT.unpack_from(data, fact.offset + CHUNK_HEADER.size)[0] if fact else None, _cue_points(data, chunks),
               _regions(data, chunks), _smpl_loops(data, chunks))


def _first(chunks, ident, name, end):
    """-> the first chunk named `ident`, or MissingChunk at the end of the walk."""
    found = next((c for c in chunks if c.ident == ident), None)
    if found is None:
        raise MissingChunk(name, end, f'no {ident!r} chunk')
    return found


def _body(data, chunk):
    """-> (start, end) of a chunk's body, cut at the end of the file."""
    start = chunk.offset + CHUNK_HEADER.size
    return start, min(start + chunk.length, len(data))


def _cue_points(data, chunks):
    """-> the CuePoints of the first `cue ` chunk: as many of its declared points as the chunk and the file hold."""
    cue = next((c for c in chunks if c.ident == 'cue '), None)
    if cue is None:
        return ()
    start, end = _body(data, cue)
    if end - start < CUE_COUNT.size:
        return ()
    fits = (end - start - CUE_COUNT.size) // CUE_POINT.size
    points = (CUE_POINT.unpack_from(data, start + CUE_COUNT.size + i * CUE_POINT.size)
              for i in range(min(CUE_COUNT.unpack_from(data, start)[0], fits)))
    return tuple(CuePoint(ident, position, chunk.to_bytes(4, 'little').decode('latin1'), chunk_start, block_start, offset)
                 for ident, position, chunk, chunk_start, block_start, offset in points)


def _subchunks(data, chunk, skip):
    """-> (ident, body start, body end) of each sub-chunk after the first `skip` body bytes, as far as the body and the file hold."""
    start, end = _body(data, chunk)
    pos, found = start + skip, []
    while pos + CHUNK_HEADER.size <= end:
        ident, length = CHUNK_HEADER.unpack_from(data, pos)
        body = pos + CHUNK_HEADER.size
        found.append((ident.decode('latin1'), body, min(body + length, end)))
        pos = body + length + (length & 1)
    return found


def _regions(data, chunks):
    """-> the Regions of every `ltxt` entry of every `LIST adtl` chunk, in file order."""
    found = []
    for chunk in chunks:
        list_type = data[chunk.offset + CHUNK_HEADER.size:chunk.offset + CHUNK_HEADER.size + LIST_TYPE_BYTES]
        if chunk.ident != 'LIST' or list_type != ADTL:
            continue
        for ident, body, end in _subchunks(data, chunk, LIST_TYPE_BYTES):
            if ident == 'ltxt' and end - body >= LTXT.size:
                cue_id, length, purpose = LTXT.unpack_from(data, body)
                found.append(Region(cue_id, length, purpose.decode('latin1')))
    return tuple(found)


def _smpl_loops(data, chunks):
    """-> the SmplLoops of the first `smpl` chunk: as many of its declared loops as the chunk and the file hold."""
    sampler = next((c for c in chunks if c.ident == 'smpl'), None)
    if sampler is None:
        return ()
    start, end = _body(data, sampler)
    if end - start < SMPL_HEADER.size:
        return ()
    fits = (end - start - SMPL_HEADER.size) // SMPL_LOOP.size
    count = min(SMPL_HEADER.unpack_from(data, start)[SMPL_LOOP_COUNT], fits)
    return tuple(SmplLoop(*SMPL_LOOP.unpack_from(data, start + SMPL_HEADER.size + i * SMPL_LOOP.size)) for i in range(count))


# ---------------------------------------------------------------------------------------------------------------------
# What ioquake3's WAV reader makes of a file.

@dataclass(frozen=True)
class Ioq3Read:
    """What S_ReadRIFFHeader (../ioq3/code/client/snd_codec_wav.c:131-180) makes of a file: its snd_info_t fields and the offset
    S_WAV_CodecLoad reads `size` bytes from, or the error it prints."""
    channels: int = 0
    rate: int = 0
    width: int = 0
    data_offset: int = 0
    size: int = 0
    samples: int = 0
    error: str = None
    warnings: tuple = ()


IOQ3_NEGATIVE = "Negative chunk length"            # snd_codec_wav.c:69-72
IOQ3_NO_FMT = "Couldn't find \"fmt\" chunk"        # snd_codec_wav.c:142-144
IOQ3_NO_DATA = "Couldn't find \"data\" chunk"      # snd_codec_wav.c:174
# No engine message: FS_Read returns fewer bytes and FGetLittleShort/FGetLittleLong leave the fields undefined (:32-52).
IOQ3_SHORT_READ = 'the file ends inside the fmt fields, which FS_Read leaves undefined'
# No engine message: info->samples = size / width / channels divides by zero and the client stops with SIGFPE (:177).
IOQ3_ZERO_CHANNELS = 'zero channels: the sample count divides by zero'
IOQ3_LOW_BITS = "Less than 8 bit sound is not supported"      # snd_codec_wav.c:155-158
IOQ3_MIN_BITS = 8


def ioq3_read(data):
    """-> the Ioq3Read of a WAV file."""
    warnings = []
    pos = RIFF_HEADER.size                      # FS_Read(dump, 12): the RIFF header is skipped unchecked (:141)
    fmt_length, pos = _ioq3_find(data, pos, b'fmt ', warnings)
    if fmt_length < 0:
        return Ioq3Read(error=IOQ3_NO_FMT, warnings=tuple(warnings))
    if pos + FMT_FIELDS.size > len(data):
        return Ioq3Read(error=IOQ3_SHORT_READ, warnings=tuple(warnings))
    _, channels, rate, _, _, bits = FMT_FIELDS.unpack_from(data, pos)
    pos += FMT_FIELDS.size
    if bits < IOQ3_MIN_BITS:                    # the format tag was read and discarded (:148); only the bits are checked
        return Ioq3Read(error=IOQ3_LOW_BITS, warnings=tuple(warnings))
    if fmt_length > FMT_FIELDS.size:            # the rest of the chunk, without its pad byte (:165-169)
        pos += fmt_length - FMT_FIELDS.size
    size, pos = _ioq3_find(data, pos, b'data', warnings)
    if size < 0:
        return Ioq3Read(error=IOQ3_NO_DATA, warnings=tuple(warnings))
    if channels == 0:
        return Ioq3Read(error=IOQ3_ZERO_CHANNELS, warnings=tuple(warnings))
    width = bits // 8
    return Ioq3Read(channels, rate, width, pos, size, size // width // channels, warnings=tuple(warnings))


def _ioq3_find(data, pos, ident, warnings):
    """S_FindRIFFChunk (snd_codec_wav.c:84-100): -> (length, position after the header) of the next chunk named `ident`, each other
    chunk skipped with PAD(len, 2), or (-1, position) at the end of the file or after a length S_ReadChunkInfo reads as negative,
    which adds its warning to `warnings` (:59-76)."""
    while pos + CHUNK_HEADER.size <= len(data):
        name, length = CHUNK_HEADER.unpack_from(data, pos)
        pos += CHUNK_HEADER.size
        if length >= NEGATIVE:
            warnings.append(IOQ3_NEGATIVE)
            return -1, pos
        if name == ident:
            return length, pos
        pos += length + (length & 1)
    return -1, pos


# ---------------------------------------------------------------------------------------------------------------------
# Gold's loop: GetWavinfo (reference/dk-1.2/shadow/base/Audio/DkAudioEngine_Mix/snd_mem.cpp:223-301).

NO_LOOP = -1        # loopstart without a cue chunk (snd_mem.cpp:283)
# data_p += 32 from the `cue ` chunk header, past the length, the point count and 20 bytes of the first point, to its sample
# offset, read without checking the count or the chunk length (snd_mem.cpp:263-268).
CUE_LOOPSTART_OFFSET = 32
GOLD_LONG = struct.Struct('<i')             # GetLittleLong (snd_mem.cpp:163-172)
# The first LIST after the cue: bytes 28-31 from its header compared with "mark", then the long at byte 24 as the loop's sample
# count, "not a proper parse, but it works with cooledit" (snd_mem.cpp:269-279). In an `adtl` LIST these are an `ltxt` entry's
# purpose and sample length.
MARK = b'mark'
MARK_PURPOSE_OFFSET, MARK_LENGTH_OFFSET = 28, 24
# What GetWavinfo and S_LoadSound do with a file.
GOLD_LOADED = 'loaded'
GOLD_BAD_LOOP_LENGTH = 'bad loop length'    # Com_Error(ERR_DROP, "Sound %s has a bad loop length") (snd_mem.cpp:294-297)
# A format tag other than 1 prints "Microsoft PCM format only" and returns channels 0 (snd_mem.cpp:252-257), so S_LoadSound gives
# no sound (:119-124).
GOLD_PCM_ONLY = 'Microsoft PCM format only'
GOLD_PCM = 1
# S_LoadSound refuses a sound whose channel count is not 1 after GetWavinfo: "%s is a stereo sample" (snd_mem.cpp:119-124), as
# the Miles engine does (reference/dk-gold/base/Audio/DkAudioEngine_Miles/S_Calls.cpp:305-310).
GOLD_STEREO = 'stereo sample'
GOLD_MONO = 1
# S_LoadSound returns NULL for a file above 512,000 bytes before GetWavinfo runs: "NELNO: Hack until new sound stuff is checked
# in" (snd_mem.cpp:100-108).
GOLD_TOO_LARGE = 'larger than 512000 bytes'
MIX_SIZE_LIMIT = 512000


@dataclass(frozen=True)
class GoldInfo:
    """The wavinfo_t fields GetWavinfo fills that the loop depends on: loopstart, and samples, the loop's end."""
    loopstart: int
    samples: int
    result: str = GOLD_LOADED


def getwavinfo(data, name):
    """-> the GoldInfo GetWavinfo gives a file."""
    wav = read_wav(data, name)
    # A refused format stops GetWavinfo before its loop. The loop is still what these chunks give the converted PCM file, whose
    # data samples are the decoded frames.
    pcm = wav.format == GOLD_PCM
    # S_LoadSound checks the file length before GetWavinfo; the format stops GetWavinfo; a bad loop length drops inside it;
    # S_LoadSound checks the channels after it.
    result = (GOLD_TOO_LARGE if len(data) > MIX_SIZE_LIMIT else GOLD_PCM_ONLY if not pcm else
              GOLD_LOADED if wav.channels == GOLD_MONO else GOLD_STEREO)
    samples = wav.data_length // (wav.bits // 8) if pcm else (wav.fact_frames or 0)
    cue = next((c for c in wav.chunks if c.ident == 'cue '), None)
    if cue is None:
        return GoldInfo(NO_LOOP, samples, result)
    loopstart = GOLD_LONG.unpack_from(data, cue.offset + CUE_LOOPSTART_OFFSET)[0]
    listed = next((c for c in wav.chunks[wav.chunks.index(cue) + 1:] if c.ident == 'LIST'), None)
    purpose = data[listed.offset + MARK_PURPOSE_OFFSET:listed.offset + MARK_PURPOSE_OFFSET + len(MARK)] if listed else None
    if purpose == MARK:
        end = loopstart + GOLD_LONG.unpack_from(data, listed.offset + MARK_LENGTH_OFFSET)[0]
        return GoldInfo(loopstart, end, GOLD_BAD_LOOP_LENGTH if result == GOLD_LOADED and samples < end else result)
    return GoldInfo(loopstart, samples, result)


# ---------------------------------------------------------------------------------------------------------------------
# The conversion branch of a file (specs/assets/ASSET-sound.md, "Mapping Rules").

COPY, REPAIR, TRANSCODE, LOSS = 'copy', 'repair', 'transcode', 'loss'


@dataclass(frozen=True)
class Plan:
    """What the conversion does with a file: `branch`, and why when it is not a copy."""
    branch: str
    reason: str = None
    decoder: str = None     # the ffmpeg decoder of a transcode


# ioquake3 reads only these PCM depths as written: ResampleSfx takes width 2 as signed 16-bit and every other width as unsigned
# 8-bit (../ioq3/code/client/snd_mem.c:141-145), and the reader discards the format tag (snd_codec_wav.c:148).
IOQ3_PCM_BITS = (8, 16)
# The mixer skips a sound of 0 channels or less and interleaves only 2; any other count is mixed as mono
# (../ioq3/code/client/snd_mix.c:266, :276-277, :301, :337). A conversion keeps the channel count, so no branch fixes another.
IOQ3_CHANNELS = (1, 2)
# (format tag, bits) -> the ffmpeg decoder that reads it, names as `ffmpeg -hide_banner -decoders` of ffmpeg 7.1.5 lists them:
# IMA ADPCM (17), Microsoft ADPCM (2), A-law (6), mu-law (7), IEEE float (3) and PCM (1) deeper than ioquake3 reads.
FFMPEG_DECODERS = {(17, 4): 'adpcm_ima_wav', (2, 4): 'adpcm_ms', (6, 8): 'pcm_alaw', (7, 8): 'pcm_mulaw', (3, 32): 'pcm_f32le',
                   (3, 64): 'pcm_f64le', (1, 24): 'pcm_s24le', (1, 32): 'pcm_s32le'}


def classify(data, name):
    """-> the Plan of a WAV file: a transcode for a format or depth ioquake3 misreads, a copy when its reader model finds the
    chunk walk's format and data span, a repair otherwise, and a loss for a file no loader can read."""
    try:
        wav = read_wav(data, name)
    except WavError as error:
        return Plan(LOSS, str(error))
    if wav.channels not in IOQ3_CHANNELS:
        return Plan(LOSS, f'{wav.channels} channels: the ioquake3 mixer plays {IOQ3_CHANNELS} channels')
    if wav.rate == 0:
        return Plan(LOSS, 'rate 0: ResampleSfx divides the sample count by rate / mixer rate (snd_mem.c:125-127)')
    if wav.format != GOLD_PCM or wav.bits not in IOQ3_PCM_BITS:
        decoder = FFMPEG_DECODERS.get((wav.format, wav.bits))
        if decoder is None:
            return Plan(LOSS, f'format tag {wav.format} with {wav.bits} bits: no known ffmpeg decoder')
        return Plan(TRANSCODE, f'format tag {wav.format} with {wav.bits} bits: ioquake3 reads only {IOQ3_PCM_BITS} bit PCM', decoder)
    read = ioq3_read(data)
    if read.error is not None:
        return Plan(REPAIR, read.error)
    found = (read.channels, read.rate, read.width, read.data_offset, read.size)
    walked = (wav.channels, wav.rate, wav.bits // 8, wav.data_offset, wav.data_available)
    if found != walked:
        return Plan(REPAIR, f'ioquake3 reads (channels, rate, width, data offset, size) {found}; the file holds {walked}')
    return Plan(COPY)


# ---------------------------------------------------------------------------------------------------------------------
# The file a repair or a transcode writes.

def _chunk(ident, body):
    """-> a chunk: `ident`, the body length, the body and a pad byte after an odd body."""
    return ident + struct.pack('<I', len(body)) + body + b'\0' * (len(body) & 1)


def write_pcm(source, name, pcm, bits):
    """-> `source` rewritten as PCM of `bits` holding the samples `pcm`: RIFF, WAVE, a 16-byte `fmt ` with the source's channels and
    rate first, then the source's other chunks in their order with `data` replaced and `fact` dropped. `cue `, `LIST`, `smpl` and
    every other chunk keep their bytes, so GetWavinfo finds the same loop, and ioquake3's reader finds `data` after `fmt `."""
    wav = read_wav(source, name)
    align = wav.channels * bits // 8
    parts = [_chunk(b'fmt ', FMT_FIELDS.pack(GOLD_PCM, wav.channels, wav.rate, wav.rate * align, align, bits))]
    for chunk in wav.chunks:
        if chunk.ident == 'data':
            parts.append(_chunk(b'data', pcm))
        elif chunk.ident not in ('fmt ', 'fact'):
            parts.append(source[chunk.offset:chunk.offset + CHUNK_HEADER.size + chunk.length + (chunk.length & 1)])
    body = WAVE + b''.join(parts)
    return RIFF + struct.pack('<I', len(body)) + body


def repair(source, name):
    """-> a PCM file ioquake3 reads as written: the whole frames of `data` the file holds, a frame being channels * bits / 8 bytes as
    ioquake3 reads it (snd_codec_wav.c:177), rewritten by write_pcm at the source's depth."""
    wav = read_wav(source, name)
    frame = wav.channels * wav.bits // 8
    whole = wav.data_available // frame * frame
    return write_pcm(source, name, source[wav.data_offset:wav.data_offset + whole], wav.bits)


# ---------------------------------------------------------------------------------------------------------------------
# ffmpeg: one decode per sound, stdin to stdout, with fixed settings (specs/assets/ASSET-sound.md, "ffmpeg").

FFMPEG_INPUT = ('-nostdin', '-hide_banner', '-loglevel', 'error', '-threads', '1', '-f', 'wav')
FFMPEG_ENCODER = 'pcm_s16le'        # every transcode writes signed 16-bit little-endian PCM
FFMPEG_OUTPUT = ('-map', '0:a:0', '-map_metadata', '-1', '-bitexact', '-flags:a', '+bitexact', '-c:a', FFMPEG_ENCODER)
FFMPEG_STDIN, FFMPEG_STDOUT, FFMPEG_RAW = 'pipe:0', 'pipe:1', 's16le'
# What the step asks ffmpeg before converting, in check_ffmpeg's argument order: the version, the encoders, the decoders.
FFMPEG_QUERIES = (('-version',), ('-hide_banner', '-encoders'), ('-hide_banner', '-decoders'))


def ffmpeg_command(program, decoder, channels, rate):
    """-> the argv decoding a WAV on stdin with `decoder`, forced so the codec check covers it, to raw signed 16-bit little-endian
    PCM of `channels` at `rate` on stdout: one thread, no metadata, bit-exact flags."""
    return [program, *FFMPEG_INPUT, '-c:a', decoder, '-i', FFMPEG_STDIN, *FFMPEG_OUTPUT, '-ac', str(channels), '-ar', str(rate),
            '-f', FFMPEG_RAW, FFMPEG_STDOUT]


class FfmpegError(RuntimeError):
    """ffmpeg is not the recorded version, lacks a needed codec, or failed on a sound."""


FFMPEG_VERSION = re.compile(r'^ffmpeg version (\d+)\.')    # the first line of `ffmpeg -version`


def ffmpeg_major(text):
    """-> the major version from the first line of `ffmpeg -version` output; FfmpegError naming that line otherwise."""
    first = (text.splitlines() or [''])[0]
    match = FFMPEG_VERSION.match(first)
    if match is None:
        raise FfmpegError(f'ffmpeg -version printed {first!r}, not "ffmpeg version <major>.<minor>"')
    return int(match.group(1))


FFMPEG_LISTING_SEPARATOR = '------'     # ends the legend of `ffmpeg -hide_banner -encoders` and `-decoders`


def ffmpeg_codecs(listing):
    """-> the codec names of an `ffmpeg -hide_banner -encoders` or `-decoders` listing: the second field of each line after the
    legend's separator."""
    lines = listing.splitlines()
    start = next((i + 1 for i, line in enumerate(lines) if line.strip() == FFMPEG_LISTING_SEPARATOR), len(lines))
    return {line.split()[1] for line in lines[start:] if len(line.split()) > 1}


def check_ffmpeg(version_text, encoders, decoders, major, needed, encoder=FFMPEG_ENCODER):
    """-> the first line of `ffmpeg -version`, after checking that the major version is the recorded `major`; FfmpegError
    otherwise. `encoders` and `decoders` are the listings; `needed` names the decoders the plans use and `encoder` the encoder they
    write (pcm_s16le here, libvorbis for music_voice.py)."""
    found = ffmpeg_major(version_text)
    first = version_text.splitlines()[0]
    if found != major:
        raise FfmpegError(f'ffmpeg major {found} ({first}) differs from the recorded major {major}')
    if encoder not in ffmpeg_codecs(encoders):
        raise FfmpegError(f'ffmpeg ({first}) lacks the {encoder} encoder every transcode writes')
    missing = sorted(set(needed) - ffmpeg_codecs(decoders))
    if missing:
        raise FfmpegError(f'ffmpeg ({first}) lacks the decoders {", ".join(missing)} the plans need')
    return first


FFMPEG_BITS, PCM16_BYTES = 16, 2    # the depth a transcode writes, and its bytes per sample


def transcode(source, name, plan, program, run):
    """-> (the PCM file, the decoded frames cut): `run(argv, stdin)` decodes `source` with `plan.decoder` through ffmpeg_command and
    returns raw 16-bit frames. ffmpeg decodes whole blocks, so the frames are cut to the `fact` count when the file has one."""
    wav = read_wav(source, name)
    raw = run(ffmpeg_command(program, plan.decoder, wav.channels, wav.rate), source)
    frame = wav.channels * PCM16_BYTES
    decoded = len(raw) // frame
    frames = decoded if wav.fact_frames is None else wav.fact_frames
    if decoded < frames:
        raise FfmpegError(f'{name}: ffmpeg decoded {decoded} frames, fewer than fact {frames}')
    return write_pcm(source, name, raw[:frames * frame], FFMPEG_BITS), decoded - frames


STDERR_TAIL = 2000      # the characters of a failed run's standard error an FfmpegError quotes


def guarded_runner(dkguard, mem, timeout):
    """-> run(argv, stdin): `dkguard --mem <mem> --timeout <timeout> -- <argv>` with `stdin` on its standard input, returning its
    standard output, so every ffmpeg runs under its own dkguard (spec R7); FfmpegError naming the command, dkguard's exit status and
    the end of the standard error when it does not exit 0."""
    def run(argv, stdin):
        proc = subprocess.run([dkguard, '--mem', mem, '--timeout', timeout, '--', *argv], input=stdin, capture_output=True,
                              check=False)
        if proc.returncode != 0:
            detail = proc.stderr.decode('utf-8', 'replace')[-STDERR_TAIL:]
            raise FfmpegError(f'{" ".join(argv)}: dkguard exit {proc.returncode}: {detail}')
        return proc.stdout
    return run


# ---------------------------------------------------------------------------------------------------------------------
# The sidecar `sounds/<name>.wav.json` of a packaged sound (specs/assets/ASSET-sound.md, "Sidecar").

SIDECAR_FORMAT, SIDECAR_VERSION = 'dkq3-wav', 1
# S_LoadSound prints "%s is not a 22kHz audio file" at developer level for any other rate and resamples every sound to the mixer
# rate (../ioq3/code/client/snd_mem.c:231-233).
IOQ3_NOTICE_RATE = 22050


def sidecar(name, archive, source, plan, packaged, trimmed):
    """-> the sidecar of the sound `name` read from `archive`: `source` is the file as the archive holds it, `plan` its Plan,
    `packaged` the file the package holds and `trimmed` the decoded frames a transcode cut."""
    gold, out = getwavinfo(packaged, name), read_wav(packaged, name)
    package = dict(branch=plan.branch, reason=plan.reason, decoder=plan.decoder, bits=out.bits, bytes=len(packaged),
                   frames=out.data_length // (out.channels * out.bits // 8), trimmed_frames=trimmed,
                   chunks=[chunk.ident for chunk in out.chunks])
    return dict(format=SIDECAR_FORMAT, version=SIDECAR_VERSION, sound=name, package=package,
                source=dict(archive=archive, bytes=len(source), **_file_properties(read_wav(source, name))),
                loaders=dict(getwavinfo=getwavinfo(source, name).result,
                             # Gold's Miles S_LoadSound refuses channels other than 1 (S_Calls.cpp:305-310) and decodes the rest
                             miles=GOLD_LOADED if read_wav(source, name).channels == GOLD_MONO else GOLD_STEREO,
                             ioquake3=dict(error=ioq3_read(packaged).error, warnings=list(ioq3_read(packaged).warnings),
                                           rate_notice=out.rate != IOQ3_NOTICE_RATE)),
                loop=dict(gold=dict(loopstart=gold.loopstart, samples=gold.samples),
                          cue_points=[asdict(point) for point in out.cue_points], regions=[asdict(region) for region in out.regions],
                          smpl_loops=[asdict(loop) for loop in out.smpl_loops]))


def _file_properties(wav):
    """-> the properties of a read file a sidecar records: its `fmt ` fields, samples per block, `fact` frames, data bytes and chunks."""
    return dict(format=wav.format, channels=wav.channels, rate=wav.rate, bits=wav.bits, block_align=wav.block_align,
                samples_per_block=wav.samples_per_block, fact_frames=wav.fact_frames, data_bytes=wav.data_length,
                chunks=[chunk.ident for chunk in wav.chunks])


def sidecar_bytes(doc):
    """The sidecar as sorted, compact, ASCII JSON and a newline: equal sidecars give equal package bytes."""
    return json.dumps(doc, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode('ascii') + b'\n'


# ---------------------------------------------------------------------------------------------------------------------
# Corpus driver: `zig build assets-sound`.

PREFIX = 'media:'
WAV_SUFFIX, SIDECAR_SUFFIX = '.wav', '.json'
MAX_JOBS = 4                        # spec R7: at most 4 ffmpeg jobs
# The dkguard caps of one ffmpeg decode: the largest corpus sound (sounds/e4/m_kage_ghost_am.wav, 413,756 bytes) took 0.10 s and
# 63,704 KiB peak RSS (specs/assets/ASSET-sound.md, "Corpus Statistics").
FFMPEG_JOB_MEM, FFMPEG_JOB_TIMEOUT = '512M', '120'
CONVERTED, OVERRIDDEN, FAILED = dkm2md3.CONVERTED, dkm2md3.OVERRIDDEN, dkm2md3.FAILED
LOST = 'lost'


def read_copy(root, archives, name, origin):
    """-> the bytes of `name` from `origin`: an archive name of `archives`, or the loose file's path relative to `root`."""
    paks = dict(archives)
    if origin in paks:
        return paks[origin].read(name)
    with open(os.path.join(root, origin), 'rb') as f:
        return f.read()


def convert_copy(name, origin, data, plan, program, run):
    """-> (report row, (packaged bytes, sidecar) or None) of one copy of a sound with its Plan; every conversion error becomes a
    failed row."""
    row = dict(name=name, archive=origin, branch=plan.branch, reason=plan.reason)
    if plan.branch == LOSS:
        return dict(row, status=LOST), None
    try:
        if plan.branch == TRANSCODE:
            packaged, trimmed = transcode(data, name, plan, program, run)
        else:
            packaged, trimmed = (repair(data, name) if plan.branch == REPAIR else data), 0
        doc = sidecar(name, origin, data, plan, packaged, trimmed)
    except Exception as error:  # every per-sound error is reported by name; none may stop the other sounds unreported
        return dict(row, status=FAILED, error=f'{type(error).__name__}: {error}'), None
    return dict(row, status=CONVERTED, sidecar=name + SIDECAR_SUFFIX), (packaged, doc)


def table(copies, rows):
    """Marks each converted copy after the first of its name overridden, with the archives on both sides."""
    for row in rows:
        origins = copies[row['name']]
        if row['archive'] == origins[0]:
            row['overrides'] = origins[1:]
            continue
        row['overridden_by'] = origins[0]
        if row['status'] == CONVERTED:
            row['status'] = OVERRIDDEN
    return rows


def package_entries(rows, outputs):
    """-> the pk3 entries sorted by name: every packaged sound and its sidecar."""
    entries = []
    for row, output in zip(rows, outputs):
        if row['status'] == CONVERTED:
            packaged, doc = output
            entries += [(row['name'], packaged), (row['sidecar'], sidecar_bytes(doc))]
    return sorted(entries)


# Format tag names for the encoding histogram (the WAVE_FORMAT_* tags of the formats FFMPEG_DECODERS reads, and PCM).
CODECS = {1: 'PCM', 2: 'Microsoft ADPCM', 3: 'IEEE float', 6: 'A-law', 7: 'mu-law', 17: 'IMA ADPCM'}


def encoding(data, name):
    """-> (codec, format tag, rate, channels, bits) of a readable file, or None for a file no loader can read."""
    try:
        wav = read_wav(data, name)
    except WavError:
        return None
    return CODECS.get(wav.format, f'format {wav.format}'), wav.format, wav.rate, wav.channels, wav.bits


def histogram(encodings):
    """-> one row per distinct encoding of the readable copies, most files first, then by codec, tag, rate, channels and bits."""
    counts = collections.Counter(found for found in encodings if found is not None)
    return [dict(codec=codec, format=tag, rate=rate, channels=channels, bits=bits, files=files)
            for (codec, tag, rate, channels, bits), files in sorted(counts.items(), key=lambda item: (-item[1], item[0]))]


def document(rows, encodings, version, expected):
    """-> the report: the ffmpeg version, the totals, the losses and those `expected`, the encoding histogram of every copy, the
    branch counts and every row."""
    status = collections.Counter(row['status'] for row in rows)
    lost = sorted({row['name'] for row in rows if row['status'] == LOST})
    return dict(ffmpeg=version, entries=len(rows), packaged=status[CONVERTED], converted=status[CONVERTED] + status[OVERRIDDEN],
                overridden=status[OVERRIDDEN], lost=lost, expected_losses=[name for name in lost if name in expected],
                failed=sorted({row['name'] for row in rows if row['status'] == FAILED}), encodings=histogram(encodings),
                branches=dict(sorted(collections.Counter(row['branch'] for row in rows).items())), sounds=rows)


def summary_line(row):
    detail = row.get('error') or row.get('reason') or 'ioquake3 reads it as written'
    return f"{PREFIX} {row['name']} ({row['archive']}): {row['status']}, {row['branch']}: {detail}"


def summary(report):
    """-> the lines printed and written as the text report: one per copy, one per encoding, the branches, ffmpeg and the total."""
    lines = [summary_line(row) for row in report['sounds']]
    lines += [f"{PREFIX} encoding codec {row['codec']}, format {row['format']}, rate {row['rate']}, channels {row['channels']}, "
              f"bits {row['bits']}, files {row['files']}" for row in report['encodings']]
    lines.append(f'{PREFIX} branches ' + ', '.join(f'{branch} {count}' for branch, count in report['branches'].items()))
    lines.append(f"{PREFIX} {report['ffmpeg']}")
    lines.append(f"{PREFIX} total: {report['entries']} entries, {report['packaged']} sounds packaged, {report['converted']} converted "
                 f"({report['overridden']} overridden), {len(report['lost'])} lost, {len(report['failed'])} failed")
    return lines


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--data', required=True, help='game directory (zig build -DDK_DATA): loose files and pak0.pak-pak9.pak')
    ap.add_argument('--pak5', help='pak5.pak extracted from pak5.zip, searched before the numbered archives')
    ap.add_argument('--ffmpeg', required=True, help='the ffmpeg program that decodes the sounds ioquake3 cannot read')
    ap.add_argument('--ffmpeg-major', required=True, type=int, help='the recorded ffmpeg major version')
    ap.add_argument('--dkguard', required=True, help='dkguard, which runs every ffmpeg under its caps')
    ap.add_argument('--jobs', required=True, type=int, choices=range(1, MAX_JOBS + 1), metavar=f'1-{MAX_JOBS}',
                    help='ffmpeg runs at once')
    ap.add_argument('--pk3', required=True, help='pk3 to write: every packaged sound and its sidecar')
    ap.add_argument('--report', required=True, help='JSON report to write')
    ap.add_argument('--summary', required=True, help='text report to write: the lines printed on stdout')
    ap.add_argument('--expected-loss', action='append', default=[], metavar='NAME',
                    help='a sound no loader can read that the run reports without failing; repeatable')
    return ap.parse_args(argv)


def _write_text(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def main(argv=None):
    args = parse_args(argv)
    pak5 = dkpak.Pak(args.pak5) if args.pak5 else None
    run = guarded_runner(args.dkguard, FFMPEG_JOB_MEM, FFMPEG_JOB_TIMEOUT)
    with dk2q3.GameDir(args.data) as game:
        archives = dkm2md3.search_order(game, pak5)
        copies = dkm2md3.discover(game.root, archives, suffix=WAV_SUFFIX)
        keys = [(name, origin) for name, origins in sorted(copies.items()) for origin in origins]
        sources = [read_copy(game.root, archives, name, origin) for name, origin in keys]
    plans = [classify(data, name) for (name, _), data in zip(keys, sources)]
    try:
        answers = [run([args.ffmpeg, *query], b'').decode('utf-8', 'replace') for query in FFMPEG_QUERIES]
        version = check_ffmpeg(*answers, args.ffmpeg_major, {plan.decoder for plan in plans if plan.branch == TRANSCODE})
    except FfmpegError as error:
        print(f'{PREFIX} FAIL {error}', file=sys.stderr)
        return 1
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: convert_copy(*item[0], item[1], item[2], args.ffmpeg, run), zip(keys, sources, plans)))
    rows = table(copies, [row for row, _ in results])
    report = document(rows, [encoding(data, name) for (name, _), data in zip(keys, sources)], version, set(args.expected_loss))
    lines = summary(report)
    _write_text(args.report, json.dumps(report, indent=1, sort_keys=True) + '\n')
    _write_text(args.summary, ''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    failures = [row for row in rows if row['status'] == FAILED or (row['status'] == LOST and row['name'] not in report['expected_losses'])]
    for row in failures:
        print(f"{PREFIX} FAIL {row['name']} ({row['archive']}): {row.get('error') or row['reason']}", file=sys.stderr)
    unlost = sorted(set(args.expected_loss) - set(report['lost']))
    for name in unlost:
        print(f'{PREFIX} FAIL expected loss {name} is not lost', file=sys.stderr)
    if failures or unlost:
        return 1
    pk3.write(args.pk3, package_entries(rows, [output for _, output in results]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
