#version 330

// Vanilla 26.2's position_tex_color.fsh plus hiding the HUD while an MCME-GUI screen is open
// (include/mcme_gui_hud.glsl): the quads whose corners are all the HUD's.

#moj_import <minecraft:dynamictransforms.glsl>
#moj_import <minecraft:projection.glsl>
#moj_import <minecraft:globals.glsl>
#moj_import <minecraft:mcme_gui_hud.glsl>

uniform sampler2D Sampler0;

in vec2 texCoord0;
in vec4 vertexColor;
in float hudCorner;

out vec4 fragColor;

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
