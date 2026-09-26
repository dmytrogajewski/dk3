// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const rules = @import("../domain/damage.zig");
pub fn apply(world: *data.World, entity: ecs.Entity, amount: i32, now: i64, options: rules.Options) !rules.Result {
    if (world.get(entity, data.Destructible)) |state| {
        if (state.hidden or state.broken or !state.shootable) return .{};
    } else |_| {}
    const health = world.get(entity, data.Health) catch return .{};
    const character: ?data.Character = if (world.get(entity, data.Character)) |value| value.* else |_| null;
    const result = rules.apply(health, character, amount, now, options);
    if (result.blood > 0) if (world.get(entity, data.Hurt)) |receipt| {
        receipt.source = options.source;
        receipt.at_ms = now;
        receipt.revision +%= 1;
    } else |_| {};
    if (result.killed) {
        if (world.get(entity, data.Player)) |player| player.mode = .dead else |_| {}
        if (world.get(entity, data.Ailments)) |ailments| ailments.* = .{} else |_| {}
    }
    return result;
}
