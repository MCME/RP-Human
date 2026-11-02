// MCME GUI add-ons: pieces drawn by other features inside a screen, such as a map (docs/gui.md: Add-ons). A display
// with text opacity 240-252 comes here. An add-on lands in the shader base as its own include, imported below and
// called from gui_addon_place and gui_addon_colour (mcme_gui_addons_frag.glsl) by its opacity; until then nothing
// draws.

#ifndef MCME_GUI_ADDONS_GLSL
#define MCME_GUI_ADDONS_GLSL

// Places one vertex: may change its corner and board point (both set as for a panel); returns its depth slot
// (gui_slot).
float gui_addon_place(vec4 color, vec3 position, vec2 uv, inout vec2 corner, inout vec2 board) {
    return gui_slot(GUI_LAYERS - 1, 2);
}

#endif
