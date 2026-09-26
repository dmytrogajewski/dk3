// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 14;
pub const spec: profiles.Spec = .{
    .combat = .zeus,
    .ammo_class = "ammo_zeus", // zeus
    .ammo_pack = 1,
    .companion_pickup = false,
    .visual = .{ .color = .{ 0.2, 0.65, 1 } },
    .world_model = "models/e2/a_zeus.dkm",
    .animation = .{
        .view_model = "models/e2/w_zeuseye.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .fire_end = "shootc",
        .idle = .{ null, null, null },
        .raise_ms = 750,
        .drop_ms = 500,
    },
    .audio = .{
        .fire = "e2/we_zeusshoot.wav",
        .ready = "e2/we_zeusready.wav",
        .away = "e2/we_zeusaway.wav",
    },
};
pub const identity = .{ .classname = "weapon_zeus", .label = "Eye of Zeus", .episode = 2, .interval = 8000 };

const shot_rules = @import("../shot.zig");
pub const maximum_targets = 20;
pub const visual = .{ .flare = "models/global/e_flblue.sp2", .color = .{ 0.25, 0.45, 0.85 } };
pub const sounds = [_][:0]const u8{ "global/e_lightninga.wav", "global/e_lightningb.wav", "global/e_lightningc.wav" };
pub const Chain = struct {
    owner: u32,
    damage: f32,
    range: f32,
    ammo_cost: i32,
    ready_ms: i64,
    expires_ms: i64,
    phase: enum { pending, active, finished } = .pending,
    closed_ms: ?i64 = null,
    targets: [maximum_targets]u32 = @splat(0),
    count: u8 = 0,
    active: u8 = 0,
    zaps: u8 = 0,
    pub fn contains(self: Chain, target: u32) bool {
        for (self.targets[0..self.count]) |persistent_id| if (persistent_id == target) return true;
        return false;
    }
    pub fn reserve(self: *Chain, target: u32) bool {
        if (self.count == maximum_targets or self.contains(target)) return false;
        self.targets[self.count] = target;
        self.count += 1;
        self.active += 1;
        return true;
    }
    pub fn zap(self: *Chain) f32 {
        const amount = self.damage * (if (self.zaps > 15) @as(f32, 0.25) else if (self.zaps > 10) @as(f32, 0.5) else if (self.zaps > 5) @as(f32, 0.75) else 1);
        self.zaps += 1;
        self.active -|= 1;
        return amount;
    }
};
pub const Bolt = struct {
    owner: u32,
    chain: u32,
    source: u32,
    target: u32,
    born_ms: i64,
    next_ms: i64,
    phase: enum { spreading, zapping, fading } = .spreading,
    endpoint: [3]f32 = @splat(0),
};
pub fn releaseDelay(factor: f32) u32 {
    return @intFromFloat(1750 / factor);
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    // Gold charges only after a target is found (or on a deathmatch miss).
    if (controller.ps.ammo[id] >= result.cost) result.cost = 0;
    result.duration_ms = controller.scaled(1750) + 5000;
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
