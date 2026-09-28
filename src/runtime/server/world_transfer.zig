// SPDX-License-Identifier: GPL-2.0-or-later
//! Admission precedes ownership transfer. No spawn, travel reset or connection
//! restart is involved: even the pending user command and weapon action survive.
const std = @import("std");
const Context = @import("world_context.zig").Context;
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const worlds = @import("../engine/worlds.zig");
const resources = @import("resources.zig");
pub fn player(source: *Context, destination: *Context, now: i64) !void {
    if (source == destination) return error.AlreadyInWorld;
    const original = source.clients.entities[0] orelse return error.MissingTraveler;
    if (destination.clients.entities[0] != null) return error.DuplicateTraveler;
    const handle = destination.handle orelse return error.WorldNotAttached;
    const previous = worlds.current();
    const previous_resources = resources.select(&destination.resources);
    defer _ = resources.select(previous_resources);
    try worlds.select(handle);
    defer worlds.select(previous) catch @panic("lost source world");
    try destination.awaken(now);
    const entity = try source.world.?.cloneInto(original, &destination.world.?);
    errdefer destination.world.?.destroy(entity) catch unreachable;
    _ = try destination.slots.acquire(entity, 0);
    errdefer destination.slots.release(0, entity) catch unreachable;
    destination.clients.entities[0] = entity;
    errdefer destination.clients.entities[0] = null;
    destination.players[0] = source.players[0];
    destination.players[0].dk3World = @bitCast(destination.network_id);
    (try destination.world.?.get(entity, data.Binding)).slot = 0;
    try destination.clients.publish(&destination.world.?, &destination.projection, &destination.players, 0, now);
    errdefer engine.unlink(&destination.projection[0]);
    // A carried flashlight, beam or wind-up is part of the player's current
    // action. World-local projectiles and placed charges stay in their owner.
    const ecs = @import("../ecs/world.zig");
    var attached: [ecs.max_entities]struct { old: ecs.Entity, new: ecs.Entity } = undefined;
    var attached_count: usize = 0;
    errdefer for (attached[0..attached_count]) |item| {
        if (destination.world.?.get(item.new, data.Binding) catch null) |binding| {
            engine.unlink(&destination.projection[binding.slot]);
            destination.slots.release(binding.slot, item.new) catch unreachable;
        }
        destination.world.?.destroy(item.new) catch unreachable;
    };
    const identity = try source.world.?.persistentId(original);
    {
        var query = source.world.?.queryAccess(0, 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |action| {
            if (@import("weapon_actions.zig").owner(&source.world.?, action) != identity) continue;
            const moved = try source.world.?.cloneInto(action, &destination.world.?);
            errdefer destination.world.?.destroy(moved) catch unreachable;
            if (destination.world.?.get(moved, data.Binding) catch null) |binding| {
                const slot = try destination.slots.acquire(moved, null);
                errdefer destination.slots.release(slot, moved) catch unreachable;
                binding.slot = slot;
                if (binding.model != 0) {
                    if (binding.model >= source.resources.models.count) return error.InvalidTransferResource;
                    const path = std.mem.sliceTo(&source.resources.models.names[binding.model], 0);
                    binding.model = try resources.model(path);
                }
                destination.projection[slot] = std.mem.zeroes(@import("../engine/abi.zig").EntityProjection);
                destination.projection[slot].state.number = slot;
                destination.projection[slot].shared.ownerNum = @import("../engine/abi.zig").c.ENTITYNUM_NONE;
                try @import("persistence.zig").projectEntity(&destination.world.?, &destination.slots, &destination.projection, &destination.systems, moved, now);
            }
            attached[attached_count] = .{ .old = action, .new = moved };
            attached_count += 1;
        };
    }
    // No fallible allocation remains after the stream's ownership boundary.
    var command: [96]u8 = undefined;
    engine.send(0, try std.fmt.bufPrintZ(&command, "dk3_world_enter {d}", .{destination.network_id}));
    worlds.activate(handle) catch @panic("prepared world activation failed");
    // Unlink in the old spatial tree, then retire the source identity exactly once.
    try worlds.select(previous);
    for (attached[0..attached_count]) |item| {
        if (source.world.?.get(item.old, data.Binding) catch null) |binding| {
            engine.unlink(&source.projection[binding.slot]);
            try source.slots.release(binding.slot, item.old);
            source.projection[binding.slot].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
        }
        try source.world.?.destroy(item.old);
    }
    engine.unlink(&source.projection[0]);
    try source.slots.release(0, original);
    try source.world.?.destroy(original);
    source.clients.entities[0] = null;
    source.projection[0].shared.contents = 0;
    source.projection[0].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
}
