#version 460
// SPDX-License-Identifier: GPL-2.0-or-later
// Directional lightmap bake (bake.zig): world triangles rasterised in lightmap space.
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer BakeParams {
    uvec2 vertices;   // world Vertex array
    uvec2 indices;    // this page's triangles
    uvec2 lights;     // map lights
    uvec2 cells;      // light cells
    vec4 cellOrigin;  // xyz, w = cell size
    uvec4 cellDims;   // w = light count
};
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer Words { uint v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer Reals { float v[]; };
layout(push_constant) uniform Push { uvec2 params; } push;

layout(location = 0) out vec3 worldPos;
layout(location = 1) out vec3 worldNormal;

void main() {
    BakeParams p = BakeParams(push.params);
    uint index = Words(p.indices).v[gl_VertexIndex];
    Reals v = Reals(p.vertices);
    uint o = index * 12u;
    worldPos = vec3(v.v[o], v.v[o + 1u], v.v[o + 2u]);
    worldNormal = vec3(v.v[o + 7u], v.v[o + 8u], v.v[o + 9u]);
    vec2 lm = vec2(v.v[o + 5u], v.v[o + 6u]);
    gl_Position = vec4(lm * 2.0 - 1.0, 0.0, 1.0);
}
