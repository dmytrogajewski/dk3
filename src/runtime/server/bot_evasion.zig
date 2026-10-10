// SPDX-License-Identifier: GPL-2.0-or-later
//! Bot survival movement: what a careful player does under fire. Incoming
//! hostile projectiles and forecast spray impacts become threats; the bot picks
//! a walkable step that maximises its distance from them. Only movement input is
//! produced; damage, collision and projectile flight stay with the simulation.
const std = @import("std");
const data = @import("../domain/components.zig");
const c = @import("../engine/abi.zig").c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const nav = @import("../domain/navigation.zig");
const Frame = @import("bot_pilot.zig").Frame;
/// A predicted hit: where and when it lands, and how far its damage reaches.
pub const Threat = struct { point: v.Vec3, eta: f32, radius: f32 = 96 };
pub const Threats = struct {
    items: [16]Threat = undefined,
    len: usize = 0,
    fn add(self: *Threats, threat: Threat) void {
        if (self.len < self.items.len) {
            self.items[self.len] = threat;
            self.len += 1;
        }
    }
    pub fn slice(self: *const Threats) []const Threat {
        return self.items[0..self.len];
    }
};
/// Hostile shots that will pass close to the player within 1.5 s, and spray
/// that the server forecasts to land near it within 2.5 s.
pub fn gather(frame: Frame, position: v.Vec3) !Threats {
    var result: Threats = .{};
    const world = frame.world;
    const self_id = try world.persistentId(frame.entity);
    {
        var query = world.queryAccess(data.World.mask(.{ data.Projectile, data.Transform, data.Velocity }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.Projectile), view.read(data.Transform), view.read(data.Velocity)) |shot, pose, velocity| {
            if (shot.owner == self_id or shot.stuck or shot.resting) continue;
            const speed2 = v.dot(velocity.linear, velocity.linear);
            if (speed2 < 1) continue;
            const relative = v.subtract(position, pose.position);
            const time = v.dot(relative, velocity.linear) / speed2;
            if (time < 0 or time > 1.5) continue;
            const closest = v.add(pose.position, v.scale(velocity.linear, time));
            if (v.length(v.subtract(closest, position)) > 96) continue;
            result.add(.{ .point = closest, .eta = time });
        };
    }
    // Actor-launched missiles (sludge globs, fireballs, rockets) are their
    // own attack entities, not player projectiles: dodge them alike.
    {
        var query = world.queryAccess(data.World.mask(.{ data.ActorAttack, data.Transform, data.Velocity }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.ActorAttack), view.read(data.Transform), view.read(data.Velocity)) |attack, pose, velocity| {
            if (attack.owner == self_id) continue;
            const speed2 = v.dot(velocity.linear, velocity.linear);
            if (speed2 < 1) continue;
            const relative = v.subtract(position, pose.position);
            const time = v.dot(relative, velocity.linear) / speed2;
            if (time < 0 or time > 1.5) continue;
            const closest = v.add(pose.position, v.scale(velocity.linear, time));
            if (v.length(v.subtract(closest, position)) > 96) continue;
            result.add(.{ .point = closest, .eta = time });
        };
    }
    // Actor lasers (an inmater's, a lasergat's, a deathsphere's bolts) fly
    // as their own entities too.
    {
        var query = world.queryAccess(data.World.mask(.{ data.ActorLaser, data.Transform, data.Velocity }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.ActorLaser), view.read(data.Transform), view.read(data.Velocity)) |laser, pose, velocity| {
            if (laser.owner == self_id) continue;
            const speed2 = v.dot(velocity.linear, velocity.linear);
            if (speed2 < 1) continue;
            const relative = v.subtract(position, pose.position);
            const time = v.dot(relative, velocity.linear) / speed2;
            if (time < 0 or time > 1.5) continue;
            const closest = v.add(pose.position, v.scale(velocity.linear, time));
            if (v.length(v.subtract(closest, position)) > 96) continue;
            result.add(.{ .point = closest, .eta = time, .radius = 48 });
        };
    }
    // Slow authored missiles burst on contact with the player as well as on
    // geometry: dodge their closest approach, not only their floor impact.
    inline for (.{ data.ThunderSpray, data.FrogSpit }) |Missile| {
        var query = world.queryAccess(data.World.mask(.{ Missile, data.Transform, data.Velocity }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.read(data.Transform), view.read(data.Velocity)) |pose, velocity| {
            const speed2 = v.dot(velocity.linear, velocity.linear);
            if (speed2 < 1) continue;
            const relative = v.subtract(position, pose.position);
            const time = v.dot(relative, velocity.linear) / speed2;
            if (time < 0 or time > 2.5) continue;
            const closest = v.add(pose.position, v.scale(velocity.linear, time));
            if (v.length(v.subtract(closest, position)) > 200) continue;
            result.add(.{ .point = closest, .eta = time, .radius = 256 });
        };
    }
    var sprays = world.queryAccess(data.World.mask(.{data.ThunderSpray}), 0, 0);
    defer sprays.deinit();
    while (sprays.next()) |view| for (view.entities()) |entity| {
        const prediction = try @import("thunder_spray.zig").forecast(world, entity, frame.now);
        if (engine.integer("developer") > 1) {
            const pose = (try world.get(entity, data.Transform)).position;
            var text: [256]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 {s}: t={d} event=spray id={d} pos={d:.0},{d:.0},{d:.0} forecast={d} eta={d:.2} impact={d:.0},{d:.0},{d:.0}\n", .{ frame.label, frame.now, try world.persistentId(entity), pose[0], pose[1], pose[2], @intFromBool(prediction != null), if (prediction) |value| value.eta else -1, if (prediction) |value| value.point[0] else 0, if (prediction) |value| value.point[1] else 0, if (prediction) |value| value.point[2] else 0 }));
        }
        const forecast = prediction orelse continue;
        if (forecast.eta < 0 or forecast.eta > 2.5) continue;
        const dx = forecast.point[0] - position[0];
        const dy = forecast.point[1] - position[1];
        if (dx * dx + dy * dy > 400 * 400 or @abs(forecast.point[2] - position[2]) > 160) continue;
        result.add(.{ .point = forecast.point, .eta = forecast.eta, .radius = 256 });
    };
    return result;
}
/// Walkable step (16 headings, three lengths) with the least expected splash
/// damage at the moment each threat lands, or null when standing still is as
/// good. A held fight dodges inside a wide tether around its position.
pub fn inside(arena: ?[2][2]f32, point: v.Vec3) bool {
    const box = arena orelse return true;
    return point[0] >= box[0][0] and point[0] <= box[1][0] and point[1] >= box[0][1] and point[1] <= box[1][1];
}
pub fn escape(frame: Frame, position: v.Vec3, velocity: v.Vec3, threats: []const Threat, leash: ?v.Vec3, arena: ?[2][2]f32, attempt: u32, avoid: *const fn (Frame, v.Vec3, v.Vec3) anyerror!bool) !?v.Vec3 {
    var best: ?v.Vec3 = null;
    var best_exposure = exposure(position, position, threats) - 0.05;
    const running = v.normalize(.{ velocity[0], velocity[1], 0 });
    for ([_]f32{ 80, 160, 288, 416 }) |reach| for (0..16) |slot| {
        // Attempt-dependent candidate order changes tie-breaks between retries.
        const index = (slot + attempt * 5) % 16;
        const angle = @as(f32, @floatFromInt(index)) * std.math.pi / 8;
        var point = v.add(position, .{ @cos(angle) * reach, @sin(angle) * reach, 0 });
        // Inside an arena, a step that would leave it ends at its boundary.
        if (arena) |box| {
            point[0] = std.math.clamp(point[0], box[0][0], box[1][0]);
            point[1] = std.math.clamp(point[1], box[0][1], box[1][1]);
        }
        const step = v.subtract(point, position);
        if (nav.horizontalDistance(step, @splat(0)) < 40) continue;
        // Shots are led at the current velocity: favour breaking the line.
        const turning: f32 = if (v.dot(running, v.normalize(step)) < 0.7) 0.08 else 0;
        const value = exposure(position, point, threats) - turning;
        if (value >= best_exposure) continue;
        if (leash) |anchor| if (@sqrt((point[0] - anchor[0]) * (point[0] - anchor[0]) + (point[1] - anchor[1]) * (point[1] - anchor[1])) > 320) continue;
        if (!inside(arena, point)) continue;
        if (!try walkable(frame, position, point) or try avoid(frame, position, step)) continue;
        best_exposure = value;
        best = step;
    };
    return best;
}
/// Shot by something the player cannot see to shoot back at: the nearest
/// walkable step (8 headings, two lengths) out of its line of fire, if any.
pub fn cover(frame: Frame, position: v.Vec3, shooter: v.Vec3) !?v.Vec3 {
    const collision = frame.collision;
    var best: ?v.Vec3 = null;
    var shortest: f32 = std.math.inf(f32);
    for ([_]f32{ 64, 128 }) |length| for (0..8) |heading| {
        const angle = @as(f32, @floatFromInt(heading)) * std.math.pi / 4;
        const step: v.Vec3 = .{ @cos(angle) * length, @sin(angle) * length, 0 };
        const spot = v.add(position, step);
        if (!try walkable(frame, position, spot)) continue;
        // Hidden when no line runs from the shooter to the head or the waist.
        var seen = false;
        for ([_]f32{ 24, 0 }) |height| {
            const line = try collision.trace(.{ .start = shooter, .end = v.add(spot, .{ 0, 0, height }), .mins = @splat(0), .maxs = @splat(0), .slot = frame.slot, .mask = c.MASK_SOLID });
            if (line.fraction == 1) seen = true;
        }
        if (seen or length >= shortest) continue;
        shortest = length;
        best = step;
    };
    return best;
}
/// Sum of quadratic splash fractions at each impact, running toward
/// `destination` at about player speed from `position`.
fn exposure(position: v.Vec3, destination: v.Vec3, threats: []const Threat) f32 {
    const distance = @max(1, @sqrt((destination[0] - position[0]) * (destination[0] - position[0]) + (destination[1] - position[1]) * (destination[1] - position[1])));
    var total: f32 = 0;
    for (threats) |threat| {
        const fraction = @min(1, @max(0, threat.eta - 0.1) * 280 / distance);
        const x = position[0] + (destination[0] - position[0]) * fraction - threat.point[0];
        const y = position[1] + (destination[1] - position[1]) * fraction - threat.point[1];
        total += @max(0, 1 - (x * x + y * y) / (threat.radius * threat.radius));
    }
    return total;
}
/// A step is walkable when the hull can move there and every point along it
/// (each 48 units) has supported floor within a stair's drop, without slime,
/// lava, nitro or water: a sweep alone passes straight over gaps and ledges.
pub fn walkable(frame: Frame, from: v.Vec3, to: v.Vec3) !bool {
    if (!try supported(frame, from, to)) return false;
    const collision = frame.collision;
    const hull_mins = frame.hull.mins;
    const hull_maxs = frame.hull.maxs;
    const sweep = try collision.trace(.{ .start = from, .end = to, .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    // Knockback from the very blasts being dodged must not carry the player
    // over an edge: the destination needs floor all around it as well.
    for ([_]v.Vec3{ .{ 40, 0, 0 }, .{ -40, 0, 0 }, .{ 0, 40, 0 }, .{ 0, -40, 0 } }) |offset| {
        const around = v.add(sweep.end, offset);
        const floor = try collision.trace(.{ .start = around, .end = v.add(around, .{ 0, 0, -48 }), .mins = .{ -4, -4, hull_mins[2] }, .maxs = .{ 4, 4, 8 }, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (!floor.start_solid and floor.fraction == 1) return false;
    }
    return true;
}
/// Any step the motor takes off its route (sidestep, charge, unstick) keeps
/// floor under the player along the whole way and stays out of liquids.
pub fn supported(frame: Frame, from: v.Vec3, to: v.Vec3) !bool {
    return supportedUnder(frame, from, to, frame.hull.maxs[2]);
}
/// `supported` for a hull `head` high (a crouched player: a crawlway).
pub fn supportedUnder(frame: Frame, from: v.Vec3, to: v.Vec3, head: f32) !bool {
    const collision = frame.collision;
    const hull_mins = frame.hull.mins;
    const hull_maxs: v.Vec3 = .{ frame.hull.maxs[0], frame.hull.maxs[1], head };
    // Wading already, the step may stay in the same shallow water; harmful
    // liquids are never stepped into.
    var avoided: u32 = c.CONTENTS_LAVA | c.CONTENTS_SLIME | c.CONTENTS_DK3_NITRO | c.CONTENTS_WATER;
    if (try collision.contents(v.add(from, .{ 0, 0, hull_mins[2] + 1 }), frame.slot) & c.CONTENTS_WATER != 0) avoided &= ~@as(u32, c.CONTENTS_WATER);
    const sweep = try collision.trace(.{ .start = from, .end = to, .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
    if (sweep.start_solid or sweep.all_solid or sweep.fraction < 0.9) return false;
    const length = v.length(v.subtract(sweep.end, from));
    const samples: usize = @max(1, @as(usize, @intFromFloat(@ceil(length / 48))));
    for (1..samples + 1) |sample| {
        const point = v.add(from, v.scale(v.subtract(sweep.end, from), @as(f32, @floatFromInt(sample)) / @as(f32, @floatFromInt(samples))));
        const floor = try collision.trace(.{ .start = point, .end = v.add(point, .{ 0, 0, -36 }), .mins = hull_mins, .maxs = hull_maxs, .slot = frame.slot, .mask = c.MASK_PLAYERSOLID });
        if (floor.fraction == 1 or floor.normal[2] < 0.7) return false;
        if (try collision.contents(v.add(floor.end, .{ 0, 0, hull_mins[2] + 1 }), frame.slot) & avoided != 0) return false;
    }
    return true;
}
/// Sidestep across the enemy's line of fire, alternating sides, tethered to
/// the position the route chose to hold.
pub fn strafe(frame: Frame, position: v.Vec3, enemy: v.Vec3, anchor: v.Vec3, side: f32, tethered: bool, arena: ?[2][2]f32, avoid: *const fn (Frame, v.Vec3, v.Vec3) anyerror!bool) !?v.Vec3 {
    // Outside the arena, the first move is back into it.
    if (!inside(arena, position)) {
        const box = arena.?;
        const centre: v.Vec3 = .{ (box[0][0] + box[1][0]) / 2, (box[0][1] + box[1][1]) / 2, position[2] };
        return v.subtract(centre, position);
    }
    const away = v.subtract(position, anchor);
    const bearing = v.normalize(.{ enemy[0] - position[0], enemy[1] - position[1], 0 });
    // Inside a brawler's reach, back straight off (the tether gives way up
    // to twice its length): it hits far harder up close than from range
    // (a cryotech's freezing spray reaches about 250).
    const range = v.length(.{ enemy[0] - position[0], enemy[1] - position[1], 0 });
    if (range < 280 and v.length(.{ away[0], away[1], 0 }) < 224) {
        const back = v.scale(bearing, -96);
        if (inside(arena, v.add(position, back)) and try walkable(frame, position, v.add(position, back)) and !try avoid(frame, position, back)) return back;
    }
    if (tethered and v.length(.{ away[0], away[1], 0 }) > 112) return v.scale(.{ -away[0], -away[1], 0 }, 1);
    const step = v.scale(.{ -bearing[1] * side, bearing[0] * side, 0 }, 96);
    if (!inside(arena, v.add(position, step)) or !try walkable(frame, position, v.add(position, step)) or try avoid(frame, position, step)) return null;
    return step;
}

test "evasion minimises the summed splash at the moment each threat lands" {
    const threats = [_]Threat{ .{ .point = .{ 0, 0, 0 }, .eta = 1, .radius = 256 }, .{ .point = .{ 100, 0, 0 }, .eta = 1, .radius = 256 } };
    try std.testing.expect(exposure(.{ 0, 0, 0 }, .{ -288, 0, 0 }, &threats) < exposure(.{ 0, 0, 0 }, .{ 50, 0, 0 }, &threats));
    try std.testing.expectApproxEqAbs(@as(f32, 1 + 1 - 10000.0 / 65536.0), exposure(.{ 0, 0, 0 }, .{ 0, 0, 0 }, &threats), 0.001);
    // An impact far in the future can still be outrun; an imminent one cannot.
    const late = [_]Threat{.{ .point = .{ 0, 0, 0 }, .eta = 2, .radius = 256 }};
    const soon = [_]Threat{.{ .point = .{ 0, 0, 0 }, .eta = 0.2, .radius = 256 }};
    try std.testing.expect(exposure(.{ 0, 0, 0 }, .{ 288, 0, 0 }, &late) < exposure(.{ 0, 0, 0 }, .{ 288, 0, 0 }, &soon));
}
