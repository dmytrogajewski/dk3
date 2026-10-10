// SPDX-License-Identifier: GPL-2.0-or-later
// Path tracing mode (pathtrace.zig) shared parameters.
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer PtParams {
    mat4 inverseCurrent;  // unjittered clip -> world
    mat4 previous;        // world -> previous clip
    vec4 origin;          // eye, w = frame index
    vec4 forward;         // w = tan(fov_x / 2)
    vec4 left;            // w = tan(fov_y / 2)
    vec4 up;              // w = light scale
    vec4 rect;            // view rect in target pixels
    vec4 jitter;          // NDC jitter xy, near, far
    vec4 sky;             // miss radiance, w = overbright scale
    vec4 cells;           // light cell origin xyz, cell size
    uvec4 cellDims;       // light cells per axis, w = map light count
    uvec4 counts;         // dynamic lights, history valid, unused
    uvec2 table;          // RtTable
    uvec2 lights;         // map lights (two vec4 each)
    uvec2 lightCells;     // per cell: count, indices
    uvec2 dynamicLights;  // view dlights (two vec4 each)
    uvec2 viewData;       // ViewData (froxel fog for the composite)
    uvec2 pad;
    uvec4 ddgiSlots;      // probe field (ddgi.zig), for lightmap-free bounce light
    uvec4 ddgiSlots2;
    ivec4 ddgiOrigin;     // w = field present
    ivec4 ddgiDims;
    vec4 rtSky;           // sky radiance, w = ray traced lighting (no lightmaps)
};

float ptLinearDepth(float d, float n, float f) { return n * f / max(f - d * (f - n), 1e-3); }

uint ptHash(uint x) {
    x ^= x >> 16; x *= 0x7feb352du; x ^= x >> 15; x *= 0x846ca68bu; x ^= x >> 16;
    return x;
}
float ptRandom(inout uint state) {
    state = ptHash(state);
    return float(state >> 8) / 16777216.0;
}
