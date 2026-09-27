// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/damage.zig");
pub fn apply(world: *data.World, entity: ecs.Entity, amount: i32, now: i64, options: rules.Options) !rules.Result {
    return applyResolved(world, try @import("wall_breakage.zig").recipient(world, entity, amount), amount, now, options);
}
fn applyResolved(world: *data.World, entity: ecs.Entity, amount: i32, now: i64, options: rules.Options) !rules.Result {
    if ((world.get(entity, data.Performer) catch null) != null) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .psyclaw and now <= actor.psyclaw.protected_until_ms) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .column and !@import("actor_catalog").column.acceptsWeapon(options.weapon == @import("weapon_catalog").hammer.id)) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .buboid and actor.buboid.invulnerable()) return .{};
    // C4 explosions schedule nearby charges explicitly; radius damage must not
    // collapse the staggered chain into simultaneous deaths.
    if ((world.get(entity, data.Charge) catch null) != null and options.weapon == @import("weapon_catalog").c4.id) return .{};
    if (world.get(entity, data.Destructible)) |state| {
        if (state.hidden or state.broken or !state.shootable) return .{};
    } else |_| {}
    if ((world.get(entity, data.Player) catch null) != null) if (world.get(entity, data.Body) catch null) |body| if (body.motion_owner) |owner_id| if (world.find(owner_id)) |owner| if (world.get(owner, data.Cinematic) catch null) |cinematic| if (cinematic.active) return .{};
    if (world.get(entity, data.Body) catch null) |body| if (body.motion_owner) |owner_id| if (world.find(owner_id)) |owner| if (world.get(owner, data.Exit) catch null) |exit| if (exit.ending_started != null) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .lycanthir and actor.lycanthir.phase != .living and options.weapon != @import("weapon_catalog").silverclaw.id) return .{};
    if (world.get(entity, data.ActorAttack) catch null) |attack| if (attack.attack == .npc_wisp and attack.attack.npc_wisp.fading) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .kage and actor.kage.invulnerable()) return .{};
    if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .nharre and actor.nharre.invulnerable()) return .{};
    if (world.get(entity, data.HealthTree) catch null) |tree| if (tree.drugbox != null) return .{};
    const health = world.get(entity, data.Health) catch return .{};
    const participant = world.get(entity, data.Session) catch null;
    if (participant) |session| {
        if (session.team == .spectator) return .{};
        if (options.self_hazard and options.source == try world.persistentId(entity) and !options.bypass_protection and @import("../engine/server.zig").integer("g_gametype") == @import("../engine/abi.zig").c.GT_DK3_DEATHTAG) {
            var objectives = world.queryAccess(data.World.mask(.{data.Objective}), 0, 0);
            defer objectives.deinit();
            while (objectives.next()) |view| for (view.read(data.Objective)) |objective| if (objective.phase == .carried and objective.carrier == options.source) return .{};
        }
        if (!options.bypass_protection) if (world.find(options.source)) |attacker| if (attacker.index != entity.index) {
            if (world.get(attacker, data.Session) catch null) |source| if (@import("../domain/multiplayer.zig").allied(session.*, source.*) and @import("../engine/server.zig").integer("g_friendlyFire") == 0) return .{};
        };
    }
    const character: ?data.Character = if (world.get(entity, data.Character)) |value| value.* else |_| null;
    var result = rules.apply(health, character, amount, now, options);
    if (result.blood > 0) if (world.get(entity, data.Actor) catch null) |actor| {
        const kind = @import("actor_catalog").entries[actor.definition].kind;
        if (kind == .kage and actor.kage.recharging()) {
            actor.kage.refund(&health.current, amount);
            result.killed = false;
        }
        if (kind == .ghost and !result.killed) if (world.find(options.source)) |source| if ((world.get(source, data.Player) catch null) != null) {
            health.current -= amount;
            result.blood += amount;
            result.killed = health.current <= 0;
        };
    };
    if (result.killed) if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .lycanthir and options.weapon != @import("weapon_catalog").silverclaw.id) {
        actor.lycanthir.collapse(now, @import("../engine/server.zig").integer("g_spSkill"));
        health.current = 1;
        result.killed = false;
    };
    if (result.blood > 0) if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .buboid) {
        const previous = actor.buboid.phase;
        result.killed = actor.buboid.damage(&health.current, options.source == try world.persistentId(entity) and amount >= 32000, now);
        if (actor.buboid.phase == .collapsed and previous != .collapsed) {
            actor.melee.begin(5, now);
            actor.reaction = null;
            actor.reaction_until_ms = null;
            actor.scripted_pose = null;
            actor.mode = .idle;
            actor.changed_ms = now;
            actor.think_ms = now;
            if (world.find(options.source)) |source| if ((world.get(source, data.Player) catch null) != null or (world.get(source, data.Companion) catch null) != null) {
                actor.threat = options.source;
                actor.ignore_player = false;
            };
        }
    };
    if (result.blood > 0) if (world.get(entity, data.Actor) catch null) |actor| if (@import("actor_catalog").entries[actor.definition].kind == .rockgat) {
        const extra = @import("actor_catalog").rockgat.painDamage(amount);
        health.current -= extra;
        result.blood += extra;
        result.killed = health.current <= 0;
    };
    if (result.blood > 0) if (world.get(entity, data.ActorAttack) catch null) |attack| if (attack.attack == .npc_wisp and options.source != attack.owner) {
        // The class pain callback deducts the incoming hit a second time.
        health.current -= amount;
        result.blood += amount;
        if (health.current <= 0) {
            @import("wyndrax_attacks.zig").fade(&attack.attack.npc_wisp, now);
            (try world.get(entity, data.Velocity)).linear = @splat(0);
        }
        result.killed = false; // The attack owns its fading/removal, not actor death.
    };
    if (result.blood > 0) if (world.get(entity, data.Hurt)) |receipt| {
        receipt.source = options.source;
        receipt.weapon = options.weapon;
        receipt.amount = result.blood;
        receipt.at_ms = now;
        receipt.revision +%= 1;
        if ((world.get(entity, data.Player) catch null) != null) receipt.feedback.hit(result.blood, now, options.suppress_flash);
    } else |_| {};
    if (result.killed) {
        if (participant) |session| {
            session.deaths += 1;
            session.respawn_ms = now + 1000;
            if (world.find(options.source)) |attacker| {
                if (world.get(attacker, data.Session) catch null) |source| {
                    try @import("ctf_scoring.zig").killed(world, entity, attacker);
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

test "Buboid recovery suppresses false kills and melt immunity leaves receipts unchanged" {
    const t = @import("std").testing;
    const catalog = @import("actor_catalog");
    var world = data.World.init(t.allocator, 2);
    defer world.deinit();
    const entity = try world.create(1, .{ data.Actor{ .definition = catalog.find("monster_buboid").? }, data.Health{ .current = 100, .maximum = 100 }, data.Hurt{} });
    const first = try apply(&world, entity, 150, 1000, .{ .source = 2 });
    try t.expect(!first.killed);
    try t.expectEqual(@as(i32, 1), (try world.get(entity, data.Health)).current);
    try t.expectEqual(@as(u32, 1), (try world.get(entity, data.Hurt)).revision);
    const actor = try world.get(entity, data.Actor);
    try t.expect(actor.buboid.phase == .collapsed);
    try t.expect(actor.melee.active and actor.melee.pose == 5);
    const second = try apply(&world, entity, 1, 1100, .{ .source = 2 });
    try t.expect(second.killed);
    try t.expect(actor.buboid.phase == .terminal);
    (try world.get(entity, data.Health)).current = 100;
    actor.buboid.phase = .melting;
    const revision = (try world.get(entity, data.Hurt)).revision;
    try t.expectEqual(@as(i32, 0), (try apply(&world, entity, 500, 1200, .{ .source = 2 })).blood);
    try t.expectEqual(revision, (try world.get(entity, data.Hurt)).revision);
    try t.expectEqual(@as(i32, 100), (try world.get(entity, data.Health)).current);
}

test "NPC Wisp pain repeats damage then disables damage during its owned fade" {
    const t = @import("std").testing;
    var world = data.World.init(t.allocator, 1);
    defer world.deinit();
    const entity = try world.create(10, .{ data.Velocity{}, data.Health{ .current = 10, .maximum = 10 }, data.Hurt{}, data.ActorAttack{ .owner = 1, .born_ms = 100, .stepped_ms = 100, .attack = .{ .npc_wisp = .{ .target = 2, .next_ms = 200, .personality = -0.5, .forward = .{ 1, 0, 0 }, .sprite_scale = 1.2 } } } });
    const hit = try apply(&world, entity, 5, 200, .{ .source = 2 });
    try t.expectEqual(@as(i32, 10), hit.blood);
    try t.expect(!hit.killed);
    const attack = try world.get(entity, data.ActorAttack);
    try t.expect(attack.attack.npc_wisp.fading);
    try t.expectEqual(@as(f32, -1), attack.attack.npc_wisp.personality);
    try t.expectEqual(@as(i64, 300), attack.attack.npc_wisp.next_ms);
    try t.expectEqual(@as(i32, 0), (try apply(&world, entity, 20, 210, .{ .source = 2 })).blood);
    try t.expectEqual(@as(u32, 1), (try world.get(entity, data.Hurt)).revision);
}

test "Kage recharge prevents lethal dispatch, smoke prevents receipts, other bosses still die" {
    const t = @import("std").testing;
    const catalog = @import("actor_catalog");
    var world = data.World.init(t.allocator, 3);
    defer world.deinit();
    var state = catalog.kage.initialize(1200, 2);
    state.phase = .charging;
    const boss = try world.create(1, .{ data.Actor{ .definition = catalog.find("monster_kage").?, .kage = state }, data.Health{ .current = 100, .maximum = 1200 }, data.Hurt{} });
    const other = try world.create(2, .{ data.Actor{ .definition = catalog.find("monster_mikiko").? }, data.Health{ .current = 100, .maximum = 100 }, data.Hurt{} });
    const result = try apply(&world, boss, 200, 100, .{ .source = 3 });
    try t.expect(!result.killed);
    try t.expectEqual(@as(i32, 500), (try world.get(boss, data.Health)).current);
    try t.expect((try world.get(boss, data.Actor)).kage.feedback);
    try t.expect((try apply(&world, other, 200, 100, .{ .source = 3 })).killed);
    const actor = try world.get(boss, data.Actor);
    actor.kage.phase = .smoke;
    const receipt = (try world.get(boss, data.Hurt)).*;
    try t.expectEqual(@as(i32, 0), (try apply(&world, boss, 1000, 200, .{ .source = 3 })).blood);
    try t.expectEqualDeep(receipt, (try world.get(boss, data.Hurt)).*);
    actor.kage.phase = .combat;
    try t.expect((try apply(&world, boss, 1000, 300, .{ .source = 3 })).killed);
}

test "Ghost pain doubles surviving player hits, not monster damage or already lethal hits" {
    const t = @import("std").testing;
    const catalog = @import("actor_catalog");
    var world = data.World.init(t.allocator, 3);
    defer world.deinit();
    _ = try world.create(1, .{data.Player{}});
    const ghost = try world.create(2, .{ data.Actor{ .definition = catalog.find("monster_ghost").? }, data.Health{ .current = 50, .maximum = 50 }, data.Hurt{} });
    const monster = try apply(&world, ghost, 10, 100, .{ .source = 3 });
    try t.expectEqual(@as(i32, 10), monster.blood);
    const player = try apply(&world, ghost, 20, 200, .{ .source = 1 });
    try t.expectEqual(@as(i32, 40), player.blood);
    try t.expect(player.killed);
    (try world.get(ghost, data.Health)).current = 10;
    try t.expectEqual(@as(i32, 10), (try apply(&world, ghost, 10, 300, .{ .source = 1 })).blood);
}

test "lethal wall hits select lower sections while ordinary damage and other groups stay local" {
    const t = @import("std").testing;
    var world = data.World.init(t.allocator, 8);
    defer world.deinit();
    const upper = try world.create(1, .{ data.Health{ .current = 10, .maximum = 10 }, data.Hurt{}, data.Random{ .state = 1 }, data.Destructible{ .wall_explode = .{} }, data.MapObject{ .classname = "func_wall_explode", .properties = &.{ .{ .key = "team", .value = "collapse" }, .{ .key = "indexnumber", .value = "2" } } } });
    const lower = try world.create(2, .{ data.Health{ .current = 20, .maximum = 20 }, data.Hurt{}, data.Random{ .state = 2 }, data.Destructible{ .wall_explode = .{} }, data.MapObject{ .classname = "func_wall_explode", .properties = &.{ .{ .key = "team", .value = "collapse" }, .{ .key = "indexnumber", .value = "1" } } } });
    const unrelated = try world.create(3, .{ data.Health{ .current = 20, .maximum = 20 }, data.Hurt{}, data.Destructible{ .wall_explode = .{} }, data.MapObject{ .classname = "func_wall_explode", .properties = &.{.{ .key = "team", .value = "other" }} } });
    _ = try apply(&world, upper, 3, 1000, .{ .source = 99 });
    try t.expectEqual(@as(i32, 7), (try world.get(upper, data.Health)).current);
    _ = try apply(&world, upper, 7, 1100, .{ .source = 99 });
    try t.expectEqual(@as(i32, 7), (try world.get(upper, data.Health)).current);
    try t.expectEqual(@as(i32, 13), (try world.get(lower, data.Health)).current);
    _ = try apply(&world, upper, 13, 1200, .{ .source = 99 });
    try t.expectEqual(@as(i32, 0), (try world.get(lower, data.Health)).current);
    try t.expectEqual(@as(u32, 99), (try world.get(lower, data.Hurt)).source);
    _ = try apply(&world, upper, 7, 1300, .{ .source = 99 });
    try t.expectEqual(@as(i32, 0), (try world.get(upper, data.Health)).current);
    try t.expectEqual(@as(i32, 20), (try world.get(unrelated, data.Health)).current);
}
