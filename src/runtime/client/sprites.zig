// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const rules = @import("../domain/sprites.zig");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const Frame = struct { width: f32, height: f32, origin_x: f32, origin_y: f32, shaders: [2]c.qhandle_t };
const Media = struct { name: [64]u8 = @splat(0), frames: [128]Frame = undefined, count: u8 = 0 };
var media: [32]Media = @splat(.{});
var used: u8 = 0;
pub fn reset() void {
    used = 0;
}
pub fn register(name: []const u8) !u8 {
    for (media[0..used], 0..) |entry, i| if (std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), name)) return @intCast(i);
    if (used == media.len or name.len >= 64) return error.SpriteMediaCapacity;
    var path: [80]u8 = undefined;
    const bytes = try @import("../engine/files.zig").read(.client, &engine.gateway, std.heap.c_allocator, try std.fmt.bufPrintZ(&path, "{s}.frames", .{name}), 65536);
    defer std.heap.c_allocator.free(bytes);
    const parsed = try rules.parse(bytes);
    const target = &media[used];
    target.* = .{ .count = parsed.count };
    @memcpy(target.name[0..name.len], name);
    for (parsed.frames[0..parsed.count], target.frames[0..parsed.count]) |frame, *output| {
        output.* = .{ .width = @floatFromInt(frame.width), .height = @floatFromInt(frame.height), .origin_x = @floatFromInt(frame.origin_x), .origin_y = @floatFromInt(frame.origin_y), .shaders = undefined };
        for ([_][]const u8{ frame.shader, frame.additive }, &output.shaders) |shader, *handle| {
            handle.* = @intCast(engine.gateway.call(c.CG_R_REGISTERSHADER, .{(try std.fmt.bufPrintZ(&path, "{s}", .{shader})).ptr}));
            if (handle.* == 0) return error.MissingSpriteShader;
        }
    }
    const index = used;
    used += 1;
    return index;
}
pub fn draw(index: u8, frame: usize, origin: v.Vec3, scale: f32, additive: bool, ref: *const c.refdef_t) void {
    if (index >= used or frame >= media[index].count) return;
    const value = media[index].frames[frame];
    const left = -value.origin_x * scale;
    const right = (value.width - value.origin_x) * scale;
    const bottom = -value.origin_y * scale;
    const top = (value.height - value.origin_y) * scale;
    var vertices: [4]c.polyVert_t = undefined;
    for ([_][4]f32{ .{ left, bottom, 0, 1 }, .{ right, bottom, 1, 1 }, .{ right, top, 1, 0 }, .{ left, top, 0, 0 } }, &vertices) |point, *vertex| {
        vertex.* = .{ .xyz = v.add(origin, v.add(v.scale(ref.viewaxis[1], -point[0]), v.scale(ref.viewaxis[2], point[1]))), .st = .{ point[2], point[3] }, .modulate = @splat(255) };
    }
    _ = engine.gateway.call(c.CG_R_ADDPOLYTOSCENE, .{ @as(isize, value.shaders[@intFromBool(additive)]), @as(isize, 4), &vertices });
}
pub fn count(index: u8) u8 {
    return media[index].count;
}
