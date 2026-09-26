// SPDX-License-Identifier: GPL-2.0-or-later
const data = @import("components.zig");
pub const Trace = struct { fraction: f32, contents: u32 = 0, sky: bool = false, end: data.Vec3, normal: data.Vec3, start_solid: bool = false, all_solid: bool = false, entity: u16 = 2047, slick: bool = false, ladder: bool = false };
pub const Request = struct { start: data.Vec3, end: data.Vec3, mins: data.Vec3, maxs: data.Vec3, slot: u16, mask: u32 };
pub const Collision = struct {
    context: *anyopaque,
    trace_fn: *const fn (*anyopaque, Request) anyerror!Trace,
    contents_fn: ?*const fn (*anyopaque, data.Vec3, u16) anyerror!u32 = null,
    pub fn contents(self: Collision, point: data.Vec3, skip: u16) !u32 {
        return (self.contents_fn orelse return error.MissingPointContents)(self.context, point, skip);
    }
    pub fn trace(self: Collision, request: Request) !Trace {
        return self.trace_fn(self.context, request);
    }
};
