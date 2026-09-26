// SPDX-License-Identifier: GPL-2.0-or-later
//! Delayed Hammer strikes become persistent quakes after a grounded full charge.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").hammer;
const v = @import("../domain/vector.zig");
const damage = @import("weapon_damage.zig");
const area = @import("area_damage.zig");
const c = abi.c;
const entities = @import("weapon_entities.zig");
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const action = (try world.get(entity, data.Hammer)).*;
    const until = action.quake_until_ms orelse return;
    const slot = (try world.get(entity, data.Binding)).slot;
    const position = (try world.get(entity, data.Transform)).position;
    const projection = &projections[slot];
    projection.state.number = slot;
    projection.state.eType = c.ET_DK3_EFFECT;
    projection.state.weapon = W.id;
    projection.state.time = @intCast(until - 6000);
    projection.state.time2 = @intCast(until);
    projection.state.angles2[0] = action.damage;
    projection.state.pos = @import("../engine/trajectory.zig").stationary(position);
    projection.shared.currentOrigin = position;
    projection.shared.contents = 0;
    engine.link(projection);
}
pub fn launch(world: *data.World, owner: ecs.Entity, shot: @import("../domain/weapons.zig").Fired, table: *const @import("../domain/weapons.zig").Table, now: i64) !void {
    const owner_id = try world.persistentId(owner);
    const tuning = table.entries[W.id];
    _ = try world.create(null, .{ data.Transform{ .position = shot.position }, data.Hammer{ .owner = owner_id, .damage = tuning.damage, .range = if (tuning.range > 0) tuning.range else 128, .charge_ms = std.math.clamp(shot.charge, 0, 1800), .next_ms = now + W.strikeDelay(shot.charge) }, data.Random{ .state = owner_id ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) } });
}
fn airborne(world: *data.World, entity: ecs.Entity, impulse: v.Vec3) !void {
    (try world.get(entity, data.Velocity)).linear = v.add((try world.get(entity, data.Velocity)).linear, impulse);
    (try world.get(entity, data.Body)).grounded = false;
    if (world.get(entity, data.Player) catch null) |player| player.ground_entity = c.ENTITYNUM_NONE;
    if (world.get(entity, data.Actor) catch null) |actor| actor.ground_entity = c.ENTITYNUM_NONE;
}
fn strike(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, action: *data.Hammer, owner: ecs.Entity, now: i64) !bool {
    const pose = (try world.get(owner, data.Transform)).*;
    const body = (try world.get(owner, data.Body)).*;
    const slot = (try world.get(owner, data.Binding)).slot;
    const axes = v.basis(pose.angles);
    const start = v.add(pose.position, v.scale(v.cross(axes.right, axes.forward), 4));
    const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(axes.forward, 50)), .mins = @splat(-1), .maxs = @splat(1), .slot = slot, .mask = c.MASK_SHOT });
    const amount = action.damage * W.chargeScale(action.charge_ms);
    if (hit.fraction < 1 and hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |target| {
        if (try damage.hurt(world, target, action.owner, W.id, amount, now, false)) try damage.shove(world, target, action.owner, axes.forward, amount, now);
    };
    const quake = action.charge_ms >= 1800 and body.grounded;
    try area.apply(world, slots, .{ .owner = action.owner, .weapon = W.id, .origin = pose.position, .damage = if (quake) action.damage else amount, .radius = action.range, .skip_slot = slot, .self_scale = 0, .diminishing = !quake, .occlusion = quake }, now);
    try @import("events.zig").sound(world, slots, projections, W.spec.audio.fire.?, pose.position, slot, c.CHAN_WEAPON, now);
    const ground = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, -100 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
    try @import("impacts.zig").contact(world, slots, projections, W.id, if (quake) ground else hit, .{ .charged = quake, .detonation = true }, now);
    if (quake) {
        _ = try damage.hurt(world, owner, action.owner, W.id, 20, now, false);
        try airborne(world, owner, .{ 0, 0, 450 });
        (try world.get(entity, data.Transform)).position = pose.position;
        action.quake_until_ms = now + 6000;
        action.next_ms = now;
        try entities.bind(world, slots, projections, entity, "");
    }
    if (engine.integer("developer") > 0) {
        var message: [144]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&message, "dk3 zig hammer: strike charge={d} damage={d:.1} quake={d}\n", .{ action.charge_ms, amount, @intFromBool(quake) }));
    }
    return quake;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    var pending: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.Hammer}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            pending[count] = entity;
            count += 1;
        };
    }
    for (pending[0..count]) |entity| {
        var action = (try world.get(entity, data.Hammer)).*;
        if (action.quake_until_ms == null) {
            const owner = world.find(action.owner) orelse {
                try world.destroy(entity);
                continue;
            };
            if ((try world.get(owner, data.Health)).current <= 0 or (try world.get(owner, data.Weapons)).weapon != W.id) {
                try world.destroy(entity);
                continue;
            }
            if (now < action.next_ms) continue;
            if (!try strike(world, slots, projections, entity, &action, owner, now)) {
                try world.destroy(entity);
                continue;
            }
        }
        const until = action.quake_until_ms.?;
        if (now >= until) {
            try entities.remove(world, slots, projections, entity);
            continue;
        }
        if (now >= action.next_ms) {
            const position = (try world.get(entity, data.Transform)).position;
            var random = (try world.get(entity, data.Random)).*;
            for (slots.occupants) |occupant| {
                const target = occupant orelse continue;
                const actor = world.get(target, data.Actor) catch null;
                if (actor == null and (world.get(target, data.Player) catch null) == null) continue;
                if ((try world.get(target, data.Health)).current <= 0 or !(try world.get(target, data.Body)).grounded) continue;
                const strength = W.quakeStrength(v.length(v.subtract((try world.get(target, data.Transform)).position, position)), until - now, action.damage, actor != null);
                if (strength <= 0) continue;
                var impulse: v.Vec3 = undefined;
                for (&impulse) |*axis| axis.* = (random.next() - 0.5) * strength * 1.25;
                try airborne(world, target, impulse);
            }
            (try world.get(entity, data.Random)).* = random;
            action.next_ms = now + 100;
        }
        (try world.get(entity, data.Hammer)).* = action;
        try publish(world, entity, projections);
    }
}
