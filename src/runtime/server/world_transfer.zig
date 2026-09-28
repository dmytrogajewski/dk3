// SPDX-License-Identifier: GPL-2.0-or-later
//! Admission precedes ownership transfer. No spawn, travel reset or connection
//! restart is involved: even the pending user command and weapon action survive.
const std = @import("std");
const Context = @import("world_context.zig").Context;
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const worlds = @import("../engine/worlds.zig");
const resources = @import("resources.zig");
const ecs = @import("../ecs/world.zig");
const Attached = struct {
    items: [ecs.max_entities]struct { old: ecs.Entity, new: ecs.Entity } = undefined,
    count: usize = 0,
    // Destination is selected and its continuing owner has already been staged.
    fn stage(source: *Context, destination: *Context, identity: u32, now: i64) !Attached {
        var batch: Attached = .{};
        errdefer batch.rollback(destination);
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
                batch.items[batch.count] = .{ .old = action, .new = moved };
                batch.count += 1;
            };
        }
        return batch;
    }
    fn rollback(self: *const Attached, destination: *Context) void {
        for (self.items[0..self.count]) |item| {
            if (destination.world.?.get(item.new, data.Binding) catch null) |binding| {
                engine.unlink(&destination.projection[binding.slot]);
                destination.slots.release(binding.slot, item.new) catch unreachable;
            }
            destination.world.?.destroy(item.new) catch unreachable;
        }
    }
    // Commit only after all destination allocation/projection succeeded.
    fn retire(self: *const Attached, source: *Context) void {
        for (self.items[0..self.count]) |item| {
            if (source.world.?.get(item.old, data.Binding) catch null) |binding| {
                engine.unlink(&source.projection[binding.slot]);
                source.slots.release(binding.slot, item.old) catch @panic("lost attached slot");
                source.projection[binding.slot].shared.contents = 0;
                source.projection[binding.slot].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
            }
            source.world.?.destroy(item.old) catch @panic("lost attached action");
        }
    }
};
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
    try destination.expose(now);
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
    const attached = try Attached.stage(source, destination, try source.world.?.persistentId(original), now);
    errdefer attached.rollback(destination);
    try @import("region_presentation.zig").State.tag(destination);
    // No fallible allocation remains after the stream's ownership boundary.
    var command: [96]u8 = undefined;
    engine.send(0, try std.fmt.bufPrintZ(&command, "dk3_world_enter {d}", .{destination.network_id}));
    worlds.activate(handle) catch @panic("prepared world activation failed");
    // Unlink in the old spatial tree, then retire the source identity exactly once.
    try worlds.select(previous);
    attached.retire(source);
    engine.unlink(&source.projection[0]);
    try source.slots.release(0, original);
    try source.world.?.destroy(original);
    source.clients.entities[0] = null;
    source.projection[0].shared.contents = 0;
    source.projection[0].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
}

/// Relocate a free entity after its sweep reached another admitted owner. The
/// component state and birth identity move once; local resource/slot indices do
/// not. Map brushes retain their authored owner and cannot use this operation.
pub fn relocate(source: *Context, destination: *Context, original: @import("../ecs/world.zig").Entity, now: i64) !void {
    if (source == destination) return;
    const object = source.world.?.get(original, data.MapObject) catch null;
    if (object) |value| if (std.mem.startsWith(u8, value.model, "*")) return error.CannotTransferMapBrush;
    const previous = try destination.select();
    defer previous.deinit();
    try destination.expose(now);
    if (source.world.?.get(original, data.Actor) catch null) |actor| try destination.systems.actors.ensure(actor.definition);
    const moved = try source.world.?.cloneInto(original, &destination.world.?);
    errdefer destination.world.?.destroy(moved) catch unreachable;
    if (destination.world.?.get(moved, data.MapObject) catch null) |map_object| if (map_object.authoring_map.len == 0) {
        map_object.authoring_map = try destination.world.?.allocator.dupe(u8, std.mem.sliceTo(&source.map_name, 0));
    };
    if (destination.world.?.get(moved, data.Actor) catch null) |_| {
        try destination.systems.scripts.ensureForeign((try destination.world.?.get(moved, data.MapObject)).authoring_map);
    }
    const binding = try destination.world.?.get(moved, data.Binding);
    const old_slot = binding.slot;
    const slot = try destination.slots.acquire(moved, null);
    errdefer destination.slots.release(slot, moved) catch unreachable;
    binding.slot = slot;
    if (binding.model != 0) {
        if (binding.model >= source.resources.models.count) return error.InvalidTransferResource;
        binding.model = try resources.model(std.mem.sliceTo(&source.resources.models.names[binding.model], 0));
    }
    if (destination.world.?.get(moved, data.Actor) catch null) |actor| {
        actor.ground_entity = @import("../engine/abi.zig").c.ENTITYNUM_NONE;
        actor.route = .{};
    }
    if (destination.world.?.get(moved, data.Companion) catch null) |companion| companion.motor.ground_entity = @import("../engine/abi.zig").c.ENTITYNUM_NONE;
    if (destination.world.?.get(moved, data.Body) catch null) |body| body.grounded = false;
    destination.projection[slot] = std.mem.zeroes(@import("../engine/abi.zig").EntityProjection);
    destination.projection[slot].state.number = slot;
    destination.projection[slot].shared.ownerNum = @import("../engine/abi.zig").c.ENTITYNUM_NONE;
    try @import("persistence.zig").projectEntity(&destination.world.?, &destination.slots, &destination.projection, &destination.systems, moved, now);
    errdefer engine.unlink(&destination.projection[slot]);
    const attached = try Attached.stage(source, destination, try source.world.?.persistentId(original), now);
    errdefer attached.rollback(destination);
    // Commit cannot unwind destination cleanup while the source is selected.
    worlds.select(source.handle.?) catch @panic("lost transferring source");
    attached.retire(source);
    engine.unlink(&source.projection[old_slot]);
    source.slots.release(old_slot, original) catch @panic("lost transferring slot");
    source.projection[old_slot].shared.contents = 0;
    source.projection[old_slot].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
    source.world.?.destroy(original) catch @panic("lost transferring entity");
}

/// Cuts use existing class-owned arrival/spawn rules, which can change a party
/// member's presentation (for example carrying Mikiko). Rebind that destination
/// incarnation to the continuing identity, then retire only the departed copy.
/// Members without an authored arrival remain in their source world.
pub fn party(source: *Context, destination: *Context, traveler: @import("../domain/travel.zig").Traveler) !void {
    const companions = @import("companions.zig");
    const prior = worlds.current();
    defer worlds.select(prior) catch @panic("lost active party world");
    for (traveler.companions) |maybe| if (maybe) |follower| {
        const original = @import("region_access.zig").find(&source.world.?, follower.persistent_id) orelse return error.MissingDepartingCompanion;
        const origin = @import("region_access.zig").contextFor(original.world) orelse return error.MissingDepartingCompanion;
        const arrived = companions.find(&destination.world.?, follower.state.identity) orelse continue;
        const previous_id = try destination.world.?.persistentId(arrived);
        // Slots and map-authored presentation belong to the new incarnation;
        // inventory/state were applied by companions.arrive before this commit.
        try destination.world.?.reidentify(arrived, follower.persistent_id);
        try @import("../domain/snapshot_ids.zig").replace(&destination.world.?, &destination.targets.pending, previous_id, follower.persistent_id);
        try worlds.select(origin.handle orelse return error.WorldNotAttached);
        try @import("weapon_actions.zig").cancel(original.world, &origin.slots, &origin.projection, original.entity);
        const binding = (try original.get(data.Binding)).*;
        engine.unlink(&origin.projection[binding.slot]);
        try origin.slots.release(binding.slot, original.entity);
        origin.projection[binding.slot].shared.contents = 0;
        origin.projection[binding.slot].shared.svFlags = @import("../engine/abi.zig").c.SVF_NOCLIENT;
        try original.world.destroy(original.entity);
    };
}
