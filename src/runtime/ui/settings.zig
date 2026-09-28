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
        return std.fmt.bufPrint(buffer, "{d:.2}", .{self.value()});
    }
};
const on_off: []const []const u8 = &.{ "Off", "On" };
pub const entries = [_]Setting{
    .{ .group = .sound, .label = "Sound volume", .name = "s_volume", .initial = "0.8", .step = 0.05 },
    .{ .group = .sound, .label = "Music volume", .name = "s_musicvolume", .initial = "0.5", .step = 0.05 },
    .{ .group = .video, .label = "Brightness", .name = "r_gamma", .initial = "1", .minimum = 0.5, .maximum = 3, .step = 0.1 },
    .{ .group = .video, .label = "Fullscreen", .name = "r_fullscreen", .initial = "0", .choices = on_off },
    .{ .group = .video, .label = "Vertical sync", .name = "r_swapInterval", .initial = "0", .choices = on_off },
    .{ .group = .video, .label = "Texture detail", .name = "r_picmip", .initial = "0", .maximum = 3, .choices = &.{ "Highest", "High", "Medium", "Low" } },
    .{ .group = .video, .label = "Model shadows", .name = "cg_shadows", .initial = "1", .choices = on_off },
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
