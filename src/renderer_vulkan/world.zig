// SPDX-License-Identifier: GPL-2.0-or-later
//! IBSP v46 worlds as resident regions: staged admission, selection, visibility, light grid,
//! DKLS lightstyle blocks, brush models and mark fragments. Behaviour follows renderergl1
//! tr_bsp.c, tr_world.c, tr_light.c, tr_marks.c and renderercommon dk3_worlds.inc /
//! dk3_lightstyles.inc. Each world owns a static device-addressable vertex buffer.
const std = @import("std");
const c = @import("c.zig").c;
const cext = @import("c.zig");
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const image = @import("image.zig");
const shader_mod = @import("shader.zig");
const scene = @import("scene.zig");
const Shader = shader_mod.Shader;
const Vec3 = scene.Vec3;
const Vertex = scene.Vertex;

pub const max_worlds = 128;
pub const max_inline_models = 512;
const lightmap_size = 128;
const generation_max: u32 = 0x3fff;

pub const SurfaceKind = enum(u8) { face, triangles, patch, flare };

pub const Surface = struct {
    shader: *Shader,
    kind: SurfaceKind,
    first_index: u32 = 0,
    num_indexes: u32 = 0,
    mins: Vec3 = .{ 0, 0, 0 },
    maxs: Vec3 = .{ 0, 0, 0 },
    plane_normal: Vec3 = .{ 0, 0, 0 },
    plane_dist: f32 = 0,
    /// Liquid volume this surface bounds (remaster water shading), found from brush contents.
    liquid: image.Liquid = .none,
    view_count: u32 = 0,
    /// Patch grid for mark fragments: vertices are contiguous rows of `grid_width`.
    grid_width: u32 = 0,
    grid_height: u32 = 0,
    first_vertex: u32 = 0,
};

const Node = struct {
    plane: u32,
    children: [2]i32,
    mins: Vec3,
    maxs: Vec3,
    parent: i32,
    visframe: u32 = 0,
};

const Leaf = struct {
    cluster: i32,
    area: i32,
    mins: Vec3,
    maxs: Vec3,
    first_mark: u32,
    first_brush: u32 = 0,
    num_brushes: u32 = 0,
    num_marks: u32,
    parent: i32,
    visframe: u32 = 0,
};

pub const BModel = struct {
    mins: Vec3,
    maxs: Vec3,
    first_surface: u32,
    num_surfaces: u32,
};

const LightBlock = struct {
    page: u32,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
    count: u32,
    styles: [4]u32,
    scale: f32,
    previous: [4]f32,
    samples: []u8,
};

const Status = enum { free, reading, ready, failed };

pub const World = struct {
    index: u32,
    generation: u32,
    status: Status = .free,
    name: [c.MAX_QPATH]u8 = undefined,
    read: ?*c.struct_fsReadJob_s = null,
    admission: u32 = 0,
    peak: [6]i32 = .{ 0, 0, 0, 0, 0, 0 },
    // Raw lumps copied out of the file during admission.
    shaders_lump: []c.dshader_t = &.{},
    surfaces_lump: []c.dsurface_t = &.{},
    draw_verts: []c.drawVert_t = &.{},
    draw_indexes: []i32 = &.{},
    lightmap_bytes: []u8 = &.{},
    lightmap_next: u32 = 0,
    surface_next: u32 = 0,
    image_batch: ?*cext.ImageBatch = null,
    materials_ready: []bool = &.{},
    // Resident data.
    lightmaps: []*image.Image = &.{},
    planes: []c.dplane_t = &.{},
    nodes: []Node = &.{},
    leafs: []Leaf = &.{},
    marks: []u32 = &.{},
    bmodels: []BModel = &.{},
    surfaces: []Surface = &.{},
    vertices: std.ArrayList(Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,
    vertex_buffer: vk.Buffer = .{},
    vis: []u8 = &.{},
    novis: []u8 = &.{},
    num_clusters: i32 = 0,
    cluster_bytes: i32 = 0,
    entity_string: [:0]u8 = undefined,
    entity_parse: [*c]u8 = null,
    has_entities: bool = false,
    light_grid: []u8 = &.{},
    grid_size: Vec3 = .{ 64, 64, 128 },
    grid_origin: Vec3 = .{ 0, 0, 0 },
    grid_bounds: [3]i32 = .{ 0, 0, 0 },
    light_blocks: []LightBlock = &.{},
    brushes: []c.dbrush_t = &.{},
    brush_sides: []c.dbrushside_t = &.{},
    leaf_brushes: []i32 = &.{},
    /// Remaster: dominant light direction and directionality of the light grid (RGBA8 3D texture).
    grid_volume: vk.Texture = .{},
    grid_slot: ?u32 = null,
    /// Remaster: total incident light colour of the light grid (volumetric in-scattering).
    grid_color: vk.Texture = .{},
    grid_color_slot: u32 = 0,
    /// Ray tracing structures and hit tables (rt.zig), built once the world is resident.
    rt: @import("rt.zig").WorldRt = .{},
    bake: @import("bake.zig").WorldBake = .{},
    view_count: u32 = 0,
    vis_count: u32 = 0,
    view_cluster: i32 = -1,
    areamask: [c.MAX_MAP_AREA_BYTES]u8 = std.mem.zeroes([c.MAX_MAP_AREA_BYTES]u8),
    sky_view: u32 = 0,
    /// Linear radiance of the sky (skyRadiance), computed once.
    sky_radiance: ?[3]f32 = null,
    /// Linear luminance of the sky's light, from the original radiosity (calibrateSky).
    sky_level: f32 = 0,

    pub fn handle(self: *const World) u32 {
        return (self.generation << 8) | (self.index + 1);
    }

    pub fn nameSlice(self: *const World) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

var worlds: [max_worlds]World = blk: {
    var list: [max_worlds]World = undefined;
    for (&list, 0..) |*w, i| w.* = .{ .index = i, .generation = 0 };
    break :blk list;
};
var selected: ?*World = null;
var loading: ?*World = null;

pub fn registration() u32 {
    return if (selected) |w| w.handle() else 0;
}

pub fn current() ?*World {
    return selected;
}

pub fn sunDirection() Vec3 {
    return scene.normalize(.{ 0.45, 0.3, 0.9 });
}

fn resident(handle_value: u32) ?*World {
    const index = handle_value & 255;
    if (index == 0 or index > max_worlds) return null;
    const w = &worlds[index - 1];
    if (w.status == .free or w.generation != (handle_value >> 8)) return null;
    return w;
}

fn applyShaderContext(w: ?*World) void {
    shader_mod.world_registration = if (w) |world_value| world_value.handle() else 0;
    shader_mod.lightmaps = if (w) |world_value| world_value.lightmaps else &.{};
}

/// `RE_SelectWorld`.
pub fn select(handle_value: u32) bool {
    const w = resident(handle_value) orelse return false;
    if (w.status != .ready) return false;
    selected = w;
    w.view_cluster = -1;
    applyShaderContext(w);
    return true;
}

fn reserve(name: []const u8) ?*World {
    if (!std.mem.startsWith(u8, name, "maps/") or !std.ascii.endsWithIgnoreCase(name, ".bsp") or name.len >= c.MAX_QPATH) return null;
    for (&worlds) |*w| {
        if (w.status != .free or w.generation == generation_max) continue;
        if (w.generation == 0) w.generation = 1;
        const generation = w.generation;
        w.* = .{ .index = w.index, .generation = generation, .status = .reading };
        _ = common.qpath(&w.name, name);
        return w;
    }
    return null;
}

/// `RE_RequestWorld`.
pub fn request(name_ptr: [*c]const u8) u32 {
    const name = common.span(name_ptr);
    if (name.len == 0) return 0;
    var reading: u32 = 0;
    for (&worlds) |*w| {
        if (w.status != .free and std.mem.eql(u8, w.nameSlice(), name)) return w.handle();
        if (w.read != null) reading += 1;
    }
    if (reading >= 4) return 0;
    const w = reserve(name) orelse return 0;
    var path: [c.MAX_QPATH]u8 = undefined;
    w.read = common.ri.BeginBackgroundRead.?(common.qpath(&path, name).ptr, 128 * 1024 * 1024);
    if (w.read == null) w.status = .failed;
    return w.handle();
}

fn validHeader(bytes: []const u8) bool {
    if (bytes.len < @sizeOf(c.dheader_t)) return false;
    var header: c.dheader_t = undefined;
    @memcpy(std.mem.asBytes(&header), bytes[0..@sizeOf(c.dheader_t)]);
    if (header.ident != c.BSP_IDENT or header.version != c.BSP_VERSION) return false;
    for (header.lumps) |entry| {
        if (entry.fileofs < 0 or entry.filelen < 0 or entry.fileofs > bytes.len or entry.filelen > bytes.len - @as(usize, @intCast(entry.fileofs))) return false;
    }
    return true;
}

/// `RE_PollWorld`: 1 ready, 0 pending, -1 failed.
pub fn poll(handle_value: u32) c_int {
    const w = resident(handle_value) orelse return -1;
    switch (w.status) {
        .failed => return -1,
        .ready => return 1,
        else => {},
    }
    const job = w.read orelse return -1;
    var bytes_ptr: ?*const anyopaque = null;
    var length: c_int = 0;
    const result = common.ri.PollBackgroundRead.?(job, &bytes_ptr, &length);
    if (result == 0) return 0;
    if (result == 1 and bytes_ptr != null) {
        const bytes = @as([*]const u8, @ptrCast(bytes_ptr.?))[0..@intCast(length)];
        if (w.admission != 0 or validHeader(bytes)) {
            if (!admit(w, bytes) and w.status != .failed) return 0;
        } else w.status = .failed;
    } else w.status = .failed;
    if (w.status == .failed) {
        cext.R_FreeImageBatch(w.image_batch);
        w.image_batch = null;
    }
    common.ri.EndBackgroundRead.?(job);
    w.read = null;
    return if (w.status == .ready) 1 else -1;
}

/// `RE_LoadWorldMap`: synchronous admission of the first world, then selection.
pub fn load(name_ptr: [*c]const u8) void {
    if (selected != null) common.fail(c.ERR_DROP, "World already selected; use resident selection", .{});
    const name = common.span(name_ptr);
    const w = reserve(name) orelse common.fail(c.ERR_DROP, "Cannot reserve render world {s}", .{name});
    var path: [c.MAX_QPATH]u8 = undefined;
    const bytes = common.readFile(common.qpath(&path, name).ptr) orelse common.fail(c.ERR_DROP, "Invalid render world {s}", .{name});
    defer common.freeFile(bytes);
    if (!validHeader(bytes)) common.fail(c.ERR_DROP, "Invalid render world {s}", .{name});
    while (!admit(w, bytes)) {
        if (w.status == .failed) {
            cext.R_FreeImageBatch(w.image_batch);
            w.image_batch = null;
            common.fail(c.ERR_DROP, "Cannot prepare render world {s}", .{name});
        }
    }
    _ = select(w.handle());
}

pub fn shutdown() void {
    for (&worlds) |*w| {
        cext.R_FreeImageBatch(w.image_batch);
        if (w.read) |job| common.ri.EndBackgroundRead.?(job);
        freeWorld(w);
        const generation = w.generation;
        w.* = .{ .index = w.index, .generation = if (generation < generation_max) generation + 1 else generation };
    }
    selected = null;
    loading = null;
    applyShaderContext(null);
}

fn freeWorld(w: *World) void {
    const a = common.gpa;
    if (w.status == .free) return;
    @import("bake.zig").destroyWorld(&w.bake);
    @import("rt.zig").destroyWorld(&w.rt);
    vk.destroyBuffer(&w.vertex_buffer);
    a.free(w.shaders_lump);
    a.free(w.surfaces_lump);
    a.free(w.draw_verts);
    a.free(w.draw_indexes);
    a.free(w.lightmap_bytes);
    a.free(w.materials_ready);
    a.free(w.lightmaps);
    a.free(w.planes);
    a.free(w.nodes);
    a.free(w.leafs);
    a.free(w.marks);
    a.free(w.bmodels);
    a.free(w.surfaces);
    w.vertices.deinit(a);
    w.indices.deinit(a);
    if (w.vis.len > 0) a.free(w.vis);
    a.free(w.novis);
    if (w.has_entities) a.free(w.entity_string);
    a.free(w.light_grid);
    vk.destroyImage(&w.grid_volume);
    vk.destroyImage(&w.grid_color);
    a.free(w.brushes);
    a.free(w.brush_sides);
    a.free(w.leaf_brushes);
    for (w.light_blocks) |block| a.free(block.samples);
    a.free(w.light_blocks);
}

// ---------------------------------------------------------------------------------------------
// Admission

fn lump(bytes: []const u8, index: usize) []const u8 {
    var header: c.dheader_t = undefined;
    @memcpy(std.mem.asBytes(&header), bytes[0..@sizeOf(c.dheader_t)]);
    const entry = header.lumps[index];
    const start: usize = @intCast(entry.fileofs);
    return bytes[start .. start + @as(usize, @intCast(entry.filelen))];
}

fn copyLump(comptime T: type, w: *World, bytes: []const u8, index: usize) []T {
    const data = lump(bytes, index);
    if (data.len % @sizeOf(T) != 0) common.fail(c.ERR_DROP, "LoadMap: funny lump size in {s}", .{w.nameSlice()});
    const out = common.gpa.alloc(T, data.len / @sizeOf(T)) catch @panic("OOM");
    @memcpy(std.mem.sliceAsBytes(out), data);
    return out;
}

/// Runs one admission phase within a small time budget; true when the world is ready.
fn admit(w: *World, bytes: []const u8) bool {
    const previous = selected;
    loading = w;
    applyShaderContext(w);
    const phase = w.admission;
    const started = common.milliseconds();
    const done = decode(w, bytes);
    if (done and w.status != .failed) w.status = .ready;
    loading = null;
    applyShaderContext(previous);
    const elapsed = common.milliseconds() - started;
    if (phase < w.peak.len and elapsed > w.peak[phase]) w.peak[phase] = elapsed;
    if (done) common.developer("dk3 render admission: map={s} peak_ms init={d} definitions={d} lightmaps={d} fog={d} surfaces={d} finalize={d} uploads={d} pages={d}\n", .{ w.nameSlice(), w.peak[0], w.peak[1], w.peak[2], w.peak[3], w.peak[4], w.peak[5], w.lightmap_next, w.lightmaps.len });
    return done;
}

fn decode(w: *World, bytes: []const u8) bool {
    switch (w.admission) {
        0 => {
            loadLightstyles(w, bytes);
            w.shaders_lump = copyLump(c.dshader_t, w, bytes, c.LUMP_SHADERS);
            w.surfaces_lump = copyLump(c.dsurface_t, w, bytes, c.LUMP_SURFACES);
            w.draw_verts = copyLump(c.drawVert_t, w, bytes, c.LUMP_DRAWVERTS);
            w.draw_indexes = copyLump(i32, w, bytes, c.LUMP_DRAWINDEXES);
            const lightmaps = lump(bytes, c.LUMP_LIGHTMAPS);
            if (lightmaps.len % (lightmap_size * lightmap_size * 3) != 0) common.fail(c.ERR_DROP, "Invalid lightmap lump size", .{});
            w.lightmap_bytes = common.gpa.dupe(u8, lightmaps) catch @panic("OOM");
            var count = lightmaps.len / (lightmap_size * lightmap_size * 3);
            // Maps with a single lightmap turn fullbright without a second one (tr_bsp.c HACK).
            if (count == 1) count = 2;
            w.lightmaps = common.gpa.alloc(*image.Image, count) catch @panic("OOM");
            w.materials_ready = common.gpa.alloc(bool, w.shaders_lump.len) catch @panic("OOM");
            @memset(w.materials_ready, false);
            w.surfaces = common.gpa.alloc(Surface, w.surfaces_lump.len) catch @panic("OOM");
            w.admission = 2;
            return false;
        },
        2 => {
            if (!loadLightmaps(w)) return false;
            applyShaderContext(w);
            w.admission = 3;
            return false;
        },
        3 => {
            w.planes = copyLump(c.dplane_t, w, bytes, c.LUMP_PLANES);
            w.admission = 4;
            return false;
        },
        4 => {
            if (!loadSurfaces(w)) return false;
            w.admission = 5;
            return false;
        },
        else => {
            loadMarks(w, bytes);
            w.brushes = copyLump(c.dbrush_t, w, bytes, c.LUMP_BRUSHES);
            w.brush_sides = copyLump(c.dbrushside_t, w, bytes, c.LUMP_BRUSHSIDES);
            w.leaf_brushes = copyLump(i32, w, bytes, c.LUMP_LEAFBRUSHES);
            loadNodesAndLeafs(w, bytes);
            loadSubmodels(w, bytes);
            loadVisibility(w, bytes);
            loadEntities(w, bytes);
            loadLightGrid(w, bytes);
            finishGeometry(w);
            classifyLiquids(w);
            return true;
        },
    }
}

pub fn half(value: f32) u16 {
    return @bitCast(@as(f16, @floatCast(value)));
}

/// A stored lightmap texel (0-1 per channel) as linear radiance. The overbright shift is
/// applied as renderergl1 does (R_ColorShiftLightingBytes): a texel whose brightest channel
/// exceeds white is scaled back so that channel sits at white, keeping its hue, since the maps
/// were lit for that display. The remaster keeps a quarter stop of headroom above white for
/// exposure and bloom instead of the full shifted range, which washed every lit surface out.
fn linearLight(rgb: [3]f32) [3]f32 {
    const scale = std.math.pow(f32, 2, @floatFromInt(std.math.clamp(cvars.mapOverBrightBits.integer, 0, 8)));
    var out = rgb;
    for (&out) |*value| value.* *= scale;
    const peak = @max(out[0], @max(out[1], out[2]));
    if (peak > 1) {
        const limit = 1 + 0.25 * (1 - @exp(-(peak - 1)));
        for (&out) |*value| value.* *= limit / peak;
    }
    for (&out) |*value| value.* = std.math.pow(f32, value.*, 2.2);
    return out;
}

fn colorShift(input: [3]u8) [3]u8 {
    const shift: u5 = @intCast(std.math.clamp(cvars.mapOverBrightBits.integer, 0, 8));
    var r: u32 = @as(u32, input[0]) << shift;
    var g: u32 = @as(u32, input[1]) << shift;
    var b: u32 = @as(u32, input[2]) << shift;
    if ((r | g | b) > 255) {
        const max = @max(r, @max(g, b));
        r = r * 255 / max;
        g = g * 255 / max;
        b = b * 255 / max;
    }
    return .{ @intCast(r), @intCast(g), @intCast(b) };
}

fn loadLightmaps(w: *World) bool {
    const started = common.milliseconds();
    const on_disk = w.lightmap_bytes.len / (lightmap_size * lightmap_size * 3);
    var pixels: [lightmap_size * lightmap_size * 4]u8 = undefined;
    while (w.lightmap_next < w.lightmaps.len) {
        const i = w.lightmap_next;
        const source = if (on_disk == 0) &[_]u8{} else w.lightmap_bytes[(i % on_disk) * lightmap_size * lightmap_size * 3 ..][0 .. lightmap_size * lightmap_size * 3];
        var name: [c.MAX_QPATH]u8 = undefined;
        const label = std.fmt.bufPrint(&name, "*w{d}/lightmap{d}", .{ w.handle(), i }) catch "*lightmap";
        if (@import("window.zig").remaster) {
            // Linear radiance with the full overbright range instead of the normalized bytes.
            var texels: [lightmap_size * lightmap_size * 4]u16 = undefined;
            for (0..lightmap_size * lightmap_size) |j| {
                const linear = if (source.len == 0) [3]f32{ 0, 0, 0 } else linearLight(.{
                    @as(f32, @floatFromInt(source[j * 3])) / 255.0,
                    @as(f32, @floatFromInt(source[j * 3 + 1])) / 255.0,
                    @as(f32, @floatFromInt(source[j * 3 + 2])) / 255.0,
                });
                for (0..3) |k| texels[j * 4 + k] = half(linear[k]);
                texels[j * 4 + 3] = half(1);
            }
            w.lightmaps[i] = image.createRaw(label, std.mem.sliceAsBytes(&texels), lightmap_size, lightmap_size, c.VK_FORMAT_R16G16B16A16_SFLOAT, .{ .no_light_scale = true, .clamp = true });
        } else {
            for (0..lightmap_size * lightmap_size) |j| {
                const shifted = if (source.len == 0) [3]u8{ 0, 0, 0 } else colorShift(.{ source[j * 3], source[j * 3 + 1], source[j * 3 + 2] });
                pixels[j * 4 ..][0..4].* = .{ shifted[0], shifted[1], shifted[2], 255 };
            }
            w.lightmaps[i] = image.create(label, &pixels, lightmap_size, lightmap_size, .{ .no_light_scale = true, .clamp = true });
        }
        w.lightmap_next = i + 1;
        if (w.lightmap_next < w.lightmaps.len and common.milliseconds() - started >= 4) return false;
    }
    return true;
}

fn shaderFor(w: *World, shader_num: i32, lightmap_num: i32) *Shader {
    if (shader_num < 0 or shader_num >= w.shaders_lump.len) common.fail(c.ERR_DROP, "ShaderForShaderNum: bad num {d}", .{shader_num});
    const name = common.span(&w.shaders_lump[@intCast(shader_num)].shader);
    const lightmap = if (cvars.fullbright.integer != 0) shader_mod.lightmap_white else lightmap_num;
    const found = shader_mod.find(name, lightmap, true);
    return if (found.default_shader) shader_mod.default_shader else found;
}

/// Materials compile surface by surface; each material's PNGs decode on worker threads first
/// (R_LoadSurfaces with R_QueueShaderImages).
fn loadSurfaces(w: *World) bool {
    const started = common.milliseconds();
    while (w.surface_next < w.surfaces_lump.len) {
        const i = w.surface_next;
        const in = w.surfaces_lump[i];
        const material = in.shaderNum;
        if (material < 0 or material >= w.shaders_lump.len) common.fail(c.ERR_DROP, "Invalid resident material index", .{});
        const index: usize = @intCast(material);
        if (!w.materials_ready[index]) {
            if (w.image_batch == null) {
                w.image_batch = cext.R_CreateImageBatch(shader_mod.max_stages * shader_mod.max_animations + 12);
                if (w.image_batch == null or !shader_mod.queueImages(w.image_batch, common.span(&w.shaders_lump[index].shader))) {
                    common.warn("Cannot prepare resident material {s}\n", .{common.span(&w.shaders_lump[index].shader)});
                    w.status = .failed;
                    return false;
                }
            }
            const ready = cext.R_PollImageBatch(w.image_batch);
            if (ready < 0) w.status = .failed;
            if (ready <= 0) return false;
            cext.R_SelectImageBatch(w.image_batch);
        }
        w.surfaces[i] = .{ .shader = shaderFor(w, in.shaderNum, in.lightmapNum), .kind = switch (in.surfaceType) {
            c.MST_PLANAR => .face,
            c.MST_TRIANGLE_SOUP => .triangles,
            c.MST_PATCH => .patch,
            c.MST_FLARE => .flare,
            else => common.fail(c.ERR_DROP, "Bad surfaceType", .{}),
        } };
        cext.R_SelectImageBatch(null);
        cext.R_FreeImageBatch(w.image_batch);
        w.image_batch = null;
        w.materials_ready[index] = true;
        w.surface_next = i + 1;
        if (w.surface_next < w.surfaces_lump.len and (common.milliseconds() - started >= 4 or (i & 63) == 63)) return false;
    }
    return true;
}

fn vertexOf(in: c.drawVert_t) Vertex {
    const shifted = colorShift(.{ in.color[0], in.color[1], in.color[2] });
    return .{ .pos = in.xyz, .st = in.st, .lm = in.lightmap, .normal = in.normal, .color = .{ shifted[0], shifted[1], shifted[2], in.color[3] } };
}

fn boundsOf(w: *World, first: u32, count: u32) [2]Vec3 {
    var mins: Vec3 = .{ 1e30, 1e30, 1e30 };
    var maxs: Vec3 = .{ -1e30, -1e30, -1e30 };
    for (w.vertices.items[first .. first + count]) |v| for (0..3) |k| {
        mins[k] = @min(mins[k], v.pos[k]);
        maxs[k] = @max(maxs[k], v.pos[k]);
    };
    return .{ mins, maxs };
}

fn lerpVertex(a: Vertex, b: Vertex, t: f32) Vertex {
    var out: Vertex = undefined;
    for (0..3) |k| out.pos[k] = a.pos[k] + (b.pos[k] - a.pos[k]) * t;
    for (0..3) |k| out.normal[k] = a.normal[k] + (b.normal[k] - a.normal[k]) * t;
    for (0..2) |k| out.st[k] = a.st[k] + (b.st[k] - a.st[k]) * t;
    for (0..2) |k| out.lm[k] = a.lm[k] + (b.lm[k] - a.lm[k]) * t;
    for (0..4) |k| out.color[k] = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(a.color[k])) + (@as(f32, @floatFromInt(b.color[k])) - @as(f32, @floatFromInt(a.color[k]))) * t, 0, 255));
    out.pad = 0;
    return out;
}

fn quadratic(p0: Vertex, p1: Vertex, p2: Vertex, t: f32) Vertex {
    return lerpVertex(lerpVertex(p0, p1, t), lerpVertex(p1, p2, t), t);
}

/// Biquadratic patch tessellation at a fixed subdivision per 3x3 control block.
fn tessellatePatch(w: *World, surface: *Surface, in: c.dsurface_t) void {
    const width: u32 = @intCast(in.patchWidth);
    const height: u32 = @intCast(in.patchHeight);
    if (width < 3 or height < 3 or width % 2 == 0 or height % 2 == 0) return;
    const control = w.draw_verts[@intCast(in.firstVert)..][0 .. width * height];
    const level: u32 = @intCast(std.math.clamp(64 / @max(cvars.subdivisions.integer, 1), 2, 16));
    const columns = (width - 1) / 2 * level + 1;
    const rows = (height - 1) / 2 * level + 1;
    const first: u32 = @intCast(w.vertices.items.len);
    for (0..rows) |row| {
        const block_y = @min(row / level, (height - 1) / 2 - 1);
        const ty = @as(f32, @floatFromInt(row - block_y * level)) / @as(f32, @floatFromInt(level));
        for (0..columns) |column| {
            const block_x = @min(column / level, (width - 1) / 2 - 1);
            const tx = @as(f32, @floatFromInt(column - block_x * level)) / @as(f32, @floatFromInt(level));
            var curve: [3]Vertex = undefined;
            for (0..3) |k| {
                const base = (block_y * 2 + k) * width + block_x * 2;
                curve[k] = quadratic(vertexOf(control[base]), vertexOf(control[base + 1]), vertexOf(control[base + 2]), tx);
            }
            var v = quadratic(curve[0], curve[1], curve[2], ty);
            v.normal = scene.normalize(v.normal);
            w.vertices.append(common.gpa, v) catch @panic("OOM");
        }
    }
    surface.first_index = @intCast(w.indices.items.len);
    for (0..rows - 1) |row| for (0..columns - 1) |column| {
        const a: u32 = first + @as(u32, @intCast(row * columns + column));
        const b = a + @as(u32, @intCast(columns));
        w.indices.appendSlice(common.gpa, &.{ a, b, a + 1, a + 1, b, b + 1 }) catch @panic("OOM");
    };
    surface.num_indexes = @as(u32, @intCast(w.indices.items.len)) - surface.first_index;
    surface.grid_width = @intCast(columns);
    surface.grid_height = @intCast(rows);
    surface.first_vertex = first;
    const box = boundsOf(w, first, @intCast(rows * columns));
    surface.mins = box[0];
    surface.maxs = box[1];
}

fn finishGeometry(w: *World) void {
    const a = common.gpa;
    w.vertices.ensureTotalCapacity(a, w.draw_verts.len) catch @panic("OOM");
    for (w.draw_verts) |v| w.vertices.appendAssumeCapacity(vertexOf(v));
    for (w.surfaces_lump, 0..) |in, i| {
        const surface = &w.surfaces[i];
        switch (surface.kind) {
            .face, .triangles => {
                const first_vert: u32 = @intCast(in.firstVert);
                const count: u32 = @intCast(in.numVerts);
                if (in.numIndexes < 0 or in.firstIndex < 0 or in.firstIndex + in.numIndexes > w.draw_indexes.len or in.firstVert + in.numVerts > w.draw_verts.len) {
                    surface.kind = .flare;
                    continue;
                }
                surface.first_index = @intCast(w.indices.items.len);
                for (w.draw_indexes[@intCast(in.firstIndex)..][0..@intCast(in.numIndexes)]) |index| {
                    if (index < 0 or index >= in.numVerts) common.fail(c.ERR_DROP, "Bad index in face surface", .{});
                    w.indices.append(a, first_vert + @as(u32, @intCast(index))) catch @panic("OOM");
                }
                surface.num_indexes = @intCast(in.numIndexes);
                const box = boundsOf(w, first_vert, count);
                surface.mins = box[0];
                surface.maxs = box[1];
                if (surface.kind == .face) {
                    surface.plane_normal = in.lightmapVecs[2];
                    surface.plane_dist = if (count > 0) scene.dot(w.vertices.items[first_vert].pos, surface.plane_normal) else 0;
                }
            },
            .patch => tessellatePatch(w, surface, in),
            .flare => {},
        }
    }
    w.vertex_buffer = vk.staticBuffer(std.mem.sliceAsBytes(w.vertices.items), @as(c.VkBufferUsageFlags, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT) | vk.rtInputUsage());
    // The raw lumps are only needed during admission.
    a.free(w.draw_verts);
    w.draw_verts = &.{};
    a.free(w.draw_indexes);
    w.draw_indexes = &.{};
    calibrateSky(w);
    a.free(w.lightmap_bytes);
    w.lightmap_bytes = &.{};
    var faces: u32 = 0;
    var meshes: u32 = 0;
    var tris: u32 = 0;
    var flares: u32 = 0;
    for (w.surfaces) |surface| switch (surface.kind) {
        .face => faces += 1,
        .patch => meshes += 1,
        .triangles => tris += 1,
        .flare => flares += 1,
    };
    common.info("...loaded {d} faces, {d} meshes, {d} trisurfs, {d} flares\n", .{ faces, meshes, tris, flares });
}

fn loadMarks(w: *World, bytes: []const u8) void {
    const raw = copyLump(i32, w, bytes, c.LUMP_LEAFSURFACES);
    defer common.gpa.free(raw);
    w.marks = common.gpa.alloc(u32, raw.len) catch @panic("OOM");
    for (raw, w.marks) |value, *out| {
        if (value < 0 or value >= w.surfaces.len) common.fail(c.ERR_DROP, "Bad leaf surface in {s}", .{w.nameSlice()});
        out.* = @intCast(value);
    }
}

fn toVec(v: [3]c_int) Vec3 {
    return .{ @floatFromInt(v[0]), @floatFromInt(v[1]), @floatFromInt(v[2]) };
}

fn loadNodesAndLeafs(w: *World, bytes: []const u8) void {
    const nodes = copyLump(c.dnode_t, w, bytes, c.LUMP_NODES);
    defer common.gpa.free(nodes);
    const leafs = copyLump(c.dleaf_t, w, bytes, c.LUMP_LEAFS);
    defer common.gpa.free(leafs);
    w.nodes = common.gpa.alloc(Node, nodes.len) catch @panic("OOM");
    w.leafs = common.gpa.alloc(Leaf, leafs.len) catch @panic("OOM");
    for (nodes, w.nodes) |in, *out| out.* = .{ .plane = @intCast(in.planeNum), .children = in.children, .mins = toVec(in.mins), .maxs = toVec(in.maxs), .parent = -1 };
    for (leafs, w.leafs) |in, *out| {
        if (in.firstLeafSurface < 0 or in.numLeafSurfaces < 0 or in.firstLeafSurface + in.numLeafSurfaces > w.marks.len) common.fail(c.ERR_DROP, "Bad leaf in {s}", .{w.nameSlice()});
        out.* = .{ .cluster = in.cluster, .area = in.area, .mins = toVec(in.mins), .maxs = toVec(in.maxs), .first_mark = @intCast(in.firstLeafSurface), .num_marks = @intCast(in.numLeafSurfaces), .parent = -1 };
        if (in.firstLeafBrush >= 0 and in.numLeafBrushes >= 0) {
            out.first_brush = @intCast(in.firstLeafBrush);
            out.num_brushes = @intCast(in.numLeafBrushes);
        }
        if (in.cluster >= w.num_clusters) w.num_clusters = in.cluster + 1;
    }
    for (w.nodes, 0..) |node, index| for (node.children) |child| {
        if (child >= 0) w.nodes[@intCast(child)].parent = @intCast(index) else w.leafs[@intCast(-child - 1)].parent = @intCast(index);
    };
}

fn loadSubmodels(w: *World, bytes: []const u8) void {
    const models = copyLump(c.dmodel_t, w, bytes, c.LUMP_MODELS);
    defer common.gpa.free(models);
    if (models.len > max_inline_models) common.fail(c.ERR_DROP, "{s} has more than {d} brush models", .{ w.nameSlice(), max_inline_models });
    w.bmodels = common.gpa.alloc(BModel, models.len) catch @panic("OOM");
    for (models, w.bmodels) |in, *out| {
        if (in.firstSurface < 0 or in.numSurfaces < 0 or in.firstSurface + in.numSurfaces > w.surfaces.len) common.fail(c.ERR_DROP, "Bad brush model in {s}", .{w.nameSlice()});
        out.* = .{ .mins = in.mins, .maxs = in.maxs, .first_surface = @intCast(in.firstSurface), .num_surfaces = @intCast(in.numSurfaces) };
    }
}

fn loadVisibility(w: *World, bytes: []const u8) void {
    const novis_len: usize = @intCast((@max(w.num_clusters, 1) + 63) & ~@as(i32, 63));
    w.novis = common.gpa.alloc(u8, novis_len) catch @panic("OOM");
    @memset(w.novis, 0xff);
    const data = lump(bytes, c.LUMP_VISIBILITY);
    if (data.len < 8) return;
    w.num_clusters = std.mem.readInt(i32, data[0..4], .little);
    w.cluster_bytes = std.mem.readInt(i32, data[4..8], .little);
    w.vis = common.gpa.dupe(u8, data[8..]) catch @panic("OOM");
    const needed: usize = @intCast((@max(w.num_clusters, 1) + 63) & ~@as(i32, 63));
    if (needed > w.novis.len) {
        common.gpa.free(w.novis);
        w.novis = common.gpa.alloc(u8, needed) catch @panic("OOM");
        @memset(w.novis, 0xff);
    }
}

fn loadEntities(w: *World, bytes: []const u8) void {
    const data = lump(bytes, c.LUMP_ENTITIES);
    const end = std.mem.indexOfScalar(u8, data, 0) orelse data.len;
    w.entity_string = common.gpa.allocSentinel(u8, end, 0) catch @panic("OOM");
    @memcpy(w.entity_string[0..end], data[0..end]);
    w.entity_parse = w.entity_string.ptr;
    w.has_entities = true;
    // Worldspawn keys: gridsize and shader remaps (R_LoadEntities).
    const copy = common.gpa.dupeZ(u8, w.entity_string) catch return;
    defer common.gpa.free(copy);
    var p: [*c]u8 = copy.ptr;
    if (common.span(c.COM_ParseExt(&p, c.qtrue)).len == 0) return;
    while (true) {
        var key_buffer: [c.MAX_TOKEN_CHARS]u8 = undefined;
        const key_token = common.span(c.COM_ParseExt(&p, c.qtrue));
        if (key_token.len == 0 or key_token[0] == '}') break;
        const key = key_buffer[0..@min(key_token.len, key_buffer.len)];
        @memcpy(key, key_token[0..key.len]);
        const value = common.span(c.COM_ParseExt(&p, c.qtrue));
        if (value.len == 0 or value[0] == '}') break;
        if (std.mem.startsWith(u8, key, "vertexremapshader")) continue;
        if (std.mem.startsWith(u8, key, "remapshader")) {
            const split = std.mem.indexOfScalar(u8, value, ';') orelse {
                common.warn("no semi colon in shaderremap '{s}'\n", .{value});
                break;
            };
            shader_mod.remap(value[0..split], value[split + 1 ..], "0");
            continue;
        }
        if (std.ascii.eqlIgnoreCase(key, "gridsize")) {
            var parts = std.mem.tokenizeScalar(u8, value, ' ');
            for (&w.grid_size) |*size| size.* = std.fmt.parseFloat(f32, parts.next() orelse "0") catch 0;
        }
    }
}

fn loadLightGrid(w: *World, bytes: []const u8) void {
    if (w.bmodels.len == 0) return;
    const mins = w.bmodels[0].mins;
    const maxs = w.bmodels[0].maxs;
    for (0..3) |i| {
        if (w.grid_size[i] <= 0) return;
        w.grid_origin[i] = w.grid_size[i] * @ceil(mins[i] / w.grid_size[i]);
        const top = w.grid_size[i] * @floor(maxs[i] / w.grid_size[i]);
        w.grid_bounds[i] = @as(i32, @intFromFloat((top - w.grid_origin[i]) / w.grid_size[i])) + 1;
    }
    const points: usize = @intCast(@max(w.grid_bounds[0] * w.grid_bounds[1] * w.grid_bounds[2], 0));
    const data = lump(bytes, c.LUMP_LIGHTGRID);
    if (data.len != points * 8) {
        common.warn("light grid mismatch\n", .{});
        return;
    }
    w.light_grid = common.gpa.dupe(u8, data) catch @panic("OOM");
    for (0..points) |i| {
        const ambient = colorShift(w.light_grid[i * 8 ..][0..3].*);
        const directed = colorShift(w.light_grid[i * 8 + 3 ..][0..3].*);
        w.light_grid[i * 8 ..][0..3].* = ambient;
        w.light_grid[i * 8 + 3 ..][0..3].* = directed;
    }
    if (@import("window.zig").remaster) createGridVolume(w, points);
}

/// RGB = dominant light direction, A = how directional the light is (directed / total).
fn createGridVolume(w: *World, points: usize) void {
    const texels = common.gpa.alloc(u8, points * 4) catch return;
    defer common.gpa.free(texels);
    const colors = common.gpa.alloc(u8, points * 4) catch return;
    defer common.gpa.free(colors);
    const unit = 360.0 / 1023.0 * std.math.pi / 180.0;
    for (0..points) |i| {
        const data = w.light_grid[i * 8 ..][0..8];
        const lat = @as(f32, @floatFromInt(@as(u32, data[7]) * 4));
        const lng = @as(f32, @floatFromInt(@as(u32, data[6]) * 4));
        const dir: Vec3 = .{ @sin(@mod(lat + 256, 1024) * unit) * @sin(lng * unit), @sin(lat * unit) * @sin(lng * unit), @sin(@mod(lng + 256, 1024) * unit) };
        const ambient = @as(f32, @floatFromInt(@as(u32, data[0]) + data[1] + data[2]));
        const directed = @as(f32, @floatFromInt(@as(u32, data[3]) + data[4] + data[5]));
        const ratio = if (ambient + directed > 0) directed / (ambient + directed) else 0;
        for (0..3) |k| texels[i * 4 + k] = @intFromFloat(std.math.clamp((dir[k] * 0.5 + 0.5) * 255, 0, 255));
        texels[i * 4 + 3] = @intFromFloat(std.math.clamp(ratio * 255, 0, 255));
        for (0..3) |k| colors[i * 4 + k] = @intCast(@min(@as(u32, data[k]) + data[k + 3], 255));
        colors[i * 4 + 3] = 255;
    }
    const dims = [3]u32{ @intCast(w.grid_bounds[0]), @intCast(w.grid_bounds[1]), @intCast(w.grid_bounds[2]) };
    w.grid_volume = vk.createVolume(dims[0], dims[1], dims[2], c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT);
    vk.uploadVolume(&w.grid_volume, dims[2], texels);
    w.grid_slot = vk.bindVolume(w.grid_volume.view);
    w.grid_color = vk.createVolume(dims[0], dims[1], dims[2], c.VK_FORMAT_R8G8B8A8_UNORM, c.VK_IMAGE_USAGE_SAMPLED_BIT | c.VK_IMAGE_USAGE_TRANSFER_DST_BIT);
    vk.uploadVolume(&w.grid_color, dims[2], colors);
    w.grid_color_slot = vk.bindVolume(w.grid_color.view);
}

/// Grid sampling parameters for the stage shader: origin of texel 0's corner and the scale to
/// normalized volume coordinates.
/// How bright the original radiosity made its sky: upward-facing faces under open sky receive
/// pi x the sky radiance, and the radiosity stored that (as lightmaps hold irradiance / pi for
/// a white surface). The converted shaders lost the sky's emission value, so the level is read
/// back from the 75th percentile of upward-facing lightmap texels (the brightest are mostly lamp-lit).
fn calibrateSky(w: *World) void {
    const page_bytes = lightmap_size * lightmap_size * 3;
    const pages = w.lightmap_bytes.len / page_bytes;
    if (pages == 0) return;
    var samples: std.ArrayList(f32) = .empty;
    defer samples.deinit(common.gpa);
    for (w.surfaces_lump) |in| {
        if (in.surfaceType != c.MST_PLANAR or in.lightmapNum < 0 or @as(usize, @intCast(in.lightmapNum)) >= pages) continue;
        if (in.lightmapVecs[2][2] < 0.85) continue;
        const page = w.lightmap_bytes[@as(usize, @intCast(in.lightmapNum)) * page_bytes ..][0..page_bytes];
        const x0: usize = @intCast(@max(in.lightmapX, 0));
        const y0: usize = @intCast(@max(in.lightmapY, 0));
        const width: usize = @intCast(@max(in.lightmapWidth, 0));
        const height: usize = @intCast(@max(in.lightmapHeight, 0));
        var y = y0;
        while (y < @min(y0 + height, lightmap_size)) : (y += 2) {
            var x = x0;
            while (x < @min(x0 + width, lightmap_size)) : (x += 2) {
                const texel = page[(y * lightmap_size + x) * 3 ..][0..3];
                const linear = linearLight(.{ @as(f32, @floatFromInt(texel[0])) / 255.0, @as(f32, @floatFromInt(texel[1])) / 255.0, @as(f32, @floatFromInt(texel[2])) / 255.0 });
                samples.append(common.gpa, linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722) catch return;
            }
        }
    }
    if (samples.items.len < 64) return;
    std.mem.sort(f32, samples.items, {}, std.sort.asc(f32));
    w.sky_level = samples.items[samples.items.len * 3 / 4];
}

/// Light arriving from the sky, for rays that leave the world (ray traced lighting): the hue of
/// the sky shader's box (or cloud layer) images at the brightness the original radiosity gave
/// the sky (calibrateSky).
pub fn skyRadiance(w: *World) [3]f32 {
    if (w.sky_radiance) |value| return value;
    var sum: [3]f32 = .{ 0, 0, 0 };
    var count: f32 = 0;
    for (w.surfaces) |surface| {
        const shader = surface.shader;
        if (!shader.is_sky) continue;
        for (shader.sky.outer) |maybe| if (maybe) |img| {
            for (0..3) |k| sum[k] += img.average[k];
            count += 1;
        };
        if (count == 0) for (shader.stagesSlice()) |*stage| if (stage.bundles[0].images[0]) |img| {
            for (0..3) |k| sum[k] += img.average[k];
            count += 1;
        };
        if (count > 0) break;
    }
    var out: [3]f32 = .{ 0.05, 0.05, 0.06 };
    if (count > 0) for (0..3) |k| {
        out[k] = std.math.pow(f32, sum[k] / count, 2.2);
    };
    // Keep the sky's hue, take its brightness from the radiosity calibration.
    const luma = out[0] * 0.2126 + out[1] * 0.7152 + out[2] * 0.0722;
    if (w.sky_level > 0 and luma > 1e-4) {
        for (&out) |*channel| channel.* *= w.sky_level / luma;
    }
    w.sky_radiance = out;
    return out;
}

pub fn gridParams(w: *const World) ?struct { origin: [4]f32, scale: [4]f32, slot: u32, color_slot: u32 } {
    const slot = w.grid_slot orelse return null;
    var origin: [4]f32 = .{ 0, 0, 0, 1 };
    var scale: [4]f32 = .{ 0, 0, 0, 0 };
    for (0..3) |k| {
        origin[k] = w.grid_origin[k] - 0.5 * w.grid_size[k];
        scale[k] = 1.0 / (w.grid_size[k] * @as(f32, @floatFromInt(w.grid_bounds[k])));
    }
    return .{ .origin = origin, .scale = scale, .slot = slot, .color_slot = w.grid_color_slot };
}

// ---------------------------------------------------------------------------------------------
// DKLS lightstyle trailer (dk3_lightstyles.inc)

fn read32(p: []const u8) u32 {
    return std.mem.readInt(u32, p[0..4], .little);
}

fn loadLightstyles(w: *World, file: []const u8) void {
    w.light_blocks = &.{};
    const pages = lump(file, c.LUMP_LIGHTMAPS).len / (lightmap_size * lightmap_size * 3);
    if (file.len < 16 or !std.mem.eql(u8, file[file.len - 8 ..][0..4], "DKLT")) return;
    const size = read32(file[file.len - 4 ..]);
    if (size < 8 or size > file.len - 8) common.fail(c.ERR_DROP, "dk3: invalid lightstyle trailer length", .{});
    const end = file.len - 8;
    var p = end - size;
    if (!std.mem.eql(u8, file[p..][0..4], "DKLS")) common.fail(c.ERR_DROP, "dk3: invalid lightstyle trailer signature", .{});
    const count = read32(file[p + 4 ..]);
    p += 8;
    if (count > 1048576 or count > size / 44) common.fail(c.ERR_DROP, "dk3: invalid lightstyle block count", .{});
    const blocks = common.gpa.alloc(LightBlock, count) catch @panic("OOM");
    for (blocks) |*b| {
        if (end - p < 44) common.fail(c.ERR_DROP, "dk3: truncated lightstyle block", .{});
        const page = read32(file[p..]);
        const x = read32(file[p + 4 ..]);
        const y = read32(file[p + 8 ..]);
        const width = read32(file[p + 12 ..]);
        const height = read32(file[p + 16 ..]);
        const styles_count = read32(file[p + 20 ..]);
        const block_scale: f32 = @bitCast(read32(file[p + 24 ..]));
        var styles: [4]u32 = undefined;
        for (&styles, 0..) |*style, j| style.* = read32(file[p + 28 + 4 * j ..]);
        p += 44;
        if (page >= pages or width < 1 or height < 1 or width > 128 or height > 128 or x > 128 - width or y > 128 - height or
            styles_count < 1 or styles_count > 4 or std.math.isNan(block_scale) or block_scale < 0 or block_scale > 16)
            common.fail(c.ERR_DROP, "dk3: invalid lightstyle block dimensions", .{});
        for (styles[0..styles_count]) |style| if (style >= 256) common.fail(c.ERR_DROP, "dk3: unsupported lightstyle index", .{});
        const samples = width * height * 3 * styles_count;
        if (samples > end - p) common.fail(c.ERR_DROP, "dk3: truncated lightstyle samples", .{});
        b.* = .{ .page = page, .x = x, .y = y, .width = width, .height = height, .count = styles_count, .styles = styles, .scale = block_scale, .previous = .{ -1, -1, -1, -1 }, .samples = common.gpa.dupe(u8, file[p .. p + samples]) catch @panic("OOM") };
        p += samples;
    }
    if (p != end) common.fail(c.ERR_DROP, "dk3: trailing lightstyle data", .{});
    w.light_blocks = blocks;
}

/// `R_UpdateDkLightstyles`: recomposes changed blocks into the selected world's lightmaps.
pub fn updateLightstyles(fd: *const c.refdef_t) void {
    if (fd.rdflags & c.RDF_NOWORLDMODEL != 0) return;
    const w = selected orelse return;
    var rgba: [128 * 128 * 4]u8 = undefined;
    for (w.light_blocks) |*b| {
        var changed = false;
        for (0..b.count) |j| if (b.previous[j] != std.math.clamp(fd.dk3Lightstyles[b.styles[j]], 0, 4)) {
            changed = true;
        };
        if (!changed) continue;
        for (0..b.count) |j| b.previous[j] = std.math.clamp(fd.dk3Lightstyles[b.styles[j]], 0, 4);
        const pixels = b.width * b.height;
        if (@import("window.zig").remaster) {
            var texels: [128 * 128 * 4]u16 = undefined;
            for (0..pixels) |pixel| {
                var sum: [3]f32 = .{ 0, 0, 0 };
                for (0..3) |channel| {
                    for (0..b.count) |j| sum[channel] += @as(f32, @floatFromInt(b.samples[(j * pixels + pixel) * 3 + channel])) * b.previous[j] * b.scale;
                    sum[channel] /= 255.0;
                }
                const linear = linearLight(sum);
                for (0..3) |channel| texels[pixel * 4 + channel] = half(linear[channel]);
                texels[pixel * 4 + 3] = half(1);
            }
            if (b.page < w.lightmaps.len) vk.uploadRegion(&w.lightmaps[b.page].texture, b.x, b.y, b.width, b.height, std.mem.sliceAsBytes(texels[0 .. pixels * 4]));
            continue;
        }
        for (0..pixels) |pixel| {
            var rgb: [3]f32 = .{ 0, 0, 0 };
            var peak: f32 = 255;
            for (0..b.count) |j| for (0..3) |channel| {
                rgb[channel] += @as(f32, @floatFromInt(b.samples[(j * pixels + pixel) * 3 + channel])) * b.previous[j] * b.scale;
            };
            for (rgb) |value| peak = @max(peak, value);
            var input: [3]u8 = undefined;
            for (0..3) |channel| input[channel] = @intFromFloat(rgb[channel] * 255 / peak);
            const shifted = colorShift(input);
            rgba[pixel * 4 ..][0..4].* = .{ shifted[0], shifted[1], shifted[2], 255 };
        }
        if (b.page < w.lightmaps.len) vk.uploadRegion(&w.lightmaps[b.page].texture, b.x, b.y, b.width, b.height, rgba[0 .. pixels * 4]);
    }
}

// ---------------------------------------------------------------------------------------------
// Contents (collision brushes) and liquids

/// Brush contents at `point` in world `w` (CM_PointContents over the leaf's brushes).
pub fn contentsAt(w: *const World, point: Vec3) u32 {
    const leaf = pointInLeaf(w, point) orelse return 0;
    var contents: u32 = 0;
    if (leaf.first_brush + leaf.num_brushes > w.leaf_brushes.len) return 0;
    for (w.leaf_brushes[leaf.first_brush .. leaf.first_brush + leaf.num_brushes]) |brush_index| {
        if (brush_index < 0 or brush_index >= w.brushes.len) continue;
        const brush = w.brushes[@intCast(brush_index)];
        if (brush.shaderNum < 0 or brush.shaderNum >= w.shaders_lump.len) continue;
        const brush_contents: u32 = @bitCast(w.shaders_lump[@intCast(brush.shaderNum)].contentFlags);
        if (brush_contents & (c.CONTENTS_WATER | c.CONTENTS_SLIME | c.CONTENTS_LAVA | c.CONTENTS_FOG) == 0) continue;
        if (brush.firstSide < 0 or brush.numSides <= 0 or brush.firstSide + brush.numSides > w.brush_sides.len) continue;
        var inside = true;
        for (w.brush_sides[@intCast(brush.firstSide)..][0..@intCast(brush.numSides)]) |side| {
            if (side.planeNum < 0 or side.planeNum >= w.planes.len) {
                inside = false;
                break;
            }
            const plane = w.planes[@intCast(side.planeNum)];
            if (scene.dot(point, plane.normal) - plane.dist > 0) {
                inside = false;
                break;
            }
        }
        if (inside) contents |= brush_contents;
    }
    return contents;
}

pub fn liquidOf(contents: u32) image.Liquid {
    if (contents & c.CONTENTS_LAVA != 0) return .lava;
    if (contents & c.CONTENTS_SLIME != 0) return .slime;
    if (contents & c.CONTENTS_WATER != 0) return .water;
    return .none;
}

fn looksLiquid(shader: *const Shader) bool {
    for (shader.deforms[0..shader.num_deforms]) |deform| if (deform.kind == .wave) return true;
    for (shader.stagesSlice()) |*stage| {
        for (stage.bundles[0].texmods[0..stage.bundles[0].num_texmods]) |mod| if (mod == .turb) return true;
        if (stage.bundles[0].images[0]) |albedo| if (image.material(albedo).liquid != .none) return true;
    }
    return false;
}

/// Marks the faces that bound a liquid volume: a point just behind the face is in water, slime
/// or lava while one just in front of it is not.
fn classifyLiquids(w: *World) void {
    if (w.brushes.len == 0) return;
    var count: u32 = 0;
    for (w.surfaces) |*surface| {
        if (surface.kind != .face or surface.num_indexes < 3 or !looksLiquid(surface.shader)) continue;
        // Waterfalls and the walls of a liquid volume keep their authored (translucent,
        // scrolling) stages: the remaster liquid shading models a pool's surface.
        if (@abs(surface.plane_normal[2]) < 0.6) continue;
        var center: Vec3 = .{ 0, 0, 0 };
        for (w.indices.items[surface.first_index .. surface.first_index + surface.num_indexes]) |index| center = scene.add(center, w.vertices.items[index].pos);
        center = scene.scale(center, 1.0 / @as(f32, @floatFromInt(surface.num_indexes)));
        const behind = liquidOf(contentsAt(w, scene.madd(center, -4, surface.plane_normal)));
        const front = liquidOf(contentsAt(w, scene.madd(center, 4, surface.plane_normal)));
        surface.liquid = if (behind != .none) behind else if (front != .none) front else .none;
        if (surface.liquid != .none) count += 1;
    }
    if (count > 0) common.developer("dk3 vulkan liquids: map={s} surfaces={d}\n", .{ w.nameSlice(), count });
}

// ---------------------------------------------------------------------------------------------
// Queries

fn pointInLeaf(w: *const World, point: Vec3) ?*const Leaf {
    if (w.nodes.len == 0) return if (w.leafs.len > 0) &w.leafs[0] else null;
    var child: i32 = 0;
    while (child >= 0) {
        const node = w.nodes[@intCast(child)];
        const plane = w.planes[node.plane];
        const d = scene.dot(point, plane.normal) - plane.dist;
        child = if (d > 0) node.children[0] else node.children[1];
    }
    return &w.leafs[@intCast(-child - 1)];
}

fn clusterPvs(w: *const World, cluster: i32) []const u8 {
    if (w.vis.len == 0 or cluster < 0 or cluster >= w.num_clusters) return w.novis;
    const start: usize = @intCast(cluster * w.cluster_bytes);
    if (start >= w.vis.len) return w.novis;
    return w.vis[start..];
}

/// The visibility cluster at `point` (-1 in solid or outside the map).
pub fn clusterAt(w: *const World, point: Vec3) i32 {
    const leaf = pointInLeaf(w, point) orelse return -1;
    return leaf.cluster;
}

/// Whether the map's PVS lets cluster `from` see cluster `to`.
pub fn clusterSees(w: *const World, from: i32, to: i32) bool {
    if (from < 0 or to < 0) return false;
    const vis = clusterPvs(w, from);
    const byte: usize = @intCast(to >> 3);
    if (byte >= vis.len) return true;
    return vis[byte] & (@as(u8, 1) << @intCast(to & 7)) != 0;
}

/// `R_inPVS` (collision-map PVS, as in renderergl1).
pub fn inPvs(p1: *const Vec3, p2: *const Vec3) bool {
    const w = selected orelse return false;
    const a = pointInLeaf(w, p1.*) orelse return false;
    const vis = common.ri.CM_ClusterPVS.?(a.cluster);
    const b = pointInLeaf(w, p2.*) orelse return false;
    if (b.cluster < 0) return false;
    return vis[@intCast(b.cluster >> 3)] & (@as(u8, 1) << @intCast(b.cluster & 7)) != 0;
}

pub const GridSample = struct { ambient: Vec3, directed: Vec3, direction: Vec3 };

/// `R_SetupEntityLightingGrid`.
pub fn lightGridSample(w: *const World, origin: Vec3) ?GridSample {
    if (w.light_grid.len == 0) return null;
    var pos: [3]i32 = undefined;
    var frac: Vec3 = undefined;
    const local = scene.sub(origin, w.grid_origin);
    for (0..3) |i| {
        const v = local[i] / w.grid_size[i];
        const floor = @floor(v);
        pos[i] = @intFromFloat(std.math.clamp(floor, -1e9, 1e9));
        frac[i] = v - floor;
        pos[i] = std.math.clamp(pos[i], 0, w.grid_bounds[i] - 1);
    }
    var ambient: Vec3 = .{ 0, 0, 0 };
    var directed: Vec3 = .{ 0, 0, 0 };
    var direction: Vec3 = .{ 0, 0, 0 };
    const step = [3]i32{ 8, 8 * w.grid_bounds[0], 8 * w.grid_bounds[0] * w.grid_bounds[1] };
    const base = pos[0] * step[0] + pos[1] * step[1] + pos[2] * step[2];
    var total: f32 = 0;
    for (0..8) |i| {
        var factor: f32 = 1;
        var offset = base;
        var inside = true;
        for (0..3) |j| {
            if (i & (@as(usize, 1) << @intCast(j)) != 0) {
                if (pos[j] + 1 > w.grid_bounds[j] - 1) {
                    inside = false;
                    break;
                }
                factor *= frac[j];
                offset += step[j];
            } else factor *= 1 - frac[j];
        }
        if (!inside) continue;
        const data = w.light_grid[@intCast(offset)..][0..8];
        if (@as(u32, data[0]) + data[1] + data[2] == 0) continue;
        total += factor;
        for (0..3) |k| {
            ambient[k] += factor * @as(f32, @floatFromInt(data[k]));
            directed[k] += factor * @as(f32, @floatFromInt(data[k + 3]));
        }
        // lat/long at FUNCTABLE_SIZE/256 resolution of the sin table (360/1023 degrees per entry).
        const lat = @as(f32, @floatFromInt(@as(u32, data[7]) * 4));
        const lng = @as(f32, @floatFromInt(@as(u32, data[6]) * 4));
        const unit = 360.0 / 1023.0 * std.math.pi / 180.0;
        const normal: Vec3 = .{ @sin((@mod(lat + 256, 1024)) * unit) * @sin(lng * unit), @sin(lat * unit) * @sin(lng * unit), @sin((@mod(lng + 256, 1024)) * unit) };
        direction = scene.madd(direction, factor, normal);
    }
    if (total > 0 and total < 0.99) {
        ambient = scene.scale(ambient, 1 / total);
        directed = scene.scale(directed, 1 / total);
    }
    return .{ .ambient = scene.scale(ambient, cvars.ambientScale.value), .directed = scene.scale(directed, cvars.directedScale.value), .direction = scene.normalize(direction) };
}

pub fn lightForPoint(point: *const Vec3, ambient: *Vec3, directed: *Vec3, direction: *Vec3) c_int {
    const w = selected orelse return 0;
    const sample = lightGridSample(w, point.*) orelse return 0;
    ambient.* = sample.ambient;
    directed.* = sample.directed;
    direction.* = sample.direction;
    return 1;
}

pub fn entityToken(buffer: [*c]u8, size: c_int) c_int {
    const w = loading orelse selected orelse return 0;
    if (!w.has_entities) return 0;
    const token = c.COM_Parse(&w.entity_parse);
    _ = c.Q_strncpyz(buffer, token, size);
    if (w.entity_parse == null and token[0] == 0) {
        w.entity_parse = w.entity_string.ptr;
        return 0;
    }
    return 1;
}

/// `R_WorldInlineModel`: "*N" of the selected world as a resident inline handle.
pub fn inlineModel(name: []const u8) c.qhandle_t {
    const w = selected orelse return 0;
    if (w.status != .ready or name.len < 2 or name[0] != '*') return 0;
    const index = std.fmt.parseInt(u32, name[1..], 10) catch return 0;
    if (index >= w.bmodels.len) return 0;
    return @intCast(c.DK3_InlineHandle(w.generation, w.index, index));
}

pub const InlineRef = struct { world: *World, model: *BModel };

pub fn residentInline(handle_value: c.qhandle_t) ?InlineRef {
    var generation: c_uint = 0;
    var owner: c_uint = 0;
    var model_index: c_uint = 0;
    if (c.DK3_InlineParts(@bitCast(handle_value), &generation, &owner, &model_index) == 0) return null;
    const w = &worlds[owner];
    if (w.status != .ready or w.generation != generation or model_index >= w.bmodels.len) return null;
    return .{ .world = w, .model = &w.bmodels[model_index] };
}

// ---------------------------------------------------------------------------------------------
// Visibility and surface submission (tr_world.c)

fn markLeaves(w: *World, view: *const scene.View) void {
    const leaf = pointInLeaf(w, view.pvs_origin) orelse return;
    const cluster = leaf.cluster;
    const area_changed = !std.mem.eql(u8, &w.areamask, &view.areamask);
    if (w.view_cluster == cluster and !area_changed and w.vis_count != 0) return;
    if (cvars.lockpvs.integer != 0 and w.vis_count != 0) return;
    w.areamask = view.areamask;
    w.vis_count +%= 1;
    if (w.vis_count == 0) w.vis_count = 1;
    w.view_cluster = cluster;
    if (cvars.novis.integer != 0 or cluster == -1) {
        for (w.nodes) |*node| node.visframe = w.vis_count;
        for (w.leafs) |*l| if (l.cluster != -1) {
            l.visframe = w.vis_count;
        };
        return;
    }
    const vis = clusterPvs(w, cluster);
    for (w.leafs) |*l| {
        const c2 = l.cluster;
        if (c2 < 0 or c2 >= w.num_clusters) continue;
        if (@as(usize, @intCast(c2 >> 3)) >= vis.len or vis[@intCast(c2 >> 3)] & (@as(u8, 1) << @intCast(c2 & 7)) == 0) continue;
        if (l.area >= 0 and view.areamask[@intCast(l.area >> 3)] & (@as(u8, 1) << @intCast(l.area & 7)) != 0) continue;
        l.visframe = w.vis_count;
        var parent = l.parent;
        while (parent >= 0) {
            const node = &w.nodes[@intCast(parent)];
            if (node.visframe == w.vis_count) break;
            node.visframe = w.vis_count;
            parent = node.parent;
        }
    }
}

fn cullSurface(view: *const scene.View, surface: *const Surface, view_origin: Vec3) bool {
    if (cvars.nocull.integer != 0) return false;
    if (surface.kind == .flare) return true;
    if (surface.kind != .face) return view.cullBox(surface.mins, surface.maxs);
    if (surface.shader.cull == .two_sided) return false;
    const d = scene.dot(view_origin, surface.plane_normal);
    if (surface.shader.cull == .front) {
        if (d < surface.plane_dist - 8) return true;
    } else if (d > surface.plane_dist + 8) return true;
    return false;
}

fn dlightBits(view: *const scene.View, surface: *const Surface) u32 {
    var bits: u32 = 0;
    for (view.dlights, 0..) |light, index| {
        var inside = true;
        for (0..3) |k| {
            if (light.origin[k] - light.radius > surface.maxs[k] or light.origin[k] + light.radius < surface.mins[k]) inside = false;
        }
        // More than 32 lights (remaster clusters) alias: the mask only gates lighting work.
        if (inside) bits |= @as(u32, 1) << @intCast(index & 31);
    }
    return bits;
}

fn addSurface(view: *scene.View, w: *World, index: u32, entity: u32, view_origin: Vec3, transformed_lights: bool) void {
    const surface = &w.surfaces[index];
    if (surface.view_count == w.view_count) return;
    surface.view_count = w.view_count;
    if (surface.kind == .flare or surface.num_indexes == 0 and !surface.shader.is_sky) return;
    if (cullSurface(view, surface, view_origin)) return;
    if (surface.shader.is_sky) {
        // One sky draw per view: the backend renders the whole box around the viewer.
        if (w.sky_view != scene.view_sequence) {
            w.sky_view = scene.view_sequence;
            scene.addDrawSurf(surface.shader, scene.world_entity, .sky, 0);
        }
        return;
    }
    const bits = if (transformed_lights) @as(u32, if (view.dlights.len > 0) 1 else 0) else dlightBits(view, surface);
    const liquid_sort: ?f32 = if (surface.liquid != .none and @import("window.zig").remaster) shader_mod.Sort.underwater + 0.5 else null;
    scene.addDrawSurfSorted(surface.shader, entity, .{ .world = .{ .owner = w, .surface = index } }, bits, liquid_sort);
}

fn recursiveWorldNode(view: *scene.View, w: *World, start: i32, planes_in: u4) void {
    var child = start;
    var planes = planes_in;
    while (true) {
        var mins: Vec3 = undefined;
        var maxs: Vec3 = undefined;
        if (child >= 0) {
            const node = &w.nodes[@intCast(child)];
            if (node.visframe != w.vis_count) return;
            mins = node.mins;
            maxs = node.maxs;
        } else {
            const leaf = &w.leafs[@intCast(-child - 1)];
            if (leaf.visframe != w.vis_count) return;
            mins = leaf.mins;
            maxs = leaf.maxs;
        }
        if (cvars.nocull.integer == 0 and planes != 0) {
            for (view.frustum, 0..) |plane, i| {
                const bit = @as(u4, 1) << @intCast(i);
                if (planes & bit == 0) continue;
                var near: Vec3 = undefined;
                var far: Vec3 = undefined;
                for (0..3) |k| {
                    near[k] = if (plane.normal[k] >= 0) maxs[k] else mins[k];
                    far[k] = if (plane.normal[k] >= 0) mins[k] else maxs[k];
                }
                if (scene.dot(near, plane.normal) < plane.dist) return; // fully outside
                if (scene.dot(far, plane.normal) >= plane.dist) planes &= ~bit; // fully inside
            }
        }
        if (child < 0) break;
        const node = &w.nodes[@intCast(child)];
        recursiveWorldNode(view, w, node.children[0], planes);
        child = node.children[1];
    }
    const leaf = &w.leafs[@intCast(-child - 1)];
    view.addVisBounds(leaf.mins, leaf.maxs);
    for (w.marks[leaf.first_mark .. leaf.first_mark + leaf.num_marks]) |surface| addSurface(view, w, surface, scene.world_entity, view.origin, false);
}

/// `R_AddWorldSurfaces`.
pub fn addWorldSurfaces(view: *scene.View, w: *World) void {
    if (w.status != .ready) return;
    w.view_count +%= 1;
    if (w.view_count == 0) w.view_count = 1;
    markLeaves(w, view);
    if (w.nodes.len == 0) return;
    recursiveWorldNode(view, w, 0, 0xf);
}

/// `R_AddBrushModelSurfaces`.
pub fn addBrushModel(view: *scene.View, entity: *scene.Entity, number: u32, ref: InlineRef) void {
    const e = &entity.e;
    // World-space bounds of the rotated box.
    var mins: Vec3 = .{ 1e30, 1e30, 1e30 };
    var maxs: Vec3 = .{ -1e30, -1e30, -1e30 };
    for (0..8) |corner| {
        const local: Vec3 = .{
            if (corner & 1 != 0) ref.model.maxs[0] else ref.model.mins[0],
            if (corner & 2 != 0) ref.model.maxs[1] else ref.model.mins[1],
            if (corner & 4 != 0) ref.model.maxs[2] else ref.model.mins[2],
        };
        var p: Vec3 = e.origin;
        p = scene.madd(p, local[0], e.axis[0]);
        p = scene.madd(p, local[1], e.axis[1]);
        p = scene.madd(p, local[2], e.axis[2]);
        for (0..3) |k| {
            mins[k] = @min(mins[k], p[k]);
            maxs[k] = @max(maxs[k], p[k]);
        }
    }
    if (view.cullBox(mins, maxs)) return;
    const o = scene.orientation(view, entity);
    ref.world.view_count +%= 1;
    if (ref.world.view_count == 0) ref.world.view_count = 1;
    for (ref.model.first_surface..ref.model.first_surface + ref.model.num_surfaces) |index| {
        addSurface(view, ref.world, @intCast(index), number, o.view_origin, true);
    }
}

/// Appends the indices of consecutive world surfaces into the stream ring.
pub fn mergeIndices(self: *World, surfaces: []const scene.DrawSurf) ?scene.Mesh {
    var total: u64 = 0;
    for (surfaces) |surface| total += self.surfaces[surface.geometry.world.surface].num_indexes;
    if (total == 0) return null;
    const space = vk.frame().stream.alloc(total * 4, 4) orelse return null;
    const out = std.mem.bytesAsSlice(u32, space.bytes);
    var offset: usize = 0;
    for (surfaces) |surface| {
        const s = &self.surfaces[surface.geometry.world.surface];
        @memcpy(out[offset .. offset + s.num_indexes], self.indices.items[s.first_index .. s.first_index + s.num_indexes]);
        offset += s.num_indexes;
    }
    return .{ .kind = 0, .vertices = self.vertex_buffer.address, .indices = space.address, .count = @intCast(total) };
}

pub fn lightGrid(self: *const World, origin: Vec3) ?GridSample {
    return lightGridSample(self, origin);
}

pub fn bounds(handle_value: c.qhandle_t, mins: *Vec3, maxs: *Vec3) bool {
    const ref = residentInline(handle_value) orelse return false;
    mins.* = ref.model.mins;
    maxs.* = ref.model.maxs;
    return true;
}

// ---------------------------------------------------------------------------------------------
// Mark fragments (tr_marks.c)

const max_verts_on_poly = 64;

fn chopPolyBehindPlane(in: []const Vec3, out: *[max_verts_on_poly]Vec3, normal: Vec3, dist: f32, epsilon: f32) usize {
    if (in.len >= max_verts_on_poly - 2) return 0;
    var dists: [max_verts_on_poly + 4]f32 = undefined;
    var sides: [max_verts_on_poly + 4]u8 = undefined;
    var counts = [3]u32{ 0, 0, 0 };
    for (in, 0..) |point, i| {
        const d = scene.dot(point, normal) - dist;
        dists[i] = d;
        sides[i] = if (d > epsilon) 0 else if (d < -epsilon) 1 else 2;
        counts[sides[i]] += 1;
    }
    sides[in.len] = sides[0];
    dists[in.len] = dists[0];
    if (counts[0] == 0) return 0;
    if (counts[1] == 0) {
        @memcpy(out[0..in.len], in);
        return in.len;
    }
    var count: usize = 0;
    for (in, 0..) |p1, i| {
        if (sides[i] == 2) {
            out[count] = p1;
            count += 1;
            continue;
        }
        if (sides[i] == 0) {
            out[count] = p1;
            count += 1;
        }
        if (sides[i + 1] == 2 or sides[i + 1] == sides[i]) continue;
        const p2 = in[(i + 1) % in.len];
        const d = dists[i] - dists[i + 1];
        const t: f32 = if (d == 0) 0 else dists[i] / d;
        out[count] = .{ p1[0] + t * (p2[0] - p1[0]), p1[1] + t * (p2[1] - p1[1]), p1[2] + t * (p2[2] - p1[2]) };
        count += 1;
    }
    return count;
}

const MarkState = struct {
    normals: []const Vec3,
    dists: []const f32,
    points: [*]Vec3,
    max_points: usize,
    fragments: [*]c.markFragment_t,
    max_fragments: usize,
    returned_points: usize = 0,
    returned_fragments: usize = 0,
};

fn addMarkFragments(state: *MarkState, triangle: [3]Vec3) bool {
    var buffers: [2][max_verts_on_poly]Vec3 = undefined;
    buffers[0][0..3].* = triangle;
    var count: usize = 3;
    var ping: usize = 0;
    for (state.normals, state.dists) |normal, dist| {
        count = chopPolyBehindPlane(buffers[ping][0..count], &buffers[ping ^ 1], normal, dist, 0.5);
        ping ^= 1;
        if (count == 0) break;
    }
    if (count == 0) return false;
    if (count + state.returned_points > state.max_points) return false;
    const fragment = &state.fragments[state.returned_fragments];
    fragment.firstPoint = @intCast(state.returned_points);
    fragment.numPoints = @intCast(count);
    @memcpy(state.points[state.returned_points .. state.returned_points + count], buffers[ping][0..count]);
    state.returned_points += count;
    state.returned_fragments += 1;
    return state.returned_fragments == state.max_fragments;
}

fn boxOnPlaneSide(mins: Vec3, maxs: Vec3, normal: Vec3, dist: f32) u2 {
    var near: Vec3 = undefined;
    var far: Vec3 = undefined;
    for (0..3) |k| {
        near[k] = if (normal[k] >= 0) mins[k] else maxs[k];
        far[k] = if (normal[k] >= 0) maxs[k] else mins[k];
    }
    var sides: u2 = 0;
    if (scene.dot(far, normal) >= dist) sides |= 1;
    if (scene.dot(near, normal) < dist) sides |= 2;
    return sides;
}

fn boxSurfaces(w: *World, start: i32, mins: Vec3, maxs: Vec3, list: *std.ArrayList(u32), direction: Vec3) void {
    var child = start;
    while (child >= 0) {
        const node = w.nodes[@intCast(child)];
        const plane = w.planes[node.plane];
        const side = boxOnPlaneSide(mins, maxs, plane.normal, plane.dist);
        if (side == 1) child = node.children[0] else if (side == 2) child = node.children[1] else {
            boxSurfaces(w, node.children[0], mins, maxs, list, direction);
            child = node.children[1];
        }
    }
    const leaf = w.leafs[@intCast(-child - 1)];
    for (w.marks[leaf.first_mark .. leaf.first_mark + leaf.num_marks]) |index| {
        if (list.items.len >= 64) break;
        const surface = &w.surfaces[index];
        if (surface.view_count == w.view_count) continue;
        surface.view_count = w.view_count;
        if (surface.shader.surface_flags & (c.SURF_NOIMPACT | c.SURF_NOMARKS) != 0 or surface.shader.content_flags & c.CONTENTS_FOG != 0) continue;
        switch (surface.kind) {
            .face => {
                const s = boxOnPlaneSide(mins, maxs, surface.plane_normal, surface.plane_dist);
                if (s == 1 or s == 2) continue;
                if (scene.dot(surface.plane_normal, direction) > -0.5) continue;
            },
            .patch => {},
            else => continue,
        }
        list.append(common.gpa, index) catch return;
    }
}

/// `R_MarkFragments`.
pub fn markFragments(num_points: c_int, points: [*c]const c.vec3_t, projection: *const Vec3, max_points: c_int, point_buffer: [*c]c.vec3_t, max_fragments: c_int, fragment_buffer: [*c]c.markFragment_t) c_int {
    const w = selected orelse return 0;
    if (num_points <= 0 or w.nodes.len == 0) return 0;
    w.view_count +%= 1;
    if (w.view_count == 0) w.view_count = 1;
    const direction = scene.normalize(projection.*);
    var mins: Vec3 = .{ 1e30, 1e30, 1e30 };
    var maxs: Vec3 = .{ -1e30, -1e30, -1e30 };
    const count: usize = @intCast(@min(num_points, max_verts_on_poly));
    for (0..@intCast(num_points)) |i| {
        const p: Vec3 = points[i];
        for ([_]Vec3{ p, scene.add(p, projection.*), scene.madd(p, -20, direction) }) |q| for (0..3) |k| {
            mins[k] = @min(mins[k], q[k]);
            maxs[k] = @max(maxs[k], q[k]);
        };
    }
    var normals: [max_verts_on_poly + 2]Vec3 = undefined;
    var dists: [max_verts_on_poly + 2]f32 = undefined;
    for (0..count) |i| {
        const p: Vec3 = points[i];
        const v1 = scene.sub(points[(i + 1) % count], p);
        const v2 = scene.sub(p, scene.add(p, projection.*));
        normals[i] = scene.normalize(scene.cross(v1, v2));
        dists[i] = scene.dot(normals[i], p);
    }
    normals[count] = direction;
    dists[count] = scene.dot(direction, points[0]) - 32;
    normals[count + 1] = scene.scale(direction, -1);
    dists[count + 1] = scene.dot(normals[count + 1], points[0]) - 20;
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(common.gpa);
    boxSurfaces(w, 0, mins, maxs, &list, direction);
    var state: MarkState = .{
        .normals = normals[0 .. count + 2],
        .dists = dists[0 .. count + 2],
        .points = @ptrCast(point_buffer),
        .max_points = @intCast(@max(max_points, 0)),
        .fragments = fragment_buffer,
        .max_fragments = @intCast(@max(max_fragments, 0)),
    };
    if (state.max_fragments == 0) return 0;
    for (list.items) |index| {
        const surface = &w.surfaces[index];
        switch (surface.kind) {
            .face => {
                var k: u32 = 0;
                while (k + 2 < surface.num_indexes) : (k += 3) {
                    const ids = w.indices.items[surface.first_index + k ..][0..3];
                    if (addMarkFragments(&state, .{ w.vertices.items[ids[0]].pos, w.vertices.items[ids[1]].pos, w.vertices.items[ids[2]].pos })) return @intCast(state.returned_fragments);
                }
            },
            .patch => {
                const width = surface.grid_width;
                for (0..surface.grid_height - 1) |m| for (0..width - 1) |n| {
                    const base = surface.first_vertex + @as(u32, @intCast(m * width + n));
                    const v = w.vertices.items;
                    const tri1 = [3]Vec3{ v[base].pos, v[base + width].pos, v[base + 1].pos };
                    var normal = scene.normalize(scene.cross(scene.sub(tri1[0], tri1[1]), scene.sub(tri1[2], tri1[1])));
                    if (scene.dot(normal, direction) < -0.1 and addMarkFragments(&state, tri1)) return @intCast(state.returned_fragments);
                    const tri2 = [3]Vec3{ v[base + 1].pos, v[base + width].pos, v[base + width + 1].pos };
                    normal = scene.normalize(scene.cross(scene.sub(tri2[0], tri2[1]), scene.sub(tri2[2], tri2[1])));
                    if (scene.dot(normal, direction) < -0.05 and addMarkFragments(&state, tri2)) return @intCast(state.returned_fragments);
                };
            },
            else => {},
        }
    }
    return @intCast(state.returned_fragments);
}
