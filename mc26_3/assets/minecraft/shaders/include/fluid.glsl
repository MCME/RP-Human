// 26.3's copy of assets/minecraft/shaders/include/fluid.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_FLUID_GLSL
#define MCME_FLUID_GLSL
// What the fluids share - the shader base's water (water.glsl) and a pack's
// own, such as RP-Mordor's lava and ice: telling their faces apart from every
// other, where on such a face a fragment is, and patterns fixed to the world
// that repeat as it does.
//
// Shared by vanilla's terrain.fsh, Sodium's block_layer_opaque.fsh and
// Distant Horizons' terrain. Whatever draws without them - a shader pack,
// Voxy, another mod - shows the fluids' textures, which this leaves looking
// as they did.
//
// They are told by their textures, block/lava_still, lava_flow, water_still,
// water_flow and ice, and a pack's own fluids' textures: the lowest two bits
// of each texel's red, green and blue hold a code, by the texel's place in
// its 4x4 block of the sprite and by the sprite (fluidCode) - at most 3 steps
// in 255, which no one sees.
// A texel's code is checked, and if it is a fluid's, the codes of its whole
// 4x4 block. Lava's texels are opaque, the others' needn't be. The
// build writes the water's codes into every pack's water textures
// (ResourcePackScripts' generateVanilla/fluid_signature.py); a pack's own it
// signs with signFluids.py there, again after every edit of the textures.
//
// Everything is fixed to the world modulo 64 blocks. fluidWorld, the
// fragment's position, is its place in its chunk section plus that section's
// position mod 64 - all Sodium can give, from its 128x64x128 regions - so
// every pattern here repeats every 64 blocks, and looks the same with and
// without Sodium. Time is the game's: seconds into the day, as the eye's.

// ---------------------------------------------------------------- telling them

#define FLUID_LAVA_STILL 0
#define FLUID_LAVA_FLOWING 1
#define FLUID_WATER_STILL 2
#define FLUID_WATER_FLOWING 3
#define FLUID_ICE 4
// 5 to 7 are a pack's own, which it names in its hooks: RP-Mordor's fog
// block, tar pits and waterfall spray (its mordor_fluid.glsl)
#define FLUID_KINDS 8

uint fluidHash(ivec4 p) {
    uint h = uint(p.x) * 73856093u ^ uint(p.y) * 19349663u ^ uint(p.z) * 83492791u ^ uint(p.w) * 2654435761u;
    h ^= h >> 13;
    h *= 0x5bd1e995u;
    h ^= h >> 15;
    return h;
}

float fluidRand(ivec4 p) {
    return float(fluidHash(p) & 0xFFFFu) / 65535.0;
}

// The code the texel at atlas texel t of a fluid sprite of kind holds: 6
// bits, by t's place in its 4x4 block (sprites start on one).
int fluidCode(int kind, ivec2 t) {
    return int(fluidHash(ivec4(t & 3, kind, 731)) >> 26u);
}

// Whether a texel at atlas texel t holds kind's code: opaque, for lava.
bool fluidFits(int kind, vec4 texel, ivec2 t) {
    ivec4 c = ivec4(texel * 255.0 + 0.5);
    return (kind < FLUID_WATER_STILL ? c.a == 255 : c.a > 0)
        && (((c.r & 3) << 4) | ((c.g & 3) << 2) | (c.b & 3)) == fluidCode(kind, t);
}

// Which of their sprites the atlas holds at uv - a FLUID_ kind - or -1 if none.
// A texel's code can be more than one kind's: each such kind is checked on
// the whole 4x4 block.
int fluidKind(sampler2D atlas, vec2 uv) {
    ivec2 t = ivec2(floor(uv * vec2(textureSize(atlas, 0))));
    vec4 texel = texelFetch(atlas, t, 0);
    ivec2 block = t - (t & 3);
    for (int k = 0; k < FLUID_KINDS; k++) {
        if (!fluidFits(k, texel, t)) continue;
        bool all = true;
        for (int i = 0; i < 16 && all; i++) {
            ivec2 p = block + ivec2(i & 3, i >> 2);
            all = fluidFits(k, texelFetch(atlas, p, 0), p);
        }
        if (all) return k;
    }
    return -1;
}

// ---------------------------------------------------------------- where it is

// A fragment's place on a fluid's face: where it is, and the derivatives the
// rest is found from - taken before any branching, as they must be, and
// nothing more, as every terrain fragment takes them.
struct FluidFrame {
    vec3 world;     // its position, mod 64 blocks (see above)
    vec3 pos;       // ...and relative to the camera
    vec3 dx, dy;    // pos's change to the next pixel across and up
    vec2 dv;        // the texture's v's change to the same
};

FluidFrame fluidFrame(vec3 world, vec3 pos, vec2 uv) {
    return FluidFrame(world, pos, dFdx(pos), dFdy(pos), vec2(dFdx(uv.y), dFdy(uv.y)));
}

// The face's normal, towards the camera.
vec3 fluidNormal(FluidFrame f) {
    vec3 n = cross(f.dx, f.dy);
    float nn = dot(n, n);
    n = nn > 0.0 ? n * inversesqrt(nn) : vec3(0.0, 1.0, 0.0);
    return dot(n, f.pos) > 0.0 ? -n : n;
}

// The way the face's texture runs - the flow sprite's v - in the world: v's
// gradient along the face, which dotted with each pixel's step gives v's
// change over it.
vec3 fluidFlow(FluidFrame f) {
    vec3 n = cross(f.dx, f.dy);
    float nn = dot(n, n);
    return nn > 0.0 ? (f.dv.x * cross(f.dy, n) + f.dv.y * cross(n, f.dx)) / nn : vec3(0.0);
}

// ---------------------------------------------------------------- patterns

// Smooth value noise on a lattice of cells per unit along each axis, where 64
// units hold whole cells - so that, fed coordinates that are the world's mod
// 64 under a whole-number matrix, it repeats as they do. Where its cells get
// smaller than a pixel (pixel units) it fades to its average, as a
// mipmapped texture does.
float fluidNoise(vec2 q, vec2 cells, float pixel, int salt) {
    vec2 g = q * cells;
    ivec2 period = ivec2(64.0 * cells + 0.5);
    ivec2 c = ivec2(floor(g));
    vec2 f = fract(g);
    f = f * f * (3.0 - 2.0 * f);
    // wrapped by flooring: GLSL leaves % of a negative number undefined
    ivec2 c0 = c - period * ivec2(floor(vec2(c) / vec2(period)));
    ivec2 c1 = c0 + 1 - period * ivec2(greaterThanEqual(c0 + 1, period));
    float n = mix(mix(fluidRand(ivec4(c0, salt, 640)), fluidRand(ivec4(c1.x, c0.y, salt, 640)), f.x),
                  mix(fluidRand(ivec4(c0.x, c1.y, salt, 640)), fluidRand(ivec4(c1, salt, 640)), f.x), f.y);
    return mix(0.5, n, 1.0 / max(pixel * max(cells.x, cells.y) * 2.0, 1.0));
}

// A pair of it, for warping coordinates by: from -0.5 to 0.5.
vec2 fluidWarp(vec2 q, vec2 cells, float pixel, int salt) {
    return vec2(fluidNoise(q, cells, pixel, salt), fluidNoise(q, cells, pixel, salt + 1)) - 0.5;
}

// How each layer stirs, and the lava's crust slowly changes: whole steps of
// 64 blocks a day along each axis, so that all is where it started when the
// day's clock starts over.
const ivec2 FLUID_STIR[6] = ivec2[6](ivec2(1, 0), ivec2(0, -1), ivec2(-1, 1), ivec2(1, 1), ivec2(-1, 0), ivec2(0, 1));

// How each still layer's lattice is turned, so that none shows: by
// whole-number matrices, which keep its repeat - 0, 27, 63, -45, -27 and 45
// degrees, growing it by 1, 2.24 or 1.41 - and its cells, per unit of that.
const mat2 FLUID_TURN[6] = mat2[6](mat2(1.0, 0.0, 0.0, 1.0), mat2(2.0, 1.0, -1.0, 2.0), mat2(1.0, 2.0, -2.0, 1.0),
                                  mat2(1.0, -1.0, 1.0, 1.0), mat2(2.0, -1.0, 1.0, 2.0), mat2(1.0, 1.0, -1.0, 1.0));
const float FLUID_CELLS[6] = float[6](2.0, 1.0, 0.5, 1.0, 0.25, 0.5);

// A flowing fluid runs whichever of the eight ways - along x, z or the
// diagonals between - is nearest its flow: a whole-number step, so that its
// pattern repeats as a still one's does.
ivec2 fluidWay(vec2 flow) {
    vec2 a = abs(flow);
    ivec2 way = ivec2(sign(flow));
    if (a.x > 2.414 * a.y) way.y = 0;
    if (a.y > 2.414 * a.x) way.x = 0;
    return way;
}

// A whole-number matrix taking a way onto its first axis, for its streaks.
mat2 fluidAlong(ivec2 way) {
    if (way.y == 0) return mat2(1.0, 0.0, 0.0, 1.0);
    if (way.x == 0) return mat2(0.0, 1.0, 1.0, 0.0);
    return way.x == way.y ? mat2(1.0, -1.0, 1.0, 1.0) : mat2(1.0, 1.0, -1.0, 1.0);
}

// A step of 64 blocks a day, in blocks a second.
#define FLUID_STEP (64.0 / 1200.0)

#endif
