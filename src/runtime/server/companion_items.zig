// SPDX-License-Identifier: GPL-2.0-or-later
//! Party collection uses ordinary pickup contact, admitted classes and real routes.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const nav = @import("../domain/navigation.zig");
const v = @import("../domain/vector.zig");
const weapons = @import("../domain/weapons.zig");
const catalog = @import("weapon_catalog");
const items = @import("../domain/items.zig");
pub fn allows(world: *data.World, collector: ecs.Entity, entity: ecs.Entity, table: *const weapons.Table, episode: u8, forced: bool, now: i64) !bool {
    const companion = (try world.get(collector, data.Companion)).*;
    const pickup = (world.get(entity, data.Pickup) catch return false).*;
    if (!companion.enabled or !pickup.visible) return false;
    const object = (try world.get(entity, data.MapObject)).*;
    const flags: u32 = @intFromFloat(@max(0, try @import("properties.zig").number(object, "itemspawnflags", 0)));
    const excluded: u32 = if (companion.identity == .mikiko) 2 else 1;
    if (!forced and flags & excluded != 0) return false;
    var health = (try world.get(collector, data.Health)).*;
    var loadout = (try world.get(collector, data.Weapons)).*;
    switch (pickup.kind) {
        .health => if (health.current * 100 >= health.maximum * 95) return false,
        .soul => if (health.current > 100 and !forced) return false,
        .weapon, .ammunition => |id| {
            if (companion.carrying) return false;
            const entry = catalog.find(id) orelse return false;
            const policy = entry.spec.companion orelse return false;
            if (entry.episode != episode) return false;
            if (pickup.kind == .weapon and !policy.pickup) return false;
            if (pickup.kind == .ammunition and (!policy.ammunition or loadout.dk3Inventory & (@as(i32, 1) << id) == 0)) return false;
        },
        .armor => |armor| if (health.current * armor.absorption <= health.armor * health.absorption) return false,
        else => return false,
    }
    var keys = (try world.get(collector, data.Keys)).*;
    var character = (try world.get(collector, data.Character)).*;
    var ailments = (try world.get(collector, data.Ailments)).*;
    return items.give(pickup, .{ .health = &health, .loadout = &loadout, .keys = &keys, .character = &character, .ailments = &ailments }, table, now, true);
}
fn length(service: nav.Service, position: v.Vec3, destination: v.Vec3, slot: u16, limit: f32) !?f32 {
    var point = position;
    var total: f32 = 0;
    for (0..32) |_| {
        const remaining = v.length(v.subtract(destination, point));
        if (total + remaining >= limit) return null;
        if (remaining < 24) return total + remaining;
        const next = try service.next(.{ .position = point, .destination = destination, .slot = slot, .player = true }) orelse return null;
        const step = v.length(v.subtract(next.point, point));
        if (step < 1) return null;
        total += step;
        if (total >= limit) return null;
        point = next.point;
    }
    return null;
}
pub fn choose(world: *data.World, collector: ecs.Entity, table: *const weapons.Table, episode: u8, service: nav.Service, now: i64) !u32 {
    const companion = (try world.get(collector, data.Companion)).*;
    const pose = (try world.get(collector, data.Transform)).position;
    const body = (try world.get(collector, data.Body)).*;
    const binding = (try world.get(collector, data.Binding)).*;
    const health = (try world.get(collector, data.Health)).*;
    const inventory = (try world.get(collector, data.Weapons)).*;
    var result: u32 = 0;
    var nearest: f32 = std.math.inf(f32);
    var priority: u8 = 255;
    var query = world.queryAccess(data.World.mask(.{ data.Pickup, data.Transform, data.Binding }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Pickup), view.read(data.Transform), view.read(data.Binding)) |entity, pickup, target, target_binding| {
        const id = try world.persistentId(entity);
        if (id == companion.avoided_item and now < companion.avoid_until_ms) continue;
        const distance = v.length(v.subtract(target.position, pose));
        if (distance >= 256 or !try allows(world, collector, entity, table, episode, false, now)) continue;
        const hit = try engine.collisionService().trace(.{ .start = pose, .end = target.position, .mins = @splat(0), .maxs = @splat(0), .slot = binding.slot, .mask = c.MASK_SHOT });
        if (hit.start_solid or (hit.fraction < 1 and hit.entity != target_binding.slot)) continue;
        const rank: u8 = switch (pickup.kind) {
            .health => if (health.current * 2 < health.maximum) 0 else 4,
            .weapon => |weapon| if (inventory.dk3Inventory & (@as(i32, 1) << weapon) == 0) 1 else 6,
            .ammunition => 2,
            .soul => 3,
            .armor => 5,
            else => continue,
        };
        if (rank > priority) continue;
        const path = if (try @import("actor_motion.zig").direct(pose, target.position, body, binding.slot)) distance else try length(service, pose, target.position, binding.slot, 256) orelse continue;
        if (rank == priority and path >= nearest) continue;
        nearest = path;
        priority = rank;
        result = id;
    };
    return result;
}
pub fn pursuing(world: *data.World, collector: ecs.Entity, actor: *data.Actor, pose: data.Transform, table: *const weapons.Table, episode: u8, now: i64) !bool {
    const companion = try world.get(collector, data.Companion);
    if (companion.collecting == 0) return false;
    const item = world.find(companion.collecting);
    const valid = if (item) |entity| try allows(world, collector, entity, table, episode, companion.collect_forced, now) else false;
    if (!valid or now >= companion.collect_until_ms or (actor.route.blocked and now - actor.route.progress_ms > 2000)) {
        if (valid) {
            companion.avoided_item = companion.collecting;
            companion.avoid_until_ms = now + 10000;
            if (companion.collect_forced) engine.send(0, "cp \"Companion cannot reach that item\"");
        }
        companion.collecting = 0;
        companion.collect_forced = false;
        if (companion.order == .collect) companion.order = .follow;
        actor.route = .{};
        return false;
    }
    actor.threat = 0;
    actor.threat_position = (try world.get(item.?, data.Transform)).position;
    actor.mode = if (v.length(v.subtract(actor.threat_position, pose.position)) > 4) .chase else .idle;
    return true;
}

test "bounded pickup paths reject a looping or overlong route" {
    const t = std.testing;
    const Fake = struct {
        loop: bool = false,
        fn next(raw: *anyopaque, request: nav.Request) !?nav.Waypoint {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return .{ .point = if (self.loop) request.position else request.destination };
        }
    };
    var fake: Fake = .{};
    const service: nav.Service = .{ .context = &fake, .next_fn = Fake.next };
    try t.expectEqual(@as(?f32, 128), try length(service, @splat(0), .{ 128, 0, 0 }, 1, 256));
    try t.expectEqual(@as(?f32, null), try length(service, @splat(0), .{ 256, 0, 0 }, 1, 256));
    fake.loop = true;
    try t.expectEqual(@as(?f32, null), try length(service, @splat(0), .{ 128, 0, 0 }, 1, 256));
}

test "companions obey authored exclusions, weapon permission, carrying and actual need" {
    const t = std.testing;
    var world = data.World.init(t.allocator, 8);
    defer world.deinit();
    const collector = try world.create(1, .{ data.Companion{ .identity = .mikiko }, data.Health{ .current = 80 }, data.Weapons{}, data.Keys{}, data.Character{}, data.Ailments{} });
    const pickup = try world.create(2, .{ data.Pickup{ .kind = .{ .health = 25 } }, data.MapObject{ .classname = "item_health_25", .properties = &.{.{ .key = "itemspawnflags", .value = "2" }} } });
    var table: weapons.Table = .{};
    table.entries[catalog.ion.id] = .{ .ammoMax = 100, .initialAmmo = 20 };
    table.entries[catalog.trident.id] = .{ .ammoMax = 100, .initialAmmo = 20 };
    try t.expect(!try allows(&world, collector, pickup, &table, 1, false, 100));
    try t.expect(try allows(&world, collector, pickup, &table, 1, true, 100));
    try t.expectEqual(@as(i32, 80), (try world.get(collector, data.Health)).current);
    (try world.get(pickup, data.MapObject)).properties = &.{};
    (try world.get(pickup, data.Pickup)).kind = .{ .weapon = catalog.ion.id };
    try t.expect(try allows(&world, collector, pickup, &table, 1, false, 100));
    try t.expect(!try allows(&world, collector, pickup, &table, 2, true, 100));
    (try world.get(collector, data.Companion)).carrying = true;
    try t.expect(!try allows(&world, collector, pickup, &table, 1, true, 100));
    (try world.get(collector, data.Companion)).carrying = false;
    (try world.get(pickup, data.Pickup)).kind = .{ .weapon = catalog.trident.id };
    try t.expect(!try allows(&world, collector, pickup, &table, 2, true, 100));
    (try world.get(pickup, data.Pickup)).kind = .{ .ammunition = catalog.ion.id };
    try t.expect(!try allows(&world, collector, pickup, &table, 1, true, 100));
    (try world.get(collector, data.Weapons)).dk3Inventory = 1 << catalog.ion.id;
    try t.expect(try allows(&world, collector, pickup, &table, 1, false, 100));
    (try world.get(collector, data.Weapons)).ammo[catalog.ion.id] = 100;
    try t.expect(!try allows(&world, collector, pickup, &table, 1, true, 100));
}
