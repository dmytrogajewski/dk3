// SPDX-License-Identifier: GPL-2.0-or-later
//! Heavy flier's pursuit, elevation checks, four-shot burst and hover pause.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
pub fn fly(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, now: i64, elapsed: u32) !void {
    const definition = actors.table.definitions[actor.definition];
    const slot = (try world.get(entity, data.Binding)).slot;
    if (now >= actor.think_ms) {
        actor.think_ms = now + 100;
        const enemy = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
        const previous = actor.thunder.phase;
        const hover_rise = velocity.linear[2];
        velocity.linear = @splat(0);
        if (enemy.enemy) |target| {
            const target_position = (try world.get(target, data.Transform)).position;
            const delta = v.subtract(target_position, pose.position);
            pose.angles = .{ 0, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
            switch (actor.thunder.phase) {
                .chase => {
                    if (!enemy.visible or @abs(delta[2]) < 96) {
                        actor.thunder.enter(.hover, now);
                    } else if (enemy.distance < definition.attack_range) actor.thunder.enter(.attack, now) else if (try actors.air_routes.next(pose.position, v.add(target_position, .{ 0, 0, 96 }), body, slot)) |point| {
                        const offset = v.subtract(point, pose.position);
                        velocity.linear = v.scale(v.normalize(offset), @min(definition.speed, v.length(offset) * 10));
                    }
                },
                .attack => {
                    const start = actor.thunder.next_shot;
                    const shots = actor.thunder.shots(now, definition.attacks[0].first, definition.attacks[0].fps);
                    for (0..shots) |index| try @import("thunder_spray.zig").launch(world, slots, projections, entity, target, pose.*, start + index >= 2, definition.offset, now);
                    try @import("actor_attack_sounds.zig").at(world, slots, projections, entity, actor, definition, 0, actor.thunder.started_ms, now, 3);
                    if (now >= actor.thunder.started_ms + definition.attacks[0].duration()) {
                        actor.thunder.enter(.hover, now);
                    }
                },
                .hover => {
                    velocity.linear[2] = hover_rise;
                    // The reference hover task's two-second finish deadline precedes
                    // its local 2.75-second deadline; task scheduling owns completion.
                    if (now > actor.thunder.started_ms + 2000) actor.thunder.enter(.chase, now);
                },
            }
            if (actor.thunder.phase == .hover and (previous != .hover or enemy.distance < 128)) {
                const ceiling = try engine.collisionService().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, 1024 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = c.MASK_SOLID });
                if (ceiling.end[2] - pose.position[2] > 128) velocity.linear[2] = 64;
            }
        } else actor.thunder.enter(.chase, now);
        if (previous != actor.thunder.phase) actor.changed_ms = now;
        actor.mode = if (actor.thunder.phase == .attack) .attack else if (v.length(velocity.linear) > 0) .chase else .idle;
    }
    try @import("actor_flight.zig").move(pose, body, velocity, slot, elapsed);
    actor.ground_entity = c.ENTITYNUM_NONE;
}
