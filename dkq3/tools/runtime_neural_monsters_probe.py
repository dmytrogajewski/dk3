#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Rendered episode monster/physics fixture; invoke under dkguard --headless."""
import argparse
import math
import json
from pathlib import Path
import re
import time
import zipfile
from runtime_bugfix_probe import run,aim_actor
from runtime_opening_route import actors
from runtime_probe import wait


def scene(driver,report,capture):
    wait(driver.process,driver.log,lambda t:'dk3 region: initial admission committed' in t,90)
    driver.until(lambda s:s['mode']=='normal')
    driver.issue('dk3_runtime_probe_health 10000')
    driver.until(lambda s:s['health']==10000)
    driver.issue('con_notifytime 0')
    if args.actor_id:
        identity=args.actor_id
        assert actors(driver)[identity]['class']=='monster_'+args.actor
    else:
        initial=driver.stop_forward(settle_vertical=True)
        for yaw in (90,0,180,270):
            driver.aim(yaw,0);driver.issue('+forward')
            try:
                driver.until(lambda s:math.dist(s['pos'][:2],initial['pos'][:2])>130,seconds=3)
                break
            except TimeoutError: pass
            finally: driver.stop_forward(settle_vertical=True)
        else: raise RuntimeError('No clear fixture walking direction')
        x,y,z=initial['pos']
        # Hull heights vary substantially between a worker, robot and boar.
        # Failed placements are explicitly rejected by the native collision
        # service; only a clear, grounded class-owned hull is admitted.
        failures=[]
        match=None
        for dx,dy in ((0,0),(96,0),(-96,0),(0,-96),(160,0),(-160,0)):
            for lift in (8,40,64):
                text=driver.diagnostics(f'dk3_runtime_actor_spawn monster_{args.actor} {x+dx} {y+dy} {z+lift} 0 {args.start_map} 1 ground','dk3 actor ',seconds=30)
                match=re.search(r'id=(\d+).*hull-clear=1.*grounded=1',text)
                if match:break
                assert 'dk3 actor probe failed:' in text,text
                failures.append(text)
            if match:break
        assert match,failures
        identity=int(match[1])
    driver.diagnostics(f'dk3_runtime_face_target {identity} 160',f'target={identity}')
    driver.stop_forward(settle_vertical=True)
    row=actors(driver)[identity]
    aim_actor(driver,row)
    driver.elapsed(200);capture('monster-alive')
    saved=driver.save('neural_monster_alive')
    expected=f'models/neural/e1_{args.actor}.iqm'
    assert expected in driver.text(),expected
    samples=[]
    child=None
    if args.hatch:
        assert args.actor=='protopod'
        marker=f'dk3 pod: id={identity} hatched='
        text=wait(driver.process,driver.log,lambda t:marker in t,12)
        child=int(re.search(re.escape(marker)+r'(\d+)',text)[1])
        hatched=actors(driver)[child]
        assert hatched['class']=='monster_slaughterskeet',hatched
        for frame in range(12):
            capture(f'pod-hatch-{frame:03}')
            driver.elapsed(80)
        assert 'models/neural/e1_slaughterskeet.iqm' in driver.text()
    if args.physics:
        driver.issue('set dk3_runtime_restore_audit 1')
        if args.retain_body: driver.issue('gib_enable 0')
        driver.diagnostics(f'dk3_runtime_probe_health 1 {identity}',f'id={identity} health=1')
        driver.issue('dk3_runtime_equip 21');driver.ready(21)
        deadline=time.monotonic()+12
        while time.monotonic()<deadline:
            current=actors(driver)
            if identity not in current or current[identity]['health']<=0: break
            aim_actor(driver,current[identity]);driver.fire()
        else: raise TimeoutError('Ordinary Glock fire did not kill the monster')
        for frame in range(24):
            text=driver.diagnostics('dk3_runtime_presentation','dk3 presentation:')
            for line in text.splitlines():
                if line.startswith('dk3 ragdoll: ') and f'identity={identity} ' in line:
                    samples.append(dict(re.findall(r'(\w+)=([^ ]+)',line)))
            if frame in (0,4,12,23): capture(f'monster-dead-{frame:03}')
            driver.elapsed(70)
        if args.expect_gibs:
            assert f'id={identity} reason=gibbed' in driver.text() or f'dk3 actor gibs: id={identity}' in driver.text(), 'No authored gib evidence'
        else:
            assert samples and max(int(r['contacts']) for r in samples)>0,samples
            assert all(int(r['bones'])>=2 for r in samples),samples
        driver.load('neural_monster_alive')
        assert actors(driver)[identity]['health']>0
        text=driver.diagnostics('dk3_runtime_presentation','dk3 presentation:')
        assert not any(f'identity={identity} ' in line for line in text.splitlines() if line.startswith('dk3 ragdoll: '))
        capture('monster-restored')
    assert not re.search(r'R_AddIQMSurfaces: no such frame|MissingAuthoredActorHardpoint|R_LoadIQM:',driver.text())
    return dict(actor=args.actor,identity=identity,model=expected,physics=samples,saved=saved.name,hatched_child=child,
                retain_body=args.retain_body,expect_gibs=args.expect_gibs,
                scope='Controlled visible actor, native skeletal rendering and save restoration; optional ordinary-fire death and contacts. No full campaign or hardware-renderer acceptance.')


def batch(driver,report,capture):
    """Render each installed roster actor from the same clean saved world."""
    wait(driver.process,driver.log,lambda t:'dk3 region: initial admission committed' in t,90)
    driver.until(lambda s:s['mode']=='normal')
    driver.save('neural_roster_base')
    rows=[]
    for slug in args.actors:
        driver.load('neural_roster_base')
        args.actor=slug
        rows.append(scene(driver,report,lambda name:capture(slug+'-'+name)))
        print(slug+': native rendered fixture passed',flush=True)
    return dict(actors=rows,scope='Controlled native rendering of the installed episode roster; isolated saved world per actor. No campaign acceptance.')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--actor')
    parser.add_argument('--all',action='store_true',help='exercise all episode monsters in the installed cosmetic roster')
    parser.add_argument('--actor-id',type=int)
    parser.add_argument('--map',default='e1m3b')
    parser.add_argument('--renderer',default='opengl2')
    parser.add_argument('--capture-size',type=int,nargs=2,metavar=('WIDTH','HEIGHT'),help='explicit software-rendered capture dimensions')
    parser.add_argument('--physics',action='store_true')
    parser.add_argument('--hatch',action='store_true',help='verify the real Protopod event spawns a separate skeletal mechanical mosquito')
    parser.add_argument('--expect-gibs',action='store_true')
    parser.add_argument('--retain-body',action='store_true',help='disable fragments for a controlled articulated-body diagnostic; default gib behavior is a separate scenario')
    args=parser.parse_args()
    if args.capture_size and any(value<=0 for value in args.capture_size):parser.error('--capture-size dimensions must be positive')
    if not args.actor and not args.all:parser.error('select --actor or --all')
    args.engine=args.engine.resolve();args.report=args.report.resolve()
    args.start_map=args.map;args.scenario='neural-monsters';args.developer=True;args.cinematics=False
    if args.all:
        if args.actor_id:parser.error('--actor-id cannot be combined with --all')
        with zipfile.ZipFile(args.engine/'share/dk3/zz-dk3-neural.pk3') as archive:
            roster=json.loads(archive.read('dk3/neural-assets.json'))['actors']
        args.actors=[r['slug'] for r in roster if r.get('kind')!='character']
        run(args,batch)
    else:run(args,scene)
