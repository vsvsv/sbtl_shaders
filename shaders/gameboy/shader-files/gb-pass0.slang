#version 450

layout(push_constant) uniform Push {
    vec4 OutputSize;
    vec4 OriginalSize;
    vec4 SourceSize;
    vec4 OriginalHistorySize1;
    float baseline_alpha;
    float grey_balance;
    float response_time;
    float video_scale;
    float color_toggle;
    float grid_intensity;
} registers;

layout(std140, set = 0, binding = 0) uniform UBO {
    mat4 MVP;
} global;

////////////////////////////////////////////////////////////////////////////////
// Config                                                                     //
////////////////////////////////////////////////////////////////////////////////

#pragma parameter color_toggle "Color Toggle" 0.0 0.0 1.0 1.0 // Toggle between color (1.0) and greyscale (0.0)

// The alpha value of dots in their "off" state
// Does not affect the border region of the screen - [0, 1]
#pragma parameter baseline_alpha "Baseline Alpha" 0.10 0.0 1.0 0.01

// How strong the grid between pixels is
#pragma parameter grid_intensity "Grid Intensity" 1.0 0.0 1.0 0.01

// Fine-tune the balance between the different shades of grey
#pragma parameter grey_balance "Grey Balance" 3.0 2.0 4.0 0.1

// Set video scale when used in console-border shaders
#pragma parameter video_scale "Video Scale" 3.0 3.0 5.0 1.0

///////////////////////////////////////////////////////////////////////////
//                                                                       //
// Gameboy Classic Shader v0.2.2                                         //
//                                                                       //
// Copyright (C) 2013 Harlequin : unknown92835@gmail.com                 //
//                                                                       //
// Modified 2/6/24 to support color output by mattakins.                 //
//                                                                       //
// This program is free software: you can redistribute it and/or modify  //
// it under the terms of the GNU General Public License as published by  //
// the Free Software Foundation, either version 3 of the License, or     //
// (at your option) any later version.                                   //
//                                                                       //
// This program is distributed in the hope that it will be useful,       //
// but WITHOUT ANY WARRANTY; without even the implied warranty of        //
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         //
// GNU General Public License for more details.                          //
//                                                                       //
// You should have received a copy of the GNU General Public License     //
// along with this program.  If not, see <http://www.gnu.org/licenses/>. //
//                                                                       //
///////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Vertex shader                                                              //
////////////////////////////////////////////////////////////////////////////////

#pragma stage vertex
layout(location = 0) in vec4 Position;
layout(location = 1) in vec2 TexCoord;
layout(location = 0) out vec2 vTexCoord;
layout(location = 2) out vec2 dot_size;
layout(location = 3) out vec2 one_texel;

////////////////////////////////////////////////////////////////////////////////
// Vertex definitions                                                         //
////////////////////////////////////////////////////////////////////////////////

// Largest integer scale of input video that will fit in the current output (y axis would typically be limiting on widescreens)
//#define video_scale         floor(registers.OutputSize.y * registers.SourceSize.w) <- moved to parameter

// Size of the scaled video
//#define scaled_video_out    (registers.SourceSize.xy * vec2(video_scale)) <- moved to parameter

//it's... half a pixel
#define half_pixel          (vec2(0.5) * registers.OutputSize.zw)

void main() {
    float video_scale_factor = floor(registers.OutputSize.y * registers.SourceSize.w);
    vec2 scaled_video_out = (registers.SourceSize.xy * vec2(video_scale_factor));
    // Remaps position to integer scaled output
    gl_Position = global.MVP * Position / vec4(vec2(registers.OutputSize.xy / scaled_video_out), 1.0, 1.0);
    vTexCoord = TexCoord * 1.0001; // + half_pixel;
    dot_size = registers.SourceSize.zw;
    one_texel = 1.0 / (registers.SourceSize.xy * video_scale_factor);
}

////////////////////////////////////////////////////////////////////////////////
// Fragment shader                                                            //
////////////////////////////////////////////////////////////////////////////////

#pragma stage fragment
layout(location = 0) in vec2 vTexCoord;
layout(location = 2) in vec2 dot_size;
layout(location = 3) in vec2 one_texel;
layout(location = 0) out vec4 FragColor;
layout(set = 0, binding = 2) uniform sampler2D Source;
layout(set = 0, binding = 3) uniform sampler2D COLOR_PALETTE;

////////////////////////////////////////////////////////////////////////////////
//fragment definitions                                                        //
////////////////////////////////////////////////////////////////////////////////

//hardcoded to look up the foreground color from the right half of the palette image
#define foreground_color texture(COLOR_PALETTE, vec2(0.75, 0.5)).rgb 

vec3 foreground_source = texture(Source, vTexCoord).rgb; // samples color from source for color mode

void main() {
    // Determine if the corrent texel lies on a dot or in the space between dots
    float is_on_dot = 0.0;
    if (mod(vTexCoord.x, dot_size.x) > one_texel.x && mod(vTexCoord.y, dot_size.y * 1.0001) > one_texel.y)
        is_on_dot = 1.0;

    vec3 input_rgb = abs(1.0 - texture(Source, vTexCoord).rgb);
    float rgb_to_alpha = (input_rgb.r + input_rgb.g + input_rgb.b) / registers.grey_balance
            + (is_on_dot * registers.baseline_alpha);

    // Apply foreground color and assign alpha value
    // Apply the foreground color to all texels -
    // the color will be modified by alpha later - and assign alpha based on rgb input

    vec4 out_color;
    if (registers.color_toggle == 0.0)
        out_color = vec4(foreground_color, rgb_to_alpha);
    else
        out_color = vec4(foreground_source, rgb_to_alpha);

    // Overlay the matrix
    out_color.a *= (is_on_dot + (1.0 - is_on_dot) * pow(rgb_to_alpha, 1 / 8) * (1.0 - registers.grid_intensity));
    out_color.a = mix(rgb_to_alpha, out_color.a, registers.grid_intensity);

    FragColor = out_color;
}

