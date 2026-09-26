// SPDX-License-Identifier: GPL-2.0-or-later
const s = @import("combat.zig");
const c = s.c;
const v = s.v;
pub fn stick(comptime W: type, hit: s.Contact) void {
    hit.effect(W);
    s.stop(hit.ent, hit.hit.endpos);
    s.setState(hit.ent, .stuck);
    hit.ent.dk.expires = s.now() + 5000;
    hit.ent.s.dk3Alpha = 1;
    if (hit.victim().s.eType == c.ET_MOVER) hit.ent.dk.parentId = hit.victim().dk.id;
    s.link(hit.ent);
}
