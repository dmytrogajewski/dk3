// SPDX-License-Identifier: GPL-2.0-or-later
//! Delivery of the two supplied attack sound events, through the existing cursor.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, position: data.Vec3, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const index = actor.melee.pose;
    const times = [_]?i64{ definition.attack_sound_ms[index], definition.second_sound_ms[index] };
    const names = [_][]const u8{ definition.attack_sounds[index], definition.second_attack_sounds[index] };
    for (times, names, 0..) |time, name, i| if (time) |at| {
        if (name.len > 0 and actor.melee.event(@as(u2, 1) << @intCast(i), at, now, true)) try @import("events.zig").sound(world, slots, projections, name, position, (try world.get(entity, data.Binding)).slot, abi.c.CHAN_WEAPON, now);
    };
}
