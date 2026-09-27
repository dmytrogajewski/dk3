// SPDX-License-Identifier: GPL-2.0-or-later
//! Configstring model cache; converted source assets remain supplied locally.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var names: [c.MAX_MODELS][c.MAX_QPATH]u8 = undefined;
var handles: [c.MAX_MODELS]c.qhandle_t = @splat(0);
var player_skins: [c.MAX_CLIENTS]struct { name: [c.MAX_QPATH]u8 = @splat(0), handle: c.qhandle_t = 0 } = @splat(.{});
pub fn reset() void {
    player_skins = @splat(.{});
    @memset(std.mem.asBytes(&names), 0);
    @memset(&handles, 0);
}
pub fn register(name: []const u8) !c.qhandle_t {
    var buffer: [c.MAX_QPATH + 5]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buffer, "{s}{s}", .{ name, if (std.mem.endsWith(u8, name, ".dkm")) @as([]const u8, ".md3") else "" });
    return @intCast(engine.gateway.call(c.CG_R_REGISTERMODEL, .{path.ptr}));
}
pub fn get(game: *const c.gameState_t, index: i32) !c.qhandle_t {
    if (index <= 0 or index >= c.MAX_MODELS) return 0;
    const i: usize = @intCast(index);
    const name = try engine.config(game, c.CS_MODELS + i);
    if (name.len == 0) return 0;
    if (name.len >= c.MAX_QPATH) return error.InvalidModelPath;
    if (std.mem.eql(u8, name, std.mem.sliceTo(&names[i], 0))) return handles[i];
    handles[i] = try register(name);
    @memcpy(names[i][0..name.len], name);
    names[i][name.len] = 0;
    return handles[i];
}

pub fn playerSkin(game: *const c.gameState_t, slot: i32) !c.qhandle_t {
    if (slot < 0 or slot >= c.MAX_CLIENTS) return 0;
    const info = try engine.config(game, @as(usize, c.CS_PLAYERS) + @as(usize, @intCast(slot)));
    const name = engine.info(info, "skin") orelse return 0;
    if (name.len == 0 or name.len >= c.MAX_QPATH) return error.InvalidPlayerSkin;
    var admitted = false;
    for (@import("appearance_catalog").entries) |entry| if (std.mem.eql(u8, entry.skin, name)) {
        admitted = true;
        break;
    };
    if (!admitted) return error.UnknownPlayerSkin;
    const skin = &player_skins[@intCast(slot)];
    if (!std.mem.eql(u8, std.mem.sliceTo(&skin.name, 0), name)) {
        @memset(&skin.name, 0);
        @memcpy(skin.name[0..name.len], name);
        skin.handle = @intCast(engine.gateway.call(c.CG_R_REGISTERSKIN, .{&skin.name}));
        if (skin.handle == 0) return error.PlayerSkinUnavailable;
    }
    return skin.handle;
}
