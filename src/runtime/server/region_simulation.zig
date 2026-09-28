// SPDX-License-Identifier: GPL-2.0-or-later
//! Previously exposed neighbors keep their controllers alive after a crossing.
//! Preparation alone never starts an encounter; authored cuts freeze old regions.
const access = @import("region_access.zig");
const Context = @import("world_context.zig").Context;
const std = @import("std");
pub fn step(active: *Context, now: i64, elapsed: u32) !void {
    const region = access.region orelse return;
    const connected = access.connected(active);
    if (region.initial != active) try member(region.initial, region.manifest, connected, now, elapsed);
    for (region.residents.entries) |maybe| if (maybe) |entry| if (entry.ready) if (entry.context) |context| {
        if (context != active) try member(context, region.manifest, connected, now, elapsed);
    };
}
fn member(context: *Context, manifest: *const @import("../domain/campaign_regions.zig").Manifest, connected: [128]bool, now: i64, elapsed: u32) !void {
    const index = manifest.find(std.mem.sliceTo(&context.map_name, 0));
    if (!context.activated or index == null or !connected[index.?]) {
        context.running = false;
        return;
    }
    try context.expose(now);
    const scope = try context.select();
    defer scope.deinit();
    try context.systems.step(&context.world.?, &context.slots, &context.projection, &context.targets, now, elapsed, &context.clients.weapon_table);
    context.stepped_at = now;
}
