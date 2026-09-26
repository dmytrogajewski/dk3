/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_INVENTORY_H
#define DK_INVENTORY_H
#define DK_KEY_COUNT 32
extern const char *dk_keyClasses[DK_KEY_COUNT];
extern const char *dk_keyLabels[DK_KEY_COUNT];
const char *DK_ItemModelName(const char *classname);
#endif
