#version 450

/*
    sbtl_lcd v1.0 shader

    The goal is to simulate RGB subpixel grid of typical consumer-grade LCD screen,
    while not targeting specific ones.

    This shader assumes [R][G][B] subpixel order. To change the order edit `rgb_offsets` contant.

    By: vsvsv (https://github.com/vsvsv)
    Licence: MIT
*/

#pragma parameter strength "[sbtl_lcd] Overall Effect Strength, %" 100.0 0.0 100.0 1.0
#pragma parameter vlc_mix "[sbtl_lcd] Vert. RGB Subpixel Mix, %" 100.0 1.0 100.0 1.0
#pragma parameter vlg_mix "[sbtl_lcd] Vert. Grayscale Line Mix, %" 0.0 1.0 100.0 1.0
#pragma parameter vl_brt "[sbtl_lcd] Vert. Line Brightness" 4.0 1.0 64.0 0.25
#pragma parameter hl_brt "[sbtl_lcd] Horiz. Line Brightness" 16.0 1.0 32.0 0.5
#pragma parameter brightness "[sbtl_lcd] Output Brightness, %" 100.0 50.0 300.0 1.0

layout(push_constant) uniform Push {
    vec4 OutputSize;
    vec4 OriginalSize;
    float strength;
    float vlg_mix;
    float vlc_mix;
    float vl_brt;
    float hl_brt;
    float brightness;
} params;

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
} global;

#pragma stage vertex

layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec2 lcd_size;
layout(location = 2) out vec2 out_size;
layout(location = 3) out vec2 scr_ratio;
layout(location = 4) out float brightness;
layout(location = 5) out float vl_brt;
layout(location = 6) out float hl_brt;
layout(location = 7) out float strength;
layout(location = 8) out float vlc_mix;
layout(location = 9) out float vlg_mix;

// Vertex shader entry point
void main() {
    lcd_size = params.OriginalSize.xy;
    out_size = params.OutputSize.xy;
    scr_ratio = out_size / lcd_size;

    brightness = params.brightness / 100.0;
    strength = params.strength / 100.0;
    vlc_mix = params.vlc_mix / 100.0;
    vlg_mix = params.vlg_mix / 100.0;
    vl_brt = params.vl_brt;
    hl_brt = params.hl_brt;

    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord * 1.000001;
}

#pragma stage fragment

layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec2 lcd_size;
layout(location = 2) in vec2 out_size;
layout(location = 3) in vec2 scr_ratio;
layout(location = 4) in float brightness;
layout(location = 5) in float vl_brt;
layout(location = 6) in float hl_brt;
layout(location = 7) in float strength;
layout(location = 8) in float vlc_mix;
layout(location = 9) in float vlg_mix;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

#define PI 3.14159265359

vec3 rgb2yuv(vec3 rgb) {
    float y = 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b;
    return vec3(y, 0.493 * (rgb.b - y), 0.877 * (rgb.r - y));
}

// vec3 yuv2rgb(vec3 yuv) {
//     float y = yuv.x;
//     float u = yuv.y;
//     float v = yuv.z;
//     return vec3(
//         y + 1.0 / 0.877 * v,
//         y - 0.39393 * u - 0.58081 * v,
//         y + 1.0 / 0.493 * u
//     );
// }

// Fragment shader entry point
void main() {
    vec2 src_pix_f = vTexCoord * lcd_size;
    vec2 src_pix_i = floor(src_pix_f);
    vec2 subpix_pos = src_pix_f - src_pix_i;

    vec3 in_pix = texture(Source, (src_pix_i + vec2(0.5, 0.5)) / lcd_size).rgb;
    vec3 out_pix = in_pix;

    if (vlc_mix > 0.02) {
        vec3 in_pix_r = texture(Source, (src_pix_i + vec2(1.5, 0.5)) / lcd_size).rgb;
        vec3 in_pix_l = texture(Source, (src_pix_i + vec2(-0.5, 0.5)) / lcd_size).rgb;

        vec2 pix_pos = vTexCoord.xy * out_size;
        // Center of each subpixel, in a scale of 0..1, where 0 -> left corner of a pixel, 1 -> right corner
        const vec3 rgb_offsets = vec3(-1, 0, 1) * 0.3333 + 0.5;

        // Generate RGB subpixel coloring
        const float subpixel_glow = 2.0;
        float peripheral_glow = 0.4 / (scr_ratio.x / 7.0);

        vec3 sp_glow = vec3(1.0 / subpixel_glow);
        vec3 pr_glow = vec3(1.0 / peripheral_glow);

        const float bright_adj = 0.7;
        vec3 x = 1.0 - abs(rgb_offsets - vec3(subpix_pos.x));
        vec3 weight = bright_adj * (pow(x, sp_glow) + pow(x, sp_glow * 2 + pow(x, sp_glow * 0.5)));

        vec3 x_r = 1.0 - min(abs(rgb_offsets + vec3(1) - vec3(subpix_pos.x)), 1);
        vec3 weight_r = bright_adj * (pow(x_r, pr_glow) + pow(x_r, pr_glow * 2));

        vec3 x_l = 1.0 - min(abs(rgb_offsets - vec3(1) - vec3(subpix_pos.x)), 1);
        vec3 weight_l = bright_adj * (pow(x_l, pr_glow) + pow(x_l, pr_glow * 2));

        out_pix = (in_pix * weight + in_pix_r * weight_r + in_pix_l * weight_l) * vec3(1.0, 0.95, 1.0);

        vec3 in_pix_yuv = rgb2yuv(in_pix);
        out_pix = mix(in_pix, out_pix, 0.2 + 1 - abs(in_pix_yuv.x - 0.5) * 2);
        out_pix = mix(in_pix, out_pix, vlc_mix);
    }

    vec2 angle = 2.0 * PI * (src_pix_f - 0.25);
    if (vlg_mix > 0.01) {
        // Generate grayscale vertical lines
        float vlines = (vl_brt + sin(angle.x)) / (vl_brt + 1.0);
        out_pix = mix(out_pix, out_pix * vlines, vlg_mix);
    }

    // Add horizontal lines
    float hlines = (hl_brt + sin(angle.y)) / (hl_brt + 1.0);
    out_pix *= hlines;

    out_pix = mix(in_pix, out_pix, strength);
    FragColor = vec4(out_pix * brightness, 1.0);
}
