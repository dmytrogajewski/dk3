// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared client/UI drawing adapter. Geometry and glyph layout use pixel coordinates.
const std = @import("std");
const abi = @import("abi.zig");
const c = abi.c;
pub const Color = [4]f32;
pub const white: Color = @splat(1);
pub const Font = struct { metrics: @import("../domain/font.zig").Metrics, shader: c.qhandle_t, width: u16, height: u16 };
pub fn Canvas(comptime side: enum { client, ui }) type {
    return struct {
        gateway: *abi.Gateway,
        pub fn shader(self: @This(), name: [:0]const u8) c.qhandle_t {
            return @intCast(self.gateway.call(if (side == .client) c.CG_R_REGISTERSHADERNOMIP else c.UI_R_REGISTERSHADERNOMIP, .{name.ptr}));
        }
        pub fn font(self: @This(), name: []const u8) !Font {
            var path: [64]u8 = undefined;
            const bytes = try @import("files.zig").read(if (side == .client) .client else .ui, self.gateway, std.heap.c_allocator, try std.fmt.bufPrintZ(&path, "fonts/{s}.dkf", .{name}), 4096);
            defer std.heap.c_allocator.free(bytes);
            const picture = try std.fmt.bufPrintZ(&path, "fonts/{s}.tga", .{name});
            const header = try @import("files.zig").read(if (side == .client) .client else .ui, self.gateway, std.heap.c_allocator, picture, 4 << 20);
            defer std.heap.c_allocator.free(header);
            if (header.len < 18) return error.InvalidFontImage;
            const width = std.mem.readInt(u16, header[12..14], .little);
            const height = std.mem.readInt(u16, header[14..16], .little);
            return .{ .metrics = try @import("../domain/font.zig").Metrics.parse(bytes, width, height), .shader = self.shader(picture), .width = width, .height = height };
        }
        pub fn color(self: @This(), value: ?*const Color) void {
            _ = self.gateway.call(if (side == .client) c.CG_R_SETCOLOR else c.UI_R_SETCOLOR, .{value});
        }
        pub fn image(self: @This(), x: f32, y: f32, width: f32, height: f32, uv: [4]f32, handle: c.qhandle_t) void {
            _ = self.gateway.call(if (side == .client) c.CG_R_DRAWSTRETCHPIC else c.UI_R_DRAWSTRETCHPIC, .{ float(x), float(y), float(width), float(height), float(uv[0]), float(uv[1]), float(uv[2]), float(uv[3]), @as(isize, handle) });
        }
        pub fn rect(self: @This(), x: f32, y: f32, width: f32, height: f32, handle: c.qhandle_t, tint: Color) void {
            self.color(&tint);
            self.image(x, y, width, height, .{ 0, 0, 1, 1 }, handle);
            self.color(null);
        }
        pub fn text(self: @This(), font_value: Font, left: f32, top: f32, scale: f32, value: []const u8, tint: Color) void {
            self.color(&tint);
            defer self.color(null);
            var x = left;
            var y = top;
            const width: f32 = @floatFromInt(font_value.width);
            const height: f32 = @floatFromInt(font_value.height);
            const glyph_height: f32 = @floatFromInt(font_value.metrics.height);
            for (value) |char| {
                if (char == '\n') {
                    x = left;
                    y += (glyph_height + 3) * scale;
                    continue;
                }
                const w: f32 = @floatFromInt(font_value.metrics.widths[char]);
                if (char != ' ' and w > 0) {
                    const sx: f32 = @floatFromInt(font_value.metrics.x[char]);
                    const sy: f32 = @floatFromInt(font_value.metrics.y[char]);
                    self.image(x, y, w * scale, glyph_height * scale, .{ sx / width, sy / height, (sx + w) / width, (sy + glyph_height) / height }, font_value.shader);
                }
                x += font_value.metrics.advance(char, scale);
            }
        }
    };
}
fn float(value: f32) isize {
    return @as(i32, @bitCast(value));
}
