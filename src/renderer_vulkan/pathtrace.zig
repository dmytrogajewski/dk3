// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster path tracing mode (`r_vkPathTracing 1`, ray tracing tier). After the opaque world
//! is rasterised, every pixel traces its primary ray against the world structures; where the
//! hit agrees with the raster depth, the world's lighting is recomputed: direct light from the
//! map's own light entities (resampled importance sampling over a world light grid, one shadow
//! ray) and dynamic lights, plus one bounce that reads the baked lightmap radiance at its hit.
//! The noisy result is accumulated over time with depth/normal-checked reprojection and
//! filtered by three variance-guided à-trous iterations before it replaces the raster colour.
//! Models, liquids, particles and sky stay rasterised.
const std = @import("std");
const c = @import("c.zig").c;
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const post = @import("post.zig");
const window = @import("window.zig");
const taa = @import("taa.zig");
const rt = @import("rt.zig");

const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;

const Image = struct { texture: vk.Texture = .{}, storage: u32 = 0, sampled: u32 = 0 };
var noisy: Image = .{};
var albedo: Image = .{};
var normal_depth: [2]Image = .{ .{}, .{} };
var history: [2]Image = .{ .{}, .{} };
var moments: [2]Image = .{ .{}, .{} };
var filtered: [2]Image = .{ .{}, .{} };
var current: u1 = 0;
var history_valid = false;
var frame: u32 = 0;
var created = false;
var width: u32 = 0;
var height: u32 = 0;

/// Mirrors pt_common.glsl `PtParams`.
const Params = extern struct {
    inverse_current: [16]f32,
    previous: [16]f32,
    origin: [4]f32,
    forward: [4]f32,
    left: [4]f32,
    up: [4]f32,
    rect: [4]f32,
    jitter: [4]f32,
    sky: [4]f32,
    cells: [4]f32,
    cell_dims: [4]u32,
    counts: [4]u32,
    table: u64,
    lights: u64,
    light_cells: u64,
    dynamic_lights: u64,
    view_data: u64,
    pad: u64 = 0,
    ddgi_slots: [4]u32 = .{ 0, 0, 0, 0 },
    ddgi_slots2: [4]u32 = .{ 0, 0, 0, 0 },
    ddgi_origin: [4]i32 = .{ 0, 0, 0, 0 },
    ddgi_dims: [4]i32 = .{ 0, 0, 0, 0 },
    rt_sky: [4]f32 = .{ 0, 0, 0, 0 },
};

fn makeImage(cmd: c.VkCommandBuffer) Image {
    var out: Image = .{};
    out.texture = vk.createImage(width, height, 1, format, c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
    out.storage = vk.bindStorage(out.texture.view);
    out.sampled = vk.bindView(out.texture.view, .nearest_clamp, c.VK_IMAGE_LAYOUT_GENERAL);
    vk.barrier(cmd, out.texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL, vk.stage_all, 0, vk.stage_all, vk.access_memory_read | vk.access_memory_write);
    return out;
}

pub fn create(w: u32, h: u32) void {
    if (!vk.ray_tracing) return;
    width = w;
    height = h;
    const cmd = vk.uploadCommands();
    noisy = makeImage(cmd);
    albedo = makeImage(cmd);
    for (0..2) |k| {
        normal_depth[k] = makeImage(cmd);
        history[k] = makeImage(cmd);
        moments[k] = makeImage(cmd);
        filtered[k] = makeImage(cmd);
    }
    created = true;
    history_valid = false;
}

pub fn destroy() void {
    vk.destroyImage(&noisy.texture);
    vk.destroyImage(&albedo.texture);
    for (0..2) |k| {
        vk.destroyImage(&normal_depth[k].texture);
        vk.destroyImage(&history[k].texture);
        vk.destroyImage(&moments[k].texture);
        vk.destroyImage(&filtered[k].texture);
    }
    created = false;
}

pub fn active() bool {
    return created and cvars.vkPathTracing.integer != 0 and rt.enabled();
}

pub const Camera = struct {
    origin: [3]f32,
    axis: [3][3]f32,
    fov_x: f32,
    fov_y: f32,
    znear: f32,
    zfar: f32,
    rect: [4]f32,
    dlights: u64,
    dlight_count: u32,
    view_data: u64,
    sky: [3]f32,
};

fn barrierAll(cmd: c.VkCommandBuffer) void {
    vk.computeBarrier(cmd);
}

/// Traces, accumulates, filters and composites into the HDR target. Called between the opaque
/// and the translucent surfaces of the main world view.
pub fn run(cmd: c.VkCommandBuffer, owner: *@import("world.zig").World, table: u64, camera: Camera) void {
    if (!active() or table == 0) return;
    const state = &owner.rt;
    const matrices = taa.reprojection() orelse return;
    frame +%= 1;
    const jitter = taa.currentJitter();
    var params: Params = .{
        .inverse_current = matrices.inverse_current,
        .previous = matrices.previous,
        .origin = .{ camera.origin[0], camera.origin[1], camera.origin[2], @floatFromInt(frame) },
        .forward = .{ camera.axis[0][0], camera.axis[0][1], camera.axis[0][2], @tan(camera.fov_x * std.math.pi / 360.0) },
        .left = .{ camera.axis[1][0], camera.axis[1][1], camera.axis[1][2], @tan(camera.fov_y * std.math.pi / 360.0) },
        .up = .{ camera.axis[2][0], camera.axis[2][1], camera.axis[2][2], @max(cvars.vkPtLightScale.value, 0) },
        .rect = camera.rect,
        .jitter = .{ jitter[0], jitter[1], camera.znear, camera.zfar },
        .sky = .{ camera.sky[0], camera.sky[1], camera.sky[2], std.math.pow(f32, 2, @floatFromInt(std.math.clamp(cvars.mapOverBrightBits.integer, 0, 8))) },
        .cells = .{ state.cell_origin[0], state.cell_origin[1], state.cell_origin[2], rt.light_cell_size },
        .cell_dims = .{ state.cell_dims[0], state.cell_dims[1], state.cell_dims[2], state.light_count },
        .counts = .{ if (camera.dlights == 0) 0 else camera.dlight_count, @intFromBool(history_valid and matrices.valid), if (cvars.vkDebugView.integer == 1 or cvars.vkDebugView.integer == 2) @intCast(cvars.vkDebugView.integer) else 0, 0 },
        .table = table,
        .lights = state.lights.address,
        .light_cells = state.light_cells.address,
        .dynamic_lights = camera.dlights,
        .view_data = camera.view_data,
    };
    if (state.light_count == 0) params.cell_dims[3] = 0;
    // Ray traced lighting: bounce hits are lit by the map lights and the probe field instead of
    // the lightmaps, so the whole image is free of baked light.
    if (cvars.vkLighting.integer != 0) if (@import("ddgi.zig").last_field) |field| {
        params.ddgi_slots = field.slots;
        params.ddgi_slots2 = field.slots2;
        params.ddgi_origin = field.origin;
        params.ddgi_dims = field.dims;
        const sky_light = @import("rt.zig").skyFor(owner);
        params.rt_sky = .{ sky_light[0], sky_light[1], sky_light[2], 1 };
    };
    const space = vk.frame().stream.alloc(@sizeOf(Params), 16) orelse return;
    @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
    const previous: u1 = current;
    const next: u1 = current ^ 1;
    window.hdrToCompute();
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT | c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT | c.VK_ACCESS_2_SHADER_WRITE_BIT);
    const group = [3]u32{ 8, 8, 1 };
    vk.dispatch(cmd, "pt_trace.comp", post.Push{
        .slots = .{ noisy.storage, albedo.storage, normal_depth[next].storage, window.depth_slot },
        .size = .{ width, height, 0, 0 },
        .buffer1 = space.address,
    }, width, height, 1, group);
    barrierAll(cmd);
    vk.dispatch(cmd, "pt_temporal.comp", post.Push{
        .slots = .{ noisy.storage, normal_depth[next].storage, history[next].storage, moments[next].storage },
        .size = .{ width, height, history[previous].sampled, normal_depth[previous].sampled },
        .buffer1 = space.address,
        .params = .{ @floatFromInt(width), @floatFromInt(height), @floatFromInt(moments[previous].sampled), 0 },
    }, width, height, 1, group);
    barrierAll(cmd);
    var input = history[next].storage;
    for (0..3) |iteration| {
        const output = filtered[iteration % 2].storage;
        vk.dispatch(cmd, "pt_atrous.comp", post.Push{
            .slots = .{ input, output, normal_depth[next].storage, moments[next].storage },
            .size = .{ width, height, 0, 0 },
            .params = .{ @floatFromInt(@as(u32, 1) << @intCast(iteration)), 0, 0, 0 },
        }, width, height, 1, group);
        barrierAll(cmd);
        input = output;
    }
    vk.dispatch(cmd, "pt_composite.comp", post.Push{
        .slots = .{ input, albedo.storage, normal_depth[next].storage, window.hdr_storage },
        .size = .{ width, height, 0, 0 },
        .buffer1 = space.address,
    }, width, height, 1, group);
    window.hdrFromCompute();
    current = next;
    history_valid = true;
}

/// Camera cuts and disabled frames restart the accumulation.
pub fn invalidate() void {
    history_valid = false;
}
