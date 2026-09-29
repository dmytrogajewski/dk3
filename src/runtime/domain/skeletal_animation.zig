// SPDX-License-Identifier: GPL-2.0-or-later
//! Cosmetic skeletal clips retain their own cycle rate. One-shot performances
//! retain the authoritative animation duration so contact events remain aligned.
const std = @import("std");
pub const Clip = struct { first: u16, last: u16, rate: u16 };
pub const Sample = struct { frame: u16, oldframe: u16, backlerp: f32 };
pub fn sample(clip: Clip, source_count: u32, source_rate: u16, elapsed_ms: i64, looping: bool, reverse: bool) Sample {
    const count: u32 = @as(u32, clip.last) - clip.first + 1;
    const elapsed: f64 = @floatFromInt(@max(0, elapsed_ms));
    const rate = if (clip.rate > 0) @as(f64, @floatFromInt(clip.rate)) else @as(f64, @floatFromInt(count * source_rate)) / @as(f64, @floatFromInt(source_count));
    const cycle = elapsed * rate * 0.001;
    const phase = if (looping) @mod(cycle, @as(f64, @floatFromInt(count))) else @min(cycle, @as(f64, @floatFromInt(count - 1)));
    const old: u16 = @intFromFloat(@floor(phase));
    const next: u16 = if (@as(u32, old) + 1 < count) old + 1 else if (looping) 0 else old;
    return .{ .oldframe = if (reverse) clip.last - old else clip.first + old, .frame = if (reverse) clip.last - next else clip.first + next, .backlerp = @floatCast(1 - (phase - @floor(phase))) };
}
test "locomotion cadence does not stretch with an authored frame range" {
    const clip: Clip = .{ .first = 500, .last = 514, .rate = 30 };
    const a = sample(clip, 14, 10, 250, true, false);
    const b = sample(clip, 40, 10, 250, true, false);
    try std.testing.expectEqualDeep(a, b);
    try std.testing.expectEqual(@as(u16, 507), a.oldframe);
    try std.testing.expectEqual(@as(f32, 0.5), a.backlerp);
    try std.testing.expectEqual(@as(u16, 500), sample(clip, 14, 10, 500, true, false).oldframe);
}
test "one-shot contact phase and final holds retain authoritative timing" {
    const clip: Clip = .{ .first = 500, .last = 523, .rate = 0 };
    try std.testing.expectEqual(@as(u16, 512), sample(clip, 10, 10, 500, false, false).oldframe);
    try std.testing.expectEqual(@as(u16, 523), sample(clip, 10, 10, 10000, false, false).frame);
    try std.testing.expectEqual(@as(u16, 500), sample(clip, 10, 10, -100, false, false).oldframe);
    try std.testing.expectEqual(@as(u16, 500), sample(clip, 10, 10, 10000, false, true).frame);
}
