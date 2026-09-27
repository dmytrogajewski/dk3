// SPDX-License-Identifier: GPL-2.0-or-later
//! Read-only input-driver acknowledgements, available without enabling mutation fixtures.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
pub fn match(world: *data.World, now: i64) !void {
    var text: [768]u8 = undefined;
    var participants = world.queryAccess(data.World.mask(.{ data.Session, data.Player, data.Health, data.Weapons, data.Binding, data.Transform, data.Character }), 0, 0);
    {
        defer participants.deinit();
        while (participants.next()) |view| for (view.entities()) |entity| {
            const session = (try world.get(entity, data.Session)).*;
            const player = (try world.get(entity, data.Player)).*;
            const weapons = (try world.get(entity, data.Weapons)).*;
            const character = (try world.get(entity, data.Character)).*;
            const position = (try world.get(entity, data.Transform)).position;
            const hurt = (try world.get(entity, data.Hurt)).*;
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 match player: slot={d} id={d} bot={d} team={s} health={d} mode={s} score={d} deaths={d} captures={d} weapon={d} inventory={d} ammo={d} fire={d} event={d} experience={d} level={d} hurt={d} source={d} hit_weapon={d} pos={d:.3},{d:.3},{d:.3}\n", .{
                (try world.get(entity, data.Binding)).slot, try world.persistentId(entity), @intFromBool(session.bot), @tagName(session.team), (try world.get(entity, data.Health)).current, @tagName(player.mode), session.score, session.deaths, session.captures, weapons.weapon, weapons.dk3Inventory, weapons.ammo[@intCast(std.math.clamp(weapons.weapon, 0, 31))], weapons.last_fire_ms orelse -1, weapons.event_sequence, character.experience, character.level, hurt.amount, hurt.source, hurt.weapon, position[0], position[1], position[2],
            }));
        };
    }
    var objectives = world.queryAccess(data.World.mask(.{data.Objective}), 0, 0);
    {
        defer objectives.deinit();
        while (objectives.next()) |view| for (view.entities(), view.read(data.Objective)) |entity, objective| {
            engine.print(try std.fmt.bufPrintZ(&text, "dk3 match objective: id={d} team={s} phase={s} carrier={d} deadline={d}\n", .{ try world.persistentId(entity), @tagName(objective.team), @tagName(objective.phase), objective.carrier orelse 0, objective.deadline orelse 0 }));
        };
    }
    engine.print(try std.fmt.bufPrintZ(&text, "dk3 match complete: now={d}\n", .{now}));
}
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
