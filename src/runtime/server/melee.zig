// SPDX-License-Identifier: GPL-2.0-or-later
//! Delayed strikes are persistent actions. Resolve current owner pose at each strike.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const catalog = @import("weapon_catalog");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const weapons = @import("../domain/weapons.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
pub fn launch(world: *data.World, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const action: data.Melee = .{ .owner = try world.persistentId(owner), .weapon = shot.weapon, .sequence = shot.sequence, .experience = (try world.get(owner, data.Weapons)).dk3SwordExperience, .damage = table.entries[shot.weapon].damage, .started_ms = now, .timing_factor = catalog.transitions.attackFactor((try world.get(owner, data.Character)).attribute(.attack, now)) };
    _ = try action.plan();
    _ = try world.create(null, .{ data.Transform{ .position = shot.position }, action });
}
fn trace(start: v.Vec3, end: v.Vec3, radius: f32, slot: u16) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(-radius), .maxs = @splat(radius), .slot = slot, .mask = c.MASK_SHOT });
}
fn arc(pose: data.Transform, plan: catalog.melee.Plan, index: u8, range: f32, muzzle: v.Vec3, slot: u16, ducked: bool) !@import("../domain/collision.zig").Trace {
    const basis = v.basis(pose.angles);
    const up = v.cross(basis.right, basis.forward);
    const origin = v.add(v.add(pose.position, if (plan.world_muzzle) muzzle else @as(v.Vec3, @splat(0))), .{ 0, 0, if (ducked) plan.crouching_height else plan.height });
    if (v.length(plan.from[index]) < 0.01) {
        const goal = v.add(origin, v.scale(basis.forward, plan.range orelse range));
        if (plan.body_trace) return engine.collisionService().trace(.{ .start = origin, .end = goal, .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, if (ducked) @as(f32, 4) else 32 }, .slot = slot, .mask = c.MASK_SHOT });
        return trace(origin, goal, plan.radius, slot);
    }
    var last: @import("../domain/collision.zig").Trace = .{ .fraction = 1, .end = origin, .normal = @splat(0) };
    // Expand an arc in bounded radial bands, resolving the nearest band first.
    for (0..5) |band| {
        const distance = range * (0.01 + @as(f32, @floatFromInt(band)) * 0.2);
        const from = v.scale(v.normalize(plan.from[index]), distance);
        const to = v.scale(v.normalize(plan.to[index]), distance);
        const middle = v.scale(v.normalize(v.add(from, to)), distance);
        var points: [3]v.Vec3 = undefined;
        for ([_]v.Vec3{ from, middle, to }, &points) |offset, *point| point.* = v.add(origin, v.add(v.scale(basis.forward, offset[0]), v.add(v.scale(basis.right, offset[1]), v.scale(up, offset[2]))));
        for (points[1..]) |end| {
            last = try trace(points[0], end, plan.radius, slot);
            if (last.fraction < 1) return last;
        }
    }
    return last;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, table: *const weapons.Table, now: i64) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.Melee}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        var action = (try world.get(entity, data.Melee)).*;
        const owner = world.find(action.owner) orelse {
            try world.destroy(entity);
            continue;
        };
        const plan = try action.plan();
        const loadout = (try world.get(owner, data.Weapons)).*;
        if ((try world.get(owner, data.Health)).current <= 0 or (plan.require_selected and loadout.weapon != action.weapon)) {
            try world.destroy(entity);
            continue;
        }
        const binding = (try world.get(owner, data.Binding)).*;
        const pose = (try world.get(owner, data.Transform)).*;
        const ducked = (try world.get(owner, data.Player)).ducked;
        while (try action.due(now)) {
            const hit = try arc(pose, plan, action.next_hit, if (table.entries[action.weapon].range > 0) table.entries[action.weapon].range else plan.fallback_range, table.entries[action.weapon].muzzle, binding.slot, ducked);
            if (plan.sound_on_strike and action.next_hit == 0) if (catalog.fireSound(action.weapon, action.sequence, try world.persistentId(entity))) |sound| try @import("events.zig").sound(world, slots, projections, sound, pose.position, binding.slot, c.CHAN_WEAPON, now);
            if (hit.fraction < 1 and hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |target| {
                const target_pose = (try world.get(target, data.Transform)).*;
                const object = world.get(target, data.MapObject) catch null;
                const defending = if (world.get(target, data.Weapons) catch null) |weapons_state| weapons_state.weapon == action.weapon else false;
                const result = catalog.meleeDamage(action.weapon, .{ .damage = action.damage, .lifetime_ms = @intFromFloat(std.math.clamp(table.entries[action.weapon].lifetime * 1000, 0, 3600000)), .experience = action.experience, .victim_class = if (object) |value| value.classname else "", .forward = v.basis(pose.angles).forward, .facing = v.basis(target_pose.angles).forward, .defending = defending, .serial = try world.persistentId(entity) });
                if (try @import("weapon_damage.zig").hurt(world, target, action.owner, action.weapon, result.amount, now, false)) {
                    if (plan.inertial) try @import("weapon_damage.zig").shove(world, target, action.owner, v.basis(pose.angles).forward, result.amount, now);
                    try @import("ailments.zig").apply(world, target, result.effect, action.owner, action.weapon, now);
                }
                if (result.sound) |sound| try @import("events.zig").sound(world, slots, projections, sound, pose.position, binding.slot, c.CHAN_BODY, now);
            };
            try @import("impacts.zig").contact(world, slots, projections, action.weapon, hit, .{ .sequence = action.sequence }, now);
            if (engine.integer("developer") > 0) {
                var message: [160]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig melee: weapon={d} sequence={d} strike={d} age={d} hit={d} id={d}\n", .{ action.weapon, action.sequence, action.next_hit, now - action.started_ms, @intFromBool(hit.fraction < 1), try world.persistentId(entity) }));
            }
            action.next_hit += 1;
        }
        if (action.next_hit >= plan.hits) try world.destroy(entity) else (try world.get(entity, data.Melee)).* = action;
    }
}
