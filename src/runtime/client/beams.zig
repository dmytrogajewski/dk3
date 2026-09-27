// SPDX-License-Identifier: GPL-2.0-or-later
//! Camera-facing beam geometry; callers own colors, media and endpoints.
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(shader_name: [:0]const u8, start: v.Vec3, end: v.Vec3, radius: f32, color: [4]u8, ref: *const c.refdef_t) void {
    tapered(shader_name, start, end, radius, radius, color, ref);
}
pub fn tapered(shader_name: [:0]const u8, start: v.Vec3, end: v.Vec3, radius: f32, end_radius: f32, color: [4]u8, ref: *const c.refdef_t) void {
    gradient(shader_name, start, end, radius, end_radius, color, color, ref);
}
pub fn gradient(shader_name: [:0]const u8, start: v.Vec3, end: v.Vec3, radius: f32, end_radius: f32, color: [4]u8, end_color: [4]u8, ref: *const c.refdef_t) void {
    const direction = v.subtract(end, start);
    const perpendicular = v.cross(direction, v.subtract(ref.vieworg, start));
    const normal = if (v.length(perpendicular) > 0.001) v.normalize(perpendicular) else ref.viewaxis[1];
    const side = v.scale(normal, radius);
    const far_side = v.scale(normal, end_radius);
    var vertices: [4]c.polyVert_t = undefined;
    for ([_]v.Vec3{ v.subtract(start, side), v.add(start, side), v.add(end, far_side), v.subtract(end, far_side) }, [_][2]f32{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 } }, &vertices) |position, uv, *vertex| vertex.* = .{ .xyz = position, .st = uv, .modulate = if (uv[0] == 0) color else end_color };
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{shader_name.ptr});
    _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, 4), &vertices });
}
