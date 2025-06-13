#version 450

layout(push_constant) uniform Push {
    float comb, ln_delay, d_crawl, ntsc_blur_pixels;
    float yuv_y_mult, yuv_u_mult, yuv_v_mult;
    float src_x_scale;
} params;

// #pragma parameter ntsc_lut_delim_1 "------------------------------------------------" 0.0 0.0 0.0 1.0
#pragma parameter comb "[TINY NTSC] Comb Filter Quality (0 -> poor, 1 -> best)" 0.95 0.0 1.0 0.05
#pragma parameter ln_delay "[TINY NTSC] Line Delay - rotate abberation lines" 1.0 0.0 1.0 1.0
#pragma parameter d_crawl "[TINY NTSC] Dot Crawl - animate abberations" 1.0 0.0 1.0 1.0
#pragma parameter ntsc_blur_pixels "[TINY NTSC] Signal blur amount (pixels, 0.25 -> sharp)" 0.5 0.25 1.5 0.25
#pragma parameter src_x_scale "[TINY NTSC] Source X scale (ajust if not native)" 1.0 0.0 4.0 0.01
#pragma parameter yuv_y_mult "[TINY NTSC] YUV - luma Y multiplier" 1.0 0.0 3.0 0.01
#pragma parameter yuv_u_mult "[TINY NTSC] YUV - croma U multiplier" 1.0 0.0 3.0 0.01
#pragma parameter yuv_v_mult "[TINY NTSC] YUV - chroma V multiplier" 1.0 0.0 3.0 0.01

#define comb params.comb
#define ln_delay params.ln_delay
#define d_crawl params.d_crawl
#define ntsc_blur_pixels params.ntsc_blur_pixels

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
} global;

#define OutputSize global.OutputSize
#define SourceSize global.SourceSize
#define OriginalSize global.OriginalSize
#define FrameCount global.FrameCount

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec2 ogl2pos;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord * 1.0001;
    ogl2pos = vTexCoord * SourceSize.xy;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec2 ogl2pos;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

#define PI 3.14159265358979323846

mat3 MAT_RGB_TO_YUV = mat3(
    0.299, 0.587, 0.114,
    -0.299, -0.587, 0.886,
    0.701, -0.587, -0.114);

mat3 MAT_YUV_TO_RGB = mat3(
    1.0, 0.0, 1.13983,
    1.0, -0.39465, -0.58060,
    1.0, 2.03211, 0.0);

// max 170.666 color "dots" per line
#define NTSC_RES 170.6666

void main() {
    float pixsize = ntsc_blur_pixels;
    vec2 dxy = vec2(SourceSize.z * pixsize, 0.0);
    vec2 dy = vec2(0.0, SourceSize.w * 0.125);
    vec3 final = vec3(0.0);
    float sum = 0.0;
    float timer = 0.0;
    if (d_crawl == 1.0) timer = mod(float(FrameCount), 3.0);

    for (int i = 0; i < 2; i++) {
        float n = float(i);
        float w = exp(-0.15 * n * n); // gaussian low pass

        float line_delay = 0.0;
        if (ln_delay == 1.0) line_delay = ogl2pos.y * params.src_x_scale; // add SNES line delay

        // SNES-type line delay deployed at 170/256, 2/3 of pi(180'), 120' or 1/3 lines as in real SNES
        float phase = (ogl2pos.x + n - line_delay + timer) * PI * NTSC_RES / OriginalSize.x;

        // Comb filter line
        float phaseup = phase + PI;

        vec3 res = texture(Source, vTexCoord - dxy + dxy * n).rgb * MAT_RGB_TO_YUV;
        vec3 resup = texture(Source, vTexCoord - dxy + dxy * n + dy).rgb * MAT_RGB_TO_YUV;

        vec3 carrier = vec3(1.0, sin(phase), cos(phase));
        vec3 carrierup = vec3(1.0, sin(phaseup), cos(phaseup));

        res *= carrier;
        resup *= carrierup;

        float line = dot(vec3(0.5), res);
        float lineup = dot(vec3(0.5), resup);
        // comb luma is line adding previous line, chroma is cancelled!
        float luma = line + lineup;
        // comb chroma is line subtracting luma we already have!
        float chroma = line - luma * 0.5 * comb;
        final.r += luma * w;
        final.gb += 2.0 * vec2(chroma) * carrier.yz * w;
        sum += w;
    }

    final.rgb /= sum;
    final.rgb *= vec3(params.yuv_y_mult, params.yuv_u_mult, params.yuv_v_mult);
    FragColor.rgb = final * MAT_YUV_TO_RGB;
}

