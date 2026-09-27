// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/damage.zig");
pub fn apply(world: *data.World, entity: ecs.Entity, amount: i32, now: i64, options: rules.Options) !rules.Result {
    if ((world.get(entity, data.Performer) catch null) != null) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .psyclaw and now <= actor.psyclaw.protected_until_ms) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .column and !@import("actor_catalog").column.acceptsWeapon(options.weapon == @import("weapon_catalog").hammer.id)) return .{};
    // C4 explosions schedule nearby charges explicitly; radius damage must not
    // collapse the staggered chain into simultaneous deaths.
    if ((world.get(entity, data.Charge) catch null) != null and options.weapon == @import("weapon_catalog").c4.id) return .{};
    if (world.get(entity, data.Destructible)) |state| {
        if (state.hidden or state.broken or !state.shootable) return .{};
    } else |_| {}
    if ((world.get(entity, data.Player) catch null) != null) if (world.get(entity, data.Body) catch null) |body| if (body.motion_owner) |owner_id| if (world.find(owner_id)) |owner| if (world.get(owner, data.Cinematic) catch null) |cinematic| if (cinematic.active) return .{};
    if (world.get(entity, data.Body) catch null) |body| if (body.motion_owner) |owner_id| if (world.find(owner_id)) |owner| if (world.get(owner, data.Exit) catch null) |exit| if (exit.ending_started != null) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .lycanthir and actor.lycanthir.phase != .living and options.weapon != @import("weapon_catalog").silverclaw.id) return .{};
    const health = world.get(entity, data.Health) catch return .{};
    const participant = world.get(entity, data.Session) catch null;
    if (participant) |session| {
        if (session.team == .spectator) return .{};
        if (!options.bypass_protection) if (world.find(options.source)) |attacker| if (attacker.index != entity.index) {
            if (world.get(attacker, data.Session) catch null) |source| if (@import("../domain/multiplayer.zig").allied(session.*, source.*) and @import("../engine/server.zig").integer("g_friendlyFire") == 0) return .{};
        };
    }
    const character: ?data.Character = if (world.get(entity, data.Character)) |value| value.* else |_| null;
    var result = rules.apply(health, character, amount, now, options);
    if (result.killed) if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .lycanthir and options.weapon != @import("weapon_catalog").silverclaw.id) {
        actor.lycanthir.collapse(now, @import("../engine/server.zig").integer("g_spSkill"));
        health.current = 1;
        result.killed = false;
    };
    if (result.blood > 0) if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .rockgat) {
        const extra = @import("actor_catalog").rockgat.painDamage(amount);
        health.current -= extra;
        result.blood += extra;
        result.killed = health.current <= 0;
    };
    if (result.blood > 0) if (world.get(entity, data.Hurt)) |receipt| {
        receipt.source = options.source;
        receipt.weapon = options.weapon;
        receipt.amount = result.blood;
        receipt.at_ms = now;
        receipt.revision +%= 1;
    } else |_| {};
    if (result.killed) {
        if (participant) |session| {
            session.deaths += 1;
            session.respawn_ms = now + 1000;
            if (world.find(options.source)) |attacker| {
                if (world.get(attacker, data.Session) catch null) |source| {
                    source.score += if (attacker.index == entity.index or @import("../domain/multiplayer.zig").allied(session.*, source.*)) @as(i32, -1) else 1;
                } else session.score -= 1;
            } else session.score -= 1;
        }
        if (world.get(entity, data.Player)) |player| player.mode = .dead else |_| {}
        if (world.get(entity, data.Ailments)) |ailments| ailments.* = .{} else |_| {}
    }
    return result;
}

test "Rockgat pain deduction is class-scoped and dispatches the resulting death" {
    const t = @import("std").testing;
    const catalog = @import("actor_catalog");
    var world = data.World.init(t.allocator, 8);
    defer world.deinit();
    const gun = try world.create(1, .{ data.Actor{ .definition = catalog.find("monster_rockgat").? }, data.Health{ .current = 30, .maximum = 30 }, data.Hurt{} });
    const croc = try world.create(2, .{ data.Actor{ .definition = catalog.find("monster_crox").? }, data.Health{ .current = 30, .maximum = 30 }, data.Hurt{} });
    const person = try world.create(3, .{ data.Player{}, data.Health{ .current = 30, .maximum = 30 }, data.Hurt{} });
    try t.expect((try apply(&world, gun, 15, 100, .{ .source = 3 })).killed);
    try t.expectEqual(@as(i32, 0), (try world.get(gun, data.Health)).current);
    try t.expect(!(try apply(&world, croc, 15, 100, .{ .source = 3 })).killed);
    try t.expectEqual(@as(i32, 15), (try world.get(croc, data.Health)).current);
    try t.expect(!(try apply(&world, person, 15, 100, .{ .source = 2 })).killed);
    try t.expectEqual(@as(i32, 15), (try world.get(person, data.Health)).current);
}
