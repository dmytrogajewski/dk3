// SPDX-License-Identifier: GPL-2.0-or-later
//! Rectangular faces of the reviewed six-plane, axis-aligned exit brushes.
const v = @import("vector.zig");
pub const Aperture = struct {
    source: u32,
    destination: u32,
    axis: u2,
    direction: i2,
    mins: v.Vec3,
    maxs: v.Vec3,
    pub fn validate(self: Aperture) !void {
        const std = @import("std");
        if (self.source == self.destination or self.axis > 2 or (self.direction != -1 and self.direction != 1)) return error.InvalidWorldAperture;
        for (self.mins, self.maxs) |low, high| if (!std.math.isFinite(low) or !std.math.isFinite(high) or low >= high) return error.InvalidWorldAperture;
    }
    pub fn center(self: Aperture) v.Vec3 {
        var point = v.scale(v.add(self.mins, self.maxs), 0.5);
        point[self.axis] = if (self.direction > 0) self.mins[self.axis] else self.maxs[self.axis];
        return point;
    }
    pub fn vertices(self: Aperture) [4]v.Vec3 {
        const b = (@as(usize, self.axis) + 1) % 3;
        const c = (@as(usize, self.axis) + 2) % 3;
        var result: [4]v.Vec3 = @splat(self.center());
        for (&result, [_][2]bool{ .{ false, false }, .{ true, false }, .{ true, true }, .{ false, true } }) |*point, upper| {
            point[b] = if (upper[0]) self.maxs[b] else self.mins[b];
            point[c] = if (upper[1]) self.maxs[c] else self.mins[c];
        }
        if (self.direction < 0) @import("std").mem.swap(v.Vec3, &result[1], &result[3]);
        return result;
    }
};
test "aperture uses the outgoing near face and renderer clockwise normal in every axis" {
    const t = @import("std").testing;
    for (0..3) |axis| for ([_]i2{ -1, 1 }) |direction| {
        const aperture: Aperture = .{ .source = 0, .destination = 2, .axis = @intCast(axis), .direction = direction, .mins = .{ -4, -8, -16 }, .maxs = .{ 4, 8, 16 } };
        try aperture.validate();
        const points = aperture.vertices();
        const normal = v.normalize(v.cross(v.subtract(points[2], points[0]), v.subtract(points[1], points[0])));
        try t.expectEqual(-@as(f32, @floatFromInt(direction)), normal[axis]);
        try t.expectEqual(if (direction > 0) aperture.mins[axis] else aperture.maxs[axis], aperture.center()[axis]);
    };
}
