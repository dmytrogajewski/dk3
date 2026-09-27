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

/*****************************************************************************
 * name:		be_aas_main.c
 *
 * desc:		AAS
 *
 * $Archive: /MissionPack/code/botlib/be_aas_main.c $
 *
 *****************************************************************************/

#include "../qcommon/q_shared.h"
#include "l_memory.h"
#include "l_libvar.h"
#include "l_utils.h"
#include "l_script.h"
#include "l_precomp.h"
#include "l_struct.h"
#include "l_log.h"
#include "aasfile.h"
#include "botlib.h"
#include "be_aas.h"
#include "be_aas_funcs.h"
#include "be_interface.h"
#include "be_aas_def.h"

static aas_t aasDefaultWorld;
aas_t *aasCurrentWorld = &aasDefaultWorld;
static aas_t *aasResidents[128];

libvar_t *saveroutingcache;

//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
void QDECL AAS_Error(char *fmt, ...)
{
	char str[1024];
	va_list arglist;

	va_start(arglist, fmt);
	Q_vsnprintf(str, sizeof(str), fmt, arglist);
	va_end(arglist);
	botimport.Print(PRT_FATAL, "%s", str);
} //end of the function AAS_Error
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
int AAS_Loaded(void)
{
	return aasworld.loaded;
} //end of the function AAS_Loaded
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
int AAS_Initialized(void)
{
	return aasworld.initialized;
} //end of the function AAS_Initialized
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
void AAS_SetInitialized(void)
{
	aasworld.initialized = qtrue;
	botimport.Print(PRT_MESSAGE, "AAS initialized.\n");
#ifdef DEBUG
	//create all the routing cache
	//AAS_CreateAllRoutingCache();
	//
	//AAS_RoutingInfo();
#endif
} //end of the function AAS_SetInitialized
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
void AAS_ContinueInit(float time)
{
	//if no AAS file loaded
	if (!aasworld.loaded) return;
	//if AAS is already initialized
	if (aasworld.initialized) return;
	//calculate reachability, if not finished return
	if (AAS_ContinueInitReachability(time)) return;
	//initialize clustering for the new map
	AAS_InitClustering();
	//if reachability has been calculated and an AAS file should be written
	//or there is a forced data optimization
	if (aasworld.savefile || ((int)LibVarGetValue("forcewrite")))
	{
		//optimize the AAS data
		if ((int)LibVarValue("aasoptimize", "0")) AAS_Optimize();
		//save the AAS file
		if (AAS_WriteAASFile(aasworld.filename))
		{
			botimport.Print(PRT_MESSAGE, "%s written successfully\n", aasworld.filename);
		} //end if
		else
		{
			botimport.Print(PRT_ERROR, "couldn't write %s\n", aasworld.filename);
		} //end else
	} //end if
	//initialize the routing
	AAS_InitRouting();
	//at this point AAS is initialized
	AAS_SetInitialized();
} //end of the function AAS_ContinueInit
//===========================================================================
// called at the start of every frame
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
int AAS_StartFrame(float time)
{
	aasworld.time = time;
	//unlink all entities that were not updated last frame
	AAS_UnlinkInvalidEntities();
	//invalidate the entities
	AAS_InvalidateEntities();
	//initialize AAS
	AAS_ContinueInit(time);
	//
	aasworld.frameroutingupdates = 0;
	//
	if (botDeveloper)
	{
		if (LibVarGetValue("showcacheupdates"))
		{
			AAS_RoutingInfo();
			LibVarSet("showcacheupdates", "0");
		} //end if
		if (LibVarGetValue("showmemoryusage"))
		{
			PrintUsedMemorySize();
			LibVarSet("showmemoryusage", "0");
		} //end if
		if (LibVarGetValue("memorydump"))
		{
			PrintMemoryLabels();
			LibVarSet("memorydump", "0");
		} //end if
	} //end if
	//
	if (saveroutingcache->value)
	{
		AAS_WriteRouteCache();
		LibVarSet("saveroutingcache", "0");
	} //end if
	//
	aasworld.numframes++;
	return BLERR_NOERROR;
} //end of the function AAS_StartFrame
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
float AAS_Time(void)
{
	return aasworld.time;
} //end of the function AAS_Time
//===========================================================================
//
// Parameter:			-
// Returns:				-
// Changes Globals:		-
//===========================================================================
void AAS_ProjectPointOntoVector( vec3_t point, vec3_t vStart, vec3_t vEnd, vec3_t vProj )
{
	vec3_t pVec, vec;

	VectorSubtract( point, vStart, pVec );
	VectorSubtract( vEnd, vStart, vec );
	VectorNormalize( vec );
	// project onto the directional vector for this segment
	VectorMA( vStart, DotProduct( pVec, vec ), vec, vProj );
} //end of the function AAS_ProjectPointOntoVector
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
int AAS_LoadFiles(const char *mapname)
{
	int errnum;
	char aasfile[MAX_QPATH];

	Q_strncpyz(aasworld.mapname, mapname, sizeof(aasworld.mapname));
	//NOTE: first reset the entity links into the AAS areas and BSP leaves
	// the AAS link heap and BSP link heap are reset after respectively the
	// AAS file and BSP file are loaded
	AAS_ResetEntityLinks();
	// load bsp info
	AAS_LoadBSPFile();

	//load the aas file
	Com_sprintf(aasfile, sizeof(aasfile), "maps/%s.aas", mapname);
	errnum = AAS_LoadAASFile(aasfile);
	if (errnum != BLERR_NOERROR)
		return errnum;

	botimport.Print(PRT_MESSAGE, "loaded %s\n", aasfile);
	Q_strncpyz(aasworld.filename, aasfile, sizeof(aasworld.filename));
	return BLERR_NOERROR;
} //end of the function AAS_LoadFiles
//===========================================================================
// called every time a map changes
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
int AAS_LoadMap(const char *mapname)
{
	int	errnum;

	//if no mapname is provided then the string indexes are updated
	if (!mapname)
	{
		return 0;
	} //end if
	//
	aasworld.initialized = qfalse;
	//NOTE: free the routing caches before loading a new map because
	// to free the caches the old number of areas, number of clusters
	// and number of areas in a clusters must be available
	AAS_FreeRoutingCaches();
	//load the map
	errnum = AAS_LoadFiles(mapname);
	if (errnum != BLERR_NOERROR)
	{
		aasworld.loaded = qfalse;
		return errnum;
	} //end if
	//
	AAS_InitSettings();
	//initialize the AAS link heap for the new map
	AAS_InitAASLinkHeap();
	//initialize the AAS linked entities for the new map
	AAS_InitAASLinkedEntities();
	//initialize reachability for the new map
	AAS_InitReachability();
	//initialize the alternative routing
	AAS_InitAlternativeRouting();
	//everything went ok
	return 0;
} //end of the function AAS_LoadMap
//===========================================================================
// called when the library is first loaded
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
int AAS_Setup(void)
{
	aasworld.maxclients = (int) LibVarValue("maxclients", "128");
	aasworld.maxentities = (int) LibVarValue("maxentities", "1024");
	// as soon as it's set to 1 the routing cache will be saved
	saveroutingcache = LibVar("saveroutingcache", "0");
	//allocate memory for the entities
	if (aasworld.entities) FreeMemory(aasworld.entities);
	aasworld.entities = (aas_entity_t *) GetClearedMemory(aasworld.maxentities * sizeof(aas_entity_t));
	//invalidate all the entities
	AAS_InvalidateEntities();
	//force some recalculations
	//LibVarSet("forceclustering", "1");			//force clustering calculation
	//LibVarSet("forcereachability", "1");		//force reachability calculation
	aasworld.numframes = 0;
	return BLERR_NOERROR;
} //end of the function AAS_Setup
//===========================================================================
//
// Parameter:				-
// Returns:					-
// Changes Globals:		-
//===========================================================================
static void AAS_ShutdownCurrent(void)
{
    if (aasworld.reachabilityheap) FreeMemory(aasworld.reachabilityheap);
    if (aasworld.areareachability) FreeMemory(aasworld.areareachability);
	AAS_ShutdownAlternativeRouting();
	//
	AAS_DumpBSPData();
	//free routing caches
	AAS_FreeRoutingCaches();
	//free aas link heap
	AAS_FreeAASLinkHeap();
	//free aas linked entities
	AAS_FreeAASLinkedEntities();
	//free the aas data
	AAS_DumpAASData();
	//free the entities
	if (aasworld.entities) FreeMemory(aasworld.entities);
	//clear the aasworld structure
	Com_Memset(&aasworld, 0, sizeof(aas_t));
	//aas has not been initialized
	aasworld.initialized = qfalse;
	//NOTE: as soon as a new .bsp file is loaded the .bsp file memory is
	// freed and reallocated, so there's no need to free that memory here
	//print shutdown
	botimport.Print(PRT_MESSAGE, "AAS shutdown.\n");
} //end of the function AAS_Shutdown

/* Native resident navigation uses the existing AAS algorithms with explicit
 * map ownership. Calls are owner-thread only, with matching server collision
 * selected by the caller for BSP/trace imports. */
int AAS_BindWorld(unsigned int handle) {
    unsigned int i;
    if (!handle || !aasworld.loaded) return 0;
    if (aasworld.worldHandle) return aasworld.worldHandle == handle;
    for (i = 0; i < ARRAY_LEN(aasResidents); ++i) {
        if (aasResidents[i]) continue;
        aasworld.worldHandle = handle;
        aasResidents[i] = aasCurrentWorld;
        return 1;
    }
    return 0;
}
int AAS_SelectWorld(unsigned int handle) {
    unsigned int i;
    for (i = 0; i < ARRAY_LEN(aasResidents); ++i) {
        if (aasResidents[i] && aasResidents[i]->worldHandle == handle) {
            aasCurrentWorld = aasResidents[i];
            return 1;
        }
    }
    return 0;
}
int AAS_LoadWorld(unsigned int handle, const char *asset, int checksum) {
    aas_t *previous = aasCurrentWorld, *world;
    char savedChecksum[64], nextChecksum[64];
    int error;
    unsigned int i;
    if (!handle || !LibVarGetValue("dk3_navigation")) return 0;
    if (AAS_SelectWorld(handle)) return 1;
    for (i = 0; i < ARRAY_LEN(aasResidents) && aasResidents[i]; ++i) {}
    if (i == ARRAY_LEN(aasResidents)) return 0;
    world = GetClearedMemory(sizeof(*world));
    aasCurrentWorld = world;
    Q_strncpyz(savedChecksum, LibVarGetString("sv_mapChecksum"), sizeof(savedChecksum));
    Com_sprintf(nextChecksum, sizeof(nextChecksum), "%i", checksum);
    LibVarSet("sv_mapChecksum", nextChecksum);
    error = AAS_Setup();
    if (!error) error = AAS_LoadMap(asset);
    LibVarSet("sv_mapChecksum", savedChecksum);
    if (error) {
        AAS_ShutdownCurrent();
        FreeMemory(world);
        aasCurrentWorld = previous;
        return 0;
    }
    world->worldHandle = handle;
    aasResidents[i] = world;
    return 1;
}
int AAS_ReleaseWorld(unsigned int handle) {
    unsigned int i;
    aas_t *previous = aasCurrentWorld;
    for (i = 0; i < ARRAY_LEN(aasResidents); ++i) {
        aas_t *world = aasResidents[i];
        if (!world || world->worldHandle != handle) continue;
        if (world == previous || world == &aasDefaultWorld) return 0;
        aasCurrentWorld = world;
        AAS_ShutdownCurrent();
        FreeMemory(world);
        aasResidents[i] = NULL;
        aasCurrentWorld = previous;
        return 1;
    }
    return 1;
}
void AAS_Shutdown(void) {
    unsigned int i;
    for (i = 0; i < ARRAY_LEN(aasResidents); ++i) {
        aas_t *world = aasResidents[i];
        if (!world || world == &aasDefaultWorld) continue;
        aasCurrentWorld = world;
        AAS_ShutdownCurrent();
        FreeMemory(world);
    }
    memset(aasResidents, 0, sizeof(aasResidents));
    aasCurrentWorld = &aasDefaultWorld;
    AAS_ShutdownCurrent();
}
