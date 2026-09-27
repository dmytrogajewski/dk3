// SPDX-License-Identifier: GPL-2.0-or-later
//! Episode decoration authoring, animation and contact policies.
const std = @import("std");
const v = @import("vector.zig");
const tables = @import("tables.zig");
const animation = @import("animation.zig");
pub const render_tag = 10002;
pub const explosion_tag = 10003;
pub const Material = enum { unbreakable, wood, metal, glass, flesh };
pub const Movement = enum { stationary, toss, bounce };
pub const State = struct {
    model: []const u8,
    movement: Movement = .stationary,
    material: Material = .unbreakable,
    sequence: animation.Sequence = .{},
    looping: bool = false,
    started_ms: i64,
    scale: v.Vec3 = @splat(1),
    alpha: f32 = 1,
    spin: v.Vec3 = @splat(0),
    breakable: bool = false,
    explosive: bool = false,
    damage: f32 = 25,
    broken: bool = false,
    breaking_ms: ?i64 = null,
    expires_ms: ?i64 = null,
    fragment: bool = false,
    explosion: bool = false,
    gib: ?@import("gibs.zig").State = null,
};
pub const Definition = struct {
    model: []const u8,
    movement: Movement,
    material: Material,
    solid: bool,
    mass: f32,
    health: i32,
    exploding: bool,
    mins: v.Vec3,
    maxs: v.Vec3,
    sequences: [5]struct { frames: animation.Sequence, looping: bool } = @splat(.{ .frames = .{}, .looping = false }),
    count: u3,
};
pub fn owns(classname: []const u8) bool {
    return classname.len == 7 and std.mem.startsWith(u8, classname, "deco_e") and classname[6] >= '1' and classname[6] <= '4';
}
pub fn material(name: []const u8) Material {
    const names = .{ .{ "WOOD", Material.wood }, .{ "METAL", Material.metal }, .{ "GLASS", Material.glass }, .{ "GIBS", Material.flesh } };
    inline for (names) |entry| if (std.ascii.eqlIgnoreCase(name, entry[0])) return entry[1];
    // STONE is not a breakable material in the decoration authoring contract.
    return .unbreakable;
}
pub fn find(bytes: []const u8, name: []const u8) !Definition {
    var reader = try tables.Reader.init(bytes);
    while (try reader.next()) |row| {
        if (!std.ascii.eqlIgnoreCase(row.field("modelname") orelse "", name)) continue;
        const move = row.field("movetype") orelse return error.MissingDecorationMovement;
        const solid = row.field("solidtype") orelse return error.MissingDecorationSolidity;
        var result: Definition = .{
            .model = row.field("pathname") orelse return error.MissingDecorationModel,
            .movement = if (std.ascii.eqlIgnoreCase(move, "none")) .stationary else if (std.ascii.eqlIgnoreCase(move, "toss")) .toss else if (std.ascii.eqlIgnoreCase(move, "bounce")) .bounce else return error.UnknownDecorationMovement,
            .material = material(row.field("gibtype") orelse ""),
            .solid = if (std.ascii.eqlIgnoreCase(solid, "bbox")) true else if (std.ascii.eqlIgnoreCase(solid, "not")) false else return error.UnknownDecorationSolidity,
            .mass = try row.number("mass", 1),
            .health = 20,
            .exploding = try row.number("exploding", 0) != 0,
            .mins = undefined,
            .maxs = undefined,
            .count = @intFromFloat(std.math.clamp(try row.number("animseq", 0), 0, 5)),
        };
        const health = try row.number("hitpoints", 20);
        result.health = @intFromFloat(if (health < 1) 20 else health);
        inline for (.{ "x", "y", "z" }, 0..) |axis, i| {
            result.mins[i] = try row.number("min" ++ axis, -16);
            result.maxs[i] = try row.number("max" ++ axis, 16);
            if (result.mins[i] > result.maxs[i]) return error.InvalidDecorationBounds;
        }
        for (0..result.count) |index| {
            var key: [8]u8 = undefined;
            const text = row.field(try std.fmt.bufPrint(&key, "seq{d}", .{index})) orelse return error.MissingDecorationSequence;
            var words = std.mem.tokenizeAny(u8, text, "-~; \t\r\n");
            const first = try std.fmt.parseInt(u16, words.next() orelse return error.InvalidDecorationSequence, 10);
            const last = if (words.next()) |word| try std.fmt.parseInt(u16, word, 10) else first;
            if (last < first or words.next() != null) return error.InvalidDecorationSequence;
            result.sequences[index] = .{ .frames = .{ .first = first, .last = last }, .looping = std.mem.indexOfScalar(u8, text, '~') != null };
        }
        if (!std.mem.startsWith(u8, result.model, "models/") or std.mem.indexOf(u8, result.model, "..") != null or result.model.len >= 64 or result.mass < 0) return error.InvalidDecorationDefinition;
        return result;
    }
    return error.UnknownDecorationModel;
}
pub fn contact(velocity: v.Vec3, normal: v.Vec3, bounce: bool) v.Vec3 {
    const clipped = v.subtract(velocity, v.scale(normal, v.dot(velocity, normal) * (if (bounce) @as(f32, 1.5) else 1)));
    if (normal[2] > 0.7 and (!bounce or clipped[2] < 60)) return @splat(0);
    return clipped;
}
