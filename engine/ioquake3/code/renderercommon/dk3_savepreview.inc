/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Save previews are menu thumbnails. Full-size captures at high resolutions
   exceed the image loader's main-zone allocation when the menu shows them. */
#define DK3_PREVIEW_WIDTH 400
#define DK3_PREVIEW_HEIGHT 300

static qboolean R_SavePreviewJPEG( const byte *source, int width, int height, int padlen, const char *fileName ) {
	byte *preview, *dst;
	int px, py, sx, sy, x0, x1, y0, y1, count, sum[3], stride = width * 3 + padlen;

	if ( Q_strncmp( fileName, "screenshots/dk3-save-", 21 ) ||
		width <= DK3_PREVIEW_WIDTH || height <= DK3_PREVIEW_HEIGHT ) {
		return qfalse;
	}
	preview = ri.Hunk_AllocateTempMemory( DK3_PREVIEW_WIDTH * DK3_PREVIEW_HEIGHT * 3 );
	dst = preview;
	for ( py = 0; py < DK3_PREVIEW_HEIGHT; py++ ) {
		y0 = py * height / DK3_PREVIEW_HEIGHT;
		y1 = ( py + 1 ) * height / DK3_PREVIEW_HEIGHT;
		for ( px = 0; px < DK3_PREVIEW_WIDTH; px++ ) {
			x0 = px * width / DK3_PREVIEW_WIDTH;
			x1 = ( px + 1 ) * width / DK3_PREVIEW_WIDTH;
			sum[0] = sum[1] = sum[2] = count = 0;
			for ( sy = y0; sy < y1; sy++ ) {
				const byte *src = source + sy * stride + x0 * 3;
				for ( sx = x0; sx < x1; sx++, src += 3, count++ ) {
					sum[0] += src[0];
					sum[1] += src[1];
					sum[2] += src[2];
				}
			}
			*dst++ = sum[0] / count;
			*dst++ = sum[1] / count;
			*dst++ = sum[2] / count;
		}
	}
	if ( glConfig.deviceSupportsGamma ) {
		R_GammaCorrect( preview, DK3_PREVIEW_WIDTH * DK3_PREVIEW_HEIGHT * 3 );
	}
	RE_SaveJPG( (char *)fileName, r_screenshotJpegQuality->integer, DK3_PREVIEW_WIDTH, DK3_PREVIEW_HEIGHT, preview, 0 );
	ri.Hunk_FreeTempMemory( preview );
	return qtrue;
}
