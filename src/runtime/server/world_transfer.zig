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
    // No fallible allocation remains after the stream's ownership boundary.
    var command: [96]u8 = undefined;
    engine.send(0, try std.fmt.bufPrintZ(&command, "dk3_world_enter {d}", .{destination.network_id}));
    worlds.activate(handle) catch @panic("prepared world activation failed");
    // Unlink in the old spatial tree, then retire the source identity exactly once.
    try worlds.select(previous);
    engine.unlink(&source.projection[0]);
    try source.slots.release(0, original);
    try source.world.?.destroy(original);
    source.clients.entities[0] = null;
    source.projection[0].shared.contents = 0;
    source.projection[0].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
}
