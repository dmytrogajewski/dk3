// SPDX-License-Identifier: GPL-2.0-or-later
//! Hostile perception and attack adapter. The class owns its combat cycle.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actors.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
fn alivePlayer(world: *data.World, entity: ecs.Entity) bool {
    const player = world.get(entity, data.Player) catch return false;
    if (player.mode == .dead or player.mode == .noclip or player.mode == .spectator) return false;
    return if (world.get(entity, data.Health)) |health| health.current > 0 else |_| false;
}
fn trace(start: v.Vec3, end: v.Vec3, slot: u16, mask: u32) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = mask });
}
pub fn guard(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: rules.Definition, now: i64) !void {
    const owner_id = try world.persistentId(entity);
    const slot = (try world.get(entity, data.Binding)).slot;
    const eye = v.add(pose.position, .{ 0, 0, 24 });
    const receipt = (try world.get(entity, data.Hurt)).*;
    if (receipt.revision != actor.receipt) {
        actor.receipt = receipt.revision;
        if (world.find(receipt.source)) |attacker| if (alivePlayer(world, attacker)) {
            actor.threat = receipt.source;
            actor.threat_position = (try world.get(attacker, data.Transform)).position;
            actor.threat_seen_ms = now;
        };
    }
    if (world.find(actor.threat)) |enemy| {
        if (!alivePlayer(world, enemy)) actor.threat = 0;
    } else actor.threat = 0;
    if (actor.threat == 0) {
        var nearest = definition.sight_range;
        for (slots.occupants) |occupant| {
            const candidate = occupant orelse continue;
            if (!alivePlayer(world, candidate)) continue;
            if (world.get(candidate, data.Character)) |character| {
                if (character.invisible_until > now) continue;
            } else |_| {}
            const position = (try world.get(candidate, data.Transform)).position;
            const delta = v.add(position, v.scale(pose.position, -1));
            const distance = v.length(delta);
            if (distance > nearest) continue;
            const direction = v.normalize(.{ delta[0], delta[1], 0 });
            if (v.dot(direction, v.basis(pose.angles).forward) < @cos(definition.fov * std.math.pi / 360.0)) continue;
            const target_slot = (try world.get(candidate, data.Binding)).slot;
            const sight = try trace(eye, v.add(position, .{ 0, 0, 16 }), slot, c.MASK_SOLID);
            if (sight.fraction < 1 and sight.entity != target_slot) continue;
            actor.threat = try world.persistentId(candidate);
            actor.threat_position = position;
            actor.threat_seen_ms = now;
            nearest = distance;
        }
    }
    var clear = false;
    var start = eye;
    var aim = eye;
    if (world.find(actor.threat)) |enemy| {
        const target = (try world.get(enemy, data.Transform)).position;
        const delta = v.add(target, v.scale(pose.position, -1));
        const target_slot = (try world.get(enemy, data.Binding)).slot;
        const sight = try trace(eye, v.add(target, .{ 0, 0, 16 }), slot, c.MASK_SOLID);
        if (sight.fraction == 1 or sight.entity == target_slot) {
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
        const visible = hit.fraction == 1 or hit.entity == target_slot;
        if (visible) {
            actor.threat_position = target;
            actor.threat_seen_ms = now;
        } else if (now - actor.threat_seen_ms >= 10000) actor.threat = 0;
        clear = visible and v.length(delta) <= definition.range;
    }
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
        if (hit.entity < slots.occupants.len) if (slots.occupants[hit.entity]) |victim| {
            const amount = definition.damage + actor.guard.fraction() * definition.random_damage;
            _ = try @import("damage.zig").apply(world, victim, @intFromFloat(@ceil(amount)), now, .{ .source = owner_id });
        };
        const sound = definition.attack_sounds[actor.guard.pose];
        if (sound.len != 0) try @import("events.zig").sound(world, slots, projections, sound, start, slot, c.CHAN_WEAPON, now);
        if (engine.integer("developer") != 0) {
            var buffer: [160]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 zig guard: id={d} fired rounds={d} enemy={d}\n", .{ owner_id, actor.guard.rounds, actor.threat }));
        }
    }
    if (event.reload_sound) {
        try @import("events.zig").sound(world, slots, projections, @import("actor_catalog").mishima.reload_sound, pose.position, slot, c.CHAN_AUTO, now);
        var buffer: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&buffer, "dk3 zig guard: id={d} reload sound dispatched\n", .{owner_id}));
    }
}
