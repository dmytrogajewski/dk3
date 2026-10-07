// SPDX-License-Identifier: GPL-2.0-or-later
//! Attached models sample the same parent trajectory as their brush carrier.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const wire = @import("../engine/trajectory.zig");
const poses = @import("../domain/poses.zig");
const Pose = poses.Pose;
fn sample(state: c.entityState_t, now: i32) Pose {
    return .{ .position = wire.evaluate(state.pos, now), .angles = wire.evaluate(state.apos, now) };
}
const Resolver = struct {
    source: []const c.entityState_t,
    display: []c.entityState_t,
    at: i32,
    now: i32,
    visited: [c.MAX_GENTITIES]enum { fresh, visiting, done } = @splat(.fresh),
    fn resolve(self: *Resolver, index: usize) void {
        if (self.visited[index] != .fresh) return;
        self.visited[index] = .visiting;
        const child = self.source[index];
        if (child.dk3ParentIdentity != 0) for (self.source, 0..) |parent, j| {
            if (parent.dk3Identity != child.dk3ParentIdentity or parent.dk3World != child.dk3World or self.visited[j] == .visiting) continue;
            self.resolve(j);
            const before = sample(parent, self.at);
            const after = sample(self.display[j], self.now);
            // Own button/door travel is already sampled at render time. Apply
            // only the parent's displacement since its committed snapshot.
            const own = sample(self.display[index], self.now);
            self.display[index].pos = wire.stationary(poses.point(own.position, before, after));
            self.display[index].apos = wire.stationary(poses.orientation(own.angles, before.angles, after.angles));
            break;
        };
        self.visited[index] = .done;
    }
};
pub fn apply(source: []const c.entityState_t, display: []c.entityState_t, at: i32, now: i32) void {
    if (source.len != display.len or source.len > c.MAX_GENTITIES) return;
    var resolver: Resolver = .{ .source = source, .display = display, .at = at, .now = now };
    for (0..source.len) |i| resolver.resolve(i);
}
pub fn diagnostics(source: []const c.entityState_t, display: []const c.entityState_t, at: i32, now: i32) void {
    var buffer: [384]u8 = undefined;
    for (source, display) |raw, rendered| {
        const point = wire.evaluate(rendered.pos, now);
        if (raw.dk3ParentIdentity != 0) for (display) |parent| {
            if (parent.dk3Identity != raw.dk3ParentIdentity or parent.dk3World != raw.dk3World) continue;
            const carrier = wire.evaluate(parent.pos, now);
            const relative = @import("../domain/vector.zig").subtract(point, carrier);
            @import("../engine/client.zig").print(std.fmt.bufPrintZ(&buffer, "dk3 attachment view: now={d} snapshot={d} id={d} parent={d} pos={d:.4},{d:.4},{d:.4} relative={d:.4},{d:.4},{d:.4}\n", .{ now, at, raw.dk3Identity, raw.dk3ParentIdentity, point[0], point[1], point[2], relative[0], relative[1], relative[2] }) catch unreachable);
            break;
        };
        if (raw.eType == c.ET_DK3_ITEM) @import("../engine/client.zig").print(std.fmt.bufPrintZ(&buffer, "dk3 item view: now={d} id={d} ground={d} pos={d:.4},{d:.4},{d:.4}\n", .{ now, raw.dk3Identity, raw.groundEntityNum, point[0], point[1], point[2] }) catch unreachable);
    }
}
test "nested lift attachments stay fixed relative to the carrier between snapshots" {
    const v = @import("../domain/vector.zig");
    var states = [_]c.entityState_t{std.mem.zeroes(c.entityState_t)} ** 3;
    states[0].dk3Identity = 10;
    states[0].pos = wire.linear(.{ 0, 0, 0 }, .{ 0, 0, 100 }, 0);
    states[1].dk3Identity = 11;
    states[1].dk3ParentIdentity = 10;
    states[1].pos = wire.stationary(.{ 10, 0, 10 });
    states[2].dk3Identity = 12;
    states[2].dk3ParentIdentity = 11;
    states[2].pos = wire.stationary(.{ 12, 0, 10 });
    for ([_]i32{ 51, 75, 99, 100, 125 }) |now| {
        var display = states;
        apply(&states, &display, 100, now);
        const deck = wire.evaluate(display[0].pos, now);
        try std.testing.expectApproxEqAbs(@as(f32, 0), v.subtract(wire.evaluate(display[1].pos, now), deck)[2], 0.0001);
        try std.testing.expectApproxEqAbs(@as(f32, 0), v.subtract(wire.evaluate(display[2].pos, now), deck)[2], 0.0001);
    }
}
