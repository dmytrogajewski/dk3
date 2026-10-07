// SPDX-License-Identifier: GPL-2.0-or-later
//! Party spawning, orders and class-owned weapon execution. What a companion
//! wants is companion_brain's; how it moves and aims is the shared pilot's.
const std = @import("std");
const data = @import("../domain/components.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const access = @import("region_access.zig");
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
/// A continuing party member can physically occupy any admitted identity neighbor.
/// Authored destination incarnations remain handled by the local find/arrive path.
pub fn member(world: *data.World, identity: policy.Identity, owner: u32) ?Ref {
    if (find(world, identity)) |entity| if ((world.get(entity, data.Companion) catch unreachable).owner == owner) return .{ .world = world, .entity = entity };
    const context = access.contextFor(world) orelse return null;
    var neighbors = access.Neighbors.init(context);
    while (neighbors.next()) |neighbor| {
        if (&neighbor.world.? == world) continue;
        const entity = find(&neighbor.world.?, identity) orelse continue;
        if ((neighbor.world.?.get(entity, data.Companion) catch unreachable).owner == owner) return .{ .world = &neighbor.world.?, .entity = entity };
    }
    return null;
}
/// Include recruited members in neighboring worlds, including a stopped or
/// carried companion. Unrecruited map actors are not members of Hiro's party.
pub fn healthyParty(world: *data.World, player: ecs.Entity) !bool {
    const eligible = @import("../domain/checkpoint.zig").Autosave.healthy;
    const health = (try world.get(player, data.Health)).*;
    if (!eligible(health.current, health.maximum)) return false;
    const owner = try world.persistentId(player);
    for ([_]policy.Identity{ .mikiko, .superfly }) |identity| {
        const follower = member(world, identity, owner) orelse continue;
        const value = (try follower.world.get(follower.entity, data.Health)).*;
        if (!eligible(value.current, value.maximum)) return false;
    }
    return true;
}
pub fn capture(world: *data.World, player: ecs.Entity, episode: u8, now: i64) !@import("../domain/travel.zig").Traveler {
    const travel = @import("../domain/travel.zig");
    var result = try travel.Traveler.capture(world, player, episode, now);
    const owner = try world.persistentId(player);
    const origin = (try world.get(player, data.Transform)).position;
    for ([_]policy.Identity{ .mikiko, .superfly }, 0..) |identity, index| {
        const follower = member(world, identity, owner) orelse continue;
        result.companions[index] = try travel.Follower.capture(follower.world, follower.entity, origin);
    }
    return result;
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
    const context = access.contextFor(world) orelse return error.PartyWorldUnavailable;
    var candidates = access.Damageables.init(world, &context.slots);
    var changed = false;
    while (candidates.next()) |ref| {
        const companion = ref.get(data.Companion) catch continue;
        if (!std.mem.eql(u8, name, "all") and !std.mem.eql(u8, name, @tagName(companion.identity))) continue;
        if ((try ref.get(data.Health)).current <= 0 or !companion.enabled) continue;
        if (requested == .collect) {
            const item = ref.world.find(target) orelse continue;
            if (!try @import("companion_items.zig").allows(ref.world, ref.entity, item, &actors.weapons, actors.episode, true, now)) continue;
        }
        if (requested == .attack) {
            const enemy = access.find(world, target) orelse continue;
            const target_actor = enemy.get(data.Actor) catch continue;
            const kind = @import("actor_catalog").entries[target_actor.definition].kind;
            if (kind == .companion or kind == .civilian or @import("actor_catalog").ambient(kind) or companion.carrying or (try enemy.get(data.Health)).current <= 0) continue;
        }
        companion.collecting = if (requested == .collect) target else 0;
        companion.collect_forced = requested == .collect;
        companion.collect_until_ms = now + 15000;
        companion.yielding_until_ms = 0;
        (try ref.get(data.Actor)).route = .{};
        @import("companion_pilot.zig").forget(try ref.id());
        companion.owner = try world.persistentId(player);
        companion.order = requested;
        companion.target = target;
        companion.stopped = false;
        companion.authored = .none;
        companion.animation_until = null;
        (try ref.get(data.Actor)).scripted_pose = null;
        if (requested == .move) {
            companion.destination = if (access.find(world, target)) |destination| (try destination.get(data.Transform)).position else point;
        }
        changed = true;
    }
    return changed;
}
pub fn combat(actors: *const @import("actors.zig").Actors, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, table: *const @import("../domain/weapons.zig").Table, now: i64, elapsed: u32) !void {
    const occupants = slots.occupants;
    for (occupants) |occupant| {
        const entity = occupant orelse continue;
        const companion = world.get(entity, data.Companion) catch continue;
        const health = (try world.get(entity, data.Health)).current;
        if (health <= 0) {
            if (!companion.death_reported) {
                if (access.find(world, companion.owner)) |owner| if ((try owner.get(data.Health)).current > 0) {
                    const actor = (try world.get(entity, data.Actor)).*;
                    const player = try owner.get(data.Player);
                    player.mode = .frozen;
                    if (now >= actor.changed_ms + actors.table.definitions[actor.definition].death.duration()) {
                        player.mode = .dead;
                        companion.death_reported = true;
                        engine.send(0, "cp \"A companion has died. Load a saved game to continue.\"");
                    }
                    if (access.contextFor(owner.world)) |context| {
                        const scope = try context.select();
                        defer scope.deinit();
                        try @import("weapon_actions.zig").cancel(owner.world, &context.slots, &context.projection, owner.entity);
                    } else try @import("weapon_actions.zig").cancel(owner.world, slots, projections, owner.entity);
                };
            }
            continue;
        }
        const pose = (try world.get(entity, data.Transform)).*;
        const slot = (try world.get(entity, data.Binding)).slot;
        const loadout = try world.get(entity, data.Weapons);
        // The pilot chose the weapon and whether to pull the trigger this
        // frame; the companion's own weapon step raises, fires and reloads.
        const decided = @import("companion_pilot.zig").output(try world.persistentId(entity), now);
        if (decided) |choice| companion.selected_weapon = if (companion.carrying or loadout.dk3Inventory & (@as(i32, 1) << choice.weapon) == 0) 0 else choice.weapon;
        if (loadout.weapon == 0 and companion.selected_weapon == 0) continue;
        var events: @import("../domain/weapons.zig").Events = .{};
        var context: @import("../domain/weapons.zig").Context = .{ .ps = loadout, .table = table, .events = &events, .service = engine.collisionService(), .slot = slot, .shot_mask = c.MASK_SHOT, .single_player = true };
        var player = companion.motor;
        var motion: @import("../domain/slide.zig").State = .{ .position = pose.position, .velocity = @splat(0) };
        const hook = context.hook();
        const target = access.find(world, (try world.get(entity, data.Actor)).threat);
        // The weapon's own leader-safety lane stays the last word.
        const wants_fire = companion.enabled and !companion.stopped and !companion.carrying and companion.selected_weapon != 0 and (if (decided) |choice| choice.fire else false) and !@import("nightmare.zig").frozen(world, entity) and (if (target) |enemy| try @import("companion_weapons.zig").clear(world, entity, enemy, companion.selected_weapon, table) else false);
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
        const entity = member(world, identity, try world.persistentId(player)) orelse return false;
        if ((try entity.get(data.Health)).current <= 0) return false;
        const pose = (try entity.get(data.Transform)).position;
        if (v.length(v.subtract(pose, origin)) >= 150) return false;
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

test "autosaves require healthy recruited companions even when stopped or carried" {
    var world = data.World.init(std.testing.allocator, 8);
    defer world.deinit();
    const player = try world.create(1, .{data.Health{ .current = 91 }});
    const mikiko = try world.create(2, .{ data.Health{ .current = 180, .maximum = 200 }, data.Companion{ .identity = .mikiko, .owner = 1, .carrying = true } });
    const superfly = try world.create(3, .{ data.Health{ .current = 100 }, data.Companion{ .identity = .superfly, .owner = 1, .stopped = true } });
    try std.testing.expect(!try healthyParty(&world, player));
    (try world.get(mikiko, data.Health)).current = 181;
    try std.testing.expect(try healthyParty(&world, player));
    (try world.get(superfly, data.Health)).current = 0;
    try std.testing.expect(!try healthyParty(&world, player));
    (try world.get(superfly, data.Companion)).owner = 0;
    try std.testing.expect(try healthyParty(&world, player));
    (try world.get(player, data.Health)).current = 90;
    try std.testing.expect(!try healthyParty(&world, player));
}
