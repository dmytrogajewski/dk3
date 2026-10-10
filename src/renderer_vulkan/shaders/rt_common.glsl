// SPDX-License-Identifier: GPL-2.0-or-later
// Ray tracing tier shared code (rt.zig): the top-level structure and hit shading from the
// per-world tables. Needs GL_EXT_ray_query, buffer references and `textures[]` (set 0).
layout(set = 1, binding = 3) uniform accelerationStructureEXT tlas;

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer RtTable {
    uvec2 vertices;    // world Vertex array (12 words each)
    uvec2 indices;     // traced triangles (3 words each)
    uvec2 triSurface;  // triangle -> surface
    uvec2 materials;   // surface -> (albedo slot, lightmap slot + 1, emissive bits, flags)
};
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer RtMaterials { uvec4 v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer RtWords { uint v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer RtFloats { float v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) buffer RtWordsRw { uint v[]; };

struct RtHit {
    bool hit;
    bool front;
    float t;
    vec3 normal;    // geometric, facing the ray origin
    vec3 albedo;    // linear
    vec3 radiance;  // albedo x lightmap + emissive: light leaving the surface
    float emissive; // material emissive scale
};

vec3 rtToLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

// Map lights (rt.zig `MapLight`, RT_LIGHT_STRIDE floats each after RT_LIGHT_HEADER style values):
//   0 origin, 3 intensity, 4 colour, 7 style, 8 axis_u, 11 kind, 12 axis_v, 15 limit,
//   16 direction
// Kinds follow the original radiosity (rt.zig `Kind`).
const uint RT_LIGHT_STRIDE = 20u;
const uint RT_LIGHT_HEADER = 256u;
const uint RT_LIGHT_POINT = 0u;
const uint RT_LIGHT_SURFACE = 1u;
const uint RT_LIGHT_SUN = 3u;

uint rtLightOffset(uint index) { return RT_LIGHT_HEADER + index * RT_LIGHT_STRIDE; }
vec3 rtLightOrigin(RtFloats lights, uint index) {
    uint o = rtLightOffset(index);
    return vec3(lights.v[o], lights.v[o + 1u], lights.v[o + 2u]);
}
uint rtLightKind(RtFloats lights, uint index) { return uint(lights.v[rtLightOffset(index) + 11u]); }

// Where shadow rays aim on a light: its centre, an area light's point picked by `jitter` (0-1
// each, so temporal accumulation turns hard shadows soft), or far towards the sun.
// How far across an area light shadow rays may aim (1 = its whole rectangle).
float rtLightSpread = 1.0;
vec3 rtLightPoint(RtFloats lights, uint index, vec2 jitter, vec3 from) {
    uint o = rtLightOffset(index);
    vec3 origin = vec3(lights.v[o], lights.v[o + 1u], lights.v[o + 2u]);
    uint kind = uint(lights.v[o + 11u]);
    if (kind == RT_LIGHT_SUN) return from + vec3(lights.v[o + 16u], lights.v[o + 17u], lights.v[o + 18u]) * 16384.0;
    if (kind != RT_LIGHT_SURFACE) return origin;
    vec3 u = vec3(lights.v[o + 8u], lights.v[o + 9u], lights.v[o + 10u]);
    vec3 v = vec3(lights.v[o + 12u], lights.v[o + 13u], lights.v[o + 14u]);
    return origin + (u * (jitter.x * 2.0 - 1.0) + v * (jitter.y * 2.0 - 1.0)) * rtLightSpread;
}

// One map light at `pos` in the radiosity's units (255 = a fully lit lightmap texel), before
// visibility. `n` is the receiver normal; vec3(0) for a point in the air (no receiver cosine).
// The light style's current value scales it (switched-off lights give 0).
vec3 rtLightRaw(RtFloats lights, uint index, vec3 pos, vec3 n) {
    uint o = rtLightOffset(index);
    vec3 origin = vec3(lights.v[o], lights.v[o + 1u], lights.v[o + 2u]);
    float intensity = lights.v[o + 3u];
    vec3 color = vec3(lights.v[o + 4u], lights.v[o + 5u], lights.v[o + 6u]) * lights.v[uint(lights.v[o + 7u])];
    uint kind = uint(lights.v[o + 11u]);
    float limit = lights.v[o + 15u];
    vec3 axis = vec3(lights.v[o + 16u], lights.v[o + 17u], lights.v[o + 18u]);
    bool surface = n != vec3(0.0);
    if (kind == RT_LIGHT_SUN) {
        float cosine = surface ? dot(n, axis) : 1.0;
        return cosine > 0.0 ? color * intensity * cosine : vec3(0.0);
    }
    vec3 d = origin - pos;
    float dist = length(d);
    vec3 l = d / max(dist, 1e-3);
    float cosine = surface ? dot(n, l) : 1.0;
    if (cosine <= 0.0) return vec3(0.0);
    if (kind == RT_LIGHT_SURFACE) {
        if (dist >= limit) return vec3(0.0);
        // Emits from its front only; the area term keeps it finite right at the face.
        float emit = dot(axis, -l);
        if (emit <= 0.0) return vec3(0.0);
        vec3 u = vec3(lights.v[o + 8u], lights.v[o + 9u], lights.v[o + 10u]);
        vec3 v = vec3(lights.v[o + 12u], lights.v[o + 13u], lights.v[o + 14u]);
        float area = 4.0 * length(u) * length(v);
        float fade = 1.0 - smoothstep(0.75, 1.0, dist / limit);
        return color * intensity * cosine * emit / (dist * dist + area * 0.3183) * fade;
    }
    if (dist >= intensity) return vec3(0.0);
    float amount = (intensity - dist) * cosine;
    // "cap": the most this light adds (measured on the shipped lightmaps).
    if (limit > 0.0) amount = min(amount, limit);
    return color * amount;
}

// Map light cells (rt.zig `lights_per_cell`): a count, then up to this many light indices.
const uint RT_LIGHTS_PER_CELL = 63u;
const uint RT_CELL_STRIDE = RT_LIGHTS_PER_CELL + 1u;
// After the lists (total cells x RT_CELL_STRIDE words), the same layout holds how many of
// RT_VISIBILITY_RAYS rays from the cell reached each listed light (light_visibility.comp).
const uint RT_VISIBILITY_RAYS = 32u;
uint rtVisibility(RtWords list, uvec3 cellDims, uint slotWord) {
    return list.v[cellDims.x * cellDims.y * cellDims.z * RT_CELL_STRIDE + slotWord];
}

// Alpha test of a candidate hit on an alpha-tested surface (foliage): the texture's alpha at
// the hit against the stage's test (rt.zig materialOf flags). Without a table everything passes.
bool rtAlphaPass(uvec2 tableAddress, rayQueryEXT rq) {
    if (tableAddress == uvec2(0u)) return false;
    // Characters are opaque geometry; only world instances carry alpha-tested candidates.
    RtTable table = RtTable(tableAddress);
    uint tri = uint(rayQueryGetIntersectionInstanceCustomIndexEXT(rq, false)) + uint(rayQueryGetIntersectionPrimitiveIndexEXT(rq, false));
    uvec4 m = RtMaterials(table.materials).v[RtWords(table.triSurface).v[tri]];
    if ((m.w & 2u) == 0u) return true;
    vec2 bary = rayQueryGetIntersectionBarycentricsEXT(rq, false);
    vec3 w = vec3(1.0 - bary.x - bary.y, bary.x, bary.y);
    RtWords indices = RtWords(table.indices);
    RtFloats vertices = RtFloats(table.vertices);
    vec2 st = vec2(0.0);
    for (uint k = 0u; k < 3u; ++k) {
        uint o = indices.v[tri * 3u + k] * 12u;
        st += w[k] * vec2(vertices.v[o + 3u], vertices.v[o + 4u]);
    }
    float alpha = textureLod(textures[nonuniformEXT(m.x)], st, 0.0).a;
    uint func = (m.w >> 2u) & 3u;
    return func == 1u ? alpha > 0.0 : (func == 2u ? alpha < 0.5 : alpha >= 0.5);
}

// Distance to the first world hit along a ray (alpha-tested), or `tmax` when it escapes.
float rtHitDistance(uvec2 tableAddress, vec3 origin, vec3 dir, float tmax) {
    rayQueryEXT rq;
    rayQueryInitializeEXT(rq, tlas, gl_RayFlagsNoneEXT, 0x01u, origin, 0.0, dir, tmax);
    while (rayQueryProceedEXT(rq)) {
        if (rayQueryGetIntersectionTypeEXT(rq, false) == gl_RayQueryCandidateIntersectionTriangleEXT && rtAlphaPass(tableAddress, rq))
            rayQueryConfirmIntersectionEXT(rq);
    }
    if (rayQueryGetIntersectionTypeEXT(rq, true) == gl_RayQueryCommittedIntersectionNoneEXT) return tmax;
    return rayQueryGetIntersectionTEXT(rq, true);
}

bool rtOccluded(uvec2 tableAddress, vec3 origin, vec3 dir, float tmax) {
    if (tmax <= 0.0) return false;
    rayQueryEXT rq;
    rayQueryInitializeEXT(rq, tlas, gl_RayFlagsTerminateOnFirstHitEXT, 0xFFu, origin, 0.0, dir, tmax);
    while (rayQueryProceedEXT(rq)) {
        if (rayQueryGetIntersectionTypeEXT(rq, false) == gl_RayQueryCandidateIntersectionTriangleEXT && rtAlphaPass(tableAddress, rq))
            rayQueryConfirmIntersectionEXT(rq);
    }
    return rayQueryGetIntersectionTypeEXT(rq, true) != gl_RayQueryCommittedIntersectionNoneEXT;
}

RtHit rtTrace(uvec2 tableAddress, vec3 origin, vec3 dir, float tmax, float lod) {
    RtHit h;
    h.hit = false;
    h.front = true;
    h.t = tmax;
    h.normal = -dir;
    h.albedo = vec3(0.0);
    h.radiance = vec3(0.0);
    h.emissive = 0.0;
    rayQueryEXT rq;
    // World geometry only (mask 1): characters have no hit-table entries (rt.zig masks).
    rayQueryInitializeEXT(rq, tlas, gl_RayFlagsNoneEXT, 0x01u, origin, 0.0, dir, tmax);
    while (rayQueryProceedEXT(rq)) {
        if (rayQueryGetIntersectionTypeEXT(rq, false) == gl_RayQueryCandidateIntersectionTriangleEXT && rtAlphaPass(tableAddress, rq))
            rayQueryConfirmIntersectionEXT(rq);
    }
    if (rayQueryGetIntersectionTypeEXT(rq, true) == gl_RayQueryCommittedIntersectionNoneEXT) return h;
    h.hit = true;
    h.front = rayQueryGetIntersectionFrontFaceEXT(rq, true);
    h.t = rayQueryGetIntersectionTEXT(rq, true);
    RtTable table = RtTable(tableAddress);
    uint tri = uint(rayQueryGetIntersectionInstanceCustomIndexEXT(rq, true)) + uint(rayQueryGetIntersectionPrimitiveIndexEXT(rq, true));
    vec2 bary = rayQueryGetIntersectionBarycentricsEXT(rq, true);
    vec3 w = vec3(1.0 - bary.x - bary.y, bary.x, bary.y);
    RtWords indices = RtWords(table.indices);
    RtFloats vertices = RtFloats(table.vertices);
    vec2 st = vec2(0.0), lm = vec2(0.0);
    vec3 p[3];
    for (uint k = 0u; k < 3u; ++k) {
        uint o = indices.v[tri * 3u + k] * 12u;
        p[k] = vec3(vertices.v[o], vertices.v[o + 1u], vertices.v[o + 2u]);
        st += w[k] * vec2(vertices.v[o + 3u], vertices.v[o + 4u]);
        lm += w[k] * vec2(vertices.v[o + 5u], vertices.v[o + 6u]);
    }
    vec3 n = cross(p[1] - p[0], p[2] - p[0]);
    n = dot(n, n) > 0.0 ? normalize(n) : -dir;
    h.normal = dot(n, dir) > 0.0 ? -n : n;
    uvec4 m = RtMaterials(table.materials).v[RtWords(table.triSurface).v[tri]];
    h.albedo = rtToLinear(textureLod(textures[nonuniformEXT(m.x)], st, lod).rgb);
    vec3 light = m.y != 0u ? textureLod(textures[nonuniformEXT(m.y - 1u)], lm, 0.0).rgb : vec3(1.0);
    h.emissive = uintBitsToFloat(m.z);
    h.radiance = h.albedo * (light + h.emissive);
    return h;
}
