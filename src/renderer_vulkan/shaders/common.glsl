// SPDX-License-Identifier: GPL-2.0-or-later
// Draw record shared by every Q3 material stage (layout mirrors scene.zig `Record`).
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require
#extension GL_EXT_nonuniform_qualifier : require

layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Record {
    mat4 clip;
    vec4 modelView[3];
    vec4 model[3];
    vec4 viewOrigin;   // eye in model space; w = shader time in seconds
    vec4 constColor;
    vec4 ambient;      // w = identityLight
    vec4 directed;
    vec4 lightDir;     // model space; w = portal range
    vec4 tcmod[8];     // per op: [0] = (type, a, b, c), [1] = (d, e, f, g)
    vec4 deform[6];    // per deform: [0] = (type, base, amplitude, phase), [1] = (frequency, spread, func, extra)
    vec4 tcGenVector[2];
    vec4 fog;          // start, end, enabled, unused
    vec4 fogColor;
    uvec4 mode;        // vertex kind, rgbGen, alphaGen, tcGen
    uvec4 mode2;       // texture slot, second slot (+1, 0 none), flags, alpha function
    uvec4 counts;      // tcMods, deforms, dynamic lights, unused
    uvec2 vertices;
    uvec2 indices;
    uvec2 frameB;
    uvec2 extra;
    vec4 misc;         // backlerp, depth hack, unused, unused
    vec4 clipPlane;    // world-space portal plane: keep dot(p, xyz) - w >= 0
    vec4 material;     // roughness, metalness, bump strength, emissive
    vec4 material2;    // specular strength, liquid kind, exposure hint, unused
    uvec4 maps;        // normal map slot + 1, specular map slot + 1, light grid volume + 1, flags2
    vec4 grid0;        // light grid origin, w = grid present
    vec4 grid1;        // 1 / (grid size * grid bounds) per axis
    vec4 worldLight;   // entity light direction in world space
    vec4 viewPos;      // eye position in world space
    uvec2 lights;
    uvec2 view;        // ViewData of the camera (0 = none)
};

// Per-camera data shared by every record of a view (volume.zig `ViewData`).
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer ViewData {
    vec4 rect;         // view x, y, width, height in framebuffer pixels
    vec4 froxel;       // near, 1 / log(far / near), far, enabled
    uvec4 slots;       // integrated froxel volume slot
    vec4 jitter;
    uvec4 weather;     // weather box count
    vec4 weatherParams; // wetness strength, snow strength, time, unused
    vec4 boxes[16];    // per box: (mins, kind 0 rain / 1 snow), (maxs, 0)
    uvec4 clusters;    // enabled, grid x, y, z
    vec4 clusterParams; // near, 1 / log(far / near), lights per cluster
    uvec4 clusterList; // xy = cluster list address
    uvec4 shadows;     // caster count, shadow atlas slot
    uvec4 shadowList;  // xy = ShadowCasters address
    uvec4 rt;          // ray tracing: 1 dynamic-light shadows, 2 reflections
    uvec4 rtTable;     // xy = RtTable address
    uvec4 ddgiSlots;   // DDGI probe textures (sampled volume slots)
    uvec4 ddgiSlots2;  // DDGI distance and squared distance volumes
    ivec4 ddgiOrigin;  // first world probe index, w = enabled
    ivec4 ddgiDims;    // probes per axis, w = spacing (float bits)
    mat4 rainToTile;   // world -> rain occlusion map clip (shadows.zig rainCamera)
    vec4 rain;         // atlas uv origin, uv size, enabled
    vec4 rainParams;   // depth per world unit, z top, texel uv, half extent
    vec4 fogParams;    // depth the sky column samples the froxel volume at, eye liquid
    uvec4 rtLights;    // ray traced lighting: lights address, cell lists address
    vec4 rtCells;      // cell grid origin, cell size
    uvec4 rtCellDims;  // cells per axis, w = ray traced lighting enabled
    vec4 rtLightScale; // radiosity scale, overbright
    vec4 rtSky;        // sky light: w = 2 radiosity units, w = 1 linear radiance, 0 none
};

struct ShadowCaster {
    mat4 worldToTile;
    vec4 tile;         // atlas uv origin, uv size, depth bias
    vec4 sphere;       // receiver bound
    vec4 info;         // strength, reach in depth units, texel uv
};
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer ShadowCasters { ShadowCaster v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer ClusterList { uint v[]; };

// Procedural weather volume (weather.zig `Params`), mesh kind 3.
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer WeatherParams {
    vec4 mins;         // w = kind (0 rain, 1 snow)
    vec4 maxs;         // w = time
    vec4 velocity;     // w = seed
    vec4 eye;          // w = mode (0 drops / flakes, 1 splashes)
    vec4 shape;        // exposure (s), world size of a pixel per unit of distance, base alpha, count
    vec4 tiles;        // first tile x, y, tiles per row, particles per tile
    vec4 grid0;        // light grid origin, w = colour volume slot + 1
    vec4 grid1;        // light grid scale, w = direction volume slot + 1
    vec4 sky;          // sky radiance (linear), w = intensity (r_vkWeatherDensity)
};
const float WEATHER_TILE = 512.0;

float hash11(float n) { return fract(sin(n * 12.9898 + 78.233) * 43758.5453); }
vec4 hash4(vec3 p) {
    vec4 q = vec4(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)),
                  dot(p, vec3(113.5, 271.9, 124.6)), dot(p, vec3(271.3, 117.7, 315.2)));
    return fract(sin(q) * 43758.5453);
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float valueNoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}
// Where rain collects in puddles (shared by wet surfaces and splashes: drops hitting a puddle
// only ripple it).
float puddleNoise(vec2 xy) {
    return smoothstep(0.52, 0.68, valueNoise(xy / 170.0) * 0.7 + valueNoise(xy / 47.0) * 0.3);
}
// Henyey-Greenstein phase times 4 pi (1 = isotropic).
float phaseHG4pi(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * g * cosTheta, 1e-4), 1.5);
}

layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer Floats { float v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer Uints { uint v[]; };
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Lights { vec4 v[]; };

layout(push_constant) uniform Push { uvec2 record; } push;

layout(set = 0, binding = 0) uniform sampler2D textures[];

const uint FLAG_SECOND_LIGHTMAP = 1u;   // second texture is a lightmap: dynamic lights add to it
const uint FLAG_FIRST_LIGHTMAP = 2u;    // the stage texture is a lightmap
const uint FLAG_FOG = 4u;
const uint FLAG_CLIP = 8u;
const uint FLAG_LINEAR = 16u;          // remaster HDR target: linear light
const uint FLAG_OVERLAY_OPAQUE = 32u;  // unblended stage into the premultiplied UI overlay
const uint FLAG_PBR_WORLD = 64u;       // lightmapped surface shaded as a PBR material
const uint FLAG_PBR_MODEL = 128u;      // light-grid lit model shaded per pixel
const uint FLAG_LIQUID = 256u;         // water, slime or lava surface (material2.y = kind)
const uint FLAG_VOLUME = 512u;         // froxel volumetric fog (fogColor.w = blend mode)
const uint FLAG_RT = 1024u;            // the view's world is ray traced (ViewData.rt)
const uint FLAG_DYNAMIC = 2048u;       // opaque model stage: HDR alpha 0 marks moving pixels for TAA

// Height of the highest world surface over `xy` in the rain occlusion map (the shadow atlas
// slot `slot`), or far below everything off the map or without a map.
float rainSurface(ViewData view, uint slot, vec2 xy) {
    if (view.rain.w < 0.5) return -1e30;
    vec4 p = view.rainToTile * vec4(xy, view.rainParams.y, 1.0);
    if (any(greaterThan(abs(p.xy), vec2(1.0)))) return -1e30;
    vec2 uv = view.rain.xy + vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5) * view.rain.z;
    float texel = view.rainParams.z;
    uv = clamp(uv, view.rain.xy + texel, view.rain.xy + view.rain.z - texel);
    float stored = textureLod(textures[nonuniformEXT(slot)], uv, 0.0).r;
    return view.rainParams.y - stored / view.rainParams.x;
}

// 1 where `pos` is open to the sky, 0 under a roof, soft over a 3x3 texel footprint.
float rainExposure(ViewData view, uint slot, vec3 pos) {
    if (view.rain.w < 0.5) return 1.0;
    vec4 p = view.rainToTile * vec4(pos, 1.0);
    if (any(greaterThan(abs(p.xy), vec2(1.0)))) return 1.0;
    vec2 uv = view.rain.xy + vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5) * view.rain.z;
    float texel = view.rainParams.z;
    vec2 lo = view.rain.xy + texel, hi = view.rain.xy + view.rain.z - texel;
    // Six units of slack: a texel spans five world units, and slopes store their high side.
    float bias = 6.0 * view.rainParams.x;
    float open = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float stored = textureLod(textures[nonuniformEXT(slot)], clamp(uv + vec2(x, y) * texel, lo, hi), 0.0).r;
            if (p.z - bias <= stored) open += 1.0;
        }
    }
    return open / 9.0;
}

layout(set = 1, binding = 1) uniform sampler3D volumes[];

vec3 toLinear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
