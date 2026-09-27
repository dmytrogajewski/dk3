// SPDX-License-Identifier: GPL-2.0-or-later
//! Party spawning, orders, perception and class-owned weapon execution.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const policy = @import("actor_catalog").companions;
pub fn find(world: *data.World, identity: policy.Identity) ?ecs.Entity {
    var query = world.queryAccess(data.World.mask(.{data.Companion}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Companion)) |entity, companion| if (companion.identity == identity) return entity;
    return null;
}
pub fn initialize(world: *data.World, entity: ecs.Entity, episode: u8, table: *const @import("../domain/weapons.zig").Table, now: i64) !void {
    const classname = (try world.get(entity, data.MapObject)).classname;
    try world.put(entity, data.Companion{ .identity = if (std.mem.eql(u8, classname, "mikiko")) .mikiko else .superfly, .carrying = std.mem.eql(u8, classname, "mikikofly"), .last_ms = now, .motor = .{ .command_ms = now } });
    try world.put(entity, data.Weapons{});
    try world.put(entity, data.Character{});
    try world.put(entity, data.Keys{});
    (try world.get(entity, data.Health)).* = .{};
    if (episode == 1 and !std.mem.eql(u8, classname, "mikikofly")) {
        const weapon = @import("weapon_catalog").starting(1);
        _ = (try world.get(entity, data.Weapons)).acquire(table, weapon, table.entries[weapon].initialAmmo);
    }
}
pub fn start(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, player: ecs.Entity, entry: []const u8, transfer_mask: ?u2, now: i64) !void {
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER) return;
    const origin = (try world.get(player, data.Transform)).position;
    for ([_][]const u8{ "mikiko", "superfly", "mikikofly" }) |classname| {
        const identity: policy.Identity = if (std.mem.eql(u8, classname, "mikiko")) .mikiko else .superfly;
        if (find(world, identity) != null) continue;
        var expected: [48]u8 = undefined;
        const name = try std.fmt.bufPrint(&expected, "info_{s}_start", .{classname});
        var chosen: ?data.Transform = null;
        var nearest: f32 = std.math.inf(f32);
        var query = world.queryAccess(data.World.mask(.{ data.MapObject, data.Transform }), 0, 0);
        {
            defer query.deinit();
            while (query.next()) |view| for (view.read(data.MapObject), view.read(data.Transform)) |object, pose| {
                if (!std.mem.eql(u8, object.classname, name)) continue;
                if (object.targetname.len > 0 and !std.mem.eql(u8, object.targetname, entry)) continue;
                if (object.targetname.len == 0 and (entry.len > 0 or (transfer_mask != null and transfer_mask.? & (@as(u2, 1) << @as(u1, @intCast(@intFromEnum(identity)))) == 0))) continue;
                const distance = v.length(v.subtract(pose.position, origin));
                if (distance < nearest) {
                    chosen = pose;
                    nearest = distance;
                }
            };
        }
        if (chosen) |pose| {
            const entity = try actors.spawnDynamic(world, slots, projections, classname, pose.position, pose.angles, now);
            (try world.get(entity, data.Companion)).owner = try world.persistentId(player);
        }
    }
}
pub fn order(actors: *const @import("actors.zig").Actors, world: *data.World, now: i64, player: ecs.Entity, name: []const u8, command: []const u8, target: u32, point: v.Vec3) !bool {
    const requested = std.meta.stringToEnum(policy.Order, command) orelse return false;
    var query = world.queryAccess(data.World.mask(.{data.Companion}), 0, data.World.mask(.{data.Companion}));
    defer query.deinit();
    var changed = false;
    while (query.next()) |view| for (view.entities(), view.write(data.Companion)) |entity, *companion| {
        if (!std.mem.eql(u8, name, "all") and !std.mem.eql(u8, name, @tagName(companion.identity))) continue;
        if ((try world.get(entity, data.Health)).current <= 0 or !companion.enabled) continue;
        if (requested == .collect) {
            const item = world.find(target) orelse continue;
            if (!try @import("companion_items.zig").allows(world, entity, item, &actors.weapons, actors.episode, true, now)) continue;
        }
        if (requested == .attack) {
            const enemy = world.find(target) orelse continue;
            const target_actor = world.get(enemy, data.Actor) catch continue;
            const kind = @import("actor_catalog").entries[target_actor.definition].kind;
            if (kind == .companion or kind == .civilian or @import("actor_catalog").ambient(kind) or companion.carrying or (try world.get(enemy, data.Health)).current <= 0) continue;
        }
        companion.collecting = if (requested == .collect) target else 0;
        companion.collect_forced = requested == .collect;
        companion.collect_until_ms = now + 15000;
        companion.yielding_until_ms = 0;
        (try world.get(entity, data.Actor)).route = .{};
        companion.owner = try world.persistentId(player);
        companion.order = requested;
        companion.target = target;
        companion.stopped = false;
        companion.authored = .none;
        companion.animation_until = null;
        (try world.get(entity, data.Actor)).scripted_pose = null;
        if (requested == .move) {
            companion.destination = if (world.find(target)) |destination| (try world.get(destination, data.Transform)).position else point;
        }
        changed = true;
    };
    return changed;
}
pub fn goal(actors: *const @import("actors.zig").Actors, navigation: @import("../domain/navigation.zig").Service, world: *data.World, slots: *Slots, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, now: i64) !void {
    const table = &actors.weapons;
    const companion = try world.get(entity, data.Companion);
    if (actor.reaction != null) {
        actor.mode = .idle;
        return;
    }
    if (try @import("companion_triggers.zig").advance(world, entity, actor, pose, now)) return;
    if (!companion.enabled) {
        actor.mode = .idle;
        return;
    }
    if (world.find(companion.owner) == null) if (slots.occupants[0]) |player| {
        companion.owner = try world.persistentId(player);
    };
    const owner = world.find(companion.owner) orelse {
        actor.mode = .idle;
        return;
    };
    if (companion.order == .collect and companion.collecting == 0 and companion.target != 0) {
        companion.collecting = companion.target;
        companion.collect_forced = true;
        companion.collect_until_ms = now + 15000;
    }
    if (try @import("companion_items.zig").pursuing(world, entity, actor, pose.*, table, actors.episode, now)) return;
    if (companion.order == .move) {
        actor.threat_position = companion.destination;
        actor.mode = if (v.length(v.subtract(companion.destination, pose.position)) > 24) .chase else .idle;
        if (actor.mode == .idle) companion.order = .stay;
        return;
    }
    if (companion.stopped) {
        actor.threat = 0;
        actor.mode = .idle;
        return;
    }
    var enemy: ?ecs.Entity = null;
    var distance: f32 = 1000;
    if (!companion.carrying) for (slots.occupants) |occupant| {
        const candidate = occupant orelse continue;
        const other = world.get(candidate, data.Actor) catch continue;
        const kind = @import("actor_catalog").entries[other.definition].kind;
        if (kind == .civilian or @import("actor_catalog").ambient(kind) or kind == .companion or (try world.get(candidate, data.Health)).current <= 0) continue;
        const commanded = companion.order == .attack and companion.target == try world.persistentId(candidate);
        if (!commanded and actor.threat != try world.persistentId(candidate) and other.threat != companion.owner and other.threat != try world.persistentId(entity)) continue;
        const target = (try world.get(candidate, data.Transform)).position;
        const range = v.length(v.subtract(target, pose.position));
        if (range >= distance and !commanded) continue;
        const trace = try engine.collisionService().trace(.{ .start = v.add(pose.position, .{ 0, 0, 22 }), .end = target, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SHOT });
        if (trace.fraction < 1 and trace.entity != (try world.get(candidate, data.Binding)).slot) continue;
        enemy = candidate;
        distance = range;
        if (commanded) break;
    };
    companion.selected_weapon = try @import("companion_weapons.zig").choose(world, entity, enemy, table, actors.episode);
    if (enemy) |target| if (!companion.carrying and (try world.get(target, data.Health)).current > 0) {
        actor.threat = try world.persistentId(target);
        actor.threat_position = (try world.get(target, data.Transform)).position;
        const delta = v.subtract(actor.threat_position, pose.position);
        pose.angles = .{ -std.math.atan2(delta[2] - 22, @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
        const loadout = (try world.get(entity, data.Weapons)).*;
        const range = @import("companion_weapons.zig").range(loadout, companion.selected_weapon, table);
        const can_fire = (try world.get(entity, data.Health)).current >= 15 and range > 0 and v.length(delta) <= range and try @import("companion_weapons.zig").clear(world, entity, target, companion.selected_weapon, table);
        actor.mode = if (can_fire) .attack else if ((try world.get(entity, data.Health)).current < 15) .flee else if (companion.order == .stay or companion.selected_weapon == 0) .idle else .chase;
        return;
    };
    actor.threat = 0;
    if (companion.order == .stay) {
        actor.mode = .idle;
        return;
    }
    const leader = (try world.get(owner, data.Transform)).*;
    const side: f32 = if (companion.identity == .mikiko) -48 else 48;
    const axes = v.basis(leader.angles);
    actor.threat_position = v.add(leader.position, v.add(v.scale(axes.forward, -80), v.scale(axes.right, side)));
    actor.mode = if (v.length(v.subtract(pose.position, actor.threat_position)) > 64) .chase else .idle;
    if (actor.mode == .idle and now >= companion.collect_scan_ms) {
        companion.collect_scan_ms = now + 1000;
        companion.collecting = try @import("companion_items.zig").choose(world, entity, table, actors.episode, navigation, now);
        companion.collect_forced = false;
        companion.collect_until_ms = now + 10000;
        if (companion.collecting != 0) {
            actor.route = .{};
            _ = try @import("companion_items.zig").pursuing(world, entity, actor, pose.*, table, actors.episode, now);
        }
    }
}
pub fn combat(actors: *const @import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, table: *const @import("../domain/weapons.zig").Table, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        const companion = world.get(entity, data.Companion) catch continue;
        const health = (try world.get(entity, data.Health)).current;
        if (health <= 0) {
            if (!companion.death_reported) {
                if (world.find(companion.owner)) |owner| if ((try world.get(owner, data.Health)).current > 0) {
                    const actor = (try world.get(entity, data.Actor)).*;
                    const player = try world.get(owner, data.Player);
                    player.mode = .frozen;
                    if (now >= actor.changed_ms + actors.table.definitions[actor.definition].death.duration()) {
                        player.mode = .dead;
                        companion.death_reported = true;
                        engine.send(0, "cp \"A companion has died. Load a saved game to continue.\"");
                    }
                    try @import("weapon_actions.zig").cancel(world, slots, projections, owner);
                };
            }
            continue;
        }
        const actor = (try world.get(entity, data.Actor)).*;
        const pose = (try world.get(entity, data.Transform)).*;
        const slot = (try world.get(entity, data.Binding)).slot;
        const loadout = try world.get(entity, data.Weapons);
        if (loadout.weapon == 0 and companion.selected_weapon == 0) continue;
        var events: @import("../domain/weapons.zig").Events = .{};
        var context: @import("../domain/weapons.zig").Context = .{ .ps = loadout, .table = table, .events = &events, .service = engine.collisionService(), .slot = slot, .shot_mask = c.MASK_SHOT, .single_player = true };
        var player = companion.motor;
        var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = @splat(0) };
        const hook = context.hook();
        const target = world.find(actor.threat);
        const wants_fire = companion.enabled and !companion.stopped and !companion.carrying and actor.mode == .attack and companion.selected_weapon != 0 and health >= 15 and !@import("nightmare.zig").frozen(world, entity) and (if (target) |enemy| try @import("companion_weapons.zig").clear(world, entity, enemy, companion.selected_weapon, table) else false);
        try hook.run_fn(hook.context, &player, &motion, .{ .time_ms = now, .angles = pose.angles, .weapon = if (companion.selected_weapon > 0) companion.selected_weapon else @intCast(loadout.weapon), .attack = wants_fire }, @min(elapsed, 200));
        for (events.values[0..events.count]) |event| switch (event) {
            .fired => |shot| try @import("combat.zig").fire(world, slots, projections, entity, shot, table, now),
            .no_ammo => {},
        };
    }
}

pub fn camera(world: *data.World, player: ecs.Entity, state: *c.playerState_t) !void {
    if ((try world.get(player, data.Player)).mode == .normal) return;
    const owner = try world.persistentId(player);
    var query = world.queryAccess(data.World.mask(.{data.Companion}), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities(), view.read(data.Companion)) |entity, companion| {
        if (companion.owner != owner or (try world.get(entity, data.Health)).current > 0) continue;
        const pose = (try world.get(entity, data.Transform)).*;
        const focus = v.add(pose.position, .{ 0, 0, 12 });
        const desired = v.add(focus, v.add(v.scale(v.basis(pose.angles).forward, -96), .{ 0, 0, 48 }));
        const hit = try engine.collisionService().trace(.{ .start = focus, .end = desired, .mins = .{ -4, -4, -4 }, .maxs = .{ 4, 4, 4 }, .slot = (try world.get(entity, data.Binding)).slot, .mask = c.MASK_SOLID });
        const delta = v.subtract(focus, hit.end);
        state.dk3CameraActive = 3;
        state.dk3CameraOrigin = hit.end;
        state.dk3CameraAngles = .{ -std.math.atan2(delta[2], @sqrt(delta[0] * delta[0] + delta[1] * delta[1])) * 180 / std.math.pi, std.math.atan2(delta[1], delta[0]) * 180 / std.math.pi, 0 };
        state.dk3CameraFov = 90;
        return;
    };
}
pub fn required(world: *data.World, player: ecs.Entity, flags: u32) !bool {
    const origin = (try world.get(player, data.Transform)).position;
    for ([_]policy.Identity{ .mikiko, .superfly }, [_]u32{ 4, 2 }) |identity, bit| {
        if (flags & bit == 0) continue;
        const entity = find(world, identity) orelse return false;
        if ((try world.get(entity, data.Health)).current <= 0) return false;
        const pose = (try world.get(entity, data.Transform)).position;
        if ((try world.get(entity, data.Companion)).owner != try world.persistentId(player) or v.length(v.subtract(pose, origin)) >= 150) return false;
    }
    return true;
}

pub fn arrive(actors: *@import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, player: ecs.Entity, traveler: @import("../domain/travel.zig").Traveler, journey: @import("../domain/travel.zig").Journey, now: i64) !void {
    for (traveler.companions) |maybe| if (maybe) |follower| {
        var found = find(world, follower.state.identity);
        if (found == null and journey.kind == .submap and journey.companions & (@as(u2, 1) << @as(u1, @intCast(@intFromEnum(follower.state.identity)))) != 0) {
            const origin = v.add((try world.get(player, data.Transform)).position, follower.offset);
            found = try actors.spawnDynamic(world, slots, projections, follower.classname, origin, follower.angles, now);
        }
        const entity = found orelse continue;
        (try world.get(entity, data.Health)).* = follower.health;
        (try world.get(entity, data.Weapons)).* = follower.weapons;
        (try world.get(entity, data.Character)).* = follower.character;
        (try world.get(entity, data.Keys)).* = follower.keys;
        (try world.get(entity, data.Ailments)).* = follower.ailments;
        var state = follower.state;
        state.carrying = (try world.get(entity, data.Companion)).carrying;
        state.owner = try world.persistentId(player);
        (try world.get(entity, data.Companion)).* = state;
        (try world.get(entity, data.Actor)).threat = 0;
        (try world.get(entity, data.Actor)).mode = .idle;
        (try world.get(entity, data.Actor)).route = .{};
        (try world.get(entity, data.Velocity)).linear = @splat(0);
        try actors.publish(world, entity, projections, now);
    };
}
