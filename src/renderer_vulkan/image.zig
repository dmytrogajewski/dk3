// SPDX-License-Identifier: GPL-2.0-or-later
//! Image registry: R_LoadImage/R_FindImageFile/R_CreateImage (renderergl1/tr_image.c) on
//! Vulkan textures in the bindless set. Mipmaps are box-filtered on the CPU as GL1 does with
//! r_simpleMipMaps; picmip drops the top levels; gamma/intensity tables apply at upload.
const std = @import("std");
const c = @import("c.zig").c;
const cext = @import("c.zig");
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");

pub const Flags = packed struct(u8) {
    mipmap: bool = false,
    picmip: bool = false,
    clamp: bool = false,
    no_light_scale: bool = false,
    nearest: bool = false,
    _: u3 = 0,
};

pub const Liquid = enum(u8) { none, water, slime, lava };

/// Remaster surface response. Values come from `<image>.mat` sidecars (dkq3/tools/materialgen.py)
/// or, without one, from the texture name; `<image>_n` and `<image>_s` maps are used when present.
pub const Material = struct {
    roughness: f32 = 0.75,
    metalness: f32 = 0,
    bump: f32 = 0.6,
    emissive: f32 = 0,
    specular: f32 = 1,
    liquid: Liquid = .none,
    normal: ?*Image = null,
    spec: ?*Image = null,
};

pub const Image = struct {
    name: [c.MAX_QPATH]u8 = undefined,
    width: u32,
    height: u32,
    upload_width: u32,
    upload_height: u32,
    flags: Flags,
    texture: vk.Texture,
    has_alpha: bool,
    /// Mean colour of the source pixels (display-encoded 0-1), e.g. a sky box's light.
    average: [3]f32 = .{ 0.5, 0.5, 0.5 },
    material: Material = .{},
    material_ready: bool = false,
    /// Lightmaps: slot + 1 of the baked direction page (bake.zig), 0 before or without it.
    deluxe_slot: u32 = 0,

    pub fn nameSlice(self: *const Image) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

var images: std.ArrayList(*Image) = .empty;
var by_name: std.StringHashMapUnmanaged(*Image) = .empty;

pub var default_image: *Image = undefined;
pub var white: *Image = undefined;
pub var identity_light: *Image = undefined;
pub var scratch: [32]*Image = undefined;

var gamma_table: [256]u8 = undefined;
var intensity_table: [256]u8 = undefined;

const Loader = struct { ext: []const u8, load: *const fn ([*:0]const u8, *?[*]u8, *c_int, *c_int) callconv(.c) void };
/// Order of preference when several formats exist (tr_image.c `imageLoaders`).
pub const loaders = [_]Loader{
    .{ .ext = "tga", .load = cext.R_LoadTGA },
    .{ .ext = "jpg", .load = cext.R_LoadJPG },
    .{ .ext = "jpeg", .load = cext.R_LoadJPG },
    .{ .ext = "png", .load = cext.R_LoadPNG },
    .{ .ext = "pcx", .load = cext.R_LoadPCX },
    .{ .ext = "bmp", .load = cext.R_LoadBMP },
    .{ .ext = "pvr", .load = cext.R_LoadPVR },
};

/// `R_SetColorMappings` without hardware gamma: no overbright, software gamma tables.
pub fn setColorMappings() void {
    if (cvars.intensity.value <= 1) common.ri.Cvar_Set.?("r_intensity", "1");
    if (cvars.gamma.value < 0.5) common.ri.Cvar_Set.?("r_gamma", "0.5") else if (cvars.gamma.value > 3.0) common.ri.Cvar_Set.?("r_gamma", "3.0");
    // The remaster pipeline applies display gamma once, in the composite pass.
    const g = if (cvars.vkRemaster.integer != 0) 1.0 else cvars.gamma.value;
    for (&gamma_table, 0..) |*entry, index| {
        const value: f32 = if (g == 1) @floatFromInt(index) else 255.0 * std.math.pow(f32, @as(f32, @floatFromInt(index)) / 255.0, 1.0 / g) + 0.5;
        entry.* = @intFromFloat(std.math.clamp(@floor(value), 0, 255));
    }
    for (&intensity_table, 0..) |*entry, index| {
        const value = @as(f32, @floatFromInt(index)) * cvars.intensity.value;
        entry.* = @intFromFloat(@min(@floor(value), 255));
    }
}

pub fn extension(name: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfScalar(u8, name, '/') orelse 0;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return "";
    if (dot < slash) return "";
    return name[dot + 1 ..];
}

pub fn stripExtension(name: []const u8) []const u8 {
    const ext = extension(name);
    if (ext.len == 0) return name;
    return name[0 .. name.len - ext.len - 1];
}

const Pixels = struct { data: [*]u8, width: u32, height: u32 };

fn tryLoader(loader: Loader, name: [*:0]const u8) ?Pixels {
    var pic: ?[*]u8 = null;
    var width: c_int = 0;
    var height: c_int = 0;
    loader.load(name, &pic, &width, &height);
    const data = pic orelse return null;
    if (width <= 0 or height <= 0) {
        common.ri.Free.?(data);
        return null;
    }
    return .{ .data = data, .width = @intCast(width), .height = @intCast(height) };
}

/// `R_LoadImage`: the named loader, then every other format in preference order.
fn loadPixels(name: []const u8) ?Pixels {
    var local_buffer: [c.MAX_QPATH]u8 = undefined;
    var local: []const u8 = name;
    const ext = extension(name);
    var original: ?usize = null;
    if (ext.len > 0) {
        for (loaders, 0..) |loader, index| {
            if (!std.ascii.eqlIgnoreCase(ext, loader.ext)) continue;
            if (tryLoader(loader, common.qpath(&local_buffer, name).ptr)) |pixels| return pixels;
            original = index;
            local = stripExtension(name);
            break;
        }
    }
    for (loaders, 0..) |loader, index| {
        if (original == index) continue;
        var alternative: [c.MAX_QPATH + 8]u8 = undefined;
        const path = std.fmt.bufPrintZ(&alternative, "{s}.{s}", .{ local, loader.ext }) catch continue;
        if (tryLoader(loader, path.ptr)) |pixels| {
            if (original != null) common.developer("WARNING: {s} not present, using {s} instead\n", .{ name, path });
            return pixels;
        }
    }
    return null;
}

/// `R_FindImageFile`: null when no file loads (callers choose the default image).
pub fn find(name: []const u8, flags: Flags) ?*Image {
    if (name.len == 0 or name.len >= c.MAX_QPATH) return null;
    if (by_name.get(name)) |existing| {
        if (!std.mem.eql(u8, name, "*white") and @as(u8, @bitCast(existing.flags)) != @as(u8, @bitCast(flags)))
            common.developer("WARNING: reused image {s} with mixed flags\n", .{name});
        return existing;
    }
    const started = common.milliseconds();
    const pixels = loadPixels(name) orelse return null;
    defer common.ri.Free.?(pixels.data);
    const decoded = common.milliseconds();
    const result = create(name, pixels.data[0 .. @as(usize, pixels.width) * pixels.height * 4], pixels.width, pixels.height, flags);
    const completed = common.milliseconds();
    if (completed - started >= 4)
        common.developer("dk3 image admission: name={s} size={d}x{d} read_decode_ms={d} prepare_upload_ms={d}\n", .{ name, pixels.width, pixels.height, decoded - started, completed - decoded });
    return result;
}

fn mipLevel(source: []const u8, width: u32, height: u32, out: []u8) void {
    const w2 = @max(width >> 1, 1);
    const h2 = @max(height >> 1, 1);
    var y: u32 = 0;
    while (y < h2) : (y += 1) {
        var x: u32 = 0;
        while (x < w2) : (x += 1) {
            const x0 = @min(x * 2, width - 1);
            const x1 = @min(x * 2 + 1, width - 1);
            const y0 = @min(y * 2, height - 1);
            const y1 = @min(y * 2 + 1, height - 1);
            for (0..4) |channel| {
                const sum = @as(u32, source[(y0 * width + x0) * 4 + channel]) + source[(y0 * width + x1) * 4 + channel] +
                    source[(y1 * width + x0) * 4 + channel] + source[(y1 * width + x1) * 4 + channel];
                out[(y * w2 + x) * 4 + channel] = @intCast(sum >> 2);
            }
        }
    }
}

/// `R_CreateImage`: registers `name` with RGBA8 `pixels` and uploads it.
pub fn create(name: []const u8, pixels: []const u8, width: u32, height: u32, flags: Flags) *Image {
    const image = common.gpa.create(Image) catch @panic("OOM");
    image.* = .{
        .width = width,
        .height = height,
        .upload_width = width,
        .upload_height = height,
        .flags = flags,
        .texture = .{},
        .has_alpha = false,
    };
    _ = common.qpath(&image.name, name);
    // Mip chain: level 0 is the source; picmip removes the largest levels.
    var levels: std.ArrayList([]u8) = .empty;
    defer {
        for (levels.items) |level| common.gpa.free(level);
        levels.deinit(common.gpa);
    }
    const first = common.gpa.dupe(u8, pixels) catch @panic("OOM");
    levels.append(common.gpa, first) catch @panic("OOM");
    var w = width;
    var h = height;
    if (flags.mipmap) {
        while (w > 1 or h > 1) {
            const next = common.gpa.alloc(u8, @as(usize, @max(w >> 1, 1)) * @max(h >> 1, 1) * 4) catch @panic("OOM");
            mipLevel(levels.items[levels.items.len - 1], w, h, next);
            levels.append(common.gpa, next) catch @panic("OOM");
            w = @max(w >> 1, 1);
            h = @max(h >> 1, 1);
        }
    }
    var skip: usize = 0;
    if (flags.picmip and flags.mipmap and cvars.picmip.integer > 0) skip = @min(@as(usize, @intCast(cvars.picmip.integer)), levels.items.len - 1);
    const limit: u32 = @intCast(@max(vk.s.properties.limits.maxImageDimension2D, 1));
    while (skip + 1 < levels.items.len and ((width >> @intCast(skip)) > limit or (height >> @intCast(skip)) > limit)) skip += 1;
    const used = levels.items[skip..];
    image.upload_width = @max(width >> @intCast(skip), 1);
    image.upload_height = @max(height >> @intCast(skip), 1);
    {
        var sum: [3]f64 = .{ 0, 0, 0 };
        const step: usize = @max(pixels.len / 4 / 4096, 1);
        var samples: f64 = 0;
        var index: usize = 0;
        while (index < pixels.len / 4) : (index += step) {
            for (0..3) |channel| sum[channel] += @floatFromInt(pixels[index * 4 + channel]);
            samples += 1;
        }
        if (samples > 0) for (0..3) |channel| {
            image.average[channel] = @floatCast(sum[channel] / samples / 255.0);
        };
    }
    for (0..pixels.len / 4) |index| {
        if (pixels[index * 4 + 3] != 255) {
            image.has_alpha = true;
            break;
        }
    }
    if (!flags.no_light_scale) for (used) |level| {
        var index: usize = 0;
        while (index < level.len) : (index += 4) {
            for (0..3) |channel| {
                const value = level[index + channel];
                level[index + channel] = if (flags.mipmap) gamma_table[intensity_table[value]] else gamma_table[value];
            }
        }
    };
    image.texture = vk.createImage(image.upload_width, image.upload_height, @intCast(used.len), c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
    var const_levels: [16][]const u8 = undefined;
    for (used, 0..) |level, index| const_levels[index] = level;
    vk.uploadTexture(&image.texture, const_levels[0..used.len], true);
    vk.bindTexture(&image.texture, samplerFor(flags));
    images.append(common.gpa, image) catch @panic("OOM");
    by_name.put(common.gpa, image.nameSlice(), image) catch @panic("OOM");
    return image;
}

fn samplerFor(flags: Flags) vk.SamplerKind {
    if (flags.nearest) return .nearest_clamp;
    if (flags.mipmap) return if (flags.clamp) .clamp_mip else .repeat_mip;
    return if (flags.clamp) .clamp else .repeat;
}

/// Replaces level 0 of a non-mipmapped image, recreating it when the size changes.
pub fn replace(image: *Image, pixels: []const u8, width: u32, height: u32) void {
    if (width != image.upload_width or height != image.upload_height) {
        // The old texture may still be read by a frame in flight; it is released at Shutdown.
        replaced.append(common.gpa, image.texture) catch @panic("OOM");
        image.texture = vk.createImage(width, height, 1, c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
        image.width = width;
        image.height = height;
        image.upload_width = width;
        image.upload_height = height;
        const levels = [_][]const u8{pixels};
        vk.uploadTexture(&image.texture, &levels, true);
        vk.bindTexture(&image.texture, samplerFor(image.flags));
        return;
    }
    vk.uploadRegion(&image.texture, 0, 0, width, height, pixels);
}

/// A non-mipmapped image of another format from raw texels (float lightmaps).
pub fn createRaw(name: []const u8, texels: []const u8, width: u32, height: u32, format: c.VkFormat, flags: Flags) *Image {
    const image = common.gpa.create(Image) catch @panic("OOM");
    image.* = .{ .width = width, .height = height, .upload_width = width, .upload_height = height, .flags = flags, .texture = .{}, .has_alpha = false };
    _ = common.qpath(&image.name, name);
    image.texture = vk.createImage(width, height, 1, format, c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT, c.VK_IMAGE_ASPECT_COLOR_BIT);
    const levels = [_][]const u8{texels};
    vk.uploadTexture(&image.texture, &levels, true);
    vk.bindTexture(&image.texture, samplerFor(flags));
    images.append(common.gpa, image) catch @panic("OOM");
    by_name.put(common.gpa, image.nameSlice(), image) catch @panic("OOM");
    return image;
}

/// A keyword starts or ends one of the letter runs of the file name (materialgen.py `has`):
/// `swamp03` and `wtrfall` match, `swtrunk` is not water and `seat` is not sea.
fn contains(name: []const u8, words: []const []const u8) bool {
    const base = if (std.mem.lastIndexOfScalar(u8, name, '/')) |slash| name[slash + 1 ..] else name;
    var tokens = std.mem.tokenizeAny(u8, base, "0123456789_-.# ");
    while (tokens.next()) |token| for (words) |word| {
        // Three-letter keywords only as whole runs (`seat` is not sea).
        if (std.ascii.eqlIgnoreCase(token, word)) return true;
        if (word.len > 3 and (std.ascii.startsWithIgnoreCase(token, word) or std.ascii.endsWithIgnoreCase(token, word))) return true;
    };
    return false;
}

/// Defaults from the texture name; the same rules seed dkq3/tools/materialgen.py.
fn guessMaterial(name: []const u8) Material {
    var m: Material = .{};
    // Model skins (characters, weapons, items) carry painted shading: a height derived from
    // their luminance carves folds into faces and cloth, and their highlights are painted
    // too, so they get no procedural bump and no specular (the original lit them diffusely).
    if (!std.ascii.startsWithIgnoreCase(name, "textures/")) {
        m.bump = 0;
        m.specular = 0;
    }
    if (contains(name, &.{ "metal", "steel", "grate", "pipe", "chrome", "iron", "rust", "panel", "vent", "tech", "door", "plate" })) {
        m.metalness = 0.55;
        m.roughness = 0.45;
    }
    if (contains(name, &.{ "rock", "stone", "brick", "dirt", "mud", "sand", "moss", "bark", "wood", "ground", "grass" })) {
        m.roughness = 0.9;
        m.bump = 0.9;
    }
    if (contains(name, &.{ "glass", "window", "ice", "marble", "tile", "floor" })) m.roughness = 0.3;
    if (contains(name, &.{ "light", "lamp", "glow", "neon", "fire", "flame", "torch", "lite" })) m.emissive = 1.5;
    if (contains(name, &.{ "water", "swamp", "pool", "wave", "river", "sea", "lake" })) m.liquid = .water;
    if (contains(name, &.{ "slime", "sludge", "acid", "toxic", "goo" })) m.liquid = .slime;
    if (contains(name, &.{ "lava", "magma" })) m.liquid = .lava;
    if (m.liquid != .none) {
        m.roughness = 0.06;
        m.bump = 0;
        if (m.liquid == .lava) m.emissive = 2.5;
    }
    return m;
}

fn parseMaterial(text: []const u8, m: *Material) void {
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const key = fields.next() orelse continue;
        const value = fields.next() orelse continue;
        if (key[0] == '#' or key[0] == '/') continue;
        const number = std.fmt.parseFloat(f32, value) catch 0;
        if (std.ascii.eqlIgnoreCase(key, "roughness")) m.roughness = number else if (std.ascii.eqlIgnoreCase(key, "metalness")) m.metalness = number else if (std.ascii.eqlIgnoreCase(key, "bump")) m.bump = number else if (std.ascii.eqlIgnoreCase(key, "emissive")) m.emissive = number else if (std.ascii.eqlIgnoreCase(key, "specular")) m.specular = number else if (std.ascii.eqlIgnoreCase(key, "liquid")) {
            m.liquid = if (std.ascii.eqlIgnoreCase(value, "water")) .water else if (std.ascii.eqlIgnoreCase(value, "slime")) .slime else if (std.ascii.eqlIgnoreCase(value, "lava")) .lava else .none;
        }
    }
}

/// The image's remaster material, resolved on first use.
pub fn material(image: *Image) *const Material {
    if (image.material_ready) return &image.material;
    image.material_ready = true;
    const name = image.nameSlice();
    if (name.len == 0 or name[0] == '*') return &image.material;
    const base = stripExtension(name);
    image.material = guessMaterial(base);
    var path: [c.MAX_QPATH + 8]u8 = undefined;
    if (std.fmt.bufPrintZ(&path, "{s}.mat", .{base})) |file| {
        if (common.readFile(file.ptr)) |bytes| {
            defer common.freeFile(bytes);
            parseMaterial(bytes, &image.material);
        }
    } else |_| {}
    const map_flags: Flags = .{ .mipmap = image.flags.mipmap, .picmip = image.flags.picmip, .clamp = image.flags.clamp, .no_light_scale = true };
    if (std.fmt.bufPrint(&path, "{s}_n", .{base})) |normal| image.material.normal = find(normal, map_flags) else |_| {}
    if (std.fmt.bufPrint(&path, "{s}_s", .{base})) |spec| image.material.spec = find(spec, map_flags) else |_| {}
    return &image.material;
}

/// Textures replaced by `replace`, destroyed with the registry.
var replaced: std.ArrayList(vk.Texture) = .empty;

pub fn createBuiltins() void {
    var data: [16 * 16 * 4]u8 = undefined;
    @memset(&data, 32);
    for (0..16) |x| {
        for ([_]usize{ x, x * 16, 15 * 16 + x, x * 16 + 15 }) |pixel| @memset(data[pixel * 4 .. pixel * 4 + 4], 255);
    }
    default_image = create("*default", &data, 16, 16, .{ .mipmap = true });
    @memset(&data, 255);
    white = create("*white", data[0 .. 8 * 8 * 4], 8, 8, .{});
    identity_light = create("*identityLight", data[0 .. 8 * 8 * 4], 8, 8, .{});
    for (&scratch, 0..) |*entry, index| {
        var name: [16]u8 = undefined;
        entry.* = create(std.fmt.bufPrint(&name, "*scratch{d}", .{index}) catch unreachable, &data, 16, 16, .{ .picmip = true, .clamp = true });
    }
}

/// Destroys every content image; the caller releases their memory blocks.
pub fn shutdown() void {
    for (images.items) |image| {
        vk.destroyImage(&image.texture);
        common.gpa.destroy(image);
    }
    for (replaced.items) |*texture| vk.destroyImage(texture);
    replaced.clearAndFree(common.gpa);
    images.clearAndFree(common.gpa);
    by_name.clearAndFree(common.gpa);
}

pub fn list() void {
    var bytes: u64 = 0;
    for (images.items) |image| {
        bytes += @as(u64, image.upload_width) * image.upload_height * 4;
        common.info("{d:5} {d:5} {d:2} {s}\n", .{ image.upload_width, image.upload_height, image.texture.levels, image.nameSlice() });
    }
    common.info(" ---------\n {d} total images, {d} kB\n", .{ images.items.len, bytes / 1024 });
}

// ---------------------------------------------------------------------------------------------
// Resident preparation: `R_PrepareImage` (dk3_image_prefetch.inc). Only queues PNG decodes; the
// material compiler still creates images through `find`.

pub fn prepare(batch: ?*cext.ImageBatch, name: []const u8) bool {
    if (name.len == 0 or name[0] == '$' or name[0] == '*' or name.len >= c.MAX_QPATH) return true;
    if (by_name.contains(name)) return true;
    var buffer: [c.MAX_QPATH]u8 = undefined;
    var local: []const u8 = name;
    const ext = extension(name);
    var original: ?usize = null;
    if (ext.len > 0) {
        for (loaders, 0..) |loader, index| {
            if (!std.ascii.eqlIgnoreCase(ext, loader.ext)) continue;
            const path = common.qpath(&buffer, name);
            if (common.fileExists(path.ptr)) return if (std.ascii.eqlIgnoreCase(ext, "png")) cext.R_QueuePNG(batch, path.ptr) != 0 else true;
            original = index;
            local = stripExtension(name);
            break;
        }
    }
    for (loaders, 0..) |loader, index| {
        if (original == index) continue;
        var candidate: [c.MAX_QPATH + 8]u8 = undefined;
        const path = std.fmt.bufPrintZ(&candidate, "{s}.{s}", .{ local, loader.ext }) catch continue;
        if (common.fileExists(path.ptr)) return if (std.mem.eql(u8, loader.ext, "png")) cext.R_QueuePNG(batch, path.ptr) != 0 else true;
    }
    return true;
}
