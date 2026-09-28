// SPDX-License-Identifier: GPL-2.0-or-later
//! Ground pursuit, authored strikes and class-specific frog jumps.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const policy = @import("actor_catalog").froginator;
pub fn think(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: data.Body, velocity: *data.Velocity, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    if (now < actor.think_ms) return;
    actor.think_ms = now + 100;
    const slot = (try world.get(entity, data.Binding)).slot;
    const enemy = try @import("actor_perception.zig").perceive(world, slots, entity, actor, pose.*, definition, now);
    const target = enemy.enemy orelse {
        actor.mode = .idle;
        actor.frog.enter(.decide, now);
        return;
    };
    const previous = actor.frog.phase;
    if (previous == .jump) {
        if (body.grounded and now > actor.frog.started_ms) {
            actor.frog.enter(.decide, now);
            try @import("events.zig").sound(world, slots, projections, policy.landing_sound, pose.position, slot, c.CHAN_AUTO, now);
            pose.angles[0] = 0;
        }
    } else if (previous == .spit or previous == .bite) {
        const index = actor.frog.pose();
        const ground = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, -20 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (ground.fraction == 1) actor.frog.enter(.decide, now) else {
            const fps: i64 = definition.attacks[index].fps;
            const second: ?i64 = if (definition.second_strikes[index]) |frame| @divTrunc(@as(i64, frame) * 1000, fps) else null;
            const count = actor.frog.strikes(now, @divTrunc(@as(i64, definition.strikes[index]) * 1000, fps), second);
            for (0..count) |_| {
                if (previous == .spit) try @import("frog_spit.zig").launch(world, slots, projections, entity, target, pose.*, definition.frog, now) else {
                    const direction = v.normalize(v.subtract((try target.get(data.Transform)).position, pose.position));
                    const contact = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(direction, definition.range)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
                    if (@import("region_access.zig").victim(world, slots, contact)) |victim| if ((victim.get(data.Health) catch null) != null) {
                        const amount = definition.damage + (try world.get(entity, data.Random)).next() * definition.random_damage;
                        _ = try @import("weapon_damage.zig").hurt(victim.world, victim.entity, try world.persistentId(entity), 0, amount, now, false);
                        try @import("weapon_damage.zig").shove(victim.world, victim.entity, try world.persistentId(entity), direction, amount, now);
                        var text: [128]u8 = undefined;
                        engine.print(try std.fmt.bufPrintZ(&text, "dk3 frog: id={d} bite={d} damage={d:.2}\n", .{ try world.persistentId(entity), try victim.id(), amount }));
                    };
                }
            }
            try @import("actor_attack_sounds.zig").at(world, slots, projections, entity, actor, definition, @intCast(index), actor.frog.started_ms, now, 3);
            if (now >= actor.frog.started_ms + definition.attacks[index].duration()) actor.frog.enter(.decide, now);
        }
    } else {
        const feet = v.add(pose.position, .{ 0, 0, body.mins[2] + 1 });
        const dry = try @import("actor_collision.zig").service().contents(feet, slot) & c.MASK_WATER == 0;
        actor.frog.choose(now, enemy.distance, definition.range, dry, engine.integer("g_spSkill") > 2, (try world.get(entity, data.Random)).next());
        if (actor.frog.phase == .jump) {
            velocity.linear = v.scale(v.normalize(v.subtract(actor.threat_position, pose.position)), definition.speed * (enemy.distance / 425 * 2.35));
            velocity.linear[2] = definition.frog.upward;
            const lift = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, 10 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            pose.position = lift.end;
            for (policy.jump_sounds) |sound| try @import("events.zig").sound(world, slots, projections, sound, pose.position, slot, c.CHAN_AUTO, now);
        }
    }
    if (previous != actor.frog.phase) actor.changed_ms = now;
    actor.mode = switch (actor.frog.phase) {
        .chase => .chase,
        .spit, .bite, .jump => .attack,
        .decide => .idle,
    };
    if (actor.frog.phase != .jump) {
        const direction = v.subtract(actor.threat_position, pose.position);
        pose.angles[1] = std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi;
    }
}

pub fn jump(actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, slot: u16, elapsed: u32) !void {
    var remaining = elapsed;
    while (remaining > 0) {
        const milliseconds = @min(remaining, 50);
        remaining -= milliseconds;
        const seconds = @as(f32, @floatFromInt(milliseconds)) * 0.001;
        const floor = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, .{ 0, 0, -0.5 }), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        body.grounded = policy.acceptsFloor(velocity.linear[2], floor.normal[2]) and !floor.start_solid and !floor.all_solid and floor.fraction < 1;
        actor.ground_entity = if (body.grounded) floor.entity else c.ENTITYNUM_NONE;
        if (body.grounded) {
            pose.position = floor.end;
            velocity.linear = @splat(0);
            return;
        }
        velocity.linear[2] -= 800 * seconds;
        const hit = try @import("actor_collision.zig").service().trace(.{ .start = pose.position, .end = v.add(pose.position, v.scale(velocity.linear, seconds)), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
        if (hit.start_solid) {
            velocity.linear = @splat(0);
            return;
        }
        pose.position = hit.end;
        // Reference toss physics uses 1.5 plane backoff for this jump's bounce mode.
        if (hit.fraction < 1) velocity.linear = v.subtract(velocity.linear, v.scale(hit.normal, v.dot(velocity.linear, hit.normal) * 1.5));
    }
    const direction = velocity.linear;
    if (v.length(direction) > 0.1) pose.angles = .{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 };
}
