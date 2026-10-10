// SPDX-License-Identifier: GPL-2.0-or-later
//! Models and skins: MD3 (frames interpolated in the vertex shader), IQM (skinned in the vertex
//! shader from CPU pose matrices or dk3 live bone matrices) and resident brush models.
//! Follows renderergl1 tr_model.c, tr_mesh.c, tr_model_iqm.c and the skin parts of tr_image.c.
const std = @import("std");
const c = @import("c.zig").c;
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const shader_mod = @import("shader.zig");
const scene = @import("scene.zig");
const world = @import("world.zig");
const Shader = shader_mod.Shader;
const Vec3 = scene.Vec3;

const md3_max_lods = 3;
const max_models = 1024;
const max_iqm_joints = 128;

const Md3Surface = struct {
    name: [c.MAX_QPATH]u8,
    shaders: []*Shader,
    num_verts: u32,
    num_frames: u32,
    num_indexes: u32,
    /// Offsets into the model buffer.
    frames_offset: u64,
    st_offset: u64,
    index_offset: u64,
};

const Md3Tag = struct { name: [c.MAX_QPATH]u8, origin: Vec3, axis: [3]Vec3 };

const Md3 = struct {
    num_frames: u32,
    bounds: [][2]Vec3,
    radius: []f32,
    tags: []Md3Tag, // numFrames * numTags
    num_tags: u32,
    surfaces: []Md3Surface,
    buffer: vk.Buffer,
};

const Transform = struct { translate: Vec3, rotate: [4]f32, scale: Vec3 };

const IqmSurface = struct {
    name: [c.MAX_QPATH]u8,
    shader: *Shader,
    first_triangle: u32,
    num_triangles: u32,
};

const Iqm = struct {
    num_vertexes: u32,
    num_frames: u32,
    num_joints: u32,
    num_poses: u32,
    joint_names: [][]const u8,
    joint_parents: []i32,
    bind_joints: []f32,
    inv_bind_joints: []f32,
    poses: []Transform,
    bounds: ?[]f32,
    surfaces: []IqmSurface,
    buffer: vk.Buffer,
    vertices_offset: u64,
    index_offset: u64,
    text: []u8,
};

pub const Model = struct {
    name: [c.MAX_QPATH]u8,
    index: c.qhandle_t,
    kind: union(enum) { bad, md3: [md3_max_lods]?*Md3, iqm: *Iqm },
    num_lods: u32 = 0,

    fn nameSlice(self: *const Model) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }
};

var models: std.ArrayList(*Model) = .empty;

const SkinSurface = struct { name: [c.MAX_QPATH]u8, shader: *Shader };
const Skin = struct { name: [c.MAX_QPATH]u8, surfaces: []SkinSurface };
var skins: std.ArrayList(*Skin) = .empty;

pub fn init() void {
    const bad = common.gpa.create(Model) catch @panic("OOM");
    bad.* = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .index = 0, .kind = .bad };
    models.append(common.gpa, bad) catch @panic("OOM");
    const default_skin = common.gpa.create(Skin) catch @panic("OOM");
    default_skin.* = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .surfaces = common.gpa.alloc(SkinSurface, 1) catch @panic("OOM") };
    _ = common.qpath(&default_skin.name, "<default skin>");
    default_skin.surfaces[0] = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .shader = shader_mod.default_shader };
    skins.append(common.gpa, default_skin) catch @panic("OOM");
}

pub fn shutdown() void {
    for (models.items) |model| {
        switch (model.kind) {
            .md3 => |lods| {
                var released: [md3_max_lods]?*Md3 = .{ null, null, null };
                for (lods, 0..) |entry, index| {
                    const md3 = entry orelse continue;
                    if (std.mem.indexOfScalar(?*Md3, released[0..index], md3) != null) continue;
                    released[index] = md3;
                    freeMd3(md3);
                }
            },
            .iqm => |iqm| freeIqm(iqm),
            .bad => {},
        }
        common.gpa.destroy(model);
    }
    models.clearAndFree(common.gpa);
    for (skins.items) |skin| {
        common.gpa.free(skin.surfaces);
        common.gpa.destroy(skin);
    }
    skins.clearAndFree(common.gpa);
}

fn freeMd3(md3: *Md3) void {
    vk.destroyBuffer(&md3.buffer);
    for (md3.surfaces) |surface| common.gpa.free(surface.shaders);
    common.gpa.free(md3.surfaces);
    common.gpa.free(md3.bounds);
    common.gpa.free(md3.radius);
    common.gpa.free(md3.tags);
    common.gpa.destroy(md3);
}

fn freeIqm(iqm: *Iqm) void {
    vk.destroyBuffer(&iqm.buffer);
    common.gpa.free(iqm.joint_names);
    common.gpa.free(iqm.joint_parents);
    common.gpa.free(iqm.bind_joints);
    common.gpa.free(iqm.inv_bind_joints);
    common.gpa.free(iqm.poses);
    if (iqm.bounds) |b| common.gpa.free(b);
    common.gpa.free(iqm.surfaces);
    common.gpa.free(iqm.text);
    common.gpa.destroy(iqm);
}

pub fn byHandle(handle: c.qhandle_t) *Model {
    if (handle < 1 or handle >= models.items.len) return models.items[0];
    return models.items[@intCast(handle)];
}

// ---------------------------------------------------------------------------------------------
// MD3

fn readAt(comptime T: type, bytes: []const u8, offset: usize) ?T {
    if (offset > bytes.len or bytes.len - offset < @sizeOf(T)) return null;
    var value: T = undefined;
    @memcpy(std.mem.asBytes(&value), bytes[offset..][0..@sizeOf(T)]);
    return value;
}

var sin_table: [1024]f32 = blk: {
    @setEvalBranchQuota(100000);
    var t: [1024]f32 = undefined;
    for (&t, 0..) |*v, i| v.* = @sin(@as(f32, @floatFromInt(i)) * 360.0 / 1023.0 * std.math.pi / 180.0);
    break :blk t;
};

fn decodeNormal(code: i16) Vec3 {
    const bits: u16 = @bitCast(code);
    const lat: u32 = @as(u32, (bits >> 8) & 0xff) * 4;
    const lng: u32 = @as(u32, bits & 0xff) * 4;
    return .{ sin_table[(lat + 256) & 1023] * sin_table[lng], sin_table[lat] * sin_table[lng], sin_table[(lng + 256) & 1023] };
}

fn loadMd3(bytes: []const u8, name: []const u8) ?*Md3 {
    const header = readAt(c.md3Header_t, bytes, 0) orelse return null;
    if (header.version != c.MD3_VERSION) {
        common.warn("R_LoadMD3: {s} has wrong version ({d} should be {d})\n", .{ name, header.version, c.MD3_VERSION });
        return null;
    }
    if (header.numFrames < 1) {
        common.warn("R_LoadMD3: {s} has no frames\n", .{name});
        return null;
    }
    if (header.ofsEnd < 0 or header.ofsEnd > bytes.len) return null;
    const a = common.gpa;
    const num_frames: u32 = @intCast(header.numFrames);
    const md3 = a.create(Md3) catch @panic("OOM");
    md3.* = .{
        .num_frames = num_frames,
        .bounds = a.alloc([2]Vec3, num_frames) catch @panic("OOM"),
        .radius = a.alloc(f32, num_frames) catch @panic("OOM"),
        .tags = &.{},
        .num_tags = @intCast(@max(header.numTags, 0)),
        .surfaces = &.{},
        .buffer = .{},
    };
    for (0..num_frames) |i| {
        const frame = readAt(c.md3Frame_t, bytes, @as(usize, @intCast(header.ofsFrames)) + i * @sizeOf(c.md3Frame_t)) orelse {
            freeMd3Partial(md3);
            return null;
        };
        md3.bounds[i] = .{ frame.bounds[0], frame.bounds[1] };
        md3.radius[i] = frame.radius;
    }
    md3.tags = a.alloc(Md3Tag, md3.num_tags * num_frames) catch @panic("OOM");
    for (md3.tags, 0..) |*tag, i| {
        const raw = readAt(c.md3Tag_t, bytes, @as(usize, @intCast(header.ofsTags)) + i * @sizeOf(c.md3Tag_t)) orelse {
            freeMd3Partial(md3);
            return null;
        };
        tag.* = .{ .name = raw.name, .origin = raw.origin, .axis = raw.axis };
    }
    var surfaces: std.ArrayList(Md3Surface) = .empty;
    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(a);
    var offset: usize = @intCast(header.ofsSurfaces);
    for (0..@intCast(@max(header.numSurfaces, 0))) |_| {
        const surface = readAt(c.md3Surface_t, bytes, offset) orelse break;
        if (surface.numVerts <= 0 or surface.numTriangles <= 0 or surface.ofsEnd <= 0) break;
        const verts: u32 = @intCast(surface.numVerts);
        const frames: u32 = @intCast(surface.numFrames);
        var info: Md3Surface = .{
            .name = surface.name,
            .shaders = a.alloc(*Shader, @intCast(@max(surface.numShaders, 0))) catch @panic("OOM"),
            .num_verts = verts,
            .num_frames = frames,
            .num_indexes = @intCast(surface.numTriangles * 3),
            .frames_offset = 0,
            .st_offset = 0,
            .index_offset = 0,
        };
        // Lowercase and strip a trailing _1/_2 so skin compares match (R_LoadMD3).
        for (&info.name) |*char| char.* = std.ascii.toLower(char.*);
        const length = std.mem.indexOfScalar(u8, &info.name, 0) orelse info.name.len;
        if (length > 2 and info.name[length - 2] == '_') info.name[length - 2] = 0;
        for (info.shaders, 0..) |*shader, j| {
            const entry = readAt(c.md3Shader_t, bytes, offset + @as(usize, @intCast(surface.ofsShaders)) + j * @sizeOf(c.md3Shader_t)) orelse break;
            const found = shader_mod.find(common.span(&entry.name), shader_mod.lightmap_none, true);
            shader.* = if (found.default_shader) shader_mod.default_shader else found;
        }
        info.frames_offset = std.mem.alignForward(u64, data.items.len, 16);
        data.appendNTimes(a, 0, info.frames_offset - data.items.len) catch @panic("OOM");
        for (0..frames * verts) |j| {
            const xyz = readAt(c.md3XyzNormal_t, bytes, offset + @as(usize, @intCast(surface.ofsXyzNormals)) + j * @sizeOf(c.md3XyzNormal_t)) orelse c.md3XyzNormal_t{ .xyz = .{ 0, 0, 0 }, .normal = 0 };
            const normal = decodeNormal(xyz.normal);
            const values = [6]f32{ @as(f32, @floatFromInt(xyz.xyz[0])) / 64.0, @as(f32, @floatFromInt(xyz.xyz[1])) / 64.0, @as(f32, @floatFromInt(xyz.xyz[2])) / 64.0, normal[0], normal[1], normal[2] };
            data.appendSlice(a, std.mem.asBytes(&values)) catch @panic("OOM");
        }
        info.st_offset = data.items.len;
        for (0..verts) |j| {
            const st = readAt(c.md3St_t, bytes, offset + @as(usize, @intCast(surface.ofsSt)) + j * @sizeOf(c.md3St_t)) orelse c.md3St_t{ .st = .{ 0, 0 } };
            data.appendSlice(a, std.mem.asBytes(&st.st)) catch @panic("OOM");
        }
        info.index_offset = data.items.len;
        for (0..info.num_indexes / 3) |j| {
            const triangle = readAt(c.md3Triangle_t, bytes, offset + @as(usize, @intCast(surface.ofsTriangles)) + j * @sizeOf(c.md3Triangle_t)) orelse c.md3Triangle_t{ .indexes = .{ 0, 0, 0 } };
            for (triangle.indexes) |index| {
                const value: u32 = if (index >= 0 and index < verts) @intCast(index) else 0;
                data.appendSlice(a, std.mem.asBytes(&value)) catch @panic("OOM");
            }
        }
        surfaces.append(a, info) catch @panic("OOM");
        offset += @intCast(surface.ofsEnd);
    }
    md3.surfaces = surfaces.toOwnedSlice(a) catch @panic("OOM");
    md3.buffer = vk.staticBuffer(data.items, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    return md3;
}

fn freeMd3Partial(md3: *Md3) void {
    common.gpa.free(md3.bounds);
    common.gpa.free(md3.radius);
    common.gpa.free(md3.tags);
    common.gpa.destroy(md3);
}

/// `R_RegisterMD3`: level of detail siblings `name_1.md3`, `name_2.md3`.
fn registerMd3(name: []const u8, model: *Model) bool {
    var lods: [md3_max_lods]?*Md3 = .{ null, null, null };
    const dot = std.mem.lastIndexOfScalar(u8, name, '.');
    const base = if (dot) |d| name[0..d] else name;
    const ext = if (dot) |d| name[d + 1 ..] else "md3";
    var loaded: u32 = 0;
    var lod: usize = md3_max_lods;
    while (lod > 0) {
        lod -= 1;
        var path: [c.MAX_QPATH + 20]u8 = undefined;
        const file = (if (lod > 0) std.fmt.bufPrintZ(&path, "{s}_{d}.{s}", .{ base, lod, ext }) else std.fmt.bufPrintZ(&path, "{s}.{s}", .{ base, ext })) catch continue;
        const bytes = common.readFile(file.ptr) orelse continue;
        defer common.freeFile(bytes);
        const ident = readAt(i32, bytes, 0) orelse 0;
        if (ident != c.MD3_IDENT) {
            common.warn("R_RegisterMD3: unknown fileid for {s}\n", .{name});
            break;
        }
        lods[lod] = loadMd3(bytes, name) orelse break;
        loaded += 1;
    }
    if (loaded == 0) return false;
    var highest: usize = 0;
    for (lods, 0..) |entry, index| if (entry != null) {
        highest = index;
    };
    for (0..highest + 1) |index| {
        if (lods[index] != null) continue;
        var fallback: ?*Md3 = null;
        var k = index;
        while (k > 0) {
            k -= 1;
            if (lods[k]) |found| {
                fallback = found;
                break;
            }
        }
        if (fallback == null) for (index + 1..highest + 1) |up| if (lods[up]) |found| {
            fallback = found;
            break;
        };
        lods[index] = fallback;
    }
    for (1..highest + 1) |index| if (lods[index].?.num_frames != lods[0].?.num_frames) {
        common.warn("R_RegisterMD3: mismatched detail frames for {s} level {d}\n", .{ name, index });
        lods[index] = lods[0];
    };
    model.kind = .{ .md3 = lods };
    model.num_lods = @intCast(highest + 1);
    return true;
}

// ---------------------------------------------------------------------------------------------
// IQM

fn matrix34Multiply(a: []const f32, b: []const f32, out: []f32) void {
    var r: [12]f32 = undefined;
    r[0] = a[0] * b[0] + a[1] * b[4] + a[2] * b[8];
    r[1] = a[0] * b[1] + a[1] * b[5] + a[2] * b[9];
    r[2] = a[0] * b[2] + a[1] * b[6] + a[2] * b[10];
    r[3] = a[0] * b[3] + a[1] * b[7] + a[2] * b[11] + a[3];
    r[4] = a[4] * b[0] + a[5] * b[4] + a[6] * b[8];
    r[5] = a[4] * b[1] + a[5] * b[5] + a[6] * b[9];
    r[6] = a[4] * b[2] + a[5] * b[6] + a[6] * b[10];
    r[7] = a[4] * b[3] + a[5] * b[7] + a[6] * b[11] + a[7];
    r[8] = a[8] * b[0] + a[9] * b[4] + a[10] * b[8];
    r[9] = a[8] * b[1] + a[9] * b[5] + a[10] * b[9];
    r[10] = a[8] * b[2] + a[9] * b[6] + a[10] * b[10];
    r[11] = a[8] * b[3] + a[9] * b[7] + a[10] * b[11] + a[11];
    @memcpy(out[0..12], &r);
}

fn jointToMatrix(rot: [4]f32, s: Vec3, t: Vec3, mat: []f32) void {
    const xx = 2 * rot[0] * rot[0];
    const yy = 2 * rot[1] * rot[1];
    const zz = 2 * rot[2] * rot[2];
    const xy = 2 * rot[0] * rot[1];
    const xz = 2 * rot[0] * rot[2];
    const yz = 2 * rot[1] * rot[2];
    const wx = 2 * rot[3] * rot[0];
    const wy = 2 * rot[3] * rot[1];
    const wz = 2 * rot[3] * rot[2];
    mat[0..12].* = .{
        s[0] * (1 - (yy + zz)), s[0] * (xy - wz),       s[0] * (xz + wy),       t[0],
        s[1] * (xy + wz),       s[1] * (1 - (xx + zz)), s[1] * (yz - wx),       t[1],
        s[2] * (xz - wy),       s[2] * (yz + wx),       s[2] * (1 - (xx + yy)), t[2],
    };
}

fn matrix34Invert(in: []const f32, out: []f32) void {
    out[0] = in[0];
    out[1] = in[4];
    out[2] = in[8];
    out[4] = in[1];
    out[5] = in[5];
    out[6] = in[9];
    out[8] = in[2];
    out[9] = in[6];
    out[10] = in[10];
    for ([_]usize{ 0, 4, 8 }) |row| {
        const v = out[row..][0..3];
        const square = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
        const inverse: f32 = if (square != 0) 1 / square else 0;
        for (v) |*value| value.* *= inverse;
    }
    const t = [3]f32{ in[3], in[7], in[11] };
    out[3] = -(out[0] * t[0] + out[1] * t[1] + out[2] * t[2]);
    out[7] = -(out[4] * t[0] + out[5] * t[1] + out[6] * t[2]);
    out[11] = -(out[8] * t[0] + out[9] * t[1] + out[10] * t[2]);
}

fn quatNormalize(v: [4]f32) [4]f32 {
    const square = v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3];
    if (square == 0) return .{ 0, 0, 0, -1 };
    const inverse = 1 / @sqrt(square);
    return .{ v[0] * inverse, v[1] * inverse, v[2] * inverse, v[3] * inverse };
}

fn quatSlerp(from: [4]f32, to_in: [4]f32, fraction: f32) [4]f32 {
    var cos_angle = from[0] * to_in[0] + from[1] * to_in[1] + from[2] * to_in[2] + from[3] * to_in[3];
    var to = to_in;
    if (cos_angle < 0) {
        cos_angle = -cos_angle;
        to = .{ -to_in[0], -to_in[1], -to_in[2], -to_in[3] };
    }
    var back: f32 = 1 - fraction;
    var lerp: f32 = fraction;
    if (cos_angle < 0.999999) {
        const angle = std.math.acos(cos_angle);
        const sin_angle = @sin(angle);
        back = @sin((1 - fraction) * angle) / sin_angle;
        lerp = @sin(fraction * angle) / sin_angle;
    }
    return .{ from[0] * back + to[0] * lerp, from[1] * back + to[1] * lerp, from[2] * back + to[2] * lerp, from[3] * back + to[3] * lerp };
}

fn iqmText(text: []const u8, offset: u32) []const u8 {
    if (offset >= text.len) return "";
    return std.mem.sliceTo(text[offset..], 0);
}

fn loadIqm(bytes: []const u8, name: []const u8) ?*Iqm {
    const header = readAt(c.iqmHeader_t, bytes, 0) orelse return null;
    if (!std.mem.eql(u8, header.magic[0..15], c.IQM_MAGIC) or header.version != c.IQM_VERSION or header.filesize > bytes.len) {
        common.warn("R_LoadIQM: {s} is not a version {d} IQM\n", .{ name, c.IQM_VERSION });
        return null;
    }
    if (header.num_joints > max_iqm_joints or header.num_poses > max_iqm_joints) {
        common.warn("R_LoadIQM: {s} has more than {d} joints\n", .{ name, max_iqm_joints });
        return null;
    }
    const a = common.gpa;
    const vertex_count = header.num_vertexes;
    var positions: ?[]const u8 = null;
    var normals: ?[]const u8 = null;
    var texcoords: ?[]const u8 = null;
    var blend_indexes: ?[]const u8 = null;
    var blend_weights: ?[]const u8 = null;
    var colors: ?[]const u8 = null;
    var index_format: u32 = c.IQM_UBYTE;
    var weight_format: u32 = c.IQM_UBYTE;
    for (0..header.num_vertexarrays) |i| {
        const array = readAt(c.iqmVertexArray_t, bytes, header.ofs_vertexarrays + i * @sizeOf(c.iqmVertexArray_t)) orelse return null;
        const element: u32 = switch (array.format) {
            c.IQM_BYTE, c.IQM_UBYTE => 1,
            c.IQM_SHORT, c.IQM_USHORT, c.IQM_HALF => 2,
            c.IQM_INT, c.IQM_UINT, c.IQM_FLOAT => 4,
            c.IQM_DOUBLE => 8,
            else => return null,
        };
        const size = @as(usize, vertex_count) * array.size * element;
        if (array.offset > bytes.len or size > bytes.len - array.offset) return null;
        const data = bytes[array.offset..][0..size];
        switch (array.type) {
            c.IQM_POSITION => if (array.format == c.IQM_FLOAT and array.size == 3) {
                positions = data;
            },
            c.IQM_NORMAL => if (array.format == c.IQM_FLOAT and array.size == 3) {
                normals = data;
            },
            c.IQM_TEXCOORD => if (array.format == c.IQM_FLOAT and array.size == 2) {
                texcoords = data;
            },
            c.IQM_BLENDINDEXES => if ((array.format == c.IQM_UBYTE or array.format == c.IQM_INT) and array.size == 4) {
                blend_indexes = data;
                index_format = array.format;
            },
            c.IQM_BLENDWEIGHTS => if ((array.format == c.IQM_UBYTE or array.format == c.IQM_FLOAT) and array.size == 4) {
                blend_weights = data;
                weight_format = array.format;
            },
            c.IQM_COLOR => if (array.format == c.IQM_UBYTE and array.size == 4) {
                colors = data;
            },
            else => {},
        }
    }
    const position_data = positions orelse {
        common.warn("R_LoadIQM: {s} has no positions\n", .{name});
        return null;
    };
    if (header.ofs_text > bytes.len or header.num_text > bytes.len - header.ofs_text) return null;
    const iqm = a.create(Iqm) catch @panic("OOM");
    iqm.* = .{
        .num_vertexes = vertex_count,
        .num_frames = header.num_frames,
        .num_joints = header.num_joints,
        .num_poses = header.num_poses,
        .joint_names = a.alloc([]const u8, header.num_joints) catch @panic("OOM"),
        .joint_parents = a.alloc(i32, header.num_joints) catch @panic("OOM"),
        .bind_joints = a.alloc(f32, header.num_joints * 12) catch @panic("OOM"),
        .inv_bind_joints = a.alloc(f32, header.num_joints * 12) catch @panic("OOM"),
        .poses = a.alloc(Transform, header.num_frames * header.num_poses) catch @panic("OOM"),
        .bounds = null,
        .surfaces = a.alloc(IqmSurface, header.num_meshes) catch @panic("OOM"),
        .buffer = .{},
        .vertices_offset = 0,
        .index_offset = 0,
        .text = a.dupe(u8, bytes[header.ofs_text..][0..header.num_text]) catch @panic("OOM"),
    };
    // Vertices: position, normal, st, blend indexes, blend weights, colour (12 words).
    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(a);
    for (0..vertex_count) |v| {
        var out: [12]u32 = .{0} ** 12;
        for (0..3) |k| out[k] = std.mem.readInt(u32, position_data[(v * 3 + k) * 4 ..][0..4], .little);
        if (normals) |n| for (0..3) |k| {
            out[3 + k] = std.mem.readInt(u32, n[(v * 3 + k) * 4 ..][0..4], .little);
        };
        if (texcoords) |t| for (0..2) |k| {
            out[6 + k] = std.mem.readInt(u32, t[(v * 2 + k) * 4 ..][0..4], .little);
        };
        var indexes: [4]u8 = .{ 0, 0, 0, 0 };
        var weights: [4]u8 = .{ 255, 0, 0, 0 };
        if (blend_indexes) |b| for (0..4) |k| {
            indexes[k] = if (index_format == c.IQM_UBYTE) b[v * 4 + k] else @intCast(std.math.clamp(std.mem.readInt(i32, b[(v * 4 + k) * 4 ..][0..4], .little), 0, 255));
        };
        if (blend_weights) |w| for (0..4) |k| {
            weights[k] = if (weight_format == c.IQM_UBYTE) w[v * 4 + k] else @intFromFloat(std.math.clamp(@as(f32, @bitCast(std.mem.readInt(u32, w[(v * 4 + k) * 4 ..][0..4], .little))) * 255 + 0.5, 0, 255));
        };
        if (blend_weights == null or header.num_poses == 0) weights = .{ 0, 0, 0, 0 };
        out[8] = std.mem.readInt(u32, &indexes, .little);
        out[9] = std.mem.readInt(u32, &weights, .little);
        out[10] = if (colors) |col| std.mem.readInt(u32, col[v * 4 ..][0..4], .little) else 0;
        data.appendSlice(a, std.mem.sliceAsBytes(&out)) catch @panic("OOM");
    }
    iqm.index_offset = data.items.len;
    for (0..header.num_triangles) |t| {
        const triangle = readAt(c.iqmTriangle_t, bytes, header.ofs_triangles + t * @sizeOf(c.iqmTriangle_t)) orelse c.iqmTriangle_t{ .vertex = .{ 0, 0, 0 } };
        for (triangle.vertex) |index| {
            const value: u32 = if (index < vertex_count) index else 0;
            data.appendSlice(a, std.mem.asBytes(&value)) catch @panic("OOM");
        }
    }
    for (iqm.surfaces, 0..) |*surface, m| {
        const mesh = readAt(c.iqmMesh_t, bytes, header.ofs_meshes + m * @sizeOf(c.iqmMesh_t)) orelse c.iqmMesh_t{ .name = 0, .material = 0, .first_vertex = 0, .num_vertexes = 0, .first_triangle = 0, .num_triangles = 0 };
        var lowered: [c.MAX_QPATH]u8 = std.mem.zeroes([c.MAX_QPATH]u8);
        const mesh_name = iqmText(iqm.text, mesh.name);
        for (mesh_name[0..@min(mesh_name.len, lowered.len - 1)], 0..) |char, k| lowered[k] = std.ascii.toLower(char);
        const material = shader_mod.find(iqmText(iqm.text, mesh.material), shader_mod.lightmap_none, true);
        surface.* = .{
            .name = lowered,
            .shader = if (material.default_shader) shader_mod.default_shader else material,
            .first_triangle = @min(mesh.first_triangle, header.num_triangles),
            .num_triangles = if (mesh.first_triangle <= header.num_triangles) @min(mesh.num_triangles, header.num_triangles - mesh.first_triangle) else 0,
        };
    }
    for (0..header.num_joints) |j| {
        var joint = readAt(c.iqmJoint_t, bytes, header.ofs_joints + j * @sizeOf(c.iqmJoint_t)) orelse std.mem.zeroes(c.iqmJoint_t);
        iqm.joint_names[j] = iqmText(iqm.text, joint.name);
        iqm.joint_parents[j] = if (joint.parent < @as(i32, @intCast(j))) joint.parent else -1;
        joint.rotate = quatNormalize(joint.rotate);
        var base: [12]f32 = undefined;
        var inverse: [12]f32 = undefined;
        jointToMatrix(joint.rotate, joint.scale, joint.translate, &base);
        matrix34Invert(&base, &inverse);
        const parent = iqm.joint_parents[j];
        if (parent >= 0) {
            const p: usize = @intCast(parent);
            matrix34Multiply(iqm.bind_joints[p * 12 ..][0..12], &base, iqm.bind_joints[j * 12 ..][0..12]);
            matrix34Multiply(&inverse, iqm.inv_bind_joints[p * 12 ..][0..12], iqm.inv_bind_joints[j * 12 ..][0..12]);
        } else {
            @memcpy(iqm.bind_joints[j * 12 ..][0..12], &base);
            @memcpy(iqm.inv_bind_joints[j * 12 ..][0..12], &inverse);
        }
    }
    if (header.num_poses > 0) {
        var frame_offset: usize = header.ofs_frames;
        for (0..header.num_frames) |f| {
            for (0..header.num_poses) |p| {
                const pose = readAt(c.iqmPose_t, bytes, header.ofs_poses + p * @sizeOf(c.iqmPose_t)) orelse std.mem.zeroes(c.iqmPose_t);
                var channels: [10]f32 = undefined;
                for (0..10) |k| {
                    channels[k] = pose.channeloffset[k];
                    if (pose.mask & (@as(u32, 1) << @intCast(k)) != 0) {
                        const value = readAt(u16, bytes, frame_offset) orelse 0;
                        frame_offset += 2;
                        channels[k] += @as(f32, @floatFromInt(value)) * pose.channelscale[k];
                    }
                }
                iqm.poses[f * header.num_poses + p] = .{
                    .translate = channels[0..3].*,
                    .rotate = quatNormalize(channels[3..7].*),
                    .scale = channels[7..10].*,
                };
            }
        }
    }
    if (header.ofs_bounds != 0 and header.num_frames > 0) {
        const b = a.alloc(f32, header.num_frames * 6) catch @panic("OOM");
        for (0..header.num_frames) |f| {
            const entry = readAt(c.iqmBounds_t, bytes, header.ofs_bounds + f * @sizeOf(c.iqmBounds_t)) orelse std.mem.zeroes(c.iqmBounds_t);
            b[f * 6 ..][0..6].* = .{ entry.bbmin[0], entry.bbmin[1], entry.bbmin[2], entry.bbmax[0], entry.bbmax[1], entry.bbmax[2] };
        }
        iqm.bounds = b;
    } else if (header.num_meshes > 0 and header.num_frames == 0) {
        const b = a.alloc(f32, 6) catch @panic("OOM");
        b[0..6].* = .{ 1e30, 1e30, 1e30, -1e30, -1e30, -1e30 };
        for (0..vertex_count) |v| for (0..3) |k| {
            const value: f32 = @bitCast(std.mem.readInt(u32, position_data[(v * 3 + k) * 4 ..][0..4], .little));
            b[k] = @min(b[k], value);
            b[3 + k] = @max(b[3 + k], value);
        };
        iqm.bounds = b;
    }
    iqm.buffer = vk.staticBuffer(data.items, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT);
    return iqm;
}

fn computePoseMats(iqm: *const Iqm, frame: u32, oldframe: u32, backlerp: f32, out: []f32) void {
    var relative: [max_iqm_joints]Transform = undefined;
    const n = iqm.num_poses;
    if (frame == oldframe) {
        @memcpy(relative[0..n], iqm.poses[frame * n ..][0..n]);
    } else {
        const lerp = 1 - backlerp;
        for (0..n) |i| {
            const pose = iqm.poses[frame * n + i];
            const old = iqm.poses[oldframe * n + i];
            for (0..3) |k| {
                relative[i].translate[k] = old.translate[k] * backlerp + pose.translate[k] * lerp;
                relative[i].scale[k] = old.scale[k] * backlerp + pose.scale[k] * lerp;
            }
            relative[i].rotate = quatSlerp(old.rotate, pose.rotate, lerp);
        }
    }
    for (0..n) |i| {
        var mat1: [12]f32 = undefined;
        var mat2: [12]f32 = undefined;
        jointToMatrix(relative[i].rotate, relative[i].scale, relative[i].translate, &mat1);
        const parent = if (i < iqm.joint_parents.len) iqm.joint_parents[i] else -1;
        const inv = iqm.inv_bind_joints[i * 12 ..][0..12];
        if (parent >= 0) {
            const p: usize = @intCast(parent);
            matrix34Multiply(iqm.bind_joints[p * 12 ..][0..12], &mat1, &mat2);
            matrix34Multiply(&mat2, inv, &mat1);
            matrix34Multiply(out[p * 12 ..][0..12], &mat1, out[i * 12 ..][0..12]);
        } else matrix34Multiply(&mat1, inv, out[i * 12 ..][0..12]);
    }
}

fn computeJointMats(iqm: *const Iqm, frame: u32, oldframe: u32, backlerp: f32, out: []f32) void {
    if (iqm.num_poses == 0) {
        @memcpy(out[0 .. iqm.num_joints * 12], iqm.bind_joints);
        return;
    }
    computePoseMats(iqm, frame, oldframe, backlerp, out);
    for (0..iqm.num_joints) |i| {
        var pose: [12]f32 = undefined;
        @memcpy(&pose, out[i * 12 ..][0..12]);
        matrix34Multiply(&pose, iqm.bind_joints[i * 12 ..][0..12], out[i * 12 ..][0..12]);
    }
}

fn registerIqm(name: []const u8, model: *Model) bool {
    var path: [c.MAX_QPATH]u8 = undefined;
    const bytes = common.readFile(common.qpath(&path, name).ptr) orelse return false;
    defer common.freeFile(bytes);
    const iqm = loadIqm(bytes, name) orelse {
        common.warn("R_RegisterIQM: couldn't load iqm file {s}\n", .{name});
        return false;
    };
    model.kind = .{ .iqm = iqm };
    return true;
}

// ---------------------------------------------------------------------------------------------
// Registration

const Loader = struct { ext: []const u8, load: *const fn ([]const u8, *Model) bool };
const loaders = [_]Loader{ .{ .ext = "iqm", .load = registerIqm }, .{ .ext = "md3", .load = registerMd3 } };

/// `RE_RegisterModel`.
pub fn register(name_ptr: [*c]const u8) c.qhandle_t {
    const name = common.span(name_ptr);
    if (name.len == 0) {
        common.info("RE_RegisterModel: NULL name\n", .{});
        return 0;
    }
    if (name.len >= c.MAX_QPATH) {
        common.info("Model name exceeds MAX_QPATH\n", .{});
        return 0;
    }
    if (name[0] == '*') return world.inlineModel(name);
    for (models.items[1..]) |model| {
        if (std.mem.eql(u8, model.nameSlice(), name)) return if (model.kind == .bad) 0 else model.index;
    }
    if (models.items.len >= max_models) {
        common.warn("RE_RegisterModel: R_AllocModel() failed for '{s}'\n", .{name});
        return 0;
    }
    const model = common.gpa.create(Model) catch @panic("OOM");
    model.* = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .index = @intCast(models.items.len), .kind = .bad };
    _ = common.qpath(&model.name, name);
    models.append(common.gpa, model) catch @panic("OOM");
    const ext = @import("image.zig").extension(name);
    var original: ?usize = null;
    var local: []const u8 = name;
    if (ext.len > 0) {
        for (loaders, 0..) |loader, index| {
            if (!std.ascii.eqlIgnoreCase(ext, loader.ext)) continue;
            if (loader.load(name, model)) return model.index;
            original = index;
            local = @import("image.zig").stripExtension(name);
            break;
        }
    }
    for (loaders, 0..) |loader, index| {
        if (original == index) continue;
        var buffer: [c.MAX_QPATH]u8 = undefined;
        const alternative = std.fmt.bufPrint(&buffer, "{s}.{s}", .{ local, loader.ext }) catch continue;
        if (loader.load(alternative, model)) {
            if (original != null) common.developer("WARNING: {s} not present, using {s} instead\n", .{ name, alternative });
            return model.index;
        }
    }
    return 0;
}

/// `RE_RegisterSkin`.
pub fn registerSkin(name_ptr: [*c]const u8) c.qhandle_t {
    const name = common.span(name_ptr);
    if (name.len == 0) {
        common.info("Empty name passed to RE_RegisterSkin\n", .{});
        return 0;
    }
    if (name.len >= c.MAX_QPATH) {
        common.info("Skin name exceeds MAX_QPATH\n", .{});
        return 0;
    }
    for (skins.items, 0..) |skin, index| {
        if (std.ascii.eqlIgnoreCase(std.mem.sliceTo(&skin.name, 0), name)) return if (skin.surfaces.len == 0) 0 else @intCast(index);
    }
    const skin = common.gpa.create(Skin) catch @panic("OOM");
    skin.* = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .surfaces = &.{} };
    _ = common.qpath(&skin.name, name);
    skins.append(common.gpa, skin) catch @panic("OOM");
    const index: c.qhandle_t = @intCast(skins.items.len - 1);
    if (!std.ascii.endsWithIgnoreCase(name, ".skin")) {
        skin.surfaces = common.gpa.alloc(SkinSurface, 1) catch @panic("OOM");
        skin.surfaces[0] = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .shader = shader_mod.find(name, shader_mod.lightmap_none, true) };
        return index;
    }
    var path: [c.MAX_QPATH]u8 = undefined;
    const bytes = common.readFile(common.qpath(&path, name).ptr) orelse return 0;
    defer common.freeFile(bytes);
    const text = common.gpa.dupeZ(u8, bytes) catch return 0;
    defer common.gpa.free(text);
    var entries: std.ArrayList(SkinSurface) = .empty;
    var lines = std.mem.splitAny(u8, text, "\r\n");
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t");
        const comma = std.mem.indexOfScalar(u8, line, ',') orelse continue;
        const surface_name = std.mem.trim(u8, line[0..comma], " \t\"");
        const shader_name = std.mem.trim(u8, line[comma + 1 ..], " \t\"");
        if (surface_name.len == 0 or std.mem.indexOf(u8, surface_name, "tag_") != null) continue;
        var entry: SkinSurface = .{ .name = std.mem.zeroes([c.MAX_QPATH]u8), .shader = undefined };
        for (surface_name[0..@min(surface_name.len, c.MAX_QPATH - 1)], 0..) |char, k| entry.name[k] = std.ascii.toLower(char);
        entry.shader = shader_mod.find(shader_name, shader_mod.lightmap_none, true);
        entries.append(common.gpa, entry) catch break;
        if (entries.items.len >= 256) break;
    }
    skin.surfaces = entries.toOwnedSlice(common.gpa) catch &.{};
    return if (skin.surfaces.len == 0) 0 else index;
}

fn skinShader(handle: c.qhandle_t, surface_name: []const u8) *Shader {
    if (handle <= 0 or handle >= skins.items.len) return shader_mod.default_shader;
    const skin = skins.items[@intCast(handle)];
    for (skin.surfaces) |entry| {
        if (std.mem.eql(u8, std.mem.sliceTo(&entry.name, 0), surface_name)) return entry.shader;
    }
    common.developer("WARNING: no shader for surface {s} in skin {s}\n", .{ surface_name, std.mem.sliceTo(&skin.name, 0) });
    return shader_mod.default_shader;
}

// ---------------------------------------------------------------------------------------------
// Queries

fn md3Tag(md3: *const Md3, frame_in: c_int, tag_name: []const u8) ?*const Md3Tag {
    if (md3.num_tags == 0) return null;
    const frame: u32 = if (frame_in < 0) 0 else @min(@as(u32, @intCast(frame_in)), md3.num_frames - 1);
    for (md3.tags[frame * md3.num_tags ..][0..md3.num_tags]) |*tag| {
        if (std.mem.eql(u8, std.mem.sliceTo(&tag.name, 0), tag_name)) return tag;
    }
    return null;
}

/// `R_LerpTag`.
pub fn lerpTag(tag: *c.orientation_t, handle: c.qhandle_t, start_frame: c_int, end_frame: c_int, frac: f32, tag_name_ptr: [*c]const u8) c_int {
    const tag_name = common.span(tag_name_ptr);
    const model = byHandle(handle);
    tag.* = std.mem.zeroes(c.orientation_t);
    tag.axis = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    switch (model.kind) {
        .md3 => |lods| {
            const md3 = lods[0] orelse return 0;
            const start = md3Tag(md3, start_frame, tag_name) orelse return 0;
            const end = md3Tag(md3, end_frame, tag_name) orelse return 0;
            const back = 1 - frac;
            for (0..3) |i| {
                tag.origin[i] = start.origin[i] * back + end.origin[i] * frac;
                for (0..3) |k| tag.axis[k][i] = start.axis[k][i] * back + end.axis[k][i] * frac;
            }
            for (&tag.axis) |*axis| axis.* = scene.normalize(axis.*);
            return 1;
        },
        .iqm => |iqm| {
            var joint: usize = 0;
            while (joint < iqm.num_joints) : (joint += 1) {
                if (std.mem.eql(u8, iqm.joint_names[joint], tag_name)) break;
            }
            if (joint >= iqm.num_joints) return 0;
            var mats: [max_iqm_joints * 12]f32 = undefined;
            const frames = @max(iqm.num_frames, 1);
            computeJointMats(iqm, @intCast(@mod(@max(start_frame, 0), @as(c_int, @intCast(frames)))), @intCast(@mod(@max(end_frame, 0), @as(c_int, @intCast(frames)))), frac, &mats);
            const m = mats[joint * 12 ..][0..12];
            tag.axis = .{ .{ m[0], m[4], m[8] }, .{ m[1], m[5], m[9] }, .{ m[2], m[6], m[10] } };
            tag.origin = .{ m[3], m[7], m[11] };
            return 1;
        },
        .bad => return 0,
    }
}

/// `R_ModelBounds`.
/// World-space box of an MD3 or IQM entity this frame (null for brush models and bad models).
pub fn entityBox(e: *const c.refEntity_t) ?[2]Vec3 {
    if (world.residentInline(e.hModel) != null) return null;
    const model = byHandle(e.hModel);
    switch (model.kind) {
        .md3 => |lods| {
            const base = lods[0] orelse return null;
            if (base.num_frames == 0) return null;
            const frame: usize = @intCast(std.math.clamp(e.frame, 0, @as(c_int, @intCast(base.num_frames - 1))));
            return worldBox(e, base.bounds[frame][0], base.bounds[frame][1]);
        },
        .iqm => |iqm| {
            if (e.dk3BoneCount == iqm.num_joints and iqm.num_joints <= 64 and iqm.num_joints > 0) return worldBox(e, e.dk3BoneBounds[0], e.dk3BoneBounds[1]);
            const b = iqm.bounds orelse return null;
            const frames = @max(iqm.num_frames, 1);
            const frame: usize = @intCast(@mod(e.frame, @as(c_int, @intCast(frames))));
            const box = b[frame * 6 ..][0..6];
            return worldBox(e, box[0..3].*, box[3..6].*);
        },
        .bad => return null,
    }
}

pub fn bounds(handle: c.qhandle_t, mins: *Vec3, maxs: *Vec3) void {
    if (world.bounds(handle, mins, maxs)) return;
    const model = byHandle(handle);
    switch (model.kind) {
        .md3 => |lods| if (lods[0]) |md3| {
            mins.* = md3.bounds[0][0];
            maxs.* = md3.bounds[0][1];
            return;
        },
        .iqm => |iqm| if (iqm.bounds) |b| {
            mins.* = b[0..3].*;
            maxs.* = b[3..6].*;
            return;
        },
        .bad => {},
    }
    mins.* = .{ 0, 0, 0 };
    maxs.* = .{ 0, 0, 0 };
}

// ---------------------------------------------------------------------------------------------
// Entity surfaces

fn worldBox(e: *const c.refEntity_t, mins: Vec3, maxs: Vec3) [2]Vec3 {
    var out_min: Vec3 = .{ 1e30, 1e30, 1e30 };
    var out_max: Vec3 = .{ -1e30, -1e30, -1e30 };
    for (0..8) |corner| {
        const local: Vec3 = .{
            if (corner & 1 != 0) maxs[0] else mins[0],
            if (corner & 2 != 0) maxs[1] else mins[1],
            if (corner & 4 != 0) maxs[2] else mins[2],
        };
        var p: Vec3 = e.origin;
        for (0..3) |k| p = scene.madd(p, local[k], e.axis[k]);
        for (0..3) |k| {
            out_min[k] = @min(out_min[k], p[k]);
            out_max[k] = @max(out_max[k], p[k]);
        }
    }
    return .{ out_min, out_max };
}

fn computeLod(view: *const scene.View, model: *const Model, md3: *const Md3, e: *const c.refEntity_t) u32 {
    var lod: i32 = 0;
    if (model.num_lods >= 2) {
        const frame: usize = @intCast(@min(@max(e.frame, 0), @as(c_int, @intCast(md3.num_frames - 1))));
        const b = md3.bounds[frame];
        const radius = scene.length(scene.scale(scene.sub(b[1], b[0]), 0.5));
        const distance = scene.dot(view.axis[0], e.origin) - scene.dot(view.axis[0], view.origin);
        var flod: f32 = 0;
        if (distance > 0) {
            var projected = @abs(radius) * view.projection[1][1] / distance;
            if (projected > 1) projected = 1;
            if (projected != 0) flod = 1.0 - projected * @min(lodscale(), 20);
        }
        flod *= @floatFromInt(model.num_lods);
        lod = std.math.clamp(@as(i32, @intFromFloat(flod)), 0, @as(i32, @intCast(model.num_lods)) - 1);
    }
    lod += cvars.lodbias.integer;
    return @intCast(std.math.clamp(lod, 0, @as(i32, @intCast(model.num_lods)) - 1));
}

var lodscale_cvar: ?*c.cvar_t = null;
fn lodscale() f32 {
    if (lodscale_cvar == null) lodscale_cvar = common.cvar("r_lodscale", "5", c.CVAR_CHEAT);
    return lodscale_cvar.?.value;
}

/// R_AddEntitySurfaces for RT_MODEL: MD3, IQM or a resident brush model.
pub fn addEntitySurfaces(view: *scene.View, entity: *scene.Entity, number: u32) void {
    const e = &entity.e;
    if (world.residentInline(e.hModel)) |ref| {
        scene.stats.brush += 1;
        world.addBrushModel(view, entity, number, ref);
        return;
    }
    const model = byHandle(e.hModel);
    // Shadow tiles include the player's own third-person body.
    const personal = e.renderfx & c.RF_THIRD_PERSON != 0 and !view.is_portal and !view.shadow;
    switch (model.kind) {
        .bad => {
            if (personal) return;
            common.developer("renderer_vulkan: entity with bad model {d}\n", .{e.hModel});
        },
        .md3 => |lods| {
            const base = lods[0] orelse return;
            if (e.renderfx & c.RF_WRAP_FRAMES != 0) {
                e.frame = @mod(e.frame, @as(c_int, @intCast(base.num_frames)));
                e.oldframe = @mod(e.oldframe, @as(c_int, @intCast(base.num_frames)));
            }
            if (e.frame >= base.num_frames or e.frame < 0 or e.oldframe >= base.num_frames or e.oldframe < 0) {
                common.developer("R_AddMD3Surfaces: no such frame {d} to {d} for '{s}'\n", .{ e.oldframe, e.frame, model.nameSlice() });
                e.frame = 0;
                e.oldframe = 0;
            }
            scene.stats.md3 += 1;
            const md3 = lods[computeLod(view, model, base, e)] orelse base;
            const frame: u32 = @intCast(e.frame);
            const oldframe: u32 = @intCast(e.oldframe);
            var mins = md3.bounds[frame][0];
            var maxs = md3.bounds[frame][1];
            for (0..3) |k| {
                mins[k] = @min(mins[k], md3.bounds[oldframe][0][k]);
                maxs[k] = @max(maxs[k], md3.bounds[oldframe][1][k]);
            }
            const box = worldBox(e, mins, maxs);
            if (view.cullBox(box[0], box[1])) return;
            if (personal) return;
            for (md3.surfaces) |*surface| {
                const shader = if (e.customShader != 0) shader_mod.byHandle(e.customShader) else if (e.customSkin > 0) skinShader(e.customSkin, std.mem.sliceTo(&surface.name, 0)) else if (surface.shaders.len == 0) shader_mod.default_shader else surface.shaders[@intCast(@mod(e.skinNum, @as(c_int, @intCast(surface.shaders.len))))];
                const surface_frame = @min(frame, surface.num_frames - 1);
                const surface_old = @min(oldframe, surface.num_frames - 1);
                const stride: u64 = @as(u64, surface.num_verts) * 24;
                scene.addDrawSurf(shader, number, .{ .mesh = .{
                    .kind = 1,
                    .vertices = md3.buffer.address + surface.frames_offset + surface_frame * stride,
                    .frame_b = md3.buffer.address + surface.frames_offset + surface_old * stride,
                    .extra = md3.buffer.address + surface.st_offset,
                    .indices = md3.buffer.address + surface.index_offset,
                    .count = surface.num_indexes,
                    .backlerp = e.backlerp,
                } }, 0);
            }
        },
        .iqm => |iqm| {
            scene.stats.iqm += 1;
            const frames = @max(iqm.num_frames, 1);
            if (e.renderfx & c.RF_WRAP_FRAMES != 0 and iqm.num_frames > 0) {
                e.frame = @mod(e.frame, @as(c_int, @intCast(frames)));
                e.oldframe = @mod(e.oldframe, @as(c_int, @intCast(frames)));
            }
            if (e.frame >= iqm.num_frames or e.frame < 0 or e.oldframe >= iqm.num_frames or e.oldframe < 0) {
                if (iqm.num_frames > 0) common.developer("R_AddIQMSurfaces: no such frame {d} to {d} for '{s}'\n", .{ e.oldframe, e.frame, model.nameSlice() });
                e.frame = 0;
                e.oldframe = 0;
            }
            // Live physics bounds supersede stored animation bounds (R_CullIQM).
            if (e.dk3BoneCount == iqm.num_joints and iqm.num_joints <= 64) {
                const box = worldBox(e, e.dk3BoneBounds[0], e.dk3BoneBounds[1]);
                if (view.cullBox(box[0], box[1])) {
                    scene.stats.iqm_culled += 1;
                    return;
                }
            } else if (iqm.bounds) |b| {
                const new = b[@as(usize, @intCast(e.frame)) * 6 ..][0..6];
                const old = b[@as(usize, @intCast(e.oldframe)) * 6 ..][0..6];
                const box = worldBox(e, .{ @min(new[0], old[0]), @min(new[1], old[1]), @min(new[2], old[2]) }, .{ @max(new[3], old[3]), @max(new[4], old[4]), @max(new[5], old[5]) });
                if (view.cullBox(box[0], box[1])) {
                    scene.stats.iqm_culled += 1;
                    if (cvars.vkStats.integer > 0 and scene.stats.iqm_culled == 1)
                        common.developer("vk cull iqm: model={s} frame={d}/{d} origin={d:.0},{d:.0},{d:.0} local={d:.1},{d:.1},{d:.1}..{d:.1},{d:.1},{d:.1} view={d:.0},{d:.0},{d:.0} fwd={d:.2},{d:.2},{d:.2}\n", .{ model.nameSlice(), e.frame, iqm.num_frames, e.origin[0], e.origin[1], e.origin[2], new[0], new[1], new[2], new[3], new[4], new[5], view.origin[0], view.origin[1], view.origin[2], view.axis[0][0], view.axis[0][1], view.axis[0][2] });
                    return;
                }
            }
            if (personal) return;
            var bones: u64 = 0;
            if (iqm.num_poses > 0) {
                const space = vk.frame().stream.alloc(@as(u64, iqm.num_poses) * 48, 16) orelse return;
                const mats: []f32 = @alignCast(std.mem.bytesAsSlice(f32, space.bytes));
                if (e.dk3BoneCount == iqm.num_poses and iqm.num_poses <= 64) {
                    for (0..iqm.num_poses) |i| @memcpy(mats[i * 12 ..][0..12], &e.dk3BoneMatrices[i]);
                } else {
                    const frame: u32 = if (iqm.num_frames > 0) @intCast(@mod(e.frame, @as(c_int, @intCast(frames)))) else 0;
                    const oldframe: u32 = if (iqm.num_frames > 0) @intCast(@mod(e.oldframe, @as(c_int, @intCast(frames)))) else 0;
                    if (iqm.num_frames > 0) {
                        computePoseMats(iqm, frame, oldframe, e.backlerp, mats);
                    } else for (0..iqm.num_poses) |i| {
                        mats[i * 12 ..][0..12].* = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 };
                    }
                }
                bones = space.address;
            }
            for (iqm.surfaces) |*surface| {
                if (surface.num_triangles == 0) continue;
                const shader = if (e.customShader != 0) shader_mod.byHandle(e.customShader) else if (e.customSkin > 0) skinShader(e.customSkin, std.mem.sliceTo(&surface.name, 0)) else surface.shader;
                scene.addDrawSurf(shader, number, .{ .mesh = .{
                    .kind = 2,
                    .vertices = iqm.buffer.address,
                    .indices = iqm.buffer.address + iqm.index_offset + @as(u64, surface.first_triangle) * 12,
                    .count = surface.num_triangles * 3,
                    .extra = bones,
                } }, 0);
            }
        },
    }
}

/// Characters and other animated models (skeletal IQM, or MD3 with more than one frame), as
/// opposed to static props such as lamps whose own shade would hide their light.
pub fn isAnimated(handle: c.qhandle_t) bool {
    const model = byHandle(handle);
    return switch (model.kind) {
        .iqm => true,
        .md3 => |lods| if (lods[0]) |md3| md3.num_frames > 1 else false,
        .bad => false,
    };
}

pub fn list() void {
    for (models.items[1..]) |model| {
        const kind = switch (model.kind) {
            .md3 => "MD3",
            .iqm => "IQM",
            .bad => "BAD",
        };
        common.info("{s} {d} : {s}\n", .{ kind, model.num_lods, model.nameSlice() });
    }
    common.info("{d} total models\n", .{models.items.len - 1});
}
