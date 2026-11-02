#version 330
#extension GL_ARB_separate_shader_objects : require

// Vanilla 26.3's text.fsh plus MCME-GUI's screens (include/mcme_gui.glsl). Written by hand for its transparency
// passes; its inputs take the locations of the translated text.vsh's outputs, in the order it declares them.

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
#include <minecraft:fog.glsl>
#endif

#include <minecraft:dynamictransforms.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:oit.glsl>
#include <minecraft:mcme_gui.glsl>
#include <minecraft:mcme_gui_frag.glsl>
#include <minecraft:mcme_gui_hud.glsl>

uniform sampler2D Sampler0;

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
#endif

layout(location = 2) in vec4 vertexColor;
layout(location = 3) in vec2 texCoord0;
layout(location = 4) flat in int guiKind;
layout(location = 5) flat in ivec4 guiCode;
layout(location = 6) in vec2 guiCorner;
layout(location = 7) in vec2 guiBoard;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

vec4 calculateFinalColor(vec4 color) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    #endif

    #if !defined(IS_SEE_THROUGH) && !defined(IS_GUI)

    #ifdef OIT_ACCUMULATE
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif

    color = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
    #endif

    return color;
}

void main() {
    #ifdef IS_GUI
    if (guiKind == GUI_HUD && guiCorner.x > 0.999) {
        discard;
    }
    #endif

    #if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
    if (guiKind != GUI_NONE) {
        vec4 gui = gui_colour(guiKind, guiCode, guiCorner, guiBoard, Sampler0, texCoord0, vertexColor);
        // Opaque or nothing, so drawing order can't matter (include/mcme_gui_frag.glsl).
        if (gui.a < 0.004 || !gui_solid(gui.a, gl_FragCoord.xy)) {
            discard;
        }
        gui.a = 1.0;
        // No fog: the screen isn't something in the world.
        #ifdef OIT_ALPHA_ONLY
        executeAlphaOnlyPhase(gl_FragCoord.z, gui.a);
        #else
        #ifdef OIT_ACCUMULATE
        gui = sampleColorForAccumulation(gui);
        #endif
        fragColor = gui;
        #endif
        return;
    }
    #endif

    #ifdef IS_GRAYSCALE
    vec4 texColor = texture(Sampler0, texCoord0).rrrr;
    #else
    vec4 texColor = texture(Sampler0, texCoord0);
    #endif

    vec4 color = texColor * vertexColor * ColorModulator;

    if (color.a < 0.1) {
        discard;
    }

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}
