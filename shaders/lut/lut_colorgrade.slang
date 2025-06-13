#version 450

/*
   This shader comines LUT shader and color grading into a single pass.
   Edited by vsvsv.

   Order of processing: [LUT] -> [Color grade]

   color-mangler shader originally by hunterk
   LUT shader is taken from Retroarch
*/

#pragma parameter lut_mix "[LUT] LUT mix, %" 100.0 0.0 100.0 1.0
#pragma parameter sep___1 "------------------------------------------" 0.0 0.0 0.0 0.0
#pragma parameter gamma_boost "[color-mangle] Gamma boost" 0.0 -5.0 5.0 0.1
#pragma parameter saturation "[color-mangle] Saturation" 1.0 0.0 3.0 0.01
#pragma parameter luminance "[color-mangle] Luminance" 1.0 0.0 5.0 0.01
#pragma parameter contrast "[color-mangle] Contrast" 1.0 0.0 2.0 0.01
#pragma parameter r "[color-mangle] Red" 1.0 0.0 2.0 0.01
#pragma parameter g "[color-mangle] Green" 1.0 0.0 2.0 0.01
#pragma parameter b "[color-mangle] Blue" 1.0 0.0 2.0 0.01
#pragma parameter rg "[color-mangle] Red-Green Tint" 0.0 0.0 1.0 0.005
#pragma parameter rb "[color-mangle] Red-Blue Tint" 0.0 0.0 1.0 0.005
#pragma parameter gr "[color-mangle] Green-Red Tint" 0.0 0.0 1.0 0.005
#pragma parameter gb "[color-mangle] Green-Blue Tint" 0.0 0.0 1.0 0.005
#pragma parameter br "[color-mangle] Blue-Red Tint" 0.0 0.0 1.0 0.005
#pragma parameter bg "[color-mangle] Blue-Green Tint" 0.0 0.0 1.0 0.005
#pragma parameter separator_1 "------------------------------------------" 0.0 0.0 0.0 0.0

layout(push_constant) uniform Push {
    float lut_mix;

    float gamma_boost;
    float saturation;
    float luminance;
    float contrast;
    float r;
    float g;
    float b;
    float rg;
    float rb;
    float gr;
    float gb;
    float br;
    float bg;
} params;

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
    //----------- Step 1: Apply LUT -----------
    vec2 LUT_Size = textureSize(SamplerLUT, 0);
    vec4 img_color = texture(Source, vTexCoord.xy);
    float red = (img_color.r * (LUT_Size.y - 1.0) + 0.499999999) / (LUT_Size.y * LUT_Size.y);
    float green = (img_color.g * (LUT_Size.y - 1.0) + 0.49999999) / LUT_Size.y;

    float blue1 = (floor(img_color.b * (LUT_Size.y - 1.0)) / LUT_Size.y) + red;
    float blue2 = (ceil(img_color.b * (LUT_Size.y - 1.0)) / LUT_Size.y) + red;

    float mixer = clamp(max((img_color.b - blue1) / (blue2 - blue1), 0.0), 0.0, 32.0);

    vec4 color1 = texture(SamplerLUT, vec2(blue1, green));
    vec4 color2 = texture(SamplerLUT, vec2(blue2, green));

    vec4 lutted_color = mixfix(color1, color2, mixer);
    vec4 color_after_lut = mix(img_color, lutted_color, params.lut_mix / 100.0);

    //----------- Step 2: Apply grading -----------
    float base_gamma = 2.2;
    vec4 screen = pow(color_after_lut, vec4(vec3(base_gamma + params.gamma_boost), 1.0));
    screen = mix(screen, vec4(0.5), (1.0 - params.contrast));

    mat4 color = mat4(
            params.r, params.rg, params.rb, 0.0, //red channel
            params.gr, params.g, params.gb, 0.0, //green channel
            params.br, params.bg, params.b, 0.0, //blue channel
            0.0, 0.0, 0.0, 1.0); //alpha channel; these numbers do nothing for our purposes.

    float sat = params.saturation;
    float isat = 1.0 - sat;
    mat4 adjust = mat4(
            isat * 0.2126 + sat, isat * 0.2126 + 0.0, isat * 0.2126 + 0.0, 1.0,
            isat * 0.7152 + 0.0, isat * 0.7152 + sat, isat * 0.7152 + 0.0, 1.0,
            isat * 0.0722 + 0.0, isat * 0.0722 + 0.0, isat * 0.0722 + sat, 1.0,
            0.0, 0.0, 0.0, 1.0);
    color *= adjust;
    screen = clamp(screen * params.luminance, 0.0, 1.0);
    screen = color * screen;
    vec4 corrected_color = pow(screen, vec4(vec3(1.0 / base_gamma), 1.0));

    FragColor = corrected_color;
}
