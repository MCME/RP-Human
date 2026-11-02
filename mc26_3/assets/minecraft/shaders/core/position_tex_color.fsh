#version 330
// 26.3's copy of assets/minecraft/shaders/core/position_tex_color.fsh, translated by ResourcePackScripts' shader_base.py: don't edit it.
#extension GL_ARB_separate_shader_objects : require

// Vanilla 26.2's position_tex_color.fsh plus hiding the HUD while an MCME-GUI screen is open
// (include/mcme_gui_hud.glsl): the quads whose corners are all the HUD's.

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:mcme_gui_hud.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in vec2 texCoord0;
layout(location = 1) in vec4 vertexColor;
layout(location = 2) in float hudCorner;

layout(location = 0) out vec4 fragColor;

void main() {
    if (hudCorner > 0.999) {
        discard;
    }
    vec4 color = texture(Sampler0, texCoord0) * vertexColor;
    if (color.a == 0.0) {
        discard;
    }
    fragColor = color * ColorModulator;
}
