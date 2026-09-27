// SPDX-License-Identifier: GPL-2.0-or-later
//! Bind the map's supplied cloud/lightning shader variants to its sky surface.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
pub const Binding = struct {
    original: [c.MAX_QPATH:0]u8 = @splat(0),
    variants: [5][c.MAX_QPATH:0]u8 = @splat(@splat(0)),
    pub fn parse(bytes: []const u8) !Binding {
        var reader: @import("../domain/tables.zig").Reader = .{ .bytes = bytes };
        if (!std.mem.eql(u8, try reader.token() orelse return error.InvalidSky, "dk3_sky")) return error.InvalidSky;
        const version = try reader.token() orelse return error.InvalidSky;
        if (!std.mem.eql(u8, version, "1") and !std.mem.eql(u8, version, "2")) return error.InvalidSky;
        var result: Binding = .{};
        try name(&result.original, try reader.token() orelse return error.InvalidSky);
        for (&result.variants, 0..) |*variant, i| {
            if (i > 0 and std.mem.eql(u8, version, "1")) variant.* = result.variants[0] else try name(variant, try reader.token() orelse return error.InvalidSky);
        }
        if (try reader.token() != null) return error.InvalidSky;
        return result;
    }
    fn name(out: *[c.MAX_QPATH:0]u8, value: []const u8) !void {
        if (value.len == 0 or value.len >= out.len) return error.InvalidSky;
        @memcpy(out[0..value.len], value);
    }
};
var binding: ?Binding = null;
var selected: ?usize = null;
pub fn init(map: []const u8, game: *const c.gameState_t) !void {
    binding = null;
    selected = null;
    var path: [128]u8 = undefined;
    const bytes = try @import("../engine/files.zig").readOptional(.client, &engine.gateway, std.heap.c_allocator, try std.fmt.bufPrintZ(&path, "dk3/skies/{s}.cfg", .{map}), 1024) orelse return;
    defer std.heap.c_allocator.free(bytes);
    binding = try Binding.parse(bytes);
    try update(game);
}
pub fn update(game: *const c.gameState_t) !void {
    const active = binding orelse return;
    const number = std.fmt.parseInt(i32, try engine.config(game, c.CS_DK3_SKY), 10) catch 1;
    const index: usize = @intCast(std.math.clamp(number, 1, 5) - 1);
    if (selected == index) return;
    _ = engine.gateway.call(c.CG_R_REGISTERSHADER, .{&active.variants[index]});
    _ = engine.gateway.call(c.CG_R_REMAP_SHADER, .{ &active.original, &active.variants[index], @as([*:0]const u8, "0") });
    selected = index;
    var text: [192]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 sky: {s} -> {s}\n", .{ std.mem.sliceTo(&active.original, 0), std.mem.sliceTo(&active.variants[index], 0) }));
}
test "sky bindings preserve all authored variants and reject incomplete data" {
    const t = std.testing;
    const binding2 = try Binding.parse("dk3_sky 2 original one two three four five");
    try t.expectEqualStrings("five", std.mem.sliceTo(&binding2.variants[4], 0));
    const binding1 = try Binding.parse("dk3_sky 1 original shared");
    try t.expectEqualStrings("shared", std.mem.sliceTo(&binding1.variants[4], 0));
    try t.expectError(error.InvalidSky, Binding.parse("dk3_sky 2 original one"));
}
