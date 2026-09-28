/* SPDX-License-Identifier: GPL-2.0-or-later
 * Brush models belong to a renderer world, not the shared model cache.
 * Positive handles reserve bit 30; 14 generation, 7 owner and 9 model bits
 * make old handles invalid when a world slot is recycled. */
#ifndef DK3_INLINE_HANDLES_H
#define DK3_INLINE_HANDLES_H
#define DK3_INLINE_TAG (1u << 30)
#define DK3_RENDER_GENERATION_MAX 0x3fffu
static unsigned int DK3_InlineHandle(unsigned int generation, unsigned int owner, unsigned int model) {
    if (!generation || generation > DK3_RENDER_GENERATION_MAX || owner >= 128 || model >= 512) return 0;
    return DK3_INLINE_TAG | (generation << 16) | (owner << 9) | model;
}
static int DK3_InlineParts(unsigned int handle, unsigned int *generation, unsigned int *owner, unsigned int *model) {
    if ((handle & 0xc0000000u) != DK3_INLINE_TAG) return 0;
    *generation = (handle >> 16) & DK3_RENDER_GENERATION_MAX;
    *owner = (handle >> 9) & 127;
    *model = handle & 511;
    return *generation != 0;
}
#endif
