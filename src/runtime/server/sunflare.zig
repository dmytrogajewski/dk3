// SPDX-License-Identifier: GPL-2.0-or-later
//! Thrown pots become persistent timed flame fields; damage follows the moving source.
const std = @import("std");
const data = @import("../domain/components.zig");
const access = @import("region_access.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const ecs = @import("../ecs/world.zig");
const Slots = @import("../engine/slots.zig").Slots;
const W = @import("weapon_catalog").sunflare;
const v = @import("../domain/vector.zig");
const c = abi.c;
const remove = @import("weapon_entities.zig").remove;
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const projectile = (try world.get(entity, data.Projectile)).*;
    const flame = projectile.flight.sunflare;
    try @import("weapon_entities.zig").effect(world, entity, projections, .{ .weapon = W.id, .owner = projectile.owner, .phase = @intFromEnum(flame.phase), .strength = @floatFromInt(flame.flames), .endpoint = .{ @floatFromInt(@intFromBool(flame.floating)), 0, 0 }, .born_ms = projectile.born_ms + flame.burn_ms, .end_ms = projectile.born_ms + flame.burn_ms + 10000 });
}
fn burn(world: *data.World, slots: *Slots, projectile: data.Projectile, position: v.Vec3, now: i64) !void {
    const flame = projectile.flight.sunflare;
    var candidates = access.Damageables.init(world, slots);
    while (candidates.next()) |target| {
        const health = try target.get(data.Health);
        if (health.current <= 0) continue;
        const center = try @import("area_damage.zig").center(target.world, target.entity);
        if (v.length(v.subtract(center, position)) > flame.radius()) continue;
        _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, projectile.owner, W.id, flame.damage(projectile.damage), now, false);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        var projectile = (world.get(entity, data.Projectile) catch continue).*;
        if (projectile.flight != .sunflare or now <= projectile.stepped_ms) continue;
        var motion = @import("region_motion.zig").Cursor.init(world, projectile.owner);
        if (now >= (try world.get(entity, data.Lifetime)).expires_ms) {
            try remove(world, slots, projections, entity);
            continue;
        }
        const slot = (try world.get(entity, data.Binding)).slot;
        const owner_slot: u16 = if (world.find(projectile.owner)) |owner| slots.find(owner) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
        var pose = (try world.get(entity, data.Transform)).*;
        var velocity = (try world.get(entity, data.Velocity)).linear;
        var at = projectile.stepped_ms;
        while (at < now) {
            const milliseconds: u32 = @intCast(@min(20, now - at));
            const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
            var flame = projectile.flight.sunflare;
            const age = at - projectile.born_ms;
            projectile.wet = (try motion.contents(pose.position)) & c.MASK_WATER != 0;
            if (flame.phase == .flight) {
                pose.angles = v.add(pose.angles, v.scale(flame.angular_velocity, seconds));
                const goal = v.add(v.add(pose.position, v.scale(velocity, seconds)), .{ 0, 0, -400 * seconds * seconds });
                velocity[2] -= 800 * seconds;
                const hit = try motion.trace(.{ .start = pose.position, .end = goal, .mins = W.spec.projectile.mins, .maxs = W.spec.projectile.maxs, .slot = owner_slot, .mask = c.MASK_SHOT });
                pose.position = hit.end;
                if (hit.sky or hit.no_impact) {
                    try remove(world, slots, projections, entity);
                    break;
                }
                if (hit.fraction < 1 or projectile.wet) {
                    if (hit.fraction < 1) {
                        pose.position = v.add(pose.position, v.scale(hit.normal, 4));
                        if (access.victim(world, slots, hit)) |target| {
                            _ = try @import("weapon_damage.zig").hurt(target.world, target.entity, projectile.owner, W.id, projectile.damage * 5, now, false);
                        }
                        try @import("impacts.zig").contact(world, slots, projections, W.id, hit, .{ .detonation = true }, now);
                    } else try @import("events.zig").impactOwned(world, slots, projections, motion.owner, .{ .weapon = W.id, .kind = .water, .normal = .{ 0, 0, 1 }, .detonation = true }, pose.position, now);
                    flame.ignite(age);
                    velocity = @splat(0);
                    if (engine.integer("developer") > 0) engine.print("dk3 zig sunflare: ignited\n");
                }
            } else {
                if (age >= flame.next_ms) {
                    switch (flame.phase) {
                        .settling => {
                            try burn(world, slots, projectile, pose.position, now);
                            var random = (try world.get(entity, data.Random)).*;
                            flame.burn(age, random.next());
                            flame.floating = projectile.wet;
                            (try world.get(entity, data.Random)).* = random;
                            (try world.get(entity, data.Lifetime)).expires_ms = projectile.born_ms + flame.burn_ms + 10000;
                            try @import("events.zig").soundOwned(world, slots, projections, motion.owner, W.visual.burn_sound, pose.position, c.ENTITYNUM_NONE, c.CHAN_BODY, now);
                            if (engine.integer("developer") > 0) engine.print("dk3 zig sunflare: burning\n");
                        },
                        .burning => {
                            if (age >= flame.burn_ms + 5000) {
                                flame.phase = .cooling;
                                flame.next_ms = flame.burn_ms + 10000;
                            } else {
                                try burn(world, slots, projectile, pose.position, now);
                                flame.next_ms = age + 300;
                            }
                        },
                        .cooling => {},
                        .flight => unreachable,
                    }
                }
                if (flame.phase != .settling) {
                    var goal: v.Vec3 = undefined;
                    if (flame.floating) {
                        const water = try @import("region_collision.zig").from(motion.owner, .{ .start = v.add(pose.position, .{ 0, 0, 18 }), .end = v.add(pose.position, .{ 0, 0, -4.5 }), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_WATER }, motion.skip);
                        const submerged: f32 = if (water.all_solid and water.start_solid) 1 else 1 - water.fraction;
                        const density: f32 = if (water.contents & c.CONTENTS_LAVA != 0) 2 else if (water.contents & c.CONTENTS_SLIME != 0) 1.2 else 1;
                        velocity = W.buoyancy(velocity, submerged, density, seconds);
                        goal = v.add(pose.position, v.scale(velocity, seconds));
                    } else {
                        goal = v.add(v.add(pose.position, v.scale(velocity, seconds)), .{ 0, 0, -400 * seconds * seconds });
                        velocity[2] -= 800 * seconds;
                    }
                    const hit = try motion.trace(.{ .start = pose.position, .end = goal, .mins = .{ 0, 0, -18 }, .maxs = .{ 0, 0, 18 }, .slot = slot, .mask = c.MASK_SOLID });
                    pose.position = hit.end;
                    if (hit.fraction < 1) {
                        velocity = @import("../domain/combat.zig").reflect(velocity, hit.normal, 0.75);
                        if (hit.normal[2] > 0.7 and @abs(velocity[2]) < 30) velocity = @splat(0);
                        pose.position = v.add(pose.position, v.scale(hit.normal, 0.1));
                    }
                }
            }
            projectile.flight.sunflare = flame;
            at += milliseconds;
        }
        if (!world.alive(entity)) continue;
        projectile.stepped_ms = now;
        (try world.get(entity, data.Projectile)).* = projectile;
        (try world.get(entity, data.Transform)).* = pose;
        (try world.get(entity, data.Velocity)).linear = velocity;
        try @import("projectiles.zig").publish(world, entity, projections, now);
        try motion.finish(world, entity, now);
    }
}
