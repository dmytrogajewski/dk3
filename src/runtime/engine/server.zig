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
/// True means the native regional stream owns publication of this change.
pub var config_observer: ?*const fn (i32) bool = null;
pub fn config(index: i32, text: [:0]const u8) void {
    if (config_observer != null) {
        var previous: [c.MAX_GAMESTATE_CHARS]u8 = undefined;
        _ = gateway.call(c.G_GET_CONFIGSTRING, .{ @as(isize, index), &previous, @as(isize, previous.len) });
        if (std.mem.eql(u8, std.mem.sliceTo(&previous, 0), text)) return;
    }
    const queued = if (config_observer) |observer| observer(index) else false;
    _ = gateway.call(if (queued) c.G_DK3_WORLD_CONFIGSTRING_V1 else c.G_SET_CONFIGSTRING, .{ @as(isize, index), text.ptr });
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
    return .{ .context = &gateway, .trace_fn = trace, .contents_fn = contents };
}
fn trace(raw: *anyopaque, request: @import("../domain/collision.zig").Request) !@import("../domain/collision.zig").Trace {
    const engine: *abi.Gateway = @ptrCast(@alignCast(raw));
    var result: c.trace_t = undefined;
    _ = engine.call(c.G_TRACE, .{ &result, &request.start, &request.mins, &request.maxs, &request.end, @as(isize, request.slot), @as(isize, @as(i32, @bitCast(request.mask))) });
    return .{ .fraction = result.fraction, .contents = @bitCast(result.contents), .sky = result.surfaceFlags & c.SURF_SKY != 0, .end = result.endpos, .normal = result.plane.normal, .start_solid = result.startsolid != 0, .all_solid = result.allsolid != 0, .entity = @intCast(result.entityNum), .holy = result.surfaceFlags & c.SURF_DK_HOLY != 0, .slick = result.surfaceFlags & c.SURF_SLICK != 0, .ladder = result.surfaceFlags & c.SURF_LADDER != 0, .no_impact = result.surfaceFlags & c.SURF_NOIMPACT != 0, .material = if (result.surfaceFlags & c.SURF_DK_WOOD != 0) .wood else if (result.surfaceFlags & c.SURF_METALSTEPS != 0) .metal else .ordinary };
}

fn contents(raw: *anyopaque, point: @import("../domain/components.zig").Vec3, skip: u16) !u32 {
    const engine: *abi.Gateway = @ptrCast(@alignCast(raw));
    return @bitCast(@as(i32, @intCast(engine.call(c.G_POINT_CONTENTS, .{ &point, @as(isize, skip) }))));
}
pub fn usercmd(index: u16, out: *c.usercmd_t) void {
    _ = gateway.call(c.G_GET_USERCMD, .{ @as(isize, index), out });
}
pub fn link(entity: *abi.EntityProjection) void {
    _ = gateway.call(c.G_LINKENTITY, .{entity});
}
pub fn unlink(entity: *abi.EntityProjection) void {
    _ = gateway.call(c.G_UNLINKENTITY, .{entity});
}

pub fn send(client: u16, command: [:0]const u8) void {
    _ = gateway.call(c.G_SEND_SERVER_COMMAND, .{ @as(isize, client), command.ptr });
}
pub fn inPvs(a: [3]f32, b: [3]f32) bool {
    return gateway.call(c.G_IN_PVS, .{ &a, &b }) != 0;
}

pub fn inPhs(a: [3]f32, b: [3]f32) bool {
    return gateway.call(c.G_DK3_IN_PHS, .{ &a, &b }) != 0;
}

/// Name of the explicitly selected game world, independent of connection cvars.
pub fn mapName(buffer: []u8) []const u8 {
    @memset(buffer, 0);
    std.debug.assert(buffer.len > 0 and buffer.len <= c.MAX_QPATH);
    _ = gateway.call(c.G_DK3_WORLD_NAME_V1, .{ buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
