// SPDX-License-Identifier: GPL-2.0-or-later
//! Hostile perception and attack adapter. The class owns its combat cycle.
const std = @import("std");
const data = @import("../domain/components.zig");
const access = @import("region_access.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actors.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
fn alivePlayer(entity: Ref) bool {
    if (entity.get(data.Player) catch null) |player| {
        if (player.mode != .normal) return false;
    } else if ((entity.get(data.Companion) catch null) == null) return false;
    return if (entity.get(data.Health)) |health| health.current > 0 else |_| false;
}
fn trace(start: v.Vec3, end: v.Vec3, slot: u16, mask: u32) !@import("../domain/collision.zig").Trace {
    return @import("region_collision.zig").trace(.{ .start = start, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = mask });
}
pub fn guard(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: rules.Definition, now: i64) !void {
    const owner_id = try world.persistentId(entity);
    const slot = (try world.get(entity, data.Binding)).slot;
    const eye = v.add(pose.position, .{ 0, 0, 24 });
    const receipt = (try world.get(entity, data.Hurt)).*;
    if (receipt.revision != actor.receipt) {
        actor.receipt = receipt.revision;
        if (access.find(world, receipt.source)) |attacker| if (alivePlayer(attacker)) {
            actor.threat = receipt.source;
            actor.threat_position = (try attacker.get(data.Transform)).position;
            actor.threat_seen_ms = now;
        };
    }
    if (access.find(world, actor.threat)) |enemy| {
        if (!alivePlayer(enemy)) actor.threat = 0;
    } else actor.threat = 0;
    if (actor.threat == 0) {
        var nearest = definition.sight_range;
        var candidates = access.Damageables.init(world, slots);
        while (candidates.next()) |candidate| {
            if (!alivePlayer(candidate)) continue;
            if (candidate.get(data.Character)) |character| {
                if (character.invisible_until > now) continue;
            } else |_| {}
            const position = (try candidate.get(data.Transform)).position;
            const delta = v.add(position, v.scale(pose.position, -1));
            const distance = v.length(delta);
            if (distance > nearest) continue;
            const direction = v.normalize(.{ delta[0], delta[1], 0 });
            if (v.dot(direction, v.basis(pose.angles).forward) < @cos(definition.fov * std.math.pi / 360.0)) continue;
            const sight = try trace(eye, v.add(position, .{ 0, 0, 16 }), slot, c.MASK_SOLID);
            if (!@import("region_collision.zig").reaches(world, sight, candidate)) continue;
            actor.threat = try candidate.id();
            actor.threat_position = position;
            actor.threat_seen_ms = now;
            nearest = distance;
        }
    }
    var clear = false;
    var start = eye;
    var aim = eye;
    if (access.find(world, actor.threat)) |enemy| {
        const target = (try enemy.get(data.Transform)).position;
        const delta = v.add(target, v.scale(pose.position, -1));
        const sight = try trace(eye, v.add(target, .{ 0, 0, 16 }), slot, c.MASK_SOLID);
        if (@import("region_collision.zig").reaches(world, sight, enemy)) {
            actor.threat_position = target;
            actor.threat_seen_ms = now;
        }
        const remembered = v.subtract(actor.threat_position, pose.position);
        pose.angles[1] = std.math.atan2(remembered[1], remembered[0]) * (180.0 / std.math.pi);
        const axes = v.basis(pose.angles);
        start = v.add(pose.position, v.add(v.scale(axes.right, definition.offset[0]), v.add(v.scale(axes.forward, definition.offset[1]), .{ 0, 0, definition.offset[2] })));
        start = (try trace(eye, start, slot, c.MASK_SHOT)).end;
        aim = v.add(target, .{ 0, 0, 8 });
        const hit = try trace(start, aim, slot, c.MASK_SHOT);
        const visible = @import("region_collision.zig").reaches(world, hit, enemy);
        if (visible) {
            actor.threat_position = target;
            actor.threat_seen_ms = now;
        } else if (now - actor.threat_seen_ms >= 10000) actor.threat = 0;
        clear = visible and v.length(delta) <= definition.range;
    }
    // Consume the outgoing pose before tick can complete it. Its last frame can
    // be crossed on the same update that returns the guard to ready.
    if (actor.guard.phase == .firing) try @import("actor_attack_sounds.zig").at(world, slots, projections, entity, actor, definition, @intCast(actor.guard.pose), actor.guard.started_ms, now, 3);
    const event = actor.guard.tick(now, clear, definition.guardTiming());
    const mode: rules.Mode = switch (actor.guard.phase) {
        .firing => .attack,
        .reloading => .reload,
        .ready, .recovering => if (actor.threat != 0 and !clear and @import("../domain/navigation.zig").horizontalDistance(pose.position, actor.threat_position) > 20) .chase else .idle,
    };
    if (mode != actor.mode) actor.changed_ms = now;
    actor.mode = mode;
    if (event.fire) {
        const axes = v.basis(pose.angles);
        var target = v.add(aim, v.scale(axes.right, (actor.guard.fraction() * 2 - 1) * definition.spread[0]));
        target[2] += (actor.guard.fraction() * 2 - 1) * definition.spread[1];
        const direction = v.normalize(v.add(target, v.scale(start, -1)));
        const hit = try trace(start, v.add(start, v.scale(direction, definition.range)), slot, c.MASK_SHOT);
        // Reference ai_fire_bullet: a round that meets a body hurts it only
        // past the skill's chance (half the time on the easiest skill).
        const admitted = @import("actor_catalog").rockgat.damageAdmitted(@intCast(std.math.clamp(engine.integer("g_spSkill"), 1, 5)), actor.guard.fraction());
        if (access.victim(world, slots, hit)) |victim| if (admitted) {
            const amount = definition.damage + actor.guard.fraction() * definition.random_damage;
            _ = try @import("damage.zig").apply(victim.world, victim.entity, @intFromFloat(@ceil(amount)), now, .{ .source = owner_id });
        };

        if (engine.integer("developer") != 0) {
            var buffer: [160]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 zig guard: id={d} fired rounds={d} enemy={d}\n", .{ owner_id, actor.guard.rounds, actor.threat }));
        }
    }
    if (actor.guard.phase == .firing) try @import("actor_attack_sounds.zig").at(world, slots, projections, entity, actor, definition, @intCast(actor.guard.pose), actor.guard.started_ms, now, 3);
    if (event.reload_sound) {
        try @import("events.zig").sound(world, slots, projections, @import("actor_catalog").mishima.reload_sound, pose.position, slot, c.CHAN_AUTO, now);
        var buffer: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 zig guard: id={d} reload sound dispatched\n", .{owner_id}));
    }
}
