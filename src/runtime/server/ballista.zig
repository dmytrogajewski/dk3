// SPDX-License-Identifier: GPL-2.0-or-later
//! Ballista contact, bounded victim transport and wall pinning.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
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
    const owner = access.find(world, owner_id) orelse return;
    const projectile = owner.get(data.Projectile) catch return;
    if (projectile.flight == .ballista and projectile.flight.ballista.victim == try world.persistentId(target)) {
        body.motion_owner = null;
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
    if (state.victim) |victim_id| if (access.find(world, victim_id)) |target| {
        const body = try target.get(data.Body);
        if (body.motion_owner == id) body.motion_owner = null;
        if (alive(target.world, target.entity)) try setVelocity(target.world, target.entity, @splat(0));
        if (target.get(data.MapObject) catch null) |object| if (std.mem.eql(u8, object.classname, "monster_lycanthir")) {
            state.releases +|= 50;
        };
    };
    state.victim = null;
    state.releases +|= 1;
}
fn remove(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, position: v.Vec3, normal: v.Vec3, explode: bool, owner: u32, now: i64) !void {
    var state = projectile.flight.ballista;
    if (state.victim != null) try release(world, entity, &state);
    if (explode) {
        try @import("area_damage.zig").apply(world, slots, .{ .world = owner, .owner = projectile.owner, .weapon = W.id, .origin = position, .damage = projectile.damage * 0.5, .radius = 128, .skip_slot = (try world.get(entity, data.Binding)).slot, .occlusion = false, .inertial = true }, now);
        try @import("events.zig").impactOwned(world, slots, projections, owner, .{ .weapon = W.id, .kind = .world, .normal = normal, .detonation = true }, position, now);
    }
    if (engine.integer("developer") > 0) {
        var text: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig ballista: removed={d} explode={d} releases={d}\n", .{ try world.persistentId(entity), @intFromBool(explode), state.releases }));
    }
    try entities.remove(world, slots, projections, entity);
}
fn skewer(world: *data.World, entity: ecs.Entity, target: Ref, projectile: *data.Projectile, position: v.Vec3, now: i64) !void {
    const target_id = try target.id();
    _ = try damage.hurt(target.world, target.entity, projectile.owner, W.id, projectile.damage, now, false);
    const body = (try target.get(data.Body)).*;
    const target_position = (try target.get(data.Transform)).position;
    const state = &projectile.flight.ballista;
    state.last_victim = target_id;
    if (!W.midsection(v.subtract(position, target_position), body.mins, body.maxs)) return;
    const object = target.get(data.MapObject) catch null;
    state.victim = target_id;
    state.release_ms = now - projectile.born_ms + W.holdMilliseconds(if (object) |value| value.classname else "", body.mass);
    (try target.get(data.Body)).motion_owner = try world.persistentId(entity);
    try setVelocity(target.world, target.entity, state.velocity);
    if (engine.integer("developer") > 0) {
        var text: [140]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig ballista: bolt={d} victim={d} hold={d}\n", .{ try world.persistentId(entity), target_id, state.release_ms - (now - projectile.born_ms) }));
    }
}
fn sweep(motion: *@import("region_motion.zig").Cursor, request: @import("../domain/collision.zig").Request, ignored: ?Ref) !@import("../domain/collision.zig").Trace {
    if (ignored) |target| {
        const context = access.contextFor(target.world) orelse return error.BallistaVictimWorldUnavailable;
        const scope = try context.select();
        defer scope.deinit();
        const projection = &context.projection[(try target.get(data.Binding)).slot];
        engine.unlink(projection);
        defer engine.link(projection);
        return motion.trace(request);
    }
    return motion.trace(request);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .ballista or now <= projectile.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, projectile.owner);
        var pose = (try world.get(entity, data.Transform)).*;
        const age = now - projectile.born_ms;
        const state = &projectile.flight.ballista;
        var velocity = if (projectile.stuck) v.Vec3{ 0, 0, 0 } else state.velocity;
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms or state.releases >= 2) {
            try remove(world, slots, projections, entity, projectile, pose.position, state.normal, projectile.stuck or state.releases >= 2, motion.owner, now);
            continue;
        }
        if (age >= state.next_ms) {
            state.next_ms = age + 100;
            if (state.releases > 0 and v.length(v.subtract(pose.position, state.previous_position)) < 20) projectile.stuck = true;
            state.previous_position = pose.position;
            if (state.victim) |victim_id| {
                const target = access.find(world, victim_id);
                if (target == null or !alive(target.?.world, target.?.entity) or age >= state.release_ms) {
                    try release(world, entity, state);
                } else if (projectile.stuck) {
                    const body = (try target.?.get(data.Body)).*;
                    const center = v.add((try target.?.get(data.Transform)).position, v.scale(v.add(body.mins, body.maxs), 0.5));
                    const delta = v.subtract(v.add(pose.position, v.scale(state.normal, 20)), center);
                    try setVelocity(target.?.world, target.?.entity, v.add(v.scale(state.normal, if (v.length(delta) > 50) -500 else 0), v.scale(v.normalize(delta), 200)));
                    if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) _ = try damage.hurt(target.?.world, target.?.entity, projectile.owner, W.id, 1, now, false);
                } else try setVelocity(target.?.world, target.?.entity, state.velocity);
            }
        }
        if (projectile.stuck and state.victim == null) {
            try remove(world, slots, projections, entity, projectile, pose.position, state.normal, true, motion.owner, now);
            continue;
        }
        if (!projectile.stuck) {
            // Unlink a carried/recently struck hull only for this sweep. Other actors
            // still block the bolt, and their own locomotion remains collision checked.
            const ignored = if (state.victim orelse state.last_victim) |id| access.find(world, id) else null;
            const hit = try sweep(&motion, .{ .start = pose.position, .end = v.add(pose.position, v.scale(state.velocity, @as(f32, @floatFromInt(now - projectile.stepped_ms)) * 0.001)), .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SHOT }, ignored);
            pose.position = hit.end;
            if (hit.fraction < 1) {
                const target = access.victim(world, slots, hit);
                const actor = if (target) |who| (who.get(data.Actor) catch null) != null or (who.get(data.Player) catch null) != null else false;
                if (hit.sky or hit.no_impact) {
                    try remove(world, slots, projections, entity, projectile, pose.position, hit.normal, false, motion.owner, now);
                    continue;
                } else if (actor) {
                    if (state.victim != null or (try target.?.get(data.Body)).motion_owner != null) {
                        try remove(world, slots, projections, entity, projectile, pose.position, hit.normal, true, motion.owner, now);
                        continue;
                    }
                    try skewer(world, entity, target.?, &projectile, pose.position, now);
                } else if (state.victim != null and W.canPin(v.normalize(state.velocity), hit.normal)) {
                    projectile.stuck = true;
                    state.normal = hit.normal;
                    state.release_ms = age + 2000;
                    velocity = @splat(0);
                    if (access.find(world, state.victim.?)) |who| try setVelocity(who.world, who.entity, @splat(0));
                    (try world.get(entity, data.Lifetime)).expires_ms = now + 2000;
                    if (engine.integer("developer") > 0) {
                        var text: [130]u8 = undefined;
                        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig ballista: pinned={d} victim={d}\n", .{ try world.persistentId(entity), state.victim.? }));
                    }
                } else {
                    try remove(world, slots, projections, entity, projectile, pose.position, hit.normal, true, motion.owner, now);
                    continue;
                }
            }
        }
        projectile.stepped_ms = now;
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = if (projectile.stuck) @splat(0) else velocity;
        try @import("projectiles.zig").publish(world, entity, projections, now);
        try motion.finish(world, entity, now);
    }
}
