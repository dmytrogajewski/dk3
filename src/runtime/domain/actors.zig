// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const catalog = @import("actor_catalog");
const v = @import("vector.zig");
const animation = @import("animation.zig");
pub const Mode = enum { idle, flee, chase, attack, reload, dead };
pub const State = struct {
    definition: u8,
    guard: catalog.mishima.State = .{},
    mode: Mode = .idle,
    changed_ms: i64 = 0,
    panic_until: i64 = 0,
    threat: u32 = 0,
    threat_position: v.Vec3 = @splat(0),
    witness_ms: i64 = -1,
    receipt: u32 = 0,
    death_dispatched: bool = false,
    ground_entity: u16 = 2047,
    pub fn panic(self: *State, source: u32, point: v.Vec3, now: i64) void {
        if (self.mode == .dead) return;
        if (self.mode != .flee) self.changed_ms = now;
        self.mode = .flee;
        self.panic_until = now + catalog.entries[self.definition].panic_ms;
        self.threat = source;
        self.threat_position = point;
    }
};
pub const Definition = struct {
    loaded: bool = false,
    model: []const u8 = "",
    health: i32 = 0,
    speed: f32 = 0,
    mins: v.Vec3 = @splat(0),
    maxs: v.Vec3 = @splat(0),
    idle: animation.Sequence = .{},
    run: animation.Sequence = .{},
    death: animation.Sequence = .{},
    attacks: [3]animation.Sequence = @splat(.{}),
    strikes: [3]u16 = @splat(1),
    attack_sounds: [3][]const u8 = @splat(""),
    reload: animation.Sequence = .{},
    sight_range: f32 = 0,
    fov: f32 = 180,
    damage: f32 = 0,
    random_damage: f32 = 0,
    range: f32 = 0,
    offset: v.Vec3 = @splat(0),
    spread: [2]f32 = @splat(0),
    scale: v.Vec3 = @splat(1),
    pub fn guardTiming(self: Definition) catalog.mishima.Timing {
        var result: catalog.mishima.Timing = undefined;
        for (self.attacks, self.strikes, 0..) |sequence, strike, i| {
            result.attack_ms[i] = @divTrunc(@as(i64, sequence.last - sequence.first + 1) * 1000, sequence.fps);
            result.strike_ms[i] = @divTrunc(@as(i64, strike) * 1000, sequence.fps);
        }
        result.reload_ms = @divTrunc(@as(i64, self.reload.last - self.reload.first + 1) * 1000, self.reload.fps);
        result.reload_sound_ms = @divTrunc(@as(i64, catalog.mishima.reload_sound_frame) * 1000, self.reload.fps);
        return result;
    }
};
pub const Table = struct {
    definitions: [catalog.entries.len]Definition = @splat(.{}),
    pub fn parse(bytes: []const u8) !Table {
        var result: Table = .{};
        var reader = try @import("tables.zig").Reader.init(bytes);
        while (try reader.next()) |row| {
            const id = catalog.find(row.field("classname") orelse return error.MissingActorClass) orelse continue;
            const entry = &result.definitions[id];
            if (entry.loaded) return error.DuplicateActorClass;
            entry.model = row.field("model_name") orelse return error.MissingActorModel;
            if (entry.model.len == 0 or entry.model.len >= 64) return error.InvalidActorModel;
            const health = try row.number("health", 0);
            entry.speed = try row.number("run_speed", 0);
            if (health <= 0 or health > 1000000 or entry.speed < 0 or entry.speed > 2000) return error.InvalidActorTuning;
            entry.health = @intFromFloat(health);
            entry.sight_range = try row.number("active_distance", 1000);
            entry.fov = try row.number("fov", 180);
            entry.damage = try row.number("weapon1_base_damage", 0);
            entry.random_damage = try row.number("weapon1_random_damage", 0);
            entry.range = try row.number("weapon1_distance", 0);
            entry.spread = .{ try row.number("weapon1_spread_x", 0), try row.number("weapon1_spread_z", 0) };
            if (entry.sight_range < 0 or entry.sight_range > 65536 or entry.fov < 0 or entry.fov > 360 or entry.damage < 0 or entry.damage > 1000000 or entry.random_damage < 0 or entry.random_damage > 1000000 or entry.range < 0 or entry.range > 65536) return error.InvalidActorTuning;
            for (entry.spread) |spread| if (spread < 0 or spread > 8192) return error.InvalidActorSpread;
            if (row.field("render_scale")) |scale| {
                var axes = std.mem.tokenizeAny(u8, scale, " \t");
                for (&entry.scale) |*value| {
                    value.* = try std.fmt.parseFloat(f32, axes.next() orelse return error.InvalidActorScale);
                    if (!std.math.isFinite(value.*) or value.* <= 0 or value.* > 16) return error.InvalidActorScale;
                }
                if (axes.next() != null) return error.InvalidActorScale;
            }
            inline for (.{ "x", "y", "z" }, 0..) |axis, i| {
                entry.offset[i] = try row.number("weapon1_offset_" ++ axis, 0);
                if (@abs(entry.offset[i]) > 1024) return error.InvalidActorOffset;
                entry.mins[i] = try row.number("size_min_" ++ axis, 0);
                entry.maxs[i] = try row.number("size_max_" ++ axis, 0);
                if (entry.mins[i] >= entry.maxs[i] or @abs(entry.mins[i]) > 1024 or @abs(entry.maxs[i]) > 1024) return error.InvalidActorBounds;
            }
            entry.loaded = true;
        }
        return result;
    }
};
pub fn fleeVelocity(position: v.Vec3, threat: v.Vec3, speed: f32) v.Vec3 {
    var away = v.add(position, v.scale(threat, -1));
    away[2] = 0;
    if (v.length(away) < 0.01) away = .{ 1, 0, 0 };
    return v.scale(v.normalize(away), speed);
}
test "civilian panic has bounded duration, stable speed and no post-death transition" {
    var state: State = .{ .definition = 0 };
    state.panic(42, .{ 10, 20, 0 }, 1000);
    try std.testing.expectEqual(Mode.flee, state.mode);
    try std.testing.expect(state.panic_until > 1000);
    try std.testing.expectApproxEqAbs(@as(f32, 150), v.length(fleeVelocity(.{ 1, 2, 0 }, .{ 1, 3, 0 }, 150)), 0.001);
    state.mode = .dead;
    state.panic(43, @splat(0), 2000);
    try std.testing.expectEqual(@as(u32, 42), state.threat);
}
