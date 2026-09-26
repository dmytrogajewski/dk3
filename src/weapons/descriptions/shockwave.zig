// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 6;
pub const spec: profiles.Spec = .{
    .combat = .shockwave,
    .splash_hazard = true,
    .ammo_class = "ammo_shocksphere", // shockwave
    .ammo_pack = 1,
    .projectile = .{ .mins = @splat(-15), .maxs = @splat(15), .direct_scale = 3, .splash_scale = 0.75, .splash_radius = 300, .action_delay_ms = 1600, .recoil = 200, .recoil_on_launch = true, .sound_on_launch = false, .lifetime_ms = 60000 },
    .visual = .{ .projectile_model = "models/e1/we_3dshock.dkm", .projectile_scale = 15, .impact_sprite = "models/e1/we_shockexp.sp2", .blast_sound = "e1/we_shockwaveexp.wav", .color = .{ 1, 1, 1 }, .glow = false },
    .world_model = "models/e1/a_shokwv.dkm",
    .animation = .{
        .view_model = "models/e1/w_shockwave.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", null, null },
        .raise_ms = 400,
        .drop_ms = 350,
    },
    .audio = .{
        .ammo_pickup = "global/i_swaveammo.wav",
        .fire = "e1/we_shockwaveshoota.wav",
        .ready = "e1/we_shockwaveready.wav",
        .away = "e1/we_shockwaveaway.wav",
        .hum = "e1/we_shockwaveamba.wav",
    },
    .projectile_muzzle = true,
    .muzzle = .{ .model = "models/e1/we_mfswave.sp2", .sprite = true, .delay_ms = 1600, .scale = 0.285, .color = .{ 1, 1, 1 } },
};
pub const identity = .{ .classname = "weapon_shockwave", .label = "Shockwave", .episode = 1, .interval = 2850 };

const v = @import("../vector.zig");
const flight = @import("../ballistics.zig");
pub const flight_tag = "shockwave";
pub const BallisticState = struct { next_ms: i64 = 100, last_ring: ?v.Vec = null, rings: u8 = 0, touched_water: bool = false };
pub fn flightMotion(_: *BallisticState, frame: flight.Frame) flight.Motion {
    return .{ .velocity = frame.velocity };
}
pub const Flight = struct { velocity: v.Vec, trail: bool = false, explode: bool = false };
pub fn think(state: *BallisticState, age: i64, wet: bool, position: v.Vec, velocity: v.Vec) Flight {
    var result: Flight = .{ .velocity = velocity };
    if (age < state.next_ms) return result;
    state.next_ms = age + 100;
    if (wet) {
        state.touched_water = true;
        if (v.length(result.velocity) > 100) result.velocity = v.scale(v.normal(result.velocity), 100);
    }
    if (v.length(result.velocity) < 1) {
        result.explode = true;
    } else if (state.rings < 6 and v.distance(position, state.last_ring orelse position) > 75) {
        state.rings += 1;
        state.last_ring = position;
        result.trail = true;
    } else result.velocity[2] -= 50;
    return result;
}
pub const Ring = struct { start_ms: i64 = 0, inner: f32 = 0, outer: f32 = 15 };
pub const Wave = struct {
    owner: u32,
    damage: f32,
    born_ms: i64,
    next_ms: i64,
    count: u8 = 1,
    rings: [6]Ring = @splat(.{}),
    pub fn init(owner: u32, damage: f32, now: i64) Wave {
        var value: Wave = .{ .owner = owner, .damage = damage, .born_ms = now, .next_ms = now + 50 };
        value.rings[0].start_ms = now;
        return value;
    }
    /// Damage uses each preceding band, then expansion and the next ring commit.
    pub fn advance(self: *Wave, now: i64) bool {
        for (self.rings[0..self.count]) |*ring| {
            ring.inner = ring.outer - 20;
            ring.outer = if (now >= ring.start_ms + 3000) 350 else @as(f32, @floatFromInt(@max(0, now - ring.start_ms))) * (350.0 / 3000.0);
        }
        if (self.count < self.rings.len and now >= self.rings[self.count - 1].start_ms + 500) {
            self.rings[self.count] = .{ .start_ms = now };
            self.count += 1;
        }
        self.next_ms = now + 50;
        return self.rings[self.count - 1].outer >= 350;
    }
};
pub fn ringDamage(base: f32, distance: f32, owner: bool, in_pvs: bool, visible: bool) f32 {
    return base * @max(0, 1 - distance * 0.001) * (if (owner) @as(f32, 0.5) else 1) * (if (!in_pvs) @as(f32, 0.05) else if (!visible) @as(f32, 0.9) else 1);
}
pub fn pushDirection(delta: v.Vec) v.Vec {
    var result = v.normal(delta);
    if (result[2] > -0.1 and result[2] < 0.4) result[2] = 0.4;
    return result;
}
pub const ring_visual = .{ .sprite = "models/e1/we_shockring.sp2", .duration_ms = 3000, .start_scale = 1.0, .end_scale = 14.0, .alpha = 51 };
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    if (context.trail) return .{ .sprite = "models/e1/we_shotring.sp2", .sprite_scale = 0.5, .sprite_rate = 20, .oriented = true, .additive = false, .alpha = 245, .fade = true, .color = .{ 0.25, 0.25, 1 }, .light_radius = 200, .light_ms = 500 };
    if (context.detonation) return .{ .sprite = spec.visual.impact_sprite, .sprite_scale = 1.5, .sound = if (context.sequence == 0) spec.visual.blast_sound else null };
    return .{ .sprite = "models/e1/we_shockwall.sp2", .sprite_scale = 2, .oriented = true, .additive = false };
}
test "shockwave expands six persistent bands and water arms the next contact" {
    const std = @import("std");
    var wave = Wave.init(7, 150, 1000);
    try std.testing.expectEqual(@as(f32, 15), wave.rings[0].outer);
    try std.testing.expect(!wave.advance(1050));
    try std.testing.expectApproxEqAbs(@as(f32, 350.0 / 60.0), wave.rings[0].outer, 0.001);
    var now: i64 = 1100;
    while (now < 6500) : (now += 50) try std.testing.expect(!wave.advance(now));
    try std.testing.expectEqual(@as(u8, 6), wave.count);
    try std.testing.expect(wave.advance(6500));
    var state: BallisticState = .{ .last_ring = .{ 0, 0, 0 } };
    const motion = think(&state, 100, true, .{ 100, 0, 0 }, .{ 700, 0, 0 });
    try std.testing.expect(motion.trail and state.touched_water);
    try std.testing.expectEqual(@as(f32, 100), motion.velocity[0]);
    try std.testing.expectApproxEqAbs(@as(f32, 67.5), ringDamage(150, 0, true, true, false), 0.001);
}

const shot_rules = @import("../shot.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
