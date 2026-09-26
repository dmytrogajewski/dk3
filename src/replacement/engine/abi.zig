// SPDX-License-Identifier: GPL-2.0-or-later
//! Public engine ABI only. No game/client private headers enter domain code.
const std = @import("std");
pub const c = @cImport({
    @cDefine("DK3_GAME", "1");
    @cInclude("q_shared.h");
    @cInclude("g_public.h");
    @cInclude("cg_public.h");
    @cInclude("ui_public.h");
    @cInclude("bg_public.h");
});
pub const Syscall = *const fn (isize, ...) callconv(.c) isize;
pub const Gateway = struct {
    callback: ?Syscall = null,
    owner: ?std.Thread.Id = null,
    pub fn bind(self: *Gateway, callback: Syscall) void {
        self.callback = callback;
        self.owner = std.Thread.getCurrentId();
    }
    pub fn call(self: *const Gateway, operation: c_int, args: anytype) isize {
        std.debug.assert(self.owner != null and self.owner.? == std.Thread.getCurrentId());
        return @call(.auto, self.callback.?, .{@as(isize, operation)} ++ args);
    }
};
pub const EntityProjection = extern struct { state: c.entityState_t, shared: c.entityShared_t };
comptime {
    if (@sizeOf(EntityProjection) != @sizeOf(c.sharedEntity_t) or @alignOf(EntityProjection) != @alignOf(c.sharedEntity_t) or
        @offsetOf(EntityProjection, "state") != @offsetOf(c.sharedEntity_t, "s") or
        @offsetOf(EntityProjection, "shared") != @offsetOf(c.sharedEntity_t, "r")) @compileError("engine entity projection ABI mismatch");
}
