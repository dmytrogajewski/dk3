// SPDX-License-Identifier: GPL-2.0-or-later
//! Navigation values and policy. Routes propose movement; collision remains authoritative.
const std = @import("std");
const v = @import("vector.zig");
pub const Mode = enum { easy, normal, hard, dm, ctf, deathtag };
pub fn selection(bytes: []const u8, wanted: Mode) ![]const u8 {
    var tokens = std.mem.tokenizeAny(u8, bytes, " \t\r\n");
    if (!std.mem.eql(u8, tokens.next() orelse "", "dk3_navigation") or !std.mem.eql(u8, tokens.next() orelse "", "1")) return error.NavigationHeader;
    var seen: u8 = 0;
    var result: ?[]const u8 = null;
    while (tokens.next()) |name| {
        const mode = std.meta.stringToEnum(Mode, name) orelse return error.NavigationMode;
        const bit = @as(u8, 1) << @intFromEnum(mode);
        if (seen & bit != 0) return error.DuplicateNavigationMode;
        seen |= bit;
        const value = tokens.next() orelse return error.NavigationName;
        if (value.len == 0 or value.len >= 64) return error.NavigationName;
        for (value) |char| if (!(char >= 'a' and char <= 'z') and !std.ascii.isDigit(char) and char != '_' and char != '-') return error.NavigationName;
        if (mode == wanted) result = value;
    }
    return result orelse error.MissingNavigationMode;
}
pub const Waypoint = struct { point: v.Vec3, jump: bool = false, from_area: i32 = 0, to_area: i32 = 0 };
pub const Request = struct { position: v.Vec3, destination: v.Vec3, slot: u16 };
pub const Service = struct {
    context: *anyopaque,
    next_fn: *const fn (*anyopaque, Request) anyerror!?Waypoint,
    pub fn next(self: Service, request: Request) !?Waypoint {
        return self.next_fn(self.context, request);
    }
};
pub const State = struct {
    destination: v.Vec3 = @splat(0),
    waypoint: ?Waypoint = null,
    refresh_ms: i64 = 0,
    progress_ms: i64 = 0,
    progress_position: v.Vec3 = @splat(0),
    blocked: bool = false,
    fleeing: bool = false,
    pub fn update(self: *State, service: Service, request: Request, now: i64) !?Waypoint {
        const changed = v.length(v.subtract(request.destination, self.destination)) > 48;
        if (v.length(v.subtract(request.position, self.progress_position)) > 8 or changed) {
            self.progress_position = request.position;
            self.progress_ms = now;
            self.blocked = false;
        } else if (now - self.progress_ms >= 750) {
            self.blocked = true;
        }
        const reached = if (self.waypoint) |point| horizontalDistance(request.position, point.point) < 16 else false;
        if (changed or reached or now >= self.refresh_ms) {
            self.destination = request.destination;
            self.waypoint = try service.next(request);
            self.refresh_ms = now + if (self.blocked) @as(i64, 200) else 400;
        }
        return self.waypoint;
    }
};
pub fn horizontalDistance(a: v.Vec3, b: v.Vec3) f32 {
    return @sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]));
}
pub fn velocity(position: v.Vec3, destination: v.Vec3, speed: f32, delta: f32) v.Vec3 {
    var direction = v.subtract(destination, position);
    direction[2] = 0;
    const distance = v.length(direction);
    if (distance < 0.01 or delta <= 0) return @splat(0);
    return v.scale(direction, @min(speed, distance / delta) / distance);
}
test "navigation selection rejects ambiguous and unsafe asset names" {
    try std.testing.expectEqualStrings("e1m1c-normal", try selection("dk3_navigation 1 easy e1m1c normal e1m1c-normal hard e1m1c-hard", .normal));
    try std.testing.expectError(error.DuplicateNavigationMode, selection("dk3_navigation 1 dm a dm b", .dm));
    try std.testing.expectError(error.NavigationName, selection("dk3_navigation 1 dm ../a", .dm));
    try std.testing.expectError(error.MissingNavigationMode, selection("dk3_navigation 1 dm a", .hard));
}
test "route invalidation follows progress, goal changes and endpoint arrival" {
    const Fake = struct {
        calls: usize = 0,
        fn next(raw: *anyopaque, request: Request) !?Waypoint {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            return .{ .point = request.destination };
        }
    };
    var fake: Fake = .{};
    const service: Service = .{ .context = &fake, .next_fn = Fake.next };
    var state: State = .{};
    const request: Request = .{ .position = @splat(0), .destination = .{ 100, 0, 0 }, .slot = 3 };
    _ = try state.update(service, request, 0);
    _ = try state.update(service, request, 100);
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
    _ = try state.update(service, request, 800);
    try std.testing.expect(state.blocked);
    _ = try state.update(service, .{ .position = .{ 90, 0, 0 }, .destination = request.destination, .slot = 3 }, 850);
    try std.testing.expect(!state.blocked);
    try std.testing.expectEqual(@as(usize, 3), fake.calls);
    try std.testing.expectApproxEqAbs(@as(f32, 20), velocity(.{ 99, 0, 0 }, request.destination, 300, 0.05)[0], 0.001);
}
