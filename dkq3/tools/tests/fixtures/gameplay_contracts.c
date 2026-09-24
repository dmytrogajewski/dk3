/* SPDX-License-Identifier: GPL-2.0-or-later */
#undef NDEBUG /* Zig cc optimization must not remove the contract assertions. */
#include "g_local.h"
#include "dk_weapons.h"
#include "dk_inventory.h"
#include <assert.h>

/* The collision service rejects the synthetic contentless brush. Native
   trigger admission must still use the authored volume, not this trace. */
qboolean trap_EntityContact(const vec3_t mins, const vec3_t maxs, const gentity_t *entity) {
    (void)mins; (void)maxs; (void)entity;
    return qfalse;
}
char *QDECL va(char *format, ...) {
    static char text[1024];
    va_list args;
    va_start(args, format); vsnprintf(text, sizeof(text), format, args); va_end(args);
    return text;
}

int main(void) {
    gentity_t trigger;
    vec3_t mins = {-10, -10, -10}, maxs = {10, 10, 10};
    memset(&trigger, 0, sizeof(trigger));
    trigger.classname = "trigger_hurt";
    trigger.r.bmodel = qtrue;
    trigger.r.absmin[0] = 9; trigger.r.absmin[1] = -12; trigger.r.absmin[2] = -12;
    trigger.r.absmax[0] = 13; trigger.r.absmax[1] = 12; trigger.r.absmax[2] = 12;
    assert(DK_TriggerContact(mins, maxs, &trigger));
    trigger.r.absmin[0] = 12;
    assert(!DK_TriggerContact(mins, maxs, &trigger));
    trigger.r.absmin[0] = 9; trigger.classname = "func_event_generator";
    assert(DK_TriggerContact(mins, maxs, &trigger));
    trigger.r.bmodel = qfalse; trigger.classname = "ammo_ionpack";
    assert(!DK_TriggerContact(mins, maxs, &trigger));

    assert(DK_ExperienceThreshold(-1) == 0);
    assert(DK_ExperienceThreshold(0) == 0);
    assert(DK_ExperienceThreshold(1) == 500);
    assert(DK_ExperienceThreshold(5) == 8000);
    assert(DK_ExperienceThreshold(6) == 12000);
    assert(DK_ExperienceThreshold(8) == 20000);
    assert(DK_ExperienceThreshold(9) == 25000);
    assert(DK_ExperienceThreshold(24) == 100000);
    assert(DK_ExperienceThreshold(25) == 110000);
    assert(!strcmp(DK_WeaponWorldModel(DK_W_ION), "models/e1/a_ion.dkm"));
    assert(!strcmp(DK_ItemModelName("ammo_ionpack"), "e1/wa_ion"));
    assert(!strcmp(DK_WeaponWorldModel(DK_W_RIPGUN), "models/e4/a_ripgun.dkm"));
    assert(!strcmp(DK_ItemModelName("ammo_ripgun"), "e4/wa_slug"));
    assert(!strcmp(DK_ItemModelName("ammo_slugger"), "e4/wa_rip"));
    return 0;
}
