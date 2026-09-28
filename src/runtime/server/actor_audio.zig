// SPDX-License-Identifier: GPL-2.0-or-later
//! Frame cues consume actual projected actor poses. Attack controllers retain their cues.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const policy = @import("../domain/actor_audio.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Definition = @import("../domain/actors.zig").Definition;
fn audible(world: *data.World, slots: *const Slots, origin: v.Vec3, definition: Definition) bool {
    if (definition.attenuation[1] <= definition.attenuation[0]) return false;
    for (slots.occupants) |occupant| if (occupant) |entity| {
        const player = world.get(entity, data.Player) catch continue;
        if (player.mode == .spectator) continue;
        const pose = world.get(entity, data.Transform) catch continue;
        if (v.length(v.subtract(pose.position, origin)) < definition.sight_range) return true;
    };
    return false;
}
pub fn play(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, definition: Definition, name: []const u8, now: i64) !void {
    if (name.len == 0) return;
    const origin = (try world.get(entity, data.Transform)).position;
    if (!audible(world, slots, origin, definition)) return;
    try @import("events.zig").configuredSound(world, slots, projections, name, origin, (try world.get(entity, data.Binding)).slot, c.CHAN_AUTO, now, .{ .minimum = definition.attenuation[0], .maximum = definition.attenuation[1] });
}
fn idle(actors: *const @import("actors.zig").Actors, world: *data.World, entity: ecs.Entity, projections: []abi.EntityProjection, now: i64) !void {
    const actor = try world.get(entity, data.Actor);
    const definition = actors.table.definitions[actor.definition];
    const scripted = if (world.get(entity, data.Script) catch null) |script| script.active else false;
    const kind = @import("actor_catalog").entries[actor.definition].kind;
    const swimming_or_wandering = kind == .crox and (actor.crox.swimming or actor.crox.wandering);
    if (actor.worker.phase == .cower or actor.mode != .idle or actor.reaction != null or actor.melee.active or actor.scripted_pose != null or scripted or swimming_or_wandering or definition.idle_choices.len == 0) {
        actor.idle_pose = null;
        actor.idle_started_ms = null;
        return;
    }
    if (actor.idle_started_ms) |started| if (now < started + actor.idle_pose.?.duration()) return;
    const random = try world.get(entity, data.Random);
    var remaining: f32 = 1;
    for (definition.idle_choices) |choice| {
        actor.idle_pose = choice.sequence;
        if (random.next() <= choice.weight / remaining) break;
        remaining = @max(0.0001, remaining - choice.weight);
    }
    actor.idle_started_ms = now;
    try actors.publish(world, entity, projections, now);
}
pub fn step(actors: *const @import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, now: i64) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        if ((world.get(entity, data.Actor) catch null) == null) continue;
        try idle(actors, world, entity, projections, now);
        const actor = (try world.get(entity, data.Actor)).*;
        const definition = actors.table.definitions[actor.definition];
        const origin = (try world.get(entity, data.Transform)).position;
        const heard = audible(world, slots, origin, definition);
        var state = actor.audio;
        const threat = actor.threat;
        const kind = @import("actor_catalog").entries[actor.definition].kind;
        if (actor.mode != .dead and threat != 0 and state.threat != threat and kind != .civilian and kind != .companion and !@import("actor_catalog").ambient(kind) and heard) {
            var remaining: f32 = 1;
            var selected: ?[]const u8 = null;
            for (definition.audio) |cue| {
                if (cue.sequence != null or !std.mem.startsWith(u8, cue.name, "sight")) continue;
                selected = cue.sounds[0];
                if ((try world.get(entity, data.Random)).next() <= cue.weight / remaining) break;
                remaining = @max(0.0001, remaining - cue.weight);
            }
            if (selected) |name| try play(world, slots, projections, entity, definition, name, now);
        }
        state.threat = threat;
        // Existing class controllers own attack sounds, including impact-only
        // and class-specific launch cues. Do not duplicate them from frame rows.
        const petrified = if (world.get(entity, data.Ailments) catch null) |ailments| ailments.stone else false;
        const owned = petrified or (kind != .companion and (actor.melee.active or actor.mode == .attack or actor.mode == .reload));
        if (!owned and !actor.gibbed) {
            const projection = projections[(try world.get(entity, data.Binding)).slot];
            const frame: u16 = @intCast(projection.state.frame);
            var selected: ?u16 = null;
            for (definition.audio, 0..) |cue, index| if (cue.sequence) |sequence| {
                if (frame >= sequence.first and frame <= sequence.last) {
                    selected = @intCast(index);
                    break;
                }
            };
            if (selected) |index| {
                const cue = definition.audio[index];
                var started = if (actor.reaction != null and actor.mode != .dead) actor.reaction_started_ms else if (actor.scripted_pose != null and actor.mode != .dead) actor.scripted_ms else if (actor.mode == .idle and actor.idle_started_ms != null) actor.idle_started_ms.? else actor.changed_ms;
                var looping = actor.mode != .dead and actor.reaction == null and (actor.mode == .idle or actor.mode == .chase or actor.mode == .flee);
                if (kind == .companion and actor.mode != .dead and actor.reaction == null and actor.scripted_pose == null) {
                    const playback = try actors.companionPlayback(world, entity, now);
                    started = playback.started;
                    looping = playback.looping;
                }
                const roll = if (cue.alternative != null and (state.cue != index or state.started_ms != started)) (try world.get(entity, data.Random)).next() else 0;
                const events = policy.sample(&state, cue, index, frame, now, started, looping, roll);
                state.pending |= events;
                const ambient = std.mem.startsWith(u8, cue.name, "amb");
                if (heard and (!ambient or now > (state.ambient_ready_ms orelse -1))) {
                    for (cue.sounds, 0..) |name, i| {
                        const bit = @as(u2, 1) << @intCast(i);
                        if (state.pending & bit == 0) continue;
                        state.pending &= ~bit;
                        if (name.len == 0) continue;
                        try play(world, slots, projections, entity, definition, name, now);
                        if (ambient) {
                            state.ambient_ready_ms = now + 10000 + @as(i64, @intFromFloat((try world.get(entity, data.Random)).next() * 30000));
                            break;
                        }
                    }
                }
            } else {
                state.cue = null;
                state.pending = 0;
            }
        } else {
            state.cue = null;
            state.pending = 0;
        }
        (try world.get(entity, data.Actor)).audio = state;
    }
}
