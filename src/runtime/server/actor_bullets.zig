// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed monster bullet trace shared by turret and mobile gunner controllers.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").rockgat;
pub fn fire(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, enemy: ecs.Entity, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !u32 {
    const random = try world.get(entity, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, enemy, pose, tuning.offset, random);
    const slot = (try world.get(entity, data.Binding)).slot;
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, tuning.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    var contact: u32 = 0;
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| if ((world.get(victim, data.Health) catch null) != null and policy.damageAdmitted(@intCast(std.math.clamp(engine.integer("g_spSkill"), 1, 5)), random.next())) {
        const amount = tuning.damage + random.next() * tuning.random_damage;
        if (try @import("weapon_damage.zig").hurt(world, victim, try world.persistentId(entity), 0, amount, now, false)) {
            contact = try world.persistentId(victim);
            try @import("weapon_damage.zig").shove(world, victim, try world.persistentId(entity), aim.direction, amount, now);
        }
    };
    const chance = random.next();
    if (hit.fraction < 1 and chance < (if (contact != 0) @as(f32, 0.85) else 0.75)) {
        var name: [64]u8 = undefined;
        const count: f32 = if (contact != 0) 4 else 8;
        const letter = @as(u8, 'a') + @as(u8, @intFromFloat(random.next() * count));
        const sound = try std.fmt.bufPrint(&name, "global/e_{s}{c}.wav", .{ if (contact != 0) @as([]const u8, "bulflesh") else "ricochet", letter });
        try @import("events.zig").sound(world, slots, projections, sound, hit.end, hit.entity, c.CHAN_AUTO, now);
    }
    return contact;
}
