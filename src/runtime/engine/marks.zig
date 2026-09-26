// SPDX-License-Identifier: GPL-2.0-or-later
//! Mechanical collision projection for world decals; ownership stays with presentation.
const engine = @import("client.zig");
const c = @import("abi.zig").c;
const v = @import("../domain/vector.zig");
pub const Polygon = struct { vertices: [32]c.polyVert_t = undefined, count: u8 = 0 };
pub const Projection = struct { polygons: [32]Polygon = undefined, count: u8 = 0 };
pub fn project(origin: v.Vec3, normal: v.Vec3, radius: f32, angle: f32) !Projection {
    const axis = v.normalize(v.cross(normal, if (@abs(normal[2]) > 0.9) .{ 1, 0, 0 } else .{ 0, 0, 1 }));
    const tangent = v.add(v.scale(axis, @cos(angle)), v.scale(v.cross(normal, axis), @sin(angle)));
    const bitangent = v.cross(normal, tangent);
    const center = v.add(origin, v.scale(normal, 0.5));
    var corners: [4]v.Vec3 = undefined;
    for ([_][2]f32{ .{ -1, -1 }, .{ -1, 1 }, .{ 1, 1 }, .{ 1, -1 } }, &corners) |offset, *point| point.* = v.add(center, v.add(v.scale(tangent, radius * offset[0]), v.scale(bitangent, radius * offset[1])));
    const projection = v.scale(normal, -20);
    var points: [128]v.Vec3 = undefined;
    var fragments: [32]c.markFragment_t = undefined;
    const count = engine.gateway.call(c.CG_CM_MARKFRAGMENTS, .{ @as(isize, corners.len), &corners, &projection, @as(isize, points.len), &points, @as(isize, fragments.len), &fragments });
    if (count < 0 or count > fragments.len) return error.InvalidMarkFragments;
    var result: Projection = .{};
    for (fragments[0..@intCast(count)]) |fragment| {
        if (fragment.firstPoint < 0 or fragment.numPoints < 0 or fragment.numPoints > points.len or fragment.firstPoint > @as(c_int, points.len) - fragment.numPoints) return error.InvalidMarkVertices;
        if (fragment.numPoints < 3 or fragment.numPoints > 32) continue;
        const polygon = &result.polygons[result.count];
        result.count += 1;
        polygon.count = @intCast(fragment.numPoints);
        for (polygon.vertices[0..polygon.count], points[@intCast(fragment.firstPoint)..][0..polygon.count]) |*vertex, point| {
            const offset = v.subtract(point, origin);
            vertex.* = .{ .xyz = point, .st = .{ 0.5 + v.dot(offset, tangent) / (radius * 2), 0.5 + v.dot(offset, bitangent) / (radius * 2) }, .modulate = @splat(255) };
        }
    }
    return result;
}
