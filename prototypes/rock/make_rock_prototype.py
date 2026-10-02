"""Builds RP-rock-prototype: world-position rock variation on one blockstate.

A prototype, not part of the pack. honeycomb_block becomes a stone cube whose
faces all point (UV inside one opaque texel) at a descriptor in a generated
material sheet. The terrain shader recognises the descriptor - an opaque
marker and signature at its sheet's top-left - and textures the face from the
world position instead, all from hashes and noise of the position: a stone
variant, rotation and mirror per block, discoloured and mossy patches, strata
lines, weathering streaks down the sides, and clustered cracks.
dead_horn_coral_block becomes the same stone under layers of webbing, sludge
and egg sacs.

Exposed edges get faint, lighter wear too. The shader can't see neighbouring
blocks, but the model can: thin strips along each face's edges are culled by
the block beyond that edge, so one shows only where both sides of its edge
are open (see EDGE_STRIP).

The materials are shader includes this script writes - rockproto_config.glsl
(TUNE), rockproto_main.glsl (the vertex part) and rockproto.glsl (the colours)
- hooked into vanilla's terrain shaders and, where the base pack has them, the
vanilla pack's Sodium block shaders. Sodium tells its shaders no position in
the world, only within the vertex's region of 128 x 64 x 128 blocks, so there
every pattern is fitted to that region and repeats with it, seamlessly (see
ROCK_REGION in rockproto.glsl).

    python make_rock_prototype.py [--base pack] [output folder]

writes the pack to .minecraft/resourcepacks/RP-rock-prototype by default.
It is built on a base pack's terrain, objmc and Sodium shaders - this
repository's vanilla pack unless --base names another - and brings them with
it. Load it above that base: its objmc models then look as they do without
it. Above a pack with another objmc format, that pack's objmc models break.

    python make_rock_prototype.py --base path/to/Mordor-Vanilla RP-rock-prototype-Mordor
"""

import argparse
import json
import random
import re
import shutil
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
STONE = REPO / "assets/minecraft/textures/block"
RESOURCEPACKS = Path.home() / "AppData/Roaming/.minecraft/resourcepacks"

DESCRIPTOR = (8, 8)          # the texel every face's UV points at
# exposed-edge strips: thin faces on each face, along each of its edges,
# culled by the block beyond that edge - so one shows only where both
# sides of the edge are open. Each points at its own descriptor, right of the
# main one, at 1 + 6 * face + edge, telling the shader which face it lies on
# and along which edge.
DIRECTIONS = ("north", "south", "east", "west", "up", "down")
EDGE_STRIP = 4               # strip width, in texels; strips lie on their faces and
                             # the vertex shader lifts them off
VARIANT_ROW = 16             # 16x16 stone variants
CRACK_ROW = 32               # crack overlays from here, CRACK_BLOCKS blocks square each
CRACK_BLOCKS = 4             # keep it dividing 64, Sodium's region height
CRACK_TILE = 16 * CRACK_BLOCKS
CRACKS = 16
SHEET_W = 256
CRACKS_PER_ROW = SHEET_W // CRACK_TILE
SHEET_H = CRACK_ROW + -(-CRACKS // CRACKS_PER_ROW) * CRACK_TILE

# settings, read by the shader from the header
CRACK_CHANCE = 0.45          # of a crack cell having a crack, in each of two layers
DISCOLOUR = 0.45             # how far discoloured patches go to their tint
NOISE_BLOCKS = 7             # size of the discoloured patches, in blocks
TINT_A = (150, 128, 104)     # darker, warmer (x/128 multiplier)
TINT_B = (118, 130, 108)     # mossier

# the web material: the same stone, covered in webbing, sludge and secretions
WEB_BLOCK = "dead_horn_coral_block"
WEB_FRESH = (226, 226, 216)  # fresh webbing
WEB_OLD = (146, 164, 158)    # old, dusty webbing, greenish blue-grey
WEB_TOXIC = (88, 118, 72)    # the poisonous tint it takes in broad washes, a dark sickly green
WEB_SLUDGE = (104, 118, 100) # sludge, spit and other liquids
WEB_SAC = (214, 216, 202)    # egg sacs and clumps, near the webbing's own colour

# shader tunables (written into rockproto_config.glsl as #defines). Under
# Sodium, sizes are fitted to its region, a whole number of them to it.
TUNE = {
    "ROCK_PATCH_BLOCKS": 3.0,        # size of the smaller discoloured patches
    "ROCK_WARP": 2.5,                # how much patch outlines are bent, in blocks
    "ROCK_MOSS_STRENGTH": 0.6,       # the mossy tint's strength, relative to DISCOLOUR
    "ROCK_MOSS_SCALE": 2.0,          # its patches' size, relative to ROCK_PATCH_BLOCKS
    "ROCK_MOSS_COVER": 0.5,          # lower covers more: where its noise passes this
    "ROCK_STRATA_SPACING": 3.0,      # blocks per strata layer, each with at most one line
    "ROCK_STRATA_SHOW": 0.85,         # chance a layer's line shows
    "ROCK_STRATA_RUN_MIN": 4.0,      # each line is cut into pieces of its own length, between these, in blocks...
    "ROCK_STRATA_RUN_MAX": 20.0,
    "ROCK_STRATA_PRESENT": 0.55,     # ...each piece holding the line with this chance
    "ROCK_STRATA_LASTS": 0.7,        # chance the line is there at all over pieces 3 times as long
    "ROCK_STRATA_BREAKS": 0.5,       # chance a line also breaks briefly within its runs
    "ROCK_STRATA_WIDTH_MIN": 1.0,    # thinnest line, in texels
    "ROCK_STRATA_WIDTH_MAX": 14.0,    # widest band, in texels; most lines are nearer the thin end
    "ROCK_STRATA_PAIR": 0.25,        # chance a line has a thinner companion beside it
    "ROCK_STRATA_MIN_SLOPE": 0.3,    # caps how much wider lines get on top faces, where layers run nearly flat
    "ROCK_STRATA_STRENGTH": 0.3,     # how much lighter or darker a line is
    "ROCK_STRATA_DIP": 0.5,         # the layers' steady slope; keep it above the waves' steepest
    "ROCK_STRATA_DIP_ANGLE": 30.0,   # the direction they dip towards, in degrees from east...
    "ROCK_STRATA_DRIFT": 50.0,       # ...drifting by a tilt this many blocks high over 400 blocks (~+-20 degrees);
                                     # under Sodium the dip turns to the nearest axis, steepens to rise a whole
                                     # region height (64) across a region, and doesn't drift
    "ROCK_STRATA_WOBBLE": 3.0,       # each line's own up-and-down along its length, in blocks
    "ROCK_STRATA_WAVE": 2.0,         # how much lines curve, in blocks...
    "ROCK_STRATA_WAVE_BLOCKS": 18.0, # ...over this distance; with a ripple a quarter as big, a third as long
    "ROCK_STREAK_CHANCE": 0.12,      # of a texel column having a weathering streak
    "ROCK_STREAK_LENGTH": 0.6,       # roughly how long a streak runs, in blocks
    "ROCK_STREAK_STRENGTH": 0.3,     # how much a streak darkens
    "ROCK_STREAK_CLUSTER": 3.0,      # size of streaked and clear areas, in blocks
    "ROCK_EDGE_SPLOTCH": 2.5,        # size of the worn and unworn stretches along exposed edges, in blocks
    "ROCK_EDGE_COVER": 0.58,         # higher leaves fewer edges worn
    "ROCK_EDGE_WIDTH": 3.0,          # furthest the wear reaches in, in texels (under EDGE_STRIP)
    "ROCK_EDGE_STRENGTH": 0.2,       # how much lighter worn edges get
    "ROCK_EDGE_DISTANCE": 96.0,      # edge strips aren't drawn past this, in blocks
    "ROCK_CRACK_CLUSTER": 9.0,       # size of more and less cracked areas, in blocks
    "ROCK_CRACK_LAYERS": 3,
    "WEB_PATCH": 4.0,                # size of the thicker and thinner webbing, in blocks
    "WEB_COVER": 0.4,                # lower covers more of the stone
    "WEB_OPEN_DENSITY": 0.6,         # the thickest webbing away from corners, 0-1...
    "WEB_CORNER": 0.9,               # ...and how much more piles into concave corners
    "WEB_SHOW_CORNERS": 0,           # 1 paints the corners found red, to check them
    "WEB_FILM_LAYERS": 3,            # layers of matted webbing...
    "WEB_FILM_OPACITY": 0.6,         # ...each this opaque at most
    "WEB_THREAD_LAYERS": 3,          # layers of loose threads
    "WEB_TOXIC": 0.55,               # higher makes the poisonous tint rarer...
    "WEB_TOXIC_SIZE": 14.0,          # ...its washes this big, in blocks...
    "WEB_TOXIC_STRENGTH": 0.45,      # ...and at most this strong
    "WEB_SLUDGE_SIZE": 2.5,          # size of the sludge's spread, in blocks
    "WEB_SLUDGE_COVER": 0.6,         # higher leaves less sludge
    "WEB_SLUDGE_OPACITY": 0.55,      # how much it covers where it's thickest
    "WEB_DRIP_CHANCE": 0.08,         # of a texel column dripping or hanging a thread, on the sides
    "WEB_SAC_CHANCE": 0.04,          # of an egg sac per 1.1 blocks square, three times more under ceilings
    "WEB_SAC_OPACITY": 0.6,          # how much they show through the webbing
    "WEB_ORB_CELL": 3.0,             # orb webs: at most one per this many blocks square...
    "WEB_ORB_CHANCE": 0.12,          # ...with this chance
}


def crack(rng, size=CRACK_TILE):
    """A crack overlay: rgb is a colour multiplier x128, alpha its strength.

    A wandering line with sudden kinks and a little jitter, and branches that
    may branch again. Its sharpness drifts along it: crisp, dark and narrow in
    places, soft and faint in others. Only the ends taper away.
    """
    import math

    def drift(n):
        # a smooth random curve in [0, 1] over n steps
        keys = [rng.random() for _ in range(n // 12 + 2)]
        return [keys[i // 12] + (keys[i // 12 + 1] - keys[i // 12]) * (i % 12) / 12 for i in range(n)]

    def stroke(x, y, angle, length, weight, depth):
        steps = int(length / 0.5)
        points = []
        heading = angle
        for _ in range(steps):
            jitter = rng.gauss(0, 0.12)
            points.append((x - math.sin(angle) * jitter, y + math.cos(angle) * jitter))
            # wander, but drawn back to a slowly drifting heading: squiggly,
            # yet going somewhere
            heading += rng.gauss(0, 0.03)
            angle += rng.gauss(0, 0.25) + (heading - angle) * 0.18
            if rng.random() < 0.04:
                angle += rng.choice((-1, 1)) * rng.uniform(0.5, 1.0)   # a kink
            x += math.cos(angle) * 0.5
            y += math.sin(angle) * 0.5
        strokes.append((points, drift(steps), weight))
        if depth < 2:
            for _ in range(rng.choice((1, 2, 2, 3)) if depth == 0 else rng.choice((0, 0, 1))):
                i = rng.randrange(steps // 5, 4 * steps // 5)
                bx, by = points[i]
                stroke(bx, by, angle + rng.choice((-1, 1)) * rng.uniform(0.5, 1.2),
                       length * rng.uniform(0.25, 0.5), weight * 0.75, depth + 1)

    strokes = []
    thickness = rng.uniform(0.5, 1.6)
    opacity = rng.uniform(0.45, 1.0)
    angle = rng.uniform(0, 2 * math.pi)
    length = rng.uniform(0.3, 0.9) * size
    x = size / 2 - math.cos(angle) * length / 2
    y = size / 2 - math.sin(angle) * length / 2
    stroke(x, y, angle, length, 1.0, 0)

    dark = [[0.0] * size for _ in range(size)]
    lit = [[0.0] * size for _ in range(size)]
    for points, sharp, weight in strokes:
        n = len(points)
        for i, (cx, cy) in enumerate(points):
            along = i / max(n - 1, 1)
            ends = min(1.0, along / 0.15, (1 - along) / 0.15)      # tapers only the ends
            s = sharp[i]
            strength = opacity * weight * ends * (0.6 + 0.4 * s)
            width = thickness * (0.3 + 0.75 * (1 - s))             # sharp: narrow; soft: wide
            for gy in range(max(0, int(cy) - 4), min(size, int(cy) + 5)):
                for gx in range(max(0, int(cx) - 4), min(size, int(cx) + 5)):
                    d = math.hypot(gx + 0.5 - cx, gy + 0.5 - cy)
                    dark[gy][gx] = max(dark[gy][gx], strength * math.exp(-(d / width) ** 2))
                    rim = math.hypot(gx + 0.5 - (cx + 0.9), gy + 0.5 - (cy + 0.9))
                    lit[gy][gx] = max(lit[gy][gx], 0.4 * strength * math.exp(-(rim / 0.7) ** 2))

    img = Image.new("RGBA", (size, size), (128, 128, 128, 0))
    px = img.load()
    for gy in range(size):
        for gx in range(size):
            # fade the tile's edges, so a crack never ends on a cell border
            edge = min(gx + 0.5, gy + 0.5, size - 0.5 - gx, size - 0.5 - gy)
            fade = min(1.0, max(0.0, (edge - 1.0) / 3.0))
            d, l = dark[gy][gx] * fade, lit[gy][gx] * fade
            if d >= l and d > 0.03:
                px[gx, gy] = (round(128 * 0.38),) * 3 + (round(255 * min(1.0, d)),)
            elif l > 0.03:
                px[gx, gy] = (round(128 * 1.22),) * 3 + (round(255 * l),)
    return img


def sheet(signature, extra=()):
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 255))
    px = img.load()
    header = [
        (98, 76, 54, 255),                            # marker
        signature,                                    # which material
        (7, CRACKS, round(CRACK_CHANCE * 255), 255),  # variants, cracks, crack chance
        (round(DISCOLOUR * 255), NOISE_BLOCKS, 0, 255),
        TINT_A + (255,),
        TINT_B + (255,),
        (CRACK_BLOCKS, CRACKS_PER_ROW, CRACK_ROW // 16, 255),
        *(c + (255,) for c in extra),
    ]
    for x, p in enumerate(header):
        px[x, 0] = p
    dx, dy = DESCRIPTOR
    for x in range(dx, dx + 1 + len(DIRECTIONS) ** 2):
        px[x, dy] = (x >> 4, ((x & 15) << 4) | (dy >> 8), dy & 255, 255)

    variants = [STONE / "stone.png"] + [STONE / f"stone_{i}.png" for i in range(2, 8)]
    for i, f in enumerate(variants):
        img.paste(Image.open(f).convert("RGBA"), (16 * i, VARIANT_ROW))
    rng = random.Random(7)
    for i in range(CRACKS):
        img.paste(crack(rng), (CRACK_TILE * (i % CRACKS_PER_ROW), CRACK_ROW + CRACK_TILE * (i // CRACKS_PER_ROW)))
    return img


def model(texture, strips=True):
    dx, dy = DESCRIPTOR

    def uv(x):
        return [16 * (x + 0.25) / SHEET_W, 16 * (dy + 0.25) / SHEET_H,
                16 * (x + 0.75) / SHEET_W, 16 * (dy + 0.75) / SHEET_H]

    faces = {d: {"uv": uv(dx), "texture": "#0", "cullface": d} for d in DIRECTIONS}
    elements = [{"from": [0, 0, 0], "to": [16, 16, 16], "faces": faces}]
    axis = {"north": 2, "south": 2, "east": 0, "west": 0, "up": 1, "down": 1}
    high = {"south", "east", "up"}
    for f, face in enumerate(DIRECTIONS):
        for k, edge in enumerate(DIRECTIONS):
            if not strips or axis[edge] == axis[face]:
                continue
            lo, hi = [0.0, 0.0, 0.0], [16.0, 16.0, 16.0]
            lo[axis[face]] = hi[axis[face]] = 16.0 if face in high else 0.0
            if edge in high:
                lo[axis[edge]] = 16 - EDGE_STRIP
            else:
                hi[axis[edge]] = EDGE_STRIP
            elements.append({"from": lo, "to": hi, "faces": {
                face: {"uv": uv(dx + 1 + 6 * f + k), "texture": "#0", "cullface": edge}}})
    return {"textures": {"0": texture, "particle": "minecraft:block/stone"},
            "elements": elements}


VSH_OUTS = """
// rock prototype (rockproto_main.glsl)
flat out int material;
flat out ivec2 matOrigin;
flat out ivec4 matInfo;
flat out ivec4 matTune;
flat out ivec4 matTintA;
flat out ivec4 matTintB;
flat out ivec4 matCrack;
flat out int matEdge;
out vec3 worldPos;"""

FSH_INS = """
// rock prototype (rockproto.glsl)
flat in int material;
flat in ivec2 matOrigin;
flat in ivec4 matInfo;
flat in ivec4 matTune;
flat in ivec4 matTintA;
flat in ivec4 matTintB;
flat in ivec4 matCrack;
flat in int matEdge;
in vec3 worldPos;"""

# rockproto_main.glsl
RP_MAIN = """// The rock prototype's vertex part, imported into main() right after
// objmc_main.glsl, whose atlasSize it reads. Shared by vanilla's terrain.vsh
// and Sodium's block_layer_opaque.vsh: ROCK_WORLD is the vertex's position in
// the world - or, under Sodium, in its region - and ROCK_SECTION_CENTRE its
// section's centre relative to the camera, both set there.
//
// A face whose UV sits on an opaque texel leading to the material marker and
// signature is textured by world position (rockproto.glsl).

material = 0;
matEdge = -1;
int stripFace = 0;
worldPos = ROCK_WORLD;
if (isCustom == 0) {
    vec2 matFrac = fract(UV0 * vec2(atlasSize));
    if (all(greaterThan(matFrac, vec2(0.1))) && all(lessThan(matFrac, vec2(0.9)))) {
        ivec2 at = ivec2(UV0 * vec2(atlasSize));
        ivec4 p = ivec4(texelFetch(Sampler0, at, 0) * 255.0 + 0.5);
        ivec2 tl = at - ivec2(p.r * 16 + (p.g >> 4), (p.g & 15) * 256 + p.b);
        if (p.a == 255 && all(greaterThanEqual(tl, ivec2(0)))) {
            ivec4 m0 = ivec4(texelFetch(Sampler0, tl, 0) * 255.0 + 0.5);
            ivec4 m1 = ivec4(texelFetch(Sampler0, tl + ivec2(1, 0), 0) * 255.0 + 0.5);
            // signature (13, 57, 91): rock; (13, 57, 92): rock under webs
            if (m0 == ivec4(98, 76, 54, 255) && m1.rg == ivec2(13, 57) && m1.b >= 91 && m1.b <= 92 && m1.a == 255) {
                material = m1.b - 90;
                matOrigin = tl;
                // an exposed-edge strip's descriptor sits right of the
                // main one, at 1 + 6 * its face + its edge, each a
                // direction: north, south, east, west, up, down
                int strip = at.x - tl.x - (ROCK_DESCRIPTOR_X + 1);
                if (strip >= 0 && material == 1) {
                    matEdge = strip % 6;
                    stripFace = strip / 6;
                }
                matInfo = ivec4(texelFetch(Sampler0, tl + ivec2(2, 0), 0) * 255.0 + 0.5);
                matTune = ivec4(texelFetch(Sampler0, tl + ivec2(3, 0), 0) * 255.0 + 0.5);
                matTintA = ivec4(texelFetch(Sampler0, tl + ivec2(4, 0), 0) * 255.0 + 0.5);
                matTintB = ivec4(texelFetch(Sampler0, tl + ivec2(5, 0), 0) * 255.0 + 0.5);
                matCrack = ivec4(texelFetch(Sampler0, tl + ivec2(6, 0), 0) * 255.0 + 0.5);
            }
        }
    }
}
// Exposed-edge strips lie on their faces. Drawn as they are they would
// fight the face's depth (and each other's at corners), so they are lifted
// off it along the face's normal - by more further off, where depth is
// coarser, staying well under a screen pixel. Along the normal, not
// towards the camera: a strip whose face is against a solid block (shown
// as the block beyond its edge is open) then sinks into that block, rather
// than poking out, unlit, past the faces next to it. Overlapping strips
// run along different axes, so each axis gets its own lift: up and down
// edges furthest, then north and south, then east and west. Past
// ROCK_EDGE_DISTANCE, by section, where the wear is too small to see, they
// are dropped.
if (matEdge >= 0) {
    const vec3 stripNormals[6] = vec3[](vec3(0.0, 0.0, -1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0),
                                        vec3(-1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0));
    if (length(ROCK_SECTION_CENTRE) > ROCK_EDGE_DISTANCE) {
        Pos = vec3(0.0);
    } else {
        float level = matEdge >= 4 ? 3.0 : matEdge <= 1 ? 2.0 : 1.0;
        float d = length(Pos);
        Pos += stripNormals[min(stripFace, 5)] * level * (5.0e-4 + 2.5e-6 * d * d);
    }
}
"""

# rockproto.glsl
RP_FUNCS = """// The rock prototype's colours: rockColor() for rock, webColor() for rock
// under webs, both from the world position (worldPos). Shared by vanilla's
// terrain.fsh and Sodium's block_layer_opaque.fsh: ROCK_ATLAS_SIZE is the
// atlas's size in texels, set there.
//
// Sodium tells its shaders no position in the world, only within the vertex's
// region; there ROCK_REGION is that region's size, 128 x 64 x 128 blocks, and
// every pattern repeats with it. Each one is fitted to it - a whole number of
// noise cells, strata layers, pieces, cells of threads and sacs to a region -
// and its lattice wraps round, so it carries on seamlessly into the next
// region, where positions start again. Per-block and per-texel hashes need
// nothing: they are only ever compared with themselves.

uint rockHash(ivec4 p) {
    uint h = uint(p.x) * 73856093u ^ uint(p.y) * 19349663u ^ uint(p.z) * 83492791u ^ uint(p.w) * 2654435761u;
    h ^= h >> 13;
    h *= 0x5bd1e995u;
    h ^= h >> 15;
    return h;
}

float rockRand(ivec4 p) {
    return float(rockHash(p) & 0xFFFFu) / 65535.0;
}

// Lattice cell c wrapped round period, on each axis that has one (0: none).
int rockWrap(int c, int period) {
    return period > 0 ? ((c % period) + period) % period : c;
}

ivec2 rockWrap(ivec2 c, ivec2 period) {
    return ivec2(rockWrap(c.x, period.x), rockWrap(c.y, period.y));
}

ivec3 rockWrap(ivec3 c, ivec3 period) {
    return ivec3(rockWrap(c.x, period.x), rockWrap(c.y, period.y), rockWrap(c.z, period.z));
}

// Value noise on the integer lattice, smoothly interpolated, repeating every
// `period` cells on each axis that has one.
float rockNoiseP(vec3 p, ivec3 period, int salt) {
    ivec3 i = ivec3(floor(p));
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = 0.0;
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, (k >> 2) & 1);
        vec3 w = mix(1.0 - f, f, vec3(o));
        n += w.x * w.y * w.z * rockRand(ivec4(rockWrap(i + o, period), salt));
    }
    return n;
}

// Three of them at once, from one hash per corner.
vec3 rockNoiseP3(vec3 p, ivec3 period, int salt) {
    ivec3 i = ivec3(floor(p));
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    vec3 n = vec3(0.0);
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, (k >> 2) & 1);
        vec3 w = mix(1.0 - f, f, vec3(o));
        uint h = rockHash(ivec4(rockWrap(i + o, period), salt));
        n += w.x * w.y * w.z * vec3(uvec3(h, h >> 10, h >> 20) & 1023u) / 1023.0;
    }
    return n;
}

float rockNoise(vec3 p, int salt) {
    return rockNoiseP(p, ivec3(0), salt);
}

// World position w on a noise lattice of cells `blocks` big, and the period
// that lattice has: under ROCK_REGION the cells are fitted to the region.
vec3 rockLattice(vec3 w, vec3 blocks, out ivec3 period) {
#ifdef ROCK_REGION
    vec3 cells = max(floor(ROCK_REGION / blocks + 0.5), 1.0);
    period = ivec3(cells);
    return w * cells / ROCK_REGION;
#else
    period = ivec3(0);
    return w / blocks;
#endif
}

// Noise of world position w, in cells `blocks` big, its lattice moved by
// `offset` cells.
float rockField(vec3 w, vec3 blocks, vec3 offset, int salt) {
    ivec3 period;
    vec3 p = rockLattice(w, blocks, period);
    return rockNoiseP(p + offset, period, salt);
}

float rockField(vec3 w, float blocks, vec3 offset, int salt) {
    return rockField(w, vec3(blocks), offset, salt);
}

// The same, but with its peaks lined up on no row, column or block edge: on a
// lattice turned against the block grid - or, under ROCK_REGION, where a
// turned lattice couldn't repeat with the region, a bent one.
float rockFieldSkew(vec3 w, vec3 blocks, vec3 offset, int salt) {
#ifdef ROCK_REGION
    ivec3 period;
    vec3 bend = rockNoiseP3(rockLattice(w, blocks * 1.7, period) + offset, period, salt + 500) - 0.5;
    return rockField(w + bend * blocks * 1.2, blocks, offset, salt);
#else
    const mat3 turn = mat3( 0.00,  0.80,  0.60,
                           -0.80,  0.36, -0.48,
                           -0.60, -0.48,  0.64);
    return rockNoise(turn * (w / blocks + offset), salt);
#endif
}

float rockFieldSkew(vec3 w, float blocks, vec3 offset, int salt) {
    return rockFieldSkew(w, vec3(blocks), offset, salt);
}

// Noise along s, a horizontal position along one axis, in cells `blocks` long
// (yz picking the line of it).
float rockAlong(float s, float blocks, vec2 yz, int salt) {
#ifdef ROCK_REGION
    float cells = max(floor(ROCK_REGION.x / blocks + 0.5), 1.0);
    return rockNoiseP(vec3(s * cells / ROCK_REGION.x, yz), ivec3(int(cells), 0, 0), salt);
#else
    return rockNoise(vec3(s / blocks, yz), salt);
#endif
}

// A horizontal length fitted to the region, a whole number of them to it.
float rockFitH(float blocks) {
#ifdef ROCK_REGION
    return ROCK_REGION.x / max(floor(ROCK_REGION.x / blocks + 0.5), 1.0);
#else
    return blocks;
#endif
}

// How many of them that is, to wrap round (0: none).
int rockCellsH(float blocks) {
#ifdef ROCK_REGION
    return int(floor(ROCK_REGION.x / blocks + 0.5));
#else
    return 0;
#endif
}

// A face's plane's extent in the region, along its two axes (0: none).
ivec2 rockPlanePeriod(int axis) {
#ifdef ROCK_REGION
    ivec3 r = ivec3(ROCK_REGION);
    return axis == 1 ? r.xz : axis == 0 ? r.zy : r.xy;
#else
    return ivec2(0);
#endif
}

// Cells about `size` blocks square on a face's plane, fitted to its extent in
// the region on each axis; their count along each, to wrap round, in `period`.
vec2 rockPlaneCells(float size, ivec2 planePeriod, out ivec2 period) {
#ifdef ROCK_REGION
    vec2 count = max(floor(vec2(planePeriod) / size + 0.5), 1.0);
    period = ivec2(count);
    return vec2(planePeriod) / count;
#else
    period = ivec2(0);
    return vec2(size);
#endif
}

// (u, v) on the face turned by quarter turns and mirrored, within [0, 1).
vec2 rockTurn(vec2 uv, int turns, bool mirror) {
    if (mirror) uv.x = 1.0 - uv.x;
    for (int i = 0; i < turns; i++) uv = vec2(1.0 - uv.y, uv.x);
    return uv;
}

vec4 rockSample(vec2 texel, vec2 dTexelX, vec2 dTexelY, vec2 lo, vec2 hi) {
    vec2 atlas = ROCK_ATLAS_SIZE;
    vec2 pixelSize = 1.0 / atlas;
    vec2 du = dTexelX * pixelSize;
    vec2 dv = dTexelY * pixelSize;
    // stay a filter footprint inside the tile, as objmc's sampleCustom does
    float footprint = min(max(length(dTexelX), length(dTexelY)), 16.0);
    vec2 margin = vec2(0.5 + footprint);
    texel = clamp(texel, lo + margin, hi - margin);
    return sampleNearest(Sampler0, texel * pixelSize, pixelSize, du, dv, sqrt(du * du + dv * dv));
}

// The direction the strata dip towards. Under ROCK_REGION, turned to the
// nearest axis: a slope along an axis can rise a whole number of the region's
// heights across it, and repeat with it.
vec2 rockDipDir() {
    float angle = radians(ROCK_STRATA_DIP_ANGLE);
    vec2 d = vec2(cos(angle), sin(angle));
#ifdef ROCK_REGION
    d = abs(d.x) >= abs(d.y) ? vec2(sign(d.x), 0.0) : vec2(0.0, sign(d.y));
#endif
    return d;
}

float rockDipSlope() {
#ifdef ROCK_REGION
    return max(floor(ROCK_STRATA_DIP * ROCK_REGION.x / ROCK_REGION.y + 0.5), 1.0) * ROCK_REGION.y / ROCK_REGION.x;
#else
    return ROCK_STRATA_DIP;
#endif
}

// The strata layers' spacing; under ROCK_REGION a whole number of them to the
// region's height.
float rockStrataSpacing() {
#ifdef ROCK_REGION
    return ROCK_REGION.y / max(floor(ROCK_REGION.y / ROCK_STRATA_SPACING + 0.5), 1.0);
#else
    return ROCK_STRATA_SPACING;
#endif
}

// Which line a layer holds: under ROCK_REGION the region's height of layers
// over, the same one again.
int rockStrataLine(int layer) {
#ifdef ROCK_REGION
    return rockWrap(layer, max(int(floor(ROCK_REGION.y / ROCK_STRATA_SPACING + 0.5)), 1));
#else
    return layer;
#endif
}

// The strata height at a point: its height, tilted by one steady dip and
// curved by waves. Strata lines lie at fixed values of it. The dip is steeper
// than the waves ever get, so the layers have no highs or lows: lines on a top
// face always run one way, never closing on themselves, and lines on a side
// always climb or fall one way.
float rockStrataY(vec3 p) {
    vec3 ground = vec3(p.x, 0.0, p.z);
    float dip = dot(p.xz, rockDipDir()) * rockDipSlope();
    float wave = (rockField(ground, ROCK_STRATA_WAVE_BLOCKS, vec3(0.0), 31) - 0.5)
               + (rockField(ground, ROCK_STRATA_WAVE_BLOCKS / 3.0, vec3(13.0), 36) - 0.5) * 0.25;
    // a very large, gentle tilt on top, turning the dip's direction and
    // steepness slowly across the land (under ROCK_REGION, too large to fit:
    // none)
    float drift = (rockField(ground, 400.0, vec3(71.0), 37) - 0.5) * ROCK_STRATA_DRIFT;
    return p.y + dip + drift + wave * ROCK_STRATA_WAVE;
}

// A strata line's own wobble at s along the strike, about -0.5 to 0.5.
float rockStrataWobble(float s, float blocks, int line) {
    return rockAlong(s, blocks, vec2(float(line) * 5.3, 9.0), 79) - 0.5
         + (rockAlong(s, blocks / 2.7, vec2(float(line) * 5.3, 19.0), 80) - 0.5) * 0.4;
}

// Whether strata line `line` is present at ground point g (in its own piece
// lengths): the ground is cut into pieces, each holding the line or not, with
// `chance`. A present piece holds it at full strength; only where a run of
// them ends does it fade out, over `soft` of a piece. Absent pieces in a row
// leave long gaps, and the line may not come back at all within view.
float rockStrataPresence(vec2 g, ivec2 period, int line, int salt, float chance, float soft) {
    vec2 c = floor(g);
    vec2 f = smoothstep(0.5 - soft, 0.5 + soft, fract(g));
    ivec2 i = ivec2(c);
    float v00 = step(rockRand(ivec4(rockWrap(i, period), line, salt)), chance);
    float v10 = step(rockRand(ivec4(rockWrap(i + ivec2(1, 0), period), line, salt)), chance);
    float v01 = step(rockRand(ivec4(rockWrap(i + ivec2(0, 1), period), line, salt)), chance);
    float v11 = step(rockRand(ivec4(rockWrap(i + ivec2(1, 1), period), line, salt)), chance);
    return mix(mix(v00, v10, f.x), mix(v01, v11, f.x), f.y);
}

vec4 rockColor(vec3 normal) {
    vec3 an = abs(normal);
    int axis = (an.y >= an.x && an.y >= an.z) ? 1 : (an.x >= an.z ? 0 : 2);
    float side = axis == 0 ? sign(normal.x) : axis == 1 ? sign(normal.y) : sign(normal.z);
    // the face's plane, upright on the sides
    vec2 plane = axis == 1 ? worldPos.xz : axis == 0 ? vec2(-side * worldPos.z, -worldPos.y)
                                                     : vec2(side * worldPos.x, -worldPos.y);
    vec2 dPlaneX = dFdx(plane), dPlaneY = dFdy(plane);
    ivec3 cell = ivec3(floor(worldPos - normal * 0.01));
    ivec4 key = ivec4(cell, axis * 2 + int(side > 0.0));

    // a stone variant per block; tops and bottoms turned at random, sides mirrored
    uint h = rockHash(key);
    int variant = int(h % uint(max(matInfo.x, 1)));
    int turns = axis == 1 ? int((h >> 8) & 3u) : 0;
    bool mirror = ((h >> 10) & 1u) == 1u;
    vec2 local = rockTurn(fract(plane), turns, mirror);
    vec2 tileLo = vec2(matOrigin) + vec2(16 * variant, 16);
    // derivatives of the continuous plane coordinates, turned like local
    vec2 dx = rockTurn(dPlaneX + 0.5, turns, mirror) - rockTurn(vec2(0.5), turns, mirror);
    vec2 dy = rockTurn(dPlaneY + 0.5, turns, mirror) - rockTurn(vec2(0.5), turns, mirror);
    vec4 color = rockSample(tileLo + local * 16.0, dx * 16.0, dy * 16.0, tileLo, tileLo + 16.0);

    // discoloration, per texel, so it keeps the texture's pixel grid
    vec3 texelPos = (floor(worldPos * 16.0 - normal * 0.5) + 0.5) / 16.0;
    float strength = float(matTune.x) / 255.0;
    // patch outlines bent by another noise, for organic shapes
    vec3 warp = vec3(rockField(texelPos, 5.0, vec3(0.0), 21), rockField(texelPos, 5.0, vec3(0.0), 22),
                     rockField(texelPos, 5.0, vec3(0.0), 23)) - 0.5;
    vec3 warped = texelPos + warp * ROCK_WARP;
    // hard edges in some places, soft in others; strong patches in some, faint in others
    float edge = mix(0.03, 0.18, rockField(texelPos, 6.0, vec3(0.0), 16));
    float contrast = mix(0.35, 1.0, rockField(texelPos, 8.0, vec3(0.0), 17));
    float fieldA = rockField(warped, ROCK_PATCH_BLOCKS / 0.5, vec3(0.0), 11) * 0.5
                 + rockField(warped, ROCK_PATCH_BLOCKS, vec3(0.0), 12) * 0.35
                 + rockField(warped, ROCK_PATCH_BLOCKS / 4.0, vec3(0.0), 15) * 0.15;
    // the mossy tint: larger, softer, gentler washes
    float moss = ROCK_PATCH_BLOCKS * ROCK_MOSS_SCALE;
    float fieldB = rockField(warped, moss / 0.5, vec3(31.7), 13) * 0.5
                 + rockField(warped, moss, vec3(9.1), 14) * 0.35
                 + rockField(warped, moss / 4.0, vec3(5.3), 18) * 0.15;
    // strata: lines where the face cuts the tilted, undulating layers - on
    // the sides, and on tops and bottoms where a layer meets their height
    float strata = 0.0;
    float strataSign = 1.0;
    {
        // each layer of the strata height holds at most one line, at its own
        // offset, width, strength and shade; the texel's distance to it is
        // taken across the line, so it keeps one thickness however it runs
        // the strata height's slope within the face's own plane
        vec3 faceU = axis == 0 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
        vec3 faceV = axis == 1 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
        float sy = rockStrataY(texelPos);
        vec2 gradient = vec2(rockStrataY(texelPos + faceU / 16.0) - sy,
                             rockStrataY(texelPos + faceV / 16.0) - sy) * 16.0;
        float steep = max(length(gradient), ROCK_STRATA_MIN_SLOPE);
        float spacing = rockStrataSpacing();
        int layer = int(floor(sy / spacing));
        vec2 dipDir = rockDipDir();
        vec2 strikeDir = vec2(-dipDir.y, dipDir.x);
        // a line wobbles up to about 0.7 * ROCK_STRATA_WOBBLE out of its own layer
        for (int i = -2; i <= 2; i++) {
            int id = rockStrataLine(layer + i);
            ivec4 key = ivec4(id, 0, 0, 71);
            if (rockRand(key) > ROCK_STRATA_SHOW) continue;
            float lineY = (float(layer + i) + rockRand(key + ivec4(0, 1, 0, 0))) * spacing;
            // its own wobble, so no two lines run parallel. It moves the line
            // only along the strike, across the dip, so it can't cancel the
            // dip and the line still never folds back on itself.
            float wobbleLength = mix(6.0, 16.0, rockRand(key + ivec4(0, 16, 0, 0)));
            float wobbleSize = ROCK_STRATA_WOBBLE * mix(0.5, 1.0, rockRand(key + ivec4(0, 17, 0, 0)));
            float s0 = dot(texelPos.xz, strikeDir);
            float sU = dot((texelPos + faceU / 16.0).xz, strikeDir);
            float sV = dot((texelPos + faceV / 16.0).xz, strikeDir);
            float w0 = rockStrataWobble(s0, wobbleLength, id) * wobbleSize;
            vec2 lineGradient = gradient - vec2(rockStrataWobble(sU, wobbleLength, id) * wobbleSize - w0,
                                                rockStrataWobble(sV, wobbleLength, id) * wobbleSize - w0) * 16.0;
            float lineSteep = max(length(lineGradient), ROCK_STRATA_MIN_SLOPE);
            float across = (sy - w0 - lineY) / lineSteep * 16.0;           // in texels
            float distance = abs(across);
            // its own width - mostly thin, sometimes a broad band - swelling and
            // narrowing along it, and its own edge, crisp or soft
            float wide = rockRand(key + ivec4(0, 2, 0, 0));
#ifdef ROCK_REGION
            float along = rockAlong(s0, 8.0, vec2(float(id) * 3.1, 5.0), 73);
#else
            float along = rockNoise(vec3((texelPos.x - texelPos.z) / 8.0, float(id) * 3.1, 5.0), 73);
#endif
            float width = mix(ROCK_STRATA_WIDTH_MIN, ROCK_STRATA_WIDTH_MAX, wide) * mix(0.3, 1.8, along);
            float soft = mix(0.4, 0.9, rockRand(key + ivec4(0, 5, 0, 0)));
            // where it shows is its own: pieces of its own length along it,
            // each there or not, so it breaks off at its own intervals and
            // sometimes never comes back; its ends crisp or long fades, faded
            // or thinned out. Pieces are taken on the ground, turned to the
            // layers' strike and bent a little, so a line breaks on any face.
            float pieceLength = mix(ROCK_STRATA_RUN_MIN, ROCK_STRATA_RUN_MAX, rockRand(key + ivec4(0, 9, 0, 0)));
            float endSoft = mix(0.05, 0.4, rockRand(key + ivec4(0, 10, 0, 0)));
            vec2 bend = vec2(rockField(texelPos, 7.0, vec3(0.0), 74), rockField(texelPos, 7.0, vec3(17.0), 75)) - 0.5;
            vec2 ground = texelPos.xz + bend * 4.0;
            vec2 strike = vec2(dot(ground, strikeDir), dot(ground, dipDir));
            vec2 offset = vec2(rockRand(key + ivec4(0, 12, 0, 0)), rockRand(key + ivec4(0, 13, 0, 0))) * 97.0;
            float stretch = rockStrataPresence(strike / rockFitH(pieceLength) + offset, ivec2(rockCellsH(pieceLength)),
                                               id, 76, ROCK_STRATA_PRESENT, endSoft)
                          // over far longer stretches it is there or gone altogether
                          * rockStrataPresence(strike / rockFitH(pieceLength * 3.0) + offset, ivec2(rockCellsH(pieceLength * 3.0)),
                                               id, 77, ROCK_STRATA_LASTS, 0.3);
            // some lines also break for a moment now and then within their runs
            if (rockRand(key + ivec4(0, 14, 0, 0)) < ROCK_STRATA_BREAKS) {
                float gapLength = mix(1.0, 3.0, rockRand(key + ivec4(0, 15, 0, 0)));
                stretch *= rockStrataPresence(strike / rockFitH(gapLength) + offset, ivec2(rockCellsH(gapLength)),
                                              id, 78, 0.8, 0.2);
            }
            float taper = rockRand(key + ivec4(0, 11, 0, 0));
            width *= mix(1.0, stretch, taper);
            // broad bands gentle, thin lines strong
            // every line fades in and out; the tapering ones thin out too
            float weight = mix(0.5, 1.0, rockRand(key + ivec4(0, 3, 0, 0))) * mix(1.0, 0.45, wide)
                         * mix(stretch, smoothstep(0.0, 0.6, stretch), taper);
            float line = (1.0 - smoothstep(width * (1.0 - soft), width, distance)) * weight;
            // now and then a thinner companion a few texels off
            if (rockRand(key + ivec4(0, 6, 0, 0)) < ROCK_STRATA_PAIR) {
                float gap = width + mix(1.5, 4.0, rockRand(key + ivec4(0, 7, 0, 0)));
                float pairSide = rockRand(key + ivec4(0, 8, 0, 0)) > 0.5 ? 1.0 : -1.0;
                float pairDistance = abs(across - pairSide * gap);
                line = max(line, (1.0 - smoothstep(0.5, 1.0, pairDistance)) * weight * 0.7);
            }
            if (line > strata) {
                strata = line;
                strataSign = rockRand(key + ivec4(0, 4, 0, 0)) > 0.5 ? 1.0 : -1.0;
            }
        }
    }

    // patches, kept off the strata lines
    float a = smoothstep(0.6 - edge, 0.6 + edge, fieldA) * contrast * (1.0 - strata);
    float b = smoothstep(ROCK_MOSS_COVER - 0.15, ROCK_MOSS_COVER + 0.15, fieldB) * contrast * (1.0 - strata) * ROCK_MOSS_STRENGTH;
    color.rgb = mix(color.rgb, color.rgb * vec3(matTintA.rgb) / 128.0, a * strength);
    color.rgb = mix(color.rgb, color.rgb * vec3(matTintB.rgb) / 128.0, b * strength);
    color.rgb *= 1.0 + strataSign * strata * ROCK_STRATA_STRENGTH;

    // weathering: short, thin darker streaks running down the sides
    if (axis != 1) {
        int column = int(floor(plane.x * 16.0));
        // a column is streaky over a few blocks of height at a time, offset
        // per column, so streaks don't stack up in the same columns all the
        // way up a wall
        // its own band height too, so band ends don't fall into rows
        float phase = rockRand(ivec4(column, cell[axis], axis, 55)) * 13.0;
        float bandHeight = mix(2.0, 5.0, rockRand(ivec4(column, cell[axis], axis, 57)));
        int heightBand = int(floor(texelPos.y / bandHeight + phase));
        ivec4 columnKey = ivec4(column, cell[axis] * 31 + heightBand, axis, 51);
        // more streaks in some soft, irregular areas, few elsewhere; the noise
        // is turned against the block grid, as an upright one put its
        // clusters on a regular grid of columns and heights
        vec3 clusterBlocks = vec3(1.0, 1.0 / 0.6, 1.0) * ROCK_STREAK_CLUSTER;
        float clustering = rockFieldSkew(texelPos, clusterBlocks, vec3(0.0), 54) * 0.65
                         + rockFieldSkew(texelPos, clusterBlocks / 2.3, vec3(7.0), 56) * 0.35;
        float cluster = smoothstep(0.45, 0.75, clustering);
        float chance = ROCK_STREAK_CHANCE * mix(0.15, 4.0, cluster);
        if (rockRand(columnKey) < chance) {
            // neighbouring streaks run alike, so a cluster reads as one wider patch
            // its own vertical phase, so neighbours don't start and stop level
            float run = rockNoise(vec3(float(column) * 0.15, texelPos.y / ROCK_STREAK_LENGTH + phase, float(cell[axis])), 52);
            // a short run, its strength varying texel by texel down it
            // lone streaks, outside the clusters, only faint
            float streak = smoothstep(0.58, 0.75, run) * mix(0.3, 1.0, cluster)
                         * mix(0.4, 1.0, rockNoise(vec3(float(column), texelPos.y * 4.0, 3.0), 53))
                         * mix(0.5, 1.0, rockRand(columnKey + ivec4(0, 0, 0, 1)));
            color.rgb *= 1.0 - streak * ROCK_STREAK_STRENGTH;
        }
    }

    // cracks, per cell of matCrack.x blocks on the face's plane, in layers
    // offset from each other - so they overlap, and hide the grid - and more
    // likely in some areas than others, so they cluster
    int cellBlocks = max(matCrack.x, 1);
    int perRow = max(matCrack.y, 1);
    float tile = 16.0 * float(cellBlocks);
    ivec2 crackPeriod = rockPlanePeriod(axis) / cellBlocks;
    float cracked = mix(0.1, 2.0, smoothstep(0.3, 0.75, rockField(worldPos, ROCK_CRACK_CLUSTER, vec3(0.0), 61)));
    for (int layer = 0; layer < ROCK_CRACK_LAYERS; layer++) {
        vec2 cellPlane = plane / float(cellBlocks) + vec2(0.37, 0.61) * float(layer);
        uint hc = rockHash(ivec4(rockWrap(ivec2(floor(cellPlane)), crackPeriod), axis * 7 + cell[axis], 99 + layer));
        if (float(hc & 255u) / 255.0 < cracked * float(matInfo.z) / 255.0) {
            int crack = int((hc >> 8) % uint(max(matInfo.y, 1)));
            int cTurns = int((hc >> 12) & 3u);
            bool cMirror = ((hc >> 14) & 1u) == 1u;
            vec2 cLocal = rockTurn(fract(cellPlane), cTurns, cMirror);
            vec2 cLo = vec2(matOrigin) + vec2(float(crack % perRow) * tile, float(matCrack.z * 16) + float(crack / perRow) * tile);
            vec2 cdx = rockTurn(dPlaneX / float(cellBlocks) + 0.5, cTurns, cMirror) - rockTurn(vec2(0.5), cTurns, cMirror);
            vec2 cdy = rockTurn(dPlaneY / float(cellBlocks) + 0.5, cTurns, cMirror) - rockTurn(vec2(0.5), cTurns, cMirror);
            vec4 overlay = rockSample(cLo + cLocal * tile, cdx * tile, cdy * tile, cLo, cLo + tile);
            color.rgb = mix(color.rgb, color.rgb * overlay.rgb * (255.0 / 128.0), overlay.a);
        }
    }

    // exposed edges (see the model's strips): faint, lighter wear in
    // splotches along some of them, wrapping round the edge onto both faces,
    // reaching a ragged few texels in
    if (matEdge >= 0) {
        const vec3 edgeDirs[6] = vec3[](vec3(0.0, 0.0, -1.0), vec3(0.0, 0.0, 1.0), vec3(1.0, 0.0, 0.0),
                                        vec3(-1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, -1.0, 0.0));
        float toward = dot(texelPos - (vec3(cell) + 0.5), edgeDirs[min(matEdge, 5)]);
        float edgeDistance = (0.5 - toward) * 16.0 - 0.5;            // texels in from the edge
        float splotch = rockFieldSkew(texelPos, ROCK_EDGE_SPLOTCH, vec3(0.0), 81) * 0.7
                      + rockFieldSkew(texelPos, ROCK_EDGE_SPLOTCH / 3.1, vec3(5.0), 82) * 0.3;
        float amount = smoothstep(ROCK_EDGE_COVER, ROCK_EDGE_COVER + 0.12, splotch);
        float reach = mix(0.6, ROCK_EDGE_WIDTH, rockFieldSkew(texelPos, 1.0 / 1.7, vec3(3.0), 83));
        float ragged = rockRand(ivec4(ivec3(floor(texelPos * 16.0)), 84));
        float wear = amount * (1.0 - smoothstep(reach * 0.3, reach, edgeDistance + ragged));
        float grey = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        color.rgb = mix(color.rgb, vec3(grey), wear * 0.3) * (1.0 + wear * ROCK_EDGE_STRENGTH);
    }
    return vec4(color.rgb, 1.0);
}

// ---------------------------------------------------------------- webs
// The web material: rockColor's stone, covered in layers of webbing, with
// sludge, drips, hanging threads, egg sacs, and now and then an orb web. Its
// colours are in the sheet's header, after rock's.

vec3 webHeader(int i) {
    return texelFetch(Sampler0, matOrigin + ivec2(i, 0), 0).rgb;
}

float webByte(uint h, int i) {
    return float((h >> (8 * i)) & 255u) / 255.0;
}

// Coverage of a 1-texel thread through texel distance d.
float webLine(float d) {
    return 1.0 - smoothstep(0.35, 0.85, d);
}

// Distance from p to the thread from a to b, sagging by `sag` at its middle
// (towards +y, down on the sides).
float webThread(vec2 p, vec2 a, vec2 b, float sag) {
    vec2 ab = b - a;
    float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    return length(p - (a + ab * t + vec2(0.0, sag * 4.0 * t * (1.0 - t))));
}

// One layer of loose threads at texel point p (in blocks, on a face's plane
// of extent planePeriod): up to two per cell of about cellSize, each reaching
// into the cells around it. Their cover, 0 to 1.
float webThreads(vec2 p, float cellSize, ivec2 planePeriod, bool hangs, int salt) {
    ivec2 period;
    vec2 size = rockPlaneCells(cellSize, planePeriod, period);
    ivec2 c0 = ivec2(floor(p / size));
    float cover = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            for (int k = 0; k < 2; k++) {
                ivec2 c = c0 + ivec2(i, j);
                ivec2 id = rockWrap(c, period);
                uint h = rockHash(ivec4(id, k, salt));
                if (webByte(h, 0) > 0.8) continue;
                uint h2 = rockHash(ivec4(id, k, salt + 1));
                vec2 centre = (vec2(c) + vec2(webByte(h, 1), webByte(h, 2))) * size;
                float angle = webByte(h, 3) * 3.14159;
                vec2 reach = vec2(cos(angle), sin(angle)) * mix(0.3, 0.9, webByte(h2, 0)) * cellSize;
                float sag = hangs ? abs(reach.x) * 0.3 * webByte(h2, 1) : 0.0;
                float d = webThread(p, centre - reach, centre + reach, sag) * 16.0;
                cover = max(cover, webLine(d) * mix(0.35, 1.0, webByte(h2, 2)));
            }
        }
    }
    return cover;
}

// Matted webbing: fibres stretched along the layer's own direction, clumped.
// Under ROCK_REGION the fibres run along the face's own axes, a turned lattice
// not repeating with the region.
float webFilm(vec2 p, ivec2 planePeriod, int layer) {
#ifdef ROCK_REGION
    bool across = rockRand(ivec4(layer, 7, 7, 120)) < 0.5;
    vec2 q = across ? p.yx : p;
    vec2 extent = vec2(across ? planePeriod.yx : planePeriod);
    // cells per block along each axis, fitted to the extent
    vec2 fibreCells = max(floor(extent * vec2(1.5, 24.0) + 0.5), 1.0);
    vec2 fineCells = max(floor(extent * vec2(4.0, 40.0) + 0.5), 1.0);
    vec2 clumpCells = max(floor(extent * 1.3 + 0.5), 1.0);
    float fibre = rockNoiseP(vec3(q * fibreCells / extent, float(layer) * 9.1), ivec3(ivec2(fibreCells), 0), 121);
    float fine = rockNoiseP(vec3(q * fineCells / extent, float(layer) * 4.7), ivec3(ivec2(fineCells), 0), 123);
    float clump = rockNoiseP(vec3(q * clumpCells / extent, float(layer) * 3.3), ivec3(ivec2(clumpCells), 0), 122);
#else
    float a = rockRand(ivec4(layer, 7, 7, 120)) * 3.14159;
    vec2 q = mat2(cos(a), -sin(a), sin(a), cos(a)) * p;
    float fibre = rockNoise(vec3(q.x * 1.5, q.y * 24.0, float(layer) * 9.1), 121);
    float fine = rockNoise(vec3(q.x * 4.0, q.y * 40.0, float(layer) * 4.7), 123);
    float clump = rockNoise(vec3(q * 1.3, float(layer) * 3.3), 122);
#endif
    return clamp(smoothstep(0.3, 0.8, fibre * 0.7 + fine * 0.3) * 0.7 + smoothstep(0.4, 0.8, clump) * 0.5, 0.0, 1.0);
}

// Where sludge lies, 0 to 1: spread wide and thin like spit, its outline
// ragged and splattered, stretched downwards on the sides as if running.
float webSludge(vec3 texelPos) {
    vec3 blocks = vec3(1.0, 1.0 / 0.6, 1.0) * WEB_SLUDGE_SIZE;
    vec3 warp = vec3(rockField(texelPos, 1.0 / 1.3, vec3(0.0), 143), rockField(texelPos, 1.0 / 1.3, vec3(0.0), 144),
                     rockField(texelPos, 1.0 / 1.3, vec3(0.0), 145)) - 0.5;
    float wet = rockFieldSkew(texelPos + warp * 0.8 * blocks, blocks, vec3(3.0), 140) * 0.65
              + rockFieldSkew(texelPos + warp * 1.6 * blocks / 3.0, blocks / 3.0, vec3(0.0), 141) * 0.35;
    return smoothstep(WEB_SLUDGE_COVER - 0.06, WEB_SLUDGE_COVER + 0.14, wet);
}

vec4 webColor(vec3 normal) {
    vec4 color = rockColor(normal);
    color.rgb *= 0.94;                     // the stone, in the webbing's shade

    vec3 an = abs(normal);
    int axis = (an.y >= an.x && an.y >= an.z) ? 1 : (an.x >= an.z ? 0 : 2);
    float side = axis == 0 ? sign(normal.x) : axis == 1 ? sign(normal.y) : sign(normal.z);
    vec2 plane = axis == 1 ? worldPos.xz : axis == 0 ? vec2(-side * worldPos.z, -worldPos.y)
                                                     : vec2(side * worldPos.x, -worldPos.y);
    ivec2 planePeriod = rockPlanePeriod(axis);
    ivec3 cell = ivec3(floor(worldPos - normal * 0.01));
    int faceId = axis * 2 + int(side > 0.0);
    bool upright = axis != 1;
    // texel centres, so everything keeps the textures' pixel grid
    vec2 p = (floor(plane * 16.0) + 0.5) / 16.0;
    vec3 texelPos = (floor(worldPos * 16.0 - normal * 0.5) + 0.5) / 16.0;

    // how thick the webbing is: in irregular patches, and piled into
    // corners - concave ones, which the client darkens with its ambient
    // occlusion: the vertex colour over the face's own directional shade
    float shade = axis == 1 ? (side > 0.0 ? 1.0 : 0.5) : axis == 2 ? 0.8 : 0.6;
    float occlusion = clamp(vertexColor.g / shade, 0.0, 1.0);
    float corner = smoothstep(0.95, 0.55, occlusion);
    float field = rockFieldSkew(texelPos, WEB_PATCH, vec3(0.0), 130) * 0.6
                + rockFieldSkew(texelPos, WEB_PATCH / 2.7, vec3(4.0), 131) * 0.3
                + rockFieldSkew(texelPos, WEB_PATCH / 7.0, vec3(9.0), 132) * 0.1;
    // away from corners it stays below full, so the corners still stand out
    float density = clamp(smoothstep(WEB_COVER - 0.2, WEB_COVER + 0.2, field) * WEB_OPEN_DENSITY
                          + corner * WEB_CORNER, 0.0, 1.0);

    // its colour: fresh or old in patches, brighter and dimmer, and in places
    // a poisonous tint
    float age = smoothstep(0.3, 0.75, rockFieldSkew(texelPos, 2.3, vec3(11.0), 133));
    vec3 web = mix(webHeader(7), webHeader(8), age) * mix(0.8, 1.08, rockFieldSkew(texelPos, 1.0 / 1.5, vec3(0.0), 134));
    float toxicField = rockFieldSkew(texelPos, WEB_TOXIC_SIZE, vec3(37.0), 135) * 0.75
                     + rockFieldSkew(texelPos, WEB_TOXIC_SIZE / 2.9, vec3(37.0 * 2.9), 136) * 0.25;
    float toxic = smoothstep(WEB_TOXIC - 0.15, WEB_TOXIC + 0.2, toxicField) * WEB_TOXIC_STRENGTH;
    web = mix(web, webHeader(9), toxic);

    // matted layers, each its own brightness
    for (int l = 0; l < WEB_FILM_LAYERS; l++) {
        float film = webFilm(p, planePeriod, l + faceId * 8);
        float layerDensity = smoothstep(float(l) * 0.25, float(l) * 0.25 + 0.4, density);
        float bright = mix(0.82, 1.08, rockRand(ivec4(l, faceId, 3, 124)));
        color.rgb = mix(color.rgb, web * bright, film * layerDensity * WEB_FILM_OPACITY);
    }

    // corners: webbing spun across them, thick and bright
    float cornerSheet = corner * WEB_CORNER * (0.55 + 0.45 * webFilm(p, planePeriod, 7 + faceId * 8));
    color.rgb = mix(color.rgb, web * 1.06, clamp(cornerSheet, 0.0, 0.92));

    // sludge, spit and other liquids: a thin, see-through film, pooled
    // unevenly into strings, with droplets splattered round its edges and a
    // bubble or glint here and there
    float spread = webSludge(texelPos);
    ivec4 texelKey = ivec4(ivec3(floor(texelPos * 16.0)), 142);
    float strings = 1.0 - abs(2.0 * rockFieldSkew(texelPos, 1.0 / 2.2, vec3(8.0), 146) - 1.0);
    float thickness = mix(0.3, 1.0, smoothstep(0.5, 0.92, strings));
    float edge = smoothstep(0.0, 0.25, spread) * (1.0 - smoothstep(0.35, 0.7, spread));
    float speck = step(0.9, rockRand(texelKey)) * edge;
    vec3 sludgeColor = mix(webHeader(10), webHeader(9) * 0.9, toxic) * mix(0.92, 1.08, strings);
    float sludge = max(spread * thickness, speck) * WEB_SLUDGE_OPACITY;
    float glint = step(0.95, rockRand(texelKey + ivec4(0, 0, 0, 1))) * smoothstep(0.5, 0.9, spread);
    color.rgb = mix(color.rgb, sludgeColor, sludge) + glint * 0.12;

    // on the sides: drips, and threads hanging down, some ending in a clump
    if (upright) {
        int column = int(floor(plane.x * 16.0));
        ivec4 columnKey = ivec4(column, cell[axis], faceId, 150);
        float bandHeight = mix(1.0, 2.5, rockRand(columnKey));
        float y = plane.y / bandHeight + rockRand(columnKey + ivec4(0, 0, 0, 1));
        uint h = rockHash(ivec4(column, int(floor(y)), cell[axis] * 8 + faceId, 152));
        if (webByte(h, 0) < WEB_DRIP_CHANCE * mix(0.3, 2.0, density)) {
            float texels = (fract(y) - webByte(h, 1) * 0.5) * bandHeight * 16.0;   // down from its top
            float runLength = mix(0.15, 0.6, webByte(h, 2)) * bandHeight * 16.0;
            int kind = int((h >> 24) & 3u);
            if (texels > 0.0 && texels < runLength + 2.0) {
                bool end = texels >= runLength;
                if (kind < 2) {
                    // a drip runs only from sludge above it: a faint wet trail,
                    // thinning down its run, a drop with a glint at its end
                    float source = webSludge(texelPos + vec3(0.0, texels / 16.0, 0.0));
                    float trail = end ? 0.6 : mix(0.5, 0.15, texels / runLength);
                    color.rgb = mix(color.rgb, sludgeColor * 0.9, trail * source * WEB_SLUDGE_OPACITY);
                    if (end && texels < runLength + 1.0) color.rgb += 0.1 * source;
                } else if (!end || kind == 3) {
                    // a hanging thread; some end in a clump
                    color.rgb = mix(color.rgb, end ? web * 1.12 : web, end ? 0.95 : 0.75);
                }
            }
        }
    }

    // egg sacs and clumps, round, near the webbing's own colour and wrapped
    // in it: soft-edged, only gently shaded, threads drawn over them. More
    // under ceilings.
    {
        ivec2 period;
        vec2 size = rockPlaneCells(1.1, planePeriod, period);
        ivec2 c = ivec2(floor(p / size));
        uint h = rockHash(ivec4(rockWrap(c, period), cell[axis] * 8 + faceId, 170));
        float chance = WEB_SAC_CHANCE * (axis == 1 && side < 0.0 ? 3.0 : 1.0) * mix(0.3, 1.5, density);
        if (webByte(h, 0) < chance) {
            vec2 centre = (vec2(c) + 0.35 + 0.3 * vec2(webByte(h, 1), webByte(h, 2))) * size;
            float radius = mix(1.3, 2.6, webByte(h, 3)) / 16.0;
            vec2 d = (p - centre) / radius;
            if (upright) d.y *= 0.8;                       // sagging a little
            float r = length(d);
            float lit = mix(1.06, 0.9, clamp(length(d + vec2(0.35, 0.35)), 0.0, 1.0));
            vec3 sac = mix(web, webHeader(11), 0.5) * lit;
            color.rgb = mix(color.rgb, sac, (1.0 - smoothstep(0.55, 1.05, r)) * WEB_SAC_OPACITY);
        }
    }

    // loose threads over it all, more of them where the webbing is thick
    for (int l = 0; l < WEB_THREAD_LAYERS; l++) {
        float cellSize = mix(0.4, 1.2, rockRand(ivec4(l, faceId, 5, 125)));
        float threads = webThreads(p + float(l) * 3.7, cellSize, planePeriod, upright, 160 + l * 2 + faceId * 16);
        color.rgb = mix(color.rgb, web * 1.1, threads * mix(0.3, 1.0, density));
    }

    // now and then an orb web: spokes, and rings strung between them, some
    // broken
    {
        ivec2 period;
        vec2 size = rockPlaneCells(WEB_ORB_CELL, planePeriod, period);
        ivec2 c = ivec2(floor(p / size));
        ivec2 id = rockWrap(c, period);
        uint h = rockHash(ivec4(id, cell[axis] * 8 + faceId, 180));
        if (webByte(h, 0) < WEB_ORB_CHANCE) {
            uint h2 = rockHash(ivec4(id, cell[axis] * 8 + faceId, 181));
            vec2 centre = (vec2(c) + 0.4 + 0.2 * vec2(webByte(h, 1), webByte(h, 2))) * size;
            float radius = mix(0.18, 0.3, webByte(h, 3)) * WEB_ORB_CELL;
            vec2 d = p - centre;
            float r = length(d);
            if (r < radius * 1.15) {
                float spokes = float(9 + int(h2 % 6u));
                float sector = 6.28318 / spokes;
                float a = atan(d.y, d.x) + 3.14159 + webByte(h2, 1) * sector;
                float within = mod(a, sector);
                int spoke = int(floor(a / sector));
                float spokeDistance = r * sin(min(within, sector - within)) * 16.0;
                // a ring is a polygon: chords from spoke to spoke
                float gap = mix(1.6, 2.6, webByte(h2, 2)) / 16.0;
                float chord = r * cos(within - sector * 0.5) / cos(sector * 0.5);
                int ring = int(floor(chord / gap + 0.5));
                float ringDistance = abs(chord - float(ring) * gap) * cos(sector * 0.5) * 16.0;
                bool broken = rockRand(ivec4(id, spoke * 31 + ring, 182)) < 0.2;
                float rings = (ring >= 2 && chord < radius && !broken) ? webLine(ringDistance) : 0.0;
                float lines = max(webLine(spokeDistance) * (1.0 - smoothstep(radius, radius * 1.15, r)), rings);
                color.rgb = mix(color.rgb, web * 1.18, lines * 0.85);
            }
        }
    }
#if WEB_SHOW_CORNERS
    color.rgb = mix(color.rgb, vec3(1.0, 0.0, 0.0), corner * 0.8);
#endif
    return vec4(color.rgb, 1.0);
}
"""

FSH_MAIN = """
    // rock prototype: textured from the world position
    if (material == 1) {
        color = rockColor(normalize(cross(dFdx(Pos), dFdy(Pos)))) * vertexColor * lightColor;
    } else if (material == 2) {
        color = webColor(normalize(cross(dFdx(Pos), dFdy(Pos)))) * vertexColor * lightColor;
    }
"""


def patch(text, anchor, insert, before=False):
    m = re.search(anchor, text)
    assert m, anchor
    nl = "\r\n" if "\r\n" in text else "\n"
    insert = insert.replace("\n", nl)
    i = m.start() if before else m.end()
    return text[:i] + insert + text[i:]


def main():
    parser = argparse.ArgumentParser(description="Builds the rock prototype overlay pack.")
    parser.add_argument("--base", type=Path, default=REPO / "vanilla",
                        help="the pack whose terrain, objmc and Sodium shaders it builds on")
    parser.add_argument("out", type=Path, nargs="?", default=RESOURCEPACKS / "RP-rock-prototype")
    args = parser.parse_args()
    assert TUNE["ROCK_EDGE_WIDTH"] <= EDGE_STRIP - 1, "edge wear must fade out inside its strip"
    assert 64 % CRACK_BLOCKS == 0, "crack cells must fit Sodium's region"
    build(args.base, args.out)


def build(BASE, OUT):
    if OUT.exists():
        # only ever replace a pack this script wrote
        assert (OUT / "assets/rockproto").is_dir(), f"{OUT} exists and isn't a rock prototype pack"
        shutil.rmtree(OUT)
    shaders = BASE / "assets/minecraft/shaders"
    core = OUT / "assets/minecraft/shaders/core"
    core.mkdir(parents=True)
    for name in ("terrain.vsh", "terrain.fsh"):
        shutil.copy(shaders / "core" / name, core / name)
    # and the objmc files they import, so a pack below without them (or with
    # others) can't fail every shader reload
    include = OUT / "assets/minecraft/shaders/include"
    include.mkdir(parents=True)
    for source in (shaders / "include").glob("objmc_*.glsl"):
        shutil.copy(source, include / source.name)
    # and the Sodium shaders, if the base has them
    sodium = BASE / "assets/sodium/shaders"
    if sodium.is_dir():
        shutil.copytree(sodium, OUT / "assets/sodium/shaders")

    # the materials, as includes
    config = "// The rock prototype's settings (make_rock_prototype.py's TUNE).\n"
    config += f"#define ROCK_DESCRIPTOR_X {DESCRIPTOR[0]}\n"
    config += "".join(f"#define {k} {float(v) if isinstance(v, float) else v}\n" for k, v in TUNE.items())
    (include / "rockproto_config.glsl").write_text(config)
    (include / "rockproto_main.glsl").write_text(RP_MAIN)
    (include / "rockproto.glsl").write_text(RP_FUNCS)

    # hooked into vanilla's terrain shaders...
    vsh = core / "terrain.vsh"
    t = vsh.read_bytes().decode()
    t = patch(t, r"flat out int maxLod;", VSH_OUTS)
    t = patch(t, r"#moj_import <objmc_tools\.glsl>", "\n#moj_import <rockproto_config.glsl>")
    t = patch(t, r"#moj_import <objmc_main\.glsl>", """
    #define ROCK_WORLD (Position + vec3(ChunkPosition))
    #define ROCK_SECTION_CENTRE (vec3(ChunkPosition - CameraBlockPos) + 8.0)
    #moj_import <rockproto_main.glsl>""")
    vsh.write_bytes(t.encode())

    fsh = core / "terrain.fsh"
    t = fsh.read_bytes().decode()
    t = patch(t, r"flat in int maxLod;", FSH_INS)
    t = patch(t, r"void main\(\) \{", """#moj_import <rockproto_config.glsl>
#define ROCK_ATLAS_SIZE vec2(TextureSize)
#moj_import <rockproto.glsl>

""", before=True)
    # right after objmc's lighting
    t = patch(t, r"#moj_import ?<objmc_light\.glsl>", FSH_MAIN)
    fsh.write_bytes(t.encode())

    # ...and Sodium's, where positions are only known within their region
    if sodium.is_dir():
        blocks = OUT / "assets/sodium/shaders/blocks"
        vsh = blocks / "block_layer_opaque.vsh"
        t = vsh.read_bytes().decode()
        t = patch(t, r"flat out int maxLod;", VSH_OUTS)
        t = patch(t, r"#moj_import <minecraft:objmc_tools\.glsl>", "\n#moj_import <minecraft:rockproto_config.glsl>")
        t = patch(t, r"#moj_import <minecraft:objmc_main\.glsl>", """
#define ROCK_WORLD (_vert_position + _get_draw_translation(_draw_id))
#define ROCK_SECTION_CENTRE (translation + 8.0)
#moj_import <minecraft:rockproto_main.glsl>""")
        vsh.write_bytes(t.encode())

        fsh = blocks / "block_layer_opaque.fsh"
        t = fsh.read_bytes().decode()
        t = patch(t, r"flat in int maxLod;", FSH_INS)
        t = patch(t, r"#moj_import <minecraft:objmc_fragment\.glsl>", """
#moj_import <minecraft:rockproto_config.glsl>
#define ROCK_ATLAS_SIZE (1.0 / u_TexelSize)
#define ROCK_REGION vec3(128.0, 64.0, 128.0)
#moj_import <minecraft:rockproto.glsl>""")
        t = patch(t, r"#moj_import <minecraft:objmc_light\.glsl>", FSH_MAIN)
        fsh.write_bytes(t.encode())

    tex = OUT / "assets/rockproto/textures/block"
    tex.mkdir(parents=True)
    sheet((13, 57, 91, 255)).save(tex / "rock.png")
    sheet((13, 57, 92, 255), (WEB_FRESH, WEB_OLD, WEB_TOXIC, WEB_SLUDGE, WEB_SAC)).save(tex / "web.png")
    models = OUT / "assets/rockproto/models/block"
    models.mkdir(parents=True)
    (models / "rock.json").write_text(json.dumps(model("rockproto:block/rock"), indent=2))
    (models / "web.json").write_text(json.dumps(model("rockproto:block/web", strips=False), indent=2))
    states = OUT / "assets/minecraft/blockstates"
    states.mkdir(parents=True)
    for block, name in (("honeycomb_block", "rock"), (WEB_BLOCK, "web")):
        (states / f"{block}.json").write_text(
            json.dumps({"variants": {"": {"model": f"rockproto:block/{name}"}}}, indent=2))
    (OUT / "pack.mcmeta").write_text(json.dumps({"pack": {
        "pack_format": 88, "min_format": 88, "max_format": 88,
        "description": f"rock prototype - load above {BASE.name}"}}, indent=4))
    print("written", OUT)


if __name__ == "__main__":
    main()
