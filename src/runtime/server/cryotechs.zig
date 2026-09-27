// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
const policy = @import("actor_catalog").cryotech;

pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const hurt = (try world.get(entity, data.Hurt)).*;
    const injured = hurt.revision != actor.receipt;
    const perceived = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    if (actor.reaction_until_ms) |until| {
        if (now < until) {
            actor.mode = .idle;
            return;
        }
        actor.reaction = null;
        actor.reaction_until_ms = null;
    }
    if (injured and hurt.amount >= 35 and (try world.get(entity, data.Random)).next() < 0.25) if (definition.pain[0]) |sequence| {
        actor.reaction = sequence;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + sequence.duration();
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const target = perceived.enemy orelse {
        actor.melee.active = false;
        actor.mode = .idle;
        return;
    };
    const delta = v.subtract(actor.threat_position, pose.position);
    const yaw = std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi;
    if (now >= actor.think_ms) {
        pose.angles[1] += std.math.clamp(@mod(yaw - pose.angles[1] + 180, 360) - 180, -definition.yaw_speed, definition.yaw_speed);
        actor.think_ms = now + 100;
    }
    const facing = @abs(@mod(yaw - pose.angles[1] + 180, 360) - 180) <= 5;
    const clear = perceived.visible and perceived.distance <= definition.attack_range;
    if (actor.melee.active) {
        try emit(world, slots, projections, entity, actor, pose.*, definition, target, now);
        if (now - actor.melee.started_ms >= definition.attacks[0].duration()) actor.melee.active = false;
    }
    if (!actor.melee.active and clear and facing and now >= actor.cryotech.ready_ms) {
        actor.melee.begin(0, now);
        actor.cryotech.begin(now);
        actor.changed_ms = now;
    }
    actor.mode = if (actor.melee.active) .attack else if (clear) .idle else .chase;
    if (actor.melee.active) try emit(world, slots, projections, entity, actor, pose.*, definition, target, now);
}
fn emit(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, target: ecs.Entity, now: i64) !void {
    const sequence = definition.attacks[0];
    while (actor.cryotech.next(now - actor.melee.started_ms, sequence.fps)) |event| try @import("cryo_spray.zig").launch(world, slots, projections, entity, target, pose, event.offset, definition, now);
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
}
pub fn ambient(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: Definition, now: i64) !void {
    const sequence = actor.scripted_pose orelse return;
    const index: usize = if (sequence.first == definition.attacks[0].first) 0 else if (sequence.first == definition.attacks[1].first) 1 else return;
    const state = &actor.cryotech;
    if (state.ambient_started != actor.scripted_ms or state.ambient_frame != sequence.first) {
        state.ambient_started = actor.scripted_ms;
        state.ambient_frame = sequence.first;
        state.ambient_elapsed = -1;
    }
    const elapsed = @max(0, now - actor.scripted_ms);
    const events: []const policy.Event = if (index == 0) &policy.pulses else &policy.maintenance;
    const duration = sequence.duration();
    var loop = @divTrunc(@max(0, state.ambient_elapsed), duration);
    while (loop <= @divTrunc(elapsed, duration)) : (loop += 1) for (events) |event| {
        const at = loop * duration + @divTrunc(@as(i64, event.frame) * 1000, sequence.fps);
        if (at > state.ambient_elapsed and at <= elapsed) try @import("cryo_spray.zig").launch(world, slots, projections, entity, null, pose, event.offset, definition, now);
    };
    state.ambient_elapsed = elapsed;
}
