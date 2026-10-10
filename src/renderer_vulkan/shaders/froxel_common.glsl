// SPDX-License-Identifier: GPL-2.0-or-later
// Froxel volumetric fog shared declarations (volume.zig `Params`).
#include "post_common.glsl"

layout(set = 1, binding = 2) uniform image3D froxels[];

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Params {
    vec4 origin;    // eye, w = time
    vec4 forward;   // w = tan(fov_x / 2)
    vec4 left;      // w = tan(fov_y / 2)
    vec4 up;        // w = near
    vec4 slices;    // log(far / near), far, base density, scatter strength
    vec4 fog;       // authored fog colour (display), w = authored density
    vec4 fogRange;  // authored start, end, enabled
    vec4 grid0;     // light grid origin
    vec4 grid1;     // light grid scale
    uvec4 counts;   // dlights, grid colour slot + 1, grid direction slot + 1
    mat4 rainToTile; // world -> rain occlusion map clip (shadows.zig rainCamera)
    vec4 rainTile;  // atlas uv origin, uv size, enabled
    vec4 rainParams; // depth per unit, z top, texel uv, half extent
    vec4 rainInfo;  // atlas slot, box count, intensity
    vec4 rainBoxes[16]; // (mins, kind 0 rain / 1 snow), (maxs, 0)
    uvec2 rtTable;  // ray traced shafts: hit table (froxel_inject_rt.comp)
    uvec2 rtLights; // map lights
    uvec2 rtCellLists; // map light cells
    uvec2 rtPad;
    vec4 rtCells;   // cell grid origin, cell size
    uvec4 rtCellDims;
    vec4 rtLightScale; // radiosity scale, overbright, ambient
    vec4 rtSky;     // sky radiance, enabled
};
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer LightList { vec4 v[]; };

// Boundary of slice `s` (0 at the eye, exponential from `near` to `far`).
float sliceDistance(Params p, float s) {
    if (s <= 0.0) return 0.0;
    return p.up.w * exp(p.slices.x * s / float(pc.size.z));
}
