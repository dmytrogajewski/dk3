/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef DK_MULTIPLAYER_H
#define DK_MULTIPLAYER_H
int DK_AppearanceCount(void);
int DK_AppearanceFind(const char *selection);
const char *DK_AppearanceSelection(int index);
const char *DK_AppearanceModel(int index);
const char *DK_AppearanceSkin(int index);
const char *DK_AppearanceLabel(int index);
int DK_AppearanceNext(int index, int character);
int DK_AppearanceChoose(const int *counts, int count);
const char *DK_RoomConnect(int slot, int bot);
void DK_RoomDisconnect(int slot);
int DK_RoomCommand(int slot, const char *command);
void DK_RoomTick(void);
int DK_RoomWarmup(void);
#endif
