// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("components.zig");
pub const Trace = struct { fraction: f32, end: data.Vec3, normal: data.Vec3, start_solid: bool = false };
pub const Request = struct { start: data.Vec3, end: data.Vec3, mins: data.Vec3, maxs: data.Vec3, slot: u16, mask: u32 };
pub const Collision = struct {
    context: *anyopaque,
    trace_fn: *const fn (*anyopaque, Request) anyerror!Trace,
    pub fn trace(self: Collision, request: Request) !Trace {
        return self.trace_fn(self.context, request);
    }
};
