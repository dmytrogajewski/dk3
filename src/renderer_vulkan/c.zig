// SPDX-License-Identifier: GPL-2.0-or-later
//! Engine, SDL and Vulkan C declarations. No renderer-private GL header enters.
pub const c = @cImport({
    @cDefine("VK_NO_PROTOTYPES", "1");
    @cInclude("q_shared.h");
    @cInclude("qfiles.h");
    @cInclude("tr_public.h");
    @cInclude("iqm.h");
    @cInclude("dk3_inline_handles.h");
    @cInclude("vulkan/vulkan.h");
    @cInclude("SDL.h");
    @cInclude("SDL_vulkan.h");
});

/// renderercommon decoders and the resident PNG batch (tr_common.h without qgl.h).
pub const ImageBatch = opaque {};
pub extern fn R_LoadBMP(name: [*:0]const u8, pic: *?[*]u8, width: *c_int, height: *c_int) void;
pub extern fn R_LoadJPG(name: [*:0]const u8, pic: *?[*]u8, width: *c_int, height: *c_int) void;
pub extern fn R_LoadPCX(name: [*:0]const u8, pic: *?[*]u8, width: *c_int, height: *c_int) void;
pub extern fn R_LoadPNG(name: [*:0]const u8, pic: *?[*]u8, width: *c_int, height: *c_int) void;
pub extern fn R_LoadPVR(name: [*:0]const u8, pic: *?[*]u8, width: *c_int, height: *c_int) void;
pub extern fn R_LoadTGA(name: [*:0]const u8, pic: *?[*]u8, width: *c_int, height: *c_int) void;
pub extern fn R_CreateImageBatch(capacity: c_int) ?*ImageBatch;
pub extern fn R_QueuePNG(batch: ?*ImageBatch, name: [*:0]const u8) c_int;
pub extern fn R_PollImageBatch(batch: ?*ImageBatch) c_int;
pub extern fn R_SelectImageBatch(batch: ?*ImageBatch) void;
pub extern fn R_FreeImageBatch(batch: ?*ImageBatch) void;
pub extern fn RE_SaveJPG(filename: [*:0]const u8, quality: c_int, width: c_int, height: c_int, buffer: [*]u8, padding: c_int) void;
pub extern fn RE_SaveJPGToBuffer(buffer: [*]u8, size: usize, quality: c_int, width: c_int, height: c_int, image: [*]u8, padding: c_int) usize;
pub extern fn R_NoiseInit() void;
/// The client window icon (sdl/sdl_icon.h through icon.c; translate-c cannot import its literal).
pub extern fn dk3_vk_icon(width: *c_int, height: *c_int, bytes_per_pixel: *c_int) [*]const u8;
pub extern fn R_NoiseGet4f(x: f32, y: f32, z: f32, t: f64) f32;
