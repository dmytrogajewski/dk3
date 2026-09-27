/*
===========================================================================
Copyright (C) 1999-2005 Id Software, Inc.

This file is part of Quake III Arena source code.

Quake III Arena source code is free software; you can redistribute it
and/or modify it under the terms of the GNU General Public License as
published by the Free Software Foundation; either version 2 of the License,
or (at your option) any later version.

Quake III Arena source code is distributed in the hope that it will be
useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Quake III Arena source code; if not, write to the Free Software
Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
===========================================================================
*/
// cmodel.c -- model loading

#include "cm_local.h"

#ifdef BSPC

#include "../bspc/l_qfiles.h"

void SetPlaneSignbits (cplane_t *out) {
	int	bits, j;

	// for fast box on planeside test
	bits = 0;
	for (j=0 ; j<3 ; j++) {
		if (out->normal[j] < 0) {
			bits |= 1<<j;
		}
	}
	out->signbits = bits;
}
#endif //BSPC

// to allow boxes to be treated as brush models, we allocate
// some extra indexes along with those needed by the map
#define	BOX_BRUSHES		1
#define	BOX_SIDES		6
#define	BOX_LEAFS		2
#define	BOX_PLANES		12

#define	LL(x) x=LittleLong(x)


clipMap_t	cm;
int			c_pointcontents;
int			c_traces, c_brush_traces, c_patch_traces;


byte		*cmod_base;

#ifndef BSPC
cvar_t		*cm_noAreas;
cvar_t		*cm_noCurves;
cvar_t		*cm_playerCurveClip;
#endif

cmodel_t	box_model;
cplane_t	*box_planes;
cbrush_t	*box_brush;

/* The public CM entrypoints remain owner-thread operations. Each selection
 * restores all mutable per-world state, including the temporary box hull and
 * area-portal/check counters. Parsing workers must not call these entrypoints. */
#define CM_MAX_WORLDS 128
typedef struct cmAllocation_s {
    struct cmAllocation_s *next;
    /* malloc alignment is retained by returning a separately allocated block. */
    void *bytes;
} cmAllocation_t;
typedef struct {
    clipMap_t map;
    cmodel_t box;
    cplane_t *boxPlanes;
    cbrush_t *boxBrush;
    cmAllocation_t *allocations;
    size_t bytes;
    unsigned int generation, checksum;
    qboolean occupied;
    int ready;
    fsReadJob_t *read;
    char name[MAX_QPATH];
} cmWorld_t;
static cmWorld_t cm_worlds[CM_MAX_WORLDS];
static unsigned int cm_selected;

static cmWorld_t *CM_World(unsigned int handle) {
    unsigned int slot = handle & 255;
    if (!slot || slot > CM_MAX_WORLDS) return NULL;
    if (!cm_worlds[slot - 1].occupied || cm_worlds[slot - 1].generation != (handle >> 8)) return NULL;
    return &cm_worlds[slot - 1];
}

unsigned int CM_CurrentWorld(void) {
    cmWorld_t *world = &cm_worlds[cm_selected];
    if (!world->occupied) {
        world->occupied = qtrue;
        world->ready = 1;
        if (!world->generation) world->generation = 1;
    }
    return (world->generation << 8) | (cm_selected + 1);
}

qboolean CM_SelectWorld(unsigned int handle) {
    cmWorld_t *next = CM_World(handle), *old;
    if (!next || next->ready != 1) return qfalse;
    CM_CurrentWorld();
    old = &cm_worlds[cm_selected];
    old->map = cm;
    old->box = box_model;
    old->boxPlanes = box_planes;
    old->boxBrush = box_brush;
    cm_selected = (handle & 255) - 1;
    cm = next->map;
    box_model = next->box;
    box_planes = next->boxPlanes;
    box_brush = next->boxBrush;
    CM_ClearLevelPatches(); /* Debug pointers may refer to another world. */
    return qtrue;
}

void *CM_WorldAlloc(int size) {
    cmWorld_t *world;
    cmAllocation_t *block;
    CM_CurrentWorld();
    world = &cm_worlds[cm_selected];
    if (size < 0) Com_Error(ERR_DROP, "CM_WorldAlloc: invalid size");
    block = malloc(sizeof(*block));
    if (!block) Com_Error(ERR_DROP, "CM_WorldAlloc: out of memory");
    block->bytes = calloc(1, size ? size : 1);
    if (!block->bytes) { free(block); Com_Error(ERR_DROP, "CM_WorldAlloc: out of memory"); }
    block->next = world->allocations;
    world->allocations = block;
    world->bytes += size;
    return block->bytes;
}

static void CM_FreeWorld(cmWorld_t *world) {
    cmAllocation_t *block = world->allocations;
    unsigned int generation = world->generation;
    FS_EndBackgroundRead(world->read);
    while (block) {
        cmAllocation_t *next = block->next;
        free(block->bytes);
        free(block);
        block = next;
    }
    Com_Memset(world, 0, sizeof(*world));
    /* Retire an exhausted slot rather than making an old handle valid again. */
    world->generation = generation < 0x7fffff ? generation + 1 : generation;
}

qboolean CM_ReleaseWorld(unsigned int handle) {
    cmWorld_t *world = CM_World(handle);
    if (!world || world == &cm_worlds[cm_selected]) return qfalse;
    CM_FreeWorld(world);
    return qtrue;
}

const char *CM_WorldName(unsigned int handle) {
    cmWorld_t *world = CM_World(handle);
    return !world ? "" : world == &cm_worlds[cm_selected] ? cm.name : world->map.name;
}

int CM_WorldChecksum(unsigned int handle) {
    cmWorld_t *world = CM_World(handle);
    return world ? world->checksum : 0;
}

size_t CM_WorldBytes(unsigned int handle) {
    cmWorld_t *world = CM_World(handle);
    return world ? world->bytes : 0;
}



void	CM_InitBoxHull (void);
void	CM_FloodAreaConnections (void);


/*
===============================================================================

					MAP LOADING

===============================================================================
*/

/*
=================
CMod_LoadShaders
=================
*/
void CMod_LoadShaders( lump_t *l ) {
	dshader_t	*in, *out;
	int			i, count;

	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in)) {
		Com_Error (ERR_DROP, "CMod_LoadShaders: funny lump size");
	}
	count = l->filelen / sizeof(*in);

	if (count < 1) {
		Com_Error (ERR_DROP, "Map with no shaders");
	}
	cm.shaders = CM_WorldAlloc( count * sizeof( *cm.shaders ) );
	cm.numShaders = count;

	Com_Memcpy( cm.shaders, in, count * sizeof( *cm.shaders ) );

	out = cm.shaders;
	for ( i=0 ; i<count ; i++, in++, out++ ) {
		out->contentFlags = LittleLong( out->contentFlags );
		out->surfaceFlags = LittleLong( out->surfaceFlags );
	}
}


/*
=================
CMod_LoadSubmodels
=================
*/
void CMod_LoadSubmodels( lump_t *l ) {
	dmodel_t	*in;
	cmodel_t	*out;
	int			i, j, count;
	int			*indexes;
	int brushCount, surfaceCount;

	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "CMod_LoadSubmodels: funny lump size");
	count = l->filelen / sizeof(*in);

	if (count < 1)
		Com_Error (ERR_DROP, "Map with no models");
	cm.cmodels = CM_WorldAlloc( count * sizeof( *cm.cmodels ) );
	cm.numSubModels = count;

	if ( count > CAPSULE_MODEL_HANDLE ) {
		Com_Error( ERR_DROP, "MAX_SUBMODELS exceeded" );
	}
	/* Inline leaves must use real indices into their world's arrays. The
	 * upstream pointer subtraction relied on unrelated hunk allocations. */
	brushCount = cm.numLeafBrushes;
	surfaceCount = cm.numLeafSurfaces;
	for (i = 1; i < count; ++i) {
		int brushes = LittleLong(in[i].numBrushes), surfaces = LittleLong(in[i].numSurfaces);
		if (brushes < 0 || surfaces < 0 || brushes > 0x1000000 - brushCount || surfaces > 0x1000000 - surfaceCount)
			Com_Error(ERR_DROP, "CMod_LoadSubmodels: invalid leaf count");
		brushCount += brushes;
		surfaceCount += surfaces;
	}
	indexes = CM_WorldAlloc((brushCount + BOX_BRUSHES) * sizeof(int));
	Com_Memcpy(indexes, cm.leafbrushes, cm.numLeafBrushes * sizeof(int));
	cm.leafbrushes = indexes;
	indexes = CM_WorldAlloc(surfaceCount * sizeof(int));
	Com_Memcpy(indexes, cm.leafsurfaces, cm.numLeafSurfaces * sizeof(int));
	cm.leafsurfaces = indexes;

	for ( i=0 ; i<count ; i++, in++)
	{
		out = &cm.cmodels[i];

		for (j=0 ; j<3 ; j++)
		{	// spread the mins / maxs by a pixel
			out->mins[j] = LittleFloat (in->mins[j]) - 1;
			out->maxs[j] = LittleFloat (in->maxs[j]) + 1;
		}

		if ( i == 0 ) {
			continue;	// world model doesn't need other info
		}

		// make a "leaf" just to hold the model's brushes and surfaces
		out->leaf.numLeafBrushes = LittleLong( in->numBrushes );
		out->leaf.firstLeafBrush = cm.numLeafBrushes;
		indexes = cm.leafbrushes + cm.numLeafBrushes;
		cm.numLeafBrushes += out->leaf.numLeafBrushes;
		for ( j = 0 ; j < out->leaf.numLeafBrushes ; j++ ) {
			indexes[j] = LittleLong( in->firstBrush ) + j;
		}

		out->leaf.numLeafSurfaces = LittleLong( in->numSurfaces );
		out->leaf.firstLeafSurface = cm.numLeafSurfaces;
		indexes = cm.leafsurfaces + cm.numLeafSurfaces;
		cm.numLeafSurfaces += out->leaf.numLeafSurfaces;
		for ( j = 0 ; j < out->leaf.numLeafSurfaces ; j++ ) {
			indexes[j] = LittleLong( in->firstSurface ) + j;
		}
	}
}


/*
=================
CMod_LoadNodes

=================
*/
void CMod_LoadNodes( lump_t *l ) {
	dnode_t		*in;
	int			child;
	cNode_t		*out;
	int			i, j, count;
	
	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	count = l->filelen / sizeof(*in);

	if (count < 1)
		Com_Error (ERR_DROP, "Map has no nodes");
	cm.nodes = CM_WorldAlloc( count * sizeof( *cm.nodes ) );
	cm.numNodes = count;

	out = cm.nodes;

	for (i=0 ; i<count ; i++, out++, in++)
	{
		out->plane = cm.planes + LittleLong( in->planeNum );
		for (j=0 ; j<2 ; j++)
		{
			child = LittleLong (in->children[j]);
			out->children[j] = child;
		}
	}

}

/*
=================
CM_BoundBrush

=================
*/
void CM_BoundBrush( cbrush_t *b ) {
	b->bounds[0][0] = -b->sides[0].plane->dist;
	b->bounds[1][0] = b->sides[1].plane->dist;

	b->bounds[0][1] = -b->sides[2].plane->dist;
	b->bounds[1][1] = b->sides[3].plane->dist;

	b->bounds[0][2] = -b->sides[4].plane->dist;
	b->bounds[1][2] = b->sides[5].plane->dist;
}


/*
=================
CMod_LoadBrushes

=================
*/
void CMod_LoadBrushes( lump_t *l ) {
	dbrush_t	*in;
	cbrush_t	*out;
	int			i, count;

	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in)) {
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	}
	count = l->filelen / sizeof(*in);

	cm.brushes = CM_WorldAlloc( ( BOX_BRUSHES + count ) * sizeof( *cm.brushes ) );
	cm.numBrushes = count;

	out = cm.brushes;

	for ( i=0 ; i<count ; i++, out++, in++ ) {
		out->sides = cm.brushsides + LittleLong(in->firstSide);
		out->numsides = LittleLong(in->numSides);

		out->shaderNum = LittleLong( in->shaderNum );
		if ( out->shaderNum < 0 || out->shaderNum >= cm.numShaders ) {
			Com_Error( ERR_DROP, "CMod_LoadBrushes: bad shaderNum: %i", out->shaderNum );
		}
		out->contents = cm.shaders[out->shaderNum].contentFlags;

		CM_BoundBrush( out );
	}

}

/*
=================
CMod_LoadLeafs
=================
*/
void CMod_LoadLeafs (lump_t *l)
{
	int			i;
	cLeaf_t		*out;
	dleaf_t 	*in;
	int			count;
	
	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	count = l->filelen / sizeof(*in);

	if (count < 1)
		Com_Error (ERR_DROP, "Map with no leafs");

	cm.leafs = CM_WorldAlloc( ( BOX_LEAFS + count ) * sizeof( *cm.leafs ) );
	cm.numLeafs = count;

	out = cm.leafs;	
	for ( i=0 ; i<count ; i++, in++, out++)
	{
		out->cluster = LittleLong (in->cluster);
		out->area = LittleLong (in->area);
		out->firstLeafBrush = LittleLong (in->firstLeafBrush);
		out->numLeafBrushes = LittleLong (in->numLeafBrushes);
		out->firstLeafSurface = LittleLong (in->firstLeafSurface);
		out->numLeafSurfaces = LittleLong (in->numLeafSurfaces);

		if (out->cluster >= cm.numClusters)
			cm.numClusters = out->cluster + 1;
		if (out->area >= cm.numAreas)
			cm.numAreas = out->area + 1;
	}

	cm.areas = CM_WorldAlloc( cm.numAreas * sizeof( *cm.areas ) );
	cm.areaPortals = CM_WorldAlloc( cm.numAreas * cm.numAreas * sizeof( *cm.areaPortals ) );
}

/*
=================
CMod_LoadPlanes
=================
*/
void CMod_LoadPlanes (lump_t *l)
{
	int			i, j;
	cplane_t	*out;
	dplane_t 	*in;
	int			count;
	int			bits;
	
	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	count = l->filelen / sizeof(*in);

	if (count < 1)
		Com_Error (ERR_DROP, "Map with no planes");
	cm.planes = CM_WorldAlloc( ( BOX_PLANES + count ) * sizeof( *cm.planes ) );
	cm.numPlanes = count;

	out = cm.planes;	

	for ( i=0 ; i<count ; i++, in++, out++)
	{
		bits = 0;
		for (j=0 ; j<3 ; j++)
		{
			out->normal[j] = LittleFloat (in->normal[j]);
			if (out->normal[j] < 0)
				bits |= 1<<j;
		}

		out->dist = LittleFloat (in->dist);
		out->type = PlaneTypeForNormal( out->normal );
		out->signbits = bits;
	}
}

/*
=================
CMod_LoadLeafBrushes
=================
*/
void CMod_LoadLeafBrushes (lump_t *l)
{
	int			i;
	int			*out;
	int		 	*in;
	int			count;
	
	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	count = l->filelen / sizeof(*in);

	cm.leafbrushes = CM_WorldAlloc( (count + BOX_BRUSHES) * sizeof( *cm.leafbrushes ) );
	cm.numLeafBrushes = count;

	out = cm.leafbrushes;

	for ( i=0 ; i<count ; i++, in++, out++) {
		*out = LittleLong (*in);
	}
}

/*
=================
CMod_LoadLeafSurfaces
=================
*/
void CMod_LoadLeafSurfaces( lump_t *l )
{
	int			i;
	int			*out;
	int		 	*in;
	int			count;
	
	in = (void *)(cmod_base + l->fileofs);
	if (l->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	count = l->filelen / sizeof(*in);

	cm.leafsurfaces = CM_WorldAlloc( count * sizeof( *cm.leafsurfaces ) );
	cm.numLeafSurfaces = count;

	out = cm.leafsurfaces;

	for ( i=0 ; i<count ; i++, in++, out++) {
		*out = LittleLong (*in);
	}
}

/*
=================
CMod_LoadBrushSides
=================
*/
void CMod_LoadBrushSides (lump_t *l)
{
	int				i;
	cbrushside_t	*out;
	dbrushside_t 	*in;
	int				count;
	int				num;

	in = (void *)(cmod_base + l->fileofs);
	if ( l->filelen % sizeof(*in) ) {
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	}
	count = l->filelen / sizeof(*in);

	cm.brushsides = CM_WorldAlloc( ( BOX_SIDES + count ) * sizeof( *cm.brushsides ) );
	cm.numBrushSides = count;

	out = cm.brushsides;	

	for ( i=0 ; i<count ; i++, in++, out++) {
		num = LittleLong( in->planeNum );
		out->plane = &cm.planes[num];
		out->shaderNum = LittleLong( in->shaderNum );
		if ( out->shaderNum < 0 || out->shaderNum >= cm.numShaders ) {
			Com_Error( ERR_DROP, "CMod_LoadBrushSides: bad shaderNum: %i", out->shaderNum );
		}
		out->surfaceFlags = cm.shaders[out->shaderNum].surfaceFlags;
	}
}


/*
=================
CMod_LoadEntityString
=================
*/
void CMod_LoadEntityString( lump_t *l ) {
	cm.entityString = CM_WorldAlloc( l->filelen );
	cm.numEntityChars = l->filelen;
	Com_Memcpy (cm.entityString, cmod_base + l->fileofs, l->filelen);
}

/*
=================
CMod_LoadVisibility
=================
*/
#define	VIS_HEADER	8
void CMod_LoadVisibility( lump_t *l ) {
	int		len;
	byte	*buf;

    len = l->filelen;
	if ( !len ) {
		cm.clusterBytes = ( cm.numClusters + 31 ) & ~31;
		cm.visibility = CM_WorldAlloc( cm.clusterBytes );
		Com_Memset( cm.visibility, 255, cm.clusterBytes );
		return;
	}
	buf = cmod_base + l->fileofs;

	cm.vised = qtrue;
	cm.visibility = CM_WorldAlloc( len );
	cm.numClusters = LittleLong( ((int *)buf)[0] );
	cm.clusterBytes = LittleLong( ((int *)buf)[1] );
	Com_Memcpy (cm.visibility, buf + VIS_HEADER, len - VIS_HEADER );
}

/* dk3's bounded hearing payload precedes the existing lightstyle trailer. */
static unsigned int CMod_DK3_U32(const byte *p) {
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8) |
           ((unsigned int)p[2] << 16) | ((unsigned int)p[3] << 24);
}
static void CMod_LoadHearing(const byte *bytes, int length) {
    unsigned int end, size, clusters, rowBytes;
    const byte *payload;
    if (length < 8) return;
    end = (unsigned int)length;
    if (!memcmp(bytes + end - 8, "DKLT", 4)) {
        size = CMod_DK3_U32(bytes + end - 4);
        if (size > end - 8) Com_Error(ERR_DROP, "dk3: invalid lightstyle trailer length");
        end -= size + 8;
    }
    if (end < 8 || memcmp(bytes + end - 8, "DKPT", 4)) return;
    size = CMod_DK3_U32(bytes + end - 4);
    if (size < 12 || size > end - 8) Com_Error(ERR_DROP, "dk3: invalid PHS trailer length");
    payload = bytes + end - 8 - size;
    if (memcmp(payload, "DKPH", 4)) Com_Error(ERR_DROP, "dk3: invalid PHS trailer signature");
    clusters = CMod_DK3_U32(payload + 4);
    rowBytes = CMod_DK3_U32(payload + 8);
    if (!clusters && !cm.vised && !rowBytes && size == 12) return;
    if (clusters != (unsigned int)cm.numClusters || rowBytes != (unsigned int)cm.clusterBytes ||
        !rowBytes || clusters > (size - 12) / rowBytes || clusters * rowBytes != size - 12)
        Com_Error(ERR_DROP, "dk3: invalid PHS dimensions");
    cm.hearing = CM_WorldAlloc(size - 12);
    Com_Memcpy(cm.hearing, payload + 12, size - 12);
}

//==================================================================


/*
=================
CMod_LoadPatches
=================
*/
#define	MAX_PATCH_VERTS		1024
void CMod_LoadPatches( lump_t *surfs, lump_t *verts ) {
	drawVert_t	*dv, *dv_p;
	dsurface_t	*in;
	int			count;
	int			i, j;
	int			c;
	cPatch_t	*patch;
	vec3_t		points[MAX_PATCH_VERTS];
	int			width, height;
	int			shaderNum;

	in = (void *)(cmod_base + surfs->fileofs);
	if (surfs->filelen % sizeof(*in))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");
	cm.numSurfaces = count = surfs->filelen / sizeof(*in);
	cm.surfaces = CM_WorldAlloc( cm.numSurfaces * sizeof( cm.surfaces[0] ) );

	dv = (void *)(cmod_base + verts->fileofs);
	if (verts->filelen % sizeof(*dv))
		Com_Error (ERR_DROP, "MOD_LoadBmodel: funny lump size");

	// scan through all the surfaces, but only load patches,
	// not planar faces
	for ( i = 0 ; i < count ; i++, in++ ) {
		if ( LittleLong( in->surfaceType ) != MST_PATCH ) {
			continue;		// ignore other surfaces
		}
		// FIXME: check for non-colliding patches

		cm.surfaces[ i ] = patch = CM_WorldAlloc( sizeof( *patch ) );

		// load the full drawverts onto the stack
		width = LittleLong( in->patchWidth );
		height = LittleLong( in->patchHeight );
		c = width * height;
		if ( c > MAX_PATCH_VERTS ) {
			Com_Error( ERR_DROP, "ParseMesh: MAX_PATCH_VERTS" );
		}

		dv_p = dv + LittleLong( in->firstVert );
		for ( j = 0 ; j < c ; j++, dv_p++ ) {
			points[j][0] = LittleFloat( dv_p->xyz[0] );
			points[j][1] = LittleFloat( dv_p->xyz[1] );
			points[j][2] = LittleFloat( dv_p->xyz[2] );
		}

		shaderNum = LittleLong( in->shaderNum );
		patch->contents = cm.shaders[shaderNum].contentFlags;
		patch->surfaceFlags = cm.shaders[shaderNum].surfaceFlags;

		// create the internal facet structure
		patch->pc = CM_GeneratePatchCollide( width, height, points );
	}
}

//==================================================================

unsigned CM_LumpChecksum(lump_t *lump) {
	return LittleLong (Com_BlockChecksum (cmod_base + lump->fileofs, lump->filelen));
}

unsigned CM_Checksum(dheader_t *header) {
	unsigned checksums[16];
	checksums[0] = CM_LumpChecksum(&header->lumps[LUMP_SHADERS]);
	checksums[1] = CM_LumpChecksum(&header->lumps[LUMP_LEAFS]);
	checksums[2] = CM_LumpChecksum(&header->lumps[LUMP_LEAFBRUSHES]);
	checksums[3] = CM_LumpChecksum(&header->lumps[LUMP_LEAFSURFACES]);
	checksums[4] = CM_LumpChecksum(&header->lumps[LUMP_PLANES]);
	checksums[5] = CM_LumpChecksum(&header->lumps[LUMP_BRUSHSIDES]);
	checksums[6] = CM_LumpChecksum(&header->lumps[LUMP_BRUSHES]);
	checksums[7] = CM_LumpChecksum(&header->lumps[LUMP_MODELS]);
	checksums[8] = CM_LumpChecksum(&header->lumps[LUMP_NODES]);
	checksums[9] = CM_LumpChecksum(&header->lumps[LUMP_SURFACES]);
	checksums[10] = CM_LumpChecksum(&header->lumps[LUMP_DRAWVERTS]);

	return LittleLong(Com_BlockChecksum(checksums, 11 * 4));
}

/*
==================
CM_LoadMap

Loads in the map and all submodels
==================
*/
static qboolean CM_ValidateHeader(const void *bytes, int length, dheader_t *header) {
    int i;
    if (!bytes || length < sizeof(*header)) return qfalse;
    Com_Memcpy(header, bytes, sizeof(*header));
    for (i = 0; i < sizeof(*header) / 4; ++i) ((int *)header)[i] = LittleLong(((int *)header)[i]);
    if (header->ident != BSP_IDENT || header->version != BSP_VERSION) return qfalse;
    for (i = 0; i < HEADER_LUMPS; ++i) {
        const lump_t *lump = &header->lumps[i];
        if (lump->fileofs < 0 || lump->filelen < 0 || lump->fileofs > length || lump->filelen > length - lump->fileofs) return qfalse;
    }
    return qtrue;
}

static void CM_DecodeWorld(const char *name, const void *bytes, int length, dheader_t header) {
#ifndef BSPC
    cm_noAreas = Cvar_Get("cm_noAreas", "0", CVAR_CHEAT);
    cm_noCurves = Cvar_Get("cm_noCurves", "0", CVAR_CHEAT);
    cm_playerCurveClip = Cvar_Get("cm_playerCurveClip", "1", CVAR_ARCHIVE | CVAR_CHEAT);
#endif
	cmod_base = (byte *)bytes;

	// load into heap
	CMod_LoadShaders( &header.lumps[LUMP_SHADERS] );
	CMod_LoadLeafs (&header.lumps[LUMP_LEAFS]);
	CMod_LoadLeafBrushes (&header.lumps[LUMP_LEAFBRUSHES]);
	CMod_LoadLeafSurfaces (&header.lumps[LUMP_LEAFSURFACES]);
	CMod_LoadPlanes (&header.lumps[LUMP_PLANES]);
	CMod_LoadBrushSides (&header.lumps[LUMP_BRUSHSIDES]);
	CMod_LoadBrushes (&header.lumps[LUMP_BRUSHES]);
	CMod_LoadSubmodels (&header.lumps[LUMP_MODELS]);
	CMod_LoadNodes (&header.lumps[LUMP_NODES]);
	CMod_LoadEntityString (&header.lumps[LUMP_ENTITIES]);
	CMod_LoadVisibility( &header.lumps[LUMP_VISIBILITY] );
	CMod_LoadHearing(cmod_base, length);
	CMod_LoadPatches( &header.lumps[LUMP_SURFACES], &header.lumps[LUMP_DRAWVERTS] );

    cmod_base = NULL;
    CM_InitBoxHull();
    CM_FloodAreaConnections();
    Q_strncpyz(cm.name, name, sizeof(cm.name));
    cm_worlds[cm_selected].checksum = LittleLong(Com_BlockChecksum(bytes, length));
}

unsigned int CM_LoadWorldBytes(const char *name, const void *bytes, int length) {
    unsigned int previous, handle, index;
    dheader_t header;
    if (!name || !name[0] || strlen(name) >= MAX_QPATH || !CM_ValidateHeader(bytes, length, &header)) return 0;
    previous = CM_CurrentWorld();
    for (index = 0; index < CM_MAX_WORLDS; ++index) {
        cmWorld_t *world = &cm_worlds[index];
        if (world->occupied || world->generation == 0x7fffff) continue;
        if (!world->generation) world->generation = 1;
        world->occupied = qtrue;
        world->ready = 1;
        handle = (world->generation << 8) | (index + 1);
        CM_SelectWorld(handle);
        CM_DecodeWorld(name, bytes, length, header);
        CM_SelectWorld(previous);
        return handle;
    }
    return 0;
}

unsigned int CM_RequestWorld(const char *name) {
    unsigned int index;
    fsReadJob_t *read;
    if (!name || strncmp(name, "maps/", 5) || !COM_CompareExtension(name, ".bsp") || strlen(name) >= MAX_QPATH) return 0;
    CM_CurrentWorld();
    for (index = 0; index < CM_MAX_WORLDS; ++index) {
        cmWorld_t *world = &cm_worlds[index];
        if (world->occupied || world->generation == 0x7fffff) continue;
        read = FS_BeginBackgroundRead(name, 128 * 1024 * 1024);
        if (!read) return 0;
        if (!world->generation) world->generation = 1;
        world->occupied = qtrue;
        world->read = read;
        Q_strncpyz(world->name, name, sizeof(world->name));
        return (world->generation << 8) | (index + 1);
    }
    return 0;
}

int CM_PollWorld(unsigned int handle) {
    cmWorld_t *world = CM_World(handle);
    const void *bytes;
    int length, result;
    unsigned int previous;
    dheader_t header;
    if (!world) return -1;
    if (!world->read) return world->ready;
    result = FS_PollBackgroundRead(world->read, &bytes, &length);
    if (!result) return 0;
    if (result == 1 && CM_ValidateHeader(bytes, length, &header)) {
        previous = CM_CurrentWorld();
        world->ready = 1;
        CM_SelectWorld(handle);
        CM_DecodeWorld(world->name, bytes, length, header);
        CM_SelectWorld(previous);
    } else world->ready = -1;
    FS_EndBackgroundRead(world->read);
    world->read = NULL;
    return world->ready;
}

void CM_LoadMap(const char *name, qboolean clientload, int *checksum) {
    void *bytes = NULL;
    int length;
    dheader_t header;
    if (!name || !name[0]) Com_Error(ERR_DROP, "CM_LoadMap: NULL name");
    CM_CurrentWorld();
    if (clientload && !strcmp(cm.name, name)) {
        *checksum = cm_worlds[cm_selected].checksum;
        return;
    }
#ifndef BSPC
    length = FS_ReadFile(name, &bytes);
#else
    length = LoadQuakeFile((quakefile_t *)name, &bytes);
#endif
    if (!CM_ValidateHeader(bytes, length, &header)) {
        if (bytes) FS_FreeFile(bytes);
        Com_Error(ERR_DROP, "CM_LoadMap: invalid BSP %s", name);
    }
    CM_ClearMap();
    CM_CurrentWorld();
    CM_DecodeWorld(name, bytes, length, header);
    *checksum = cm_worlds[cm_selected].checksum;
    FS_FreeFile(bytes);
}

void CM_ClearMap(void) {
    unsigned int index;
    for (index = 0; index < CM_MAX_WORLDS; ++index) CM_FreeWorld(&cm_worlds[index]);
    cm_selected = 0;
    Com_Memset(&cm, 0, sizeof(cm));
    Com_Memset(&box_model, 0, sizeof(box_model));
    box_planes = NULL;
    box_brush = NULL;
    cmod_base = NULL;
    CM_ClearLevelPatches();
}

/*
==================
CM_ClipHandleToModel
==================
*/
cmodel_t	*CM_ClipHandleToModel( clipHandle_t handle ) {
	if ( handle < 0 ) {
		Com_Error( ERR_DROP, "CM_ClipHandleToModel: bad handle %i", handle );
	}
	if ( handle < cm.numSubModels ) {
		return &cm.cmodels[handle];
	}
	if ( handle == BOX_MODEL_HANDLE ) {
		return &box_model;
	}
	if ( handle < MAX_SUBMODELS ) {
		Com_Error( ERR_DROP, "CM_ClipHandleToModel: bad handle %i < %i < %i", 
			cm.numSubModels, handle, MAX_SUBMODELS );
	}
	Com_Error( ERR_DROP, "CM_ClipHandleToModel: bad handle %i", handle + MAX_SUBMODELS );

	return NULL;

}

/*
==================
CM_InlineModel
==================
*/
clipHandle_t	CM_InlineModel( int index ) {
	if ( index < 0 || index >= cm.numSubModels ) {
		Com_Error (ERR_DROP, "CM_InlineModel: bad number");
	}
	return index;
}

int		CM_NumClusters( void ) {
	return cm.numClusters;
}

int		CM_NumInlineModels( void ) {
	return cm.numSubModels;
}

char	*CM_EntityString( void ) {
	return cm.entityString;
}

int		CM_LeafCluster( int leafnum ) {
	if (leafnum < 0 || leafnum >= cm.numLeafs) {
		Com_Error (ERR_DROP, "CM_LeafCluster: bad number");
	}
	return cm.leafs[leafnum].cluster;
}

int		CM_LeafArea( int leafnum ) {
	if ( leafnum < 0 || leafnum >= cm.numLeafs ) {
		Com_Error (ERR_DROP, "CM_LeafArea: bad number");
	}
	return cm.leafs[leafnum].area;
}

//=======================================================================


/*
===================
CM_InitBoxHull

Set up the planes and nodes so that the six floats of a bounding box
can just be stored out and get a proper clipping hull structure.
===================
*/
void CM_InitBoxHull (void)
{
	int			i;
	int			side;
	cplane_t	*p;
	cbrushside_t	*s;

	box_planes = &cm.planes[cm.numPlanes];

	box_brush = &cm.brushes[cm.numBrushes];
	box_brush->numsides = 6;
	box_brush->sides = cm.brushsides + cm.numBrushSides;
	box_brush->contents = CONTENTS_BODY;

	box_model.leaf.numLeafBrushes = 1;
//	box_model.leaf.firstLeafBrush = cm.numBrushes;
	box_model.leaf.firstLeafBrush = cm.numLeafBrushes;
	cm.leafbrushes[cm.numLeafBrushes] = cm.numBrushes;

	for (i=0 ; i<6 ; i++)
	{
		side = i&1;

		// brush sides
		s = &cm.brushsides[cm.numBrushSides+i];
		s->plane = 	cm.planes + (cm.numPlanes+i*2+side);
		s->surfaceFlags = 0;

		// planes
		p = &box_planes[i*2];
		p->type = i>>1;
		p->signbits = 0;
		VectorClear (p->normal);
		p->normal[i>>1] = 1;

		p = &box_planes[i*2+1];
		p->type = 3 + (i>>1);
		p->signbits = 0;
		VectorClear (p->normal);
		p->normal[i>>1] = -1;

		SetPlaneSignbits( p );
	}	
}

/*
===================
CM_TempBoxModel

To keep everything totally uniform, bounding boxes are turned into small
BSP trees instead of being compared directly.
Capsules are handled differently though.
===================
*/
clipHandle_t CM_TempBoxModel( const vec3_t mins, const vec3_t maxs, int capsule ) {

	VectorCopy( mins, box_model.mins );
	VectorCopy( maxs, box_model.maxs );

	if ( capsule ) {
		return CAPSULE_MODEL_HANDLE;
	}

	box_planes[0].dist = maxs[0];
	box_planes[1].dist = -maxs[0];
	box_planes[2].dist = mins[0];
	box_planes[3].dist = -mins[0];
	box_planes[4].dist = maxs[1];
	box_planes[5].dist = -maxs[1];
	box_planes[6].dist = mins[1];
	box_planes[7].dist = -mins[1];
	box_planes[8].dist = maxs[2];
	box_planes[9].dist = -maxs[2];
	box_planes[10].dist = mins[2];
	box_planes[11].dist = -mins[2];

	VectorCopy( mins, box_brush->bounds[0] );
	VectorCopy( maxs, box_brush->bounds[1] );

	return BOX_MODEL_HANDLE;
}

/*
===================
CM_ModelBounds
===================
*/
void CM_ModelBounds( clipHandle_t model, vec3_t mins, vec3_t maxs ) {
	cmodel_t	*cmod;

	cmod = CM_ClipHandleToModel( model );
	VectorCopy( cmod->mins, mins );
	VectorCopy( cmod->maxs, maxs );
}
