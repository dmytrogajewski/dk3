// SPDX-License-Identifier: GPL-2.0-or-later
// DDGI field lookup (ddgi.zig): irradiance at `pos` for normal `n`, a = confidence. Trilinear over
// the eight surrounding probes, skipping probes not yet traced or inside geometry, weighted by a
// Chebyshev visibility test on each probe's distance moments (no light through walls). Needs
// `volumes[]` (sampler3D) and ddgi_common.glsl.
vec4 ddgiSample(uvec4 slots, uvec4 slots2, ivec4 origin, ivec4 dimsIn, vec3 pos, vec3 n) {
    if (origin.w == 0) return vec4(0.0);
    ivec3 dims = dimsIn.xyz;
    float spacing = intBitsToFloat(dimsIn.w);
    vec3 g = pos / spacing - 0.5;
    ivec3 base = ivec3(floor(g));
    vec3 f = g - vec3(base);
    vec3 sum = vec3(0.0);
    float weights = 0.0;
    for (int k = 0; k < 8; ++k) {
        ivec3 offset = ivec3(k & 1, (k >> 1) & 1, (k >> 2) & 1);
        ivec3 index = base + offset;
        ivec3 local = index - origin.xyz;
        if (any(lessThan(local, ivec3(0))) || any(greaterThanEqual(local, dims))) continue;
        ivec3 storage = ddgiStorage(index, dims);
        vec4 t0 = texelFetch(volumes[nonuniformEXT(slots.x)], storage, 0);
        vec4 t1 = texelFetch(volumes[nonuniformEXT(slots.y)], storage, 0);
        vec4 t2 = texelFetch(volumes[nonuniformEXT(slots.z)], storage, 0);
        vec4 t3 = texelFetch(volumes[nonuniformEXT(slots.w)], storage, 0);
        vec3 tag = ddgiTag(index);
        if (t1.a != tag.x || t2.a != tag.y || t3.a != tag.z || t0.a < 0.5) continue;
        vec3 trilinear = mix(1.0 - f, f, vec3(offset));
        vec3 toProbe = normalize((vec3(index) + 0.5) * spacing - pos + n * 1e-3);
        float facing = (dot(toProbe, n) + 1.0) * 0.5;
        float w = trilinear.x * trilinear.y * trilinear.z * (facing * facing + 0.2);
        // Visibility (DDGI Chebyshev test on the probe's distance moments): probes behind a
        // wall do not light this side of it.
        if (slots2.x != 0u) {
            vec4 d1 = texelFetch(volumes[nonuniformEXT(slots2.x)], storage, 0);
            vec4 d2 = texelFetch(volumes[nonuniformEXT(slots2.y)], storage, 0);
            vec3 fromProbe = pos + n * 2.0 - (vec3(index) + 0.5) * spacing;
            float dist = length(fromProbe);
            vec3 dir = fromProbe / max(dist, 1e-3);
            float mean = d1.x * SH_C0 + SH_C1 * (d1.y * dir.y + d1.z * dir.z + d1.w * dir.x);
            float mean2 = d2.x * SH_C0 + SH_C1 * (d2.y * dir.y + d2.z * dir.z + d2.w * dir.x);
            if (dist > mean) {
                float variance = max(mean2 - mean * mean, 16.0);
                float excess = dist - mean;
                float chebyshev = variance / (variance + excess * excess);
                w *= max(chebyshev * chebyshev * chebyshev, 0.0) + 0.001;
            }
        }
        vec3 e = 3.14159265 * SH_C0 * t0.rgb + (2.0 * 3.14159265 / 3.0) * SH_C1 * (t1.rgb * n.y + t2.rgb * n.z + t3.rgb * n.x);
        sum += w * max(e, vec3(0.0));
        weights += w;
    }
    return weights > 0.0 ? vec4(sum / weights, clamp(weights * 3.0, 0.0, 1.0)) : vec4(0.0);
}
