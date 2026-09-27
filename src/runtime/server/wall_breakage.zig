// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored wall sections, ordered destruction, fragments and target dispatch.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
const policy = @import("../domain/wall_breakage.zig");
pub fn initialize(world: *data.World, entity: ecs.Entity) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    var state: policy.State = .{};
    if (object.flags & 2 != 0) state.models = .{ "models/global/e_wood1.dkm", "models/global/e_wood2.dkm", "models/global/e_wood2.dkm" };
    for (&state.models, [_][]const u8{ "model_1", "model_2", "model_3" }) |*model, key| if (prop.text(object, key)) |name| {
        model.* = name;
    };
    const health: i32 = @intFromFloat(try prop.number(object, "health", 0));
    if (health < 0) return error.InvalidWallHealth;
    try world.put(entity, data.Destructible{ .wall_explode = state, .shootable = health > 0 });
    try world.put(entity, data.Health{ .current = health, .maximum = @max(1, health) });
    try world.put(entity, data.Hurt{});
    try world.put(entity, data.Random{ .state = try world.persistentId(entity) });
}
/// Redirect only lethal damage. Equal-ranked pieces can be destroyed independently.
pub fn recipient(world: *data.World, entity: ecs.Entity, amount: i32) !ecs.Entity {
    const state = world.get(entity, data.Destructible) catch return entity;
    if (state.wall_explode == null or state.broken or !state.shootable) return entity;
    const health = try world.get(entity, data.Health);
    if (health.current <= 0 or amount < health.current) return entity;
    const object = (try world.get(entity, data.MapObject)).*;
    const group = prop.text(object, "team") orelse return entity;
    if (group.len == 0) return entity;
    const rank = try prop.number(object, "indexnumber", 0);
    var lowest = rank;
    var peers: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Destructible, data.Health }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject), view.read(data.Destructible), view.read(data.Health)) |other, candidate, wall, hitpoints| {
            if (other.index == entity.index or wall.wall_explode == null or wall.broken or hitpoints.current <= 0 or !std.mem.eql(u8, prop.text(candidate, "team") orelse "", group)) continue;
            const index = try prop.number(candidate, "indexnumber", 0);
            if (index >= rank or index > lowest) continue;
            if (index < lowest) {
                lowest = index;
                count = 0;
            }
            peers[count] = other;
            count += 1;
        };
    }
    if (count == 0) return entity;
    const random = try world.get(entity, data.Random);
    return peers[@as(usize, @intFromFloat(random.next() * @as(f32, @floatFromInt(count))))];
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, name: []const u8, now: i64) !void {
    if (name.len == 0) return;
    try @import("events.zig").configuredSound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now, .{ .volume = 0.85 });
}
pub fn destroy(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, activator: u32, now: i64) !void {
    const state = try world.get(entity, data.Destructible);
    if (state.broken) return;
    state.broken = true;
    const object = (try world.get(entity, data.MapObject)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const out = &projections[binding.slot];
    const wall = &state.wall_explode.?;
    wall.bounds_min = out.shared.absmin;
    wall.bounds_max = out.shared.absmax;
    const size = v.subtract(wall.bounds_max, wall.bounds_min);
    const bursts: usize = if (object.flags & 16 != 0) 0 else 1 + @as(usize, @intFromFloat(std.math.clamp(@floor((size[0] / 60 + 1) * (size[1] / 60 + 1) * (size[2] / 60 + 1) - 2), 1, 10)));
    const random = try world.get(entity, data.Random);
    for (wall.bursts[0..bursts]) |*burst| {
        for (&burst.position, wall.bounds_min, size) |*axis, base, width| axis.* = base + random.next() * width;
        burst.due_ms = now + @as(i64, @intFromFloat(random.next() * 250));
    }
    (try world.get(entity, data.Health)).current = 0;
    (try world.get(entity, data.Body)).contents = 0;
    out.shared.contents = 0;
    out.shared.svFlags |= c.SVF_NOCLIENT;
    engine.link(out);
    if (object.flags & 32 == 0) try sound(world, slots, projections, entity, prop.text(object, "sound") orelse "", now);
    try sound(world, slots, projections, world.find(activator) orelse entity, "global/e_explodec.wav", now);
    try router.fire(world, slots, projections, entity, activator, now);
}
pub fn use(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, activator: u32, now: i64) !void {
    if ((try world.get(entity, data.Destructible)).shootable) return;
    try destroy(world, slots, projections, router, entity, activator, now);
}
fn fragment(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, wall: policy.State, flags: u32, random: *data.Random, now: i64) !void {
    var point: v.Vec3 = undefined;
    for (&point, wall.bounds_min, wall.bounds_max) |*axis, low, high| axis.* = low + random.next() * (high - low);
    const scale = 0.8 + random.next() * 1.2;
    const mins: v.Vec3 = @splat(-8 * scale);
    const maxs: v.Vec3 = @splat(8 * scale);
    const space = try engine.collisionService().trace(.{ .start = point, .end = point, .mins = mins, .maxs = maxs, .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID });
    if (space.start_solid or space.all_solid) return;
    const choice: u2 = @intFromFloat(random.next() * 4);
    const model = wall.models[@min(2, @as(usize, choice))];
    const index = try @import("resources.zig").model(model);
    const stable_name = @import("resources.zig").modelName(index);
    var velocity: v.Vec3 = .{ random.next() * 500 - 250, random.next() * 500 - 250, 270 };
    if (flags & 8 != 0) velocity = v.scale(velocity, 2);
    const spin: v.Vec3 = .{ random.next() * 1400 - 700, random.next() * 1400 - 700, random.next() * 1400 - 700 };
    const part = try world.create(null, .{ data.Transform{ .position = point }, data.Velocity{ .linear = velocity }, data.Body{ .mins = mins, .maxs = maxs, .collision_mask = c.MASK_SHOT }, data.Scenery{ .model = stable_name, .movement = .bounce, .started_ms = now, .scale = @splat(scale), .spin = spin, .fragment = true, .expires_ms = now + 10000 + @as(i64, @intFromFloat(random.next() * 10000)) } });
    try @import("weapon_entities.zig").bind(world, slots, projections, part, stable_name);
    try @import("scenery.zig").publish(world, part, projections, now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, now: i64) !void {
    var state = (try world.get(entity, data.Destructible)).*;
    if (!state.broken and state.shootable and (try world.get(entity, data.Health)).current <= 0) {
        try destroy(world, slots, projections, router, entity, (try world.get(entity, data.Hurt)).source, now);
        if (!world.alive(entity)) return;
        state = (try world.get(entity, data.Destructible)).*;
    }
    if (!state.broken) return;
    const flags = (try world.get(entity, data.MapObject)).flags;
    var random = (try world.get(entity, data.Random)).*;
    for (state.wall_explode.?.bursts, 0..) |burst, index| if (burst.due_ms) |due| {
        if (now < due) continue;
        // Consume before allocating effect entities or dispatching callbacks.
        (try world.get(entity, data.Destructible)).wall_explode.?.bursts[index].due_ms = null;
        const count: usize = if (flags & 4 != 0) 1 + @as(usize, @intFromFloat(random.next() * 4)) else 1;
        for (0..count) |_| try fragment(world, slots, projections, state.wall_explode.?, flags, &random, now);
        if (flags & 128 == 0) {
            try @import("scenery.zig").explosionVariant(world, slots, projections, burst.position, 1, random.next() >= 0.5, now);
            if (flags & 32 == 0) try @import("events.zig").configuredSound(world, slots, projections, "global/e_explode1.wav", burst.position, c.ENTITYNUM_WORLD, c.CHAN_AUTO, now, .{});
        }
    };
    (try world.get(entity, data.Random)).* = random;
}
