// SPDX-License-Identifier: GPL-2.0-or-later
//! Camera-facing beam geometry; callers own colors, media and endpoints.
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(shader_name: [:0]const u8, start: v.Vec3, end: v.Vec3, radius: f32, color: [4]u8, ref: *const c.refdef_t) void {
    const direction = v.subtract(end, start);
    const perpendicular = v.cross(direction, v.subtract(ref.vieworg, start));
    const side = v.scale(if (v.length(perpendicular) > 0.001) v.normalize(perpendicular) else ref.viewaxis[1], radius);
    var vertices: [4]c.polyVert_t = undefined;
    for ([_]v.Vec3{ v.subtract(start, side), v.add(start, side), v.add(end, side), v.subtract(end, side) }, [_][2]f32{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 } }, &vertices) |position, uv, *vertex| vertex.* = .{ .xyz = position, .st = uv, .modulate = color };
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{shader_name.ptr});
    _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, 4), &vertices });
}
