// SPDX-License-Identifier: GPL-2.0-or-later
// Default light animation samples: Copyright (C) 1997-2001 Id Software, Inc.
// GPL-2.0-or-later, Quake-2 game/g_spawn.c at 372afde46e7defc9dd2d719a1732b8ace1fa096e.
// Source and review: docs/provenance.md, sequence 275.
//! Lightstyle transport and class-owned ramp state. Default samples match shadergen.py.
const std = @import("std");
pub const render_tag = 10036;
pub const Kind = enum { light, spot, strobe, flare, flame };
pub const Light = struct {
    kind: Kind,
    enabled: bool = true,
    switchable: bool = false,
    style: u8 = 0,
    pattern: []const u8 = "",
    level: ?u8 = null,
    revision: u64 = 0,
    phase_ms: i64 = 0,
    model: []const u8 = "",
    scale: [3]f32 = @splat(1),
};
pub const Ramp = struct {
    from: u8,
    to: u8,
    duration_ms: i64 = 1000,
    started_ms: i64 = 0,
    next_ms: ?i64 = null,
    target: u32 = 0,
    reverse: bool = false,
    pub fn sample(self: Ramp, now: i64) u8 {
        const fraction = @as(f32, @floatFromInt(now - self.started_ms)) / @as(f32, @floatFromInt(self.duration_ms));
        return @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(self.from)) + fraction * (@as(f32, @floatFromInt(self.to)) - @as(f32, @floatFromInt(self.from))), 0, 48));
    }
};
pub fn sample(pattern: []const u8, age_ms: i64) u8 {
    if (pattern.len == 0) return 12;
    const index: usize = @intCast(@mod(@divFloor(age_ms, 100), @as(i64, @intCast(pattern.len))));
    return @intCast(std.math.clamp(@as(i32, pattern[index]) - 'a', 0, 48));
}
pub fn defaults(now: i64) [256]u8 {
    var result: [256]u8 = @splat(12);
    result[0] = sample("m", now);
    result[1] = sample("mmnmmommommnonmmonqnmmo", now);
    result[2] = sample("abcdefghijklmnopqrstuvwxyzyxwvutsrqponmlkjihgfedcba", now);
    result[3] = sample("mmmmmaaaaammmmmaaaaaabcdefgabcdefg", now);
    result[4] = sample("mamamamamama", now);
    result[5] = sample("jklmnopqrstuvwxyzyxwvutsrqponmlkj", now);
    result[6] = sample("nmonqnmomnmomomno", now);
    result[7] = sample("mmmaaaabcdefgmmmmaaaammmaamm", now);
    result[8] = sample("mmmaaammmaaammmabcdefaaaammmmabcdefmmmaaaa", now);
    result[9] = sample("aaaaaaaazzzzzzzz", now);
    result[10] = sample("mmamammmmammamamaaamammma", now);
    result[11] = sample("abcdefghijklmnopqrrqponmlkjihgfedcba", now);
    result[63] = sample("a", now);
    return result;
}
pub fn encode(values: [256]u8) [514:0]u8 {
    var text: [514:0]u8 = undefined;
    text[0] = '1'; text[1] = ':';
    const hex = "0123456789abcdef";
    for (values, 0..) |level, i| { text[2 + i * 2] = hex[level >> 4]; text[3 + i * 2] = hex[level & 15]; }
    text[514] = 0;
    return text;
}
pub fn decode(text: []const u8) ![256]f32 {
    if (text.len != 514 or !std.mem.startsWith(u8, text, "1:")) return error.InvalidLightstyles;
    var result: [256]f32 = undefined;
    for (&result, 0..) |*out, i| {
        const level = std.fmt.parseInt(u8, text[2 + i * 2 .. 4 + i * 2], 16) catch return error.InvalidLightstyles;
        if (level > 48) return error.InvalidLightstyles;
        out.* = @as(f32, @floatFromInt(level)) / 12;
    }
    return result;
}
test "light ramps retain direction, do not force their endpoint early, and transport full intensity range" {
    const t = std.testing;
    const ramp: Ramp = .{ .from = 0, .to = 25, .started_ms = 1000 };
    try t.expectEqual(@as(u8, 12), ramp.sample(1500));
    try t.expectEqual(@as(u8, 25), ramp.sample(2000));
    try t.expectEqual(@as(u8, 27), ramp.sample(2100));
    var levels = defaults(0);
    levels[32] = 0; levels[33] = 25; levels[34] = 48;
    const encoded = encode(levels);
    const decoded = try decode(&encoded);
    try t.expectEqual(@as(f32, 0), decoded[32]);
    try t.expectApproxEqAbs(@as(f32, 25.0 / 12.0), decoded[33], 0.0001);
    try t.expectEqual(@as(f32, 4), decoded[34]);
    try t.expectEqual(@as(u8, 0), sample("10", 0));
    try t.expectEqual(sample("amb", 500), sample("amb", 3500));
}
