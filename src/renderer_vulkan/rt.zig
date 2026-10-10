// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster ray tracing tier (VK_KHR_acceleration_structure + VK_KHR_ray_query). Every resident
//! world gets bottom-level structures for its static opaque geometry (model 0) and for each
//! inline brush model; a top-level structure is rebuilt per frame from the world and the brush
//! entities in view. Shaders trace with ray queries: dynamic-light shadows, reflections on
//! liquids and smooth or wet materials, probe updates (ddgi.zig) and the path tracer. Hits are
//! shaded from a per-world table: vertices, triangle indices, triangle -> surface and the
//! surface's albedo and lightmap slots (common.glsl `RtTable`).
const std = @import("std");
const c = @import("c.zig").c;
const common = @import("common.zig");
const cvars = @import("cvars.zig");
const vk = @import("vk.zig");
const world = @import("world.zig");
const shader_mod = @import("shader.zig");

pub const max_instances = 1024;

/// VkAccelerationStructureInstanceKHR without C bitfields.
const Instance = extern struct {
    transform: [12]f32,
    custom_and_mask: u32,
    sbt_and_flags: u32,
    reference: u64,
};
comptime {
    if (@sizeOf(Instance) != 64) @compileError("acceleration structure instance layout");
}

/// Mirrors common.glsl `RtTable`.
pub const Table = extern struct {
    vertices: u64,
    indices: u64,
    tri_surface: u64,
    materials: u64,
};

/// Per surface: albedo slot, lightmap slot + 1 (0 none), emissive scale bits, flags.
const Material = extern struct { albedo: u32, lightmap: u32, emissive: f32, flags: u32 };

const ModelAs = struct {
    handle: c.VkAccelerationStructureKHR = null,
    buffer: vk.Buffer = .{},
    address: u64 = 0,
    first_triangle: u32 = 0,
    triangles: u32 = 0,
};

pub const WorldRt = struct {
    built: bool = false,
    failed: bool = false,
    indices: vk.Buffer = .{},
    tri_surface: vk.Buffer = .{},
    materials: vk.Buffer = .{},
    models: []ModelAs = &.{},
    /// The same models' alpha-tested surfaces (foliage, grates): non-opaque, so ray queries
    /// test the texture's alpha at each candidate hit (rt_common.glsl rtAlphaPass).
    alpha_models: []ModelAs = &.{},
    triangles: u32 = 0,
    /// Path tracing: the map's point light entities and a world grid of the lights per cell.
    lights: vk.Buffer = .{},
    light_count: u32 = 0,
    /// Worldspawn "ambient" (radiosity light units).
    ambient: f32 = 0,
    /// Light of the open sky in radiosity units (buildLights), when the map's surface data is known.
    sky_raw: [3]f32 = .{ 0, 0, 0 },
    sky_known: bool = false,
    /// The lights as built, for the r_vkDebugView 19 report.
    debug_lights: []MapLight = &.{},
    /// Byte offset of the r_vkDebugView 19 probe words in the cell buffer.
    probe_offset: u64 = 0,
    /// Next light cell whose visibility counts light_visibility.comp refreshes.
    visibility_cursor: u32 = 0,
    /// Light style values last uploaded to the light buffer's header.
    styles: [256]f32 = .{1} ** 256,
    light_cells: vk.Buffer = .{},
    cell_origin: [3]f32 = .{ 0, 0, 0 },
    cell_dims: [3]u32 = .{ 0, 0, 0 },
};

pub const light_cell_size: f32 = 256;
/// Up to this many lights per 256-unit cell (rt_common.glsl RT_LIGHTS_PER_CELL); a full cell
/// keeps its strongest. The busiest original maps reach ~45.
pub const lights_per_cell = 63;
/// The light buffer starts with the 256 light style values (rt_common.glsl RT_LIGHT_HEADER),
/// rewritten when the styles change (updateStyles); the lights follow.
pub const style_count = 256;
/// Rays per cell and light in the visibility cache (rt_common.glsl RT_VISIBILITY_RAYS).
const visibility_rays = 32;
const probe_words = 64;
var probe_host: vk.Buffer = .{};
var probe_frame: u32 = 0;
/// Cells whose visibility is refreshed per frame.
const visibility_cells_per_frame = 512;

/// How a map light shines (rt_common.glsl RT_LIGHT_*), following the original radiosity
/// (qrad3 lightmap.c, measured against the shipped Daikatana lightmaps):
const Kind = enum(u32) {
    /// Light entity: linear falloff, light - distance, times the receiver's cosine.
    point = 0,
    /// Emitting face (texinfo SURF_LIGHT): value x 0.4 x area, inverse square, cosine at both ends.
    surface = 1,
    /// Worldspawn _sun_*: parallel light from a direction, wherever the sky is visible.
    sun = 3,
};

/// Mirrors rt_common.glsl (RT_LIGHT_STRIDE floats).
const MapLight = extern struct {
    origin: [3]f32,
    intensity: f32,
    color: [3]f32,
    /// Light style index (RT_LIGHT_HEADER values); 0 is the always-on style.
    style: f32 = 0,
    /// Surface lights: half-axes of the face's rectangle (shadow rays aim across it).
    axis_u: [3]f32 = .{ 0, 0, 0 },
    kind: f32 = 0,
    axis_v: [3]f32 = .{ 0, 0, 0 },
    /// Point lights: the entity's "cap" (most this light adds, 0 none);
    /// surface lights: the distance past which they add nothing noticeable.
    limit: f32 = 0,
    /// Sun: towards the sun; surface: the face normal.
    direction: [3]f32 = .{ 0, 0, 0 },
    pad: f32 = 0,

    /// Distance past which the light contributes nothing (cell assignment).
    fn reach(self: MapLight) f32 {
        return switch (@as(Kind, @enumFromInt(@as(u32, @intFromFloat(self.kind))))) {
            .point => self.intensity,
            .surface => self.limit,
            .sun => 1e9,
        };
    }

    /// What the light adds at most within `distance` of its origin (radiosity units, cosines
    /// ignored): how a full cell decides which lights to keep.
    fn strengthAt(self: MapLight, distance: f32) f32 {
        return switch (@as(Kind, @enumFromInt(@as(u32, @intFromFloat(self.kind))))) {
            .point => blk: {
                const amount = @max(self.intensity - distance, 0);
                break :blk if (self.limit > 0) @min(amount, self.limit) else amount;
            },
            .surface => blk: {
                const area = 4 * @sqrt(dot3(self.axis_u, self.axis_u) * dot3(self.axis_v, self.axis_v));
                break :blk self.intensity / (distance * distance + area * 0.3183);
            },
            .sun => 1e9,
        };
    }
};
comptime {
    if (@sizeOf(MapLight) != 80) @compileError("rt_common.glsl RT_LIGHT_STRIDE");
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn kindValue(kind: Kind) f32 {
    return @floatFromInt(@intFromEnum(kind));
}

fn parseVector(text: []const u8) ?[3]f32 {
    var out: [3]f32 = undefined;
    var fields = std.mem.tokenizeAny(u8, text, " \t");
    for (&out) |*value| value.* = std.fmt.parseFloat(f32, fields.next() orelse return null) catch return null;
    return out;
}

fn parseNumber(text: []const u8) ?f32 {
    return std.fmt.parseFloat(f32, std.mem.trim(u8, text, " \t\r\n")) catch null;
}

/// Colour scaled so its brightest channel is 1 (qrad3 ColorNormalize); null for black.
fn normalized(color: [3]f32) ?[3]f32 {
    const peak = @max(color[0], @max(color[1], color[2]));
    if (peak <= 0) return null;
    return .{ color[0] / peak, color[1] / peak, color[2] / peak };
}

/// One entity's key/value pairs, as slices into the entity text.
const Entity = struct {
    pairs: [64][2][]const u8 = undefined,
    count: usize = 0,

    fn parse(block: []const u8) Entity {
        var e: Entity = .{};
        var quoted = std.mem.tokenizeScalar(u8, block, '"');
        var key: ?[]const u8 = null;
        while (quoted.next()) |token| {
            if (std.mem.trim(u8, token, " \t\r\n").len == 0) continue;
            if (key) |k| {
                if (e.count < e.pairs.len) {
                    e.pairs[e.count] = .{ k, token };
                    e.count += 1;
                }
                key = null;
            } else key = token;
        }
        return e;
    }

    fn get(self: *const Entity, key: []const u8) ?[]const u8 {
        for (self.pairs[0..self.count]) |pair| if (std.ascii.eqlIgnoreCase(pair[0], key)) return pair[1];
        return null;
    }

    fn number(self: *const Entity, key: []const u8) ?f32 {
        return parseNumber(self.get(key) orelse return null);
    }
};

/// The original emitting surfaces: `maps/<map>.lights` (dkq3/tools/surface_lights.py), or null
/// when the remaster package does not carry them.
const SurfaceLightData = struct {
    entries: std.ArrayList(struct { surface: u32, value: f32, color: [3]f32 }) = .empty,
    sky: ?struct { value: f32, color: [3]f32 } = null,
};

fn readSurfaceLights(w: *const world.World) ?SurfaceLightData {
    const name = w.nameSlice();
    if (!std.mem.endsWith(u8, name, ".bsp")) return null;
    var path: [c.MAX_QPATH]u8 = undefined;
    var joined: [c.MAX_QPATH]u8 = undefined;
    const stem = name[0 .. name.len - 4];
    const text_name = std.fmt.bufPrint(&joined, "{s}.lights", .{stem}) catch return null;
    const bytes = common.readFile(common.qpath(&path, text_name).ptr) orelse return null;
    defer common.freeFile(bytes);
    var data: SurfaceLightData = .{};
    var lines = std.mem.tokenizeAny(u8, bytes, "\r\n");
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const tag = fields.next() orelse continue;
        if (std.mem.eql(u8, tag, "surface")) {
            const index = std.fmt.parseInt(u32, fields.next() orelse continue, 10) catch continue;
            const value = parseNumber(fields.next() orelse continue) orelse continue;
            const color = parseVector(fields.rest()) orelse continue;
            if (index >= w.surfaces.len) continue;
            data.entries.append(common.gpa, .{ .surface = index, .value = value, .color = color }) catch break;
        } else if (std.mem.eql(u8, tag, "sky")) {
            const value = parseNumber(fields.next() orelse continue) orelse continue;
            const color = parseVector(fields.rest()) orelse continue;
            data.sky = .{ .value = value, .color = color };
        }
    }
    return data;
}

/// A surface's area, centre and bounding rectangle in its plane.
const FaceShape = struct { area: f32, centre: [3]f32, axis_u: [3]f32, axis_v: [3]f32, normal: [3]f32 };

fn faceShape(w: *const world.World, surface: *const world.Surface) ?FaceShape {
    const S = @import("scene.zig");
    if (surface.kind != .face or surface.num_indexes < 3) return null;
    var area: f32 = 0;
    var centre: [3]f32 = .{ 0, 0, 0 };
    const indices = w.indices.items[surface.first_index .. surface.first_index + surface.num_indexes];
    var t: usize = 0;
    while (t + 2 < indices.len) : (t += 3) {
        const a = w.vertices.items[indices[t]].pos;
        const b = w.vertices.items[indices[t + 1]].pos;
        const c3 = w.vertices.items[indices[t + 2]].pos;
        const tri = 0.5 * S.length(S.cross(S.sub(b, a), S.sub(c3, a)));
        area += tri;
        for (0..3) |k| centre[k] += tri * (a[k] + b[k] + c3[k]) / 3.0;
    }
    if (area < 1) return null;
    for (&centre) |*value| value.* /= area;
    const n = surface.plane_normal;
    const first_edge = S.sub(w.vertices.items[indices[1]].pos, w.vertices.items[indices[0]].pos);
    var u_dir = S.normalize(S.sub(first_edge, S.scale(n, S.dot(first_edge, n))));
    if (S.dot(u_dir, u_dir) < 0.5) u_dir = S.normalize(S.cross(n, if (@abs(n[2]) < 0.9) [3]f32{ 0, 0, 1 } else [3]f32{ 1, 0, 0 }));
    const v_dir = S.cross(n, u_dir);
    var lo: [2]f32 = .{ 1e30, 1e30 };
    var hi: [2]f32 = .{ -1e30, -1e30 };
    for (indices) |index| {
        const d = S.sub(w.vertices.items[index].pos, centre);
        const pu = S.dot(d, u_dir);
        const pv = S.dot(d, v_dir);
        lo = .{ @min(lo[0], pu), @min(lo[1], pv) };
        hi = .{ @max(hi[0], pu), @max(hi[1], pv) };
    }
    centre = S.add(centre, S.add(S.scale(u_dir, (lo[0] + hi[0]) * 0.5), S.scale(v_dir, (lo[1] + hi[1]) * 0.5)));
    return .{
        .area = area,
        .centre = centre,
        .axis_u = S.scale(u_dir, @max((hi[0] - lo[0]) * 0.5, 0.5)),
        .axis_v = S.scale(v_dir, @max((hi[1] - lo[1]) * 0.5, 0.5)),
        .normal = n,
    };
}

fn surfaceTexture(surface: *const world.Surface) ?*@import("image.zig").Image {
    for (surface.shader.stagesSlice()) |*stage| {
        const first = stage.bundles[0].images[0] orelse continue;
        if (stage.bundles[0].is_lightmap) continue;
        return first;
    }
    return null;
}

/// The original emitting faces (texinfo SURF_LIGHT + value + extsurfinfo colour) as area lights:
/// qrad3 CreateDirectLights gives each patch value x reflectivity x area x 0.4 (direct_scale) and
/// GatherSampleLight lights a point with intensity x cos x cos' / distance^2. Measured against
/// the shipped lightmaps, this matches the original levels.
fn originalSurfaceLights(w: *const world.World, data: *const SurfaceLightData, out: *std.ArrayList(MapLight)) void {
    const S = @import("scene.zig");
    for (data.entries.items) |entry| {
        const surface = &w.surfaces[entry.surface];
        const shape = faceShape(w, surface) orelse continue;
        // A liquid's underside lit the bottom it faces; ray traced, liquids are not in the scene,
        // so probe rays through the surface would carry that light up into the air. Faces that
        // emit into a liquid are left out.
        const front = S.add(shape.centre, S.scale(shape.normal, 4));
        if (world.liquidOf(world.contentsAt(w, front)) != .none) continue;
        var color = entry.color;
        var strength: f32 = 1;
        if (normalized(color)) |hue| {
            strength = @max(color[0], @max(color[1], color[2]));
            color = hue;
        } else {
            // No colour of its own: the texture's (qrad3 texture_reflectivity, normalised).
            const texture = surfaceTexture(surface) orelse continue;
            color = normalized(texture.average) orelse continue;
        }
        const intensity = entry.value * 0.4 * shape.area * strength;
        if (intensity <= 0) continue;
        // The face lights itself: the shipped lightmaps of emitting faces hold the value (up to
        // the radiosity's 196 maximum) tinted by the colour twice (emitted, then reflected).
        const own = @min(entry.value * strength, 196);
        for (0..3) |k| surface.shader.rt_self_light[k] = @max(surface.shader.rt_self_light[k], own * color[k] * color[k]);
        // Where it falls below one radiosity unit (a 255th of full brightness).
        const reach = std.math.clamp(@sqrt(intensity), 64, 4096);
        out.append(common.gpa, .{
            .origin = S.add(shape.centre, S.scale(shape.normal, 1.0)),
            .intensity = intensity,
            .color = color,
            .kind = kindValue(.surface),
            .axis_u = shape.axis_u,
            .axis_v = shape.axis_v,
            .limit = reach,
            .direction = shape.normal,
        }) catch return;
    }
}

/// Without the original surface data: glowing surfaces guessed from their material (lamp heads,
/// light panels, monitors) as moderate area lights.
fn guessedSurfaceLights(w: *const world.World, out: *std.ArrayList(MapLight)) void {
    const image = @import("image.zig");
    const S = @import("scene.zig");
    for (w.surfaces) |*surface| {
        if (surface.shader.is_sky) continue;
        const texture = surfaceTexture(surface) orelse continue;
        const emissive = image.material(texture).emissive;
        if (emissive <= 0) continue;
        const shape = faceShape(w, surface) orelse continue;
        if (shape.area < 16) continue;
        const color = normalized(texture.average) orelse continue;
        const value = std.math.clamp(800 * @min(emissive, 2.5), 200, 2000);
        const intensity = value * 0.4 * shape.area;
        out.append(common.gpa, .{
            .origin = S.add(shape.centre, S.scale(shape.normal, 1.0)),
            .intensity = intensity,
            .color = color,
            .kind = kindValue(.surface),
            .axis_u = shape.axis_u,
            .axis_v = shape.axis_v,
            .limit = std.math.clamp(@sqrt(intensity), 64, 4096),
            .direction = shape.normal,
        }) catch return;
    }
}

/// Worldspawn values the lighting uses besides the light entities.
const WorldKeys = struct {
    /// "ambient": the radiosity's constant floor (light units).
    ambient: f32 = 0,
    /// _sun_light, _sun_color, _sun_angle ("yaw pitch" of the light's travel), _sun_diffuse.
    sun: ?MapLight = null,
    sun_diffuse: f32 = 0,
    sun_color: [3]f32 = .{ 1, 1, 1 },
};

fn sunFrom(e: *const Entity, keys: *WorldKeys) void {
    keys.ambient = e.number("ambient") orelse 0;
    const strength = e.number("_sun_light") orelse 0;
    if (e.get("_sun_color")) |text| if (parseVector(text)) |value| if (normalized(value)) |hue| {
        keys.sun_color = hue;
    };
    keys.sun_diffuse = e.number("_sun_diffuse") orelse 0;
    if (strength <= 0) return;
    var yaw: f32 = 0;
    var pitch: f32 = -90;
    if (e.get("_sun_angle")) |text| {
        var fields = std.mem.tokenizeAny(u8, text, " \t");
        yaw = parseNumber(fields.next() orelse "0") orelse 0;
        pitch = parseNumber(fields.next() orelse "-90") orelse -90;
    }
    const y = std.math.degreesToRadians(yaw);
    const p = std.math.degreesToRadians(pitch);
    // The angles give the light's travel; shading needs the way back to the sun.
    const travel: [3]f32 = .{ @cos(p) * @cos(y), @cos(p) * @sin(y), @sin(p) };
    keys.sun = .{
        .origin = .{ 0, 0, 0 },
        .intensity = strength,
        .color = keys.sun_color,
        .kind = kindValue(.sun),
        .direction = .{ -travel[0], -travel[1], -travel[2] },
    };
}

/// Light entities (every classname starting with "light", as qrad3 reads them): origin, light
/// (300 when missing), _color (normalised), style, cap. Targets and cone keys do not narrow them:
/// the shipped lightmaps light surfaces far outside any cone (e1m4a's crematorium sign sits 50
/// degrees off its lights' targets and is fully lit), so every light entity is a point light.
/// START_OFF lights without a style were not in the radiosity; with one, the style switches them.
fn mapLights(w: *const world.World, out: *std.ArrayList(MapLight), keys: *WorldKeys) void {
    if (!w.has_entities) return;
    var text: []const u8 = w.entity_string;
    while (std.mem.indexOfScalar(u8, text, '{')) |open| {
        const close = std.mem.indexOfScalarPos(u8, text, open, '}') orelse break;
        const e = Entity.parse(text[open + 1 .. close]);
        text = text[close + 1 ..];
        const classname = e.get("classname") orelse continue;
        if (std.mem.eql(u8, classname, "worldspawn")) {
            sunFrom(&e, keys);
            continue;
        }
        if (!std.mem.startsWith(u8, classname, "light")) continue;
        const origin = parseVector(e.get("origin") orelse continue) orelse continue;
        var intensity = e.number("light") orelse e.number("_light") orelse 300;
        if (intensity == 0) intensity = 300;
        if (intensity < 0) continue;
        const style: f32 = std.math.clamp(e.number("style") orelse 0, 0, style_count - 1);
        const spawnflags: u32 = @intFromFloat(std.math.clamp(e.number("spawnflags") orelse 0, 0, 65535));
        if (spawnflags & 1 != 0 and style == 0) continue;
        var color: [3]f32 = .{ 1, 1, 1 };
        if (e.get("_color") orelse e.get("color")) |value_text| if (parseVector(value_text)) |value| {
            color = normalized(value) orelse continue;
        };
        out.append(common.gpa, .{ .origin = origin, .intensity = intensity, .color = color, .style = style, .limit = @max(e.number("cap") orelse 0, 0) }) catch return;
    }
}

/// Clusters found in a light cell (-1 ends the list; all -1: none found, so nothing is culled).
const cell_cluster_slots = 24;

fn clustersOfCell(w: *const world.World, state: *const WorldRt, cell: u32, out: *[cell_cluster_slots]i32) void {
    @memset(out, -1);
    const x = cell % state.cell_dims[0];
    const y = (cell / state.cell_dims[0]) % state.cell_dims[1];
    const z = cell / (state.cell_dims[0] * state.cell_dims[1]);
    var count: usize = 0;
    const steps = 5;
    for (0..steps) |i| for (0..steps) |j| for (0..steps) |k| {
        const point: [3]f32 = .{
            state.cell_origin[0] + (@as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(i)) + 0.5) / steps) * light_cell_size,
            state.cell_origin[1] + (@as(f32, @floatFromInt(y)) + (@as(f32, @floatFromInt(j)) + 0.5) / steps) * light_cell_size,
            state.cell_origin[2] + (@as(f32, @floatFromInt(z)) + (@as(f32, @floatFromInt(k)) + 0.5) / steps) * light_cell_size,
        };
        const cluster = world.clusterAt(w, point);
        if (cluster < 0) continue;
        if (std.mem.indexOfScalar(i32, out[0..count], cluster) != null) continue;
        if (count == cell_cluster_slots) {
            // Too many to list: treat the cell as seeing everything.
            @memset(out, -1);
            return;
        }
        out[count] = cluster;
        count += 1;
    };
}

/// The light's cluster: its origin, or a little in front of an emitting face; -1 when unknown.
fn lightCluster(w: *const world.World, light: MapLight) i32 {
    if (light.kind == kindValue(.sun)) return -1;
    var cluster = world.clusterAt(w, light.origin);
    var step: f32 = 4;
    while (cluster < 0 and step <= 16) : (step *= 2) {
        const probe: [3]f32 = .{ light.origin[0] + light.direction[0] * step, light.origin[1] + light.direction[1] * step, light.origin[2] + light.direction[2] * step };
        cluster = world.clusterAt(w, probe);
    }
    return cluster;
}

fn cellSees(w: *const world.World, light_cluster: i32, clusters: *const [cell_cluster_slots]i32) bool {
    if (light_cluster < 0 or clusters[0] < 0) return true;
    for (clusters) |cluster| {
        if (cluster < 0) break;
        if (cluster == light_cluster or world.clusterSees(w, light_cluster, cluster)) return true;
    }
    return false;
}

/// A light's strength anywhere in the cell around `centre` (its nearest point).
fn cellStrength(light: MapLight, centre: [3]f32) f32 {
    const half_diagonal = light_cell_size * 0.8661;
    const d: [3]f32 = .{ centre[0] - light.origin[0], centre[1] - light.origin[1], centre[2] - light.origin[2] };
    return light.strengthAt(@max(@sqrt(dot3(d, d)) - half_diagonal, 0));
}

fn buildLights(w: *world.World) void {
    const state = &w.rt;
    var lights: std.ArrayList(MapLight) = .empty;
    defer lights.deinit(common.gpa);
    var keys: WorldKeys = .{};
    mapLights(w, &lights, &keys);
    state.ambient = keys.ambient;
    if (keys.sun) |sun| lights.append(common.gpa, sun) catch {};
    state.sky_raw = .{ 0, 0, 0 };
    state.sky_known = false;
    if (readSurfaceLights(w)) |data_value| {
        var data = data_value;
        defer data.entries.deinit(common.gpa);
        const entity_count = lights.items.len;
        originalSurfaceLights(w, &data, &lights);
        // The emitting sky faces light an upward-facing point by value x 0.6 x the fraction of
        // its hemisphere that sees the sky: fitted on the shipped lightmaps against that same
        // traced fraction (e2m2a 0.59, e2m1a 0.65, e3m1a 0.93 including bounce, which the probes
        // add here). _sun_diffuse adds its skylight on top.
        // Maps without an emitting sky get none.
        state.sky_known = true;
        if (data.sky) |sky| {
            const strength = @max(sky.color[0], @max(sky.color[1], sky.color[2]));
            const hue = normalized(sky.color) orelse [3]f32{ 1, 1, 1 };
            for (0..3) |k| state.sky_raw[k] = sky.value * 0.6 * strength * hue[k];
        }
        common.developer("dk3 vulkan lights: map={s} entity+sun={d} surfaces={d} of {d} sky={d:.0}\n", .{ w.nameSlice(), entity_count, lights.items.len - entity_count, data.entries.items.len, if (data.sky) |sky| sky.value else 0 });
    } else guessedSurfaceLights(w, &lights);
    for (0..3) |k| state.sky_raw[k] += keys.sun_diffuse * keys.sun_color[k];
    if (lights.items.len == 0) return;
    const mins = w.bmodels[0].mins;
    const maxs = w.bmodels[0].maxs;
    var cells: u64 = 1;
    for (0..3) |axis| {
        state.cell_origin[axis] = mins[axis];
        state.cell_dims[axis] = @intFromFloat(std.math.clamp(@ceil((maxs[axis] - mins[axis]) / light_cell_size), 1, 256));
        cells *= state.cell_dims[axis];
    }
    if (cells > 1 << 20) return;
    const table = common.gpa.alloc(u32, cells * (lights_per_cell + 1)) catch return;
    defer common.gpa.free(table);
    @memset(table, 0);
    // Visibility: a light reaches only cells with a cluster its own cluster can see (the map's
    // PVS, which the radiosity's transfers also respected). Without that, emitting panels in the
    // next room fill a cell's list and its shadow rays, darkening the lights that do reach it.
    const cell_clusters = common.gpa.alloc([cell_cluster_slots]i32, cells) catch return;
    defer common.gpa.free(cell_clusters);
    for (cell_clusters, 0..) |*list, cell| clustersOfCell(w, state, @intCast(cell), list);
    for (lights.items, 0..) |light, index| {
        const light_cluster = lightCluster(w, light);
        var lo: [3]u32 = undefined;
        var hi: [3]u32 = undefined;
        const reach = light.reach();
        for (0..3) |axis| {
            const a = (light.origin[axis] - reach - state.cell_origin[axis]) / light_cell_size;
            const b = (light.origin[axis] + reach - state.cell_origin[axis]) / light_cell_size;
            const top: f32 = @floatFromInt(state.cell_dims[axis] - 1);
            lo[axis] = @intFromFloat(std.math.clamp(@floor(a), 0, top));
            hi[axis] = @intFromFloat(std.math.clamp(@floor(b), 0, top));
        }
        var z = lo[2];
        while (z <= hi[2]) : (z += 1) {
            var y = lo[1];
            while (y <= hi[1]) : (y += 1) {
                var x = lo[0];
                while (x <= hi[0]) : (x += 1) {
                    const cell = (z * state.cell_dims[1] + y) * state.cell_dims[0] + x;
                    if (!cellSees(w, light_cluster, &cell_clusters[cell])) continue;
                    const list = table[cell * (lights_per_cell + 1) ..][0 .. lights_per_cell + 1];
                    if (list[0] < lights_per_cell) {
                        list[1 + list[0]] = @intCast(index);
                        list[0] += 1;
                    } else {
                        // A full cell keeps the lights that add most somewhere inside it.
                        const centre: [3]f32 = .{
                            state.cell_origin[0] + (@as(f32, @floatFromInt(x)) + 0.5) * light_cell_size,
                            state.cell_origin[1] + (@as(f32, @floatFromInt(y)) + 0.5) * light_cell_size,
                            state.cell_origin[2] + (@as(f32, @floatFromInt(z)) + 0.5) * light_cell_size,
                        };
                        var weakest: usize = 1;
                        var weakest_strength: f32 = std.math.floatMax(f32);
                        for (1..lights_per_cell + 1) |slot| {
                            const strength = cellStrength(lights.items[list[slot]], centre);
                            if (strength < weakest_strength) {
                                weakest = slot;
                                weakest_strength = strength;
                            }
                        }
                        if (cellStrength(light, centre) > weakest_strength) list[weakest] = @intCast(index);
                    }
                }
            }
        }
    }
    var full: u32 = 0;
    for (0..cells) |cell| full += @intFromBool(table[cell * (lights_per_cell + 1)] >= lights_per_cell);
    common.developer("dk3 vulkan light cells: map={s} lights={d} cells={d} full={d}\n", .{ w.nameSlice(), lights.items.len, cells, full });
    // Header (style values, all on until the first frame's styles arrive), then the lights.
    const bytes = common.gpa.alloc(u8, style_count * 4 + lights.items.len * @sizeOf(MapLight)) catch return;
    defer common.gpa.free(bytes);
    const header = std.mem.bytesAsSlice(f32, bytes[0 .. style_count * 4]);
    for (header) |*value| value.* = 1;
    @memcpy(bytes[style_count * 4 ..], std.mem.sliceAsBytes(lights.items));
    state.styles = .{1} ** style_count;
    state.lights = vk.staticBuffer(bytes, 0);
    state.debug_lights = common.gpa.dupe(MapLight, lights.items) catch &.{};
    // The visibility counts (light_visibility.comp) follow the lists, all seen until measured.
    // Then probe_words for r_vkDebugView 19 (stage.frag writes the centre pixel's lights).
    const with_visibility = common.gpa.alloc(u32, table.len * 2 + probe_words) catch return;
    defer common.gpa.free(with_visibility);
    @memcpy(with_visibility[0..table.len], table);
    @memset(with_visibility[table.len .. table.len * 2], visibility_rays);
    @memset(with_visibility[table.len * 2 ..], 0);
    state.probe_offset = table.len * 2 * 4;
    state.light_cells = vk.staticBuffer(std.mem.sliceAsBytes(with_visibility), c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT);
    state.visibility_cursor = 0;
    state.light_count = @intCast(lights.items.len);
}

/// Light styles for the ray traced lights (RT_LIGHT_HEADER): the frame's style values (flicker,
/// pulse, switched lights), uploaded when they change.
pub fn updateStyles(w: *world.World, fd: *const c.refdef_t) void {
    const state = &w.rt;
    if (state.light_count == 0 or state.lights.buffer == null) return;
    var values: [style_count]f32 = undefined;
    for (&values, 0..) |*value, k| value.* = std.math.clamp(fd.dk3Lightstyles[k], 0, 4);
    if (std.mem.eql(f32, &values, &state.styles)) return;
    state.styles = values;
    vk.uploadBuffer(state.lights.buffer, 0, std.mem.sliceAsBytes(&values));
}

/// Linear light of the open sky for ray traced lighting (rt_lighting.glsl rtRawToLinear on the
/// emitting sky's radiosity units), or null when the map's surface data is missing.
pub fn skyLight(w: *const world.World, scale: f32, overbright: f32) ?[3]f32 {
    if (!w.rt.sky_known) return null;
    return rawToLinear(w.rt.sky_raw, scale, overbright);
}

/// The sky's light for the remaster's lighting (stage, probes, path tracer): the original
/// emitting sky when the map's surface data is known, else the sky box's calibrated radiance.
/// The sky box's own hue (a teal sea sky, a green night) is not the light the map was lit with.
pub fn skyFor(w: *world.World) [3]f32 {
    const overbright = std.math.pow(f32, 2, @floatFromInt(std.math.clamp(cvars.mapOverBrightBits.integer, 0, 8)));
    if (skyLight(w, @max(cvars.vkPtLightScale.value, 0), overbright)) |value| return value;
    return world.skyRadiance(w);
}

/// The open sky's light in radiosity units, when the map's surface data is known.
pub fn skyRaw(w: *const world.World) ?[3]f32 {
    return if (w.rt.sky_known) w.rt.sky_raw else null;
}

pub fn rawToLinear(raw: [3]f32, scale: f32, overbright: f32) [3]f32 {
    var v: [3]f32 = undefined;
    for (0..3) |k| v[k] = @min(raw[k] / 255.0 * scale, 1.0) * overbright;
    const peak = @max(v[0], @max(v[1], v[2]));
    if (peak > 1.0) {
        const factor = (1.0 + 0.25 * (1.0 - @exp(-(peak - 1.0)))) / peak;
        for (&v) |*channel| channel.* *= factor;
    }
    for (&v) |*channel| channel.* = std.math.pow(f32, @max(channel.*, 0), 2.2);
    return v;
}

var tlas: c.VkAccelerationStructureKHR = null;
var tlas_buffer: vk.Buffer = .{};
var tlas_scratch: vk.Buffer = .{};
var instance_buffers: [vk.frames_in_flight]vk.Buffer = .{ .{}, .{} };
var scratch: vk.Buffer = .{};
var scratch_size: u64 = 0;
var ready = false;

/// The world's map lights for ray traced lighting (rt_lighting.glsl), or null without any.
pub fn mapLightData(w: *const world.World) ?struct { lights: u64, cells: u64, origin: [3]f32, dims: [3]u32, ambient: f32 } {
    const state = &w.rt;
    if (state.light_count == 0 or state.light_cells.address == 0) return null;
    return .{ .lights = state.lights.address, .cells = state.light_cells.address, .origin = state.cell_origin, .dims = state.cell_dims, .ambient = state.ambient };
}

pub fn enabled() bool {
    return ready and cvars.vkRayTracing.integer != 0;
}

fn alignUp(value: u64, alignment: u64) u64 {
    return (value + alignment - 1) / alignment * alignment;
}

fn asAddress(handle: c.VkAccelerationStructureKHR) u64 {
    const info = std.mem.zeroInit(c.VkAccelerationStructureDeviceAddressInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_DEVICE_ADDRESS_INFO_KHR,
        .accelerationStructure = handle,
    });
    return vk.d.GetAccelerationStructureDeviceAddressKHR.?(vk.s.device, &info);
}

fn createStructure(kind: c.VkAccelerationStructureTypeKHR, size: u64, out_buffer: *vk.Buffer) c.VkAccelerationStructureKHR {
    out_buffer.* = vk.createBuffer(size, c.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_STORAGE_BIT_KHR, vk.device_flags);
    const info = std.mem.zeroInit(c.VkAccelerationStructureCreateInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_CREATE_INFO_KHR,
        .buffer = out_buffer.buffer,
        .size = size,
        .type = kind,
    });
    var handle: c.VkAccelerationStructureKHR = null;
    vk.must(vk.d.CreateAccelerationStructureKHR.?(vk.s.device, &info, null, &handle), "vkCreateAccelerationStructureKHR");
    return handle;
}

fn scratchAddress(size: u64) u64 {
    if (size + vk.as_scratch_alignment > scratch_size) {
        // Persistent memory is bump allocated: a grown scratch keeps the old one until shutdown.
        const was_content = vk.content_arena;
        vk.content_arena = false;
        scratch = vk.createBuffer(size + vk.as_scratch_alignment, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vk.device_flags);
        vk.content_arena = was_content;
        scratch_size = size + vk.as_scratch_alignment;
    }
    return alignUp(scratch.address, vk.as_scratch_alignment);
}

/// Creates the frame-persistent top-level structure and binds it (set 1, binding 3).
pub fn init() void {
    ready = false;
    if (!vk.ray_tracing) return;
    const geometry = std.mem.zeroInit(c.VkAccelerationStructureGeometryKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
        .geometryType = c.VK_GEOMETRY_TYPE_INSTANCES_KHR,
        .geometry = c.VkAccelerationStructureGeometryDataKHR{ .instances = std.mem.zeroInit(c.VkAccelerationStructureGeometryInstancesDataKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
        }) },
    });
    const build = std.mem.zeroInit(c.VkAccelerationStructureBuildGeometryInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
        .type = c.VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR,
        .flags = c.VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
        .mode = c.VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
        .geometryCount = 1,
        .pGeometries = &geometry,
    });
    var sizes = std.mem.zeroInit(c.VkAccelerationStructureBuildSizesInfoKHR, .{ .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR });
    const count: u32 = max_instances;
    vk.d.GetAccelerationStructureBuildSizesKHR.?(vk.s.device, c.VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, &build, &count, &sizes);
    tlas = createStructure(c.VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR, sizes.accelerationStructureSize, &tlas_buffer);
    tlas_scratch = vk.createBuffer(sizes.buildScratchSize + vk.as_scratch_alignment, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vk.device_flags);
    for (&instance_buffers) |*buffer| {
        buffer.* = vk.createBuffer(max_instances * @sizeOf(Instance), c.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR, vk.host_flags);
    }
    const as_write = std.mem.zeroInit(c.VkWriteDescriptorSetAccelerationStructureKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET_ACCELERATION_STRUCTURE_KHR,
        .accelerationStructureCount = 1,
        .pAccelerationStructures = &tlas,
    });
    const write = std.mem.zeroInit(c.VkWriteDescriptorSet, .{
        .sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
        .pNext = &as_write,
        .dstSet = vk.storage_set,
        .dstBinding = 3,
        .descriptorCount = 1,
        .descriptorType = c.VK_DESCRIPTOR_TYPE_ACCELERATION_STRUCTURE_KHR,
    });
    vk.d.UpdateDescriptorSets.?(vk.s.device, 1, &write, 0, null);
    // An empty build so the structure is valid before the first world exists.
    const cmd = vk.uploadCommands();
    buildTlas(cmd, &.{});
    ready = true;
    common.info("renderer_vulkan: ray tracing tier active (acceleration structures, ray queries)\n", .{});
}

pub fn shutdown() void {
    if (tlas != null) vk.d.DestroyAccelerationStructureKHR.?(vk.s.device, tlas, null);
    tlas = null;
    vk.destroyBuffer(&tlas_buffer);
    vk.destroyBuffer(&tlas_scratch);
    for (&instance_buffers) |*buffer| vk.destroyBuffer(buffer);
    for (0..vk.frames_in_flight) |slot| {
        if (character_blas[slot] != null) vk.d.DestroyAccelerationStructureKHR.?(vk.s.device, character_blas[slot], null);
        character_blas[slot] = null;
        vk.destroyBuffer(&character_blas_buffer[slot]);
        vk.destroyBuffer(&character_vertices[slot]);
    }
    vk.destroyBuffer(&character_scratch);
    character_ready = false;
    vk.destroyBuffer(&scratch);
    scratch_size = 0;
    ready = false;
}

pub fn destroyWorld(w: *WorldRt) void {
    for ([_][]ModelAs{ w.models, w.alpha_models }) |list| {
        for (list) |*model| {
            if (model.handle != null) vk.d.DestroyAccelerationStructureKHR.?(vk.s.device, model.handle, null);
            vk.destroyBuffer(&model.buffer);
        }
        if (list.len > 0) common.gpa.free(list);
    }
    vk.destroyBuffer(&w.indices);
    vk.destroyBuffer(&w.tri_surface);
    vk.destroyBuffer(&w.materials);
    vk.destroyBuffer(&w.lights);
    vk.destroyBuffer(&w.light_cells);
    w.* = .{};
}

const Traceable = enum { no, solid, alpha_tested };

/// Surfaces that block rays: drawn, not sky, not liquid, not blended. Alpha-tested ones (leaves,
/// grates, fences) block where their texture is solid.
fn traceable(surface: *const world.Surface) Traceable {
    if (surface.num_indexes < 3 or surface.kind == .flare) return .no;
    const shader = surface.shader;
    if (shader.is_sky or surface.liquid != .none) return .no;
    if (shader.surface_flags & (c.SURF_NODRAW | c.SURF_SKY) != 0) return .no;
    const stages = shader.stagesSlice();
    if (stages.len == 0 or stages[0].blended) return .no;
    if (stages[0].alpha_func != .none) return if (shader.sort <= shader_mod.Sort.see_through) .alpha_tested else .no;
    if (shader.sort > shader_mod.Sort.@"opaque") return .no;
    return .solid;
}

fn materialOf(surface: *const world.Surface) Material {
    var out: Material = .{ .albedo = 0, .lightmap = 0, .emissive = 0, .flags = 0 };
    var have_albedo = false;
    for (surface.shader.stagesSlice()) |*stage| {
        for (&stage.bundles) |*bundle| {
            const first = bundle.images[0] orelse continue;
            if (bundle.is_lightmap) {
                if (out.lightmap == 0) out.lightmap = first.texture.slot + 1;
            } else if (!have_albedo) {
                out.albedo = first.texture.slot;
                out.emissive = @import("image.zig").material(first).emissive;
                // Bit 1: alpha tested; bits 2-3: the test (shader.AlphaFunc gt0, lt128, ge128).
                if (stage.alpha_func != .none) out.flags = 2 | (@as(u32, @intFromEnum(stage.alpha_func)) << 2);
                have_albedo = true;
            }
        }
    }
    if (!have_albedo) out.albedo = @import("image.zig").white.texture.slot;
    return out;
}

/// Builds a world's bottom-level structures once it is fully resident.
fn ensureWorld(cmd: c.VkCommandBuffer, w: *world.World) bool {
    const state = &w.rt;
    if (state.built) return true;
    if (state.failed or w.status != .ready or w.bmodels.len == 0 or w.vertex_buffer.address == 0) return false;
    const a = common.gpa;
    var indices: std.ArrayList(u32) = .empty;
    defer indices.deinit(a);
    var tri_surface: std.ArrayList(u32) = .empty;
    defer tri_surface.deinit(a);
    const materials = a.alloc(Material, w.surfaces.len) catch return false;
    defer a.free(materials);
    var untextured: u32 = 0;
    for (w.surfaces, 0..) |*surface, index| {
        materials[index] = materialOf(surface);
        if (traceable(surface) != .no and materials[index].albedo == @import("image.zig").white.texture.slot) {
            if (untextured < 6) common.developer("dk3 vulkan rt: untextured traced surface {d} shader={s} stages={d}\n", .{ index, std.mem.sliceTo(&surface.shader.name, 0), surface.shader.stagesSlice().len });
            untextured += 1;
        }
    }
    if (untextured > 0) common.developer("dk3 vulkan rt: map={s} untextured traced surfaces={d}\n", .{ w.nameSlice(), untextured });
    state.models = a.alloc(ModelAs, w.bmodels.len) catch return false;
    for (state.models) |*model| model.* = .{};
    state.alpha_models = a.alloc(ModelAs, w.bmodels.len) catch return false;
    for (state.alpha_models) |*model| model.* = .{};
    for (w.bmodels, 0..) |bmodel, model_index| {
        for ([_]Traceable{ .solid, .alpha_tested }) |kind| {
            const first: u32 = @intCast(tri_surface.items.len);
            for (bmodel.first_surface..bmodel.first_surface + bmodel.num_surfaces) |surface_index| {
                if (surface_index >= w.surfaces.len) break;
                const surface = &w.surfaces[surface_index];
                if (traceable(surface) != kind) continue;
                const triangles = surface.num_indexes / 3;
                indices.appendSlice(a, w.indices.items[surface.first_index..][0 .. triangles * 3]) catch return false;
                tri_surface.appendNTimes(a, @intCast(surface_index), triangles) catch return false;
            }
            const target = if (kind == .solid) &state.models[model_index] else &state.alpha_models[model_index];
            target.first_triangle = first;
            target.triangles = @as(u32, @intCast(tri_surface.items.len)) - first;
        }
    }
    if (tri_surface.items.len == 0) {
        state.failed = true;
        return false;
    }
    state.triangles = @intCast(tri_surface.items.len);
    const input = c.VK_BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT_KHR;
    state.indices = vk.staticBuffer(std.mem.sliceAsBytes(indices.items), input);
    state.tri_surface = vk.staticBuffer(std.mem.sliceAsBytes(tri_surface.items), 0);
    state.materials = vk.staticBuffer(std.mem.sliceAsBytes(materials), 0);
    buildLights(w);
    vk.flushUploads();
    const vertex_count: u32 = @intCast(w.vertices.items.len);
    for ([_][]ModelAs{ state.models, state.alpha_models }, 0..) |list, list_index| for (list) |*model| {
        if (model.triangles == 0) continue;
        const triangles = std.mem.zeroInit(c.VkAccelerationStructureGeometryTrianglesDataKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
            .vertexFormat = c.VK_FORMAT_R32G32B32_SFLOAT,
            .vertexData = c.VkDeviceOrHostAddressConstKHR{ .deviceAddress = w.vertex_buffer.address },
            .vertexStride = @sizeOf(@import("scene.zig").Vertex),
            .maxVertex = vertex_count - 1,
            .indexType = c.VK_INDEX_TYPE_UINT32,
            .indexData = c.VkDeviceOrHostAddressConstKHR{ .deviceAddress = state.indices.address + @as(u64, model.first_triangle) * 12 },
        });
        const geometry = std.mem.zeroInit(c.VkAccelerationStructureGeometryKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
            .geometryType = c.VK_GEOMETRY_TYPE_TRIANGLES_KHR,
            .geometry = c.VkAccelerationStructureGeometryDataKHR{ .triangles = triangles },
            // Alpha-tested geometry stays non-opaque: ray queries see its candidates.
            .flags = @as(c.VkGeometryFlagsKHR, if (list_index == 0) c.VK_GEOMETRY_OPAQUE_BIT_KHR else 0),
        });
        var build = std.mem.zeroInit(c.VkAccelerationStructureBuildGeometryInfoKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
            .type = c.VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR,
            .flags = c.VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
            .mode = c.VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
            .geometryCount = 1,
            .pGeometries = &geometry,
        });
        var sizes = std.mem.zeroInit(c.VkAccelerationStructureBuildSizesInfoKHR, .{ .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR });
        vk.d.GetAccelerationStructureBuildSizesKHR.?(vk.s.device, c.VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, &build, &model.triangles, &sizes);
        model.handle = createStructure(c.VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR, sizes.accelerationStructureSize, &model.buffer);
        build.dstAccelerationStructure = model.handle;
        build.scratchData = c.VkDeviceOrHostAddressKHR{ .deviceAddress = scratchAddress(sizes.buildScratchSize) };
        const range = c.VkAccelerationStructureBuildRangeInfoKHR{ .primitiveCount = model.triangles, .primitiveOffset = 0, .firstVertex = 0, .transformOffset = 0 };
        const ranges = [_]*const c.VkAccelerationStructureBuildRangeInfoKHR{&range};
        vk.d.CmdBuildAccelerationStructuresKHR.?(cmd, 1, &build, @ptrCast(&ranges));
        // The next build reuses the scratch buffer.
        vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR | c.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR);
        model.address = asAddress(model.handle);
    };
    state.built = true;
    common.developer("renderer_vulkan: world ray tracing structures: {d} triangles in {d} models\n", .{ state.triangles, w.bmodels.len });
    return true;
}

fn buildTlas(cmd: c.VkCommandBuffer, instances: []const Instance) void {
    const buffer = &instance_buffers[vk.frame_index];
    if (instances.len > 0) @memcpy(buffer.mapped.?[0 .. instances.len * @sizeOf(Instance)], std.mem.sliceAsBytes(instances));
    const geometry = std.mem.zeroInit(c.VkAccelerationStructureGeometryKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
        .geometryType = c.VK_GEOMETRY_TYPE_INSTANCES_KHR,
        .geometry = c.VkAccelerationStructureGeometryDataKHR{ .instances = std.mem.zeroInit(c.VkAccelerationStructureGeometryInstancesDataKHR, .{
            .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_INSTANCES_DATA_KHR,
            .data = c.VkDeviceOrHostAddressConstKHR{ .deviceAddress = buffer.address },
        }) },
    });
    const build = std.mem.zeroInit(c.VkAccelerationStructureBuildGeometryInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
        .type = c.VK_ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL_KHR,
        .flags = c.VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT_KHR,
        .mode = c.VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
        .dstAccelerationStructure = tlas,
        .geometryCount = 1,
        .pGeometries = &geometry,
        .scratchData = c.VkDeviceOrHostAddressKHR{ .deviceAddress = alignUp(tlas_scratch.address, vk.as_scratch_alignment) },
    });
    const range = c.VkAccelerationStructureBuildRangeInfoKHR{ .primitiveCount = @intCast(instances.len), .primitiveOffset = 0, .firstVertex = 0, .transformOffset = 0 };
    const ranges = [_]*const c.VkAccelerationStructureBuildRangeInfoKHR{&range};
    // Earlier ray queries (this or the previous frame) must finish before the rebuild.
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR | c.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR | c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR);
    vk.d.CmdBuildAccelerationStructuresKHR.?(cmd, 1, &build, @ptrCast(&ranges));
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR);
}

/// Instance masks: world geometry answers every ray; characters only shadow rays (they have
/// no entries in the hit tables, so rtTrace, which reads materials, skips them).
const mask_world: u32 = 0x01;
const mask_characters: u32 = 0x02;

/// A character mesh for this frame's character structure: what stage.vert draws (scene.Mesh)
/// and the entity transform.
pub const CharacterMesh = struct { mesh: @import("scene.zig").Mesh, model: [3][4]f32 };

const max_character_corners: u32 = 3 * 300_000;
var character_vertices: [vk.frames_in_flight]vk.Buffer = .{ .{}, .{} };
var character_blas: [vk.frames_in_flight]c.VkAccelerationStructureKHR = .{ null, null };
var character_blas_buffer: [vk.frames_in_flight]vk.Buffer = .{ .{}, .{} };
var character_scratch: vk.Buffer = .{};
var character_ready = false;

fn createCharacterResources() bool {
    if (character_ready) return true;
    const was_content = vk.content_arena;
    vk.content_arena = false;
    defer vk.content_arena = was_content;
    const triangles = std.mem.zeroInit(c.VkAccelerationStructureGeometryTrianglesDataKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
        .vertexFormat = c.VK_FORMAT_R32G32B32_SFLOAT,
        .vertexStride = 12,
        .maxVertex = max_character_corners - 1,
        .indexType = c.VK_INDEX_TYPE_NONE_KHR,
    });
    const geometry = std.mem.zeroInit(c.VkAccelerationStructureGeometryKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
        .geometryType = c.VK_GEOMETRY_TYPE_TRIANGLES_KHR,
        .geometry = c.VkAccelerationStructureGeometryDataKHR{ .triangles = triangles },
        .flags = c.VK_GEOMETRY_OPAQUE_BIT_KHR,
    });
    const build = std.mem.zeroInit(c.VkAccelerationStructureBuildGeometryInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
        .type = c.VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR,
        .flags = c.VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR,
        .mode = c.VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
        .geometryCount = 1,
        .pGeometries = &geometry,
    });
    var sizes = std.mem.zeroInit(c.VkAccelerationStructureBuildSizesInfoKHR, .{ .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_SIZES_INFO_KHR });
    const max_triangles: u32 = max_character_corners / 3;
    vk.d.GetAccelerationStructureBuildSizesKHR.?(vk.s.device, c.VK_ACCELERATION_STRUCTURE_BUILD_TYPE_DEVICE_KHR, &build, &max_triangles, &sizes);
    for (0..vk.frames_in_flight) |slot| {
        character_vertices[slot] = vk.createBuffer(@as(u64, max_character_corners) * 12, @as(c.VkBufferUsageFlags, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT) | vk.rtInputUsage(), vk.device_flags);
        character_blas[slot] = createStructure(c.VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR, sizes.accelerationStructureSize, &character_blas_buffer[slot]);
    }
    character_scratch = vk.createBuffer(sizes.buildScratchSize + vk.as_scratch_alignment, c.VK_BUFFER_USAGE_STORAGE_BUFFER_BIT, vk.device_flags);
    character_ready = true;
    return true;
}

/// Skins this frame's character meshes into world space and builds their structure; returns
/// its instance, or null without characters.
fn prepareCharacters(cmd: c.VkCommandBuffer, meshes: []const CharacterMesh) ?Instance {
    if (meshes.len == 0 or !createCharacterResources()) return null;
    const slot = vk.frame_index;
    const out = &character_vertices[slot];
    var corners: u32 = 0;
    const SkinParams = extern struct {
        vertices: u64,
        indices: u64,
        frame_b: u64,
        extra: u64,
        info: [4]u32,
        misc: [4]f32,
        model: [3][4]f32,
    };
    // Earlier ray queries may still read last use of this slot's buffer and structure.
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT | c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_SHADER_READ_BIT | c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT);
    for (meshes) |entry| {
        const mesh = entry.mesh;
        if (mesh.count == 0 or corners + mesh.count > max_character_corners) continue;
        const params: SkinParams = .{
            .vertices = mesh.vertices,
            .indices = mesh.indices,
            .frame_b = mesh.frame_b,
            .extra = mesh.extra,
            .info = .{ mesh.kind, mesh.count, corners, 0 },
            .misc = .{ mesh.backlerp, 0, 0, 0 },
            .model = entry.model,
        };
        const space = vk.frame().stream.alloc(@sizeOf(SkinParams), 16) orelse break;
        @memcpy(space.bytes[0..@sizeOf(SkinParams)], std.mem.asBytes(&params));
        vk.dispatch(cmd, "rt_skin.comp", @import("post.zig").Push{
            .buffer0 = space.address,
            .buffer1 = out.address,
            .size = .{ mesh.count, 0, 0, 0 },
        }, mesh.count, 1, 1, .{ 64, 1, 1 });
        corners += mesh.count;
    }
    if (corners < 3) return null;
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR | c.VK_ACCESS_2_SHADER_READ_BIT);
    const triangles = std.mem.zeroInit(c.VkAccelerationStructureGeometryTrianglesDataKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_TRIANGLES_DATA_KHR,
        .vertexFormat = c.VK_FORMAT_R32G32B32_SFLOAT,
        .vertexData = c.VkDeviceOrHostAddressConstKHR{ .deviceAddress = out.address },
        .vertexStride = 12,
        .maxVertex = corners - 1,
        .indexType = c.VK_INDEX_TYPE_NONE_KHR,
    });
    const geometry = std.mem.zeroInit(c.VkAccelerationStructureGeometryKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_GEOMETRY_KHR,
        .geometryType = c.VK_GEOMETRY_TYPE_TRIANGLES_KHR,
        .geometry = c.VkAccelerationStructureGeometryDataKHR{ .triangles = triangles },
        .flags = c.VK_GEOMETRY_OPAQUE_BIT_KHR,
    });
    const build = std.mem.zeroInit(c.VkAccelerationStructureBuildGeometryInfoKHR, .{
        .sType = c.VK_STRUCTURE_TYPE_ACCELERATION_STRUCTURE_BUILD_GEOMETRY_INFO_KHR,
        .type = c.VK_ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL_KHR,
        .flags = c.VK_BUILD_ACCELERATION_STRUCTURE_PREFER_FAST_BUILD_BIT_KHR,
        .mode = c.VK_BUILD_ACCELERATION_STRUCTURE_MODE_BUILD_KHR,
        .dstAccelerationStructure = character_blas[slot],
        .geometryCount = 1,
        .pGeometries = &geometry,
        .scratchData = c.VkDeviceOrHostAddressKHR{ .deviceAddress = alignUp(character_scratch.address, vk.as_scratch_alignment) },
    });
    const range = c.VkAccelerationStructureBuildRangeInfoKHR{ .primitiveCount = corners / 3, .primitiveOffset = 0, .firstVertex = 0, .transformOffset = 0 };
    const ranges = [_]*const c.VkAccelerationStructureBuildRangeInfoKHR{&range};
    vk.d.CmdBuildAccelerationStructuresKHR.?(cmd, 1, &build, @ptrCast(&ranges));
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_WRITE_BIT_KHR, c.VK_PIPELINE_STAGE_2_ACCELERATION_STRUCTURE_BUILD_BIT_KHR, c.VK_ACCESS_2_ACCELERATION_STRUCTURE_READ_BIT_KHR);
    return .{
        .transform = .{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 },
        .custom_and_mask = @as(u32, mask_characters) << 24,
        .sbt_and_flags = @as(u32, c.VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR) << 24,
        .reference = asAddress(character_blas[slot]),
    };
}

fn instanceFor(model: *const ModelAs, transform: [12]f32) Instance {
    return .{
        .transform = transform,
        .custom_and_mask = (model.first_triangle & 0xffffff) | (@as(u32, mask_world) << 24),
        // Quake 3 front faces wind clockwise; flip facing so rayQuery front faces match.
        .sbt_and_flags = @as(u32, c.VK_GEOMETRY_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT_KHR | c.VK_GEOMETRY_INSTANCE_TRIANGLE_FLIP_FACING_BIT_KHR) << 24,
        .reference = model.address,
    };
}

/// Rebuilds the top-level structure for a world camera; returns the hit table for its shaders.
/// Runs outside rendering.
/// Measures, for a slice of light cells, how many rays from each cell reach each of its lights
/// (light_visibility.comp); rolling, so doors that open or close are picked up again.
fn refreshVisibility(cmd: c.VkCommandBuffer, owner: *world.World, table_address: u64) void {
    const state = &owner.rt;
    if (state.light_count == 0 or state.light_cells.address == 0) return;
    const total = state.cell_dims[0] * state.cell_dims[1] * state.cell_dims[2];
    if (total == 0) return;
    if (state.visibility_cursor >= total) state.visibility_cursor = 0;
    const first = state.visibility_cursor;
    const slice = @min(visibility_cells_per_frame, total - first);
    const Params = extern struct { table: u64, lights: u64, cells: u64, unused: u64, origin: [4]f32, dims: [4]u32 };
    const params: Params = .{
        .table = table_address,
        .lights = state.lights.address,
        .cells = state.light_cells.address,
        .unused = 0,
        .origin = .{ state.cell_origin[0], state.cell_origin[1], state.cell_origin[2], light_cell_size },
        .dims = .{ state.cell_dims[0], state.cell_dims[1], state.cell_dims[2], first },
    };
    const space = vk.frame().stream.alloc(@sizeOf(Params), 16) orelse return;
    @memcpy(space.bytes[0..@sizeOf(Params)], std.mem.asBytes(&params));
    // Earlier frames' shading may still read the counts being rewritten; a count is one word.
    vk.dispatch(cmd, "light_visibility.comp", @import("post.zig").Push{ .buffer0 = space.address }, lights_per_cell * visibility_rays, slice, 1, .{ visibility_rays, 1, 1 });
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT | c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, c.VK_ACCESS_2_SHADER_READ_BIT);
    state.visibility_cursor = first + slice;
}

/// r_vkDebugView 19: prints the centre pixel's four shadow-tested lights about once a second
/// (copied from the cell buffer a frame or two late).
fn reportProbe(cmd: c.VkCommandBuffer, owner: *world.World) void {
    const state = &owner.rt;
    if (state.light_cells.buffer == null or state.probe_offset == 0) return;
    if (probe_host.buffer == null) {
        const was_content = vk.content_arena;
        vk.content_arena = false;
        probe_host = vk.createBuffer(probe_words * 4, c.VK_BUFFER_USAGE_TRANSFER_DST_BIT, vk.host_flags);
        vk.content_arena = was_content;
    }
    probe_frame += 1;
    if (probe_frame % 10 == 0) if (probe_host.mapped) |bytes| {
        const words: [*]const u32 = @ptrCast(@alignCast(bytes));
        if (words[0] != 0x5052424F) common.developer("dk3 rt probe: no sample yet ({x})\n", .{words[0]});
        if (words[0] == 0x5052424F) {
            const f = struct {
                fn at(w: [*]const u32, i: usize) f32 {
                    return @bitCast(w[i]);
                }
            };
            common.developer("dk3 rt probe: pos={d:.0},{d:.0},{d:.0} n={d:.2},{d:.2},{d:.2} viewPos={d:.0},{d:.0},{d:.0} vertex n.z={d:.2} front={d}\n", .{ f.at(words, 40), f.at(words, 41), f.at(words, 42), f.at(words, 43), f.at(words, 44), f.at(words, 45), f.at(words, 46), f.at(words, 47), f.at(words, 48), f.at(words, 49), words[50] });
            const lights: [*]const MapLight = @ptrCast(@alignCast(state.debug_lights.ptr));
            for (0..4) |j| {
                const index = words[1 + j * 8];
                if (f.at(words, 2 + j * 8) <= 0) continue;
                const light = if (index < state.debug_lights.len) lights[index] else std.mem.zeroes(MapLight);
                common.developer("  light {d} kind={d:.0} at {d:.0},{d:.0},{d:.0} raw={d:.1} dist={d:.0} blocked={d:.0} hit={d:.2}\n", .{ index, light.kind, light.origin[0], light.origin[1], light.origin[2], f.at(words, 2 + j * 8), f.at(words, 3 + j * 8), f.at(words, 4 + j * 8), f.at(words, 5 + j * 8) });
            }
        }
    };
    const region = c.VkBufferCopy{ .srcOffset = state.probe_offset, .dstOffset = 0, .size = probe_words * 4 };
    vk.memoryBarrier(cmd, c.VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT, c.VK_ACCESS_2_SHADER_WRITE_BIT, c.VK_PIPELINE_STAGE_2_COPY_BIT, c.VK_ACCESS_2_TRANSFER_READ_BIT);
    vk.d.CmdCopyBuffer.?(cmd, state.light_cells.buffer, probe_host.buffer, 1, &region);
}

pub fn prepare(cmd: c.VkCommandBuffer, owner: *world.World, entities: []const @import("scene.zig").Entity, characters: []const CharacterMesh) ?u64 {
    if (!enabled()) return null;
    if (!ensureWorld(cmd, owner)) return null;
    const state = &owner.rt;
    var instances: [max_instances]Instance = undefined;
    var count: usize = 0;
    const identity = [12]f32{ 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 };
    for ([_]*const ModelAs{ &state.models[0], &state.alpha_models[0] }) |model| if (model.address != 0) {
        instances[count] = instanceFor(model, identity);
        count += 1;
    };
    // Moving brush models (doors, lifts, platforms) at their entity transforms.
    for (entities) |*entity| {
        if (count == max_instances) break;
        const e = &entity.e;
        if (e.reType != c.RT_MODEL) continue;
        const ref = world.residentInline(e.hModel) orelse continue;
        if (ref.world != owner) continue;
        const index = (@intFromPtr(ref.model) - @intFromPtr(owner.bmodels.ptr)) / @sizeOf(world.BModel);
        if (index == 0 or index >= state.models.len) continue;
        if (state.models[index].address == 0 and state.alpha_models[index].address == 0) continue;
        var transform: [12]f32 = undefined;
        for (0..3) |row| {
            transform[row * 4 + 0] = e.axis[0][row];
            transform[row * 4 + 1] = e.axis[1][row];
            transform[row * 4 + 2] = e.axis[2][row];
            transform[row * 4 + 3] = e.origin[row];
        }
        for ([_]*const ModelAs{ &state.models[index], &state.alpha_models[index] }) |model| {
            if (model.address == 0 or count == max_instances) continue;
            instances[count] = instanceFor(model, transform);
            count += 1;
        }
    }
    if (count < max_instances) if (prepareCharacters(cmd, characters)) |instance| {
        instances[count] = instance;
        count += 1;
    };
    buildTlas(cmd, instances[0..count]);
    const table: Table = .{
        .vertices = owner.vertex_buffer.address,
        .indices = state.indices.address,
        .tri_surface = state.tri_surface.address,
        .materials = state.materials.address,
    };
    const space = vk.frame().stream.alloc(@sizeOf(Table), 16) orelse return null;
    @memcpy(space.bytes[0..@sizeOf(Table)], std.mem.asBytes(&table));
    if (cvars.vkLighting.integer != 0 and cvars.vkLightVisibility.integer != 0) refreshVisibility(cmd, owner, space.address);
    if (cvars.vkDebugView.integer == 19) reportProbe(cmd, owner);
    return space.address;
}
