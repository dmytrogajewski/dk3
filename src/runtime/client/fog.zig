// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored worldspawn distance fog. Gold reads `fog_value`, `fog_start`, `fog_end`,
//! `fog_skyend` and `fog_color` (0-255) or `_color` (0-1) in its world spawn and sends them to
//! the client once (dlls/world/World.cpp, client.cpp ET_FOG). The renderer clears fog with every
//! scene, so the selected render world's values are submitted after each CLEARSCENE.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;

pub const Fog = struct {
    active: bool = false,
    color: [3]f32 = .{ 0, 0, 0 },
    start: f32 = 0,
    end: f32 = 0,
    sky_end: f32 = 0,

    /// Applies one worldspawn key; unknown keys are ignored.
    pub fn apply(self: *Fog, key: []const u8, value: []const u8) void {
        if (std.ascii.eqlIgnoreCase(key, "fog_value")) {
            self.active = (std.fmt.parseInt(i32, std.mem.trim(u8, value, " "), 10) catch 0) != 0;
        } else if (std.ascii.eqlIgnoreCase(key, "fog_start")) {
            self.start = number(value);
        } else if (std.ascii.eqlIgnoreCase(key, "fog_end")) {
            self.end = number(value);
        } else if (std.ascii.eqlIgnoreCase(key, "fog_skyend")) {
            self.sky_end = number(value);
        } else if (std.ascii.eqlIgnoreCase(key, "fog_color")) {
            self.color = triple(value);
            for (&self.color) |*channel| channel.* /= 255;
        } else if (std.ascii.eqlIgnoreCase(key, "_color")) {
            self.color = triple(value);
        }
    }
};

fn number(value: []const u8) f32 {
    return std.fmt.parseFloat(f32, std.mem.trim(u8, value, " ")) catch 0;
}

fn triple(value: []const u8) [3]f32 {
    var out: [3]f32 = .{ 0, 0, 0 };
    var parts = std.mem.tokenizeScalar(u8, value, ' ');
    for (&out) |*channel| channel.* = number(parts.next() orelse break);
    return out;
}

const Cached = struct { world: u32, fog: Fog };
var cache: [16]Cached = undefined;
var cached: usize = 0;

/// The worldspawn of the selected render world. Every token is read so the renderer's parse
/// position returns to the start of the entity string for the next reader.
fn parse() Fog {
    var fog: Fog = .{};
    var token: [c.MAX_TOKEN_CHARS]u8 = undefined;
    var key: [c.MAX_TOKEN_CHARS]u8 = undefined;
    var depth: u32 = 0;
    var entity: u32 = 0;
    var pending_key: ?[]const u8 = null;
    while (engine.gateway.call(c.CG_GET_ENTITY_TOKEN, .{ &token, @as(isize, token.len) }) != 0) {
        const text = std.mem.sliceTo(&token, 0);
        if (std.mem.eql(u8, text, "{")) {
            depth += 1;
            entity += 1;
            continue;
        }
        if (std.mem.eql(u8, text, "}")) {
            depth -|= 1;
            pending_key = null;
            continue;
        }
        if (entity != 1 or depth != 1) continue;
        if (pending_key) |name| {
            fog.apply(name, text);
            pending_key = null;
        } else {
            @memcpy(key[0..text.len], text);
            pending_key = key[0..text.len];
        }
    }
    return fog;
}

/// Submits the selected world's fog for the scene being built.
pub fn submit() void {
    const world: u32 = @intCast(engine.gateway.call(c.CG_DK3_WORLD_CURRENT_V1, .{}));
    if (world == 0) return;
    const fog = for (cache[0..cached]) |entry| {
        if (entry.world == world) break entry.fog;
    } else blk: {
        const parsed = parse();
        if (cached == cache.len) cached = 0;
        cache[cached] = .{ .world = world, .fog = parsed };
        cached += 1;
        break :blk parsed;
    };
    if (!fog.active) return;
    _ = engine.gateway.call(c.CG_DK3_R_FOG_V1, .{ &fog.color, engine.floatArg(fog.start), engine.floatArg(fog.end), engine.floatArg(fog.sky_end) });
}

/// Map changes reuse render world handles only after the renderer restarts; drop the cache.
pub fn reset() void {
    cached = 0;
}

test "worldspawn fog keys follow Gold's world spawn" {
    var fog: Fog = .{};
    fog.apply("fog_value", "1");
    fog.apply("fog_start", "128");
    fog.apply("fog_end", "1024.5");
    fog.apply("fog_skyend", "2048");
    fog.apply("fog_color", "255 51 0");
    try std.testing.expect(fog.active);
    try std.testing.expectEqual(@as(f32, 1024.5), fog.end);
    try std.testing.expectApproxEqAbs(@as(f32, 0.2), fog.color[1], 1e-6);
    fog.apply("_color", "0.5 0.25 1");
    try std.testing.expectEqual(@as(f32, 0.25), fog.color[1]);
    fog.apply("fog_value", "0");
    try std.testing.expect(!fog.active);
}
