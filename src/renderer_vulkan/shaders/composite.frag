#version 460
// SPDX-License-Identifier: GPL-2.0-or-later
// Final composite. Mode 0 copies a display-ready image (classic renderer, final -> swapchain).
// Mode 1 (remaster) exposes the HDR scene, adds bloom, applies the AgX view transform with a
// slight "punchy" look and display gamma, then lays the premultiplied UI overlay on top.
// Gamma and intensity of the classic path are applied to textures at upload, exactly as the
// OpenGL renderers do without hardware gamma.
#include "post_common.glsl"
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 color;

// AgX (Troy Sobotka) with the polynomial fit by Benjamin Wrensch.
vec3 agx_contrast(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;
    return 15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}
vec3 agx(vec3 v) {
    const mat3 inset = mat3(0.842479062253094, 0.0423282422610123, 0.0423756549057051,
                            0.0784335999999992, 0.878468636469772, 0.0784336,
                            0.0792237451477643, 0.0791661274605434, 0.879142973793104);
    const float min_ev = -12.47393;
    const float max_ev = 4.026069;
    v = inset * max(v, vec3(1e-10));
    v = clamp(log2(v), min_ev, max_ev);
    v = (v - min_ev) / (max_ev - min_ev);
    return agx_contrast(v);
}
vec3 agx_look(vec3 v, float saturation) {
    float luma = dot(v, vec3(0.2126, 0.7152, 0.0722));
    return luma + saturation * (v - luma);
}

// Khronos PBR Neutral without its black-level toe: identity below 0.76, so the authored
// lightmap tones (and the game's deep shadows) display as they did, then a hue-preserving
// rolloff that only desaturates close to white.
vec3 neutral(vec3 color) {
    const float startCompression = 0.8 - 0.04;
    const float desaturation = 0.15;
    float peak = max(color.r, max(color.g, color.b));
    if (peak < startCompression) return color;
    const float d = 1.0 - startCompression;
    float newPeak = 1.0 - d * d / (peak + d - startCompression);
    color *= newPeak / peak;
    float g = 1.0 - 1.0 / (desaturation * (peak - newPeak) + 1.0);
    return mix(color, vec3(newPeak), g);
}

void main() {
    if (pc.slots.w == 0u) {
        color = vec4(texture(textures[pc.slots.x], uv).rgb, 1.0);
        return;
    }
    float exposure = Values(pc.buffer1).v[0];
    vec2 suv = uv;
    uint liquid = pc.size.y;
    if (liquid != 0u) {
        // Underwater: wobbling refraction of the whole view.
        float t = pc.params.w;
        suv += vec2(sin(uv.y * 38.0 + t * 2.1), cos(uv.x * 31.0 + t * 1.7)) * 0.0035;
    }
    vec3 hdr = texture(textures[pc.slots.y], suv).rgb;
    if (pc.params3.x > 0.0) {
        // Contrast-adaptive sharpening (after AMD FidelityFX CAS) on a tone-compressed luma.
        vec2 texel = pc.params3.yz;
        vec3 n = texture(textures[pc.slots.y], suv + vec2(0.0, -texel.y)).rgb;
        vec3 s = texture(textures[pc.slots.y], suv + vec2(0.0, texel.y)).rgb;
        vec3 e = texture(textures[pc.slots.y], suv + vec2(texel.x, 0.0)).rgb;
        vec3 w = texture(textures[pc.slots.y], suv + vec2(-texel.x, 0.0)).rgb;
        float lc = dot(hdr, LUMA), ln = dot(n, LUMA), ls = dot(s, LUMA), le = dot(e, LUMA), lw = dot(w, LUMA);
        float mn = min(lc, min(min(ln, ls), min(le, lw))) * exposure;
        float mx = max(lc, max(max(ln, ls), max(le, lw))) * exposure;
        mn = mn / (1.0 + mn);
        mx = mx / (1.0 + mx);
        float amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, 1e-4), 0.0, 1.0));
        float weight = -amp * mix(0.125, 0.2, clamp(pc.params3.x, 0.0, 1.0));
        hdr = max((hdr + weight * (n + s + e + w)) / (1.0 + 4.0 * weight), vec3(0.0));
    }
    if (pc.slots.z != 0u) hdr += texture(textures[pc.slots.z - 1u], suv).rgb * pc.params.x;
    if (liquid != 0u) {
        // Distance absorption and in-scattering toward the liquid's colour (Beer-Lambert).
        float n = pc.params2.x, f = pc.params2.y;
        float d = texture(textures[pc.size.x], suv).r;
        float dist = n * f / max(f - d * (f - n), 1e-3);
        vec3 coefficient = liquid == 1u ? vec3(0.0060, 0.0028, 0.0022) : (liquid == 2u ? vec3(0.010, 0.004, 0.012) : vec3(0.004, 0.012, 0.03));
        vec3 medium = liquid == 1u ? vec3(0.02, 0.07, 0.08) : (liquid == 2u ? vec3(0.04, 0.12, 0.02) : vec3(0.9, 0.25, 0.04));
        vec3 transmittance = exp(-coefficient * dist);
        hdr = hdr * transmittance + medium * (1.0 - transmittance);
    }
    // size.z: 0 PBR Neutral (sRGB-encoded here), 1 AgX (its fit is already display-encoded).
    vec3 display = pc.size.z == 1u ? agx_look(agx(hdr * exposure), pc.params.z)
                                   : agx_look(pow(neutral(max(hdr * exposure, vec3(0.0))), vec3(1.0 / 2.2)), pc.params.z);
    display = pow(clamp(display, 0.0, 1.0), vec3(pc.params.y));
    vec4 ui = texture(textures[pc.slots.x], uv);
    color = vec4(display * (1.0 - ui.a) + ui.rgb, 1.0);
}
