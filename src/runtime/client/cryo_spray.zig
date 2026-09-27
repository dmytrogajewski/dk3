// SPDX-License-Identifier: GPL-2.0-or-later
//! Seeded spray particles share the original atlas rectangle and physical units.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
pub fn draw(entity: c.entityState_t, now: i64, ref: *const c.refdef_t) void {
    const seconds = @as(f32, @floatFromInt(now - entity.time)) * 0.001;
    if (seconds < 0 or seconds >= 1.5) return;
    const shader = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/cryo-spray")});
    const basis = v.basis(entity.angles2);
    const up = v.cross(basis.right, basis.forward);
    var random: @import("../domain/components.zig").Random = .{ .state = @bitCast(entity.frame) };
    const fade = @max(0, seconds - 0.5);
    const color: [4]u8 = .{ 8, 204, 255, @intFromFloat(255 * (0.4 - fade * 0.4)) };
    for (0..35) |_| {
        const cone = random.next() * 5 * std.math.pi / 180;
        const rotation = random.next() * 2 * std.math.pi;
        const speed = 200 + random.next() * 75;
        const direction = v.add(v.scale(basis.forward, @cos(cone)), v.add(v.scale(basis.right, @sin(cone) * @cos(rotation)), v.scale(up, @sin(cone) * @sin(rotation))));
        const origin = v.add(entity.origin2, v.scale(direction, speed * seconds));
        // Native growth is time-based. The reference adds a unit per render frame.
        const size = (14 + (random.next() * 2 - 1) * 6 + fade * 60) * 0.5;
        var vertices: [4]c.polyVert_t = undefined;
        for ([_][4]f32{ .{ -1, -1, 0, 1 }, .{ 1, -1, 1, 1 }, .{ 1, 1, 1, 0 }, .{ -1, 1, 0, 0 } }, &vertices) |corner, *vertex| {
            vertex.* = .{ .xyz = v.add(origin, v.add(v.scale(ref.viewaxis[1], corner[0] * size), v.scale(ref.viewaxis[2], corner[1] * size))), .st = .{ corner[2], corner[3] }, .modulate = color };
        }
        _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ shader, @as(isize, 4), &vertices });
    }
}
