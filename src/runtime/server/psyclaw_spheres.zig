// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").psyclaw;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    for (0..2) |i| {
        const random = try world.get(owner, data.Random);
        const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
        const position = v.add(pose.position, v.add(v.scale(v.basis(pose.angles).forward, 40), .{ 0, 0, 15 }));
        const small = i == 1;
        const damage = tuning.damage + random.next() * tuning.random_damage;
        const angles: v.Vec3 = .{ -std.math.atan2(aim.direction[2], @sqrt(aim.direction[0] * aim.direction[0] + aim.direction[1] * aim.direction[1])) * 180 / std.math.pi, std.math.atan2(aim.direction[1], aim.direction[0]) * 180 / std.math.pi, 0 };
        const entity = try world.create(null, .{ data.Transform{ .position = position, .angles = angles }, data.Velocity{ .linear = v.scale(aim.direction, tuning.speed) }, data.Body{ .mins = @splat(if (small) 0 else -5), .maxs = @splat(if (small) 0 else 5), .collision_mask = c.MASK_SHOT }, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .psyclaw_sphere = .{ .damage = damage, .small = small, .scale = if (small) 0.8 else 1, .color = if (small) 22 else 0, .color_direction = if (small) -8 else 0, .next_ms = now + 100 } } } });
        errdefer world.destroy(entity) catch unreachable;
        try lifecycle.bind(world, slots, projections, entity, policy.model);
        try publish(world, entity, projections, now);
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const sphere = attack.attack.psyclaw_sphere;
    const pose = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.generic1 = policy.render_tag;
    projection.state.weapon = @intFromBool(sphere.small);
    projection.state.angles2 = @splat(sphere.scale);
    projection.state.origin2 = sphere.tint();
    projection.state.time = @intCast(attack.born_ms);
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").linear(pose.angles, spin(sphere.small), now);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
fn spin(small: bool) v.Vec3 {
    return if (small) .{ 0, 220, 160 } else .{ 0, 160, 120 };
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    var sphere = attack.attack.psyclaw_sphere;
    var pose = (try world.get(entity, data.Transform)).*;
    const velocity = (try world.get(entity, data.Velocity)).linear;
    const body = (try world.get(entity, data.Body)).*;
    const owner = world.find(attack.owner);
    const skip: u16 = if (owner) |actor| (try world.get(actor, data.Binding)).slot else c.ENTITYNUM_NONE;
    // The reference writes an eight-second hook lifetime but never checks it for
    // flying spheres. Native ownership bounds that omitted cleanup explicitly.
    const expiry = attack.born_ms + 8000;
    while (attack.stepped_ms < @min(now, expiry)) {
        const at = @min(@min(now, expiry), attack.stepped_ms + 50);
        const seconds = @as(f32, @floatFromInt(at - attack.stepped_ms)) * 0.001;
        pose.angles = v.add(pose.angles, v.scale(spin(sphere.small), seconds));
        const hit = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, seconds)), .mins = body.mins, .maxs = body.maxs, .slot = skip, .mask = c.MASK_SHOT });
        pose.position = hit.end;
        attack.stepped_ms = at;
        if (hit.fraction < 1 or hit.start_solid) {
            if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
                if ((world.get(victim, data.Health) catch null) != null) {
                    var source = attack.owner;
                    var applied_warp = false;
                    if (owner != null and (world.get(victim, data.Player) catch null) != null) {
                        const ailments = try world.get(victim, data.Ailments);
                        if (ailments.warp == null or ailments.warp.?.until_ms <= at) {
                            const id = try world.persistentId(victim);
                            ailments.warp = .{ .source = attack.owner, .until_ms = at + 8000, .next_ms = at + 100, .random = (attack.owner *% 2654435761) ^ id };
                            // Contact changes the reference sphere's owner to the
                            // player before damage: retain that first-hit attribution.
                            source = id;
                            applied_warp = true;
                        }
                    }
                    _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(sphere.damage)), at, .{ .source = source, .attacker_class = "monster_psyclaw" });
                    if (!applied_warp) try @import("weapon_damage.zig").shove(world, victim, source, velocity, sphere.damage, at);
                }
            };
            return lifecycle.remove(world, slots, projections, entity);
        }
        while (sphere.next_ms <= at) {
            sphere.pulse();
            sphere.next_ms += 100;
        }
    }
    if (now >= expiry) return lifecycle.remove(world, slots, projections, entity);
    attack.attack.psyclaw_sphere = sphere;
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).* = pose;
    try publish(world, entity, projections, now);
}
