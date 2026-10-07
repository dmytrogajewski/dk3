// SPDX-License-Identifier: GPL-2.0-or-later
//! What a companion wants this frame, as an intent for the shared pilot:
//! follow the leader to a safe spot beside or behind it, fight what threatens
//! the party from a held position on the leader's tether, and look after its
//! own life. Healthy, it engages like the co-op bot; hurt below half, it no
//! longer closes in and fetches health when a pack is near; badly hurt, it
//! falls back behind the leader out of the enemy's line of fire and shoots
//! only when cornered or to finish an enemy that is nearly dead. Orders,
//! authored stops, item collection and lane yielding keep their meaning.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const v = @import("../domain/vector.zig");
const nav = @import("../domain/navigation.zig");
const pilot = @import("bot_pilot.zig");
const survival = @import("bot_survival.zig");
const access = @import("region_access.zig");
const flight = @import("companion_pilot.zig");
const Slots = @import("../engine/slots.zig").Slots;
const Actors = @import("actors.zig").Actors;
const policy = @import("actor_catalog").companions;

/// Health tiers, as percentages of maximum health.
pub const cautious_pct = 50;
pub const retreat_pct = 25;
/// Engagements and approaches stay this close to the leader (an attack
/// order lets the companion go twice as far).
const tether: f32 = 512;
const tether_rise: f32 = 128;
/// A hunter out of sight further than this does not hold the companion.
const unseen_reach: f32 = 384;
/// How far a companion with only a close-quarters weapon fetches a gun.
const unarmed_weapon_reach: f32 = 640;
/// A companion standing this near the leader (and not in its way) stays put.
const comfort_near: f32 = 48;
const comfort_far: f32 = 192;
/// By an exit that takes the companion along (the reference counts it only
/// within 150 units of the player who enters): no further than this.
const exit_far: f32 = 112;
/// How near the leader such an exit has to be for that.
const exit_reach: f32 = 320;
/// Cosine of the half-angle ahead of the leader kept clear (30 degrees).
const line_of_fire_cos: f32 = 0.866;
/// Follow hysteresis: settle within, set off again beyond.
const settle_radius: f32 = 64;
const resume_radius: f32 = 96;
/// An enemy this close leaves a retreating companion nowhere to go.
const cornered_range: f32 = 192;

pub const State = struct {
    /// The leader's recent footing (newest at `crumb_cursor - 1`).
    crumbs: [16]v.Vec3 = @splat(@splat(0)),
    crumb_count: usize = 0,
    crumb_cursor: usize = 0,
    crumb_ms: i64 = 0,
    leader_mark: ?v.Vec3 = null,
    /// Validated follow spot, and where the leader stood when it was chosen.
    follow: ?v.Vec3 = null,
    follow_ms: i64 = 0,
    follow_leader: v.Vec3 = @splat(0),
    /// A spot the pilot refused to step toward (a hazard or exit in the
    /// way): skipped for a while.
    rejected: ?v.Vec3 = null,
    rejected_until: i64 = 0,
    avoided_since: ?i64 = null,
    following: bool = false,
    stay_anchor: ?v.Vec3 = null,
    /// Where the area graph last had a route from, and since when it has
    /// had none (off the navigation mesh: on a machine, a crate, a ledge).
    routable: ?v.Vec3 = null,
    lost_ms: ?i64 = null,
    /// Where straight steering last made headway.
    lost_mark: v.Vec3 = @splat(0),
    retracing: bool = false,
    /// Stranded (no route on, none back): wait here until then; each
    /// fruitless retry doubles the wait (4 s up to 16 s).
    stranded_until: i64 = 0,
    stranded_wait: i64 = 4000,
    engagement: survival.Engagement = .{},
    ignoring: survival.Ignore = .{},
    detour: survival.Detour = .{},
    /// The companion stands in front of the leader, in its line of fire.
    in_way: bool = false,
    /// The leader is by an exit that requires this companion.
    exit_near: bool = false,
    /// The branch that set this frame's intent (developer status line).
    why: []const u8 = "",
};

pub fn think(actors: *const Actors, navigation: nav.Service, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, actor: *data.Actor, pose: *data.Transform, definition: @import("../domain/actors.zig").Definition, now: i64) !void {
    const table = &actors.weapons;
    const companion = try world.get(entity, data.Companion);
    const self_id = try world.persistentId(entity);
    const flown = flight.entry(world, self_id, @intFromEnum(companion.identity), now);
    const brain = &flown.brain;
    brain.why = "inactive";
    // Inactive unless something below gives it a purpose; physics still runs.
    flown.intent = .{ .fight = false, .fire = .hold };
    if (actor.reaction != null) {
        actor.mode = .idle;
        return;
    }
    if (try @import("companion_triggers.zig").advance(world, entity, actor, pose, now)) {
        // An authored stop walks to its mark; a teleport has already happened.
        if (actor.mode == .chase) flown.intent = .{ .destination = actor.threat_position, .fight = false, .fire = .hold, .brake = true };
        return;
    }
    if (!companion.enabled) {
        actor.mode = .idle;
        return;
    }
    if (access.find(world, companion.owner) == null) if (slots.occupants[0]) |player| {
        companion.owner = try world.persistentId(player);
    };
    const owner = access.find(world, companion.owner) orelse {
        actor.mode = .idle;
        return;
    };
    if (companion.order == .collect and companion.collecting == 0 and companion.target != 0) {
        companion.collecting = companion.target;
        companion.collect_forced = true;
        companion.collect_until_ms = now + 15000;
    }
    const frame = try flight.frame(actors, world, slots, projections, entity, navigation, definition, now);
    const leader = (try owner.get(data.Transform)).*;
    const leader_state: ?data.Player = if (owner.get(data.Player) catch null) |state| state.* else null;
    const leader_grounded = if (leader_state) |state| state.ground_entity != c.ENTITYNUM_NONE else true;
    const leader_wet = if (leader_state) |state| state.water_level > 0 else false;
    remember(brain, leader.position, leader_grounded, now);
    if (companion.order != .stay) brain.stay_anchor = null;

    const report = flown.report;
    const health = (try world.get(entity, data.Health)).*;
    const loadout = (try world.get(entity, data.Weapons)).*;
    const attack_order = companion.order == .attack and companion.target != 0;
    const reach_limit: f32 = if (attack_order) tether * 2 else tether;
    var intent: pilot.Intent = .{
        .fight = !companion.carrying and !companion.stopped,
        .guard = companion.owner,
        .preferred = if (attack_order) companion.target else 0,
        .arena = .{ .{ leader.position[0] - reach_limit, leader.position[1] - reach_limit }, .{ leader.position[0] + reach_limit, leader.position[1] + reach_limit } },
    };
    defer {
        retrace(brain, report, &intent, pose.position, now);
        flown.intent = intent;
        cohere(actor, intent, report, pose.position);
    }

    const percent = @divTrunc(health.current * 100, @max(health.maximum, 1));
    // Orders and duties that set their own destination; fighting goes on.
    if (try @import("companion_items.zig").pursuing(world, entity, actor, pose.*, table, actors.episode, now)) {
        intent.close_in = false;
        if (actor.mode == .chase) intent.destination = actor.threat_position;
        if (percent < retreat_pct and !cornered(report, null)) intent.fire = .finish_only;
        brain.why = "collect";
        return;
    }
    if (companion.order == .move) {
        if (v.length(v.subtract(companion.destination, pose.position)) > 24) {
            intent.destination = companion.destination;
            intent.close_in = false;
            brain.why = "move";
            return;
        }
        companion.order = .stay;
    }
    if (companion.stopped) {
        intent.fight = false;
        brain.why = "stopped";
        return;
    }
    if (companion.order == .stay and brain.stay_anchor == null) brain.stay_anchor = pose.position;

    brain.exit_near = try partyExit(frame, leader.position, companion.identity);
    const follow_point = followPoint(frame, brain, leader, leader_wet, companion.identity, pose.position, now);
    var aggressor: ?survival.Aggressor = null;
    // Something hunting the party but out of sight and not close may never
    // find a way here: it does not pin the companion down meanwhile.
    if (intent.fight) aggressor = try survival.pick(frame, pose.position, .{ .self_id = self_id, .guard = companion.owner, .preferred = intent.preferred, .seen = report.enemy, .cautious = true, .engaged = brain.engagement.id, .ignore = &brain.ignoring, .unseen_reach = unseen_reach, .eye = v.add(pose.position, .{ 0, 0, frame.state.view_height }) });
    const danger: ?v.Vec3 = if (aggressor) |target| (try target.ref.get(data.Transform)).position else null;
    // With only a close-quarters weapon (Superfly's starting disruptor), a
    // companion does not trade blows with what hunts it: it keeps behind the
    // leader as a badly hurt one does and strikes only when cornered.
    var tier = percent;
    const unarmed = !@import("../domain/bot_combat.zig").rangedFor(loadout, table, .{});
    // Look for something worth picking up when nothing is being fought; with
    // only a close-quarters weapon, a gun is worth fetching (further, and
    // even mid-fight): it is the companion's best defence.
    if (!companion.carrying and now >= companion.collect_scan_ms and (report.enemy == 0 or unarmed)) {
        companion.collect_scan_ms = now + 1000;
        const found = try @import("companion_items.zig").choose(world, entity, table, actors.episode, navigation, now, .{ .weapons_only = report.enemy != 0, .weapon_reach = if (unarmed) unarmed_weapon_reach else 256 });
        if (found != 0) {
            companion.collecting = found;
            companion.collect_forced = false;
            companion.collect_until_ms = now + 10000;
            actor.route = .{};
            flown.pilot.route = .{};
            brain.why = "scan";
            return;
        }
    }
    if (aggressor) |target| if (unarmed) {
        const hunting = if (target.ref.get(data.Actor) catch null) |other| other.threat == self_id else false;
        if (hunting or target.distance < 300) tier = @min(tier, retreat_pct - 1);
    };

    // Hurt: fetch health on the way when a pack is near and reachable.
    if (!companion.carrying and percent < cautious_pct) {
        const accept: Acceptance = .{ .collector = entity, .table = table, .episode = actors.episode, .now = now, .position = pose.position, .danger = danger };
        const query: survival.Detour.Query = .{ .world = world, .service = navigation, .slot = frame.slot, .position = pose.position, .health = health, .now = now, .threshold_pct = cautious_pct, .accept = .{ .context = &accept, .call = Acceptance.call } };
        const point = try brain.detour.current(query, false) orelse if (try brain.detour.choose(query)) |found| found.point else null;
        if (point) |goal| {
            // A companion takes only the item it has set out to collect.
            if (companion.collecting != brain.detour.target) {
                companion.collecting = brain.detour.target;
                companion.collect_forced = false;
                companion.collect_until_ms = now + 10000;
                flown.pilot.route = .{};
            }
            intent.destination = goal;
            intent.close_in = false;
            if (percent < retreat_pct and !cornered(report, aggressor)) intent.fire = .finish_only;
            brain.why = "detour";
            return;
        }
    }

    if (aggressor) |target| {
        if (tier < retreat_pct) {
            // Badly hurt: behind the leader, away from the enemy, out of its
            // line of fire; shoot back only when there is nowhere to go.
            const enemy = (try target.ref.get(data.Transform)).position;
            const refuge = try retreatPoint(frame, leader, leader_wet, enemy, pose.position);
            intent.close_in = false;
            intent.fire = if (refuge == null or cornered(report, aggressor)) .free else .finish_only;
            if (refuge) |point| {
                if (nav.horizontalDistance(point, pose.position) > 32) intent.destination = point else intent.leash = point;
            } else intent.leash = pose.position;
            brain.why = "retreat";
            return;
        }
        if (tier < cautious_pct or companion.order == .stay) {
            // Hurt (or told to stay): hold where it stands, at the follow spot
            // or its post, and shoot from there.
            intent.close_in = false;
            const post = if (companion.order == .stay) brain.stay_anchor.? else follow_point;
            if (nav.horizontalDistance(post, pose.position) > settle_radius) intent.destination = post else intent.leash = post;
            brain.why = "post";
            return;
        }
        const decision = try survival.engage(&brain.engagement, .{ .frame = frame, .report = report, .position = pose.position, .health = health, .loadout = loadout, .detouring = brain.detour.target != 0, .break_pct = cautious_pct, .max_reach = 900 }, target);
        switch (decision) {
            .none => {},
            .ignore => |until| brain.ignoring.ignore(target.id, until.until),
            .hold => |stand| {
                intent.leash = stand;
                brain.why = "hold";
                return;
            },
            .approach => |goal| if (tethered(leader.position, goal, reach_limit)) {
                intent.destination = goal;
                intent.look_at = (try target.ref.get(data.Transform)).position;
                brain.why = "approach";
                return;
            } else {
                // Beyond the leash: fight from the follow spot instead.
                intent.close_in = false;
                if (nav.horizontalDistance(follow_point, pose.position) > settle_radius) intent.destination = follow_point else intent.leash = follow_point;
                brain.why = "beyond";
                return;
            },
        }
    } else brain.engagement = .{};

    if (companion.order == .stay) {
        brain.why = "stay";
        return;
    }
    if (companion.carrying) intent.fight = false;
    // Follow, with hysteresis so the companion does not shuffle.
    const gap = nav.horizontalDistance(follow_point, pose.position);
    if (gap > resume_radius) brain.following = true else if (gap < settle_radius) brain.following = false;
    if (brain.exit_near and nav.horizontalDistance(pose.position, leader.position) > exit_far and gap > 8) brain.following = true;
    // Standing in the leader's line of fire: step aside however short the way.
    if (brain.in_way and gap > 8) brain.following = true;
    if (brain.following) {
        intent.destination = follow_point;
        intent.close_in = false;
        // The pilot refused to step toward this spot (a hazard or exit in
        // the way) for a second: take the next candidate for a while.
        if (report.avoided_exit != 0) {
            if (brain.avoided_since == null) brain.avoided_since = now;
            if (now - brain.avoided_since.? > 1000) {
                brain.rejected = follow_point;
                brain.rejected_until = now + 3000;
                brain.follow = null;
                brain.avoided_since = null;
            }
        } else brain.avoided_since = null;
        brain.why = "follow";
        return;
    }
    brain.why = "settled";
}

/// Straight steering got the companion somewhere the area graph does not
/// cover, or the leader went where it has no way (a conveyor, a vent): after
/// two seconds without headway, walk back the way it came to the last place a
/// route existed; with nowhere to go back to, wait there and try again now
/// and then rather than hop against the obstacle.
fn retrace(brain: *State, report: pilot.Report, intent: *pilot.Intent, position: v.Vec3, now: i64) void {
    if (report.waypoint != null) {
        brain.routable = position;
        brain.lost_ms = null;
        brain.retracing = false;
        brain.stranded_until = 0;
        brain.stranded_wait = 4000;
        return;
    }
    if (brain.retracing) {
        const back = brain.routable.?;
        // There, or the way back is shut too: plan afresh from here.
        if (nav.horizontalDistance(back, position) < 24 or now - brain.lost_ms.? > 7000) {
            brain.retracing = false;
            brain.lost_ms = now;
            brain.lost_mark = position;
            if (nav.horizontalDistance(back, position) >= 24) brain.routable = null;
            return;
        }
        steerBack(intent, back);
        return;
    }
    // While waiting, the pilot plans nothing and so reports no route
    // problem: that is no sign the way has opened.
    if (now < brain.stranded_until) {
        intent.destination = null;
        return;
    }
    if (intent.destination == null or !(report.no_route or report.routeless)) {
        brain.lost_ms = null;
        brain.stranded_until = 0;
        return;
    }
    // Straight steering that is getting somewhere is not lost.
    if (brain.lost_ms == null or nav.horizontalDistance(position, brain.lost_mark) > 48) {
        if (brain.lost_ms != null) brain.stranded_wait = 4000;
        brain.lost_ms = now;
        brain.lost_mark = position;
        return;
    }
    if (now - brain.lost_ms.? < 2000) return;
    if (brain.routable) |back| if (nav.horizontalDistance(back, position) >= 24 and nav.horizontalDistance(back, position) <= 384) {
        brain.retracing = true;
        steerBack(intent, back);
        return;
    };
    brain.stranded_until = now + brain.stranded_wait;
    brain.lost_ms = brain.stranded_until;
    brain.stranded_wait = @min(brain.stranded_wait * 2, 16000);
    intent.destination = null;
}
fn steerBack(intent: *pilot.Intent, back: v.Vec3) void {
    intent.destination = back;
    intent.direct = true;
    intent.brake = true;
    intent.leash = null;
}
/// Keep the actor's own fields telling the truth for animation, hostiles and
/// the lane-yield check.
fn cohere(actor: *data.Actor, intent: pilot.Intent, report: pilot.Report, position: v.Vec3) void {
    actor.threat = report.enemy;
    if (intent.destination) |goal| {
        actor.threat_position = goal;
        actor.mode = if (nav.horizontalDistance(goal, position) > 24) .chase else .idle;
    } else actor.mode = if (report.enemy != 0 and intent.fight) .attack else .idle;
}
fn cornered(report: pilot.Report, aggressor: ?survival.Aggressor) bool {
    if (report.enemy != 0 and report.enemy_distance < cornered_range) return true;
    if (aggressor) |target| if (report.enemy == target.id and report.dodging) return target.distance < cornered_range * 1.5;
    return false;
}
fn tethered(leader: v.Vec3, point: v.Vec3, reach: f32) bool {
    return nav.horizontalDistance(leader, point) <= reach and @abs(point[2] - leader[2]) <= tether_rise;
}
const Acceptance = struct {
    collector: ecs.Entity,
    table: *const @import("../domain/weapons.zig").Table,
    episode: u8,
    now: i64,
    position: v.Vec3,
    /// What hunts the companion: no pack past it is worth the walk.
    danger: ?v.Vec3 = null,
    fn call(context: *const anyopaque, world: *data.World, item: ecs.Entity) anyerror!bool {
        const self: *const Acceptance = @ptrCast(@alignCast(context));
        if (self.danger) |enemy| if (passesNear(self.position, (try world.get(item, data.Transform)).position, enemy, 160)) return false;
        return @import("companion_items.zig").allows(world, self.collector, item, self.table, self.episode, false, self.now);
    }
};

/// Record where the leader has walked; a teleport breaks the trail.
fn remember(brain: *State, leader: v.Vec3, grounded: bool, now: i64) void {
    if (brain.leader_mark) |mark| if (v.length(v.subtract(leader, mark)) > 512) {
        brain.crumb_count = 0;
        brain.follow = null;
    };
    brain.leader_mark = leader;
    if (!grounded or now - brain.crumb_ms < 200) return;
    if (brain.crumb_count > 0) {
        const newest = brain.crumbs[(brain.crumb_cursor + brain.crumbs.len - 1) % brain.crumbs.len];
        if (v.length(v.subtract(newest, leader)) < 48) return;
    }
    brain.crumbs[brain.crumb_cursor] = leader;
    brain.crumb_cursor = (brain.crumb_cursor + 1) % brain.crumbs.len;
    brain.crumb_count = @min(brain.crumb_count + 1, brain.crumbs.len);
    brain.crumb_ms = now;
}

/// Where to stand while following: beside and behind the leader on the
/// companion's own side, the other side, straight behind, or back along the
/// leader's trail, whichever first is solid, dry, out of every hazard and
/// crusher's path and reachable. With none, the leader's own spot (the
/// follow radius keeps the companion short of it).
fn followPoint(frame: pilot.Frame, brain: *State, leader: data.Transform, leader_wet: bool, identity: policy.Identity, position: v.Vec3, now: i64) v.Vec3 {
    if (brain.follow) |held| if (now - brain.follow_ms < 500 and v.length(v.subtract(leader.position, brain.follow_leader)) < 48) return held;
    // Where the companion already stands will do while it is near, level
    // with the leader, out of its line of fire and on safe footing: the
    // leader turning on the spot must not send it running round.
    const stays = comfortable(frame, brain, leader, leader_wet, position, now) catch false;
    const chosen = if (stays) position else chooseFollow(frame, brain, leader, leader_wet, identity, position, now) catch null;
    brain.follow = chosen orelse leader.position;
    brain.follow_ms = now;
    brain.follow_leader = leader.position;
    return brain.follow.?;
}
fn chooseFollow(frame: pilot.Frame, brain: *State, leader: data.Transform, leader_wet: bool, identity: policy.Identity, position: v.Vec3, now: i64) !?v.Vec3 {
    const side: f32 = if (identity == .mikiko) -48 else 48;
    const axes = v.basis(.{ 0, leader.angles[1], 0 });
    const offsets = [_][2]f32{ .{ -80, side }, .{ -80, -side }, .{ -128, 0 }, .{ -64, 0 } };
    // Of the spots behind the leader, the one nearest the companion: the
    // shortest move that puts it right again.
    var best: ?v.Vec3 = null;
    for (offsets) |offset| {
        const candidate = v.add(leader.position, v.add(v.scale(axes.forward, offset[0]), v.scale(axes.right, offset[1])));
        if (rejected(brain, candidate, now)) continue;
        const point = try standable(frame, candidate, leader.position, leader_wet, position) orelse continue;
        if (best == null or nav.horizontalDistance(point, position) < nav.horizontalDistance(best.?, position)) best = point;
    }
    if (best) |point| return point;
    var index: usize = 0;
    while (index < brain.crumb_count) : (index += 1) {
        const crumb = brain.crumbs[(brain.crumb_cursor + brain.crumbs.len - 1 - index) % brain.crumbs.len];
        const back = nav.horizontalDistance(crumb, leader.position);
        if (back < 96 or back > 256 or rejected(brain, crumb, now)) continue;
        if (try standable(frame, crumb, leader.position, leader_wet, position)) |point| return point;
    }
    return null;
}
fn comfortable(frame: pilot.Frame, brain: *State, leader: data.Transform, leader_wet: bool, position: v.Vec3, now: i64) !bool {
    const away = nav.horizontalDistance(position, leader.position);
    // In front of the leader (and not far off) is in its line of fire.
    const offset: v.Vec3 = .{ position[0] - leader.position[0], position[1] - leader.position[1], 0 };
    brain.in_way = away > 1 and away < 400 and v.dot(v.scale(offset, 1 / away), v.basis(.{ 0, leader.angles[1], 0 }).forward) > line_of_fire_cos;
    if (brain.in_way) return false;
    if (away < comfort_near or away > (if (brain.exit_near) exit_far else comfort_far) or @abs(position[2] - leader.position[2]) > 48) return false;
    if (rejected(brain, position, now)) return false;
    return try standable(frame, position, leader.position, leader_wet, position) != null;
}
/// Whether an exit that takes this companion along lies by `point`.
fn partyExit(frame: pilot.Frame, point: v.Vec3, identity: policy.Identity) !bool {
    const bit: u32 = if (identity == .mikiko) 4 else 2;
    var exits = frame.world.queryAccess(data.World.mask(.{ data.Exit, data.MapObject, data.Binding }), 0, 0);
    defer exits.deinit();
    while (exits.next()) |view| for (view.read(data.MapObject), view.read(data.Binding)) |object, binding| {
        if (object.flags & bit == 0 or binding.slot >= frame.projections.len) continue;
        const box = frame.projections[binding.slot].shared;
        var nearest: v.Vec3 = undefined;
        for (0..3) |axis| nearest[axis] = std.math.clamp(point[axis], box.absmin[axis], box.absmax[axis]);
        if (v.length(v.subtract(nearest, point)) < exit_reach) return true;
    };
    return false;
}
fn rejected(brain: *const State, point: v.Vec3, now: i64) bool {
    const bad = brain.rejected orelse return false;
    return now < brain.rejected_until and v.length(v.subtract(bad, point)) < 32;
}
/// Behind the leader as seen from the enemy, on safe footing.
fn retreatPoint(frame: pilot.Frame, leader: data.Transform, leader_wet: bool, enemy: v.Vec3, position: v.Vec3) !?v.Vec3 {
    var away = v.subtract(leader.position, enemy);
    away[2] = 0;
    if (v.length(away) < 1) away = v.basis(.{ 0, leader.angles[1] + 180, 0 }).forward;
    const direction = v.normalize(away);
    for ([_]f32{ 160, 96 }) |distance| for ([_]f32{ 0, 35, -35 }) |degrees| {
        const angle = std.math.atan2(direction[1], direction[0]) + degrees * std.math.pi / 180;
        const candidate = v.add(leader.position, .{ @cos(angle) * distance, @sin(angle) * distance, 0 });
        // Never by way of the enemy.
        if (passesNear(position, candidate, enemy, 160)) continue;
        const point = try standable(frame, candidate, leader.position, leader_wet, position) orelse continue;
        // Out of the enemy's line of fire where possible: the leader's body
        // or cover between.
        if (try @import("bot_evasion.zig").cover(frame, point, v.add(enemy, .{ 0, 0, 24 }))) |aside| {
            const hidden = v.add(point, aside);
            if (try standable(frame, hidden, leader.position, leader_wet, position)) |better| return better;
        }
        return point;
    };
    return null;
}
/// Whether walking straight from `from` to `to` takes the walker within
/// `radius` of `point` (horizontally) and closer than it already is.
fn passesNear(from: v.Vec3, to: v.Vec3, point: v.Vec3, radius: f32) bool {
    const segment: v.Vec3 = .{ to[0] - from[0], to[1] - from[1], 0 };
    const offset: v.Vec3 = .{ point[0] - from[0], point[1] - from[1], 0 };
    const length2 = v.dot(segment, segment);
    const along = if (length2 < 1) 0 else std.math.clamp(v.dot(offset, segment) / length2, 0, 1);
    const closest = nav.horizontalDistance(v.add(from, v.scale(segment, along)), point);
    return closest < radius and closest < nav.horizontalDistance(from, point) - 16;
}
/// `point` settled on the floor below it, when that floor is level with the
/// leader's, dry (water only when the leader is in it), outside every hazard
/// volume and crusher's path, and the companion can get there.
pub fn standable(frame: pilot.Frame, point: v.Vec3, leader: v.Vec3, leader_wet: bool, position: v.Vec3) !?v.Vec3 {
    const hull = frame.hull;
    const raised = v.add(point, .{ 0, 0, 18 });
    const floor = try frame.collision.trace(.{ .start = raised, .end = v.add(raised, .{ 0, 0, -82 }), .mins = hull.mins, .maxs = hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    if (floor.start_solid or floor.all_solid or floor.fraction == 1 or floor.normal[2] < 0.7) return null;
    const spot = floor.end;
    if (@abs(spot[2] - leader[2]) > 48) return null;
    var harmful: u32 = c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO;
    if (!leader_wet) harmful |= c.CONTENTS_WATER;
    if (try frame.collision.contents(v.add(spot, .{ 0, 0, hull.mins[2] + 1 }), frame.slot) & harmful != 0) return null;
    if (try pilot.insideHazard(frame, spot)) return null;
    if (try pilot.crushOverhead(frame, spot) != null) return null;
    if (try pilot.walkable(frame, leader, spot)) return spot;
    if (try frame.service.next(.{ .position = position, .destination = spot, .slot = frame.slot, .player = true }) != null) return spot;
    return null;
}

const testing = std.testing;
/// Flat floor at z = 0 (an origin rests at 24); a pit beyond x = 200 and
/// lava between y = 100 and 200.
const Ground = struct {
    fn trace(_: *anyopaque, request: @import("../domain/collision.zig").Request) anyerror!@import("../domain/collision.zig").Trace {
        if (request.end[2] < request.start[2] - 1 and @abs(request.end[0] - request.start[0]) < 0.5 and @abs(request.end[1] - request.start[1]) < 0.5) {
            if (request.start[0] > 200) return .{ .fraction = 1, .end = request.end, .normal = .{ 0, 0, 1 } };
            const rest = -request.mins[2];
            if (request.start[2] < rest or request.end[2] > rest) return .{ .fraction = 1, .end = request.end, .normal = .{ 0, 0, 1 } };
            const fraction = (request.start[2] - rest) / (request.start[2] - request.end[2]);
            return .{ .fraction = fraction, .end = .{ request.start[0], request.start[1], rest }, .normal = .{ 0, 0, 1 } };
        }
        return .{ .fraction = 1, .end = request.end, .normal = .{ 0, 0, 1 } };
    }
    fn contents(_: *anyopaque, point: v.Vec3, _: u16) anyerror!u32 {
        if (point[1] > 100 and point[1] < 200 and point[2] < 8) return c.CONTENTS_LAVA;
        return 0;
    }
    /// The area graph routes around the lava to any floor.
    fn next(_: *anyopaque, request: nav.Request) anyerror!?nav.Waypoint {
        return .{ .point = request.destination };
    }
};
fn testFrame(world: *data.World, slots: *Slots) pilot.Frame {
    const static = struct {
        var ground: u8 = 0;
    };
    return .{
        .world = world,
        .slots = slots,
        .projections = &.{},
        .service = .{ .context = &static.ground, .next_fn = Ground.next },
        .collision = .{ .context = &static.ground, .trace_fn = Ground.trace, .contents_fn = Ground.contents },
        .table = undefined,
        .slot = 0,
        .entity = undefined,
        .state = .{},
        .now = 0,
        .region = true,
    };
}
test "follow spots are never over a pit or in lava, and fall back along the leader's trail" {
    var world = data.World.init(testing.allocator, 1);
    defer world.deinit();
    var slots: Slots = .{};
    const frame = testFrame(&world, &slots);
    const leader: v.Vec3 = .{ 0, 0, 24 };
    try testing.expect(try standable(frame, .{ -80, 48, 24 }, leader, false, leader) != null);
    try testing.expectEqual(@as(?v.Vec3, null), try standable(frame, .{ 260, 0, 24 }, leader, false, leader));
    try testing.expectEqual(@as(?v.Vec3, null), try standable(frame, .{ 0, 150, 24 }, leader, false, leader));
    // Leader facing -x at the pit's edge: every spot behind it is in the pit
    // (Superfly's side is lava); the trail back toward safe ground is used.
    var brain: State = .{};
    remember(&brain, .{ 60, 0, 24 }, true, 1000);
    remember(&brain, .{ 120, 0, 24 }, true, 1300);
    remember(&brain, .{ 190, 0, 24 }, true, 1600);
    const edge: data.Transform = .{ .position = .{ 190, 160, 24 }, .angles = .{ 0, 180, 0 } };
    const chosen = try chooseFollow(frame, &brain, edge, false, .superfly, edge.position, 1700);
    try testing.expect(chosen != null);
    try testing.expect(chosen.?[0] <= 200);
    try testing.expect(chosen.?[1] <= 100 or chosen.?[1] >= 200);
}
test "a retreat goes behind the leader away from the enemy" {
    var world = data.World.init(testing.allocator, 1);
    defer world.deinit();
    var slots: Slots = .{};
    const frame = testFrame(&world, &slots);
    const leader: data.Transform = .{ .position = .{ 0, -200, 24 } };
    const point = (try retreatPoint(frame, leader, false, .{ 150, -200, 24 }, .{ 50, -200, 24 })).?;
    try testing.expect(point[0] < leader.position[0]);
}
test "the leader's trail resets on a teleport" {
    var brain: State = .{};
    remember(&brain, .{ 0, 0, 0 }, true, 1000);
    remember(&brain, .{ 100, 0, 0 }, true, 1300);
    try testing.expectEqual(@as(usize, 2), brain.crumb_count);
    remember(&brain, .{ 2000, 0, 0 }, true, 1600);
    try testing.expectEqual(@as(usize, 1), brain.crumb_count);
}
test "a companion off the area graph walks back to where a route last existed" {
    var brain: State = .{};
    var intent: pilot.Intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{ .waypoint = .{ .point = .{ 10, 0, 0 } } }, &intent, .{ 0, 0, 0 }, 0);
    try testing.expectEqual(@as(?v.Vec3, .{ 0, 0, 0 }), brain.routable);
    intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{ .routeless = true }, &intent, .{ 80, 0, 0 }, 1000);
    retrace(&brain, .{ .routeless = true }, &intent, .{ 90, 0, 0 }, 2000);
    try testing.expectEqual(@as(?v.Vec3, .{ 500, 0, 0 }), intent.destination);
    retrace(&brain, .{ .routeless = true }, &intent, .{ 90, 0, 0 }, 3100);
    try testing.expectEqual(@as(?v.Vec3, .{ 0, 0, 0 }), intent.destination);
    try testing.expect(intent.direct);
    // Steering straight back reports no route problem; the retrace holds.
    intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{}, &intent, .{ 60, 0, 0 }, 3200);
    try testing.expectEqual(@as(?v.Vec3, .{ 0, 0, 0 }), intent.destination);
    // Back on the graph: planning resumes toward the real goal.
    intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{ .waypoint = .{ .point = .{ 10, 0, 0 } } }, &intent, .{ 5, 0, 0 }, 3500);
    try testing.expectEqual(@as(?v.Vec3, .{ 500, 0, 0 }), intent.destination);
    try testing.expect(!brain.retracing);
}
test "a stranded companion waits instead of hopping against the way it cannot go" {
    var brain: State = .{};
    var intent: pilot.Intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{ .waypoint = .{ .point = .{ 10, 0, 0 } } }, &intent, .{ 0, 0, 0 }, 0);
    // The last routable spot is where it stands: no way back to take.
    retrace(&brain, .{ .routeless = true }, &intent, .{ 4, 0, 0 }, 100);
    retrace(&brain, .{ .routeless = true }, &intent, .{ 4, 0, 30 }, 2200);
    try testing.expectEqual(@as(?v.Vec3, null), intent.destination);
    intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{ .routeless = true }, &intent, .{ 4, 0, 0 }, 4000);
    try testing.expectEqual(@as(?v.Vec3, null), intent.destination);
    // The idle pilot's clean report does not end the wait early.
    intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{}, &intent, .{ 4, 0, 0 }, 4100);
    try testing.expectEqual(@as(?v.Vec3, null), intent.destination);
    // The wait over, it tries again.
    intent = .{ .destination = .{ 500, 0, 0 } };
    retrace(&brain, .{ .routeless = true }, &intent, .{ 4, 0, 0 }, 6300);
    try testing.expectEqual(@as(?v.Vec3, .{ 500, 0, 0 }), intent.destination);
}
test "a retreat never runs past the enemy" {
    try testing.expect(passesNear(.{ 0, 0, 0 }, .{ 400, 0, 0 }, .{ 200, 50, 0 }, 160));
    try testing.expect(!passesNear(.{ 0, 0, 0 }, .{ -400, 0, 0 }, .{ 200, 50, 0 }, 160));
    try testing.expect(!passesNear(.{ 0, 0, 0 }, .{ 0, 400, 0 }, .{ 300, 200, 0 }, 160));
    // Already beside it: stepping straight away is no approach.
    try testing.expect(!passesNear(.{ 0, 0, 0 }, .{ -300, 0, 0 }, .{ 100, 0, 0 }, 160));
}
test "a companion near the leader stays put while the leader turns, and steps out of its line of fire" {
    var world = data.World.init(testing.allocator, 1);
    defer world.deinit();
    var slots: Slots = .{};
    const frame = testFrame(&world, &slots);
    // Beside the leader, 100 units off on safe floor.
    const standing: v.Vec3 = .{ -40, -90, 24 };
    var brain: State = .{};
    for ([_]f32{ 0, 90, 180, 270, 45 }, 0..) |yaw, turn| {
        const leader: data.Transform = .{ .position = .{ 0, 0, 24 }, .angles = .{ 0, yaw, 0 } };
        const forward = v.basis(.{ 0, yaw, 0 }).forward;
        const ahead = v.dot(v.normalize(.{ standing[0], standing[1], 0 }), forward) > line_of_fire_cos;
        const point = followPoint(frame, &brain, leader, false, .superfly, standing, @as(i64, @intCast(turn)) * 1000);
        if (ahead) {
            // Out of the way, and only as far as the nearest spot behind.
            try testing.expect(v.length(v.subtract(point, standing)) > 1);
            try testing.expect(v.dot(v.subtract(point, leader.position), forward) < 0);
        } else try testing.expectEqual(standing, point);
    }
}
