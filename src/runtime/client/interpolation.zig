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
        // CG time lies between the preceding and newest snapshots. Subtracting
        // the newest timestamp freezes every intermediate pose (862 < 900 in
        // the captured arrival cinematic), then jumps at the next snapshot.
        const fraction = if (self.interval > 0) std.math.clamp(@as(f32, @floatFromInt(@as(i64, now) - (self.at - self.interval))) / @as(f32, @floatFromInt(self.interval)), 0, 1) else 1;
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
var world_id: i32 = 0;
pub fn reset() void {
    @memset(&entities, .{});
    camera_track = .{};
    prior_time = 0;
    world_id = 0;
}
pub fn ingest(snapshot: *const c.snapshot_t, boundary: u32) void {
    if (snapshot.ps.dk3World != world_id) {
        @memset(&entities, .{});
        world_id = snapshot.ps.dk3World;
    }
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
pub fn blendedMotion(now: i32) usize {
    var count: usize = 0;
    for (entities) |track| {
        if (!track.valid or track.at != prior_time or track.interval <= 0) continue;
        const delta = v.length(v.subtract(track.current.position, track.before.position));
        if (delta < 0.01) continue;
        const point = track.sample(now).position;
        if (v.length(v.subtract(point, track.before.position)) > 0.001 and v.length(v.subtract(point, track.current.position)) > 0.001) count += 1;
    }
    return count;
}

test "snapshot poses interpolate shortest angles and reset on cuts gaps and clock restoration" {
    const t = std.testing;
    var track: Track = .{};
    track.put(.{ .position = .{ 0, 0, 0 }, .angles = .{ 0, 359, 0 } }, 1, 100, 0);
    track.put(.{ .position = .{ 10, 0, 0 }, .angles = .{ 0, 1, 0 } }, 1, 150, 100);
    try t.expectEqual(@as(f32, 5), track.sample(125).position[0]);
    try t.expectEqual(@as(f32, 360), track.sample(125).angles[1]);
    try t.expectEqual(@as(f32, 0), track.sample(99).position[0]);
    try t.expectEqual(@as(f32, 10), track.sample(175).position[0]);
    track.put(.{ .position = .{ 100, 0, 0 } }, 2, 200, 150);
    try t.expectEqual(@as(f32, 100), track.sample(200).position[0]);
    track.put(.{ .position = .{ 200, 0, 0 } }, 2, 300, 250);
    try t.expectEqual(@as(f32, 200), track.sample(300).position[0]);
    track.put(.{ .position = .{ 1, 0, 0 } }, 2, 50, 300);
    try t.expectEqual(@as(f32, 1), track.sample(50).position[0]);
}
test "captured client clock interpolates both actors and cameras before the newest snapshot" {
    var track: Track = .{};
    track.put(.{ .position = .{ 0, 0, 0 } }, 1, 850, 800);
    track.put(.{ .position = .{ 10, 0, 0 } }, 1, 900, 850);
    try std.testing.expectApproxEqAbs(@as(f32, 2.4), track.sample(862).position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5.6), track.sample(878).position[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.8), track.sample(894).position[0], 0.001);
}
