// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied model frame sequences, independent of renderer and simulation storage.
const std = @import("std");
pub const Sequence = struct {
    first: u16 = 0,
    last: u16 = 0,
    fps: u16 = 10,
    pub fn frame(self: Sequence, elapsed_ms: i64, looping: bool) u16 {
        const count: u64 = self.last - self.first + 1;
        const elapsed: u64 = @intCast(@max(0, elapsed_ms));
        const step = elapsed / 1000 * self.fps + elapsed % 1000 * self.fps / 1000;
        return self.first + @as(u16, @intCast(if (looping) step % count else @min(step, count - 1)));
    }
};
pub fn find(bytes: []const u8, name: []const u8) !?Sequence {
    var words = std.mem.tokenizeAny(u8, bytes, " \t\r\n\"");
    if (!std.mem.eql(u8, words.next() orelse return error.InvalidAnimation, "dk3_animation")) return error.InvalidAnimation;
    if (!std.mem.eql(u8, words.next() orelse return error.InvalidAnimation, "1")) return error.InvalidAnimation;
    const frames = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidAnimation, 10);
    var selected: ?Sequence = null;
    while (words.next()) |sequence_name| {
        const first = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidAnimation, 10);
        const last = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidAnimation, 10);
        const fps = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidAnimation, 10);
        if (last < first or last >= frames or fps == 0 or fps > 240) return error.InvalidAnimation;
        if (std.mem.eql(u8, sequence_name, name)) {
            if (selected != null) return error.DuplicateAnimation;
            selected = .{ .first = first, .last = last, .fps = fps };
        }
    }
    return selected;
}
test "animation timing follows elapsed time and death holds its final frame" {
    const sequence = (try find("dk3_animation 1\n20\n\"diea\" 5 12 10\n", "diea")).?;
    try std.testing.expectEqual(@as(u16, 8), sequence.frame(350, false));
    try std.testing.expectEqual(@as(u16, 12), sequence.frame(10000, false));
    try std.testing.expectEqual(@as(u16, 7), sequence.frame(1000, true));
    try std.testing.expectError(error.InvalidAnimation, find("dk3_animation 1 20 \"diea\" 5 20 10", "diea"));
}
