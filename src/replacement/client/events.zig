// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var seen: [c.MAX_GENTITIES]u32 = @splat(0);
var names: [c.MAX_SOUNDS][c.MAX_QPATH]u8 = @splat(@splat(0));
var sounds: [c.MAX_SOUNDS]c.sfxHandle_t = @splat(0);
pub fn reset() void {
    @memset(&seen, 0);
    @memset(&sounds, 0);
    @memset(std.mem.asBytes(&names), 0);
}
fn sound(game: *const c.gameState_t, index: i32) !c.sfxHandle_t {
    if (index <= 0 or index >= c.MAX_SOUNDS) return error.InvalidSoundIndex;
    const i: usize = @intCast(index);
    const name = try engine.config(game, c.CS_SOUNDS + i);
    if (name.len == 0 or name.len >= c.MAX_QPATH) return error.InvalidSoundPath;
    if (!std.mem.eql(u8, name, std.mem.sliceTo(&names[i], 0))) {
        var buffer: [c.MAX_QPATH + 8]u8 = undefined;
        const path = try std.fmt.bufPrintZ(&buffer, "sounds/{s}", .{name});
        sounds[i] = @intCast(engine.gateway.call(c.CG_S_REGISTERSOUND, .{ path.ptr, @as(isize, 0) }));
        @memcpy(names[i][0..name.len], name);
        names[i][name.len] = 0;
    }
    return sounds[i];
}
pub fn consume(game: *const c.gameState_t, entities: []const c.entityState_t) !void {
    for (entities) |entity| {
        if (entity.eType != c.ET_EVENTS + c.EV_GENERAL_SOUND) continue;
        if (entity.number < 0 or entity.number >= seen.len or entity.otherEntityNum < 0 or entity.otherEntityNum >= c.MAX_GENTITIES or entity.generic1 < 0 or entity.generic1 > c.CHAN_ANNOUNCER) return error.InvalidSoundEvent;
        const slot: usize = @intCast(entity.number);
        const serial: u32 = @bitCast(entity.time2);
        if (serial == 0 or seen[slot] == serial) continue;
        seen[slot] = serial;
        const handle = try sound(game, entity.eventParm);
        if (handle == 0) {
            engine.print("dk3 zig: snapshot sound unavailable\n");
            continue;
        }
        _ = engine.gateway.call(c.CG_S_STARTSOUND, .{ &entity.pos.trBase, @as(isize, entity.otherEntityNum), @as(isize, entity.generic1), @as(isize, handle) });
        if (engine.integer("developer") > 0) engine.print("dk3 zig: snapshot sound dispatched\n");
    }
}
