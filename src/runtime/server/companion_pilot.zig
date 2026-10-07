// SPDX-License-Identifier: GPL-2.0-or-later
//! Companions flown by the shared bot pilot. The brain fills an intent; the
//! pilot plans it like the co-op bot (perception at the highest skill, aim,
//! fire discipline, dodging, hazard and drop safety, lift riding); this sink
//! runs the companion's own player motor with the class hull and speed and
//! leaves the trigger to the companion's weapon step. Planning state is
//! transient: keyed by persistent identity, never saved, and reset whenever
//! the companion was not flown for a while or changed worlds.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const nav = @import("../domain/navigation.zig");
const pilot = @import("bot_pilot.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Actors = @import("actors.zig").Actors;

/// Companions see, react, turn and aim at the top of the bot ladder.
pub const skill_level = 10;
/// The trigger decision the companion weapon step consumes this frame.
pub const Output = struct { at_ms: i64 = -1, fire: bool = false, weapon: u5 = 0 };
pub const Entry = struct {
    id: u32 = 0,
    world: ?*data.World = null,
    last_ms: i64 = 0,
    pilot: pilot.Pilot = .{ .level = skill_level },
    intent: pilot.Intent = .{},
    report: pilot.Report = .{},
    output: Output = .{},
    brain: @import("companion_brain.zig").State = .{},
    status_ms: i64 = 0,
};
var entries: [4]Entry = @splat(.{});

/// The companion's planning state, fresh after an absence, a rewind or a
/// world change (another area graph, other slots).
pub fn entry(world: *data.World, id: u32, identity: u8, now: i64) *Entry {
    var oldest: usize = 0;
    for (&entries, 0..) |*candidate, index| {
        if (candidate.id == id) {
            if (candidate.world != world or now < candidate.last_ms or now - candidate.last_ms > 500) start(candidate, world, id, identity);
            candidate.last_ms = now;
            return candidate;
        }
        if (candidate.last_ms < entries[oldest].last_ms or candidate.id == 0 and entries[oldest].id != 0) oldest = index;
    }
    const chosen = &entries[oldest];
    start(chosen, world, id, identity);
    chosen.last_ms = now;
    return chosen;
}
fn start(target: *Entry, world: *data.World, id: u32, identity: u8) void {
    target.* = .{ .id = id, .world = world };
    // The two companions break to opposite sides when strafing and detouring.
    target.pilot.vary(identity);
}
pub fn find(id: u32) ?*Entry {
    for (&entries) |*candidate| if (candidate.id == id and id != 0) return candidate;
    return null;
}
/// Orders replace whatever the companion was doing.
pub fn forget(id: u32) void {
    const found = find(id) orelse return;
    found.pilot.reset();
    found.brain = .{};
    found.intent = .{};
}
/// A new map, a restore or shutdown: nothing planned survives.
pub fn reset() void {
    entries = @splat(.{});
}
/// This frame's trigger decision, if the companion was flown this frame.
pub fn output(id: u32, now: i64) ?Output {
    const found = find(id) orelse return null;
    if (found.output.at_ms != now) return null;
    return found.output;
}

pub fn frame(actors: *const Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, service: nav.Service, definition: @import("../domain/actors.zig").Definition, now: i64) !pilot.Frame {
    const companion = try world.get(entity, data.Companion);
    return .{
        .world = world,
        .slots = slots,
        .projections = projections,
        .service = service,
        .collision = @import("actor_collision.zig").probe(),
        .table = &actors.weapons,
        .slot = (try world.get(entity, data.Binding)).slot,
        .entity = entity,
        .state = companion.motor,
        .hull = .{ .mins = definition.mins, .maxs = definition.maxs },
        .now = now,
        .region = true,
        .capabilities = .{ .controls = false, .operate_lifts = false, .passages = false, .exits = false, .use = false, .nuisance = false, .ignore_ambient = true, .duck_to_shoot = false },
        .exclusion = .{ .context = actors, .mask = exclusion },
        // Companions keep out of anything that hurts, not only what kills.
        .hazard_damage = 5,
        .label = "sidekick",
    };
}
fn exclusion(context: *const anyopaque, at: pilot.Frame, enemy: ?v.Vec3) anyerror!i32 {
    const actors: *const Actors = @ptrCast(@alignCast(context));
    return @import("companion_weapons.zig").excluded(at.world, at.entity, actors.episode, enemy);
}

/// Plan the brain's intent and move the companion with its own player motor.
pub fn drive(actors: *const Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, body: *data.Body, velocity: *data.Velocity, service: nav.Service, definition: @import("../domain/actors.zig").Definition, speed: f32, now: i64, elapsed: u32) !void {
    const movement = @import("../domain/player_move.zig");
    const companion = try world.get(entity, data.Companion);
    const id = try world.persistentId(entity);
    const flown = entry(world, id, @intFromEnum(companion.identity), now);
    const plan_frame = try frame(actors, world, slots, projections, entity, service, definition, now);
    const steering = try flown.pilot.steer(plan_frame, flown.intent);
    flown.report = steering.report;
    var command = steering.command;
    // An emptied thrown weapon still strikes up close (the reviewed policy);
    // the bot ladder only counts weapons with rounds.
    if (!command.attack and flown.intent.fight and flown.intent.fire != .hold and steering.report.enemy != 0 and steering.report.enemy_distance <= 128) {
        const loadout = (try world.get(entity, data.Weapons)).*;
        if (@import("companion_weapons.zig").emptyMelee(loadout, &actors.weapons, actors.episode)) |weapon| {
            command.weapon = weapon;
            command.attack = loadout.weapon == weapon;
        }
    }
    flown.output = .{ .at_ms = now, .fire = command.attack, .weapon = command.weapon };
    // The weapon step checks its leader-safety lane against this frame's target.
    if (flown.intent.fight) actor.threat = steering.report.enemy;
    if (@import("../engine/server.zig").integer("developer") >= 1 and now >= flown.status_ms) {
        flown.status_ms = now + 1000;
        const health = (try world.get(entity, data.Health)).*;
        const destination = flown.intent.destination orelse pose.position;
        const waypoint = if (steering.report.waypoint) |point| point.point else pose.position;
        var text: [448]u8 = undefined;
        @import("../engine/server.zig").print(std.fmt.bufPrintZ(&text, "dk3 sidekick: t={d} who={s} health={d}/{d} pos={d:.0},{d:.0},{d:.0} goal={d:.0},{d:.0},{d:.0} leash={d} fire={s} enemy={d} range={d:.0} fired={d} dodging={d} avoided={d} weapon={d} waypoint={d:.0},{d:.0},{d:.0} blocked={d} no_route={d} routeless={d} ground={d} water={d} lost={d} stranded={d} retracing={d} routable={d} collecting={d} why={s}\n", .{ now, @tagName(companion.identity), health.current, health.maximum, pose.position[0], pose.position[1], pose.position[2], destination[0], destination[1], destination[2], @intFromBool(flown.intent.leash != null), @tagName(flown.intent.fire), steering.report.enemy, steering.report.enemy_distance, @intFromBool(command.attack), @intFromBool(steering.report.dodging), steering.report.avoided_exit, command.weapon, waypoint[0], waypoint[1], waypoint[2], @intFromBool(steering.report.blocked), @intFromBool(steering.report.no_route), @intFromBool(steering.report.routeless), companion.motor.ground_entity, companion.motor.water_level, if (flown.brain.lost_ms) |since| now - since else -1, @max(0, flown.brain.stranded_until - now), @intFromBool(flown.brain.retracing), @intFromBool(flown.brain.routable != null), companion.collecting, flown.brain.why }) catch "dk3 sidekick: status\n");
    }
    // Item pursuit judges reachability by the route's progress.
    actor.route = flown.pilot.route;
    pose.angles = .{ command.angles[0], command.angles[1], 0 };
    var input: movement.Command = .{ .time_ms = now, .angles = .{ command.angles[0], command.angles[1], 0 }, .forward = command.forward, .right = command.right, .up = command.up };
    if (body.motion_owner != null) input = .{ .time_ms = now, .angles = input.angles };
    // Cinematic pauses and explicit motion owners must not accumulate commands.
    companion.motor.command_ms = @max(companion.motor.command_ms, now - elapsed);
    companion.motor.mode = if (body.motion_owner != null) .frozen else .normal;
    var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = velocity.linear };
    const result = try movement.run(&companion.motor, &motion, input, .{ .speed = speed, .jump_speed = definition.upward_speed, .slot = plan_frame.slot, .mask = body.collision_mask, .water_mask = c.MASK_WATER, .solid_mask = c.CONTENTS_SOLID, .mins = definition.mins, .maxs = definition.maxs, .snap_velocity = false }, @import("actor_collision.zig").service());
    for (result.events[0..result.event_count]) |event| switch (event) {
        .jump => companion.jump_started_ms = now,
        else => {},
    };
    body.mins = result.mins;
    body.maxs = result.maxs;
    actor.ground_entity = companion.motor.ground_entity;
    body.grounded = actor.ground_entity != c.ENTITYNUM_NONE;
    pose.position = motion.position;
    velocity.linear = motion.velocity;
}

test "companion planning state is per identity and fresh after an absence or a world change" {
    reset();
    defer reset();
    var first = data.World.init(std.testing.allocator, 1);
    defer first.deinit();
    var second = data.World.init(std.testing.allocator, 1);
    defer second.deinit();
    const mikiko = entry(&first, 7, 0, 1000);
    mikiko.pilot.target = 99;
    try std.testing.expectEqual(@as(u32, 99), entry(&first, 7, 0, 1050).pilot.target);
    try std.testing.expectEqual(@as(u32, 0), entry(&first, 7, 0, 1700).pilot.target);
    entry(&first, 7, 0, 1750).pilot.target = 99;
    try std.testing.expectEqual(@as(u32, 0), entry(&second, 7, 0, 1800).pilot.target);
    const superfly = entry(&first, 8, 1, 1800);
    try std.testing.expect(superfly != entry(&second, 7, 0, 1800));
    try std.testing.expectEqual(@as(i32, skill_level), superfly.pilot.level);
    try std.testing.expect(superfly.pilot.strafe_side != entry(&second, 7, 0, 1800).pilot.strafe_side);
    entry(&second, 7, 0, 1850).output = .{ .at_ms = 1850, .fire = true, .weapon = 3 };
    try std.testing.expect(output(7, 1850).?.fire);
    try std.testing.expectEqual(@as(?Output, null), output(7, 1900));
}
