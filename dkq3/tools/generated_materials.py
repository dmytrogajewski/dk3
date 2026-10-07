#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Bake cloth, leather and skin materials on the new neutral generated mesh.

Source images remain read-only. Optional measured generated-surface transfer
preserves fabric detail, repairs hair/skin contamination in declared cloth
regions and bakes to the qualified atlas without ray-projection misses.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import numpy as np
import animation_manifest as schema
import skeletal_iqm as sk


def transferred_uv(points: np.ndarray, uv: np.ndarray, triangle: np.ndarray,
                   closest: np.ndarray) -> np.ndarray:
    """Interpolate the generated source atlas at a measured surface point."""
    if triangle.shape!=(3,) or triangle.dtype.kind not in 'iu' or triangle.min()<0 or triangle.max()>=len(points):
        raise schema.Error('invalid source triangle','ANIM_INVALID_RANGE')
    a,b,c=points[triangle];ab=b-a;ac=c-a;ap=closest-a
    aa=ab@ab;bb=ac@ac;cross=ab@ac;denominator=aa*bb-cross*cross
    if not np.isfinite([*a,*b,*c,*closest,denominator]).all() or denominator<=1e-16:
        raise schema.Error('degenerate source triangle','ANIM_NONFINITE_TRANSFORM')
    v=(bb*(ap@ab)-cross*(ap@ac))/denominator
    w=(aa*(ap@ac)-cross*(ap@ab))/denominator
    amounts=np.maximum([1-v-w,v,w],0);amounts/=amounts.sum()
    return amounts@uv[triangle]


def sample_uv_rgb(image: np.ndarray, uv: np.ndarray) -> np.ndarray:
    """Sample a top-left-origin IQM atlas without interpolating across charts."""
    if image.ndim!=3 or image.shape[2]<3 or uv.ndim!=2 or uv.shape[1]!=2 or not np.isfinite(uv).all():
        raise schema.Error('invalid source atlas sample','ANIM_NONFINITE_TRANSFORM')
    xy=np.clip(uv,0,1)*[image.shape[1]-1,image.shape[0]-1]
    a=np.floor(xy).astype(int);b=np.minimum(a+1,[image.shape[1]-1,image.shape[0]-1]);t=xy-a
    rgb=image[:,:,:3].astype(float)/255.
    first=rgb[a[:,1],a[:,0]]*(1-t[:,0,None])+rgb[a[:,1],b[:,0]]*t[:,0,None]
    last=rgb[b[:,1],a[:,0]]*(1-t[:,0,None])+rgb[b[:,1],b[:,0]]*t[:,0,None]
    return first*(1-t[:,1,None])+last*t[:,1,None]


def repair_generated_albedo(points: np.ndarray, colors: np.ndarray) -> tuple[np.ndarray,dict]:
    """Remove reconstructed hair/skin stains from declared cloth regions in 3D.

    Sample neighbouring generated cotton rather than projecting a different
    portrait or copying the retail clothing atlas. Preserve valid fold shading.
    """
    if colors.shape!=points.shape or not np.isfinite(colors).all():
        raise schema.Error('invalid generated surface colors','ANIM_NONFINITE_TRANSFORM')
    regions=garment_colors(points);cloth=np.isclose(regions[:,0],.78);leather=np.isclose(regions[:,0],.045)
    brightness=colors.mean(axis=1)
    valid=cloth&(brightness>.38)&(np.ptp(colors,axis=1)<.1)
    rejected=cloth&~valid
    if valid.sum()<8:raise schema.Error('generated cotton surface is unobservable')
    result=colors.copy()
    if rejected.any():
        try:
            from mathutils.kdtree import KDTree
        except ModuleNotFoundError:
            from scipy.spatial import cKDTree
            distance,nearest=cKDTree(points[valid]).query(points[rejected],k=4)
        else:
            # Blender ships its own tree; do not require a separate SciPy
            # wheel in Blender's Python environment.
            tree=KDTree(int(valid.sum()))
            for index,point in enumerate(points[valid]):tree.insert(point,index)
            tree.balance();rows=[tree.find_n(point,4) for point in points[rejected]]
            distance=np.asarray([[row[2] for row in group] for group in rows])
            nearest=np.asarray([[row[1] for row in group] for group in rows])
        influence=1/np.maximum(distance,.05)**2;influence/=influence.sum(axis=1,keepdims=True)
        result[rejected]=np.einsum('vi,vic->vc',influence,colors[valid][nearest])
    # Existing generated seams remain; darken the grey reconstructed bracers,
    # lapels, belt and panels to the original design's black leather palette.
    result[leather]*=.45
    return result,dict(cloth_samples=int(cloth.sum()),repaired_cloth_samples=int(rejected.sum()),
                       method='Nearest valid generated cotton samples in neutral 3D; retained source fold shading; black leather palette')


def garment_colors(points: np.ndarray) -> np.ndarray:
    """Material regions in the measured neutral +X-forward, Z-up rig space."""
    if points.ndim!=2 or points.shape[1]!=3 or not np.isfinite(points).all():
        raise schema.Error('finite neutral points required','ANIM_NONFINITE_TRANSFORM')
    x,y,z=points.T;side=np.abs(y)
    ivory=np.array([.78,.765,.715]);leather=np.array([.045,.05,.043]);skin=np.array([.62,.43,.31])
    result=np.broadcast_to(skin,(len(points),3)).copy()
    torso=(side<7.8)&(z>11.5)&(z<23.5)
    sleeve=np.zeros(len(points),dtype=bool)
    for sign in (1,-1):
        a=np.array([0,sign*7,20]);b=np.array([0,sign*12,12]);delta=b-a
        t=(points-a)@delta/(delta@delta)
        distance=np.linalg.norm(points-(a+t[:,None]*delta),axis=1)
        sleeve|=(t<.65)&(t>-.4)&(distance<5)&(y*sign>5)
    lower=(z<7)&(side<13)
    result[torso|sleeve|lower]=ivory
    opening=(x>1.)&(z>11.3)&(z<24)&(side<(z-11.3)*.25)
    lapel=(x>.5)&(z>10.5)&(z<24)&(np.abs(side-(z-11.3)*.25)<.6)
    result[opening]=skin;result[lapel]=leather
    obi=(z>=7)&(z<=11.5)&(side<8.5)
    panels=(z<7)&(z>-16)&(side>7.7)&(side<13)
    front=(z>-5)&(z<7)&(side<2.1)&(x>.6)
    boots=z<-16
    result[obi|panels|front|boots]=leather
    # Preserve exposed upper arms and hands between sleeve/bracer boundaries.
    for sign in (1,-1):
        a=np.array([0,sign*12,12]);b=np.array([0,sign*15.5,5]);delta=b-a
        t=(points-a)@delta/(delta@delta)
        distance=np.linalg.norm(points-(a+t[:,None]*delta),axis=1)
        bracer=(t>.22)&(t<.97)&(distance<2.7)&(y*sign>10)
        result[bracer]=leather
    return result


def material_nodes(nodes, links, offset: np.ndarray, scale: float):
    """Evaluate the material regions per surface sample, giving crisp boundaries."""
    def math(op, a, b=None):
        node=nodes.new('ShaderNodeMath');node.operation=op
        for j,value in enumerate((a,b)):
            if value is None:continue
            if isinstance(value,(int,float)):node.inputs[j].default_value=value
            else:links.new(value,node.inputs[j])
        return node.outputs[0]
    def all_of(*values):
        result=values[0]
        for value in values[1:]:result=math('MULTIPLY',result,value)
        return result
    def any_of(*values):
        result=values[0]
        for value in values[1:]:result=math('MAXIMUM',result,value)
        return result
    def greater(a,b):return math('GREATER_THAN',a,b)
    def less(a,b):return math('LESS_THAN',a,b)
    def add(a,b):return math('ADD',a,b)
    def sub(a,b):return math('SUBTRACT',a,b)
    def mul(a,b):return math('MULTIPLY',a,b)
    def sqr(a):return mul(a,a)
    geometry=nodes.new('ShaderNodeNewGeometry');origin=nodes.new('ShaderNodeVectorMath');origin.operation='SUBTRACT'
    origin.inputs[1].default_value=offset;links.new(geometry.outputs['Position'],origin.inputs[0])
    normalize=nodes.new('ShaderNodeVectorMath');normalize.operation='SCALE';normalize.inputs['Scale'].default_value=scale
    links.new(origin.outputs['Vector'],normalize.inputs[0]);xyz=nodes.new('ShaderNodeSeparateXYZ');links.new(normalize.outputs['Vector'],xyz.inputs[0])
    x,y,z=(xyz.outputs[k] for k in ('X','Y','Z'));side=math('ABSOLUTE',y)
    torso=all_of(less(side,7.8),greater(z,11.5),less(z,23.5));lower=all_of(less(z,7),less(side,13))
    sleeves=[];bracers=[]
    for sign in (1,-1):
        lateral=mul(y,sign)
        t=math('DIVIDE',add(mul(sub(lateral,7),5),mul(sub(z,20),-8)),89.)
        distance=add(sqr(x),add(sqr(sub(lateral,add(7,mul(t,5)))),sqr(sub(z,sub(20,mul(t,8))))))
        sleeves.append(all_of(less(t,.65),greater(t,-.4),less(distance,25),greater(lateral,5)))
        t=math('DIVIDE',add(mul(sub(lateral,12),3.5),mul(sub(z,12),-7)),61.25)
        distance=add(sqr(x),add(sqr(sub(lateral,add(12,mul(t,3.5)))),sqr(sub(z,sub(12,mul(t,7))))))
        bracers.append(all_of(greater(t,.22),less(t,.97),less(distance,2.7**2),greater(lateral,10)))
    v=mul(sub(z,11.3),.25)
    opening=all_of(greater(x,1.),greater(z,11.3),less(z,24),less(side,v))
    lapel=all_of(greater(x,.5),greater(z,10.5),less(z,24),less(math('ABSOLUTE',sub(side,v)),.6))
    obi=all_of(greater(z,7),less(z,11.5),less(side,8.5))
    panels=all_of(less(z,7),greater(z,-16),greater(side,7.7),less(side,13))
    front=all_of(greater(z,-5),less(z,7),less(side,2.1),greater(x,.6));boots=less(z,-16)
    skin=(.62,.43,.31,1);ivory=(.78,.765,.715,1);leather=(.045,.05,.043,1)
    def mix(mask,a,b):
        node=nodes.new('ShaderNodeMixRGB');links.new(mask,node.inputs[0])
        for j,value in enumerate((a,b),1):
            if isinstance(value,tuple):node.inputs[j].default_value=value
            else:links.new(value,node.inputs[j])
        return node.outputs[0]
    color=mix(any_of(torso,lower,*sleeves),skin,ivory);color=mix(opening,color,skin)
    color=mix(any_of(lapel,obi,panels,front,boots,*bracers),color,leather)
    return color,geometry.outputs['Position']


def bake(input_path: Path, output: Path, source: Path | None = None) -> dict:
    import bpy
    import dkimg
    if input_path.stat().st_size>32*1024*1024:raise schema.Error('neutral mesh exceeds limit')
    model=sk.read(input_path.read_bytes())
    if output.exists() and any(output.iterdir()):raise schema.Error('material output already exists')
    output.mkdir(parents=True,exist_ok=True)
    points=model.arrays[0];height=np.ptp(points[:,2]);low=points[:,2].min()
    if not 10<=height<=200:raise schema.Error('implausible neutral mesh scale')
    cy=(points[:,1].min()+points[:,1].max())*.5;z=(points[:,2]-low)*56/height-24
    torso=points[(z>8)&(z<20)&(np.abs(points[:,1]-cy)<height/10)]
    if len(torso)<8:raise schema.Error('neutral torso is unobservable')
    normalized=(points-[np.median(torso[:,0]),cy,low+24*height/56])*56/height
    garment_colors(normalized)  # Reject nonfinite/invalid coordinates before Blender.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh=bpy.data.meshes.new('generated gi material surface')
    mesh.from_pydata(points.tolist(),[],model.triangles[:,[0,2,1]].tolist());mesh.update()
    obj=bpy.data.objects.new('generated gi',mesh);bpy.context.collection.objects.link(obj)
    uv=mesh.uv_layers.new(name='qualified atlas')
    for loop in mesh.loops:
        u,v=model.arrays[1][loop.vertex_index];uv.data[loop.index].uv=(u,1-v)
    material=bpy.data.materials.new('new gi cloth, leather and skin');material.use_nodes=True
    mesh.materials.append(material);nodes=material.node_tree.nodes;links=material.node_tree.links
    source_receipt={}
    if source:
        from mathutils import Vector
        from mathutils.bvhtree import BVHTree
        source_path=source/'model.iqm';texture_path=source/'body.png'
        if source_path.stat().st_size>32*1024*1024 or texture_path.stat().st_size>64*1024*1024:
            raise schema.Error('generated material source exceeds limits')
        original=sk.read(source_path.read_bytes())
        tree=BVHTree.FromPolygons(original.arrays[0].tolist(),original.triangles.tolist(),all_triangles=True)
        mapped=[];distances=[]
        for point in points:
            nearest=tree.find_nearest(Vector(point))
            if nearest is None:raise schema.Error('generated material source is unobservable')
            closest,_,face,distance=nearest
            mapped.append(transferred_uv(original.arrays[0],original.arrays[1],original.triangles[face],np.asarray(closest)))
            distances.append(distance)
        pixels=dkimg.read_png(texture_path)
        if pixels.shape[:2]!=(4096,4096):raise schema.Error('generated source atlas must be 4096px')
        colors=sample_uv_rgb(pixels,np.asarray(mapped))
        colors,repair=repair_generated_albedo(normalized,colors)
        attribute=mesh.color_attributes.new(name='measured generated albedo',type='FLOAT_COLOR',domain='CORNER')
        for loop in mesh.loops:attribute.data[loop.index].color=(*colors[loop.vertex_index],1.)
        detail=nodes.new('ShaderNodeVertexColor');detail.layer_name=attribute.name
        # Original generated folds, seams and skin detail survive. The bounded
        # nearest-surface query also fills closed patches where ray projection
        # misses. Reduce the albedo for the native renderer's lighting gain.
        value=nodes.new('ShaderNodeVectorMath');value.operation='SCALE';value.inputs['Scale'].default_value=.72
        links.new(detail.outputs['Color'],value.inputs[0]);color=value.outputs['Vector']
        position=nodes.new('ShaderNodeNewGeometry').outputs['Position']
        source_receipt=dict(source_iqm_sha256=schema.sha(source_path),source_texture_sha256=schema.sha(texture_path),
                            surface_distance_max=float(max(distances)),albedo_scale=.72,material_repair=repair)
    else:
        color,position=material_nodes(nodes,links,np.array([np.median(torso[:,0]),cy,low+24*height/56]),56/height)
    # Fine deterministic surface grain is baked into the albedo; folds/seams
    # remain actual generated geometry rather than painted shadow patches.
    grain=nodes.new('ShaderNodeTexNoise');grain.inputs['Scale'].default_value=120
    grain.inputs['Detail'].default_value=2;grain.inputs['Roughness'].default_value=.6
    links.new(position,grain.inputs['Vector'])
    value=nodes.new('ShaderNodeMath');value.operation='MULTIPLY_ADD'
    value.inputs[1].default_value=.08;value.inputs[2].default_value=.96;links.new(grain.outputs['Fac'],value.inputs[0])
    multiply=nodes.new('ShaderNodeVectorMath');multiply.operation='SCALE'
    links.new(color,multiply.inputs[0]);links.new(value.outputs[0],multiply.inputs['Scale'])
    emission=nodes.new('ShaderNodeEmission');links.new(multiply.outputs['Vector'],emission.inputs['Color'])
    links.new(emission.outputs[0],nodes.get('Material Output').inputs['Surface'])
    image=bpy.data.images.new('new gi albedo',width=4096,height=4096,alpha=False)
    image.colorspace_settings.name='Non-Color';target=nodes.new('ShaderNodeTexImage');target.image=image;nodes.active=target
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=1
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    bpy.ops.object.bake(type='EMIT',use_selected_to_active=False,margin=8)
    pixels=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(pixels)
    rgb=np.rint(np.clip(pixels.reshape(4096,4096,4)[::-1,:,:3],0,1)*255).astype('u1')
    destination=output/'body.png';temporary=output/'body.partial'
    temporary.write_bytes(dkimg.encode_png(rgb));temporary.replace(destination)
    result=dict(passed=True,input_sha256=schema.sha(input_path),output_sha256=schema.sha(destination),
                tool_sha256=schema.sha(Path(__file__)),blender=bpy.app.version_string,texture_size=[4096,4096],
                method=('generated_surface_transfer' if source else 'direct_semantic_surface_bake'),
                originals_modified=False,visual_acceptance='unverified')
    result.update(source_receipt)
    schema.write_json(output/'materials.json',result);return result


def main() -> None:
    import json
    argv=sys.argv[sys.argv.index('--')+1:]
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--source',type=Path,help='pinned generated geometry and its own albedo; closest-surface transfer')
    args=parser.parse_args(argv)
    print(json.dumps(bake(args.input,args.out,args.source),sort_keys=True))


if __name__=='__main__':main()
