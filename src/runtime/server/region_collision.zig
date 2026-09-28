// SPDX-License-Identifier: GPL-2.0-or-later
//! Combat sweeps through hash-qualified corridor brushes. Landing travel and
//! cinematic cuts cannot become portals. Dynamic solids remain map-owned.
const std = @import("std");
const data = @import("../domain/components.zig");
const collision = @import("../domain/collision.zig");
const walk = @import("../domain/portal_trace.zig");
const access = @import("region_access.zig");
const engine = @import("../engine/server.zig");
const worlds = @import("../engine/worlds.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");

const Backend = struct {
    skip: u32,
    pub fn local(self: Backend, owner: u32, request: collision.Request) !collision.Trace {
        const context = access.byHandle(@enumFromInt(owner)) orelse return error.TraceWorldUnavailable;
        const scope = try context.select();
        defer scope.deinit();
        var selected = request;
        selected.slot = if (context.world.?.find(self.skip)) |entity| context.slots.find(entity) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
        return engine.collisionService().trace(selected);
    }
    pub fn crossing(_: Backend, owner: u32, request: collision.Request, visited: *const [256]bool) !?walk.Crossing {
        const region = access.region orelse return null;
        const context = access.byHandle(@enumFromInt(owner)) orelse return error.TraceWorldUnavailable;
        const map = region.manifest.find(std.mem.sliceTo(&context.map_name, 0)) orelse return null;
        var nearest: ?walk.Crossing = null;
        for (region.manifest.edges[0..region.manifest.edge_count], 0..) |edge, index| {
            if (visited[index] or edge.source != map or edge.kind != .identity) continue;
            if ((request.end[edge.axis] - request.start[edge.axis]) * @as(f32, @floatFromInt(edge.direction)) <= 0) continue;
            const destination = access.byMap(edge.destination) orelse return error.SeamWorldNotAdmitted;
            const id = (context.world.?.id_first & 0xff000000) | @as(u32, edge.exit);
            const exit = context.world.?.find(id) orelse return error.SeamExitMissing;
            const binding = try context.world.?.get(exit, data.Binding);
            const position = (try context.world.?.get(exit, data.Transform)).position;
            // Trigger angles are behavioral, not BSP rotation (brushes.zig).
            const hit = try worlds.trace(context.handle.?, v.subtract(request.start, position), v.subtract(request.end, position), request.mins, request.maxs, binding.model, -1);
            const fraction: f32 = if (hit.startsolid != 0) 0 else hit.fraction;
            if (fraction >= 1 or (nearest != null and nearest.?.fraction <= fraction)) continue;
            nearest = .{ .fraction = fraction, .world = @intFromEnum(destination.handle.?), .edge = @intCast(index) };
        }
        return nearest;
    }
};

pub fn trace(request: collision.Request) !collision.Trace {
    if (access.region == null) return engine.collisionService().trace(request);
    const handle = worlds.current();
    const context = access.byHandle(handle) orelse return engine.collisionService().trace(request);
    const skip = if (request.slot < context.slots.occupants.len) (if (context.slots.occupants[request.slot]) |entity| try context.world.?.persistentId(entity) else 0) else 0;
    return walk.trace(Backend{ .skip = skip }, @intFromEnum(handle), request);
}

/// Continue a moving controller from the owner reached by its previous segment.
/// The skipped actor remains a persistent ID, never a slot in another world.
pub fn from(owner: u32, request: collision.Request, skip: u32) !collision.Trace {
    if (owner == 0) return trace(request);
    return walk.trace(Backend{ .skip = skip }, owner, request);
}
pub fn contents(owner: u32, point: v.Vec3, skip: u32) !u32 {
    if (owner == 0) return engine.collisionService().contents(point, c.ENTITYNUM_NONE);
    const context = access.byHandle(@enumFromInt(owner)) orelse return error.TraceWorldUnavailable;
    const scope = try context.select();
    defer scope.deinit();
    const slot: u16 = if (context.world.?.find(skip)) |entity| context.slots.find(entity) orelse c.ENTITYNUM_NONE else c.ENTITYNUM_NONE;
    return engine.collisionService().contents(point, slot);
}
pub fn reaches(local: *data.World, hit: collision.Trace, target: @import("../domain/world_references.zig").Ref) bool {
    const owner = if (hit.world == 0) local else &(access.byHandle(@enumFromInt(hit.world)) orelse return false).world.?;
    if (owner != target.world or hit.start_solid or hit.all_solid) return false;
    if (hit.fraction == 1) return true;
    const binding = target.get(data.Binding) catch return false;
    return hit.entity == binding.slot;
}
