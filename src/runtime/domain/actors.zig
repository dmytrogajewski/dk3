// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const catalog = @import("actor_catalog");
const v = @import("vector.zig");
const animation = @import("animation.zig");
pub const Mode = enum { idle, flee, dead };
pub const State = struct {
    definition: u8,
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
        self.panic_until = now + catalog.civilians[self.definition].panic_ms;
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
};
pub const Table = struct {
    definitions: [catalog.civilians.len]Definition = @splat(.{}),
    pub fn parse(bytes: []const u8) !Table {
        var result: Table = .{};
        var reader = try @import("tables.zig").Reader.init(bytes);
        while (try reader.next()) |row| {
            const id = catalog.civilian(row.field("classname") orelse return error.MissingActorClass) orelse continue;
            const entry = &result.definitions[id];
            if (entry.loaded) return error.DuplicateActorClass;
            entry.model = row.field("model_name") orelse return error.MissingActorModel;
            if (entry.model.len == 0 or entry.model.len >= 64) return error.InvalidActorModel;
            const health = try row.number("health", 0);
            entry.speed = try row.number("run_speed", 0);
            if (health <= 0 or health > 1000000 or entry.speed < 0 or entry.speed > 2000) return error.InvalidActorTuning;
            entry.health = @intFromFloat(health);
            inline for (.{ "x", "y", "z" }, 0..) |axis, i| {
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
