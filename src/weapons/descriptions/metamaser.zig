// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 26;
pub const spec: profiles.Spec = .{
    .player_grip = .rifle,
    .combat = .metamaser,
    .ammo_class = "ammo_metamaser", // metamaser
    .projectile = .{ .gravity = true, .action_delay_ms = 300, .mins = .{ -6, -6, 0 }, .maxs = .{ 6, 6, 12 } },
    .visual = .{ .projectile_model = "models/e4/we_mmprj.dkm", .projectile_scale = 8, .impact_sprite = "models/e4/we_mmaserexp.sp2", .color = .{ 0, 0, 1 }, .glow = false },
    .world_model = "models/e4/a_mmaser.dkm",
    .animation = .{
        .view_model = "models/e4/w_mmaser.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .raise_ms = 400,
        .drop_ms = 250,
    },
    .audio = .{
        .fire = "e2/we_sflareshoota.wav",
        .ready = "e4/we_metaready.wav",
        .away = "e4/we_metaaway.wav",
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_metamaser", .label = "Metamaser", .episode = 4, .interval = 1000 };

const shot_rules = @import("../shot.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub const flight_tag = "metamaser";
pub const Track = struct { target: u32 = 0, until_ms: i64 = 0, damage_ms: i64 = 0, sound_ms: i64 = 0 };
pub const BallisticState = struct {
    phase: enum { flight, arming, tracking, dying } = .flight,
    settled: bool = false,
    next_ms: i64 = 100,
    arm_ms: i64 = 0,
    beep_ms: i64 = 0,
    pause_ms: i64 = 0,
    end_ms: i64 = 60000,
    burst_ms: i64 = 0,
    bursts: u8 = 0,
    charges: i32 = 120,
    pain_level: i32 = 0,
    receipt: u32 = 0,
    range: f32 = 512,
    targets: [12]Track = @splat(.{}),
    acquired: [4]Track = @splat(.{}),
    pub fn settle(self: *BallisticState, age: i64) void {
        self.settled = true;
        if (self.phase != .flight) return;
        self.phase = .arming;
        self.arm_ms = age + 3000;
        self.beep_ms = age + 500;
        // Reference threshold is based on its 1000-health default, even with supplied 300 health.
        self.pain_level = 700;
    }
    pub fn die(self: *BallisticState, age: i64) void {
        if (self.phase == .dying) return;
        self.phase = .dying;
        self.end_ms = age + 5000;
        self.burst_ms = age;
        self.acquired = @splat(.{});
        self.targets = @splat(.{});
    }
    pub fn include(self: *BallisticState, target: u32, age: i64) bool {
        if (target == 0) return false;
        for (self.targets) |existing| if (existing.target == target) return false;
        for (&self.targets) |*empty| if (empty.target == 0) {
            empty.* = .{ .target = target, .until_ms = age + 3000 };
            return true;
        };
        return false;
    }
    pub fn forget(self: *BallisticState, target: u32) void {
        for (&self.targets) |*track| if (track.target == target) {
            track.* = .{};
        };
        for (&self.acquired) |*track| if (track.target == target) {
            track.* = .{};
        };
    }
    pub fn lock(self: *BallisticState, target: u32, age: i64, random: f32) bool {
        if (target == 0) return false;
        for (self.acquired) |existing| if (existing.target == target) return false;
        for (&self.acquired) |*empty| if (empty.target == 0) {
            empty.* = .{ .target = target, .until_ms = age + 500 + @as(i64, @intFromFloat(500 * random)), .damage_ms = age, .sound_ms = age };
            return true;
        };
        return false;
    }
};
pub const Ring = struct { owner: u32, cube: u32, damage: f32, born_ms: i64, next_ms: i64 };
pub const Laser = struct { owner: u32, cube: u32, damage: f32, next_ms: i64, expires_ms: i64, fired: bool = false, endpoint: [3]f32 = @splat(0) };
pub fn ringDamage(damage: f32, age: i64, distance: f32, vertical: f32, self_hit: bool) f32 {
    if (age < 0 or age > 2000 or @abs(vertical) >= 64) return 0;
    const radius = @as(f32, @floatFromInt(age)) * (425.0 / 2000.0);
    if (distance <= radius - 25 or distance >= radius) return 0;
    return damage * @max(0, (425 - distance) / 425) * (if (self_hit) @as(f32, 0.5) else 1);
}
pub const visual = .{ .ring = "models/e1/we_shockring.sp2", .flare = "models/global/e_flblue.sp2" };
pub const sounds = .{ .beep = "e1/we_c4beepa.wav", .small = [_][:0]const u8{ "e4/we_metamaszapa.wav", "e4/we_metamaszapb.wav" }, .large = [_][:0]const u8{ "e4/we_metamalzapa.wav", "e4/we_metamalzapb.wav" } };
pub fn flightMotion(_: *BallisticState, frame: @import("../ballistics.zig").Frame) @import("../ballistics.zig").Motion {
    return .{ .velocity = frame.velocity, .gravity = 800 };
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
