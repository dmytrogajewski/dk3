// SPDX-License-Identifier: GPL-2.0-or-later
//! Explicit development-only target fixture; never used for authored actors.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const v = @import("../domain/vector.zig");
const c = abi.c;
pub fn command(name: []const u8, world: *data.World, slots: *Slots, projections: []abi.EntityProjection, player: ?ecs.Entity, table: *const @import("../domain/weapons.zig").Table, now: i64) !bool {
    if (std.mem.eql(u8, name, "dk3_runtime_beams")) {
        if (player) |owner| {
            const loadout = (try world.get(owner, data.Weapons)).*;
            var output: [96]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig beam owner: weapon={d} ammo={d}\n", .{ loadout.weapon, loadout.ammo[@intCast(loadout.weapon)] }));
        }
        for (slots.occupants) |occupant| if (occupant) |entity| {
            var output: [200]u8 = undefined;
            if (world.get(entity, data.Nova) catch null) |beam| engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig nova state: id={d} phase={s} remaining={d:.3} next={d} expires={d}\n", .{ try world.persistentId(entity), @tagName(beam.phase), beam.remaining_damage, beam.next_ms - now, beam.expires_ms - now }));
            if (world.get(entity, data.Flashlight) catch null) |light| engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig flashlight state: id={d} strength={d:.3} expires={d}\n", .{ try world.persistentId(entity), light.strength, light.expires_ms - now }));
            if (world.get(entity, data.Zeus) catch null) |chain| engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig zeus state: id={d} phase={s} targets={d} active={d} zaps={d} ready={d}\n", .{ try world.persistentId(entity), @tagName(chain.phase), chain.count, chain.active, chain.zaps, chain.ready_ms - now }));
            if (world.get(entity, data.Nightmare) catch null) |ritual| engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig nightmare state: id={d} phase={s} targets={d} cursor={d} victim={d} next={d}\n", .{ try world.persistentId(entity), @tagName(ritual.phase), ritual.count, ritual.cursor, ritual.victim orelse 0, ritual.next_ms - now }));
        };
        engine.print("dk3 zig beam states complete\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_area_weapons")) {
        var query = world.queryAccess(data.World.mask(.{data.Transform}), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities(), view.read(data.Transform)) |entity, pose| {
            var output: [300]u8 = undefined;
            if (world.get(entity, data.Charge) catch null) |charge| {
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig charge state: id={d} attached={d} health={d} next={d} remaining={d} detonate={d} parent={d} position={d:.2},{d:.2},{d:.2}\n", .{ try world.persistentId(entity), @intFromBool(charge.attached), (try world.get(entity, data.Health)).current, charge.next_ms - now, charge.expires_ms - now, if (charge.detonate_ms) |at| at - now else -1, if (world.get(entity, data.Attachment) catch null) |value| value.parent_id else 0, pose.position[0], pose.position[1], pose.position[2] }));
            }
            if (world.get(entity, data.Hammer) catch null) |hammer| {
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig hammer state: id={d} charge={d} next={d} quake_remaining={d}\n", .{ try world.persistentId(entity), hammer.charge_ms, hammer.next_ms - now, if (hammer.quake_until_ms) |at| at - now else 0 }));
            }
            if (world.get(entity, data.Shockwave) catch null) |wave| {
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig shockwave state: id={d} age={d} rings={d} next={d} inner={d:.2} outer={d:.2} position={d:.2},{d:.2},{d:.2}\n", .{ try world.persistentId(entity), now - wave.born_ms, wave.count, wave.next_ms - now, wave.rings[wave.count - 1].inner, wave.rings[wave.count - 1].outer, pose.position[0], pose.position[1], pose.position[2] }));
            }
        };
        engine.print("dk3 zig area weapon states complete\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_ailments")) {
        for (slots.occupants) |occupant| {
            const target = occupant orelse continue;
            const status = world.get(target, data.Ailments) catch continue;
            if (status.mask & 7 == 0) continue;
            var output: [240]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig ailment state: id={d} mask={d} freeze={d:.3} poison_remaining={d} poison_next={d}\n", .{ try world.persistentId(target), status.mask, status.freeze_level, if (status.poison) |value| value.until_ms - now else 0, if (status.poison) |value| value.next_ms - now else 0 }));
        }
        engine.print("dk3 zig ailment states complete\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_progression")) {
        const owner = player orelse return error.MissingPlayer;
        const state = (try world.get(owner, data.Character)).*;
        const loadout = (try world.get(owner, data.Weapons)).*;
        var output: [192]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig progression state: experience={d} sword={d} level={d} points={d}\n", .{ state.experience, loadout.dk3SwordExperience, state.level, state.points }));
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_projectiles")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const projectile = world.get(entity, data.Projectile) catch continue;
            const lifetime = world.get(entity, data.Lifetime) catch null;
            const velocity = (try world.get(entity, data.Velocity)).linear;
            const position = (try world.get(entity, data.Transform)).position;
            var output: [300]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig projectile state: id={d} weapon={d} stuck={d} resting={d} age={d} remaining={d} velocity={d:.2},{d:.2},{d:.2} position={d:.2},{d:.2},{d:.2}\n", .{ try world.persistentId(entity), projectile.weapon, @intFromBool(projectile.stuck), @intFromBool(projectile.resting), now - projectile.born_ms, if (lifetime) |value| value.expires_ms - now else 0, velocity[0], velocity[1], velocity[2], position[0], position[1], position[2] }));
            if (projectile.flight == .trident) {
                const tip = projectile.flight.trident;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig trident state: id={d} kind={s} leader={d} left={d} right={d} charged={d} next={d}\n", .{ try world.persistentId(entity), @tagName(tip.kind), tip.leader, tip.left, tip.right, @intFromBool(tip.charged), tip.next_ms }));
            }
            if (projectile.flight == .ballista) {
                const bolt = projectile.flight.ballista;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig ballista state: id={d} victim={d} releases={d} release={d} next={d}\n", .{ try world.persistentId(entity), bolt.victim orelse 0, bolt.releases, bolt.release_ms - (now - projectile.born_ms), bolt.next_ms }));
            }
            if (projectile.flight == .discus) {
                const disc = projectile.flight.discus;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig discus state: id={d} target={d} reflected={d} dropped={d} pickup={d} next={d}\n", .{ try world.persistentId(entity), disc.target orelse 0, @intFromBool(disc.reflected), @intFromBool(disc.dropped), @intFromBool(disc.pickup_only), disc.next_ms }));
            }
            if (projectile.flight == .sunflare) {
                const flame = projectile.flight.sunflare;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig sunflare state: id={d} phase={s} flames={d} floating={d} next={d}\n", .{ try world.persistentId(entity), @tagName(flame.phase), flame.flames, @intFromBool(flame.floating), flame.next_ms }));
            }
            if (projectile.flight == .stavros) {
                const meteor = projectile.flight.stavros;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig stavros state: id={d} fragment={d} scale={d:.3} next={d}\n", .{ try world.persistentId(entity), @intFromBool(meteor.fragment), meteor.scale[0], meteor.next_ms }));
            }
            if (projectile.flight == .wyndrax) {
                const wisp = projectile.flight.wyndrax;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig wyndrax state: id={d} phase={s} enemy={d} targets={d},{d},{d},{d} alpha={d:.3}\n", .{ try world.persistentId(entity), @tagName(wisp.phase), wisp.enemy orelse 0, wisp.targets[0], wisp.targets[1], wisp.targets[2], wisp.targets[3], wisp.alpha }));
            }
            if (projectile.flight == .metamaser) {
                const cube = projectile.flight.metamaser;
                engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig metamaser state: id={d} phase={s} health={d} charges={d} locks={d},{d},{d},{d} bursts={d} end={d}\n", .{ try world.persistentId(entity), @tagName(cube.phase), (try world.get(entity, data.Health)).current, cube.charges, cube.acquired[0].target, cube.acquired[1].target, cube.acquired[2].target, cube.acquired[3].target, cube.bursts, cube.end_ms - (now - projectile.born_ms) }));
            }
        }
        engine.print("dk3 zig projectile states complete\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_probe_health")) {
        var target_argument: [24]u8 = undefined;
        const target_text = engine.argv(2, &target_argument);
        const owner = if (target_text.len == 0) player orelse return error.MissingPlayer else world.find(try std.fmt.parseInt(u32, target_text, 10)) orelse return error.MissingTarget;
        var argument: [16]u8 = undefined;
        const value = try std.fmt.parseInt(i32, engine.argv(1, &argument), 10);
        if (value < 1 or value > 10000) return error.InvalidProbeHealth;
        (try world.get(owner, data.Health)).current = value;
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_shot_lanes")) {
        const owner = player orelse return error.MissingPlayer;
        const slot = (try world.get(owner, data.Binding)).slot;
        const eye = v.add((try world.get(owner, data.Transform)).position, .{ 0, 0, 22 });
        var best: f32 = 0;
        var angles: v.Vec3 = @splat(0);
        for ([_]f32{ 0, -15, -30 }) |pitch| for (0..24) |index| {
            const candidate: v.Vec3 = .{ pitch, @as(f32, @floatFromInt(index)) * 15, 0 };
            const hit = try engine.collisionService().trace(.{ .start = eye, .end = v.add(eye, v.scale(v.basis(candidate).forward, 2048)), .mins = @splat(0), .maxs = @splat(0), .slot = slot, .mask = c.MASK_SHOT });
            if (!hit.start_solid and hit.fraction * 2048 > best) {
                best = hit.fraction * 2048;
                angles = candidate;
            }
        };
        var output: [120]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig shot lane: yaw={d:.1} pitch={d:.1} clearance={d:.1}\n", .{ angles[1], angles[0], best }));
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_face_target")) {
        const owner = player orelse return error.MissingPlayer;
        var argument: [32]u8 = undefined;
        const id = try std.fmt.parseInt(u32, engine.argv(1, &argument), 10);
        const target = world.find(id) orelse return error.MissingTarget;
        const owner_slot = (try world.get(owner, data.Binding)).slot;
        const target_slot = (try world.get(target, data.Binding)).slot;
        const brush = projections[target_slot].shared.bmodel != 0;
        const target_position = if (brush) v.scale(v.add(projections[target_slot].shared.absmin, projections[target_slot].shared.absmax), 0.5) else (try world.get(target, data.Transform)).position;
        const target_body = (try world.get(target, data.Body)).*;
        var radius_argument: [32]u8 = undefined;
        const radius_text = engine.argv(2, &radius_argument);
        const first_radius = if (radius_text.len == 0) 96 else try std.fmt.parseFloat(f32, radius_text);
        if (!std.math.isFinite(first_radius) or first_radius < 32 or first_radius > 256) return error.InvalidTargetDistance;
        var minimum_argument: [32]u8 = undefined;
        const minimum_text = engine.argv(3, &minimum_argument);
        const minimum_radius = if (minimum_text.len == 0) 0 else try std.fmt.parseFloat(f32, minimum_text);
        if (!std.math.isFinite(minimum_radius) or minimum_radius < 0 or minimum_radius > 256) return error.InvalidTargetDistance;
        var reports: usize = 0;
        const heights: []const f32 = if (brush) &.{ 56, 0, -64, -128, -192 } else &.{target_body.mins[2] + 56};
        for (heights) |height| for ([_]f32{ first_radius, 64, 160, 256 }) |radius| for (0..8) |direction| {
            if (radius < minimum_radius) continue;
            const angle = @as(f32, @floatFromInt(direction)) * (std.math.pi / 4.0);
            const candidate = v.add(target_position, .{ @cos(angle) * radius, @sin(angle) * radius, height });
            const floor = try engine.collisionService().trace(.{ .start = candidate, .end = v.add(candidate, .{ 0, 0, -96 }), .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 }, .slot = owner_slot, .mask = c.MASK_PLAYERSOLID });
            if (floor.start_solid or floor.all_solid or floor.fraction == 1 or floor.normal[2] < 0.7) continue;
            const eye = v.add(floor.end, .{ 0, 0, 22 });
            const aim = try engine.collisionService().trace(.{ .start = eye, .end = v.add(target_position, .{ 0, 0, 8 }), .mins = @splat(0), .maxs = @splat(0), .slot = owner_slot, .mask = c.MASK_SHOT });
            if (aim.fraction < 1 and aim.entity != target_slot) {
                if (brush and reports < 24) {
                    reports += 1;
                    var output: [200]u8 = undefined;
                    engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig fixture blocked: at={d:.2},{d:.2},{d:.2} hit={d} fraction={d:.3} target_slot={d}\n", .{ floor.end[0], floor.end[1], floor.end[2], if (aim.entity < slots.occupants.len) (if (slots.occupants[aim.entity]) |blocker| try world.persistentId(blocker) else 0) else 0, aim.fraction, target_slot }));
                }
                continue;
            }
            (try world.get(owner, data.Transform)).position = floor.end;
            (try world.get(owner, data.Velocity)).linear = @splat(0);
            (try world.get(owner, data.Player)).ground_entity = floor.entity;
            var output: [180]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig combat: fixture player={d:.3},{d:.3},{d:.3} target={d}\n", .{ floor.end[0], floor.end[1], floor.end[2], id }));
            return true;
        };
        return error.NoTargetSpace;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_equip")) {
        const owner = player orelse return error.MissingPlayer;
        var buffer: [16]u8 = undefined;
        const id = try std.fmt.parseInt(u5, engine.argv(1, &buffer), 10);
        if (@import("weapon_catalog").find(id) == null) return error.UnknownWeapon;
        const loadout = try world.get(owner, data.Weapons);
        _ = loadout.acquire(table, id, table.entries[id].ammoMax);
        loadout.weapon = id;
        loadout.weaponTime = 0;
        loadout.weaponstate = 0;
        loadout.dk3GlockClip = 10;
        if (id == 7) loadout.gas_until_ms = (try @import("weapon_catalog").gas.extend(loadout.gas_until_ms, now, table.entries[id].lifetime)) orelse loadout.gas_until_ms;
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_target")) {
        const owner = player orelse return error.MissingPlayer;
        const pose = (try world.get(owner, data.Transform)).*;
        const height = (try world.get(owner, data.Player)).view_height;
        const start = @import("../domain/combat.zig").eye(pose.position, height);
        const binding = (try world.get(owner, data.Binding)).*;
        const hit = try engine.collisionService().trace(.{ .start = start, .end = v.add(start, v.scale(v.basis(pose.angles).forward, 120)), .mins = @splat(-12), .maxs = @splat(12), .slot = binding.slot, .mask = c.MASK_SHOT });
        if (hit.start_solid or hit.fraction < 0.5) return error.NoTargetSpace;
        const target = try world.create(null, .{ data.Transform{ .position = hit.end }, data.Health{}, data.Body{ .mins = @splat(-12), .maxs = @splat(12), .contents = c.CONTENTS_BODY }, data.MapObject{ .classname = "runtime_target" } });
        errdefer world.destroy(target) catch unreachable;
        const slot = try slots.acquire(target, null);
        errdefer slots.release(slot, target) catch unreachable;
        try world.put(target, data.Binding{ .slot = slot });
        const projection = &projections[slot];
        projection.* = std.mem.zeroes(abi.EntityProjection);
        projection.state.number = slot;
        projection.state.eType = c.ET_DK3_ITEM;
        projection.state.modelindex = try @import("resources.zig").model("models/e1/a_ion.dkm");
        projection.state.pos = @import("../engine/trajectory.zig").stationary(hit.end);
        projection.shared.currentOrigin = hit.end;
        projection.shared.mins = @splat(-12);
        projection.shared.maxs = @splat(12);
        projection.shared.contents = c.CONTENTS_BODY;
        projection.shared.ownerNum = c.ENTITYNUM_NONE;
        engine.link(projection);
        engine.print("dk3 zig combat: target fixture created\n");
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_clear_targets")) {
        const occupants = slots.occupants;
        for (occupants, 0..) |occupant, slot| {
            const entity = occupant orelse continue;
            const object = world.get(entity, data.MapObject) catch continue;
            if (!std.mem.eql(u8, object.classname, "runtime_target")) continue;
            engine.unlink(&projections[slot]);
            try slots.release(@intCast(slot), entity);
            try world.destroy(entity);
        }
        return true;
    }
    if (std.mem.eql(u8, name, "dk3_runtime_targets")) {
        for (slots.occupants) |occupant| {
            const entity = occupant orelse continue;
            const object = world.get(entity, data.MapObject) catch continue;
            if (!std.mem.eql(u8, object.classname, "runtime_target")) continue;
            var output: [128]u8 = undefined;
            engine.print(try std.fmt.bufPrintZ(&output, "dk3 zig combat: target={d} health={d}\n", .{ try world.persistentId(entity), (try world.get(entity, data.Health)).current }));
        }
        return true;
    }
    return false;
}
