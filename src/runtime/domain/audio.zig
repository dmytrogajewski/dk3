// SPDX-License-Identifier: GPL-2.0-or-later
//! Authored positional sound parameters shared by server transport and client mixer.
const std = @import("std");
pub const parameter_tag = 10030;
pub const Parameters = struct {
    volume: f32 = 1,
    minimum: f32 = 256,
    maximum: f32 = 648,
    nondirectional: bool = false,
    pub fn valid(self: Parameters) bool {
        return std.math.isFinite(self.volume) and std.math.isFinite(self.minimum) and std.math.isFinite(self.maximum) and self.volume >= 0 and self.volume <= 1 and self.minimum >= 0 and self.maximum > self.minimum and self.maximum <= 65536;
    }
};
pub const Speaker = struct {
    sounds: [6]u16 = @splat(0),
    count: u4 = 0,
    parameters: Parameters = .{},
    loopable: bool = false,
    active: bool = false,
    reliable: bool = false,
    delay_secs: u32 = 0,
    timed: bool = false,
    minimum_secs: u32 = 0,
    next_ms: ?i64 = null,
    random: u32 = 1,
    pub fn start(self: *Speaker, flags: u32, named: bool, now: i64) void {
        self.parameters.nondirectional = flags & 8 != 0;
        self.reliable = flags & 4 != 0;
        self.active = self.count <= 1 and flags & 1 != 0;
        self.loopable = self.active or flags & 2 != 0;
        if (!self.active) {
            if (self.count > 1 and self.delay_secs == 0 and !named) self.delay_secs = 3;
            self.timed = self.delay_secs > 0;
            if (self.timed and flags & (16 | 2) == 0) self.next_ms = now + 1000;
        }
    }
    pub fn draw(self: *Speaker, limit: u32) u32 {
        self.random = self.random *% 1664525 +% 1013904223;
        return if (limit == 0) 0 else (self.random >> 8) % limit;
    }
    pub fn interval(self: *Speaker) i64 {
        return @max(100, @as(i64, @max(self.minimum_secs, self.draw(self.delay_secs))) * 1000);
    }
};

test "speaker loop eligibility, start-off and random delay survive a copy" {
    const t = std.testing;
    var loop: Speaker = .{ .count = 1 };
    loop.start(1, false, 2000);
    try t.expect(loop.active and loop.loopable and loop.next_ms == null);
    var random: Speaker = .{ .count = 3, .minimum_secs = 2 };
    random.start(1, false, 2000);
    try t.expect(!random.active and !random.loopable);
    try t.expectEqual(@as(u32, 3), random.delay_secs);
    try t.expectEqual(@as(?i64, 3000), random.next_ms);
    var restored = random;
    for (0..16) |_| {
        try t.expectEqual(random.draw(3), restored.draw(3));
        const interval = random.interval();
        try t.expectEqual(interval, restored.interval());
        try t.expectEqual(@as(i64, 2000), interval);
    }
    var triggered: Speaker = .{ .count = 3 };
    triggered.start(4 | 8 | 16, true, 2000);
    try t.expect(triggered.reliable and triggered.parameters.nondirectional and triggered.next_ms == null and triggered.delay_secs == 0);
    var off: Speaker = .{ .count = 1, .delay_secs = 10 };
    off.start(2, false, 2000);
    try t.expect(off.loopable and !off.active and off.next_ms == null);
}

/// Original one-shot and looping transports encode gain as an unsigned byte.
/// Supplied maps include gain 2; retain the observable 254/255 wire gain.
pub fn wireVolume(value: f32) !f32 {
    if (!std.math.isFinite(value) or value < 0 or value > 1000000) return error.InvalidSoundVolume;
    const encoded: u32 = @intFromFloat(value * 255);
    return @as(f32, @floatFromInt(encoded & 255)) / 255;
}
test "authored gains retain original byte quantization including supplied gain two" {
    try std.testing.expectEqual(@as(f32, 254.0 / 255.0), try wireVolume(2));
    try std.testing.expectEqual(@as(f32, 127.0 / 255.0), try wireVolume(0.5));
    try std.testing.expectError(error.InvalidSoundVolume, wireVolume(-1));
}

pub fn soundPath(path: []const u8, normalized: []u8) ![]const u8 {
    var length: usize = 0;
    for (path) |char| {
        const next = if (char == '\\') '/' else std.ascii.toLower(char);
        // Map keys also spell paths as "/doors/...". Resource paths are
        // relative to sounds; retaining that slash creates sounds//doors/...
        // and fails resident-world media admission after restoring old saves.
        if (next == '/' and (length == 0 or normalized[length - 1] == '/')) continue;
        if (length == normalized.len) return error.InvalidResourcePath;
        normalized[length] = next;
        length += 1;
    }
    const name = normalized[0..length];
    return if (std.mem.startsWith(u8, name, "sounds/")) name[7..] else name;
}

test "authored sound separators normalize without replacing the named asset" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("global/e_forcefield.wav", try soundPath("Sounds\\GLOBAL\\\\e_forcefield.wav", &buffer));
    try std.testing.expectEqualStrings("global/e_forcefield.wav", try soundPath("global//e_forcefield.wav", &buffer));
    try std.testing.expectEqualStrings("weapons/ion/fire.wav", try soundPath("weapons/ion/fire.wav", &buffer));
    try std.testing.expectEqualStrings("doors/e1/hydrolic2loop.wav", try soundPath("/doors/e1/hydrolic2loop.wav", &buffer));
    try std.testing.expectEqualStrings("doors/e1/hydrolic2loop.wav", try soundPath("\\Sounds\\doors\\e1\\hydrolic2loop.wav", &buffer));
}
