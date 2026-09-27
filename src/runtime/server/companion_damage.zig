// SPDX-License-Identifier: GPL-2.0-or-later
//! Party injury consumes the same receipt as combat, without attacking friends.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").companions;
const Actors = @import("actors.zig").Actors;
fn speak(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, kind: policy.Voice, now: i64) !void {
    const companion = (try world.get(entity, data.Companion)).*;
    const random = try world.get(entity, data.Random);
    const count: f32 = if (kind == .burning) 3 else if (kind == .cold or kind == .drowning) 2 else 4;
    const sample = policy.voice(companion.identity, kind, @intFromFloat(random.next() * count));
    var buffer: [96]u8 = undefined;
    const name = try std.fmt.bufPrint(&buffer, "{s}/{s}", .{ @tagName(companion.identity), sample });
    try @import("events.zig").sound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, abi.c.CHAN_BODY, now);
}
pub fn death(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64) !void {
    const liquid = (try world.get(entity, data.Actor)).liquid;
    const health = try world.get(entity, data.Health);
    const kind: policy.Voice = if (liquid.level > 2) .water_death else if (health.current < -40) .extreme_death else .death;
    health.armor = 0;
    health.absorption = 0;
    try @import("weapon_actions.zig").cancel(world, slots, projections, entity);
    try speak(world, slots, projections, entity, kind, now);
}
pub fn react(actors: *const Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, now: i64) !void {
    if (actor.reaction_until_ms) |until| if (now >= until) {
        actor.reaction = null;
        actor.reaction_until_ms = null;
    };
    const receipt = (try world.get(entity, data.Hurt)).*;
    if (receipt.revision == actor.receipt) return;
    actor.receipt = receipt.revision;
    if (receipt.amount <= 0) return;
    const identity = try world.persistentId(entity);
    const self_hurt = receipt.source == identity;
    const liquid = actor.liquid;
    const kind: policy.Voice = if (self_hurt and liquid.kind == .water) (if (actors.episode == 3) .cold else .drowning) else if (self_hurt and (liquid.kind == .lava or liquid.kind == .slime)) .burning else .pain;
    if (kind == .pain or (try world.get(entity, data.Random)).next() < 0.15) try speak(world, slots, projections, entity, kind, now);
    if (self_hurt or now <= actor.pain_ready_ms) return;
    if (world.find(receipt.source)) |attacker| if (world.get(attacker, data.Actor) catch null) |enemy| {
        const enemy_kind = @import("actor_catalog").entries[enemy.definition].kind;
        if (enemy_kind != .companion and !@import("actor_catalog").ambient(enemy_kind) and (try world.get(attacker, data.Health)).current > 0) {
            actor.threat = receipt.source;
            actor.threat_position = (try world.get(attacker, data.Transform)).position;
            actor.threat_seen_ms = now;
        }
    };
    const poses = actors.companion_poses[actor.definition] orelse return error.MissingCompanionPoses;
    const loadout = (try world.get(entity, data.Weapons)).*;
    var sequence = (try actors.companionPlayback(world, entity, now)).sequence;
    if (actor.scripted_pose) |scripted| sequence = scripted;
    if (@as(u8, @intFromFloat((try world.get(entity, data.Random)).next() * 99.9)) < policy.pain_chance) {
        if (poses.pain[@import("../domain/companion_pose.zig").weaponGrip(loadout.weapon)]) |hit| {
            sequence = hit;
            actor.reaction = hit;
            actor.reaction_started_ms = now;
            actor.reaction_until_ms = now + hit.duration();
            actor.mode = .idle;
        }
    }
    actor.pain_ready_ms = now + @divTrunc(@as(i64, sequence.last - sequence.first) * 1000, sequence.fps);
}
