// SPDX-License-Identifier: GPL-2.0-or-later
// Shared declarations for compute post passes (post.zig `Push`).
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require
#extension GL_EXT_nonuniform_qualifier : require
#extension GL_EXT_shader_image_load_formatted : require

layout(set = 0, binding = 0) uniform sampler2D textures[];
layout(set = 1, binding = 0) uniform image2D images[];
layout(set = 1, binding = 1) uniform sampler3D volumes[];

layout(push_constant) uniform Push {
    uvec4 slots;     // source sampler, destination image, auxiliary sampler, auxiliary image
    uvec4 size;      // destination width, height, source width, source height
    uvec2 buffer0;   // histogram / particle buffer
    uvec2 buffer1;   // exposure / state buffer
    vec4 params;     // pass-specific
    vec4 params2;    // pass-specific
    vec4 params3;    // pass-specific
} pc;

layout(buffer_reference, std430, buffer_reference_align = 4) buffer Words { uint v[]; };
layout(buffer_reference, std430, buffer_reference_align = 4) buffer Values { float v[]; };

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 toLinearPost(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }
