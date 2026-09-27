// SPDX-License-Identifier: GPL-2.0-or-later
//! Target-effect bursts retain authored particle kind and byte-direction semantics.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const particles = @import("fx_particles.zig");
const Random = @import("../domain/components.zig").Random;
const Seen = struct { id: i32 = 0, serial: i32 = 0 };
var seen: [c.MAX_GENTITIES]Seen = @splat(.{});
pub fn reset() void { seen = @splat(.{}); }
const Media = struct { kind: particles.Kind, factor: f32 };
fn media(kind: u8) Media {
    return switch (kind) {
        0 => .{ .kind = .simple, .factor = 1 },
        1 => .{ .kind = .snow, .factor = 2.3 },
        2 => .{ .kind = .rain, .factor = 2 },
        3 => .{ .kind = .blood1, .factor = 1.5 },
        4 => .{ .kind = .blood2, .factor = 1.5 },
        5 => .{ .kind = .blood3, .factor = 1.5 },
        6 => .{ .kind = .blood4, .factor = 1.5 },
        // The fifth blood enum has no initialized renderer definition in Gold.
        7 => .{ .kind = .simple, .factor = 0 },
        8 => .{ .kind = .bubble, .factor = 1.5 },
        9 => .{ .kind = .smoke, .factor = 7 },
        10 => .{ .kind = .spark, .factor = 1.5 },
        11 => .{ .kind = .spark, .factor = 3 },
        12 => .{ .kind = .poison, .factor = 1.5 },
        13 => .{ .kind = .blue_spark, .factor = 3 },
        14 => .{ .kind = .ice, .factor = 3 },
        15 => .{ .kind = .sparkle1, .factor = 3 },
        16 => .{ .kind = .sparkle2, .factor = 3 },
        17...19 => .{ .kind = .drip, .factor = 3 },
        20 => .{ .kind = .splash1, .factor = 4 },
        21 => .{ .kind = .splash2, .factor = 4 },
        22 => .{ .kind = .splash3, .factor = 4 },
        23 => .{ .kind = .beam_spark, .factor = 1.5 },
        24, 28 => .{ .kind = .fire, .factor = 3 },
        25 => .{ .kind = .cryo, .factor = 1 },
        26 => .{ .kind = .spark1, .factor = 1.5 },
        27 => .{ .kind = .spark2, .factor = 1.5 },
        29 => .{ .kind = .cp1, .factor = 1.5 },
        30 => .{ .kind = .cp2, .factor = 1.5 },
        31 => .{ .kind = .cp3, .factor = 1.5 },
        32 => .{ .kind = .cp4, .factor = 1.5 },
        else => unreachable,
    };
}
pub fn emit(entity: c.entityState_t, now: i32) void {
    if (entity.number < 0 or entity.number >= seen.len or entity.time2 == 0 or entity.frame == 0 or now < entity.time or now - entity.time > 300) return;
    for (entity.origin2 ++ entity.angles2 ++ entity.pos.trBase ++ entity.pos.trDelta ++ entity.apos.trDelta) |value| if (!std.math.isFinite(value) or @abs(value) > 1000000) return;
    if (entity.origin2[0] < 1 or entity.origin2[0] > 64 or entity.origin2[1] < 0 or entity.origin2[1] >= 33 or entity.origin2[2] < 0) return;
    const cache = &seen[@intCast(entity.number)];
    if (cache.id == entity.time2 and cache.serial == entity.frame) return;
    cache.* = .{ .id = entity.time2, .serial = entity.frame };
    var random: Random = .{ .state = @as(u32, @bitCast(entity.time2)) ^ (@as(u32, @bitCast(entity.frame)) *% 0x9e3779b9) };
    const flags: u32 = @intFromFloat(entity.origin2[2]);
    if (flags & 2 != 0) { sparks(entity, flags & 8 != 0, &random); return; }
    const selected = media(@intFromFloat(entity.origin2[1]));
    const count: usize = @intFromFloat(entity.origin2[0]);
    for (0..count) |_| particles.add(.{ .born_ms = entity.time, .position = entity.pos.trBase, .velocity = v.scale(entity.pos.trDelta, entity.angles2[0] * 10), .acceleration = .{0, 0, entity.angles2[2]}, .color = entity.apos.trDelta, .alpha = 1, .fade = 2 - random.next() * 0.75, .size = 0, .kind = selected.kind, .classic_factor = selected.factor });
}
fn integer(random: *Random, limit: u32) u32 { return @as(u32, @intFromFloat(random.next() * 2147483648)) % limit; }
fn sparks(entity: c.entityState_t, smoke: bool, random: *Random) void {
    const strength: u32 = @as(u32, @intFromFloat(@mod(@trunc(entity.angles2[1]), 256))) & 31;
    const count = (integer(random, 32) * (1 + strength)) & 63;
    const direction = v.scale(v.normalize(entity.pos.trDelta), @floatFromInt(strength * strength));
    for (0..count) |_| {
        const variation = integer(random, 8);
        const velocity = v.add(direction, .{ (random.next() * 2 - 1) * 100, (random.next() * 2 - 1) * 100, (random.next() * 2 - 1) * 100 });
        particles.add(.{ .born_ms = entity.time, .position = entity.pos.trBase, .last_position = entity.pos.trBase, .velocity = velocity, .acceleration = .{-velocity[0], -velocity[1], -250}, .color = entity.apos.trDelta, .alpha = 1, .fade = 0.5 + 0.1 * @as(f32, @floatFromInt(variation)), .size = @as(f32, @floatFromInt(variation * strength)) * 0.005, .kind = .beam_spark });
    }
    if (smoke) {
        const gray = 0.2 + 0.1 * (random.next() * 2 - 1);
        particles.add(.{ .born_ms = entity.time, .position = v.add(entity.pos.trBase, .{ random.next() * 10 - 5, random.next() * 10 - 5, random.next() * 10 - 5 }), .velocity = .{0, random.next() * 20, random.next() * 20}, .acceleration = .{0, 0, 20}, .color = @splat(gray), .alpha = 1, .fade = 1.4 + 0.2 * random.next(), .size = 2, .classic_factor = 7, .kind = .smoke });
    }
}
