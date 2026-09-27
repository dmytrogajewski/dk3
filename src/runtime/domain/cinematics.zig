// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied cinematic records and camera evaluation. No engine or private code dependency.
const std = @import("std");
const v = @import("vector.zig");
const Sequence = @import("animation.zig").Sequence;
pub const TaskKind = enum(u8) { none, move, turn, move_turn, backup, restore, run_speed, walk_speed, yaw_speed, wait, teleport, run, walk, use, head, animation, idle, sound, spawn, remove, clear };
pub const Task = struct {
    kind: TaskKind,
    when: f32,
    destination: v.Vec3,
    angles: v.Vec3,
    attribute: f32,
    duration: f32,
    animation: []const u8,
    use: []const u8,
    sound: []const u8,
    unique: []const u8,
    head: []const [12]f32 = &.{},
    head_initial: v.Vec3 = @splat(0),
};
pub const Track = struct { classname: []const u8, unique: []const u8, first: u16, count: u16 };
pub const Sound = struct { path: []const u8, loop: bool, channel: u8, when: f32 };
pub const Segment = struct {
    seconds: f32,
    fov_flags: [2]bool,
    fov: [2]f32,
    speed_flags: [2]bool,
    speed: [2]f32,
    blend_flags: [2]bool,
    blend: [2][4]f32,
    position: [12]f32,
    angles: [12]f32,
};
pub const Camera = struct { position: v.Vec3, angles: v.Vec3, fov: f32 = 90, blend: [4]f32 = .{ 0, 0, 0, 0 } };
pub const Shot = struct {
    seconds: f32,
    pre: f32,
    post: f32,
    target: bool,
    end_on_actor: bool,
    has_fov: bool,
    fov: f32,
    sky: bool,
    velocity_modes: [2]u8,
    target_name: []const u8,
    end_name: []const u8,
    points: u16,
    initial: Camera,
    segments: []const Segment,
    sounds: []const Sound,
    tracks: []const Track,
    pub fn duration(self: Shot) i64 {
        return @intFromFloat(@round((self.seconds + self.pre + self.post) * 1000));
    }
    pub fn camera(self: Shot, elapsed_ms: i64, inherited: Camera) Camera {
        var result = self.initial;
        result.fov = if (self.has_fov) self.fov else inherited.fov;
        result.blend = inherited.blend;
        var seconds = @max(0, @as(f32, @floatFromInt(elapsed_ms)) * 0.001 - self.pre);
        for (self.segments[0..@min(self.segments.len, self.points -| 1)]) |segment| {
            const time = @min(seconds, segment.seconds);
            const fraction = if (segment.seconds > 0) time / segment.seconds else 1;
            // Curves are supplied cubic coefficients in seconds, grouped by axis.
            for (0..3) |axis| {
                result.position[axis] = polynomial(segment.position[axis * 4 ..][0..4].*, time);
                result.angles[axis] = polynomial(segment.angles[axis * 4 ..][0..4].*, time);
            }
            const start_fov = if (segment.fov_flags[0]) segment.fov[0] else result.fov;
            result.fov = if (segment.fov_flags[1]) start_fov + (segment.fov[1] - start_fov) * fraction else start_fov;
            const start_blend = if (segment.blend_flags[0]) segment.blend[0] else result.blend;
            for (&result.blend, start_blend, segment.blend[1]) |*value, start, end| value.* = if (segment.blend_flags[1]) start + (end - start) * fraction else start;
            if (seconds <= segment.seconds) break;
            seconds -= segment.seconds;
        }
        return result;
    }
};
fn polynomial(coefficients: [4]f32, seconds: f32) f32 {
    return ((coefficients[0] * seconds + coefficients[1]) * seconds + coefficients[2]) * seconds + coefficients[3];
}
pub const Program = struct { shots: []const Shot, tasks: []const Task };
const Reader = struct {
    tokens: @import("tables.zig").Reader,
    fn word(self: *Reader) ![]const u8 {
        return try self.tokens.token() orelse error.TruncatedCinematic;
    }
    fn expect(self: *Reader, expected: []const u8) !void {
        if (!std.mem.eql(u8, try self.word(), expected)) return error.InvalidCinematicRecord;
    }
    fn scalar(self: *Reader) !f32 {
        const value = try std.fmt.parseFloat(f32, try self.word());
        if (!std.math.isFinite(value)) return error.InvalidCinematicNumber;
        return value;
    }
    fn count(self: *Reader, limit: usize) !usize {
        const value = try std.fmt.parseInt(usize, try self.word(), 10);
        if (value > limit) return error.CinematicCapacity;
        return value;
    }
    fn flag(self: *Reader) !bool {
        return (try self.count(1)) == 1;
    }
    fn numbers(self: *Reader, comptime n: usize) ![n]f32 {
        var values: [n]f32 = undefined;
        for (&values) |*value| value.* = try self.scalar();
        return values;
    }
    fn flags(self: *Reader) ![2]bool {
        return .{ try self.flag(), try self.flag() };
    }
};
/// All strings borrow bytes, arrays belong to the caller's map-scoped arena.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) !Program {
    if (bytes.len == 0 or bytes.len > 4 * 1024 * 1024) return error.CinematicSize;
    var reader: Reader = .{ .tokens = .{ .bytes = bytes } };
    try reader.expect("dk3_cinematic");
    try reader.expect("1");
    const shots = try allocator.alloc(Shot, try reader.count(256));
    var tasks: std.ArrayList(Task) = .empty;
    for (shots) |*shot| {
        try reader.expect("shot");
        shot.seconds = try reader.scalar();
        shot.pre = try reader.scalar();
        shot.post = try reader.scalar();
        if (shot.seconds < 0 or shot.pre < 0 or shot.post < 0 or shot.seconds + shot.pre + shot.post > 3600) return error.InvalidCinematicTime;
        shot.target = try reader.flag();
        shot.end_on_actor = try reader.flag();
        shot.has_fov = try reader.flag();
        shot.fov = try reader.scalar();
        shot.sky = try reader.flag();
        shot.velocity_modes = .{ @intCast(try reader.count(2)), @intCast(try reader.count(2)) };
        shot.target_name = try reader.word();
        shot.end_name = try reader.word();
        try reader.expect("camera");
        shot.points = @intCast(try reader.count(8192));
        const segments = try allocator.alloc(Segment, try reader.count(8192));
        shot.segments = segments;
        if (segments.len < shot.points -| 1) return error.InvalidCinematicCamera;
        shot.initial = .{ .position = try reader.numbers(3), .angles = try reader.numbers(3) };
        for (segments) |*segment| {
            try reader.expect("segment");
            segment.seconds = try reader.scalar();
            if (segment.seconds < 0 or segment.seconds > 3600) return error.InvalidCinematicTime;
            segment.fov_flags = try reader.flags();
            segment.fov = try reader.numbers(2);
            segment.speed_flags = try reader.flags();
            segment.speed = try reader.numbers(2);
            segment.blend_flags = try reader.flags();
            segment.blend = .{ try reader.numbers(4), try reader.numbers(4) };
            segment.position = try reader.numbers(12);
            segment.angles = try reader.numbers(12);
        }
        try reader.expect("sounds");
        const sounds = try allocator.alloc(Sound, try reader.count(4096));
        shot.sounds = sounds;
        for (sounds) |*sound| sound.* = .{ .path = try reader.word(), .loop = try reader.flag(), .channel = @intCast(try reader.count(255)), .when = try reader.scalar() };
        try reader.expect("entities");
        const tracks = try allocator.alloc(Track, try reader.count(128));
        shot.tracks = tracks;
        for (tracks) |*track| {
            track.classname = try reader.word();
            track.unique = try reader.word();
            track.first = @intCast(tasks.items.len);
            track.count = @intCast(try reader.count(32768));
            if (tasks.items.len + track.count > 65535) return error.CinematicCapacity;
            for (0..track.count) |_| {
                var task: Task = .{ .kind = @enumFromInt(try reader.count(20)), .when = try reader.scalar(), .destination = try reader.numbers(3), .angles = try reader.numbers(3), .attribute = try reader.scalar(), .duration = try reader.scalar(), .animation = try reader.word(), .use = try reader.word(), .sound = try reader.word(), .unique = try reader.word() };
                if (task.kind == .head) {
                    try reader.expect("head");
                    const points = try reader.count(8192);
                    task.head_initial = try reader.numbers(3);
                    const curves = try allocator.alloc([12]f32, points -| 1);
                    for (curves) |*curve| curve.* = try reader.numbers(12);
                    task.head = curves;
                }
                try tasks.append(allocator, task);
            }
        }
    }
    if (try reader.tokens.token() != null) return error.TrailingCinematicData;
    return .{ .shots = shots, .tasks = try tasks.toOwnedSlice(allocator) };
}
// Native save state is separate from immutable supplied program data.
pub const Playback = struct {
    name: []const u8,
    shot: u16 = 0,
    started_ms: i64 = 0,
    active: bool = false,
    finished: bool = false,
    sounds: u16 = 0,
    queued: [128]u16 = @splat(0),
    inherited: Camera = .{ .position = @splat(0), .angles = @splat(0) },
};
pub const Performer = struct {
    unique: []const u8,
    classname: []const u8,
    model: []const u8,
    scale: v.Vec3 = @splat(1),
    walk_speed: f32 = 25,
    run_speed: f32 = 125,
    yaw_speed: f32 = 20,
    running: bool = false,
    animation: Sequence = .{},
    idle: Sequence = .{},
    movement: Sequence = .{},
    animation_ms: i64 = 0,
    queue: [128]u16 = @splat(0),
    count: u16 = 0,
    started: bool = false,
    due_ms: i64 = 0,
    next_ms: i64 = 0,
    velocity: v.Vec3 = @splat(0),
};
test "cinematic cubic evaluates seconds and holds segment endpoints" {
    const segment: Segment = .{ .seconds = 2, .fov_flags = .{ true, true }, .fov = .{ 90, 60 }, .speed_flags = .{ false, false }, .speed = .{ 1, 1 }, .blend_flags = .{ true, true }, .blend = .{ .{ 0, 0, 0, 255 }, .{ 0, 0, 0, 0 } }, .position = .{ 0, 0, 10, 100, 0, 0, 0, 2, 0, 0, 0, 3 }, .angles = @splat(0) };
    const shot: Shot = .{ .seconds = 2, .pre = 1, .post = 1, .target = false, .end_on_actor = false, .has_fov = false, .fov = 90, .sky = true, .velocity_modes = .{ 1, 1 }, .target_name = "", .end_name = "", .points = 2, .initial = .{ .position = .{ 100, 2, 3 }, .angles = @splat(0) }, .segments = &.{segment}, .sounds = &.{}, .tracks = &.{} };
    const mid = shot.camera(2000, shot.initial);
    try std.testing.expectEqual(@as(f32, 110), mid.position[0]);
    try std.testing.expectEqual(@as(f32, 75), mid.fov);
    try std.testing.expectEqual(@as(f32, 127.5), mid.blend[3]);
    try std.testing.expectEqual(@as(f32, 120), shot.camera(9000, shot.initial).position[0]);
}
