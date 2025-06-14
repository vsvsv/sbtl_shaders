#version 450

// See dual_filter.inc for copyright and other information.

#include "include/parameters.inc"
#include "include/parameters_bloom.inc"

layout(push_constant) uniform Push {
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
    float ADAPT_SPEED;
} param;

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D MovingAverageFeedback;

void main() {
    vec3 mavg_fb_pixel = texture(MovingAverageFeedback, vTexCoord).rgb;
    vec3 lod_pixel = textureLod(Source, vTexCoord, 9000.1).rgb;
    vec3 adjusted = mix(mavg_fb_pixel, lod_pixel, param.ADAPT_SPEED);
    FragColor = vec4(adjusted, 1.0);
}
