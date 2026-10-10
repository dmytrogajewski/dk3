// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster post-processing on the HDR scene: log-luminance histogram auto exposure and a
//! physically based bloom mip chain. The composite pass (composite.frag) applies exposure,
//! bloom and the AgX view transform before laying the UI overlay on top.
const std = @import("std");
const c = @import("c.zig").c;
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");

/// Push constants shared by every compute pass and the composite (post_common.glsl).
pub const Push = extern struct {
    slots: [4]u32 = .{ 0, 0, 0, 0 },
    size: [4]u32 = .{ 0, 0, 0, 0 },
    buffer0: u64 = 0,
    buffer1: u64 = 0,
    params: [4]f32 = .{ 0, 0, 0, 0 },
    params2: [4]f32 = .{ 0, 0, 0, 0 },
    params3: [4]f32 = .{ 0, 0, 0, 0 },
};
comptime {
    if (@sizeOf(Push) > vk.push_size) @compileError("post push constants exceed the pipeline layout");
}

pub const bloom_format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
const max_levels = 7;
const min_log2: f32 = -10;
const log2_range: f32 = 14;

var bloom: vk.Texture = .{};
var bloom_levels: u32 = 0;
var level_views: [max_levels]c.VkImageView = .{null} ** max_levels;
var level_storage: [max_levels]u32 = undefined;
var level_sampled: [max_levels]u32 = undefined;
var level_size: [max_levels][2]u32 = undefined;
pub var histogram: vk.Buffer = .{};
pub var exposure: vk.Buffer = .{};
var last_ms: i32 = 0;

pub fn create(width: u32, height: u32) void {
    var w = @max(width / 2, 1);
    var h = @max(height / 2, 1);
    bloom_levels = 0;
    var dims: [max_levels][2]u32 = undefined;
    while (bloom_levels < max_levels and w >= 4 and h >= 4) : (bloom_levels += 1) {
        dims[bloom_levels] = .{ w, h };
        w = @max(w / 2, 1);
        h = @max(h / 2, 1);
    }
    bloom = vk.createImage(dims[0][0], dims[0][1], bloom_levels, bloom_format, c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
    for (0..bloom_levels) |level| {
        level_views[level] = vk.mipView(bloom.image, bloom_format, @intCast(level));
        level_storage[level] = vk.bindStorage(level_views[level]);
        level_sampled[level] = vk.bindView(level_views[level], .clamp, c.VK_IMAGE_LAYOUT_GENERAL);
        level_size[level] = dims[level];
    }
    histogram = vk.createBuffer(256 * 4, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, vk.device_flags);
    exposure = vk.createBuffer(16, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT | c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, vk.device_flags);
    const cmd = vk.uploadCommands();
    vk.d.CmdFillBuffer.?(cmd, histogram.buffer, 0, c.VK_WHOLE_SIZE, 0);
    vk.d.CmdFillBuffer.?(cmd, exposure.buffer, 0, c.VK_WHOLE_SIZE, 0);
    vk.barrier(cmd, bloom.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL, vk.stage_all, 0, vk.stage_all, vk.access_memory_read | vk.access_memory_write);
    vk.memoryBarrier(cmd, vk.stage_copy, vk.access_transfer_write, vk.stage_all, vk.access_memory_read | vk.access_memory_write);
}

pub fn destroy() void {
    for (level_views[0..bloom_levels]) |*view| {
        if (view.* != null) vk.d.DestroyImageView.?(vk.s.device, view.*, null);
        view.* = null;
    }
    vk.destroyImage(&bloom);
    vk.destroyBuffer(&histogram);
    vk.destroyBuffer(&exposure);
    bloom_levels = 0;
}

/// Sampler slot + 1 of the accumulated bloom, 0 when bloom is off.
pub fn bloomSlot() u32 {
    if (bloom_levels == 0 or cvars.vkBloom.value <= 0) return 0;
    return level_sampled[0] + 1;
}

/// Runs exposure and bloom on the HDR scene, which must be shader-readable.
pub fn run(cmd: c.VkCommandBuffer, hdr_slot: u32, width: u32, height: u32) void {
    const now = common.milliseconds();
    const dt: f32 = if (last_ms == 0) 0 else @as(f32, @floatFromInt(std.math.clamp(now - last_ms, 0, 250))) / 1000.0;
    last_ms = now;
    const auto = cvars.vkAutoExposure.integer != 0;
    const rt_lit = cvars.vkLighting.integer != 0 and @import("rt.zig").enabled();
    vk.dispatch(cmd, "post_histogram.comp", Push{
        .slots = .{ hdr_slot, 0, 0, 0 },
        .size = .{ width / 2, height / 2, width, height },
        .buffer0 = histogram.address,
        .params = .{ min_log2, 1.0 / log2_range, 0, 0 },
    }, width / 2, height / 2, 1, .{ 16, 16, 1 });
    vk.computeBarrier(cmd);
    vk.dispatch(cmd, "post_exposure.comp", Push{
        .buffer0 = histogram.address,
        .buffer1 = exposure.address,
        // Key 0.1 with partial adaptation clamped to [0.75, 1.25]: the authored levels lead and
        // the eye only adds a touch of adaptation either way.
        .params = .{ min_log2, log2_range, 0.1, if (auto) 1.6 else 0 },
        // Ray traced lighting has no designer-baked fill light: like a modern game's eye
        // adaptation, exposure may rise up to 3x so dark rooms stay readable.
        .params2 = .{ dt, if (auto) (if (rt_lit) @as(f32, 0.6) else 0.75) else 1, if (auto) (if (rt_lit) @as(f32, 3.0) else 1.25) else 1, cvars.vkExposure.value },
    }, 1, 1, 1, .{ 1, 1, 1 });
    vk.computeBarrier(cmd);
    if (cvars.vkBloom.value <= 0 or bloom_levels == 0) return;
    // Downsample: the HDR scene into level 0 with the threshold, then level by level.
    for (0..bloom_levels) |level| {
        const source_slot = if (level == 0) hdr_slot else level_sampled[level - 1];
        const source_size = if (level == 0) [2]u32{ width, height } else level_size[level - 1];
        vk.dispatch(cmd, "bloom_down.comp", Push{
            .slots = .{ source_slot, level_storage[level], 0, 0 },
            .size = .{ level_size[level][0], level_size[level][1], source_size[0], source_size[1] },
            .buffer1 = exposure.address,
            .params = .{ if (level == 0) 1 else 0, 0.9, 0.5, 0 },
        }, level_size[level][0], level_size[level][1], 1, .{ 8, 8, 1 });
        vk.computeBarrier(cmd);
    }
    // Upsample: accumulate each lower level into the next higher one.
    var level: usize = bloom_levels - 1;
    while (level > 0) : (level -= 1) {
        vk.dispatch(cmd, "bloom_up.comp", Push{
            .slots = .{ level_sampled[level], level_storage[level - 1], 0, 0 },
            .size = .{ level_size[level - 1][0], level_size[level - 1][1], level_size[level][0], level_size[level][1] },
            .params = .{ 1.0, 0, 0, 0 },
        }, level_size[level - 1][0], level_size[level - 1][1], 1, .{ 8, 8, 1 });
        vk.computeBarrier(cmd);
    }
}
