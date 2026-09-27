// SPDX-License-Identifier: GPL-2.0-or-later
//! Station sparkles and fountain spray use the supplied particle atlas.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const policy = @import("item_catalog").hosportal;
fn particle(shader: isize, point: v.Vec3, radius: f32, color: [4]u8) void {
    var ref = std.mem.zeroes(c.refEntity_t);
    ref.reType = c.RT_SPRITE;
    ref.customShader = @intCast(shader);
    ref.origin = point;
    ref.radius = radius;
    ref.shaderRGBA = color;
    _ = engine.gateway.call(c.CG_R_ADDREFENTITYTOSCENE, .{&ref});
}
pub fn draw(entity: c.entityState_t, now: i32) void {
    if (entity.time2 == 0) return;
    const age = @as(f32, @floatFromInt(now - entity.time)) * 0.001;
    const fountain = entity.weapon == @intFromEnum(policy.Kind.fountain);
    if (age < 0 or age >= (if (fountain) @as(f32, 1.8) else 5)) return;
    const origin = @import("../engine/trajectory.zig").evaluate(entity.pos, now);
    var random: @import("../domain/components.zig").Random = .{ .state = @as(u32, @intCast(entity.number)) *% 1664525 +% @as(u32, @bitCast(entity.time)) };
    if (!fountain) {
        const first = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/healer-sparkle-1")});
        const second = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/healer-sparkle-2")});
        for (0..128) |_| {
            const x = random.next() * 32 - 16;
            const y = random.next() * 32 - 16;
            const z = random.next() * 52 - 20;
            const initial = @sqrt(x * x + y * y);
            const radius = initial - 5 * age;
            const period = 0.05 + random.next() * 0.75;
            const phase = random.next() * std.math.pi;
            if (radius < 3) continue;
            // Integrate the class's 20-unit tangent and five-unit inward velocity.
            const angle = std.math.atan2(y, x) + 4 * @log(initial / radius);
            const point = v.add(origin, .{ @cos(angle) * radius, @sin(angle) * radius, z });
            particle(if (@mod(@floor(age / period), 2) == 0) first else second, point, 3 * (1 + @sin(phase + age * 5)), .{ 255, 255, 255, @intFromFloat(@sin(age * std.math.pi / 5) * 255) });
        }
    } else {
        const water = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/healer-water")});
        const mist = engine.gateway.call(c.CG_R_REGISTERSHADER, .{@as([*:0]const u8, "dk3/fx/healer-mist")});
        _ = engine.gateway.call(c.CG_R_ADDLIGHTTOSCENE, .{ &origin, engine.floatArg(95), engine.floatArg(0.005), engine.floatArg(0), engine.floatArg(0.7) });
        for (0..70) |index| {
            const elapsed = @mod(age + random.next() * 1.4, 1.4);
            const is_mist = index >= 40;
            const angle = random.next() * (2 * std.math.pi);
            const spread = random.next() * 7;
            const lateral: f32 = if (is_mist) 30 else 5;
            const direction: v.Vec3 = .{ (random.next() * 2 - 1) * lateral, (random.next() * 2 - 1) * lateral, if (is_mist) 30 else 70 };
            const point = v.add(v.add(origin, .{ @cos(angle) * spread, @sin(angle) * spread, 6 - 50 * elapsed * elapsed }), v.scale(direction, elapsed));
            const alpha = @max(0, 0.65 - 0.45 * elapsed);
            particle(if (is_mist) mist else water, point, if (is_mist) 7 else 1.5, .{ 64, 115, 166, @intFromFloat(alpha * 255) });
        }
    }
}
