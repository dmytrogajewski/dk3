// SPDX-License-Identifier: GPL-2.0-or-later
//! Measured liquid exposure, player landings and authored protection.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/environment.zig");
const abi = @import("../engine/abi.zig");
const c = abi.c;
const engine = @import("../engine/server.zig");
const v = @import("../domain/vector.zig");
const Slots = @import("../engine/slots.zig").Slots;
const catalog = @import("actor_catalog");
fn subject(world: *data.World, entity: ecs.Entity) !rules.Subject {
    if ((world.get(entity, data.Player) catch null) != null) return .player;
    const actor = (try world.get(entity, data.Actor)).*;
    const policy = catalog.entries[actor.definition];
    if (policy.kind == .companion) return .companion;
    if (policy.kind == .shark) return .aquatic_actor;
    return if (policy.nitro_immune) .robot else .land_actor;
}
pub fn measure(service: @import("../domain/collision.zig").Collision, position: v.Vec3, body: data.Body, view: f32, slot: u16) !rules.Exposure {
    const mask = c.MASK_WATER | c.CONTENTS_DK3_NITRO;
    const feet = try service.contents(v.add(position, .{ 0, 0, body.mins[2] + 1 }), slot);
    var result: rules.Exposure = .{};
    if (feet & mask == 0) return result;
    result.kind = if (feet & c.CONTENTS_DK3_NITRO != 0) .nitro else if (feet & c.CONTENTS_LAVA != 0) .lava else if (feet & c.CONTENTS_SLIME != 0) .slime else .water;
    result.level = 1;
    const middle = body.mins[2] + (view - body.mins[2]) * 0.5;
    if (try service.contents(v.add(position, .{ 0, 0, middle }), slot) & mask == 0) return result;
    result.level = 2;
    if (try service.contents(v.add(position, .{ 0, 0, view }), slot) & mask != 0) result.level = 3;
    return result;
}
fn waterWeapon(world: *data.World, entity: ecs.Entity) bool {
    const loadout = world.get(entity, data.Weapons) catch return false;
    if (loadout.weapon <= 0 or loadout.weapon >= 32) return false;
    const weapon = @import("weapon_catalog").find(@intCast(loadout.weapon)) orelse return false;
    return weapon.spec.protects_water;
}
fn voice(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, drowned: bool, now: i64) !void {
    const player = world.get(entity, data.Player) catch return;
    _ = player;
    const appearance = (try world.get(entity, data.Session)).appearance % 3;
    const name = if (appearance == 1) "mikiko" else if (appearance == 2) "superfly" else "hiro";
    const sample = if (!drowned) "breathe2.wav" else if (appearance == 1) "waterchoke1.wav" else if (appearance == 2) "waterchoke2.wav" else "waterdeath1.wav";
    var path: [64]u8 = undefined;
    try @import("events.zig").sound(world, slots, projections, try std.fmt.bufPrint(&path, "{s}/{s}", .{ name, sample }), (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, c.CHAN_VOICE, now);
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, episode: u8, now: i64) !void {
    var ids: [ecs.max_entities]ecs.Entity = undefined;
    var count: usize = 0;
    {
        var query = world.queryAccess(data.World.mask(.{ data.Transform, data.Body, data.Health, data.Binding }), 0, 0);
        defer query.deinit();
        while (query.next()) |view| for (view.entities()) |entity| if ((world.get(entity, data.Actor) catch null) != null or (world.get(entity, data.Player) catch null) != null) {
            ids[count] = entity;
            count += 1;
        };
    }
    const cinematic = @import("cinematics.zig").active(world);
    for (ids[0..count]) |entity| {
        const person = (world.get(entity, data.Player) catch null) != null;
        const who = try subject(world, entity);
        const body = (try world.get(entity, data.Body)).*;
        const player = world.get(entity, data.Player) catch null;
        const companion = world.get(entity, data.Companion) catch null;
        const view: f32 = if (player) |value| value.view_height else if (companion) |value| value.motor.view_height else @max(body.mins[2] + 2, body.maxs[2] - 4);
        var exposure = try measure(engine.collisionService(), (try world.get(entity, data.Transform)).position, body, view, (try world.get(entity, data.Binding)).slot);
        exposure.subject = who;
        exposure.active = !cinematic and (try world.get(entity, data.Health)).current > 0 and (world.get(entity, data.Performer) catch null) == null;
        if (player) |value| if (value.mode != .normal) { exposure.active = false; };
        var state = if (person) (try world.get(entity, data.Character)).liquid else (try world.get(entity, data.Actor)).liquid;
        const fresh = !state.initialized;
        if (fresh) state.initialize(now, who);
        const protected_weapon = person and waterWeapon(world, entity);
        if (person) {
            const character = try world.get(entity, data.Character);
            // Migrate earlier native timed suits only once, on first exposure update.
            if (fresh and character.environment_charge_ms == 0 and character.environment_until > now) character.environment_charge_ms = @min(40000, character.environment_until - now);
        }
        var choking = false;
        var surfaced = false;
        while (state.next_ms <= now) {
            const at = state.next_ms;
            state.next_ms += 100;
            exposure.cold_water = person and episode == 3;
            if (person) {
                const character = try world.get(entity, data.Character);
                exposure.protected_liquid = character.environment_charge_ms > 0;
                exposure.protected_air = exposure.protected_liquid or protected_weapon or character.invincible_until > at;
                const draining = exposure.active and (exposure.kind == .lava or exposure.kind == .slime or (exposure.level == 3 and !protected_weapon));
                if (draining) character.environment_charge_ms = @max(0, character.environment_charge_ms - 100);
                // Transport retains the existing deadline field; reserve pauses in air.
                character.environment_until = if (character.environment_charge_ms > 0) now + character.environment_charge_ms else 0;
            }
            const tick = state.sample(at, exposure);
            if (tick.freeze > 0) _ = (try world.get(entity, data.Ailments)).apply(.{ .freeze = tick.freeze }, try world.persistentId(entity), 0, at);
            if (tick.damage > 0) {
                const hit = try @import("damage.zig").apply(world, entity, tick.damage, at, .{ .source = try world.persistentId(entity), .bypass_armor = tick.bypass_armor, .environmental = exposure.kind != .nitro, .self_hazard = exposure.kind != .nitro });
                choking = choking or (tick.drowning and hit.blood > 0);
                if (hit.killed) exposure.active = false;
            }
            surfaced = surfaced or tick.surfaced;
        }
        if (person) {
            (try world.get(entity, data.Character)).liquid = state;
            (try world.get(entity, data.Ailments)).cold_water = exposure.active and episode == 3 and exposure.kind == .water and exposure.level > 1;
        } else (try world.get(entity, data.Actor)).liquid = state;
        if (choking or surfaced) try voice(world, slots, projections, entity, choking, now);
    }
}
pub fn land(world: *data.World, entity: ecs.Entity, speed: f32, now: i64) !void {
    if (engine.integer("g_gametype") != c.GT_SINGLE_PLAYER and engine.integer("dm_falling_damage") == 0) return;
    const character = (try world.get(entity, data.Character)).*;
    const damage = rules.fall(speed, character.attribute(.acro, now), character.boost_until[@intFromEnum(@import("../domain/character.zig").Attribute.acro)] > now);
    if (damage > 0) _ = try @import("damage.zig").apply(world, entity, damage, now, .{ .source = try world.persistentId(entity), .self_hazard = true });
}

test "exposure samples actual feet waist and head and keeps nitro distinct" {
    const t = std.testing;
    const Fixture = struct {
        surface: f32 = 50,
        kind: u32 = c.CONTENTS_WATER,
        fn contents(raw: *anyopaque, point: v.Vec3, _: u16) !u32 {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return if (point[2] < self.surface) self.kind else 0;
        }
        fn trace(_: *anyopaque, request: @import("../domain/collision.zig").Request) !@import("../domain/collision.zig").Trace {
            return .{ .fraction = 1, .end = request.end, .normal = @splat(0) };
        }
    };
    var fixture: Fixture = .{};
    const service: @import("../domain/collision.zig").Collision = .{ .context = &fixture, .trace_fn = Fixture.trace, .contents_fn = Fixture.contents };
    const body: data.Body = .{ .mins = .{ -15, -15, -24 }, .maxs = .{ 15, 15, 32 } };
    try t.expectEqual(@as(u2, 3), (try measure(service, .{ 0, 0, 24 }, body, 22, 0)).level);
    fixture.surface = 16;
    try t.expectEqual(@as(u2, 1), (try measure(service, .{ 0, 0, 24 }, body, 22, 0)).level);
    fixture.surface = 30;
    fixture.kind = c.CONTENTS_DK3_NITRO;
    const nitro = try measure(service, .{ 0, 0, 24 }, body, 22, 0);
    try t.expect(nitro.level == 2 and nitro.kind == .nitro);
    fixture.surface = 0;
    try t.expectEqual(@as(u2, 0), (try measure(service, .{ 0, 0, 24 }, body, 22, 0)).level);
}
