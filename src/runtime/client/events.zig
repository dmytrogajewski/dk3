// SPDX-License-Identifier: GPL-2.0-or-later
const std = @import("std");
const engine = @import("../engine/client.zig");
const c = @import("../engine/abi.zig").c;
var seen: [c.MAX_GENTITIES]u32 = @splat(0);
var names: [c.MAX_SOUNDS][c.MAX_QPATH]u8 = @splat(@splat(0));
var sounds: [c.MAX_SOUNDS]c.sfxHandle_t = @splat(0);
pub fn reset() void {
    @import("impacts.zig").reset();
    for (0..c.MAX_GENTITIES) |slot| configure(@intCast(slot), null) catch {};
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
        sounds[i] = try engine.registerSound(name);
        @memcpy(names[i][0..name.len], name);
        names[i][name.len] = 0;
    }
    return sounds[i];
}
pub fn loop(game: *const c.gameState_t, entity: c.entityState_t, origin: [3]f32) !void {
    if (entity.loopSound == 0) return;
    try configure(entity.number, if (entity.generic1 == @import("../domain/audio.zig").parameter_tag) try parameters(entity) else null);
    const handle = try sound(game, entity.loopSound);
    if (handle != 0) _ = engine.gateway.call(c.CG_S_ADDLOOPINGSOUND, .{ @as(isize, entity.number), &origin, &entity.pos.trDelta, @as(isize, handle) });
}
pub fn consume(game: *const c.gameState_t, entities: []const c.entityState_t) !void {
    for (entities) |entity| {
        if (entity.eType == c.ET_EVENTS + c.EV_DK3_IMPACT) {
            try @import("impacts.zig").consume(entity);
            continue;
        }
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
        try configure(entity.otherEntityNum, if (entity.frame == @import("../domain/audio.zig").parameter_tag) try parameters(entity) else null);
        _ = engine.gateway.call(c.CG_S_STARTSOUND, .{ &entity.pos.trBase, @as(isize, entity.otherEntityNum), @as(isize, entity.generic1), @as(isize, handle) });
        if (engine.integer("developer") > 0) engine.print("dk3 zig: snapshot sound dispatched\n");
    }
}

fn parameters(entity: c.entityState_t) !@import("../domain/audio.zig").Parameters {
    const result: @import("../domain/audio.zig").Parameters = .{ .volume = entity.angles2[0], .minimum = entity.angles2[1], .maximum = entity.angles2[2], .nondirectional = entity.weapon != 0 };
    if (!result.valid() or (entity.weapon != 0 and entity.weapon != 1)) return error.InvalidSoundParameters;
    return result;
}
fn configure(subject: i32, value: ?@import("../domain/audio.zig").Parameters) !void {
    if (subject < 0 or subject >= c.MAX_GENTITIES) return error.InvalidSoundSubject;
    const params: @import("../domain/audio.zig").Parameters = value orelse .{ .volume = 1, .minimum = 0, .maximum = 0 };
    // Parameters remain attached to the emitter during spatialization. Resetting
    // immediately after StartSound would erase attenuation on the next mixer frame.
    _ = engine.gateway.call(c.CG_DK3_SOUND_PARAMS_V1, .{ @as(isize, subject), engine.floatArg(params.volume), engine.floatArg(params.minimum), engine.floatArg(params.maximum), @as(isize, @intFromBool(params.nondirectional)) });
}
fn argument(index: usize, buffer: []u8) []const u8 {
    @memset(buffer, 0);
    _ = engine.gateway.call(c.CG_ARGV, .{ @as(isize, @intCast(index)), buffer.ptr, @as(isize, @intCast(buffer.len)) });
    return std.mem.sliceTo(buffer, 0);
}
/// Reliable dialogue uses its normalized path, independent of configstring command order.
pub fn command() !void {
    var buffer: [c.MAX_QPATH]u8 = undefined;
    if (!std.mem.eql(u8, argument(0, &buffer), "dk3_sound")) return;
    if (engine.gateway.call(c.CG_ARGC, .{}) != 10) return error.InvalidSpeakerCommand;
    const handle = try engine.registerSound(argument(1, &buffer));
    const subject = try std.fmt.parseInt(i32, argument(2, &buffer), 10);
    var values: [6]f32 = undefined;
    for (&values, 3..) |*value, index| {
        value.* = try std.fmt.parseFloat(f32, argument(index, &buffer));
        if (!std.math.isFinite(value.*)) return error.InvalidSpeakerCommand;
    }
    const nondirectional = try std.fmt.parseInt(u1, argument(9, &buffer), 10);
    const params: @import("../domain/audio.zig").Parameters = .{ .volume = values[3], .minimum = values[4], .maximum = values[5], .nondirectional = nondirectional != 0 };
    if (!params.valid()) return error.InvalidSoundParameters;
    try configure(subject, params);
    const point: [3]f32 = values[0..3].*;
    if (handle != 0) _ = engine.gateway.call(c.CG_S_STARTSOUND, .{ &point, @as(isize, subject), @as(isize, c.CHAN_VOICE), @as(isize, handle) });
}
