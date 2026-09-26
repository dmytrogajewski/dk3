// SPDX-License-Identifier: GPL-2.0-or-later
//! Native client ABI boundary; no legacy client behavior is linked.
const abi = @import("engine/abi.zig");
const c = abi.c;
var gateway: abi.Gateway = .{};
export fn dllEntry(callback: abi.Syscall) callconv(.c) void {
    gateway.bind(callback);
}
export fn vmMain(command: c_int, arg0: isize, arg1: isize, arg2: isize, arg3: isize, arg4: isize, arg5: isize, arg6: isize, arg7: isize, arg8: isize, arg9: isize, arg10: isize, arg11: isize) callconv(.c) isize {
    _ = .{ arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 };
    switch (command) {
        c.CG_INIT => {
            _ = gateway.call(c.CG_ERROR, .{@as([*:0]const u8, "Zig replacement client gameplay is not yet qualified.")});
        },
        c.CG_SHUTDOWN => {},
        c.CG_CROSSHAIR_PLAYER, c.CG_LAST_ATTACKER => return -1,
        else => return 0,
    }
    return 0;
}
