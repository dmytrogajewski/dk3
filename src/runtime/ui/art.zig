// SPDX-License-Identifier: GPL-2.0-or-later
//! Supplied menu artwork and animated plates; no menu decisions live here.
const std = @import("std");
const engine = @import("../engine/ui.zig");
const c = engine.c;
const v = @import("../domain/vector.zig");
const canvas = @import("../engine/canvas.zig");
const Layout = @import("../domain/menu.zig").Layout;
pub const plates = [_][:0]const u8{ "singleplay", "multi", "loadgame", "savegame", "sound", "video", "mouse", "keyboard", "joystick", "options", "config", "credits", "resume", "quit" };
pub const Art = struct {
    font: canvas.Font = undefined,
    bright: canvas.Font = undefined,
    buttons: canvas.Font = undefined,
    tiles: [6]c.qhandle_t = @splat(0),
    skins: [14]c.qhandle_t = @splat(0),
    figures: [3]c.qhandle_t = @splat(0),
    cursors: [9]c.qhandle_t = @splat(0),
    model: c.qhandle_t = 0,
    white: c.qhandle_t = 0,
    poses: [14]f32 = @splat(0),
    previous: i32 = 0,
    pub fn init(self: *Art) !void {
        self.* = .{};
        self.font = try engine.draw.font("int_font");
        self.bright = try engine.draw.font("int_font_bright");
        self.buttons = try engine.draw.font("int_buttons");
        self.white = engine.draw.shader("white");
        var path: [128]u8 = undefined;
        for (&self.tiles, 0..) |*tile, i| tile.* = engine.draw.shader(try std.fmt.bufPrintZ(&path, "pics/interface/back{d}{d}.tga", .{ i / 3, i % 3 }));
        for (&self.figures, 0..) |*figure, i| figure.* = engine.draw.shader(try std.fmt.bufPrintZ(&path, "pics/menu/skill_{d}.tga", .{i}));
        for (&self.cursors, 1..) |*cursor, i| cursor.* = engine.draw.shader(try std.fmt.bufPrintZ(&path, "pics/interface/cursor_{d:0>2}.tga", .{i}));
        for (&self.skins, plates) |*skin, name| skin.* = engine.draw.shader(try std.fmt.bufPrintZ(&path, "dkq3/menu/ib_{s}", .{name}));
        self.model = @intCast(engine.gateway.call(c.UI_R_REGISTERMODEL, .{@as([*:0]const u8, "models/interface/ib_button.dkm.md3")}));
    }
    pub fn text(self: *const Art, layout: Layout, x: f32, y: f32, value: []const u8, highlight: bool) void {
        const font = if (highlight) self.bright else self.font;
        engine.draw.text(font, layout.x + x * layout.scale, layout.y + y * layout.scale, layout.scale, value, canvas.white);
    }
    pub fn rect(_: *const Art, layout: Layout, x: f32, y: f32, width: f32, height: f32, shader: c.qhandle_t, tint: canvas.Color) void {
        engine.draw.rect(layout.x + x * layout.scale, layout.y + y * layout.scale, width * layout.scale, height * layout.scale, shader, tint);
    }
    pub fn glyph(self: *const Art, layout: Layout, code: u8, x: f32, y: f32, width: f32) void {
        const font = self.buttons;
        const gx: f32 = @floatFromInt(font.metrics.x[code]);
        const gy: f32 = @floatFromInt(font.metrics.y[code]);
        const gw: f32 = @floatFromInt(font.metrics.widths[code]);
        const gh: f32 = @floatFromInt(font.metrics.height);
        const tw: f32 = @floatFromInt(font.width);
        const th: f32 = @floatFromInt(font.height);
        engine.draw.image(layout.x + x * layout.scale, layout.y + y * layout.scale, width * layout.scale, gh * layout.scale, .{ gx / tw, gy / th, (gx + gw) / tw, (gy + gh) / th }, font.shader);
    }
    pub fn button(self: *const Art, layout: Layout, x: f32, y: f32, width: f32, label: []const u8, highlight: bool, down: bool) void {
        const code: u8 = (if (width <= 70) @as(u8, 2) else if (width <= 130) @as(u8, 5) else 8) + @as(u8, @intFromBool(down));
        self.glyph(layout, code, x, y, width);
        const inset = (width - self.font.metrics.width(label, 1)) * 0.5;
        self.text(layout, x + @max(3, inset), y + (@as(f32, @floatFromInt(self.buttons.metrics.height)) - @as(f32, @floatFromInt(self.font.metrics.height))) * 0.5, label, highlight);
    }
    pub fn render(self: *Art, layout: Layout, now: i32, selected: usize, hover: ?usize, in_game: bool) void {
        for (self.tiles, 0..) |tile, i| {
            const width: f32 = if (i % 3 == 2) 128 else 256;
            const height: f32 = if (i / 3 == 1) 224 else 256;
            engine.draw.image(layout.x + @as(f32, @floatFromInt(i % 3)) * 256 * layout.scale, layout.y + @as(f32, @floatFromInt(i / 3)) * 256 * layout.scale, width * layout.scale, height * layout.scale, .{ 0, 0, width / 256, height / 256 }, tile);
        }
        var scene = std.mem.zeroes(c.refdef_t);
        scene.x = @intFromFloat(layout.x);
        scene.y = @intFromFloat(layout.y);
        scene.width = @intFromFloat(640 * layout.scale);
        scene.height = @intFromFloat(480 * layout.scale);
        scene.fov_x = 40;
        scene.fov_y = std.math.atan(@as(f32, @tan(20.0 * std.math.pi / 180.0) * (480.0 / 640.0))) * 360 / std.math.pi;
        scene.rdflags = c.RDF_NOWORLDMODEL;
        scene.time = now;
        scene.viewaxis = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
        _ = engine.gateway.call(c.UI_R_CLEARSCENE, .{});
        for (self.skins, 0..) |skin, i| {
            const goal: f32 = if (selected == i) 15 else if (hover != null and hover.? == i) 1 else 0;
            const step: f32 = @as(f32, @floatFromInt(std.math.clamp(now - self.previous, 0, 100))) * (if (goal == 15 or self.poses[i] > 1) @as(f32, 14.0 / 350.0) else @as(f32, 1.0 / 175.0));
            self.poses[i] += std.math.clamp(goal - self.poses[i], -step, step);
            var entity = std.mem.zeroes(c.refEntity_t);
            entity.reType = c.RT_MODEL;
            entity.hModel = self.model;
            entity.customShader = skin;
            entity.origin = .{ 35, -2.8, 8.35 - 1.165 * @as(f32, @floatFromInt(i)) };
            const basis = v.basis(.{ 0, 210, 0 });
            entity.axis = .{ v.scale(basis.forward, 1.09), v.scale(basis.right, -1.09), .{ 0, 0, 1.09 } };
            entity.nonNormalizedAxes = c.qtrue;
            entity.oldframe = @intFromFloat(self.poses[i]);
            entity.frame = @min(entity.oldframe + 1, 15);
            entity.backlerp = 1 - (self.poses[i] - @as(f32, @floatFromInt(entity.oldframe)));
            entity.shaderRGBA = @splat(if (!in_game and (i == 3 or i == 12)) @as(u8, 64) else 255);
            entity.shaderRGBA[3] = 255;
            _ = engine.gateway.call(c.UI_R_ADDREFENTITYTOSCENE, .{&entity});
        }
        _ = engine.gateway.call(c.UI_R_RENDERSCENE, .{&scene});
        self.previous = now;
    }
};
