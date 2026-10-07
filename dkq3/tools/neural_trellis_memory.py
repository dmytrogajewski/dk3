# SPDX-License-Identifier: GPL-2.0-or-later
"""Bound CuMesh topology temporaries without changing its remesh resolution."""
import inspect
import torch


def topology(coords, intersected, dual, hashmap, resolution, center, scale, tables):
    from cumesh import _C
    quads, directions = [], []
    for start in range(0, len(coords), 65536):
        cells, crosses = coords[start:start+65536], intersected[start:start+65536]
        neighbors = cells.reshape(-1,1,1,3)+tables.edge_neighbor_voxel_offset
        neighbors = neighbors[crosses!=0]
        crosses = crosses[crosses!=0]
        query = neighbors.reshape(-1,3)
        query = torch.cat([torch.zeros_like(query[:,:1]),query],dim=1)
        indices = _C.hashmap_lookup_3d_cuda(*hashmap,query,resolution,resolution,resolution).reshape(-1,4).int()
        valid = (indices!=0xffffffff).all(dim=1)
        quads.append(indices[valid].cpu())
        directions.append(crosses[valid].cpu())
    quads, directions = torch.cat(quads), torch.cat(directions)
    unique, inverse = torch.unique(quads.reshape(-1),sorted=True,return_inverse=True)
    quads = inverse.reshape(-1,4).int()
    vertices = (dual[unique.to(dual.device)]/resolution-.5)*scale+center
    triangles = []
    for start in range(0,len(quads),65536):
        corners = quads[start:start+65536].to(vertices.device)
        direction = (directions[start:start+65536].to(vertices.device)==1).unsqueeze(1)
        options, alignment = [], []
        for positive,negative in [(tables.quad_split_1_p,tables.quad_split_1_n),
                                  (tables.quad_split_2_p,tables.quad_split_2_n)]:
            candidate = torch.where(direction,corners[:,positive],corners[:,negative])
            a,b,c,d = [vertices[candidate[:,i]] for i in range(4)]
            n0,n1 = torch.cross(b-a,c-a,dim=1),torch.cross(c-b,d-b,dim=1)
            options.append(candidate)
            alignment.append((n0*n1).sum(dim=1).abs())
        chosen = torch.where((alignment[0]>alignment[1]).unsqueeze(1),*options)
        triangles.append(chosen.reshape(-1,3).cpu())
    return vertices,torch.cat(triangles).to(vertices.device)


def install():
    """Replace only the admitted upstream topology block; reject source drift."""
    import cumesh.remeshing as module
    original = inspect.getsource(module.remesh_narrow_band_dc)
    first = original.index('    # Find connected voxels\n')
    last = original.index('    # 8. Optional: Project back to exact surface')
    last = original.rfind('    # --------------------------------------------------------------------------',first,last)
    replacement = ('    del pts, distances, subdiv_mask, grid_verts, pts_vert, distances_vert, hashmap_vert\n'
                   '    torch.cuda.empty_cache()\n'
                   '    mesh_vertices, mesh_triangles = _bounded_topology(coords, intersected, dual_verts,\n'
                   '        hashmap_vox, resolution, center, scale, remesh_narrow_band_dc)\n'
                   '    del coords, intersected, dual_verts, hashmap_vox\n')
    module.__dict__['_bounded_topology'] = topology
    exec(compile(original[:first]+replacement+original[last:],'<dk3 bounded CuMesh topology>','exec'),module.__dict__)
