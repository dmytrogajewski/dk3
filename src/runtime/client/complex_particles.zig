// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored particle media and emission windows use a stable 60 Hz visual clock.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const policy = @import("../domain/complex_particles.zig");
const Random = @import("../domain/components.zig").Random;
const particles = @import("fx_particles.zig");
const Clock = struct { identity: i32, born: i32, next_tick: i64, seen_ms: i32, cadence: policy.Cadence, random: Random };
var clocks: [2048]?Clock = @splat(null);
pub fn reset() void { clocks = @splat(null); }
pub fn emit(entity: c.entityState_t, now: i32) void {
    if (entity.number < 0 or entity.number >= clocks.len) return;
    const frequency: f32 = @bitCast(entity.apos.trTime);
    const alternate: f32 = @bitCast(entity.apos.trDuration);
    for (entity.origin2 ++ entity.angles2 ++ entity.pos.trDelta ++ entity.apos.trBase ++ entity.apos.trDelta ++ [2]f32{ frequency, alternate }) |value| if (!std.math.isFinite(value) or @abs(value) > 1000000) return;
    if (frequency < 0 or alternate <= 0 or entity.origin2[2] < 1 or entity.origin2[2] > 10) return;
    const tick = @divFloor(@as(i64, now) * 60, 1000);
    const cache = &clocks[@intCast(entity.number)];
    if (cache.* == null or cache.*.?.identity != entity.time2 or cache.*.?.born != entity.time or now < cache.*.?.seen_ms or now - cache.*.?.seen_ms > 250) {
        cache.* = .{ .identity = entity.time2, .born = entity.time, .next_tick = tick, .seen_ms = now, .cadence = .{ .frequency = frequency, .alternate = alternate }, .random = .{ .state = @as(u32, @bitCast(entity.time2)) ^ @as(u32, @bitCast(entity.time)) } };
    }
    const clock = &cache.*.?;
    clock.seen_ms = now;
    clock.next_tick = @max(clock.next_tick, tick - 5);
    const flags: u32 = @bitCast(entity.weapon);
    while (clock.next_tick <= tick) : (clock.next_tick += 1) {
        if (!clock.cadence.emit(clock.next_tick, flags & 256 != 0, flags & 512 != 0, clock.random.next())) continue;
        burst(entity, @intCast(@divFloor(clock.next_tick * 1000, 60)), &clock.random);
    }
}
fn burst(entity: c.entityState_t, at: i32, random: *Random) void {
    const origin = entity.pos.trBase;
    var direction = entity.apos.trBase;
    if (std.mem.eql(f32, &direction, &origin)) direction = .{ random.next() * 2 - 1, random.next() * 2 - 1, 0 };
    const kind: particles.Kind = switch (policy.kind(@bitCast(entity.weapon))) {
        .simple => .simple, .cp1 => .cp1, .cp2 => .cp2, .cp3 => .cp3, .cp4 => .cp4, .rain => .rain, .smoke => .smoke, .bubble => .bubble,
    };
    const size = entity.angles2[1] * (1 + 0.5 * (random.next() * 2 - 1)) * 3 * (switch (kind) { .simple => @as(f32, 1), .rain => 2, .smoke => 7, else => 1.5 });
    const count: usize = @intFromFloat(entity.origin2[2]);
    const spread: f32 = @floatFromInt(entity.frame);
    const radius = entity.angles2[2];
    var jitter = spread * 0.18;
    if (jitter < 1 or jitter > 10) jitter = 1;
    const base = policy.angles(direction);
    for (0..count) |i| {
        const cone = spread * (if (radius != 0) @as(f32, 0.5) else 1);
        const flight = v.basis(v.add(base, .{ (random.next() * 2 - 1) * cone, (random.next() * 2 - 1) * cone, 0 })).forward;
        var point = origin;
        if (radius != 0) {
            // The emitter's authored radial convention rotates a swapped direction,
            // then swaps the two horizontal output axes; it is not a uniform disc.
            const radial: v.Vec3 = .{ direction[0], direction[2], direction[1] };
            const basis = v.basis(v.scale(radial, @as(f32, @floatFromInt(count - i)) * 360 / @as(f32, @floatFromInt(count))));
            const transformed = v.add(v.scale(basis.forward, radial[0]), v.add(v.scale(basis.right, radial[1]), v.scale(v.cross(basis.right, basis.forward), radial[2])));
            point = v.add(origin, v.scale(v.normalize(.{ transformed[1], transformed[0], transformed[2] }), radius));
        } else if (spread != 0) point = v.add(origin, .{ (random.next() - 0.5) * jitter, (random.next() - 0.5) * jitter, 0 });
        particles.add(.{ .born_ms = at, .position = point, .velocity = v.scale(flight, entity.angles2[0] * (0.55 + random.next() * 0.45)), .acceleration = entity.apos.trDelta, .color = entity.pos.trDelta, .alpha = entity.origin2[0], .fade = entity.origin2[1], .size = size, .kind = kind });
    }
}
