// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/items.zig");
const prop = @import("properties.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const resources = @import("resources.zig");
const c = abi.c;
fn model(object: data.MapObject, kind: rules.Kind, episode: u8, buffer: []u8) ![]const u8 {
    if (object.model.len > 0) return object.model;
    if (kind == .weapon) return @import("weapon_catalog").find(kind.weapon).?.spec.world_model orelse "";
    if (std.mem.eql(u8, object.classname, "item_health_25") or std.mem.eql(u8, object.classname, "item_health_50")) {
        return std.fmt.bufPrint(buffer, "models/e{d}/a{d}_hlth{s}.dkm", .{ episode, episode, if (episode != 2 and kind.health == 50) @as([]const u8, "2") else "" });
    }
    const path = @import("item_catalog").model(object.classname) orelse return "";
    return std.fmt.bufPrint(buffer, "models/{s}.dkm", .{path});
}
pub fn spawn(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64, episode: u8) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.MapObject)) |entity, object| if (rules.classify(object.classname) != null) {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const object = (try world.get(entity, data.MapObject)).*;
        const kind = rules.classify(object.classname).?;
        const position = (try world.get(entity, data.Transform)).position;
        const slot = try slots.acquire(entity, null);
        errdefer slots.release(slot, entity) catch unreachable;
        var buffer: [c.MAX_QPATH]u8 = undefined;
        const path = try model(object, kind, episode, &buffer);
        const model_index = try resources.model(path);
        var body: data.Body = .{ .mins = @splat(-16), .maxs = @splat(16), .contents = c.CONTENTS_TRIGGER, .collision_mask = c.MASK_SOLID };
        if (try resources.floorBounds(path)) |bounds| {
            body.mins = bounds.mins;
            body.maxs = bounds.maxs;
        }
        try world.put(entity, data.Binding{ .slot = slot, .model = model_index });
        try world.put(entity, body);
        try world.put(entity, data.Pickup{ .kind = kind, .amount = @intFromFloat(try prop.number(object, "count", 0)) });
        try world.put(entity, data.ItemMotion{ .base = position, .started_ms = now });
        try publish(world, entity, projections);
    }
}
pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const binding = (try world.get(entity, data.Binding)).*;
    const transform = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const pickup = (try world.get(entity, data.Pickup)).*;
    const motion = (try world.get(entity, data.ItemMotion)).*;
    const projection = &projections[binding.slot];
    projection.state.eType = c.ET_DK3_ITEM;
    projection.state.modelindex = binding.model;
    projection.state.pos = if (motion.ground != null) @import("../engine/trajectory.zig").stationary(transform.position) else @import("../engine/trajectory.zig").linear(motion.base, motion.velocity, motion.started_ms);
    if (motion.ground == null) projection.state.pos.trType = c.TR_GRAVITY;
    projection.state.apos = @import("../engine/trajectory.zig").stationary(transform.angles);
    projection.state.groundEntityNum = motion.ground orelse c.ENTITYNUM_NONE;
    projection.shared.currentOrigin = transform.position;
    projection.shared.currentAngles = transform.angles;
    projection.shared.mins = body.mins;
    projection.shared.maxs = body.maxs;
    projection.shared.contents = if (pickup.visible) c.CONTENTS_TRIGGER else 0;
    if (pickup.visible) {
        projection.shared.svFlags &= ~@as(i32, c.SVF_NOCLIENT);
        engine.link(projection);
    } else {
        projection.shared.svFlags |= c.SVF_NOCLIENT;
        engine.unlink(projection);
    }
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, table: *const @import("../domain/weapons.zig").Table, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        const pickup = world.get(entity, data.Pickup) catch continue;
        if (pickup.respawn_ms) |due| if (now >= due) {
            pickup.visible = true;
            pickup.respawn_ms = null;
        };
        const motion = try world.get(entity, data.ItemMotion);
        const transform = try world.get(entity, data.Transform);
        const body = try world.get(entity, data.Body);
        const slot = (try world.get(entity, data.Binding)).slot;
        if (motion.ground == null) {
            var trace = try engine.collisionService().trace(.{ .start = transform.position, .end = motion.sample(now), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
            transform.position = trace.end;
            if (trace.start_solid) trace.fraction = 0;
            if (trace.fraction < 1) {
                if (try engine.collisionService().contents(transform.position, slot) & c.CONTENTS_NODROP != 0) {
                    engine.unlink(&projections[slot]);
                    try slots.release(slot, entity);
                    try world.destroy(entity);
                    continue;
                }
                transform.position = motion.impact(trace, now, elapsed);
            }
        }
        try publish(world, entity, projections);
        if (!pickup.visible) continue;
        for (occupants[0..Slots.clients]) |client| {
            const player = client orelse continue;
            if (!world.alive(player)) continue;
            if ((try world.get(player, data.Player)).mode != .normal) continue;
            const player_slot = (try world.get(player, data.Binding)).slot;
            if (!@import("interactions.zig").overlap(&projections[slot], &projections[player_slot], 0)) continue;
            if (!rules.give(pickup.*, try world.get(player, data.Keys), try world.get(player, data.Health), try world.get(player, data.Weapons), table, now, engine.integer("g_gametype") == c.GT_SINGLE_PLAYER)) continue;
            pickup.visible = false;
            if (pickup.kind == .weapon) {
                var command: [48]u8 = undefined;
                const selected = (try world.get(player, data.Weapons)).weapon;
                engine.send(player_slot, try std.fmt.bufPrintZ(&command, "dk3_weapon {d}", .{selected}));
            }
            const object = (try world.get(entity, data.MapObject)).*;
            if (rules.respawnDelay(object.classname, engine.integer("g_gametype") == c.GT_SINGLE_PLAYER)) |delay| pickup.respawn_ms = now + delay;
            try publish(world, entity, projections);
            try router.fire(world, slots, projections, entity, try world.persistentId(player), now);
            break; // Targets may destroy this item or other queried entities.
        }
    }
}
