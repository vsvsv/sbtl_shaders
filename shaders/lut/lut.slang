#version 450

layout(push_constant) uniform Push {
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
    float lut_mix;
} params;

#pragma parameter lut_mix "[LUT] LUT mix, %" 100.0 0.0 100.0 1.0
#pragma parameter sep___1 "------------------------------------------" 0.0 0.0 0.0 0.0

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;

void main()
{
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord * 1.0001;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D SamplerLUT;

// This shouldn't be necessary but it seems some undefined values can
// creep in and each GPU vendor handles that differently. This keeps
// all values within a safe range
vec4 mixfix(vec4 a, vec4 b, float c) {
    return (a.z < 1.0) ? mix(a, b, c) : a;
}

void main() {
    vec2 LUT_Size = textureSize(SamplerLUT, 0);
    vec4 img_color = texture(Source, vTexCoord.xy);
    float red = (img_color.r * (LUT_Size.y - 1.0) + 0.499999999) / (LUT_Size.y * LUT_Size.y);
    float green = (img_color.g * (LUT_Size.y - 1.0) + 0.49999999) / LUT_Size.y;

    float blue1 = (floor(img_color.b * (LUT_Size.y - 1.0)) / LUT_Size.y) + red;
    float blue2 = (ceil(img_color.b * (LUT_Size.y - 1.0)) / LUT_Size.y) + red;

    float mixer = clamp(max((img_color.b - blue1) / (blue2 - blue1), 0.0), 0.0, 32.0);

    vec4 color1 = texture(SamplerLUT, vec2(blue1, green));
    vec4 color2 = texture(SamplerLUT, vec2(blue2, green));

    vec4 result_color = mixfix(color1, color2, mixer);
    FragColor = mix(img_color, result_color, params.lut_mix / 100.0);
}
