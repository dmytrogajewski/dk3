// SPDX-License-Identifier: GPL-2.0-or-later
// Ray traced lighting (r_vkLighting 1, rt.zig `buildLights`): direct light from the map's light
// entities, emitting faces and sun instead of the baked lightmaps. Lights use the original
// radiosity tool's models (rt_common.glsl rtLightRaw) so levels stay close to the original;
// visibility is traced. Needs rt_common.glsl.
//
// Per receiver, the up to 63 lights of its 256-unit cell are evaluated; the four strongest get
// an exact shadow ray and the rest two importance-sampled ones, at most six rays.

const uint RT_LIGHT_SHADOWS = 4u;
const uint RT_LIGHT_SAMPLES = 2u;

// Per-sample randomness for area light shadow rays; callers set it (frame-varying).
vec2 rtLightJitter = vec2(0.5);
// r_vkDebugView 17: the strongest light's shadow ray: green clear; blocked red near the
// receiver (< 10%), yellow on the way, blue near the light (> 90%).
vec3 rtShadowDebug = vec3(0.0);
// r_vkDebugView 18: the albedo of what blocks that ray (black: nothing).
vec3 rtShadowBlocker = vec3(0.0);
// r_vkDebugView 19: the four shadow-tested lights (index, luminance, distance, blocked, hit fraction).
uint rtProbeIndex[4] = uint[](0u, 0u, 0u, 0u);
vec4 rtProbeLight[4] = vec4[](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));

// Summed light in the radiosity tool's units (255 = a fully lit lightmap texel).
vec3 rtMapLightRaw(uvec2 tableAddress, uvec2 lightsAddress, uvec2 cellsAddress, vec4 cellOrigin, uvec3 cellDims,
                   vec3 pos, vec3 n, vec3 rayOrigin, uint shadowRays) {
    if (cellsAddress == uvec2(0u) || cellDims.x == 0u) return vec3(0.0);
    ivec3 cell = clamp(ivec3(floor((pos - cellOrigin.xyz) / cellOrigin.w)), ivec3(0), ivec3(cellDims) - 1);
    uint base = uint((cell.z * int(cellDims.y) + cell.y) * int(cellDims.x) + cell.x) * RT_CELL_STRIDE;
    RtWords list = RtWords(cellsAddress);
    RtFloats lights = RtFloats(lightsAddress);
    uint count = min(list.v[base], RT_LIGHTS_PER_CELL);
    vec3 total = vec3(0.0);
    float topWeight[RT_LIGHT_SHADOWS];
    uint topIndex[RT_LIGHT_SHADOWS];
    vec3 topRaw[RT_LIGHT_SHADOWS];
    for (uint j = 0u; j < RT_LIGHT_SHADOWS; ++j) {
        topWeight[j] = 0.0;
        topIndex[j] = 0u;
        topRaw[j] = vec3(0.0);
    }
    for (uint k = 0u; k < count; ++k) {
        uint index = list.v[base + 1u + k];
        // No ray from this cell reached the light: it cannot light the receiver.
        uint seen = rtVisibility(list, cellDims, base + 1u + k);
        if (seen == 0u) continue;
        vec3 raw = rtLightRaw(lights, index, pos, n);
        if (raw == vec3(0.0)) continue;
        total += raw;
        // Shadow rays go to the lights that bring most light and are most often seen.
        float weight = dot(raw, vec3(0.2126, 0.7152, 0.0722)) * float(seen) / float(RT_VISIBILITY_RAYS);
        // Keep the strongest lights, sorted, for the shadow rays.
        for (uint j = 0u; j < RT_LIGHT_SHADOWS; ++j) {
            if (weight > topWeight[j]) {
                for (uint m = RT_LIGHT_SHADOWS - 1u; m > j; --m) {
                    topWeight[m] = topWeight[m - 1u];
                    topIndex[m] = topIndex[m - 1u];
                    topRaw[m] = topRaw[m - 1u];
                }
                topWeight[j] = weight;
                topIndex[j] = index;
                topRaw[j] = raw;
                break;
            }
        }
    }
    vec3 tested = vec3(0.0), visible = vec3(0.0);
    for (uint j = 0u; j < min(shadowRays, RT_LIGHT_SHADOWS); ++j) {
        if (topWeight[j] <= 0.0) break;
        uint index = topIndex[j];
        vec3 origin = rtLightPoint(lights, index, fract(rtLightJitter + vec2(0.618, 0.382) * float(j)), rayOrigin);
        vec3 d = origin - rayOrigin;
        float dist = length(d);
        tested += topRaw[j];
        // Stop short of the light: map lights often sit just inside their fixture.
        bool blocked = rtOccluded(tableAddress, rayOrigin, d / max(dist, 1e-3), dist - 12.0);
        if (!blocked) visible += topRaw[j];
        rtProbeIndex[j] = index;
        rtProbeLight[j] = vec4(dot(topRaw[j], vec3(0.2126, 0.7152, 0.0722)), dist, blocked ? 1.0 : 0.0,
                               rtHitDistance(tableAddress, rayOrigin, d / max(dist, 1e-3), max(dist - 12.0, 0.0)) / max(dist - 12.0, 1e-3));
        if (j == 0u) {
            float f = rtHitDistance(tableAddress, rayOrigin, d / max(dist, 1e-3), dist - 12.0) / max(dist - 12.0, 1e-3);
            rtShadowDebug = !blocked ? vec3(0.0, 1.0, 0.0) : f < 0.1 ? vec3(1.0, 0.0, 0.0) : f > 0.9 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 1.0, 0.0);
            RtHit h = rtTrace(tableAddress, rayOrigin, d / max(dist, 1e-3), dist - 12.0, 0.0);
            rtShadowBlocker = h.hit ? h.albedo + vec3(0.05) : vec3(0.0);
        }
    }
    uint exact = min(shadowRays, RT_LIGHT_SHADOWS);
    if (exact == 0u) return total;
    // The other lights: RT_LIGHT_SAMPLES shadow rays at lights picked in proportion to their
    // light here (weighted reservoir sampling), each standing for its share of the rest. Unbiased,
    // so a strong light behind a wall cannot darken the others; the frame-varying choice is
    // averaged by temporal anti-aliasing.
    vec3 rest = total - tested;
    if (dot(rest, vec3(0.2126, 0.7152, 0.0722)) <= 1e-3) return visible;
    float seed = fract(dot(pos, vec3(0.1031, 0.1030, 0.0973)) * 43.7585 + rtLightJitter.x * 7.31 + rtLightJitter.y * 3.17);
    vec3 estimate = vec3(0.0);
    for (uint sampleIndex = 0u; sampleIndex < RT_LIGHT_SAMPLES; ++sampleIndex) {
        float weightSum = 0.0;
        uint chosen = 0u;
        vec3 chosenRaw = vec3(0.0);
        float chosenSeen = 1.0;
        float u = fract(seed + 0.618034 * float(sampleIndex));
        for (uint k = 0u; k < count; ++k) {
            uint index = list.v[base + 1u + k];
            bool top = false;
            for (uint j = 0u; j < exact; ++j) top = top || (topWeight[j] > 0.0 && topIndex[j] == index);
            if (top) continue;
            uint seen = rtVisibility(list, cellDims, base + 1u + k);
            if (seen == 0u) continue;
            vec3 raw = rtLightRaw(lights, index, pos, n);
            float w = dot(raw, vec3(0.2126, 0.7152, 0.0722)) * float(seen) / float(RT_VISIBILITY_RAYS);
            if (w <= 0.0) continue;
            weightSum += w;
            // Keep this light with probability w / weightSum (one uniform number, rescaled).
            if (u * weightSum < w) {
                chosen = index;
                chosenRaw = raw;
                chosenSeen = float(seen) / float(RT_VISIBILITY_RAYS);
                u = u * weightSum / w;
            } else {
                u = (u * weightSum - w) / (weightSum - w);
            }
        }
        if (weightSum <= 0.0) break;
        vec3 origin = rtLightPoint(lights, chosen, fract(rtLightJitter.yx + vec2(0.382, 0.618) * float(sampleIndex + 1u)), rayOrigin);
        vec3 d = origin - rayOrigin;
        float dist = length(d);
        float chosenWeight = dot(chosenRaw, vec3(0.2126, 0.7152, 0.0722)) * chosenSeen;
        if (!rtOccluded(tableAddress, rayOrigin, d / max(dist, 1e-3), dist - 12.0))
            estimate += chosenRaw * (weightSum / chosenWeight);
    }
    return visible + estimate / float(RT_LIGHT_SAMPLES);
}

// The same for a point in the air (light shafts): no surface, so no cosine; lights are only
// visibility-tested, not shaded.
vec3 rtMapLightRawIsotropic(uvec2 tableAddress, uvec2 lightsAddress, uvec2 cellsAddress, vec4 cellOrigin, uvec3 cellDims,
                            vec3 pos, uint shadowRays) {
    if (cellsAddress == uvec2(0u) || cellDims.x == 0u) return vec3(0.0);
    ivec3 cell = clamp(ivec3(floor((pos - cellOrigin.xyz) / cellOrigin.w)), ivec3(0), ivec3(cellDims) - 1);
    uint base = uint((cell.z * int(cellDims.y) + cell.y) * int(cellDims.x) + cell.x) * RT_CELL_STRIDE;
    RtWords list = RtWords(cellsAddress);
    RtFloats lights = RtFloats(lightsAddress);
    uint count = min(list.v[base], RT_LIGHTS_PER_CELL);
    vec3 total = vec3(0.0), tested = vec3(0.0), visible = vec3(0.0);
    float strongest[2] = float[](0.0, 0.0);
    uint strongestIndex[2] = uint[](0u, 0u);
    vec3 strongestRaw[2] = vec3[](vec3(0.0), vec3(0.0));
    for (uint k = 0u; k < count; ++k) {
        uint index = list.v[base + 1u + k];
        if (rtVisibility(list, cellDims, base + 1u + k) == 0u) continue;
        vec3 raw = rtLightRaw(lights, index, pos, vec3(0.0));
        if (raw == vec3(0.0)) continue;
        total += raw;
        float weight = dot(raw, vec3(0.2126, 0.7152, 0.0722));
        if (weight > strongest[0]) {
            strongest[1] = strongest[0]; strongestIndex[1] = strongestIndex[0]; strongestRaw[1] = strongestRaw[0];
            strongest[0] = weight; strongestIndex[0] = index; strongestRaw[0] = raw;
        } else if (weight > strongest[1]) {
            strongest[1] = weight; strongestIndex[1] = index; strongestRaw[1] = raw;
        }
    }
    for (uint j = 0u; j < min(shadowRays, 2u); ++j) {
        if (strongest[j] <= 0.0) break;
        uint index = strongestIndex[j];
        vec3 d = rtLightPoint(lights, index, vec2(0.5), pos) - pos;
        float dist = length(d);
        tested += strongestRaw[j];
        if (!rtOccluded(tableAddress, pos, d / max(dist, 1e-3), dist - 12.0)) visible += strongestRaw[j];
    }
    float testedWeight = dot(tested, vec3(0.2126, 0.7152, 0.0722));
    float fraction = testedWeight > 0.0 ? dot(visible, vec3(0.2126, 0.7152, 0.0722)) / testedWeight : 1.0;
    return visible + (total - tested) * fraction;
}

// Radiosity units to linear radiance, as world.zig `linearLight` converts baked lightmaps: the
// lightmap scale, the overbright shift, each texel normalised so its brightest channel keeps a
// quarter stop of headroom above white, then display gamma removed.
// The inverse (without the headroom curve): linear light back to radiosity units, so light
// computed in linear space (probe bounce) joins the sum before the conversion.
vec3 rtLinearToRaw(vec3 linear, float scale, float overbright) {
    return pow(max(linear, vec3(0.0)), vec3(1.0 / 2.2)) / max(overbright, 1e-3) / max(scale, 1e-3) * 255.0;
}

vec3 rtRawToLinear(vec3 raw, float scale, float overbright) {
    vec3 v = min(raw / 255.0 * scale, vec3(1.0)) * overbright;
    float peak = max(v.r, max(v.g, v.b));
    if (peak > 1.0) v *= (1.0 + 0.25 * (1.0 - exp(-(peak - 1.0)))) / peak;
    return pow(v, vec3(2.2));
}
