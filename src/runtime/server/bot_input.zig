// SPDX-License-Identifier: GPL-2.0-or-later
//! A pilot command as ordinary client input: the user command a bot client
//! submits (view relative to the server's delta angles) and the "use" it
//! presses. Shared by the co-op bot and the multiplayer bots.
const std = @import("std");
const engine = @import("../engine/server.zig");
const c = @import("../engine/abi.zig").c;
const pilot = @import("bot_pilot.zig");

pub fn submit(index: u16, command: pilot.Command, delta_angles: [3]i32, now: i64) void {
    var input = encode(command, delta_angles, now);
    _ = engine.gateway.call(c.BOTLIB_USER_COMMAND, .{ @as(isize, index), &input });
    if (command.use) _ = engine.gateway.call(c.BOTLIB_EA_COMMAND, .{ @as(isize, index), @as([*:0]const u8, "use") });
}
/// A client command carries its view relative to the server's delta angles.
pub fn encode(command: pilot.Command, delta_angles: [3]i32, now: i64) c.usercmd_t {
    var input = std.mem.zeroes(c.usercmd_t);
    input.serverTime = @intCast(now);
    for (command.angles, 0..) |angle, axis| input.angles[axis] = @as(i32, @intFromFloat(angle * 65536 / 360)) -% delta_angles[axis];
    input.forwardmove = command.forward;
    input.rightmove = command.right;
    input.upmove = command.up;
    input.weapon = command.weapon;
    if (command.attack) input.buttons |= c.BUTTON_ATTACK;
    if (command.any) input.buttons |= c.BUTTON_ANY;
    return input;
}

test "client commands carry view relative to delta angles and every pressed button" {
    const input = encode(.{ .angles = .{ 10, 90, 0 }, .forward = 127, .right = -64, .up = -127, .attack = true, .any = true, .weapon = 3 }, .{ 0, 16384, 0 }, 4000);
    try std.testing.expectEqual(@as(i32, 4000), input.serverTime);
    try std.testing.expectEqual(@as(i32, @intFromFloat(10.0 * 65536.0 / 360.0)), input.angles[0]);
    try std.testing.expectEqual(@as(i32, 0), input.angles[1]);
    try std.testing.expectEqual(@as(i8, 127), input.forwardmove);
    try std.testing.expectEqual(@as(i8, -64), input.rightmove);
    try std.testing.expectEqual(@as(u8, 3), input.weapon);
    try std.testing.expect(input.buttons & c.BUTTON_ATTACK != 0 and input.buttons & c.BUTTON_ANY != 0);
}
