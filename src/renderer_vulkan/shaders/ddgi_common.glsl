// SPDX-License-Identifier: GPL-2.0-or-later
// DDGI probe field (ddgi.zig): L1 spherical-harmonic irradiance per probe in four RGBA16F 3D
// textures addressed toroidally by world probe index. Texture 0: (L00, validity); textures
// 1-3: (L1-1, L10, L11 per channel order y, z, x) with the probe's world index modulo 1024 in
// alpha so stale probes after the field scrolls are ignored.
const float SH_C0 = 0.282095;
const float SH_C1 = 0.488603;

ivec3 ddgiStorage(ivec3 index, ivec3 dims) { return ((index % dims) + dims) % dims; }
vec3 ddgiTag(ivec3 index) { return vec3(((index % 1024) + 1024) % 1024); }
