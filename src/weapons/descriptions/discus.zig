// SPDX-License-Identifier: GPL-2.0-or-later
const profiles = @import("../profiles.zig");
pub const id: u5 = 9;
pub const spec: profiles.Spec = .{
    .companion = .{ .slot = 0, .ammunition = false, .empty_melee = true, .clearance = 8 },
    .player_grip = .glove, // discus
    .combat = .discus,
    .visual = .{ .projectile_model = "models/e2/we_discus.dkm", .glow = false },
    .world_model = "models/e2/a_discus.dkm",
    .animation = .{
        .view_model = "models/e2/w_discus.dkm",
        .ready = "readya",
        .away = "awaya",
        .fire = "shootb",
        .idle = .{ "amba", "ambb", null },
        .alternate = "shootc",
        .raise_ms = 400,
        .drop_ms = 350,
    },
    .audio = .{
        .fire = "e2/we_discfire.wav",
        .ready = "e2/we_discreadya.wav",
        .away = "e2/we_discawaya.wav",
    },
    .projectile = .{ .loop_sound = "e2/we_discshoota.wav", .mins = .{ -8, -8, -4 }, .maxs = .{ 8, 8, 4 }, .action_delay_ms = 300, .inertial = true, .lifetime_ms = 60000 },
    .projectile_muzzle = true,
};
pub const identity = .{ .classname = "weapon_discus", .label = "Discus of Daedalus", .episode = 2, .interval = 650 };

const shot_rules = @import("../shot.zig");
const v = @import("../vector.zig");
const ballistic = @import("../ballistics.zig");
pub const flight_tag = "discus";
pub const catch_sound = "e2/we_disccatch.wav";
pub const BallisticState = struct {
    next_ms: i64 = 100,
    drop_ms: i64 = 5000,
    target: ?u32 = null,
    forward: v.Vec = .{ 1, 0, 0 },
    base_speed: f32 = 1000,
    speed: f32 = 1000,
    clear: u8 = 0,
    seek: bool = true,
    reflected: bool = false,
    dropped: bool = false,
    pickup_only: bool = false,
    pub fn tick(self: *BallisticState, age: i64, wet: bool) bool {
        if (age < self.next_ms) return false;
        self.next_ms = age + 100;
        self.clear -|= 1;
        self.speed = if (wet) self.speed * 0.75 else @min(self.base_speed, self.speed * 1.25);
        return true;
    }
    pub fn mustDrop(self: BallisticState, age: i64) bool {
        return age >= self.drop_ms or self.speed < self.base_speed / 8;
    }
    pub fn drop(self: *BallisticState, owner: u32, age: i64) void {
        self.dropped = true;
        self.pickup_only = true;
        self.target = owner;
        self.seek = true;
        self.drop_ms = age + 5000;
    }
    pub fn home(self: *BallisticState, delta: v.Vec, owner: bool) void {
        self.forward = v.normal(if (owner) delta else v.add(v.scale(self.forward, self.speed * 0.35), v.scale(delta, 0.65)));
    }
};
pub fn meleeOrigin(position: v.Vec, muzzle: v.Vec, ducked: bool) v.Vec {
    return v.add(v.add(position, muzzle), .{ 0, 0, if (ducked) @as(f32, -25) else 0 });
}
pub fn combatFor(sequence: i32) profiles.Combat {
    return if (sequence >= 128) .melee else .discus;
}
pub fn meleePlan(_: i32, _: i32) !@import("../melee.zig").Plan {
    return .{ .delays_ms = .{ 250, 0 }, .range = 120, .world_muzzle = true, .crouching_height = -25, .inertial = true, .scale_timing = true };
}
pub fn flightMotion(_: *BallisticState, frame: ballistic.Frame) ballistic.Motion {
    return .{ .velocity = frame.velocity };
}
pub fn attackAnimation(sequence: i32, _: i32) profiles.AttackAnimation {
    return .{ .pose = if (sequence == 128) "shootc" else if (sequence == 129) "shootd" else "shootb", .rate = 20 };
}
pub fn fireSound(sequence: i32, _: u32) ?[:0]const u8 {
    return if (sequence >= 128) "e2/we_discambb.wav" else spec.audio.fire;
}
pub fn impact(context: @import("../impact.zig").Context) @import("../impact.zig").Cue {
    const flesh = context.kind == .flesh;
    return .{ .sound = if (flesh) "global/m_knifehitb.wav" else "e2/we_dischit1.wav", .particles = if (flesh) 4 else if (context.sequence >= 128) 10 else 1, .color = if (flesh) .{ 0.2, 0.4, 0.8 } else .{ 1, 1, 0.4 } };
}
pub fn predictionShot(controller: anytype) shot_rules.Shot {
    var result = shot_rules.standard(controller);
    if (controller.discusMelee()) {
        result.cost = 0;
        result.sequence = 128 + @mod(@divTrunc(controller.now(), 50), 2);
    }
    return result;
}

pub fn update(controller: anytype) void {
    controller.automatic(@This());
}
