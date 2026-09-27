// SPDX-License-Identifier: GPL-2.0-or-later
//! Presentation-only snapshot interpolation. Prediction and collision use authoritative poses.
const std = @import("std");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const trajectory = @import("../engine/trajectory.zig");
const Pose = struct {
    position: v.Vec3 = @splat(0),
    angles: v.Vec3 = @splat(0),
    fov: f32 = 90,
};
const Track = struct {
    before: Pose = .{},
    current: Pose = .{},
    at: i32 = 0,
    interval: i32 = 0,
    key: u64 = 0,
    valid: bool = false,
    fn put(self: *Track, value: Pose, key: u64, time: i32, previous: i32) void {
        const continuous = self.valid and self.at == previous and time > previous and self.key == key;
        self.before = if (continuous) self.current else value;
        self.current = value;
        self.interval = if (continuous) time - previous else 0;
        self.at = time;
        self.key = key;
        self.valid = true;
    }
    fn sample(self: Track, now: i32) Pose {
        const fraction = if (self.interval > 0) std.math.clamp(@as(f32, @floatFromInt(@as(i64, now) - self.at)) / @as(f32, @floatFromInt(self.interval)), 0, 1) else 1;
        var result = self.current;
        result.position = v.add(self.before.position, v.scale(v.subtract(self.current.position, self.before.position), fraction));
        for (&result.angles, self.before.angles, self.current.angles) |*angle, first, last| angle.* = first + (@mod(last - first + 180, 360) - 180) * fraction;
        result.fov = self.before.fov + (self.current.fov - self.before.fov) * fraction;
        return result;
    }
};
var entities: [c.MAX_GENTITIES]Track = @splat(.{});
var camera_track: Track = .{};
var prior_time: i32 = 0;
pub fn reset() void {
    @memset(&entities, .{});
    camera_track = .{};
    prior_time = 0;
}
pub fn ingest(snapshot: *const c.snapshot_t, boundary: u32) void {
    for (snapshot.entities[0..@intCast(snapshot.numEntities)]) |entity| {
        if (entity.number < 0 or entity.number >= entities.len) continue;
        const key = @as(u64, @intCast(entity.modelindex)) | (@as(u64, @intCast(entity.eType)) << 16) | (@as(u64, @intCast(entity.eFlags & c.EF_TELEPORT_BIT)) << 32);
        entities[@intCast(entity.number)].put(.{ .position = entity.pos.trBase, .angles = entity.apos.trBase }, key, snapshot.serverTime, prior_time);
    }
    camera_track.put(.{ .position = snapshot.ps.dk3CameraOrigin, .angles = snapshot.ps.dk3CameraAngles, .fov = snapshot.ps.dk3CameraFov }, @as(u64, boundary) << 32 | @as(u32, @bitCast(snapshot.ps.dk3CameraActive)), snapshot.serverTime, prior_time);
    prior_time = snapshot.serverTime;
}
pub fn apply(value: *c.entityState_t, now: i32) void {
    if (value.number < 0 or value.number >= entities.len) return;
    const pose = entities[@intCast(value.number)].sample(now);
    if (value.pos.trType == c.TR_INTERPOLATE) value.pos = trajectory.stationary(pose.position);
    if (value.apos.trType == c.TR_INTERPOLATE) value.apos = trajectory.stationary(pose.angles);
}
pub fn camera(now: i32) Pose {
    return camera_track.sample(now);
}

test "snapshot poses interpolate shortest angles and reset on cuts gaps and clock restoration" {
    const t = std.testing;
    var track: Track = .{};
    track.put(.{ .position = .{ 0, 0, 0 }, .angles = .{ 0, 359, 0 } }, 1, 100, 0);
    track.put(.{ .position = .{ 10, 0, 0 }, .angles = .{ 0, 1, 0 } }, 1, 150, 100);
    try t.expectEqual(@as(f32, 5), track.sample(175).position[0]);
    try t.expectEqual(@as(f32, 360), track.sample(175).angles[1]);
    track.put(.{ .position = .{ 100, 0, 0 } }, 2, 200, 150);
    try t.expectEqual(@as(f32, 100), track.sample(200).position[0]);
    track.put(.{ .position = .{ 200, 0, 0 } }, 2, 300, 250);
    try t.expectEqual(@as(f32, 200), track.sample(300).position[0]);
    track.put(.{ .position = .{ 1, 0, 0 } }, 2, 50, 300);
    try t.expectEqual(@as(f32, 1), track.sample(50).position[0]);
}
