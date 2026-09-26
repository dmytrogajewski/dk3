// SPDX-License-Identifier: GPL-2.0-or-later
//! Native UI ABI boundary; unimplemented product screens fail explicitly.
const std = @import("std");
const abi = @import("engine/abi.zig");
const c = abi.c;
var gateway: abi.Gateway = .{};
export fn dllEntry(callback: abi.Syscall) callconv(.c) void {
    gateway.bind(callback);
}
export fn vmMain(command: c_int, arg0: isize, arg1: isize, arg2: isize, arg3: isize, arg4: isize, arg5: isize, arg6: isize, arg7: isize, arg8: isize, arg9: isize, arg10: isize, arg11: isize) callconv(.c) isize {
    _ = .{ arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 };
    switch (command) {
        c.UI_GETAPIVERSION => return c.UI_API_VERSION,
        c.UI_INIT => {
            _ = gateway.call(c.UI_CVAR_REGISTER, .{ @as(?*c.vmCvar_t, null), @as([*:0]const u8, "dk3_runtime_build"), @as([*:0]const u8, @import("engine/player_state.zig").version), @as(isize, c.CVAR_USERINFO | c.CVAR_ROM) });
            _ = gateway.call(c.UI_CVAR_SET, .{ @as([*:0]const u8, "dk3_runtime_build"), @as([*:0]const u8, @import("engine/player_state.zig").version) });
            var value: [16]u8 = @splat(0);
            _ = gateway.call(c.UI_CVAR_VARIABLESTRINGBUFFER, .{ @as([*:0]const u8, "dk3_runtime_probe"), &value, @as(isize, value.len) });
            if (!std.mem.eql(u8, std.mem.sliceTo(&value, 0), "2")) _ = gateway.call(c.UI_ERROR, .{@as([*:0]const u8, "Zig replacement UI is not yet qualified; use the legacy runtime.")});
        },
        c.UI_SHUTDOWN => {},
        else => return 0,
    }
    return 0;
}
