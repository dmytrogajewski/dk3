// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const particles = @import("fx_particles.zig");
const data = @import("../domain/components.zig");
const Clock = struct { id: i32 = 0, tick: i32 = -1, random: data.Random = .{ .state = 1 } };
var clocks: [c.MAX_GENTITIES]Clock = @splat(.{});
pub fn reset() void {
    clocks = @splat(.{});
}
pub fn emit(entity: c.entityState_t, now: i32) void {
    if (entity.number < 0 or entity.number >= clocks.len or entity.time2 == 0 or now < entity.time or now >= entity.time + 500) return;
    for (entity.origin2 ++ entity.pos.trBase) |axis| if (!std.math.isFinite(axis) or @abs(axis) > 1048576) return;
    const clock = &clocks[@intCast(entity.number)];
    if (clock.id != entity.time2) clock.* = .{ .id = entity.time2, .random = .{ .state = @bitCast(entity.time2) } };
    const end = @divTrunc((now - entity.time) * 60, 1000);
    clock.tick = @max(clock.tick, end - 6);
    while (clock.tick < end) {
        clock.tick += 1;
        const random = &clock.random;
        const at = entity.time + @divTrunc(clock.tick * 1000, 60);
        var point = entity.pos.trBase;
        for (&point, entity.origin2, 0..) |*axis, extent, i| axis.* += (random.next() * 2 - 1) * extent * (if (i == 2) @as(f32, 0.5) else 0.85);
        const direction: data.Vec3 = .{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 };
        const size = if (entity.origin2[0] > 100) @as(f32, 1) else entity.origin2[0] / 85;
        particles.cloud(point, direction, .{ 0.2, -0.65, -0.65 }, .{ 0.45, 1.65, 0.1 }, 1.5 + 80 * size, 2, 360, 100, .{ 0, 0, -100 }, 5, .smoke, at, random);
        particles.cloud(point, direction, .{ 0.2, -1, -1 }, .{ 0.55, 0.8, 0.1 }, 5.5 + 80 * size, 3, 35, 50, .{ 0, 0, -100 }, 5, .cp4, at, random);
    }
}
