// SPDX-License-Identifier: GPL-2.0-or-later
//! Replace one admitted configstring without changing any other map's indices.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
pub fn apply(game: *c.gameState_t, index: usize, value: []const u8) !void {
    if (index >= c.MAX_CONFIGSTRINGS or std.mem.indexOfScalar(u8, value, 0) != null) return error.InvalidWorldConfig;
    var result = std.mem.zeroes(c.gameState_t);
    result.dataCount = 1;
    for (0..c.MAX_CONFIGSTRINGS) |i| {
        const text = if (i == index) value else try @import("../engine/client.zig").config(game, i);
        if (text.len == 0) continue;
        const start: usize = @intCast(result.dataCount);
        if (text.len + 1 > result.stringData.len - start) return error.WorldConfigCapacity;
        result.stringOffsets[i] = @intCast(start);
        @memcpy(result.stringData[start..][0..text.len], text);
        result.dataCount += @intCast(text.len + 1);
    }
    game.* = result;
}
test "map config replacement preserves other indices and supports removal atomically" {
    const t = std.testing;
    var game = std.mem.zeroes(c.gameState_t);
    game.dataCount = 1;
    try apply(&game, 3, "old");
    try apply(&game, 7, "keep");
    try apply(&game, 3, "expanded name");
    try t.expectEqualStrings("keep", try @import("../engine/client.zig").config(&game, 7));
    try apply(&game, 3, "");
    try t.expectEqual(@as(i32, 0), game.stringOffsets[3]);
    try t.expectEqualStrings("keep", try @import("../engine/client.zig").config(&game, 7));
    const before = game;
    try t.expectError(error.InvalidWorldConfig, apply(&game, c.MAX_CONFIGSTRINGS, "bad"));
    try t.expectEqualSlices(u8, std.mem.asBytes(&before), std.mem.asBytes(&game));
}
