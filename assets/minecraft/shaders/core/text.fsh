#version 330

// Vanilla 26.2's text.fsh plus MCME-GUI's screens (include/mcme_gui.glsl).

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
#moj_import <minecraft:fog.glsl>
#endif

#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:globals.glsl>
#moj_import <minecraft:mcme_gui.glsl>
#moj_import <minecraft:mcme_gui_frag.glsl>
#moj_import <minecraft:mcme_gui_hud.glsl>

uniform sampler2D Sampler0;

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
in float sphericalVertexDistance;
in float cylindricalVertexDistance;
#endif

in vec4 vertexColor;
in vec2 texCoord0;
flat in int guiKind;
flat in ivec4 guiCode;
in vec2 guiCorner;
in vec2 guiBoard;

out vec4 fragColor;

void main() {
#ifdef IS_GUI
    if (guiKind == GUI_HUD && guiCorner.x > 0.999) {
        discard;
    }
#endif

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
    if (guiKind != GUI_NONE) {
        // No fog: the screen isn't something in the world.
        vec4 gui = gui_colour(guiKind, guiCode, guiCorner, guiBoard, Sampler0, texCoord0, vertexColor);
        // Opaque or nothing, so drawing order can't matter (include/mcme_gui_frag.glsl).
        if (gui.a < 0.004 || !gui_solid(gui.a, gl_FragCoord.xy)) {
            discard;
        }
        gui.a = 1.0;
        fragColor = gui;
        return;
    }
#endif

#ifdef IS_GRAYSCALE
    vec4 texColor = texture(Sampler0, texCoord0).rrrr;
#else
    vec4 texColor = texture(Sampler0, texCoord0);
#endif

#ifdef IS_SEE_THROUGH
    vec4 color = texColor * vertexColor;
#else
    vec4 color = texColor * vertexColor * ColorModulator;
#endif
    if (color.a < 0.1) {
        discard;
    }

#ifdef IS_SEE_THROUGH
    fragColor = color * ColorModulator;
#elif defined(IS_GUI)
    fragColor = color;
#else
    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
#endif
}
