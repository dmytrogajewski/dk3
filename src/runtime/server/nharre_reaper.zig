// SPDX-License-Identifier: GPL-2.0-or-later
//! Nharre's reaper owns one victim until its strike or interrupted removal.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").nharre;
const lifetime = @import("weapon_entities.zig");
pub fn frozen(world: *data.World, target: ecs.Entity) bool {
    const owner = (world.get(target, data.Body) catch return false).motion_owner orelse return false;
    const controller = world.find(owner) orelse return false;
    const attack = world.get(controller, data.ActorAttack) catch return false;
    return attack.attack == .nharre_reaper and !attack.attack.nharre_reaper.released and attack.attack.nharre_reaper.target == (world.persistentId(target) catch return false);
}
pub fn release(world: *data.World, entity: ecs.Entity, state: *policy.Reaper) !void {
    if (state.released) return;
    if (world.find(state.target)) |target| {
        const body = try world.get(target, data.Body);
        if (body.motion_owner == try world.persistentId(entity)) {
            body.motion_owner = null;
            body.collision_mask = state.previous_mask;
            (try world.get(target, data.Velocity)).linear = state.previous_velocity;
            if (world.get(target, data.Player) catch null) |player| {
                player.view_height = state.previous_view_height;
                if (player.mode == .frozen) player.mode = if ((try world.get(target, data.Health)).current > 0) .normal else .dead;
            }
        }
    }
    state.released = true;
}
fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, state: *policy.Reaper) !void {
    try release(world, entity, state);
    try lifetime.remove(world, slots, projections, entity);
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, now: i64) !void {
    if ((try world.get(target, data.Health)).current <= 0 or (try world.get(target, data.Body)).motion_owner != null) return;
    if (world.get(target, data.Player) catch null) |player| if (player.mode != .normal) return;
    if (world.get(target, data.Ailments) catch null) |status| if (status.warp != null) return;
    const direction = try @import("clear_direction.zig").choose(world, target, c.MASK_SOLID);
    const point = v.add((try world.get(target, data.Transform)).position, v.scale(direction, 100));
    const yaw = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
    const is_player = (world.get(target, data.Player) catch null) != null;
    var state: policy.Reaper = .{ .target = try world.persistentId(target), .next_ms = now + 500, .previous_velocity = if (is_player) @splat(0) else (try world.get(target, data.Velocity)).linear, .previous_mask = (try world.get(target, data.Body)).collision_mask, .look_angles = .{ -25, yaw, 0 } };
    if (is_player) state.previous_view_height = (try world.get(target, data.Player)).view_height;
    const entity = try world.create(null, .{ data.Transform{ .position = point, .angles = .{ 0, yaw + 180, 0 } }, data.Velocity{}, data.Body{}, data.Random{ .state = try world.persistentId(owner) ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) }, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .nharre_reaper = state } } });
    errdefer world.destroy(entity) catch unreachable;
    try lifetime.bind(world, slots, projections, entity, policy.reaper_model);
    (try world.get(target, data.Body)).motion_owner = try world.persistentId(entity);
    (try world.get(target, data.Velocity)).linear = @splat(0);
    if (is_player) {
        const player = try world.get(target, data.Player);
        player.mode = .frozen;
        player.view_height = 22;
        var appearance: []const u8 = "hiro";
        if (world.get(target, data.Session) catch null) |session| appearance = @import("appearance_catalog").entries[session.appearance].model;
        const voice = if (std.mem.indexOf(u8, appearance, "mikiko") != null) "mikiko/death8.wav" else if (std.mem.indexOf(u8, appearance, "superfly") != null) "superfly/death4.wav" else "hiro/death8.wav";
        try @import("events.zig").sound(world, slots, projections, voice, (try world.get(target, data.Transform)).position, (try world.get(target, data.Binding)).slot, c.CHAN_BODY, now);
    } else (try world.get(target, data.Body)).collision_mask = c.MASK_SOLID;
    try sound(world, slots, projections, entity, "e3/we_reaperappear2.wav", now);
    try sound(world, slots, projections, entity, "e3/we_nharrewind.wav", now);
    try publish(world, entity, projections, now);
}
fn sound(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, name: []const u8, now: i64) !void {
    try @import("events.zig").sound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const state = attack.attack.nharre_reaper;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const out = &projections[binding.slot];
    out.state.number = binding.slot;
    out.state.eType = c.ET_GENERAL;
    out.state.modelindex = binding.model;
    out.state.generic1 = policy.reaper_tag;
    out.state.time = @intCast(attack.born_ms);
    out.state.time2 = @intCast(state.appeared_ms orelse 0);
    out.state.weapon = @intFromBool(state.appeared_ms != null);
    out.state.frame = if (state.appeared_ms) |at| @intCast(std.math.clamp(@divTrunc(now - at, 100), 0, 43)) else 0;
    out.state.origin2 = state.floor;
    out.state.angles2 = state.ceiling;
    out.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    out.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    out.state.pos.trDelta = state.normal;
    out.state.apos.trDelta = state.scorch;
    out.shared.currentOrigin = pose.position;
    out.shared.contents = 0;
    engine.link(out);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    const state = &attack.attack.nharre_reaper;
    const owner = world.find(attack.owner);
    const target = world.find(state.target);
    if (owner == null or target == null or (try world.get(owner.?, data.Health)).current <= 0 or (try world.get(target.?, data.Health)).current <= 0) return remove(world, slots, projections, entity, state);
    if (!state.released) {
        if ((try world.get(target.?, data.Body)).motion_owner != try world.persistentId(entity)) return remove(world, slots, projections, entity, state);
        if ((world.get(target.?, data.Player) catch null) != null) {
            const pose = try world.get(target.?, data.Transform);
            const turn = @as(f32, @floatFromInt(@max(0, now - attack.stepped_ms))) * 0.2;
            for (&pose.angles, state.look_angles) |*current, wanted| current.* += std.math.clamp(@mod(wanted - current.* + 180, 360) - 180, -turn, turn);
        }
        (try world.get(target.?, data.Velocity)).linear = @splat(0);
    }
    if (now >= state.next_ms) {
        if (state.appeared_ms == null) {
            state.appeared_ms = now;
            const point = (try world.get(entity, data.Transform)).position;
            const slot = (try world.get(entity, data.Binding)).slot;
            state.floor = (try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -2000 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID })).end;
            state.ceiling = (try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, 2000 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID })).end;
            const hit = try engine.collisionService().trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -2000 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_PLAYERSOLID });
            if (hit.fraction < 1) {
                state.scorch = hit.end;
                state.normal = hit.normal;
            }
            state.flame_next_ms = now + 100;
        } else {
            const age = now - state.appeared_ms.?;
            if (age >= 4200 and !state.struck) {
                const point = (try world.get(entity, data.Transform)).position;
                const victim = target.?;
                const direction = v.normalize(v.subtract((try world.get(victim, data.Transform)).position, point));
                try release(world, entity, state);
                if ((world.get(victim, data.Player) catch null) != null) {
                    (try world.get(victim, data.Velocity)).linear = v.scale(direction, 1500);
                    (try world.get(victim, data.Body)).grounded = false;
                    (try world.get(victim, data.Player)).ground_entity = c.ENTITYNUM_NONE;
                }
                try sound(world, slots, projections, entity, "e3/we_reaperattack2.wav", now);
                _ = try @import("damage.zig").apply(world, victim, 50, now, .{ .source = try world.persistentId(entity), .attacker_class = "reaper" });
                state.struck = true;
            } else if (age >= 4300) return remove(world, slots, projections, entity, state);
            if (age < 1900 and now >= state.flame_next_ms) {
                const random = try world.get(entity, data.Random);
                state.ceiling[0] += (random.next() * 2 - 1) * 15;
                state.ceiling[1] += (random.next() * 2 - 1) * 15;
                state.flame_next_ms = now + 200;
            }
        }
        state.next_ms = now + 100;
    }
    attack.stepped_ms = now;
    (try world.get(entity, data.ActorAttack)).* = attack;
    try publish(world, entity, projections, now);
}

test "Nharre releases exactly its own victim and restores NPC velocity and mask" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    const controller = try world.create(2, .{data.Transform{}});
    const npc = try world.create(1, .{ data.Body{ .motion_owner = 2, .collision_mask = c.MASK_SOLID }, data.Velocity{}, data.Health{} });
    var state: policy.Reaper = .{ .target = 1, .next_ms = 500, .previous_velocity = .{ 40, 20, -30 }, .previous_mask = c.MASK_PLAYERSOLID };
    try release(&world, controller, &state);
    try t.expect(state.released);
    try t.expect((try world.get(npc, data.Body)).motion_owner == null);
    try t.expectEqual(@as(u32, c.MASK_PLAYERSOLID), (try world.get(npc, data.Body)).collision_mask);
    try t.expectEqual(@as(v.Vec3, .{ 40, 20, -30 }), (try world.get(npc, data.Velocity)).linear);
    state.released = false;
    (try world.get(npc, data.Body)).motion_owner = 3;
    (try world.get(npc, data.Velocity)).linear = @splat(5);
    try release(&world, controller, &state);
    try t.expectEqual(@as(?u32, 3), (try world.get(npc, data.Body)).motion_owner);
    try t.expectEqual(@as(v.Vec3, @splat(5)), (try world.get(npc, data.Velocity)).linear);
}
