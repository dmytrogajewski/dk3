// SPDX-License-Identifier: GPL-2.0-or-later
//! Resolve current entity ownership without exporting local ECS handles across
//! worlds. The campaign owners retain the contexts; this adapter borrows them.
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const Context = @import("world_context.zig").Context;
const Residents = @import("resident_worlds.zig").State;
pub const Region = struct { initial: *Context, residents: *Residents, manifest: *const @import("../domain/campaign_regions.zig").Manifest };
pub var region: ?Region = null;

pub fn find(local: *data.World, id: u32) ?Ref {
    if (local.find(id)) |entity| return .{ .world = local, .entity = entity };
    const owners = region orelse return null;
    if (owners.initial.world) |*world| if (world != local) if (world.find(id)) |entity| return .{ .world = world, .entity = entity };
    for (owners.residents.entries) |maybe| if (maybe) |entry| if (entry.ready) if (entry.context) |context| {
        const world = if (context.world) |*value| value else continue;
        if (world == local) continue;
        if (world.find(id)) |entity| return .{ .world = world, .entity = entity };
    };
    return null;
}
pub fn contextFor(world: *data.World) ?*Context {
    const owners = region orelse return null;
    if (owners.initial.world) |*initial| if (initial == world) return owners.initial;
    for (owners.residents.entries) |maybe| if (maybe) |entry| if (entry.ready) if (entry.context) |context| {
        if (context.world) |*candidate| if (candidate == world) return context;
    };
    return null;
}
pub fn byHandle(handle: @import("../engine/worlds.zig").Handle) ?*Context {
    const owners = region orelse return null;
    if (owners.initial.handle == handle) return owners.initial;
    for (owners.residents.entries) |maybe| if (maybe) |entry| if (entry.ready and entry.handle == handle) return entry.context;
    return null;
}
pub fn byMap(index: u7) ?*Context {
    const owners = region orelse return null;
    if (index >= owners.manifest.count) return null;
    const name = owners.manifest.names[index];
    if (@import("std").mem.eql(u8, name, @import("std").mem.sliceTo(&owners.initial.map_name, 0))) return owners.initial;
    return owners.residents.destination(name) catch null;
}

/// Collision slots are meaningful only in the owner that performed the trace.
pub fn victim(local: *data.World, slots: *const @import("../engine/slots.zig").Slots, hit: @import("../domain/collision.zig").Trace) ?Ref {
    if (hit.world != 0) {
        const context = byHandle(@enumFromInt(hit.world)) orelse return null;
        if (hit.entity >= context.slots.occupants.len) return null;
        return .{ .world = &context.world.?, .entity = context.slots.occupants[hit.entity] orelse return null };
    }
    if (hit.entity >= slots.occupants.len) return null;
    return .{ .world = local, .entity = slots.occupants[hit.entity] orelse return null };
}

pub fn expose(world: *data.World, now: i64) !void {
    if (contextFor(world)) |context| try context.expose(now);
}

/// Only identity-qualified edges share a physical coordinate space. A landing
/// in the same prefetched region does not make its entities spatial neighbors.
pub fn connected(context: *Context) [128]bool {
    var selected: [128]bool = @splat(false);
    const owners = region orelse return selected;
    const seed = owners.manifest.find(@import("std").mem.sliceTo(&context.map_name, 0)) orelse return selected;
    selected[seed] = true;
    var changed = true;
    while (changed) {
        changed = false;
        for (owners.manifest.edges[0..owners.manifest.edge_count]) |edge| {
            if (edge.kind != .identity or selected[edge.source] == selected[edge.destination]) continue;
            selected[edge.source] = true;
            selected[edge.destination] = true;
            changed = true;
        }
    }
    return selected;
}

pub const Neighbors = struct {
    selected: [128]bool,
    cursor: usize = 0,
    pub fn init(context: *Context) Neighbors {
        return .{ .selected = connected(context) };
    }
    pub fn next(self: *Neighbors) ?*Context {
        const owners = region orelse return null;
        while (self.cursor < owners.manifest.count) {
            const index = self.cursor;
            self.cursor += 1;
            if (self.selected[index]) if (byMap(@intCast(index))) |context| return context;
        }
        return null;
    }
};

pub const Damageables = struct {
    local: *data.World,
    world: *data.World,
    slots: *const @import("../engine/slots.zig").Slots,
    neighbors: ?Neighbors,
    cursor: usize = 0,
    pub fn init(world: *data.World, slots: *const @import("../engine/slots.zig").Slots) Damageables {
        return .{ .local = world, .world = world, .slots = slots, .neighbors = if (contextFor(world)) |context| Neighbors.init(context) else null };
    }
    pub fn next(self: *Damageables) ?Ref {
        while (true) {
            while (self.cursor < self.slots.occupants.len) {
                const index = self.cursor;
                self.cursor += 1;
                const entity = self.slots.occupants[index] orelse continue;
                if (!self.world.alive(entity)) continue;
                const ref: Ref = .{ .world = self.world, .entity = entity };
                ref.require(.{ data.Health, data.Transform }) catch continue;
                return ref;
            }
            if (self.neighbors) |*neighbors| {
                const context = neighbors.next() orelse return null;
                if (&context.world.? == self.local) continue;
                self.world = &context.world.?;
                self.slots = &context.slots;
                self.cursor = 0;
            } else return null;
        }
    }
};

test "foreign persistent owners and aliased transport slots cannot select a local entity" {
    const t = @import("std").testing;
    const first = try t.allocator.create(Context);
    defer t.allocator.destroy(first);
    first.* = .{ .world = data.World.initNamespaced(t.allocator, 2, 0), .handle = @enumFromInt(513) };
    defer first.world.?.deinit();
    const second = try t.allocator.create(Context);
    defer t.allocator.destroy(second);
    second.* = .{ .world = data.World.initNamespaced(t.allocator, 2, 1), .handle = @enumFromInt(514) };
    defer second.world.?.deinit();
    const residents = try t.allocator.create(Residents);
    defer t.allocator.destroy(residents);
    residents.* = .{};
    residents.entries[0] = .{ .handle = second.handle.?, .context = second, .ready = true };
    var manifest: @import("../domain/campaign_regions.zig").Manifest = .{};
    const previous = region;
    region = .{ .initial = first, .residents = residents, .manifest = &manifest };
    defer region = previous;
    const a = try first.world.?.create(null, .{data.Health{ .current = 31 }});
    const b = try second.world.?.create(null, .{data.Health{ .current = 79 }});
    try t.expectEqual(a.index, b.index);
    const a_slot = try first.slots.acquire(a, null);
    const b_slot = try second.slots.acquire(b, null);
    try t.expectEqual(a_slot, b_slot);
    const by_id = find(&first.world.?, try second.world.?.persistentId(b)).?;
    try t.expect(by_id.world == &second.world.?);
    const hit: @import("../domain/collision.zig").Trace = .{ .fraction = 0.5, .world = 514, .entity = b_slot, .end = @splat(0), .normal = @splat(0) };
    const foreign = victim(&first.world.?, &first.slots, hit).?;
    (try foreign.get(data.Health)).current -= 10;
    try t.expectEqual(@as(i32, 31), (try first.world.?.get(a, data.Health)).current);
    try t.expectEqual(@as(i32, 69), (try second.world.?.get(b, data.Health)).current);
    var stale = hit;
    stale.world = 1026;
    try t.expect(victim(&first.world.?, &first.slots, stale) == null);
}
