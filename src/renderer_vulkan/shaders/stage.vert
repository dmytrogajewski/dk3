#version 460
// SPDX-License-Identifier: GPL-2.0-or-later
// One Q3 material stage: vertex pulling, deforms, colour and texture-coordinate generation.
// Behaviour follows renderergl1/tr_shade_calc.c; CPU-time-only terms arrive precomputed.
#include "common.glsl"

layout(location = 0) out vec4 color;
layout(location = 1) out vec2 uv0;
layout(location = 2) out vec2 uv1;
layout(location = 3) out float eyeDepth;
layout(location = 4) out vec3 worldPos;
layout(location = 5) out vec3 worldNormal;
out gl_PerVertex { vec4 gl_Position; float gl_ClipDistance[1]; };

const float TAU = 6.283185307179586;

float wave(float func, float x) {
    x = fract(x);
    if (func == 2.0) return x < 0.5 ? 1.0 : -1.0;
    if (func == 3.0) return x < 0.25 ? 4.0 * x : (x < 0.75 ? 2.0 - 4.0 * x : 4.0 * x - 4.0);
    if (func == 4.0) return x;
    if (func == 5.0) return 1.0 - x;
    return sin(x * TAU);
}

struct Vtx { vec3 pos; vec3 normal; vec2 st; vec2 lm; vec4 color; };

// Mesh kind 3: one weather particle per six vertices, derived from its index (weather.zig).
// Where the drop of cycle `cycleIndex` lands: the first surface of the rain occlusion map under
// its slanted path (two refinements), or the volume floor; `tHit` is its fall time.
void weatherLanding(WeatherParams w, ViewData view, uint mapSlot, bool mapped, vec2 tileCoord, float local, float cycleIndex, float speed, out vec2 xy, out float z, out float tHit) {
    vec4 h = hash4(vec3(tileCoord + cycleIndex * vec2(0.618, 0.414), local));
    vec2 start = (tileCoord + h.xy) * WEATHER_TILE;
    float height = w.maxs.z - w.mins.z;
    xy = start + w.velocity.xy * (height / speed);
    z = w.mins.z;
    if (mapped) {
        float s0 = clamp(rainSurface(view, mapSlot, xy), w.mins.z, w.maxs.z);
        xy = start + w.velocity.xy * ((w.maxs.z - s0) / speed);
        z = clamp(rainSurface(view, mapSlot, xy), w.mins.z, w.maxs.z);
    }
    tHit = (w.maxs.z - z) / speed;
}

// Light reaching a drop or flake at `pos` seen from `toEye`: the light grid (ambient plus its
// dominant direction), the open sky, and dynamic lights. Drops act as tiny wide-angle lenses
// that send most light forward, so lights behind a drop make it glint (Garg & Nayar 2006).
vec3 weatherLight(Record r, WeatherParams w, vec3 pos, vec3 toEye, bool snow) {
    float g = snow ? 0.2 : 0.75;
    vec3 light = vec3(0.12);
    if (w.grid0.w > 0.5) {
        vec3 uvw = (pos - w.grid0.xyz) * w.grid1.xyz;
        vec3 grid = toLinear(texture(volumes[nonuniformEXT(uint(w.grid0.w) - 1u)], uvw).rgb);
        // A drop refracts its bright surroundings (165 degree field), so it reads a little
        // brighter than the scene's ambient light.
        light = grid * 0.45;
        if (w.grid1.w > 0.5) {
            vec4 d = texture(volumes[nonuniformEXT(uint(w.grid1.w) - 1u)], uvw);
            vec3 l = normalize(d.xyz * 2.0 - 1.0);
            light += grid * d.a * 0.1 * phaseHG4pi(dot(-l, toEye), g);
        }
    }
    light += w.sky.rgb * 0.3;
    Lights lights = Lights(r.lights);
    uint count = min(r.counts.z, 32u);
    for (uint k = 0u; k < count; ++k) {
        vec4 a = lights.v[k * 2u], b = lights.v[k * 2u + 1u];
        vec3 toLight = a.xyz - pos;
        float dist = length(toLight);
        if (dist >= a.w) continue;
        float fall = 1.0 - dist / a.w;
        light += toLinear(b.rgb) * fall * fall * 0.15 * phaseHG4pi(dot(-toLight / max(dist, 1e-3), toEye), g);
    }
    return light;
}

// Rain gusts: large drifting cells of denser and thinner rain.
float weatherGust(WeatherParams w, vec2 xy, float time) {
    vec2 drift = w.velocity.xy * 0.25 * time + vec2(time * 40.0, time * 23.0);
    return mix(0.4, 1.0, valueNoise((xy - drift) / 1500.0));
}

Vtx weatherParticle(Record r, uint index) {
    Vtx v;
    WeatherParams w = WeatherParams(r.vertices);
    uint particle = index / 6u;
    uint corner = index % 6u;
    vec2 q = corner == 0u ? vec2(0.0, 0.0) : corner == 1u || corner == 4u ? vec2(1.0, 0.0) : corner == 2u || corner == 3u ? vec2(0.0, 1.0) : vec2(1.0, 1.0);
    v.st = q;
    v.lm = vec2(0.0);
    v.normal = vec3(0.0, 0.0, 1.0);
    v.color = vec4(0.0);
    v.pos = w.eye.xyz;
    uint perTile = uint(w.tiles.w);
    uint tile = particle / max(perTile, 1u);
    uint row = uint(w.tiles.z);
    vec2 tileCoord = w.tiles.xy + vec2(float(tile % row), float(tile / row));
    float local = float(particle % max(perTile, 1u));
    bool snow = w.mins.w > 0.5;
    float time = w.maxs.w;
    float height = w.maxs.z - w.mins.z;
    vec4 h0 = hash4(vec3(tileCoord, local + w.velocity.w * 0.37));
    // Rain: drop diameter 1-3 mm (inches here), skewed small; terminal velocity from the
    // Gunn-Kinzer fit v = 9.65 - 10.3 exp(-0.6 D[mm]) m/s, 160-310 in/s.
    float diameter = mix(0.04, 0.12, h0.w * h0.w);
    float speed = snow ? max(-w.velocity.z, 1.0) * (0.75 + 0.5 * h0.w)
                       : (9.65 - 10.3 * exp(-0.6 * diameter * 25.4)) * 39.37;
    float cycle = time * speed / height + h0.z;
    float f = fract(cycle);
    float cycleIndex = floor(cycle);
    bool splash = w.eye.w > 0.5;
    // Rain occlusion map (shadows.zig rainCamera): nothing falls under a roof.
    ViewData view = ViewData(r.view);
    bool mapped = false;
    uint mapSlot = 0u;
    if (r.view != uvec2(0u)) {
        mapped = view.rain.w > 0.5;
        mapSlot = view.shadows.y;
    }
    if (splash) {
        if (h0.x > 0.7) return v;
        // The landing of this cycle's drop, or of the previous one just after a cycle wrap.
        float elapsed = f * height / speed;
        vec2 xy;
        float z, tHit;
        weatherLanding(w, view, mapSlot, mapped, tileCoord, local, cycleIndex, speed, xy, z, tHit);
        float age = elapsed - tHit;
        if (age < 0.0) {
            weatherLanding(w, view, mapSlot, mapped, tileCoord, local, cycleIndex - 1.0, speed, xy, z, tHit);
            age = elapsed + height / speed - tHit;
        }
        // A crown 0.5-1.5 in across lasting 60-120 ms; drops landing in puddles only ripple.
        float life = mix(0.06, 0.12, h0.y);
        if (age < 0.0 || age > life) return v;
        if (any(lessThan(xy, w.mins.xy)) || any(greaterThan(xy, w.maxs.xy))) return v;
        if (puddleNoise(xy) > 0.5) return v;
        vec3 base = vec3(xy, z + 0.1);
        vec3 toEye = w.eye.xyz - base;
        float dist = length(toEye);
        toEye /= max(dist, 1e-3);
        float t = age / life;
        float radius = mix(0.5, 1.5, h0.x / 0.7) * (0.4 + 0.6 * sqrt(t));
        float pixel = w.shape.y * dist;
        float coverage = clamp(2.0 * radius / max(pixel, 1e-4), 0.0, 1.0);
        vec3 right = normalize(cross(vec3(0.0, 0.0, 1.0), toEye) + vec3(1e-4, 0.0, 0.0)) * max(radius, pixel * 0.5);
        vec3 up = vec3(0.0, 0.0, max(radius * 1.2, pixel));
        v.pos = base + right * (q.x * 2.0 - 1.0) + up * q.y;
        v.color.rgb = weatherLight(r, w, base, toEye, false);
        v.color.a = w.shape.z * 1.5 * coverage * (1.0 - t) * (1.0 - smoothstep(600.0, 800.0, dist));
        return v;
    }
    vec4 h = hash4(vec3(tileCoord + cycleIndex * vec2(0.618, 0.414), local));
    float fallTime = f * height / speed;
    vec2 start = (tileCoord + h.xy) * WEATHER_TILE;
    vec3 pos = vec3(start + w.velocity.xy * fallTime, w.maxs.z - f * height);
    if (snow) pos.xy += vec2(sin(time * 0.9 + h.z * 6.283), cos(time * 0.7 + h.w * 6.283)) * (10.0 + 8.0 * h.z);
    if (any(lessThan(pos.xy, w.mins.xy)) || any(greaterThan(pos.xy, w.maxs.xy))) return v;
    if (mapped && pos.z < rainSurface(view, mapSlot, pos.xy) - 1.0) return v;
    vec3 toEye = w.eye.xyz - pos;
    float dist = length(toEye);
    toEye /= max(dist, 1e-3);
    float gust = weatherGust(w, pos.xy, time);
    v.color.rgb = weatherLight(r, w, pos, toEye, snow);
    if (snow) {
        float alpha = w.shape.z * smoothstep(8.0, 48.0, dist) * (1.0 - smoothstep(1400.0, 2000.0, dist));
        vec3 right = normalize(cross(vec3(0.0, 0.0, 1.0), toEye) + vec3(1e-4, 0.0, 0.0));
        vec3 up = cross(toEye, right);
        float size = 2.2 * (0.7 + 0.6 * h.w) * (1.0 + dist * 0.0015);
        v.pos = pos + (right * (q.x * 2.0 - 1.0) + up * (q.y * 2.0 - 1.0)) * size;
        v.color.a = alpha * gust;
        return v;
    }
    // Streak: the drop's path during the exposure, at least one pixel wide. Coverage-preserving
    // alpha keeps a far streak as faint as the drop really is, instead of a widening grey bar.
    vec3 dir = normalize(vec3(w.velocity.xy, -speed));
    float pixel = w.shape.y * dist;
    float width = max(diameter, pixel);
    float len = max(speed * w.shape.x, pixel * 2.0);
    vec3 right = normalize(cross(dir, toEye) + vec3(1e-4, 0.0, 0.0)) * width;
    v.pos = pos + right * (q.x * 2.0 - 1.0) - dir * len * q.y;
    float near = smoothstep(4.0, 24.0, dist);
    float far = 1.0 - smoothstep(600.0, 800.0, dist);
    // Coverage falls off a little slower than the true drop/pixel ratio: heavy rain reads as
    // a dense field of fine streaks, as it does on camera.
    v.color.a = w.shape.z * pow(diameter / width, 0.6) * near * far * gust;
    return v;
}

Vtx fetch(Record r, uint index) {
    Vtx v;
    uint kind = r.mode.x;
    if (kind == 3u) return weatherParticle(r, index);
    if (kind == 1u) {
        // MD3: two frames of (position, normal), linear blend; separate texture coordinates.
        Floats a = Floats(r.vertices), b = Floats(r.frameB), st = Floats(r.extra);
        uint o = index * 6u;
        vec3 pa = vec3(a.v[o], a.v[o + 1u], a.v[o + 2u]), na = vec3(a.v[o + 3u], a.v[o + 4u], a.v[o + 5u]);
        vec3 pb = vec3(b.v[o], b.v[o + 1u], b.v[o + 2u]), nb = vec3(b.v[o + 3u], b.v[o + 4u], b.v[o + 5u]);
        float back = r.misc.x;
        v.pos = mix(pa, pb, back);
        v.normal = normalize(mix(na, nb, back));
        v.st = vec2(st.v[index * 2u], st.v[index * 2u + 1u]);
        v.lm = vec2(0.0);
        v.color = vec4(1.0);
    } else if (kind == 2u) {
        // IQM: linear-blend skinning with row-major 3x4 bone matrices.
        Floats f = Floats(r.vertices);
        Uints u = Uints(r.vertices);
        Floats bones = Floats(r.extra);
        uint o = index * 12u;
        vec4 p = vec4(f.v[o], f.v[o + 1u], f.v[o + 2u], 1.0);
        vec3 n = vec3(f.v[o + 3u], f.v[o + 4u], f.v[o + 5u]);
        v.st = vec2(f.v[o + 6u], f.v[o + 7u]);
        uvec4 bi = (uvec4(u.v[o + 8u]) >> uvec4(0, 8, 16, 24)) & 255u;
        vec4 bw = vec4((uvec4(u.v[o + 9u]) >> uvec4(0, 8, 16, 24)) & 255u) / 255.0;
        v.color = unpackUnorm4x8(u.v[o + 10u]);
        if (r.extra != uvec2(0u) && bw.x > 0.0) {
            vec3 sp = vec3(0.0), sn = vec3(0.0);
            for (int k = 0; k < 4; ++k) {
                if (bw[k] == 0.0) continue;
                uint m = bi[k] * 12u;
                vec4 r0 = vec4(bones.v[m], bones.v[m + 1u], bones.v[m + 2u], bones.v[m + 3u]);
                vec4 r1 = vec4(bones.v[m + 4u], bones.v[m + 5u], bones.v[m + 6u], bones.v[m + 7u]);
                vec4 r2 = vec4(bones.v[m + 8u], bones.v[m + 9u], bones.v[m + 10u], bones.v[m + 11u]);
                sp += bw[k] * vec3(dot(r0, p), dot(r1, p), dot(r2, p));
                sn += bw[k] * vec3(dot(r0.xyz, n), dot(r1.xyz, n), dot(r2.xyz, n));
            }
            v.pos = sp;
            v.normal = length(sn) > 0.0 ? normalize(sn) : n;
        } else {
            v.pos = p.xyz;
            v.normal = n;
        }
        v.lm = vec2(0.0);
    } else {
        Floats f = Floats(r.vertices);
        Uints u = Uints(r.vertices);
        uint o = index * 12u;
        v.pos = vec3(f.v[o], f.v[o + 1u], f.v[o + 2u]);
        v.st = vec2(f.v[o + 3u], f.v[o + 4u]);
        v.lm = vec2(f.v[o + 5u], f.v[o + 6u]);
        v.normal = vec3(f.v[o + 7u], f.v[o + 8u], f.v[o + 9u]);
        v.color = unpackUnorm4x8(u.v[o + 10u]);
    }
    return v;
}

vec3 deformed(Record r, Vtx v) {
    // deform[2k] = (type + 10 * waveFunc, ...), deform[2k + 1] = wave or move parameters.
    vec3 pos = v.pos;
    float time = r.viewOrigin.w;
    for (uint k = 0u; k < r.counts.y; ++k) {
        vec4 a = r.deform[k * 2u], b = r.deform[k * 2u + 1u];
        float type = mod(a.x, 10.0), func = floor(a.x / 10.0);
        if (type == 1.0) {            // wave: (base, amplitude, phase) | (frequency, spread)
            float off = (pos.x + pos.y + pos.z) * b.y;
            pos += v.normal * (a.y + wave(func, a.w + off + time * b.x) * a.z);
        } else if (type == 3.0) {     // bulge: (width, height, speed)
            pos += v.normal * sin(v.st.x * a.y + time * a.w) * a.z;
        } else if (type == 4.0) {     // move: (vector) | (base, amplitude, phase, frequency)
            pos += a.yzw * (b.x + wave(func, b.z + time * b.w) * b.y);
        }
    }
    return pos;
}

vec2 texgen(Record r, uint gen, Vtx v, vec3 pos) {
    if (gen == 1u) return v.lm;
    if (gen == 2u) {
        vec3 viewer = normalize(r.viewOrigin.xyz - pos);
        float d = dot(v.normal, viewer);
        vec3 reflected = v.normal * 2.0 * d - viewer;
        return vec2(0.5 + reflected.y * 0.5, 0.5 - reflected.z * 0.5);
    }
    if (gen == 3u) return vec2(dot(pos, r.tcGenVector[0].xyz), dot(pos, r.tcGenVector[1].xyz));
    if (gen == 4u) return vec2(0.0);
    return v.st;
}

vec2 texmods(Record r, vec2 st, vec3 pos) {
    for (uint k = 0u; k < r.counts.x; ++k) {
        vec4 a = r.tcmod[k * 2u], b = r.tcmod[k * 2u + 1u];
        if (a.x == 1.0) {
            // turb: amplitude, now (phase + time * frequency)
            vec2 t = st;
            st.x = t.x + sin(((pos.x + pos.z) * (1.0 / 128.0) * 0.125 + a.z) * TAU) * a.y;
            st.y = t.y + sin((pos.y * (1.0 / 128.0) * 0.125 + a.z) * TAU) * a.y;
        } else {
            // affine: s' = a.y*s + a.z*t + b.x ; t' = a.w*s + b.y*t + b.z
            st = vec2(a.y * st.x + a.z * st.y + b.x, a.w * st.x + b.y * st.y + b.z);
        }
    }
    return st;
}

void main() {
    Record r = Record(push.record);
    uint index = r.mode.x == 3u ? uint(gl_VertexIndex) : Uints(r.indices).v[gl_VertexIndex];
    Vtx v = fetch(r, index);
    vec3 pos = deformed(r, v);
    vec4 p = vec4(pos, 1.0);
    gl_Position = r.clip * p;
    eyeDepth = -dot(r.modelView[2], p);
    worldPos = vec3(dot(r.model[0], p), dot(r.model[1], p), dot(r.model[2], p));
    vec3 wn = vec3(dot(r.model[0].xyz, v.normal), dot(r.model[1].xyz, v.normal), dot(r.model[2].xyz, v.normal));
    worldNormal = dot(wn, wn) > 0.0 ? normalize(wn) : vec3(0.0, 0.0, 1.0);
    gl_ClipDistance[0] = (r.mode2.z & FLAG_CLIP) != 0u ? dot(worldPos, r.clipPlane.xyz) - r.clipPlane.w : 1.0;

    vec4 c = r.constColor;
    uint rgb = r.mode.y, alpha = r.mode.z;
    if (rgb == 1u) c.rgb = v.color.rgb * r.ambient.w;
    else if (rgb == 2u) c.rgb = vec3(1.0) - v.color.rgb * r.ambient.w;
    else if (rgb == 3u) {
        float incoming = dot(v.normal, r.lightDir.xyz);
        c.rgb = min(r.ambient.rgb + max(incoming, 0.0) * r.directed.rgb, vec3(1.0));
    } else if (rgb == 4u) c.rgb = v.color.rgb;
    if (alpha == 1u) c.a = v.color.a;
    else if (alpha == 2u) c.a = 1.0 - v.color.a;
    else if (alpha == 3u) {
        vec3 lightDir = normalize(vec3(-960.0, 1980.0, 96.0) - pos);
        float d = dot(v.normal, lightDir);
        vec3 reflected = v.normal * 2.0 * d - lightDir;
        vec3 viewer = r.viewOrigin.xyz - pos;
        float l = dot(reflected, viewer) / max(length(viewer), 1e-4);
        l = l < 0.0 ? 0.0 : l * l * l * l;
        c.a = min(l, 1.0);
    } else if (alpha == 4u) {
        c.a = clamp(distance(pos, r.viewOrigin.xyz) / max(r.lightDir.w, 1e-4), 0.0, 1.0);
    }
    color = c;
    uv0 = texmods(r, texgen(r, r.mode.w, v, pos), pos);
    uv1 = v.lm;
}
