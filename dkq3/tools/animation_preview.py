#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate a sealed animation studio and record native cinematic regression video.

Engine execution is always a dkguard child, with a disposable home. The reviewed
installation, launcher and user saves are read-only inputs to this tool.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import zipfile

import numpy as np
from PIL import Image

import animation_manifest as schema
from animation_author import fresh
import map_build
import quake_map
from runtime_input import NativeInput,engine_failure,record_identity,cinematic_shots
from runtime_probe import client_settings,stage_client_modules,wait,send


def validate_arguments(args: argparse.Namespace) -> None:
    """Validate command tokens before constructing any native console input."""
    from cinematic_reconstruction import filename_token
    schema.number(args.seconds, 1, 600, 'preview timeout')
    if args.operation == 'record':
        filename_token(args.map, 'preview map')
        filename_token(args.program, 'preview program')
        schema.number(args.trigger, 1, 65535, 'preview trigger', integer=True)
        schema.number(args.shots, 1, 256, 'preview shots', integer=True)
    else:
        filename_token(args.demo.stem, 'preview demo')
        schema.number(args.fps, 1, 120, 'video rate', integer=True)


def presentation_settings(engine: Path, home: Path, settings: dict,
                          presentation: str, overlays: list[Path]) -> list[str]:
    """Select real original-only assets in a disposable base path.

    An empty mapping is weaker evidence than an absent optional package. The
    legacy profile excludes packages containing the neural admission manifest;
    exact excluded archives are recorded and original files remain read-only.
    """
    if presentation in ('skeletal','fallback'):return []
    excluded=[];base=home/'original-base'/'dk3';base.mkdir(parents=True)
    for package in sorted((engine/'share/dk3').glob('*.pk3')):
        with zipfile.ZipFile(package) as archive:
            optional='dk3/neural-models.cfg' in archive.namelist()
        if optional:excluded.append(str(package))
        else:(base/package.name).symlink_to(package)
    for package in overlays:
        with zipfile.ZipFile(package) as archive:
            if any(name.startswith(('models/neural/','dk3/neural-')) for name in archive.namelist()):
                raise schema.Error('legacy preview cannot include a skeletal overlay')
    regions=engine/'share/dk3/dk3'
    if regions.exists():(base/'dk3').symlink_to(regions)
    settings['fs_basepath']=str(base.parent)
    return excluded


def studio(program,output,prefix=Path('zig-out/native-dev')):
    program=Path(program).resolve();name=program.stem;schema.text(name,'program name',32)
    root=fresh(output,True).resolve();base=root/'compiler/home/.q3a/baseq3'
    for sub in ('maps','scripts','textures/authoring'): (base/sub).mkdir(parents=True,exist_ok=True)
    image=Image.new('RGB',(64,64),(65,69,73));image.save(base/'textures/authoring/studio.png')
    shader='textures/authoring/studio'
    (base/'scripts/authoring.shader').write_text(shader+'\n{\n qer_editorimage textures/authoring/studio.png\n { map $lightmap rgbGen identity }\n { map textures/authoring/studio.png blendFunc filter rgbGen identity }\n}\n'
        +'textures/authoring/trigger\n{\n qer_editorimage textures/authoring/studio.png\n surfaceparm nodraw\n surfaceparm nonsolid\n surfaceparm trigger\n}\n')
    (base/'scripts/shaderlist.txt').write_text('authoring\n')
    style=quake_map.FaceStyle('authoring/studio',scale=(1,1))
    def box(lo,hi):
        points=[(x,y,z) for z in (lo[2],hi[2]) for y in (lo[1],hi[1]) for x in (lo[0],hi[0])]
        polygons=[(0,1,3,2),(4,6,7,5),(0,4,5,1),(2,3,7,6),(0,2,6,4),(1,5,7,3)]
        return quake_map.brush_from_mesh(points,polygons,lambda *_:style,'studio-shell')
    brushes=[box((-320,-256,-32),(320,256,0)),box((-320,-256,160),(320,256,192)),
             box((-352,-288,-32),(-320,288,192)),box((320,-288,-32),(352,288,192)),
             box((-320,-288,-32),(320,-256,192)),box((-320,256,-32),(320,288,192))]
    # An unobtrusive step creates real connected AAS areas; a single flat room
    # otherwise produces only one area and fails the admitted navigation check.
    brushes.append(box((-260,150,0),(-180,220,16)))
    trigger=box((-270,-240,0),(-240,-210,48))
    trigger_style=quake_map.FaceStyle('authoring/trigger',solid=False)
    from dataclasses import replace
    trigger.faces=[replace(face,style=trigger_style) for face in trigger.faces]
    document=quake_map.MapDoc([
        quake_map.Entity(dict(classname='worldspawn',message='DK3 animation authoring studio',ambient='35'),brushes),
        quake_map.Entity(dict(classname='info_player_start',origin='240 -180 24',angle='145')),
        quake_map.Entity(dict(classname='trigger_script',targetname='author_preview',cinescript=name),[trigger]),
        quake_map.Entity(dict(classname='light',origin='0 -120 140',light='650')),
        quake_map.Entity(dict(classname='light',origin='0 120 130',light='400'))])
    # intr* selects the existing opening-character performance family; no
    # private source model or runtime class admission is needed for this map.
    mapname='intr_anim';quake_map.write_map(document,root/(mapname+'.map'))
    bsp,report=map_build.compile_map(base,root,mapname,False,[shader,'textures/authoring/trigger'])
    navigation=map_build.bot_navigation(Path(prefix).resolve(),bsp,root,mapname)
    destination=root/'zzz-dk3-animation-studio.pk3'
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED) as z:
        z.write(bsp,f'maps/{mapname}.bsp');z.write(program,f'dk3/cinematics/{name}.cfg')
        z.write(navigation['selection'],f'dk3/navigation/{mapname}.cfg')
        for stem,path in navigation['aas'].items():z.write(path,f'maps/{stem}.aas')
        z.write(base/'scripts/authoring.shader','scripts/authoring.shader');z.write(base/'textures/authoring/studio.png','textures/authoring/studio.png')
    report.pop('shader_text',None)
    receipt=dict(passed=True,map=mapname,program=name,trigger_id=3,package=destination.name,sha256=schema.sha(destination),
                 source_program_sha256=schema.sha(program),bsp=report,navigation=navigation['variants'])
    schema.write_json(root/'studio.json',receipt)
    return receipt


def record(args):
    report=fresh(args.report,True);engine=args.engine.resolve();inputs=[]
    identity=record_identity(engine,engine,report,require_installation=True)
    overlays={str(path.resolve()):schema.sha(path) for path in args.overlay}
    with tempfile.TemporaryDirectory(prefix='dk3-author-preview-') as temporary:
        home=Path(temporary);stage_client_modules(engine,home,installation=engine)
        for i,path in enumerate(args.overlay):shutil.copy2(path,home/'dk3'/f'zzz-author-{i:02}.pk3')
        settings=client_settings(engine,home,args.renderer)
        settings.update(dk3_cinematics='1',developer='1',r_picmip='0',r_customwidth='960',r_customheight='540',
                        cg_neuralCinematics='1' if args.presentation=='skeletal' else '0')
        excluded=presentation_settings(engine,home,settings,args.presentation,args.overlay)
        command=[str(args.guard.resolve()),'--headless','--',str(engine/'bin/dk3')]
        for key,value in settings.items():command+=['+set',key,value]
        command+=['+devmap',args.map]
        log=report/'client.log'
        with log.open('w') as output:
            process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
            driver=NativeInput(process,home/'dk3/commands.fifo',log,home,inputs,diagnostic=True)
            try:
                wait(process,log,lambda text:engine_failure(text) or ('first snapshot applied' in text and driver.pipe.exists()),60)
                driver.until(lambda s:s['mode']=='normal' and s['map']==args.map,description='preview map admitted')
                driver.issue('record author_preview');driver.elapsed(200)
                driver.issue(f'dk3_runtime_activate {args.trigger} player')
                driver.until(lambda s:s['cinematic'] and s['mode']=='frozen',description='compiled scene owns camera')
                rows=[];performances=[];shots=set();captured=set();last_save=None;deadline=time.monotonic()+args.seconds
                while time.monotonic()<deadline:
                    state=driver.observe();rows.append(state)
                    if state['cinematic']:
                        shots.add(state['shot'])
                        key=(state['shot'],state['now']//500)
                        if key not in captured:
                            captured.add(key);name=f'shot-{state["shot"]:03}-{state["now"]:08}'
                            actors=driver.diagnostics('dk3_runtime_performers','dk3 performers:')
                            rendered=driver.diagnostics('dk3_runtime_presentation','dk3 presentation:')
                            performances.append(dict(shot=state['shot'],now=state['now'],actors=actors,presentation=rendered))
                            driver.issue('screenshotJPEG '+name);source=home/f'dk3/screenshots/{name}.jpg'
                            wait(process,log,lambda _:source.exists() and source.stat().st_size>0,5);shutil.copy2(source,report/source.name)
                        if args.restore and last_save is None and state['shot']==0:
                            saved=driver.save('author_preview');shutil.copy2(saved,report/saved.name);last_save=saved.name
                    elif state['mode']=='normal':break
                else:raise TimeoutError('compiled scene did not release camera/input')
                shots|=cinematic_shots(driver.text(),inputs,args.map,args.program,args.shots)
                if shots!=set(range(args.shots)):raise RuntimeError(f'incomplete compiled scene: {shots}/{args.shots}')
                driver.issue('stoprecord');driver.elapsed(200)
                demos=list((home/'dk3/demos').glob('author_preview.dm_*'))
                if len(demos)!=1 or demos[0].stat().st_size<1000:raise RuntimeError('native scene recording missing')
                demo=report/demos[0].name;shutil.copy2(demos[0],demo)
                restoration=None
                if last_save:
                    restoration=driver.load('author_preview')
                    if not restoration['cinematic']:raise RuntimeError('scene save did not restore active playback')
                    driver.until(lambda s:not s['cinematic'] and s['mode']=='normal',seconds=args.seconds,description='restored scene released input')
                driver.issue('quit');code=process.wait(timeout=15)
                if code:raise RuntimeError('native preview exited '+str(code))
                receipt=dict(passed=True,identity=identity,overlays=overlays,scene=args.program,map=args.map,shots=sorted(shots),
                             presentation=args.presentation,excluded_packages=excluded,
                             samples=rows,performances=performances,demo=demo.name,demo_sha256=schema.sha(demo),restoration=restoration,
                             scope='Explicit diagnostic fixture, native camera/actor playback, release and optional save/load; no campaign or artistic acceptance claim')
                schema.write_json(report/'recording.json',receipt)
            except Exception as error:
                schema.write_json(report/'failure.json',dict(error=str(error),identity=identity,overlays=overlays));raise
            finally:
                schema.write_json(report/'inputs.json',inputs)
                if process.poll() is None:process.kill();process.wait(timeout=10)
    return receipt


def replay(args):
    directory=fresh(args.report,True);engine=args.engine.resolve();demo=args.demo.resolve()
    identity=record_identity(engine,engine,directory,require_installation=True)
    overlays={str(p.resolve()):schema.sha(p) for p in args.overlay}
    recorded_path=demo.parent/'recording.json'
    if not recorded_path.is_file():raise schema.Error('demo replay requires its recording.json identity receipt')
    recorded=json.loads(recorded_path.read_text())
    if not recorded.get('passed') or recorded['identity']!=identity or recorded['overlays']!=overlays or recorded['demo_sha256']!=schema.sha(demo):
        raise schema.Error('demo, runtime or overlays differ from recorded identity')
    if recorded.get('presentation','skeletal')!=args.presentation:raise schema.Error('demo presentation differs from requested replay')
    with tempfile.TemporaryDirectory(prefix='dk3-author-video-') as temporary:
        home=Path(temporary);stage_client_modules(engine,home,installation=engine)
        (home/'dk3/demos').mkdir();shutil.copy2(demo,home/'dk3/demos'/demo.name)
        for i,path in enumerate(args.overlay):shutil.copy2(path,home/'dk3'/f'zzz-author-{i:02}.pk3')
        settings=client_settings(engine,home,args.renderer)
        settings.update(dk3_cinematics='1',cl_aviFrameRate=str(args.fps),cl_aviMotionJpeg='1',r_picmip='0',nextdemo='echo DK3_AUTHOR_DEMO_DONE',
                        cg_neuralCinematics='1' if args.presentation=='skeletal' else '0')
        excluded=presentation_settings(engine,home,settings,args.presentation,args.overlay)
        command=[str(args.guard.resolve()),'--headless','--',str(engine/'bin/dk3')]
        for key,value in settings.items():command+=['+set',key,value]
        command+=['+demo',demo.stem]
        log=directory/'replay.log';pipe=home/'dk3/commands.fifo'
        with log.open('w') as output:
            process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT)
            try:
                wait(process,log,lambda text:engine_failure(text) or ('first snapshot applied' in text and pipe.exists()),60)
                send(pipe,'video author_preview')
                wait(process,log,lambda text:engine_failure(text) or 'DK3_AUTHOR_DEMO_DONE' in text,args.seconds)
                if failure:=engine_failure(log.read_text(errors='replace')):raise RuntimeError(failure)
                send(pipe,'stopvideo');send(pipe,'quit')
                if process.wait(timeout=15):raise RuntimeError('demo replay exited with failure')
                videos=list((home/'dk3/videos').glob('author_preview*.avi'))
                if len(videos)!=1 or videos[0].stat().st_size<1000:raise RuntimeError('engine AVI capture missing')
                avi=directory/'author_preview.avi';shutil.copy2(videos[0],avi)
                mp4=directory/'author_preview.mp4'
                subprocess.run(['ffmpeg','-nostdin','-v','error','-i',str(avi),'-c:v','libx264','-crf','18','-pix_fmt','yuv420p',str(mp4)],check=True,timeout=180)
                metadata=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(mp4)]))
                receipt=dict(passed=True,identity=identity,demo_sha256=schema.sha(demo),overlays=overlays,
                             presentation=args.presentation,excluded_packages=excluded,
                             fps=args.fps,video=mp4.name,sha256=schema.sha(mp4),metadata=metadata,scope='Engine demo replay to AVI and H.264; exact recorded snapshots and cosmetic overlay hashes')
                schema.write_json(directory/'video.json',receipt)
            except Exception as error:
                schema.write_json(directory/'failure.json',dict(error=str(error),identity=identity));raise
            finally:
                if process.poll() is None:process.kill();process.wait(timeout=10)
    return receipt


def main():
    parser=argparse.ArgumentParser(description=__doc__);sub=parser.add_subparsers(dest='operation',required=True)
    p=sub.add_parser('studio');p.add_argument('program',type=Path);p.add_argument('--out',type=Path,required=True);p.add_argument('--prefix',type=Path,default=Path('zig-out/native-dev'))
    for op in ('record','replay'):
        p=sub.add_parser(op);p.add_argument('--engine',type=Path,required=True);p.add_argument('--guard',type=Path,default=Path('zig-out/native-dev/bin/dkguard'))
        p.add_argument('--report',type=Path,required=True);p.add_argument('--overlay',type=Path,action='append',default=[])
        p.add_argument('--renderer',choices=('opengl1','opengl2'),default='opengl2');p.add_argument('--seconds',type=float,default=90)
        p.add_argument('--presentation',choices=('skeletal','legacy','fallback'),default='skeletal',
                       help='fallback keeps the optional package present but uses original cinematic models')
        p.add_argument('--guarded',action='store_true',help=argparse.SUPPRESS)
        if op=='record':
            p.add_argument('--map',default='intr_anim');p.add_argument('--program',default='author_studio');p.add_argument('--trigger',type=int,default=3)
            p.add_argument('--shots',type=int,required=True);p.add_argument('--restore',action='store_true')
        else:p.add_argument('--demo',type=Path,required=True);p.add_argument('--fps',type=int,default=30)
    args=parser.parse_args()
    if args.operation!='studio':
        validate_arguments(args)
    if args.operation!='studio' and not args.guarded:
        command=[str(args.guard.resolve()),'--headless','--mem','8G','--timeout',str(int(args.seconds+120))+'s','--',
                 '/usr/bin/python3','-B',str(Path(__file__).resolve()),*sys.argv[1:],'--guarded']
        sys.exit(subprocess.run(command).returncode)
    result=studio(args.program,args.out,args.prefix) if args.operation=='studio' else record(args) if args.operation=='record' else replay(args)
    print(json.dumps({k:v for k,v in result.items() if k not in ('samples','performances','metadata')},indent=2))


if __name__=='__main__':
    try:
        main()
    except schema.Error as error:
        print(json.dumps(dict(passed=False,diagnostics=[error.diagnostic()])),file=sys.stderr)
        raise SystemExit(1)
