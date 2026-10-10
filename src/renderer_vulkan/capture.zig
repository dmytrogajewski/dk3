// SPDX-License-Identifier: GPL-2.0-or-later
//! Screenshots, levelshots, save previews, video frames and prebuilt fonts. Captures read the
//! finished scene image at the end of the frame; rows are converted to the bottom-up RGB layout
//! the shared TGA/JPEG/AVI writers expect from glReadPixels (renderergl1/tr_init.c).
const std = @import("std");
const c = @import("c.zig").c;
const cext = @import("c.zig");
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const window = @import("window.zig");
const world = @import("world.zig");
const shader_mod = @import("shader.zig");

const Shot = struct { name: [c.MAX_OSPATH]u8, jpeg: bool, levelshot: bool };
const Video = struct { width: c_int, height: c_int, capture: [*c]u8, encode: [*c]u8, motion_jpeg: bool };

var shot: ?Shot = null;
var video: ?Video = null;

pub fn pending() bool {
    return shot != null or video != null;
}

/// Reads back the frame's composited image (window.capture_requested, after the submit).
pub fn process(capture: window.Capture, value: u64) void {
    vk.waitValue(value);
    const width = capture.width;
    const height = capture.height;
    const rgba = capture.buffer.mapped.?[0 .. @as(usize, width) * height * 4];
    const rgb = common.gpa.alloc(u8, @as(usize, width) * height * 3) catch return;
    defer common.gpa.free(rgb);
    // Bottom-up rows, as glReadPixels returns them.
    for (0..height) |row| {
        const source = rgba[(height - 1 - row) * width * 4 ..][0 .. width * 4];
        const target = rgb[row * width * 3 ..][0 .. width * 3];
        for (0..width) |x| target[x * 3 ..][0..3].* = source[x * 4 ..][0..3].*;
    }
    if (shot) |request| {
        const name = std.mem.sliceTo(&request.name, 0);
        if (request.levelshot) levelshot(rgb, width, height) else if (request.jpeg) saveJpeg(name, rgb, width, height) else saveTga(name, rgb, width, height);
        shot = null;
    }
    if (video) |request| {
        writeVideo(request, rgb, width, height);
        video = null;
    }
}

fn saveTga(name: []const u8, rgb: []const u8, width: u32, height: u32) void {
    const buffer = common.gpa.alloc(u8, rgb.len + 18) catch return;
    defer common.gpa.free(buffer);
    @memset(buffer[0..18], 0);
    buffer[2] = 2;
    buffer[12] = @truncate(width);
    buffer[13] = @truncate(width >> 8);
    buffer[14] = @truncate(height);
    buffer[15] = @truncate(height >> 8);
    buffer[16] = 24;
    var index: usize = 0;
    while (index < rgb.len) : (index += 3) buffer[18 + index ..][0..3].* = .{ rgb[index + 2], rgb[index + 1], rgb[index] };
    var path: [c.MAX_OSPATH]u8 = undefined;
    common.ri.FS_WriteFile.?(common.qpath(@ptrCast(&path), name).ptr, buffer.ptr, @intCast(buffer.len));
}

/// `R_SavePreviewJPEG` (dk3_savepreview.inc): menu thumbnails at 400x300.
fn savePreview(name: []const u8, rgb: []const u8, width: u32, height: u32) bool {
    const preview_width = 400;
    const preview_height = 300;
    if (!std.mem.startsWith(u8, name, "screenshots/dk3-save-") or width <= preview_width or height <= preview_height) return false;
    var preview: [preview_width * preview_height * 3]u8 = undefined;
    for (0..preview_height) |py| {
        const y0 = py * height / preview_height;
        const y1 = (py + 1) * height / preview_height;
        for (0..preview_width) |px| {
            const x0 = px * width / preview_width;
            const x1 = (px + 1) * width / preview_width;
            var sum = [3]u32{ 0, 0, 0 };
            var count: u32 = 0;
            for (y0..y1) |sy| for (x0..x1) |sx| {
                for (0..3) |k| sum[k] += rgb[(sy * width + sx) * 3 + k];
                count += 1;
            };
            for (0..3) |k| preview[(py * preview_width + px) * 3 + k] = @intCast(sum[k] / @max(count, 1));
        }
    }
    var path: [c.MAX_OSPATH]u8 = undefined;
    cext.RE_SaveJPG(common.qpath(@ptrCast(&path), name).ptr, cvars.screenshotJpegQuality.integer, preview_width, preview_height, &preview, 0);
    return true;
}

fn saveJpeg(name: []const u8, rgb: []u8, width: u32, height: u32) void {
    if (savePreview(name, rgb, width, height)) return;
    var path: [c.MAX_OSPATH]u8 = undefined;
    cext.RE_SaveJPG(common.qpath(@ptrCast(&path), name).ptr, cvars.screenshotJpegQuality.integer, @intCast(width), @intCast(height), rgb.ptr, 0);
}

/// `R_LevelShot`: 128x128 thumbnail sampled from the full frame.
fn levelshot(rgb: []const u8, width: u32, height: u32) void {
    const w = world.current() orelse return;
    var base = std.fs.path.basename(w.nameSlice());
    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| base = base[0..dot];
    var name_buffer: [c.MAX_OSPATH]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buffer, "levelshots/{s}.tga", .{base}) catch return;
    var buffer: [128 * 128 * 3 + 18]u8 = undefined;
    @memset(buffer[0..18], 0);
    buffer[2] = 2;
    buffer[12] = 128;
    buffer[14] = 128;
    buffer[16] = 24;
    const x_scale = @as(f32, @floatFromInt(width)) / 512.0;
    const y_scale = @as(f32, @floatFromInt(height)) / 384.0;
    for (0..128) |y| for (0..128) |x| {
        var sum = [3]u32{ 0, 0, 0 };
        for (0..3) |yy| for (0..4) |xx| {
            const sy: usize = @intFromFloat(@as(f32, @floatFromInt(y * 3 + yy)) * y_scale);
            const sx: usize = @intFromFloat(@as(f32, @floatFromInt(x * 4 + xx)) * x_scale);
            const src = rgb[(@min(sy, height - 1) * width + @min(sx, width - 1)) * 3 ..][0..3];
            for (0..3) |k| sum[k] += src[k];
        };
        buffer[18 + (y * 128 + x) * 3 ..][0..3].* = .{ @intCast(sum[2] / 12), @intCast(sum[1] / 12), @intCast(sum[0] / 12) };
    };
    common.ri.FS_WriteFile.?(name.ptr, &buffer, buffer.len);
    common.info("Wrote {s}\n", .{name});
}

fn writeVideo(request: Video, rgb: []u8, width: u32, height: u32) void {
    if (request.width != width or request.height != height) return;
    const line = width * 3;
    if (request.motion_jpeg) {
        const size = cext.RE_SaveJPGToBuffer(request.encode, line * height, cvars.aviMotionJpegQuality.integer, @intCast(width), @intCast(height), rgb.ptr, 0);
        common.ri.CL_WriteAVIVideoFrame.?(request.encode, @intCast(size));
        return;
    }
    const padded = std.mem.alignForward(usize, line, 4);
    for (0..height) |row| {
        const target = request.encode[row * padded ..][0..padded];
        const source = rgb[row * line ..][0..line];
        var x: usize = 0;
        while (x < line) : (x += 3) target[x..][0..3].* = .{ source[x + 2], source[x + 1], source[x] };
        @memset(target[line..padded], 0);
    }
    common.ri.CL_WriteAVIVideoFrame.?(request.encode, @intCast(padded * height));
}

pub fn takeVideoFrame(width: c_int, height: c_int, capture: [*c]u8, encode: [*c]u8, motion_jpeg: bool) void {
    video = .{ .width = width, .height = height, .capture = capture, .encode = encode, .motion_jpeg = motion_jpeg };
}

fn screenshotCommand(jpeg: bool) void {
    const argument = common.span(common.ri.Cmd_Argv.?(1));
    if (std.mem.eql(u8, argument, "levelshot")) {
        shot = .{ .name = std.mem.zeroes([c.MAX_OSPATH]u8), .jpeg = false, .levelshot = true };
        return;
    }
    const silent = std.mem.eql(u8, argument, "silent");
    var request: Shot = .{ .name = std.mem.zeroes([c.MAX_OSPATH]u8), .jpeg = jpeg, .levelshot = false };
    const ext = if (jpeg) "jpg" else "tga";
    if (common.ri.Cmd_Argc.?() == 2 and !silent) {
        _ = std.fmt.bufPrintZ(&request.name, "screenshots/{s}.{s}", .{ argument, ext }) catch return;
    } else {
        const counter = if (jpeg) &last_jpeg else &last_tga;
        while (counter.* <= 9999) : (counter.* += 1) {
            const candidate = std.fmt.bufPrintZ(&request.name, "screenshots/shot{d:0>4}.{s}", .{ @as(u32, @intCast(counter.*)), ext }) catch return;
            if (common.ri.FS_FileExists.?(candidate.ptr) == 0) break;
        }
        if (counter.* >= 9999) {
            common.info("ScreenShot: Couldn't create a file\n", .{});
            return;
        }
        counter.* += 1;
    }
    shot = request;
    if (!silent) common.info("Wrote {s}\n", .{std.mem.sliceTo(&request.name, 0)});
}

var last_tga: i32 = 0;
var last_jpeg: i32 = 0;

pub fn screenshotTga() callconv(.c) void {
    screenshotCommand(false);
}

pub fn screenshotJpeg() callconv(.c) void {
    screenshotCommand(true);
}

// ---------------------------------------------------------------------------------------------
// Prebuilt fonts (the non-FreeType path of renderercommon/tr_font.c).

var fonts: std.ArrayList(c.fontInfo_t) = .empty;

pub fn registerFont(font_name: [*c]const u8, point_size_in: c_int, font: *c.fontInfo_t) void {
    if (font_name == null) {
        common.info("RE_RegisterFont: called with empty name\n", .{});
        return;
    }
    const point_size = if (point_size_in <= 0) 12 else point_size_in;
    var name_buffer: [64]u8 = undefined;
    const name = std.fmt.bufPrintZ(&name_buffer, "fonts/fontImage_{d}.dat", .{point_size}) catch return;
    for (fonts.items) |*existing| {
        if (std.ascii.eqlIgnoreCase(common.span(&existing.name), name)) {
            font.* = existing.*;
            return;
        }
    }
    if (fonts.items.len >= 6) {
        common.warn("RE_RegisterFont: Too many fonts registered already.\n", .{});
        return;
    }
    const bytes = common.readFile(name.ptr) orelse {
        common.warn("RE_RegisterFont: FreeType code not available\n", .{});
        return;
    };
    defer common.freeFile(bytes);
    if (bytes.len != @sizeOf(c.fontInfo_t)) {
        common.warn("RE_RegisterFont: FreeType code not available\n", .{});
        return;
    }
    @memcpy(std.mem.asBytes(font), bytes);
    _ = common.qpath(@ptrCast(&font.name), name);
    for (c.GLYPH_START..c.GLYPH_END + 1) |i| font.glyphs[i].glyph = shader_mod.register(common.span(&font.glyphs[i].shaderName), false);
    fonts.append(common.gpa, font.*) catch {};
}

pub fn shutdown() void {
    fonts.clearAndFree(common.gpa);
    shot = null;
    video = null;
}
