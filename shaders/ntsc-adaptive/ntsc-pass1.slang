#version 450

// NTSC-Adaptive Pass1
// based on Themaister's NTSC shader

layout(push_constant) uniform Push
{
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    uint FrameCount;
    float quality, ntsc_sat, ntsc_bright, ntsc_scale, ntsc_phase, ntsc_gamma, ntsc_taps, auto_res;
} params;

layout(std140, set = 0, binding = 0) uniform UBO
{
    mat4 MVP;
} global;

#pragma parameter ntsc-row0 "------------------------------------------------" 0.0 0.0 0.0 1.0
#pragma parameter auto_res    "SNES/Amiga Hi-Res Auto Mode (off/on)" 0.0 0.0 1.0 1.0
#pragma parameter ntsc_phase  "NTSC Phase (1->Auto | 2 phase | 3 phase | 4->Mixed)" 1.0 1.0 4.0 1.0
#pragma parameter ntsc_scale  "NTSC Resolution Scaling" 1.0 0.20 2.5 0.025
#pragma parameter ntsc_sat    "NTSC Color Saturation" 1.25 0.0 2.0 0.01
#pragma parameter ntsc_bright "NTSC Brightness" 1.0 0.0 1.5 0.01
#pragma parameter ntsc_gamma  "NTSC Filtering Gamma Correction" 1.0 0.25 2.5 0.025
#pragma parameter ntsc-row3 "------------------------------------------------" 0.0 0.0 0.0 1.0
#pragma parameter ntsc_taps   "NTSC # of Taps (Filter Width)" 6.0 6.0 32.0 1.0

float FrameCount = float(params.FrameCount);
float auto_rez = mix(1.0, 0.5, clamp(params.auto_res * round(params.OriginalSize.x / 300.0) - 1.0, 0.0, 1.0));
#define ntsc_scale params.ntsc_scale * auto_rez

#define PI 3.14159265

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out vec2 pix_no;
layout(location = 2) out float phase;
layout(location = 3) out float BRIGHTNESS;
layout(location = 4) out float SATURATION;
layout(location = 7) out float CHROMA_MOD_FREQ;
layout(location = 8) out float MERGE;

void main()
{
    float res = min(ntsc_scale, 1.0);
    float OriginalSize = params.OriginalSize.x * auto_rez;
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
    pix_no = TexCoord * params.OriginalSize.xy * vec2(res, res / auto_rez) * vec2(4.0, 1.0);

    phase = (params.ntsc_phase < 1.5) ? ((OriginalSize > 300.0) ? 2.0 : 3.0) : ((params.ntsc_phase > 2.5) ? 3.0 : 2.0);
    if (params.ntsc_phase == 4.0) phase = 3.0;

    CHROMA_MOD_FREQ = (phase < 2.5) ? (4.0 * PI / 15.0) : (PI / 3.0);
    SATURATION = params.ntsc_sat;
    BRIGHTNESS = params.ntsc_bright;
    MERGE = 0.0 + float(phase == 3.0);
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in vec2 pix_no;
layout(location = 2) in float phase;
layout(location = 3) in float BRIGHTNESS;
layout(location = 4) in float SATURATION;
layout(location = 7) in float CHROMA_MOD_FREQ;
layout(location = 8) in float MERGE;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

const mat3 yiq2rgb_mat = mat3(
        1.0, 0.956, 0.6210,
        1.0, -0.2720, -0.6474,
        1.0, -1.1060, 1.7046);

vec3 yiq2rgb(vec3 yiq) {
    return yiq * yiq2rgb_mat;
}

const mat3 yiq_mat = mat3(
        0.2989, 0.5870, 0.1140,
        0.5959, -0.2744, -0.3216,
        0.2115, -0.5229, 0.3114
    );

vec3 rgb2yiq(vec3 col) {
    return col * yiq_mat;
}

float get_luma(vec3 c) {
    return dot(c, vec3(0.2989, 0.5870, 0.1140));
}

float my_smoothstep(float e0, float e1, float x) {
    return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
}

void main()
{
    float res = ntsc_scale;
    float mit = params.ntsc_taps;
    mit = my_smoothstep(16.0, 8.0, mit) * 0.325;

    vec3 col = texture(Source, vTexCoord).rgb;

    vec3 yiq = rgb2yiq(col);
    yiq.x = pow(yiq.x, params.ntsc_gamma);
    float lum = yiq.x;

    vec2 dx = vec2(params.OriginalSize.z / auto_rez, 0.0);
    float c1 = get_luma(texture(Source, vTexCoord - dx).rgb);
    float c2 = get_luma(texture(Source, vTexCoord + dx).rgb);

    if (params.ntsc_phase == 4.0)
    {
        float mix01 = min(5.0 * abs(c1 - c2), 1.0);
        c1 = pow(c1, params.ntsc_gamma);
        c2 = pow(c2, params.ntsc_gamma);
        yiq.x = mix(min(0.5 * (yiq.x + max(c1, c2)), max(yiq.x, min(c1, c2))), yiq.x, mix01);
    }
    vec3 yiq2 = yiq;
    vec3 yiqs = yiq;
    vec3 yiqz = yiq;
    vec3 tmp = yiq;

    vec3 brightness_and_saturation = vec3(BRIGHTNESS, 2.0 * SATURATION, 2.0 * SATURATION);

    if (MERGE > 0.5) {
        float chroma_phase2 = (phase < 2.5) ? PI * (mod(pix_no.y, 2.0) + mod(FrameCount + 1.0, 2.0)) : 0.6667 * PI * (mod(pix_no.y, 3.0) + mod(FrameCount + 1.0, 2.0));
        float mod_phase2 = chroma_phase2 + pix_no.x * CHROMA_MOD_FREQ;
        float i_mod2 = cos(mod_phase2);
        float q_mod2 = sin(mod_phase2);
        yiq2.yz *= vec2(i_mod2, q_mod2); // Modulate.
        yiq2 *= brightness_and_saturation; // Cross-talk.
        yiq2.yz *= vec2(i_mod2, q_mod2); // Demodulate.
        yiq2.yz = mix(yiq2.yz, tmp.yz, mit);

        if (res > 1.025) {
            mod_phase2 = chroma_phase2 + pix_no.x * CHROMA_MOD_FREQ * res;
            i_mod2 = cos(mod_phase2);
            q_mod2 = sin(mod_phase2);
            yiqs.yz *= vec2(i_mod2, q_mod2); // Modulate.
            yiq2.x = yiqs.x * brightness_and_saturation[0];
        }
    }

    float chroma_phase = (phase < 2.5) ? PI * (mod(pix_no.y, 2.0) + mod(FrameCount, 2.0)) : 0.6667 * PI * (mod(pix_no.y, 3.0) + mod(FrameCount, 2.0));
    float mod_phase = chroma_phase + pix_no.x * CHROMA_MOD_FREQ;
    float i_mod = cos(mod_phase);
    float q_mod = sin(mod_phase);
    yiq.yz *= vec2(i_mod, q_mod); // Modulate.
    yiq *= brightness_and_saturation; // Cross-talk.
    yiq.yz *= vec2(i_mod, q_mod); // Demodulate.
    yiq.yz = mix(yiq.yz, tmp.yz, mit);

    if (res > 1.025) {
        mod_phase = chroma_phase + pix_no.x * CHROMA_MOD_FREQ * res;
        i_mod = cos(mod_phase);
        q_mod = sin(mod_phase);
        yiqz.yz *= vec2(i_mod, q_mod); // Modulate.
        yiq.x = yiqz.x * brightness_and_saturation[0];
    }

    if (params.ntsc_phase == 4.0) {
        yiq.x = lum;
        yiq2.x = lum;
    }

    if (MERGE > 0.5) {
        yiq = 0.5 * (yiq + yiq2);
    }

    FragColor = vec4(yiq, lum);
}
