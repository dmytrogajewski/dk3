// SPDX-License-Identifier: GPL-2.0-or-later
//! Leading point contact and inertial damage for class-owned melee events.
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const v = @import("../domain/vector.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
pub fn punch(world: *data.World, slots: *Slots, owner: ecs.Entity, target: Ref, pose: data.Transform, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const aim = try @import("actor_aim.zig").lead(world, target, pose, definition.offset, try world.get(owner, data.Random));
    const hit = try @import("region_collision.zig").trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(owner, data.Binding)).slot, .mask = @import("../engine/abi.zig").c.MASK_SHOT });
    if (@import("region_access.zig").victim(world, slots, hit)) |victim| {
        const amount = definition.damage + (try world.get(owner, data.Random)).next() * definition.random_damage;
        const source = try world.persistentId(owner);
        if (try @import("weapon_damage.zig").hurt(victim.world, victim.entity, source, 0, amount, now, false)) try @import("weapon_damage.zig").shove(victim.world, victim.entity, source, aim.direction, amount, now);
    }
}
