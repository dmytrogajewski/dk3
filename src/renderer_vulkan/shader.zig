// SPDX-License-Identifier: GPL-2.0-or-later
//! Q3 shader scripts: scanning, parsing, implicit shaders and stage collapse.
//! Ports renderergl1/tr_shader.c (ScanAndLoadShaderFiles, ParseShader, ParseStage,
//! FinishShader, CollapseMultitexture, R_FindShader, R_RemapShader). The tokenizer is the
//! shared q_shared.c COM_ParseExt, so script interpretation matches the OpenGL renderers.
const std = @import("std");
const c = @import("c.zig").c;
const cext = @import("c.zig");
const common = @import("common.zig");
const image = @import("image.zig");
const Image = image.Image;

pub const max_stages = 8;
pub const max_animations = 8;
pub const max_texmods = 4;
pub const max_deforms = 3;

pub const lightmap_2d: i32 = -4;
pub const lightmap_by_vertex: i32 = -3;
pub const lightmap_white: i32 = -2;
pub const lightmap_none: i32 = -1;

pub const Sort = struct {
    pub const bad: f32 = 0;
    pub const portal: f32 = 1;
    pub const environment: f32 = 2;
    pub const @"opaque": f32 = 3;
    pub const decal: f32 = 4;
    pub const see_through: f32 = 5;
    pub const banner: f32 = 6;
    pub const fog: f32 = 7;
    pub const underwater: f32 = 8;
    pub const blend0: f32 = 9;
    pub const blend1: f32 = 10;
    pub const stencil_shadow: f32 = 14;
    pub const almost_nearest: f32 = 15;
    pub const nearest: f32 = 16;
};

pub const Func = enum(u8) { none, sin, square, triangle, sawtooth, inverse_sawtooth, noise };

pub const Wave = struct {
    func: Func = .none,
    base: f32 = 0,
    amplitude: f32 = 0,
    phase: f32 = 0,
    frequency: f32 = 0,
};

pub const TexMod = union(enum) {
    turb: Wave,
    scale: [2]f32,
    scroll: [2]f32,
    stretch: Wave,
    transform: struct { matrix: [2][2]f32, translate: [2]f32 },
    rotate: f32,
    entity_translate,
};

pub const TcGen = enum(u8) { bad, texture, lightmap, environment, vector, identity };
pub const RgbGen = enum(u8) { bad, identity_lighting, identity, entity, one_minus_entity, exact_vertex, vertex, one_minus_vertex, wave, lighting_diffuse, constant };
pub const AlphaGen = enum(u8) { identity, skip, entity, one_minus_entity, vertex, one_minus_vertex, lighting_specular, wave, portal, constant };
pub const AlphaFunc = enum(u8) { none, gt0, lt128, ge128 };
pub const Cull = enum(u8) { front, back, two_sided };

/// Blend factor codes (vk.blendFactor).
pub const Blend = struct {
    pub const zero: u8 = 0;
    pub const one: u8 = 1;
    pub const dst_color: u8 = 2;
    pub const one_minus_dst_color: u8 = 3;
    pub const src_alpha: u8 = 4;
    pub const one_minus_src_alpha: u8 = 5;
    pub const dst_alpha: u8 = 6;
    pub const one_minus_dst_alpha: u8 = 7;
    pub const alpha_saturate: u8 = 8;
    pub const src_color: u8 = 9;
    pub const one_minus_src_color: u8 = 10;
};

pub const Bundle = struct {
    images: [max_animations]?*Image = .{null} ** max_animations,
    num_images: u8 = 0,
    animation_speed: f32 = 0,
    is_lightmap: bool = false,
    video: c_int = -1,
    tc_gen: TcGen = .bad,
    tc_gen_vectors: [2][3]f32 = .{ .{ 0, 0, 0 }, .{ 0, 0, 0 } },
    texmods: [max_texmods]TexMod = undefined,
    num_texmods: u8 = 0,
};

pub const Stage = struct {
    active: bool = false,
    bundles: [2]Bundle = .{ .{}, .{} },
    rgb_gen: RgbGen = .bad,
    alpha_gen: AlphaGen = .identity,
    rgb_wave: Wave = .{},
    alpha_wave: Wave = .{},
    constant: [4]u8 = .{ 0, 0, 0, 0 },
    /// Blend factors; `blended` false means src ONE dst ZERO without blending.
    blended: bool = false,
    src: u8 = Blend.one,
    dst: u8 = Blend.zero,
    depth_write: bool = true,
    depth_equal: bool = false,
    depth_test: bool = true,
    alpha_func: AlphaFunc = .none,
    detail: bool = false,
    collapsed: bool = false,

    fn blendIs(self: *const Stage, src: u8, dst: u8) bool {
        return self.blended and self.src == src and self.dst == dst;
    }
};

pub const DeformKind = enum(u8) { none, wave, normals, bulge, move, projection_shadow, autosprite, autosprite2, text };

pub const Deform = struct {
    kind: DeformKind = .none,
    move: [3]f32 = .{ 0, 0, 0 },
    wave: Wave = .{},
    spread: f32 = 0,
    bulge_width: f32 = 0,
    bulge_height: f32 = 0,
    bulge_speed: f32 = 0,
    text: u8 = 0,
};

pub const Sky = struct {
    outer: [6]?*Image = .{null} ** 6,
    inner: [6]?*Image = .{null} ** 6,
    cloud_height: f32 = 0,
};

pub const Shader = struct {
    name: [c.MAX_QPATH]u8 = undefined,
    lightmap_index: i32 = 0,
    world_registration: u32 = 0,
    index: i32 = 0,
    sort: f32 = 0,
    stages: [max_stages]Stage = .{Stage{}} ** max_stages,
    num_stages: u8 = 0,
    deforms: [max_deforms]Deform = .{Deform{}} ** max_deforms,
    num_deforms: u8 = 0,
    cull: Cull = .front,
    polygon_offset: bool = false,
    no_mipmaps: bool = false,
    no_picmip: bool = false,
    is_sky: bool = false,
    /// Ray traced lighting: the light an emitting face (texinfo SURF_LIGHT) shows on itself, in
    /// radiosity units, as its original lightmap carried it (rt.zig originalSurfaceLights).
    rt_self_light: [3]f32 = .{ 0, 0, 0 },
    sky: Sky = .{},
    entity_mergable: bool = false,
    portal_range: f32 = 0,
    time_offset: f32 = 0,
    clamp_time: f32 = 0,
    default_shader: bool = false,
    explicitly_defined: bool = false,
    surface_flags: i32 = 0,
    content_flags: i32 = 0,
    remapped: ?*Shader = null,
    sun_light: ?[3]f32 = null,
    sun_direction: [3]f32 = .{ 0, 0, 0 },

    pub fn nameSlice(self: *const Shader) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    pub fn stagesSlice(self: *const Shader) []const Stage {
        return self.stages[0..self.num_stages];
    }
};

var shaders: std.ArrayList(*Shader) = .empty;
pub var default_shader: *Shader = undefined;
pub var shadow_shader: *Shader = undefined;

/// Lightmaps of the world being registered against (`tr.lightmaps`), set by world.zig.
pub var lightmaps: []const *Image = &.{};
pub var world_registration: u32 = 0;

/// Parse diagnostics; `r_vkMaterialScan` reports them.
pub var unknown_keywords: std.StringHashMapUnmanaged(u32) = .empty;

// ---------------------------------------------------------------------------------------------
// Script text

var shader_text: ?[]u8 = null;
var text_index: std.StringHashMapUnmanaged(std.ArrayList([*c]u8)) = .empty;

fn lowerKey(buffer: *[c.MAX_QPATH]u8, name: []const u8) []const u8 {
    const length = @min(name.len, buffer.len);
    for (name[0..length], 0..) |char, index| buffer[index] = std.ascii.toLower(if (char == '\\') '/' else char);
    return buffer[0..length];
}

/// `ScanAndLoadShaderFiles`: one text buffer, files concatenated in reverse listing order so
/// the first definition found belongs to the last file, and an index of definition starts.
pub fn scanFiles() void {
    var file_count: c_int = 0;
    const files = common.ri.FS_ListFiles.?("scripts", ".shader", &file_count);
    if (files == null or file_count == 0) {
        common.warn("no shader files found\n", .{});
        return;
    }
    defer common.ri.FS_FreeFileList.?(files);
    const total: usize = @intCast(@min(file_count, 4096));
    const buffers = common.gpa.alloc(?[]u8, total) catch @panic("OOM");
    defer common.gpa.free(buffers);
    var sum: usize = 0;
    for (0..total) |index| {
        var path: [c.MAX_QPATH]u8 = undefined;
        const filename = std.fmt.bufPrintZ(&path, "scripts/{s}", .{common.span(files[index])}) catch {
            buffers[index] = null;
            continue;
        };
        common.developer("...loading '{s}'\n", .{filename});
        const bytes = common.readFile(filename.ptr) orelse common.fail(c.ERR_DROP, "Couldn't load {s}", .{filename});
        buffers[index] = bytes;
        // One malformed file must not break every other definition.
        var p: [*c]u8 = bytes.ptr;
        c.COM_BeginParseSession(filename.ptr);
        while (true) {
            const name_token = c.COM_ParseExt(&p, c.qtrue);
            if (name_token[0] == 0) break;
            var name: [c.MAX_QPATH]u8 = undefined;
            const shader_name = common.qpath(&name, common.span(name_token));
            const brace = c.COM_ParseExt(&p, c.qtrue);
            if (brace[0] != '{' or brace[1] != 0) {
                common.warn("Ignoring shader file {s}. Shader \"{s}\" missing opening brace.\n", .{ filename, shader_name });
                common.freeFile(bytes);
                buffers[index] = null;
                break;
            }
            if (c.SkipBracedSection(&p, 1) == 0) {
                common.warn("Ignoring shader file {s}. Shader \"{s}\" missing closing brace.\n", .{ filename, shader_name });
                common.freeFile(bytes);
                buffers[index] = null;
                break;
            }
        }
        if (buffers[index]) |kept| sum += kept.len;
    }
    const text = common.gpa.alloc(u8, sum + total * 2 + 1) catch @panic("OOM");
    var end: usize = 0;
    var index = total;
    while (index > 0) {
        index -= 1;
        const bytes = buffers[index] orelse continue;
        const length = std.mem.indexOfScalar(u8, bytes, 0) orelse bytes.len;
        @memcpy(text[end .. end + length], bytes[0..length]);
        end += length;
        text[end] = '\n';
        end += 1;
        common.freeFile(bytes);
    }
    text[end] = 0;
    _ = c.COM_Compress(text.ptr);
    shader_text = text;
    var p: [*c]u8 = text.ptr;
    while (true) {
        const start = p;
        const name_token = c.COM_ParseExt(&p, c.qtrue);
        if (name_token[0] == 0) break;
        var key_buffer: [c.MAX_QPATH]u8 = undefined;
        const key = lowerKey(&key_buffer, common.span(name_token));
        const entry = text_index.getOrPut(common.gpa, key) catch @panic("OOM");
        if (!entry.found_existing) {
            entry.key_ptr.* = common.gpa.dupe(u8, key) catch @panic("OOM");
            entry.value_ptr.* = .empty;
        }
        entry.value_ptr.append(common.gpa, start) catch @panic("OOM");
        _ = c.SkipBracedSection(&p, 0);
    }
}

/// `FindShaderInShaderText`: the text after the shader name, or null.
pub fn findText(name: []const u8) ?[*c]u8 {
    var key_buffer: [c.MAX_QPATH]u8 = undefined;
    const entries = text_index.get(lowerKey(&key_buffer, name)) orelse return null;
    for (entries.items) |start| {
        var p = start;
        const name_token = c.COM_ParseExt(&p, c.qtrue);
        if (std.ascii.eqlIgnoreCase(common.span(name_token), name)) return p;
    }
    return null;
}

// ---------------------------------------------------------------------------------------------
// Parsing. `current` is the working shader, as the global `shader` in tr_shader.c.

var current: Shader = .{};

fn token(p: *[*c]u8, line_breaks: bool) []const u8 {
    return common.span(c.COM_ParseExt(p, if (line_breaks) c.qtrue else c.qfalse));
}

fn atof(text: []const u8) f32 {
    return std.fmt.parseFloat(f32, text) catch blk: {
        // atof accepts a numeric prefix ("1.5x" -> 1.5); keep that behaviour.
        var end: usize = 0;
        while (end < text.len and (std.ascii.isDigit(text[end]) or text[end] == '.' or text[end] == '-' or text[end] == '+' or text[end] == 'e' or text[end] == 'E')) end += 1;
        while (end > 0) : (end -= 1) {
            if (std.fmt.parseFloat(f32, text[0..end])) |value| break :blk value else |_| {}
        }
        break :blk 0;
    };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn note(keyword: []const u8) void {
    const entry = unknown_keywords.getOrPut(common.gpa, keyword) catch return;
    if (!entry.found_existing) {
        entry.key_ptr.* = common.gpa.dupe(u8, keyword) catch return;
        entry.value_ptr.* = 0;
    }
    entry.value_ptr.* += 1;
}

fn shaderName() []const u8 {
    return current.nameSlice();
}

fn parseVector(p: *[*c]u8, out: []f32) bool {
    if (!std.mem.eql(u8, token(p, false), "(")) {
        common.warn("missing parenthesis in shader '{s}'\n", .{shaderName()});
        return false;
    }
    for (out) |*value| {
        const t = token(p, false);
        if (t.len == 0) {
            common.warn("missing vector element in shader '{s}'\n", .{shaderName()});
            return false;
        }
        value.* = atof(t);
    }
    if (!std.mem.eql(u8, token(p, false), ")")) {
        common.warn("missing parenthesis in shader '{s}'\n", .{shaderName()});
        return false;
    }
    return true;
}

fn genFunc(name: []const u8) Func {
    if (eql(name, "sin")) return .sin;
    if (eql(name, "square")) return .square;
    if (eql(name, "triangle")) return .triangle;
    if (eql(name, "sawtooth")) return .sawtooth;
    if (eql(name, "inversesawtooth")) return .inverse_sawtooth;
    if (eql(name, "noise")) return .noise;
    common.warn("invalid genfunc name '{s}' in shader '{s}'\n", .{ name, shaderName() });
    return .sin;
}

fn parseWave(p: *[*c]u8) Wave {
    var wave: Wave = .{};
    const func = token(p, false);
    if (func.len == 0) {
        common.warn("missing waveform parm in shader '{s}'\n", .{shaderName()});
        return wave;
    }
    wave.func = genFunc(func);
    const fields = [_]*f32{ &wave.base, &wave.amplitude, &wave.phase, &wave.frequency };
    for (fields) |field| {
        const t = token(p, false);
        if (t.len == 0) {
            common.warn("missing waveform parm in shader '{s}'\n", .{shaderName()});
            return wave;
        }
        field.* = atof(t);
    }
    return wave;
}

fn parseTexMod(text: []const u8, stage: *Stage) void {
    const bundle = &stage.bundles[0];
    if (bundle.num_texmods == max_texmods) common.fail(c.ERR_DROP, "ERROR: too many tcMod stages in shader '{s}'", .{shaderName()});
    var copy: [1024]u8 = undefined;
    const length = @min(text.len, copy.len - 1);
    @memcpy(copy[0..length], text[0..length]);
    copy[length] = 0;
    var p: [*c]u8 = &copy;
    const kind = token(&p, false);
    var numbers: [6]f32 = .{ 0, 0, 0, 0, 0, 0 };
    const mod: TexMod = if (eql(kind, "turb")) blk: {
        for (numbers[0..4]) |*n| n.* = atof(token(&p, false));
        break :blk .{ .turb = .{ .func = .sin, .base = numbers[0], .amplitude = numbers[1], .phase = numbers[2], .frequency = numbers[3] } };
    } else if (eql(kind, "scale")) blk: {
        for (numbers[0..2]) |*n| n.* = atof(token(&p, false));
        break :blk .{ .scale = .{ numbers[0], numbers[1] } };
    } else if (eql(kind, "scroll")) blk: {
        for (numbers[0..2]) |*n| n.* = atof(token(&p, false));
        break :blk .{ .scroll = .{ numbers[0], numbers[1] } };
    } else if (eql(kind, "stretch")) blk: {
        const func = genFunc(token(&p, false));
        for (numbers[0..4]) |*n| n.* = atof(token(&p, false));
        break :blk .{ .stretch = .{ .func = func, .base = numbers[0], .amplitude = numbers[1], .phase = numbers[2], .frequency = numbers[3] } };
    } else if (eql(kind, "transform")) blk: {
        for (&numbers) |*n| n.* = atof(token(&p, false));
        break :blk .{ .transform = .{ .matrix = .{ .{ numbers[0], numbers[1] }, .{ numbers[2], numbers[3] } }, .translate = .{ numbers[4], numbers[5] } } };
    } else if (eql(kind, "rotate")) .{ .rotate = atof(token(&p, false)) } else if (eql(kind, "entityTranslate")) .entity_translate else {
        common.warn("unknown tcMod '{s}' in shader '{s}'\n", .{ kind, shaderName() });
        note(kind);
        return;
    };
    bundle.texmods[bundle.num_texmods] = mod;
    bundle.num_texmods += 1;
}

fn imageFlags(clamp: bool) image.Flags {
    return .{ .mipmap = !current.no_mipmaps, .picmip = !current.no_picmip, .clamp = clamp };
}

fn srcBlend(name: []const u8) u8 {
    const table = .{
        .{ "GL_ONE", Blend.one },                           .{ "GL_ZERO", Blend.zero },
        .{ "GL_DST_COLOR", Blend.dst_color },               .{ "GL_ONE_MINUS_DST_COLOR", Blend.one_minus_dst_color },
        .{ "GL_SRC_ALPHA", Blend.src_alpha },               .{ "GL_ONE_MINUS_SRC_ALPHA", Blend.one_minus_src_alpha },
        .{ "GL_DST_ALPHA", Blend.dst_alpha },               .{ "GL_ONE_MINUS_DST_ALPHA", Blend.one_minus_dst_alpha },
        .{ "GL_SRC_ALPHA_SATURATE", Blend.alpha_saturate },
    };
    inline for (table) |entry| if (eql(name, entry[0])) return entry[1];
    common.warn("unknown blend mode '{s}' in shader '{s}', substituting GL_ONE\n", .{ name, shaderName() });
    return Blend.one;
}

fn dstBlend(name: []const u8) u8 {
    const table = .{
        .{ "GL_ONE", Blend.one },             .{ "GL_ZERO", Blend.zero },
        .{ "GL_SRC_ALPHA", Blend.src_alpha }, .{ "GL_ONE_MINUS_SRC_ALPHA", Blend.one_minus_src_alpha },
        .{ "GL_DST_ALPHA", Blend.dst_alpha }, .{ "GL_ONE_MINUS_DST_ALPHA", Blend.one_minus_dst_alpha },
        .{ "GL_SRC_COLOR", Blend.src_color }, .{ "GL_ONE_MINUS_SRC_COLOR", Blend.one_minus_src_color },
    };
    inline for (table) |entry| if (eql(name, entry[0])) return entry[1];
    common.warn("unknown blend mode '{s}' in shader '{s}', substituting GL_ONE\n", .{ name, shaderName() });
    return Blend.one;
}

fn findStageImage(name: []const u8, clamp: bool) ?*Image {
    const found = image.find(name, imageFlags(clamp));
    if (found == null) common.warn("R_FindImageFile could not find '{s}' in shader '{s}'\n", .{ name, shaderName() });
    return found;
}

fn parseStage(stage: *Stage, p: *[*c]u8) bool {
    var depth_mask_explicit = false;
    var blend_set = false;
    var src: u8 = Blend.one;
    var dst: u8 = Blend.zero;
    stage.active = true;
    while (true) {
        const t = token(p, true);
        if (t.len == 0) {
            common.warn("no matching '}}' found\n", .{});
            return false;
        }
        if (t[0] == '}') break;
        if (eql(t, "map")) {
            const name = token(p, false);
            if (name.len == 0) {
                common.warn("missing parameter for 'map' keyword in shader '{s}'\n", .{shaderName()});
                return false;
            }
            if (eql(name, "$whiteimage")) {
                stage.bundles[0].images[0] = image.white;
            } else if (eql(name, "$lightmap")) {
                stage.bundles[0].is_lightmap = true;
                stage.bundles[0].images[0] = if (current.lightmap_index < 0 or lightmaps.len == 0) image.white else lightmaps[@intCast(current.lightmap_index)];
            } else {
                stage.bundles[0].images[0] = findStageImage(name, false) orelse return false;
            }
            stage.bundles[0].num_images = 1;
        } else if (eql(t, "clampmap")) {
            const name = token(p, false);
            if (name.len == 0) {
                common.warn("missing parameter for 'clampmap' keyword in shader '{s}'\n", .{shaderName()});
                return false;
            }
            stage.bundles[0].images[0] = findStageImage(name, true) orelse return false;
            stage.bundles[0].num_images = 1;
        } else if (eql(t, "animMap")) {
            const speed = token(p, false);
            if (speed.len == 0) {
                common.warn("missing parameter for 'animMap' keyword in shader '{s}'\n", .{shaderName()});
                return false;
            }
            stage.bundles[0].animation_speed = atof(speed);
            var total: usize = 0;
            while (true) {
                const name = token(p, false);
                if (name.len == 0) break;
                if (stage.bundles[0].num_images < max_animations) {
                    stage.bundles[0].images[stage.bundles[0].num_images] = findStageImage(name, false) orelse return false;
                    stage.bundles[0].num_images += 1;
                }
                total += 1;
            }
            if (total > max_animations) common.warn("ignoring excess images for 'animMap' (found {d}, max is {d}) in shader '{s}'\n", .{ total, max_animations, shaderName() });
        } else if (eql(t, "videoMap")) {
            const name = token(p, false);
            if (name.len == 0) {
                common.warn("missing parameter for 'videoMap' keyword in shader '{s}'\n", .{shaderName()});
                return false;
            }
            var path: [c.MAX_QPATH]u8 = undefined;
            const handle = common.ri.CIN_PlayCinematic.?(common.qpath(&path, name).ptr, 0, 0, 256, 256, c.CIN_loop | c.CIN_silent | c.CIN_shader);
            if (handle != -1) {
                stage.bundles[0].video = handle;
                stage.bundles[0].images[0] = image.scratch[@intCast(handle)];
                stage.bundles[0].num_images = 1;
            } else common.warn("could not load '{s}' for 'videoMap' keyword in shader '{s}'\n", .{ name, shaderName() });
        } else if (eql(t, "alphaFunc")) {
            const func = token(p, false);
            if (func.len == 0) {
                common.warn("missing parameter for 'alphaFunc' keyword in shader '{s}'\n", .{shaderName()});
                return false;
            }
            stage.alpha_func = if (eql(func, "GT0")) .gt0 else if (eql(func, "LT128")) .lt128 else if (eql(func, "GE128")) .ge128 else blk: {
                common.warn("invalid alphaFunc name '{s}' in shader '{s}'\n", .{ func, shaderName() });
                break :blk .none;
            };
        } else if (eql(t, "depthfunc")) {
            const func = token(p, false);
            if (func.len == 0) {
                common.warn("missing parameter for 'depthfunc' keyword in shader '{s}'\n", .{shaderName()});
                return false;
            }
            if (eql(func, "lequal")) stage.depth_equal = false else if (eql(func, "equal")) stage.depth_equal = true else common.warn("unknown depthfunc '{s}' in shader '{s}'\n", .{ func, shaderName() });
        } else if (eql(t, "detail")) {
            stage.detail = true;
        } else if (eql(t, "blendfunc")) {
            const first = token(p, false);
            if (first.len == 0) {
                common.warn("missing parm for blendFunc in shader '{s}'\n", .{shaderName()});
                continue;
            }
            if (eql(first, "add")) {
                src = Blend.one;
                dst = Blend.one;
            } else if (eql(first, "filter")) {
                src = Blend.dst_color;
                dst = Blend.zero;
            } else if (eql(first, "blend")) {
                src = Blend.src_alpha;
                dst = Blend.one_minus_src_alpha;
            } else {
                src = srcBlend(first);
                const second = token(p, false);
                if (second.len == 0) {
                    common.warn("missing parm for blendFunc in shader '{s}'\n", .{shaderName()});
                    continue;
                }
                dst = dstBlend(second);
            }
            blend_set = true;
            if (!depth_mask_explicit) stage.depth_write = false;
        } else if (eql(t, "rgbGen")) {
            const gen = token(p, false);
            if (gen.len == 0) {
                common.warn("missing parameters for rgbGen in shader '{s}'\n", .{shaderName()});
                continue;
            }
            if (eql(gen, "wave")) {
                stage.rgb_wave = parseWave(p);
                stage.rgb_gen = .wave;
            } else if (eql(gen, "const")) {
                var color = [3]f32{ 0, 0, 0 };
                _ = parseVector(p, &color);
                for (0..3) |index| stage.constant[index] = byteOf(255 * color[index]);
                stage.rgb_gen = .constant;
            } else if (eql(gen, "identity")) stage.rgb_gen = .identity else if (eql(gen, "identityLighting")) stage.rgb_gen = .identity_lighting else if (eql(gen, "entity")) stage.rgb_gen = .entity else if (eql(gen, "oneMinusEntity")) stage.rgb_gen = .one_minus_entity else if (eql(gen, "vertex")) {
                stage.rgb_gen = .vertex;
                if (stage.alpha_gen == .identity) stage.alpha_gen = .vertex;
            } else if (eql(gen, "exactVertex")) stage.rgb_gen = .exact_vertex else if (eql(gen, "lightingDiffuse")) stage.rgb_gen = .lighting_diffuse else if (eql(gen, "oneMinusVertex")) stage.rgb_gen = .one_minus_vertex else {
                common.warn("unknown rgbGen parameter '{s}' in shader '{s}'\n", .{ gen, shaderName() });
                note(gen);
            }
        } else if (eql(t, "alphaGen")) {
            const gen = token(p, false);
            if (gen.len == 0) {
                common.warn("missing parameters for alphaGen in shader '{s}'\n", .{shaderName()});
                continue;
            }
            if (eql(gen, "wave")) {
                stage.alpha_wave = parseWave(p);
                stage.alpha_gen = .wave;
            } else if (eql(gen, "const")) {
                stage.constant[3] = byteOf(255 * atof(token(p, false)));
                stage.alpha_gen = .constant;
            } else if (eql(gen, "identity")) stage.alpha_gen = .identity else if (eql(gen, "entity")) stage.alpha_gen = .entity else if (eql(gen, "oneMinusEntity")) stage.alpha_gen = .one_minus_entity else if (eql(gen, "vertex")) stage.alpha_gen = .vertex else if (eql(gen, "lightingSpecular")) stage.alpha_gen = .lighting_specular else if (eql(gen, "oneMinusVertex")) stage.alpha_gen = .one_minus_vertex else if (eql(gen, "portal")) {
                stage.alpha_gen = .portal;
                const range = token(p, false);
                if (range.len == 0) {
                    current.portal_range = 256;
                    common.warn("missing range parameter for alphaGen portal in shader '{s}', defaulting to 256\n", .{shaderName()});
                } else current.portal_range = atof(range);
            } else {
                common.warn("unknown alphaGen parameter '{s}' in shader '{s}'\n", .{ gen, shaderName() });
                note(gen);
            }
        } else if (eql(t, "texgen") or eql(t, "tcGen")) {
            const gen = token(p, false);
            if (gen.len == 0) {
                common.warn("missing texgen parm in shader '{s}'\n", .{shaderName()});
                continue;
            }
            if (eql(gen, "environment")) stage.bundles[0].tc_gen = .environment else if (eql(gen, "lightmap")) stage.bundles[0].tc_gen = .lightmap else if (eql(gen, "texture") or eql(gen, "base")) stage.bundles[0].tc_gen = .texture else if (eql(gen, "vector")) {
                _ = parseVector(p, &stage.bundles[0].tc_gen_vectors[0]);
                _ = parseVector(p, &stage.bundles[0].tc_gen_vectors[1]);
                stage.bundles[0].tc_gen = .vector;
            } else common.warn("unknown texgen parm in shader '{s}'\n", .{shaderName()});
        } else if (eql(t, "tcMod")) {
            var buffer: [1024]u8 = undefined;
            var length: usize = 0;
            while (true) {
                const part = token(p, false);
                if (part.len == 0) break;
                if (length + part.len + 1 >= buffer.len) break;
                @memcpy(buffer[length .. length + part.len], part);
                length += part.len;
                buffer[length] = ' ';
                length += 1;
            }
            parseTexMod(buffer[0..length], stage);
        } else if (eql(t, "depthwrite")) {
            stage.depth_write = true;
            depth_mask_explicit = true;
        } else {
            common.warn("unknown parameter '{s}' in shader '{s}'\n", .{ t, shaderName() });
            note(t);
            return false;
        }
    }
    // An unspecified colour generator is identity or identityLighting by blend (tr_shader.c:1053).
    if (stage.rgb_gen == .bad) {
        stage.rgb_gen = if (!blend_set or src == Blend.one or src == Blend.src_alpha) .identity_lighting else .identity;
    }
    // ONE ZERO is no blending at all.
    if (blend_set and src == Blend.one and dst == Blend.zero) {
        blend_set = false;
        stage.depth_write = true;
    }
    if (stage.alpha_gen == .identity and (stage.rgb_gen == .identity or stage.rgb_gen == .lighting_diffuse)) stage.alpha_gen = .skip;
    stage.blended = blend_set;
    stage.src = if (blend_set) src else Blend.one;
    stage.dst = if (blend_set) dst else Blend.zero;
    return true;
}

fn byteOf(value: f32) u8 {
    return @intFromFloat(std.math.clamp(@trunc(value), 0, 255));
}

fn parseDeform(p: *[*c]u8) void {
    const kind = token(p, false);
    if (kind.len == 0) {
        common.warn("missing deform parm in shader '{s}'\n", .{shaderName()});
        return;
    }
    if (current.num_deforms == max_deforms) {
        common.warn("MAX_SHADER_DEFORMS in '{s}'\n", .{shaderName()});
        return;
    }
    const deform = &current.deforms[current.num_deforms];
    deform.* = .{};
    current.num_deforms += 1;
    if (eql(kind, "projectionShadow")) {
        deform.kind = .projection_shadow;
    } else if (eql(kind, "autosprite")) {
        deform.kind = .autosprite;
    } else if (eql(kind, "autosprite2")) {
        deform.kind = .autosprite2;
    } else if (kind.len >= 4 and eql(kind[0..4], "text")) {
        deform.kind = .text;
        deform.text = if (kind.len > 4 and kind[4] >= '0' and kind[4] <= '7') kind[4] - '0' else 0;
    } else if (eql(kind, "bulge")) {
        deform.bulge_width = atof(token(p, false));
        deform.bulge_height = atof(token(p, false));
        deform.bulge_speed = atof(token(p, false));
        deform.kind = .bulge;
    } else if (eql(kind, "wave")) {
        const spread = atof(token(p, false));
        if (spread != 0) deform.spread = 1.0 / spread else {
            deform.spread = 100;
            common.warn("illegal div value of 0 in deformVertexes command for shader '{s}'\n", .{shaderName()});
        }
        deform.wave = parseWave(p);
        deform.kind = .wave;
    } else if (eql(kind, "normal")) {
        deform.wave.amplitude = atof(token(p, false));
        deform.wave.frequency = atof(token(p, false));
        deform.kind = .normals;
    } else if (eql(kind, "move")) {
        for (&deform.move) |*value| value.* = atof(token(p, false));
        deform.wave = parseWave(p);
        deform.kind = .move;
    } else {
        common.warn("unknown deformVertexes subtype '{s}' found in shader '{s}'\n", .{ kind, shaderName() });
        note(kind);
        current.num_deforms -= 1;
    }
}

const sky_suffixes = [_][]const u8{ "rt", "bk", "lf", "ft", "up", "dn" };

fn parseSky(p: *[*c]u8) void {
    const outer = token(p, false);
    if (outer.len == 0) {
        common.warn("'skyParms' missing parameter in shader '{s}'\n", .{shaderName()});
        return;
    }
    if (!std.mem.eql(u8, outer, "-")) {
        for (sky_suffixes, 0..) |suffix, index| {
            var path: [c.MAX_QPATH]u8 = undefined;
            const name = std.fmt.bufPrint(&path, "{s}_{s}.tga", .{ outer, suffix }) catch continue;
            current.sky.outer[index] = image.find(name, .{ .mipmap = true, .picmip = true, .clamp = true }) orelse image.default_image;
        }
    }
    const height = token(p, false);
    if (height.len == 0) {
        common.warn("'skyParms' missing parameter in shader '{s}'\n", .{shaderName()});
        return;
    }
    current.sky.cloud_height = atof(height);
    if (current.sky.cloud_height == 0) current.sky.cloud_height = 512;
    const inner = token(p, false);
    if (inner.len == 0) {
        common.warn("'skyParms' missing parameter in shader '{s}'\n", .{shaderName()});
        return;
    }
    if (!std.mem.eql(u8, inner, "-")) {
        for (sky_suffixes, 0..) |suffix, index| {
            var path: [c.MAX_QPATH]u8 = undefined;
            const name = std.fmt.bufPrint(&path, "{s}_{s}.tga", .{ inner, suffix }) catch continue;
            current.sky.inner[index] = image.find(name, .{ .mipmap = true, .picmip = true }) orelse image.default_image;
        }
    }
    current.is_sky = true;
}

fn parseSort(p: *[*c]u8) void {
    const value = token(p, false);
    if (value.len == 0) {
        common.warn("missing sort parameter in shader '{s}'\n", .{shaderName()});
        return;
    }
    current.sort = if (eql(value, "portal")) Sort.portal else if (eql(value, "sky")) Sort.environment else if (eql(value, "opaque")) Sort.@"opaque" else if (eql(value, "decal")) Sort.decal else if (eql(value, "seeThrough")) Sort.see_through else if (eql(value, "banner")) Sort.banner else if (eql(value, "additive")) Sort.blend1 else if (eql(value, "nearest")) Sort.nearest else if (eql(value, "underwater")) Sort.underwater else atof(value);
}

const InfoParm = struct { name: []const u8, surface: i32, contents: i32 };
const info_parms = [_]InfoParm{
    .{ .name = "water", .surface = 0, .contents = c.CONTENTS_WATER },                 .{ .name = "slime", .surface = 0, .contents = c.CONTENTS_SLIME },
    .{ .name = "lava", .surface = 0, .contents = c.CONTENTS_LAVA },                   .{ .name = "playerclip", .surface = 0, .contents = c.CONTENTS_PLAYERCLIP },
    .{ .name = "monsterclip", .surface = 0, .contents = c.CONTENTS_MONSTERCLIP },     .{ .name = "nodrop", .surface = 0, .contents = @bitCast(@as(u32, c.CONTENTS_NODROP)) },
    .{ .name = "nonsolid", .surface = c.SURF_NONSOLID, .contents = 0 },               .{ .name = "origin", .surface = 0, .contents = c.CONTENTS_ORIGIN },
    .{ .name = "trans", .surface = 0, .contents = c.CONTENTS_TRANSLUCENT },           .{ .name = "detail", .surface = 0, .contents = c.CONTENTS_DETAIL },
    .{ .name = "structural", .surface = 0, .contents = c.CONTENTS_STRUCTURAL },       .{ .name = "areaportal", .surface = 0, .contents = c.CONTENTS_AREAPORTAL },
    .{ .name = "clusterportal", .surface = 0, .contents = c.CONTENTS_CLUSTERPORTAL }, .{ .name = "donotenter", .surface = 0, .contents = c.CONTENTS_DONOTENTER },
    .{ .name = "fog", .surface = 0, .contents = c.CONTENTS_FOG },                     .{ .name = "sky", .surface = c.SURF_SKY, .contents = 0 },
    .{ .name = "lightfilter", .surface = c.SURF_LIGHTFILTER, .contents = 0 },         .{ .name = "alphashadow", .surface = c.SURF_ALPHASHADOW, .contents = 0 },
    .{ .name = "hint", .surface = c.SURF_HINT, .contents = 0 },                       .{ .name = "slick", .surface = c.SURF_SLICK, .contents = 0 },
    .{ .name = "noimpact", .surface = c.SURF_NOIMPACT, .contents = 0 },               .{ .name = "nomarks", .surface = c.SURF_NOMARKS, .contents = 0 },
    .{ .name = "ladder", .surface = c.SURF_LADDER, .contents = 0 },                   .{ .name = "nodamage", .surface = c.SURF_NODAMAGE, .contents = 0 },
    .{ .name = "metalsteps", .surface = c.SURF_METALSTEPS, .contents = 0 },           .{ .name = "flesh", .surface = c.SURF_FLESH, .contents = 0 },
    .{ .name = "nosteps", .surface = c.SURF_NOSTEPS, .contents = 0 },                 .{ .name = "nodraw", .surface = c.SURF_NODRAW, .contents = 0 },
    .{ .name = "pointlight", .surface = c.SURF_POINTLIGHT, .contents = 0 },           .{ .name = "nolightmap", .surface = c.SURF_NOLIGHTMAP, .contents = 0 },
    .{ .name = "nodlight", .surface = c.SURF_NODLIGHT, .contents = 0 },               .{ .name = "dust", .surface = c.SURF_DUST, .contents = 0 },
};

fn parseShader(p: *[*c]u8) bool {
    var stage_count: usize = 0;
    const open = token(p, true);
    if (open.len == 0 or open[0] != '{') {
        common.warn("expecting '{{', found '{s}' instead in shader '{s}'\n", .{ open, shaderName() });
        return false;
    }
    while (true) {
        const t = token(p, true);
        if (t.len == 0) {
            common.warn("no concluding '}}' in shader {s}\n", .{shaderName()});
            return false;
        }
        if (t[0] == '}') break;
        if (t[0] == '{') {
            if (stage_count >= max_stages) {
                common.warn("too many stages in shader {s} (max is {d})\n", .{ shaderName(), max_stages });
                return false;
            }
            if (!parseStage(&current.stages[stage_count], p)) return false;
            current.stages[stage_count].active = true;
            stage_count += 1;
        } else if (t.len >= 3 and eql(t[0..3], "qer")) {
            c.SkipRestOfLine(p);
        } else if (eql(t, "q3map_sun") or eql(t, "q3map_sunExt")) {
            var light = [3]f32{ atof(token(p, false)), atof(token(p, false)), atof(token(p, false)) };
            const length = @sqrt(light[0] * light[0] + light[1] * light[1] + light[2] * light[2]);
            const scale = atof(token(p, false));
            for (&light) |*value| value.* = if (length > 0) value.* / length * scale else 0;
            const a = atof(token(p, false)) / 180.0 * std.math.pi;
            const b = atof(token(p, false)) / 180.0 * std.math.pi;
            current.sun_light = light;
            current.sun_direction = .{ @cos(a) * @cos(b), @sin(a) * @cos(b), @sin(b) };
            c.SkipRestOfLine(p);
        } else if (eql(t, "deformVertexes")) {
            parseDeform(p);
        } else if (eql(t, "tesssize")) {
            c.SkipRestOfLine(p);
        } else if (eql(t, "clampTime")) {
            const value = token(p, false);
            if (value.len > 0) current.clamp_time = atof(value);
        } else if (t.len >= 5 and eql(t[0..5], "q3map")) {
            c.SkipRestOfLine(p);
        } else if (eql(t, "surfaceParm")) {
            const name = token(p, false);
            for (info_parms) |parm| if (eql(name, parm.name)) {
                current.surface_flags |= parm.surface;
                current.content_flags |= parm.contents;
                break;
            };
        } else if (eql(t, "nomipmaps")) {
            current.no_mipmaps = true;
            current.no_picmip = true;
        } else if (eql(t, "nopicmip")) {
            current.no_picmip = true;
        } else if (eql(t, "polygonOffset")) {
            current.polygon_offset = true;
        } else if (eql(t, "entityMergable")) {
            current.entity_mergable = true;
        } else if (eql(t, "fogParms")) {
            var color = [3]f32{ 0, 0, 0 };
            if (!parseVector(p, &color)) return false;
            _ = token(p, false);
            c.SkipRestOfLine(p);
        } else if (eql(t, "portal")) {
            current.sort = Sort.portal;
        } else if (eql(t, "skyparms")) {
            parseSky(p);
        } else if (eql(t, "light")) {
            _ = token(p, false);
        } else if (eql(t, "cull")) {
            const face = token(p, false);
            if (face.len == 0) {
                common.warn("missing cull parms in shader '{s}'\n", .{shaderName()});
                continue;
            }
            if (eql(face, "none") or eql(face, "twosided") or eql(face, "disable")) current.cull = .two_sided else if (eql(face, "back") or eql(face, "backside") or eql(face, "backsided")) current.cull = .back else common.warn("invalid cull parm '{s}' in shader '{s}'\n", .{ face, shaderName() });
        } else if (eql(t, "sort")) {
            parseSort(p);
        } else {
            common.warn("unknown general shader parameter '{s}' in '{s}'\n", .{ t, shaderName() });
            note(t);
            return false;
        }
    }
    current.num_stages = @intCast(stage_count);
    if (stage_count == 0 and !current.is_sky and current.content_flags & c.CONTENTS_FOG == 0) return false;
    current.explicitly_defined = true;
    return true;
}

// ---------------------------------------------------------------------------------------------
// FinishShader

fn collapseMultitexture() bool {
    const a = &current.stages[0];
    const b = &current.stages[1];
    if (!a.active or !b.active) return false;
    // Identical state apart from blending and depth writes (tr_shader.c:1836).
    if (a.alpha_func != b.alpha_func or a.depth_equal != b.depth_equal or a.depth_test != b.depth_test) return false;
    const a_blend: [2]u8 = if (a.blended) .{ a.src, a.dst } else .{ 255, 255 };
    const b_blend: [2]u8 = if (b.blended) .{ b.src, b.dst } else .{ 255, 255 };
    const none = [2]u8{ 255, 255 };
    const filter = [2]u8{ Blend.dst_color, Blend.zero };
    const filter2 = [2]u8{ Blend.zero, Blend.src_color };
    const Rule = struct { a: [2]u8, b: [2]u8, result: [2]u8 };
    // GL_MODULATE rows of the collapse table; GL_ADD rows stay separate passes.
    const rules = [_]Rule{
        .{ .a = none, .b = filter2, .result = none },
        .{ .a = none, .b = filter, .result = none },
        .{ .a = filter, .b = filter, .result = filter },
        .{ .a = filter2, .b = filter, .result = filter },
        .{ .a = filter, .b = filter2, .result = filter },
        .{ .a = filter2, .b = filter2, .result = filter },
    };
    var found: ?Rule = null;
    for (rules) |rule| {
        if (std.mem.eql(u8, &rule.a, &a_blend) and std.mem.eql(u8, &rule.b, &b_blend)) {
            found = rule;
            break;
        }
    }
    const rule = found orelse return false;
    if (a.rgb_gen != b.rgb_gen or a.alpha_gen != b.alpha_gen) return false;
    if (a.rgb_gen == .wave and !std.meta.eql(a.rgb_wave, b.rgb_wave)) return false;
    if (a.alpha_gen == .wave and !std.meta.eql(a.alpha_wave, b.alpha_wave)) return false;
    // The lightmap goes to the second bundle.
    if (a.bundles[0].is_lightmap) {
        const lightmap_bundle = a.bundles[0];
        a.bundles[0] = b.bundles[0];
        a.bundles[1] = lightmap_bundle;
    } else {
        a.bundles[1] = b.bundles[0];
    }
    if (std.mem.eql(u8, &rule.result, &none)) {
        a.blended = false;
        a.src = Blend.one;
        a.dst = Blend.zero;
    } else {
        a.blended = true;
        a.src = rule.result[0];
        a.dst = rule.result[1];
    }
    a.collapsed = true;
    var index: usize = 1;
    while (index + 1 < max_stages) : (index += 1) current.stages[index] = current.stages[index + 1];
    current.stages[max_stages - 1] = .{};
    return true;
}

fn finish() *Shader {
    var has_lightmap_stage = false;
    if (current.is_sky) current.sort = Sort.environment;
    if (current.polygon_offset and current.sort == 0) current.sort = Sort.decal;
    var stage_index: usize = 0;
    // Stages counted by the parser for explicit shaders, by `active` for implicit ones.
    var active_count: usize = 0;
    while (active_count < max_stages and current.stages[active_count].active) active_count += 1;
    while (stage_index < active_count) {
        const stage = &current.stages[stage_index];
        if (stage.bundles[0].images[0] == null) {
            common.warn("Shader {s} has a stage with no image\n", .{shaderName()});
            // tr_shader.c keeps scanning but the inactive stage ends the pass list.
            stage.active = false;
            active_count = stage_index;
            break;
        }
        if (stage.bundles[0].is_lightmap) {
            if (stage.bundles[0].tc_gen == .bad) stage.bundles[0].tc_gen = .lightmap;
            has_lightmap_stage = true;
        } else if (stage.bundles[0].tc_gen == .bad) stage.bundles[0].tc_gen = .texture;
        if (stage.blended and current.stages[0].blended and current.sort == 0) {
            current.sort = if (stage.depth_write) Sort.see_through else Sort.blend0;
        }
        stage_index += 1;
    }
    if (current.sort == 0) current.sort = Sort.@"opaque";
    var passes = active_count;
    if (passes > 1 and collapseMultitexture()) passes -= 1;
    if (current.lightmap_index >= 0 and !has_lightmap_stage) {
        common.developer("WARNING: shader '{s}' has lightmap but no lightmap stage!\n", .{shaderName()});
        current.lightmap_index = lightmap_none;
    }
    current.num_stages = @intCast(passes);
    if (passes == 0 and !current.is_sky) current.sort = Sort.fog;
    return permanent();
}

fn permanent() *Shader {
    if (shaders.items.len >= (1 << 14)) {
        common.warn("GeneratePermanentShader - MAX_SHADERS hit\n", .{});
        return default_shader;
    }
    const created = common.gpa.create(Shader) catch @panic("OOM");
    created.* = current;
    created.index = @intCast(shaders.items.len);
    shaders.append(common.gpa, created) catch @panic("OOM");
    by_name.append(common.gpa, created) catch @panic("OOM");
    return created;
}

/// Creation order list used for name lookups; tr_shader.c hashes, a linear scan of the
/// matching bucket is equivalent.
var by_name: std.ArrayList(*Shader) = .empty;

fn initShader(name: []const u8, lightmap_index: i32) void {
    current = .{};
    _ = common.qpath(&current.name, name);
    current.lightmap_index = lightmap_index;
    current.world_registration = if (lightmap_index == lightmap_2d) 0 else world_registration;
}

fn stripped(buffer: *[c.MAX_QPATH]u8, name: []const u8) []const u8 {
    return common.qpath(buffer, image.stripExtension(name));
}

/// `R_FindShaderByName`.
pub fn findByName(name: []const u8) *Shader {
    if (name.len == 0) return default_shader;
    var buffer: [c.MAX_QPATH]u8 = undefined;
    const key = stripped(&buffer, name);
    for (by_name.items) |shader| {
        if (shader.world_registration == world_registration and std.ascii.eqlIgnoreCase(shader.nameSlice(), key)) return shader;
    }
    return default_shader;
}

/// `R_FindShader`: always a shader, possibly the default one.
pub fn find(name: []const u8, requested_lightmap: i32, mip_raw_image: bool) *Shader {
    if (name.len == 0) return default_shader;
    var lightmap_index = requested_lightmap;
    if (lightmap_index >= 0 and lightmap_index >= lightmaps.len) {
        lightmap_index = lightmap_by_vertex;
    } else if (lightmap_index < lightmap_2d) {
        common.warn("shader '{s}' has invalid lightmap index of {d}\n", .{ name, lightmap_index });
        lightmap_index = lightmap_by_vertex;
    }
    var buffer: [c.MAX_QPATH]u8 = undefined;
    const key = stripped(&buffer, name);
    const registration: u32 = if (lightmap_index == lightmap_2d) 0 else world_registration;
    for (by_name.items) |shader| {
        if ((shader.lightmap_index == lightmap_index or shader.default_shader) and shader.world_registration == registration and std.ascii.eqlIgnoreCase(shader.nameSlice(), key)) return shader;
    }
    initShader(key, lightmap_index);
    if (findText(key)) |text| {
        var p = text;
        if (!parseShader(&p)) current.default_shader = true;
        return finish();
    }
    const flags: image.Flags = if (mip_raw_image) .{ .mipmap = true, .picmip = true } else .{ .clamp = true };
    const found = image.find(name, flags) orelse {
        common.developer("Couldn't find image file for shader {s}\n", .{name});
        current.default_shader = true;
        return finish();
    };
    implicitStages(found);
    return finish();
}

fn implicitStages(found: *Image) void {
    const s = &current.stages;
    if (current.lightmap_index == lightmap_none) {
        s[0].bundles[0].images[0] = found;
        s[0].active = true;
        s[0].rgb_gen = .lighting_diffuse;
    } else if (current.lightmap_index == lightmap_by_vertex) {
        s[0].bundles[0].images[0] = found;
        s[0].active = true;
        s[0].rgb_gen = .exact_vertex;
        s[0].alpha_gen = .skip;
    } else if (current.lightmap_index == lightmap_2d) {
        s[0].bundles[0].images[0] = found;
        s[0].active = true;
        s[0].rgb_gen = .vertex;
        s[0].alpha_gen = .vertex;
        s[0].depth_test = false;
        s[0].blended = true;
        s[0].src = Blend.src_alpha;
        s[0].dst = Blend.one_minus_src_alpha;
        s[0].depth_write = true;
    } else if (current.lightmap_index == lightmap_white) {
        s[0].bundles[0].images[0] = image.white;
        s[0].active = true;
        s[0].rgb_gen = .identity_lighting;
        s[1].bundles[0].images[0] = found;
        s[1].active = true;
        s[1].rgb_gen = .identity;
        s[1].blended = true;
        s[1].src = Blend.dst_color;
        s[1].dst = Blend.zero;
    } else {
        s[0].bundles[0].images[0] = lightmaps[@intCast(current.lightmap_index)];
        s[0].bundles[0].is_lightmap = true;
        s[0].active = true;
        s[0].rgb_gen = .identity;
        s[1].bundles[0].images[0] = found;
        s[1].active = true;
        s[1].rgb_gen = .identity;
        s[1].blended = true;
        s[1].src = Blend.dst_color;
        s[1].dst = Blend.zero;
    }
    for (s[0..2]) |*stage| {
        if (stage.active) stage.bundles[0].num_images = 1;
    }
}

/// `RE_RegisterShaderFromImage` (fonts and save previews registered from pixels).
pub fn fromImage(name: []const u8, requested_lightmap: i32, source: *Image) *Shader {
    var lightmap_index = requested_lightmap;
    if (lightmap_index >= lightmaps.len) lightmap_index = lightmap_white;
    const registration: u32 = if (lightmap_index == lightmap_2d) 0 else world_registration;
    for (by_name.items) |shader| {
        if ((shader.lightmap_index == lightmap_index or shader.default_shader) and shader.world_registration == registration and std.ascii.eqlIgnoreCase(shader.nameSlice(), name)) return shader;
    }
    initShader(name, lightmap_index);
    implicitStages(source);
    return finish();
}

pub fn byHandle(handle: c.qhandle_t) *Shader {
    if (handle < 0 or handle >= shaders.items.len) {
        common.warn("R_GetShaderByHandle: out of range hShader '{d}'\n", .{handle});
        return default_shader;
    }
    return shaders.items[@intCast(handle)];
}

pub fn handleOf(shader: *const Shader) c.qhandle_t {
    return if (shader.default_shader) 0 else shader.index;
}

/// `R_RemapShader`.
pub fn remap(old_name: []const u8, new_name: []const u8, time_offset: ?[]const u8) void {
    var old = findByName(old_name);
    if (old == default_shader) old = byHandle(registerLightmap(old_name, 0));
    if (old == default_shader) {
        common.warn("R_RemapShader: shader {s} not found\n", .{old_name});
        return;
    }
    var replacement = findByName(new_name);
    if (replacement == default_shader) replacement = byHandle(registerLightmap(new_name, 0));
    if (replacement == default_shader) {
        common.warn("R_RemapShader: new shader {s} not found\n", .{new_name});
        return;
    }
    var buffer: [c.MAX_QPATH]u8 = undefined;
    const key = stripped(&buffer, old_name);
    for (by_name.items) |shader| {
        if (shader.world_registration == world_registration and std.ascii.eqlIgnoreCase(shader.nameSlice(), key))
            shader.remapped = if (shader != replacement) replacement else null;
    }
    if (time_offset) |offset| replacement.time_offset = atof(offset);
}

pub fn registerLightmap(name: []const u8, lightmap_index: i32) c.qhandle_t {
    if (name.len >= c.MAX_QPATH) {
        common.info("Shader name exceeds MAX_QPATH\n", .{});
        return 0;
    }
    return handleOf(find(name, lightmap_index, true));
}

pub fn register(name: []const u8, mip: bool) c.qhandle_t {
    if (name.len >= c.MAX_QPATH) {
        common.info("Shader name exceeds MAX_QPATH\n", .{});
        return 0;
    }
    return handleOf(find(name, lightmap_2d, mip));
}

pub fn init() void {
    common.info("Initializing Shaders\n", .{});
    initShader("<default>", lightmap_none);
    current.stages[0].bundles[0].images[0] = image.default_image;
    current.stages[0].bundles[0].num_images = 1;
    current.stages[0].active = true;
    default_shader = finish();
    initShader("<stencil shadow>", lightmap_none);
    current.sort = Sort.stencil_shadow;
    shadow_shader = finish();
    scanFiles();
}

pub fn shutdown() void {
    for (shaders.items) |shader| common.gpa.destroy(shader);
    shaders.clearAndFree(common.gpa);
    by_name.clearAndFree(common.gpa);
    if (shader_text) |text| common.gpa.free(text);
    shader_text = null;
    var iterator = text_index.iterator();
    while (iterator.next()) |entry| {
        common.gpa.free(entry.key_ptr.*);
        entry.value_ptr.deinit(common.gpa);
    }
    text_index.clearAndFree(common.gpa);
    lightmaps = &.{};
    world_registration = 0;
}

pub fn shaderCount() usize {
    return shaders.items.len;
}

pub fn list() void {
    common.info("-----------------------\n", .{});
    for (shaders.items) |shader| {
        common.info("{d} {s}{s}{s}: {s}{s}\n", .{
            shader.num_stages,
            if (shader.lightmap_index >= 0) "L " else "  ",
            if (shader.num_stages > 0 and shader.stages[0].collapsed) "MT(m) " else "      ",
            if (shader.explicitly_defined) "E " else "  ",
            shader.nameSlice(),
            if (shader.default_shader) " (DEFAULTED)" else "",
        });
    }
    common.info("{d} total shaders\n------------------\n", .{shaders.items.len});
}

/// `r_vkMaterialScan 1`: compile every named definition once, as 2D materials, and report
/// keywords this compiler does not handle.
pub fn scanAll() void {
    var compiled: usize = 0;
    var iterator = text_index.iterator();
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(common.gpa);
    while (iterator.next()) |entry| names.append(common.gpa, entry.key_ptr.*) catch break;
    for (names.items) |name| {
        _ = find(name, lightmap_2d, true);
        compiled += 1;
    }
    common.info("dk3 vulkan material scan: definitions={d} shaders={d} unknown_keywords={d}\n", .{ compiled, shaders.items.len, unknown_keywords.count() });
    var unknown = unknown_keywords.iterator();
    while (unknown.next()) |entry| common.info("dk3 vulkan material scan: unknown '{s}' x{d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
}

// ---------------------------------------------------------------------------------------------
// Resident preparation: `R_QueueShaderImages` (dk3_shader_prefetch.inc).

pub fn queueImages(batch: ?*cext.ImageBatch, name: []const u8) bool {
    var buffer: [c.MAX_QPATH]u8 = undefined;
    const key = stripped(&buffer, name);
    var p = findText(key) orelse return image.prepare(batch, name);
    var depth: i32 = 0;
    while (true) {
        const t = token(&p, true);
        if (t.len == 0) break;
        if (std.mem.eql(u8, t, "{")) {
            depth += 1;
            continue;
        }
        if (std.mem.eql(u8, t, "}")) {
            depth -= 1;
            if (depth <= 0) break;
            continue;
        }
        if (depth == 2 and (eql(t, "map") or eql(t, "clampmap"))) {
            if (!image.prepare(batch, token(&p, false))) return false;
        } else if (depth == 2 and eql(t, "animMap")) {
            _ = token(&p, false);
            var index: usize = 0;
            while (true) {
                const frame = token(&p, false);
                if (frame.len == 0) break;
                if (index < max_animations and !image.prepare(batch, frame)) return false;
                index += 1;
            }
        } else if (depth == 1 and eql(t, "skyparms")) {
            for (0..2) |box| {
                const prefix = token(&p, false);
                var copy: [c.MAX_QPATH]u8 = undefined;
                const kept = common.qpath(&copy, prefix);
                if (kept.len > 0 and !std.mem.eql(u8, kept, "-")) for (sky_suffixes) |suffix| {
                    var path: [c.MAX_QPATH]u8 = undefined;
                    const sky_name = std.fmt.bufPrint(&path, "{s}_{s}.tga", .{ kept, suffix }) catch continue;
                    if (!image.prepare(batch, sky_name)) return false;
                };
                if (box == 0) _ = token(&p, false);
            }
        }
    }
    return true;
}
