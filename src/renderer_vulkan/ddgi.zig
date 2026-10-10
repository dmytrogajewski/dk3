// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster dynamic diffuse global illumination (ray tracing tier). A camera-centred field of
//! 32x32x16 probes, 96 units apart, scrolls with the eye and keeps per-probe history through
//! toroidal addressing. Every frame a rotating share of the probes traces 64 rays each against
//! the world (ddgi.comp); hits carry the baked lightmap radiance plus dynamic lights, so the
//! field holds the indirect light around the camera, including bounce from muzzle flashes and
//! explosions. Grid-lit models then take their ambient light from the field per pixel.
const std = @import("std");
const c = @import("c.zig").c;
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const post = @import("post.zig");

pub const dims = [3]i32{ 32, 32, 16 };
pub const spacing: f32 = 96;
const total: u32 = @intCast(dims[0] * dims[1] * dims[2]);

/// 0-3: irradiance L1 SH (see ddgi_common.glsl); 4-5: L1 SH of the distance and the squared
/// distance to the geometry around the probe (visibility: no light through walls).
var volumes: [6]vk.Texture = .{ .{}, .{}, .{}, .{}, .{}, .{} };
var storage: [6]u32 = .{ 0, 0, 0, 0, 0, 0 };
var sampled: [6]u32 = .{ 0, 0, 0, 0, 0, 0 };
var created = false;
var next_probe: u32 = 0;
var frame: u32 = 0;

/// Mirrors ddgi.comp `Params`.
const Params = extern struct {
    origin: [4]i32,
    dims: [4]i32,
    spacing: [4]f32,
    counts: [4]u32,
    table: u64,
    lights: u64,
    sky: [4]f32,
    map_lights: [4]u32 = .{ 0, 0, 0, 0 },
    cells: [4]f32 = .{ 0, 0, 0, 0 },
    cell_dims: [4]u32 = .{ 0, 0, 0, 0 },
    light_scale: [4]f32 = .{ 0, 0, 0, 0 },
};

/// Ray traced lighting inputs (rt.mapLightData); null keeps the baked lightmap radiance.
pub const MapLights = struct { lights: u64, cells: u64, origin: [3]f32, dims: [3]u32, scale: f32, overbright: f32, ambient: f32 };

pub const Field = struct { slots: [4]u32, slots2: [4]u32, origin: [4]i32, dims: [4]i32 };

/// The field of the last world view this frame (path tracing reads it for its bounce light).
pub var last_field: ?Field = null;

pub fn create() void {
    if (!vk.ray_tracing) return;
    const usage = c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    const cmd = vk.uploadCommands();
    const range = c.VkImageSubresourceRange{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 };
    const zero = c.VkClearColorValue{ .float32 = .{ 0, 0, 0, 0 } };
    for (&volumes, 0..) |*volume, index| {
        volume.* = vk.createVolume(@intCast(dims[0]), @intCast(dims[1]), @intCast(dims[2]), c.VK_FORMAT_R16G16B16A16_SFLOAT, usage);
        storage[index] = vk.bindStorageVolume(volume.view);
        sampled[index] = vk.bindVolumeLayout(volume.view, c.VK_IMAGE_LAYOUT_GENERAL);
        vk.barrier(cmd, volume.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL, vk.stage_all, 0, vk.stage_copy, vk.access_transfer_write);
        // Tag 0 everywhere with validity 0: nothing reads as a probe until it is traced.
        vk.d.CmdClearColorImage.?(cmd, volume.image, c.VK_IMAGE_LAYOUT_GENERAL, &zero, 1, &range);
        vk.barrier(cmd, volume.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_GENERAL, vk.stage_copy, vk.access_transfer_write, vk.stage_all, vk.access_memory_read | vk.access_memory_write);
    }
    created = true;
}

pub fn destroy() void {
    for (&volumes) |*volume| vk.destroyImage(volume);
    created = false;
}

/// Updates part of the field around `eye`; null when the tier or the field is off.
pub fn update(cmd: c.VkCommandBuffer, table: u64, eye: [3]f32, lights: u64, light_count: u32, sky: [3]f32, map_lights: ?MapLights) ?Field {
    last_field = null;
    if (!created or cvars.vkDdgi.integer == 0 or table == 0) return null;
    var origin: [4]i32 = .{ 0, 0, 0, 1 };
    for (0..3) |axis| origin[axis] = @as(i32, @intFromFloat(@floor(eye[axis] / spacing))) - @divTrunc(dims[axis], 2);
    const per_frame: u32 = @intCast(std.math.clamp(cvars.vkDdgiProbes.integer, 64, @as(c_int, @intCast(total))));
    frame +%= 1;
    var params: Params = .{
        .origin = origin,
        .dims = .{ dims[0], dims[1], dims[2], @intCast(total) },
        .spacing = .{ spacing, 0.98, 0, @floatFromInt(next_probe) },
        .counts = .{ per_frame, if (lights == 0) 0 else light_count, frame, 0 },
        .table = table,
        .lights = lights,
        .sky = .{ sky[0], sky[1], sky[2], 0 },
    };
    if (map_lights) |m| {
        params.map_lights = .{ @truncate(m.lights), @truncate(m.lights >> 32), @truncate(m.cells), @truncate(m.cells >> 32) };
        params.cells = .{ m.origin[0], m.origin[1], m.origin[2], @import("rt.zig").light_cell_size };
        params.cell_dims = .{ m.dims[0], m.dims[1], m.dims[2], 0 };
        params.light_scale = .{ m.scale, m.overbright, m.ambient, 0 };
    }
    const space = vk.frame().stream.alloc(@sizeOf(Params), 16) orelse return null;
    @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT | c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT | c.VK_ACCESS_2_SHADER_WRITE_BIT);
    vk.dispatch(cmd, "ddgi.comp", post.Push{
        .slots = storage[0..4].*,
        .size = .{ storage[4], storage[5], 0, 0 },
        .buffer1 = space.address,
    }, per_frame * 64, 1, 1, .{ 64, 1, 1 });
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT);
    next_probe = (next_probe + per_frame) % total;
    last_field = .{ .slots = sampled[0..4].*, .slots2 = .{ sampled[4], sampled[5], 0, 0 }, .origin = origin, .dims = .{ dims[0], dims[1], dims[2], @bitCast(@as(f32, spacing)) } };
    return .{ .slots = sampled[0..4].*, .slots2 = .{ sampled[4], sampled[5], 0, 0 }, .origin = origin, .dims = .{ dims[0], dims[1], dims[2], @bitCast(@as(f32, spacing)) } };
}
