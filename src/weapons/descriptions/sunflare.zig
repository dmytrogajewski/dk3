// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 10;
pub const spec: profiles.Spec = .{
    .player_grip = .glove, // sunflare
    .combat = .sunflare,
    .projectile = .{ .gravity = true, .mins = .{ -12, -12, -18 }, .maxs = .{ 12, 12, 18 }, .action_delay_ms = 400, .lifetime_ms = 60000 },
    .visual = .{ .projectile_model = "models/e2/we_sunprj.dkm", .projectile_scale = 2, .blast_sound = "e2/we_sflareexplodea.wav", .spin = true },
    .world_model = "models/e2/a_sflare.dkm",
    .animation = .{
        .view_model = "models/e2/w_sflare.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e2/we_sflareshoota.wav",
        .ready = "e2/we_sflareready.wav",
        .away = "e2/we_sflareaway.wav",
        .hum = "e2/we_sflareamba.wav",
        .idle = .{ "e2/we_sflareamba.wav", null, null },
    },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_sunflare", .label = "Sunflare", .episode = 2, .interval = 900 };

const shot_rules = @import("../shot.zig");
const ballistic = @import("../ballistics.zig");
pub const flight_tag = "sunflare";
pub const visual = .{ .fire = "models/global/e2_firea.sp2", .glow = "models/global/e_sflorange.sp2", .burn_sound = "e2/we_sflareexploded.wav" };
pub const Phase = enum { flight, settling, burning, cooling };
pub const BallisticState = struct {
    phase: Phase = .flight,
    next_ms: i64 = 100,
    burn_ms: i64 = 0,
    flames: u8 = 0,
    floating: bool = false,
    angular_velocity: [3]f32 = .{ 90, 90, 90 },
    pub fn ignite(self: *BallisticState, age: i64) void {
        self.phase = .settling;
        self.next_ms = age + 100;
    }
    pub fn burn(self: *BallisticState, age: i64, random: f32) void {
        self.phase = .burning;
        self.burn_ms = age;
        self.next_ms = age + 100;
        self.flames = @intFromFloat(5 + 4.9 * random);
    }
    pub fn radius(self: BallisticState) f32 {
        return 60 + 10 * @as(f32, @floatFromInt(self.flames));
    }
    pub fn damage(self: BallisticState, base: f32) f32 {
        return 3 * (base + 0.25 * @as(f32, @floatFromInt(self.flames)));
    }
    pub fn visualRadius(self: BallisticState) f32 {
        return 50 + 10 * @as(f32, @floatFromInt(self.flames -| 5));
    }
};
pub fn buoyancy(velocity: [3]f32, submerged: f32, fluid_density: f32, seconds: f32) [3]f32 {
    var result = velocity;
    if (submerged <= 0) {
        result[2] -= 1200 * seconds;
        return result;
    }
    result[2] += 1200 / fluid_density * seconds * (fluid_density * 2 / 1.85 * submerged - 1);
    const retention = @import("std").math.pow(f32, (0.9875 + (fluid_density - 1) * 0.7125) / fluid_density * 0.9, seconds * 10);
    result[0] *= retention;
    result[1] *= retention;
    if (@abs(result[2]) > 32) result[2] *= retention;
    return result;
}
pub fn appearance(age_ms: i32) struct { scale: f32, alpha: f32 } {
    const ticks: f32 = @floatFromInt(@divTrunc(@max(0, age_ms), 50));
    return .{ .scale = @max(1, 2 - 0.015 * ticks), .alpha = @max(0, 0.6 - 0.015 * @max(0, ticks - 66)) };
}
pub fn flightLaunch(tuning: @import("../values.zig").Values, _: i32, _: u8) ballistic.Launch {
    var muzzle = tuning.muzzle;
    muzzle[1] += 13;
    muzzle[2] -= 5;
    return .{ .muzzle = muzzle, .pitch = -22.5 };
}
pub fn flightMotion(_: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    return .{ .velocity = frame.velocity, .gravity = 800 };
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    return @import("../impact.zig").explosion(spec.visual, context);
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
