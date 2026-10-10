// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster temporal anti-aliasing and upscaling. World views render with a sub-pixel Halton
//! jitter at `window.render_scale`; the resolve pass reprojects the previous output through the
//! depth buffer (camera motion), clips it to the current neighbourhood in YCoCg and blends it
//! with a Catmull-Rom upsample of the new frame into an output-resolution history image. The
//! composite then applies contrast-adaptive sharpening.
const std = @import("std");
const c = @import("c.zig").c;
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const post = @import("post.zig");
const window = @import("window.zig");

const Mat4 = [4][4]f32;

var history: [2]vk.Texture = .{ .{}, .{} };
var history_storage: [2]u32 = .{ 0, 0 };
var history_sampled: [2]u32 = .{ 0, 0 };
var current: u1 = 0;
var created = false;
var history_valid = false;

var frame_index: u32 = 0;
var frame_counter: u32 = 0;
/// This frame's jitter in NDC units (applied to world-view projections).
var jitter: [2]f32 = .{ 0, 0 };
var enabled_this_frame = false;

/// The registered camera of this frame and the previous resolved frame.
var camera_count: u32 = 0;
var view_projection: Mat4 = undefined;
var origin: [3]f32 = .{ 0, 0, 0 };
var previous_view_projection: Mat4 = undefined;
var previous_origin: [3]f32 = .{ 0, 0, 0 };
var previous_forward: [3]f32 = .{ 1, 0, 0 };
var forward: [3]f32 = .{ 1, 0, 0 };

const Params = extern struct {
    inverse: [16]f32, // current unjittered clip -> world (column-major)
    previous: [16]f32, // world -> previous clip (column-major)
};

pub fn create(width: u32, height: u32) void {
    const usage = c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    const cmd = vk.uploadCommands();
    for (0..2) |index| {
        history[index] = vk.createImage(width, height, 1, window.hdr_format, usage, c.VK_IMAGE_ASPECT_COLOR_BIT);
        history_storage[index] = vk.bindStorage(history[index].view);
        history_sampled[index] = vk.bindView(history[index].view, .clamp, c.VK_IMAGE_LAYOUT_GENERAL);
        vk.barrier(cmd, history[index].image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_GENERAL, vk.stage_all, 0, vk.stage_all, vk.access_memory_read | vk.access_memory_write);
    }
    created = true;
    history_valid = false;
}

pub fn destroy() void {
    for (&history) |*texture| vk.destroyImage(texture);
    created = false;
    history_valid = false;
}

fn halton(index: u32, base: u32) f32 {
    var f: f32 = 1;
    var r: f32 = 0;
    var i = index;
    while (i > 0) {
        f /= @floatFromInt(base);
        r += f * @as(f32, @floatFromInt(i % base));
        i /= base;
    }
    return r;
}

/// True when this frame resolves temporally or upscales.
fn wanted() bool {
    return created and (cvars.vkTAA.integer != 0 or window.render_scale < 1);
}

pub fn beginFrame() void {
    camera_count = 0;
    frame_counter +%= 1;
    enabled_this_frame = created and cvars.vkTAA.integer != 0;
    if (!enabled_this_frame) {
        jitter = .{ 0, 0 };
        return;
    }
    frame_index = (frame_index + 1) % 16;
    // Halton(2, 3) sub-pixel offsets in render-target pixels, as NDC.
    const w: f32 = @floatFromInt(@max(window.hdr.width, 1));
    const h: f32 = @floatFromInt(@max(window.hdr.height, 1));
    jitter = .{ (halton(frame_index + 1, 2) - 0.5) * 2 / w, (halton(frame_index + 1, 3) - 0.5) * 2 / h };
}

/// Applies the frame jitter to a remaster world projection (row-major, Q3 layout).
pub fn jitterProjection(projection: *Mat4) void {
    if (!enabled_this_frame) return;
    projection[0][2] -= jitter[0];
    projection[1][2] -= jitter[1];
}

fn mul(a: Mat4, b: Mat4) Mat4 {
    var out: Mat4 = undefined;
    for (0..4) |row| for (0..4) |column| {
        var sum: f32 = 0;
        for (0..4) |k| sum += a[row][k] * b[k][column];
        out[row][column] = sum;
    };
    return out;
}

fn inverse(m: Mat4) ?Mat4 {
    var a: [4][8]f64 = undefined;
    for (0..4) |row| for (0..8) |column| {
        a[row][column] = if (column < 4) m[row][column] else if (column - 4 == row) 1 else 0;
    };
    for (0..4) |pivot_column| {
        var pivot = pivot_column;
        for (pivot_column + 1..4) |row| {
            if (@abs(a[row][pivot_column]) > @abs(a[pivot][pivot_column])) pivot = row;
        }
        if (@abs(a[pivot][pivot_column]) < 1e-12) return null;
        std.mem.swap([8]f64, &a[pivot], &a[pivot_column]);
        const scale = 1 / a[pivot_column][pivot_column];
        for (&a[pivot_column]) |*value| value.* *= scale;
        for (0..4) |row| {
            if (row == pivot_column) continue;
            const factor = a[row][pivot_column];
            if (factor == 0) continue;
            for (0..8) |column| a[row][column] -= factor * a[pivot_column][column];
        }
    }
    var out: Mat4 = undefined;
    for (0..4) |row| for (0..4) |column| {
        out[row][column] = @floatCast(a[row][column + 4]);
    };
    return out;
}

fn columnMajor(m: Mat4) [16]f32 {
    var out: [16]f32 = undefined;
    for (0..4) |row| for (0..4) |column| {
        out[column * 4 + row] = m[row][column];
    };
    return out;
}

/// Current unjittered clip -> world and the previous frame's world -> clip, column-major.
pub fn reprojection() ?struct { inverse_current: [16]f32, previous: [16]f32, valid: bool } {
    if (camera_count == 0) return null;
    const inverse_current = inverse(view_projection) orelse return null;
    return .{ .inverse_current = columnMajor(inverse_current), .previous = columnMajor(previous_view_projection), .valid = history_valid and camera_count == 1 };
}

/// Frame counter for temporally stratified sampling (stage.frag low-discrepancy sequences).
pub fn frameCounter() u32 {
    return frame_counter;
}

pub fn currentJitter() [2]f32 {
    return if (enabled_this_frame) jitter else .{ 0, 0 };
}

/// Registers a main (non-portal) world camera. A second camera in the same frame (split views)
/// disables reprojection for the frame.
pub fn registerView(projection: Mat4, view_matrix: Mat4, eye: [3]f32, axis_forward: [3]f32) void {
    camera_count += 1;
    if (camera_count > 1) return;
    var unjittered = projection;
    if (enabled_this_frame) {
        unjittered[0][2] += jitter[0];
        unjittered[1][2] += jitter[1];
    }
    view_projection = mul(unjittered, view_matrix);
    origin = eye;
    forward = axis_forward;
}

/// Resolves this frame's HDR world image to output resolution. Returns the sampled slot the
/// post chain and composite read. The HDR target and depth must be shader-readable.
pub fn resolve(cmd: c.VkCommandBuffer, world_drawn: bool) u32 {
    if (!world_drawn or !wanted() or camera_count == 0) {
        history_valid = false;
        return window.hdr.slot;
    }
    const next: u1 = current ^ 1;
    var reset = !history_valid or camera_count > 1 or !enabled_this_frame;
    // Camera cuts (teleports, cinematic cuts) start a fresh history.
    const moved = [3]f32{ origin[0] - previous_origin[0], origin[1] - previous_origin[1], origin[2] - previous_origin[2] };
    if (moved[0] * moved[0] + moved[1] * moved[1] + moved[2] * moved[2] > 160 * 160) reset = true;
    if (forward[0] * previous_forward[0] + forward[1] * previous_forward[1] + forward[2] * previous_forward[2] < 0.5) reset = true;
    const inverse_current = inverse(view_projection) orelse {
        history_valid = false;
        return window.hdr.slot;
    };
    const params: Params = .{
        .inverse = columnMajor(inverse_current),
        .previous = columnMajor(if (reset) view_projection else previous_view_projection),
    };
    const space = vk.frame().stream.alloc(@sizeOf(Params), 16) orelse return window.hdr.slot;
    @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
    // The previous frame's composite may still be reading the image this frame writes.
    vk.memoryBarrier(cmd, vk.stage_fragment | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT);
    const out = history[next];
    const scaled = window.render_scale < 1;
    vk.dispatch(cmd, "taa.comp", post.Push{
        .slots = .{ window.hdr.slot, history_storage[next], history_sampled[current], window.depth_slot },
        .size = .{ out.width, out.height, window.hdr.width, window.hdr.height },
        .buffer1 = space.address,
        // UV offset of the jittered samples (viewport y is flipped), blend weight, reset.
        .params = .{ jitter[0] * 0.5, -jitter[1] * 0.5, if (scaled) 0.14 else 0.1, if (reset) 1 else 0 },
    }, out.width, out.height, 1, .{ 8, 8, 1 });
    vk.computeBarrier(cmd);
    current = next;
    history_valid = enabled_this_frame;
    previous_view_projection = view_projection;
    previous_origin = origin;
    previous_forward = forward;
    return history_sampled[current];
}
