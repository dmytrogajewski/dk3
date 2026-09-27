// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only input-driver acknowledgements, available without enabling mutation fixtures.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
pub fn report(world: *data.World, player: ?ecs.Entity, now: i64) !void {
    var argument: [24]u8 = undefined;
    const serial = try std.fmt.parseInt(u32, engine.argv(1, &argument), 10);
    const entity = player orelse {
        var pending: [96]u8 = undefined;
        engine.print(try std.fmt.bufPrintZ(&pending, "dk3 observe {d}: connecting=1\n", .{serial}));
        return;
    };
    const state = (try world.get(entity, data.Player)).*;
    const pose = (try world.get(entity, data.Transform)).*;
    const health = (try world.get(entity, data.Health)).*;
    const loadout = (try world.get(entity, data.Weapons)).*;
    var input: c.usercmd_t = undefined;
    engine.usercmd((try world.get(entity, data.Binding)).slot, &input);
    var map_buffer: [64]u8 = undefined;
    const map_name = @import("persistence.zig").mapName(&map_buffer);
    const controller = @import("cinematics.zig").findController(world);
    const cinematic = if (controller) |id| (try world.get(id, data.Cinematic)).* else null;
    var output: [768]u8 = undefined;
    engine.print(try std.fmt.bufPrintZ(&output, "dk3 observe {d}: now={d} map={s} skill={d} cinematic={d} shot={d} processed={d} cmd={d} input={d} forward={d} right={d} up={d} buttons={d} weapon={d} ready={d} ammo={d} event={d} fire={d} health={d} armor={d} mode={s} water={d} pos={d:.3},{d:.3},{d:.3} angles={d:.3},{d:.3},{d:.3}\n", .{
        serial, now, map_name, engine.integer("g_spSkill"), if (cinematic) |value| @as(i32, @intFromBool(value.active)) else 0, if (cinematic) |value| @as(i32, value.shot) else -1, @intFromBool(state.command_ms >= input.serverTime), state.command_ms, input.serverTime, input.forwardmove, input.rightmove, input.upmove, input.buttons, loadout.weapon, @intFromBool(loadout.weaponTime <= 0 and loadout.weaponstate == 0), loadout.ammo[@intCast(std.math.clamp(loadout.weapon, 0, 31))], loadout.event_sequence, loadout.last_fire_ms orelse -1, health.current, health.armor, @tagName(state.mode), state.water_level, pose.position[0], pose.position[1], pose.position[2], pose.angles[0], pose.angles[1], pose.angles[2],
    }));
}
