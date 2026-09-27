// SPDX-License-Identifier: GPL-2.0-or-later
//! Shared generic pain contract. Classes supply their chance and heavy-hit limit.
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const Definition = @import("../domain/actors.zig").Definition;
pub fn generic(world: *data.World, entity: ecs.Entity, actor: *data.Actor, definition: Definition, amount: i32, chance: u8, limit: i32, now: i64) !bool {
    if (amount <= 0 or now <= actor.pain_ready_ms) return false;
    const random = try world.get(entity, data.Random);
    const first = @as(u8, @intFromFloat(random.next() * 99.9)) < chance;
    const second = @as(u8, @intFromFloat(random.next() * 99.9)) < chance;
    if (first or (second and amount >= limit)) {
        const hit = definition.pain[0] orelse return false;
        actor.reaction = hit;
        actor.reaction_started_ms = now;
        actor.reaction_until_ms = now + hit.duration();
        actor.pain_ready_ms = now + @divTrunc(@as(i64, hit.last - hit.first) * 1000, hit.fps);
        actor.melee.active = false;
        actor.mode = .idle;
        return true;
    }
    if (!second) return false;
    const sequence = if (actor.melee.active) definition.attacks[actor.melee.pose] else if (actor.mode == .chase) definition.run else definition.idle;
    actor.pain_ready_ms = now + @divTrunc(@as(i64, sequence.last - sequence.first) * 1000, sequence.fps);
    // Below the limit the wrapper leaves the sequence unchanged. The pain task
    // yields at its next tick because this is not a hit animation.
    actor.reaction_until_ms = now + 100;
    actor.mode = .idle;
    return true;
}
test "light damage can trigger the first pain roll before the heavy-hit limit" {
    const t = @import("std").testing;
    var world = data.World.init(t.allocator, 1);
    defer world.deinit();
    const entity = try world.create(1, .{data.Random{ .state = 0 }});
    var actor: data.Actor = .{ .definition = 0, .mode = .attack };
    actor.melee.begin(0, 100);
    var definition: Definition = .{};
    definition.pain[0] = .{ .first = 40, .last = 49, .fps = 10 };
    try t.expect(try generic(&world, entity, &actor, definition, 1, 25, 35, 1000));
    try t.expectEqual(@as(u16, 40), actor.reaction.?.first);
    try t.expect(!actor.melee.active);
    try t.expectEqual(@as(i64, 1900), actor.pain_ready_ms);
    // The lock suppresses both random draws, including on its final millisecond.
    const seed = (try world.get(entity, data.Random)).state;
    try t.expect(!try generic(&world, entity, &actor, definition, 100, 100, 35, 1900));
    try t.expectEqual(seed, (try world.get(entity, data.Random)).state);
}
test "the second light-hit roll retains the active attack and locks for that sequence" {
    const t = @import("std").testing;
    var world = data.World.init(t.allocator, 1);
    defer world.deinit();
    const entity = try world.create(1, .{data.Random{ .state = 8 }});
    var actor: data.Actor = .{ .definition = 0, .mode = .attack };
    actor.melee.begin(0, 100);
    actor.melee.struck = 1;
    var definition: Definition = .{};
    definition.attacks[0] = .{ .first = 20, .last = 39, .fps = 10 };
    definition.pain[0] = .{ .first = 40, .last = 49, .fps = 10 };
    try t.expect(try generic(&world, entity, &actor, definition, 1, 20, 35, 1000));
    try t.expectEqual(null, actor.reaction);
    try t.expect(actor.melee.active);
    try t.expectEqual(@as(u2, 1), actor.melee.struck);
    try t.expectEqual(@as(i64, 2900), actor.pain_ready_ms);
    try t.expectEqual(@as(?i64, 1100), actor.reaction_until_ms);
}
