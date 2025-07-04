#version 450

/*
    zfast_crt_standard - A simple, fast CRT shader.

    Copyright (C) 2017 Greg Hogan (SoltanGris42)

    This program is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2 of the License, or (at your option)
    any later version.


Notes:  This shader does scaling with a weighted linear filter for adjustable
    sharpness on the x and y axes based on the algorithm by Inigo Quilez here:
    http://http://www.iquilezles.org/www/articles/texture/texture.htm
    but modified to be somewhat sharper.  Then a scanline effect that varies
    based on pixel brighness is applied along with a monochrome aperture mask.
    This shader runs at 60fps on the Raspberry Pi 3 hardware at 2mpix/s
    resolutions (1920x1080 or 1600x1200).
*/

layout(push_constant) uniform Push {
    vec4 SourceSize;
    vec4 OriginalSize;
    vec4 OutputSize;
    uint FrameCount;
    float BLURSCALEX, LOWLUMSCAN, HILUMSCAN, BRIGHTBOOST, MASK_DARK, MASK_FADE;
} params;

#pragma parameter separator_ "----------------------------------------------------" 0.0 0.0 0.0 0.0
#pragma parameter BLURSCALEX "[zfast-crt] Blur Amount X-Axis" 0.30 0.0 1.0 0.05
#pragma parameter LOWLUMSCAN "[zfast-crt] Scanline Darkness - Low" 6.0 0.0 10.0 0.5
#pragma parameter HILUMSCAN "[zfast-crt] Scanline Darkness - High" 8.0 0.0 50.0 1.0
#pragma parameter BRIGHTBOOST "[zfast-crt] Dark Pixel Brightness Boost" 1.25 0.5 1.5 0.05
#pragma parameter MASK_DARK "[zfast-crt] Mask Effect Amount" 0.25 0.0 1.0 0.05
#pragma parameter MASK_FADE "[zfast-crt] Mask/Scanline Fade" 0.8 0.0 1.0 0.05

#define BLURSCALEX params.BLURSCALEX
#define LOWLUMSCAN params.LOWLUMSCAN
#define HILUMSCAN params.HILUMSCAN
#define BRIGHTBOOST params.BRIGHTBOOST
#define MASK_DARK params.MASK_DARK
#define MASK_FADE params.MASK_FADE

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
} global;

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 1) out float maskFade;
layout(location = 2) out vec2 invDims;

void main() {
    gl_Position = global.MVP * Position;
    vTexCoord = TexCoord;
    maskFade = 0.3333 * MASK_FADE;
    invDims = 1.0 / params.OriginalSize.xy;
}

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 1) in float maskFade;
layout(location = 2) in vec2 invDims;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;

void main() {
    //This is just like "Quilez Scaling" but sharper
    vec2 p = vTexCoord * params.OriginalSize.xy;
    vec2 i = floor(p) + 0.50;
    vec2 f = p - i;
    p = (i + 4.0 * f * f * f) * invDims;
    p.x = mix(p.x, vTexCoord.x, BLURSCALEX);
    float X = f.x * f.x;
    float XX = X * X;

    float whichmask = fract(floor(vTexCoord.y * params.OutputSize.y) * -0.3333);
    float mask = 1.0 + float(whichmask <= 0.33333) * -MASK_DARK;

    vec3 colour = texture(Source, p).rgb;

    float scanLineWeight = (BRIGHTBOOST - LOWLUMSCAN * (X - 2.05 * XX));
    float scanLineWeightB = 1.0 - HILUMSCAN * (XX - 2.8 * XX * X);

    FragColor.rgb = colour.rgb * mix(scanLineWeight * mask, scanLineWeightB, dot(colour.rgb, vec3(maskFade)));
}
