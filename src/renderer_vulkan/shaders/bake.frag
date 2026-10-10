#version 460
// SPDX-License-Identifier: GPL-2.0-or-later
// Directional lightmap bake: the luminance-weighted direction to the map lights that reach
// this lightmap texel (shadow rays against the world), rgb = direction * 0.5 + 0.5,
// a = directionality (how much of the light comes from one direction).
#extension GL_EXT_ray_query : require
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require
#extension GL_EXT_nonuniform_qualifier : require

layout(set = 0, binding = 0) uniform sampler2D textures[];
#include "rt_common.glsl"

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer BakeParams {
    uvec2 vertices;
    uvec2 indices;
    uvec2 lights;
    uvec2 cells;
    vec4 cellOrigin;
    uvec4 cellDims;
};
layout(push_constant) uniform Push { uvec2 params; } push;

layout(location = 0) in vec3 worldPos;
layout(location = 1) in vec3 worldNormal;
layout(location = 0) out vec4 outColor;

void main() {
    BakeParams p = BakeParams(push.params);
    vec3 n = normalize(worldNormal);
    vec3 sum = vec3(0.0);
    float total = 0.0;
    if (p.cellDims.w > 0u) {
        ivec3 cell = clamp(ivec3(floor((worldPos - p.cellOrigin.xyz) / p.cellOrigin.w)), ivec3(0), ivec3(p.cellDims.xyz) - 1);
        uint base = uint((cell.z * int(p.cellDims.y) + cell.y) * int(p.cellDims.x) + cell.x) * RT_CELL_STRIDE;
        RtWords list = RtWords(p.cells);
        RtFloats lights = RtFloats(p.lights);
        uint count = min(list.v[base], RT_LIGHTS_PER_CELL);
        vec3 origin = worldPos + n * 1.0;
        for (uint k = 0u; k < count; ++k) {
            uint index = list.v[base + 1u + k];
            vec3 lp = rtLightPoint(lights, index, vec2(0.5), origin);
            vec3 d = lp - origin;
            float dist = length(d);
            vec3 l = d / max(dist, 1e-3);
            float contribution = dot(rtLightRaw(lights, index, origin, n), vec3(0.2126, 0.7152, 0.0722));
            if (contribution <= 0.0 || rtOccluded(uvec2(0u), origin, l, dist - 4.0)) continue;
            sum += l * contribution;
            total += contribution;
        }
    }
    if (total <= 0.0) {
        outColor = vec4(n * 0.5 + 0.5, 0.0);
        return;
    }
    float directionality = clamp(length(sum) / total, 0.0, 1.0);
    outColor = vec4(normalize(sum) * 0.5 + 0.5, directionality);
}
