// SPDX-License-Identifier: GPL-2.0-or-later
//! Directional lightmap rebake (ray tracing tier). The original radiosity lightmaps carry no
//! direction, so normal maps could only borrow the coarse light grid's. Once a world's ray
//! tracing structures exist, each lightmap page is re-rasterised in lightmap space and every
//! texel traces shadow rays to the map's light entities in its light cell; the visible,
//! luminance-weighted direction and its directionality land in a "deluxe" page beside the
//! lightmap. Pages bake a few per frame so loading never stalls.
const std = @import("std");
const c = @import("c.zig").c;
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const world = @import("world.zig");
const rt = @import("rt.zig");
const image = @import("image.zig");

pub const page_size: u32 = 128;
const format = c.VK_FORMAT_R8G8B8A8_UNORM;

/// Mirrors bake.vert `BakeParams`.
const Params = extern struct {
    vertices: u64,
    indices: u64,
    lights: u64,
    cells: u64,
    cell_origin: [4]f32,
    cell_dims: [4]u32,
};

pub const WorldBake = struct {
    pages: []vk.Texture = &.{},
    /// Per page: first index and count in `indices`.
    ranges: [][2]u32 = &.{},
    indices: vk.Buffer = .{},
    next_page: u32 = 0,
    started: bool = false,
    done: bool = false,
};

pub fn destroyWorld(state: *WorldBake) void {
    for (state.pages) |*page| vk.destroyImage(page);
    if (state.pages.len > 0) common.gpa.free(state.pages);
    if (state.ranges.len > 0) common.gpa.free(state.ranges);
    vk.destroyBuffer(&state.indices);
    state.* = .{};
}

fn pageOf(w: *const world.World, lightmap: *const image.Image) ?u32 {
    for (w.lightmaps, 0..) |candidate, index| if (candidate == lightmap) return @intCast(index);
    return null;
}

fn lightmapOf(surface: *const world.Surface) ?*image.Image {
    for (surface.shader.stagesSlice()) |*stage| for (&stage.bundles) |*bundle| {
        if (bundle.is_lightmap) return bundle.images[0];
    };
    return null;
}

fn start(w: *world.World) bool {
    const state = &w.bake;
    state.started = true;
    if (w.lightmaps.len == 0 or w.rt.light_count == 0) {
        state.done = true;
        return false;
    }
    const a = common.gpa;
    const pages = w.lightmaps.len;
    var lists = a.alloc(std.ArrayList(u32), pages) catch return false;
    defer {
        for (lists) |*list| list.deinit(a);
        a.free(lists);
    }
    for (lists) |*list| list.* = .empty;
    for (w.surfaces) |*surface| {
        if (surface.num_indexes < 3 or surface.kind == .flare or surface.shader.is_sky) continue;
        const lightmap = lightmapOf(surface) orelse continue;
        const page = pageOf(w, lightmap) orelse continue;
        lists[page].appendSlice(a, w.indices.items[surface.first_index..][0..surface.num_indexes]) catch return false;
    }
    var all: std.ArrayList(u32) = .empty;
    defer all.deinit(a);
    state.ranges = a.alloc([2]u32, pages) catch return false;
    for (lists, 0..) |list, page| {
        state.ranges[page] = .{ @intCast(all.items.len), @intCast(list.items.len) };
        all.appendSlice(a, list.items) catch return false;
    }
    if (all.items.len == 0) {
        state.done = true;
        return false;
    }
    state.indices = vk.staticBuffer(std.mem.sliceAsBytes(all.items), 0);
    state.pages = a.alloc(vk.Texture, pages) catch return false;
    for (state.pages, 0..) |*page, index| {
        page.* = vk.createImage(page_size, page_size, 1, format, c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
        vk.bindTexture(page, .clamp);
        _ = index;
    }
    vk.flushUploads();
    return true;
}

/// Bakes the next pages of `w`; runs outside rendering after `rt.prepare` built its TLAS.
pub fn step(cmd: c.VkCommandBuffer, w: *world.World) void {
    if (!vk.ray_tracing or cvars.vkDirectionalBake.integer == 0) return;
    const state = &w.bake;
    if (state.done) return;
    if (!state.started and !start(w)) return;
    if (state.done or state.pages.len == 0) return;
    const per_frame: u32 = @intCast(std.math.clamp(cvars.vkBakePages.integer, 1, 256));
    const pipeline = vk.pipeline(.{ .src = 1, .dst = 0, .format = format, .program = vk.program_bake });
    var baked: u32 = 0;
    while (baked < per_frame and state.next_page < state.pages.len) : (baked += 1) {
        const page_index = state.next_page;
        state.next_page += 1;
        const range = state.ranges[page_index];
        const page = &state.pages[page_index];
        vk.barrier(cmd, page.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.stage_all, 0, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
        const color = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
            .imageView = page.view,
            .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
            .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
            .clearValue = c.VkClearValue{ .color = .{ .float32 = .{ 0.5, 0.5, 1, 0 } } },
        });
        const extent = c.VkExtent2D{ .width = page_size, .height = page_size };
        const info = std.mem.zeroInit(c.VkRenderingInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
            .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
            .layerCount = 1,
            .colorAttachmentCount = 1,
            .pColorAttachments = &color,
        });
        vk.d.CmdBeginRendering.?(cmd, &info);
        if (range[1] > 0) {
            const params: Params = .{
                .vertices = w.vertex_buffer.address,
                .indices = state.indices.address + @as(u64, range[0]) * 4,
                .lights = w.rt.lights.address,
                .cells = w.rt.light_cells.address,
                .cell_origin = .{ w.rt.cell_origin[0], w.rt.cell_origin[1], w.rt.cell_origin[2], rt.light_cell_size },
                .cell_dims = .{ w.rt.cell_dims[0], w.rt.cell_dims[1], w.rt.cell_dims[2], w.rt.light_count },
            };
            if (vk.frame().stream.alloc(@sizeOf(Params), 16)) |space| {
                @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
                vk.d.CmdBindPipeline.?(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
                const sets = [_]c.VkDescriptorSet{ vk.descriptor_set, vk.storage_set };
                vk.d.CmdBindDescriptorSets.?(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk.pipeline_layout, 0, 2, &sets, 0, null);
                const viewport = c.VkViewport{ .x = 0, .y = 0, .width = @floatFromInt(page_size), .height = @floatFromInt(page_size), .minDepth = 0, .maxDepth = 1 };
                const scissor = c.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = extent };
                vk.d.CmdSetViewport.?(cmd, 0, 1, &viewport);
                vk.d.CmdSetScissor.?(cmd, 0, 1, &scissor);
                vk.d.CmdSetCullMode.?(cmd, c.VK_CULL_MODE_NONE);
                vk.d.CmdSetFrontFace.?(cmd, c.VK_FRONT_FACE_COUNTER_CLOCKWISE);
                vk.d.CmdSetDepthTestEnable.?(cmd, c.VK_FALSE);
                vk.d.CmdSetDepthWriteEnable.?(cmd, c.VK_FALSE);
                vk.d.CmdSetDepthCompareOp.?(cmd, c.VK_COMPARE_OP_ALWAYS);
                vk.d.CmdSetDepthBiasEnable.?(cmd, c.VK_FALSE);
                vk.d.CmdSetDepthBias.?(cmd, 0, 0, 0);
                const push = [2]u32{ @truncate(space.address), @truncate(space.address >> 32) };
                vk.d.CmdPushConstants.?(cmd, vk.pipeline_layout, vk.all_stages, 0, 8, &push);
                vk.d.CmdDraw.?(cmd, range[1], 1, 0, 0);
            }
        }
        vk.d.CmdEndRendering.?(cmd);
        vk.barrier(cmd, page.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, vk.stage_fragment, vk.access_shader_read);
        // The page's lightmap now points its stage records at the direction page.
        w.lightmaps[page_index].deluxe_slot = page.slot + 1;
    }
    if (state.next_page >= state.pages.len) {
        state.done = true;
        common.developer("renderer_vulkan: directional lightmaps baked ({d} pages)\n", .{state.pages.len});
    }
}
