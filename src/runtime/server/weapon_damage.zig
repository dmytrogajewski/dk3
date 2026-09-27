// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared weapon damage and impulse application; actor death/reactions keep their owners.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const catalog = @import("weapon_catalog");
const v = @import("../domain/vector.zig");
const c = @import("../engine/abi.zig").c;
pub fn hurt(world: *data.World, target: ecs.Entity, owner_id: u32, weapon: u5, amount: f32, now: i64, bypass_armor: bool) !bool {
    const scaled = amount * try powerFactor(world, target, owner_id, now);
    if (!std.math.isFinite(scaled) or scaled <= 0) return false;
    const result = try @import("damage.zig").apply(world, target, @intFromFloat(@min(@ceil(scaled), 1000000)), now, .{ .bypass_armor = bypass_armor, .source = owner_id, .weapon = weapon });
    if (engine.integer("developer") != 0 and (result.blood > 0 or result.armor > 0)) {
        var buffer: [160]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 zig combat: target={d} blood={d} armor={d} killed={d}\n", .{ try world.persistentId(target), result.blood, result.armor, @intFromBool(result.killed) }));
    }
    return result.blood > 0 or result.armor > 0;
}
fn powerFactor(world: *data.World, target: ecs.Entity, owner_id: u32, now: i64) !f32 {
    if (world.find(owner_id)) |owner| {
        if (try world.persistentId(target) != owner_id) {
            if (world.get(owner, data.Character)) |state| return catalog.character.powerFactor(state.attribute(.power, now)) else |_| {}
        }
    }
    return 1;
}
pub fn shove(world: *data.World, target: ecs.Entity, owner: u32, direction: v.Vec3, amount: f32, now: i64) !void {
    if ((world.get(target, data.Player) catch null) == null and (world.get(target, data.Actor) catch null) == null) return;
    if (world.get(target, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .buboid and actor.buboid.invulnerable()) return;
    if ((try world.get(target, data.Health)).current <= 0) return;
    const force = amount * try powerFactor(world, target, owner, now);
    const body = try world.get(target, data.Body);
    const kick = v.scale(v.add(v.scale(v.normalize(direction), force * 1.75), .{ 0, 0, force * 2 }), 100 / @max(100, body.mass));
    const velocity = try world.get(target, data.Velocity);
    velocity.linear = v.add(velocity.linear, kick);
    body.grounded = false;
    if (world.get(target, data.Player) catch null) |player| player.ground_entity = c.ENTITYNUM_NONE;
    if (world.get(target, data.Actor) catch null) |actor| actor.ground_entity = c.ENTITYNUM_NONE;
}
