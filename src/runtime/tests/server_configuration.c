/* SPDX-License-Identifier: GPL-2.0-or-later
 * Exercise the engine registry's actual regional and ordinary publication. */
#ifdef NDEBUG
#error Configuration contracts require assertions
#endif
#include <assert.h>
#include "../../../engine/ioquake3/code/server/sv_init.c"

server_t sv;
serverStatic_t svs;
cvar_t *sv_maxclients;
static int commands;
void QDECL Com_Error(int code, const char *format, ...) { abort(); }
void Z_Free(void *p) { free(p); }
char *CopyString(const char *text) { char *p = strdup(text); assert(p); return p; }
void QDECL SV_SendServerCommand(client_t *client, const char *format, ...) {
    assert(client == &svs.clients[0]);
    ++commands;
}

int main(void) {
    serverWorld_t first = {0}, second = {0};
    client_t client = {0};
    cvar_t count = {0};
    count.integer = 1; sv_maxclients = &count;
    svs.clients = &client; client.state = CS_ACTIVE;
    sv.world = sv.primaryWorld = &first; sv.state = SS_GAME;
    const int index = 29;
    first.configstrings[index] = CopyString("");
    second.configstrings[index] = CopyString("");
    char value[64], actual[64];
    for (int i = 0; i < 500; ++i) {
        snprintf(value, sizeof(value), "regional-%d", i);
        SV_SetWorldConfigstring(index, value);
    }
    assert(commands == 0);
    SV_GetConfigstring(index, actual, sizeof(actual));
    assert(strcmp(actual, "regional-499") == 0);
    SV_SetConfigstring(index, "arena");
    assert(commands == 1);
    SV_SetConfigstring(index, "arena");
    assert(commands == 1);
    sv.world = &second;
    SV_SetWorldConfigstring(index, "resident");
    assert(strcmp(second.configstrings[index], "resident") == 0);
    assert(strcmp(first.configstrings[index], "arena") == 0);
    assert(commands == 1);
    sv.world = &first; client.state = CS_PRIMED;
    SV_SetWorldConfigstring(index, "regional-primed");
    assert(!client.csUpdated[index]);
    SV_SetConfigstring(index, "arena-primed");
    assert(client.csUpdated[index]);
    assert(commands == 1);
    SV_UpdateConfigstrings(&client);
    assert(commands == 2 && !client.csUpdated[index]);
    SV_SetWorldConfigstring(index, NULL);
    assert(first.configstrings[index][0] == 0 && commands == 2);
    Z_Free(first.configstrings[index]); Z_Free(second.configstrings[index]);
    return 0;
}
