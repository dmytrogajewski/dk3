// SPDX-License-Identifier: GPL-2.0-or-later
//! renderer_vulkan.so: the refexport v13 table (renderercommon/tr_public.h) over the native
//! Vulkan renderer. GetRefAPI refuses machines without a Vulkan 1.3 device so the client can
//! fall back to the default OpenGL2 renderer.
const std = @import("std");
const c = @import("c.zig").c;
const cext = @import("c.zig");
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const window = @import("window.zig");
const image = @import("image.zig");
const shader = @import("shader.zig");
const scene = @import("scene.zig");
const world = @import("world.zig");
const model = @import("model.zig");
const capture = @import("capture.zig");

var initialized = false;
var registered = false;

fn init() void {
    common.info("----- R_Init (Vulkan) -----\n", .{});
    cvars.register();
    image.setColorMappings();
    if (window.config.vidWidth == 0) window.init();
    vk.content_arena = true;
    scene.initTables();
    cext.R_NoiseInit();
    image.createBuiltins();
    shader.init();
    model.init();
    addCommands();
    initialized = true;
    if (cvars.vkMaterialScan.integer != 0) shader.scanAll();
    common.info("----- finished R_Init -----\n", .{});
}

const commands = [_]struct { name: [*:0]const u8, function: *const fn () callconv(.c) void }{
    .{ .name = "imagelist", .function = imageList },
    .{ .name = "shaderlist", .function = shaderList },
    .{ .name = "modellist", .function = modelList },
    .{ .name = "screenshot", .function = capture.screenshotTga },
    .{ .name = "screenshotJPEG", .function = capture.screenshotJpeg },
    .{ .name = "gfxinfo", .function = gfxInfo },
    .{ .name = "minimize", .function = minimize },
    .{ .name = "vk_materialscan", .function = materialScan },
};

fn addCommands() void {
    for (commands) |command| common.ri.Cmd_AddCommand.?(command.name, command.function);
}

fn removeCommands() void {
    for (commands) |command| common.ri.Cmd_RemoveCommand.?(command.name);
}

fn imageList() callconv(.c) void {
    image.list();
}
fn shaderList() callconv(.c) void {
    shader.list();
}
fn modelList() callconv(.c) void {
    model.list();
}
fn minimize() callconv(.c) void {
    window.minimize();
}
fn materialScan() callconv(.c) void {
    shader.scanAll();
}
fn gfxInfo() callconv(.c) void {
    common.info("\nVK_VENDOR: {s}\n", .{common.span(&window.config.vendor_string)});
    common.info("VK_EXTENSIONS: {s}\n", .{common.span(&window.config.extensions_string)});
    window.reportDevice();
    common.info("MODE: {d}, {d} x {d} {s}\n", .{ cvars.mode.integer, window.config.vidWidth, window.config.vidHeight, if (window.config.isFullscreen != 0) "fullscreen" else "windowed" });
    common.info("picmip: {d}  texturemode: {s}  gamma: software\n", .{ cvars.picmip.integer, common.span(cvars.textureMode.string) });
    common.info("textures: {d} slots used of the bindless set\n", .{vk.next_slot});
}

/// Waits for the GPU and releases every content resource; the device and window stay.
fn releaseContent() void {
    if (window.recording) _ = window.endFrame();
    vk.flushUploads();
    vk.waitIdle();
    world.shutdown();
    model.shutdown();
    shader.shutdown();
    image.shutdown();
    capture.shutdown();
    @import("weather.zig").shutdown();
    vk.freeContentMemory();
    vk.next_slot = vk.persistent_slots;
    vk.next_volume_slot = vk.persistent_volume_slots;
}

fn shutdownC(destroy_window: c.qboolean) callconv(.c) void {
    common.info("RE_Shutdown( {d} )\n", .{destroy_window});
    removeCommands();
    if (initialized) releaseContent() else world.shutdown();
    if (destroy_window != 0) window.shutdown(true);
    initialized = false;
    registered = false;
}

fn beginRegistration(config: [*c]c.glconfig_t) callconv(.c) void {
    if (!initialized) init();
    config.* = window.config;
    scene.clearScene();
    registered = true;
}

fn registerModel(name: [*c]const u8) callconv(.c) c.qhandle_t {
    return model.register(name);
}
fn registerSkin(name: [*c]const u8) callconv(.c) c.qhandle_t {
    return model.registerSkin(name);
}
fn registerShader(name: [*c]const u8) callconv(.c) c.qhandle_t {
    return shader.register(common.span(name), true);
}
fn registerShaderNoMip(name: [*c]const u8) callconv(.c) c.qhandle_t {
    return shader.register(common.span(name), false);
}
fn loadWorld(name: [*c]const u8) callconv(.c) void {
    world.load(name);
}
fn setWorldVisData(_: [*c]const u8) callconv(.c) void {
    // Each resident world owns its PVS bytes (dk3_worlds.inc ignores external vis data).
}
fn endRegistration() callconv(.c) void {}

fn clearScene() callconv(.c) void {
    scene.clearScene();
}
fn addRefEntity(entity: [*c]const c.refEntity_t) callconv(.c) void {
    if (!registered) return;
    scene.addEntity(entity);
}
fn addPoly(handle: c.qhandle_t, count: c_int, verts: [*c]const c.polyVert_t, polys: c_int) callconv(.c) void {
    if (!registered) return;
    scene.addPoly(handle, count, verts, polys);
}
fn lightForPoint(point: [*c]f32, ambient: [*c]f32, directed: [*c]f32, direction: [*c]f32) callconv(.c) c_int {
    return world.lightForPoint(@ptrCast(point), @ptrCast(ambient), @ptrCast(directed), @ptrCast(direction));
}
fn addLight(origin: [*c]const f32, intensity: f32, r: f32, g: f32, b: f32) callconv(.c) void {
    if (!registered) return;
    scene.addLight(@ptrCast(origin), intensity, r, g, b, false);
}
fn addAdditiveLight(origin: [*c]const f32, intensity: f32, r: f32, g: f32, b: f32) callconv(.c) void {
    if (!registered) return;
    scene.addLight(@ptrCast(origin), intensity, r, g, b, true);
}
fn renderScene(fd: [*c]const c.refdef_t) callconv(.c) void {
    if (!registered) return;
    scene.renderScene(fd);
}
fn setColor(rgba: [*c]const f32) callconv(.c) void {
    scene.setColor(if (rgba == null) null else @ptrCast(rgba));
}
fn drawStretchPic(x: f32, y: f32, w: f32, h: f32, s1: f32, t1: f32, s2: f32, t2: f32, handle: c.qhandle_t) callconv(.c) void {
    if (!registered) return;
    scene.stretchPic(x, y, w, h, s1, t1, s2, t2, handle);
}
fn drawStretchRaw(x: c_int, y: c_int, w: c_int, h: c_int, cols: c_int, rows: c_int, data: [*c]const u8, client: c_int, dirty: c.qboolean) callconv(.c) void {
    if (!registered) return;
    scene.stretchRaw(x, y, w, h, cols, rows, data, client, dirty != 0);
}
fn uploadCinematic(_: c_int, _: c_int, cols: c_int, rows: c_int, data: [*c]const u8, client: c_int, dirty: c.qboolean) callconv(.c) void {
    if (!registered) return;
    scene.uploadCinematic(cols, rows, data, client, dirty != 0);
}
fn beginFrame(_: c.stereoFrame_t) callconv(.c) void {
    if (!registered) return;
    if (window.beginFrame()) scene.resetBindings();
    scene.beginFrame();
}
var stats_frames: i32 = 0;

fn reportStats() void {
    const every = cvars.vkStats.integer;
    if (every <= 0) {
        scene.stats = .{};
        return;
    }
    stats_frames += 1;
    if (stats_frames < every) {
        scene.stats = .{};
        return;
    }
    stats_frames = 0;
    const s = scene.stats;
    const f = vk.frame();
    common.info("vk stats: views={d} entities={d} md3={d} iqm={d} iqm_culled={d} brush={d} polys={d} surfaces={d} draws={d} stream_kb={d} records_kb={d} grown_stream={d} grown_records={d} textures={d}\n", .{ s.views, s.entities, s.md3, s.iqm, s.iqm_culled, s.brush, s.polys, s.surfaces, s.draws, f.stream.bytesUsed() / 1024, f.records.bytesUsed() / 1024, f.stream.grown, f.records.grown, vk.next_slot });
    scene.stats = .{};
}

fn endFrame(front: [*c]c_int, back: [*c]c_int) callconv(.c) void {
    if (front != null) front.* = 0;
    if (back != null) back.* = 0;
    if (!registered) return;
    reportStats();
    if (capture.pending()) {
        if (window.beginFrame()) scene.resetBindings();
        window.capture_requested = true;
        const value = window.endFrame();
        if (window.last_capture) |captured| capture.process(captured, value);
    } else _ = window.endFrame();
}
fn markFragments(count: c_int, points: [*c]const c.vec3_t, projection: [*c]const f32, max_points: c_int, buffer: [*c]c.vec3_t, max_fragments: c_int, fragments: [*c]c.markFragment_t) callconv(.c) c_int {
    return world.markFragments(count, points, @ptrCast(projection), max_points, buffer, max_fragments, fragments);
}
fn lerpTag(tag: [*c]c.orientation_t, handle: c.qhandle_t, start: c_int, end: c_int, frac: f32, name: [*c]const u8) callconv(.c) c_int {
    return model.lerpTag(tag, handle, start, end, frac, name);
}
fn modelBounds(handle: c.qhandle_t, mins: [*c]f32, maxs: [*c]f32) callconv(.c) void {
    model.bounds(handle, @ptrCast(mins), @ptrCast(maxs));
}
fn registerFont(name: [*c]const u8, size: c_int, font: [*c]c.fontInfo_t) callconv(.c) void {
    capture.registerFont(name, size, font);
}
fn remapShader(old: [*c]const u8, new: [*c]const u8, offset: [*c]const u8) callconv(.c) void {
    shader.remap(common.span(old), common.span(new), if (offset == null) null else common.span(offset));
}
fn getEntityToken(buffer: [*c]u8, size: c_int) callconv(.c) c.qboolean {
    return @intCast(world.entityToken(buffer, size));
}
fn inPvs(a: [*c]const f32, b: [*c]const f32) callconv(.c) c.qboolean {
    return @intFromBool(world.inPvs(@ptrCast(a), @ptrCast(b)));
}
fn takeVideoFrame(width: c_int, height: c_int, captured: [*c]u8, encoded: [*c]u8, motion_jpeg: c.qboolean) callconv(.c) void {
    capture.takeVideoFrame(width, height, captured, encoded, motion_jpeg != 0);
}
fn setDk3Fog(color: [*c]const f32, start: f32, end: f32, sky_end: f32) callconv(.c) void {
    scene.setFog(if (color == null) null else @ptrCast(color), start, end, sky_end);
}
fn addDk3Weather(kind: c_int, flags: c_int, mins: [*c]const f32, maxs: [*c]const f32, id: c_int) callconv(.c) c.qboolean {
    if (mins == null or maxs == null) return c.qfalse;
    return @intFromBool(@import("weather.zig").add(kind, flags, @ptrCast(mins), @ptrCast(maxs), id));
}
fn requestWorld(name: [*c]const u8) callconv(.c) c_uint {
    return world.request(name);
}
fn pollWorld(handle: c_uint) callconv(.c) c_int {
    return world.poll(handle);
}
fn selectWorld(handle: c_uint) callconv(.c) c.qboolean {
    return @intFromBool(world.select(handle));
}
fn currentWorld() callconv(.c) c_uint {
    return world.registration();
}

var re: c.refexport_t = undefined;

fn fillExports() void {
    re = std.mem.zeroes(c.refexport_t);
    re.Shutdown = shutdownC;
    re.BeginRegistration = beginRegistration;
    re.RegisterModel = registerModel;
    re.RegisterSkin = registerSkin;
    re.RegisterShader = registerShader;
    re.RegisterShaderNoMip = registerShaderNoMip;
    re.LoadWorld = loadWorld;
    re.SetWorldVisData = @ptrCast(&setWorldVisData);
    re.EndRegistration = endRegistration;
    re.ClearScene = clearScene;
    re.AddRefEntityToScene = addRefEntity;
    re.AddPolyToScene = addPoly;
    re.LightForPoint = @ptrCast(&lightForPoint);
    re.AddLightToScene = @ptrCast(&addLight);
    re.AddAdditiveLightToScene = @ptrCast(&addAdditiveLight);
    re.RenderScene = renderScene;
    re.SetColor = setColor;
    re.DrawStretchPic = drawStretchPic;
    re.DrawStretchRaw = drawStretchRaw;
    re.UploadCinematic = uploadCinematic;
    re.BeginFrame = beginFrame;
    re.EndFrame = endFrame;
    re.MarkFragments = @ptrCast(&markFragments);
    re.LerpTag = lerpTag;
    re.ModelBounds = @ptrCast(&modelBounds);
    re.RegisterFont = registerFont;
    re.RemapShader = remapShader;
    re.GetEntityToken = getEntityToken;
    re.inPVS = @ptrCast(&inPvs);
    re.TakeVideoFrame = takeVideoFrame;
    re.SetDk3Fog = @ptrCast(&setDk3Fog);
    re.RequestWorld = requestWorld;
    re.PollWorld = pollWorld;
    re.SelectWorld = selectWorld;
    re.CurrentWorld = currentWorld;
    re.AddDk3WeatherToScene = @ptrCast(&addDk3Weather);
}

/// A Vulkan 1.3 device must exist before the engine commits to this renderer.
fn probe() bool {
    const video_was_up = c.SDL_WasInit(c.SDL_INIT_VIDEO) != 0;
    if (!video_was_up and c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        common.warn("renderer_vulkan: SDL video unavailable: {s}\n", .{common.span(c.SDL_GetError())});
        return false;
    }
    vk.loadLibrary() catch {
        if (!video_was_up) c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        return false;
    };
    vk.createInstance(null, false) catch {
        if (!video_was_up) c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        return false;
    };
    defer vk.destroyInstance();
    const candidate = vk.pickDevice(false, -1, false) catch {
        common.warn("renderer_vulkan: no Vulkan 1.3 device with dynamic rendering, descriptor indexing and buffer device addresses\n", .{});
        if (!video_was_up) c.SDL_QuitSubSystem(c.SDL_INIT_VIDEO);
        return false;
    };
    common.info("renderer_vulkan: probe found {s}\n", .{common.span(&candidate.properties.deviceName)});
    return true;
}

export fn GetRefAPI(api_version: c_int, rimp: *c.refimport_t) ?*c.refexport_t {
    common.ri = rimp.*;
    if (api_version != c.REF_API_VERSION) {
        common.info("Mismatched REF_API_VERSION: expected {d}, got {d}\n", .{ c.REF_API_VERSION, api_version });
        return null;
    }
    if (!probe()) return null;
    fillExports();
    return &re;
}
