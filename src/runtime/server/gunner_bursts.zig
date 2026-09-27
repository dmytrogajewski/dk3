// SPDX-License-Identifier: GPL-2.0-or-later
//! Persistent gunfire callbacks; cadence follows the reference server tick.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").gunners;
const lifecycle = @import("weapon_entities.zig");
pub fn launch(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, kind: policy.BurstKind, two_hands: bool, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    if (kind == .shotgun) try shotgun(world, slots, owner, target, pose, tuning, now);
    // The reference's temporary chaingun entity shoots once before its think
    // callbacks. Use the owner's muzzle; its unplaced temporary origin is not a
    // valid firing location in maps whose world origin is outside playable space.
    if (kind == .commando or kind == .chaingang) _ = try @import("actor_bullets.zig").fire(world, slots, projections, owner, target, pose, tuning, now);
    const entity = try world.create(null, .{ pose, data.Velocity{}, data.Body{ .mins = @splat(0), .maxs = @splat(0) }, data.ActorAttack{ .owner = try world.persistentId(owner), .born_ms = now, .stepped_ms = now, .attack = .{ .gunner_burst = .{ .kind = kind, .tuning = tuning, .two_hands = two_hands, .next_ms = now + (if (kind == .shotgun) @as(i64, 200) else policy.burst_tick_ms) } } } });
    errdefer world.destroy(entity) catch unreachable;
    try lifecycle.bind(world, slots, projections, entity, "");
    try publish(world, entity, projections, now);
}
fn shotgun(world: *data.World, slots: *Slots, owner: ecs.Entity, target: ecs.Entity, pose: data.Transform, tuning: @import("actor_catalog").weapon.Tuning, now: i64) !void {
    const random = try world.get(owner, data.Random);
    const aim = try @import("actor_aim.zig").lead(world, target, pose, tuning.offset, random);
    const hit = try engine.collisionService().trace(.{ .start = aim.origin, .end = v.add(aim.origin, v.scale(aim.direction, tuning.range)), .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(owner, data.Binding)).slot, .mask = c.MASK_SHOT });
    if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
        if ((world.get(victim, data.Health) catch null) == null) return;
        const distance = v.length(v.subtract((try world.get(target, data.Transform)).position, pose.position));
        const damage = policy.shotgunDamage(tuning.damage, tuning.random_damage, random.next(), distance, tuning.range);
        if (damage <= 0) return;
        const source = try world.persistentId(owner);
        _ = try @import("weapon_damage.zig").hurt(world, victim, source, 0, damage, now, false);
        try @import("weapon_damage.zig").shove(world, victim, source, aim.direction, damage, now);
    };
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    _ = now;
    const attack = (try world.get(entity, data.ActorAttack)).*;
    const burst = attack.attack.gunner_burst;
    const owner = world.find(attack.owner) orelse return;
    const pose = (try world.get(owner, data.Transform)).*;
    const binding = (try world.get(entity, data.Binding)).*;
    const projection = &projections[binding.slot];
    projection.state.number = binding.slot;
    projection.state.eType = c.ET_GENERAL;
    projection.state.generic1 = policy.render_tag;
    projection.state.weapon = @intFromEnum(burst.kind);
    projection.state.otherEntityNum = (try world.get(owner, data.Binding)).slot;
    projection.state.frame = @intFromBool(burst.two_hands);
    projection.state.time = @intCast(attack.born_ms);
    projection.state.time2 = @intCast(burst.shots);
    projection.state.pos = @import("../engine/trajectory.zig").stationary(pose.position);
    projection.shared.currentOrigin = pose.position;
    projection.shared.ownerNum = projection.state.otherEntityNum;
    projection.shared.contents = 0;
    engine.link(projection);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    var attack = (try world.get(entity, data.ActorAttack)).*;
    var burst = attack.attack.gunner_burst;
    const owner = world.find(attack.owner) orelse return lifecycle.remove(world, slots, projections, entity);
    const actor = (world.get(owner, data.Actor) catch return lifecycle.remove(world, slots, projections, entity)).*;
    const target = world.find(actor.threat) orelse return lifecycle.remove(world, slots, projections, entity);
    while (burst.next_ms <= now) {
        if (burst.kind == .shotgun) return lifecycle.remove(world, slots, projections, entity);
        _ = try @import("actor_bullets.zig").fire(world, slots, projections, owner, target, (try world.get(owner, data.Transform)).*, burst.tuning, burst.next_ms);
        attack.stepped_ms = burst.next_ms;
        burst.next_ms += policy.burst_tick_ms;
        burst.shots +|= 1;
        // Uzi's stop is an absolute model frame, including non-attack poses.
        const frame = projections[(try world.get(owner, data.Binding)).slot].state.frame;
        if (((burst.kind == .commando or burst.kind == .chaingang) and burst.shots == 5) or (burst.kind == .uzi and frame >= 80)) return lifecycle.remove(world, slots, projections, entity);
    }
    attack.attack.gunner_burst = burst;
    (try world.get(entity, data.ActorAttack)).* = attack;
    try publish(world, entity, projections, now);
}
