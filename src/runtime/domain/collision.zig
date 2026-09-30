// SPDX-License-Identifier: GPL-2.0-or-later
const vector = @import("vector.zig");
// A zero world denotes the caller's local collision service. Region queries
// return a checked engine world handle alongside its local entity slot.
pub const Trace = struct { fraction: f32, world: u32 = 0, contents: u32 = 0, sky: bool = false, no_impact: bool = false, material: enum { ordinary, metal, wood } = .ordinary, end: vector.Vec3, normal: vector.Vec3, start_solid: bool = false, all_solid: bool = false, entity: u16 = 2047, slick: bool = false, ladder: bool = false, holy: bool = false };
pub const Request = struct { brushes_only: bool = false, start: vector.Vec3, end: vector.Vec3, mins: vector.Vec3, maxs: vector.Vec3, slot: u16, mask: u32 };
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
