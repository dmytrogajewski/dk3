// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 3;
pub const spec: profiles.Spec = .{
    .player_grip = .rifle,
    .combat = .charge,
    .reselect_command = "detonate",
    .splash_hazard = true,
    .ammo_class = "ammo_c4", // c4
    .projectile = .{ .gravity = true, .splash_scale = 1, .splash_radius = 300 },
    .visual = .{ .projectile_model = "models/e1/we_c4prj.dkm", .blast_sound = "global/e_explode1.wav", .color = .{ 1, 0.5, 0 }, .glow = false },
    .world_model = "models/e1/a_c4.dkm",
    .animation = .{
        .view_model = "models/e1/w_c4.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .reselect = "btnpsh",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 350,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e1/we_c4shoota.wav",
        .ready = "e1/we_c4ready.wav",
        .away = "e1/we_c4away.wav",
        .idle = .{ null, "e1/we_c4ambb.wav", null },
    },
    .projectile_muzzle = true,
};

pub const chain_range: f32 = 200;
pub const blast_range: f32 = 300;
pub const trigger_range: f32 = 150;
pub const sense_range: f32 = 300;
pub const max_deployed: usize = 4;
pub const beep_sound = "e1/we_c4beepa.wav";
pub const Charge = struct {
    owner: u32,
    damage: f32,
    born_ms: i64,
    stepped_ms: i64,
    next_ms: i64,
    expires_ms: i64,
    detonate_ms: ?i64 = null,
    beep_ms: ?i64 = null,
    attached: bool = false,
    pub fn schedule(self: *Charge, at: i64) void {
        self.detonate_ms = @min(self.detonate_ms orelse at, at);
    }
    pub fn attach(self: *Charge, now: i64) void {
        self.attached = true;
        self.next_ms = now + 1000;
    }
    pub fn sensing(self: *Charge, distance: f32, now: i64) enum { none, beep, explode } {
        if (!self.attached or distance >= sense_range) return .none;
        if (distance < trigger_range) return .explode;
        if (now - (self.beep_ms orelse self.born_ms) <= @as(i64, @intFromFloat(distance * 2))) return .none;
        self.beep_ms = now;
        return .beep;
    }
};
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    if (context.detonation) return @import("../impact.zig").explosion(spec.visual, context);
    return .{ .sound = switch (context.kind) {
        .metal => "e1/we_c4metala.wav",
        .wood => "e1/we_c4wooda.wav",
        else => "e1/we_c4cona.wav",
    } };
}
test "charge arming and chain scheduling retain the earliest deadline" {
    const std = @import("std");
    var charge: Charge = .{ .owner = 1, .damage = 100, .born_ms = 0, .stepped_ms = 0, .next_ms = 50, .expires_ms = 10000 };
    try std.testing.expectEqual(.none, charge.sensing(100, 500));
    charge.attach(1000);
    try std.testing.expectEqual(@as(i64, 2000), charge.next_ms);
    try std.testing.expectEqual(.beep, charge.sensing(200, 2000));
    try std.testing.expectEqual(.none, charge.sensing(200, 2300));
    try std.testing.expectEqual(.explode, charge.sensing(100, 2400));
    charge.schedule(3000);
    charge.schedule(3200);
    charge.schedule(2900);
    try std.testing.expectEqual(@as(?i64, 2900), charge.detonate_ms);
}
pub const identity = .{ .classname = "weapon_c4", .label = "C4 Vizatergo", .episode = 1, .interval = 1350 };

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
