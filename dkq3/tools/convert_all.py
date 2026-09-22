#!/usr/bin/env python3
"""Every map of a game directory converted with dk2q3.py's pass, checked against the expected map list, reported per map and
packaged (specs/assets/ASSET-bsp.md, "Corpus Conversion").

- **Discovery.** Every `maps/<name>.bsp`: loose files of the game directory and entries of each `pakN.pak`. A map's source is
  its first copy in the 1.3 search order (`dk2q3.GameDir`); the later copies are the ones it overrides.
- **Expected set.** Every `--map` must be discovered and every discovered map must be listed. A missing or unaccounted map
  fails the run, named on stderr and in its report row.
- **Conversion.** `dk2q3.run` for each map in at most 12 worker processes (spec R7), writing `<out-dir>/bsp/<map>.bsp`,
  `stock/<map>.bsp`, `reports/<map>.json` (dk2q3's report) and `shaders/<map>.json` (dk2q3's shader definitions).
- **Report.** Per map: status, source and overridden copies, entity source, counts, projected entities kept and dropped,
  losses, output sizes, the ioquake3 limits checked with value and maximum, and the acceptance log paths below `--logs`. A
  map over a limit fails.
- **Packages.** When every map converted: `--pk3` holds each product BSP and `--stock-pk3` each stock projection, as
  `maps/<map>.bsp` sorted by map name (pk3.py).

`zig build assets-maps` runs it under dkguard. Exit status 0 when every listed map converted, 1 otherwise, 2 on usage.

FRD: specs/frds/FRD-016-all-84-maps-convert-and-load-headless.md
"""
import argparse
import collections
import concurrent.futures
import json
import os
import sys

import dk2q3
import entities
import pk3

PREFIX = 'convert-all:'
MAX_WORKERS = 12                 # spec R7: parallel corpus work uses at most 12 workers
MAPS_DIR, BSP = 'maps/', '.bsp'
PRODUCT_DIR, STOCK_DIR, REPORTS_DIR, SHADERS_DIR = 'bsp', 'stock', 'reports', 'shaders'
# code/renderergl1/tr_local.h:785: R_CreateImage stops the map with ERR_DROP at MAX_DRAWIMAGES (tr_image.c:853-854). Every
# lightmap page, texture frame, glow layer and sky side of a map is one image.
MAX_DRAWIMAGES = 2048
# code/renderergl1/tr_local.h:49-50: GeneratePermanentShader warns and draws the default shader at MAX_SHADERS (tr_shader.c:2040-2041).
MAX_SHADERS = 1 << 14
SKY_SIDES = 6                    # skyParms loads six sides (code/renderergl1/tr_shader.c ParseSkyParms)
# The acceptance logs of one map below --logs, as dkq3/tools/tests/accept_maps.py writes them.
LOG_FILES = dict(client_console='client/console.log', client_runner='client/runner.txt',
                 client_shader_check='client/shader-check.txt', client_entity_check='client/entity-check.txt',
                 server_console='server/console.log', server_runner='server/runner.txt',
                 server_entity_check='server/entity-check.txt')


def discover(game):
    """-> {map name: its copies in the 1.3 search order}: `maps/<name>.bsp` for a loose file, `<pak>:maps/<name>.bsp` for an
    archive entry. `game.paks` is already pak9..pak0, and the game directory comes before every archive."""
    found, loose = collections.defaultdict(list), os.path.join(game.root, 'maps')
    for name in sorted(os.listdir(loose)) if os.path.isdir(loose) else ():
        if name.endswith(BSP) and os.path.isfile(os.path.join(loose, name)):
            found[name[:-len(BSP)]].append(MAPS_DIR + name)
    for pak_name, pak in game.paks:
        for entry in sorted(pak.entries):
            stem = entry[len(MAPS_DIR):-len(BSP)] if entry.startswith(MAPS_DIR) and entry.endswith(BSP) else ''
            if stem and '/' not in stem:
                found[stem].append(f'{pak_name}:{entry}')
    return dict(found)


def outputs(out_dir, name):
    """-> (product BSP, stock BSP, dk2q3 report, shader definitions) paths of one map."""
    return (os.path.join(out_dir, PRODUCT_DIR, name + BSP), os.path.join(out_dir, STOCK_DIR, name + BSP),
            os.path.join(out_dir, REPORTS_DIR, name + '.json'), os.path.join(out_dir, SHADERS_DIR, name + '.json'))


def convert_map(job):
    """Worker: converts one map and writes its outputs. -> (dk2q3 report, shader definitions, None) or (None, None, error)."""
    name, data, manifest, textures, out_dir = job
    bsp, stock, report, shaders = outputs(out_dir, name)
    args = dk2q3.parse_args([name, f'--data={data}', f'--manifest={manifest}', f'--textures={textures}', f'--out={bsp}',
                             f'--stock-out={stock}', f'--report={report}', f'--shaders={shaders}'])
    try:
        converted = dk2q3.run(args)
    except dk2q3.FAILURES as error:
        return None, None, str(error)
    dk2q3.write(args, *converted)
    return converted[2], converted[3], None


def limits(report, document):
    """-> {limit: {value, max}} of the ioquake3 loaders a converted map meets (specs/assets/ASSET-bsp.md, "Corpus Conversion")."""
    counts, projection, images = report['counts'], report['projection'], set()
    for definition in document['shaders'].values():
        if definition['kind'] == 'surface':
            images.update(definition['frames'] + definition['glow'])
        elif definition['kind'] == 'sky':
            images.update(f"{definition['box']}_{side}" for side in range(SKY_SIDES))
    names = [len(name.encode('latin1')) for name in document['shaders']]
    return dict(models=dict(value=counts['models'], max=dk2q3.MAX_SUBMODELS),
                surface_verts=dict(value=counts['max_surface_verts'], max=dk2q3.MAX_FACE_POINTS),
                shader_name_bytes=dict(value=max(names, default=0), max=dk2q3.MAX_SHADER_NAME),
                shaders=dict(value=len(names), max=MAX_SHADERS),
                images=dict(value=counts['lightmap_pages'] + len(images), max=MAX_DRAWIMAGES),
                stock_sounds=dict(value=projection['sounds'], max=entities.SOUND_LIMIT),
                stock_live_entities=dict(value=projection['live_entities'], max=entities.LIVE_LIMIT))


def exceeded(checked):
    """-> `<limit> <value> > <max>` for every limit a map passes, sorted."""
    return [f"{name} {limit['value']} > {limit['max']}" for name, limit in sorted(checked.items()) if limit['value'] > limit['max']]


def converted_row(name, copies, report, document, args):
    """-> the report row of a converted map and its failure, or None when it is within every limit."""
    bsp, stock, _, _ = outputs(args.out_dir, name)
    projection, checked = report['projection'], limits(report, document)
    row = dict(report, status='converted', overrides=copies[1:], limits=checked,
               entities_projected=dict(kept=sum(projection['mapped'].values()), dropped=sum(projection['dropped'].values())),
               sizes=dict(bsp=os.path.getsize(bsp), stock_bsp=os.path.getsize(stock)),
               logs={key: f'{args.logs}/{name}/{path}' for key, path in LOG_FILES.items()})
    over = exceeded(checked)
    if not over:
        return row, None
    row.update(status='failed', error='over ioquake3 limits: ' + ', '.join(over))
    return row, row['error']


def convert(args, copies, names):
    """-> {map name: (report, shader definitions, error)} of `names`, converted in the worker pool."""
    for directory in (PRODUCT_DIR, STOCK_DIR, REPORTS_DIR, SHADERS_DIR):
        os.makedirs(os.path.join(args.out_dir, directory), exist_ok=True)
    results = {}
    with concurrent.futures.ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = {name: pool.submit(convert_map, (name, args.data, args.manifest, args.textures, args.out_dir)) for name in names}
        for name, future in futures.items():
            try:
                results[name] = future.result()
            except concurrent.futures.process.BrokenProcessPool as error:
                results[name] = (None, None, f'a worker process died: {error}')
    return results


def rows(args, copies):
    """-> (report rows by map name, failure lines) for the expected maps and every discovered map."""
    expected, table, failures = sorted(set(args.maps)), {}, []
    for name in expected:
        if name not in copies:
            table[name] = dict(status='missing')
            failures.append(f'{name}: expected, but no maps/{name}{BSP} in the game directory')
    for name in sorted(set(copies) - set(expected)):
        table[name] = dict(status='unaccounted', source=copies[name][0], overrides=copies[name][1:])
        failures.append(f'{name}: {copies[name][0]} is not in the expected map list')
    present = [name for name in expected if name in copies]
    for name, (report, document, error) in convert(args, copies, present).items():
        if error is not None:
            table[name] = dict(status='failed', source=copies[name][0], overrides=copies[name][1:], error=error)
            failures.append(f'{name}: {error}')
            continue
        table[name], failure = converted_row(name, copies[name], report, document, args)
        if failure:
            failures.append(f'{name}: {failure}')
    return dict(sorted(table.items())), failures


def summary_line(name, row):
    """One line of the text report."""
    if row['status'] != 'converted':
        return f"{PREFIX} {name}: {row['status']}" + (f": {row['error']}" if 'error' in row else '')
    c, p, s = row['counts'], row['entities_projected'], row['sizes']
    over = f" over {', '.join(row['overrides'])}" if row['overrides'] else ''
    return (f"{PREFIX} {name}: converted from {row['source']}{over}, entities from {row['entities']}: {c['surfaces']} surfaces, "
            f"{c['brushes']} brushes, {c['models']} models, {c['visibility_clusters']} clusters, {c['shaders']} shaders, "
            f"{c['lightmap_pages']} lightmap pages; projection {p['kept']} kept, {p['dropped']} dropped; {s['bsp']} bytes, "
            f"stock {s['stock_bsp']} bytes; limits met; logs {os.path.dirname(os.path.dirname(row['logs']['client_console']))}/")


def document(args, copies, table):
    """-> the JSON report: rows and totals."""
    status = collections.Counter(row['status'] for row in table.values())
    return dict(maps=table, expected=len(set(args.maps)), discovered=len(copies), converted=status['converted'],
                failed=sorted(name for name, row in table.items() if row['status'] == 'failed'),
                missing=sorted(name for name, row in table.items() if row['status'] == 'missing'),
                unaccounted=sorted(name for name, row in table.items() if row['status'] == 'unaccounted'))


def package(args, names):
    """Writes the product and stock packages of the converted maps, sorted by name, one BSP read at a time."""
    for path, index in ((args.pk3, 0), (args.stock_pk3, 1)):
        pk3.write_files(path, [(f'{MAPS_DIR}{name}{BSP}', outputs(args.out_dir, name)[index]) for name in names])


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--data', required=True, help='game directory (zig build -DDK_DATA): loose maps/ files and pak0.pak-pak9.pak')
    ap.add_argument('--manifest', required=True, help='manifest.json written by dk_extract.py')
    ap.add_argument('--textures', required=True, help='textures.json written by pack_textures.py')
    ap.add_argument('--out-dir', required=True, help='directory to write: bsp/, stock/, reports/ and shaders/ per map')
    ap.add_argument('--pk3', required=True, help='pk3 to write: every product BSP as maps/<map>.bsp')
    ap.add_argument('--stock-pk3', required=True, help='pk3 to write: every stock-projection BSP as maps/<map>.bsp')
    ap.add_argument('--report', required=True, help='JSON report to write')
    ap.add_argument('--summary', required=True, help='text report to write: the lines printed on stdout')
    ap.add_argument('--logs', required=True, help='directory the acceptance logs are indexed under, relative to the install prefix')
    ap.add_argument('--workers', type=int, required=True, help=f'worker processes, 1 to {MAX_WORKERS} (spec R7)')
    ap.add_argument('--map', dest='maps', action='append', required=True, metavar='NAME',
                    help='a map the game directory must hold; repeatable')
    args = ap.parse_args(argv)
    if not 1 <= args.workers <= MAX_WORKERS:
        ap.error(f'--workers must be 1 to {MAX_WORKERS} (spec R7), not {args.workers}')
    return args


def main(argv=None):
    args = parse_args(argv)
    with dk2q3.GameDir(args.data) as game:
        copies = discover(game)
    table, failures = rows(args, copies)
    report = document(args, copies, table)
    lines = [summary_line(name, row) for name, row in table.items()]
    lines.append(f"{PREFIX} total: {report['expected']} maps expected, {report['discovered']} discovered, {report['converted']} "
                 f"converted, {len(report['failed'])} failed, {len(report['missing'])} missing, {len(report['unaccounted'])} "
                 f"unaccounted")
    for path in (args.report, args.summary, args.pk3, args.stock_pk3):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(args.report, 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=1, sort_keys=True)
        f.write('\n')
    with open(args.summary, 'w', encoding='utf-8') as f:
        f.write(''.join(line + '\n' for line in lines))
    print('\n'.join(lines))
    for failure in failures:
        print(f'{PREFIX} FAIL {failure}', file=sys.stderr)
    if failures:
        return 1
    package(args, list(table))
    return 0


if __name__ == '__main__':
    sys.exit(main())
