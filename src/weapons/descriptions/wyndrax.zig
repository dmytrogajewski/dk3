// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 19;
pub const spec: profiles.Spec = .{
    .combat = .wyndrax,
    .projectile = .{ .action_delay_ms = 500, .mins = @splat(-16), .maxs = @splat(16) },
    .ammo_class = "ammo_wisp", // wyndrax
    .visual = .{ .projectile_model = "models/e3/we_wisp.dkm", .color = .{ 0.25, 0.45, 0.85 }, .glow = false },
    .world_model = "models/e3/a_wyndrx.dkm",
    .animation = .{
        .view_model = "models/e3/w_wisp.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", null, null },
        .raise_ms = 600,
        .drop_ms = 400,
    },
    .audio = .{
        .fire = "e3/we_wwispshoota.wav",
        .ready = "e3/we_wwispready.wav",
        .away = "e3/we_wwispaway.wav",
    },
};
pub const identity = .{ .classname = "weapon_wyndrax", .label = "Wyndrax's wisp", .episode = 3, .interval = 1400 };

const shot_rules = @import("../shot.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}

const std = @import("std");
const v = @import("../vector.zig");
pub const flight_tag = "wyndrax";
pub const sounds = [_][:0]const u8{ "e3/we_wwispcorditea.wav", "e3/we_wwispcorditeb.wav", "e3/we_wwispcorditec.wav" };
pub const flare = "models/global/e_flare4+o.sp2";
pub const BallisticState = struct {
    enemy: ?u32 = null,
    targets: [4]u32 = @splat(0),
    next_ms: i64 = 100,
    sound_ms: i64 = 100,
    sine_ms: i64 = 0,
    phase: enum { active, fading } = .active,
    sine: u8 = 0,
    personality: f32 = 0,
    alpha: f32 = 1,
    scale: v.Vec = @splat(2),

    pub fn include(self: *BallisticState, target: u32) bool {
        if (target == 0) return false;
        for (self.targets) |existing| if (existing == target) return false;
        for (&self.targets) |*empty| if (empty.* == 0) {
            empty.* = target;
            return true;
        };
        return false;
    }
    pub fn steer(self: *BallisticState, heading: v.Vec, distance: f32, random: anytype) v.Vec {
        var velocity = v.scale(v.normal(heading), 150);
        // Reference oscillator samples are rounded to three decimals, at 1 + 30*n degrees.
        const radians = (@as(f32, @floatFromInt(self.sine)) * 30 + 1) * (std.math.pi / 180.0);
        const wobble = 75 * self.personality;
        const axis: usize = if (@abs(@as(i32, @intFromFloat(velocity[0]))) > @abs(@as(i32, @intFromFloat(velocity[1])))) 1 else 0;
        velocity[axis] += @round(@cos(radians) * 1000) * 0.001 * wobble * (if (axis == 1) @as(f32, 1) else -1);
        velocity[2] += @round(@sin(radians) * 1000) * 0.001 * wobble;
        if (distance < 100) {
            const factor: f32 = if (distance < 64) -1 else 0;
            velocity[0] *= factor;
            velocity[1] *= factor;
        }
        self.sine = (self.sine + 1) % 12;
        if (self.sine == 0 and random.next() > 0.55) self.personality = random.next();
        return velocity;
    }
    pub fn fade(self: *BallisticState) bool {
        self.alpha -= 0.05;
        self.scale[0] -= 0.1;
        self.scale[1] -= 0.1;
        self.scale[2] += if (self.alpha < 0.5) @as(f32, -0.2) else 0.1;
        return self.alpha < 0.001 or self.scale[0] <= 0.1;
    }
};
pub fn flightMotion(_: *BallisticState, frame: @import("../ballistics.zig").Frame) @import("../ballistics.zig").Motion {
    return .{ .velocity = frame.velocity };
}
