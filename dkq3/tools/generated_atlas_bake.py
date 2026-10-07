#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bake bounded material corrections per texel, retaining the source UV atlas.

No vertex-colour interpolation, nearest-neighbour repaint or image projection.
The source texture is evaluated directly at each baked texel. Only brown skin
colour in declared cotton regions and already dark leather are corrected.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import numpy as np
import animation_manifest as schema
from generated_materials import garment_colors, material_nodes
import skeletal_iqm as sk


def correct_samples(points: np.ndarray, rgb: np.ndarray) -> tuple[np.ndarray, dict]:
    """Report the bounded correction policy without depending on Blender."""
    if rgb.shape!=points.shape or not np.isfinite(rgb).all() or np.any((rgb<0)|(rgb>1)):
        raise schema.Error('finite RGB samples required','ANIM_NONFINITE_TRANSFORM')
    regions=garment_colors(points)
    cotton=np.isclose(regions[:,0],.78)&((rgb[:,0]-rgb[:,2])>.16)&((rgb[:,0]-rgb[:,1])>.065)
    leather=np.isclose(regions[:,0],.045)&(rgb.max(axis=1)<.38)
    result=rgb.copy();level=np.clip(rgb[cotton].mean(axis=1)*1.4,0,1)
    result[cotton]=level[:,None]*[1.,.985,.95];result[leather]*=.7
    return result,dict(cotton_correction_samples=int(cotton.sum()),leather_samples=int(leather.sum()),samples=len(rgb))


def bake(input_path: Path, texture: Path, output: Path) -> dict:
    import bpy
    import dkimg
    from generated_materials import sample_uv_rgb
    if input_path.stat().st_size>32*1024*1024 or texture.stat().st_size>64*1024*1024:
        raise schema.Error('material input exceeds limits')
    model=sk.read(input_path.read_bytes());pixels=dkimg.read_png(texture)
    if pixels.shape[:2]!=(4096,4096):raise schema.Error('4096px source atlas required')
    if output.exists():raise schema.Error('material output must be fresh')
    points=model.arrays[0];height=np.ptp(points[:,2]);low=points[:,2].min()
    if not 10<=height<=200:raise schema.Error('implausible neutral mesh height')
    cy=(points[:,1].min()+points[:,1].max())*.5;z=(points[:,2]-low)*56/height-24
    torso=points[(z>8)&(z<20)&(np.abs(points[:,1]-cy)<height/10)]
    if len(torso)<8:raise schema.Error('unobservable neutral torso')
    origin=np.array([np.median(torso[:,0]),cy,low+24*height/56]);scale=56/height
    _,summary=correct_samples((points-origin)*scale,sample_uv_rgb(pixels,model.arrays[1]))
    if summary['cotton_correction_samples']>len(points)*.08:
        raise schema.Error('cotton contamination exceeds local correction budget; regenerate the source','ANIM_MATERIAL_CONTAMINATION')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh=bpy.data.meshes.new('preserved generated surface');mesh.from_pydata(points.tolist(),[],model.triangles[:,[0,2,1]].tolist());mesh.update()
    obj=bpy.data.objects.new('generated character',mesh);bpy.context.collection.objects.link(obj)
    uv=mesh.uv_layers.new(name='source atlas')
    for loop in mesh.loops:
        u,v=model.arrays[1][loop.vertex_index];uv.data[loop.index].uv=(u,1-v)
    material=bpy.data.materials.new('per texel source material');material.use_nodes=True;mesh.materials.append(material)
    nodes=material.node_tree.nodes;links=material.node_tree.links
    image=nodes.new('ShaderNodeTexImage');image.image=bpy.data.images.load(str(texture.resolve()));image.image.colorspace_settings.name='Non-Color'
    image.interpolation='Linear';image.extension='EXTEND'
    def math(op,a,b):
        node=nodes.new('ShaderNodeMath');node.operation=op
        for i,value in enumerate((a,b)):
            if isinstance(value,(float,int)):node.inputs[i].default_value=value
            else:links.new(value,node.inputs[i])
        return node.outputs[0]
    def separate(color):
        node=nodes.new('ShaderNodeSeparateXYZ');links.new(color,node.inputs[0]);return [node.outputs[i] for i in range(3)]
    def mix(mask,a,b):
        node=nodes.new('ShaderNodeMixRGB');links.new(mask,node.inputs[0]);links.new(a,node.inputs[1]);links.new(b,node.inputs[2]);return node.outputs[0]
    regions,_=material_nodes(nodes,links,origin,scale);label=separate(regions)[0];r,g,b=separate(image.outputs['Color'])
    cotton=math('LESS_THAN',math('ABSOLUTE',math('SUBTRACT',label,.78),0),.001)
    cotton=math('MULTIPLY',cotton,math('GREATER_THAN',math('SUBTRACT',r,b),.16))
    cotton=math('MULTIPLY',cotton,math('GREATER_THAN',math('SUBTRACT',r,g),.065))
    level=math('MINIMUM',math('MULTIPLY',math('ADD',math('ADD',r,g),b),1.4/3),1.)
    tint=nodes.new('ShaderNodeVectorMath');tint.operation='SCALE';tint.inputs[0].default_value=(1.,.985,.95);links.new(level,tint.inputs['Scale'])
    color=mix(cotton,image.outputs['Color'],tint.outputs['Vector'])
    leather=math('LESS_THAN',math('ABSOLUTE',math('SUBTRACT',label,.045),0),.001)
    leather=math('MULTIPLY',leather,math('LESS_THAN',math('MAXIMUM',math('MAXIMUM',r,g),b),.38))
    dark=nodes.new('ShaderNodeVectorMath');dark.operation='SCALE';dark.inputs['Scale'].default_value=.7;links.new(color,dark.inputs[0])
    color=mix(leather,color,dark.outputs['Vector'])
    emission=nodes.new('ShaderNodeEmission');links.new(color,emission.inputs['Color']);links.new(emission.outputs[0],nodes.get('Material Output').inputs['Surface'])
    target_image=bpy.data.images.new('preserved atlas correction',width=4096,height=4096,alpha=False);target_image.colorspace_settings.name='Non-Color'
    target=nodes.new('ShaderNodeTexImage');target.image=target_image;nodes.active=target
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
    bpy.context.view_layer.objects.active=obj;obj.select_set(True);bpy.ops.object.bake(type='EMIT',use_selected_to_active=False,margin=8)
    values=np.empty(len(target_image.pixels),np.float32);target_image.pixels.foreach_get(values)
    rgb=np.rint(np.clip(values.reshape(4096,4096,4)[::-1,:,:3],0,1)*255).astype('u1')
    output.mkdir(parents=True);temporary=output/'body.partial';temporary.write_bytes(dkimg.encode_png(rgb));temporary.replace(output/'body.png')
    report=dict(passed=True,method='per_texel_generated_atlas',input_sha256=schema.sha(input_path),
        source_texture_sha256=schema.sha(texture),output_sha256=schema.sha(output/'body.png'),tool_sha256=schema.sha(Path(__file__)),
        blender=bpy.app.version_string,texture_size=[4096,4096],corrections=summary,vertex_colour_bake=False,
        originals_modified=False,visual_acceptance='unverified')
    schema.write_json(output/'materials.json',report);return report


def main() -> None:
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--texture',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    print(json.dumps(bake(args.input,args.texture,args.out),sort_keys=True))


if __name__=='__main__':main()
