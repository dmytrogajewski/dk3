// SPDX-License-Identifier: GPL-2.0-or-later
//! Reviewed monster bullet trace shared by turret and mobile gunner controllers.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").rockgat;
pub fn fire(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, enemy: Ref, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !u32 {
    const random = try world.get(entity, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, enemy, pose, tuning.offset, random);
    const slot = (try world.get(entity, data.Binding)).slot;
    const hit = try @import("region_collision.zig").trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, tuning.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
    var contact: u32 = 0;
    if (@import("region_access.zig").victim(world, slots, hit)) |victim| if ((victim.get(data.Health) catch null) != null and policy.damageAdmitted(@intCast(std.math.clamp(engine.integer("g_spSkill"), 1, 5)), random.next())) {
        const amount = tuning.damage + random.next() * tuning.random_damage;
        if (try @import("weapon_damage.zig").hurt(victim.world, victim.entity, try world.persistentId(entity), 0, amount, now, false)) {
            contact = try victim.id();
            try @import("weapon_damage.zig").shove(victim.world, victim.entity, try world.persistentId(entity), aim.direction, amount, now);
        }
    };
    const chance = random.next();
    if (hit.fraction < 1 and chance < (if (contact != 0) @as(f32, 0.85) else 0.75)) {
        var name: [64]u8 = undefined;
        const count: f32 = if (contact != 0) 4 else 8;
        const letter = @as(u8, 'a') + @as(u8, @intFromFloat(random.next() * count));
        const sound = try std.fmt.bufPrint(&name, "global/e_{s}{c}.wav", .{ if (contact != 0) @as([]const u8, "bulflesh") else "ricochet", letter });
        try @import("events.zig").soundOwned(world, slots, projections, hit.world, sound, hit.end, hit.entity, c.CHAN_AUTO, now);
    }
    return contact;
}
