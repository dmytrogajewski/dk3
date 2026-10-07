// SPDX-License-Identifier: GPL-2.0-or-later
//! Survival decisions shared by the co-op bot and the companions: which
//! aggressor to deal with, whether to hold and shoot or close in for a firing
//! line, when to break off for a health pack, and the health detour itself.
//! Movement, aim and fire stay with the pilot; these only shape its intent.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const nav = @import("../domain/navigation.zig");
const combat = @import("../domain/bot_combat.zig");
const route = @import("../domain/coop_route.zig");
const catalog = @import("actor_catalog");
const access = @import("region_access.zig");
const Ref = @import("../domain/world_references.zig").Ref;
const pilot = @import("bot_pilot.zig");

/// Aggressors let be for now (unreachable, unhurt or unfinished).
pub const Ignore = struct {
    ids: [6]u32 = @splat(0),
    until: [6]i64 = @splat(0),
    pub fn ignored(self: *const Ignore, id: u32, now: i64) bool {
        for (self.ids, self.until) |entry, until| if (entry == id and now < until) return true;
        return false;
    }
    pub fn ignore(self: *Ignore, id: u32, until: i64) void {
        var slot: usize = 0;
        for (self.until, 0..) |entry, index| if (entry < self.until[slot]) {
            slot = index;
        };
        self.ids[slot] = id;
        self.until[slot] = until;
    }
};

/// A visible health pack or soul close by and on this floor.
pub fn healthNear(world: *data.World, position: v.Vec3) !bool {
    var query = world.queryAccess(data.World.mask(.{ data.Pickup, data.Transform }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.read(data.Pickup), view.read(data.Transform)) |pickup, pose| {
        if (!pickup.visible) continue;
        switch (pickup.kind) {
            .health, .soul => {},
            else => continue,
        }
        if (v.length(v.subtract(pose.position, position)) < 560 and @abs(pose.position[2] - position[2]) <= 128) return true;
    };
    return false;
}

/// Whether a collector may take a pickup (a companion leaves its leader's
/// share and what it is barred from).
pub const Accept = struct {
    context: *const anyopaque,
    call: *const fn (context: *const anyopaque, world: *data.World, item: ecs.Entity) anyerror!bool,
};

/// Badly hurt: detour to the nearest reachable health pickup in view range,
/// still fighting on the way.
pub const Detour = struct {
    target: u32 = 0,
    until: i64 = 0,
    mark: v.Vec3 = @splat(0),
    progress_ms: i64 = 0,
    /// Pickups a detour failed to reach (newest last), and no new detour
    /// before `pause_until`: two packs behind one shut door must not trade
    /// places every frame.
    avoid: [8]u32 = @splat(0),
    avoided: usize = 0,
    pause_until: i64 = 0,
    pub const Query = struct {
        world: *data.World,
        service: nav.Service,
        slot: u16,
        position: v.Vec3,
        health: data.Health,
        now: i64,
        /// Detour below this percentage of maximum health.
        threshold_pct: i32 = 45,
        radius: f32 = 560,
        rise: f32 = 128,
        accept: ?Accept = null,
    };
    /// Where the detour under way leads, or null when there is none (it may
    /// just have ended: reached, gone, too slow, or healed). A detour that
    /// stalled, or whose way the caller found shut (`stuck_control`), is
    /// abandoned and its pack avoided for a while.
    pub fn current(self: *Detour, query: Query, stuck_control: bool) !?v.Vec3 {
        if (self.target == 0) return null;
        const world = query.world;
        const item = world.find(self.target);
        const pickup = if (item) |entity| world.get(entity, data.Pickup) catch null else null;
        if (v.length(v.subtract(query.position, self.mark)) > 24) {
            self.mark = query.position;
            self.progress_ms = query.now;
        }
        const stuck = query.now - self.progress_ms > 5000 or stuck_control;
        if (stuck) {
            self.avoid[self.avoided % self.avoid.len] = self.target;
            self.avoided += 1;
            self.pause_until = query.now + 8000;
        }
        if (pickup == null or !pickup.?.visible or query.now >= self.until or query.health.current >= query.health.maximum or stuck) {
            self.target = 0;
            return null;
        }
        return (try world.get(item.?, data.Transform)).position;
    }
    pub const Found = struct { id: u32, distance: f32, point: v.Vec3 };
    /// Start a detour when hurt enough and a pack lies close, on this floor,
    /// and both reachable and with a way back (never down a drop with no way
    /// back up).
    pub fn choose(self: *Detour, query: Query) !?Found {
        if (query.health.current * 100 >= query.health.maximum * query.threshold_pct) return null;
        if (query.now < self.pause_until) return null;
        const world = query.world;
        var best: ?Found = null;
        var nearest = query.radius;
        var query_items = world.queryAccess(data.World.mask(.{ data.Pickup, data.Transform }), 0, 0);
        defer query_items.deinit();
        while (query_items.next()) |view| for (view.entities(), view.read(data.Pickup), view.read(data.Transform)) |entity, pickup, pose| {
            if (!pickup.visible or std.mem.indexOfScalar(u32, &self.avoid, try world.persistentId(entity)) != null) continue;
            switch (pickup.kind) {
                .health, .soul => {},
                else => continue,
            }
            // Close by and on this floor: navigation ignores doors, and a far
            // item can lie behind one that is shut.
            const distance = v.length(v.subtract(pose.position, query.position));
            if (distance >= nearest or @abs(pose.position[2] - query.position[2]) > query.rise) continue;
            if (query.accept) |accept| if (!try accept.call(accept.context, world, entity)) continue;
            if (try query.service.next(.{ .position = query.position, .destination = pose.position, .slot = query.slot, .player = true }) == null) continue;
            if (try query.service.next(.{ .position = pose.position, .destination = query.position, .slot = query.slot, .player = true }) == null) continue;
            nearest = distance;
            best = .{ .id = try world.persistentId(entity), .distance = distance, .point = pose.position };
        };
        const found = best orelse return null;
        self.target = found.id;
        self.until = query.now + 10000;
        self.mark = query.position;
        self.progress_ms = query.now;
        return found;
    }
};

/// The fight under way: whom, since when, since when cover has blocked the
/// shots, and where the firing stand began.
pub const Engagement = struct {
    id: u32 = 0,
    since_ms: i64 = 0,
    covered_ms: ?i64 = null,
    stand: ?v.Vec3 = null,
};
/// `distance` is the preference-weighted one the choice was made on.
pub const Aggressor = struct { ref: Ref, id: u32, distance: f32 };
pub const Pick = struct {
    self_id: u32,
    /// Hostiles hunting this body are dealt with as hunting this one.
    guard: u32 = 0,
    /// An ordered target is always a candidate.
    preferred: u32 = 0,
    /// The enemy the pilot sees now (taken on when `cautious`).
    seen: u32 = 0,
    cautious: bool = false,
    range: f32 = 1000,
    engaged: u32 = 0,
    ignore: *const Ignore,
    /// A hunter out of sight beyond this distance is not dealt with (it may
    /// never find a way here); null takes every hunter in range.
    unseen_reach: ?f32 = null,
    /// Eye position for the sight check of `unseen_reach`.
    eye: v.Vec3 = @splat(0),
};
/// The nearest living hostile hunting this body (or the guarded one, or
/// ordered, or seen while cautious) within range, favouring the one already
/// engaged.
pub fn pick(frame: pilot.Frame, position: v.Vec3, rule: Pick) !?Aggressor {
    var chosen: ?Aggressor = null;
    var nearest = rule.range;
    if (frame.region) {
        var candidates = access.Damageables.init(frame.world, frame.slots);
        while (candidates.next()) |candidate| if (try consider(frame, candidate, position, rule, nearest)) |found| {
            nearest = found.distance;
            chosen = found;
        };
    } else {
        var query = frame.world.queryAccess(data.World.mask(.{ data.Actor, data.Health, data.Transform }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| if (try consider(frame, .{ .world = frame.world, .entity = entity }, position, rule, nearest)) |found| {
            nearest = found.distance;
            chosen = found;
        };
    }
    return chosen;
}
fn consider(frame: pilot.Frame, candidate: Ref, position: v.Vec3, rule: Pick, nearest: f32) !?Aggressor {
    const actor = candidate.get(data.Actor) catch return null;
    const health = candidate.get(data.Health) catch return null;
    const kind = catalog.entries[actor.definition].kind;
    if (health.current <= 0 or !route.hostile(kind)) return null;
    if (frame.capabilities.ignore_ambient and catalog.ambient(kind)) return null;
    const id = try candidate.id();
    const ordered = rule.preferred != 0 and id == rule.preferred;
    const hunting = actor.threat == rule.self_id or (rule.guard != 0 and actor.threat == rule.guard);
    if (!hunting and !ordered and !(rule.cautious and rule.seen == id)) return null;
    if (!ordered and rule.ignore.ignored(id, frame.now)) return null;
    var distance = v.length(v.subtract((try candidate.get(data.Transform)).position, position));
    if (id == rule.engaged) distance *= 0.6;
    if (ordered) distance *= 0.25;
    if (distance >= nearest) return null;
    if (rule.unseen_reach) |reach| if (!ordered and id != rule.seen and id != rule.engaged and distance > reach and !try pilot.inSight(frame, rule.eye, candidate)) return null;
    return .{ .ref = candidate, .id = id, .distance = distance };
}

pub const Decision = union(enum) {
    /// Not this fight now (broken off for health, or nothing to do).
    none,
    /// Let it be until then; `stale` when time, futile fire or the lack of
    /// a ranged weapon gave up on it (progress toward the route resets).
    ignore: struct { until: i64, stale: bool },
    /// In sight with a clear lane and in reach: hold here (tethered,
    /// dodging) and shoot.
    hold: v.Vec3,
    /// Close in along the area graph for a firing line.
    approach: v.Vec3,
};
pub const Situation = struct {
    frame: pilot.Frame,
    report: pilot.Report,
    position: v.Vec3,
    health: data.Health,
    loadout: data.Weapons,
    /// A health detour is under way.
    detouring: bool = false,
    /// Break off below this percentage of maximum health with a pack near.
    break_pct: i32 = 40,
    max_reach: f32 = 900,
};
/// How to deal with `target`: hold and shoot, close in, break off for a
/// health pack (unless the aggressor is nearly finished), or let it be for a
/// while when it cannot be reached, hurt or finished within 25 s.
pub fn engage(state: *Engagement, situation: Situation, target: Aggressor) !Decision {
    const frame = situation.frame;
    const now = frame.now;
    const health = situation.health;
    if (situation.detouring or (health.current * 100 < health.maximum * situation.break_pct and try healthNear(frame.world, situation.position))) if (target.ref.get(data.Health) catch null) |enemy| if (enemy.current > pilot.finish_health) {
        state.id = 0;
        return .none;
    };
    if (state.id != target.id) {
        state.id = target.id;
        state.since_ms = now;
        state.covered_ms = null;
    }
    const armed = combat.rangedFor(situation.loadout, frame.table, .{ .advancing = true }) or combat.ranged(situation.loadout, frame.table);
    if (now - state.since_ms > 25_000 or situation.report.futile or !armed) {
        state.id = 0;
        return .{ .ignore = .{ .until = now + 15_000, .stale = true } };
    }
    var at = (try target.ref.get(data.Transform)).position;
    if (target.ref.get(data.Body) catch null) |body| at[2] += (body.mins[2] + body.maxs[2]) * 0.5;
    const weapon = combat.select(situation.loadout, frame.table, target.distance);
    const reach = @min(situation.max_reach, @max(@as(f32, 96), frame.table.entries[weapon].range * 0.6));
    // A lane cover keeps blocking for long is no firing position: close in.
    if (situation.report.enemy == target.id and situation.report.lane_blocked) {
        if (state.covered_ms == null) state.covered_ms = now;
    } else state.covered_ms = null;
    const covered = if (state.covered_ms) |since| now - since > 1500 else false;
    const firing = situation.report.enemy == target.id and !covered and v.length(v.subtract(at, situation.position)) <= reach;
    if (firing) {
        if (state.stand == null) state.stand = situation.position;
        return .{ .hold = state.stand.? };
    }
    state.stand = null;
    // Hunting the player from out of sight and far off (a guard in a nest a
    // closed door away): it comes, or is met on the way; never go round the
    // map for it.
    if (situation.report.enemy != target.id and v.length(v.subtract(at, situation.position)) > 600) {
        state.id = 0;
        return .{ .ignore = .{ .until = now + 5_000, .stale = false } };
    }
    const goal = try standing(frame, at);
    // Nowhere to walk to it from here (across a gap, behind a door): let it
    // be for a while.
    if (try frame.service.next(.{ .position = situation.position, .destination = goal, .slot = frame.slot, .player = true }) == null and v.length(v.subtract(goal, situation.position)) > 64) {
        state.id = 0;
        return .{ .ignore = .{ .until = now + 10_000, .stale = false } };
    }
    return .{ .approach = goal };
}
/// The floor below `point` where the body would stand (or `point` itself).
pub fn standing(frame: pilot.Frame, point: v.Vec3) !v.Vec3 {
    const floor = try frame.collision.trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -512 }), .mins = frame.hull.mins, .maxs = frame.hull.maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    if (floor.start_solid or floor.all_solid or floor.fraction == 1) return point;
    return floor.end;
}

test "an ignored aggressor returns once its time is up, and the oldest entry is replaced" {
    var ignore: Ignore = .{};
    ignore.ignore(7, 1000);
    try std.testing.expect(ignore.ignored(7, 999));
    try std.testing.expect(!ignore.ignored(7, 1000));
    for (0..6) |i| ignore.ignore(@intCast(10 + i), @intCast(2000 + i));
    try std.testing.expect(!ignore.ignored(7, 0));
    try std.testing.expect(ignore.ignored(15, 2004));
}
test "a detour ends when healed, gone, slow or shut, and avoids a stalled pack" {
    var world = data.World.init(std.testing.allocator, 4);
    defer world.deinit();
    const pack = try world.create(40, .{ data.Pickup{ .kind = .{ .health = 25 } }, data.Transform{ .position = .{ 100, 0, 0 } } });
    _ = pack;
    var detour: Detour = .{ .target = 40, .until = 10_000, .mark = @splat(0), .progress_ms = 0 };
    const service: nav.Service = undefined;
    var query: Detour.Query = .{ .world = &world, .service = service, .slot = 0, .position = @splat(0), .health = .{ .current = 30, .maximum = 100 }, .now = 1000 };
    try std.testing.expectEqual(@as(?v.Vec3, .{ 100, 0, 0 }), try detour.current(query, false));
    query.now = 6001;
    try std.testing.expectEqual(@as(?v.Vec3, null), try detour.current(query, false));
    try std.testing.expectEqual(@as(u32, 40), detour.avoid[0]);
    try std.testing.expectEqual(@as(i64, 14_001), detour.pause_until);
    detour.target = 40;
    query.now = 7000;
    detour.progress_ms = 7000;
    query.health.current = 100;
    try std.testing.expectEqual(@as(?v.Vec3, null), try detour.current(query, false));
}
