// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared radius geometry and visibility. Weapon controllers supply damage policy.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const Slots = @import("../engine/slots.zig").Slots;
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub const Blast = struct {
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
    for (slots.occupants, 0..) |occupant, slot| {
        const target = occupant orelse continue;
        if (slot == blast.skip_slot) continue;
        const health = world.get(target, data.Health) catch continue;
        if (health.current <= 0) continue;
        const point = try center(world, target);
        const distance = v.length(v.subtract(point, blast.origin));
        if (distance >= blast.radius) continue;
        const owner = try world.persistentId(target) == blast.owner;
        const amount = (if (blast.diminishing) @import("../domain/combat.zig").radiusDamage(blast.damage, distance, blast.radius, false, false) else blast.damage) * (if (owner) blast.self_scale else 1);
        if (amount <= 0 or (blast.occlusion and !try visible(blast.origin, point, blast.skip_slot, @intCast(slot)))) continue;
        if (try @import("weapon_damage.zig").hurt(world, target, blast.owner, blast.weapon, amount, now, false)) if (blast.inertial) try @import("weapon_damage.zig").shove(world, target, blast.owner, v.subtract(point, blast.origin), amount, now);
    }
}
