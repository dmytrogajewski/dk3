// SPDX-License-Identifier: GPL-2.0-or-later
//! Settings describe actual client/engine controls; difficulty belongs to new game.
const std = @import("std");
const engine = @import("../engine/ui.zig");
pub const Group = enum { sound, video, mouse, options, joystick };
pub const Setting = struct {
    group: Group,
    label: []const u8,
    name: [:0]const u8,
    initial: [:0]const u8,
    minimum: f32 = 0,
    maximum: f32 = 1,
    step: f32 = 1,
    choices: []const []const u8 = &.{},
    /// Video settings are spread over several pages (page titles in `video_pages`).
    page: u8 = 0,
    /// Shown value = cvar value x `display_scale` (tiny densities read as 0.0-2.0).
    display_scale: f32 = 1,
    pub fn value(self: Setting) f32 {
        return std.math.clamp(engine.number(self.name), self.minimum, self.maximum);
    }
    pub fn change(self: Setting, direction: i32) void {
        var next = self.value() + self.step * @as(f32, @floatFromInt(direction));
        if (self.choices.len > 0) {
            if (next > self.maximum + 0.001) next = self.minimum;
            if (next < self.minimum - 0.001) next = self.maximum;
        }
        engine.setNumber(self.name, std.math.clamp(next, self.minimum, self.maximum));
    }
    pub fn labelValue(self: Setting, buffer: []u8) ![]const u8 {
        if (self.choices.len > 0) return self.choices[@min(self.choices.len - 1, @as(usize, @intFromFloat(self.value())))];
        return std.fmt.bufPrint(buffer, "{d:.2}", .{self.value() * self.display_scale});
    }
};
const on_off: []const []const u8 = &.{ "Off", "On" };
/// Titles of the Video pages; settings marked `restart` need "Apply video changes".
pub const video_pages = [_][]const u8{ "Display", "Remaster", "Image", "Lighting", "Atmosphere", "Weather", "Surfaces" };
pub const entries = [_]Setting{
    .{ .group = .sound, .label = "Sound volume", .name = "s_volume", .initial = "0.8", .step = 0.05 },
    .{ .group = .sound, .label = "Music volume", .name = "s_musicvolume", .initial = "0.5", .step = 0.05 },
    .{ .group = .video, .label = "Brightness", .name = "r_gamma", .initial = "1", .minimum = 0.5, .maximum = 3, .step = 0.1 },
    .{ .group = .video, .label = "Fullscreen", .name = "r_fullscreen", .initial = "0", .choices = on_off },
    .{ .group = .video, .label = "Vertical sync", .name = "r_swapInterval", .initial = "0", .choices = on_off },
    .{ .group = .video, .label = "Texture detail", .name = "r_picmip", .initial = "0", .maximum = 3, .choices = &.{ "Highest", "High", "Medium", "Low" } },
    .{ .group = .video, .label = "Model shadows", .name = "cg_shadows", .initial = "1", .choices = on_off },
    // Vulkan remaster (renderer_vulkan cvars; defaults match src/renderer_vulkan/cvars.zig).
    .{ .group = .video, .page = 1, .label = "Remaster (restart)", .name = "r_vkRemaster", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 1, .label = "Ray tracing (restart)", .name = "r_vkRayTracing", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 1, .label = "Path tracing", .name = "r_vkPathTracing", .initial = "0", .choices = on_off },
    .{ .group = .video, .page = 1, .label = "Ray traced light level", .name = "r_vkPtLightScale", .initial = "0.5", .minimum = 0.1, .maximum = 2, .step = 0.05 },
    .{ .group = .video, .page = 1, .label = "Render scale (restart)", .name = "r_vkRenderScale", .initial = "1", .minimum = 0.5, .maximum = 1, .step = 0.05 },
    .{ .group = .video, .page = 2, .label = "Anti-aliasing (TAA)", .name = "r_vkTAA", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 2, .label = "Sharpening", .name = "r_vkSharpen", .initial = "0.3", .maximum = 1, .step = 0.05 },
    .{ .group = .video, .page = 2, .label = "Bloom", .name = "r_vkBloom", .initial = "0.05", .maximum = 0.2, .step = 0.01 },
    .{ .group = .video, .page = 2, .label = "Exposure (EV)", .name = "r_vkExposure", .initial = "0", .minimum = -2, .maximum = 2, .step = 0.25 },
    .{ .group = .video, .page = 2, .label = "Filmic tone mapping", .name = "r_vkTonemap", .initial = "0", .choices = on_off },
    .{ .group = .video, .page = 3, .label = "Ray traced shadows", .name = "r_vkRtShadows", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 3, .label = "Ray traced reflections", .name = "r_vkRtReflections", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 3, .label = "Probe lighting (GI)", .name = "r_vkDdgi", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 3, .label = "Ray traced lighting", .name = "r_vkLighting", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 3, .label = "Ray traced characters", .name = "r_vkRtCharacters", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 4, .label = "Volumetric fog", .name = "r_vkVolumetric", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 4, .label = "Light shafts (ray traced)", .name = "r_vkVolumetricShadows", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 4, .label = "Map fog", .name = "r_vkMapFog", .initial = "0.3", .maximum = 1, .step = 0.05 },
    .{ .group = .video, .page = 4, .label = "Air density", .name = "r_vkFogDensity", .initial = "0.00005", .maximum = 0.0002, .step = 0.00001, .display_scale = 10000 },
    .{ .group = .video, .page = 4, .label = "Light scattering", .name = "r_vkFogScatter", .initial = "1", .maximum = 2, .step = 0.1 },
    .{ .group = .video, .page = 5, .label = "Rain and snow", .name = "r_vkWeather", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 5, .label = "Rain intensity", .name = "r_vkWeatherDensity", .initial = "1", .maximum = 2, .step = 0.1 },
    .{ .group = .video, .page = 5, .label = "Wet surfaces", .name = "r_vkWetness", .initial = "1", .maximum = 1, .step = 0.1 },
    .{ .group = .video, .page = 5, .label = "Rain splashes", .name = "r_vkWeatherSplashes", .initial = "1", .choices = on_off },
    .{ .group = .video, .page = 6, .label = "Surface relief", .name = "r_vkBump", .initial = "1", .maximum = 2, .step = 0.1 },
    .{ .group = .video, .page = 6, .label = "Shininess", .name = "r_vkSpecular", .initial = "1", .maximum = 2, .step = 0.1 },
    .{ .group = .video, .page = 6, .label = "Saturation", .name = "r_vkSaturation", .initial = "1", .minimum = 0.5, .maximum = 1.5, .step = 0.05 },
    .{ .group = .mouse, .label = "Sensitivity", .name = "sensitivity", .initial = "5", .minimum = 0.5, .maximum = 10, .step = 0.25 },
    .{ .group = .mouse, .label = "Mouse smoothing", .name = "m_filter", .initial = "0", .choices = on_off },
    .{ .group = .options, .label = "HUD size", .name = "cg_hudScale", .initial = "1", .minimum = 0.75, .maximum = 1.5, .step = 0.05 },
    .{ .group = .options, .label = "Shiny weapons", .name = "cg_shinyWeapons", .initial = "1", .maximum = 2, .choices = &.{ "Off", "Original", "Enhanced" } },
    .{ .group = .options, .label = "Show weapon", .name = "cg_drawGun", .initial = "1", .choices = on_off },
    .{ .group = .joystick, .label = "Enable joystick", .name = "in_joystick", .initial = "0", .choices = on_off },
    .{ .group = .joystick, .label = "Dead zone", .name = "joy_threshold", .initial = "0.15", .minimum = 0.05, .maximum = 0.3, .step = 0.05 },
};
pub fn init() void {
    for (entries) |setting| engine.register(setting.name, setting.initial);
}
