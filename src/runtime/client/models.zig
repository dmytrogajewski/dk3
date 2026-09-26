// SPDX-License-Identifier: GPL-2.0-or-later
//! Configstring model cache; converted source assets remain supplied locally.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var names: [c.MAX_MODELS][c.MAX_QPATH]u8 = undefined;
var handles: [c.MAX_MODELS]c.qhandle_t = @splat(0);
pub fn reset() void {
    @memset(std.mem.asBytes(&names), 0);
    @memset(&handles, 0);
}
pub fn get(game: *const c.gameState_t, index: i32) !c.qhandle_t {
    if (index <= 0 or index >= c.MAX_MODELS) return 0;
    const i: usize = @intCast(index);
    const name = try engine.config(game, c.CS_MODELS + i);
    if (name.len == 0) return 0;
    if (name.len >= c.MAX_QPATH) return error.InvalidModelPath;
    if (std.mem.eql(u8, name, std.mem.sliceTo(&names[i], 0))) return handles[i];
    var buffer: [c.MAX_QPATH + 5]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buffer, "{s}{s}", .{ name, if (std.mem.endsWith(u8, name, ".dkm")) @as([]const u8, ".md3") else "" });
    handles[i] = @intCast(engine.gateway.call(c.CG_R_REGISTERMODEL, .{path.ptr}));
    @memcpy(names[i][0..name.len], name);
    names[i][name.len] = 0;
    return handles[i];
}
