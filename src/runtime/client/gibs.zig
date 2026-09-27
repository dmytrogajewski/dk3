// SPDX-License-Identifier: GPL-2.0-or-later
//! Diminishing blood trails sample actual fragment travel, independent of frame rate.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const Random = @import("../domain/components.zig").Random;
const particles = @import("fx_particles.zig");
const Trail = struct { born: i32, point: v.Vec3, count: u16 = 1024, random: Random };
var trails: [2048]?Trail = @splat(null);
pub fn reset() void { trails = @splat(null); }
pub fn emit(entity: c.entityState_t, point: v.Vec3, now: i32) void {
    if (entity.number < 0 or entity.number >= trails.len) return;
    const saved = &trails[@intCast(entity.number)];
    if (saved.* == null or saved.*.?.born != entity.time) {
        saved.* = .{ .born = entity.time, .point = point, .random = .{ .state = @as(u32, @bitCast(entity.time)) ^ (@as(u32, @intCast(entity.number)) *% 2654435761) } };
        if (entity.weapon & 4 != 0 and now >= entity.time and now - entity.time < 300) {
            for (0..2) |_| particles.add(.{ .born_ms = now, .position = point, .velocity = .{ 0, saved.*.?.random.next() * 50, saved.*.?.random.next() * 50 }, .acceleration = .{ 0, 0, 50 }, .color = @splat(1), .alpha = 1, .fade = 1.4 + saved.*.?.random.next() * 0.2, .size = 14, .kind = .smoke });
        }
    }
    const trail = &saved.*.?;
    if (entity.weapon & 2 != 0) { trail.point = point; return; }
    const distance = v.length(v.subtract(point, trail.point));
    if (distance < 2) return;
    // A discontinuity is a restoration/teleport, not a segment of flight.
    if (distance > 512) { trail.point = point; return; }
    const step = v.scale(v.normalize(v.subtract(point, trail.point)), 2);
    const spread: f32 = if (trail.count > 700) 4 else if (trail.count > 400) 2 else 1;
    const speed: f32 = if (trail.count > 700) 15 else if (trail.count > 400) 10 else 5;
    const random = &trail.random;
    for (0..@as(usize, @intFromFloat(distance / 2))) |_| {
        if (@as(u16, @intFromFloat(random.next() * 256)) & 128 < trail.count) {
            const kind: particles.Kind = @enumFromInt(@intFromEnum(particles.Kind.blood1) + @as(u8, @intFromFloat(random.next() * 4)));
            const vertical = if (random.next() > 0.7) (random.next() * 2 - 1) * speed else 0;
            particles.add(.{ .born_ms = now, .position = v.add(trail.point, .{ (random.next() * 2 - 1) * spread, (random.next() * 2 - 1) * spread, (random.next() * 2 - 1) * spread }), .velocity = .{ (random.next() * 2 - 1) * speed, (random.next() * 2 - 1) * speed, vertical }, .acceleration = .{ 0, 0, -250 }, .color = .{ 0.8, 0, 0 }, .alpha = 1, .fade = 1, .size = random.next() * 5, .kind = kind });
        }
        trail.count = @max(100, trail.count - 5);
        trail.point = v.add(trail.point, step);
    }
}
