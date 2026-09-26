// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent C4 controller: flight, attachment, sensing and chained detonation.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("weapon_catalog");
const W = catalog.c4;
const v = @import("../domain/vector.zig");
const rules = @import("../domain/combat.zig");
const entities = @import("weapon_entities.zig");
const area = @import("area_damage.zig");
const c = abi.c;

pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const charge = (try world.get(entity, data.Charge)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_MISSILE;
    projection.state.weapon = W.id;
    projection.state.modelindex = binding.model;
    projection.state.time = @intCast(charge.born_ms);
    projection.state.time2 = @intCast(charge.beep_ms orelse 0);
    // Dedicated transport bit; stuck bolts use bit 0 for their fading lifetime.
    projection.state.generic1 = if (charge.attached) 4 else 0;
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = @bitCast(body.contents);
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: @import("../domain/weapons.zig").Fired, table: *const @import("../domain/weapons.zig").Table, now: i64) !void {
    const tuning = table.entries[W.id];
    const owner_id = try world.persistentId(owner);
    const owner_slot = (try world.get(owner, data.Binding)).slot;
    const eye = rules.eye(shot.position, shot.view_height);
    const forward = v.basis(shot.angles).forward;
    const start = (try engine.collisionService().trace(.{ .start = eye, .end = rules.muzzle(eye, shot.angles, tuning.muzzle), .mins = @splat(-8), .maxs = @splat(8), .slot = owner_slot, .mask = c.MASK_SHOT })).end;
    const target = (try engine.collisionService().trace(.{ .start = eye, .end = v.add(eye, v.scale(forward, 2000)), .mins = @splat(0), .maxs = @splat(0), .slot = owner_slot, .mask = c.MASK_SHOT })).end;
    const attack = (try world.get(owner, data.Character)).attribute(.attack, now);
    const entity = try world.create(null, .{
        data.Transform{ .position = start, .angles = shot.angles },
        data.Velocity{ .linear = v.scale(rules.aim(start, target, forward), tuning.speed * (1 + 0.3 * @as(f32, @floatFromInt(attack)))) },
        data.Body{ .mins = @splat(-8), .maxs = @splat(8), .contents = c.CONTENTS_CORPSE, .collision_mask = c.MASK_SOLID },
        data.Health{ .current = 5, .maximum = 5 },
        data.Charge{ .owner = owner_id, .damage = tuning.damage, .born_ms = now, .stepped_ms = now, .next_ms = now + 50, .expires_ms = now + @as(i64, @intFromFloat(std.math.clamp(tuning.lifetime * 1000, 1, 3600000))) },
        data.Random{ .state = owner_id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) },
    });
    errdefer world.destroy(entity) catch unreachable;
    try entities.bind(world, slots, projections, entity, W.spec.visual.projectile_model);
    try publish(world, entity, projections, now);
}
pub fn detonate(world: *data.World, owner: u32, now: i64, staggered: bool) !usize {
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.Charge}), 0, data.World.mask(.{data.Charge}));
    defer query.deinit();
    while (query.next()) |view| for (view.write(data.Charge)) |*charge| if (charge.owner == owner) {
        count += 1;
        charge.schedule(now + if (staggered) @as(i64, @intCast(count * 200)) else 0);
    };
    return count;
}
fn deployed(world: *data.World, owner: u32) usize {
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.Charge}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Charge)) |charge| {
        if (charge.owner == owner) count += 1;
    };
    return count;
}
fn explode(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const charge = (try world.get(entity, data.Charge)).*;
    const position = (try world.get(entity, data.Transform)).position;
    const slot = (try world.get(entity, data.Binding)).slot;
    var count: usize = 1;
    {
        var query = world.queryAccess(data.World.mask(.{ data.Charge, data.Transform }), 0, data.World.mask(.{data.Charge}));
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.write(data.Charge), view.read(data.Transform)) |other, *nearby, pose| {
            if (other.index == entity.index or v.length(v.subtract(position, pose.position)) > W.chain_range) continue;
            nearby.schedule(now + @as(i64, @intCast(count * 100)));
            count += 1;
        };
    }
    engine.unlink(&projections[slot]);
    try area.apply(world, slots, .{ .owner = charge.owner, .weapon = W.id, .origin = position, .damage = charge.damage * (1 + 0.1 * @as(f32, @floatFromInt(count))), .radius = W.blast_range, .skip_slot = slot, .self_scale = if (charge.attached) 1 else 0.5 }, now);
    try @import("events.zig").impact(world, slots, projections, .{ .weapon = W.id, .kind = .world, .normal = .{ 0, 0, 1 }, .detonation = true }, position, now);
    if (engine.integer("developer") > 0) {
        var message: [160]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig charge: id={d} exploded chain={d} attached={d}\n", .{ try world.persistentId(entity), count, @intFromBool(charge.attached) }));
    }
    try entities.remove(world, slots, projections, entity);
}
fn sense(world: *data.World, slots: *const Slots, position: v.Vec3, skip: u16) !f32 {
    var nearest: f32 = W.sense_range;
    for (slots.occupants, 0..) |occupant, slot| {
        const target = occupant orelse continue;
        if ((world.get(target, data.Actor) catch null) == null and (world.get(target, data.Player) catch null) == null) continue;
        if ((try world.get(target, data.Health)).current <= 0) continue;
        const distance = v.length(v.subtract((try world.get(target, data.Transform)).position, position));
        if (distance >= nearest or !try area.visible(position, try area.center(world, target), skip, @intCast(slot))) continue;
        nearest = distance;
    }
    return nearest;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    for (slots.occupants) |occupant| {
        const entity = occupant orelse continue;
        var charge = (world.get(entity, data.Charge) catch continue).*;
        const slot = (try world.get(entity, data.Binding)).slot;
        if ((try world.get(entity, data.Health)).current <= 0) charge.schedule(now);
        if (charge.detonate_ms) |at| if (now >= at) {
            try explode(world, slots, projections, entity, now);
            continue;
        };
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var random = (try world.get(entity, data.Random)).*;
        var collided = false;
        if (!charge.attached) {
            // Charge is shootable, so exclude its own hull while sweeping from the owner.
            engine.unlink(&projections[slot]);
            const skip: u16 = if (world.find(charge.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
            var at = charge.stepped_ms;
            while (at < now) {
                const elapsed: f32 = @as(f32, @floatFromInt(@min(20, now - at))) * 0.001;
                const end = v.add(v.add(pose.position, v.scale(velocity, elapsed)), .{ 0, 0, -400 * elapsed * elapsed });
                velocity[2] -= 800 * elapsed;
                const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = end, .mins = @splat(-8), .maxs = @splat(8), .slot = skip, .mask = c.MASK_SHOT });
                pose.position = hit.end;
                at += @min(20, now - at);
                if (hit.sky or hit.no_impact) {
                    try entities.remove(world, slots, projections, entity);
                    break;
                }
                if (hit.fraction == 1) continue;
                const target = if (hit.entity < slots.occupants.len) slots.occupants[hit.entity] else null;
                if (target) |who| if ((world.get(who, data.Health) catch null) != null) {
                    collided = true;
                    break;
                };
                pose.position = v.add(pose.position, v.scale(hit.normal, 0.5));
                velocity = @splat(0);
                charge.attach(now);
                if (target) |who| if (projections[hit.entity].shared.bmodel != 0) {
                    try world.put(entity, data.Attachment{ .parent_id = try world.persistentId(who), .offset = v.subtract(pose.position, (try world.get(who, data.Transform)).position) });
                };
                try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{}, now);
                break;
            }
        }
        if (!world.alive(entity)) continue;
        if (!charge.attached) pose.angles[2] = @mod(@as(f32, @floatFromInt(now - charge.born_ms)) * 1.44, 360);
        charge.stepped_ms = now;
        var beep = false;
        if (charge.detonate_ms == null and now >= charge.next_ms) {
            charge.next_ms = now + 100;
            if (!charge.attached) {
                velocity[0] += (random.next() - 0.5) * 80;
                velocity[1] += (random.next() - 0.5) * 80;
                velocity[2] += (random.next() - 0.5) * 20;
            }
            if (now >= charge.expires_ms or deployed(world, charge.owner) > W.max_deployed) {
                if (now >= charge.expires_ms or random.next() <= 0.05) {
                    // Publish the local state before the group scheduling mutation.
                    (try world.get(entity, data.Charge)).* = charge;
                    _ = try detonate(world, charge.owner, now, true);
                    charge = (try world.get(entity, data.Charge)).*;
                } else beep = true;
            }
            if (charge.detonate_ms == null) switch (charge.sensing(try sense(world, slots, pose.position, slot), now)) {
                .none => {},
                .beep => beep = true,
                .explode => collided = true,
            };
        }
        (try world.get(entity, data.Charge)).* = charge;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        (try world.get(entity, data.Random)).* = random;
        if (collided) {
            try explode(world, slots, projections, entity, now);
            continue;
        }
        if (beep) {
            (try world.get(entity, data.Charge)).beep_ms = now;
            try @import("events.zig").sound(world, slots, projections, W.beep_sound, pose.position, slot, c.CHAN_WEAPON, now);
        }
        try publish(world, entity, projections, now);
    }
}
