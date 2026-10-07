// SPDX-License-Identifier: GPL-2.0-or-later
//! Ground-brush presentation between snapshot physics time and render time.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const wire = @import("../engine/trajectory.zig");

pub fn adjust(position: v.Vec3, ground: u16, namespace: i32, entities: []const c.entityState_t, from: i32, to: i32) v.Vec3 {
    for (entities) |entity| {
        if (entity.number != @as(i32, ground) or entity.dk3World != namespace or entity.solid != c.SOLID_BMODEL) continue;
        const before = wire.evaluate(entity.pos, from);
        const after = wire.evaluate(entity.pos, to);
        const rotation = v.subtract(wire.evaluate(entity.apos, to), wire.evaluate(entity.apos, from));
        const offset = v.subtract(position, before);
        const axes = v.basis(rotation);
        const rotated = v.add(v.add(v.scale(axes.forward, offset[0]), v.scale(axes.right, -offset[1])), v.scale(v.cross(axes.right, axes.forward), offset[2]));
        return v.add(after, rotated);
    }
    return position;
}

test "ridden brush uses snapshot time including frames before the newest snapshot" {
    var lift = std.mem.zeroes(c.entityState_t);
    lift.number = 71;
    lift.dk3World = 6;
    lift.solid = c.SOLID_BMODEL;
    lift.pos = wire.fromMotion(.{ .base = .{ 0, 0, -120 }, .end = .{ 0, 0, 0 }, .start_ms = 1000, .duration_ms = 600 });
    for ([_]i32{ 1162, 1174, 1186, 1200, 1212, 1224 }) |now| {
        const point = adjust(.{ 1608, 448, -16 }, 71, 6, &.{lift}, 1200, now);
        try std.testing.expectApproxEqAbs(@as(f32, 64), point[2] - wire.evaluate(lift.pos, now)[2], 0.001);
    }
    try std.testing.expectEqual(v.Vec3{ 1608, 448, -16 }, adjust(.{ 1608, 448, -16 }, 2047, 6, &.{lift}, 1200, 1212));
    try std.testing.expectEqual(v.Vec3{ 1608, 448, -16 }, adjust(.{ 1608, 448, -16 }, 71, 7, &.{lift}, 1200, 1212));
    lift.pos = wire.stationary(.{ 0, 0, 0 });
    try std.testing.expectEqual(v.Vec3{ 1608, 448, 104 }, adjust(.{ 1608, 448, 104 }, 71, 6, &.{lift}, 1600, 1612));
}
