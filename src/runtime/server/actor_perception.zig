// SPDX-License-Identifier: GPL-2.0-or-later
//! Pod hatching and Slaughterskeet flight consume class policy and supplied tuning.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/actors.zig");
const v = @import("../domain/vector.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
fn sight(from: v.Vec3, to: v.Vec3, slot: u16, target: u16) !bool {
    const hit = try engine.collisionService().trace(.{ .start = from, .end = to, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_OPAQUE });
    return !hit.start_solid and !hit.all_solid and (hit.fraction == 1 or hit.entity == target);
}
fn eligible(world: *data.World, entity: ecs.Entity, now: i64) bool {
    if ((world.get(entity, data.Health) catch return false).current <= 0) return false;
    if (world.get(entity, data.Player) catch null) |player| {
        if (player.mode != .normal and !(player.mode == .frozen and @import("nharre_reaper.zig").frozen(world, entity))) return false;
    } else if ((world.get(entity, data.Companion) catch null) == null) return false;
    if (world.get(entity, data.Character) catch null) |character| if (character.invisible_until > now) return false;
    return true;
}
pub fn perceive(world: *data.World, slots: *Slots, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: rules.Definition, now: i64) !struct { enemy: ?ecs.Entity, visible: bool, distance: f32 } {
    const slot = (try world.get(entity, data.Binding)).slot;
    const hurt = (try world.get(entity, data.Hurt)).*;
    if (hurt.revision != actor.receipt) {
        actor.receipt = hurt.revision;
        if (world.find(hurt.source)) |attacker| if (eligible(world, attacker, now)) {
            actor.ignore_player = false;
            actor.threat = hurt.source;
        };
    }
    if (actor.ignore_player) {
        actor.threat = 0;
        return .{ .enemy = null, .visible = false, .distance = std.math.inf(f32) };
    }
    if (world.find(actor.threat)) |target| {
        if (!eligible(world, target, now)) actor.threat = 0;
    } else actor.threat = 0;
    try acquire(world, slots, entity, actor, pose, definition, now);
    const enemy = world.find(actor.threat) orelse return .{ .enemy = null, .visible = false, .distance = std.math.inf(f32) };
    const point = (try world.get(enemy, data.Transform)).position;
    const visible = try sight(pose.position, v.add(point, .{ 0, 0, 16 }), slot, (try world.get(enemy, data.Binding)).slot);
    if (visible) {
        actor.threat_position = point;
        actor.threat_seen_ms = now;
    }
    return .{ .enemy = enemy, .visible = visible, .distance = v.length(v.subtract(point, pose.position)) };
}

/// Patrol observation does not consume injury receipts; the owning combat/pain
/// controller still receives each injury when it interrupts the patrol.
pub fn acquire(world: *data.World, slots: *Slots, entity: ecs.Entity, actor: *data.Actor, pose: data.Transform, definition: rules.Definition, now: i64) !void {
    if (actor.ignore_player) return;
    const slot = (try world.get(entity, data.Binding)).slot;
    if (actor.threat == 0) {
        const catalog = @import("actor_catalog");
        const kind = catalog.entries[actor.definition].kind;
        var best = try @import("properties.zig").number((try world.get(entity, data.MapObject)).*, "sight", definition.sight_range);
        if (kind == .protopod) best = 512;
        for (slots.occupants) |occupant| {
            const target = occupant orelse continue;
            if (!eligible(world, target, now)) continue;
            const point = (try world.get(target, data.Transform)).position;
            const offset = v.subtract(point, pose.position);
            const distance = catalog.perception.distance(kind, offset);
            const horizontal = v.length(.{ offset[0], offset[1], 0 });
            const dot = v.dot(v.normalize(.{ offset[0], offset[1], 0 }), v.basis(.{ 0, pose.angles[1], 0 }).forward);
            if (distance > best or !catalog.perception.inCone(kind, (world.get(target, data.Player) catch null) != null, horizontal, dot, definition.fov)) continue;
            if (!try sight(pose.position, v.add(point, .{ 0, 0, 16 }), slot, (try world.get(target, data.Binding)).slot)) continue;
            actor.threat = try world.persistentId(target);
            best = distance;
        }
    }
}
