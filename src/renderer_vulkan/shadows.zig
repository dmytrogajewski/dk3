// SPDX-License-Identifier: GPL-2.0-or-later
//! Remaster model shadows. The nearest shadow-casting models each get a 256x256 tile in a
//! depth atlas, rendered with an orthographic camera along the model's dominant light-grid
//! direction (the light that the baked radiosity says reaches it). World materials then darken
//! the baked light where a caster occludes it, with PCF and a fade along the shadow's reach.
//! Replaces the OpenGL stencil shadow volumes, which cannot follow GPU-skinned models.
const std = @import("std");
const window = @import("window.zig");

pub const tile_size: u32 = 256;
pub const tiles_per_row: u32 = window.shadow_atlas_size / tile_size;
/// Casters fill the top rows of the atlas; the rain map takes the bottom half.
pub const max_casters: u32 = 24;
pub const max_distance: f32 = 1400;

/// Rain occlusion map: a top-down orthographic depth image of the world around the eye in the
/// lower-left quarter of the atlas. Weather particles vanish under the stored surface and only
/// surfaces open to the sky get wet or snowed on.
pub const rain_map_size: u32 = 1024;
pub const rain_half_extent: f32 = 2560;

const Vec3 = [3]f32;
const Mat4 = [4][4]f32;

/// Mirrors stage.frag `ShadowCaster`.
pub const Caster = extern struct {
    world_to_tile: [16]f32, // column-major world -> tile clip (x, y in [-1, 1], z in [0, 1])
    tile: [4]f32, // atlas uv origin x, y, uv size, depth bias
    sphere: [4]f32, // receiver bound: centre, radius
    info: [4]f32, // strength, unused, texel uv, unused
};

pub const Camera = struct {
    view_matrix: Mat4,
    projection: Mat4,
    x: i32,
    y: i32,
    caster: Caster,
};

pub const RainMap = struct {
    view_matrix: Mat4,
    projection: Mat4,
    x: i32,
    y: i32,
    centre: [2]f32,
    world_to_tile: [16]f32, // column-major world -> map clip
    tile: [4]f32, // atlas uv origin x, y, uv size, enabled
    params: [4]f32, // depth per world unit, z top, texel uv, half extent
};

fn dot(a: Vec3, b: Vec3) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn cross(a: Vec3, b: Vec3) Vec3 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}
fn normalize(a: Vec3) Vec3 {
    const l = @sqrt(dot(a, a));
    return if (l > 1e-6) .{ a[0] / l, a[1] / l, a[2] / l } else .{ 0, 0, 1 };
}
fn madd(a: Vec3, s: f32, b: Vec3) Vec3 {
    return .{ a[0] + s * b[0], a[1] + s * b[1], a[2] + s * b[2] };
}

/// Light direction (towards the light) kept steep enough that shadows stay short.
pub fn castDirection(to_light: Vec3) Vec3 {
    var l = normalize(to_light);
    if (l[2] < 0.45) l = normalize(.{ l[0], l[1], l[2] + (0.45 - l[2]) * 1.6 });
    return l;
}

fn clipMatrix(view_matrix: Mat4, projection: Mat4) [16]f32 {
    var clip: Mat4 = undefined;
    for (0..4) |row| for (0..4) |column| {
        var sum: f32 = 0;
        for (0..4) |k| sum += projection[row][k] * view_matrix[k][column];
        clip[row][column] = sum;
    };
    var column_major: [16]f32 = undefined;
    for (0..4) |row| for (0..4) |column| {
        column_major[column * 4 + row] = clip[row][column];
    };
    return column_major;
}

/// Camera of the rain occlusion map: straight down from `z_top` over the eye, covering
/// `rain_half_extent` each way and the depth range down to `z_bottom`. The centre snaps to the
/// map's texel grid so the stored heights do not swim as the eye moves.
pub fn rainCamera(eye: Vec3, z_top: f32, z_bottom: f32) RainMap {
    const texel_world = 2 * rain_half_extent / @as(f32, @floatFromInt(rain_map_size));
    const centre: [2]f32 = .{ @floor(eye[0] / texel_world) * texel_world, @floor(eye[1] / texel_world) * texel_world };
    const far = @max(z_top - z_bottom, 16);
    // Rows as in scene.viewMatrix with forward -z, left +y and up +x.
    const cam_eye: Vec3 = .{ centre[0], centre[1], z_top };
    const left: Vec3 = .{ 0, 1, 0 };
    const up: Vec3 = .{ 1, 0, 0 };
    const forward: Vec3 = .{ 0, 0, -1 };
    const view_matrix: Mat4 = .{
        .{ -left[0], -left[1], -left[2], dot(cam_eye, left) },
        .{ up[0], up[1], up[2], -dot(cam_eye, up) },
        .{ -forward[0], -forward[1], -forward[2], dot(cam_eye, forward) },
        .{ 0, 0, 0, 1 },
    };
    const projection: Mat4 = .{
        .{ 1 / rain_half_extent, 0, 0, 0 },
        .{ 0, 1 / rain_half_extent, 0, 0 },
        .{ 0, 0, -1 / far, 0 },
        .{ 0, 0, 0, 1 },
    };
    const atlas: f32 = @floatFromInt(window.shadow_atlas_size);
    const uv_size = @as(f32, @floatFromInt(rain_map_size)) / atlas;
    return .{
        .view_matrix = view_matrix,
        .projection = projection,
        .x = 0,
        .y = @intCast(window.shadow_atlas_size - rain_map_size),
        .centre = centre,
        .world_to_tile = clipMatrix(view_matrix, projection),
        .tile = .{ 0, 1 - uv_size, uv_size, 1 },
        .params = .{ 1 / far, z_top, 1 / atlas, rain_half_extent },
    };
}

/// Orthographic tile camera for a caster bounded by (centre, radius) lit from `to_light`.
pub fn camera(slot: u32, centre: Vec3, radius: f32, to_light: Vec3) Camera {
    const l = castDirection(to_light);
    const forward: Vec3 = .{ -l[0], -l[1], -l[2] };
    const helper: Vec3 = if (@abs(forward[2]) > 0.9) .{ 1, 0, 0 } else .{ 0, 0, 1 };
    const left = normalize(cross(helper, forward));
    const up = cross(forward, left);
    const reach = std.math.clamp(radius * 3, 96, 420);
    const eye = madd(centre, radius * 2, l);
    const far = radius * 3 + reach;
    const extent = radius * 1.15;
    // Rows as in scene.viewMatrix: x = -left, y = up, z = -forward.
    const view_matrix: Mat4 = .{
        .{ -left[0], -left[1], -left[2], dot(eye, left) },
        .{ up[0], up[1], up[2], -dot(eye, up) },
        .{ -forward[0], -forward[1], -forward[2], dot(eye, forward) },
        .{ 0, 0, 0, 1 },
    };
    const projection: Mat4 = .{
        .{ 1 / extent, 0, 0, 0 },
        .{ 0, 1 / extent, 0, 0 },
        .{ 0, 0, -1 / far, 0 },
        .{ 0, 0, 0, 1 },
    };
    const column_major = clipMatrix(view_matrix, projection);
    const tx = slot % tiles_per_row;
    const ty = slot / tiles_per_row;
    const atlas: f32 = @floatFromInt(window.shadow_atlas_size);
    const uv_size = @as(f32, @floatFromInt(tile_size)) / atlas;
    const texel_world = 2 * extent / @as(f32, @floatFromInt(tile_size));
    const reach_centre = madd(centre, -reach * 0.5, l);
    return .{
        .view_matrix = view_matrix,
        .projection = projection,
        .x = @intCast(tx * tile_size),
        .y = @intCast(ty * tile_size),
        .caster = .{
            .world_to_tile = column_major,
            .tile = .{ @as(f32, @floatFromInt(tx)) * uv_size, @as(f32, @floatFromInt(ty)) * uv_size, uv_size, texel_world * 2.5 / far },
            .sphere = .{ reach_centre[0], reach_centre[1], reach_centre[2], radius + reach * 0.5 },
            .info = .{ 1, reach / far, 1 / atlas, 0 },
        },
    };
}
