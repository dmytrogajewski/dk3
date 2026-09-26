// SPDX-License-Identifier: GPL-2.0-or-later
//! Ballista contact, bounded victim transport and wall pinning.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").ballista;
const v = @import("../domain/vector.zig");
const damage = @import("weapon_damage.zig");
const entities = @import("weapon_entities.zig");
const c = abi.c;
pub fn detach(world: *data.World, target: ecs.Entity) !void {
    const body = try world.get(target, data.Body);
    const owner_id = body.motion_owner orelse return;
    body.motion_owner = null;
    const owner = world.find(owner_id) orelse return;
    const projectile = world.get(owner, data.Projectile) catch return;
    if (projectile.flight == .ballista and projectile.flight.ballista.victim == try world.persistentId(target)) {
        projectile.flight.ballista.victim = null;
        projectile.flight.ballista.releases +|= 1;
    }
}
fn alive(world: *data.World, entity: ecs.Entity) bool {
    return if (world.get(entity, data.Health) catch null) |health| health.current > 0 else false;
}
fn setVelocity(world: *data.World, target: ecs.Entity, velocity: v.Vec3) !void {
    (try world.get(target, data.Velocity)).linear = velocity;
    (try world.get(target, data.Body)).grounded = false;
    if (world.get(target, data.Actor) catch null) |actor| actor.ground_entity = c.ENTITYNUM_NONE;
    if (world.get(target, data.Player) catch null) |player| {
        player.ground_entity = c.ENTITYNUM_NONE;
        player.timer = .knockback;
        player.timer_ms = 100;
    }
}
fn release(world: *data.World, entity: ecs.Entity, state: *W.BallisticState) !void {
    const id = try world.persistentId(entity);
    if (state.victim) |victim_id| if (world.find(victim_id)) |target| {
        const body = try world.get(target, data.Body);
        if (body.motion_owner == id) body.motion_owner = null;
        if (alive(world, target)) try setVelocity(world, target, @splat(0));
        if (world.get(target, data.MapObject) catch null) |object| if (std.mem.eql(u8, object.classname, "monster_lycanthir")) {
            state.releases +|= 50;
        };
    };
    state.victim = null;
    state.releases +|= 1;
}
fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, position: v.Vec3, normal: v.Vec3, explode: bool, now: i64) !void {
    var state = projectile.flight.ballista;
    if (state.victim != null) try release(world, entity, &state);
    if (explode) {
        try @import("area_damage.zig").apply(world, slots, .{ .owner = projectile.owner, .weapon = W.id, .origin = position, .damage = projectile.damage * 0.5, .radius = 128, .skip_slot = (try world.get(entity, data.Binding)).slot, .occlusion = false, .inertial = true }, now);
        try @import("events.zig").impact(world, slots, projections, .{ .weapon = W.id, .kind = .world, .normal = normal, .detonation = true }, position, now);
    }
    if (engine.integer("developer") > 0) {
        var text: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig ballista: removed={d} explode={d} releases={d}\n", .{ try world.persistentId(entity), @intFromBool(explode), state.releases }));
    }
    try entities.remove(world, slots, projections, entity);
}
fn skewer(world: *data.World, entity: ecs.Entity, target: ecs.Entity, projectile: *data.Projectile, position: v.Vec3, now: i64) !void {
    const target_id = try world.persistentId(target);
    _ = try damage.hurt(world, target, projectile.owner, W.id, projectile.damage, now, false);
    const body = (try world.get(target, data.Body)).*;
    const target_position = (try world.get(target, data.Transform)).position;
    const state = &projectile.flight.ballista;
    state.last_victim = target_id;
    if (!W.midsection(v.subtract(position, target_position), body.mins, body.maxs)) return;
    const object = world.get(target, data.MapObject) catch null;
    state.victim = target_id;
    state.release_ms = now - projectile.born_ms + W.holdMilliseconds(if (object) |value| value.classname else "", body.mass);
    (try world.get(target, data.Body)).motion_owner = try world.persistentId(entity);
    try setVelocity(world, target, state.velocity);
    if (engine.integer("developer") > 0) {
        var text: [140]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig ballista: bolt={d} victim={d} hold={d}\n", .{ try world.persistentId(entity), target_id, state.release_ms - (now - projectile.born_ms) }));
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .ballista) continue;
        var pose = (try world.get(entity, data.Transform)).*;
        const age = now - projectile.born_ms;
        const state = &projectile.flight.ballista;
        var velocity = if (projectile.stuck) v.Vec3{ 0, 0, 0 } else state.velocity;
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms or state.releases >= 2) {
            try remove(world, slots, projections, entity, projectile, pose.position, state.normal, projectile.stuck or state.releases >= 2, now);
            continue;
        }
        if (age >= state.next_ms) {
            state.next_ms = age + 100;
            if (state.releases > 0 and v.length(v.subtract(pose.position, state.previous_position)) < 20) projectile.stuck = true;
            state.previous_position = pose.position;
            if (state.victim) |victim_id| {
                const target = world.find(victim_id);
                if (target == null or !alive(world, target.?) or age >= state.release_ms) {
                    try release(world, entity, state);
                } else if (projectile.stuck) {
                    const body = (try world.get(target.?, data.Body)).*;
                    const center = v.add((try world.get(target.?, data.Transform)).position, v.scale(v.add(body.mins, body.maxs), 0.5));
                    const delta = v.subtract(v.add(pose.position, v.scale(state.normal, 20)), center);
                    try setVelocity(world, target.?, v.add(v.scale(state.normal, if (v.length(delta) > 50) -500 else 0), v.scale(v.normalize(delta), 200)));
                    if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) _ = try damage.hurt(world, target.?, projectile.owner, W.id, 1, now, false);
                } else try setVelocity(world, target.?, state.velocity);
            }
        }
        if (projectile.stuck and state.victim == null) {
            try remove(world, slots, projections, entity, projectile, pose.position, state.normal, true, now);
            continue;
        }
        if (!projectile.stuck) {
            // Unlink a carried/recently struck hull only for this sweep. Other actors
            // still block the bolt, and their own locomotion remains collision checked.
            const ignored = if (state.victim orelse state.last_victim) |id| world.find(id) else null;
            const ignored_slot = if (ignored) |target| slots.find(target) else null;
            if (ignored_slot) |index| engine.unlink(&projections[index]);
            const skip: u16 = if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
            const hit = engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(state.velocity, @as(f32, @floatFromInt(now - projectile.stepped_ms)) * 0.001)), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = skip, .mask = c.MASK_SHOT }) catch |err| {
                if (ignored_slot) |index| engine.link(&projections[index]);
                return err;
            };
            if (ignored_slot) |index| engine.link(&projections[index]);
            pose.position = hit.end;
            if (hit.fraction < 1) {
                const target = if (hit.entity < slots.occupants.len) slots.occupants[hit.entity] else null;
                const actor = if (target) |who| (world.get(who, data.Actor) catch null) != null or (world.get(who, data.Player) catch null) != null else false;
                if (hit.sky or hit.no_impact) {
                    try remove(world, slots, projections, entity, projectile, pose.position, hit.normal, false, now);
                    continue;
                } else if (actor) {
                    if (state.victim != null or (try world.get(target.?, data.Body)).motion_owner != null) {
                        try remove(world, slots, projections, entity, projectile, pose.position, hit.normal, true, now);
                        continue;
                    }
                    try skewer(world, entity, target.?, &projectile, pose.position, now);
                } else if (state.victim != null and W.canPin(v.normalize(state.velocity), hit.normal)) {
                    projectile.stuck = true;
                    state.normal = hit.normal;
                    state.release_ms = age + 2000;
                    velocity = @splat(0);
                    if (world.find(state.victim.?)) |who| try setVelocity(world, who, @splat(0));
                    (try world.get(entity, data.Lifetime)).expires_ms = now + 2000;
                    if (engine.integer("developer") > 0) {
                        var text: [130]u8 = undefined;
                        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig ballista: pinned={d} victim={d}\n", .{ try world.persistentId(entity), state.victim.? }));
                    }
                } else {
                    try remove(world, slots, projections, entity, projectile, pose.position, hit.normal, true, now);
                    continue;
                }
            }
        }
        projectile.stepped_ms = now;
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = if (projectile.stuck) @splat(0) else velocity;
        try @import("projectiles.zig").publish(world, entity, projections, now);
    }
}
