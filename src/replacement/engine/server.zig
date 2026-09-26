// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const abi = @import("abi.zig");
const c = abi.c;
pub var gateway: abi.Gateway = .{};
pub fn print(text: [:0]const u8) void {
    _ = gateway.call(c.G_PRINT, .{text.ptr});
}
pub fn fatal(text: [:0]const u8) noreturn {
    _ = gateway.call(c.G_ERROR, .{text.ptr});
    @panic("engine error returned");
}
pub fn integer(name: [:0]const u8) i32 {
    return @intCast(gateway.call(c.G_CVAR_VARIABLE_INTEGER_VALUE, .{name.ptr}));
}
pub fn register(name: [:0]const u8, value: [:0]const u8, flags: i32) void {
    _ = gateway.call(c.G_CVAR_REGISTER, .{ @as(?*c.vmCvar_t, null), name.ptr, value.ptr, @as(isize, flags) });
}
pub fn config(index: i32, text: [:0]const u8) void {
    _ = gateway.call(c.G_SET_CONFIGSTRING, .{ @as(isize, index), text.ptr });
}
pub fn token(out: []u8) ?[]const u8 {
    if (gateway.call(c.G_GET_ENTITY_TOKEN, .{ out.ptr, @as(isize, @intCast(out.len)) }) == 0) return null;
    return std.mem.sliceTo(out, 0);
}
pub fn locate(entities: []abi.EntityProjection, players: []c.playerState_t) void {
    _ = gateway.call(c.G_LOCATE_GAME_DATA, .{ entities.ptr, @as(isize, @intCast(entities.len)), @as(isize, @sizeOf(abi.EntityProjection)), players.ptr, @as(isize, @sizeOf(c.playerState_t)) });
}
pub fn argv(index: i32, out: []u8) []const u8 {
    _ = gateway.call(c.G_ARGV, .{ @as(isize, index), out.ptr, @as(isize, @intCast(out.len)) });
    return std.mem.sliceTo(out, 0);
}

pub fn collisionService() @import("../domain/collision.zig").Collision {
    return .{ .context = &gateway, .trace_fn = trace };
}
fn trace(raw: *anyopaque, request: @import("../domain/collision.zig").Request) !@import("../domain/collision.zig").Trace {
    const engine: *abi.Gateway = @ptrCast(@alignCast(raw));
    var result: c.trace_t = undefined;
    _ = engine.call(c.G_TRACE, .{ &result, &request.start, &request.mins, &request.maxs, &request.end, @as(isize, request.slot), @as(isize, @as(i32, @bitCast(request.mask))) });
    return .{ .fraction = result.fraction, .end = result.endpos, .normal = result.plane.normal, .start_solid = result.startsolid != 0 };
}
