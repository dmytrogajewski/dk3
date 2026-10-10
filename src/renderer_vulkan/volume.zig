// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster volumetric fog: a camera-aligned froxel grid (exponential depth slices). The
//! inject pass evaluates extinction and in-scattered light per froxel (authored worldspawn fog,
//! a thin base atmosphere lit by the light grid, dynamic lights with a Henyey-Greenstein phase);
//! the integrate pass accumulates them front to back. Stage shaders then look up the integrated
//! in-scattering and transmittance at each fragment's depth instead of linear distance fog.
const std = @import("std");
const c = @import("c.zig").c;
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const post = @import("post.zig");

pub const grid = [3]u32{ 128, 72, 64 };
pub const format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
/// Distance of the first slice boundary; nearer fragments use the first slice.
pub const near: f32 = 12;
const max_far: f32 = 6000;

var inject: vk.Texture = .{};
var integrated: vk.Texture = .{};
var inject_storage: u32 = 0;
var integrated_storage: u32 = 0;
/// Sampled (GENERAL layout) slot of the integrated volume.
var integrated_slot: u32 = 0;
/// Dynamic-light glow travels in its own pair so the authored fog's display remap
/// (stage.frag) does not dim it.
var inject_glow: vk.Texture = .{};
var integrated_glow: vk.Texture = .{};
var inject_glow_storage: u32 = 0;
var integrated_glow_storage: u32 = 0;
var integrated_glow_slot: u32 = 0;
var created = false;

/// Per-dispatch parameters, written to the frame stream (froxel_common.glsl `Params`).
const Params = extern struct {
    origin: [4]f32, // eye, w = time
    forward: [4]f32, // w = tan(fov_x / 2)
    left: [4]f32, // w = tan(fov_y / 2)
    up: [4]f32, // w = near
    slices: [4]f32, // log(far / near), far, base density, scatter strength
    fog: [4]f32, // authored fog colour (display), w = authored density
    fog_range: [4]f32, // authored start, end, enabled, unused
    grid0: [4]f32, // light grid origin, w = present
    grid1: [4]f32, // light grid scale
    counts: [4]u32, // dlights, grid colour slot + 1, grid direction slot + 1, unused
    rain_to_tile: [16]f32 = std.mem.zeroes([16]f32), // world -> rain occlusion map clip
    rain_tile: [4]f32 = .{ 0, 0, 0, 0 }, // atlas uv origin, uv size, enabled
    rain_params: [4]f32 = .{ 0, 0, 0, 0 }, // depth per unit, z top, texel uv, half extent
    rain_info: [4]f32 = .{ 0, 0, 0, 0 }, // atlas slot, box count, intensity, unused
    rain_boxes: [16][4]f32 = std.mem.zeroes([16][4]f32), // (mins, kind), (maxs, 0)
    // Ray traced light shafts (froxel_inject_rt.comp): visibility of map lights and sky.
    rt_table: u64 = 0,
    rt_lights: u64 = 0,
    rt_cells_address: u64 = 0,
    rt_pad: u64 = 0,
    rt_cells: [4]f32 = .{ 0, 0, 0, 0 }, // cell grid origin, cell size
    rt_cell_dims: [4]u32 = .{ 0, 0, 0, 0 },
    rt_light_scale: [4]f32 = .{ 0, 0, 0, 0 }, // radiosity scale, overbright, ambient
    rt_sky: [4]f32 = .{ 0, 0, 0, 0 }, // sky radiance, enabled
};

/// What stage shaders need to sample the result (common.glsl `ViewData`).
pub const ViewData = extern struct {
    rect: [4]f32, // view x, y, width, height in framebuffer pixels
    froxel: [4]f32, // near, 1 / log(far / near), far, enabled
    slots: [4]u32, // integrated volume slot, integrated glow slot
    jitter: [4]f32 = .{ 0, 0, 0, 0 },
    weather: [4]u32 = .{ 0, 0, 0, 0 },
    weather_params: [4]f32 = .{ 0, 0, 0, 0 },
    boxes: [16][4]f32 = std.mem.zeroes([16][4]f32),
    clusters: [4]u32 = .{ 0, 0, 0, 0 },
    cluster_params: [4]f32 = .{ 0, 0, 0, 0 },
    cluster_list: [4]u32 = .{ 0, 0, 0, 0 },
    shadows: [4]u32 = .{ 0, 0, 0, 0 },
    shadow_list: [4]u32 = .{ 0, 0, 0, 0 },
    rt: [4]u32 = .{ 0, 0, 0, 0 },
    rt_table: [4]u32 = .{ 0, 0, 0, 0 },
    ddgi_slots: [4]u32 = .{ 0, 0, 0, 0 },
    ddgi_slots2: [4]u32 = .{ 0, 0, 0, 0 }, // distance, squared distance volumes
    ddgi_origin: [4]i32 = .{ 0, 0, 0, 0 }, // w = enabled
    ddgi_dims: [4]i32 = .{ 0, 0, 0, 0 }, // w = spacing bits
    rain_to_tile: [16]f32 = std.mem.zeroes([16]f32),
    rain: [4]f32 = .{ 0, 0, 0, 0 }, // atlas uv origin x, y, uv size, enabled
    rain_params: [4]f32 = .{ 0, 0, 0, 0 }, // depth per unit, z top, texel uv, half extent
    fog_params: [4]f32 = .{ 0, 0, 0, 0 }, // sky column depth, eye liquid
    // Ray traced lighting (r_vkLighting 1, shaders/rt_lighting.glsl): map lights and their cells.
    rt_lights: [4]u32 = .{ 0, 0, 0, 0 }, // lights address, cell lists address
    rt_cells: [4]f32 = .{ 0, 0, 0, 0 }, // cell grid origin, cell size
    rt_cell_dims: [4]u32 = .{ 0, 0, 0, 0 }, // cells per axis, enabled
    rt_light_scale: [4]f32 = .{ 0, 0, 0, 0 }, // radiosity scale, overbright, unused
    rt_sky: [4]f32 = .{ 0, 0, 0, 0 }, // sky radiance for per-pixel sky light, w = enabled
};

pub fn create() void {
    const usage = c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    inject = vk.createVolume(grid[0], grid[1], grid[2], format, usage);
    integrated = vk.createVolume(grid[0], grid[1], grid[2], format, usage);
    inject_glow = vk.createVolume(grid[0], grid[1], grid[2], format, usage);
    integrated_glow = vk.createVolume(grid[0], grid[1], grid[2], format, usage);
    inject_storage = vk.bindStorageVolume(inject.view);
    integrated_storage = vk.bindStorageVolume(integrated.view);
    inject_glow_storage = vk.bindStorageVolume(inject_glow.view);
    integrated_glow_storage = vk.bindStorageVolume(integrated_glow.view);
    integrated_slot = vk.bindVolumeLayout(integrated.view, c.VK_IMAGE_LAYOUT_GENERAL);
    integrated_glow_slot = vk.bindVolumeLayout(integrated_glow.view, c.VK_IMAGE_LAYOUT_GENERAL);
    const cmd = vk.uploadCommands();
    for ([_]*vk.Texture{ &inject, &integrated, &inject_glow, &integrated_glow }) |texture| {
        vk.barrier(cmd, texture.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL, vk.stage_all, 0, vk.stage_all, vk.access_memory_read | vk.access_memory_write);
    }
    created = true;
}

pub fn destroy() void {
    vk.destroyImage(&inject);
    vk.destroyImage(&integrated);
    vk.destroyImage(&inject_glow);
    vk.destroyImage(&integrated_glow);
    created = false;
}

pub const Input = struct {
    origin: [3]f32,
    axis: [3][3]f32,
    fov_x: f32,
    fov_y: f32,
    far: f32,
    time: f32,
    dlights: u64,
    dlight_count: u32,
    fog: ?struct { color: [3]f32, start: f32, end: f32 },
    grid: ?struct { origin: [4]f32, scale: [4]f32, slot: u32, color_slot: u32 },
    rain: ?struct { boxes: [16][4]f32, count: u32, to_tile: [16]f32, tile: [4]f32, params: [4]f32, slot: u32, intensity: f32 } = null,
    rt: ?struct { table: u64, lights: u64, cells: u64, cell_origin: [3]f32, cell_dims: [3]u32, light_scale: [3]f32, sky: [3]f32 } = null,
};

/// Builds the froxel volume for one camera. Must run outside dynamic rendering. Returns the
/// sampling description for the view's stage shaders.
pub fn run(cmd: c.VkCommandBuffer, in: Input) ?ViewData {
    if (!created or cvars.vkVolumetric.integer == 0) return null;
    const far = std.math.clamp(in.far, near * 4, max_far);
    const log_range = @log(far / near);
    var params: Params = .{
        .origin = .{ in.origin[0], in.origin[1], in.origin[2], in.time },
        .forward = .{ in.axis[0][0], in.axis[0][1], in.axis[0][2], @tan(in.fov_x * std.math.pi / 360.0) },
        .left = .{ in.axis[1][0], in.axis[1][1], in.axis[1][2], @tan(in.fov_y * std.math.pi / 360.0) },
        .up = .{ in.axis[2][0], in.axis[2][1], in.axis[2][2], near },
        .slices = .{ log_range, far, @max(cvars.vkFogDensity.value, 0), @max(cvars.vkFogScatter.value, 0) },
        .fog = .{ 0, 0, 0, 0 },
        .fog_range = .{ 0, 1, 0, 0 },
        .grid0 = .{ 0, 0, 0, 0 },
        .grid1 = .{ 0, 0, 0, 0 },
        .counts = .{ if (in.dlights == 0) 0 else in.dlight_count, 0, 0, 0 },
    };
    if (in.fog) |fog| {
        // Linear fog reaches full cover at `end`; exponential extinction of 1.5 / span leaves
        // ~47% at mid-span and ~22% at the end. stage.frag remaps the coverage so the mix
        // matches the original's display-space blend.
        const span = @max(fog.end - fog.start, 1);
        params.fog = .{ fog.color[0], fog.color[1], fog.color[2], 1.5 / span };
        params.fog_range = .{ fog.start, fog.end, 1, 0 };
    }
    if (in.grid) |g| {
        params.grid0 = g.origin;
        params.grid1 = g.scale;
        params.counts[1] = g.color_slot + 1;
        params.counts[2] = g.slot + 1;
    }
    if (in.rain) |rain| if (rain.intensity > 0) {
        params.rain_to_tile = rain.to_tile;
        params.rain_tile = rain.tile;
        params.rain_params = rain.params;
        params.rain_info = .{ @floatFromInt(rain.slot), @floatFromInt(rain.count), rain.intensity, 0 };
        params.rain_boxes = rain.boxes;
    };
    var traced = false;
    if (in.rt) |r| if (cvars.vkVolumetricShadows.integer != 0) {
        traced = true;
        params.rt_table = r.table;
        params.rt_lights = r.lights;
        params.rt_cells_address = r.cells;
        params.rt_cells = .{ r.cell_origin[0], r.cell_origin[1], r.cell_origin[2], @import("rt.zig").light_cell_size };
        params.rt_cell_dims = .{ r.cell_dims[0], r.cell_dims[1], r.cell_dims[2], 0 };
        params.rt_light_scale = .{ r.light_scale[0], r.light_scale[1], r.light_scale[2], 0 };
        params.rt_sky = .{ r.sky[0], r.sky[1], r.sky[2], 1 };
    };
    // Authored map fog (worldspawn): the original hid its draw distance in it; r_vkMapFog scales it.
    params.fog[3] *= @max(cvars.vkMapFog.value, 0);
    const space = vk.frame().stream.alloc(@sizeOf(Params), 16) orelse return null;
    @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
    // Earlier views of this frame may still sample the volume.
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT);
    if (traced) vk.dispatch(cmd, "froxel_inject_rt.comp", post.Push{
        .slots = .{ inject_storage, integrated_storage, inject_glow_storage, integrated_glow_storage },
        .size = .{ grid[0], grid[1], grid[2], 0 },
        .buffer0 = in.dlights,
        .buffer1 = space.address,
    }, grid[0], grid[1], grid[2], .{ 8, 8, 1 }) else vk.dispatch(cmd, "froxel_inject.comp", post.Push{
        .slots = .{ inject_storage, integrated_storage, inject_glow_storage, integrated_glow_storage },
        .size = .{ grid[0], grid[1], grid[2], 0 },
        .buffer0 = in.dlights,
        .buffer1 = space.address,
    }, grid[0], grid[1], grid[2], .{ 8, 8, 1 });
    vk.computeBarrier(cmd);
    vk.dispatch(cmd, "froxel_integrate.comp", post.Push{
        .slots = .{ inject_storage, integrated_storage, inject_glow_storage, integrated_glow_storage },
        .size = .{ grid[0], grid[1], grid[2], 0 },
        .buffer1 = space.address,
    }, grid[0], grid[1], 1, .{ 8, 8, 1 });
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT);
    return .{
        .rect = .{ 0, 0, 1, 1 },
        .froxel = .{ near, 1.0 / log_range, far, 1 },
        .slots = .{ integrated_slot, integrated_glow_slot, 0, 0 },
    };
}

/// A view without volumetrics (disabled or not built).
pub fn emptyViewData() ViewData {
    return .{ .rect = .{ 0, 0, 1, 1 }, .froxel = .{ near, 1, 1, 0 }, .slots = .{ 0, 0, 0, 0 } };
}
