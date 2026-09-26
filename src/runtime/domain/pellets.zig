// SPDX-License-Identifier: GPL-2.0-or-later
//! A blast divides damage across the full pellet count and bounds distinct victims.
const std = @import("std");
const v = @import("vector.zig");
pub fn direction(forward: v.Vec3, right: v.Vec3, horizontal: f32, vertical: f32, spread: f32) v.Vec3 {
    const up = v.cross(right, forward);
    return v.normalize(v.add(forward, v.add(v.scale(right, (horizontal * 2 - 1) * spread), v.scale(up, (vertical * 2 - 1) * spread))));
}
pub const Hits = struct {
    ids: [12]u32 = @splat(0),
    counts: [12]u8 = @splat(0),
    used: usize = 0,
    pub fn add(self: *Hits, id: u32, maximum: usize) void {
        for (self.ids[0..self.used], 0..) |prior, i| if (prior == id) {
            self.counts[i] += 1;
            return;
        };
        if (self.used >= @min(maximum, self.ids.len)) return;
        self.ids[self.used] = id;
        self.counts[self.used] = 1;
        self.used += 1;
    }
    pub fn damage(self: Hits, index: usize, damage_per_blast: f32, total_pellets: u8) f32 {
        return damage_per_blast * @as(f32, @floatFromInt(self.counts[index])) / @as(f32, @floatFromInt(total_pellets));
    }
};
test "missed and capped pellets never redistribute damage to other victims" {
    var hits: Hits = .{};
    hits.add(5, 2);
    hits.add(9, 2);
    hits.add(5, 2);
    hits.add(11, 2);
    try std.testing.expectEqual(@as(usize, 2), hits.used);
    try std.testing.expectEqual(@as(f32, 20), hits.damage(0, 100, 10));
    try std.testing.expectEqual(@as(f32, 10), hits.damage(1, 100, 10));
    try std.testing.expectEqual(v.Vec3{ 1, 0, 0 }, direction(.{ 1, 0, 0 }, .{ 0, -1, 0 }, 0.5, 0.5, 0.1));
}
