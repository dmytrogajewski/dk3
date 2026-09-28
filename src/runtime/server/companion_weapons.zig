// SPDX-License-Identifier: GPL-2.0-or-later
//! Companion selection consults weapon-owned eligibility and enemy-owned choices.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const ecs = @import("../ecs/world.zig");
const catalog = @import("weapon_catalog");
const v = @import("../domain/vector.zig");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/server.zig");
const weapons = @import("../domain/weapons.zig");
pub const Situation = struct { episode: u8, choices: [3]u2 = .{ 0, 1, 2 }, owner_distance: f32 = std.math.inf(f32), owner_enemy_distance: f32 = std.math.inf(f32), enemy_distance: ?f32 = null };
pub fn select(loadout: data.Weapons, table: *const weapons.Table, situation: Situation) u5 {
    var available: [3]u5 = @splat(0);
    for (catalog.entries) |entry| {
        const policy = entry.spec.companion orelse continue;
        if (entry.episode != situation.episode or loadout.dk3Inventory & (@as(i32, 1) << entry.id) == 0) continue;
        if (!policy.empty_melee and loadout.ammo[entry.id] < table.entries[entry.id].ammoCost) continue;
        if (situation.enemy_distance) |distance| switch (policy.safety) {
            .none => {},
            .spread => if (situation.owner_distance < 96 or distance > 400) continue,
            .owner => if (situation.owner_enemy_distance < 156) continue,
            .both => if (situation.owner_enemy_distance < 156 or distance < 156) continue,
        };
        std.debug.assert(policy.slot < available.len);
        available[policy.slot] = entry.id;
    }
    // The reviewed selector's presence checks give the later available choice
    // priority, including repeated slots for special enemy classes.
    var result: u5 = 0;
    for (situation.choices) |slot| if (available[slot] != 0) {
        result = available[slot];
    };
    return result;
}
pub fn choose(world: *data.World, entity: ecs.Entity, enemy: ?Ref, table: *const weapons.Table, episode: u8) !u5 {
    const companion = (try world.get(entity, data.Companion)).*;
    if (companion.carrying) return 0;
    const pose = (try world.get(entity, data.Transform)).position;
    var situation: Situation = .{ .episode = episode };
    if (@import("region_access.zig").find(world, companion.owner)) |owner| {
        const point = (try owner.get(data.Transform)).position;
        situation.owner_distance = v.length(v.subtract(pose, point));
        if (enemy) |target| situation.owner_enemy_distance = v.length(v.subtract((try target.get(data.Transform)).position, point));
    }
    if (enemy) |target| {
        situation.enemy_distance = v.length(v.subtract((try target.get(data.Transform)).position, pose));
        if (target.get(data.Actor) catch null) |actor| situation.choices = @import("actor_catalog").entries[actor.definition].companion_choices;
    }
    return select((try world.get(entity, data.Weapons)).*, table, situation);
}
pub fn range(loadout: data.Weapons, id: u5, table: *const weapons.Table) f32 {
    const entry = catalog.find(id) orelse return 0;
    const policy = entry.spec.companion orelse return 0;
    if (policy.empty_melee and loadout.ammo[id] < table.entries[id].ammoCost) return @min(table.entries[id].range, 128);
    return table.entries[id].range;
}
pub fn clear(world: *data.World, entity: ecs.Entity, target: Ref, id: u5, table: *const weapons.Table) !bool {
    const entry = catalog.find(id) orelse return false;
    const policy = entry.spec.companion orelse return false;
    const origin = (try world.get(entity, data.Transform)).position;
    const destination = (try target.get(data.Transform)).position;
    if (@import("../domain/navigation.zig").horizontalDistance(origin, destination) > range((try world.get(entity, data.Weapons)).*, id, table)) return false;
    const slot = (try world.get(entity, data.Binding)).slot;
    const width = policy.clearance;
    const offsets = [_]v.Vec3{ .{ width, 0, width }, .{ 0, 0, width * 2 }, .{ width, 0, width }, .{ 0, 0, 0 } };
    for (offsets[0..if (width == 0) @as(usize, 1) else offsets.len]) |offset| {
        const trace = try @import("region_collision.zig").trace(.{ .start = v.add(origin, offset), .end = destination, .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = if (width == 0) c.MASK_SHOT else c.MASK_PLAYERSOLID });
        if (!@import("region_collision.zig").reaches(world, trace, target)) return false;
    }
    return true;
}

test "companion weapon selection respects enemy choices and friendly splash distances" {
    const t = std.testing;
    var table: weapons.Table = .{};
    var inventory: data.Weapons = .{};
    for (catalog.entries) |entry| {
        inventory.dk3Inventory |= @as(i32, 1) << entry.id;
        inventory.ammo[entry.id] = 50;
        table.entries[entry.id] = .{ .ammoCost = 1, .range = 1000 };
    }
    try t.expectEqual(catalog.silverclaw.id, select(inventory, &table, .{ .episode = 3, .choices = .{ 0, 0, 0 }, .enemy_distance = 100 }));
    try t.expectEqual(catalog.ballista.id, select(inventory, &table, .{ .episode = 3, .enemy_distance = 300 }));
    try t.expectEqual(catalog.bolter.id, select(inventory, &table, .{ .episode = 3, .owner_enemy_distance = 100, .enemy_distance = 300 }));
    inventory.ammo[catalog.bolter.id] = 0;
    try t.expectEqual(catalog.silverclaw.id, select(inventory, &table, .{ .episode = 3, .choices = .{ 0, 1, 1 }, .enemy_distance = 500 }));
}
