// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied chapter plaques and resource-driven progress during native admission.
const std = @import("std");
const engine = @import("../engine/ui.zig");
const c = engine.c;
const Art = @import("art.zig").Art;
const Layout = @import("../domain/menu.zig").Layout;
const Picture = struct { handle: c.qhandle_t = 0, width: u16 = 0, height: u16 = 0 };
fn picture(path: [:0]const u8) !?Picture {
    const bytes = try @import("../engine/files.zig").readOptional(.ui, &engine.gateway, std.heap.c_allocator, path, 4 << 20) orelse return null;
    defer std.heap.c_allocator.free(bytes);
    if (bytes.len < 18) return error.InvalidLoadingImage;
    return .{ .handle = engine.draw.shader(path), .width = std.mem.readInt(u16, bytes[12..14], .little), .height = std.mem.readInt(u16, bytes[14..16], .little) };
}
fn config(index: usize, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = engine.gateway.call(c.UI_GETCONFIGSTRING, .{ @as(isize, @intCast(index)), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub const Screen = struct {
    root: [64]u8 = @splat(0),
    tiles: [6]Picture = @splat(.{}),
    bar: Picture = .{},
    block: Picture = .{},
    pub fn render(self: *Screen, layout: Layout, art: *const Art) !void {
        const client = engine.client();
        var name: []const u8 = "con";
        var supplied: [64]u8 = undefined;
        var info: [c.MAX_INFO_STRING]u8 = undefined;
        var previous: [64]u8 = undefined;
        if (client.connState >= c.CA_LOADING) {
            const map = @import("../engine/info.zig").get(config(c.CS_SERVERINFO, &info), "mapname") orelse "";
            const prior = engine.get("dk3_loading_previous_map", &previous);
            const chapter_entry = map.len > 1 and map[map.len - 1] == 'a' and !(prior.len == map.len and std.mem.eql(u8, prior[0 .. prior.len - 1], map[0 .. map.len - 1]));
            if (chapter_entry) {
                const value = config(c.CS_DK3_LOADSCREEN, &supplied);
                var valid = value.len > 0;
                for (value) |ch| if (!std.ascii.isAlphanumeric(ch) and ch != '_') {
                    valid = false;
                };
                name = if (valid) value else "gen";
            }
        }
        if (!std.mem.eql(u8, name, std.mem.sliceTo(&self.root, 0))) {
            var path: [128]u8 = undefined;
            var tiles: [6]Picture = undefined;
            var actual = name;
            for (&tiles, 0..) |*tile, index| {
                tile.* = try picture(try std.fmt.bufPrintZ(&path, "pics/loadscreens/{s}_{d}.tga", .{ actual, index })) orelse {
                    if (std.mem.eql(u8, actual, "gen")) return error.MissingLoadingImage;
                    actual = "gen";
                    break;
                };
            }
            if (!std.mem.eql(u8, actual, name)) for (&tiles, 0..) |*tile, index| {
                tile.* = (try picture(try std.fmt.bufPrintZ(&path, "pics/loadscreens/gen_{d}.tga", .{index}))) orelse return error.MissingLoadingImage;
            };
            self.tiles = tiles;
            self.bar = (try picture("pics/loadbar.tga")) orelse return error.MissingLoadingImage;
            self.block = (try picture("pics/loadblock.tga")) orelse return error.MissingLoadingImage;
            @memset(&self.root, 0);
            @memcpy(self.root[0..name.len], name);
            engine.print(try std.fmt.bufPrintZ(&path, "dk3 loading: artwork={s}\n", .{actual}));
        }
        art.rect(layout, 0, 0, 640, 480, art.white, .{ 0, 0, 0, 1 });
        for (self.tiles, 0..) |tile, i| art.rect(layout, @as(f32, @floatFromInt(i % 3)) * 256, if (i < 3) 0 else 224, @floatFromInt(tile.width), @floatFromInt(tile.height), tile.handle, @splat(1));
        art.rect(layout, 383, 357, @floatFromInt(self.bar.width), @floatFromInt(self.bar.height), self.bar.handle, @splat(1));
        const amount = if (client.connState >= c.CA_LOADING) std.math.clamp(engine.number("dk3_loading_progress"), 0, 1) else 0;
        const blocks: usize = @intFromFloat(@floor(amount * 184 / 5));
        for (0..blocks) |i| art.rect(layout, 451 + @as(f32, @floatFromInt(i)) * 5, 382, @floatFromInt(self.block.width), @floatFromInt(self.block.height), self.block.handle, @splat(1));
        if (client.connState < c.CA_LOADING) art.text(layout, 90, 300, std.mem.sliceTo(&client.servername, 0), false);
        const message = std.mem.sliceTo(&client.messageString, 0);
        if (message.len > 0) art.text(layout, 90, 330, message, false);
    }
};
