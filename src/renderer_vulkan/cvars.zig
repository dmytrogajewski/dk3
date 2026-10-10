// SPDX-License-Identifier: GPL-2.0-or-later
//! Renderer cvars. Names shared with the OpenGL renderers keep their flags so the
//! menus and saved configurations behave the same across `cl_renderer` choices.
const c = @import("c.zig").c;
const common = @import("common.zig");

pub var mode: *c.cvar_t = undefined;
pub var fullscreen: *c.cvar_t = undefined;
pub var noborder: *c.cvar_t = undefined;
pub var customwidth: *c.cvar_t = undefined;
pub var customheight: *c.cvar_t = undefined;
pub var customPixelAspect: *c.cvar_t = undefined;
pub var swapInterval: *c.cvar_t = undefined;
pub var allowResize: *c.cvar_t = undefined;
pub var centerWindow: *c.cvar_t = undefined;
pub var picmip: *c.cvar_t = undefined;
pub var roundImagesDown: *c.cvar_t = undefined;
pub var gamma: *c.cvar_t = undefined;
pub var intensity: *c.cvar_t = undefined;
pub var mapOverBrightBits: *c.cvar_t = undefined;
pub var overBrightBits: *c.cvar_t = undefined;
pub var textureMode: *c.cvar_t = undefined;
pub var dk3Fog: *c.cvar_t = undefined;
pub var shadows: *c.cvar_t = undefined;
pub var screenshotJpegQuality: *c.cvar_t = undefined;
pub var aviMotionJpegQuality: *c.cvar_t = undefined;
pub var fullbright: *c.cvar_t = undefined;
pub var lightmap: *c.cvar_t = undefined;
pub var novis: *c.cvar_t = undefined;
pub var nocull: *c.cvar_t = undefined;
pub var lockpvs: *c.cvar_t = undefined;
pub var drawworld: *c.cvar_t = undefined;
pub var drawentities: *c.cvar_t = undefined;
pub var dynamiclight: *c.cvar_t = undefined;
pub var znear: *c.cvar_t = undefined;
pub var zproj: *c.cvar_t = undefined;
pub var ambientScale: *c.cvar_t = undefined;
pub var directedScale: *c.cvar_t = undefined;
pub var debugLight: *c.cvar_t = undefined;
pub var lodbias: *c.cvar_t = undefined;
pub var subdivisions: *c.cvar_t = undefined;
pub var flares: *c.cvar_t = undefined;
pub var vkDevice: *c.cvar_t = undefined;
pub var vkValidation: *c.cvar_t = undefined;
pub var vkRayTracing: *c.cvar_t = undefined;
pub var vkMaterialScan: *c.cvar_t = undefined;
pub var vkStats: *c.cvar_t = undefined;
pub var vkRemaster: *c.cvar_t = undefined;
pub var vkExposure: *c.cvar_t = undefined;
pub var vkAutoExposure: *c.cvar_t = undefined;
pub var vkBloom: *c.cvar_t = undefined;
pub var vkSaturation: *c.cvar_t = undefined;
pub var vkTonemap: *c.cvar_t = undefined;
pub var vkBump: *c.cvar_t = undefined;
pub var vkSpecular: *c.cvar_t = undefined;
pub var vkVolumetric: *c.cvar_t = undefined;
pub var vkFogDensity: *c.cvar_t = undefined;
pub var vkFogScatter: *c.cvar_t = undefined;
pub var vkMapFog: *c.cvar_t = undefined;
pub var vkVolumetricShadows: *c.cvar_t = undefined;
pub var vkTAA: *c.cvar_t = undefined;
pub var vkWeather: *c.cvar_t = undefined;
pub var vkModelShadows: *c.cvar_t = undefined;
pub var vkRtShadows: *c.cvar_t = undefined;
pub var vkDdgi: *c.cvar_t = undefined;
pub var vkPathTracing: *c.cvar_t = undefined;
pub var vkLighting: *c.cvar_t = undefined;
pub var vkPtLightScale: *c.cvar_t = undefined;
pub var vkDebugView: *c.cvar_t = undefined;
pub var vkDirectionalBake: *c.cvar_t = undefined;
pub var vkBakePages: *c.cvar_t = undefined;
pub var vkDdgiProbes: *c.cvar_t = undefined;
pub var vkRtReflections: *c.cvar_t = undefined;
pub var vkRtCharacters: *c.cvar_t = undefined;
pub var vkLightVisibility: *c.cvar_t = undefined;
pub var vkWeatherDensity: *c.cvar_t = undefined;
pub var vkWeatherSplashes: *c.cvar_t = undefined;
pub var vkWetness: *c.cvar_t = undefined;
pub var vkSnowCover: *c.cvar_t = undefined;
pub var vkSharpen: *c.cvar_t = undefined;
pub var vkRenderScale: *c.cvar_t = undefined;

const archive_latch = c.CVAR_ARCHIVE | c.CVAR_LATCH;

pub fn register() void {
    const get = common.cvar;
    mode = get("r_mode", "-2", archive_latch);
    fullscreen = get("r_fullscreen", "1", c.CVAR_ARCHIVE);
    noborder = get("r_noborder", "0", archive_latch);
    customwidth = get("r_customwidth", "1600", archive_latch);
    customheight = get("r_customheight", "1024", archive_latch);
    customPixelAspect = get("r_customPixelAspect", "1", archive_latch);
    swapInterval = get("r_swapInterval", "0", c.CVAR_ARCHIVE);
    allowResize = get("r_allowResize", "0", archive_latch);
    centerWindow = get("r_centerWindow", "0", archive_latch);
    picmip = get("r_picmip", "1", archive_latch);
    roundImagesDown = get("r_roundImagesDown", "1", archive_latch);
    gamma = get("r_gamma", "1", c.CVAR_ARCHIVE);
    intensity = get("r_intensity", "1", c.CVAR_LATCH);
    mapOverBrightBits = get("r_mapOverBrightBits", "2", c.CVAR_LATCH);
    overBrightBits = get("r_overBrightBits", "1", archive_latch);
    textureMode = get("r_textureMode", "GL_LINEAR_MIPMAP_LINEAR", c.CVAR_ARCHIVE);
    dk3Fog = get("r_dk3Fog", "1", c.CVAR_ARCHIVE);
    shadows = get("cg_shadows", "1", c.CVAR_ARCHIVE);
    screenshotJpegQuality = get("r_screenshotJpegQuality", "90", c.CVAR_ARCHIVE);
    aviMotionJpegQuality = get("r_aviMotionJpegQuality", "90", c.CVAR_ARCHIVE);
    fullbright = get("r_fullbright", "0", c.CVAR_LATCH | c.CVAR_CHEAT);
    lightmap = get("r_lightmap", "0", c.CVAR_CHEAT);
    novis = get("r_novis", "0", c.CVAR_CHEAT);
    nocull = get("r_nocull", "0", c.CVAR_CHEAT);
    lockpvs = get("r_lockpvs", "0", c.CVAR_CHEAT);
    drawworld = get("r_drawworld", "1", c.CVAR_CHEAT);
    drawentities = get("r_drawentities", "1", c.CVAR_CHEAT);
    dynamiclight = get("r_dynamiclight", "1", c.CVAR_ARCHIVE);
    znear = get("r_znear", "4", c.CVAR_CHEAT);
    zproj = get("r_zproj", "64", c.CVAR_ARCHIVE);
    ambientScale = get("r_ambientScale", "0.6", c.CVAR_CHEAT);
    directedScale = get("r_directedScale", "1", c.CVAR_CHEAT);
    debugLight = get("r_debuglight", "0", c.CVAR_TEMP);
    lodbias = get("r_lodbias", "0", c.CVAR_ARCHIVE);
    subdivisions = get("r_subdivisions", "4", archive_latch);
    flares = get("r_flares", "0", c.CVAR_ARCHIVE);
    vkDevice = get("r_vkDevice", "-1", archive_latch);
    vkValidation = get("r_vkValidation", "0", c.CVAR_LATCH);
    vkRayTracing = get("r_vkRayTracing", "1", archive_latch);
    vkMaterialScan = get("r_vkMaterialScan", "0", c.CVAR_TEMP);
    vkStats = get("r_vkStats", "0", c.CVAR_TEMP);
    vkRemaster = get("r_vkRemaster", "1", archive_latch);
    vkExposure = get("r_vkExposure", "0", c.CVAR_ARCHIVE);
    vkAutoExposure = get("r_vkAutoExposure", "1", c.CVAR_ARCHIVE);
    vkBloom = get("r_vkBloom", "0.05", c.CVAR_ARCHIVE);
    vkSaturation = get("r_vkSaturation", "1", c.CVAR_ARCHIVE);
    vkTonemap = get("r_vkTonemap", "0", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkTonemap, "Remaster tonemapper: 0 PBR Neutral (authored tones kept), 1 AgX (filmic)");
    vkBump = get("r_vkBump", "1", c.CVAR_ARCHIVE);
    vkSpecular = get("r_vkSpecular", "1", c.CVAR_ARCHIVE);
    vkVolumetric = get("r_vkVolumetric", "1", c.CVAR_ARCHIVE);
    vkFogDensity = get("r_vkFogDensity", "0.00005", c.CVAR_ARCHIVE);
    vkFogScatter = get("r_vkFogScatter", "1", c.CVAR_ARCHIVE);
    vkMapFog = get("r_vkMapFog", "0.3", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkMapFog, "Remaster: strength of the maps' authored fog (1 = original, which hid the draw distance)");
    vkVolumetricShadows = get("r_vkVolumetricShadows", "1", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkVolumetricShadows, "Remaster with ray tracing: fog lit only where map lights and the sky reach (light shafts)");
    vkTAA = get("r_vkTAA", "1", c.CVAR_ARCHIVE);
    vkWeather = get("r_vkWeather", "1", c.CVAR_ARCHIVE);
    vkModelShadows = get("r_vkModelShadows", "1", c.CVAR_ARCHIVE);
    vkRtShadows = get("r_vkRtShadows", "1", c.CVAR_ARCHIVE);
    vkDdgi = get("r_vkDdgi", "1", c.CVAR_ARCHIVE);
    vkPathTracing = get("r_vkPathTracing", "0", c.CVAR_ARCHIVE);
    vkLighting = get("r_vkLighting", "1", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkLighting, "Remaster lighting with ray tracing: 0 the original baked lightmaps, 1 map lights with ray traced shadows and probe global illumination (no lightmaps)");
    vkPtLightScale = get("r_vkPtLightScale", "0.5", c.CVAR_ARCHIVE);
    vkDebugView = get("r_vkDebugView", "0", c.CVAR_TEMP);
    common.ri.Cvar_SetDescription.?(vkDebugView, "Remaster debug view: 1 path-traced lighting, 2 path-traced pixels, 3 directional lightmaps, 4 world irradiance, 5 ignore directional lightmaps, 6 texture colour only, 7 light only, 12-15 ray traced direct, bounce, sky light, unshadowed direct");
    vkDirectionalBake = get("r_vkDirectionalBake", "0", c.CVAR_ARCHIVE);
    vkBakePages = get("r_vkBakePages", "4", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkDirectionalBake, "Bake directional (deluxe) lightmaps from map lights with ray tracing for normal maps");
    common.ri.Cvar_SetDescription.?(vkBakePages, "Directional lightmap pages baked per frame");
    common.ri.Cvar_SetDescription.?(vkPathTracing, "Path-traced world lighting from the map's light entities (ray tracing tier; heavy)");
    common.ri.Cvar_SetDescription.?(vkPtLightScale, "Brightness of path-traced map lights relative to the original radiosity");
    vkDdgiProbes = get("r_vkDdgiProbes", "8192", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkDdgi, "Ray-traced irradiance probes for model ambient light (ray tracing tier)");
    common.ri.Cvar_SetDescription.?(vkDdgiProbes, "DDGI probes re-traced per frame (64 rays each)");
    vkRtReflections = get("r_vkRtReflections", "1", c.CVAR_ARCHIVE);
    vkRtCharacters = get("r_vkRtCharacters", "1", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkRtCharacters, "Remaster with ray tracing: characters cast and receive ray traced shadows");
    vkLightVisibility = get("r_vkLightVisibility", "1", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkLightVisibility, "Ray traced lighting: measure which lights each light cell can see (0 treats every listed light as visible)");
    common.ri.Cvar_SetDescription.?(vkRtShadows, "Ray-traced shadows for dynamic lights (ray tracing tier)");
    common.ri.Cvar_SetDescription.?(vkRtReflections, "Ray-traced reflections on liquids and smooth or wet materials (ray tracing tier)");
    common.ri.Cvar_SetDescription.?(vkModelShadows, "Remaster shadow-mapped model shadows along the baked light (needs cg_shadows)");
    vkWeatherDensity = get("r_vkWeatherDensity", "1", c.CVAR_ARCHIVE);
    vkWeatherSplashes = get("r_vkWeatherSplashes", "1", c.CVAR_ARCHIVE);
    vkWetness = get("r_vkWetness", "1", c.CVAR_ARCHIVE);
    vkSnowCover = get("r_vkSnowCover", "1", c.CVAR_ARCHIVE);
    common.ri.Cvar_SetDescription.?(vkWeather, "Remaster GPU rain and snow for authored weather volumes (0 keeps cgame particles)");
    common.ri.Cvar_SetDescription.?(vkWeatherDensity, "Remaster weather particle density relative to the original");
    common.ri.Cvar_SetDescription.?(vkWetness, "Remaster wet surfaces, puddles and ripples under rain");
    common.ri.Cvar_SetDescription.?(vkSnowCover, "Remaster snow accumulation on upward-facing surfaces under snow");
    vkSharpen = get("r_vkSharpen", "0.3", c.CVAR_ARCHIVE);
    vkRenderScale = get("r_vkRenderScale", "1", archive_latch);
    common.ri.Cvar_SetDescription.?(vkTAA, "Remaster temporal anti-aliasing");
    common.ri.Cvar_SetDescription.?(vkSharpen, "Remaster contrast-adaptive sharpening strength (0 off)");
    common.ri.Cvar_SetDescription.?(vkRenderScale, "Remaster world render resolution relative to the window, temporally upscaled (0.33-1)");
    common.ri.Cvar_SetDescription.?(vkVolumetric, "Remaster froxel volumetric fog with light scattering (replaces linear fog)");
    common.ri.Cvar_SetDescription.?(vkFogDensity, "Base atmospheric extinction per unit for remaster volumetrics");
    common.ri.Cvar_SetDescription.?(vkFogScatter, "Strength of light scattered by remaster volumetrics");
    common.ri.Cvar_SetDescription.?(vkRemaster, "Vulkan remaster pipeline: HDR, PBR materials and post-processing (0 = classic OpenGL1 look)");
    common.ri.Cvar_SetDescription.?(vkExposure, "Exposure compensation in EV for the remaster pipeline");
    common.ri.Cvar_SetDescription.?(vkStats, "Print renderer_vulkan frame counters every N frames (0 off)");
    common.ri.Cvar_SetDescription.?(dk3Fog, "Draw authored map distance fog");
    common.ri.Cvar_SetDescription.?(vkDevice, "Vulkan physical device index, -1 selects automatically");
    common.ri.Cvar_SetDescription.?(vkValidation, "Enable the Khronos validation layer when installed");
    common.ri.Cvar_SetDescription.?(vkRayTracing, "Use ray tracing extensions when the device offers them");
    common.ri.Cvar_SetDescription.?(vkMaterialScan, "Compile every shader script once and report unsupported keywords");
}

const VidMode = struct { width: c_int, height: c_int, aspect: f32 };
const modes = [_]VidMode{
    .{ .width = 320, .height = 240, .aspect = 1 },   .{ .width = 400, .height = 300, .aspect = 1 },
    .{ .width = 512, .height = 384, .aspect = 1 },   .{ .width = 640, .height = 480, .aspect = 1 },
    .{ .width = 800, .height = 600, .aspect = 1 },   .{ .width = 960, .height = 720, .aspect = 1 },
    .{ .width = 1024, .height = 768, .aspect = 1 },  .{ .width = 1152, .height = 864, .aspect = 1 },
    .{ .width = 1280, .height = 1024, .aspect = 1 }, .{ .width = 1600, .height = 1200, .aspect = 1 },
    .{ .width = 2048, .height = 1536, .aspect = 1 }, .{ .width = 856, .height = 480, .aspect = 1 },
};

/// `R_GetModeInfo` (renderergl1/tr_init.c:286).
pub fn modeInfo(width: *c_int, height: *c_int, aspect: *f32, index: c_int) bool {
    if (index < -1 or index >= modes.len) return false;
    var pixel_aspect: f32 = undefined;
    if (index == -1) {
        width.* = customwidth.integer;
        height.* = customheight.integer;
        pixel_aspect = customPixelAspect.value;
    } else {
        const entry = modes[@intCast(index)];
        width.* = entry.width;
        height.* = entry.height;
        pixel_aspect = entry.aspect;
    }
    aspect.* = @as(f32, @floatFromInt(width.*)) / (@as(f32, @floatFromInt(height.*)) * pixel_aspect);
    return true;
}
