// SPDX-License-Identifier: GPL-2.0-or-later
//! Destructible controls, switchable geometry, hurt volumes and authored target timelines.
const std = @import("std");
const data = @import("../domain/components.zig");
const rules = @import("../domain/world_actions.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const Slots = @import("../engine/slots.zig").Slots;
const Router = @import("targets.zig").Router;
const prop = @import("properties.zig");
const v = @import("../domain/vector.zig");
fn is(object: data.MapObject, classname: []const u8) bool {
    return std.mem.eql(u8, object.classname, classname);
}
fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, visible: bool, contents: u32) !void {
    const slot = (try world.get(entity, data.Binding)).slot;
    (try world.get(entity, data.Body)).contents = contents;
    projections[slot].shared.contents = @bitCast(contents);
    if (visible) projections[slot].shared.svFlags &= ~@as(i32, c.SVF_NOCLIENT) else projections[slot].shared.svFlags |= c.SVF_NOCLIENT;
    engine.link(&projections[slot]);
}
pub fn spawn(allocator: std.mem.Allocator, world: *data.World, projections: []abi.EntityProjection) !void {
    var handles: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.MapObject}), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            handles[count] = entity;
            count += 1;
        };
    }
    for (handles[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        if (is(object, "trigger_hurt")) {
            const amount = try prop.number(object, "damage", try prop.number(object, "dmg", 5));
            if (amount < 0) return error.InvalidHazardDamage;
            const hazard: data.Hazard = .{ .enabled = object.flags & 3 != 3, .toggleable = object.flags & 1 != 0, .damage = @intFromFloat(amount), .interval_ms = @max(50, try prop.milliseconds(object, "wait", 0.5)), .sound = prop.text(object, "sound") orelse "" };
            try world.put(entity, hazard);
            try publish(world, entity, projections, false, if (hazard.enabled) c.CONTENTS_TRIGGER else 0);
        } else if (is(object, "func_explosive") or is(object, "func_breakable")) {
            const health = try prop.number(object, "health", 100);
            const state: data.Destructible = .{ .hidden = object.flags & 1 != 0, .shootable = object.targetname.len == 0, .nonsolid = object.flags & 512 != 0, .damage = @max(0, try prop.number(object, "dmg", 0)), .radius = @max(1, try prop.number(object, "radius", 160)) };
            try world.put(entity, state);
            try world.put(entity, data.Health{ .current = @intFromFloat(@max(1, health)), .maximum = @intFromFloat(@max(1, health)) });
            try world.put(entity, data.Hurt{});
            try publish(world, entity, projections, !state.hidden, if (state.hidden or state.nonsolid) 0 else c.CONTENTS_SOLID);
        } else if (is(object, "func_wall")) {
            const state: data.Wall = .{ .visible = (object.flags & 3 == 0 or object.flags & 4 != 0) and (object.flags & 64 == 0 or engine.integer("g_gametype") == c.GT_CTF), .toggleable = object.flags & 2 != 0, .nonsolid = object.flags & 32 != 0 };
            try world.put(entity, state);
            try publish(world, entity, projections, state.visible, if (state.visible and !state.nonsolid) c.CONTENTS_SOLID else 0);
        } else if (is(object, "func_event_generator")) {
            var events: std.array_list.Managed(rules.Event) = .init(allocator);
            for (object.properties) |property| {
                var reserved = false;
                for ([_][]const u8{ "classname", "model", "origin", "angle", "angles", "targetname", "spawnflags", "wait", "sound", "volume", "health", "delay", "_color", "min", "max", "coop", "ctf", "deathtag" }) |name| if (std.ascii.eqlIgnoreCase(property.key, name)) {
                    reserved = true;
                    break;
                };
                if (reserved) continue;
                const seconds = std.fmt.parseFloat(f32, property.value) catch return error.InvalidEventDelay;
                if (!std.math.isFinite(seconds) or seconds < 0 or seconds > 3600 or events.items.len >= 128) return error.InvalidEventDelay;
                try events.append(.{ .target = property.key, .delay_ms = @intFromFloat(seconds * 1000) });
            }
            std.mem.sort(rules.Event, events.items, {}, struct {
                fn less(_: void, a: rules.Event, b: rules.Event) bool {
                    return a.delay_ms < b.delay_ms;
                }
            }.less);
            try world.put(entity, data.TargetSequence{ .events = try events.toOwnedSlice(), .once = object.flags & 1 != 0, .touch = object.flags & 2 != 0, .actor_allowed = object.flags & 4 != 0, .wait_ms = @max(50, try prop.milliseconds(object, "wait", 0.2)), .sound = prop.text(object, "sound") orelse "" });
            if (slotsBinding(world, entity)) |_| try publish(world, entity, projections, false, if (object.flags & 2 != 0) c.CONTENTS_TRIGGER else 0);
        }
    }
}
fn slotsBinding(world: *data.World, entity: ecs.Entity) ?data.Binding {
    return if (world.get(entity, data.Binding)) |binding| binding.* else |_| null;
}
pub fn activate(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, entity: ecs.Entity, activator: u32, now: i64) anyerror!bool {
    if (world.get(entity, data.Hazard)) |hazard| {
        if (hazard.toggleable) {
            hazard.enabled = !hazard.enabled;
            try publish(world, entity, projections, false, if (hazard.enabled) c.CONTENTS_TRIGGER else 0);
        }
        return true;
    } else |_| {}
    if (world.get(entity, data.Wall)) |wall| {
        if (wall.used and !wall.toggleable) return true;
        wall.used = true;
        wall.visible = !wall.visible;
        try publish(world, entity, projections, wall.visible, if (wall.visible and !wall.nonsolid) c.CONTENTS_SOLID else 0);
        try router.fire(world, slots, projections, entity, activator, now);
        return true;
    } else |_| {}
    if (world.get(entity, data.Destructible)) |value| {
        const state = value.*;
        if (state.broken) return true;
        if (state.hidden) {
            value.hidden = false;
            try publish(world, entity, projections, true, if (state.nonsolid) 0 else c.CONTENTS_SOLID);
            return true;
        }
        value.broken = true;
        (try world.get(entity, data.Health)).current = 0;
        const slot = (try world.get(entity, data.Binding)).slot;
        const center = v.scale(v.add(projections[slot].shared.absmin, projections[slot].shared.absmax), 0.5);
        try publish(world, entity, projections, false, 0);
        if (state.damage > 0) {
            const occupants = slots.occupants;
            for (occupants, 0..) |occupant, target_slot| {
                const target = occupant orelse continue;
                if (target_slot == slot) continue;
                const health = world.get(target, data.Health) catch continue;
                if (health.current <= 0) continue;
                const position = (try world.get(target, data.Transform)).position;
                const distance = v.length(v.subtract(position, center));
                if (distance >= state.radius) continue;
                const hit = try engine.collisionService().trace(.{ .start = center, .end = position, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SOLID });
                if (hit.fraction < 1 and hit.entity != target_slot) continue;
                _ = try @import("damage.zig").apply(world, target, @intFromFloat(@ceil(state.damage * (1 - distance / state.radius))), now, .{ .source = activator });
            }
        }
        try router.fire(world, slots, projections, entity, activator, now);
        return true;
    } else |_| {}
    if (world.get(entity, data.TargetSequence)) |sequence| {
        const owner = world.find(activator) orelse return true;
        const health = world.get(owner, data.Health) catch return true;
        if (health.current <= 0) return true;
        if ((world.get(owner, data.Player) catch null) == null and (!sequence.actor_allowed or (world.get(owner, data.Actor) catch null) == null)) return true;
        if (sequence.start(activator, now)) {
            const sound = sequence.sound;
            if (sound.len > 0) {
                const position = (try world.get(entity, data.Transform)).position;
                const slot: u16 = if (slotsBinding(world, entity)) |binding| binding.slot else c.ENTITYNUM_NONE;
                try @import("events.zig").sound(world, slots, projections, sound, position, slot, c.CHAN_AUTO, now);
            }
        }
        return true;
    } else |_| {}
    return false;
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *Router, now: i64) !void {
    var sequences: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{data.TargetSequence}), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            sequences[count] = entity;
            count += 1;
        };
    }
    for (sequences[0..count]) |entity| while (world.alive(entity)) {
        const state = try world.get(entity, data.TargetSequence);
        const name = state.next(now) orelse break;
        const owner = state.activator;
        try router.fireNamed(world, slots, projections, name, entity, owner, now);
    };
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        if (world.get(entity, data.Destructible)) |state| {
            if (!state.broken and !state.hidden and (try world.get(entity, data.Health)).current <= 0) {
                const attacker = (try world.get(entity, data.Hurt)).source;
                _ = try activate(world, slots, projections, router, entity, attacker, now);
            }
        } else |_| {}
        if (!world.alive(entity)) continue;
    }
    try @import("campaign_rules.zig").repairHazards(world, projections);
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        const hazard = (world.get(entity, data.Hazard) catch continue).*;
        if (!hazard.enabled or now < hazard.ready_ms) continue;
        const slot = (try world.get(entity, data.Binding)).slot;
        var contacted = false;
        for (occupants, 0..) |candidate, target_slot| {
            const target = candidate orelse continue;
            if (!world.alive(target)) continue;
            const health = world.get(target, data.Health) catch continue;
            if (health.current <= 0) continue;
            if (world.get(target, data.Player)) |player| {
                if (player.mode != .normal) continue;
            } else |_| if ((world.get(target, data.Actor) catch null) == null) continue;
            if (!@import("interactions.zig").overlap(&projections[slot], &projections[target_slot], 1)) continue;
            const result = try @import("damage.zig").apply(world, target, hazard.damage, now, .{ .source = try world.persistentId(entity), .environmental = true });
            if (engine.integer("developer") != 0 and result.blood > 0) {
                var text: [140]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig hazard hit: id={d} target={d} blood={d}\n", .{ try world.persistentId(entity), try world.persistentId(target), result.blood }));
            }
            contacted = true;
        }
        if (contacted) {
            (try world.get(entity, data.Hazard)).ready_ms = now + hazard.interval_ms;
            if (hazard.sound.len > 0) try @import("events.zig").sound(world, slots, projections, hazard.sound, projections[slot].shared.currentOrigin, slot, c.CHAN_AUTO, now);
        }
    }
}
