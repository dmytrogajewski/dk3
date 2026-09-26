// SPDX-License-Identifier: GPL-2.0-or-later
//! Resolves copied fire intents after movement releases ECS component pointers.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("weapon_catalog");
const weapons = @import("../domain/weapons.zig");
const rules = @import("../domain/combat.zig");
const v = @import("../domain/vector.zig");
const c = abi.c;
const damage = @import("weapon_damage.zig");
fn trace(start: v.Vec3, end: v.Vec3, skip: u16, radius: f32, mask: u32) !@import("../domain/collision.zig").Trace {
    return engine.collisionService().trace(.{ .start = start, .end = end, .mins = @splat(-radius), .maxs = @splat(radius), .slot = skip, .mask = mask });
}
fn victim(slots: *const Slots, slot: u16) ?ecs.Entity {
    return if (slot < slots.occupants.len) slots.occupants[slot] else null;
}
pub fn fire(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, owner: ecs.Entity, shot: weapons.Fired, table: *const weapons.Table, now: i64) !void {
    const entry = catalog.find(shot.weapon) orelse return error.UnknownWeapon;
    const tuning = table.entries[shot.weapon];
    const owner_id = try world.persistentId(owner);
    const slot = (try world.get(owner, data.Binding)).slot;
    const eye = rules.eye(shot.position, shot.view_height);
    const forward = v.basis(shot.angles).forward;
    const combat_policy = catalog.combatFor(shot.weapon, shot.sequence);
    switch (combat_policy) {
        .pending => {
            engine.print("dk3 zig: weapon combat policy pending\n");
            return;
        },
        .hitscan => |policy| {
            const height = (if (shot.ducked) policy.crouching_height else policy.standing_height) orelse shot.view_height;
            const start = rules.eye(shot.position, height);
            const hit = try trace(start, v.add(start, v.scale(forward, tuning.range)), slot, 0, c.MASK_SHOT);
            if (hit.fraction < 1) if (victim(slots, hit.entity)) |target| {
                const amount = tuning.damage * (if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) policy.single_player_scale else 1);
                if (try damage.hurt(world, target, owner_id, shot.weapon, amount, now, false)) if (policy.inertial) try damage.shove(world, target, owner_id, forward, amount, now);
            };
            try @import("impacts.zig").contact(world, slots, projections, shot.weapon, hit, .{ .charged = hit.entity < c.ENTITYNUM_WORLD or v.length(v.subtract(hit.end, shot.position)) < 40 }, now);
        },
        .pellets => |policy| {
            const start = (try trace(eye, rules.muzzle(eye, shot.angles, tuning.muzzle), slot, 0, c.MASK_SHOT)).end;
            const aim = (try trace(eye, v.add(eye, v.scale(forward, if (policy.aim_reach) policy.range else 2000)), slot, 0, c.MASK_SHOT)).end;
            const direction = rules.aim(start, aim, forward);
            const perpendicular = v.cross(direction, .{ 0, 0, 1 });
            const right = if (v.length(perpendicular) > 0.001) v.normalize(perpendicular) else v.basis(shot.angles).right;
            const reach = if (policy.aim_reach) v.length(v.subtract(aim, start)) + 64 else policy.range;
            if ((world.get(owner, data.Random) catch null) == null) try world.put(owner, data.Random{ .state = owner_id ^ 0x91e10da5 });
            var random = (try world.get(owner, data.Random)).*;
            var hits: @import("../domain/pellets.zig").Hits = .{};
            var last: @import("../domain/collision.zig").Trace = undefined;
            for (0..policy.count) |_| {
                const x = random.next();
                const y = random.next();
                const spread = @import("../domain/pellets.zig").direction(direction, right, x, y, policy.spread);
                last = try trace(start, v.add(start, v.scale(spread, reach)), slot, 0, c.MASK_SHOT);
                if (last.fraction < 1) if (victim(slots, last.entity)) |target| {
                    if ((world.get(target, data.Health) catch null) != null) hits.add(try world.persistentId(target), policy.max_victims);
                };
            }
            (try world.get(owner, data.Random)).* = random;
            const blast_damage = tuning.damage * (if (engine.integer("g_gametype") == c.GT_SINGLE_PLAYER) policy.single_player_scale else 1);
            for (hits.ids[0..hits.used], 0..) |id, i| if (world.find(id)) |target| {
                const amount = hits.damage(i, blast_damage, policy.count);
                if (try damage.hurt(world, target, owner_id, shot.weapon, amount, now, false)) if (policy.inertial) try damage.shove(world, target, owner_id, direction, amount, now);
            };
            try @import("impacts.zig").contact(world, slots, projections, shot.weapon, last, .{}, now);
            if (engine.integer("developer") > 0) {
                var text: [128]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig pellets: weapon={d} pellets={d} victims={d}\n", .{ shot.weapon, policy.count, hits.used }));
            }
        },
        .melee => try @import("melee.zig").launch(world, owner, shot, table, now),
        .charge => try @import("c4.zig").launch(world, slots, projections, owner, shot, table, now),
        .trident => try @import("trident.zig").launch(world, slots, projections, owner, shot, table, now),
        .novabeam => try @import("novabeam.zig").launch(world, slots, projections, owner, shot, table, now),
        .flashlight => try @import("flashlight.zig").refresh(world, slots, projections, owner, now),
        .hammer => {
            try @import("hammer.zig").launch(world, owner, shot, table, now);
            return;
        },
        .projectile, .shockwave, .ballista, .discus, .sunflare => {
            if (entry.spec.projectile.action_delay_ms > 0) {
                const factor = catalog.transitions.attackFactor((try world.get(owner, data.Character)).attribute(.attack, now));
                try @import("weapon_launches.zig").queue(world, owner, shot, now, @intFromFloat(@as(f32, @floatFromInt(entry.spec.projectile.action_delay_ms)) / factor));
                if (entry.spec.projectile.sound_on_launch) return;
            } else try @import("projectiles.zig").launch(world, slots, projections, owner, shot, table, now);
        },
        .ion => |policy| {
            const start = (try trace(eye, rules.muzzle(eye, shot.angles, tuning.muzzle), slot, policy.radius, c.MASK_SHOT)).end;
            const aimed = (try trace(eye, v.add(eye, v.scale(forward, 2000)), slot, 0, c.MASK_SHOT)).end;
            const speed_factor = if (world.get(owner, data.Character)) |state| 1 + 0.3 * @as(f32, @floatFromInt(state.attribute(.attack, now))) else |_| 1;
            const model = try @import("resources.zig").model(entry.spec.visual.projectile_model);
            const bolt = try world.create(null, .{ data.Transform{ .position = start, .angles = shot.angles }, data.Velocity{ .linear = v.scale(rules.aim(start, aimed, forward), tuning.speed * speed_factor) }, data.Projectile{ .owner = owner_id, .weapon = shot.weapon, .damage = tuning.damage, .born_ms = now, .stepped_ms = now } });
            errdefer world.destroy(bolt) catch unreachable;
            const bolt_slot = try slots.acquire(bolt, null);
            errdefer slots.release(bolt_slot, bolt) catch unreachable;
            try world.put(bolt, data.Binding{ .slot = bolt_slot, .model = model });
            projections[bolt_slot] = std.mem.zeroes(abi.EntityProjection);
            try @import("projectiles.zig").publish(world, bolt, projections, now);
        },
    }
    if (combat_policy == .melee and (try catalog.meleePlan(shot.weapon, shot.sequence, (try world.get(owner, data.Weapons)).dk3SwordExperience)).sound_on_strike) return;
    if (catalog.fireSound(shot.weapon, shot.sequence, @truncate(@as(u64, @bitCast(shot.command_ms))))) |sound| try @import("events.zig").sound(world, slots, projections, sound, eye, slot, c.CHAN_WEAPON, now);
}
