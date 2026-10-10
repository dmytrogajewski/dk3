// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster clustered dynamic lights: a compute pass bins the view's lights into a
//! camera-aligned 16x9x24 grid (exponential depth slices) so fragments only shade the lights
//! that reach their cluster. Lifts the OpenGL-era 32 light limit for the remaster path.
const std = @import("std");
const c = @import("c.zig").c;
const vk = @import("vk.zig");
const post = @import("post.zig");

pub const grid = [3]u32{ 16, 9, 24 };
pub const max_per_cluster = 63;
pub const max_lights = 256;
pub const near: f32 = 8;
const cluster_count = grid[0] * grid[1] * grid[2];

var buffer: vk.Buffer = .{};
var created = false;

/// Mirrors light_cull.comp `Params`.
const Params = extern struct {
    origin: [4]f32,
    forward: [4]f32, // w = tan(fov_x / 2)
    left: [4]f32, // w = tan(fov_y / 2)
    up: [4]f32, // w = near
    slices: [4]f32, // log(far / near), far, light count, unused
};

pub fn create() void {
    buffer = vk.createBuffer(@as(u64, cluster_count) * (max_per_cluster + 1) * 4, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, vk.device_flags);
    created = true;
}

pub fn destroy() void {
    vk.destroyBuffer(&buffer);
    created = false;
}

pub const Result = struct { address: u64, near: f32, inverse_log: f32 };

/// Bins `count` lights at `lights` (two vec4 each) for one camera. Runs outside rendering.
pub fn run(cmd: c.VkCommandBuffer, origin: [3]f32, axis: [3][3]f32, fov_x: f32, fov_y: f32, far_in: f32, lights: u64, count: u32) ?Result {
    if (!created or count == 0 or lights == 0) return null;
    const far = @max(far_in, near * 4);
    const log_range = @log(far / near);
    const params: Params = .{
        .origin = .{ origin[0], origin[1], origin[2], 0 },
        .forward = .{ axis[0][0], axis[0][1], axis[0][2], @tan(fov_x * std.math.pi / 360.0) },
        .left = .{ axis[1][0], axis[1][1], axis[1][2], @tan(fov_y * std.math.pi / 360.0) },
        .up = .{ axis[2][0], axis[2][1], axis[2][2], near },
        .slices = .{ log_range, far, @floatFromInt(@min(count, max_lights)), 0 },
    };
    const space = vk.frame().stream.alloc(@sizeOf(Params), 16) orelse return null;
    @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT);
    vk.dispatch(cmd, "light_cull.comp", post.Push{
        .size = .{ grid[0], grid[1], grid[2], max_per_cluster },
        .buffer0 = lights,
        .buffer1 = space.address,
        .slots = .{ @truncate(buffer.address), @truncate(buffer.address >> 32), 0, 0 },
    }, grid[0], grid[1], grid[2], .{ 4, 3, 4 });
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT);
    return .{ .address = buffer.address, .near = near, .inverse_log = 1.0 / log_range };
}
