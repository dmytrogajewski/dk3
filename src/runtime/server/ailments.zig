// SPDX-License-Identifier: GPL-2.0-or-later
//! Apply class-owned status requests only to living characters; dispatch timed damage.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const Effect = @import("weapon_catalog").affliction.Effect;
pub fn apply(world: *data.World, target: ecs.Entity, effect: Effect, source: u32, weapon: u5, now: i64) !void {
    if (effect == .none or (world.get(target, data.Actor) catch null) == null and (world.get(target, data.Player) catch null) == null) return;
    if ((try world.get(target, data.Health)).current <= 0) return;
    if ((world.get(target, data.Ailments) catch null) == null) try world.put(target, data.Ailments{});
    if ((try world.get(target, data.Ailments)).apply(effect, source, weapon, now) and engine.integer("developer") > 0) {
        var text: [128]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig status: target={d} effect={s} source={d} weapon={d}\n", .{ try world.persistentId(target), @tagName(effect), source, weapon }));
    }
}
pub fn step(world: *data.World, now: i64) !void {
    var query = world.queryAccess(data.World.mask(.{ data.Ailments, data.Health }), 0, 0);
    defer query.deinit();
    while (query.next()) |view| for (view.entities()) |entity| {
        var state = (try world.get(entity, data.Ailments)).*;
        if ((try world.get(entity, data.Health)).current <= 0) continue;
        while (state.next(now)) |tick| {
            const result = try @import("damage.zig").apply(world, entity, @intFromFloat(@ceil(tick.amount)), now, .{ .source = tick.source, .weapon = tick.weapon, .bypass_armor = tick.bypass_armor });
            if (result.blood > 0 and engine.integer("developer") > 0) {
                var text: [160]u8 = undefined;
                engine.print(try std.fmt.bufPrintZ(&text, "dk3 zig status tick: target={d} weapon={d} blood={d} killed={d}\n", .{ try world.persistentId(entity), tick.weapon, result.blood, @intFromBool(result.killed) }));
            }
            if (result.killed) {
                state = .{};
                break;
            }
        }
        try @import("psyclaw_warp.zig").step(world, entity, &state, now);
        (try world.get(entity, data.Ailments)).* = state;
    };
}
