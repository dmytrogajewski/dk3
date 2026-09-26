// SPDX-License-Identifier: GPL-2.0-or-later
const vector = @import("vector.zig");
pub const Trace = struct { fraction: f32, contents: u32 = 0, sky: bool = false, end: vector.Vec3, normal: vector.Vec3, start_solid: bool = false, all_solid: bool = false, entity: u16 = 2047, slick: bool = false, ladder: bool = false };
pub const Request = struct { start: vector.Vec3, end: vector.Vec3, mins: vector.Vec3, maxs: vector.Vec3, slot: u16, mask: u32 };
pub const Collision = struct {
    context: *anyopaque,
    trace_fn: *const fn (*anyopaque, Request) anyerror!Trace,
    contents_fn: ?*const fn (*anyopaque, vector.Vec3, u16) anyerror!u32 = null,
    pub fn contents(self: Collision, point: vector.Vec3, skip: u16) !u32 {
        return (self.contents_fn orelse return error.MissingPointContents)(self.context, point, skip);
    }
    pub fn trace(self: Collision, request: Request) !Trace {
        return self.trace_fn(self.context, request);
    }
};
