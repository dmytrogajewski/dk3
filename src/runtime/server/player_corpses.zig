// SPDX-License-Identifier: GPL-2.0-or-later
//! Retained multiplayer bodies remain damageable after their player respawns.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;

pub fn retain(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, state: c.entityState_t, appearance: u8, now: i64) !void {
    var oldest: ?ecs.Entity = null;
    var oldest_ms: i64 = std.math.maxInt(i64);
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.Scenery}), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.Scenery)) |other, scenery| if (scenery.corpse != null) {
            count += 1;
            if (scenery.started_ms < oldest_ms) {
                oldest = other;
                oldest_ms = scenery.started_ms;
            }
        };
    }
    if (count >= 32) try @import("weapon_entities.zig").remove(world, slots, projections, oldest.?);
    const model = @import("resources.zig").modelName((try world.get(entity, data.Binding)).model);
    inline for (.{ data.Session, data.Player, data.Weapons, data.Keys, data.Character, data.Ailments }) |T| try world.remove(entity, T);
    try world.put(entity, data.Scenery{
        .model = model,
        .movement = .toss,
        .started_ms = state.dk3AnimationStart,
        .sequence = .{ .first = @intCast(@min(state.dk3AnimationFirst, state.dk3AnimationLast)), .last = @intCast(@max(state.dk3AnimationFirst, state.dk3AnimationLast)), .fps = @intCast(@max(1, state.dk3AnimationRate)) },
        .expires_ms = now + 15000,
        .corpse = .{ .appearance = appearance },
    });
    const slot = try slots.acquire(entity, null);
    (try world.get(entity, data.Binding)).slot = slot;
    projections[slot] = std.mem.zeroes(abi.EntityProjection);
    try @import("scenery.zig").publish(world, entity, projections, now);
}

pub fn fragment(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    if (@import("../engine/server.zig").integer("gib_enable") == 0 or @import("../engine/server.zig").integer("sv_violence") != 0) return;
    const hurt = (try world.get(entity, data.Hurt)).*;
    const health = (try world.get(entity, data.Health)).*;
    const weapon = @import("weapon_catalog").find(hurt.weapon) orelse return;
    if (hurt.feedback.gibbed or !@import("../domain/gibs.zig").playerEligible(hurt.amount, health.current, weapon.spec.projectile.splash_radius > 0)) return;
    if ((world.get(entity, data.Random) catch null) == null) try world.put(entity, data.Random{ .state = (try world.persistentId(entity)) *% 1664525 +% hurt.revision });
    const body = (try world.get(entity, data.Body)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const point = (try world.get(entity, data.Transform)).position;
    const origin = if (@import("region_access.zig").find(world, hurt.source)) |source| (try source.get(data.Transform)).position else point;
    try @import("actor_gibs.zig").burst(world, slots, projections, entity, body, hurt, .{}, "", velocity, origin, now);
    (try world.get(entity, data.Hurt)).feedback.gibbed = true;
    (try world.get(entity, data.Body)).contents = 0;
}
