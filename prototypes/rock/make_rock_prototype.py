"""Builds RP-rock-prototype: world-position rock variation on one blockstate.

A prototype, not part of the pack. honeycomb_block becomes a stone cube whose
faces all point (UV inside one opaque texel) at a descriptor in a generated
material sheet. The terrain shader recognises the descriptor - an opaque
marker and signature at its sheet's top-left - and textures the face from the
world position instead, all from hashes and noise of the position: a stone
variant, rotation and mirror per block, discoloured and mossy patches, strata
lines, weathering streaks down the sides, and clustered cracks.

Exposed edges get faint, lighter wear too. The shader can't see neighbouring
blocks, but the model can: thin strips along each face's edges are culled by
the block beyond that edge, so one shows only where both sides of its edge
are open (see EDGE_STRIP).

The shaders are vanilla's terrain shaders from this repository's vanilla pack
with the material added; Sodium's aren't patched. Tunables are in TUNE.

    python make_rock_prototype.py [output folder]

writes the pack to .minecraft/resourcepacks/RP-rock-prototype by default.
Load it above the vanilla pack.
"""

import json
import random
import re
import shutil
import sys
from pathlib import Path

from PIL import Image

REPO = Path(__file__).resolve().parents[2]
VANILLA = REPO / "vanilla"                  # the terrain shaders this builds on
STONE = REPO / "assets/minecraft/textures/block"
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "AppData/Roaming/.minecraft/resourcepacks/RP-rock-prototype"

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
CRACK_BLOCKS = 4
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

# shader tunables (written into it as #defines)
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
                                     # the dip has to stay above drift, waves and ripple together
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


def sheet():
    img = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 255))
    px = img.load()
    header = [
        (98, 76, 54, 255),                            # marker
        (13, 57, 91, 255),                            # signature
        (7, CRACKS, round(CRACK_CHANCE * 255), 255),  # variants, cracks, crack chance
        (round(DISCOLOUR * 255), NOISE_BLOCKS, 0, 255),
        TINT_A + (255,),
        TINT_B + (255,),
        (CRACK_BLOCKS, CRACKS_PER_ROW, CRACK_ROW // 16, 255),
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


def model():
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
            if axis[edge] == axis[face]:
                continue
            lo, hi = [0.0, 0.0, 0.0], [16.0, 16.0, 16.0]
            lo[axis[face]] = hi[axis[face]] = 16.0 if face in high else 0.0
            if edge in high:
                lo[axis[edge]] = 16 - EDGE_STRIP
            else:
                hi[axis[edge]] = EDGE_STRIP
            elements.append({"from": lo, "to": hi, "faces": {
                face: {"uv": uv(dx + 1 + 6 * f + k), "texture": "#0", "cullface": edge}}})
    return {"textures": {"0": "rockproto:block/rock", "particle": "minecraft:block/stone"},
            "elements": elements}


VSH_OUTS = """
// rock prototype
flat out int material;
flat out ivec2 matOrigin;
flat out ivec4 matInfo;
flat out ivec4 matTune;
flat out ivec4 matTintA;
flat out ivec4 matTintB;
flat out ivec4 matCrack;
flat out int matEdge;
out vec3 worldPos;"""

VSH_MAIN = """

    // rock prototype: a face whose UV sits on an opaque texel leading to the
    // material marker and signature is textured by world position.
    material = 0;
    matEdge = -1;
    int stripFace = 0;
    worldPos = Position + vec3(ChunkPosition);
    if (isCustom == 0) {
        vec2 matFrac = fract(UV0 * vec2(atlasSize));
        if (all(greaterThan(matFrac, vec2(0.1))) && all(lessThan(matFrac, vec2(0.9)))) {
            ivec2 at = ivec2(UV0 * vec2(atlasSize));
            ivec4 p = ivec4(texelFetch(Sampler0, at, 0) * 255.0 + 0.5);
            ivec2 tl = at - ivec2(p.r * 16 + (p.g >> 4), (p.g & 15) * 256 + p.b);
            if (p.a == 255 && all(greaterThanEqual(tl, ivec2(0)))) {
                ivec4 m0 = ivec4(texelFetch(Sampler0, tl, 0) * 255.0 + 0.5);
                ivec4 m1 = ivec4(texelFetch(Sampler0, tl + ivec2(1, 0), 0) * 255.0 + 0.5);
                if (m0 == ivec4(98, 76, 54, 255) && m1 == ivec4(13, 57, 91, 255)) {
                    material = 1;
                    matOrigin = tl;
                    // an exposed-edge strip's descriptor sits right of the
                    // main one, at 1 + 6 * its face + its edge, each a
                    // direction: north, south, east, west, up, down
                    int strip = at.x - tl.x - (ROCK_DESCRIPTOR_X + 1);
                    if (strip >= 0) {
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
        vec3 sectionCentre = vec3(ChunkPosition - CameraBlockPos) + 8.0;
        if (length(sectionCentre) > ROCK_EDGE_DISTANCE) {
            Pos = vec3(0.0);
        } else {
            float level = matEdge >= 4 ? 3.0 : matEdge <= 1 ? 2.0 : 1.0;
            float d = length(Pos);
            Pos += stripNormals[min(stripFace, 5)] * level * (5.0e-4 + 2.5e-6 * d * d);
        }
    }"""

FSH_INS = """
flat in int material;
flat in ivec2 matOrigin;
flat in ivec4 matInfo;
flat in ivec4 matTune;
flat in ivec4 matTintA;
flat in ivec4 matTintB;
flat in ivec4 matCrack;
flat in int matEdge;
in vec3 worldPos;"""

FSH_FUNCS = """
// ---- rock prototype ------------------------------------------------------

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

// Value noise on the integer lattice, smoothly interpolated.
float rockNoise(vec3 p, int salt) {
    ivec3 i = ivec3(floor(p));
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = 0.0;
    for (int k = 0; k < 8; k++) {
        ivec3 o = ivec3(k & 1, (k >> 1) & 1, (k >> 2) & 1);
        vec3 w = mix(1.0 - f, f, vec3(o));
        n += w.x * w.y * w.z * rockRand(ivec4(i + o, salt));
    }
    return n;
}

// Value noise on a lattice turned against the block grid, so its peaks line up
// with no row, column or block edge.
float rockNoiseSkew(vec3 p, int salt) {
    const mat3 turn = mat3( 0.00,  0.80,  0.60,
                           -0.80,  0.36, -0.48,
                           -0.60, -0.48,  0.64);
    return rockNoise(turn * p, salt);
}

// (u, v) on the face turned by quarter turns and mirrored, within [0, 1).
vec2 rockTurn(vec2 uv, int turns, bool mirror) {
    if (mirror) uv.x = 1.0 - uv.x;
    for (int i = 0; i < turns; i++) uv = vec2(1.0 - uv.y, uv.x);
    return uv;
}

vec4 rockSample(vec2 texel, vec2 dTexelX, vec2 dTexelY, vec2 lo, vec2 hi) {
    vec2 atlas = vec2(TextureSize);
    vec2 pixelSize = 1.0 / atlas;
    vec2 du = dTexelX * pixelSize;
    vec2 dv = dTexelY * pixelSize;
    // stay a filter footprint inside the tile, as objmc's sampleCustom does
    float footprint = min(max(length(dTexelX), length(dTexelY)), 16.0);
    vec2 margin = vec2(0.5 + footprint);
    texel = clamp(texel, lo + margin, hi - margin);
    return sampleNearest(Sampler0, texel * pixelSize, pixelSize, du, dv, sqrt(du * du + dv * dv));
}

// The strata height at a point: its height, tilted by one steady dip and
// curved by waves. Strata lines lie at fixed values of it. The dip is steeper
// than the waves ever get, so the layers have no highs or lows: lines on a top
// face always run one way, never closing on themselves, and lines on a side
// always climb or fall one way.
float rockStrataY(vec3 p) {
    vec3 ground = vec3(p.x, 0.0, p.z);
    float angle = radians(ROCK_STRATA_DIP_ANGLE);
    float dip = dot(p.xz, vec2(cos(angle), sin(angle))) * ROCK_STRATA_DIP;
    float wave = (rockNoise(ground / ROCK_STRATA_WAVE_BLOCKS, 31) - 0.5)
               + (rockNoise(ground / (ROCK_STRATA_WAVE_BLOCKS / 3.0) + 13.0, 36) - 0.5) * 0.25;
    // a very large, gentle tilt on top, turning the dip's direction and
    // steepness slowly across the land
    float drift = (rockNoise(ground / 400.0 + 71.0, 37) - 0.5) * ROCK_STRATA_DRIFT;
    return p.y + dip + drift + wave * ROCK_STRATA_WAVE;
}

// A strata line's own wobble along the strike, about -0.5 to 0.5.
float rockStrataWobble(float s, int line) {
    return rockNoise(vec3(s, float(line) * 5.3, 9.0), 79) - 0.5
         + (rockNoise(vec3(s * 2.7, float(line) * 5.3, 19.0), 80) - 0.5) * 0.4;
}

// Whether strata line `line` is present at ground point g (in its own piece
// lengths): the ground is cut into pieces, each holding the line or not, with
// `chance`. A present piece holds it at full strength; only where a run of
// them ends does it fade out, over `soft` of a piece. Absent pieces in a row
// leave long gaps, and the line may not come back at all within view.
float rockStrataPresence(vec2 g, int line, int salt, float chance, float soft) {
    vec2 c = floor(g);
    vec2 f = smoothstep(0.5 - soft, 0.5 + soft, fract(g));
    ivec2 i = ivec2(c);
    float v00 = step(rockRand(ivec4(i, line, salt)), chance);
    float v10 = step(rockRand(ivec4(i + ivec2(1, 0), line, salt)), chance);
    float v01 = step(rockRand(ivec4(i + ivec2(0, 1), line, salt)), chance);
    float v11 = step(rockRand(ivec4(i + ivec2(1, 1), line, salt)), chance);
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
    vec3 warp = vec3(rockNoise(texelPos / 5.0, 21), rockNoise(texelPos / 5.0, 22), rockNoise(texelPos / 5.0, 23)) - 0.5;
    vec3 q = (texelPos + warp * ROCK_WARP) / ROCK_PATCH_BLOCKS;
    // hard edges in some places, soft in others; strong patches in some, faint in others
    float edge = mix(0.03, 0.18, rockNoise(texelPos / 6.0, 16));
    float contrast = mix(0.35, 1.0, rockNoise(texelPos / 8.0, 17));
    float fieldA = rockNoise(q * 0.5, 11) * 0.5 + rockNoise(q, 12) * 0.35 + rockNoise(q * 4.0, 15) * 0.15;
    // the mossy tint: larger, softer, gentler washes
    vec3 qMoss = q / ROCK_MOSS_SCALE;
    float fieldB = rockNoise(qMoss * 0.5 + 31.7, 13) * 0.5 + rockNoise(qMoss + 9.1, 14) * 0.35 + rockNoise(qMoss * 4.0 + 5.3, 18) * 0.15;
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
        int layer = int(floor(sy / ROCK_STRATA_SPACING));
        // a line wobbles up to about 0.7 * ROCK_STRATA_WOBBLE out of its own layer
        for (int i = -2; i <= 2; i++) {
            ivec4 key = ivec4(layer + i, 0, 0, 71);
            if (rockRand(key) > ROCK_STRATA_SHOW) continue;
            float lineY = (float(layer + i) + rockRand(key + ivec4(0, 1, 0, 0))) * ROCK_STRATA_SPACING;
            // its own wobble, so no two lines run parallel. It moves the line
            // only along the strike, across the dip, so it can't cancel the
            // dip and the line still never folds back on itself.
            float strikeAngle = radians(ROCK_STRATA_DIP_ANGLE);
            vec2 strikeDir = vec2(-sin(strikeAngle), cos(strikeAngle));
            float wobbleLength = mix(6.0, 16.0, rockRand(key + ivec4(0, 16, 0, 0)));
            float wobbleSize = ROCK_STRATA_WOBBLE * mix(0.5, 1.0, rockRand(key + ivec4(0, 17, 0, 0)));
            float s0 = dot(texelPos.xz, strikeDir);
            float sU = dot((texelPos + faceU / 16.0).xz, strikeDir);
            float sV = dot((texelPos + faceV / 16.0).xz, strikeDir);
            float w0 = rockStrataWobble(s0 / wobbleLength, layer + i) * wobbleSize;
            vec2 lineGradient = gradient - vec2(rockStrataWobble(sU / wobbleLength, layer + i) * wobbleSize - w0,
                                                rockStrataWobble(sV / wobbleLength, layer + i) * wobbleSize - w0) * 16.0;
            float lineSteep = max(length(lineGradient), ROCK_STRATA_MIN_SLOPE);
            float across = (sy - w0 - lineY) / lineSteep * 16.0;           // in texels
            float distance = abs(across);
            // its own width - mostly thin, sometimes a broad band - swelling and
            // narrowing along it, and its own edge, crisp or soft
            float wide = rockRand(key + ivec4(0, 2, 0, 0));
            float along = rockNoise(vec3((texelPos.x - texelPos.z) / 8.0, float(layer + i) * 3.1, 5.0), 73);
            float width = mix(ROCK_STRATA_WIDTH_MIN, ROCK_STRATA_WIDTH_MAX, wide) * mix(0.3, 1.8, along);
            float soft = mix(0.4, 0.9, rockRand(key + ivec4(0, 5, 0, 0)));
            // where it shows is its own: pieces of its own length along it,
            // each there or not, so it breaks off at its own intervals and
            // sometimes never comes back; its ends crisp or long fades, faded
            // or thinned out. Pieces are taken on the ground, turned to the
            // layers' strike and bent a little, so a line breaks on any face.
            int id = layer + i;
            float pieceLength = mix(ROCK_STRATA_RUN_MIN, ROCK_STRATA_RUN_MAX, rockRand(key + ivec4(0, 9, 0, 0)));
            float endSoft = mix(0.05, 0.4, rockRand(key + ivec4(0, 10, 0, 0)));
            vec2 bend = vec2(rockNoise(texelPos / 7.0, 74), rockNoise(texelPos / 7.0 + 17.0, 75)) - 0.5;
            vec2 ground = texelPos.xz + bend * 4.0;
            vec2 strike = vec2(dot(ground, vec2(-sin(strikeAngle), cos(strikeAngle))),
                               dot(ground, vec2(cos(strikeAngle), sin(strikeAngle))));
            vec2 offset = vec2(rockRand(key + ivec4(0, 12, 0, 0)), rockRand(key + ivec4(0, 13, 0, 0))) * 97.0;
            float stretch = rockStrataPresence(strike / pieceLength + offset, id, 76, ROCK_STRATA_PRESENT, endSoft)
                          // over far longer stretches it is there or gone altogether
                          * rockStrataPresence(strike / (pieceLength * 3.0) + offset, id, 77, ROCK_STRATA_LASTS, 0.3);
            // some lines also break for a moment now and then within their runs
            if (rockRand(key + ivec4(0, 14, 0, 0)) < ROCK_STRATA_BREAKS) {
                float gapLength = mix(1.0, 3.0, rockRand(key + ivec4(0, 15, 0, 0)));
                stretch *= rockStrataPresence(strike / gapLength + offset, id, 78, 0.8, 0.2);
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
                float side = rockRand(key + ivec4(0, 8, 0, 0)) > 0.5 ? 1.0 : -1.0;
                float pairDistance = abs(across - side * gap);
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
        vec3 clusterPos = vec3(texelPos.x, texelPos.y * 0.6, texelPos.z) / ROCK_STREAK_CLUSTER;
        float clustering = rockNoiseSkew(clusterPos, 54) * 0.65 + rockNoiseSkew(clusterPos * 2.3 + 7.0, 56) * 0.35;
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
    float cracked = mix(0.1, 2.0, smoothstep(0.3, 0.75, rockNoise(worldPos / ROCK_CRACK_CLUSTER, 61)));
    for (int layer = 0; layer < ROCK_CRACK_LAYERS; layer++) {
        vec2 cellPlane = plane / float(cellBlocks) + vec2(0.37, 0.61) * float(layer);
        uint hc = rockHash(ivec4(ivec2(floor(cellPlane)), axis * 7 + cell[axis], 99 + layer));
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
        vec3 ep = texelPos / ROCK_EDGE_SPLOTCH;
        float splotch = rockNoiseSkew(ep, 81) * 0.7 + rockNoiseSkew(ep * 3.1 + 5.0, 82) * 0.3;
        float amount = smoothstep(ROCK_EDGE_COVER, ROCK_EDGE_COVER + 0.12, splotch);
        float reach = mix(0.6, ROCK_EDGE_WIDTH, rockNoiseSkew(texelPos * 1.7 + 3.0, 83));
        float ragged = rockRand(ivec4(ivec3(floor(texelPos * 16.0)), 84));
        float wear = amount * (1.0 - smoothstep(reach * 0.3, reach, edgeDistance + ragged));
        float grey = dot(color.rgb, vec3(0.299, 0.587, 0.114));
        color.rgb = mix(color.rgb, vec3(grey), wear * 0.3) * (1.0 + wear * ROCK_EDGE_STRENGTH);
    }
    return vec4(color.rgb, 1.0);
}
"""

FSH_MAIN = """
    // rock prototype: textured from the world position
    if (material == 1) {
        color = rockColor(normalize(cross(dFdx(Pos), dFdy(Pos)))) * vertexColor * lightColor;
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
    assert TUNE["ROCK_EDGE_WIDTH"] <= EDGE_STRIP - 1, "edge wear must fade out inside its strip"
    if OUT.exists():
        # only ever replace a pack this script wrote
        assert (OUT / "assets/rockproto").is_dir(), f"{OUT} exists and isn't a rock prototype pack"
        shutil.rmtree(OUT)
    core = OUT / "assets/minecraft/shaders/core"
    core.mkdir(parents=True)
    for name in ("terrain.vsh", "terrain.fsh"):
        shutil.copy(VANILLA / "assets/minecraft/shaders/core" / name, core / name)

    vsh = core / "terrain.vsh"
    t = vsh.read_bytes().decode()
    t = patch(t, r"flat out vec4 texRect;", VSH_OUTS)
    t = patch(t, r"#moj_import <objmc_main\.glsl>", VSH_MAIN.replace("ROCK_DESCRIPTOR_X", str(DESCRIPTOR[0]))
                                                            .replace("ROCK_EDGE_DISTANCE", str(float(TUNE["ROCK_EDGE_DISTANCE"]))))
    vsh.write_bytes(t.encode())

    fsh = core / "terrain.fsh"
    t = fsh.read_bytes().decode()
    t = patch(t, r"flat in vec4 texRect;", FSH_INS)
    defines = "".join(f"\n#define {k} {float(v) if isinstance(v, float) else v}" for k, v in TUNE.items())
    t = patch(t, r"#moj_import <objmc_fragment\.glsl>", defines + "\n" + FSH_FUNCS)
    # after objmc's lighting, before the chunk fade-in
    t = patch(t, r"    // A chunk that has just loaded fades in", FSH_MAIN, before=True)
    fsh.write_bytes(t.encode())

    tex = OUT / "assets/rockproto/textures/block"
    tex.mkdir(parents=True)
    sheet().save(tex / "rock.png")
    models = OUT / "assets/rockproto/models/block"
    models.mkdir(parents=True)
    (models / "rock.json").write_text(json.dumps(model(), indent=2))
    states = OUT / "assets/minecraft/blockstates"
    states.mkdir(parents=True)
    (states / "honeycomb_block.json").write_text(
        json.dumps({"variants": {"": {"model": "rockproto:block/rock"}}}, indent=2))
    (OUT / "pack.mcmeta").write_text(json.dumps({"pack": {
        "pack_format": 88, "min_format": 88, "max_format": 88,
        "description": "rock prototype - load above the vanilla pack"}}, indent=4))
    print("written", OUT)


if __name__ == "__main__":
    main()
