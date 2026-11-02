// MCME GUI: hiding the HUD while a screen is open (docs/gui.md). For the GUI pass; needs projection.glsl and
// globals.glsl.
//
// The GUI pass can't see the head turn or the screen's displays, but it does see where the camera is. The plugin
// seats a player with a screen open where the camera's x and z are each in the middle of a sixteenth of a block,
// which nobody stands at by chance (a block's centre is at the start of one), so that is how the GUI pass knows.
// Then it drops the crosshair and the hotbar with everything around it (off hand, hearts, food, armour, air, the
// experience and locator bars, the experience level), and the screen shows through to the bottom.
//
// Nothing moves a vertex: a menu opened over the screen (Esc, chat, a dialog) shares these shaders, and a quad with
// only some corners moved stretches across the screen. Each vertex says whether it is a corner of the HUD (its
// rows, the crosshair's exact corners), and only quads that are all corners go.

#ifndef MCME_GUI_HUD_GLSL
#define MCME_GUI_HUD_GLSL

// Must match MCME-GUI's Session (SEAT_GRID): the middle of a 1/16 step, the same whichever way the offset runs.
const float GUI_SEAT_GRID = 16.0;

bool gui_screen_open() {
    vec2 f = abs(fract(CameraOffset.xz * GUI_SEAT_GRID) - 0.5);
    return f.x < 0.002 && f.y < 0.002;
}

// The GUI's size in GUI pixels while a screen is open and this is the GUI's orthographic projection; else 0. The
// projection spans the window over the GUI scale, often a fraction; the game's GUI size is that rounded up.
vec2 gui_hud_ui() {
    return ProjMat[3][3] == 1.0 && gui_screen_open() ? ceil(2.0 / vec2(ProjMat[0][0], -ProjMat[1][1]) - 0.001)
                                                      : vec2(0.0);
}

bool gui_near(float a, float b) {
    return abs(a - b) < 0.01;
}

// Whether a GUI y is one of the HUD's rows, by how far up from the bottom: the hotbar and its selection, the
// experience and locator bars, hearts, food, armour and air, and for text the experience level, the held item's
// name and the action bar (with their shadows, a pixel lower).
bool gui_hud_row(float y, vec2 ui, bool text) {
    float up = ui.y - y;
    if (text) {
        return gui_near(up, 35.0) || gui_near(up, 34.0) || gui_near(up, 27.0) || gui_near(up, 26.0)
            || gui_near(up, 59.0) || gui_near(up, 58.0) || gui_near(up, 51.0) || gui_near(up, 50.0)
            || gui_near(up, 72.0) || gui_near(up, 71.0) || gui_near(up, 64.0) || gui_near(up, 63.0);
    }
    return gui_near(up, -1.0) || gui_near(up, 0.0) || gui_near(up, 22.0) || gui_near(up, 23.0)
        || gui_near(up, 24.0) || gui_near(up, 29.0) || gui_near(up, 30.0) || gui_near(up, 39.0)
        || gui_near(up, 40.0) || gui_near(up, 49.0) || gui_near(up, 50.0) || gui_near(up, 59.0)
        || gui_near(up, 60.0);
}

// 1 at a vertex of the HUD (by its row, within the hotbar's reach of the middle), 0 elsewhere. Only a quad with all
// four corners on HUD rows is 1 all over, so menus over a screen (dialogs, Esc) keep theirs.
float gui_hud_corner(vec2 pos, vec2 ui, bool text) {
    return abs(pos.x - ui.x * 0.5) <= 122.0 && gui_hud_row(pos.y, ui, text) ? 1.0 : 0.0;
}

// 1 at a corner of the crosshair (15 pixels square at ((w - 15) / 2, (h - 15) / 2), whole pixels) or of the attack
// indicator under it (16 across at w / 2 - 8, 9 to 13 below the middle); 0 elsewhere. Only a quad with all four
// corners there is 1 all over.
float gui_crosshair_corner(vec2 pos, vec2 ui) {
    vec2 at = floor((ui - 15.0) * 0.5);
    bool cross = (gui_near(pos.x, at.x) || gui_near(pos.x, at.x + 15.0))
              && (gui_near(pos.y, at.y) || gui_near(pos.y, at.y + 15.0));
    vec2 mid = floor(ui * 0.5);
    bool indicator = pos.x >= mid.x - 8.01 && pos.x <= mid.x + 8.01
                  && (gui_near(pos.y, mid.y + 9.0) || gui_near(pos.y, mid.y + 13.0));
    return cross || indicator ? 1.0 : 0.0;
}

// ---- HUD overlays: MCME-GUI's Hud, drawn while playing ----
//
// The plugin sends them as the subtitle (an empty title held for an hour), every glyph coloured 251, G, B:
// G's low 4 bits are the anchor (0-8: top-left, top, top-right, left, middle, right, bottom-left, bottom,
// bottom-right), its high 4 the colour (Minecraft's 16, GUI_PALETTE), B - 128 the element's y offset in GUI
// pixels. Its x offset is spaces in the text, and each element ends with negative space as wide as itself, so the
// line is no wide at all: then a glyph's place in its element is where the subtitle puts it, back from scale 2.
// They show at scale 1, and not while a screen is open.

const vec3 GUI_PALETTE[16] = vec3[16](
    vec3(0.0), vec3(0.0, 0.0, 0.667), vec3(0.0, 0.667, 0.0), vec3(0.0, 0.667, 0.667),
    vec3(0.667, 0.0, 0.0), vec3(0.667, 0.0, 0.667), vec3(1.0, 0.667, 0.0), vec3(0.667),
    vec3(0.333), vec3(0.333, 0.333, 1.0), vec3(0.333, 1.0, 0.333), vec3(0.333, 1.0, 1.0),
    vec3(1.0, 0.333, 0.333), vec3(1.0, 0.333, 1.0), vec3(1.0, 1.0, 0.333), vec3(1.0));

bool gui_is_overlay(vec4 color) {
    return int(color.r * 255.0 + 0.5) == 251;
}

// Where an overlay glyph's vertex goes (GUI pixels), and its colour. While a screen is open, every vertex of it
// moves the same way, off the GUI, so nothing stretches.
vec2 gui_overlay_place(vec4 color, vec3 position, vec2 ui, out vec3 tint) {
    int g = int(color.g * 255.0 + 0.5);
    int dy = int(color.b * 255.0 + 0.5) - 128;
    int anchor = g & 15;
    tint = GUI_PALETTE[g >> 4];
    vec2 origin = floor(ui * 0.5);
    vec2 local = (position.xy - origin) * 0.5 - vec2(0.0, 5.0);
    vec2 at = vec2(float(anchor % 3), float(anchor / 3)) * 0.5 * ui;
    if (gui_screen_open()) {
        at += vec2(ui.x * 4.0, 0.0);
    }
    return at + local + vec2(0.0, float(dy));
}

#endif
