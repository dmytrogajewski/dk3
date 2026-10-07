#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drain completed TRELLIS actors into CPU conversion/previews while it runs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from neural_monsters import digest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=Path('zig-out/neural-monsters/episode1'))
    parser.add_argument('--producer-pid',type=int,required=True)
    parser.add_argument('--preview-workers',type=int,default=3,choices=range(1,5),help='independent CPU preview renders; each Blender uses four threads')
    args=parser.parse_args()
    args.out=args.out.resolve()
    tools=Path(__file__).resolve().parent
    attempted=set()
    previews=[]
    failures=[]
    pool=ThreadPoolExecutor(max_workers=args.preview_workers)
    while True:
        rows=json.loads((args.out/'pipeline.json').read_text())['actors']
        processed=False
        for row in sorted(rows,key=lambda row:row.get('kind')!='character'):
            receipt=row['stages'].get('trellis',{})
            if receipt.get('state')!='complete': continue
            if row['slug'] in ('prisoner','prisonerb'): continue
            key=(row['slug'],receipt['outputs']['model.glb'],*(digest(tools/name) for name in
                 ('neural_monster_blender.py','neural_monster_rig.py','neural_monster_skeleton.py','neural_rig.py','neural_assets.py','neural_monster_preview.py')))
            if key in attempted: continue
            attempted.add(key)
            processed=True
            result=subprocess.run([sys.executable,'-B',str(tools/'neural_monsters.py'),'convert','--out',str(args.out),'--models',row['slug']])
            if result.returncode:
                print(row['slug'],'conversion failed:',result.returncode,flush=True)
                failures.append(row['slug'])
                continue
            command=[sys.executable,'-B',str(tools/'neural_monster_preview.py'),'--actor',str(args.out/row['slug'])]
            previews.append((row['slug'],pool.submit(subprocess.run,command)))
        try: os.kill(args.producer_pid,0)
        except ProcessLookupError:
            # A producer can finish another actor while this snapshot is being
            # converted. Rescan until a complete pass admits no new receipt.
            if processed: continue
            break
        time.sleep(10)
    pool.shutdown(wait=True)
    for slug,future in previews:
        if future.result().returncode: failures.append(slug)
    if failures: raise SystemExit('CPU stages incomplete: '+', '.join(failures))
    print('TRELLIS producer exited; ready CPU stages drained',flush=True)


if __name__=='__main__':main()
