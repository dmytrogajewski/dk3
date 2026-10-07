// SPDX-License-Identifier: GPL-2.0-or-later
//! Consume player injuries and deaths once, before respawn can replace the body.
const std = @import("std");
const data = @import("../domain/components.zig");
const ecs = @import("../ecs/world.zig");
const abi = @import("../engine/abi.zig");
const engine = @import("../engine/server.zig");
const Slots = @import("../engine/slots.zig").Slots;
const c = abi.c;
fn voice(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, entity: ecs.Entity, now: i64, name: []const u8, channel: u8) !void {
    try @import("events.zig").configuredSound(world, slots, projections, name, (try world.get(entity, data.Transform)).position, (try world.get(entity, data.Binding)).slot, channel, now, .{ .volume = 0.85 });
}
fn playerName(world: *data.World, entity: ecs.Entity, buffer: *[c.MAX_INFO_STRING]u8) ![]const u8 {
    const slot = (try world.get(entity, data.Binding)).slot;
    _ = engine.gateway.call(c.G_GET_CONFIGSTRING, .{ @as(isize, c.CS_PLAYERS) + slot, buffer, @as(isize, buffer.len) });
    return @import("../engine/info.zig").get(std.mem.sliceTo(buffer, 0), "n") orelse "Player";
}
fn obituary(world: *data.World, victim: ecs.Entity, hurt: data.Hurt) !void {
    var victim_info: [c.MAX_INFO_STRING]u8 = @splat(0);
    var attacker_info: [c.MAX_INFO_STRING]u8 = @splat(0);
    var command: [512]u8 = undefined;
    const victim_name = try playerName(world, victim, &victim_info);
    const attacker = world.find(hurt.source);
    const text = if (attacker != null and attacker.?.index != victim.index and (world.get(attacker.?, data.Session) catch null) != null)
        try std.fmt.bufPrintZ(&command, "chat \"{s} killed {s}{s}{s}.\"", .{ try playerName(world, attacker.?, &attacker_info), victim_name, if (hurt.weapon > 0) @as([]const u8, " with ") else "", if (@import("weapon_catalog").find(hurt.weapon)) |weapon| weapon.label else "" })
    else
        try std.fmt.bufPrintZ(&command, "chat \"{s} died.\"", .{victim_name});
    _ = engine.gateway.call(c.G_SEND_SERVER_COMMAND, .{ @as(isize, -1), text.ptr });
}
pub fn step(world: *data.World, slots: *Slots, projections: []abi.EntityProjection, episode: u8, table: *const @import("../domain/weapons.zig").Table, now: i64) !void {
    const players = slots.occupants[0..c.MAX_CLIENTS].*;
    for (players) |occupant| {
        const entity = occupant orelse continue;
        const health = (try world.get(entity, data.Health)).*;
        const hurt = (try world.get(entity, data.Hurt)).*;
        var feedback = hurt.feedback;
        const newly_dead = health.current <= 0 and !feedback.death_handled;
        if (health.current <= 0 and !feedback.gibbed) {
            try @import("player_corpses.zig").fragment(world, slots, projections, entity, now);
            feedback.gibbed = (try world.get(entity, data.Hurt)).feedback.gibbed;
        }
        if (!newly_dead and feedback.handled_revision == hurt.revision) continue;
        feedback.handled_revision = hurt.revision;
        const appearance = if (world.get(entity, data.Session) catch null) |session| @import("appearance_catalog").character(session.appearance) else 0;
        const name = ([_][]const u8{ "hiro", "mikiko", "superfly" })[appearance];
        const liquid = (try world.get(entity, data.Character)).liquid;
        var random: data.Random = .{ .state = (try world.persistentId(entity)) *% 1664525 +% hurt.revision *% 1013904223 };
        var buffer: [96]u8 = undefined;
        if (newly_dead) {
            feedback.death_handled = true;
            (try world.get(entity, data.Hurt)).feedback = feedback;
            if (@import("multiplayer.zig").enabled()) {
                try @import("progression.zig").playerKill(world, entity, hurt, episode, table);
                try obituary(world, entity, hurt);
            }
            try @import("items.zig").dropCurrent(world, slots, projections, entity, now, episode);
            try @import("multiplayer.zig").release(world, projections, entity, now);
            try @import("weapon_actions.zig").cancel(world, slots, projections, entity);
            (try world.get(entity, data.Weapons)).discardInventory();
            (try world.get(entity, data.Body)).contents = if (feedback.gibbed) 0 else c.CONTENTS_CORPSE;
            (try world.get(entity, data.Health)).armor = 0;
            (try world.get(entity, data.Health)).absorption = 0;
            (try world.get(entity, data.Character)).invisible_until = 0;
            const sample = if (liquid.level > 2) try std.fmt.bufPrint(&buffer, "hiro/waterland{d}.wav", .{@as(u8, 4) + @as(u8, @intFromFloat(random.next() * 2))}) else if (health.current < -40) try std.fmt.bufPrint(&buffer, "{s}/udeath.wav", .{name}) else try std.fmt.bufPrint(&buffer, "{s}/death{d}.wav", .{ name, @as(u8, 1) + @as(u8, @intFromFloat(random.next() * 4)) });
            try voice(world, slots, projections, entity, now, sample, if (liquid.level > 2) c.CHAN_AUTO else c.CHAN_BODY);
        } else if (health.current > 0 and hurt.amount > 0 and now >= (feedback.pain_ready_ms orelse 0)) {
            const self_hurt = hurt.source == try world.persistentId(entity);
            const hazard = self_hurt and (liquid.kind == .lava or liquid.kind == .slime);
            if (hazard) {
                if (now >= (feedback.hazard_voice_ms orelse 0)) {
                    feedback.hazard_voice_ms = now + if (liquid.kind == .lava) @as(i64, 3000) else 1500;
                    const number: u8 = if (liquid.kind == .lava) (if (appearance == 2) @as(u8, 7) else 8) else if (appearance == 1) 7 else 3;
                    try voice(world, slots, projections, entity, now, try std.fmt.bufPrint(&buffer, "{s}/death{d}.wav", .{ name, number }), c.CHAN_AUTO);
                }
            } else if (liquid.level < 3) {
                const count: f32 = if (appearance == 1) 8 else if (appearance == 2) 7 else 10;
                const number: u8 = 1 + @as(u8, @intFromFloat(random.next() * count));
                try voice(world, slots, projections, entity, now, try std.fmt.bufPrint(&buffer, "{s}/{s}{d}.wav", .{ name, if (hurt.amount > 35) @as([]const u8, "death") else "pain", number }), c.CHAN_BODY);
            }
            feedback.pain_ready_ms = now + 1000;
        }
        (try world.get(entity, data.Hurt)).feedback = feedback;
    }
}
