// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored stationary turret activation, six-shot chains and target admission.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").rockgat;
const prop = @import("properties.zig");
pub fn configure(object: data.MapObject, now: i64, last_frame: u16) !policy.State {
    var state: policy.State = .{ .toggle = object.flags & 1 != 0, .pose_ms = now - 1000, .next_sound_ms = now };
    state.phase = if (state.toggle) .disabled else .passive;
    const height = try prop.number(object, "frames", try prop.number(object, "height", 10));
    if (height < 0 or height > @as(f32, @floatFromInt(last_frame)) or @trunc(height) != height) return error.InvalidRockgatHeight;
    state.height = @intFromFloat(height);
    state.range = try prop.number(object, "range", state.range);
    state.damage = try prop.number(object, "basedmg", state.damage);
    state.random_damage = try prop.number(object, "rnddmg", state.random_damage);
    state.fire_ms = try prop.milliseconds(object, "fire_rate", 0.13);
    if (state.range <= 0 or state.range > 65536 or state.damage < 0 or state.damage > 1000000 or state.random_damage < 0 or state.random_damage > 1000000 or state.fire_ms < 10 or state.fire_ms > 3600000) return error.InvalidRockgatTuning;
    state.sound = prop.text(object, "sound") orelse state.sound;
    state.up_sound = prop.text(object, "sound_up") orelse state.up_sound;
    state.down_sound = prop.text(object, "sound_down") orelse state.down_sound;
    state.hit_sound = prop.text(object, "hit_sound") orelse state.hit_sound;
    return state;
}
fn player(world: *data.World, entity: ecs.Entity) bool {
    const state = world.get(entity, data.Player) catch return false;
    return state.mode == .normal and (world.get(entity, data.Health) catch return false).current > 0;
}
fn target(world: *data.World, slots: *Slots, actor: *data.Actor, pose: data.Transform) !?ecs.Entity {
    if (world.find(actor.threat)) |enemy| if (player(world, enemy) and v.length(v.subtract((try world.get(enemy, data.Transform)).position, pose.position)) <= actor.rockgat.range) return enemy;
    actor.threat = 0;
    // The reference enumerates clients in slot order, despite its nearest-client comment.
    for (slots.occupants[0..Slots.clients]) |occupant| if (occupant) |enemy| {
        if (!player(world, enemy) or v.length(v.subtract((try world.get(enemy, data.Transform)).position, pose.position)) >= actor.rockgat.range) continue;
        actor.threat = try world.persistentId(enemy);
        return enemy;
    };
    return null;
}
fn shot(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, enemy: ecs.Entity, pose: data.Transform, state: *policy.State, now: i64) !void {
    const contact = try @import("actor_bullets.zig").fire(world, slots, projections, entity, enemy, pose, .{ .range = state.range, .damage = state.damage, .random_damage = state.random_damage }, now);
    state.shots +%= 1;
    var text: [128]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 rockgat: id={d} shot={d} contact={d}\n", .{ try world.persistentId(entity), state.shots, contact }));
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, now: i64) !void {
    const state = &actor.rockgat;
    // Each chain has its own scheduled callback. A late frame runs one callback,
    // then schedules the next; it does not collapse all five shots into one tick.
    for (&state.bursts) |*entry| if (entry.*) |*burst| {
        const enemy = world.find(actor.threat);
        if (enemy == null or !player(world, enemy.?)) {
            entry.* = null;
            continue;
        }
        if (now < burst.next_ms) continue;
        try shot(world, slots, projections, entity, enemy.?, pose.*, state, now);
        burst.remaining -= 1;
        if (burst.remaining == 0) entry.* = null else burst.next_ms = now + 10;
    };
    if (now < actor.think_ms or state.phase == .disabled) return;
    actor.think_ms = now + 100;
    const slot = (try world.get(entity, data.Binding)).slot;
    switch (state.phase) {
        .disabled => {},
        .passive => if (try target(world, slots, actor, pose.*) != null) {
            state.phase = .raising;
        },
        .raising, .lowering => {
            const up = state.phase == .raising;
            const sound = if (up) state.up_sound else state.down_sound;
            if (sound.len != 0) try @import("events.zig").sound(world, slots, projections, sound, pose.position, slot, c.CHAN_AUTO, now);
            state.raised = up;
            state.pose_ms = now;
            if (up) {
                state.next_attack_ms = now + 1000;
                state.phase = .scanning;
            } else state.phase = if (state.toggle) .disabled else .passive;
        },
        .scanning => {
            const enemy = try target(world, slots, actor, pose.*);
            var retained = false;
            if (enemy) |target_entity| {
                const target_pose = (try world.get(target_entity, data.Transform)).*;
                actor.threat_position = target_pose.position;
                const body = (try world.get(target_entity, data.Body)).*;
                const center = v.add(target_pose.position, v.scale(v.add(body.mins, body.maxs), 0.5));
                const delta = v.normalize(v.subtract(center, pose.position));
                pose.angles = .{ 0, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
                retained = now < state.next_attack_ms;
                if (!retained) {
                    const sight = try engine.collisionService().trace(.{ .start = pose.position, .end = target_pose.position, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
                    retained = !sight.start_solid and sight.fraction == 1 and policy.pitchAllowed(delta[2]);
                    if (retained) {
                        if (now > state.next_sound_ms) {
                            if (state.sound.len != 0) try @import("events.zig").sound(world, slots, projections, state.sound, pose.position, slot, c.CHAN_WEAPON, now);
                            state.next_sound_ms = now + 220;
                        }
                        try state.startBurst(now);
                        try shot(world, slots, projections, entity, target_entity, pose.*, state, now);
                        state.next_attack_ms = now + state.fire_ms + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 30));
                    }
                }
            }
            if (!retained and !state.toggle and now > state.next_sound_ms) state.phase = .lowering;
        },
    }
    actor.mode = .idle;
}
