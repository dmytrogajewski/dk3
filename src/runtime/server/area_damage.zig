// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared radius geometry and visibility. Weapon controllers supply damage policy.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const Slots = @import("../engine/slots.zig").Slots;
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub const Blast = struct {
    world: u32 = 0,
    owner: u32,
    weapon: u5,
    origin: v.Vec3,
    damage: f32,
    radius: f32,
    skip_slot: u16 = c.ENTITYNUM_NONE,
    self_scale: f32 = 0.5,
    diminishing: bool = true,
    occlusion: bool = true,
    inertial: bool = false,
};
pub fn center(world: *data.World, target: ecs.Entity) !v.Vec3 {
    if ((world.get(target, data.Actor) catch null) != null or (world.get(target, data.Player) catch null) != null) return (try world.get(target, data.Transform)).position;
    const body = (try world.get(target, data.Body)).*;
    return v.add((try world.get(target, data.Transform)).position, v.scale(v.add(body.mins, body.maxs), 0.5));
}
pub fn visible(origin: v.Vec3, destination: v.Vec3, skip: u16, target_slot: u16) !bool {
    const hit = try engine.collisionService().trace(.{ .start = origin, .end = destination, .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SOLID });
    return hit.fraction == 1 or hit.entity == target_slot;
}
pub fn apply(world: *data.World, slots: *const Slots, blast: Blast, now: i64) !void {
    const skip = if (blast.skip_slot < slots.occupants.len) (if (slots.occupants[blast.skip_slot]) |entity| try world.persistentId(entity) else 0) else 0;
    var candidates = @import("region_access.zig").Damageables.init(world, slots);
    while (candidates.next()) |target| {
        if (try target.id() == skip) continue;
        const health = target.get(data.Health) catch continue;
        if (health.current <= 0) continue;
        const point = try center(target.world, target.entity);
        const distance = v.length(v.subtract(point, blast.origin));
        if (distance >= blast.radius) continue;
        const owner = try target.id() == blast.owner;
        const amount = (if (blast.diminishing) @import("../domain/combat.zig").radiusDamage(blast.damage, distance, blast.radius, false, false) else blast.damage) * (if (owner) blast.self_scale else 1);
        if (amount <= 0) continue;
        if (blast.occlusion) {
            const hit = try @import("region_collision.zig").from(blast.world, .{ .start = blast.origin, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = blast.skip_slot, .mask = c.MASK_SOLID }, skip);
            if (!@import("region_collision.zig").reaches(world, hit, target)) continue;
        }
        if (try @import("weapon_damage.zig").hurt(target.world, target.entity, blast.owner, blast.weapon, amount, now, false)) if (blast.inertial) try @import("weapon_damage.zig").shove(target.world, target.entity, blast.owner, v.subtract(point, blast.origin), amount, now);
    }
}
