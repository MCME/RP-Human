// 26.3's copy of assets/minecraft/shaders/include/mcme_gui.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_GUI_GLSL
#define MCME_MCME_GUI_GLSL
// MCME GUI: the text displays of an MCME-GUI screen, drawn as a flat 2D screen (docs/gui.md).
//
// The plugin seats the player and spawns text displays below their eyes, lying flat and seen only by them. A
// display's text opacity (the alpha byte of its glyphs' colour) says what it is:
//   160-191  text, drawn where it is, on layer alpha - 160
//   192-223  panel, on layer alpha - 192: an mcme_gui:ui glyph scaled to the panel's size (plus GUI_PANEL_MARGIN
//            on every side, room for its shadow); red = style, green = state (GUI_HOVER, ...), blue = the style's
//            value (a progress bar's fill, a swatch's colour)
//   224      image tile: a 240-pixel glyph on its own font page, scaled like a panel; red = layer (bits 0-4) and
//            pixel-art sampling (bit 5), the image in its top-left, transparent past it
//   240-252  reserved for add-ons (include/mcme_gui_addons.glsl), such as a map
//   253      red 1: the backdrop, covering the screen; red 2: the cursor, placed by the head turn, blue 1 when
//            over something that can be clicked
// While a screen is open, the GUI pass hides the HUD (include/mcme_gui_hud.glsl).
// Every other text keeps the vanilla path.
//
// The board is 24 x 13.5 units, y up, with its origin under the camera: positions are camera-relative, so a
// display's board point is its x and -z. North is up. The shader replaces the camera's view with the board fitted
// to the screen (more of the backdrop on the long side), so turning the head moves only the cursor.
// Glyph corners come from texture coordinates: the ui glyph has a font page to itself, at 0,0 (vertex indices don't
// work: text shares its vertex buffer, so they don't start on a quad).
// Needs dynamictransforms.glsl, projection.glsl and globals.glsl before it.

#ifndef MCME_GUI_GLSL
#define MCME_GUI_GLSL

const int GUI_NONE = 0;
const int GUI_BACKDROP = 1;
const int GUI_CURSOR = 2;
const int GUI_PANEL = 3;
const int GUI_TEXT = 4;
// GUI pass text while a screen is open: guiBoard is its GUI position (include/mcme_gui_hud.glsl).
const int GUI_HUD = 5;
const int GUI_IMAGE = 6;
const int GUI_ADDON = 7;

// Must match MCME-GUI's Board.
const vec2 GUI_BOARD_HALF = vec2(12.0, 6.75);
const float GUI_UNITS_PER_DEGREE = 0.14;
const vec2 GUI_CURSOR_EDGE = GUI_BOARD_HALF - 0.3;
const float GUI_PANEL_MARGIN = 0.1;
const int GUI_LAYERS = 32;

const int GUI_TEXT_ALPHA = 160;
const int GUI_PANEL_ALPHA = 192;
const int GUI_IMAGE_ALPHA = 224;
const int GUI_ADDON_FIRST = 240;
const int GUI_ADDON_LAST = 252;
const int GUI_SPECIAL_ALPHA = 253;

// Panel states, bits of green.
const int GUI_HOVER = 1;
const int GUI_SELECTED = 2;
const int GUI_DISABLED = 4;
const int GUI_PRESSED = 8;

// The ui glyph: 240 pixels on its 256-pixel font page.
const float GUI_GLYPH_PX = 240.0;
const float GUI_FONT_PAGE = 256.0;
const float GUI_CURSOR_SIZE = 0.5;

int gui_byte(float c) {
    return int(c * 255.0 + 0.5);
}

int gui_kind(vec4 c) {
    int a = gui_byte(c.a);
    if (a >= GUI_TEXT_ALPHA && a < GUI_TEXT_ALPHA + GUI_LAYERS) return GUI_TEXT;
    if (a >= GUI_PANEL_ALPHA && a < GUI_PANEL_ALPHA + GUI_LAYERS) return GUI_PANEL;
    if (a == GUI_IMAGE_ALPHA) return GUI_IMAGE;
    if (a >= GUI_ADDON_FIRST && a <= GUI_ADDON_LAST) return GUI_ADDON;
    if (a == GUI_SPECIAL_ALPHA) {
        int r = gui_byte(c.r);
        if (r == 1) return GUI_BACKDROP;
        if (r == 2) return GUI_CURSOR;
    }
    return GUI_NONE;
}

// Corner of the ui glyph: 0,0 top-left, 1,1 bottom-right.
vec2 gui_corner(vec2 uv) {
    return step(GUI_GLYPH_PX / GUI_FONT_PAGE * 0.5, uv);
}

// Offset of a corner from the quad's centre, on the board (y up).
vec2 gui_spread(vec2 corner, vec2 size) {
    return vec2(corner.x - 0.5, 0.5 - corner.y) * size;
}

vec2 gui_board(vec3 position) {
    return vec2(position.x, -position.z);
}

// Half-size of the board area the screen shows: all of the board, more on the long side.
vec2 gui_view_half() {
    float aspect = ScreenSize.x / max(ScreenSize.y, 1.0);
    float boardAspect = GUI_BOARD_HALF.x / GUI_BOARD_HALF.y;
    return aspect >= boardAspect ? vec2(GUI_BOARD_HALF.y * aspect, GUI_BOARD_HALF.y)
                                 : vec2(GUI_BOARD_HALF.x, GUI_BOARD_HALF.x / aspect);
}

// Head turn in degrees: yaw grows to the right, pitch grows looking down (Minecraft's convention).
vec2 gui_look() {
    float pitch = degrees(asin(clamp(ModelViewMat[1][2], -1.0, 1.0)));
    float yaw = degrees(atan(ModelViewMat[0][2], -ModelViewMat[2][2]));
    return vec2(yaw, pitch);
}

vec2 gui_cursor() {
    vec2 look = gui_look();
    return clamp(vec2(look.x, -look.y) * GUI_UNITS_PER_DEGREE, -GUI_CURSOR_EDGE, GUI_CURSOR_EDGE);
}

// A depth slot: 1 panels, 2 images, 3 text of a layer; the cursor past the last layer.
float gui_slot(int layer, int part) {
    return float(layer * 3 + part);
}

#include <minecraft:mcme_gui_addons.glsl>

// Depth just past the near plane, through the game's own projection so either depth convention works. Higher
// layers are nearer: the backdrop 0, each layer's panels, then its images, then its text (gui_slot), the cursor on
// top.
float gui_depth(float layer) {
    float d = 0.2 - 0.0014 * layer;
    return (ProjMat[2][2] * -d + ProjMat[3][2]) / d;
}

// Places one vertex of a GUI piece and returns its clip position. corner is the ui glyph's corner, board the
// vertex's board point; both for the fragment shader.
vec4 gui_place(int kind, vec4 color, vec3 position, vec2 uv, out vec2 corner, out vec2 board) {
    vec2 viewHalf = gui_view_half();
    corner = gui_corner(uv);
    float layer;
    int a = gui_byte(color.a);
    if (kind == GUI_BACKDROP) {
        board = (corner * 2.0 - 1.0) * vec2(1.0, -1.0) * viewHalf;
        layer = 0.0;
    } else if (kind == GUI_CURSOR) {
        float size = GUI_CURSOR_SIZE * (gui_byte(color.b) == 1 ? 1.3 : 1.0);
        board = gui_cursor() + gui_spread(corner, vec2(size));
        layer = gui_slot(GUI_LAYERS, 0);
    } else if (kind == GUI_IMAGE) {
        board = gui_board(position);
        layer = gui_slot(gui_byte(color.r) % 32, 2);
    } else if (kind == GUI_ADDON) {
        board = gui_board(position);
        layer = gui_addon_place(color, position, uv, corner, board);
    } else if (kind == GUI_PANEL) {
        board = gui_board(position);
        layer = gui_slot(a - GUI_PANEL_ALPHA, 1);
    } else {
        board = gui_board(position);
        layer = gui_slot(a - GUI_TEXT_ALPHA, 3);
    }
    return vec4(board / viewHalf, gui_depth(layer), 1.0);
}

#endif
#endif
