/*
Copyright (C) 1997-2001 Id Software, Inc.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/
// tr_bloom.c: 2D lighting post process effect

#include "tr_local.h"

static cvar_t *r_bloom;
static cvar_t *r_bloom_sample_size;
static cvar_t *r_bloom_alpha;
static cvar_t *r_bloom_darken;
static cvar_t *r_bloom_intensity;
static cvar_t *r_bloom_diamond_size;

static float Diamond8x[8][8] = {
	{ 0.0f, 0.0f, 0.0f, 0.1f, 0.1f, 0.0f, 0.0f, 0.0f, },
	{ 0.0f, 0.0f, 0.2f, 0.3f, 0.3f, 0.2f, 0.0f, 0.0f, },
	{ 0.0f, 0.2f, 0.4f, 0.6f, 0.6f, 0.4f, 0.2f, 0.0f, },
	{ 0.1f, 0.3f, 0.6f, 0.9f, 0.9f, 0.6f, 0.3f, 0.1f, },
	{ 0.1f, 0.3f, 0.6f, 0.9f, 0.9f, 0.6f, 0.3f, 0.1f, },
	{ 0.0f, 0.2f, 0.4f, 0.6f, 0.6f, 0.4f, 0.2f, 0.0f, },
	{ 0.0f, 0.0f, 0.2f, 0.3f, 0.3f, 0.2f, 0.0f, 0.0f, },
	{ 0.0f, 0.0f, 0.0f, 0.1f, 0.1f, 0.0f, 0.0f, 0.0f  }
};

static float Diamond6x[6][6] = {
	{ 0.0f, 0.0f, 0.1f, 0.1f, 0.0f, 0.0f, },
	{ 0.0f, 0.3f, 0.5f, 0.5f, 0.3f, 0.0f, },
	{ 0.1f, 0.5f, 0.9f, 0.9f, 0.5f, 0.1f, },
	{ 0.1f, 0.5f, 0.9f, 0.9f, 0.5f, 0.1f, },
	{ 0.0f, 0.3f, 0.5f, 0.5f, 0.3f, 0.0f, },
	{ 0.0f, 0.0f, 0.1f, 0.1f, 0.0f, 0.0f  }
};

static float Diamond4x[4][4] = {
	{ 0.3f, 0.4f, 0.4f, 0.3f, },
	{ 0.4f, 0.9f, 0.9f, 0.4f, },
	{ 0.4f, 0.9f, 0.9f, 0.4f, },
	{ 0.3f, 0.4f, 0.4f, 0.3f  }
};

static struct {
	struct {
		image_t	*texture;
		int		width, height;
		float	readW, readH;
	} effect;
	struct {
		image_t	*texture;
		int		width, height;
		float	readW, readH;
	} screen;
	struct {
		int		width, height;
	} work;
	qboolean started, failed;
} bloom;

static void R_Bloom_Quad( int width, int height, float texX, float texY, float texWidth, float texHeight ) {
	int y = glConfig.vidHeight - height;

	texWidth += texX;
	texHeight += texY;
	height += y;

	qglBegin( GL_QUADS );
	qglTexCoord2f( texX, texHeight );
	qglVertex2f( 0, y );
	qglTexCoord2f( texX, texY );
	qglVertex2f( 0, height );
	qglTexCoord2f( texWidth, texY );
	qglVertex2f( width, height );
	qglTexCoord2f( texWidth, texHeight );
	qglVertex2f( width, y );
	qglEnd();
}

static image_t *R_Bloom_Texture( const char *name, int width, int height ) {
	byte *data = ri.Hunk_AllocateTempMemory( width * height * 4 );
	image_t *image;

	Com_Memset( data, 0, width * height * 4 );
	image = R_CreateImage( name, data, width, height, IMGTYPE_COLORALPHA, IMGFLAG_NO_COMPRESSION | IMGFLAG_CLAMPTOEDGE, 0 );
	ri.Hunk_FreeTempMemory( data );
	return image;
}

static void R_Bloom_InitTextures( void ) {
	for ( bloom.screen.width = 1; bloom.screen.width < glConfig.vidWidth; bloom.screen.width *= 2 );
	for ( bloom.screen.height = 1; bloom.screen.height < glConfig.vidHeight; bloom.screen.height *= 2 );
	bloom.screen.readW = glConfig.vidWidth / (float)bloom.screen.width;
	bloom.screen.readH = glConfig.vidHeight / (float)bloom.screen.height;

	bloom.work.width = r_bloom_sample_size->integer;
	bloom.work.height = (int)( bloom.work.width * (float)glConfig.vidHeight / glConfig.vidWidth + 0.5f );
	if ( bloom.work.height < 1 )
		bloom.work.height = 1;
	for ( bloom.effect.width = 1; bloom.effect.width < bloom.work.width; bloom.effect.width *= 2 );
	for ( bloom.effect.height = 1; bloom.effect.height < bloom.work.height; bloom.effect.height *= 2 );
	bloom.effect.readW = bloom.work.width / (float)bloom.effect.width;
	bloom.effect.readH = bloom.work.height / (float)bloom.effect.height;

	if ( bloom.work.width < 32 ||
		bloom.screen.width > glConfig.maxTextureSize ||
		bloom.screen.height > glConfig.maxTextureSize ||
		bloom.effect.width > glConfig.maxTextureSize ||
		bloom.effect.height > glConfig.maxTextureSize ||
		bloom.work.width > glConfig.vidWidth ||
		bloom.work.height > glConfig.vidHeight ) {
		bloom.failed = qtrue;
		ri.Printf( PRINT_WARNING, "WARNING: r_bloom_sample_size %d does not fit this display; bloom disabled\n", r_bloom_sample_size->integer );
		return;
	}

	bloom.screen.texture = R_Bloom_Texture( "*bloomScreen", bloom.screen.width, bloom.screen.height );
	bloom.effect.texture = R_Bloom_Texture( "*bloomEffect", bloom.effect.width, bloom.effect.height );
	bloom.started = qtrue;
}

static void R_Bloom_GenerateEffect( void ) {
	int i, j, k, size;
	float intensity, scale, *diamond;

	qglColor4f( 1.0f, 1.0f, 1.0f, 1.0f );
	GL_Bind( bloom.screen.texture );
	GL_State( GLS_DEPTHTEST_DISABLE | GLS_SRCBLEND_ONE | GLS_DSTBLEND_ZERO );
	R_Bloom_Quad( bloom.work.width, bloom.work.height, 0, 0, bloom.screen.readW, bloom.screen.readH );
	GL_Bind( bloom.effect.texture );
	qglCopyTexSubImage2D( GL_TEXTURE_2D, 0, 0, 0, 0, 0, bloom.work.width, bloom.work.height );

	if ( r_bloom_darken->integer > 0 ) {
		GL_State( GLS_DEPTHTEST_DISABLE | GLS_SRCBLEND_DST_COLOR | GLS_DSTBLEND_ZERO );
		for ( i = 0; i < r_bloom_darken->integer; i++ )
			R_Bloom_Quad( bloom.work.width, bloom.work.height, 0, 0, bloom.effect.readW, bloom.effect.readH );
		qglCopyTexSubImage2D( GL_TEXTURE_2D, 0, 0, 0, 0, 0, bloom.work.width, bloom.work.height );
	}

	size = r_bloom_diamond_size->integer;
	if ( size <= 4 ) {
		size = 4; k = 2; diamond = &Diamond4x[0][0]; scale = r_bloom_intensity->value * 0.8f;
	} else if ( size <= 6 ) {
		size = 6; k = 3; diamond = &Diamond6x[0][0]; scale = r_bloom_intensity->value * 0.5f;
	} else {
		size = 8; k = 4; diamond = &Diamond8x[0][0]; scale = r_bloom_intensity->value * 0.3f;
	}

	GL_State( GLS_DEPTHTEST_DISABLE | GLS_SRCBLEND_ONE | GLS_DSTBLEND_ONE_MINUS_SRC_COLOR );
	for ( i = 0; i < size; i++ ) {
		for ( j = 0; j < size; j++, diamond++ ) {
			intensity = *diamond * scale;
			if ( intensity < 0.01f )
				continue;
			qglColor4f( intensity, intensity, intensity, 1.0f );
			R_Bloom_Quad( bloom.work.width, bloom.work.height,
				( i - k ) * ( 2 / 640.0f ) * bloom.effect.readW,
				( j - k ) * ( 2 / 480.0f ) * bloom.effect.readH,
				bloom.effect.readW, bloom.effect.readH );
		}
	}
	qglCopyTexSubImage2D( GL_TEXTURE_2D, 0, 0, 0, 0, 0, bloom.work.width, bloom.work.height );
}

/*
=================
R_BloomScreen

Runs once per frame after the first world scene, before the HUD, menus and
console draw over it.
=================
*/
void R_BloomScreen( void ) {
	if ( !r_bloom->integer || backEnd.doneBloom || !backEnd.doneSurfaces || bloom.failed )
		return;
	backEnd.doneBloom = qtrue;
	if ( !bloom.started ) {
		R_Bloom_InitTextures();
		if ( !bloom.started )
			return;
	}
	if ( tess.numIndexes )
		RB_EndSurface();
	if ( !backEnd.projection2D )
		RB_SetGL2D();

	GL_Bind( bloom.screen.texture );
	qglCopyTexSubImage2D( GL_TEXTURE_2D, 0, 0, 0, 0, 0, glConfig.vidWidth, glConfig.vidHeight );

	R_Bloom_GenerateEffect();

	GL_State( GLS_DEPTHTEST_DISABLE | GLS_SRCBLEND_ONE | GLS_DSTBLEND_ZERO );
	GL_Bind( bloom.screen.texture );
	qglColor4f( 1, 1, 1, 1 );
	R_Bloom_Quad( bloom.work.width, bloom.work.height, 0, 0,
		bloom.work.width / (float)bloom.screen.width, bloom.work.height / (float)bloom.screen.height );

	GL_Bind( bloom.effect.texture );
	GL_State( GLS_DEPTHTEST_DISABLE | GLS_SRCBLEND_ONE | GLS_DSTBLEND_ONE );
	qglColor4f( r_bloom_alpha->value, r_bloom_alpha->value, r_bloom_alpha->value, 1.0f );
	R_Bloom_Quad( glConfig.vidWidth, glConfig.vidHeight, 0, 0, bloom.effect.readW, bloom.effect.readH );
	qglColor4f( 1, 1, 1, 1 );
}

void R_BloomInit( void ) {
	memset( &bloom, 0, sizeof( bloom ) );
	r_bloom = ri.Cvar_Get( "r_bloom", "0", CVAR_ARCHIVE );
	ri.Cvar_SetDescription( r_bloom, "Screen-space light bloom after the world scene (0 keeps the original look)" );
	r_bloom_alpha = ri.Cvar_Get( "r_bloom_alpha", "0.3", CVAR_ARCHIVE );
	r_bloom_diamond_size = ri.Cvar_Get( "r_bloom_diamond_size", "8", CVAR_ARCHIVE );
	r_bloom_intensity = ri.Cvar_Get( "r_bloom_intensity", "1.3", CVAR_ARCHIVE );
	r_bloom_darken = ri.Cvar_Get( "r_bloom_darken", "4", CVAR_ARCHIVE );
	r_bloom_sample_size = ri.Cvar_Get( "r_bloom_sample_size", "128", CVAR_ARCHIVE | CVAR_LATCH );
	ri.Cvar_CheckRange( r_bloom_darken, 0, 16, qtrue );
	ri.Cvar_CheckRange( r_bloom_sample_size, 32, 1024, qtrue );
}
