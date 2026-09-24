/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Optional DKLS trailer: preserves independent authored lightstyle luxel blocks.
   Values arrive in refdef; the renderer owns only composition and texture upload. */
typedef struct {
    int page, x, y, width, height, count, styles[4];
    float scale, previous[4];
    byte *samples;
} dkLightBlock_t;
static dkLightBlock_t *dkLightBlocks;
static int dkLightBlockCount;

static unsigned int DK_Read32(const byte *p) {
    return (unsigned int)p[0] | ((unsigned int)p[1] << 8) | ((unsigned int)p[2] << 16) | ((unsigned int)p[3] << 24);
}

static void R_LoadDkLightstyles(const byte *file, int length, int pages) {
    const byte *p, *end;
    unsigned int bytes, count, i;
    dkLightBlocks = NULL; dkLightBlockCount = 0;
    if (length < 16 || memcmp(file + length - 8, "DKLT", 4)) return;
    bytes = DK_Read32(file + length - 4);
    if (bytes < 8 || bytes > (unsigned int)length - 8) ri.Error(ERR_DROP, "dk3: invalid lightstyle trailer length");
    p = file + length - 8 - bytes; end = file + length - 8;
    if (memcmp(p, "DKLS", 4)) ri.Error(ERR_DROP, "dk3: invalid lightstyle trailer signature");
    count = DK_Read32(p + 4); p += 8;
    if (count > 1048576 || count > bytes / 44) ri.Error(ERR_DROP, "dk3: invalid lightstyle block count");
    dkLightBlocks = ri.Hunk_Alloc(count * sizeof(*dkLightBlocks), h_low);
    for (i = 0; i < count; ++i) {
        dkLightBlock_t *b = &dkLightBlocks[i];
        unsigned int size, word;
        int j;
        if (end - p < 44) ri.Error(ERR_DROP, "dk3: truncated lightstyle block");
        b->page = DK_Read32(p); b->x = DK_Read32(p + 4); b->y = DK_Read32(p + 8);
        b->width = DK_Read32(p + 12); b->height = DK_Read32(p + 16); b->count = DK_Read32(p + 20);
        word = DK_Read32(p + 24); memcpy(&b->scale, &word, 4);
        for (j = 0; j < 4; ++j) { b->styles[j] = DK_Read32(p + 28 + 4*j); b->previous[j] = -1; }
        p += 44;
        if (b->page < 0 || b->page >= pages || b->x < 0 || b->y < 0 || b->width < 1 || b->height < 1 ||
            b->width > 128 || b->height > 128 || b->x > 128 - b->width || b->y > 128 - b->height ||
            b->count < 1 || b->count > 4 || Q_isnan(b->scale) || b->scale < 0 || b->scale > 16)
            ri.Error(ERR_DROP, "dk3: invalid lightstyle block dimensions");
        for (j = 0; j < b->count; ++j) if (b->styles[j] < 0 || b->styles[j] >= 256)
            ri.Error(ERR_DROP, "dk3: unsupported lightstyle index");
        size = b->width * b->height * 3 * b->count;
        if (size > end - p) ri.Error(ERR_DROP, "dk3: truncated lightstyle samples");
        b->samples = ri.Hunk_Alloc(size, h_low); memcpy(b->samples, p, size); p += size;
    }
    if (p != end) ri.Error(ERR_DROP, "dk3: trailing lightstyle data");
    dkLightBlockCount = count;
}

void R_UpdateDkLightstyles(const refdef_t *view) {
    int i, j, pixel, channel;
    qboolean flushed = qfalse;
    byte rgba[128 * 128 * 4];
    if (view->rdflags & RDF_NOWORLDMODEL || !tr.world || !tr.lightmaps) return;
    for (i = 0; i < dkLightBlockCount; ++i) {
        dkLightBlock_t *b = &dkLightBlocks[i];
        qboolean changed = qfalse;
        int pixels = b->width * b->height, page = b->page, x = b->x, y = b->y;
        for (j = 0; j < b->count; ++j) if (b->previous[j] != Com_Clamp(0, 4, view->dk3Lightstyles[b->styles[j]])) changed = qtrue;
        if (!changed) continue;
        if (!flushed) { R_IssuePendingRenderCommands(); flushed = qtrue; }
        for (j = 0; j < b->count; ++j) b->previous[j] = Com_Clamp(0, 4, view->dk3Lightstyles[b->styles[j]]);
        for (pixel = 0; pixel < pixels; ++pixel) {
            float rgb[3] = {0, 0, 0}, peak = 255;
            byte input[4];
            for (j = 0; j < b->count; ++j) for (channel = 0; channel < 3; ++channel)
                rgb[channel] += b->samples[(j * pixels + pixel) * 3 + channel] * b->previous[j] * b->scale;
            for (channel = 0; channel < 3; ++channel) if (rgb[channel] > peak) peak = rgb[channel];
            for (channel = 0; channel < 3; ++channel) input[channel] = rgb[channel] * 255 / peak;
            input[3] = 255; R_ColorShiftLightingBytes(input, rgba + pixel * 4); rgba[pixel*4+3] = 255;
        }
#ifdef DK_LIGHTSTYLE_GL2
        if (tr.fatLightmapCols > 0 && tr.fatLightmapRows > 0) {
            int perPage = tr.fatLightmapCols * tr.fatLightmapRows, tile = page % perPage;
            x += (tile % tr.fatLightmapCols) * 128; y += (tile / tr.fatLightmapCols) * 128; page /= perPage;
        }
        if (page < tr.numLightmaps) R_UpdateSubImage(tr.lightmaps[page], rgba, x, y, b->width, b->height, GL_RGBA8);
#else
        if (page < tr.numLightmaps) {
            GL_Bind(tr.lightmaps[page]);
            qglTexSubImage2D(GL_TEXTURE_2D, 0, x, y, b->width, b->height, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
        }
#endif
    }
}
