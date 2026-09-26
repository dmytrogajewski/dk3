// SPDX-License-Identifier: GPL-2.0-or-later
//! Projectile releases queued by attack animations. Current owner pose is sampled at release.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("weapon_catalog");
const weapons = @import("../domain/weapons.zig");
pub fn queue(world: *data.World, owner: ecs.Entity, shot: weapons.Fired, now: i64, delay: u32) !void {
    _ = try world.create(null, .{ data.Transform{ .position = shot.position }, data.WeaponLaunch{ .owner = try world.persistentId(owner), .weapon = shot.weapon, .sequence = shot.sequence, .charge = shot.charge, .execute_ms = now + delay } });
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, table: *const weapons.Table, now: i64) !void {
    var entities: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{data.WeaponLaunch}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            entities[count] = entity;
            count += 1;
        };
    }
    for (entities[0..count]) |entity| {
        const action = (try world.get(entity, data.WeaponLaunch)).*;
        const owner = world.find(action.owner) orelse {
            try world.destroy(entity);
            continue;
        };
        if ((try world.get(owner, data.Health)).current <= 0 or (try world.get(owner, data.Weapons)).weapon != action.weapon) {
            try world.destroy(entity);
            continue;
        }
        if (now < action.execute_ms) continue;
        const pose = (try world.get(owner, data.Transform)).*;
        const player = (try world.get(owner, data.Player)).*;
        const slot = (try world.get(owner, data.Binding)).slot;
        try world.destroy(entity);
        try @import("projectiles.zig").launch(world, slots, projections, owner, .{ .weapon = action.weapon, .sequence = action.sequence, .charge = action.charge, .position = pose.position, .angles = pose.angles, .view_height = player.view_height, .ducked = player.ducked, .command_ms = now }, table, now);
        if (catalog.fireSound(action.weapon, action.sequence, @truncate(@as(u64, @bitCast(now))))) |sound| try @import("events.zig").sound(world, slots, projections, sound, pose.position, slot, abi.c.CHAN_WEAPON, now);
    }
}
