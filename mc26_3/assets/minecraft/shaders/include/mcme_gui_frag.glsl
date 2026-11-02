// 26.3's copy of assets/minecraft/shaders/include/mcme_gui_frag.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_GUI_FRAG_GLSL
#define MCME_MCME_GUI_FRAG_GLSL
// MCME GUI: how each piece looks (docs/gui.md). Fragment shaders only; needs mcme_gui.glsl before it.
//
// Nothing here is see-through: every pixel is drawn opaque or not at all (gui_solid), so the depth test alone
// stacks the pieces and the order they're drawn in doesn't matter. Clients don't keep text displays in a
// dependable order (docs/gui.md: Draw order), and a see-through pixel drawn before what is under it shows the
// world instead. Shapes have crisp edges: drawn where they cover at least half a pixel. Only shadows are soft,
// dithered. Looks that were see-through by design are mixed with what is under them here: the backdrop
// (gui_backdrop) or a surface (GUI_SURFACE_FILL).

#ifndef MCME_GUI_FRAG_GLSL
#define MCME_GUI_FRAG_GLSL

#include <minecraft:mcme_gui_addons_frag.glsl>

// Panel styles, red of a panel. Must match MCME-GUI's PanelStyle.
const int GUI_SURFACE = 0;    // the background of a group: a side bar, a dialog
const int GUI_BUTTON = 1;
const int GUI_ROW = 2;        // a list row; blue bit 0 shades it a little (every other row)
const int GUI_TAB = 3;
const int GUI_TOOLTIP = 4;
const int GUI_TOGGLE = 5;     // a button with a switch on its right, on while selected
const int GUI_PROGRESS = 6;   // blue = how full, of 255
const int GUI_THUMB = 7;      // a scroll bar's handle
const int GUI_DIVIDER = 8;    // a line along its length
const int GUI_HEADER = 9;     // a title band with a line under it
const int GUI_FRAME = 10;     // an outline only
const int GUI_SWATCH = 11;    // a colour: blue as RRRGGGBB

const vec3 GUI_GOLD = vec3(0.86, 0.71, 0.38);
const vec3 GUI_CREAM = vec3(1.0, 0.93, 0.78);
const vec3 GUI_INK = vec3(0.05, 0.05, 0.06);
// A surface's fill: flat, so what sits on a surface can mix with it.
const vec3 GUI_SURFACE_FILL = vec3(0.064, 0.065, 0.075);

// A 4x4 ordered dither threshold for a pixel, 1/32 to 31/32.
float gui_dither(vec2 frag) {
    const float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
                                      3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    ivec2 p = ivec2(mod(frag, 4.0));
    return (bayer[p.y * 4 + p.x] + 0.5) / 16.0;
}

// Whether to draw a pixel of coverage a, dithered; drawn pixels are opaque.
bool gui_solid(float a, vec2 frag) {
    return a >= gui_dither(frag);
}

float gui_hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Signed distance to a rounded box centred on the origin.
float gui_box(vec2 p, vec2 halfSize, float r) {
    r = min(r, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// How much of a pixel a shape covers, from its distance and the board size of a pixel.
float gui_cover(float d, float aa) {
    return clamp(0.5 - d / aa, 0.0, 1.0);
}

// above over below, straight alpha.
vec4 gui_over(vec4 below, vec4 above) {
    float a = above.a + below.a * (1.0 - above.a);
    vec3 c = (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / max(a, 1e-4);
    return vec4(c, a);
}

vec4 gui_backdrop(vec2 board) {
    vec2 uv = board / gui_view_half();
    vec3 col = mix(vec3(0.085, 0.09, 0.1), vec3(0.03, 0.033, 0.04), clamp(dot(uv, uv) * 0.6, 0.0, 1.0));
    col += (gui_hash(floor(board * 40.0)) - 0.5) * 0.012;
    return vec4(col, 1.0);
}

vec3 gui_swatch(int v) {
    return vec3(float(v >> 5 & 7) / 7.0, float(v >> 2 & 7) / 7.0, float(v & 3) / 3.0);
}

// One pixel of a panel. corner and board are interpolated across its quad, which is the panel plus
// GUI_PANEL_MARGIN on every side; the panel's size comes from how fast they change.
vec4 gui_panel(int style, int state, int value, vec2 corner, vec2 board) {
    float bx = dFdx(board.x), cx = dFdx(corner.x);
    float by = dFdy(board.y), cy = dFdy(corner.y);
    vec2 quad = vec2(abs(bx) / max(abs(cx), 1e-7), abs(by) / max(abs(cy), 1e-7));
    float aa = max(max(abs(bx), abs(by)), 1e-5);   // board size of a pixel
    vec2 h = max(quad * 0.5 - GUI_PANEL_MARGIN, vec2(0.0));
    vec2 p = vec2(corner.x - 0.5, 0.5 - corner.y) * quad;
    float down = 1.0 - (p.y / max(h.y, 1e-4) * 0.5 + 0.5);   // 0 at the top, 1 at the bottom

    bool hover = (state & GUI_HOVER) != 0;
    bool selected = (state & GUI_SELECTED) != 0;
    bool disabled = (state & GUI_DISABLED) != 0;
    bool pressed = (state & GUI_PRESSED) != 0;

    if (style == GUI_DIVIDER) {
        // Fading at its ends into the surface it lies on.
        float fade = smoothstep(h.x, h.x * 0.6, abs(p.x));
        float line = gui_cover(abs(p.y) - h.y, aa);
        return line >= 0.5 && fade > 0.0 ? vec4(mix(GUI_SURFACE_FILL, GUI_GOLD * 0.8, 0.45 * fade), 1.0) : vec4(0.0);
    }

    float radius = 0.08;
    bool shadow = false;
    vec3 fill = mix(vec3(0.07, 0.07, 0.08), vec3(0.12, 0.11, 0.1), down);
    float alpha = 1.0;
    vec3 line = GUI_GOLD * 0.55;
    float lineWidth = 0.024;

    if (style == GUI_SURFACE) {
        radius = 0.12;
        shadow = true;
        fill = GUI_SURFACE_FILL;
        line = GUI_GOLD * 0.35;
        lineWidth = 0.02;
    } else if (style == GUI_BUTTON || style == GUI_TAB || style == GUI_TOGGLE) {
        shadow = true;
        bool lit = selected && style != GUI_TOGGLE;
        if (lit) fill = mix(vec3(0.24, 0.19, 0.09), vec3(0.16, 0.12, 0.05), down);
        if (hover) fill += vec3(0.08, 0.07, 0.05);
        if (pressed) fill *= 0.7;
        line = GUI_GOLD * (lit || hover ? 1.0 : 0.55);
    } else if (style == GUI_ROW) {
        radius = 0.05;
        // Every other row a little lighter than the surface it's on; the rest not drawn.
        alpha = (value & 1) == 1 ? 1.0 : 0.0;
        fill = mix(GUI_SURFACE_FILL, vec3(0.12, 0.12, 0.13), 0.22);
        line = fill;
        lineWidth = 0.0;
        if (selected) {
            fill = vec3(0.22, 0.175, 0.085);
            alpha = 1.0;
        }
        if (hover) {
            fill = selected ? vec3(0.28, 0.225, 0.115) : vec3(0.16, 0.14, 0.105);
            alpha = 1.0;
        }
    } else if (style == GUI_TOOLTIP) {
        radius = 0.05;
        shadow = true;
        fill = vec3(0.035, 0.035, 0.045);
        line = GUI_GOLD * 0.85;
        lineWidth = 0.02;
    } else if (style == GUI_PROGRESS) {
        radius = h.y;
        fill = vec3(0.04, 0.04, 0.05);
        line = GUI_GOLD * 0.4;
        lineWidth = 0.018;
    } else if (style == GUI_THUMB) {
        radius = min(h.x, h.y);
        fill = GUI_GOLD * (hover ? 0.9 : 0.6);
        line = fill;
        lineWidth = 0.0;
    } else if (style == GUI_HEADER) {
        radius = 0.0;
        // Fades into the backdrop it lies on.
        fill = mix(gui_backdrop(board).rgb, vec3(0.12, 0.1, 0.07), 0.55 * (1.0 - down));
        line = fill;
        lineWidth = 0.0;
    } else if (style == GUI_FRAME) {
        alpha = 0.0;
        line = GUI_GOLD * (hover ? 1.0 : 0.7);
        lineWidth = 0.025;
    } else if (style == GUI_SWATCH) {
        radius = 0.05;
        fill = gui_swatch(value);
        alpha = 1.0;
        line = GUI_INK;
        lineWidth = 0.02;
    }

    if (disabled) {
        fill = mix(vec3(dot(fill, vec3(0.3, 0.59, 0.11))), GUI_SURFACE_FILL, 0.4);
        line = vec3(dot(line, vec3(0.3, 0.59, 0.11))) * 0.6;
    }

    float shade = 0.0;
    if (shadow) {
        float ds = gui_box(p + vec2(0.0, 0.03), h, radius);
        shade = 0.45 * (1.0 - smoothstep(-0.02, GUI_PANEL_MARGIN * 0.9, ds));
    }
    float d = gui_box(p, h, radius);
    float inside = gui_cover(d, aa);
    vec4 body = vec4(fill, alpha);

    if (style == GUI_PROGRESS) {
        float edge = -h.x + 2.0 * h.x * float(value) / 255.0;
        vec3 bar = mix(GUI_GOLD * 1.05, GUI_GOLD * 0.7, down);
        body = gui_over(body, vec4(bar, gui_cover(p.x - edge, aa)));
    } else if (style == GUI_HEADER) {
        body = gui_over(body, vec4(GUI_GOLD * 0.8, gui_cover(abs(p.y + h.y - 0.015) - 0.015, aa)));
    } else if (style == GUI_TAB && selected) {
        body = gui_over(body, vec4(GUI_GOLD * 1.1, gui_cover(abs(p.y + h.y - 0.06) - 0.025, aa) * step(abs(p.x), h.x - 0.12)));
    } else if (style == GUI_ROW && (hover || selected)) {
        body = gui_over(body, vec4(GUI_GOLD, gui_cover(abs(p.x + h.x - 0.06) - 0.025, aa) * step(abs(p.y), h.y - 0.06)));
    }
    if (lineWidth > 0.0) {
        body = gui_over(body, vec4(line, gui_cover(abs(d + lineWidth * 0.5) - lineWidth * 0.5, aa)));
    }
    if (style == GUI_TOGGLE) {
        vec2 c = p - vec2(h.x - 0.38, 0.0);
        float pill = gui_box(c, vec2(0.24, 0.12), 0.12);
        vec3 track = selected ? GUI_GOLD * 0.85 : vec3(0.22, 0.22, 0.24);
        body = gui_over(body, vec4(disabled ? vec3(0.3) : track, gui_cover(pill, aa)));
        float knob = length(c - vec2(selected ? 0.12 : -0.12, 0.0)) - 0.09;
        body = gui_over(body, vec4(selected ? GUI_CREAM : vec3(0.6), gui_cover(knob, aa)));
    }
    // Crisp edges: the panel where it covers at least half the pixel (inside it, lines and fills mix smoothly),
    // else only its shadow, which gui_solid dithers.
    body.a *= inside;
    return body.a >= 0.5 ? vec4(body.rgb, 1.0) : vec4(0.0, 0.0, 0.0, shade);
}

// A white ring and dot with a dark outline, crisp.
vec4 gui_cursor_colour(vec2 corner, int state) {
    vec2 p = (corner - 0.5) * 2.0;
    float r = length(p);
    float ring = smoothstep(0.1, 0.0, abs(r - 0.62) - 0.08);
    float outline = smoothstep(0.1, 0.0, abs(r - 0.62) - 0.17);
    float dot_ = smoothstep(0.2, 0.12, r);
    vec3 c = state == 1 ? GUI_CREAM : vec3(1.0);
    if (max(ring, dot_) >= 0.5) return vec4(c, 1.0);
    return outline >= 0.5 ? vec4(GUI_INK, 1.0) : vec4(0.0);
}

// An image tile's texel, clamped to its 240-pixel glyph, whose page has nothing past it.
vec4 gui_texel(sampler2D tex, ivec2 p, ivec2 origin) {
    return texelFetch(tex, clamp(p, origin, origin + ivec2(239)), 0);
}

vec4 gui_bilinear(sampler2D tex, vec2 px, ivec2 origin) {
    vec2 p = px - 0.5;
    vec2 f = fract(p);
    ivec2 i = ivec2(floor(p));
    return mix(mix(gui_texel(tex, i, origin), gui_texel(tex, i + ivec2(1, 0), origin), f.x),
               mix(gui_texel(tex, i + ivec2(0, 1), origin), gui_texel(tex, i + ivec2(1, 1), origin), f.x), f.y);
}

// An image tile: the image in the top-left 240 pixels of its font page. Pixel art takes the nearest texel; the
// rest blends, with four samples across the pixel where it is drawn smaller (font pages have no mipmaps).
vec4 gui_image(sampler2D tex, vec2 uv, vec2 corner, bool pixelArt) {
    // Where the glyph sits on its page: not always at 0,0.
    vec2 local = corner * 240.0;
    vec2 origin = floor(uv * vec2(textureSize(tex, 0)) - local + 0.5);
    vec2 px = origin + local;
    if (pixelArt) {
        return gui_texel(tex, ivec2(origin) + clamp(ivec2(local), ivec2(0), ivec2(239)), ivec2(origin));
    }
    vec2 dx = dFdx(px) * 0.25;
    vec2 dy = dFdy(px) * 0.25;
    ivec2 o = ivec2(origin);
    return (gui_bilinear(tex, px + dx + dy, o) + gui_bilinear(tex, px + dx - dy, o)
          + gui_bilinear(tex, px - dx + dy, o) + gui_bilinear(tex, px - dx - dy, o)) * 0.25;
}

// The colour of a GUI piece and its coverage (0 for nothing): dither the coverage with gui_solid.
vec4 gui_colour(int kind, ivec4 code, vec2 corner, vec2 board, sampler2D font, vec2 uv, vec4 tint) {
    if (kind == GUI_BACKDROP) return gui_backdrop(board);
    if (kind == GUI_IMAGE) return gui_image(font, uv, corner, (code.r & 32) != 0);
    if (kind == GUI_ADDON) return gui_addon_colour(code, corner, board, font, uv);
    if (kind == GUI_CURSOR) return gui_cursor_colour(corner, code.b);
    if (kind == GUI_PANEL) return gui_panel(code.r, code.g, code.b, corner, board);
    vec4 text = texture(font, uv) * tint;
    return text.a < 0.1 ? vec4(0.0) : text;
}

#endif
#endif
