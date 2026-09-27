// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../engine/abi.zig").c;
const std = @import("std");
const engine = @import("../engine/client.zig");
const v = @import("../domain/vector.zig");
var collected: [2048]i32 = @splat(0);
pub fn reset() void {
    collected = @splat(0);
}
pub fn draw(entity: c.entityState_t, now: i32, ref: *const c.refdef_t) !void {
    const point = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    if (entity.time2 > 0) {
        const sprite = try @import("sprites.zig").register(@import("actor_catalog").wisp.model);
        @import("sprites.zig").drawPlane(sprite, 0, point, entity.angles2[0], false, v.scale(ref.viewaxis[1], -1), ref.viewaxis[2], .{ 255, 255, 255, @intCast(std.math.clamp(entity.time2, 0, 255)) });
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &point, engine.floatArg(135), engine.floatArg(0.35), engine.floatArg(0.35), engine.floatArg(0.75) });
    }
    if (entity.number < 0 or entity.number >= collected.len or entity.time <= 0) return;
    const previous = &collected[@intCast(entity.number)];
    if (previous.* == entity.time) return;
    previous.* = entity.time;
    if (now < entity.time or now - entity.time > 300) return;
    var random: @import("../domain/components.zig").Random = .{ .state = @as(u32, @bitCast(entity.time)) ^ @as(u32, @intCast(entity.number)) };
    const offsets = [_]v.Vec3{ .{ 4, 0, 0 }, .{ 0, 4, 0 }, .{ -4, 0, 0 }, .{ 0, -4, 0 } };
    const speeds = [_]f32{ 60, 40, 80, 50 };
    for (offsets, speeds, 0..) |offset, speed, i| for (0..7) |_| {
        const drift = @floor(random.next() * 8);
        const jitter: v.Vec3 = .{ @floor(random.next() * 8) - 4, @floor(random.next() * 8) - 4, @floor(random.next() * 8) - 4 + drift };
        @import("fx_particles.zig").add(.{ .born_ms = entity.time, .position = v.add(v.add(entity.angles, offset), jitter), .velocity = .{ 0, 0, speed }, .acceleration = .{ 0, 0, 125 }, .color = .{ 0.35, 0.35, 0.85 }, .alpha = 1, .fade = 2 - random.next() * 0.75, .size = if (i % 2 == 0) 2 else 7, .kind = if (i % 2 == 0) .spark else .smoke });
    };
}
