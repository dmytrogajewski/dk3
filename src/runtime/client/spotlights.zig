// SPDX-License-Identifier: GPL-2.0-or-later
//! Beam scattering is separate from surface illumination.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
pub fn draw(game: *const c.gameState_t, entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const start = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.weapon & 2 != 0) try flare(game, entity, start, ref);
    if (entity.weapon & 1 == 0) {
        if (entity.weapon & 2 == 0) {
            const brightness: f32 = @bitCast(entity.time2);
            if (std.math.isFinite(brightness) and brightness >= 0 and brightness <= 1000000) _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &start, engine.floatArg(brightness), engine.floatArg(entity.angles2[0]), engine.floatArg(entity.angles2[1]), engine.floatArg(entity.angles2[2]) });
        }
        return;
    }
    try cone(start, entity.origin2, @floatFromInt(entity.frame), entity.angles2);
}
pub fn cone(start: v.Vec3, end: v.Vec3, radius: f32, tint: v.Vec3) !void {
    try beam(start, end, radius, tint, 64);
    _ = engine.gateway.call(c.CG_R_ADDADDITIVELIGHTTOSCENE, .{ &end, engine.floatArg(75), engine.floatArg(tint[0]), engine.floatArg(tint[1]), engine.floatArg(tint[2]) });
}
pub fn beam(start: v.Vec3, end: v.Vec3, radius: f32, tint: v.Vec3, opacity: u8) !void {
    const direction = v.subtract(end, start);
    const basis = v.basis(.{ -std.math.atan2(direction[2], @sqrt(direction[0] * direction[0] + direction[1] * direction[1])) * 180 / std.math.pi, std.math.atan2(direction[1], direction[0]) * 180 / std.math.pi, 0 });
    const up = v.cross(basis.right, basis.forward);
    const distance = v.length(direction);
    var color: [4]u8 = .{ 255, 255, 255, opacity };
    for (tint, color[0..3]) |channel, *out| out.* = @intFromFloat(std.math.clamp(channel, 0, 1) * 255);
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/spotlight")});
    for (0..2) |layer| {
        const scale: f32 = if (layer == 0) 1 else 2.0 / 3.0;
        const near = radius * scale;
        const far = near + distance * 0.2 * scale;
        for (0..16) |side| {
            var vertices: [4]c.polyVert_t = undefined;
            for (0..4) |i| {
                const angle = @as(f32, @floatFromInt(side + @as(usize, if (i == 1 or i == 2) 1 else 0))) * (2.0 * std.math.pi / 16.0);
                const width = if (i < 2) near else far;
                const origin = if (i < 2) start else end;
                vertices[i] = .{ .xyz = v.add(origin, v.add(v.scale(basis.right, @cos(angle) * width), v.scale(up, @sin(angle) * width))), .st = @splat(0), .modulate = if (i < 2) color else .{ 0, 0, 0, 0 } };
            }
            _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, 4), &vertices });
        }
    }
}

fn flare(game: *const c.gameState_t, entity: c.entityState_t, point: v.Vec3, ref: *const c.refdef_t) !void {
    if (entity.modelindex <= 0 or entity.modelindex >= c.MAX_MODELS) return;
    const delta = v.subtract(ref.vieworg, point);
    const distance = v.length(delta);
    const hit = try engine.collisionService().trace(.{ .start = ref.vieworg, .end = point, .mins = @splat(0), .maxs = @splat(0), .slot = c.ENTITYNUM_NONE, .mask = c.MASK_SOLID });
    if (hit.start_solid or hit.all_solid or (1 - hit.fraction) * distance > 16) return;
    const half = @floor(@floor(distance) / 2);
    const alpha = std.math.clamp(1 - half / 512, 0, 1);
    if (alpha == 0) return;
    const model = try engine.config(game, @intCast(c.CS_MODELS + entity.modelindex));
    const sprites = @import("sprites.zig");
    const media = try sprites.register(model);
    const color: [4]u8 = .{ 255, 255, 255, @intFromFloat(alpha * 255) };
    sprites.drawPlane(media, 0, v.add(point, v.scale(v.normalize(delta), half)), 1 + alpha, false, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], color);
}
