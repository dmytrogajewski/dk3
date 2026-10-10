#version 460
// SPDX-License-Identifier: GPL-2.0-or-later
// One Q3 material stage. Classic mode reproduces renderergl1: texture (optionally modulated by
// a collapsed lightmap stage), alpha test, dynamic lights added to lightmaps and dk3 linear
// distance fog. Remaster mode works in linear HDR light; lightmapped world surfaces and
// grid-lit models become PBR materials (GGX) with normal maps or procedural bump.
#ifdef RAY_QUERY
#extension GL_EXT_ray_query : require
#endif
#include "common.glsl"
#include "ddgi_common.glsl"
#include "ddgi_sample.glsl"
#ifdef RAY_QUERY
#include "rt_common.glsl"
#include "rt_lighting.glsl"
#endif

layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv0;
layout(location = 2) in vec2 uv1;
layout(location = 3) in float eyeDepth;
layout(location = 4) in vec3 worldPos;
layout(location = 5) in vec3 worldNormal;
layout(location = 0) out vec4 outColor;

const float PI = 3.14159265;

// The projected 16x16 dlight image of renderergl1 (R_CreateDlightImage, ProjectDlightTexture):
// brightness 4000 / texel distance squared, cut below 75, height modulation along z.
float classicDlight(vec3 d, float radius) {
    float texels = length(d.xy) / radius * 8.0;
    float b0 = texels > 0.0 ? min(4000.0 / (texels * texels), 255.0) : 255.0;
    b0 = b0 < 75.0 ? 0.0 : b0 / 255.0;
    float z = abs(d.z);
    float modulate = z > radius ? 0.0 : (z < radius * 0.5 ? 1.0 : 2.0 * (radius - z) / radius);
    return b0 * modulate;
}

vec3 dynamicLight(Record r) {
    vec3 sum = vec3(0.0);
    Lights lights = Lights(r.lights);
    for (uint k = 0u; k < r.counts.z; ++k) {
        vec4 a = lights.v[k * 2u], b = lights.v[k * 2u + 1u];
        sum += b.rgb * classicDlight(a.xyz - worldPos, a.w);
    }
    return sum;
}

float luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Bump mapping without tangents: Mikkelsen's surface gradient from a height derived from the
// albedo's luminance, sampled one screen pixel apart.
vec3 proceduralBump(vec3 n, uint slot, vec2 uv, float strength) {
    vec2 dx = dFdx(uv), dy = dFdy(uv);
    // Magnified textures turn the one-pixel differences into per-texel steps (bilinear
    // gradients are constant inside a texel): fade the bump out once a texel spans pixels.
    vec2 size = vec2(textureSize(textures[nonuniformEXT(slot)], 0));
    float texels = max(length(dx * size), length(dy * size));
    strength *= smoothstep(0.25, 0.9, texels);
    if (strength <= 0.0) return n;
    float h0 = luminance(textureGrad(textures[nonuniformEXT(slot)], uv, dx, dy).rgb);
    float hx = luminance(textureGrad(textures[nonuniformEXT(slot)], uv + dx, dx, dy).rgb);
    float hy = luminance(textureGrad(textures[nonuniformEXT(slot)], uv + dy, dx, dy).rgb);
    vec3 sx = dFdx(worldPos), sy = dFdy(worldPos);
    vec3 r1 = cross(sy, n), r2 = cross(n, sx);
    float det = dot(sx, r1);
    if (abs(det) < 1e-8) return n;
    vec3 grad = sign(det) * ((hx - h0) * r1 + (hy - h0) * r2);
    return normalize(abs(det) * n - strength * 3.0 * grad);
}

// Tangent-space normal map with a cotangent frame from derivatives (Schüler).
vec3 normalMapped(vec3 n, uint slot, vec2 uv, float strength) {
    vec3 t = texture(textures[nonuniformEXT(slot)], uv).xyz * 2.0 - 1.0;
    t.xy *= strength;
    vec3 dp1 = dFdx(worldPos), dp2 = dFdy(worldPos);
    vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
    vec3 dp2perp = cross(dp2, n), dp1perp = cross(n, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-12));
    // Q3 texture t grows downwards: flip the bitangent.
    return normalize(mat3(T * invmax, -B * invmax, n) * t);
}

float distributionGGX(float ndoth, float a) {
    float a2 = a * a;
    float d = ndoth * ndoth * (a2 - 1.0) + 1.0;
    return a2 / (PI * d * d + 1e-6);
}
float visibilitySmith(float ndotv, float ndotl, float a) {
    float k = a * 0.5;
    return 0.25 / ((ndotv * (1.0 - k) + k) * (ndotl * (1.0 - k) + k) + 1e-4);
}
// Schlick's Fresnel toward `grazing` instead of white: rough and weakly specular materials
// barely brighten at grazing angles (Fdez-Agüera's roughness-aware form). Without the limit
// a black, rough surface turns white along every distant silhouette and grazing floor.
vec3 fresnelSchlick(float cosine, vec3 f0, float grazing) { return f0 + max(vec3(grazing) - f0, vec3(0.0)) * pow(1.0 - cosine, 5.0); }
float grazingReflectance(float rough, float specularStrength, float metal) {
    return mix((1.0 - rough) * clamp(specularStrength, 0.0, 1.0), 1.0, metal);
}

vec3 shadeLight(vec3 n, vec3 v, vec3 l, vec3 radiance, vec3 albedo, vec3 f0, float metal, float rough, float grazing) {
    float ndotl = max(dot(n, l), 0.0);
    if (ndotl <= 0.0) return vec3(0.0);
    vec3 h = normalize(v + l);
    float ndotv = max(dot(n, v), 1e-3);
    float a = max(rough * rough, 0.02);
    vec3 f = fresnelSchlick(max(dot(h, v), 0.0), f0, grazing);
    vec3 specular = distributionGGX(max(dot(n, h), 0.0), a) * visibilitySmith(ndotv, ndotl, a) * f;
    vec3 diffuse = (1.0 - f) * (1.0 - metal) * albedo / PI;
    return (diffuse + specular) * radiance * ndotl;
}

// Remaster dynamic lights: classic radius as range, smooth inverse-square falloff.
#ifdef RAY_QUERY
bool rtEnabled(Record r, uint bit) {
    if ((r.mode2.z & FLAG_RT) == 0u || r.view == uvec2(0u)) return false;
    return (ViewData(r.view).rt.x & bit) != 0u;
}

// Low-discrepancy 2D sample `k` for this pixel and frame: the R2 sequence advanced once per
// frame from a per-pixel offset, so the temporal average converges smoothly instead of chasing
// fresh white noise every frame.
vec2 rtSequence(ViewData view, uint k) {
    float frame = view.fogParams.z * 4.0 + float(k);
    vec2 offset = vec2(hash12(floor(gl_FragCoord.xy)), hash12(floor(gl_FragCoord.yx) + 17.0));
    return fract(offset + frame * vec2(0.7548776662, 0.5698402910));
}

// Ray traced lighting (r_vkLighting 1): map lights instead of the baked lightmaps.
bool rtLightingEnabled(Record r) {
    if ((r.mode2.z & FLAG_RT) == 0u || r.view == uvec2(0u)) return false;
    return ViewData(r.view).rtCellDims.w != 0u;
}

// Direct light from the map lights at the fragment, `shadowRays` exact shadows, plus
// `extraRaw` (the visible sky) in the same radiosity units before the conversion: the original
// lightmaps summed all light first, so partial sky must not be converted on its own.
vec3 rtDirectLight(Record r, vec3 n, vec3 rayOrigin, uint shadowRays, vec3 extraRaw) {
    ViewData view = ViewData(r.view);
    // Area lights: each frame aims shadow rays at a different point of the fixture.
    rtLightJitter = rtSequence(view, 0u);
    vec3 raw = rtMapLightRaw(view.rtTable.xy, view.rtLights.xy, view.rtLights.zw, view.rtCells, view.rtCellDims.xyz, worldPos, n, rayOrigin, shadowRays);
    // World surfaces: worldLight carries an emitting face's own light (rt.zig).
    vec3 own = (r.mode2.z & FLAG_PBR_WORLD) != 0u ? r.worldLight.rgb : vec3(0.0);
    return rtRawToLinear(raw + own + extraRaw + vec3(view.rtLightScale.z), view.rtLightScale.x, view.rtLightScale.y);
}

// The view's sky light (scene.zig): w = 2 radiosity units (summed with the direct light), w = 1
// linear radiance (added after it).
vec3 rtSkyRaw(Record r, float visible) {
    vec4 sky = ViewData(r.view).rtSky;
    return sky.w > 1.5 ? sky.rgb * visible : vec3(0.0);
}
vec3 rtSkyLinear(Record r, float visible) {
    vec4 sky = ViewData(r.view).rtSky;
    return sky.w > 1.5 ? vec3(0.0) : sky.rgb * visible;
}

// Per-pixel sky light and ambient occlusion: four cosine-distributed rays (rtSequence; temporal
// anti-aliasing averages frames). x = fraction that reaches the open sky, y = ambient occlusion
// from geometry within 64 units.
vec2 rtSkyAndOcclusion(Record r, vec3 n, vec3 origin) {
    ViewData view = ViewData(r.view);
    vec3 up = abs(n.z) < 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tx = normalize(cross(up, n)), ty = cross(n, tx);
    float sky = 0.0, open = 0.0;
    for (int k = 0; k < 4; ++k) {
        vec2 u = rtSequence(view, uint(k));
        float r1 = u.x, r2 = u.y;
        float radius = sqrt(r1), phi = 6.2831853 * r2;
        vec3 dir = normalize(tx * radius * cos(phi) + ty * radius * sin(phi) + n * sqrt(max(1.0 - r1, 0.0)));
        float t = rtHitDistance(view.rtTable.xy, origin, dir, 16384.0);
        if (t >= 16384.0) sky += 1.0;
        open += smoothstep(4.0, 64.0, t);
    }
    return vec2(sky, open) * 0.25;
}

// Radiance leaving the first world surface along a ray, or `miss`.
vec3 rtRadiance(Record r, vec3 origin, vec3 dir, float tmax, vec3 miss) {
    RtHit h = rtTrace(ViewData(r.view).rtTable.xy, origin, dir, tmax, 2.0);
    return h.hit ? h.radiance : miss;
}
#endif

vec3 pbrDynamicLights(Record r, vec3 n, vec3 v, vec3 albedo, vec3 f0, float metal, float rough, float grazing) {
    vec3 sum = vec3(0.0);
    Lights lights = Lights(r.lights);
    uint total = r.counts.z;
    // Clustered lights: only the lights binned into this fragment's cluster.
    bool clustered = false;
    uint base = 0u;
    ClusterList list;
    if (total > 0u && r.view != uvec2(0u)) {
        ViewData view = ViewData(r.view);
        if (view.clusters.x != 0u) {
            vec2 suv = clamp((gl_FragCoord.xy - view.rect.xy) / view.rect.zw, 0.0, 0.9999);
            float slice = eyeDepth <= view.clusterParams.x ? 0.0 : log(eyeDepth / view.clusterParams.x) * view.clusterParams.y * float(view.clusters.w);
            uvec3 cell = uvec3(uvec2(suv * vec2(view.clusters.yz)), min(uint(max(slice, 0.0)), view.clusters.w - 1u));
            uint cluster = cell.x + view.clusters.y * (cell.y + view.clusters.z * cell.z);
            list = ClusterList(view.clusterList.xy);
            base = cluster * (uint(view.clusterParams.z) + 1u);
            total = list.v[base];
            clustered = true;
        }
    }
    for (uint i = 0u; i < total; ++i) {
        uint k = clustered ? list.v[base + 1u + i] : i;
        vec4 a = lights.v[k * 2u], b = lights.v[k * 2u + 1u];
        vec3 d = a.xyz - worldPos;
        float dist2 = dot(d, d);
        float range = a.w;
        float window = clamp(1.0 - (dist2 * dist2) / (range * range * range * range), 0.0, 1.0);
        window *= window;
#ifdef RAY_QUERY
        if (window <= 0.0) continue;
        if (rtEnabled(r, 1u)) {
            float dist = sqrt(dist2);
            vec3 l = d / max(dist, 1e-3);
            if (rtOccluded(ViewData(r.view).rtTable.xy, worldPos + n * 0.75 + l * 0.75, l, dist - 8.0)) continue;
        }
#endif
        // Inverse square beyond a quarter of the radius, flat inside it: like the original's
        // projected dlight texture, a light never adds more than its own colour.
        float falloff = window * min(1.0, (range * range * 0.0625) / max(dist2, 1e-4));
        sum += shadeLight(n, v, d * inversesqrt(max(dist2, 1e-4)), toLinear(b.rgb) * falloff * PI, albedo, f0, metal, rough, grazing);
    }
    return sum;
}

vec4 lightGrid(Record r, vec3 p) {
    if (r.maps.z == 0u) return vec4(0.0);
    vec3 uvw = (p - r.grid0.xyz) * r.grid1.xyz;
    return texture(volumes[nonuniformEXT(r.maps.z - 1u)], uvw);
}

float linearDepth(float d, float n, float f) { return n * f / max(f - d * (f - n), 1e-3); }


// Liquids: analytic directional waves, refraction of the scene behind the surface with
// Beer-Lambert absorption, screen-space reflection with a sky/fog fallback, Fresnel, shoreline
// foam for water, a toxic glow for slime and an emissive crust for lava.
vec4 shadeLiquid(Record r, vec4 tex) {
    uint kind = uint(r.material2.y + 0.5);
    float t = r.viewOrigin.w;
    vec3 n0 = normalize(worldNormal);
    if (!gl_FrontFacing) n0 = -n0;
    vec3 up = abs(n0.z) < 0.9 ? vec3(0, 0, 1) : vec3(1, 0, 0);
    vec3 tx = normalize(cross(up, n0)), ty = cross(n0, tx);
    vec2 p = vec2(dot(worldPos, tx), dot(worldPos, ty));
    float speed = kind == 3u ? 0.25 : 1.0;
    vec2 grad = vec2(0.0);
    const vec4 waves[5] = vec4[](vec4(0.83, 0.55, 0.021, 0.090), vec4(-0.31, 0.95, 0.034, 0.060),
                                 vec4(0.97, -0.24, 0.057, 0.035), vec4(-0.70, -0.71, 0.093, 0.022), vec4(0.12, -0.99, 0.141, 0.014));
    for (int k = 0; k < 5; ++k) {
        vec2 dir = waves[k].xy;
        float freq = waves[k].z, amp = waves[k].w * 6.0;
        float phase = dot(dir, p) * freq + t * speed * (1.4 + float(k) * 0.37);
        grad += dir * (amp * freq * cos(phase));
    }
    grad += (vec2(valueNoise(p * 0.08 + t * 0.3 * speed), valueNoise(p.yx * 0.08 - t * 0.27 * speed)) - 0.5) * 0.25;
    vec3 n = normalize(n0 - (grad.x * tx + grad.y * ty) * 0.6);
    vec3 v = normalize(r.viewPos.xyz - worldPos);
    vec3 albedo = tex.rgb;
    if (kind != 3u && dot(normalize(worldNormal), v) < 0.0) {
        // The underside of a liquid surface seen from outside the liquid (the top of a
        // waterfall from below): the volume's own faces already show it.
        if (r.view != uvec2(0u) && ViewData(r.view).fogParams.y < 0.5) discard;
        // Seen from underneath (the eye is in the liquid): the world above shows through the
        // waves with the medium's tint, and grazing angles reflect the medium back (total
        // internal reflection) instead of an opaque lid.
        vec2 screen = gl_FragCoord.xy / vec2(textureSize(textures[nonuniformEXT(r.maps.w - 1u)], 0));
        vec3 above = texture(textures[nonuniformEXT(r.maps.w - 1u)], screen + grad * 0.04).rgb;
        vec3 tint = kind == 2u ? vec3(0.08, 0.3, 0.03) : toLinear(albedo) * 0.6 + vec3(0.0, 0.03, 0.03);
        float grazing = 1.0 - smoothstep(0.1, 0.5, max(dot(n, v), 0.0));
        return vec4(mix(above * mix(vec3(1.0), tint * 2.0, 0.5), tint, 0.3 + 0.7 * grazing), 1.0);
    }
    if (kind == 3u) {
        // Lava: opaque, emissive, with a slowly moving darker crust.
        float crust = smoothstep(0.35, 0.75, valueNoise(p * 0.03 + t * 0.05) * 0.7 + valueNoise(p * 0.11 - t * 0.02) * 0.3);
        vec3 glow = albedo * mix(6.0, 0.6, crust) + vec3(1.5, 0.35, 0.05) * (1.0 - crust) * 2.0;
        return vec4(glow, 1.0);
    }
    float n_plane = r.viewPos.w, f_plane = r.material2.z;
    vec2 size = vec2(textureSize(textures[nonuniformEXT(r.maps.w - 1u)], 0));
    vec2 screen = gl_FragCoord.xy / size;
    float behind = linearDepth(texture(textures[nonuniformEXT(r.counts.w - 1u)], screen).r, n_plane, f_plane);
    float thickness = max(behind - eyeDepth, 0.0);
    vec2 offset = grad * 0.025 * clamp(thickness / 48.0, 0.0, 1.0);
    vec2 refracted_uv = screen + offset;
    // Do not pull in geometry in front of the surface.
    float refracted_depth = linearDepth(texture(textures[nonuniformEXT(r.counts.w - 1u)], refracted_uv).r, n_plane, f_plane);
    if (refracted_depth < eyeDepth) refracted_uv = screen;
    else thickness = max(refracted_depth - eyeDepth, 0.0);
    vec3 below = texture(textures[nonuniformEXT(r.maps.w - 1u)], refracted_uv).rgb;
    vec3 coefficient = kind == 2u ? vec3(0.030, 0.012, 0.045) : vec3(0.020, 0.0085, 0.0065);
    vec3 medium = (kind == 2u ? vec3(0.05, 0.16, 0.02) : mix(vec3(0.02, 0.06, 0.06), albedo * 0.35, 0.5)) * 0.6;
    vec3 transmittance = exp(-coefficient * thickness);
    vec3 refraction = below * transmittance + medium * (1.0 - transmittance);
    // Screen-space reflection along the reflected view ray (world entity: clip = view-projection).
    vec3 rdir = reflect(-v, n);
    vec3 sky = r.fog.z > 0.5 ? toLinear(r.fogColor.rgb) * 0.6 : vec3(0.08, 0.10, 0.12);
    vec3 reflection = sky;
    float step_length = 12.0;
    vec3 ray = worldPos;
    int ssr_steps = 24;
#ifdef RAY_QUERY
    if (rtEnabled(r, 2u)) {
        reflection = rtRadiance(r, worldPos + n0 * 0.5, rdir, 8192.0, sky);
        ssr_steps = 0;
    }
#endif
    for (int k = 0; k < ssr_steps; ++k) {
        ray += rdir * step_length;
        step_length *= 1.18;
        vec4 clip = r.clip * vec4(ray, 1.0);
        if (clip.w <= 0.0) break;
        vec2 suv = vec2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
        if (any(lessThan(suv, vec2(0.0))) || any(greaterThan(suv, vec2(1.0)))) break;
        float scene_depth = linearDepth(texture(textures[nonuniformEXT(r.counts.w - 1u)], suv).r, n_plane, f_plane);
        float ray_depth = clip.w;
        if (ray_depth > scene_depth + 1.0 && ray_depth < scene_depth + step_length * 2.0) {
            vec2 edge = smoothstep(vec2(0.0), vec2(0.08), suv) * smoothstep(vec2(0.0), vec2(0.08), 1.0 - suv);
            reflection = mix(sky, texture(textures[nonuniformEXT(r.maps.w - 1u)], suv).rgb, edge.x * edge.y);
            break;
        }
    }
    float fresnel = 0.02 + 0.98 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
    vec3 color = mix(refraction, reflection, fresnel);
    vec4 grid = lightGrid(r, worldPos);
    if (grid.a > 0.0) {
        vec3 l = normalize(grid.xyz * 2.0 - 1.0);
        vec3 h = normalize(v + l);
        color += vec3(pow(max(dot(n, h), 0.0), 220.0) * 3.0 * grid.a);
    }
    color += pbrDynamicLights(r, n, v, vec3(0.0), vec3(0.02), 0.0, 0.05, 1.0);
    if (kind == 1u) {
        float shore = 1.0 - smoothstep(0.0, 10.0, thickness);
        float foam = smoothstep(0.45, 0.8, valueNoise(p * 0.25 + t * 0.4) + shore * 0.6) * shore;
        color = mix(color, vec3(0.6) * max(toLinear(albedo) + 0.3, vec3(0.3)), foam * 0.7);
    } else if (kind == 2u) {
        color += vec3(0.05, 0.25, 0.02) * (0.5 + 0.5 * sin(t * 1.3 + p.x * 0.02));
    }
    return vec4(color, 1.0);
}

// Rain ripples: rings up to 3 in across in an 8-in cell grid, 0.6-1 s each; up to four
// offset layers switch on with rain intensity (Lagarde). Returns the height gradient.
vec2 rippleGradient(vec2 p, float t, float intensity) {
    vec2 g = vec2(0.0);
    int layers = int(clamp(ceil(intensity * 4.0), 1.0, 4.0));
    for (int k = 0; k < 4; ++k) {
        if (k >= layers) break;
        vec2 q = p / 8.0 + float(k) * vec2(0.37, 0.61);
        vec2 cell = floor(q), f = fract(q);
        float h = hash11(dot(cell, vec2(17.13, 31.71)) + float(k) * 3.1);
        float phase = fract(t * mix(1.0, 1.6, hash11(h * 3.7)) + h);
        vec2 center = vec2(hash11(h * 13.1), hash11(h * 7.7)) * 0.6 + 0.2;
        vec2 d = f - center;
        float dist = length(d);
        float radius = phase * 0.375;
        float envelope = (1.0 - phase) * smoothstep(0.1, 0.0, abs(dist - radius));
        g += (d / max(dist, 1e-3)) * cos((dist - radius) * 40.0) * envelope;
    }
    return g;
}

// Wet, puddled or snow-covered world surfaces inside the view's authored weather volumes.
void applyWeather(Record r, vec3 geometric, inout vec3 n, inout vec3 albedo, inout float rough, float metal) {
    if (r.view == uvec2(0u)) return;
    ViewData view = ViewData(r.view);
    float wet = 0.0, snow = 0.0;
    for (uint k = 0u; k < view.weather.x; ++k) {
        vec4 lo = view.boxes[k * 2u], hi = view.boxes[k * 2u + 1u];
        vec3 inside = step(lo.xyz - vec3(0.0, 0.0, 24.0), worldPos) * step(worldPos, hi.xyz + vec3(0.0, 0.0, 24.0));
        if (inside.x * inside.y * inside.z < 0.5) continue;
        if (lo.w < 0.5) wet = 1.0; else snow = 1.0;
    }
    if (wet + snow == 0.0) return;
    // Only surfaces open to the sky (rain occlusion map) get wet or covered.
    float exposure = rainExposure(view, view.shadows.y, worldPos + geometric * 2.0);
    wet *= exposure;
    snow *= exposure;
    float up = clamp(geometric.z, 0.0, 1.0);
    float t = view.weatherParams.z;
    if (wet > 0.0) {
        float wetness = wet * (0.55 + 0.45 * up) * view.weatherParams.x;
        float puddle = wet * puddleNoise(worldPos.xy) * smoothstep(0.85, 0.97, up) * view.weatherParams.x;
        // Water fills a porous surface's pores and darkens it (to ~0.3); dense ones barely.
        float porosity = clamp((rough - 0.3) / 0.6, 0.0, 1.0) * (1.0 - metal);
        albedo *= mix(1.0, mix(0.85, 0.3, porosity), wetness);
        // Wet walls and floors turn glossy, not mirror-like; puddles do.
        rough = mix(rough, 0.3, wetness * 0.75);
        rough = mix(rough, 0.03, puddle);
        n = normalize(mix(n, geometric, puddle));
        // Drops only ripple standing water.
        vec2 ripple = rippleGradient(worldPos.xy, t, view.weatherParams.x) * 0.35 * puddle * up;
        n = normalize(n + vec3(ripple, 0.0));
    }
    if (snow > 0.0) {
        float cover = snow * smoothstep(0.45, 0.85, up) * (0.65 + 0.35 * valueNoise(worldPos.xy / 64.0)) * view.weatherParams.y;
        albedo = mix(albedo, vec3(0.82, 0.85, 0.9), cover);
        rough = mix(rough, 0.75, cover);
        n = normalize(mix(n, geometric, cover));
    }
}

// DDGI irradiance (ddgi.zig) at `pos` for normal `n`; a = confidence. Trilinear over the eight
// surrounding probes, skipping probes inside geometry or not yet traced.
vec4 ddgiIrradiance(Record r, vec3 pos, vec3 n) {
    if (r.view == uvec2(0u)) return vec4(0.0);
    ViewData view = ViewData(r.view);
    return ddgiSample(view.ddgiSlots, view.ddgiSlots2, view.ddgiOrigin, view.ddgiDims, pos, n);
}

// Remaster model shadows (shadows.zig): occlusion of the baked light by nearby casters.
float modelShadow(Record r) {
    if (r.view == uvec2(0u)) return 0.0;
    ViewData view = ViewData(r.view);
    uint count = view.shadows.x;
    if (count == 0u) return 0.0;
    ShadowCasters casters = ShadowCasters(view.shadowList.xy);
    float occlusion = 0.0;
    for (uint k = 0u; k < count; ++k) {
        ShadowCaster sc = casters.v[k];
        vec3 d = worldPos - sc.sphere.xyz;
        if (dot(d, d) > sc.sphere.w * sc.sphere.w) continue;
        vec4 p = sc.worldToTile * vec4(worldPos, 1.0);
        if (any(greaterThan(abs(p.xy), vec2(0.98))) || p.z <= 0.0 || p.z >= 1.0) continue;
        vec2 uv = sc.tile.xy + vec2(p.x * 0.5 + 0.5, 0.5 - p.y * 0.5) * sc.tile.z;
        float texel = sc.info.z;
        vec2 lo = sc.tile.xy + texel, hi = sc.tile.xy + sc.tile.z - texel;
        float hits = 0.0, nearest = 1.0;
        for (int y = -1; y <= 1; ++y) {
            for (int x = -1; x <= 1; ++x) {
                float stored = texture(textures[nonuniformEXT(view.shadows.y)], clamp(uv + vec2(x, y) * texel * 1.5, lo, hi)).r;
                if (p.z - sc.tile.w > stored) {
                    hits += 1.0;
                    nearest = min(nearest, stored);
                }
            }
        }
        if (hits == 0.0) continue;
        // Contact-hardened fade: strongest right under the caster, gone at the reach.
        float fade = 1.0 - smoothstep(0.15, 1.0, (p.z - nearest) / max(sc.info.y, 1e-4));
        occlusion = max(occlusion, hits / 9.0 * fade * sc.info.x);
    }
    return occlusion;
}

// Weather particle shapes (mesh kind 3): streaks, round flakes and splash crowns.
float weatherShape(Record r, vec2 q) {
    WeatherParams w = WeatherParams(r.vertices);
    vec2 p = q * 2.0 - 1.0;
    if (w.eye.w > 0.5) {
        // Crown: a thin rim rising from the impact point (q.y = 0 at the surface).
        float rim = length(vec2(p.x, q.y * 1.6 - 0.15));
        return smoothstep(0.55, 0.8, rim) * (1.0 - smoothstep(0.85, 1.0, rim)) * (1.0 - smoothstep(0.7, 1.0, q.y));
    }
    if (w.mins.w > 0.5) return 1.0 - smoothstep(0.25, 1.0, length(p));
    // Streak: Gaussian across, soft ends, and a faint brightness wobble along the length from
    // the drop's shape oscillation (Garg & Nayar).
    float across = exp(-p.x * p.x * 3.0);
    float ends = smoothstep(0.0, 0.18, q.y) * (1.0 - smoothstep(0.82, 1.0, q.y));
    return across * ends * (0.8 + 0.2 * sin(q.y * 15.0));
}

void main() {
    Record r = Record(push.record);
    uint flags = r.mode2.z;
    bool linear = (flags & FLAG_LINEAR) != 0u;
    vec4 tex = texture(textures[nonuniformEXT(r.mode2.x)], uv0);
    if (r.mode.x == 3u) {
        // Weather particles arrive lit in linear light (stage.vert weatherLight); flakes are white.
        WeatherParams w = WeatherParams(r.vertices);
        vec3 lit = color.rgb * (w.mins.w > 0.5 ? 0.9 : 1.0);
        vec4 c = vec4(lit, color.a * weatherShape(r, uv0));
        if ((flags & FLAG_VOLUME) != 0u && r.view != uvec2(0u)) {
            ViewData view = ViewData(r.view);
            vec2 suv = (gl_FragCoord.xy - view.rect.xy) / view.rect.zw;
            float wz = log(max(eyeDepth, 1e-3) / view.froxel.x) * view.froxel.y;
            vec4 fog = texture(volumes[nonuniformEXT(view.slots.x)], vec3(clamp(suv, 0.0, 1.0), clamp(wz, 0.0, 1.0)));
            c.rgb = c.rgb * pow(clamp(fog.a, 0.0, 1.0), 2.2) + fog.rgb * pow(1.0 - clamp(fog.a, 0.0, 1.0), 1.2);
        }
        if (!linear) c.rgb = pow(min(c.rgb, vec3(1.0)), vec3(1.0 / 2.2));
        outColor = c;
        return;
    }
    vec4 vertexColor = color;
    if (linear) {
        // Remaster lightmaps are uploaded as linear radiance; everything else is display-encoded.
        if ((flags & FLAG_FIRST_LIGHTMAP) == 0u) tex.rgb = toLinear(tex.rgb);
        vertexColor.rgb = toLinear(vertexColor.rgb);
    }
    vec4 c;
    if ((flags & FLAG_LIQUID) != 0u) {
        c = shadeLiquid(r, tex);
    } else if ((flags & (FLAG_PBR_WORLD | FLAG_PBR_MODEL)) != 0u) {
        // A visible surface faces the viewer. gl_FrontFacing cannot tell: the flipped viewport
        // (negative height) with Quake's winding reports ordinary visible faces as back faces, so
        // flipping on it inverted world and model normals; lit from behind, every light in
        // front failed the cosine (dark floors, black models) and sky rays left through floors.
        vec3 n = normalize(worldNormal);
        if (dot(n, r.viewPos.xyz - worldPos) < 0.0) n = -n;
        vec3 geometric = n;
        float rough = clamp(r.material.x, 0.04, 1.0);
        float metal = clamp(r.material.y, 0.0, 1.0);
        float bump = r.material.z;
        if (r.maps.x != 0u) n = normalMapped(n, r.maps.x - 1u, uv0, max(bump, 0.0));
        else if (bump > 0.0) n = proceduralBump(n, r.mode2.x, uv0, bump);
        float specularStrength = r.material2.x;
        if (r.maps.y != 0u) {
            vec4 s = texture(textures[nonuniformEXT(r.maps.y - 1u)], uv0);
            specularStrength *= s.r * 2.0;
            rough = clamp(rough * (1.4 - s.g * 0.8), 0.04, 1.0);
        }
        vec3 v = normalize(r.viewPos.xyz - worldPos);
        vec3 albedo = tex.rgb;
        if ((flags & FLAG_PBR_WORLD) != 0u) applyWeather(r, geometric, n, albedo, rough, metal);
        vec3 f0 = mix(vec3(0.04 * specularStrength), albedo, metal);
        float grazing = grazingReflectance(rough, specularStrength, metal);
        vec3 lit;
        if ((flags & FLAG_PBR_WORLD) != 0u) {
            bool rtLit = false;
#ifdef RAY_QUERY
            rtLit = rtLightingEnabled(r);
#endif
            vec3 irradiance = r.mode2.y != 0u ? texture(textures[nonuniformEXT(r.mode2.y - 1u)], uv1).rgb : vec3(1.0);
#ifdef RAY_QUERY
            if (rtLit) {
                // No lightmap: map lights with traced shadows, plus the probe field's indirect
                // light (multi-bounce, sky) and the character shadows.
                // With characters in the ray tracing scene their shadows are traced with the
                // rest; otherwise the shadow atlas still darkens the direct light.
                // Sky light only where this pixel actually sees the sky.
                vec2 skyAo = rtSkyAndOcclusion(r, geometric, worldPos + geometric * 0.75);
                // Bounce light from the probes, darkened in corners and crevices, summed with the
                // direct light and sky in radiosity units as the original lightmaps were (added
                // after the conversion, a dim bounce counted for almost nothing).
                vec4 probe = ddgiIrradiance(r, worldPos + geometric * 4.0, n);
                vec3 bounce = probe.rgb / PI * probe.a * skyAo.y;
                vec3 direct = rtDirectLight(r, n, worldPos + geometric * 0.75, RT_LIGHT_SHADOWS, rtSkyRaw(r, skyAo.x) + rtLinearToRaw(bounce, ViewData(r.view).rtLightScale.x, ViewData(r.view).rtLightScale.y));
                if (ViewData(r.view).rt.y == 0u) direct *= 1.0 - modelShadow(r) * 0.8;
                irradiance = direct + rtSkyLinear(r, skyAo.x);
                // r_vkDebugView 12 direct, 13 probe bounce, 14 sky, 15 direct without shadows.
                float term = ViewData(r.view).weatherParams.w;
                if (term == 12.0) irradiance = rtDirectLight(r, n, worldPos + geometric * 0.75, RT_LIGHT_SHADOWS, vec3(0.0));
                else if (term == 13.0) irradiance = probe.rgb / PI * probe.a * skyAo.y;
                else if (term == 14.0) irradiance = rtRawToLinear(rtSkyRaw(r, skyAo.x), ViewData(r.view).rtLightScale.x, ViewData(r.view).rtLightScale.y) + rtSkyLinear(r, skyAo.x);
                else if (term == 15.0) irradiance = rtDirectLight(r, n, worldPos + geometric * 0.75, 0u, vec3(0.0));
                else if (term == 19.0) {
                    rtDirectLight(r, n, worldPos + geometric * 0.75, RT_LIGHT_SHADOWS, vec3(0.0));
                    ViewData view = ViewData(r.view);
                    vec2 centre = view.rect.xy + view.rect.zw * 0.5;
                    if (ivec2(gl_FragCoord.xy) == ivec2(centre)) {
                        RtWordsRw probe = RtWordsRw(view.rtLights.zw);
                        uint at = view.rtCellDims.x * view.rtCellDims.y * view.rtCellDims.z * RT_CELL_STRIDE * 2u;
                        probe.v[at] = 0x5052424Fu;
                        for (uint j = 0u; j < 4u; ++j) {
                            probe.v[at + 1u + j * 8u] = rtProbeIndex[j];
                            probe.v[at + 2u + j * 8u] = floatBitsToUint(rtProbeLight[j].x);
                            probe.v[at + 3u + j * 8u] = floatBitsToUint(rtProbeLight[j].y);
                            probe.v[at + 4u + j * 8u] = floatBitsToUint(rtProbeLight[j].z);
                            probe.v[at + 5u + j * 8u] = floatBitsToUint(rtProbeLight[j].w);
                        }
                        probe.v[at + 40u] = floatBitsToUint(worldPos.x);
                        probe.v[at + 41u] = floatBitsToUint(worldPos.y);
                        probe.v[at + 42u] = floatBitsToUint(worldPos.z);
                        probe.v[at + 43u] = floatBitsToUint(n.x);
                        probe.v[at + 44u] = floatBitsToUint(n.y);
                        probe.v[at + 45u] = floatBitsToUint(n.z);
                        probe.v[at + 46u] = floatBitsToUint(r.viewPos.x);
                        probe.v[at + 47u] = floatBitsToUint(r.viewPos.y);
                        probe.v[at + 48u] = floatBitsToUint(r.viewPos.z);
                        probe.v[at + 49u] = floatBitsToUint(normalize(worldNormal).z);
                        probe.v[at + 50u] = gl_FrontFacing ? 1u : 0u;
                    }
                    outColor = vec4(1.0, 0.0, 1.0, 1.0);
                    return;
                }
                else if (term == 18.0) {
                    rtDirectLight(r, n, worldPos + geometric * 0.75, RT_LIGHT_SHADOWS, vec3(0.0));
                    outColor = vec4(rtShadowBlocker, 1.0);
                    return;
                }
                else if (term == 17.0) {
                    rtDirectLight(r, n, worldPos + geometric * 0.75, RT_LIGHT_SHADOWS, vec3(0.0));
                    outColor = vec4(rtShadowDebug, 1.0);
                    return;
                }
                else if (term == 16.0) {
                    rtLightSpread = 0.0;
                    irradiance = rtDirectLight(r, n, worldPos + geometric * 0.75, RT_LIGHT_SHADOWS, vec3(0.0));
                }
                if (r.view != uvec2(0u) && ViewData(r.view).weatherParams.w == 4.0) {
                    outColor = vec4(irradiance, 1.0);
                    return;
                }
            }
#endif
            if (!rtLit) irradiance *= 1.0 - modelShadow(r) * 0.62;
            // Bump response to the baked light: the light grid's dominant direction steers how
            // the perturbed normal differs from the flat one the radiosity was computed for.
            vec4 grid = lightGrid(r, worldPos);
            // Baked direction pages (bake.zig) supersede the coarse grid direction.
            if (r.material2.w > 0.5 && !(r.view != uvec2(0u) && ViewData(r.view).weatherParams.w == 5.0)) {
                vec4 deluxe = texture(textures[nonuniformEXT(uint(r.material2.w) - 1u)], uv1);
                // The lightmap also holds bounce light, so only part of it follows the direction.
                if (deluxe.a > 0.02 && all(greaterThan(deluxe.rgb, vec3(-1e-3)))) grid = vec4(deluxe.rgb, deluxe.a * 0.6);
                if (r.view != uvec2(0u) && ViewData(r.view).weatherParams.w == 3.0) {
                    outColor = vec4(deluxe.rgb * deluxe.a, 1.0);
                    return;
                }
                if (r.view != uvec2(0u) && ViewData(r.view).weatherParams.w == 4.0) {
                    outColor = vec4(irradiance, 1.0);
                    return;
                }
            }
            if (rtLit) {
                lit = irradiance * (1.0 - metal) * albedo;
            } else if (grid.a > 0.0) {
                vec3 l = normalize(grid.xyz * 2.0 - 1.0);
                float flat_term = max(dot(geometric, l), 0.25);
                float bumped = max(dot(n, l), 0.0);
                float ratio = bumped / flat_term;
                if (!(ratio >= 0.0)) ratio = 1.0; // guard against an invalid direction (NaN)
                irradiance *= mix(1.0, clamp(ratio, 0.35, 1.8), grid.a);
                // Baked light also produces a specular highlight toward its dominant direction.
                // That direction stands for a window or lamp of some size, not a point: widen
                // the lobe so glossy wet surfaces do not speckle wherever a bumped normal aligns.
                vec3 h = normalize(v + l);
                float a = max(rough, 0.5);
                a *= a;
                vec3 f = fresnelSchlick(max(dot(h, v), 0.0), f0, grazing);
                lit = irradiance * ((1.0 - metal) * albedo +
                    grid.a * distributionGGX(max(dot(n, h), 0.0), a) * visibilitySmith(max(dot(n, v), 1e-3), max(dot(n, l), 1e-3), a) * f * max(dot(n, l), 0.0) * PI);
            } else {
                lit = irradiance * (1.0 - metal) * albedo;
            }
        } else {
            // Grid-lit model: ambient plus the directed light, per pixel.
            vec3 ambient = toLinear(r.ambient.rgb);
            // Traced probes refine the grid's ambient term with bounce colour and occlusion,
            // but may at most double its brightness: next to emissive lamps the field would
            // otherwise wash a character out to a flat, colourless statue.
            vec4 field = ddgiIrradiance(r, worldPos, n);
            if (field.a > 0.0) {
                vec3 probe = field.rgb / PI;
                float cap = max(luminance(ambient) * 2.0, 0.02);
                probe *= min(1.0, cap / max(luminance(probe), 1e-4));
                ambient = mix(ambient, probe, field.a * 0.6);
            }
            vec3 directed = toLinear(r.directed.rgb);
            vec3 l = normalize(r.worldLight.xyz);
            lit = ambient * (1.0 - metal) * albedo + shadeLight(n, v, l, directed * PI, albedo, f0, metal, rough, grazing);
#ifdef RAY_QUERY
            if (rtLightingEnabled(r)) {
                // Characters in ray traced lighting: the same map lights with traced shadows
                // and the probe field, instead of the baked light grid.
                vec2 skyAo = rtSkyAndOcclusion(r, n, worldPos + n * 2.0);
                vec3 indirect = field.a > 0.0 ? field.rgb / PI : toLinear(r.ambient.rgb) * 0.5;
                vec3 lightScale = ViewData(r.view).rtLightScale.xyz;
                vec3 direct = rtDirectLight(r, n, worldPos + n * 2.0, 2u, rtSkyRaw(r, skyAo.x) + rtLinearToRaw(indirect * skyAo.y, lightScale.x, lightScale.y));
                lit = (direct + rtSkyLinear(r, skyAo.x)) * (1.0 - metal) * albedo;
            }
#endif
        }
        lit += pbrDynamicLights(r, n, v, albedo, f0, metal, rough, grazing);
        if (r.view != uvec2(0u)) {
            // r_vkDebugView 6: texture colour only; 7: light only (texture forced white).
            float debug = ViewData(r.view).weatherParams.w;
            if (debug == 6.0) {
                outColor = vec4(albedo, 1.0);
                return;
            }
            if (debug == 7.0) {
                outColor = vec4(lit / max(albedo, vec3(1e-3)), 1.0);
                return;
            }
        }
#ifdef RAY_QUERY
        // Traced reflections on smooth and wet world materials.
        if ((flags & FLAG_PBR_WORLD) != 0u && rough < 0.45 && rtEnabled(r, 2u)) {
            vec3 rdir = reflect(-v, n);
            if (dot(rdir, geometric) > 0.0) {
                vec3 traced = rtRadiance(r, worldPos + geometric * 0.5, rdir, 8192.0, vec3(0.04));
                lit += traced * fresnelSchlick(max(dot(n, v), 0.0), f0, grazing) * (1.0 - smoothstep(0.12, 0.45, rough));
            }
        }
#endif
        lit += albedo * r.material.w;
        c = vec4(lit * ((flags & FLAG_PBR_MODEL) != 0u ? vec3(1.0) : vertexColor.rgb), tex.a * vertexColor.a);
    } else {
        if ((flags & FLAG_FIRST_LIGHTMAP) != 0u && r.counts.z > 0u) {
            if (linear) tex.rgb += toLinear(min(dynamicLight(r), vec3(1.0)));
            else tex.rgb = min(tex.rgb + dynamicLight(r), vec3(1.0));
        }
        if (r.mode2.y != 0u) {
            vec4 second = texture(textures[nonuniformEXT(r.mode2.y - 1u)], uv1);
            if ((flags & FLAG_SECOND_LIGHTMAP) != 0u && r.counts.z > 0u) {
                if (linear) second.rgb += toLinear(min(dynamicLight(r), vec3(1.0)));
                else second.rgb = min(second.rgb + dynamicLight(r), vec3(1.0));
            } else if (linear && (flags & FLAG_SECOND_LIGHTMAP) == 0u) second.rgb = toLinear(second.rgb);
            tex *= second;
        }
        c = tex * vertexColor;
        if (linear) c.rgb += tex.rgb * r.material.w;
    }
    uint func = r.mode2.w;
    if (func == 1u && c.a <= 0.0) discard;
    if (func == 2u && c.a >= 0.5) discard;
    if (func == 3u && c.a < 0.5) discard;
    // Opaque model pixels mark the HDR alpha as dynamic: the temporal resolve (taa.comp)
    // trusts the new frame there, since reprojection only follows the camera.
    if ((flags & FLAG_DYNAMIC) != 0u) c.a = 0.0;
    if ((flags & FLAG_FOG) != 0u) {
        float f = clamp((r.fog.y - eyeDepth) / (r.fog.y - r.fog.x), 0.0, 1.0);
        // Authored linear fog was tuned in display space; the remaster mixes there too so its
        // density matches, then returns to linear light.
        if (linear) c.rgb = toLinear(mix(r.fogColor.rgb, pow(max(c.rgb, vec3(0.0)), vec3(1.0 / 2.2)), f));
        else c.rgb = mix(r.fogColor.rgb, c.rgb, f);
    }
    if ((flags & FLAG_VOLUME) != 0u && r.view != uvec2(0u)) {
        ViewData view = ViewData(r.view);
        vec2 suv = (gl_FragCoord.xy - view.rect.xy) / view.rect.zw;
        // Sky stages (fogColor.x = 1) sample the column at the authored sky coverage.
        float depth = r.fogColor.x > 0.5 ? view.fogParams.x : eyeDepth;
        float w = log(max(depth, 1e-3) / view.froxel.x) * view.froxel.y;
        vec3 lookup = vec3(clamp(suv, 0.0, 1.0), clamp(w, 0.0, 1.0));
        vec4 fog = texture(volumes[nonuniformEXT(view.slots.x)], lookup);
        vec3 glow = texture(volumes[nonuniformEXT(view.slots.y)], lookup).rgb;
        float reach = clamp(depth / view.froxel.x, 0.0, 1.0);
        fog = mix(vec4(0.0, 0.0, 0.0, 1.0), fog, reach);
        fog = clamp(fog, vec4(0.0), vec4(64.0, 64.0, 64.0, 1.0));
        // The authored fog was a display-space blend toward its colour: a few percent of a
        // bright colour was nearly invisible. Remapping the coverage by the display gamma
        // reproduces that blend from the linear integration; the dynamic-light glow stays.
        float cover = 1.0 - fog.a;
        fog.rgb = fog.rgb * pow(cover, 1.2) + glow * reach;
        fog.a = pow(fog.a, 2.2);
        // Blend-aware like the fixed-function fog colours: opaque and alpha stages receive the
        // in-scattering, additive stages only fade, filters fade toward their identity.
        uint mode = uint(r.fogColor.w);
        if (mode == 1u) c.rgb = c.rgb * fog.a + fog.rgb * (c.a > 0.0 ? 1.0 : 0.0);
        else if (mode == 2u) c.rgb *= fog.a;
        else if (mode == 3u) c.rgb = mix(vec3(1.0), c.rgb, fog.a);
        else if (mode == 4u) c.rgb = mix(vec3(0.5), c.rgb, fog.a);
    }
    if ((flags & FLAG_OVERLAY_OPAQUE) != 0u) c.a = 1.0;
    outColor = c;
}
