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
            ((out.eType == c.ET_MISSILE or out.eType == c.ET_DK3_EFFECT) and out.weapon == weapons.metamaser.id))
        {
            out.otherEntityNum = self.lookup(owner, out.otherEntityNum);
            out.otherEntityNum2 = self.lookup(owner, out.otherEntityNum2);
            for (out.origin2[0..2]) |*slot| slot.* = @floatFromInt(self.lookup(owner, @intFromFloat(slot.*)));
        }
        out.groundEntityNum = self.lookup(owner, out.groundEntityNum);
    }
    pub fn tag(active: *Context) !void {
        // Tag local states even outside campaign mode. Identity guards client
        // interpolation and transient caches when a transport number is reused.
        for (active.slots.occupants, 0..) |maybe, slot| if (maybe) |entity| {
            active.projection[slot].state.dk3World = @bitCast(active.network_id);
            active.projection[slot].state.dk3Identity = @bitCast(try active.world.?.persistentId(entity));
        };
    }
    pub fn publish(self: *State, active: *Context, now: i64) !void {
        try tag(active);
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
                if (projection.state.modelindex > 0 and destination.configuration.waiting(c.CS_MODELS + @as(usize, @intCast(projection.state.modelindex)))) continue;
                if (projection.state.loopSound > 0 and destination.configuration.waiting(c.CS_SOUNDS + @as(usize, @intCast(projection.state.loopSound)))) continue;
                if (projection.state.eType == c.ET_EVENTS + c.EV_GENERAL_SOUND and destination.configuration.waiting(c.CS_SOUNDS + @as(usize, @intCast(projection.state.eventParm)))) continue;
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
