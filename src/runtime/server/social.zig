// SPDX-License-Identifier: GPL-2.0-or-later
//! Player commands use bounded server messages; teams and scores remain authoritative.
const std = @import("std");
const data = @import("../domain/components.zig");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const Clients = @import("clients.zig").Clients;
pub const State = struct {
    chat_ready: [c.MAX_CLIENTS]i64 = @splat(0),
    score_ready: [c.MAX_CLIENTS]i64 = @splat(0),
    pub fn command(self: *State, world: *data.World, clients: *Clients, states: []const c.playerState_t, slot: u16, name: []const u8, now: i64) !bool {
        if (std.mem.eql(u8, name, "score")) {
            if (now < self.score_ready[slot]) return true;
            self.score_ready[slot] = now + 500;
            engine.send(slot, "dk3_scores_begin");
            for (clients.entities, 0..) |maybe, index| if (maybe) |entity| {
                const session = (try world.get(entity, data.Session)).*;
                var text: [256]u8 = undefined;
                engine.send(slot, try std.fmt.bufPrintZ(&text, "dk3_score {d} {d} {d} {d} {d} {d} {d} {d}", .{ index, session.score, session.deaths, session.captures, @intFromEnum(session.team), @intFromBool(session.ready), if (session.bot) @as(i32, 0) else std.math.clamp(states[index].ping, 0, 999), @divTrunc(@max(0, now - session.joined_ms), 60000) }));
            };
            engine.send(slot, "dk3_scores_end");
            return true;
        }
        const team = std.mem.eql(u8, name, "say_team");
        if (!team and !std.mem.eql(u8, name, "say")) return false;
        if (now < self.chat_ready[slot]) return true;
        self.chat_ready[slot] = now + 750;
        const entity = clients.entities[slot] orelse return true;
        const member = (try world.get(entity, data.Session)).*;
        var clean: [256]u8 = undefined;
        var length: usize = 0;
        const argc = engine.gateway.call(c.G_ARGC, .{});
        var arg: usize = 1;
        while (arg < argc and length < clean.len) : (arg += 1) {
            var raw: [256]u8 = undefined;
            if (length > 0) {
                clean[length] = ' ';
                length += 1;
            }
            for (engine.argv(@intCast(arg), &raw)) |byte| {
                if (length == clean.len) break;
                if (byte < 32 or byte == 127 or byte == '"' or byte == 92) continue;
                clean[length] = byte;
                length += 1;
            }
        }
        if (length == 0) return true;
        var info: [c.MAX_INFO_STRING]u8 = @splat(0);
        _ = engine.gateway.call(c.G_GET_CONFIGSTRING, .{ @as(isize, c.CS_PLAYERS + slot), &info, @as(isize, info.len) });
        const player_name = @import("../engine/info.zig").get(std.mem.sliceTo(&info, 0), "n") orelse "Player";
        var text: [512]u8 = undefined;
        const message = try std.fmt.bufPrintZ(&text, "{s} \"{s}{s}: {s}\"", .{ if (team) "tchat" else "chat", if (team) "(Team) " else "", player_name, clean[0..length] });
        for (clients.entities, 0..) |maybe, index| if (maybe) |other| {
            const recipient = (try world.get(other, data.Session)).*;
            if (team and recipient.team != member.team) continue;
            if (!recipient.bot) engine.send(@intCast(index), message);
        };
        return true;
    }
};
