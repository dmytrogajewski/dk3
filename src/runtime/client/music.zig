// SPDX-License-Identifier: GPL-2.0-or-later
//! Music starts only when the server's authored track changes.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var current: [128]u8 = @splat(0);
pub fn reset() void { @memset(&current, 0); }
pub fn update(game: *const c.gameState_t) !void {
    const value = try engine.config(game, c.CS_MUSIC);
    if (std.mem.eql(u8, value, std.mem.sliceTo(&current, 0))) return;
    if (value.len >= current.len) return error.InvalidMusicConfiguration;
    @memset(&current, 0);
    @memcpy(current[0..value.len], value);
    var parts = std.mem.tokenizeScalar(u8, value, ' ');
    const path = parts.next() orelse {
        _ = engine.gateway.call(c.CG_S_STOPBACKGROUNDTRACK, .{});
        return;
    };
    const volume = try std.fmt.parseFloat(f32, parts.next() orelse "1");
    if (!std.math.isFinite(volume) or volume < 0 or volume > 1) return error.InvalidMusicVolume;
    if (volume == 0) {
        _ = engine.gateway.call(c.CG_S_STOPBACKGROUNDTRACK, .{});
        return;
    }
    // Supplied map/trigger tracks use full authored volume. The user's mixer
    // volume stays authoritative; do not rewrite their settings during gameplay.
    var name: [c.MAX_QPATH]u8 = undefined;
    const file = try std.fmt.bufPrintZ(&name, "{s}", .{path});
    _ = engine.gateway.call(c.CG_S_STARTBACKGROUNDTRACK, .{ file.ptr, file.ptr });
}
