// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 20;
pub const spec: profiles.Spec = .{ // nightmare
    .combat = .nightmare,
    .visual = .{ .projectile_model = "models/e3/we_nnreaper.dkm", .color = .{ 0.9, 0.2, 1 } },
    .world_model = "models/e3/a_nmare.dkm",
    .animation = .{
        .view_model = "models/e3/w_nmare.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoot",
        .idle = .{ "amba", "ambb", "ambc" },
        .raise_ms = 750,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e3/we_chant5.wav",
        .ready = "e3/we_nharreready.wav",
        .away = "e3/we_nharreaway.wav",
    },
};
pub const identity = .{ .classname = "weapon_nightmare", .label = "Nharre's Nightmare", .episode = 3, .interval = 90000 };

const shot_rules = @import("../shot.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var shot = shot_rules.standard(controller);
    shot.duration_ms = 90000;
    return shot;
}

pub const maximum_targets = 10;
pub const Phase = enum { casting, waiting, appearing, reaping, after };
pub const Ritual = struct {
    owner: u32,
    damage: f32,
    range: f32,
    born_ms: i64,
    next_ms: i64,
    phase_ms: i64,
    phase: Phase = .casting,
    targets: [maximum_targets]u32 = @splat(0),
    count: u8 = 0,
    cursor: u8 = 0,
    victim: ?u32 = null,
    previous_view_height: f32 = 22,
    pub fn mark(self: *Ritual, target: u32) bool {
        if (target == 0 or self.count == maximum_targets) return false;
        for (self.targets[0..self.count]) |previous| if (previous == target) return false;
        self.targets[self.count] = target;
        self.count += 1;
        return true;
    }
    pub fn advance(self: *Ritual, phase: Phase, now: i64, delay: i64) void {
        self.phase = phase;
        self.phase_ms = now;
        self.next_ms = now + delay;
    }
};
pub fn searchDelay(factor: f32) i64 {
    // Supplied shoot frames 119..183: wait for last-2, sampled every 100 ms, then search.
    return @as(i64, @intFromFloat(@ceil(3100 / factor / 100))) * 100 + 100;
}
pub const strike_ms: i64 = 4200; // Supplied reaper ataka 0..43 at 10 fps, damage at last-1.
pub const visual = .{ .pentagram = "models/e3/we_nnpent.dkm", .flame = "models/global/we_nharref.sp2" };
pub const sounds = .{ .appear = "e3/we_reaperappear2.wav", .wind = "e3/we_nharrewind.wav", .strike = "e3/we_reaperattack2.wav" };

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
