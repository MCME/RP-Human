// 26.3's copy of assets/minecraft/shaders/include/mcme_gui_addons_frag.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_GUI_ADDONS_FRAG_GLSL
#define MCME_MCME_GUI_ADDONS_FRAG_GLSL
// MCME GUI add-ons, how they look (mcme_gui_addons.glsl). Fragment shaders only.

#ifndef MCME_GUI_ADDONS_FRAG_GLSL
#define MCME_GUI_ADDONS_FRAG_GLSL

// One pixel of an add-on's piece; code is its colour, alpha (its opacity) last. Coverage as gui_colour's.
vec4 gui_addon_colour(ivec4 code, vec2 corner, vec2 board, sampler2D tex, vec2 uv) {
    return vec4(0.0);
}

#endif
#endif
