// SPDX-License-Identifier: GPL-2.0-or-later
//! Objective defense is scored before death releases the carried flag.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/multiplayer.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const v = @import("../domain/vector.zig");
const std = @import("std");
pub fn center(world: *data.World, entity: ecs.Entity) !v.Vec3 {
    const origin = (try world.get(entity, data.Transform)).position;
    const body = world.get(entity, data.Body) catch return origin;
    if (body.contents & c.CONTENTS_TRIGGER != 0 or (world.get(entity, data.Mover) catch null) != null) return v.add(origin, v.scale(v.add(body.mins, body.maxs), 0.5));
    return origin;
}
pub fn visible(world: *data.World, observer: ecs.Entity, target: ecs.Entity) !bool {
    var start = try center(world, observer);
    var end = try center(world, target);
    // The shared reference visibility contract offsets both ends by the
    // observer's view height and includes opaque liquids, but not actors.
    if (world.get(observer, data.Player) catch null) |player| {
        start[2] += player.view_height;
        end[2] += player.view_height;
    }
    const hit = try engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(0), .maxs = @splat(0), .slot = (try world.get(observer, data.Binding)).slot, .mask = c.MASK_OPAQUE });
    return !hit.start_solid and !hit.all_solid and (hit.fraction == 1 or hit.entity == (try world.get(target, data.Binding)).slot) and v.length(v.subtract(start, hit.end)) >= 1;
}
pub fn killed(world: *data.World, victim: ecs.Entity, attacker: ecs.Entity) !void {
    if (engine.integer("g_gametype") != c.GT_CTF or victim.index == attacker.index) return;
    const defender = (try world.get(attacker, data.Session)).team;
    const enemy = (try world.get(victim, data.Session)).team;
    if (defender == enemy or (defender != .red and defender != .blue) or (enemy != .red and enemy != .blue)) return;
    if ((world.get(attacker, data.Player) catch null) == null or (world.get(victim, data.Player) catch null) == null) return;
    const victim_id = try world.persistentId(victim);
    const attacker_id = try world.persistentId(attacker);
    var evidence: rules.Defense = .{};
    var closest: ?ecs.Entity = null;
    var distance: f32 = std.math.inf(f32);
    const origin = (try world.get(attacker, data.Transform)).position;
    var query = world.queryAccess(data.World.mask(.{data.Transform}), 0, 0);
    {
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| {
            if (world.get(entity, data.Objective) catch null) |objective| {
                if (objective.team == defender) {
                    evidence.enemy_carrier = objective.carrier == victim_id;
                    if (objective.carrier == null) evidence.flag = try visible(world, attacker, entity) and try visible(world, victim, entity);
                } else if (objective.team == enemy) if (objective.carrier) |id| if (id != attacker_id) if (world.find(id)) |carrier| {
                    evidence.escort = try visible(world, attacker, carrier);
                };
            }
            const object = world.get(entity, data.MapObject) catch continue;
            if (!std.mem.eql(u8, object.classname, "trigger_capture") or !rules.acceptsCapture(object.flags, defender, false)) continue;
            const length = v.length(v.subtract(try center(world, entity), origin));
            if (length < distance) {
                closest = entity;
                distance = length;
            }
        };
    }
    if (closest) |zone| evidence.base = try visible(world, attacker, zone) and try visible(world, victim, zone);
    (try world.get(attacker, data.Session)).score += evidence.score();
}
