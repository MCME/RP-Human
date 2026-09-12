#version 150

// ============================================================
//  MCME-Action-Bar – GUI-scale-invariant HUD positioning
//
//  How it works:
//
//  Inspired by BetterHud's technique with BossBars - but simplified to just the action bar
//  Extending the vanilla default vertex shader to detect HUD characters
//
//  Each HUD icon character has a huge negative ascent (font
//  property controlling vertical position) baked into the
//  resource-pack font.  Minecraft applies this by pushing the
//  glyph's vertex Y to a large positive value — far below the
//  visible screen.  The shader detects this (pos.y >= ui.y)
//  and extracts an element ID encoded in those extra pixels,
//  then repositions the character to a fixed anchor expressed
//  as a *percentage* of ui (the screen size in GUI pixels).
//  Because ui already accounts for the player's GUI-scale
//  setting, the final screen position is identical at every
//  GUI scale.
//
//  Encoding formula (Java / resource-pack tooling side):
//      ascent = -(((elementId + MAGIC_OFFSET) << HEIGHT_BIT) + HEIGHT_MASK)
//  where
//      HEIGHT_BIT    = 13
//      HEIGHT_MASK = 4095
//      MAGIC_BIT     = 10
//      MAGIC_OFFSET  = 1024  (= 1 << MAGIC_BIT)
//
//  Example – element ID 1 (chat-channel icon):
//      ascent = -(((1 + 1024) << 13) + 4095) = -8 400 895
// ============================================================

// Projection matrix provided by Minecraft. For the GUI pass this is an
// orthographic matrix that scales and translates GUI-pixel coordinates
// into [-1..+1] clip space. For the 3D world pass it is a perspective matrix.
uniform mat4 ProjMat;
uniform mat4 ModelViewMat;
uniform int FogShape;

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;

uniform sampler2D Sampler2;

out vec4 vertexColor;
out vec2 texCoord0;
out float vertexDistance;

// ── Encoding constants – must match the font ascent formula ──
#define HEIGHT_BIT    13
#define HEIGHT_MASK   4095 // (1 << (HEIGHT_BIT-1)) -> Used to set all the HEIGHT offset bits
// ^ 11111111111111 = 16383 = The height of a 16k screen at GUI scale 1
#define MAGIC_BIT     10
#define MAGIC_OFFSET  1024 // (1 << MAGIC_BIT)

// Distance of the action-bar text baseline from the bottom of the
// screen, in GUI pixels.  Must match where Minecraft draws the action
// bar — do NOT change this to move icons; use per-element yOffset instead.
#define ACTION_BAR_Y  65.0

// Runs once per vertex — each character is a textured quad (4 vertices), and each vertex is processed independently
void main() {
    vec3 pos = Position;

    // The Gui pass is when this shader is used to render 2D UI elements (e.g. the action bar)
    // [3][0] is the X translation; the GUI ortho matrix always has -1 here, but not when rendering 3D world text (name tags, signs, etc.)
    bool isGuiPass = ProjMat[3][0] == -1.0;
    if (isGuiPass) {
        // Screen size in GUI pixels
        // proj[0][0] = 2 / guiWidth, proj[1][1] = -2 / guiHeight -> reversing these to get the width (x) and height (y)
        vec2 ui = ceil(2.0 / vec2(ProjMat[0][0], -ProjMat[1][1]));
        bool isBelowScreen = pos.y >= ui.y;

        if (isBelowScreen) {
            // Shift out the lower HEIGHT_BIT bits to get the magic bit and element ID
            int encodedY = int(pos.y) >> HEIGHT_BIT;

            bool hasMagicBit = ((encodedY >> MAGIC_BIT) & 1) == 1; // Isolating the magic bit and ensuring it is set
            if (hasMagicBit) {
                // We can now be certain this vertex is for a glyph within our custom HUD
                // Now we need to position it!

                // ── Step 1: move X origin to the left screen edge ──────
                // Action-bar text is centred, so subtracting half the GUI
                // width cancels that centering. Each vertex then carries
                // only its offset relative to the left edge.
                pos.x -= 0.5 * ui.x;
                // NOTE: This^ may cause issues in the future when the action bar contains multiple HUD elements since
                // the starting position won't be exactly in the centre.

                // ── Step 2: Zero-ing pos.y to just the glyph's local offset ─────
                // The TL vertex of the glpyh will have y=~0 and the BR vertex will have y=~height
                float encodedOffscreenOffset = float((encodedY << HEIGHT_BIT) + HEIGHT_MASK);
                float actionBarDistFromTop = ui.y - ACTION_BAR_Y;
                pos.y -= encodedOffscreenOffset + actionBarDistFromTop;

                // ── Step 3: anchor + offset per element ─────────────────
                //
                //   xPercent  0 = left edge   50 = centre   100 = right edge
                //   yPercent  0 = top         50 = centre   100 = bottom
                //
                //   xOffset / yOffset: fine nudge *from* the anchor, in GUI pixels
                //
                //   1 GUI pixel = (GUI scale) x (GUI scale) pixels
                //   A 1080p (1920x1080) screen at GUI scale 3 becomes 640x360 GUI pixels
                //   The PNGs scale with the GUI scale so the offsets works at any GUI scale
                float xPercent, yPercent;
                float xOffset, yOffset;

                int elementId = encodedY - MAGIC_OFFSET;
                switch (elementId) {
                    // ── Chat-channel icon — bottom-left corner ──
                    case 1:
                        xPercent = 0.0; yPercent = 100.0;
                        xOffset  = 9.0; yOffset  = -27.0;
                        break;

                    // ── Add future elements here ────────────────────────
                    // case 2:
                    //     xPercent = 100.0; yPercent = 100.0;
                    //     xOffset = -9.0;   yOffset = -49.0;
                    //     break;

                    default:
                        // Unrecognised elementId - If an icon is misplaced, check that its
                        // elementId has a case here and that the font ascent uses the matching encoding formula.
                        xPercent = 0.0; yPercent =  50.0;
                        xOffset  = 0.0; yOffset  = -10.0;
                        break;
                }

                pos.x += ui.x * (xPercent / 100.0) + xOffset;
                pos.y += ui.y * (yPercent / 100.0) + yOffset;
            }
        }
    }

    vec4 worldPos = ModelViewMat * vec4(pos, 1.0);

    // The same as vanilla — but we have to inline fog_distance() since #moj_import is unavailable in resource packs.
    // https://github.com/InventivetalentDev/minecraft-assets/blob/1.21.4/assets/minecraft/shaders/core/rendertype_text.vsh
    vertexDistance = FogShape == 0 ? length(worldPos.xyz)
                                   : max(length(worldPos.xz), abs(worldPos.y));

    vertexColor = Color * texelFetch(Sampler2, UV2 / 16, 0);
    texCoord0  = UV0;
    gl_Position = ProjMat * worldPos;
}