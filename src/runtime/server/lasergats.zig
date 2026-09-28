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
const policy = @import("actor_catalog").lasergat;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: Definition, now: i64) !void {
    const perceived = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    const target = perceived.enemy orelse {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    };
    if (!perceived.visible or perceived.distance >= definition.attack_range) {
        actor.mode = .idle;
        actor.melee.active = false;
        return;
    }
    const delta = v.subtract((try target.get(data.Transform)).position, pose.position);
    const desired: [2]f32 = .{ std.math.clamp(-std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, -60, 60), std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi };
    const tick = now >= actor.think_ms;
    if (tick) {
        actor.think_ms = now + 100;
        pose.angles[0] += std.math.clamp(@mod(desired[0] - pose.angles[0] + 180, 360) - 180, -definition.pitch_speed, definition.pitch_speed);
        pose.angles[1] += std.math.clamp(@mod(desired[1] - pose.angles[1] + 180, 360) - 180, -policy.turn_degrees, policy.turn_degrees);
    }
    actor.lasergat.turning = @abs(@mod(desired[1] - pose.angles[1] + 180, 360) - 180) > 1 or @abs(@mod(desired[0] - pose.angles[0] + 180, 360) - 180) > 2;
    if (actor.lasergat.turning) {
        actor.melee.active = false;
        actor.mode = .idle;
        if (now >= actor.lasergat.servo_ms) {
            actor.lasergat.servo_ms = now + 400;
            try @import("events.zig").sound(world, slots, projections, policy.servo_sound, pose.position, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now);
        }
        return;
    }
    if (!actor.melee.active) actor.melee.begin(0, now);
    actor.mode = .attack;
    const sequence = definition.attacks[0];
    const strikes = [_]?u16{ definition.strikes[0], definition.second_strikes[0] };
    for (strikes, 0..) |frame, i| if (frame) |at| {
        if (actor.melee.event(@as(u2, 1) << @intCast(i), @divTrunc(@as(i64, at) * 1000, sequence.fps), now, false)) {
            try @import("actor_lasers.zig").launch(world, slots, projections, entity, target, pose.*, definition.laser, true, now);
        }
    };
    try @import("actor_attack_sounds.zig").emit(world, slots, projections, entity, actor, pose.position, definition, now);
    if (now - actor.melee.started_ms >= sequence.duration()) actor.melee.active = false;
}
