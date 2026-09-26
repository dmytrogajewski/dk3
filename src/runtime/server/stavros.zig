// SPDX-License-Identifier: GPL-2.0-or-later
//! Meteor launch/fragment collisions consume class-owned growth and flight rules.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").stavros;
const weapons = @import("../domain/weapons.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
fn angles(direction: v.Vec3) v.Vec3 {
    return .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * (180.0 / std.math.pi), std.math.atan2(direction[1], direction[0]) * (180.0 / std.math.pi), 0 };
}
fn trace(start: v.Vec3, end: v.Vec3, skip: u16, meteor: W.BallisticState) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = meteor.mins(), .maxs = meteor.maxs(), .slot = skip, .mask = c.MASK_SHOT });
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const tuning = table.entries[W.id];
    const owner_id = try world.persistentId(owner);
    var random: data.Random = .{ .state = owner_id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) ^ 0xe68521f3 };
    var meteor: W.BallisticState = .{ .radius = tuning.range, .maximum_speed = tuning.speed };
    for (&meteor.angular_delta) |*axis| axis.* = (2 * random.next() - 1) * 40;
    const offset = v.add(v.scale(v.basis(v.add(shot.angles, .{ -45, 35, 0 })).forward, 25), .{ 0, 0, 25 });
    const position = (try trace(v.add(shot.position, .{ 0, 0, shot.view_height }), v.add(shot.position, offset), (try world.get(owner, data.Binding)).slot, meteor)).end;
    const projectile: data.Projectile = .{ .owner = owner_id, .weapon = W.id, .damage = tuning.damage, .born_ms = now, .stepped_ms = now, .flight = .{ .stavros = meteor }, .launch_position = position, .speed = tuning.speed, .lifetime_ms = 12000 };
    const entity = try world.create(null, .{ data.Transform{ .position = position, .angles = shot.angles }, data.Velocity{ .linear = v.scale(v.basis(shot.angles).forward, tuning.speed * 0.05) }, projectile, random, data.Lifetime{ .expires_ms = now + 12000 } });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, W.spec.visual.projectile_model);
    try @import("projectiles.zig").publish(world, entity, projections, now);
}
fn fragment(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, parent: data.Projectile, origin: v.Vec3, normal: v.Vec3, random: *data.Random, now: i64) !void {
    var orientation = angles(normal);
    orientation[0] += (2 * random.next() - 1) * 45;
    orientation[1] += (2 * random.next() - 1) * 45;
    const basis = v.basis(orientation);
    const offset = v.add(v.add(v.scale(v.cross(basis.right, basis.forward), 50 * (2 * random.next() - 1)), v.scale(basis.right, 50 * (2 * random.next() - 1))), v.scale(basis.forward, 10));
    // Gold applies a second independent cone at fragment creation.
    orientation[0] += (2 * random.next() - 1) * 45;
    orientation[1] += (2 * random.next() - 1) * 45;
    const scale = 0.3 + random.next() * 0.35;
    var meteor: W.BallisticState = .{ .fragment = true, .radius = parent.flight.stavros.radius * 0.5, .maximum_speed = parent.flight.stavros.maximum_speed, .angular_delta = .{ (2 * random.next() - 1) * 60, 0, (2 * random.next() - 1) * 60 } };
    for (&meteor.scale) |*axis| axis.* = scale + random.next() * 0.2;
    const position = (try trace(origin, v.add(origin, offset), c.ENTITYNUM_NONE, meteor)).end;
    const projectile: data.Projectile = .{ .owner = parent.owner, .weapon = W.id, .damage = parent.damage * 0.5, .born_ms = now, .stepped_ms = now, .flight = .{ .stavros = meteor }, .launch_position = position, .speed = meteor.maximum_speed * 0.75, .lifetime_ms = 6000 };
    const entity = try world.create(null, .{ data.Transform{ .position = position, .angles = orientation }, data.Velocity{ .linear = v.scale(v.basis(orientation).forward, projectile.speed) }, projectile, data.Lifetime{ .expires_ms = now + 6000 } });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, W.spec.visual.projectile_model);
    try @import("projectiles.zig").publish(world, entity, projections, now);
}
fn explode(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, projectile: data.Projectile, hit: @import("../domain/collision.zig").Trace, now: i64) !void {
    const meteor = projectile.flight.stavros;
    var fragments: u8 = 0;
    if (!meteor.fragment) {
        var random = (try world.get(entity, data.Random)).*;
        fragments = W.fragments(engine.integer("g_gametype") == c.GT_SINGLE_PLAYER, random.next());
        for (0..fragments) |_| try fragment(world, slots, projections, projectile, hit.end, hit.normal, &random, now);
    }
    const skip: u16 = if (!meteor.fragment) (if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE) else (try world.get(entity, data.Binding)).slot;
    try @import("area_damage.zig").apply(world, slots, .{ .owner = projectile.owner, .weapon = W.id, .origin = hit.end, .damage = projectile.damage, .radius = meteor.radius, .skip_slot = skip, .occlusion = false, .inertial = true }, now);
    try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{ .detonation = true, .charged = !meteor.fragment }, now);
    if (engine.integer("developer") > 0) {
        var output: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig stavros: exploded fragment={d} fragments={d} bounces={d}\n", .{ @intFromBool(meteor.fragment), fragments, projectile.bounces }));
    }
    try entities.remove(world, slots, projections, entity);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .stavros) continue;
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        var meteor = projectile.flight.stavros;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var at = projectile.stepped_ms;
        const skip: u16 = if (meteor.fragment) c.ENTITYNUM_NONE else if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
        while (at < now) {
            const milliseconds: u32 = @intCast(@min(20, now - at));
            const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
            velocity = meteor.tick(at - projectile.born_ms, velocity, &pose.angles);
            const gravity: f32 = if (meteor.fragment) 800 else 0;
            const goal = v.add(v.add(pose.position, v.scale(velocity, seconds)), .{ 0, 0, -0.5 * gravity * seconds * seconds });
            velocity[2] -= gravity * seconds;
            const hit = try trace(pose.position, goal, skip, meteor);
            pose.position = hit.end;
            at += milliseconds;
            if (hit.sky or hit.no_impact) {
                try entities.remove(world, slots, projections, entity);
                break;
            }
            if (hit.fraction == 1) continue;
            if (!meteor.fragment or projectile.bounces >= 1) {
                projectile.flight.stavros = meteor;
                try explode(world, slots, projections, entity, projectile, hit, now);
                break;
            }
            projectile.bounces += 1;
            velocity = @import("../domain/combat.zig").reflect(velocity, hit.normal, 1);
            pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
        }
        if (!world.alive(entity)) continue;
        projectile.flight.stavros = meteor;
        projectile.stepped_ms = now;
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        try @import("projectiles.zig").publish(world, entity, projections, now);
    }
}
