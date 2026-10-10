/* SPDX-License-Identifier: GPL-2.0-or-later */
/* The SDL window icon for the Vulkan renderer, as sdl_glimp.c uses it. */
#include "sdl_icon.h"

const unsigned char *dk3_vk_icon(int *width, int *height, int *bytesPerPixel) {
    *width = CLIENT_WINDOW_ICON.width;
    *height = CLIENT_WINDOW_ICON.height;
    *bytesPerPixel = CLIENT_WINDOW_ICON.bytes_per_pixel;
    return CLIENT_WINDOW_ICON.pixel_data;
}
