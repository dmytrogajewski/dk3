// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").prisoners;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: Ref, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    const point = (try target.get(data.Transform)).position;
    const delta = v.subtract(point, pose.position);
    const flight = @sqrt(delta[0] * delta[0] + delta[1] * delta[1]) / tuning.speed;
    // A target can move directly above the thrower during the windup. The
    // horizontal ballistic solution is undefined there; consume this throw.
    if (flight <= 0) return;
    var velocity = v.scale(aim.direction, tuning.speed);
    velocity[2] = (point[2] - (pose.position[2] + tuning.offset[2])) / flight + 400 * flight;
    const entity = try world.create(null, .{
        data.Transform{ .position = aim.origin },                                         data.Velocity{ .linear = velocity },
        data.Body{ .mins = @splat(0), .maxs = @splat(0), .collision_mask = c.MASK_SHOT }, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .prisoner_rock = .{ .damage = tuning.damage + random.next() * tuning.random_damage } } },
    });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, policy.rock_model);
    try publish(world, entity, projections, now);
    try @import("actor_aim.zig").finishLaunch(world, pose.position, entity, now);
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.modelindex = binding.model;
    projection.state.generic1 = policy.render_tag;
    projection.state.angles2 = @splat(1);
    projection.state.frame = 0;
    projection.state.pos = @import("../engine/trajectory.zig").linear(pose.position, (try world.get(entity, data.Velocity)).linear, now);
    projection.state.apos = @import("../engine/trajectory.zig").stationary(pose.angles);
    projection.shared.currentOrigin = pose.position;
    projection.shared.currentAngles = pose.angles;
    projection.shared.mins = @splat(0);
    projection.shared.maxs = @splat(0);
    projection.shared.contents = 0;
    projection.shared.ownerNum = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    if (now <= attack.stepped_ms) return;
    var motion = @import("region_motion.zig").Cursor.init(world, attack.owner);
    const rock = attack.attack.prisoner_rock;
    var pose = (try world.get(entity, data.Transform)).*;
    var velocity = (try world.get(entity, data.Velocity)).linear;
    const skip: u16 = if (world.find(attack.owner)) |owner| (try world.get(owner, data.Binding)).slot else c.ENTITYNUM_NONE;
    const expiry = attack.born_ms + 3000;
    while (attack.stepped_ms < @min(now, expiry)) {
        const at = @min(@min(now, expiry), attack.stepped_ms + 50);
        const seconds = @as(f32, @floatFromInt(at - attack.stepped_ms)) * 0.001;
        velocity[2] -= 400 * seconds;
        const hit = try motion.trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity, seconds)), .mins = @splat(0), .maxs = @splat(0), .slot = skip, .mask = c.MASK_SHOT });
        pose.position = hit.end;
        attack.stepped_ms = at;
        velocity[2] -= 400 * seconds;
        if (hit.fraction < 1 or hit.start_solid) {
            if (@import("region_access.zig").victim(world, slots, hit)) |victim| {
                if ((victim.get(data.Health) catch null) != null) {
                    _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(rock.damage)), now, .{ .source = attack.owner });
                    try @import("weapon_damage.zig").shove(victim.world, victim.entity, attack.owner, velocity, rock.damage, now);
                }
            }
            return lifecycle.remove(world, slots, projections, entity);
        }
    }
    if (now >= expiry) return lifecycle.remove(world, slots, projections, entity);
    (try world.get(entity, data.ActorAttack)).* = attack;
    (try world.get(entity, data.Transform)).* = pose;
    (try world.get(entity, data.Velocity)).linear = velocity;
    try publish(world, entity, projections, now);
    try motion.finish(world, entity, now);
}
