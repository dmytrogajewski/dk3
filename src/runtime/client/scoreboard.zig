// SPDX-License-Identifier: GPL-2.0-or-later
//! Transactional scoreboard messages and room state rendered from native snapshots.
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
const canvas = @import("../engine/canvas.zig");
const draw: canvas.Canvas(.client) = .{ .gateway = &engine.gateway };
const Row = struct { slot: u16, score: i32, deaths: i32, captures: i32, team: u8, ready: bool, ping: i32, minutes: i32 };
var rows: [c.MAX_CLIENTS]Row = undefined;
var pending: [c.MAX_CLIENTS]Row = undefined;
var count: usize = 0;
var pending_count: ?usize = null;
var visible = false;
var next_request: i64 = 0;
pub fn reset() void {
    count = 0;
    pending_count = null;
    visible = false;
    next_request = 0;
}
fn argument(index: usize, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, @intCast(index)), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
pub fn input(name: []const u8) bool {
    if (std.mem.eql(u8, name, "+scores")) {
        visible = true;
        next_request = 0;
        return true;
    }
    if (std.mem.eql(u8, name, "-scores")) {
        visible = false;
        return true;
    }
    return false;
}
pub fn command() void {
    var buffer: [64]u8 = undefined;
    const name = argument(0, &buffer);
    if (std.mem.eql(u8, name, "dk3_scores_begin")) {
        pending_count = 0;
        return;
    }
    if (std.mem.eql(u8, name, "dk3_scores_end")) {
        if (pending_count) |length| {
            @memcpy(rows[0..length], pending[0..length]);
            count = length;
        }
        pending_count = null;
        return;
    }
    if (!std.mem.eql(u8, name, "dk3_score")) return;
    const length = pending_count orelse return;
    if (length == pending.len) {
        pending_count = null;
        return;
    }
    var numbers: [8]i32 = undefined;
    for (&numbers, 1..) |*number, i| number.* = std.fmt.parseInt(i32, argument(i, &buffer), 10) catch {
        pending_count = null;
        return;
    };
    if (numbers[0] < 0 or numbers[0] >= c.MAX_CLIENTS or numbers[4] < 0 or numbers[4] > 3 or numbers[2] < 0 or numbers[3] < 0 or numbers[6] < 0 or numbers[7] < 0) {
        pending_count = null;
        return;
    }
    for (pending[0..length]) |row| if (row.slot == numbers[0]) {
        pending_count = null;
        return;
    };
    pending[length] = .{ .slot = @intCast(numbers[0]), .score = numbers[1], .deaths = numbers[2], .captures = numbers[3], .team = @intCast(numbers[4]), .ready = numbers[5] != 0, .ping = numbers[6], .minutes = numbers[7] };
    pending_count = length + 1;
}
pub fn render(font: canvas.Font, display: c.glconfig_t, game: *const c.gameState_t, ps: *const c.playerState_t, now: i64) !void {
    const server = try engine.config(game, c.CS_SERVERINFO);
    if (std.mem.eql(u8, engine.info(server, "g_gametype") orelse "2", "2")) return;
    const intermission = std.mem.eql(u8, try engine.config(game, c.CS_INTERMISSION), "1");
    const warmup = std.fmt.parseInt(i64, try engine.config(game, c.CS_WARMUP), 10) catch 0;
    const scale = @as(f32, @floatFromInt(display.vidHeight)) / 600;
    var text: [256]u8 = undefined;
    const left = (@as(f32, @floatFromInt(display.vidWidth)) - 600 * scale) * 0.5;
    if (warmup != 0) draw.text(font, left, 65 * scale, scale, if (warmup < 0) "Lobby: use ready when prepared" else try std.fmt.bufPrint(&text, "Match starts in {d}", .{@divTrunc(@max(0, warmup - now) + 999, 1000)}), canvas.white);
    if (!visible and !intermission and ps.stats[c.STAT_HEALTH] > 0) return;
    if (now >= next_request) {
        _ = engine.gateway.call(c.CG_SENDCLIENTCOMMAND, .{@as([*:0]const u8, "score")});
        next_request = now + 1000;
    }
    draw.rect(left - 12 * scale, 105 * scale, 624 * scale, 425 * scale, draw.shader("white"), .{ 0, 0, 0, 0.82 });
    draw.text(font, left, 115 * scale, scale, if (intermission) "Match complete" else "Scoreboard", canvas.white);
    draw.text(font, left, 146 * scale, scale * 0.65, "Player                       Score  Deaths  Caps  Ping", canvas.white);
    // Keep every player visible at the supported 32-slot room limit.
    const row_scale: f32 = if (count > 20) 0.48 else 0.7;
    const height: f32 = if (count > 20) 11 else 17;
    var ordered: [c.MAX_CLIENTS]Row = undefined;
    @memcpy(ordered[0..count], rows[0..count]);
    std.mem.sort(Row, ordered[0..count], {}, struct {
        fn less(_: void, a: Row, b: Row) bool {
            if ((a.team == 3) != (b.team == 3)) return a.team != 3;
            return a.score > b.score or (a.score == b.score and a.slot < b.slot);
        }
    }.less);
    for (ordered[0..count], 0..) |row, index| {
        const info = try engine.config(game, @as(usize, c.CS_PLAYERS) + row.slot);
        const name = engine.info(info, "n") orelse "Player";
        const y = (170 + @as(f32, @floatFromInt(index)) * height) * scale;
        const tint: canvas.Color = switch (row.team) {
            1 => .{ 1, 0.35, 0.3, 1 },
            2 => .{ 0.45, 0.65, 1, 1 },
            3 => .{ 0.65, 0.65, 0.65, 1 },
            else => canvas.white,
        };
        draw.text(font, left, y, scale * row_scale, try std.fmt.bufPrint(&text, "{d} {s}{s}", .{ row.slot, name[0..@min(24, name.len)], if (row.ready) " *" else "" }), tint);
        draw.text(font, left + 335 * scale, y, scale * row_scale, try std.fmt.bufPrint(&text, "{d}     {d}     {d}     {d}", .{ row.score, row.deaths, row.captures, row.ping }), tint);
    }
}
