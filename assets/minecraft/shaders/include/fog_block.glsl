// The fog: fog blocks, thin and thick, and fog clouds, walked through -
// tripwire states, which have no collision - and drawn on their faces as how
// much fog the view passes through in the block behind: from where the view
// ray enters it to where it leaves it, the fog along the way summed from
// drifting, slowly changing wisps, thinner towards its top. So it is soft at
// its edges, where the view only grazes it, and blocks of it side by side and
// stacked add up into one fog, every face of each drawn (no cull faces). It
// thins out round the camera, so that one can walk in it. Lit by the light
// alone - no shading of its faces, which would show them - and tinted with
// the sky's colour. Pixelated as a 16px texture is (FOG_PIXEL); its settings
// are in fog_block_config.glsl.
//
// - A fog block (block/fog, fog_thick) is its block of fog.
// - A fog cloud (block/fog_cloud) is a dome of fog rising from the block
//   placed, about 5 blocks wide and tall, its edge soft and uneven: on a
//   path, fog pooled on the ground. Its model is the blocks it fills, each
//   turned a hair (0.002 degrees), as a fog block's is, so that the game
//   lights all their faces by the cloud's own block, not by the ground or a
//   wall beside it. It starts at the placed block's floor, out of the ground.
//
// They are told apart by their textures. Each is this pack's own fluid - the
// shader base keeps kinds 5 to 7 for a pack's own - all of kind 5, which the
// sync signs (.mcme-shaders.json). Above the code, each texel's colour holds
// which of them it is (FOG_ variants, blue's bits 2 to 4) and, in the
// cloud's, which of the cloud's blocks shows it: each face of a cloud's block
// shows the middle of a 4x4 block of texels, whose red's, green's and blue's
// bits 2 to 4, 2 to 4 and 5 to 7 hold the block's place in the cloud, from 0
// to 4 along each axis (west to east and north to south round the placed
// block, up from it) - 4x4, not one texel, as Sodium keeps texture
// coordinates to 15 bits, a texel or more off on a big atlas, and a face
// reading its neighbour's place would draw its cloud in the wrong place. The
// cloud's texture is all but clear, so that whatever draws without these
// shaders shows none of it. Drawn in mcme_hook_fragment_main.glsl; needs
// the base's fluid.glsl, imported before the hooks.
//
// It is drawn on every face of every fog block and cloud there is, each look
// at the fog several noises' worth, so it is kept cheap: the noise below,
// looks only as many as the way through a block needs (fogSamples), and no
// noise looked at where it can't change what is drawn - out of a cloud, past
// its uneven edge, round the camera where it is clear.
//
// RP-Mordor's fog block, from ResourcePackScripts' toolbox (prototypes/fog) -
// not its textured mist (mcme:block/mist) - made rarer, thinner and green,
// with a thick block and the clouds added.

#define FLUID_FOG 5
#define FOG_BLOCK FLUID_FOG

// which fog a texel is (see above)
#define FOG_THIN 0
#define FOG_THICK 1
#define FOG_CLOUD 2

// The most times a block of fog is looked at, however long the view's way
// through it.
#define FOG_MOST_SAMPLES 4

// How many times to look at the fog along a way through a block this long,
// in blocks: FOG_SAMPLES a block, at least once - so a view that only grazes
// a block's corner looks once, not as often as one across it.
int fogSamples(float way) {
    return clamp(int(ceil(way * FOG_SAMPLES)), 1, FOG_MOST_SAMPLES);
}

// Smooth value noise in three dimensions, on a lattice of cells per block,
// repeating every 64 blocks along each axis, as the world's coordinates here
// do - RP-Mordor's fluidNoise3, under the fog's own name, so that it can't
// clash with one the base may get. The base's fluidRand at each corner of
// the cell, but worked out together: the parts of fluidHash the corners
// share once, the rest four corners at a time.
float fogNoise3(vec3 p, float cells, int salt) {
    vec3 g = p * cells;
    vec3 f = fract(g);
    f = f * f * (3.0 - 2.0 * f);
    int period = int(64.0 * cells + 0.5);
    ivec3 c0 = ivec3(floor(g));
    c0 -= period * ivec3(floor(vec3(c0) / float(period)));
    ivec3 c1 = c0 + 1;
    c1 -= period * ivec3(greaterThanEqual(c1, ivec3(period)));
    const uvec3 mul = uvec3(73856093u, 19349663u, 83492791u);
    uvec3 h0 = uvec3(c0) * mul;
    uvec3 h1 = uvec3(c1) * mul;
    // the corners at y0 z0, y1 z0, y0 z1 and y1 z1, at x0 (a) and x1 (b)
    uvec4 yz = uvec4(h0.y ^ h0.z, h1.y ^ h0.z, h0.y ^ h1.z, h1.y ^ h1.z) ^ (uint(salt) * 2654435761u);
    uvec4 a = h0.x ^ yz;
    uvec4 b = h1.x ^ yz;
    a ^= a >> 13u;
    b ^= b >> 13u;
    a *= 0x5bd1e995u;
    b *= 0x5bd1e995u;
    a ^= a >> 15u;
    b ^= b >> 15u;
    vec4 x = mix(vec4(a & 0xFFFFu), vec4(b & 0xFFFFu), f.x) / 65535.0;
    vec2 y = mix(x.xz, x.yw, f.y);
    return mix(y.x, y.y, f.z);
}

// The wisps at p (blocks), time seconds into the day: from 0 between them to
// 1, the fewer the more patchy.
float fogWisps(vec3 p, float time, float patchy) {
    // east and a little south, the finer wisps slower and turning against it
    vec3 wind = vec3(ivec3(FOG_DRIFT, 0, FOG_DRIFT / 3)) * FLUID_STEP * time;
    vec3 wind2 = vec3(ivec3(FOG_DRIFT / 2, 0, -FOG_CHURN)) * FLUID_STEP * time;
    float n = fogNoise3(p - wind, 1.0 / FOG_WISP, 800) * 0.65 + fogNoise3(p - wind2, 2.0 / FOG_WISP, 810) * 0.35;
    return smoothstep(patchy - 0.15, patchy + 0.25, n);
}

// How much of a cloud on base - the middle of its placed block's floor -
// there is at p, from 0 to 1, and how high up it p is, 0 to 1: its dome,
// its edge eaten into by a slow noise drifting with the wisps, so that it is
// uneven and no two are the same. The noise is only looked at near the
// edge, where it eats: below the floor or past the edge there is none of
// the cloud, and further in than it eats (FOG_CLOUD_ROUGH), all of it.
vec2 fogCloud(vec3 p, vec3 base, float time) {
    vec3 w = p - base;
    float edge = (1.0 - length(w / FOG_CLOUD_SIZE)) * dot(FOG_CLOUD_SIZE, vec3(1.0 / 3.0));
    if (w.y < 0.0 || edge <= 0.0) return vec2(0.0);
    float high = clamp(w.y / FOG_CLOUD_SIZE.y, 0.0, 1.0);
    if (edge >= FOG_CLOUD_ROUGH + FOG_CLOUD_SOFT) return vec2(1.0, high);
    vec3 wind = vec3(ivec3(1, 0, 0)) * FLUID_STEP * time;
    float eaten = (fogNoise3(p - wind, 0.5, 830) * 0.7 + fogNoise3(p - wind, 1.0, 831) * 0.3) * FOG_CLOUD_ROUGH;
    return vec2(smoothstep(0.0, FOG_CLOUD_SOFT, edge - eaten), high);
}

// Where the view from o (blocks, from its middle) along d goes into and out
// of the box from -half_ to half_.
vec2 fogBox(vec3 o, vec3 d, vec3 half_) {
    vec3 a = (-half_ - o) / d;
    vec3 b = (half_ - o) / d;
    vec3 lo = min(a, b);
    vec3 hi = max(a, b);
    return vec2(max(lo.x, max(lo.y, lo.z)), min(hi.x, min(hi.y, hi.z)));
}

vec3 fogSafe(vec3 d) {
    return vec3(abs(d.x) < 1.0e-6 ? 1.0e-6 : d.x, abs(d.y) < 1.0e-6 ? 1.0e-6 : d.y, abs(d.z) < 1.0e-6 ? 1.0e-6 : d.z);
}

// A cloud's fog at f, a face of its block cell, the cloud on base: as a fog
// block's, the fog the view passes through in this one block - the faces of
// the blocks behind it draw theirs, so that whatever stands in the cloud
// hides the fog behind it - but the cloud's dome, not the block's, and
// pixelated in the world, not on the face: each look takes the fog at the
// middle of its FOG_PIXEL cube, so that it is the same at every distance and
// matches across the blocks' faces. All its blocks' fog is of one colour, so
// it adds up the same in whatever order the game draws them.
vec4 fogCloudLook(FluidFrame f, vec3 cell, vec3 base, float time, vec3 look) {
    vec3 camera = f.world - f.pos;
    vec3 view = fogSafe(normalize(f.pos));
    // the way through the block, from the face - or the camera, in it
    vec2 h = fogBox(camera - cell - 0.5, view, vec3(0.5));
    float t0 = max(h.x, FOG_CLEAR * 0.3);
    if (h.y <= t0) return vec4(FOG_COLOR, 0.0);
    int samples = fogSamples(h.y - t0);
    float step_ = (h.y - t0) / float(samples);
    float depth = 0.0;
    for (int i = 0; i < FOG_MOST_SAMPLES; i++) {
        if (i >= samples) break;
        float t = t0 + (float(i) + 0.5) * step_;
        vec3 p = (floor((camera + view * t) / FOG_PIXEL) + 0.5) * FOG_PIXEL;
        vec2 there = fogCloud(p, base, time);
        if (there.x <= 0.0) continue;
        depth += fogWisps(p, time, look.z) * there.x * (1.0 - FOG_SETTLE * there.y) * smoothstep(FOG_CLEAR * 0.3, FOG_CLEAR, t);
    }
    return vec4(FOG_COLOR, (1.0 - exp(-depth * step_ * look.x)) * look.y);
}

// The fog's colour - over the light - and opacity at f, time seconds into the
// day, in the block behind the face: a fog block's, of look's FOG_ settings,
// or, in a cloud, the block offset from the cloud's placed block.
vec4 fogBlockLook(FluidFrame f, float time, vec3 look, bool cloud, vec3 offset) {
    vec3 n = fluidNormal(f);
    bool top = abs(n.y) > 0.6;
    vec3 axisU = top ? vec3(1.0, 0.0, 0.0) : abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 axisV = top ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);

    // pixelated: the face is cut into squares of FOG_PIXEL blocks, each
    // traced once, through its middle
    vec2 s = vec2(dot(f.world, axisU), dot(f.world, axisV));
    vec2 snap = (floor(s / FOG_PIXEL) + 0.5) * FOG_PIXEL - s;
    vec3 shift = axisU * snap.x + axisV * snap.y;
    vec3 entry = f.world + shift;

    // the block it enters - behind the face (the blocks are turned a hair:
    // see their models)
    vec3 cell = floor(entry - n * 0.01);
    if (cloud) return fogCloudLook(f, cell, cell - offset + vec3(0.5, 0.0, 0.5), time, look);

    // ...how far the ray goes in it
    vec3 ray = normalize(f.pos + shift);
    vec3 local = clamp(entry - cell, 0.0, 1.0);
    vec3 exits = vec3(ray.x > 0.0 ? (1.0 - local.x) / ray.x : ray.x < 0.0 ? -local.x / ray.x : 1.0e9,
                      ray.y > 0.0 ? (1.0 - local.y) / ray.y : ray.y < 0.0 ? -local.y / ray.y : 1.0e9,
                      ray.z > 0.0 ? (1.0 - local.z) / ray.z : ray.z < 0.0 ? -local.z / ray.z : 1.0e9);
    float length_ = min(exits.x, min(exits.y, exits.z));

    // ...from where it hasn't thinned out round the camera: each look
    // thinned by its own distance, as a cloud's are, not the whole block by
    // its face's, which would step from block to block as one walks in it
    float camera = length(f.pos + shift);
    float t0 = max(FOG_CLEAR * 0.3 - camera, 0.0);
    float t1 = length_;
    if (t1 <= t0) return vec4(FOG_COLOR, 0.0);

    // the fog along it, a few looks spread over the way, thinner to the top
    // of the block, and round the camera
    int samples = fogSamples(t1 - t0);
    float step_ = (t1 - t0) / float(samples);
    float depth = 0.0;
    for (int i = 0; i < FOG_MOST_SAMPLES; i++) {
        if (i >= samples) break;
        float t = t0 + (float(i) + 0.5) * step_;
        depth += fogWisps(entry + ray * t, time, look.z) * (1.0 - FOG_SETTLE * clamp(local.y + ray.y * t, 0.0, 1.0))
               * smoothstep(FOG_CLEAR * 0.3, FOG_CLEAR, camera + t);
    }
    return vec4(FOG_COLOR, (1.0 - exp(-depth * step_ * look.x)) * look.y);
}

// The fog's colour - over the light - and opacity at f, which shows atlas at
// uv, time seconds into the day; sky the sky's colour; eye where the view
// is from, in f.pos's terms - not at 0 while the view bobs, which would
// trace the fog wrongly: off by the bob.
vec4 fogLook(FluidFrame f, vec3 eye, sampler2D atlas, vec2 uv, float time, vec3 sky) {
    f.pos -= eye;
    ivec4 c = ivec4(texelFetch(atlas, ivec2(floor(uv * vec2(textureSize(atlas, 0)))), 0) * 255.0 + 0.5);
    int variant = (c.b >> 2) & 7;
    vec3 offset = vec3(ivec3((c.r >> 2) & 7, (c.g >> 2) & 7, (c.b >> 5) & 7) - ivec3(2, 0, 2));
    // the thin block's wisps the thick one's, so that the two move as one
    // where they meet, but less of it: thinner, and hiding at most
    // FOG_THIN_MOST - not cut off there, which would show each block
    vec3 look = variant == FOG_CLOUD ? FOG_CLOUD_LOOK : FOG_THICK_BLOCK;
    if (variant == FOG_THIN) look.xy = vec2(look.x * FOG_THIN_SHARE, FOG_THIN_MOST);
    vec4 fog = fogBlockLook(f, time, look, variant == FOG_CLOUD, offset);
    return vec4(mix(fog.rgb, sky, FOG_TINT), fog.a);
}
