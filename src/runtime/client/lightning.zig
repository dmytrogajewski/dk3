// SPDX-License-Identifier: GPL-2.0-or-later
//! Continuous authoritative bolts, with bounded visual sparks on a 60 Hz clock.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const policy = @import("../domain/lightning.zig");
const Random = @import("../domain/components.zig").Random;
const Clock = struct { id: i32, tick: i64, seen_ms: i32 };
var clocks: [c.MAX_GENTITIES]?Clock = @splat(null);
pub fn reset() void { clocks = @splat(null); }
pub fn draw(entity: c.entityState_t, snapshot: []const c.entityState_t, now: i32, ref: *const c.refdef_t) void {
    if (entity.number < 0 or entity.number >= clocks.len or entity.time2 == 0) return;
    for (entity.pos.trBase ++ entity.origin2 ++ entity.angles2 ++ entity.pos.trDelta) |value| if (!std.math.isFinite(value) or @abs(value) > 1000000) return;
    if (entity.pos.trDelta[0] <= 0 or entity.pos.trDelta[1] < 0) return;
    const origin = entity.pos.trBase;
    var end = entity.origin2;
    if (entity.otherEntityNum != c.ENTITYNUM_NONE) for (snapshot) |target| if (target.number == entity.otherEntityNum) {
        end = @import("../engine/trajectory.zig").evaluate(target.pos, now); break;
    };
    const tick = @divFloor(@as(i64, now) * 60, 1000);
    const seed = @as(u32, @bitCast(entity.time2)) ^ @as(u32, @truncate(@as(u64, @bitCast(tick)) *% 0x9e3779b9));
    var random: Random = .{ .state = seed };
    var color: [4]u8 = .{ 0, 0, 0, 191 };
    for (entity.angles2, color[0..3]) |value, *channel| channel.* = @intFromFloat(std.math.clamp(value, 0, 1) * 255);
    const sparks = entity.weapon & policy.no_sparks == 0;
    arc(origin, end, entity.pos.trDelta[0] * (1 + random.next()), entity.pos.trDelta[1], color, sparks, ref, &random);
    const clock = &clocks[@intCast(entity.number)];
    if (clock.* == null or clock.*.?.id != entity.time2 or now < clock.*.?.seen_ms or now - clock.*.?.seen_ms > 250) clock.* = .{ .id = entity.time2, .tick = tick, .seen_ms = now };
    clock.*.?.seen_ms = now;
    clock.*.?.tick = @max(clock.*.?.tick, tick - 5);
    while (clock.*.?.tick <= tick) : (clock.*.?.tick += 1) {
        if (!sparks) continue;
        const direction: v.Vec3 = .{ random.next() * 2 - 1, random.next() * 2 - 1, random.next() * 2 - 1 };
        const gravity: v.Vec3 = .{ 0, 0, (random.next() * 2 - 1) * 400 };
        const kind: @import("fx_particles.zig").Kind = if (random.next() > 0.5) .sparkle1 else .sparkle2;
        @import("fx_particles.zig").cloud(end, direction, entity.angles2, .{ 0.85, 2, 0.55 }, 1 + random.next() * 2, 2, 360, 200 + random.next() * 200, gravity, 0, kind, @intCast(@divFloor(clock.*.?.tick * 1000, 60)), &random);
    }
}
fn arc(start: v.Vec3, end: v.Vec3, radius: f32, modulation: f32, color: [4]u8, fade: bool, ref: *const c.refdef_t, random: *Random) void {
    const length = v.length(v.subtract(end, start));
    const roll = random.next();
    const displacement = (20 + 40 * roll) * length / (128 + 256 * roll) * modulation;
    const bias = (displacement / 3.5 + 3.5 * roll) * modulation;
    const maximum = length / 5 + 15 * roll;
    var minimum = length / 20 + 10 * roll;
    if (minimum < displacement) minimum += displacement;
    if (length < maximum or length < 0.001) return;
    var position = start;
    var traveled: f32 = 0;
    var alpha: f32 = @floatFromInt(color[3]);
    for (0..64) |segment| {
        const final = traveled >= length - maximum or segment == 63;
        var next = end;
        if (!final) {
            const distance = minimum + random.next() * (maximum - minimum);
            next = v.add(position, v.scale(v.normalize(v.subtract(end, position)), distance));
            for (&next) |*axis| axis.* += random.next() * displacement - bias;
        }
        const distance = v.length(v.subtract(next, position));
        var from = color; from[3] = @intFromFloat(std.math.clamp(alpha, 0, 255));
        if (fade) alpha -= distance / length * @as(f32, @floatFromInt(color[3]));
        var to = color; to[3] = @intFromFloat(std.math.clamp(alpha, 0, 255));
        @import("beams.zig").gradient("dk3/fx/ion-lightning", position, next, radius, radius, from, to, ref);
        if (final) break;
        position = next; traveled += distance;
    }
}
