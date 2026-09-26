/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_FONT_H
#define DK_FONT_H

/* Small shared renderer for glyph metrics and pixels loaded from supplied assets. */
typedef struct {
    qhandle_t shader;
    unsigned char metrics[780];
    int height, width, imageHeight;
} dkFont_t;

static unsigned int DK_ReadLE(const unsigned char *p, int size) {
    unsigned int result = 0;
    int i;
    for (i = 0; i < size; ++i) result |= (unsigned int)p[i] << (i * 8);
    return result;
}

static void DK_LoadNamedFont(dkFont_t *font, const char *name) {
    fileHandle_t file;
    unsigned char header[18];
    char path[MAX_QPATH];
    int length;
    memset(font, 0, sizeof(*font));
    Com_sprintf(path, sizeof(path), "fonts/%s.dkf", name);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < (int)sizeof(font->metrics)) {
        if (file) trap_FS_FCloseFile(file);
        trap_Error(va("dk3: missing or truncated %s; rebuild supplied assets", path));
    }
    trap_FS_Read(font->metrics, sizeof(font->metrics), file);
    trap_FS_FCloseFile(file);
    font->height = DK_ReadLE(font->metrics + 8, 4);
    if (memcmp(font->metrics, "dkf ", 4) || DK_ReadLE(font->metrics + 4, 4) ||
        font->height <= 0 || font->height > 256) trap_Error(va("dk3: invalid %s", path));
    Com_sprintf(path, sizeof(path), "fonts/%s.tga", name);
    length = trap_FS_FOpenFile(path, &file, FS_READ);
    if (length < 18) {
        if (file) trap_FS_FCloseFile(file);
        trap_Error(va("dk3: missing %s; rebuild supplied assets", path));
    }
    trap_FS_Read(header, sizeof(header), file);
    trap_FS_FCloseFile(file);
    font->width = DK_ReadLE(header + 12, 2);
    font->imageHeight = DK_ReadLE(header + 14, 2);
    if (!font->width || !font->imageHeight) trap_Error("dk3: invalid glyph image dimensions");
    font->shader = trap_R_RegisterShaderNoMip(path);
}

static void DK_LoadFont(dkFont_t *font) {
    DK_LoadNamedFont(font, "con_font");
}

static float DK_GlyphAdvance(const dkFont_t *font, unsigned char c, float scale) {
    float width = font->metrics[12 + c];
    return (c == ' ' ? font->height * 0.5f : width ? width + 1 : 0) * scale * 16.0f / font->height;
}

static float DK_TextWidth(const dkFont_t *font, const char *text, float scale) {
    float width = 0;
    while (*text && *text != '\n') width += DK_GlyphAdvance(font, (unsigned char)*text++, scale);
    return width;
}

/* Wrap at glyph boundaries without dropping the overflow character of a long
   word. Both subtitles and center messages use the same measured advances. */
static int DK_WrapText(const dkFont_t *font, const char *text, float scale, float width,
                       char *output, int capacity) {
    int used = 0, lines = 1, lineStart = 0, space = -1;
    float lineWidth = 0;
    if (capacity < 1) return 0;
    while (*text && used < capacity - 1) {
        unsigned char c = *text++;
        float advance;
        if (Q_IsColorString(text - 1)) { ++text; continue; }
        if (c == '\r') continue;
        if (c == '\t') c = ' ';
        if (c == '\n') {
            output[used++] = c; lineStart = used; space = -1; lineWidth = 0; ++lines;
            continue;
        }
        if (c == ' ' && used == lineStart) continue;
        advance = DK_GlyphAdvance(font, c, scale);
        if (lineWidth + advance > width && used > lineStart) {
            if (space >= lineStart) {
                int i;
                output[space] = '\n'; lineStart = space + 1; space = -1; lineWidth = 0; ++lines;
                for (i = lineStart; i < used; ++i) lineWidth += DK_GlyphAdvance(font, (unsigned char)output[i], scale);
            }
            if (lineWidth + advance > width && used > lineStart) {
                output[used++] = '\n'; lineStart = used; lineWidth = 0; space = -1; ++lines;
                if (used == capacity - 1) break;
            }
            if (c == ' ' && used == lineStart) continue;
        }
        if (c == ' ') space = used;
        output[used++] = c; lineWidth += advance;
    }
    output[used] = 0;
    return lines;
}

static void DK_Text(const dkFont_t *font, float x, float y, float scale, const char *text, const float *color) {
    float start = x;
    /* Layouts use a 16-unit text line, independently of the supplied font's
       bitmap height. Small source glyphs must not make widescreen UI illegible. */
    scale *= 16.0f / font->height;
    trap_R_SetColor(color);
    while (*text) {
        unsigned int c = (unsigned char)*text++;
        float width = font->metrics[12 + c];
        float sx = font->metrics[268 + c], sy = font->metrics[524 + c];
        if (c == '\n') { x = start; y += (font->height + 3) * scale; continue; }
        if (c == ' ') { x += font->height * 0.5f * scale; continue; }
        if (width) {
            trap_R_DrawStretchPic(x, y, width * scale, font->height * scale,
                sx / font->width, sy / font->imageHeight,
                (sx + width) / font->width, (sy + font->height) / font->imageHeight, font->shader);
            x += (width + 1) * scale;
        }
    }
    trap_R_SetColor(NULL);
}
#endif
