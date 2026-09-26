// SPDX-License-Identifier: GPL-2.0-or-later
//! Linked Trident tips. Persistent IDs keep the group valid across ECS relocation/save.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const weapons = @import("../domain/weapons.zig");
const W = @import("weapon_catalog").trident;
const v = @import("../domain/vector.zig");
const projectiles = @import("projectiles.zig");
const entities = @import("weapon_entities.zig");
const c = abi.c;
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    if (shot.sequence < 1 or shot.sequence > 3) return error.InvalidTridentCount;
    var tips: [3]?ecs.Entity = @splat(null);
    errdefer for (tips) |tip| if (tip) |entity| {
        entities.remove(world, slots, projections, entity) catch {};
    };
    for (0..@intCast(shot.sequence)) |index| {
        var intent = shot;
        const kind: W.Tip = ([_]W.Tip{ .middle, .left, .right })[index];
        intent.sequence = @intCast(@intFromEnum(kind));
        const entity = try projectiles.spawn(world, slots, projections, owner, intent, table, now);
        tips[index] = entity;
        const direction = v.normalize((try world.get(entity, data.Velocity)).linear);
        (try world.get(entity, data.Projectile)).flight.trident = .{ .kind = kind, .forward = direction, .right_axis = v.normalize(.{ direction[1], -direction[0], 0 }), .steering_speed = table.entries[W.id].speed };
    }
    const middle = tips[0].?;
    const middle_id = try world.persistentId(middle);
    for (tips[1..], 0..) |tip, index| if (tip) |entity| {
        (try world.get(entity, data.Projectile)).flight.trident.leader = middle_id;
        const id = try world.persistentId(entity);
        const state = &(try world.get(middle, data.Projectile)).flight.trident;
        if (index == 0) state.left = id else state.right = id;
    };
    if (engine.integer("developer") > 0) {
        var text: [120]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig trident: leader={d} tips={d}\n", .{ middle_id, shot.sequence }));
    }
}
fn findTip(world: *data.World, id: u32) ?ecs.Entity {
    const entity = world.find(id) orelse return null;
    const projectile = world.get(entity, data.Projectile) catch return null;
    return if (projectile.flight == .trident) entity else null;
}
fn groups(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .trident or projectile.flight.trident.kind != .middle) continue;
        var state = projectile.flight.trident;
        const age = now - projectile.born_ms;
        if (age < state.next_ms) continue;
        state.next_ms = age + 100;
        const left = findTip(world, state.left);
        const right = findTip(world, state.right);
        if (left != null and right != null) {
            for ([_]ecs.Entity{ left.?, right.? }) |outer| {
                const part = try world.get(outer, data.Projectile);
                // Gold's post-launch steering uses the supplied base speed.
                (try world.get(outer, data.Velocity)).linear = W.outerVelocity(&part.flight.trident, age, part.flight.trident.steering_speed);
            }
            if (age >= 360) {
                const position = (try world.get(entity, data.Transform)).position;
                try @import("area_damage.zig").apply(world, slots, .{ .owner = projectile.owner, .weapon = W.id, .origin = position, .damage = projectile.damage, .radius = 128, .skip_slot = (try world.get(entity, data.Binding)).slot, .occlusion = false }, now);
                try entities.remove(world, slots, projections, left.?);
                try entities.remove(world, slots, projections, right.?);
                state.left = 0;
                state.right = 0;
                state.charged = true;
                try @import("events.zig").impact(world, slots, projections, .{ .weapon = W.id, .kind = .world, .normal = state.forward, .trail = true, .sequence = @intCast(try world.persistentId(entity) & 1) }, position, now);
                if (engine.integer("developer") > 0) {
                    var text: [128]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig trident: leader={d} merged age={d}\n", .{ try world.persistentId(entity), age }));
                }
            }
        } else {
            state.left = 0;
            state.right = 0;
        }
        projectile.flight.trident = state;
        (try world.get(entity, data.Projectile)).* = projectile;
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    // Move before the 100-ms group callback, matching the reference contact order.
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .trident) continue;
        const slot = (try world.get(entity, data.Binding)).slot;
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        var pose = (try world.get(entity, data.Transform)).*;
        const velocity = (try world.get(entity, data.Velocity)).linear;
        const skip: u16 = if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, @as(f32, @floatFromInt(now - projectile.stepped_ms)) * 0.001)), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = skip, .mask = c.MASK_SHOT });
        pose.position = hit.end;
        projectile.wet = (try engine.collisionService().contents(pose.position, slot)) & c.MASK_WATER != 0;
        if (hit.fraction < 1) {
            if (!hit.sky and !hit.no_impact) {
                const amount = W.blastDamage(projectile.damage, projectile.wet, projectile.flight.trident.charged);
                try @import("area_damage.zig").apply(world, slots, .{ .owner = projectile.owner, .weapon = W.id, .origin = pose.position, .damage = amount, .radius = 100, .skip_slot = slot, .self_scale = 0.325, .occlusion = false }, now);
                try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{ .detonation = true, .charged = projectile.flight.trident.charged }, now);
                if (engine.integer("developer") > 0) {
                    var text: [160]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig trident: impact={d} charged={d} wet={d} damage={d:.1}\n", .{ try world.persistentId(entity), @intFromBool(projectile.flight.trident.charged), @intFromBool(projectile.wet), amount }));
                }
            }
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        pose.angles[2] = @mod(@as(f32, @floatFromInt(now - projectile.born_ms)) * 1.32, 360);
        projectile.stepped_ms = now;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Projectile)).* = projectile;
    }
    try groups(world, slots, projections, now);
    for (slots.occupants) |occupant| if (occupant) |entity| {
        const projectile = world.get(entity, data.Projectile) catch continue;
        if (projectile.flight == .trident) try projectiles.publish(world, entity, projections, now);
    };
}
