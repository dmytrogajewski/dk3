// SPDX-License-Identifier: GPL-2.0-or-later
//! Sound choices belong to an attack occurrence, independently of its damage cursor.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
pub fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, position: data.Vec3, definition: Definition, now: i64) !void {
    _ = position;
    try at(world, slots, projections, entity, actor, definition, actor.melee.pose, actor.melee.started_ms, now, 3);
}
pub fn at(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, definition: Definition, index: u3, started: i64, now: i64, mask: u2) !void {
    const state = &actor.audio;
    if (state.attack_started_ms != started or state.attack_index != index) {
        state.attack_started_ms = started;
        state.attack_index = index;
        state.attack_sounds = 0;
        state.attack_alternate = if (definition.attack_alternative[index]) |chance| (try world.get(entity, data.Random)).next() < chance else false;
    }
    var times = [_]?i64{ if (definition.attack_sound_enabled[index]) definition.attack_sound_ms[index] else null, definition.second_sound_ms[index] };
    if (definition.attack_alternative[index] != null) times = if (state.attack_alternate) .{ null, times[0] } else .{ times[0], null };
    const names = [_][]const u8{ definition.attack_sounds[index], definition.second_attack_sounds[index] };
    for (times, names, 0..) |time, name, i| if (time) |due| {
        const bit = @as(u2, 1) << @intCast(i);
        if (mask & bit == 0 or state.attack_sounds & bit != 0 or now < started + due) continue;
        state.attack_sounds |= bit;
        try @import("actor_audio.zig").play(world, slots, projections, entity, definition, name, now);
    };
}
