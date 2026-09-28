// SPDX-License-Identifier: GPL-2.0-or-later
//! Split a sweep at admitted, authored apertures. Each segment retains the
//! destination's collision owner; a nearer solid always wins over a crossing.
const collision = @import("collision.zig");
pub const Crossing = struct { fraction: f32, world: u32, edge: u8, source_entity: ?u16 = null };

pub fn trace(backend: anytype, origin: u32, request: collision.Request) !collision.Trace {
    var owner = origin;
    var remaining = request;
    var traversed: [256]bool = @splat(false);
    var consumed: f32 = 0;
    while (true) {
        var hit = try backend.local(owner, remaining);
        if (try backend.crossing(owner, remaining, &traversed)) |next| {
            // Interaction rays include triggers. The admitted exit itself is
            // an ownership boundary, not an obstruction; coincident unrelated
            // solids and all-solid starts still block the sweep.
            const exit_contact = next.source_entity != null and hit.entity == next.source_entity.? and next.fraction == hit.fraction;
            if ((next.fraction < hit.fraction or exit_contact) and !hit.all_solid) {
                traversed[next.edge] = true;
                consumed += (1 - consumed) * next.fraction;
                const v = @import("vector.zig");
                remaining.start = v.add(remaining.start, v.scale(v.subtract(remaining.end, remaining.start), next.fraction));
                owner = next.world;
                continue;
            }
        }
        hit.fraction = consumed + (1 - consumed) * hit.fraction;
        hit.world = owner;
        return hit;
    }
}

test "trigger-inclusive sweeps cross only their actual admitted exit" {
    const t = @import("std").testing;
    const Backend = struct {
        blocker: u16 = 25,
        all_solid: bool = false,
        pub fn local(self: @This(), owner: u32, request: collision.Request) !collision.Trace {
            return .{ .fraction = if (owner == 1) 0.4 else 1, .end = if (owner == 1) .{ 4, 0, 0 } else request.end, .normal = @splat(0), .entity = self.blocker, .all_solid = self.all_solid };
        }
        pub fn crossing(_: @This(), owner: u32, _: collision.Request, _: *const [256]bool) !?Crossing {
            return if (owner == 1) .{ .fraction = 0.4, .world = 2, .edge = 0, .source_entity = 25 } else null;
        }
    };
    const request: collision.Request = .{ .start = @splat(0), .end = .{ 10, 0, 0 }, .mins = @splat(0), .maxs = @splat(0), .slot = 0, .mask = 1 };
    try t.expectEqual(@as(u32, 2), (try trace(Backend{}, 1, request)).world);
    try t.expectEqual(@as(u32, 1), (try trace(Backend{ .blocker = 26 }, 1, request)).world);
    try t.expectEqual(@as(u32, 1), (try trace(Backend{ .all_solid = true }, 1, request)).world);
}

test "portal sweeps preserve total fraction, owner and earlier blockers" {
    const t = @import("std").testing;
    const Backend = struct {
        obstructed: bool = false,
        fn local(self: @This(), owner: u32, request: collision.Request) !collision.Trace {
            const x: f32 = if (owner == 1) (if (self.obstructed) 2 else 9) else 8;
            const fraction = (x - request.start[0]) / (request.end[0] - request.start[0]);
            return .{ .fraction = fraction, .end = .{ x, 0, 0 }, .normal = .{ -1, 0, 0 }, .entity = 12 };
        }
        fn crossing(_: @This(), owner: u32, request: collision.Request, visited: *const [256]bool) !?Crossing {
            if (owner != 1 or visited[0]) return null;
            return .{ .fraction = (4 - request.start[0]) / (request.end[0] - request.start[0]), .world = 2, .edge = 0 };
        }
    };
    const request: collision.Request = .{ .start = @splat(0), .end = .{ 10, 0, 0 }, .mins = @splat(0), .maxs = @splat(0), .slot = 0, .mask = 1 };
    const through = try trace(Backend{}, 1, request);
    try t.expectApproxEqAbs(@as(f32, 0.8), through.fraction, 0.0001);
    try t.expectEqual(@as(u32, 2), through.world);
    const blocked = try trace(Backend{ .obstructed = true }, 1, request);
    try t.expectApproxEqAbs(@as(f32, 0.2), blocked.fraction, 0.0001);
    try t.expectEqual(@as(u32, 1), blocked.world);
}

test "coincident reciprocal apertures terminate without revisiting an edge" {
    const t = @import("std").testing;
    const Backend = struct {
        calls: usize = 0,
        pub fn local(self: *@This(), _: u32, request: collision.Request) !collision.Trace {
            self.calls += 1;
            if (self.calls > 3) return error.RepeatedPortalCycle;
            return .{ .fraction = 1, .end = request.end, .normal = @splat(0) };
        }
        pub fn crossing(_: *@This(), owner: u32, _: collision.Request, visited: *const [256]bool) !?Crossing {
            const edge: u8 = if (owner == 1) 0 else 1;
            if (visited[edge]) return null;
            return .{ .fraction = 0, .world = if (owner == 1) 2 else 1, .edge = edge };
        }
    };
    var backend: Backend = .{};
    const hit = try trace(&backend, 1, .{ .start = @splat(0), .end = .{ 10, 0, 0 }, .mins = @splat(0), .maxs = @splat(0), .slot = 0, .mask = 1 });
    try t.expectEqual(@as(usize, 3), backend.calls);
    try t.expectEqual(@as(u32, 1), hit.world);
    try t.expectEqual(@as(f32, 1), hit.fraction);
}
