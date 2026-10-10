// SPDX-License-Identifier: GPL-2.0-or-later
//! SDL window, Vulkan surface and swapchain, scene targets and frame presentation.
//! The window flow ports sdl/sdl_glimp.c GLimp_Init/GLimp_SetMode with SDL_WINDOW_VULKAN.
const std = @import("std");
const c = @import("c.zig").c;
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");

pub var config: c.glconfig_t = std.mem.zeroes(c.glconfig_t);
pub var window: ?*c.SDL_Window = null;
var display_aspect: f32 = 0;

const mode_fallback = 3;

const Swapchain = struct {
    handle: c.VkSwapchainKHR = null,
    format: c.VkFormat = c.VK_FORMAT_UNDEFINED,
    extent: c.VkExtent2D = .{ .width = 0, .height = 0 },
    images: [8]c.VkImage = undefined,
    views: [8]c.VkImageView = undefined,
    finished: [8]c.VkSemaphore = undefined,
    count: u32 = 0,
    vsync: bool = false,
};
var swapchain: Swapchain = .{};

/// Classic render target; in the remaster pipeline it holds the premultiplied UI overlay.
pub var scene: vk.Texture = .{};
/// Remaster world views (RGBA16F, linear light).
pub var hdr: vk.Texture = .{};
pub var hdr_storage: u32 = 0;
/// Composite output read by captures and copied to the swapchain.
pub var final: vk.Texture = .{};
pub var depth: vk.Texture = .{};
/// Remaster world depth at the render scale (the classic overlay keeps `depth`).
pub var hdr_depth: vk.Texture = .{};
/// Remaster world resolution relative to the output (r_vkRenderScale, latched).
pub var render_scale: f32 = 1;
var readback: vk.Buffer = .{};
pub var remaster = false;
/// Remaster water: a copy of the HDR scene behind liquids and a sampled view of depth.
pub var refraction: vk.Texture = .{};
var depth_view: c.VkImageView = null;
pub var depth_slot: u32 = 0;
var depth_read_only = false;
/// The main world view's projection range and the liquid the camera is in (composite).
pub var view_near: f32 = 4;
pub var view_far: f32 = 2048;
pub var underwater: u32 = 0;
pub const hdr_format = c.VK_FORMAT_R16G16B16A16_SFLOAT;
pub const Target = enum { classic, hdr, shadow };
/// Remaster model shadow atlas (depth tiles, shadows.zig).
pub var shadow_atlas: vk.Texture = .{};
pub var shadow_slot: u32 = 0;
pub const shadow_atlas_size: u32 = 2048;
var shadow_readable = false;
var shadow_cleared = false;

fn setMode(mode: c_int, fullscreen_requested: bool, noborder: bool) bool {
    // High-DPI aware: the drawable, and so the scene, is in the display's physical pixels.
    var flags: u32 = c.SDL_WINDOW_HIDDEN | c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_ALLOW_HIGHDPI;
    if (cvars.allowResize.integer != 0) flags |= c.SDL_WINDOW_RESIZABLE;
    var display: c_int = 0;
    var x: c_int = c.SDL_WINDOWPOS_UNDEFINED_MASK;
    var y: c_int = c.SDL_WINDOWPOS_UNDEFINED_MASK;
    if (window) |existing| {
        display = c.SDL_GetWindowDisplayIndex(existing);
        if (display < 0) display = 0;
    }
    var desktop: c.SDL_DisplayMode = std.mem.zeroes(c.SDL_DisplayMode);
    if (c.SDL_GetDesktopDisplayMode(display, &desktop) == 0) {
        display_aspect = @as(f32, @floatFromInt(desktop.w)) / @as(f32, @floatFromInt(desktop.h));
        common.info("Display aspect: {d:.3}\n", .{display_aspect});
    } else {
        desktop = std.mem.zeroes(c.SDL_DisplayMode);
        common.info("Cannot determine display aspect, assuming 1.333\n", .{});
    }
    common.info("...setting mode {d}:", .{mode});
    if (mode == -2) {
        if (desktop.h > 0) {
            config.vidWidth = desktop.w;
            config.vidHeight = desktop.h;
        } else {
            config.vidWidth = 640;
            config.vidHeight = 480;
            common.info("Cannot determine display resolution, assuming 640x480\n", .{});
        }
        config.windowAspect = @as(f32, @floatFromInt(config.vidWidth)) / @as(f32, @floatFromInt(config.vidHeight));
    } else if (!cvars.modeInfo(&config.vidWidth, &config.vidHeight, &config.windowAspect, mode)) {
        common.info(" invalid mode\n", .{});
        return false;
    }
    common.info(" {d} {d}\n", .{ config.vidWidth, config.vidHeight });
    if (cvars.centerWindow.integer != 0 and !fullscreen_requested) {
        x = @divTrunc(desktop.w, 2) - @divTrunc(config.vidWidth, 2);
        y = @divTrunc(desktop.h, 2) - @divTrunc(config.vidHeight, 2);
    }
    if (window) |existing| {
        c.SDL_GetWindowPosition(existing, &x, &y);
        c.SDL_DestroyWindow(existing);
        window = null;
    }
    if (fullscreen_requested) {
        // Native mode (r_mode -2): borderless fullscreen at the desktop resolution, no mode switch.
        flags |= if (mode == -2) c.SDL_WINDOW_FULLSCREEN_DESKTOP else c.SDL_WINDOW_FULLSCREEN;
        config.isFullscreen = c.qtrue;
    } else {
        if (noborder) flags |= c.SDL_WINDOW_BORDERLESS;
        config.isFullscreen = c.qfalse;
    }
    window = c.SDL_CreateWindow(c.CLIENT_WINDOW_TITLE, x, y, config.vidWidth, config.vidHeight, flags) orelse {
        common.developer("SDL_CreateWindow failed: {s}\n", .{common.span(c.SDL_GetError())});
        return false;
    };
    var icon_width: c_int = 0;
    var icon_height: c_int = 0;
    var icon_bytes: c_int = 0;
    const pixels = @import("c.zig").dk3_vk_icon(&icon_width, &icon_height, &icon_bytes);
    const icon = c.SDL_CreateRGBSurfaceFrom(@ptrCast(@constCast(pixels)), icon_width, icon_height, icon_bytes * 8, icon_bytes * icon_width, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
    if (icon) |surface| {
        c.SDL_SetWindowIcon(window, surface);
        c.SDL_FreeSurface(surface);
    }
    if (fullscreen_requested) {
        var window_mode: c.SDL_DisplayMode = undefined;
        switch (cvars.mode.integer) {
            -2 => {},
            else => if (c.SDL_GetWindowDisplayMode(window, &window_mode) == 0) {
                window_mode.w = config.vidWidth;
                window_mode.h = config.vidHeight;
                _ = c.SDL_SetWindowDisplayMode(window, &window_mode);
            },
        }
    }
    c.SDL_ShowWindow(window);
    // The drawable is what the swapchain covers; a window manager may not grant the mode asked for.
    var drawable_width: c_int = 0;
    var drawable_height: c_int = 0;
    c.SDL_Vulkan_GetDrawableSize(window, &drawable_width, &drawable_height);
    if (drawable_width > 0 and drawable_height > 0) {
        if (drawable_width != config.vidWidth or drawable_height != config.vidHeight)
            common.info("Drawable is {d} {d}, not the {d} {d} asked for\n", .{ drawable_width, drawable_height, config.vidWidth, config.vidHeight });
        config.vidWidth = drawable_width;
        config.vidHeight = drawable_height;
        config.windowAspect = @as(f32, @floatFromInt(drawable_width)) / @as(f32, @floatFromInt(drawable_height));
    }
    common.info("Vulkan drawable: {d} {d}{s}\n", .{ config.vidWidth, config.vidHeight, if (mode == -2) " (native)" else "" });
    return true;
}

fn startDriverAndSetMode(mode: c_int, fullscreen_requested: bool, noborder: bool) bool {
    var fullscreen = fullscreen_requested;
    if (c.SDL_WasInit(c.SDL_INIT_VIDEO) == 0) {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            common.info("SDL_Init( SDL_INIT_VIDEO ) FAILED ({s})\n", .{common.span(c.SDL_GetError())});
            return false;
        }
        const driver = c.SDL_GetCurrentVideoDriver();
        common.info("SDL using driver \"{s}\"\n", .{common.span(driver)});
        common.ri.Cvar_Set.?("r_sdlDriver", driver);
    }
    if (fullscreen and common.ri.Cvar_VariableIntegerValue.?("in_nograb") != 0) {
        common.info("Fullscreen not allowed with in_nograb 1\n", .{});
        common.ri.Cvar_Set.?("r_fullscreen", "0");
        cvars.fullscreen.modified = c.qfalse;
        fullscreen = false;
    }
    if (!setMode(mode, fullscreen, noborder)) {
        common.info("...WARNING: could not set the given mode ({d})\n", .{mode});
        return false;
    }
    return true;
}

/// Software rendering was requested for this process (dkguard --headless sets it for GL).
fn preferCpu() bool {
    const value = std.c.getenv("LIBGL_ALWAYS_SOFTWARE") orelse return false;
    return value[0] != 0 and value[0] != '0';
}

/// Window, instance, device, frames and targets. Fatal on failure, like GLimp_Init.
pub fn init() void {
    _ = common.cvar("r_sdlDriver", "", c.CVAR_ROM);
    if (common.ri.Cvar_VariableIntegerValue.?("com_abnormalExit") != 0) {
        common.ri.Cvar_Set.?("r_mode", "3");
        common.ri.Cvar_Set.?("r_fullscreen", "0");
        common.ri.Cvar_Set.?("r_centerWindow", "0");
        common.ri.Cvar_Set.?("com_abnormalExit", "0");
    }
    common.ri.Sys_GLimpInit.?();
    const opened = startDriverAndSetMode(cvars.mode.integer, cvars.fullscreen.integer != 0, cvars.noborder.integer != 0) or blk: {
        common.ri.Sys_GLimpSafeInit.?();
        break :blk startDriverAndSetMode(cvars.mode.integer, cvars.fullscreen.integer != 0, false);
    } or (cvars.mode.integer != mode_fallback and blk: {
        common.info("Setting r_mode {d} failed, falling back on r_mode {d}\n", .{ cvars.mode.integer, mode_fallback });
        break :blk startDriverAndSetMode(mode_fallback, false, false);
    });
    if (!opened) common.fail(c.ERR_FATAL, "VKimp_Init() - could not create a Vulkan window", .{});

    vk.loadLibrary() catch common.fail(c.ERR_FATAL, "VKimp_Init() - no Vulkan loader", .{});
    vk.createInstance(window, cvars.vkValidation.integer != 0) catch common.fail(c.ERR_FATAL, "VKimp_Init() - cannot create a Vulkan 1.3 instance", .{});
    if (c.SDL_Vulkan_CreateSurface(window, @ptrCast(vk.s.instance), @ptrCast(&vk.s.surface)) == 0)
        common.fail(c.ERR_FATAL, "SDL_Vulkan_CreateSurface: {s}", .{common.span(c.SDL_GetError())});
    const candidate = vk.pickDevice(true, cvars.vkDevice.integer, preferCpu()) catch
        common.fail(c.ERR_FATAL, "VKimp_Init() - no Vulkan 1.3 device can present to this window", .{});
    vk.createDevice(candidate, cvars.vkRayTracing.integer != 0) catch common.fail(c.ERR_FATAL, "VKimp_Init() - cannot create the Vulkan device", .{});
    vk.createFrames();
    vk.createSamplers(@min(vk.s.properties.limits.maxSamplerAnisotropy, 8));
    vk.createBindless();
    vk.createModules();
    @import("rt.zig").init();
    createSwapchain();
    createTargets();
    vk.persistent_slots = vk.next_slot;
    vk.persistent_volume_slots = vk.next_volume_slot;
    vk.content_arena = true;
    fillConfig();
    reportDevice();
    _ = common.cvar("r_availableModes", "", c.CVAR_ROM);
    common.ri.IN_Init.?(window);
}

fn fillConfig() void {
    config.driverType = c.GLDRV_ICD;
    config.hardwareType = c.GLHW_GENERIC;
    config.deviceSupportsGamma = c.qfalse;
    config.textureCompression = c.TC_NONE;
    config.textureEnvAddAvailable = c.qtrue;
    config.numTextureUnits = 8;
    config.colorBits = 24;
    config.depthBits = if (vk.s.depth_format == c.VK_FORMAT_D16_UNORM) 16 else 24;
    config.stencilBits = 0;
    config.maxTextureSize = @intCast(vk.s.properties.limits.maxImageDimension2D);
    config.stereoEnabled = c.qfalse;
    config.smpActive = c.qfalse;
    _ = std.fmt.bufPrintZ(&config.renderer_string, "{s}", .{common.span(&vk.s.properties.deviceName)}) catch {};
    _ = std.fmt.bufPrintZ(&config.vendor_string, "{s} {s}", .{ common.span(&vk.s.driver.driverName), common.span(&vk.s.driver.driverInfo) }) catch {};
    const version = vk.s.properties.apiVersion;
    _ = std.fmt.bufPrintZ(&config.version_string, "Vulkan {d}.{d}.{d}", .{ c.VK_API_VERSION_MAJOR(version), c.VK_API_VERSION_MINOR(version), c.VK_API_VERSION_PATCH(version) }) catch {};
    var writer = std.Io.Writer.fixed(config.extensions_string[0 .. config.extensions_string.len - 1]);
    for (vk.s.extensions[0..vk.s.extension_count], 0..) |name, index| {
        writer.print("{s}{s}", .{ if (index > 0) " " else "", std.mem.span(name) }) catch break;
    }
    config.extensions_string[writer.end] = 0;
    var mode: c.SDL_DisplayMode = undefined;
    config.displayFrequency = if (c.SDL_GetWindowDisplayMode(window, &mode) == 0) mode.refresh_rate else 60;
}

pub fn reportDevice() void {
    const caps = vk.s.capabilities;
    common.info("VK_RENDERER: {s}\n", .{common.span(&config.renderer_string)});
    common.info("VK_DRIVER: {s}\n", .{common.span(&config.vendor_string)});
    common.info("VK_VERSION: {s}\n", .{common.span(&config.version_string)});
    common.info("VK_RAYTRACING: acceleration_structure={d} ray_query={d} ray_tracing_pipeline={d} enabled=0\n", .{ @intFromBool(caps.acceleration_structure), @intFromBool(caps.ray_query), @intFromBool(caps.ray_tracing_pipeline) });
    common.info("VK_OPTIONAL: shader_object={d} fragment_shading_rate={d} descriptor_heap={d}\n", .{ @intFromBool(caps.shader_object), @intFromBool(caps.fragment_shading_rate), @intFromBool(caps.descriptor_heap) });
    common.info("VK_TARGET: {d}x{d} swapchain={d}x{d} images={d} depth={d}\n", .{ config.vidWidth, config.vidHeight, swapchain.extent.width, swapchain.extent.height, swapchain.count, vk.s.depth_format });
}

fn createSwapchain() void {
    const device = vk.s.device;
    var capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
    vk.must(vk.i.GetPhysicalDeviceSurfaceCapabilitiesKHR.?(vk.s.physical, vk.s.surface, &capabilities), "vkGetPhysicalDeviceSurfaceCapabilitiesKHR");
    var format_count: u32 = 0;
    _ = vk.i.GetPhysicalDeviceSurfaceFormatsKHR.?(vk.s.physical, vk.s.surface, &format_count, null);
    var formats: [64]c.VkSurfaceFormatKHR = undefined;
    format_count = @min(format_count, formats.len);
    _ = vk.i.GetPhysicalDeviceSurfaceFormatsKHR.?(vk.s.physical, vk.s.surface, &format_count, &formats);
    var chosen = formats[0];
    for (formats[0..format_count]) |format| {
        if ((format.format == c.VK_FORMAT_B8G8R8A8_UNORM or format.format == c.VK_FORMAT_R8G8B8A8_UNORM) and format.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            chosen = format;
            break;
        }
    }
    var mode_count: u32 = 0;
    _ = vk.i.GetPhysicalDeviceSurfacePresentModesKHR.?(vk.s.physical, vk.s.surface, &mode_count, null);
    var modes: [16]c.VkPresentModeKHR = undefined;
    mode_count = @min(mode_count, modes.len);
    _ = vk.i.GetPhysicalDeviceSurfacePresentModesKHR.?(vk.s.physical, vk.s.surface, &mode_count, &modes);
    const vsync = cvars.swapInterval.integer != 0;
    var present_mode: c.VkPresentModeKHR = c.VK_PRESENT_MODE_FIFO_KHR;
    if (!vsync) for ([_]c.VkPresentModeKHR{ c.VK_PRESENT_MODE_MAILBOX_KHR, c.VK_PRESENT_MODE_IMMEDIATE_KHR }) |wanted| {
        if (std.mem.indexOfScalar(c.VkPresentModeKHR, modes[0..mode_count], wanted) != null) {
            present_mode = wanted;
            break;
        }
    };
    var extent = capabilities.currentExtent;
    if (extent.width == std.math.maxInt(u32)) {
        var w: c_int = 0;
        var h: c_int = 0;
        c.SDL_Vulkan_GetDrawableSize(window, &w, &h);
        extent = .{ .width = @intCast(@max(w, 1)), .height = @intCast(@max(h, 1)) };
    }
    extent.width = std.math.clamp(extent.width, capabilities.minImageExtent.width, @max(capabilities.maxImageExtent.width, capabilities.minImageExtent.width));
    extent.height = std.math.clamp(extent.height, capabilities.minImageExtent.height, @max(capabilities.maxImageExtent.height, capabilities.minImageExtent.height));
    var image_count = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0) image_count = @min(image_count, capabilities.maxImageCount);
    image_count = @min(image_count, 8);
    const old = swapchain.handle;
    const alpha_flags: u32 = capabilities.supportedCompositeAlpha;
    const composite_alpha: u32 = if (alpha_flags & c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR != 0) c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR else alpha_flags & (~alpha_flags +% 1);
    const info = std.mem.zeroInit(c.VkSwapchainCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = vk.s.surface,
        .minImageCount = image_count,
        .imageFormat = chosen.format,
        .imageColorSpace = chosen.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = capabilities.currentTransform,
        .compositeAlpha = @as(c.VkCompositeAlphaFlagBitsKHR, @intCast(composite_alpha)),
        .presentMode = present_mode,
        .clipped = c.VK_TRUE,
        .oldSwapchain = old,
    });
    var handle: c.VkSwapchainKHR = null;
    vk.must(vk.d.CreateSwapchainKHR.?(device, &info, null, &handle), "vkCreateSwapchainKHR");
    if (old != null) destroySwapchainViews(old);
    swapchain.handle = handle;
    swapchain.format = chosen.format;
    swapchain.extent = extent;
    swapchain.vsync = vsync;
    var count: u32 = 0;
    _ = vk.d.GetSwapchainImagesKHR.?(device, handle, &count, null);
    count = @min(count, 8);
    vk.must(vk.d.GetSwapchainImagesKHR.?(device, handle, &count, &swapchain.images), "vkGetSwapchainImagesKHR");
    swapchain.count = count;
    const binary = std.mem.zeroInit(c.VkSemaphoreCreateInfo, .{ .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO });
    for (0..count) |index| {
        const view_info = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = swapchain.images[index],
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = chosen.format,
            .subresourceRange = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        });
        vk.must(vk.d.CreateImageView.?(device, &view_info, null, &swapchain.views[index]), "vkCreateImageView");
        vk.must(vk.d.CreateSemaphore.?(device, &binary, null, &swapchain.finished[index]), "vkCreateSemaphore");
    }
}

fn destroySwapchainViews(handle: c.VkSwapchainKHR) void {
    vk.waitIdle();
    for (0..swapchain.count) |index| {
        vk.d.DestroyImageView.?(vk.s.device, swapchain.views[index], null);
        vk.d.DestroySemaphore.?(vk.s.device, swapchain.finished[index], null);
    }
    swapchain.count = 0;
    vk.d.DestroySwapchainKHR.?(vk.s.device, handle, null);
}

fn recreateSwapchain() void {
    var w: c_int = 0;
    var h: c_int = 0;
    c.SDL_Vulkan_GetDrawableSize(window, &w, &h);
    if (w <= 0 or h <= 0) return;
    vk.waitIdle();
    createSwapchain();
}

fn createTargets() void {
    const width: u32 = @intCast(config.vidWidth);
    const height: u32 = @intCast(config.vidHeight);
    remaster = cvars.vkRemaster.integer != 0;
    scene = vk.createImage(width, height, 1, vk.scene_format, c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
    vk.bindTexture(&scene, .nearest_clamp);
    final = vk.createImage(width, height, 1, vk.scene_format, c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
    vk.bindTexture(&final, .clamp);
    render_scale = if (remaster) std.math.clamp(cvars.vkRenderScale.value, 0.33, 1) else 1;
    const hdr_width: u32 = @max(@as(u32, @intFromFloat(@round(@as(f32, @floatFromInt(width)) * render_scale))), 1);
    const hdr_height: u32 = @max(@as(u32, @intFromFloat(@round(@as(f32, @floatFromInt(height)) * render_scale))), 1);
    if (remaster) {
        hdr = vk.createImage(hdr_width, hdr_height, 1, hdr_format, c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_STORAGE_BIT | c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
        vk.bindTexture(&hdr, .clamp);
        hdr_storage = vk.bindStorage(hdr.view);
        @import("post.zig").create(width, height);
        @import("volume.zig").create();
        @import("taa.zig").create(width, height);
        @import("clusters.zig").create();
        @import("ddgi.zig").create();
        @import("pathtrace.zig").create(hdr_width, hdr_height);
        shadow_atlas = vk.createImage(shadow_atlas_size, shadow_atlas_size, 1, vk.s.depth_format, c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT, c.VK_IMAGE_ASPECT_DEPTH_BIT);
        shadow_slot = vk.bindView(shadow_atlas.view, .nearest_clamp, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL);
        refraction = vk.createImage(hdr_width, hdr_height, 1, hdr_format, c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
        vk.bindTexture(&refraction, .clamp);
    }
    depth = vk.createImage(width, height, 1, vk.s.depth_format, c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT, c.VK_IMAGE_ASPECT_DEPTH_BIT);
    if (remaster) {
        hdr_depth = vk.createImage(hdr_width, hdr_height, 1, vk.s.depth_format, c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT, c.VK_IMAGE_ASPECT_DEPTH_BIT);
        const view_info = std.mem.zeroInit(c.VkImageViewCreateInfo, .{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .image = hdr_depth.image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = vk.s.depth_format,
            .subresourceRange = .{ .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT, .baseMipLevel = 0, .levelCount = 1, .baseArrayLayer = 0, .layerCount = 1 },
        });
        vk.must(vk.d.CreateImageView.?(vk.s.device, &view_info, null, &depth_view), "vkCreateImageView");
        depth_slot = vk.bindView(depth_view, .nearest_clamp, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL);
    }
    readback = vk.createBuffer(@as(u64, width) * height * 4, c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, vk.host_flags);
}

/// Releases everything this module created. `destroy_window` also closes SDL video.
pub fn shutdown(destroy_window: bool) void {
    if (vk.s.device != null) {
        vk.waitIdle();
        vk.content_arena = false;
        vk.destroyImage(&scene);
        vk.destroyImage(&final);
        if (remaster) {
            vk.destroyImage(&hdr);
            vk.destroyImage(&refraction);
            if (depth_view != null) vk.d.DestroyImageView.?(vk.s.device, depth_view, null);
            depth_view = null;
            @import("post.zig").destroy();
            @import("volume.zig").destroy();
            @import("taa.zig").destroy();
            @import("clusters.zig").destroy();
            @import("ddgi.zig").destroy();
            @import("pathtrace.zig").destroy();
            vk.destroyImage(&shadow_atlas);
            vk.destroyImage(&hdr_depth);
        }
        vk.destroyImage(&depth);
        vk.destroyBuffer(&readback);
        if (swapchain.handle != null) destroySwapchainViews(swapchain.handle);
        swapchain = .{};
        vk.destroyPipelines();
        @import("rt.zig").shutdown();
        vk.destroyBindless();
        vk.destroyFrames();
        vk.freeMemory();
        vk.destroyDevice();
    }
    vk.destroyInstance();
    if (destroy_window) {
        common.ri.IN_Shutdown.?();
        if (window) |w| c.SDL_DestroyWindow(w);
        window = null;
        c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        config = std.mem.zeroes(c.glconfig_t);
    }
}

// ---------------------------------------------------------------------------------------------
// Frame recording

pub var cmd: c.VkCommandBuffer = null;
pub var recording = false;
var rendering = false;
var current_target: Target = .classic;
var hdr_cleared = false;
/// Output-resolution HDR image the composite reads (TAA history or the HDR target itself).
var resolved_slot: u32 = 0;
pub var hdr_used = false;

/// Starts recording the frame's draw commands; true when a new command buffer began.
pub fn beginFrame() bool {
    if (recording) return false;
    cmd = vk.beginDraw();
    recording = true;
    const color_access = c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT;
    vk.barrier(cmd, scene.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.stage_all, 0, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, color_access);
    if (remaster) {
        vk.barrier(cmd, hdr.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.stage_all, 0, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, color_access);
        vk.barrier(cmd, hdr_depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, vk.stage_all, 0, c.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT);
        @import("taa.zig").beginFrame();
    }
    shadow_readable = false;
    shadow_cleared = false;
    vk.barrier(cmd, depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, vk.stage_all, 0, c.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT);
    current_target = .classic;
    hdr_cleared = false;
    hdr_used = false;
    beginRendering(true);
    return true;
}

/// Switches the colour attachment (the depth buffer is shared); the first use of the HDR
/// target in a frame clears it.
pub fn useTarget(target: Target) void {
    if (target == .hdr) hdr_used = true;
    if (target == current_target and rendering) return;
    endLiquids();
    suspendRendering();
    if (target == .shadow) {
        const depth_access = c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT;
        const old: c.VkImageLayout = if (shadow_cleared) c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL else c.VK_IMAGE_LAYOUT_UNDEFINED;
        vk.barrier(cmd, shadow_atlas.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, old, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, vk.stage_fragment | depth_stages, vk.access_shader_read, depth_stages, depth_access);
        current_target = .shadow;
        const clear = !shadow_cleared;
        shadow_cleared = true;
        shadow_readable = false;
        beginRenderingColor(false, clear);
        return;
    }
    current_target = target;
    const clear = target == .hdr and !hdr_cleared;
    if (target == .hdr) hdr_cleared = true;
    beginRenderingColor(clear, clear);
}

pub fn targetFormat() c.VkFormat {
    return switch (current_target) {
        .hdr => hdr_format,
        .classic => vk.scene_format,
        .shadow => c.VK_FORMAT_UNDEFINED,
    };
}

/// Ends shadow tile rendering and makes the atlas shader-readable for this frame's views.
pub fn finishShadows() void {
    if (current_target != .shadow) return;
    suspendRendering();
    vk.barrier(cmd, shadow_atlas.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL, depth_stages, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, vk.stage_fragment, vk.access_shader_read);
    shadow_readable = true;
    current_target = .classic;
}

pub fn currentTarget() Target {
    return current_target;
}

/// Pixel scale from view (output) coordinates to the current target.
pub fn targetScale() f32 {
    return if (current_target == .hdr) render_scale else 1;
}

pub fn targetExtent() [2]u32 {
    return switch (current_target) {
        .hdr => .{ hdr.width, hdr.height },
        .classic => .{ scene.width, scene.height },
        .shadow => .{ shadow_atlas_size, shadow_atlas_size },
    };
}

fn targetDepth() *const vk.Texture {
    return switch (current_target) {
        .hdr => &hdr_depth,
        .classic => &depth,
        .shadow => &shadow_atlas,
    };
}

fn beginRendering(clear: bool) void {
    beginRenderingColor(clear, clear);
}

fn beginRenderingColor(clear: bool, clear_depth: bool) void {
    const target = if (current_target == .hdr) &hdr else &scene;
    const extent = targetExtent();
    // The remaster UI overlay starts transparent; the classic frame starts black.
    const clear_alpha: f32 = if (remaster and current_target == .classic) 0 else 1;
    const color = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = target.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = if (clear) @as(c.VkAttachmentLoadOp, c.VK_ATTACHMENT_LOAD_OP_CLEAR) else c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = c.VkClearValue{ .color = .{ .float32 = .{ 0, 0, 0, clear_alpha } } },
    });
    const depth_attachment = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = targetDepth().view,
        .imageLayout = @as(c.VkImageLayout, if (depth_read_only) c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL else c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL),
        .loadOp = if (clear_depth) @as(c.VkAttachmentLoadOp, c.VK_ATTACHMENT_LOAD_OP_CLEAR) else c.VK_ATTACHMENT_LOAD_OP_LOAD,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .clearValue = c.VkClearValue{ .depthStencil = .{ .depth = 1, .stencil = 0 } },
    });
    const info = std.mem.zeroInit(c.VkRenderingInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = .{ .width = extent[0], .height = extent[1] } },
        .layerCount = 1,
        .colorAttachmentCount = @as(u32, if (current_target == .shadow) 0 else 1),
        .pColorAttachments = &color,
        .pDepthAttachment = &depth_attachment,
    });
    vk.d.CmdBeginRendering.?(cmd, &info);
    rendering = true;
    bindCommon();
}

/// Rebinds the bindless sets; pipelines are bound per draw.
pub fn bindCommon() void {
    const sets = [_]c.VkDescriptorSet{ vk.descriptor_set, vk.storage_set };
    vk.d.CmdBindDescriptorSets.?(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk.pipeline_layout, 0, 2, &sets, 0, null);
}

/// Ends scene rendering for work that cannot run inside it (readback). Resume with `resume`.
pub fn suspendRendering() void {
    if (!rendering) return;
    vk.d.CmdEndRendering.?(cmd);
    rendering = false;
}

pub fn resumeRendering() void {
    if (rendering) return;
    beginRenderingColor(false, false);
}

pub const Capture = struct {
    buffer: vk.Buffer,
    width: u32,
    height: u32,
};

const depth_stages = c.VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | c.VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT;

/// Before the first liquid of an HDR view: copy the scene for refraction and make depth
/// read-only so liquids can sample it while still depth testing.
pub fn beginLiquids() void {
    if (!remaster or depth_read_only or current_target != .hdr) return;
    suspendRendering();
    vk.barrier(cmd, hdr.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, vk.stage_copy, vk.access_transfer_read);
    vk.barrier(cmd, refraction.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, vk.stage_all, 0, vk.stage_copy, vk.access_transfer_write);
    const region = std.mem.zeroInit(c.VkImageCopy, .{
        .srcSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .dstSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .extent = .{ .width = hdr.width, .height = hdr.height, .depth = 1 },
    });
    vk.d.CmdCopyImage.?(cmd, hdr.image, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, refraction.image, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
    vk.barrier(cmd, hdr.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.stage_copy, vk.access_transfer_read, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT);
    vk.barrier(cmd, refraction.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.stage_copy, vk.access_transfer_write, vk.stage_fragment, vk.access_shader_read);
    vk.barrier(cmd, hdr_depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL, depth_stages, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, depth_stages | vk.stage_fragment, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk.access_shader_read);
    depth_read_only = true;
    beginRenderingColor(false, false);
}

/// Makes depth writable again (a later stage writes depth, or the view ends).
pub fn endLiquids() void {
    if (!depth_read_only) return;
    suspendRendering();
    vk.barrier(cmd, hdr_depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, depth_stages | vk.stage_fragment, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | vk.access_shader_read, depth_stages, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT);
    depth_read_only = false;
    beginRenderingColor(false, false);
}

/// Hands the HDR target and its depth to compute passes in the middle of a world view.
pub fn hdrToCompute() void {
    suspendRendering();
    vk.barrier(cmd, hdr.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, vk.access_shader_read | c.VK_ACCESS_2_SHADER_WRITE_BIT);
    vk.barrier(cmd, hdr_depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL, depth_stages, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, vk.access_shader_read);
}

pub fn hdrFromCompute() void {
    vk.barrier(cmd, hdr.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_GENERAL, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT);
    vk.barrier(cmd, hdr_depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, vk.access_shader_read, depth_stages, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT | c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT);
    resumeRendering();
}

pub fn depthReadOnly() bool {
    return depth_read_only;
}

/// Set before `endFrame`: the composited frame is copied to the readback buffer.
pub var capture_requested = false;

fn copyFinal() Capture {
    const width = final.width;
    const height = final.height;
    vk.barrier(cmd, final.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, vk.stage_fragment, vk.access_shader_read, vk.stage_copy, vk.access_transfer_read);
    const region = std.mem.zeroInit(c.VkBufferImageCopy, .{
        .imageSubresource = .{ .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT, .mipLevel = 0, .baseArrayLayer = 0, .layerCount = 1 },
        .imageExtent = .{ .width = width, .height = height, .depth = 1 },
    });
    vk.d.CmdCopyImageToBuffer.?(cmd, final.image, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, readback.buffer, 1, &region);
    vk.barrier(cmd, final.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, vk.stage_copy, vk.access_transfer_read, vk.stage_fragment, vk.access_shader_read);
    vk.memoryBarrier(cmd, vk.stage_copy, vk.access_transfer_write, c.VK_PIPELINE_STAGE_2_HOST_BIT, c.VK_ACCESS_2_HOST_READ_BIT);
    return .{ .buffer = readback, .width = width, .height = height };
}

pub var last_capture: ?Capture = null;

/// Composites to the swapchain, submits and presents. Returns the submission's timeline value.
pub fn endFrame() u64 {
    if (!recording) _ = beginFrame();
    if (remaster and !hdr_used) {
        // Menus without a world view: the scene behind the UI is black.
        useTarget(.hdr);
        hdr_used = false;
    }
    endLiquids();
    suspendRendering();
    if (remaster) vk.barrier(cmd, hdr_depth.image, c.VK_IMAGE_ASPECT_DEPTH_BIT, c.VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_DEPTH_READ_ONLY_OPTIMAL, depth_stages, c.VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT, vk.stage_fragment | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, vk.access_shader_read);
    const read_stages = vk.stage_fragment | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT;
    vk.barrier(cmd, scene.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, read_stages, vk.access_shader_read);
    if (remaster) {
        vk.barrier(cmd, hdr.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, read_stages, vk.access_shader_read);
        // Temporal resolve (and upscale) to the output resolution, then exposure and bloom.
        resolved_slot = @import("taa.zig").resolve(cmd, hdr_used);
        @import("post.zig").run(cmd, resolved_slot, final.width, final.height);
    }
    compositeFinal();
    last_capture = if (capture_requested) copyFinal() else null;
    capture_requested = false;

    var present: vk.Present = .{};
    var image_index: u32 = 0;
    var acquired = false;
    if (swapchain.handle != null and (c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_MINIMIZED) == 0) {
        const semaphore = vk.frame().acquired;
        const result = vk.d.AcquireNextImageKHR.?(vk.s.device, swapchain.handle, std.math.maxInt(u64), semaphore, null, &image_index);
        if (result == c.VK_SUCCESS or result == c.VK_SUBOPTIMAL_KHR) {
            acquired = true;
            present = .{ .wait = semaphore, .signal = swapchain.finished[image_index] };
        } else if (result != c.VK_ERROR_OUT_OF_DATE_KHR) vk.must(result, "vkAcquireNextImageKHR");
    }
    if (acquired) composite(image_index);
    recording = false;
    const value = vk.submitFrame(present);
    if (acquired) {
        const info = std.mem.zeroInit(c.VkPresentInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1,
            .pWaitSemaphores = &present.signal,
            .swapchainCount = 1,
            .pSwapchains = &swapchain.handle,
            .pImageIndices = &image_index,
        });
        const result = vk.d.QueuePresentKHR.?(vk.s.queue, &info);
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR or result == c.VK_SUBOPTIMAL_KHR) recreateSwapchain() else vk.must(result, "vkQueuePresentKHR");
    } else if (swapchain.handle != null) {
        var w: c_int = 0;
        var h: c_int = 0;
        c.SDL_Vulkan_GetDrawableSize(window, &w, &h);
        if (w > 0 and h > 0 and (@as(u32, @intCast(w)) != swapchain.extent.width or @as(u32, @intCast(h)) != swapchain.extent.height)) recreateSwapchain();
    }
    if ((cvars.swapInterval.integer != 0) != swapchain.vsync) recreateSwapchain();
    toggleFullscreen();
    followDrawable();
    return value;
}

fn setFullscreenState(extent: c.VkExtent2D) void {
    const viewport = c.VkViewport{ .x = 0, .y = 0, .width = @floatFromInt(extent.width), .height = @floatFromInt(extent.height), .minDepth = 0, .maxDepth = 1 };
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
}

/// Scene (classic) or tone-mapped HDR plus UI overlay (remaster) into `final`.
fn compositeFinal() void {
    vk.barrier(cmd, final.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, vk.stage_all, 0, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    const color = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = final.view,
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
    });
    const extent = c.VkExtent2D{ .width = final.width, .height = final.height };
    const info = std.mem.zeroInit(c.VkRenderingInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = extent },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
    });
    vk.d.CmdBeginRendering.?(cmd, &info);
    vk.d.CmdBindPipeline.?(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk.pipeline(.{ .src = 1, .dst = 0, .format = vk.scene_format, .program = vk.program_composite }));
    bindCommon();
    setFullscreenState(extent);
    const post = @import("post.zig");
    var push: post.Push = .{ .slots = .{ scene.slot, 0, 0, 0 } };
    if (remaster) {
        const gamma = if (cvars.gamma.value > 0) cvars.gamma.value else 1;
        push = .{
            .slots = .{ scene.slot, resolved_slot, if (hdr_used) post.bloomSlot() else 0, 1 },
            .size = .{ depth_slot, if (hdr_used) underwater else 0, if (cvars.vkTonemap.integer == 1) 1 else 0, 0 },
            .buffer1 = post.exposure.address,
            .params = .{ cvars.vkBloom.value, 1.0 / gamma, cvars.vkSaturation.value, @as(f32, @floatFromInt(common.milliseconds())) * 0.001 },
            .params2 = .{ view_near, view_far, 0, 0 },
            .params3 = .{ if (hdr_used) cvars.vkSharpen.value else 0, 1.0 / @as(f32, @floatFromInt(final.width)), 1.0 / @as(f32, @floatFromInt(final.height)), 0 },
        };
    }
    vk.d.CmdPushConstants.?(cmd, vk.pipeline_layout, vk.all_stages, 0, @sizeOf(post.Push), &push);
    vk.d.CmdDraw.?(cmd, 3, 1, 0, 0);
    vk.d.CmdEndRendering.?(cmd);
    vk.barrier(cmd, final.image, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, vk.stage_fragment, vk.access_shader_read);
}

fn composite(image_index: u32) void {
    const target = swapchain.images[image_index];
    vk.barrier(cmd, target, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    const color = std.mem.zeroInit(c.VkRenderingAttachmentInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO,
        .imageView = swapchain.views[image_index],
        .imageLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
    });
    const info = std.mem.zeroInit(c.VkRenderingInfo, .{
        .sType = c.VK_STRUCTURE_TYPE_RENDERING_INFO,
        .renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = swapchain.extent },
        .layerCount = 1,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color,
    });
    vk.d.CmdBeginRendering.?(cmd, &info);
    vk.d.CmdBindPipeline.?(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, vk.pipeline(.{ .src = 1, .dst = 0, .format = swapchain.format, .program = vk.program_composite }));
    bindCommon();
    setFullscreenState(swapchain.extent);
    const post = @import("post.zig");
    const push: post.Push = .{ .slots = .{ final.slot, 0, 0, 0 } };
    vk.d.CmdPushConstants.?(cmd, vk.pipeline_layout, vk.all_stages, 0, @sizeOf(post.Push), &push);
    vk.d.CmdDraw.?(cmd, 3, 1, 0, 0);
    vk.d.CmdEndRendering.?(cmd);
    vk.barrier(cmd, target, c.VK_IMAGE_ASPECT_COLOR_BIT, c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, c.VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, c.VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT, c.VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT, 0);
}

/// `GLimp_EndFrame`'s fullscreen toggle (sdl_glimp.c:1216-1246).
fn toggleFullscreen() void {
    if (cvars.fullscreen.modified == 0) return;
    const fullscreen = (c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_FULLSCREEN) != 0;
    if (cvars.fullscreen.integer != 0 and common.ri.Cvar_VariableIntegerValue.?("in_nograb") != 0) {
        common.info("Fullscreen not allowed with in_nograb 1\n", .{});
        common.ri.Cvar_Set.?("r_fullscreen", "0");
        cvars.fullscreen.modified = c.qfalse;
    }
    // Re-create the window instead of resizing it, so the scene is rendered at the new
    // native drawable size rather than stretched by the composite pass.
    if ((cvars.fullscreen.integer != 0) != fullscreen) common.ri.Cmd_ExecuteText.?(c.EXEC_APPEND, "vid_restart\n");
    cvars.fullscreen.modified = c.qfalse;
}

var mismatch_since: ?i32 = null;

/// A drawable that settles at another size (desktop resolution change, resizable window)
/// restarts video so rendering returns to native pixels.
fn followDrawable() void {
    var w: c_int = 0;
    var h: c_int = 0;
    c.SDL_Vulkan_GetDrawableSize(window, &w, &h);
    if (w <= 0 or h <= 0 or (w == config.vidWidth and h == config.vidHeight)) {
        mismatch_since = null;
        return;
    }
    if (cvars.mode.integer != -2 and cvars.allowResize.integer == 0) return;
    const now = common.milliseconds();
    const since = mismatch_since orelse {
        mismatch_since = now;
        return;
    };
    if (now - since < 500) return;
    mismatch_since = null;
    common.info("Vulkan drawable changed to {d} {d}; restarting video at native size\n", .{ w, h });
    common.ri.Cmd_ExecuteText.?(c.EXEC_APPEND, "vid_restart\n");
}

pub fn minimize() void {
    if (window) |w| c.SDL_MinimizeWindow(w);
}
