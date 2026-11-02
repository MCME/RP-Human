#version 330
// 26.3's copy of assets/minecraft/shaders/core/position_tex_color.vsh, translated by ResourcePackScripts' shader_base.py: don't edit it.
#extension GL_ARB_separate_shader_objects : require

// Vanilla 26.2's position_tex_color.vsh (GUI sprites, the crosshair and a few world things), plus what its .fsh
// needs to hide the HUD while an MCME-GUI screen is open (include/mcme_gui_hud.glsl). Vanilla's copy repeats its
// uniform blocks because it is used before resource packs load; this one is only used once they have.

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:mcme_gui_hud.glsl>

layout(location = 0) in vec3 Position;
layout(location = 1) in vec2 UV0;
layout(location = 2) in vec4 Color;

layout(location = 0) out vec2 texCoord0;
layout(location = 1) out vec4 vertexColor;
layout(location = 2) out float hudCorner;

void main() {
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);

    texCoord0 = UV0;
    vertexColor = Color;
    vec2 ui = gui_hud_ui();
    hudCorner = ui.x > 0.0 ? max(gui_crosshair_corner(Position.xy, ui), gui_hud_corner(Position.xy, ui, false)) : 0.0;
}
