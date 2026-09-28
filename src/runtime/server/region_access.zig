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
pub fn byName(name: []const u8) ?*Context {
    const owners = region orelse return null;
    return byMap(owners.manifest.find(name) orelse return null);
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
/// Entity birth and physical ownership can differ from its authored script/name
/// scope (party cuts may also rebind a continuing birth identity).
pub fn authored(world: *data.World, entity: @import("../ecs/world.zig").Entity) !?*Context {
    const object = world.get(entity, data.MapObject) catch return contextFor(world);
    if (object.authoring_map.len == 0) return contextFor(world);
    const owners = region orelse return error.AuthoringWorldUnavailable;
    const index = owners.manifest.find(object.authoring_map) orelse return error.AuthoringWorldUnavailable;
    return byMap(index) orelse return error.AuthoringWorldUnavailable;
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
    first.* = .{ .world = data.World.initNamespaced(t.allocator, 32, 0), .handle = @enumFromInt(513) };
    defer first.world.?.deinit();
    const second = try t.allocator.create(Context);
    defer t.allocator.destroy(second);
    second.* = .{ .world = data.World.initNamespaced(t.allocator, 32, 1), .handle = @enumFromInt(514) };
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
    try t.expect(!by_id.same(.{ .world = &first.world.?, .entity = a }));
    // A moved party member keeps B's authored names even while its body is in
    // A. B's local entity deliberately has the same name and local ECS index.
    @memcpy(first.map_name[0..5], "e1m1a");
    @memcpy(second.map_name[0..5], "e1m1b");
    @memcpy(residents.entries[0].?.name[0..5], "e1m1b");
    residents.entries[0].?.publication = .{ .payload = &.{}, .digest = 0, .checksum = 0, .ready = true };
    manifest.count = 2;
    manifest.names[0] = "e1m1a";
    manifest.names[1] = "e1m1b";
    manifest.edge_count = 1;
    manifest.edges[0] = .{ .source = 0, .destination = 1, .exit = 25, .reciprocal = 449, .kind = .identity };
    const leader = try second.world.?.persistentId(b);
    try first.world.?.put(a, data.Transform{ .position = .{ 32, 0, 0 } });
    try first.world.?.put(a, data.MapObject{ .classname = "superfly", .targetname = "shared", .authoring_map = "e1m1b" });
    try first.world.?.put(a, data.Actor{ .definition = @import("actor_catalog").find("superfly").?, .stepped_ms = 1000 });
    try first.world.?.put(a, data.Companion{ .identity = .superfly, .owner = leader });
    try second.world.?.put(b, data.Transform{});
    try second.world.?.put(b, data.MapObject{ .classname = "player", .targetname = "shared" });
    try second.world.?.put(b, data.Player{});
    inline for (.{ data.Weapons, data.Character, data.Keys, data.Ailments }) |T| {
        try first.world.?.put(a, T{});
        try second.world.?.put(b, T{});
    }
    const names = @import("names.zig");
    try t.expectEqual(@as(usize, 0), (try names.named(&first.world.?, "shared")).count);
    try t.expectEqual(@as(usize, 2), (try names.named(&second.world.?, "shared")).count);
    try t.expect((try authored(&first.world.?, a)).? == second);
    const party = @import("companions.zig");
    try t.expect(try party.required(&second.world.?, b, 2));
    const traveler = try party.capture(&second.world.?, b, 1, 1000);
    try t.expectEqual(try first.world.?.persistentId(a), traveler.companions[1].?.persistent_id);
    try t.expectEqual(@as(data.Vec3, .{ 32, 0, 0 }), traveler.companions[1].?.offset);
    manifest.edges[0].kind = .cut;
    try t.expect(!try party.required(&second.world.?, b, 2));
    try t.expect((try party.capture(&second.world.?, b, 1, 1000)).companions[1] == null);
}
