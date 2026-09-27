// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 25;
pub const spec: profiles.Spec = .{
    .player_grip = .shoulder,
    .combat = .novabeam,
    .ammo_class = "ammo_novabeam", // novabeam
    .visual = .{ .impact_sprite = "models/e4/we_novahit.sp2" },
    .world_model = "models/e4/a_nova.dkm",
    .animation = .{
        .view_model = "models/e4/w_novabeam.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .alternate = "shootb",
        .fire_end = "shootb",
        .raise_ms = 500,
        .drop_ms = 450,
    },
    .audio = .{
        .fire = "e4/we_novafirea.wav",
        .ready = "e4/we_novaready.wav",
        .away = "e4/we_novaaway.wav",
        .finish = "e4/we_novafireb.wav",
    },
};
pub const identity = .{ .classname = "weapon_novabeam", .label = "Novabeam", .episode = 4, .interval = 80 };

const shot_rules = @import("../shot.zig");
pub const muzzle = [3]f32{ 6, 14, 20.6 };
pub const visual = .{ .muzzle = "models/e4/we_mfnbeam.sp2", .flare = "models/global/e_florange.sp2", .color = [3]f32{ 1, 0.4, 0.1 }, .range = 2000 };
pub const Discharge = struct {
    owner: u32,
    born_ms: i64,
    next_ms: i64,
    expires_ms: i64,
    lifetime_ms: i32,
    remaining_damage: f32,
    ammo_cost: i32,
    boost: u8,
    phase: enum { pending, firing, closing, finished } = .pending,
    end_ms: ?i64 = null,
    endpoint: [3]f32 = @splat(0),
    alpha: f32 = 1,
    pub const Tick = struct { consumed: i32 = 0, damage: f32 = 0, finish: bool = false };
    pub fn init(owner: u32, tuning: @import("../values.zig").Values, boost: u8, now: i64) Discharge {
        const duration = lifetime(boost, tuning.lifetime);
        return .{ .owner = owner, .born_ms = now, .next_ms = now + @as(i64, @intFromFloat(200 / @import("../controller.zig").attackFactor(boost))), .expires_ms = now + duration + 200, .lifetime_ms = duration, .remaining_damage = tuning.damage, .ammo_cost = tuning.ammoCost, .boost = boost };
    }
    pub fn advance(self: *Discharge, now: i64, ammunition: i32) Tick {
        if (now < self.next_ms or self.phase == .finished) return .{};
        self.next_ms = now + 100;
        const consumed = @min(ammunition, self.ammo_cost);
        if (self.phase == .closing) {
            self.phase = .finished;
            return .{ .consumed = consumed, .finish = true };
        }
        const damage = self.remaining_damage * @max(0.2, @as(f32, @floatFromInt(self.boost)) * 0.1);
        self.remaining_damage -= damage;
        const remaining = @as(f32, @floatFromInt(self.born_ms + self.lifetime_ms - now + 100)) / @as(f32, @floatFromInt(self.lifetime_ms));
        if (remaining <= 0.5 or ammunition <= consumed) {
            self.phase = .closing;
            self.end_ms = now + 100;
            return .{ .consumed = consumed };
        }
        self.phase = .firing;
        self.alpha = @min(1, remaining + 0.1);
        return .{ .consumed = consumed, .damage = damage };
    }
};
test "novabeam drains a finite burst at timed ticks and closes before cooldown" {
    const std = @import("std");
    var beam = Discharge.init(7, .{ .damage = 250, .ammoCost = 2, .lifetime = 2 }, 0, 1000);
    try std.testing.expectEqual(@as(f32, 0), beam.advance(1199, 100).damage);
    try std.testing.expectEqual(@as(f32, 50), beam.advance(1200, 100).damage);
    try std.testing.expectEqual(@as(f32, 0), beam.advance(1250, 98).damage);
    try std.testing.expectEqual(@as(f32, 40), beam.advance(1300, 98).damage);
    _ = beam.advance(2100, 96);
    try std.testing.expectEqual(.closing, beam.phase);
    try std.testing.expect(beam.advance(2200, 94).finish);
    try std.testing.expectEqual(@as(i64, 3200), beam.expires_ms);
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    result.duration_ms = lifetime(controller.boost(), controller.lifetime(id)) + 200;
    if (controller.ps.ammo[id] >= controller.ammoCost(id)) result.cost = 0;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

pub fn lifetime(boost: i32, seconds: f32) i32 {
    const duration = if (seconds > 0) seconds * 1000 else 2000;
    const scaled = if (boost <= 0) duration else duration / (@as(f32, @floatFromInt(boost + 1)) * 0.5);
    return @intFromFloat(@import("std").math.clamp(scaled, 1, 3600000));
}
