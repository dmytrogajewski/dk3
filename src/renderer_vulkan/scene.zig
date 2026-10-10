// SPDX-License-Identifier: GPL-2.0-or-later
//! Scene lists, views and the stage backend. Follows renderergl1 tr_scene.c (scene API),
//! tr_main.c (views, sorting, entity surfaces, resident portals), tr_shade.c/tr_shade_calc.c
//! (stage colour/texture generation, here split between the CPU and stage.vert) and tr_sky.c.
const std = @import("std");
const c = @import("c.zig").c;
const cext = @import("c.zig");
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const window = @import("window.zig");
const shader_mod = @import("shader.zig");
const image = @import("image.zig");
const world = @import("world.zig");
const model = @import("model.zig");
const volume = @import("volume.zig");
const taa = @import("taa.zig");
const weather = @import("weather.zig");
const clusters = @import("clusters.zig");
const shadows = @import("shadows.zig");
const rt = @import("rt.zig");
const ddgi = @import("ddgi.zig");
const pathtrace = @import("pathtrace.zig");
const bake = @import("bake.zig");
const Shader = shader_mod.Shader;
const Stage = shader_mod.Stage;

pub const Vec3 = [3]f32;

pub fn dot(a: Vec3, b: Vec3) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
pub fn sub(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
pub fn add(a: Vec3, b: Vec3) Vec3 {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
pub fn scale(a: Vec3, s: f32) Vec3 {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
pub fn madd(a: Vec3, s: f32, b: Vec3) Vec3 {
    return .{ a[0] + s * b[0], a[1] + s * b[1], a[2] + s * b[2] };
}
pub fn length(a: Vec3) f32 {
    return @sqrt(dot(a, a));
}
pub fn normalize(a: Vec3) Vec3 {
    const l = length(a);
    return if (l > 0) scale(a, 1 / l) else a;
}
pub fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

// ---------------------------------------------------------------------------------------------
// GPU layouts (shaders/common.glsl)

pub const Vertex = extern struct {
    pos: Vec3,
    st: [2]f32,
    lm: [2]f32,
    normal: Vec3,
    color: [4]u8,
    pad: u32 = 0,
};

const Record = extern struct {
    clip: [16]f32,
    model_view: [3][4]f32,
    model: [3][4]f32,
    view_origin: [4]f32,
    const_color: [4]f32,
    ambient: [4]f32,
    directed: [4]f32,
    light_dir: [4]f32,
    tcmod: [8][4]f32,
    deform: [6][4]f32,
    tc_gen_vector: [2][4]f32,
    fog: [4]f32,
    fog_color: [4]f32,
    mode: [4]u32,
    mode2: [4]u32,
    counts: [4]u32,
    vertices: u64,
    indices: u64,
    frame_b: u64,
    extra: u64,
    misc: [4]f32,
    clip_plane: [4]f32,
    material: [4]f32,
    material2: [4]f32,
    maps: [4]u32,
    grid0: [4]f32,
    grid1: [4]f32,
    world_light: [4]f32,
    view_pos: [4]f32,
    lights: u64,
    view: u64,
};
comptime {
    if (@sizeOf(Record) != 768) @compileError("draw record layout drifted from common.glsl");
    if (@sizeOf(Vertex) != 48) @compileError("vertex layout drifted from stage.vert");
}

const flag_second_lightmap: u32 = 1;
const flag_first_lightmap: u32 = 2;
const flag_fog: u32 = 4;
const flag_volume: u32 = 512;
const flag_rt: u32 = 1024;
const flag_dynamic: u32 = 2048;
const flag_clip: u32 = 8;
const flag_linear: u32 = 16;
const flag_overlay_opaque: u32 = 32;
const flag_pbr_world: u32 = 64;
const flag_pbr_model: u32 = 128;
const flag_liquid: u32 = 256;

pub const Mesh = struct {
    kind: u32 = 0,
    vertices: u64 = 0,
    indices: u64 = 0,
    count: u32 = 0,
    frame_b: u64 = 0,
    extra: u64 = 0,
    backlerp: f32 = 0,
};

pub const Geometry = union(enum) {
    /// World or brush-model surface: indices are merged per batch into the stream ring.
    world: struct { owner: *world.World, surface: u32 },
    mesh: Mesh,
    sky,
};

pub const DrawSurf = struct {
    key: u64,
    shader: *Shader,
    entity: u32,
    geometry: Geometry,
    dlights: u32 = 0,
};

// ---------------------------------------------------------------------------------------------
// Scene state (RE_ClearScene ... RE_RenderScene)

pub const max_entities = 1023;
pub const world_entity: u32 = max_entities;
const max_dlights = 32;
const max_polys = 8192;
const max_poly_verts = 65536;

pub const Dlight = struct { origin: Vec3, radius: f32, color: Vec3, additive: bool };

pub const Entity = struct {
    e: c.refEntity_t,
    lighting_done: bool = false,
    ambient: Vec3 = .{ 0, 0, 0 },
    directed: Vec3 = .{ 0, 0, 0 },
    light_dir: Vec3 = .{ 0, 0, 0 },
    /// The same light direction in world space (remaster per-pixel model lighting).
    light_world: Vec3 = .{ 0, 0, 1 },
    /// Bone matrices for IQM skinning, uploaded once per entity per view.
    bones: u64 = 0,
};

const Poly = struct { shader: c.qhandle_t, first: u32, count: u32, world_registration: u32 };

var entities: std.ArrayList(Entity) = .empty;
var dlights: std.ArrayList(Dlight) = .empty;
var polys: std.ArrayList(Poly) = .empty;
var poly_verts: std.ArrayList(c.polyVert_t) = .empty;
var first_entity: usize = 0;
var first_dlight: usize = 0;
var first_poly: usize = 0;

var fog_set = false;
var fog_color: Vec3 = .{ 0, 0, 0 };
var fog_start: f32 = 0;
var fog_end: f32 = 1;
var fog_sky_end: f32 = 0;

/// Per-frame lists reset at BeginFrame (`R_InitNextFrame`); scenes within a frame append.
pub fn beginFrame() void {
    entities.clearRetainingCapacity();
    dlights.clearRetainingCapacity();
    polys.clearRetainingCapacity();
    poly_verts.clearRetainingCapacity();
    first_entity = 0;
    first_dlight = 0;
    first_poly = 0;
    fog_set = false;
    weather.beginFrame();
}

pub fn clearScene() void {
    first_entity = entities.items.len;
    first_dlight = dlights.items.len;
    first_poly = polys.items.len;
    fog_set = false;
    weather.clearScene();
}

pub fn setFog(color: ?*const Vec3, start: f32, end: f32, sky_end: f32) void {
    const finite = struct {
        fn f(v: f32) bool {
            return v > -1e7 and v < 1e7;
        }
    }.f;
    const value = color orelse {
        fog_set = false;
        return;
    };
    if (!finite(start) or !finite(end) or !finite(sky_end)) {
        fog_set = false;
        return;
    }
    for (0..3) |index| fog_color[index] = std.math.clamp(value[index], 0, 1);
    fog_start = start;
    fog_end = if (end != start) end else start + 1;
    fog_sky_end = sky_end;
    fog_set = true;
}

pub fn addEntity(ent: *const c.refEntity_t) void {
    if (entities.items.len - first_entity >= max_entities) {
        common.developer("RE_AddRefEntityToScene: Dropping refEntity, reached MAX_REFENTITIES\n", .{});
        return;
    }
    if (std.math.isNan(ent.origin[0]) or std.math.isNan(ent.origin[1]) or std.math.isNan(ent.origin[2])) {
        common.warn("RE_AddRefEntityToScene passed a refEntity which has an origin with a NaN component\n", .{});
        return;
    }
    if (@as(c_int, @intCast(ent.reType)) < 0 or ent.reType >= c.RT_MAX_REF_ENTITY_TYPE) common.fail(c.ERR_DROP, "RE_AddRefEntityToScene: bad reType {d}", .{ent.reType});
    var copy: Entity = .{ .e = ent.* };
    if (copy.e.dk3World == 0) copy.e.dk3World = world.registration();
    entities.append(common.gpa, copy) catch return;
}

pub fn addPoly(shader: c.qhandle_t, num_verts: c_int, verts: [*c]const c.polyVert_t, num_polys: c_int) void {
    if (shader == 0) {
        common.warn("RE_AddPolyToScene: NULL poly shader\n", .{});
        return;
    }
    if (num_verts <= 0 or num_polys <= 0) return;
    const count: u32 = @intCast(num_verts);
    for (0..@intCast(num_polys)) |index| {
        if (poly_verts.items.len + count > max_poly_verts or polys.items.len >= max_polys) {
            common.developer("WARNING: RE_AddPolyToScene: r_max_polys or r_max_polyverts reached\n", .{});
            return;
        }
        const first: u32 = @intCast(poly_verts.items.len);
        poly_verts.appendSlice(common.gpa, verts[index * count .. (index + 1) * count]) catch return;
        polys.append(common.gpa, .{ .shader = shader, .first = first, .count = count, .world_registration = world.registration() }) catch return;
    }
}

pub fn addLight(origin: *const Vec3, intensity: f32, r: f32, g: f32, b: f32, additive: bool) void {
    // The remaster bins lights into clusters; the classic path keeps the OpenGL limit.
    const limit: usize = if (window.remaster) clusters.max_lights else max_dlights;
    if (dlights.items.len - first_dlight >= limit or intensity <= 0) return;
    dlights.append(common.gpa, .{ .origin = origin.*, .radius = intensity, .color = .{ r, g, b }, .additive = additive }) catch {};
}

// ---------------------------------------------------------------------------------------------
// Views

pub const View = struct {
    origin: Vec3,
    axis: [3]Vec3,
    fov_x: f32,
    fov_y: f32,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    znear: f32,
    zfar: f32,
    projection: [4][4]f32,
    view_matrix: [4][4]f32,
    frustum: [4]struct { normal: Vec3, dist: f32 },
    time: f32,
    time_ms: i32,
    rdflags: c_int,
    areamask: [c.MAX_MAP_AREA_BYTES]u8,
    is_portal: bool = false,
    is_mirror: bool = false,
    portal_plane: ?[4]f32 = null,
    pvs_origin: Vec3,
    world: ?*world.World,
    entities: []Entity,
    dlights: []const Dlight,
    dlight_address: u64 = 0,
    /// Remaster: ViewData (froxel volume) address shared by this camera's records.
    view_data: u64 = 0,
    volumetric: bool = false,
    /// The ray tracing tier traced this camera's world (its records may use ray queries).
    ray_traced: bool = false,
    rt_table: u64 = 0,
    /// Shadow-atlas tile camera: no culling, includes third-person models.
    shadow: bool = false,
    fog: bool,
    vis_mins: Vec3 = .{ 1e30, 1e30, 1e30 },
    vis_maxs: Vec3 = .{ -1e30, -1e30, -1e30 },
    lightstyles: *const [256]f32,
    text: *const [c.MAX_RENDER_STRINGS][c.MAX_RENDER_STRING_LENGTH]u8,

    pub fn addVisBounds(self: *View, mins: Vec3, maxs: Vec3) void {
        for (0..3) |index| {
            self.vis_mins[index] = @min(self.vis_mins[index], mins[index]);
            self.vis_maxs[index] = @max(self.vis_maxs[index], maxs[index]);
        }
    }

    /// `R_CullLocalBox`-style frustum test of a world-space AABB: true when fully outside.
    pub fn cullBox(self: *const View, mins: Vec3, maxs: Vec3) bool {
        if (cvars.nocull.integer != 0 or self.shadow) return false;
        for (self.frustum) |plane| {
            var corner: Vec3 = undefined;
            for (0..3) |index| corner[index] = if (plane.normal[index] >= 0) maxs[index] else mins[index];
            if (dot(corner, plane.normal) < plane.dist) return true;
        }
        return false;
    }

    pub fn cullSphere(self: *const View, center: Vec3, radius: f32) bool {
        if (cvars.nocull.integer != 0) return false;
        for (self.frustum) |plane| {
            if (dot(center, plane.normal) - plane.dist < -radius) return true;
        }
        return false;
    }
};

/// Per-frame counters for r_vkStats.
pub const Stats = struct {
    views: u32 = 0,
    entities: u32 = 0,
    md3: u32 = 0,
    iqm: u32 = 0,
    iqm_culled: u32 = 0,
    brush: u32 = 0,
    polys: u32 = 0,
    surfaces: u32 = 0,
    draws: u32 = 0,
};
pub var stats: Stats = .{};

pub var draw_surfs: std.ArrayList(DrawSurf) = .empty;
var sequence: u32 = 0;
/// Incremented for every rendered view; per-view deduplication keys off it.
pub var view_sequence: u32 = 0;

/// `R_AddDrawSurf`.
pub fn addDrawSurf(shader_in: *Shader, entity: u32, geometry: Geometry, dlight_bits: u32) void {
    addDrawSurfSorted(shader_in, entity, geometry, dlight_bits, null);
}

/// As `addDrawSurf` with a sort override (remaster liquids draw right after opaque surfaces).
pub fn addDrawSurfSorted(shader_in: *Shader, entity: u32, geometry: Geometry, dlight_bits: u32, sort: ?f32) void {
    const shader = shader_in.remapped orelse shader_in;
    const sort_bucket: u64 = @intFromFloat(std.math.clamp((sort orelse shader.sort) * 256.0, 0, 65535));
    const key = (sort_bucket << 46) | (@as(u64, @intCast(shader.index & 0x3fff)) << 32) | (@as(u64, entity & 0x3ff) << 22) | @as(u64, sequence & 0x3fffff);
    sequence +%= 1;
    draw_surfs.append(common.gpa, .{ .key = key, .shader = shader, .entity = entity, .geometry = geometry, .dlights = dlight_bits }) catch {};
}

fn mat4Mul(a: [4][4]f32, b: [4][4]f32) [4][4]f32 {
    var out: [4][4]f32 = undefined;
    for (0..4) |row| for (0..4) |column| {
        var sum: f32 = 0;
        for (0..4) |k| sum += a[row][k] * b[k][column];
        out[row][column] = sum;
    };
    return out;
}

/// World to GL eye space (R_RotateForViewer with s_flipMatrix): x = -left, y = up, z = -forward.
fn viewMatrix(origin: Vec3, axis: [3]Vec3) [4][4]f32 {
    return .{
        .{ -axis[1][0], -axis[1][1], -axis[1][2], dot(origin, axis[1]) },
        .{ axis[2][0], axis[2][1], axis[2][2], -dot(origin, axis[2]) },
        .{ -axis[0][0], -axis[0][1], -axis[0][2], dot(origin, axis[0]) },
        .{ 0, 0, 0, 1 },
    };
}

fn setupProjection(view: *View) void {
    const zproj = cvars.zproj.value;
    const ymax = zproj * @tan(view.fov_y * std.math.pi / 360.0);
    const xmax = zproj * @tan(view.fov_x * std.math.pi / 360.0);
    const znear = cvars.znear.value;
    const zfar = view.zfar;
    view.znear = znear;
    view.projection = .{
        .{ zproj / xmax, 0, 0, 0 },
        .{ 0, zproj / ymax, 0, 0 },
        .{ 0, 0, -zfar / (zfar - znear), -zfar * znear / (zfar - znear) },
        .{ 0, 0, -1, 0 },
    };
    // R_SetupFrustum (symmetric case).
    var len = @sqrt(xmax * xmax + zproj * zproj);
    var opp = xmax / len;
    var adj = zproj / len;
    view.frustum[0].normal = madd(scale(view.axis[0], opp), adj, view.axis[1]);
    view.frustum[1].normal = madd(scale(view.axis[0], opp), -adj, view.axis[1]);
    len = @sqrt(ymax * ymax + zproj * zproj);
    opp = ymax / len;
    adj = zproj / len;
    view.frustum[2].normal = madd(scale(view.axis[0], opp), adj, view.axis[2]);
    view.frustum[3].normal = madd(scale(view.axis[0], opp), -adj, view.axis[2]);
    for (&view.frustum) |*plane| plane.dist = dot(view.origin, plane.normal);
    if (window.remaster and view.rdflags & c.RDF_NOWORLDMODEL == 0) taa.jitterProjection(&view.projection);
}

fn setFarClip(view: *View) void {
    if (view.rdflags & c.RDF_NOWORLDMODEL != 0 or view.vis_mins[0] > view.vis_maxs[0]) {
        view.zfar = 2048;
        return;
    }
    var farthest: f32 = 0;
    for (0..8) |corner| {
        const v: Vec3 = .{
            if (corner & 1 != 0) view.vis_mins[0] else view.vis_maxs[0],
            if (corner & 2 != 0) view.vis_mins[1] else view.vis_maxs[1],
            if (corner & 4 != 0) view.vis_mins[2] else view.vis_maxs[2],
        };
        const d = sub(v, view.origin);
        farthest = @max(farthest, dot(d, d));
    }
    view.zfar = @max(@sqrt(farthest), cvars.znear.value + 64);
}

/// `RE_RenderScene`.
pub fn renderScene(fd: *const c.refdef_t) void {
    if (window.beginFrame()) resetBindings();
    if (fd.rdflags & c.RDF_NOWORLDMODEL == 0 and world.current() == null) common.fail(c.ERR_DROP, "R_RenderScene: NULL worldmodel", .{});
    world.updateLightstyles(fd);
    if (fd.rdflags & c.RDF_NOWORLDMODEL == 0) if (world.current()) |w| rt.updateStyles(w, fd);
    const scene_entities = entities.items[first_entity..];
    const scene_dlights = if (cvars.dynamiclight.integer != 0) dlights.items[first_dlight..] else dlights.items[0..0];
    var view: View = .{
        .origin = fd.vieworg,
        .axis = fd.viewaxis,
        .fov_x = fd.fov_x,
        .fov_y = fd.fov_y,
        .x = fd.x,
        .y = fd.y,
        .width = fd.width,
        .height = fd.height,
        .znear = cvars.znear.value,
        .zfar = 2048,
        .projection = undefined,
        .view_matrix = undefined,
        .frustum = undefined,
        .time = @as(f32, @floatFromInt(fd.time)) * 0.001,
        .time_ms = fd.time,
        .rdflags = fd.rdflags,
        .areamask = fd.areamask,
        .pvs_origin = fd.vieworg,
        .world = if (fd.rdflags & c.RDF_NOWORLDMODEL != 0) null else world.current(),
        .entities = scene_entities,
        .dlights = scene_dlights,
        .fog = fog_set and cvars.dk3Fog.integer != 0 and fd.rdflags & c.RDF_NOWORLDMODEL == 0,
        .lightstyles = &fd.dk3Lightstyles,
        .text = &fd.text,
    };
    renderView(&view);
    if (view.world) |owner| {
        window.view_near = view.znear;
        window.view_far = view.zfar;
        window.underwater = @intFromEnum(world.liquidOf(world.contentsAt(owner, view.origin)));
    }
}

fn uploadDlights(view: *View) void {
    if (view.dlights.len == 0) return;
    // Without the upload every consumer (froxels, clusters, probes, records) would loop over
    // the lights at address 0: on the GPU a device fault. Drop the frame's lights instead.
    const space = vk.frame().stream.alloc(view.dlights.len * 32, 16) orelse {
        common.developer("renderer_vulkan: no stream space for {d} dynamic lights; dropped this frame\n", .{view.dlights.len});
        view.dlights = view.dlights[0..0];
        return;
    };
    const out = std.mem.bytesAsSlice([4]f32, space.bytes);
    for (view.dlights, 0..) |light, index| {
        out[index * 2] = .{ light.origin[0], light.origin[1], light.origin[2], light.radius };
        out[index * 2 + 1] = .{ light.color[0], light.color[1], light.color[2], if (light.additive) 1 else 0 };
    }
    view.dlight_address = space.address;
}

/// `R_RenderView`: gather, sort, render resident portals first, then draw.
pub fn renderView(view: *View) void {
    view_sequence +%= 1;
    stats.views += 1;
    stats.entities += @intCast(view.entities.len);
    view.view_matrix = viewMatrix(view.origin, view.axis);
    view.zfar = 2048;
    setupProjection(view); // frustum for culling; z range is finished after the world pass
    uploadDlights(view);
    const first = draw_surfs.items.len;
    if (view.world) |owner| {
        if (cvars.drawworld.integer != 0) world.addWorldSurfaces(view, owner);
    }
    addPolygonSurfaces(view);
    addWeatherSurfaces(view);
    if (cvars.drawentities.integer != 0) addEntitySurfaces(view);
    setFarClip(view);
    setupProjection(view);
    const count = draw_surfs.items.len - first;
    std.mem.sort(DrawSurf, draw_surfs.items[first..], {}, struct {
        fn less(_: void, a: DrawSurf, b: DrawSurf) bool {
            return a.key < b.key;
        }
    }.less);
    // The shadow and rain-map passes append and release their own surfaces, which can move
    // the list: slice it again afterwards.
    if (!view.is_portal) buildViewData(view);
    const surfaces = draw_surfs.items[first .. first + count];
    // Portal views render before this view clears its depth (R_SortDrawSurfs).
    if (!view.is_portal) {
        for (surfaces) |surface| {
            if (surface.shader.sort > shader_mod.Sort.portal) break;
            if (renderPortal(view, surface)) break;
        }
    }
    stats.surfaces += @intCast(draw_surfs.items.len - first);
    drawView(view, draw_surfs.items[first..]);
    draw_surfs.shrinkRetainingCapacity(first);
}

const max_character_meshes = 256;

/// Characters (animated models) near the eye for the ray tracing scene (rt.prepareCharacters):
/// static props stay out, since a lamp's own shade would block the light inside it. Their meshes
/// as drawn this frame (all LOD 0 surfaces, including the player's own body for its shadow) and
/// their transforms. Solid stages only; the view weapon stays out.
fn characterMeshes(view: *View, out: *[max_character_meshes]rt.CharacterMesh) usize {
    var count: usize = 0;
    const registration = world.registration();
    var surface_view = view.*;
    surface_view.shadow = true;
    for (view.entities, 0..) |*entity, index| {
        const e = &entity.e;
        if (e.reType != c.RT_MODEL or e.dk3World != registration) continue;
        if (e.renderfx & (c.RF_DEPTHHACK | c.RF_FIRST_PERSON) != 0) continue;
        if (world.residentInline(e.hModel) != null or !model.isAnimated(e.hModel)) continue;
        if (length(sub(e.origin, view.origin)) > 3000) continue;
        const first = draw_surfs.items.len;
        model.addEntitySurfaces(&surface_view, entity, @intCast(index));
        const placement = orientation(view, entity);
        for (draw_surfs.items[first..]) |surface| {
            const mesh = switch (surface.geometry) {
                .mesh => |m| m,
                else => continue,
            };
            if (mesh.kind != 1 and mesh.kind != 2) continue;
            if (surface.shader.sort > shader_mod.Sort.see_through) continue;
            if (count == out.len) break;
            out[count] = .{ .mesh = mesh, .model = placement.model };
            count += 1;
        }
        draw_surfs.shrinkRetainingCapacity(first);
        if (count == out.len) break;
    }
    return count;
}

/// Renders the shadow-atlas tiles of the nearest model casters; returns the caster list.
fn renderShadows(view: *View, owner: *world.World) ?struct { address: u64, count: u32 } {
    if (cvars.vkModelShadows.integer == 0 or cvars.shadows.integer == 0 or cvars.drawentities.integer == 0) return null;
    const Candidate = struct { index: u32, distance: f32, centre: Vec3, radius: f32 };
    var candidates: [64]Candidate = undefined;
    var count: usize = 0;
    const registration = world.registration();
    for (view.entities, 0..) |*entity, index| {
        const e = &entity.e;
        if (e.reType != c.RT_MODEL or e.dk3World != registration) continue;
        if (e.renderfx & (c.RF_NOSHADOW | c.RF_DEPTHHACK | c.RF_FIRST_PERSON) != 0) continue;
        const box = model.entityBox(e) orelse continue;
        const centre = scale(add(box[0], box[1]), 0.5);
        const radius = length(sub(box[1], box[0])) * 0.5;
        if (radius < 4 or radius > 160) continue;
        const distance = length(sub(centre, view.origin));
        if (distance > shadows.max_distance) continue;
        // The shadow lands below and beside the caster: test a box grown by its reach.
        const grow: Vec3 = .{ radius * 3, radius * 3, radius * 3 };
        if (view.cullBox(sub(box[0], grow), add(box[1], .{ radius, radius, radius }))) continue;
        const candidate: Candidate = .{ .index = @intCast(index), .distance = distance, .centre = centre, .radius = radius };
        if (count < candidates.len) {
            candidates[count] = candidate;
            count += 1;
        }
    }
    if (count == 0) return null;
    std.mem.sort(Candidate, candidates[0..count], {}, struct {
        fn less(_: void, a: Candidate, b: Candidate) bool {
            return a.distance < b.distance;
        }
    }.less);
    const used: u32 = @intCast(@min(count, shadows.max_casters));
    const space = vk.frame().stream.alloc(@as(u64, used) * @sizeOf(shadows.Caster), 16) orelse return null;
    const out = std.mem.bytesAsSlice(shadows.Caster, space.bytes);
    for (candidates[0..used], 0..) |candidate, slot| {
        const to_light: Vec3 = if (world.lightGridSample(owner, candidate.centre)) |sample| sample.direction else .{ 0.3, 0.2, 1 };
        const cam = shadows.camera(@intCast(slot), candidate.centre, candidate.radius, to_light);
        out[slot] = cam.caster;
        var tile_view = view.*;
        tile_view.shadow = true;
        tile_view.is_portal = false;
        tile_view.portal_plane = null;
        tile_view.projection = cam.projection;
        tile_view.view_matrix = cam.view_matrix;
        tile_view.x = cam.x;
        tile_view.y = cam.y;
        tile_view.width = shadows.tile_size;
        tile_view.height = shadows.tile_size;
        tile_view.view_data = 0;
        tile_view.volumetric = false;
        tile_view.dlights = &.{};
        tile_view.fog = false;
        const first = draw_surfs.items.len;
        model.addEntitySurfaces(&tile_view, &view.entities[candidate.index], candidate.index);
        window.useTarget(.shadow);
        setScissor(cam.x, cam.y, shadows.tile_size, shadows.tile_size);
        for (draw_surfs.items[first..]) |surface| {
            const mesh = switch (surface.geometry) {
                .mesh => |m| m,
                else => continue,
            };
            if (surface.shader.sort > shader_mod.Sort.see_through) continue;
            drawBatch(&tile_view, surface.shader, &view.entities[surface.entity], mesh, false, false);
        }
        draw_surfs.shrinkRetainingCapacity(first);
    }
    window.finishShadows();
    return .{ .address = space.address, .count = used };
}

/// Renders the rain occlusion map (shadows.rainCamera) for the weather volumes `boxes`: the
/// world's surfaces seen straight down over the eye, into the lower half of the shadow atlas.
fn renderRainMap(view: *View, owner: *world.World, boxes: []const [4]f32, count: u32) ?shadows.RainMap {
    if (count == 0 or cvars.drawworld.integer == 0) return null;
    var z_top: f32 = -1e30;
    var z_bottom: f32 = 1e30;
    for (0..count) |k| {
        z_bottom = @min(z_bottom, boxes[k * 2][2]);
        z_top = @max(z_top, boxes[k * 2 + 1][2]);
    }
    const cam = shadows.rainCamera(view.origin, z_top + 16, z_bottom - 64);
    var map_view = view.*;
    map_view.shadow = true;
    map_view.is_portal = false;
    map_view.portal_plane = null;
    map_view.projection = cam.projection;
    map_view.view_matrix = cam.view_matrix;
    map_view.x = cam.x;
    map_view.y = cam.y;
    map_view.width = shadows.rain_map_size;
    map_view.height = shadows.rain_map_size;
    map_view.view_data = 0;
    map_view.volumetric = false;
    map_view.dlights = &.{};
    map_view.fog = false;
    // Facing culling must agree with the downward camera; the PVS stays the eye's.
    map_view.origin = .{ cam.centre[0], cam.centre[1], z_top + 16 };
    const half = shadows.rain_half_extent;
    map_view.frustum = .{
        .{ .normal = .{ 1, 0, 0 }, .dist = cam.centre[0] - half },
        .{ .normal = .{ -1, 0, 0 }, .dist = -(cam.centre[0] + half) },
        .{ .normal = .{ 0, 1, 0 }, .dist = cam.centre[1] - half },
        .{ .normal = .{ 0, -1, 0 }, .dist = -(cam.centre[1] + half) },
    };
    const first = draw_surfs.items.len;
    world.addWorldSurfaces(&map_view, owner);
    const surfaces = draw_surfs.items[first..];
    std.mem.sort(DrawSurf, surfaces, {}, struct {
        fn less(_: void, a: DrawSurf, b: DrawSurf) bool {
            return a.key < b.key;
        }
    }.less);
    window.useTarget(.shadow);
    setScissor(cam.x, cam.y, shadows.rain_map_size, shadows.rain_map_size);
    var index: usize = 0;
    while (index < surfaces.len) {
        const surface = surfaces[index];
        const w = switch (surface.geometry) {
            .world => |w| w,
            else => {
                index += 1;
                continue;
            },
        };
        var end = index + 1;
        while (end < surfaces.len) : (end += 1) {
            const next = surfaces[end];
            if (next.shader != surface.shader) break;
            switch (next.geometry) {
                .world => |nw| if (nw.owner != w.owner) break,
                else => break,
            }
        }
        if (surface.shader.sort <= shader_mod.Sort.see_through or w.owner.surfaces[w.surface].liquid != .none) {
            if (world.mergeIndices(w.owner, surfaces[index..end])) |mesh| drawBatch(&map_view, surface.shader, null, mesh, false, false);
        }
        index = end;
    }
    draw_surfs.shrinkRetainingCapacity(first);
    window.finishShadows();
    return cam;
}

/// Distance the sky column samples the froxel volume at. The original fogged its 4096-unit sky
/// box linearly from fog_start to fog_skyend (RB_Dk3FogSky); the volume reaches the same
/// coverage at this depth, so a `fog_skyend` far beyond the box keeps the sky clear.
fn skyFogDepth(view: *const View) f32 {
    if (!view.fog) return 3000;
    const range = fog_sky_end - fog_start;
    var coverage: f32 = 1;
    if (range > 0) coverage = std.math.clamp((4096 - fog_start) / range, 0, 1);
    if (coverage >= 0.999) return 1e9;
    const span = @max(fog_end - fog_start, 1);
    return fog_start - @log(1 - coverage) * span / 1.2;
}

/// Remaster world cameras: per-view shader data (froxel volumetric fog, weather volumes) for
/// this view and its identity portals.
fn buildViewData(view: *View) void {
    view.view_data = 0;
    view.volumetric = false;
    view.ray_traced = false;
    if (!window.remaster or view.rdflags & c.RDF_NOWORLDMODEL != 0) return;
    const owner = view.world orelse return;
    taa.registerView(view.projection, view.view_matrix, view.origin, view.axis[0]);
    window.suspendRendering();
    const fog_input: @FieldType(volume.Input, "fog") = if (view.fog) .{ .color = fog_color, .start = fog_start, .end = fog_end } else null;
    const grid_input: @FieldType(volume.Input, "grid") = if (world.gridParams(owner)) |g| .{ .origin = g.origin, .scale = g.scale, .slot = g.slot, .color_slot = g.color_slot } else null;
    // Weather volumes and the rain occlusion map first: the froxel pass turns distant rain
    // into fog where it is open to the sky.
    var boxes: [weather.max_view_boxes * 2][4]f32 = std.mem.zeroes([weather.max_view_boxes * 2][4]f32);
    const box_count = weather.viewBoxes(world.registration(), &boxes);
    const rain_map = renderRainMap(view, owner, &boxes, box_count);
    const rain_input: @FieldType(volume.Input, "rain") = if (rain_map) |map| .{
        .boxes = boxes,
        .count = box_count,
        .to_tile = map.world_to_tile,
        .tile = map.tile,
        .params = map.params,
        .slot = window.shadow_slot,
        .intensity = if (cvars.vkWeather.integer != 0) @max(cvars.vkWeatherDensity.value, 0) else 0,
    } else null;
    // The ray tracing tier first: the froxel pass traces light visibility against it.
    var character_meshes: [max_character_meshes]rt.CharacterMesh = undefined;
    const character_count = if (rt.enabled() and cvars.vkRtCharacters.integer != 0) characterMeshes(view, &character_meshes) else 0;
    const rt_table_opt = rt.prepare(window.cmd, owner, view.entities, character_meshes[0..character_count]);
    const map_light_data = if (rt_table_opt != null and cvars.vkLighting.integer != 0) rt.mapLightData(owner) else null;
    const light_scale: [3]f32 = .{ @max(cvars.vkPtLightScale.value, 0), std.math.pow(f32, 2, @floatFromInt(std.math.clamp(cvars.mapOverBrightBits.integer, 0, 8))), if (map_light_data) |m| m.ambient else 0 };
    // Ray traced lighting takes the sky's light from the original emitting sky faces (none
    // when the map's sky emitted nothing); without that data, from the sky box.
    const rt_sky: [3]f32 = rt.skyFor(owner);
    const rt_input: @FieldType(volume.Input, "rt") = if (rt_table_opt) |hit_table| .{
        .table = hit_table,
        .lights = if (map_light_data) |m| m.lights else 0,
        .cells = if (map_light_data) |m| m.cells else 0,
        .cell_origin = if (map_light_data) |m| m.origin else .{ 0, 0, 0 },
        .cell_dims = if (map_light_data) |m| m.dims else .{ 0, 0, 0 },
        .light_scale = light_scale,
        .sky = rt_sky,
    } else null;
    const built = volume.run(window.cmd, .{
        .origin = view.origin,
        .axis = view.axis,
        .fov_x = view.fov_x,
        .fov_y = view.fov_y,
        .far = view.zfar,
        .time = view.time,
        .dlights = view.dlight_address,
        .dlight_count = @intCast(view.dlights.len),
        .fog = fog_input,
        .grid = grid_input,
        .rain = rain_input,
        .rt = rt_input,
    });
    var data = built orelse volume.emptyViewData();
    view.volumetric = built != null;
    data.boxes = boxes;
    data.weather[0] = box_count;
    data.weather_params = .{ @max(cvars.vkWetness.value, 0), @max(cvars.vkSnowCover.value, 0), view.time, @floatFromInt(cvars.vkDebugView.integer) };
    // y: liquid the eye is in (world.liquidOf), for liquid surfaces seen from underneath.
    data.fog_params = .{ skyFogDepth(view), @floatFromInt(@intFromEnum(world.liquidOf(world.contentsAt(owner, view.origin)))), @floatFromInt(taa.frameCounter() % 4096), 0 };
    data.shadows[1] = window.shadow_slot;
    if (rain_map) |map| {
        data.rain_to_tile = map.world_to_tile;
        data.rain = map.tile;
        data.rain_params = map.params;
    }
    if (rt_table_opt) |rt_table| {
        const shadows_on: u32 = if (cvars.vkRtShadows.integer != 0) 1 else 0;
        const reflections_on: u32 = if (cvars.vkRtReflections.integer != 0) 2 else 0;
        // y: characters are in the ray tracing scene (their shadows are traced, not mapped).
        data.rt = .{ shadows_on | reflections_on, @intFromBool(character_count > 0), 0, 0 };
        data.rt_table = .{ @truncate(rt_table), @truncate(rt_table >> 32), 0, 0 };
        view.ray_traced = true;
        view.rt_table = rt_table;
        if (map_light_data) |lights| {
            data.rt_lights = .{ @truncate(lights.lights), @truncate(lights.lights >> 32), @truncate(lights.cells), @truncate(lights.cells >> 32) };
            data.rt_cells = .{ lights.origin[0], lights.origin[1], lights.origin[2], rt.light_cell_size };
            data.rt_cell_dims = .{ lights.dims[0], lights.dims[1], lights.dims[2], 1 };
            data.rt_light_scale = .{ light_scale[0], light_scale[1], light_scale[2], 0 };
            // Radiosity units (w 2) when the original sky is known, summed with the direct light.
            data.rt_sky = if (rt.skyRaw(owner)) |raw| .{ raw[0], raw[1], raw[2], 2 } else .{ rt_sky[0], rt_sky[1], rt_sky[2], 1 };
        }
        // The directional lightmap bake only serves the baked lighting.
        if (data.rt_cell_dims[3] == 0) bake.step(window.cmd, owner);
        resetBindings();
        // Rays that leave the world see the sky box, not the fog colour.
        const sky: Vec3 = rt.skyFor(owner);
        var map_lights: ?ddgi.MapLights = null;
        if (data.rt_cell_dims[3] != 0) map_lights = .{
            .lights = @as(u64, data.rt_lights[0]) | (@as(u64, data.rt_lights[1]) << 32),
            .cells = @as(u64, data.rt_lights[2]) | (@as(u64, data.rt_lights[3]) << 32),
            .origin = .{ data.rt_cells[0], data.rt_cells[1], data.rt_cells[2] },
            .dims = .{ data.rt_cell_dims[0], data.rt_cell_dims[1], data.rt_cell_dims[2] },
            .scale = data.rt_light_scale[0],
            .overbright = data.rt_light_scale[1],
            .ambient = data.rt_light_scale[2],
        };
        if (ddgi.update(window.cmd, rt_table, view.origin, view.dlight_address, @intCast(view.dlights.len), sky, map_lights)) |field| {
            data.ddgi_slots = field.slots;
            data.ddgi_slots2 = field.slots2;
            data.ddgi_origin = field.origin;
            data.ddgi_dims = field.dims;
        }
    }
    if (renderShadows(view, owner)) |casters| {
        data.shadows[0] = casters.count;
        data.shadow_list = .{ @truncate(casters.address), @truncate(casters.address >> 32), 0, 0 };
    }
    if (clusters.run(window.cmd, view.origin, view.axis, view.fov_x, view.fov_y, view.zfar, view.dlight_address, @intCast(view.dlights.len))) |binned| {
        data.clusters = .{ 1, clusters.grid[0], clusters.grid[1], clusters.grid[2] };
        data.cluster_params = .{ binned.near, binned.inverse_log, clusters.max_per_cluster, 0 };
        data.cluster_list = .{ @truncate(binned.address), @truncate(binned.address >> 32), 0, 0 };
    }
    const s = window.render_scale;
    data.rect = .{ @as(f32, @floatFromInt(view.x)) * s, @as(f32, @floatFromInt(view.y)) * s, @as(f32, @floatFromInt(@max(view.width, 1))) * s, @as(f32, @floatFromInt(@max(view.height, 1))) * s };
    const space = vk.frame().stream.alloc(@sizeOf(volume.ViewData), 16) orelse return;
    @memcpy(space.bytes[0..@sizeOf(volume.ViewData)], std.mem.asBytes(&data));
    view.view_data = space.address;
}

fn polyCenter(poly: Poly) Vec3 {
    var center: Vec3 = .{ 0, 0, 0 };
    for (poly_verts.items[poly.first .. poly.first + poly.count]) |vert| center = add(center, vert.xyz);
    return scale(center, 1.0 / @as(f32, @floatFromInt(poly.count)));
}

/// The RT_PORTALSURFACE entity whose origin is this aperture quad's center (R_ResidentPortal).
fn residentPortal(view: *const View, poly: Poly) ?*const c.refEntity_t {
    if (poly.count != 4) return null;
    const center = polyCenter(poly);
    for (view.entities) |*entity| {
        if (entity.e.reType != c.RT_PORTALSURFACE or entity.e.dk3PortalWorld == 0) continue;
        const d = sub(center, entity.e.origin);
        if (dot(d, d) < 0.0001) return &entity.e;
    }
    return null;
}

/// Resident seams only: identity cameras into another resident world. Engine mirrors are not
/// used by dk3 content.
fn renderPortal(view: *View, surface: DrawSurf) bool {
    const mesh = switch (surface.geometry) {
        .mesh => |m| m,
        else => return false,
    };
    if (mesh.extra == 0) return false;
    const poly = polys.items[@intCast(mesh.extra - 1)];
    const portal = residentPortal(view, poly) orelse return false;
    // PlaneFromPoints(v0, v1, v2); back-facing apertures are offscreen (SurfIsOffscreen).
    const v = poly_verts.items[poly.first .. poly.first + 3];
    const normal = normalize(cross(sub(v[2].xyz, v[0].xyz), sub(v[1].xyz, v[0].xyz)));
    if (dot(sub(v[0].xyz, view.origin), normal) >= 0) return false;
    const previous = world.registration();
    if (!world.select(portal.dk3PortalWorld)) common.fail(c.ERR_DROP, "Lost resident portal destination", .{});
    var portal_view = view.*;
    portal_view.is_portal = true;
    portal_view.pvs_origin = portal.oldorigin;
    portal_view.areamask = std.mem.zeroes([c.MAX_MAP_AREA_BYTES]u8);
    portal_view.world = world.current();
    const plane_normal = scale(normal, -1);
    portal_view.portal_plane = .{ plane_normal[0], plane_normal[1], plane_normal[2], dot(portal.origin, plane_normal) };
    portal_view.vis_mins = .{ 1e30, 1e30, 1e30 };
    portal_view.vis_maxs = .{ -1e30, -1e30, -1e30 };
    renderView(&portal_view);
    if (!world.select(previous)) common.fail(c.ERR_DROP, "Lost resident portal source", .{});
    return true;
}

/// Remaster GPU weather particles for the authored volumes of this world.
fn addWeatherSurfaces(view: *View) void {
    if (!window.remaster or view.is_portal or view.rdflags & c.RDF_NOWORLDMODEL != 0) return;
    const registration = world.registration();
    const pixels: f32 = @as(f32, @floatFromInt(@max(view.width, 1))) * window.render_scale;
    const sky: Vec3 = if (view.world) |owner| world.skyRadiance(owner) else .{ 0.05, 0.05, 0.06 };
    var lighting: weather.Lighting = .{
        .eye = view.origin,
        .time = view.time,
        .pixel_per_unit = 2 * @tan(view.fov_x * std.math.pi / 360.0) / pixels,
        .grid = null,
        .sky = sky,
    };
    if (view.world) |owner| if (world.gridParams(owner)) |g| {
        lighting.grid = .{ .origin = g.origin, .scale = g.scale, .color_slot = g.color_slot, .slot = g.slot };
    };
    for (weather.sceneVolumes()) |volume_entry| {
        if (volume_entry.registration != registration) continue;
        var parts: [2]?weather.Draw = undefined;
        weather.draws(volume_entry, lighting, &parts);
        for (parts) |maybe| {
            const part = maybe orelse continue;
            addDrawSurf(part.shader, world_entity, .{ .mesh = .{ .kind = 3, .vertices = part.params, .count = part.count } }, 0);
        }
    }
}

fn addPolygonSurfaces(view: *View) void {
    const scene_polys = polys.items[first_poly..];
    const registration = world.registration();
    for (scene_polys, first_poly..) |poly, index| {
        if (view.rdflags & c.RDF_NOWORLDMODEL == 0 and poly.world_registration != registration) continue;
        if (view.is_portal and residentPortal(view, poly) != null) continue;
        stats.polys += 1;
        const shader = shader_mod.byHandle(poly.shader);
        var geometry = streamPoly(poly) orelse continue;
        geometry.extra = index + 1; // poly identity for resident portal matching
        addDrawSurf(shader, world_entity, .{ .mesh = geometry }, 0);
    }
}

fn streamPoly(poly: Poly) ?Mesh {
    const frame = vk.frame();
    const vertices = frame.stream.alloc(@as(u64, poly.count) * @sizeOf(Vertex), 16) orelse return null;
    const index_count = (poly.count - 2) * 3;
    const indices = frame.stream.alloc(@as(u64, index_count) * 4, 4) orelse return null;
    const out = std.mem.bytesAsSlice(Vertex, vertices.bytes);
    for (poly_verts.items[poly.first .. poly.first + poly.count], 0..) |vert, index| {
        out[index] = .{ .pos = vert.xyz, .st = vert.st, .lm = .{ 0, 0 }, .normal = .{ 0, 0, 0 }, .color = vert.modulate };
    }
    const list = std.mem.bytesAsSlice(u32, indices.bytes);
    var i: u32 = 0;
    while (i < poly.count - 2) : (i += 1) {
        list[i * 3] = 0;
        list[i * 3 + 1] = i + 1;
        list[i * 3 + 2] = i + 2;
    }
    return .{ .kind = 0, .vertices = vertices.address, .indices = indices.address, .count = index_count };
}

/// Quad helper (RB_AddQuadStampExt): returns a stream mesh.
pub fn quad(origin: Vec3, left: Vec3, up: Vec3, normal: Vec3, color: [4]u8, s1: f32, t1: f32, s2: f32, t2: f32) ?Mesh {
    const frame = vk.frame();
    const vertices = frame.stream.alloc(4 * @sizeOf(Vertex), 16) orelse return null;
    const indices = frame.stream.alloc(6 * 4, 4) orelse return null;
    const out = std.mem.bytesAsSlice(Vertex, vertices.bytes);
    out[0] = .{ .pos = add(add(origin, left), up), .st = .{ s1, t1 }, .lm = .{ s1, t1 }, .normal = normal, .color = color };
    out[1] = .{ .pos = add(sub(origin, left), up), .st = .{ s2, t1 }, .lm = .{ s2, t1 }, .normal = normal, .color = color };
    out[2] = .{ .pos = sub(sub(origin, left), up), .st = .{ s2, t2 }, .lm = .{ s2, t2 }, .normal = normal, .color = color };
    out[3] = .{ .pos = sub(add(origin, left), up), .st = .{ s1, t2 }, .lm = .{ s1, t2 }, .normal = normal, .color = color };
    const list = std.mem.bytesAsSlice(u32, indices.bytes);
    list[0..6].* = .{ 0, 1, 3, 3, 1, 2 };
    return .{ .kind = 0, .vertices = vertices.address, .indices = indices.address, .count = 6 };
}

fn addEntitySurfaces(view: *View) void {
    const registration = world.registration();
    for (view.entities, 0..) |*entity, index| {
        const e = &entity.e;
        if (view.rdflags & c.RDF_NOWORLDMODEL == 0 and e.dk3World != registration) continue;
        // The hacked first-person weapon does not appear in portal views.
        if (e.renderfx & c.RF_FIRST_PERSON != 0 and view.is_portal) continue;
        const number: u32 = @intCast(index);
        switch (e.reType) {
            c.RT_PORTALSURFACE => {},
            c.RT_SPRITE, c.RT_BEAM, c.RT_LIGHTNING, c.RT_RAIL_CORE, c.RT_RAIL_RINGS => {
                if (e.renderfx & c.RF_THIRD_PERSON != 0 and !view.is_portal) continue;
                const shader = shader_mod.byHandle(e.customShader);
                if (e.reType == c.RT_SPRITE) {
                    if (spriteMesh(view, e)) |mesh| addDrawSurf(shader, number, .{ .mesh = mesh }, 0);
                } else {
                    // Beams, rail cores/rings and lightning (tr_surface.c DoRailCore): quads along
                    // origin -> oldorigin facing the eye; lightning and beams add a crossed quad.
                    const beam_shader = if (e.customShader != 0) shader else shader_mod.byHandle(0);
                    const width: f32 = switch (e.reType) {
                        c.RT_LIGHTNING => 8,
                        c.RT_BEAM => 4,
                        else => 6,
                    };
                    for (0..(if (e.reType == c.RT_LIGHTNING or e.reType == c.RT_BEAM) @as(usize, 2) else 1)) |pass| {
                        if (beamMesh(view, e, width, pass == 1)) |mesh| addDrawSurf(beam_shader, number, .{ .mesh = mesh }, 0);
                    }
                }
            },
            c.RT_MODEL => model.addEntitySurfaces(view, entity, number),
            else => common.fail(c.ERR_DROP, "R_AddEntitySurfaces: Bad reType", .{}),
        }
    }
}

/// One quad from `origin` to `oldorigin`, `width` wide, facing the eye (or perpendicular to that
/// when `crossed`).
fn beamMesh(view: *const View, e: *const c.refEntity_t, width: f32, crossed: bool) ?Mesh {
    const start: Vec3 = e.origin;
    const end: Vec3 = e.oldorigin;
    const span = sub(end, start);
    const len = length(span);
    if (len < 0.001) return null;
    const along = scale(span, 1 / len);
    const centre = madd(start, 0.5, span);
    var side = normalize(cross(along, sub(view.origin, centre)));
    if (crossed) side = normalize(cross(along, side));
    if (length(side) < 0.5) return null;
    return quad(centre, scale(along, len * 0.5), scale(side, width * 0.5), cross(along, side), e.shaderRGBA, 0, 0, len / 64.0, 1);
}

/// `RB_SurfaceSprite`.
fn spriteMesh(view: *const View, e: *const c.refEntity_t) ?Mesh {
    var left: Vec3 = undefined;
    var up: Vec3 = undefined;
    if (e.rotation == 0) {
        left = scale(view.axis[1], e.radius);
        up = scale(view.axis[2], e.radius);
    } else {
        const angle = e.rotation * std.math.pi / 180.0;
        const s = @sin(angle);
        const co = @cos(angle);
        left = madd(scale(view.axis[1], co * e.radius), -s * e.radius, view.axis[2]);
        up = madd(scale(view.axis[2], co * e.radius), s * e.radius, view.axis[1]);
    }
    if (view.is_mirror) left = scale(left, -1);
    return quad(e.origin, left, up, scale(view.axis[0], -1), e.shaderRGBA, 0, 0, 1, 1);
}

// ---------------------------------------------------------------------------------------------
// Entity orientation and lighting

pub const Orientation = struct {
    model: [3][4]f32,
    view_origin: Vec3,
    mirror: bool = false,
};

/// `R_RotateForEntity`; non-model entities use the world orientation.
pub fn orientation(view: *const View, entity: ?*const Entity) Orientation {
    const e = if (entity) |ent| &ent.e else null;
    if (e == null or e.?.reType != c.RT_MODEL) {
        return .{ .model = .{ .{ 1, 0, 0, 0 }, .{ 0, 1, 0, 0 }, .{ 0, 0, 1, 0 } }, .view_origin = view.origin };
    }
    const ent = e.?;
    const axis = ent.axis;
    const origin: Vec3 = ent.origin;
    const delta = sub(view.origin, origin);
    var axis_length: f32 = 1;
    if (ent.nonNormalizedAxes != 0) {
        const l = length(axis[0]);
        axis_length = if (l != 0) 1 / l else 0;
    }
    return .{
        .model = .{
            .{ axis[0][0], axis[1][0], axis[2][0], origin[0] },
            .{ axis[0][1], axis[1][1], axis[2][1], origin[1] },
            .{ axis[0][2], axis[1][2], axis[2][2], origin[2] },
        },
        .view_origin = .{ dot(delta, axis[0]) * axis_length, dot(delta, axis[1]) * axis_length, dot(delta, axis[2]) * axis_length },
    };
}

/// `R_SetupEntityLighting` (renderergl1/tr_light.c), values 0..255 as in the GL renderer.
pub fn setupEntityLighting(view: *const View, entity: *Entity) void {
    if (entity.lighting_done) return;
    entity.lighting_done = true;
    const e = &entity.e;
    const light_origin: Vec3 = if (e.renderfx & c.RF_LIGHTING_ORIGIN != 0) e.lightingOrigin else e.origin;
    var ambient: Vec3 = .{ 150, 150, 150 };
    var directed: Vec3 = .{ 150, 150, 150 };
    var direction: Vec3 = world.sunDirection();
    if (view.rdflags & c.RDF_NOWORLDMODEL == 0) {
        if (view.world) |owner| if (world.lightGridSample(owner, light_origin)) |sample| {
            ambient = sample.ambient;
            directed = sample.directed;
            direction = sample.direction;
        };
    }
    for (&ambient) |*value| value.* += 32;
    if (e.renderfx & c.RF_MINLIGHT != 0) for (&ambient) |*value| {
        value.* = @max(value.*, 76.5);
    };
    var light_dir = scale(direction, length(directed));
    // The remaster pipeline lights models per pixel from the dynamic lights themselves.
    for (if (window.remaster) view.dlights[0..0] else view.dlights) |light| {
        var dir = sub(light.origin, light_origin);
        var d = length(dir);
        if (d > 0) dir = scale(dir, 1 / d);
        const power = 16.0 * (light.radius * light.radius);
        if (d < 16) d = 16;
        const amount = power / (d * d);
        directed = madd(directed, amount, light.color);
        light_dir = madd(light_dir, amount, dir);
    }
    for (&ambient) |*value| value.* = @min(value.*, 255);
    light_dir = normalize(light_dir);
    entity.light_world = light_dir;
    entity.ambient = ambient;
    entity.directed = directed;
    entity.light_dir = .{ dot(light_dir, e.axis[0]), dot(light_dir, e.axis[1]), dot(light_dir, e.axis[2]) };
}

// ---------------------------------------------------------------------------------------------
// Waveforms (tr_init.c function tables)

const table_size = 1024;
var sin_table: [table_size]f32 = undefined;
var square_table: [table_size]f32 = undefined;
var triangle_table: [table_size]f32 = undefined;
var sawtooth_table: [table_size]f32 = undefined;
var inverse_sawtooth_table: [table_size]f32 = undefined;

pub fn initTables() void {
    for (0..table_size) |index| {
        const i: f32 = @floatFromInt(index);
        sin_table[index] = @sin(i * 360.0 / @as(f32, table_size - 1) * std.math.pi / 180.0);
        square_table[index] = if (index < table_size / 2) 1 else -1;
        sawtooth_table[index] = i / table_size;
        inverse_sawtooth_table[index] = 1 - sawtooth_table[index];
        if (index < table_size / 2) {
            triangle_table[index] = if (index < table_size / 4) i / (table_size / 4) else 1 - triangle_table[index - table_size / 4];
        } else triangle_table[index] = -triangle_table[index - table_size / 2];
    }
}

fn table(func: shader_mod.Func) *const [table_size]f32 {
    return switch (func) {
        .square => &square_table,
        .triangle => &triangle_table,
        .sawtooth => &sawtooth_table,
        .inverse_sawtooth => &inverse_sawtooth_table,
        else => &sin_table,
    };
}

fn lookup(func: shader_mod.Func, x: f32) f32 {
    const index: i64 = @intFromFloat(std.math.clamp(x * table_size, -1e15, 1e15));
    return table(func)[@intCast(index & (table_size - 1))];
}

fn evalWave(wave: shader_mod.Wave, time: f32) f32 {
    return wave.base + lookup(wave.func, wave.phase + time * wave.frequency) * wave.amplitude;
}

fn evalWaveClamped(wave: shader_mod.Wave, time: f32) f32 {
    return std.math.clamp(evalWave(wave, time), 0, 1);
}

// ---------------------------------------------------------------------------------------------
// Stage backend

const Batch = struct {
    shader: *Shader,
    entity: ?*Entity,
    orientation: Orientation,
    mesh: Mesh,
    time: f32,
    depth_hack: bool,
    dlights: bool,
    sky: bool = false,
    two_d: bool = false,
    liquid: image.Liquid = .none,
};

/// View rectangle (output pixels) in the current target's pixels (remaster render scale).
fn targetRect(x: i32, y: i32, w: i32, h: i32) [4]i32 {
    const s = window.targetScale();
    if (s == 1) return .{ x, y, w, h };
    const x0: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(x)) * s));
    const y0: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(y)) * s));
    const x1: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(x + w)) * s));
    const y1: i32 = @intFromFloat(@round(@as(f32, @floatFromInt(y + h)) * s));
    return .{ x0, y0, x1 - x0, y1 - y0 };
}

fn setViewport(view: *const View, depth_hack: bool, sky: bool) void {
    const cmd = window.cmd;
    const rect = targetRect(view.x, view.y, view.width, view.height);
    const x: f32 = @floatFromInt(rect[0]);
    const y: f32 = @floatFromInt(rect[1]);
    const w: f32 = @floatFromInt(rect[2]);
    const h: f32 = @floatFromInt(rect[3]);
    const viewport = c.VkViewport{ .x = x, .y = y + h, .width = w, .height = -h, .minDepth = if (sky) 1 else 0, .maxDepth = if (sky) 1 else if (depth_hack) 0.3 else 1 };
    vk.d.CmdSetViewport.?(cmd, 0, 1, &viewport);
}

fn setScissor(x: i32, y: i32, w: i32, h: i32) void {
    const extent = window.targetExtent();
    const max_w: i32 = @intCast(extent[0]);
    const max_h: i32 = @intCast(extent[1]);
    const rect = targetRect(x, y, w, h);
    const x0 = std.math.clamp(rect[0], 0, max_w);
    const y0 = std.math.clamp(rect[1], 0, max_h);
    const x1 = std.math.clamp(rect[0] + rect[2], 0, max_w);
    const y1 = std.math.clamp(rect[1] + rect[3], 0, max_h);
    const scissor = c.VkRect2D{ .offset = .{ .x = x0, .y = y0 }, .extent = .{ .width = @intCast(@max(x1 - x0, 0)), .height = @intCast(@max(y1 - y0, 0)) } };
    vk.d.CmdSetScissor.?(window.cmd, 0, 1, &scissor);
}

fn clearDepth(view: *const View) void {
    const extent = window.targetExtent();
    const area = targetRect(view.x, view.y, view.width, view.height);
    const x0 = std.math.clamp(area[0], 0, @as(i32, @intCast(extent[0])));
    const y0 = std.math.clamp(area[1], 0, @as(i32, @intCast(extent[1])));
    const x1 = std.math.clamp(area[0] + area[2], 0, @as(i32, @intCast(extent[0])));
    const y1 = std.math.clamp(area[1] + area[3], 0, @as(i32, @intCast(extent[1])));
    if (x1 <= x0 or y1 <= y0) return;
    const attachment = c.VkClearAttachment{ .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT, .colorAttachment = 0, .clearValue = .{ .depthStencil = .{ .depth = 1, .stencil = 0 } } };
    const rect = c.VkClearRect{ .rect = .{ .offset = .{ .x = x0, .y = y0 }, .extent = .{ .width = @intCast(x1 - x0), .height = @intCast(y1 - y0) } }, .baseArrayLayer = 0, .layerCount = 1 };
    vk.d.CmdClearAttachments.?(window.cmd, 1, &attachment, 1, &rect);
}

fn drawView(view: *View, surfaces: []DrawSurf) void {
    // Remaster world views render into the HDR target; menu and HUD model views stay in the
    // UI overlay with the classic look.
    window.useTarget(if (window.remaster and view.rdflags & c.RDF_NOWORLDMODEL == 0) .hdr else .classic);
    clearDepth(view);
    setScissor(view.x, view.y, view.width, view.height);
    var traced = false;
    var index: usize = 0;
    while (index < surfaces.len) {
        const surface = surfaces[index];
        // Path tracing mode relights the opaque world before translucent surfaces draw.
        if (!traced and surface.shader.sort > shader_mod.Sort.see_through) {
            pathTrace(view);
            traced = true;
        }
        const entity: ?*Entity = if (surface.entity == world_entity) null else &view.entities[surface.entity];
        switch (surface.geometry) {
            .world => |w| {
                // Merge consecutive surfaces of the same shader, entity and world into one batch.
                var end = index + 1;
                var dlight_bits = surface.dlights;
                while (end < surfaces.len) : (end += 1) {
                    const next = surfaces[end];
                    if (next.shader != surface.shader or next.entity != surface.entity) break;
                    switch (next.geometry) {
                        .world => |nw| if (nw.owner != w.owner or nw.owner.surfaces[nw.surface].liquid != w.owner.surfaces[w.surface].liquid) break,
                        else => break,
                    }
                    dlight_bits |= next.dlights;
                }
                const mesh = world.mergeIndices(w.owner, surfaces[index..end]) orelse {
                    index = end;
                    continue;
                };
                const liquid = w.owner.surfaces[w.surface].liquid;
                if (liquid != .none and window.currentTarget() == .hdr and !view.is_portal) {
                    window.beginLiquids();
                    drawLiquid(view, surface.shader, entity, mesh, liquid);
                } else drawBatch(view, surface.shader, entity, mesh, dlight_bits != 0, false);
                index = end;
            },
            .mesh => |mesh| {
                drawBatch(view, surface.shader, entity, mesh, surface.dlights != 0 or (entity != null and view.dlights.len > 0), false);
                index += 1;
            },
            .sky => {
                drawSky(view, surface.shader);
                index += 1;
            },
        }
    }
    if (!traced) pathTrace(view);
    window.endLiquids();
}

fn pathTrace(view: *const View) void {
    if (view.is_portal or !view.ray_traced or !pathtrace.active() or window.currentTarget() != .hdr) return;
    const owner = view.world orelse return;
    const s = window.render_scale;
    const sky: Vec3 = rt.skyFor(owner);
    pathtrace.run(window.cmd, owner, view.rt_table, .{
        .origin = view.origin,
        .axis = view.axis,
        .fov_x = view.fov_x,
        .fov_y = view.fov_y,
        .znear = view.znear,
        .zfar = view.zfar,
        .rect = .{ @as(f32, @floatFromInt(view.x)) * s, @as(f32, @floatFromInt(view.y)) * s, @as(f32, @floatFromInt(view.width)) * s, @as(f32, @floatFromInt(view.height)) * s },
        .dlights = view.dlight_address,
        .dlight_count = @intCast(view.dlights.len),
        .view_data = view.view_data,
        .sky = sky,
    });
}

/// A remaster liquid: one pass with the liquid shading in place of the shader's stages.
fn drawLiquid(view: *const View, shader: *Shader, entity: ?*Entity, mesh: Mesh, liquid: image.Liquid) void {
    if (mesh.count == 0 or shader.num_stages == 0) return;
    var batch: Batch = .{
        .shader = shader,
        .entity = entity,
        .orientation = orientation(view, entity),
        .mesh = mesh,
        .time = view.time - shader.time_offset,
        .depth_hack = false,
        .dlights = view.dlights.len > 0,
        .liquid = liquid,
    };
    var stage = shader.stages[0];
    stage.blended = false;
    stage.src = shader_mod.Blend.one;
    stage.dst = shader_mod.Blend.zero;
    stage.depth_write = false;
    stage.alpha_func = .none;
    drawStage(view, &batch, &stage);
    batch.liquid = .none;
}

fn drawBatch(view: *const View, shader: *Shader, entity: ?*Entity, mesh: Mesh, lit: bool, sky: bool) void {
    if (mesh.count == 0) return;
    var time = view.time;
    if (entity) |ent| time -= ent.e.shaderTime;
    time -= shader.time_offset;
    if (shader.clamp_time != 0 and time >= shader.clamp_time) time = shader.clamp_time;
    const depth_hack = if (entity) |ent| ent.e.renderfx & c.RF_DEPTHHACK != 0 else false;
    const batch: Batch = .{
        .shader = shader,
        .entity = entity,
        .orientation = orientation(view, entity),
        .mesh = mesh,
        .time = time,
        .depth_hack = depth_hack,
        .dlights = lit and view.dlights.len > 0 and shader.surface_flags & c.SURF_NODLIGHT == 0,
        .sky = sky,
    };
    if (view.shadow) {
        // Shadow tiles: depth of the first depth-writing stage only.
        for (shader.stagesSlice()) |*stage| if (stage.depth_write) {
            drawStage(view, &batch, stage);
            break;
        };
        return;
    }
    for (shader.stagesSlice()) |*stage| drawStage(view, &batch, stage);
}

fn constantColor(stage: *const Stage, batch: *const Batch) [4]f32 {
    var color: [4]f32 = .{ 1, 1, 1, 1 };
    const rgba: [4]u8 = if (batch.entity) |ent| ent.e.shaderRGBA else if (batch.two_d) entity2d_color else .{ 255, 255, 255, 255 };
    const byte = struct {
        fn f(v: u8) f32 {
            return @as(f32, @floatFromInt(v)) / 255.0;
        }
    }.f;
    switch (stage.rgb_gen) {
        .identity, .identity_lighting, .bad => color[0..3].* = .{ 1, 1, 1 },
        .entity => color[0..3].* = .{ byte(rgba[0]), byte(rgba[1]), byte(rgba[2]) },
        .one_minus_entity => color[0..3].* = .{ 1 - byte(rgba[0]), 1 - byte(rgba[1]), 1 - byte(rgba[2]) },
        .constant => color[0..3].* = .{ byte(stage.constant[0]), byte(stage.constant[1]), byte(stage.constant[2]) },
        .wave => {
            var glow: f32 = undefined;
            if (stage.rgb_wave.func == .noise) {
                glow = stage.rgb_wave.base + cext.R_NoiseGet4f(0, 0, 0, (batch.time + stage.rgb_wave.phase) * stage.rgb_wave.frequency) * stage.rgb_wave.amplitude;
            } else glow = evalWave(stage.rgb_wave, batch.time);
            glow = std.math.clamp(glow, 0, 1);
            color[0..3].* = .{ glow, glow, glow };
        },
        else => {},
    }
    switch (stage.alpha_gen) {
        .skip, .identity => color[3] = 1,
        .entity => color[3] = byte(rgba[3]),
        .one_minus_entity => color[3] = 1 - byte(rgba[3]),
        .constant => color[3] = byte(stage.constant[3]),
        .wave => color[3] = evalWaveClamped(stage.alpha_wave, batch.time),
        else => {},
    }
    return color;
}

fn rgbMode(gen: shader_mod.RgbGen) u32 {
    return switch (gen) {
        .vertex => 1,
        .one_minus_vertex => 2,
        .lighting_diffuse => 3,
        .exact_vertex => 4,
        else => 0,
    };
}

fn alphaMode(gen: shader_mod.AlphaGen) u32 {
    return switch (gen) {
        .vertex => 1,
        .one_minus_vertex => 2,
        .lighting_specular => 3,
        .portal => 4,
        else => 0,
    };
}

fn tcGenMode(gen: shader_mod.TcGen) u32 {
    return switch (gen) {
        .lightmap => 1,
        .environment => 2,
        .vector => 3,
        .identity => 4,
        else => 0,
    };
}

/// tcMods as GPU ops: turbulence stays per vertex; the rest are affine with CPU-evaluated time.
fn texMods(bundle: *const shader_mod.Bundle, batch: *const Batch, out: *[8][4]f32) u32 {
    var count: u32 = 0;
    for (bundle.texmods[0..bundle.num_texmods]) |mod| {
        var a: [4]f32 = .{ 0, 1, 0, 0 };
        var b: [4]f32 = .{ 0, 1, 0, 0 };
        switch (mod) {
            .turb => |wave| {
                a = .{ 1, wave.amplitude, wave.phase + batch.time * wave.frequency, 0 };
                b = .{ 0, 0, 0, 0 };
            },
            .scale => |s| {
                a = .{ 0, s[0], 0, 0 };
                b = .{ 0, s[1], 0, 0 };
            },
            .scroll, .entity_translate => {
                const speed: [2]f32 = switch (mod) {
                    .scroll => |s| s,
                    else => if (batch.entity) |ent| ent.e.shaderTexCoord else .{ 0, 0 },
                };
                var s = speed[0] * batch.time;
                var t = speed[1] * batch.time;
                s -= @floor(s);
                t -= @floor(t);
                a = .{ 0, 1, 0, 0 };
                b = .{ s, 1, t, 0 };
            },
            .stretch => |wave| {
                const value = evalWave(wave, batch.time);
                const p: f32 = if (value != 0) 1.0 / value else 0;
                a = .{ 0, p, 0, 0 };
                b = .{ 0.5 - 0.5 * p, p, 0.5 - 0.5 * p, 0 };
            },
            .transform => |m| {
                a = .{ 0, m.matrix[0][0], m.matrix[1][0], m.matrix[0][1] };
                b = .{ m.translate[0], m.matrix[1][1], m.translate[1], 0 };
            },
            .rotate => |degrees_per_second| {
                const degrees = -degrees_per_second * batch.time;
                const index: i64 = @intFromFloat(std.math.clamp(degrees * (@as(f32, table_size) / 360.0), -1e15, 1e15));
                const s = sin_table[@intCast(index & (table_size - 1))];
                const co = sin_table[@intCast((index + table_size / 4) & (table_size - 1))];
                // matrix[0][0]=cos [1][0]=-sin [0][1]=sin [1][1]=cos (RB_CalcRotateTexCoords)
                a = .{ 0, co, -s, s };
                b = .{ 0.5 - 0.5 * co + 0.5 * s, co, 0.5 - 0.5 * s - 0.5 * co, 0 };
            },
        }
        out[count * 2] = a;
        out[count * 2 + 1] = b;
        count += 1;
    }
    return count;
}

fn deforms(shader: *const Shader, out: *[6][4]f32) u32 {
    var count: u32 = 0;
    for (shader.deforms[0..shader.num_deforms]) |deform| {
        const func: f32 = @floatFromInt(@intFromEnum(deform.wave.func));
        switch (deform.kind) {
            .wave => {
                out[count * 2] = .{ 1 + func * 10, deform.wave.base, deform.wave.amplitude, deform.wave.phase };
                out[count * 2 + 1] = .{ deform.wave.frequency, deform.spread, 0, 0 };
            },
            .bulge => {
                out[count * 2] = .{ 3, deform.bulge_width, deform.bulge_height, deform.bulge_speed };
                out[count * 2 + 1] = .{ 0, 0, 0, 0 };
            },
            .move => {
                out[count * 2] = .{ 4 + func * 10, deform.move[0], deform.move[1], deform.move[2] };
                out[count * 2 + 1] = .{ deform.wave.base, deform.wave.amplitude, deform.wave.phase, deform.wave.frequency };
            },
            else => continue,
        }
        count += 1;
    }
    return count;
}

fn bundleImage(bundle: *const shader_mod.Bundle, time: f32) *image.Image {
    if (bundle.num_images <= 1 or bundle.animation_speed == 0) return bundle.images[0] orelse image.default_image;
    // R_BindAnimatedImage: frame = ftol(time * speed * FUNCTABLE_SIZE) >> FUNCTABLE_SIZE2.
    const frame: i64 = @intFromFloat(std.math.clamp(time * bundle.animation_speed * table_size, -1e15, 1e15));
    var index = @divFloor(frame, table_size);
    if (index < 0) index = 0;
    return bundle.images[@intCast(@mod(index, bundle.num_images))] orelse image.default_image;
}

/// Fixed-function fog colour per blend (renderergl1 RB_Dk3FogColor).
fn fogColorFor(stage: *const Stage) Vec3 {
    if (!stage.blended) return fog_color;
    if (stage.dst == shader_mod.Blend.one) return .{ 0, 0, 0 };
    if ((stage.src == shader_mod.Blend.dst_color and stage.dst == shader_mod.Blend.zero) or (stage.src == shader_mod.Blend.zero and stage.dst == shader_mod.Blend.src_color)) return .{ 1, 1, 1 };
    if (stage.src == shader_mod.Blend.dst_color and stage.dst == shader_mod.Blend.src_color) return .{ 0.5, 0.5, 0.5 };
    return fog_color;
}

/// Volumetric fog per blend, following fogColorFor: 1 in-scatter, 2 fade, 3 toward white,
/// 4 toward grey.
fn volumeMode(stage: *const Stage) u32 {
    if (!stage.blended) return 1;
    if (stage.dst == shader_mod.Blend.one) return 2;
    if ((stage.src == shader_mod.Blend.dst_color and stage.dst == shader_mod.Blend.zero) or (stage.src == shader_mod.Blend.zero and stage.dst == shader_mod.Blend.src_color)) return 3;
    if (stage.src == shader_mod.Blend.dst_color and stage.dst == shader_mod.Blend.src_color) return 4;
    return 1;
}

fn modelViewProjection(view: *const View, o: *const Orientation, two_d: bool) struct { clip: [16]f32, mv: [3][4]f32 } {
    const m: [4][4]f32 = .{ o.model[0], o.model[1], o.model[2], .{ 0, 0, 0, 1 } };
    const mv = if (two_d) m else mat4Mul(view.view_matrix, m);
    const p = if (two_d) ortho2d() else view.projection;
    const clip = mat4Mul(p, mv);
    var out: [16]f32 = undefined;
    for (0..4) |row| for (0..4) |column| {
        out[column * 4 + row] = clip[row][column];
    };
    return .{ .clip = out, .mv = .{ mv[0], mv[1], mv[2] } };
}

fn ortho2d() [4][4]f32 {
    const w: f32 = @floatFromInt(window.config.vidWidth);
    const h: f32 = @floatFromInt(window.config.vidHeight);
    return .{
        .{ 2 / w, 0, 0, -1 },
        .{ 0, -2 / h, 0, 1 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 1 },
    };
}

var current_pipeline: c.VkPipeline = null;

fn drawStage(view: *const View, batch: *const Batch, stage: *const Stage) void {
    const frame = vk.frame();
    const space = frame.records.alloc(@sizeOf(Record), 16) orelse {
        common.developer("renderer_vulkan: draw record ring full\n", .{});
        return;
    };
    const record: *Record = @ptrCast(@alignCast(space.bytes.ptr));
    record.* = std.mem.zeroes(Record);
    const transform = modelViewProjection(view, &batch.orientation, batch.two_d);
    record.clip = transform.clip;
    record.model_view = transform.mv;
    record.model = batch.orientation.model;
    record.view_origin = .{ batch.orientation.view_origin[0], batch.orientation.view_origin[1], batch.orientation.view_origin[2], batch.time };
    record.const_color = constantColor(stage, batch);
    if (batch.entity) |ent| {
        if (stage.rgb_gen == .lighting_diffuse or stage.alpha_gen == .lighting_specular) setupEntityLighting(view, ent);
        record.ambient = .{ ent.ambient[0] / 255.0, ent.ambient[1] / 255.0, ent.ambient[2] / 255.0, 1 };
        record.directed = .{ ent.directed[0] / 255.0, ent.directed[1] / 255.0, ent.directed[2] / 255.0, 0 };
        record.light_dir = .{ ent.light_dir[0], ent.light_dir[1], ent.light_dir[2], batch.shader.portal_range };
    } else {
        // The world entity: R_SetupEntityLighting is never run; renderergl1 uses its zeroed light.
        record.ambient = .{ 0, 0, 0, 1 };
        record.light_dir = .{ 0, 0, 0, batch.shader.portal_range };
    }
    const bundle = &stage.bundles[0];
    record.counts[0] = texMods(bundle, batch, &record.tcmod);
    record.counts[1] = deforms(batch.shader, &record.deform);
    record.tc_gen_vector = .{
        .{ bundle.tc_gen_vectors[0][0], bundle.tc_gen_vectors[0][1], bundle.tc_gen_vectors[0][2], 0 },
        .{ bundle.tc_gen_vectors[1][0], bundle.tc_gen_vectors[1][1], bundle.tc_gen_vectors[1][2], 0 },
    };
    record.mode = .{ batch.mesh.kind, rgbMode(stage.rgb_gen), alphaMode(stage.alpha_gen), tcGenMode(bundle.tc_gen) };
    var flags: u32 = 0;
    const first = bundleImage(bundle, batch.time);
    var second_slot: u32 = 0;
    if (stage.bundles[1].images[0] != null) {
        second_slot = bundleImage(&stage.bundles[1], batch.time).texture.slot + 1;
        if (stage.bundles[1].is_lightmap) flags |= flag_second_lightmap;
    }
    if (bundle.is_lightmap) flags |= flag_first_lightmap;
    if (cvars.lightmap.integer != 0 and stage.bundles[1].is_lightmap) second_slot = 0;
    const on_hdr = view.view_data != 0 and !batch.two_d and window.currentTarget() == .hdr;
    if (on_hdr) record.view = view.view_data;
    // Portal views into another resident world would trace the wrong world.
    if (on_hdr and view.ray_traced and !view.is_portal) flags |= flag_rt;
    if (on_hdr and view.volumetric) {
        flags |= flag_volume;
        record.fog_color[3] = @floatFromInt(volumeMode(stage));
        record.fog_color[0] = if (batch.sky) 1 else 0;
    } else if (view.fog and !batch.two_d) {
        flags |= flag_fog;
        var start = fog_start;
        var end = fog_end;
        if (batch.sky) {
            // The original 4096-unit sky box with skyEnd as its fog end (RB_Dk3FogSky).
            const range = fog_sky_end - fog_start;
            var factor: f32 = 1;
            if (range != 0) factor = (fog_sky_end - 4096) / range;
            factor = std.math.clamp(factor, 0, 1);
            end = factor * 1e6;
            start = end - 1e6;
        }
        record.fog = .{ start, end, 1, 0 };
        const color = fogColorFor(stage);
        record.fog_color = .{ color[0], color[1], color[2], 1 };
    }
    if (view.portal_plane) |plane| {
        flags |= flag_clip;
        record.clip_plane = plane;
    }
    const target = window.currentTarget();
    const linear = target == .hdr;
    const overlay = window.remaster and target == .classic;
    if (linear) {
        flags |= flag_linear;
        const material = image.material(first);
        record.material = .{ material.roughness, material.metalness, material.bump * cvars.vkBump.value, material.emissive };
        record.material2 = .{ material.specular * cvars.vkSpecular.value, @floatFromInt(@intFromEnum(material.liquid)), 0, 0 };
        record.maps = .{ if (material.normal) |n| n.texture.slot + 1 else 0, if (material.spec) |sp| sp.texture.slot + 1 else 0, 0, 0 };
        record.view_pos = .{ view.origin[0], view.origin[1], view.origin[2], 0 };
        const world_lit = stage.bundles[1].is_lightmap and !stage.blended and !bundle.is_lightmap;
        const model_lit = stage.rgb_gen == .lighting_diffuse and batch.entity != null;
        if (world_lit) {
            flags |= flag_pbr_world;
            // Emitting faces' own light for ray traced lighting (stage.frag rtDirectLight).
            const own = batch.shader.rt_self_light;
            record.world_light = .{ own[0], own[1], own[2], 0 };
        }
        if (model_lit) {
            flags |= flag_pbr_model;
            if (!stage.blended and on_hdr) flags |= flag_dynamic;
            const ent = batch.entity.?;
            record.world_light = .{ ent.light_world[0], ent.light_world[1], ent.light_world[2], 0 };
        }
        if (world_lit) if (stage.bundles[1].images[0]) |lightmap| {
            record.material2[3] = @floatFromInt(lightmap.deluxe_slot);
        };
        if (world_lit) if (view.world) |owner| if (world.gridParams(owner)) |grid| {
            record.grid0 = grid.origin;
            record.grid1 = grid.scale;
            record.maps[2] = grid.slot + 1;
        };
    }
    if (overlay and !stage.blended) flags |= flag_overlay_opaque;
    if (linear and batch.liquid != .none) {
        flags |= flag_liquid;
        flags &= ~(flag_pbr_world | flag_pbr_model);
        record.material2[1] = @floatFromInt(@intFromEnum(batch.liquid));
        record.material2[2] = view.zfar;
        record.view_pos[3] = view.znear;
        record.maps[3] = window.refraction.slot + 1;
        record.counts[3] = window.depth_slot + 1;
        if (view.world) |owner| if (world.gridParams(owner)) |grid| {
            record.grid0 = grid.origin;
            record.grid1 = grid.scale;
            record.maps[2] = grid.slot + 1;
        };
    }
    if (stage.depth_write and window.depthReadOnly()) window.endLiquids();
    var light_count: u32 = 0;
    if (batch.dlights and (bundle.is_lightmap or stage.bundles[1].is_lightmap)) light_count = @intCast(view.dlights.len);
    // Remaster models receive dynamic lights per pixel instead of through the entity light;
    // remaster world materials take every light through the clusters.
    if (linear and flags & (flag_pbr_model | flag_pbr_world) != 0) light_count = @intCast(view.dlights.len);
    // Rain and snow are lit per particle, glinting near lights (stage.vert weatherLight).
    if (batch.mesh.kind == 3) light_count = @intCast(view.dlights.len);
    record.counts[2] = light_count;
    record.lights = view.dlight_address;
    record.mode2 = .{ first.texture.slot, second_slot, flags, @intFromEnum(stage.alpha_func) };
    record.vertices = batch.mesh.vertices;
    record.indices = batch.mesh.indices;
    record.frame_b = batch.mesh.frame_b;
    record.extra = if (batch.mesh.kind == 0) 0 else batch.mesh.extra;
    record.misc = .{ batch.mesh.backlerp, 0, 0, 0 };

    const cmd = window.cmd;
    // Weather particles also lower the HDR alpha so the temporal resolve treats them as moving.
    const mark_motion = batch.mesh.kind == 3 and window.currentTarget() == .hdr;
    const pipeline = vk.pipeline(.{ .src = stage.src, .dst = stage.dst, .format = window.targetFormat(), .program = vk.program_stage, .overlay = overlay, .mark_motion = mark_motion });
    if (pipeline != current_pipeline) {
        vk.d.CmdBindPipeline.?(cmd, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline);
        current_pipeline = pipeline;
    }
    setViewport(view, batch.depth_hack, batch.sky);
    const cull: c.VkCullModeFlags = if (batch.two_d) c.VK_CULL_MODE_NONE else switch (batch.shader.cull) {
        .two_sided => c.VK_CULL_MODE_NONE,
        .front => if (view.is_mirror) c.VK_CULL_MODE_BACK_BIT else c.VK_CULL_MODE_FRONT_BIT,
        .back => if (view.is_mirror) c.VK_CULL_MODE_FRONT_BIT else c.VK_CULL_MODE_BACK_BIT,
    };
    vk.d.CmdSetCullMode.?(cmd, cull);
    vk.d.CmdSetFrontFace.?(cmd, c.VK_FRONT_FACE_COUNTER_CLOCKWISE);
    vk.d.CmdSetDepthTestEnable.?(cmd, @intFromBool(stage.depth_test));
    vk.d.CmdSetDepthWriteEnable.?(cmd, @intFromBool(stage.depth_write and !batch.two_d));
    vk.d.CmdSetDepthCompareOp.?(cmd, if (stage.depth_equal) c.VK_COMPARE_OP_EQUAL else c.VK_COMPARE_OP_LESS_OR_EQUAL);
    vk.d.CmdSetDepthBiasEnable.?(cmd, @intFromBool(batch.shader.polygon_offset));
    vk.d.CmdSetDepthBias.?(cmd, if (batch.shader.polygon_offset) -2 else 0, 0, if (batch.shader.polygon_offset) -1 else 0);
    const push = [2]u32{ @truncate(space.address), @truncate(space.address >> 32) };
    vk.d.CmdPushConstants.?(cmd, vk.pipeline_layout, vk.all_stages, 0, 8, &push);
    vk.d.CmdDraw.?(cmd, batch.mesh.count, 1, 0, 0);
    stats.draws += 1;
}

/// Called whenever a new command buffer starts recording.
pub fn resetBindings() void {
    current_pipeline = null;
}

// ---------------------------------------------------------------------------------------------
// Sky (tr_sky.c): the whole outer box, then the cloud dome for the shader's stages.

const sky_subdivisions = 8;
const half_sky = sky_subdivisions / 2;
const st_to_vec = [6][3]i32{ .{ 3, -1, 2 }, .{ -3, 1, 2 }, .{ 1, 3, 2 }, .{ -1, -3, 2 }, .{ -2, -1, 3 }, .{ 2, -1, -3 } };
const sky_texorder = [6]usize{ 0, 2, 1, 3, 4, 5 };

fn skyVec(s_in: f32, t_in: f32, axis: usize, box_size: f32, minmax: [2]f32) struct { xyz: Vec3, st: [2]f32 } {
    const b: Vec3 = .{ s_in * box_size, t_in * box_size, box_size };
    var xyz: Vec3 = undefined;
    for (0..3) |j| {
        const k = st_to_vec[axis][j];
        xyz[j] = if (k < 0) -b[@intCast(-k - 1)] else b[@intCast(k - 1)];
    }
    const s = std.math.clamp((s_in + 1) * 0.5, minmax[0], minmax[1]);
    const t = std.math.clamp((t_in + 1) * 0.5, minmax[0], minmax[1]);
    return .{ .xyz = xyz, .st = .{ s, 1 - t } };
}

/// s_cloudTexCoords for a cloud height (R_InitSkyTexCoords, radiusWorld 4096, zFar 1024).
fn cloudCoords(height: f32, side: usize, s: usize, t: usize) [2]f32 {
    const radius: f32 = 4096;
    const v0 = skyVec(@as(f32, @floatFromInt(@as(i32, @intCast(s)) - half_sky)) / half_sky, @as(f32, @floatFromInt(@as(i32, @intCast(t)) - half_sky)) / half_sky, side, 1024.0 / 1.75, .{ 0, 1 }).xyz;
    const sq = struct {
        fn f(x: f32) f32 {
            return x * x;
        }
    }.f;
    const p = (1.0 / (2 * dot(v0, v0))) * (-2 * v0[2] * radius + 2 * @sqrt(sq(v0[2]) * sq(radius) + 2 * sq(v0[0]) * radius * height + sq(v0[0]) * sq(height) +
        2 * sq(v0[1]) * radius * height + sq(v0[1]) * sq(height) + 2 * sq(v0[2]) * radius * height + sq(v0[2]) * sq(height)));
    var v = scale(v0, p);
    v[2] += radius;
    v = normalize(v);
    return .{ std.math.acos(std.math.clamp(v[0], -1, 1)), std.math.acos(std.math.clamp(v[1], -1, 1)) };
}

fn skyFace(origin: Vec3, box_size: f32, side: usize, clouds: ?f32, minmax: [2]f32) ?Mesh {
    const n = sky_subdivisions + 1;
    const frame = vk.frame();
    const vertices = frame.stream.alloc(n * n * @sizeOf(Vertex), 16) orelse return null;
    const indices = frame.stream.alloc(sky_subdivisions * sky_subdivisions * 6 * 4, 4) orelse return null;
    const out = std.mem.bytesAsSlice(Vertex, vertices.bytes);
    for (0..n) |t| for (0..n) |s| {
        const v = skyVec(@as(f32, @floatFromInt(@as(i32, @intCast(s)) - half_sky)) / half_sky, @as(f32, @floatFromInt(@as(i32, @intCast(t)) - half_sky)) / half_sky, side, box_size, minmax);
        const st = if (clouds) |height| cloudCoords(height, side, s, t) else v.st;
        out[t * n + s] = .{ .pos = add(origin, v.xyz), .st = st, .lm = st, .normal = .{ 0, 0, 0 }, .color = .{ 255, 255, 255, 255 } };
    };
    const list = std.mem.bytesAsSlice(u32, indices.bytes);
    var k: usize = 0;
    for (0..sky_subdivisions) |t| for (0..sky_subdivisions) |s| {
        const a: u32 = @intCast(t * n + s);
        const b: u32 = @intCast((t + 1) * n + s);
        list[k..][0..6].* = .{ a, b, a + 1, a + 1, b, b + 1 };
        k += 6;
    };
    return .{ .kind = 0, .vertices = vertices.address, .indices = indices.address, .count = @intCast(k) };
}

var sky_box_stage: Stage = .{};

fn drawSky(view: *const View, shader: *Shader) void {
    const box_size = view.zfar / 1.75;
    if (shader.sky.outer[0]) |first| if (first != image.default_image) {
        for (0..6) |side| {
            const mesh = skyFace(view.origin, box_size, side, null, .{ 0, 1 }) orelse return;
            sky_box_stage = .{ .active = true, .rgb_gen = .identity_lighting, .alpha_gen = .skip };
            sky_box_stage.bundles[0].images[0] = shader.sky.outer[sky_texorder[side]];
            sky_box_stage.bundles[0].num_images = 1;
            sky_box_stage.bundles[0].tc_gen = .texture;
            const batch: Batch = .{ .shader = shader, .entity = null, .orientation = orientation(view, null), .mesh = mesh, .time = view.time, .depth_hack = false, .dlights = false, .sky = true };
            drawStage(view, &batch, &sky_box_stage);
        }
    };
    if (shader.num_stages == 0 or shader.sky.cloud_height == 0) return;
    for (0..5) |side| {
        const mesh = skyFace(view.origin, box_size, side, shader.sky.cloud_height, .{ 1.0 / 256.0, 255.0 / 256.0 }) orelse return;
        const batch: Batch = .{ .shader = shader, .entity = null, .orientation = orientation(view, null), .mesh = mesh, .time = view.time - shader.time_offset, .depth_hack = false, .dlights = false, .sky = true };
        for (shader.stagesSlice()) |*stage| drawStage(view, &batch, stage);
    }
}

// ---------------------------------------------------------------------------------------------
// 2D (RE_SetColor, RE_StretchPic, RE_StretchRaw)

var entity2d_color: [4]u8 = .{ 255, 255, 255, 255 };

pub fn setColor(rgba: ?*const [4]f32) void {
    const value = if (rgba) |color| color.* else [4]f32{ 1, 1, 1, 1 };
    for (0..4) |index| entity2d_color[index] = @intFromFloat(std.math.clamp(value[index] * 255, 0, 255));
}

fn view2d() View {
    return .{
        .origin = .{ 0, 0, 0 },
        .axis = .{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } },
        .fov_x = 90,
        .fov_y = 90,
        .x = 0,
        .y = 0,
        .width = window.config.vidWidth,
        .height = window.config.vidHeight,
        .znear = 0,
        .zfar = 1,
        .projection = undefined,
        .view_matrix = undefined,
        .frustum = undefined,
        .time = @as(f32, @floatFromInt(common.milliseconds())) * 0.001,
        .time_ms = common.milliseconds(),
        .rdflags = c.RDF_NOWORLDMODEL,
        .areamask = std.mem.zeroes([c.MAX_MAP_AREA_BYTES]u8),
        .pvs_origin = .{ 0, 0, 0 },
        .world = null,
        .entities = &.{},
        .dlights = &.{},
        .fog = false,
        .lightstyles = &no_lightstyles,
        .text = &no_text,
    };
}
const no_lightstyles = std.mem.zeroes([256]f32);
const no_text = std.mem.zeroes([c.MAX_RENDER_STRINGS][c.MAX_RENDER_STRING_LENGTH]u8);

/// `RB_StretchPic`: one quad with the current 2D colour.
pub fn stretchPic(x: f32, y: f32, w: f32, h: f32, s1: f32, t1: f32, s2: f32, t2: f32, handle: c.qhandle_t) void {
    if (window.beginFrame()) resetBindings();
    const shader = shader_mod.byHandle(handle);
    drawQuad2d(shader, x, y, w, h, s1, t1, s2, t2);
}

fn drawQuad2d(shader_in: *Shader, x: f32, y: f32, w: f32, h: f32, s1: f32, t1: f32, s2: f32, t2: f32) void {
    const shader = shader_in.remapped orelse shader_in;
    const frame = vk.frame();
    const vertices = frame.stream.alloc(4 * @sizeOf(Vertex), 16) orelse return;
    const indices = frame.stream.alloc(6 * 4, 4) orelse return;
    const out = std.mem.bytesAsSlice(Vertex, vertices.bytes);
    const color = entity2d_color;
    const normal: Vec3 = .{ 0, 0, 1 };
    out[0] = .{ .pos = .{ x, y, 0 }, .st = .{ s1, t1 }, .lm = .{ s1, t1 }, .normal = normal, .color = color };
    out[1] = .{ .pos = .{ x + w, y, 0 }, .st = .{ s2, t1 }, .lm = .{ s2, t1 }, .normal = normal, .color = color };
    out[2] = .{ .pos = .{ x + w, y + h, 0 }, .st = .{ s2, t2 }, .lm = .{ s2, t2 }, .normal = normal, .color = color };
    out[3] = .{ .pos = .{ x, y + h, 0 }, .st = .{ s1, t2 }, .lm = .{ s1, t2 }, .normal = normal, .color = color };
    std.mem.bytesAsSlice(u32, indices.bytes)[0..6].* = .{ 3, 0, 2, 2, 0, 1 };
    var view = view2d();
    window.useTarget(.classic);
    setScissor(0, 0, view.width, view.height);
    const batch: Batch = .{
        .shader = shader,
        .entity = null,
        .orientation = orientation(&view, null),
        .mesh = .{ .kind = 0, .vertices = vertices.address, .indices = indices.address, .count = 6 },
        .time = view.time - shader.time_offset,
        .depth_hack = false,
        .dlights = false,
        .two_d = true,
    };
    for (shader.stagesSlice()) |*stage| drawStage(&view, &batch, stage);
}

/// `RE_StretchRaw`: uploads into a scratch image and draws it like a 2D picture.
pub fn stretchRaw(x: c_int, y: c_int, w: c_int, h: c_int, cols: c_int, rows: c_int, data: [*c]const u8, client: c_int, dirty: bool) void {
    if (window.beginFrame()) resetBindings();
    if (client < 0 or client >= image.scratch.len) return;
    uploadCinematic(cols, rows, data, client, dirty);
    raw_stage = .{ .active = true, .rgb_gen = .identity, .alpha_gen = .skip, .depth_test = false };
    raw_stage.bundles[0].images[0] = image.scratch[@intCast(client)];
    raw_stage.bundles[0].num_images = 1;
    raw_stage.bundles[0].tc_gen = .texture;
    raw_shader.stages[0] = raw_stage;
    raw_shader.num_stages = 1;
    raw_shader.cull = .two_sided;
    const saved = entity2d_color;
    entity2d_color = .{ 255, 255, 255, 255 };
    drawQuad2d(&raw_shader, @floatFromInt(x), @floatFromInt(y), @floatFromInt(w), @floatFromInt(h), 0.5 / @as(f32, @floatFromInt(cols)), 0.5 / @as(f32, @floatFromInt(rows)), (@as(f32, @floatFromInt(cols)) - 0.5) / @as(f32, @floatFromInt(cols)), (@as(f32, @floatFromInt(rows)) - 0.5) / @as(f32, @floatFromInt(rows)));
    entity2d_color = saved;
}

var raw_stage: Stage = .{};
var raw_shader: Shader = .{ .sort = shader_mod.Sort.@"opaque" };

pub fn uploadCinematic(cols: c_int, rows: c_int, data: [*c]const u8, client: c_int, dirty: bool) void {
    if (client < 0 or client >= image.scratch.len or cols <= 0 or rows <= 0) return;
    const target = image.scratch[@intCast(client)];
    const width: u32 = @intCast(cols);
    const height: u32 = @intCast(rows);
    if (width != target.upload_width or height != target.upload_height or dirty) {
        image.replace(target, data[0 .. @as(usize, width) * height * 4], width, height);
    }
}
