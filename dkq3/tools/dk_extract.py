#!/usr/bin/env python3
"""Decode every image entry of Daikatana archives the way the Gold loaders do, into PNGs and a manifest.

`zig build assets-images` runs it under dkguard into the Zig cache (specs/assets/ASSET-images.md). Archives are
given in override order: for one key (entry name minus extension) the chosen source is the first by extension
(TGA, BMP, PCX, WAL), then the latest archive. World textures decode once per level palette of the maps that
use them.

FRD: specs/frds/FRD-006-deterministic-image-extraction-with-loss-manifest.md
"""
import argparse
import collections
import concurrent.futures
import json
import multiprocessing
import os
import resource
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dkbsp  # noqa: E402
import dkimg  # noqa: E402
import asset_source  # noqa: E402
import dkwal  # noqa: E402

EXTENSIONS = ('.tga', '.bmp', '.pcx', '.wal')   # source preference, first wins
# Gold image type by top directory: BSP surfaces (gl_model.cpp:674-677), RegisterSkin (gl_draw.cpp:43-46,
# gl_model.cpp:1678), skies (gl_warp.cpp:1388-1412); everything else is drawn as a pic (gl_draw.cpp:50).
IMAGE_TYPES = {'textures': 'it_wall', 'skins': 'it_skin', 'models': 'it_skin', 'env': 'it_sky'}
PIC, SKIN, WALL = 'it_pic', 'it_skin', 'it_wall'
MAX_WORKERS = 12                                 # spec R7: at most 12 workers for corpus work
OPAQUE = 255
SCRAP_LIMIT = 64                                 # GL_LoadPic: 8-bit it_pic under 64x64 goes to the scrap (gl_image.cpp:1598-1599)
ASPECT_LIMIT = 8                                 # GL_LoadPic: ERR_FATAL beyond 8:1 (gl_image.cpp:1549-1550)
UPLOAD_TEXEL_LIMIT = 512 * 256                   # GL_Upload8: `unsigned trans[512*256]` (gl_image.cpp:1425, 1432-1435)
BMP_ROW_ALIGN = 4                                # BMP rows are padded to 4 bytes; BMPLineNone does not skip it
IMAGE, NOTEXTURE, REJECTED, FAILED = 'image', 'notexture', 'rejected', 'failed'
REJECTIONS = (dkwal.UnsupportedVersion, dkimg.UnsupportedBmpDepth)   # loader rejections --rejected may name
PREFIX = 'extract:'
# Level palette (cl_main.cpp:1355-1363, gl_image.cpp:2035-2058).
WORLDSPAWN, PALETTE_KEY = 'worldspawn', 'palette'
MAP_PREFIX, MAP_SUFFIX, TEXTURE_PREFIX = 'maps/', '.bsp', 'textures/'
LEVEL_COLORMAP, DEFAULT_COLORMAP = 'textures/{}/colormap.bmp', 'pics/colormap.bmp'
FROM_WORLDSPAWN, FROM_MAP_NAME = 'worldspawn palette', 'map name'
# Loss reasons (specs/assets/ASSET-images.md, Losses).
LOSS_MIPS, LOSS_PALETTE, LOSS_FLOOD, LOSS_FRINGE, LOSS_SCRAP, LOSS_NOTEXTURE, LOSS_REJECTED = (
    'mip_levels_not_converted', 'palette_substituted', 'skin_flood_fill', 'fringe_fill', 'scrap_level_palette',
    'miptex_old_notexture', 'loader_rejection')
LOSS_TGA_ORIGIN, LOSS_BMP_PADDING = 'tga_top_down_ignored', 'bmp_row_padding_not_skipped'


class MissingColormap(ValueError):
    """A world WAL needs a colormap.bmp the archives do not hold: Draw_GetPalette's ERR_FATAL (gl_image.cpp:2057-2058)."""


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('paks', nargs='+', metavar='PAK', help='archive to read, in override order: a later archive wins')
    ap.add_argument('--out', required=True, help='directory to write <key>.png files into')
    ap.add_argument('--manifest', required=True, help='manifest.json to create')
    ap.add_argument('--summary', required=True, help='summary text file to create')
    ap.add_argument('--workers', type=int, default=1, help=f'worker processes, 1 to {MAX_WORKERS} (spec R7)')
    ap.add_argument('--rejected', action='append', default=[], metavar='NAME',
                    help='entry its Gold loader is expected to reject (repeatable)')
    args = ap.parse_args(argv)
    if not 1 <= args.workers <= MAX_WORKERS:
        ap.error(f'--workers {args.workers}: use 1 to {MAX_WORKERS} worker processes (spec R7)')
    # Refuse before any work: a run must never replace existing data (a test once overwrote dkq3/assets).
    if os.path.isdir(args.out) and os.listdir(args.out):
        ap.error(f'refusing to write into the non-empty --out {args.out}')
    for option, path in (('--manifest', args.manifest), ('--summary', args.summary)):
        if os.path.lexists(path):
            ap.error(f'refusing to replace the existing {option} {path}')
    return args


def plan(paths):
    """-> ({key: [(archive path, entry), ...]} with the chosen source first, {map entry: archive path}); a later
    archive's map replaces an earlier one's."""
    sources, maps, overrides = collections.defaultdict(list), {}, {}
    for rank, path in enumerate(paths):
        pak = asset_source.open_source(path)
        try:
            for name in pak.order:
                key, ext = os.path.splitext(name)
                if ext in EXTENSIONS:
                    sources[key].append((EXTENSIONS.index(ext), -rank, path, name))
                elif name.startswith(MAP_PREFIX) and ext == MAP_SUFFIX:
                    maps[name] = path
                elif name.startswith(MAP_PREFIX) and ext == '.ent':
                    overrides[name[:-4] + MAP_SUFFIX] = (path, name)
        finally:
            pak.close()
    return {key: [(p, n) for *_, p, n in sorted(found)] for key, found in sorted(sources.items())}, {name: (path, overrides.get(name)) for name, path in sorted(maps.items())}


_ARCHIVES = {}   # per process: archive path -> open dkpak.Pak


def _read(path, name):
    if path not in _ARCHIVES:
        _ARCHIVES[path] = asset_source.open_source(path)
    return _ARCHIVES[path].read(name)


def _entry(sources, name):
    """-> (archive path, entry) the engine opens for `name` (the latest archive), or None."""
    return next(((p, n) for p, n in sources.get(os.path.splitext(name)[0], ()) if n == name), None)


def _colormap(directory, sources):
    """Draw_GetPalette (gl_image.cpp:2035-2058): textures/<dir>/colormap.bmp when the directory is set and the file
    exists, else pics/colormap.bmp."""
    level = LEVEL_COLORMAP.format(directory)
    return level if directory and _entry(sources, level) else DEFAULT_COLORMAP


def map_palette(job):
    """Worker: -> (map, archive path, palette directory, where it came from, texture names, failure or None) from one
    BSP's worldspawn epairs (cl_main.cpp:1355-1363) and texinfo lump (gl_model.cpp:674)."""
    name, (path, override) = job
    try:
        bsp = dkbsp.Bsp(_read(path, name))
        entity_data = bsp.entities()
        if override:
            replacement = _read(*override)
            if 2 <= len(replacement) <= 0x80000:
                entity_data = replacement.decode('latin1') if isinstance(entity_data, str) else replacement
        value = dkbsp.key_value(dkbsp.epairs_for_class(entity_data, WORLDSPAWN), PALETTE_KEY)
        textures = sorted({info['texture'] for info in bsp.texinfo()})
    except Exception as error:  # a map the client cannot read is a named failure, never a lost palette
        return name, path, None, None, [], f'{os.path.basename(path)}: {name}: {type(error).__name__}: {error}'
    directory = name[len(MAP_PREFIX):-len(MAP_SUFFIX)] if value is None else value
    return name, path, directory, FROM_MAP_NAME if value is None else FROM_WORLDSPAWN, textures, None


def level_palettes(maps, sources, workers):
    """-> ({map: manifest record}, {texture key: {colormap: [maps]}}, failures) as the client picks each map's palette."""
    records, uses, failures = {}, collections.defaultdict(lambda: collections.defaultdict(list)), []
    for name, path, directory, origin, textures, failure in run_jobs(map_palette, list(maps.items()), workers):
        if failure:
            failures.append(failure)
            continue
        colormap = _colormap(directory, sources)
        records[name] = dict(pak=os.path.basename(path), palette_dir=directory, palette=colormap, palette_from=origin)
        for texture in textures:
            uses[TEXTURE_PREFIX + texture][colormap].append(name)
    return records, uses, failures


def variants(key, uses, sources):
    """-> [(colormap, [maps])] for a world texture: every palette its maps use (its own directory's first, then by
    name), or the palette a level named after its directory would load when no map uses it."""
    parts = key.split('/')
    directory = parts[1] if len(parts) > 2 else ''
    if key not in uses:
        return [(_colormap(directory, sources), [])]
    own = LEVEL_COLORMAP.format(directory)
    return sorted(((colormap, sorted(maps)) for colormap, maps in uses[key].items()), key=lambda v: (v[0] != own, v[0]))


def _loss(reason, detail):
    return dict(reason=reason, detail=detail)


def _paletted(indices, palette, image_type, losses):
    """8-bit image -> (H,W,4) uint8 through GL_LoadPic and GL_Upload8, appending every loss they apply."""
    if image_type == SKIN:
        indices, changed = dkimg.flood_fill_skin(indices, palette)
        if changed:
            losses.append(_loss(LOSS_FLOOD, f'{changed} texels recoloured by R_FloodFillSkin (gl_image.cpp:772-828)'))
    transparent = int((indices == dkimg.TRANSPARENT_INDEX).sum())
    if transparent:
        losses.append(_loss(LOSS_FRINGE, f'{transparent} texels of index 255 get alpha 0 and a neighbour colour '
                                         f'(GL_Upload8, gl_image.cpp:1476-1495)'))
    if image_type == PIC and max(indices.shape) < SCRAP_LIMIT:
        losses.append(_loss(LOSS_SCRAP, 'Gold uploads 8-bit pics under 64x64 through the scrap with the level palette '
                                        '(gl_image.cpp:537-548, 1598-1625); decoded with the file palette'))
    return dkimg.upload8(indices, palette)


def _decode_wal(name, raw, image_type, palettes, losses):
    """-> (status, [(colormap or None, (H,W,4) uint8)], (width, height)): no image for a miptexOld_t (gl_image.cpp:
    1690-1695), an it_wall WAL once per level palette (gl_image.cpp:1711-1712), any other WAL with its embedded
    palette (gl_image.cpp:1708-1709)."""
    wal = dkwal.parse_wal(raw, name)
    width, height, texels = wal.mip(0)
    if wal.palette is None:
        losses.append(_loss(LOSS_NOTEXTURE, 'miptexOld_t: GL_LoadWal prints "old wal file not supported" and shows '
                                            'r_notexture (gl_image.cpp:1690-1695); no image'))
        return NOTEXTURE, [], (width, height)
    indices = np.frombuffer(texels, np.uint8).reshape(height, width)
    losses.append(_loss(LOSS_MIPS, 'pre-built mip levels are not converted; ioquake3 builds its own (gl_image.cpp:1373-1396)'))
    if image_type != WALL:
        return IMAGE, [(None, _paletted(indices, wal.palette, image_type, losses))], (width, height)
    images = []
    for index, (colormap, maps, palette) in enumerate(palettes):
        if palette is None:
            raise MissingColormap(f"{name}: {colormap} is not in the archives; Draw_GetPalette stops with ERR_FATAL "
                                  f"\"Couldn't load colormap.bmp\" (gl_image.cpp:2057-2058)")
        if palette != wal.palette:
            used = f"the level palette of {', '.join(maps)}" if maps else 'no map uses it: the palette of its directory'
            losses.append(_loss(LOSS_PALETTE, f'embedded palette replaced by {colormap}, {used} (gl_image.cpp:1711-1712, 2035-2058)'))
        images.append((colormap, _paletted(indices, palette, image_type, losses if index == 0 else [])))
    return IMAGE, images, (width, height)


def _decode(name, raw, image_type, palettes):
    """-> (status, [(colormap or None, (H,W,4) uint8)], losses, (width, height)) of one source: TGA as LoadTGA stores
    it, BMP, PCX and WAL mip 0 through GL_LoadPic and GL_Upload8."""
    losses = []
    if name.endswith('.tga'):
        image = dkimg.tga_to_rgba(raw, name)
        if raw[dkimg.TGA_ATTRIBUTES_AT] & dkimg.TGA_TOP_DOWN:
            losses.append(_loss(LOSS_TGA_ORIGIN, 'the file stores its top row first; LoadTGA ignores the attributes bit '
                                                 'and puts the first row at the bottom (gl_image.cpp:636, 667)'))
        return IMAGE, [(None, image)], losses, (image.shape[1], image.shape[0])
    if name.endswith('.wal'):
        status, images, size = _decode_wal(name, raw, image_type, palettes, losses)
        return status, images, losses, size
    image = (dkimg.read_bmp if name.endswith('.bmp') else dkimg.read_pcx)(raw, name)
    if name.endswith('.bmp') and image.width % BMP_ROW_ALIGN:
        losses.append(_loss(LOSS_BMP_PADDING, f'width {image.width}: BMPLineNone reads {image.width} bytes per row and '
                                              f'never skips the padding to a multiple of {BMP_ROW_ALIGN} (dk_ref_common.cpp:166-213)'))
    return IMAGE, [(None, _paletted(image.indices, image.palette, image_type, losses))], losses, (image.width, image.height)


def _write(out, key, images, palettes):
    """Writes <key>.png for the first image and <key>@<palette dir>.png for the others -> manifest `files`."""
    maps = {colormap: listed for colormap, listed, _ in palettes}
    files = []
    for index, (colormap, image) in enumerate(images):
        suffix = '' if index == 0 else '@' + os.path.dirname(colormap).replace('/', '-')
        file = f'{key}{suffix}.png'
        os.makedirs(os.path.dirname(os.path.join(out, file)), exist_ok=True)
        alpha = bool((image[..., 3] < OPAQUE).any())
        dkimg.write_png(os.path.join(out, file), image if alpha else image[..., :3])
        files.append(dict(file=file, palette=colormap, maps=maps.get(colormap, [])))
    return files


def _limits(name, width, height):
    """Gold renderer limits the chosen source passes; listed, not failures, as ioquake3 has neither."""
    found = []
    if width and max(width, height) > ASPECT_LIMIT * min(width, height):
        found.append(f"{width}x{height} beyond GL_LoadPic's {ASPECT_LIMIT}:1 aspect ratio (gl_image.cpp:1549-1550)")
    if width and not name.endswith('.tga') and width * height > UPLOAD_TEXEL_LIMIT:
        found.append(f"{width}x{height} = {width * height} texels beyond GL_Upload8's {UPLOAD_TEXEL_LIMIT} "
                     f"(gl_image.cpp:1425-1435)")
    return found


def _source(path, name, image_type, palettes, rejected):
    """-> (status, images, losses, (width, height), failure or None) of one source. An error becomes a rejection when
    --rejected names the entry and its loader rejects it, else a failure naming the archive and the entry."""
    try:
        return (*_decode(name, _read(path, name), image_type, palettes), None)
    except Exception as error:  # every per-file error is collected by name; none may escape the worker unreported
        detail = f'{type(error).__name__}: {error}'
        if name in rejected and isinstance(error, REJECTIONS):
            return REJECTED, [], [_loss(LOSS_REJECTED, detail)], (None, None), None
        return FAILED, [], [], (None, None), f'{os.path.basename(path)}: {name}: {detail}'


def decode_key(job):
    """Worker: decodes every source of one key, writes the chosen source's PNGs -> (key, manifest record,
    failures, rejected entries)."""
    key, sources, out, palettes, rejected = job
    category = key.split('/')[0]
    image_type = IMAGE_TYPES.get(category, PIC)
    decoded = [(path, name, *_source(path, name, image_type, palettes, rejected)) for path, name in sources]
    path, name, status, images, losses, (width, height), _ = decoded[0]
    listed = [dict(pak=os.path.basename(p), entry=n, w=size[0], h=size[1], status=s) for p, n, s, _, _, size, _ in decoded]
    engine = next(((s['w'], s['h']) for s in listed if s['entry'].endswith('.wal') and s['w']), (None, None))
    record = dict(status=status, src_pak=os.path.basename(path), src=name, w=width, h=height,
                  alpha=any(bool((image[..., 3] < OPAQUE).any()) for _, image in images),
                  category=category, image_type=image_type, losses=losses, sources=listed,
                  engine_w=engine[0], engine_h=engine[1], files=_write(out, key, images, palettes),
                  limits=_limits(name, width, height))
    return key, record, [d[-1] for d in decoded if d[-1]], [d[1] for d in decoded if d[2] == REJECTED]


def _palettes(key, found, uses, sources, cache, failures):
    """-> [(colormap, maps, 768 palette bytes or None)] a world-texture job with a WAL source decodes with; empty for
    any other key. Each colormap is read once (`cache`); one LoadBMP rejects becomes a failure."""
    if IMAGE_TYPES.get(key.split('/')[0]) != WALL or not any(name.endswith('.wal') for _, name in found):
        return []
    palettes = []
    for colormap, maps in variants(key, uses, sources):
        if colormap not in cache:
            located, cache[colormap] = _entry(sources, colormap), None
            try:
                cache[colormap] = located and dkimg.read_bmp(_read(*located), located[1]).palette
            except dkimg.ImageError as error:
                failures.append(f'{os.path.basename(located[0])}: {colormap}: {type(error).__name__}: {error}')
        palettes.append((colormap, maps, cache[colormap]))
    return palettes


def main(argv=None):
    args = parse_args(argv)
    sources, maps = plan(args.paks)
    rejected, cache = frozenset(args.rejected), {}
    try:
        records, uses, failures = level_palettes(maps, sources, args.workers)
        jobs = [(key, found, args.out, _palettes(key, found, uses, sources, cache, failures), rejected)
                for key, found in sources.items()]
        results = run_jobs(decode_key, jobs, args.workers)
    except WorkerDied as error:
        print(f'{PREFIX} FAIL {error}', file=sys.stderr)
        return 1
    failures += [failure for _, _, found, _ in results for failure in found]
    os.makedirs(os.path.dirname(os.path.abspath(args.manifest)), exist_ok=True)
    with open(args.manifest, 'w', encoding='utf-8') as f:
        json.dump({'images': {key: record for key, record, _, _ in results}, 'maps': records}, f, indent=1, sort_keys=True)
        f.write('\n')
    lines = summary(len(args.paks), sources, [record for _, record, _, _ in results], records)
    with open(args.summary, 'w', encoding='utf-8') as f:
        f.write(''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    for failure in failures:
        print(f'{PREFIX} FAIL {failure}', file=sys.stderr)
    print(f'{PREFIX} {args.workers} workers, peak RSS main {_rss_mib(resource.RUSAGE_SELF)} MiB, largest worker '
          f'{_rss_mib(resource.RUSAGE_CHILDREN)} MiB', file=sys.stderr)
    return 1 if failures else 0


class WorkerDied(RuntimeError):
    """A worker process ended without returning its jobs (a crash or the memory cap); the run cannot be complete."""


JOBS_PER_TASK = 8   # jobs sent to a worker at once; results still come back in job order


def run_jobs(function, jobs, workers):
    """-> [function(job) for job in jobs] computed by `workers` spawned processes, in job order. A worker process that
    dies raises WorkerDied instead of silently shortening the results."""
    results = []
    with concurrent.futures.ProcessPoolExecutor(workers, mp_context=multiprocessing.get_context('spawn')) as pool:
        try:
            results.extend(pool.map(function, jobs, chunksize=JOBS_PER_TASK))
        except concurrent.futures.process.BrokenProcessPool as error:
            raise WorkerDied(f'a worker process died after {len(results)} of {len(jobs)} jobs returned: {error}') from error
    return results


def _rss_mib(who):
    """Peak resident set of this process or of its largest finished child, MiB (ru_maxrss is KiB on Linux)."""
    return resource.getrusage(who).ru_maxrss // 1024


def summary(archives, sources, images, maps):
    """-> the deterministic summary lines: nothing here depends on the worker count, time or paths."""
    extensions = collections.Counter(os.path.splitext(name)[1] for found in sources.values() for _, name in found)
    statuses = collections.Counter(record['status'] for record in images)
    files = sum(len(record['files']) for record in images)
    reasons = collections.Counter(reason for record in images for reason in {loss['reason'] for loss in record['losses']})
    return [f"{PREFIX} {archives} archives, {len(sources)} keys, {sum(extensions.values())} sources ("
            + ', '.join(f'{ext[1:]} {extensions[ext]}' for ext in EXTENSIONS) + ')',
            f'{PREFIX} ' + ', '.join(f'{statuses[status]} {status}' for status in (IMAGE, NOTEXTURE, REJECTED, FAILED)),
            f"{PREFIX} {files} files ({files - statuses[IMAGE]} extra palette variants), {len(maps)} maps, "
            f"{len({record['palette'] for record in maps.values()})} level palettes",
            f'{PREFIX} losses ' + (', '.join(f'{reason} {count}' for reason, count in sorted(reasons.items())) or 'none'),
            f"{PREFIX} {sum(1 for record in images if record['limits'])} beyond renderer limits"]


if __name__ == '__main__':
    sys.exit(main())
