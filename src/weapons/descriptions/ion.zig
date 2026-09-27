// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 2;
pub const spec: profiles.Spec = .{
    .combat = .{ .ion = .{ .radius = 2, .water_radius = 64, .bounce_retention = 1.25, .max_bounces = 3, .cleanup_ms = 30000 } },
    .companion_episode = 1,
    .ammo_class = "ammo_ionpack", // ion
    .ammo_pack = 50,
    .projectile = .{ .water_collision = true, .loop_sound = "e1/we_ionflyby.wav" },
    .visual = .{ .projectile_model = "models/e1/we_ionbl.dkm", .impact_sprite = "models/e1/we_ionexpl.sp2", .blast_sound = "e1/we_ionexplodea.wav", .color = .{ 0, 0.8, 0 } },
    .world_model = "models/e1/a_ion.dkm",
    .animation = .{
        .view_model = "models/e1/w_ionblaster.dkm",
        .ready = "ready",
        .away = "away",
        .fire = "shoota",
        .idle = .{ "amba", "ambb", null },
        .raise_ms = 300,
        .drop_ms = 350,
    },
    .audio = .{
        .ammo_pickup = "global/i_ionammo.wav",
        .fire = "e1/we_ionshootb.wav",
        .ready = "e1/we_ionready.wav",
        .away = "e1/we_ionaway.wav",
        .hum = "e1/we_ionamba.wav",
    },
    .muzzle = .{ .model = "models/global/genflashg.dkm", .scale = 3, .alpha = 102, .offset = -2, .color = .{ 0, 1, 0 }, .shader = "dk3/fx/ion-flash" },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_ionblaster", .label = "Ion blaster", .episode = 1, .interval = 500 };

const v = @import("../vector.zig");
/// Close crosshair contact may be behind the offset muzzle. Preserve that aim;
/// forcing the view direction sends the bolt below/alongside a nearby target.
pub fn launchDirection(muzzle: v.Vec, crosshair: v.Vec) v.Vec {
    return v.normal(v.sub(crosshair, muzzle));
}

test "ion converges on close crosshair contact even behind the muzzle" {
    const std = @import("std");
    // Captured ordinary e1m1a skeet encounter: the old forward-only guard missed.
    const start: v.Vec = .{ -691.340, -1397.472, 516.076 };
    const hit: v.Vec = .{ -690.139, -1401.486, 523.946 };
    const forward: v.Vec = .{ -0.995, 0.012, 0.104 };
    const direction = launchDirection(start, hit);
    try std.testing.expect(v.dot(direction, forward) < 0);
    try std.testing.expectApproxEqAbs(@as(f32, 1), v.length(direction), 0.0001);
    try std.testing.expect(v.distance(hit, v.madd(start, v.distance(start, hit), direction)) < 0.001);
    try std.testing.expectEqual(v.Vec{ 1, 0, 0 }, launchDirection(.{ 20, 4, 16 }, .{ 2000, 4, 16 }));
    try std.testing.expectEqual(v.zero, launchDirection(start, start));
}

pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    const sparks = [_][:0]const u8{ "global/e_electronsprka.wav", "global/e_electronsprke.wav", "global/e_electronsprkg.wav", "global/e_electronsprkh.wav" };
    const explosions = [_][:0]const u8{ "e1/we_ionexplodea.wav", "e1/we_ionexplodea.wav", "e1/we_ionexplodeb.wav", "e1/we_ionexplodeb.wav", "e1/we_ionexplodec.wav" };
    return .{ .sprite = if (context.kind == .flesh or context.kind == .water) spec.visual.impact_sprite else null, .sound = switch (context.kind) {
        .flesh => explosions[(context.serial *% 7) % explosions.len],
        .water => null,
        else => sparks[context.serial % sparks.len],
    }, .particles = if (context.kind == .flesh) 12 else 8, .particle_shader = "dk3/particle/ion-sparkle", .color = .{ 0.1, 0.9, 0.1 }, .light_radius = 120 };
}
test "ion flesh impacts use explosions, world impacts sparks, water no metal sound" {
    const std = @import("std");
    for (0..20) |serial| {
        const flesh = impact(.{ .kind = .flesh, .serial = @intCast(serial) });
        const wall = impact(.{ .kind = .world, .serial = @intCast(serial) });
        try std.testing.expect(std.mem.startsWith(u8, flesh.sound.?, "e1/we_ionexplode"));
        try std.testing.expect(std.mem.startsWith(u8, wall.sound.?, "global/e_electronspr"));
    }
    try std.testing.expect(impact(.{ .kind = .water, .serial = 1 }).sound == null);
}

const shot_rules = @import("../shot.zig");
const state = @import("../weapon_state.zig");
const sword = @import("../sword_rules.zig");
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    return shot_rules.standard(controller);
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
