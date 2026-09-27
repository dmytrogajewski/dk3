// SPDX-License-Identifier: GPL-2.0-or-later
//! Two translucent sixteen-sided cones preserve the authored spotlight silhouette.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(entity: c.entityState_t, now: i32) void {
    const start = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    const basis = v.basis(@import("../engine/trajectory.zig").evaluate(entity.apos, now));
    const up = v.cross(basis.right, basis.forward);
    const distance = v.length(v.subtract(entity.origin2, start));
    var color: [4]u8 = .{ 255, 255, 255, 64 };
    for (entity.angles2, color[0..3]) |channel, *out| out.* = @intFromFloat(std.math.clamp(channel, 0, 1) * 255);
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/spotlight")});
    for (0..2) |layer| {
        const scale: f32 = if (layer == 0) 1 else 2.0 / 3.0;
        const near = @as(f32, @floatFromInt(entity.frame)) * scale;
        const far = near + distance * 0.2 * scale;
        for (0..16) |side| {
            var vertices: [4]c.polyVert_t = undefined;
            for (0..4) |i| {
                const angle = @as(f32, @floatFromInt(side + @as(usize, if (i == 1 or i == 2) 1 else 0))) * (2.0 * std.math.pi / 16.0);
                const radius = if (i < 2) near else far;
                const origin = if (i < 2) start else entity.origin2;
                vertices[i] = .{ .xyz = v.add(origin, v.add(v.scale(basis.forward, radius), v.add(v.scale(basis.right, @cos(angle) * radius), v.scale(up, @sin(angle) * radius)))), .st = @splat(0), .modulate = if (i < 2) color else .{ 0, 0, 0, 13 } };
            }
            _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, 4), &vertices });
        }
    }
    _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &entity.origin2, engine.floatArg(75), engine.floatArg(entity.angles2[0]), engine.floatArg(entity.angles2[1]), engine.floatArg(entity.angles2[2]) });
}
