// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit native save timestamp mapping. Durations never shift with the clock.
const std = @import("std");
const data = @import("components.zig");
fn shift(value: *i64, delta: i64) !void {
    value.* = try std.math.add(i64, value.*, delta);
}
fn active(value: *i64, delta: i64) !void {
    if (value.* != 0) try shift(value, delta);
}
fn deadline(value: *?i64, delta: i64) !void {
    if (value.*) |*at| try shift(at, delta);
}
pub fn rebase(comptime id: data.ComponentId, value: *data.types[@intFromEnum(id)], delta: i64) !void {
    switch (id) {
        .firefly => {
            try shift(&value.next_ms, delta);
            if (value.wisp) |*wisp| {
                try active(&wisp.respawn_ms, delta);
                try active(&wisp.collected_ms, delta);
            }
        },
        .wisp_swarm => {
            try shift(&value.next_ms, delta);
            try shift(&value.sound_ms, delta);
        },
        .scenery => {
            try shift(&value.started_ms, delta);
            try deadline(&value.breaking_ms, delta);
            try deadline(&value.expires_ms, delta);
            if (value.gib) |*gib| {
                try shift(&gib.next_ms, delta);
                try deadline(&gib.fade_ms, delta);
            }
        },
        .companion => {
            try deadline(&value.animation_until, delta);
            try shift(&value.next_ms, delta);
            try shift(&value.last_ms, delta);
        },
        .session => {
            try active(&value.respawn_ms, delta);
            try shift(&value.joined_ms, delta);
            if (value.pose.initialized) try shift(&value.pose.started_ms, delta);
        },
        .objective => {
            try deadline(&value.deadline, delta);
            try active(&value.pickup_ms, delta);
            try active(&value.beep_ms, delta);
            if (value.airborne) try shift(&value.stepped_ms, delta);
        },
        .monitor => try deadline(&value.until_ms, delta),
        .thunder_spray => {
            try shift(&value.born_ms, delta);
            try shift(&value.stepped_ms, delta);
            try shift(&value.next_ms, delta);
        },
        .health_tree => {
            try shift(&value.ready_ms, delta);
            try shift(&value.changed_ms, delta);
            try deadline(&value.recharge_ms, delta);
        },
        .script => {
            try shift(&value.due_ms, delta);
            try shift(&value.next_ms, delta);
        },
        .cinematic => try shift(&value.started_ms, delta),
        .performer => {
            try shift(&value.head_ms, delta);
            try shift(&value.animation_ms, delta);
            try shift(&value.due_ms, delta);
            try shift(&value.next_ms, delta);
        },
        .nightmare => {
            try shift(&value.born_ms, delta);
            try shift(&value.phase_ms, delta);
            try shift(&value.next_ms, delta);
        },
        .meta_ring => {
            try shift(&value.born_ms, delta);
            try shift(&value.next_ms, delta);
        },
        .meta_laser => {
            try shift(&value.next_ms, delta);
            try shift(&value.expires_ms, delta);
        },
        .lifetime => try shift(&value.expires_ms, delta),
        .player => try shift(&value.command_ms, delta),
        .weapons => {
            try active(&value.gas_until_ms, delta);
            try deadline(&value.last_fire_ms, delta);
        },
        .mover => {
            try shift(&value.motion.start_ms, delta);
            try deadline(&value.return_at.at_ms, delta);
        },
        .trigger => try active(&value.ready_ms, delta),
        .train => {
            try shift(&value.position.start_ms, delta);
            try shift(&value.angles.start_ms, delta);
            try deadline(&value.action.at_ms, delta);
        },
        .rotation => try shift(&value.started_ms, delta),
        .secret => {
            try shift(&value.motion.start_ms, delta);
            try deadline(&value.action.at_ms, delta);
        },
        .pickup => try deadline(&value.respawn_ms, delta),
        .item_motion => try shift(&value.started_ms, delta),
        .character => {
            for (&value.boost_until) |*at| try active(at, delta);
            try active(&value.invincible_until, delta);
            try active(&value.invisible_until, delta);
            try active(&value.environment_until, delta);
        },
        .dwarf_axe => {
            try shift(&value.born_ms, delta);
            try shift(&value.stepped_ms, delta);
            try deadline(&value.contact_ms, delta);
        },
        .frog_spit, .projectile, .cryo_spray => {
            try shift(&value.born_ms, delta);
            try shift(&value.stepped_ms, delta);
        },
        .melee => try shift(&value.started_ms, delta),
        .weapon_launch => try shift(&value.execute_ms, delta),
        .charge => {
            try shift(&value.born_ms, delta);
            try shift(&value.stepped_ms, delta);
            try shift(&value.next_ms, delta);
            try shift(&value.expires_ms, delta);
            try deadline(&value.detonate_ms, delta);
            try deadline(&value.beep_ms, delta);
        },
        .hammer => {
            try shift(&value.next_ms, delta);
            try deadline(&value.quake_until_ms, delta);
        },
        .shockwave => {
            try shift(&value.born_ms, delta);
            try shift(&value.next_ms, delta);
            for (value.rings[0..value.count]) |*ring| try shift(&ring.start_ms, delta);
        },
        .nova => {
            try shift(&value.born_ms, delta);
            try shift(&value.next_ms, delta);
            try shift(&value.expires_ms, delta);
            try deadline(&value.end_ms, delta);
        },
        .flashlight => try shift(&value.expires_ms, delta),
        .zeus => {
            try shift(&value.ready_ms, delta);
            try shift(&value.expires_ms, delta);
            try deadline(&value.closed_ms, delta);
        },
        .zeus_bolt => {
            try shift(&value.born_ms, delta);
            try shift(&value.next_ms, delta);
        },
        .ailments => {
            if (value.warp) |*warp| {
                try shift(&warp.until_ms, delta);
                try shift(&warp.next_ms, delta);
            }
            if (value.poison) |*poison| {
                try shift(&poison.until_ms, delta);
                try shift(&poison.next_ms, delta);
            }
            try deadline(&value.freeze_at_ms, delta);
            try deadline(&value.freeze_next_ms, delta);
        },
        .actor_attack => {
            try shift(&value.born_ms, delta);
            try shift(&value.stepped_ms, delta);
            switch (value.attack) {
                .meteor => |*meteor| try shift(&meteor.next_ms, delta),
                .npc_wisp => |*wisp| {
                    try shift(&wisp.next_ms, delta);
                    try active(&wisp.sine_ms, delta);
                },
                .wyndrax_zap => {},
                .wyndrax_bolt => |*bolt| {
                    try shift(&bolt.next_ms, delta);
                    try shift(&bolt.until_ms, delta);
                    try active(&bolt.flare_until_ms, delta);
                },
                .psyclaw_sphere => |*sphere| try shift(&sphere.next_ms, delta),
                .gunner_burst => |*burst| try shift(&burst.next_ms, delta),
                .shaft => |*shaft| try deadline(&shaft.contact_ms, delta),
                .rocket => |*rocket| try shift(&rocket.next_ms, delta),
                .fireball => |*fire| try shift(&fire.drift_ms, delta),
                .knight_zap => |*zap| for (&zap.bolts) |*maybe| {
                    if (maybe.*) |*bolt| {
                        try shift(&bolt.born_ms, delta);
                        try shift(&bolt.next_ms, delta);
                    }
                },
                .knight_punch, .rotworm_spit, .prisoner_rock, .sludge_glob => {},
            }
        },
        .actor_laser => {
            try shift(&value.born_ms, delta);
            try shift(&value.stepped_ms, delta);
            try deadline(&value.contact_ms, delta);
        },
        .actor => {
            try active(&value.gunner.ready_ms, delta);
            try active(&value.gunner.emit_ms, delta);
            try active(&value.pain_ready_ms, delta);
            try active(&value.doombat.started_ms, delta);
            try active(&value.griffon.started_ms, delta);
            try deadline(&value.griffon.until_ms, delta);
            try active(&value.harpy.started_ms, delta);
            try active(&value.harpy.warmup_started_ms, delta);
            try active(&value.harpy.ready_ms, delta);
            try active(&value.harpy.shot_ms, delta);
            try deadline(&value.harpy.until_ms, delta);
            try active(&value.dragon.until_ms, delta);
            try active(&value.dragon.ambient_ms, delta);
            try deadline(&value.dragon.breath_until_ms, delta);
            try active(&value.wyndrax.until_ms, delta);
            try active(&value.mikiko.aura_started_ms, delta);
            try active(&value.medusa.until_ms, delta);
            try active(&value.medusa.flash_until_ms, delta);
            try active(&value.buboid.started_ms, delta);
            try active(&value.buboid.until_ms, delta);
            try active(&value.chaingang.started_ms, delta);
            try active(&value.chaingang.until_ms, delta);
            try active(&value.chaingang.strafe_ms, delta);
            try active(&value.deathsphere.until_ms, delta);
            try active(&value.deathsphere.charge_ms, delta);
            try active(&value.psyclaw.protected_until_ms, delta);
            try active(&value.psyclaw.emit_ms, delta);
            try deadline(&value.psyclaw.jump_started_ms, delta);
            try active(&value.thief.next_attack_ms, delta);
            try deadline(&value.thief.sidestep_until, delta);
            try active(&value.prisoner.ready_ms, delta);
            try active(&value.prisoner.emit_ms, delta);
            try deadline(&value.evasion.until_ms, delta);
            try deadline(&value.archer.sidestep_until, delta);
            try active(&value.archer.ready_ms, delta);
            try active(&value.rocketgang.ready_ms, delta);
            try active(&value.rocketmp.ready_ms, delta);
            try deadline(&value.rocketmp.evade_until, delta);
            try active(&value.archer.clear_ms, delta);
            try deadline(&value.knight.sidestep_until, delta);
            try deadline(&value.rat.evasion_until, delta);
            try active(&value.shark.wander_until_ms, delta);
            try active(&value.vermin.ready_ms, delta);
            try shift(&value.rotworm.started_ms, delta);
            try active(&value.lasergat.servo_ms, delta);
            try deadline(&value.inmater.sidestep_until, delta);
            try active(&value.surgeon.until_ms, delta);
            try deadline(&value.script_paused_ms, delta);
            try active(&value.surgeon.reconsider_ms, delta);
            if (value.surgeon.active) try shift(&value.surgeon.started_ms, delta);
            try active(&value.cryotech.ready_ms, delta);
            try deadline(&value.cryotech.ambient_started, delta);
            try deadline(&value.spider.retreat_until, delta);
            try deadline(&value.spider.sidestep_until, delta);
            try shift(&value.lycanthir.started_ms, delta);
            try shift(&value.lycanthir.wake_ms, delta);
            try shift(&value.column.started_ms, delta);
            try shift(&value.reaction_started_ms, delta);
            try deadline(&value.reaction_until_ms, delta);
            try shift(&value.think_ms, delta);
            try shift(&value.scripted_ms, delta);
            try shift(&value.melee.started_ms, delta);
            try shift(&value.use_ready_ms, delta);
            try shift(&value.frog.started_ms, delta);
            try shift(&value.rockgat.pose_ms, delta);
            try shift(&value.rockgat.next_attack_ms, delta);
            try shift(&value.rockgat.next_sound_ms, delta);
            for (&value.rockgat.bursts) |*burst| if (burst.*) |*shot| {
                try shift(&shot.next_ms, delta);
            };
            try shift(&value.crox.started_ms, delta);
            try shift(&value.crox.cycle_ms, delta);
            try shift(&value.crox.wander_until_ms, delta);
            try shift(&value.thunder.started_ms, delta);
            try shift(&value.skeeter.started_ms, delta);
            try shift(&value.skeeter.until_ms, delta);
            try shift(&value.pod.next_ms, delta);
            try shift(&value.changed_ms, delta);
            try active(&value.panic_until, delta);
            try shift(&value.threat_seen_ms, delta);
            if (value.witness_ms != -1) try shift(&value.witness_ms, delta);
            try active(&value.escape_until, delta);
            try active(&value.jump_ready_ms, delta);
            try shift(&value.guard.started_ms, delta);
            try active(&value.guard.ready_ms, delta);
            // Routing caches are derived from the current collision/nav world.
            value.route = .{};
        },
        .hurt => if (value.at_ms != -1) {
            try shift(&value.at_ms, delta);
        },
        .hazard => try active(&value.ready_ms, delta),
        .exit => {
            try active(&value.ready_ms, delta);
            try deadline(&value.ending_started, delta);
        },
        .target_sequence => {
            try shift(&value.started_ms, delta);
            try active(&value.ready_ms, delta);
        },
        .transform, .velocity, .body, .health, .random, .binding, .map_object, .attachment, .gravity, .motion, .inventory, .keys, .sound_event, .impact_event, .destructible, .wall => {},
    }
}
test "save time rebasing preserves deadlines, inactive sentinels and durations" {
    var train: data.Train = .{ .position = .{ .start_ms = 1200, .duration_ms = 900 }, .action = .{ .at_ms = 2200 } };
    try rebase(.train, &train, 10000);
    try std.testing.expectEqual(@as(i64, 11200), train.position.start_ms);
    try std.testing.expectEqual(@as(i32, 900), train.position.duration_ms);
    try std.testing.expectEqual(@as(?i64, 12200), train.action.at_ms);
    var character: data.Character = .{ .boost_until = .{ 0, 100, 0, 0, 0 } };
    try rebase(.character, &character, 10000);
    try std.testing.expectEqual(@as(i64, 0), character.boost_until[0]);
    try std.testing.expectEqual(@as(i64, 10100), character.boost_until[1]);
}
