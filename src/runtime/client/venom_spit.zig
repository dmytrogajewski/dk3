// SPDX-License-Identifier: GPL-2.0-or-later
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
var trails: [2048]struct { serial: i32 = -1, next: i64 = 0 } = @splat(.{});
pub fn reset() void {
    trails = @splat(.{});
}
pub fn draw(entity: c.entityState_t, now: i32) void {
    if (entity.weapon != 1 or entity.number < 0 or entity.number >= trails.len) return;
    const point = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    const trail = &trails[@intCast(entity.number)];
    const tick = @divTrunc(@as(i64, now) * 60, 1000);
    if (trail.serial != entity.time or trail.next > tick + 1) trail.* = .{ .serial = entity.time, .next = tick };
    trail.next = @max(trail.next, tick - 5);
    while (trail.next <= tick) : (trail.next += 1) {
        const at: i32 = @intCast(@divTrunc(trail.next * 1000, 60));
        var random: Random = .{ .state = @as(u32, @bitCast(at)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) };
        var direction: v.Vec3 = undefined;
        for (&direction) |*axis| axis.* = random.next() * 2 - 1;
        @import("fx_particles.zig").cloud(point, v.normalize(direction), .{ 0.30, 0.85, 0.05 }, .{ 0.85, 0.45, 0.20 }, 1.25 + random.next(), 3, 180, 60, .{ 0, 0, -400 }, 0, .fire, at, &random);
        for (&direction) |*axis| axis.* = random.next() * 2 - 1;
        @import("fx_particles.zig").cloud(point, v.normalize(direction), .{ 0.20, 0.55, 0.01 }, .{ 0.35, 0.65, 0.20 }, 1 + random.next() * 0.5, 1, 1, 2, .{ 0, 0, -20 }, 0, .smoke, at, &random);
    }
}
