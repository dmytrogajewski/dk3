// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const abi = @import("abi.zig");
const c = abi.c;
const collision = @import("../domain/collision.zig");
pub var gateway: abi.Gateway = .{};
var entities: []const c.entityState_t = &.{};
var time: i32 = 0;
pub fn setSnapshot(values: []const c.entityState_t, now: i32) void {
    entities = values;
    time = now;
}
fn inlineModel(index: i32) isize {
    return gateway.call(c.CG_CM_INLINEMODEL, .{@as(isize, index)});
}
pub fn print(text: [:0]const u8) void {
    _ = gateway.call(c.CG_PRINT, .{text.ptr});
}
pub fn fatal(text: [:0]const u8) noreturn {
    _ = gateway.call(c.CG_ERROR, .{text.ptr});
    @panic("engine error returned");
}
pub fn config(game: *const c.gameState_t, index: usize) ![:0]const u8 {
    if (index >= game.stringOffsets.len) return error.InvalidConfigstring;
    const offset = game.stringOffsets[index];
    if (offset < 0 or offset >= game.stringData.len) return error.InvalidConfigstring;
    const data = game.stringData[@intCast(offset)..];
    const end = std.mem.indexOfScalar(u8, data, 0) orelse return error.InvalidConfigstring;
    return data[0..end :0];
}
pub const info = @import("info.zig").get;
pub fn integer(name: [:0]const u8) i32 {
    var buffer: [64]u8 = @splat(0);
    _ = gateway.call(c.CG_CVAR_VARIABLESTRINGBUFFER, .{ name.ptr, &buffer, @as(isize, buffer.len) });
    return std.fmt.parseInt(i32, std.mem.sliceTo(&buffer, 0), 10) catch 0;
}
pub fn collisionService() collision.Collision {
    return .{ .context = &gateway, .trace_fn = trace, .contents_fn = contents };
}
fn trace(raw: *anyopaque, request: collision.Request) !collision.Trace {
    const engine: *abi.Gateway = @ptrCast(@alignCast(raw));
    var result: c.trace_t = undefined;
    _ = engine.call(c.CG_CM_BOXTRACE, .{ &result, &request.start, &request.end, &request.mins, &request.maxs, @as(isize, 0), @as(isize, @as(i32, @bitCast(request.mask))) });
    result.entityNum = if (result.fraction < 1 or result.allsolid != 0) c.ENTITYNUM_WORLD else c.ENTITYNUM_NONE;
    for (entities) |entity| {
        if (entity.number == request.slot or entity.solid == 0) continue;
        const brush = entity.solid == c.SOLID_BMODEL;
        var model: isize = undefined;
        if (brush) model = inlineModel(entity.modelindex) else {
            const width: f32 = @floatFromInt(entity.solid & 255);
            const bottom: f32 = @floatFromInt((entity.solid >> 8) & 255);
            const top: f32 = @floatFromInt(((entity.solid >> 16) & 255) - 32);
            const mins: [3]f32 = .{ -width, -width, -bottom };
            const maxs: [3]f32 = .{ width, width, top };
            model = engine.call(c.CG_CM_TEMPBOXMODEL, .{ &mins, &maxs });
        }
        const origin = @import("trajectory.zig").evaluate(entity.pos, time);
        const angles = if (brush) @import("trajectory.zig").evaluate(entity.apos, time) else @as([3]f32, @splat(0));
        var hit: c.trace_t = undefined;
        _ = engine.call(c.CG_CM_TRANSFORMEDBOXTRACE, .{ &hit, &request.start, &request.end, &request.mins, &request.maxs, model, @as(isize, @as(i32, @bitCast(request.mask))), &origin, &angles });
        if (hit.allsolid != 0 or hit.fraction < result.fraction) {
            const started = result.startsolid;
            result = hit;
            result.entityNum = entity.number;
            if (started != 0) result.startsolid = 1;
        } else if (hit.startsolid != 0) result.startsolid = 1;
        if (result.allsolid != 0) break;
    }
    return .{ .fraction = result.fraction, .end = result.endpos, .normal = result.plane.normal, .start_solid = result.startsolid != 0, .all_solid = result.allsolid != 0, .entity = @intCast(result.entityNum), .slick = result.surfaceFlags & c.SURF_SLICK != 0, .ladder = result.surfaceFlags & c.SURF_LADDER != 0 };
}
fn contents(raw: *anyopaque, point: @import("../domain/vector.zig").Vec3, skip: u16) !u32 {
    const engine: *abi.Gateway = @ptrCast(@alignCast(raw));
    var result: u32 = @bitCast(@as(i32, @intCast(engine.call(c.CG_CM_POINTCONTENTS, .{ &point, @as(isize, 0) }))));
    for (entities) |entity| {
        if (entity.number == skip or entity.solid != c.SOLID_BMODEL) continue;
        const origin = @import("trajectory.zig").evaluate(entity.pos, time);
        const angles = @import("trajectory.zig").evaluate(entity.apos, time);
        result |= @bitCast(@as(i32, @intCast(engine.call(c.CG_CM_TRANSFORMEDPOINTCONTENTS, .{ &point, inlineModel(entity.modelindex), &origin, &angles }))));
    }
    return result;
}

pub fn floatArg(value: f32) isize {
    return @as(i32, @bitCast(value));
}
