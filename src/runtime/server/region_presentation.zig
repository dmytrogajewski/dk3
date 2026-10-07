// SPDX-License-Identifier: GPL-2.0-or-later
//! Foreign views borrow transport slots only. Simulation, collision, save data
//! and authored identifiers stay in the owning map's ECS.
const std = @import("std");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const data = @import("../domain/components.zig");
const Context = @import("world_context.zig").Context;
const engine = @import("../engine/server.zig");
const access = @import("region_access.zig");
const v = @import("../domain/vector.zig");
const Alias = struct { world: u32, identity: u32, source_slot: u16 };
pub const State = struct {
    aliases: [c.MAX_GENTITIES]?Alias = @splat(null),
    pub fn clear(self: *State, context: *Context) void {
        for (&self.aliases, 0..) |*alias, index| if (alias.* != null) {
            engine.unlink(&context.projection[index]);
            context.projection[index].shared.svFlags = c.SVF_NOCLIENT;
            context.slots.relinquish(@intCast(index));
            alias.* = null;
        };
    }
    fn lookup(self: *const State, owner: u32, source_slot: i32) i32 {
        if (source_slot >= c.ENTITYNUM_WORLD) return source_slot;
        for (self.aliases, 0..) |maybe, index| if (maybe) |alias| {
            if (alias.world == owner and alias.source_slot == source_slot) return @intCast(index);
        };
        return c.ENTITYNUM_NONE;
    }
    fn references(self: *const State, out: *c.entityState_t) void {
        const owner: u32 = @bitCast(out.dk3World);
        const actors = @import("actor_catalog");
        const weapons = @import("weapon_catalog");
        // These fields also carry class-owned flags in other effects. Only the
        // publishers declaring an entity reference participate in slot mapping.
        if (out.eType == c.ET_EVENTS + c.EV_GENERAL_SOUND or out.eType == c.ET_DK3_EFFECT or
            (out.eType == c.ET_GENERAL and (out.generic1 == actors.gunners.render_tag or
                out.generic1 == @import("../domain/lightning.zig").render_tag or out.time2 == actors.medusa.gaze_tag)))
            out.otherEntityNum = self.lookup(owner, out.otherEntityNum);
        if (out.eType == c.ET_DK3_EFFECT and out.weapon == weapons.nightmare.id) out.otherEntityNum2 = self.lookup(owner, out.otherEntityNum2);
        if ((out.eType == c.ET_MISSILE and out.weapon == weapons.wyndrax.id) or
            (out.eType == c.ET_MISSILE and out.weapon == weapons.metamaser.id))
        {
            out.otherEntityNum = self.lookup(owner, out.otherEntityNum);
            out.otherEntityNum2 = self.lookup(owner, out.otherEntityNum2);
            for (out.origin2[0..2]) |*slot| slot.* = @floatFromInt(self.lookup(owner, @intFromFloat(slot.*)));
        }
        out.groundEntityNum = self.lookup(owner, out.groundEntityNum);
    }
    fn identitySlot(self: *const State, active: *Context, identity: u32) i32 {
        if (identity == 0) return c.ENTITYNUM_NONE;
        if (active.world.?.find(identity)) |entity| if (active.slots.find(entity)) |slot| return slot;
        for (self.aliases, 0..) |maybe, slot| if (maybe) |alias| if (alias.identity == identity) return @intCast(slot);
        return c.ENTITYNUM_NONE;
    }
    fn controllerReferences(self: *const State, active: *Context, out: *c.entityState_t, now: i64) void {
        const ref = access.find(&active.world.?, @bitCast(out.dk3Identity)) orelse return;
        if (ref.get(data.Actor) catch null) |actor| if (out.time2 == @import("actor_catalog").medusa.gaze_tag) {
            out.otherEntityNum = self.identitySlot(active, actor.medusa.target);
        };
        if (ref.get(data.ActorAttack) catch null) |attack| if (attack.attack == .gunner_burst) {
            out.otherEntityNum = self.identitySlot(active, attack.owner);
        };
        if (out.eType == c.ET_DK3_EFFECT) {
            // Only effect publishers that declare an owner slot participate.
            inline for (.{ data.Nova, data.Flashlight, data.Zeus, data.ZeusBolt, data.Nightmare, data.MetaRing, data.MetaLaser }) |T| if (ref.get(T) catch null) |action| {
                out.otherEntityNum = self.identitySlot(active, action.owner);
            };
            if (ref.get(data.Nightmare) catch null) |ritual| out.otherEntityNum2 = self.identitySlot(active, ritual.victim orelse 0);
        }
        if (ref.get(data.Projectile) catch null) |projectile| switch (projectile.flight) {
            .sunflare => if (out.eType == c.ET_DK3_EFFECT) {
                out.otherEntityNum = self.identitySlot(active, projectile.owner);
            },
            .wyndrax => {
                var targets: [4]i32 = undefined;
                for (projectile.flight.wyndrax.targets, &targets) |identity, *slot| slot.* = self.identitySlot(active, identity);
                targetSlots(out, targets);
            },
            .metamaser => |cube| {
                var targets: [4]i32 = @splat(c.ENTITYNUM_NONE);
                if (cube.phase == .tracking and now >= projectile.born_ms + cube.pause_ms) for (cube.acquired, &targets) |lock, *slot| {
                    slot.* = self.identitySlot(active, lock.target);
                };
                targetSlots(out, targets);
            },
            else => {},
        };
    }
    fn targetSlots(out: *c.entityState_t, targets: [4]i32) void {
        out.otherEntityNum = targets[0];
        out.otherEntityNum2 = targets[1];
        out.origin2[0] = @floatFromInt(targets[2]);
        out.origin2[1] = @floatFromInt(targets[3]);
    }
    pub fn tag(active: *Context) !void {
        // Tag local states even outside campaign mode. Identity guards client
        // interpolation and transient caches when a transport number is reused.
        for (active.slots.occupants, 0..) |maybe, slot| if (maybe) |entity| {
            active.projection[slot].state.dk3World = @bitCast(active.network_id);
            active.projection[slot].state.dk3Identity = @bitCast(try active.world.?.persistentId(entity));
            const out = &active.projection[slot].state;
            out.dk3ParentIdentity = if (active.world.?.get(entity, data.Attachment) catch null) |parent| @bitCast(parent.parent_id) else 0;
            if (out.dk3ParentIdentity == 0) if (active.world.?.get(entity, data.ItemMotion) catch null) |motion| if (motion.ground) |ground| if (ground < c.ENTITYNUM_WORLD) if (active.slots.occupants[ground]) |parent| {
                out.dk3ParentIdentity = @bitCast(try active.world.?.persistentId(parent));
            };
            if (active.world.?.get(entity, data.Hurt) catch null) |hurt| {
                out.dk3BodyImpulse = hurt.impulse;
                out.dk3BodyImpulsePoint = hurt.impulse_point;
                out.dk3BodyImpulseSerial = @bitCast(hurt.impulse_serial);
                out.dk3BodyFlags = @intFromBool(hurt.feedback.gibbed);
                if (active.world.?.get(entity, data.Actor) catch null) |actor| if (actor.gibbed) {
                    out.dk3BodyFlags = 1;
                };
            }
        };
    }
    pub fn publish(self: *State, active: *Context, now: i64) !void {
        try tag(active);
        // Primary snapshots use the same definition barrier as foreign views.
        // Keep this transport flag separate from publisher-owned visibility.
        for (active.slots.occupants, 0..) |maybe, slot| if (maybe != null) {
            const projection = &active.projection[slot];
            projection.shared.svFlags &= ~@as(i32, c.SVF_DK3_CONFIG_PENDING);
            if (!active.configuration.available(projection.state)) projection.shared.svFlags |= c.SVF_DK3_CONFIG_PENDING;
        };
        const region = access.region orelse return;
        const map = region.manifest.find(std.mem.sliceTo(&active.map_name, 0)) orelse return;
        const hero = active.clients.entities[0] orelse return;
        var eye = (try active.world.?.get(hero, data.Transform)).position;
        eye[2] += (try active.world.?.get(hero, data.Player)).view_height;
        const Candidate = struct { context: *Context, slot: u16, identity: u32 };
        var candidates: [c.MAX_GENTITIES]Candidate = undefined;
        var count: usize = 0;
        for (region.manifest.edges[0..region.manifest.edge_count]) |edge| {
            if (edge.kind != .identity or edge.source != map) continue;
            const destination = access.byMap(edge.destination) orelse continue;
            const exit = active.world.?.find((active.world.?.id_first & 0xff000000) | @as(u32, edge.exit)) orelse return error.SeamExitMissing;
            const body = try active.world.?.get(exit, data.Body);
            const origin = (try active.world.?.get(exit, data.Transform)).position;
            const aperture: @import("../domain/world_aperture.zig").Aperture = .{ .source = active.network_id, .destination = destination.network_id, .axis = edge.axis, .direction = edge.direction, .mins = v.add(origin, body.mins), .maxs = v.add(origin, body.maxs) };
            var visible = false;
            var entry = aperture.center();
            for ([1]v.Vec3{aperture.center()} ++ aperture.vertices()) |point| {
                // Sample inside the authored face, avoiding coplanar boundary
                // ambiguity; this never changes collision or the opening size.
                var inside = v.add(v.scale(point, 0.99), v.scale(aperture.center(), 0.01));
                inside[edge.axis] += @as(f32, @floatFromInt(edge.direction));
                if (!engine.inPvs(eye, point)) continue;
                const hit = try @import("region_collision.zig").trace(.{ .start = eye, .end = inside, .mins = @splat(0), .maxs = @splat(0), .slot = 0, .mask = c.MASK_SOLID });
                if (hit.world != @intFromEnum(destination.handle.?) or hit.all_solid) continue;
                visible = true;
                entry = inside;
                break;
            }
            if (!visible) continue;
            try destination.expose(now);
            const scope = try destination.select();
            defer scope.deinit();
            for (destination.slots.occupants, 0..) |maybe, slot| if (maybe) |entity| {
                const projection = &destination.projection[slot];
                if (projection.shared.linked == 0 or projection.shared.svFlags & c.SVF_NOCLIENT != 0) continue;
                if (!destination.configuration.available(projection.state)) continue;
                const position = projection.shared.currentOrigin;
                if (projection.shared.svFlags & c.SVF_BROADCAST == 0 and !engine.inPvs(entry, position) and !engine.inPhs(entry, position)) continue;
                const identity = try destination.world.?.persistentId(entity);
                var duplicate = false;
                for (candidates[0..count]) |candidate| if (candidate.identity == identity) {
                    duplicate = true;
                    break;
                };
                if (duplicate) continue;
                if (count == candidates.len) return error.RegionPresentationCapacity;
                candidates[count] = .{ .context = destination, .slot = @intCast(slot), .identity = identity };
                count += 1;
            };
        }
        // Release disappeared projections first so turnover cannot exhaust the
        // pool merely because the previous frame occupied the final free slot.
        for (&self.aliases, 0..) |*maybe, index| if (maybe.*) |alias| {
            var retained = false;
            for (candidates[0..count]) |candidate| if (candidate.identity == alias.identity and candidate.context.network_id == alias.world) {
                retained = true;
                break;
            };
            if (retained) continue;
            engine.unlink(&active.projection[index]);
            active.projection[index].shared.svFlags = c.SVF_NOCLIENT;
            active.slots.relinquish(@intCast(index));
            maybe.* = null;
        };
        for (candidates[0..count]) |candidate| {
            var slot: ?u16 = null;
            for (self.aliases, 0..) |maybe, index| if (maybe) |alias| if (alias.identity == candidate.identity and alias.world == candidate.context.network_id) {
                slot = @intCast(index);
                break;
            };
            const index = slot orelse try active.slots.borrow();
            self.aliases[index] = .{ .world = candidate.context.network_id, .identity = candidate.identity, .source_slot = candidate.slot };
        }
        for (candidates[0..count]) |candidate| {
            const slot: usize = @intCast(self.lookup(candidate.context.network_id, candidate.slot));
            const output = &active.projection[slot];
            engine.unlink(output);
            output.* = candidate.context.projection[candidate.slot];
            output.state.number = @intCast(slot);
            output.state.dk3World = @bitCast(candidate.context.network_id);
            output.state.dk3Identity = @bitCast(candidate.identity);
            self.references(&output.state);
            // Foreign geometry participates through its own collision context,
            // never by cloning a solid into the source world's spatial tree.
            output.shared.linked = 0;
            output.shared.contents = 0;
            output.shared.ownerNum = c.ENTITYNUM_NONE;
            output.shared.svFlags = c.SVF_BROADCAST;
            engine.link(output);
            output.state.solid = candidate.context.projection[candidate.slot].state.solid;
        }
        for (active.slots.occupants, 0..) |maybe, slot| if (maybe != null or self.aliases[slot] != null) {
            self.controllerReferences(active, &active.projection[slot].state, now);
        };
    }
};

test "foreign projection references distinguish entity slots from class-owned flags" {
    var state: State = .{};
    state.aliases[100] = .{ .world = 514, .identity = 1001, .source_slot = 64 };
    state.aliases[101] = .{ .world = 515, .identity = 1002, .source_slot = 64 };
    var sound = std.mem.zeroes(c.entityState_t);
    sound.dk3World = 514;
    sound.eType = c.ET_EVENTS + c.EV_GENERAL_SOUND;
    sound.otherEntityNum = 64;
    state.references(&sound);
    try std.testing.expectEqual(@as(i32, 100), sound.otherEntityNum);
    var flags = std.mem.zeroes(c.entityState_t);
    flags.dk3World = 514;
    flags.eType = c.ET_GENERAL;
    flags.generic1 = @import("actor_catalog").knights.render_tag;
    flags.otherEntityNum = 64;
    state.references(&flags);
    try std.testing.expectEqual(@as(i32, 64), flags.otherEntityNum);
    try std.testing.expectEqual(@as(i32, c.ENTITYNUM_NONE), state.lookup(516, 64));
}

test "weapon reference slots preserve endpoints and resolve targets across owners" {
    const t = std.testing;
    const active = try t.allocator.create(Context);
    defer t.allocator.destroy(active);
    active.* = .{ .world = data.World.initNamespaced(t.allocator, 32, 0), .handle = @enumFromInt(513) };
    defer active.world.?.deinit();
    var state: State = .{};
    const local = try active.world.?.create(null, .{data.Health{ .current = 100 }});
    const local_slot = try active.slots.acquire(local, null);
    const local_id = try active.world.?.persistentId(local);
    state.aliases[100] = .{ .world = 514, .identity = 16777217, .source_slot = local_slot };
    const wisp = try active.world.?.create(null, .{data.Projectile{ .owner = local_id, .weapon = @import("weapon_catalog").wyndrax.id, .damage = 10, .born_ms = 0, .stepped_ms = 0, .flight = .{ .wyndrax = .{ .targets = .{ 16777217, local_id, 0, 0 } } } }});
    var out = std.mem.zeroes(c.entityState_t);
    out.eType = c.ET_MISSILE;
    out.dk3Identity = @bitCast(try active.world.?.persistentId(wisp));
    out.origin2[2] = 0.75;
    state.controllerReferences(active, &out, 1000);
    try t.expectEqual(@as(i32, 100), out.otherEntityNum);
    try t.expectEqual(@as(i32, local_slot), out.otherEntityNum2);
    try t.expectEqual(@as(f32, 0.75), out.origin2[2]);
    var cube: @import("weapon_catalog").metamaser.BallisticState = .{ .phase = .tracking, .pause_ms = 2000 };
    cube.acquired[0].target = 16777217;
    (try active.world.?.get(wisp, data.Projectile)).flight = .{ .metamaser = cube };
    state.controllerReferences(active, &out, 1999);
    try t.expectEqual(@as(i32, c.ENTITYNUM_NONE), out.otherEntityNum);
    state.controllerReferences(active, &out, 2000);
    try t.expectEqual(@as(i32, 100), out.otherEntityNum);
    // A destruction laser carries a position, not the cube's four target slots.
    out.dk3World = 514;
    out.eType = c.ET_DK3_EFFECT;
    out.weapon = @import("weapon_catalog").metamaser.id;
    out.origin2 = .{ -1392, 640, 529 };
    state.references(&out);
    try t.expectEqual([3]f32{ -1392, 640, 529 }, out.origin2);
}
