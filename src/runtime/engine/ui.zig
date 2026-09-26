// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const abi = @import("abi.zig");
pub const c = abi.c;
pub var gateway: abi.Gateway = .{};
pub const draw: @import("canvas.zig").Canvas(.ui) = .{ .gateway = &gateway };
pub fn get(name: [:0]const u8, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = gateway.call(c.UI_CVAR_VARIABLESTRINGBUFFER, .{ name.ptr, buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn number(name: [:0]const u8) f32 {
    var buffer: [128]u8 = undefined;
    const value = std.fmt.parseFloat(f32, get(name, &buffer)) catch return 0;
    return if (std.math.isFinite(value)) value else 0;
}
pub fn set(name: [:0]const u8, value: [:0]const u8) void {
    _ = gateway.call(c.UI_CVAR_SET, .{ name.ptr, value.ptr });
}
pub fn setNumber(name: [:0]const u8, value: f32) void {
    _ = gateway.call(c.UI_CVAR_SETVALUE, .{ name.ptr, @as(isize, @as(i32, @bitCast(value))) });
}
pub fn register(name: [:0]const u8, value: [:0]const u8) void {
    _ = gateway.call(c.UI_CVAR_REGISTER, .{ @as(?*c.vmCvar_t, null), name.ptr, value.ptr, @as(isize, c.CVAR_ARCHIVE) });
}
pub fn execute(command: [:0]const u8) void {
    _ = gateway.call(c.UI_CMD_EXECUTETEXT, .{ @as(isize, c.EXEC_APPEND), command.ptr });
}
pub fn print(message: [:0]const u8) void {
    _ = gateway.call(c.UI_PRINT, .{message.ptr});
}
pub fn sound(path: [:0]const u8) void {
    const handle = gateway.call(c.UI_S_REGISTERSOUND, .{ path.ptr, @as(isize, c.qfalse) });
    _ = gateway.call(c.UI_S_STARTLOCALSOUND, .{ handle, @as(isize, c.CHAN_LOCAL_SOUND) });
}
pub fn binding(key: i32, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = gateway.call(c.UI_KEY_GETBINDINGBUF, .{ @as(isize, key), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn bind(key: i32, command: [:0]const u8) void {
    _ = gateway.call(c.UI_KEY_SETBINDING, .{ @as(isize, key), command.ptr });
}
pub fn keyName(key: i32, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = gateway.call(c.UI_KEY_KEYNUMTOSTRINGBUF, .{ @as(isize, key), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn client() c.uiClientState_t {
    var value: c.uiClientState_t = undefined;
    _ = gateway.call(c.UI_GETCLIENTSTATE, .{&value});
    return value;
}
pub fn inGame() bool {
    return client().connState == c.CA_ACTIVE;
}
pub fn catchInput(active: bool) void {
    const prior = gateway.call(c.UI_KEY_GETCATCHER, .{});
    _ = gateway.call(c.UI_KEY_SETCATCHER, .{if (active) prior | c.KEYCATCH_UI else prior & ~@as(isize, c.KEYCATCH_UI)});
    if (!active) _ = gateway.call(c.UI_KEY_CLEARSTATES, .{});
    set("cl_paused", if (active and inGame() and number("g_gametype") == c.GT_SINGLE_PLAYER) "1" else "0");
}
