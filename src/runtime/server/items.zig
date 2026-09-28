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
    const path = @import("item_catalog").model(rules.canonicalName(object.classname)) orelse return "";
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
    for (entities[0..count]) |entity| try spawnOne(world, slots, projections, entity, now, episode);
}
pub fn spawnDynamic(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, classname: []const u8, pose: data.Transform, now: i64, episode: u8) !ecs.Entity {
    const entity = try world.create(null, .{ data.MapObject{ .classname = classname }, pose });
    errdefer world.destroy(entity) catch unreachable;
    if (@import("item_catalog").chest.kind(classname) != null) {
        const chest = try @import("chests.zig").initialize(world, entity, now);
        try world.put(entity, data.WorldControl{ .action = .{ .chest = chest } });
        try @import("chests.zig").bind(world, slots, projections, entity, now);
    } else try spawnOne(world, slots, projections, entity, now, episode);
    return entity;
}
/// Death drops carry the actual remaining ammunition and never respawn.
pub fn dropCurrent(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, now: i64, episode: u8) !void {
    const loadout = (try world.get(owner, data.Weapons)).*;
    if (loadout.weapon < 1 or loadout.weapon > 28) return;
    const id: u5 = @intCast(loadout.weapon);
    const weapon = @import("weapon_catalog").find(id) orelse return;
    if (!weapon.spec.droppable or loadout.ammo[id] <= 0 or loadout.dk3Inventory & (@as(i32, 1) << id) == 0) return;
    const multiplayer = @import("multiplayer.zig").enabled();
    const companion = (world.get(owner, data.Companion) catch null) != null;
    var pose = (try world.get(owner, data.Transform)).*;
    if (multiplayer) pose.position[2] += 16;
    pose.angles = @splat(0);
    var random: data.Random = .{ .state = (try world.persistentId(owner)) ^ @as(u32, @truncate(@as(u64, @bitCast(now)))) };
    const velocity: data.Vec3 = .{ random.next() * (if (companion) @as(f32, 300) else 400) - 200, random.next() * (if (companion) @as(f32, 300) else 400) - 200, random.next() * (if (companion) @as(f32, 200) else 250) + (if (companion) @as(f32, 200) else 250) };
    const item = try spawnDynamic(world, slots, projections, weapon.classname, pose, now, episode);
    const pickup = try world.get(item, data.Pickup);
    pickup.amount = loadout.ammo[id];
    pickup.dropped = true;
    pickup.expires_ms = if (multiplayer) now + 60000 else null;
    (try world.get(item, data.ItemMotion)).* = .{ .base = pose.position, .velocity = velocity, .started_ms = now, .bounce = 0 };
    try publish(world, item, projections);
}
fn spawnOne(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64, episode: u8) !void {
    const object = (try world.get(entity, data.MapObject)).*;
    const kind = rules.classify(object.classname) orelse return error.UnknownItemClass;
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
    // Slots can previously belong to a sound/event, corpse or brush entity.
    projections[slot] = std.mem.zeroes(abi.EntityProjection);
    try publish(world, entity, projections);
}

pub fn publish(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !void {
    const projection = try updateProjection(world, entity, projections);
    const pickup = (try world.get(entity, data.Pickup)).*;
    if (rules.rotates(pickup.kind, (try world.get(entity, data.MapObject)).classname, engine.integer("g_gametype") == c.GT_SINGLE_PLAYER)) projection.state.apos = @import("../engine/trajectory.zig").linear(.{ 0, 0, 0 }, .{ 0, 100, 0 }, 0);
    if (projection.shared.contents != 0) engine.link(projection) else engine.unlink(projection);
}

fn updateProjection(world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection) !*abi.EntityProjection {
    const binding = (try world.get(entity, data.Binding)).*;
    const transform = (try world.get(entity, data.Transform)).*;
    const body = (try world.get(entity, data.Body)).*;
    const pickup = (try world.get(entity, data.Pickup)).*;
    const motion = (try world.get(entity, data.ItemMotion)).*;
    const projection = &projections[binding.slot];
    projection.state = std.mem.zeroes(c.entityState_t);
    projection.state.number = binding.slot;
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
    projection.shared.ownerNum = c.ENTITYNUM_NONE;
    projection.shared.contents = if (pickup.visible) c.CONTENTS_TRIGGER else 0;
    if (pickup.visible) {
        projection.shared.svFlags &= ~@as(i32, c.SVF_NOCLIENT);
    } else {
        projection.shared.svFlags |= c.SVF_NOCLIENT;
    }
    return projection;
}
/// Shared tossed-item collision; a false result means an authored no-drop volume.
pub fn settle(world: *data.World, entity: ecs.Entity, now: i64, elapsed: u32) !bool {
    const motion = try world.get(entity, data.ItemMotion);
    if (motion.ground != null) return true;
    const transform = try world.get(entity, data.Transform);
    const body = (try world.get(entity, data.Body)).*;
    const slot = (try world.get(entity, data.Binding)).slot;
    var trace = try engine.collisionService().trace(.{ .start = transform.position, .end = motion.sample(now), .mins = body.mins, .maxs = body.maxs, .slot = slot, .mask = body.collision_mask });
    transform.position = trace.end;
    if (trace.start_solid) trace.fraction = 0;
    if (trace.fraction < 1) {
        if (try engine.collisionService().contents(transform.position, slot) & c.CONTENTS_NODROP != 0) return false;
        transform.position = motion.impact(trace, now, elapsed);
    }
    return true;
}

pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, router: *@import("targets.zig").Router, table: *const @import("../domain/weapons.zig").Table, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if (!world.alive(entity)) continue;
        const pickup = world.get(entity, data.Pickup) catch continue;
        if (pickup.expires_ms) |due| if (now >= due) {
            try @import("weapon_entities.zig").remove(world, slots, projections, entity);
            continue;
        };
        if (pickup.respawn_ms) |due| if (now >= due) {
            pickup.visible = true;
            pickup.respawn_ms = null;
        };
        const slot = (try world.get(entity, data.Binding)).slot;
        if (!try settle(world, entity, now, elapsed)) {
            try @import("weapon_entities.zig").remove(world, slots, projections, entity);
            continue;
        }
        try publish(world, entity, projections);
        if (!pickup.visible) continue;
        for (occupants) |client| {
            const player = client orelse continue;
            if (!world.alive(player)) continue;
            if (world.get(player, data.Player) catch null) |state| {
                if (state.mode != .normal) continue;
            } else if (world.get(player, data.Companion) catch null) |companion| {
                if (companion.collecting != try world.persistentId(entity) or companion.stopped) continue;
                const actor_system = router.actors orelse return error.MissingActorDefinitions;
                if (!try @import("companion_items.zig").allows(world, player, entity, table, actor_system.episode, companion.collect_forced, now)) continue;
            } else continue;
            const player_slot = (try world.get(player, data.Binding)).slot;
            if (!@import("interactions.zig").overlap(&projections[slot], &projections[player_slot], 0)) continue;
            const single_player = engine.integer("g_gametype") == c.GT_SINGLE_PLAYER;
            const stays = rules.weaponStays(pickup.*, !single_player and engine.integer("dm_weapons_stay") != 0);
            if (stays and (try world.get(player, data.Weapons)).dk3Inventory & (@as(i32, 1) << pickup.kind.weapon) != 0) continue;
            if (!rules.give(pickup.*, .{ .keys = try world.get(player, data.Keys), .health = try world.get(player, data.Health), .loadout = try world.get(player, data.Weapons), .character = try world.get(player, data.Character), .ailments = try world.get(player, data.Ailments) }, table, now, engine.integer("g_gametype") == c.GT_SINGLE_PLAYER)) continue;
            pickup.visible = stays;
            if (pickup.kind == .weapon and player_slot < Slots.clients) {
                var command: [48]u8 = undefined;
                const selected = (try world.get(player, data.Weapons)).weapon;
                engine.send(player_slot, try std.fmt.bufPrintZ(&command, "dk3_weapon {d}", .{selected}));
            }
            const object = (try world.get(entity, data.MapObject)).*;
            const dropped = pickup.dropped;
            // Weapon spawn callbacks own their respawn time. The item-respawn
            // switch applies to ammunition and ordinary items, not weapons.
            if (!stays and !dropped and (pickup.kind == .weapon or engine.integer("dm_item_respawn") != 0)) {
                if (rules.respawnDelay(object.classname, single_player)) |delay| pickup.respawn_ms = now + delay;
            }
            try publish(world, entity, projections);
            const sound = rules.pickupSound(pickup.kind, object.classname);
            const collector = (try world.get(player, data.Transform)).position;
            // Events add components/entities; no borrowed component pointers survive this barrier.
            try @import("events.zig").sound(world, slots, projections, sound, collector, player_slot, c.CHAN_ITEM, now);
            try router.fire(world, slots, projections, entity, try world.persistentId(player), now);
            if (dropped and world.alive(entity)) try @import("weapon_entities.zig").remove(world, slots, projections, entity);
            break; // Targets may destroy this item or other queried entities.
        }
    }
}

test "pickup projection clears a previous sound event when its slot is reused" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 4);
    defer world.deinit();
    const item = try world.create(1, .{ data.Binding{ .slot = 0, .model = 29 }, data.Transform{ .position = .{ 10, 20, 30 } }, data.Body{ .mins = @splat(-8), .maxs = @splat(8) }, data.Pickup{ .kind = .{ .ammunition = 2 } }, data.ItemMotion{ .ground = c.ENTITYNUM_WORLD } });
    var projections = [_]abi.EntityProjection{std.mem.zeroes(abi.EntityProjection)};
    projections[0].state.frame = @import("../domain/audio.zig").parameter_tag;
    projections[0].state.eFlags = c.EF_NODRAW;
    projections[0].state.event = c.EV_GENERAL_SOUND;
    projections[0].state.eventParm = 17;
    projections[0].shared.ownerNum = 3;
    const projected = try updateProjection(&world, item, &projections);
    try t.expectEqual(@as(i32, 0), projected.state.frame);
    try t.expectEqual(@as(i32, 0), projected.state.eFlags);
    try t.expectEqual(@as(i32, 0), projected.state.event);
    try t.expectEqual(@as(i32, 0), projected.state.eventParm);
    try t.expectEqual(@as(i32, c.ET_DK3_ITEM), projected.state.eType);
    try t.expectEqual(@as(i32, 29), projected.state.modelindex);
    try t.expectEqual(@as(i32, c.ENTITYNUM_NONE), projected.shared.ownerNum);
    try t.expectEqual(@as(data.Vec3, .{ 10, 20, 30 }), projected.state.pos.trBase);
    try t.expectEqual(@as(i32, c.CONTENTS_TRIGGER), projected.shared.contents);
    (try world.get(item, data.Pickup)).visible = false;
    _ = try updateProjection(&world, item, &projections);
    try t.expectEqual(@as(i32, 0), projected.shared.contents);
    try t.expect(projected.shared.svFlags & c.SVF_NOCLIENT != 0);
    (try world.get(item, data.Pickup)).visible = true;
    _ = try updateProjection(&world, item, &projections);
    try t.expectEqual(@as(i32, c.CONTENTS_TRIGGER), projected.shared.contents);
    try t.expect(projected.shared.svFlags & c.SVF_NOCLIENT == 0);
}
