// Water: the game's water, its colour the biome's as ever, with faint
// ripples drifting over it in layers - deeper ones shifting with the view, as
// the lava's do - and on still water's top a light chop running every way,
// streaks where it flows, and foam, blended in: on flowing water and falls,
// if switched on now and then in a small wave crossing still water, and,
// with Sodium, along its shores; murkier the further one looks through it.
// No reflections, as nothing else in the world has them. Drawn per pixel over water's faces -
// the fluid's, and the pack's models textured with it - fixed in the world.
// Pixelated as a 16px texture is (WATER_PIXEL); its settings are in
// water_config.glsl. Needs fluid.glsl, which tells its faces from others
// (fluidKind) - see there.
//
// Shores: Sodium lights water by the blocks round it (smooth lighting),
// darkening the corners of its faces that touch them. The vertex shader
// passes each corner's brightness on in a slot of its own, and a 1 in that
// slot alongside (water_corner.glsl's waterCorner), so the fragment knows its
// triangle's corners, and where it is between them. A corner darker than the
// brightest is on a shore, and so is an edge between two such corners: the
// foam is drawn by how far the fragment is from those - by which corners are
// darkened, not how much, nor the biome's colour or the light, which are the
// same at every corner. Vanilla doesn't darken water so: without Sodium there
// is no shore foam.

#define WATER_STILL FLUID_WATER_STILL
#define WATER_FLOWING FLUID_WATER_FLOWING

// What the water looks like at a fragment, for its shader to draw with the
// colour and light it has always had.
struct WaterLook {
    float shade;    // its brightness, over its own lit colour: about 1
    float murk;     // how murky it is, 0 to 1, for waterMurky (a shader
                    // pack's own water has murk of its own, so leaves it)
    float foam;     // how much of it is foam, 0 to 1
    float alpha;
};

// Where on its face a fragment is, and which corners of its triangle are on
// a shore, for waterLook: from what water_corner.glsl's waterCorner wrote,
// interpolated. Taken before any branching, as it needs derivatives.
struct WaterShore {
    vec2 at;          // where on its face: 0 to 1 along each side
    vec2 dx, dy;      // at's change to the next pixel across and up
    vec4 shore;       // per corner: 1 on a shore, 0 not, -1 not this triangle's
    float open;       // the brightest corner's brightness: the face's own, unoccluded
    float height;     // a side face's height, foot to top, in blocks: the same
                      // all over it (see waterShore). 1 where unknown
};

// The corners of a face, in the order its vertices come in.
const vec2 WATER_CORNERS[4] = vec2[4](vec2(0.0, 0.0), vec2(0.0, 1.0), vec2(1.0, 1.0), vec2(1.0, 0.0));

WaterShore waterShore(vec4 lights, vec4 weights, vec4 heights) {
    WaterShore s;
    float brightest = 0.0;
    vec4 corner = vec4(0.0);
    for (int k = 0; k < 4; k++) {
        corner[k] = weights[k] > 1.0e-3 ? lights[k] / weights[k] : 0.0;
        brightest = max(brightest, corner[k]);
    }
    // a side's height from the two corners both its triangles have - a quad
    // is drawn as corners 0-1-2 and 2-3-0 - which, whichever corner it starts
    // at (Sodium turns some), are one at its top and one at its foot: so the
    // same all over it. Taken from each triangle's own three, a side whose
    // top slopes had two heights, and its streaks broke off along the diagonal
    s.height = min(weights[0], weights[2]) > 1.0e-4 ? abs(heights[0] / weights[0] - heights[2] / weights[2]) : 1.0;
    s.at = vec2(0.0);
    for (int k = 0; k < 4; k++) {
        s.at += weights[k] * WATER_CORNERS[k];
        // darker than the brightest by more than the biome's colour or the
        // light would make it
        s.shore[k] = weights[k] > 1.0e-3 ? (corner[k] < brightest * 0.92 ? 1.0 : 0.0) : -1.0;
    }
    s.open = brightest;
    s.dx = dFdx(s.at);
    s.dy = dFdy(s.at);
    return s;
}

// How far point p is from the segment a to b.
float waterToSegment(vec2 p, vec2 a, vec2 b) {
    vec2 ab = b - a;
    return length(p - a - ab * clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0));
}

// How far, along its face, the fragment at s - at its pixel's middle, shift
// away in the world - is from its shores: in sides of the face, about blocks.
float waterAway(WaterShore s, FluidFrame f, vec3 shift) {
    // at's gradients along the face, each dotted with the shift giving its
    // change over it, as fluidFlow() finds the flow's
    vec3 across = cross(f.dx, f.dy);
    float aa = dot(across, across);
    vec2 at = s.at;
    if (aa > 0.0) {
        vec3 gu = (s.dx.x * cross(f.dy, across) + s.dy.x * cross(across, f.dx)) / aa;
        vec3 gv = (s.dx.y * cross(f.dy, across) + s.dy.y * cross(across, f.dx)) / aa;
        at += vec2(dot(gu, shift), dot(gv, shift));
    }
    float away = 1.0e9;
    for (int k = 0; k < 4; k++) {
        if (s.shore[k] > 0.5) {
            away = min(away, length(at - WATER_CORNERS[k]));
            if (s.shore[(k + 1) & 3] > 0.5) away = min(away, waterToSegment(at, WATER_CORNERS[k], WATER_CORNERS[(k + 1) & 3]));
        }
    }
    return away;
}

// How long a wave takes to come round again, in seconds: each divides the
// day's 1200, so waves come back as the day's clock starts over.
const float WATER_WAVE_TIMES[4] = float[4](20.0, 24.0, 30.0, 40.0);

// A small wave on still water at here (blocks): in some squares of
// WATER_WAVE_SPACING now and then, a crest of foam crossing WATER_WAVE_TRAVEL
// blocks from the west or the north-west as it rises and dies away, a trail
// of foam behind it thinning and breaking up. Each its own: longer or
// shorter, straighter or more bowed, gapped along its crest.
float waterWave(vec2 here, float time, float pixel) {
    vec2 g = here / WATER_WAVE_SPACING;
    ivec2 cell = ivec2(floor(g));
    int mask = int(64.0 / WATER_WAVE_SPACING) - 1;
    float wave = 0.0;
    for (int k = 0; k < 9; k++) {
        ivec2 o = cell + ivec2(k % 3 - 1, k / 3 - 1);
        ivec2 id = o & mask;
        float period = WATER_WAVE_TIMES[int(fluidRand(ivec4(id, 0, 700)) * 3.99)];
        float t = time / period + fluidRand(ivec4(id, 1, 700)) * 3.0;
        int rise = int(floor(t)) % int(1200.0 / period);
        float life = fract(t) / 0.4;
        if (life >= 1.0 || fluidRand(ivec4(id, rise, 701)) > WATER_WAVES) continue;
        vec2 start = (vec2(o) + vec2(fluidRand(ivec4(id, rise, 702)), fluidRand(ivec4(id, rise, 703)))) * WATER_WAVE_SPACING;
        // east, or south-east (+x, +z), give or take a little
        float a = fluidRand(ivec4(id, rise, 704)) * 0.7853982 + (fluidRand(ivec4(id, rise, 705)) - 0.5) * 0.25;
        vec2 dir = vec2(cos(a), sin(a));
        float half_ = 0.6 + 1.2 * fluidRand(ivec4(id, rise, 706));
        float bow = (fluidRand(ivec4(id, rise, 707)) - 0.3) * 0.25 / half_;
        vec2 d = here - start - dir * life * WATER_WAVE_TRAVEL;
        float across = dot(d, vec2(-dir.y, dir.x));
        float ahead = dot(d, dir) + bow * across * across;
        float reach = 1.0 - smoothstep(half_ * 0.6, half_, abs(across));
        // gaps along its crest, fixed to the wave as it goes
        float gaps = fluidNoise(vec2(across * 2.0, float(rise)) + vec2(id) * 3.0, vec2(2.0, 1.0), pixel, 708);
        float crest = (1.0 - smoothstep(WATER_PIXEL, WATER_PIXEL * 2.0, abs(ahead))) * step(0.3, gaps);
        // the trail: streaks of foam left behind across its width, breaking
        // up and fading the further back they lie, no longer than the wave
        // has gone
        float behind = -ahead / WATER_WAVE_TRAIL;
        float left = behind > 0.0 && behind * WATER_WAVE_TRAIL < life * WATER_WAVE_TRAVEL ? 1.0 - behind : 0.0;
        float streaks = fluidNoise(vec2(across * 6.0, -ahead * 1.5) + vec2(id) * 7.0 + float(rise), vec2(1.0, 1.0), pixel, 709);
        float trail = left > 0.0 ? step(1.0 - 0.6 * left, streaks) * left * left : 0.0;
        float foam = max(crest, trail * 0.7) * reach;
        wave = max(wave, foam * sin(life * 3.1415927));
    }
    return wave;
}

// The small waves on still water's top, largest first: each a train of
// crests running across it, as (its length, crest to crest, in blocks; the
// way it runs, in degrees from east towards south; how much it shows).
// They run every way, each turned the golden angle (137.5 degrees) from the
// one before, so that no way shows as a current - the map's rivers run every
// way, and are still water - none crosses another square on, and none runs
// along the blocks: crests so crossing would show a grid. Lengths and ways at
// odds with each other, so that they never line up.
const vec3 WATER_WIND_WAVES[12] = vec3[12](
    vec3(5.3, 23.0, 1.0), vec3(3.7, 160.5, 0.93), vec3(2.9, 298.0, 0.86), vec3(2.2, 75.5, 0.8),
    vec3(1.75, 213.0, 0.74), vec3(1.4, 350.5, 0.68), vec3(1.1, 128.0, 0.63), vec3(0.9, 265.5, 0.58),
    vec3(0.72, 43.0, 0.53), vec3(0.58, 180.5, 0.49), vec3(0.47, 318.0, 0.45), vec3(0.38, 95.5, 0.41));

struct WaterSurface {
    float height;   // about -0.5 to 0.5, 0 on average
    vec2 slope;     // along x and z
    float glints;   // where light may catch on its crests, 0 to 1: in the
                    // gusts, here and there - on every crest, they'd line up
};

// The wind's waves at here (x and z, blocks), time seconds into the day.
// Each has sharp crests and wide troughs (exp(sharp (sin - 1))), and pushes those
// after it along by its own slope, bunching them on its crests as the wind
// does - so that they cross, gather and break up, never quite the same. Each
// runs a whole number of crests over 64 blocks along x and z, and comes round
// a whole number of times a day, so all of it repeats as the world's
// patterns do, and is where it was when the day's clock starts over.
// So that their crossing makes no grid - a few waves crossing evenly make
// rhombs, plain to see over an ocean - their crests are bent about, finely
// (WATER_WIND_BEND) and broadly (WATER_WIND_SWAY), and gusts drift over the
// water: three patchworks of calmer and choppier water, each wave stirred
// by its own mix of them (WATER_WIND_GUSTS), so that which waves are up
// changes from place to place.
WaterSurface waterWind(vec2 here, float time, float pixel) {
    WaterSurface s = WaterSurface(0.0, vec2(0.0), 0.0);
    // a wave's average, I0(sharp) / e^sharp, from I0's series
    float mean = 0.0;
    float term = 1.0;
    for (int j = 1; j < 10; j++) {
        mean += term;
        term *= WATER_WIND_SHARP * WATER_WIND_SHARP / (4.0 * float(j * j));
    }
    mean *= exp(-WATER_WIND_SHARP);
    // all of them, shown or not - the table's whole, so that fewer waves
    // (WATER_WIND_COUNT) only lose the finest, the rest as strong as ever
    float total = 0.0;
    for (int i = 0; i < 12; i++) total += WATER_WIND_WAVES[i].z;
    // (each patchwork, and the bending, drifting its own way, slowly)
    vec2 at = here + fluidWarp(here - vec2(FLUID_STIR[2]) * FLUID_STEP * time, vec2(0.25), pixel, 150) * WATER_WIND_BEND
                   + fluidWarp(here - vec2(FLUID_STIR[1]) * FLUID_STEP * time, vec2(0.0625), pixel, 158) * WATER_WIND_SWAY;
    vec3 gusts = vec3(fluidNoise(here - vec2(FLUID_STIR[0]) * FLUID_STEP * time, vec2(0.125), pixel, 152),
                      fluidNoise(here - vec2(FLUID_STIR[4]) * FLUID_STEP * time + 21.0, vec2(0.1875), pixel, 153),
                      fluidNoise(here - vec2(FLUID_STIR[3]) * FLUID_STEP * time + 43.0, vec2(0.25), pixel, 156));
    for (int i = 0; i < WATER_WIND_COUNT; i++) {
        vec3 w = WATER_WIND_WAVES[i];
        float a = radians(w.y);
        vec2 k = floor(vec2(cos(a), sin(a)) * (64.0 / w.x) + 0.5);
        float len = 64.0 / length(k);
        // as fast as real water's of its length, sqrt(g len / 2 pi), by
        // WATER_WIND_SPEED, in whole turns a day
        float turns = floor(WATER_WIND_SPEED * sqrt(9.81 * len / 6.2831853) / len * 1200.0 + 0.5);
        // fading as its crests near a few pixels apart, as a mipmapped
        // texture's detail does - and gone, every wave after it with it, the
        // table running longest first
        float fade = clamp(len / pixel * 0.25 - 0.5, 0.0, 1.0);
        if (fade <= 0.0) break;
        // its own mix of the gusts, by the way it runs
        vec3 mixed = 0.5 + 0.5 * vec3(cos(a), sin(a), cos(3.0 * a));
        float gust = smoothstep(0.36, 0.64, dot(gusts, mixed) / (mixed.x + mixed.y + mixed.z));
        float show = w.z * fade * mix(1.0 - WATER_WIND_GUSTS, 1.0, gust);
        // ...and its crests twisted by its own mix of them, so that no two
        // bend alike, and where they cross keeps changing
        vec3 twist = vec3(sin(2.0 * a), cos(2.0 * a), sin(a));
        float phase = 6.2831853 * (fract(dot(k, at) / 64.0) - fract(turns * time / 1200.0) + dot(gusts - 0.5, twist) * WATER_WIND_TWIST);
        float e = exp(WATER_WIND_SHARP * (sin(phase) - 1.0));
        float de = e * cos(phase);
        s.height += (e - mean) * show;
        s.slope += de * show * k * (WATER_WIND_STEEP / length(k));
        at -= k * (de * show * WATER_WIND_DRAG / length(k));
    }
    s.height /= total;
    float patches = fluidNoise(here - vec2(FLUID_STIR[5]) * FLUID_STEP * time, vec2(0.375), pixel, 155);
    s.glints = smoothstep(0.38, 0.68, patches) * smoothstep(0.38, 0.62, (gusts.x + gusts.y + gusts.z) / 3.0);
    return s;
}

// The water's colour before light: its biome's, the vertex colour - or
// WATER_TEST_COLOR (water_config.glsl), for trying colours out.
vec3 waterTint(vec3 vertexColor) {
#ifdef WATER_TEST_COLOR
    return vec3((WATER_TEST_COLOR >> 16) & 255, (WATER_TEST_COLOR >> 8) & 255, WATER_TEST_COLOR & 255) / 255.0;
#else
    return vertexColor;
#endif
}

// How murky the water is looked straight down on (waterLook's murk at its
// least): through WATER_MURK_DEPTH of it.
#define WATER_MURK_DOWN (1.0 - exp(-WATER_MURK_DEPTH / WATER_MURK_CLEAR))

// Water's lit colour - the biome's, as ever - as murky as a WaterLook's
// murk: deeper and richer, the same colour still. Brightened first by as
// much as murk looked straight down darkens it, so that there it is the
// biome's colour, and only darker looked into at a slant.
vec3 waterMurky(vec3 color, float murk) {
    vec3 deep = max(mix(vec3(dot(color, vec3(0.299, 0.587, 0.114))), color, WATER_MURK_RICH), 0.0) * WATER_MURK_SHADE;
    return mix(color, deep, murk) / mix(1.0, WATER_MURK_SHADE, WATER_MURK_DOWN);
}

// The water's look at f, a face of kind, time seconds into the day; shore
// from waterShore.
WaterLook waterLook(int kind, FluidFrame f, float time, WaterShore shore) {
    vec3 n = fluidNormal(f);
    bool top = abs(n.y) > 0.6;
    // the face's own axes: x and z on top (and on flowing water's slopes),
    // along it and up on its sides - always the world's own axes
    vec3 axisU = top ? vec3(1.0, 0.0, 0.0) : abs(n.x) > abs(n.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 axisV = top ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);

    // pixelated: the face is cut into squares of WATER_PIXEL blocks, each
    // traced once, through its middle
    vec2 s = vec2(dot(f.world, axisU), dot(f.world, axisV));
    vec2 snap = (floor(s / WATER_PIXEL) + 0.5) * WATER_PIXEL - s;
    vec3 shift = axisU * snap.x + axisV * snap.y;
    vec3 world = f.world + shift;
    vec3 ray = normalize(f.pos + shift);
    float pixel = max(max(length(f.dx), length(f.dy)), WATER_PIXEL);

    // how it moves: flowing water along its texture's flow, faster on top
    // than below; still water drifting, each layer its own way
    vec3 v = fluidFlow(f);
    vec2 flow = vec2(dot(v, axisU), dot(v, axisV));
    bool flowing = kind == WATER_FLOWING && dot(flow, flow) > 0.0;
    ivec2 way = flowing ? fluidWay(flow) : ivec2(0);
    mat2 along = fluidAlong(way);
    // how steep it runs: its top calm up to about two levels' drop over a
    // block (a normal's y of 0.976; a level's drop, 0.994 - 0.988 across a
    // corner), steep from about four (0.91). Its sides are falls only where
    // they're a whole block tall, as falling water's are: the short sides of
    // water sloping down to a lower block are calm
    float steep = top ? 1.0 - smoothstep(0.92, 0.98, abs(n.y)) : smoothstep(0.92, 0.97, shore.height);
    int steps = top || steep < 0.5 ? WATER_FLOW_STEPS : WATER_FALL_STEPS;
    // its patterns drawn out along it - but not where it's calm, which looks
    // as still water does, only moving
    vec2 stretch = flowing ? vec2(steep < 0.5 ? 1.0 : top ? 0.5 : 0.25, 1.0) : vec2(1.0);
    vec2 here = vec2(dot(world, axisU), dot(world, axisV));

    // ---- still water's top: the wind's waves (waterWind), over the layers
    // below; their slopes turn its face, for its sheen and opacity
    bool windy = top && !flowing;
    WaterSurface wind = WaterSurface(0.0, vec2(0.0), 0.0);
    vec3 facing = n;
    if (windy) {
        wind = waterWind(here, time, pixel);
        facing = sign(n.y) * normalize(vec3(-wind.slope.x, 1.0, -wind.slope.y));
    }
    float glance = 1.0 - clamp(-dot(ray, facing), 0.0, 1.0);
    glance *= glance * glance;
    float flat_ = 1.0 - clamp(-dot(ray, n), 0.0, 1.0);
    flat_ *= flat_ * flat_;

    // ---- ripples: layers of soft swells, deeper ones seen further along
    // the view ray, each drifting and turned its own way; light caught on
    // the crests of the top one - the wind's, on still water's top
    float into = max(-dot(ray, n), 0.3);
    float ripple = 0.0;
    float weight = 0.0;
    float crest = windy ? smoothstep(WATER_WIND_CREST, WATER_WIND_CREST + 0.15, wind.height) * wind.glints : 0.0;
    // (under the wind's, only the deeper ones, WATER_WIND_LAYERS of them;
    // under flowing water's streaks, fewer)
    for (int i = windy ? 1 : 0; i < (windy ? 1 + WATER_WIND_LAYERS : flowing ? WATER_FLOW_LAYERS : WATER_LAYERS); i++) {
        vec3 at = world + ray * (float(i) * WATER_LAYER_DEPTH / into);
        vec2 q = vec2(dot(at, axisU), dot(at, axisV));
        ivec2 drift = flowing ? way * ((steps * (5 - i) + 2) / 5) + ivec2(-way.y, way.x) * ((i & 1) == 1 ? 1 : -1)
                              : FLUID_STIR[i] * WATER_STIR;
        q -= vec2(drift) * FLUID_STEP * time;
        q = flowing ? along * q : FLUID_TURN[i] * q;
        vec2 cells = FLUID_CELLS[i] * stretch;
        if (!flowing) q += fluidWarp(q, cells * 0.5, pixel, i + 120) * 0.8 / cells;
        float a = fluidNoise(q, cells, pixel, i + 100) * 0.65 + fluidNoise(q + 13.0, cells * 2.0, pixel, i + 110) * 0.35;
        float w = 1.0 / (1.0 + 0.6 * float(i));
        ripple += a * w;
        weight += w;
        if (i == 0) crest = smoothstep(0.86, 0.97, 1.0 - abs(2.0 * a - 1.0));
    }
    ripple = weight > 0.0 ? ripple / weight - 0.5 : 0.0;

    // ---- streaks along flowing water, top and falls: fine lines drawn out
    // along it, running with it - faint where its top is calm (steep), and
    // as bright as WATER_STREAK where it runs steep
    vec2 c = along * (here - vec2(flowing ? way * steps : FLUID_STIR[0] * WATER_STIR) * FLUID_STEP * time);
    // (and its ripples softer where calm, as still water's are under the wind)
    float calm = flowing ? mix(WATER_FLOW_CALM, 1.0, steep) : 1.0;
    float streak = 0.0;
    if (flowing) {
        // two sets of lines, the finer running a little ahead, light on
        // their ridges and a little darker between
        float lines = 1.0 - abs(2.0 * fluidNoise(c + fluidWarp(c, vec2(0.5, 1.0), pixel, 136) * 0.5, vec2(0.25, 4.0), pixel, 135) - 1.0);
        float fine = 1.0 - abs(2.0 * fluidNoise(c * vec2(1.0, 1.0) + 31.0, vec2(0.5, 8.0), pixel, 137) - 1.0);
        streak = (smoothstep(0.7, 0.92, lines) + smoothstep(0.8, 0.96, fine) * 0.5 - (1.0 - lines) * 0.2)
               * mix(WATER_STREAK_CALM, WATER_STREAK, steep);
    }

    WaterLook look;
    look.shade = 1.0 + (ripple * 2.0 * WATER_RIPPLE + crest * WATER_CREST) * calm + streak
               + wind.height * 2.0 * WATER_WIND_RIPPLE + (glance - flat_) * WATER_SHEEN;

    // ---- foam: where it flows - more where its top runs steeper, most on
    // falls - now and then a small wave crossing still water, and, with
    // Sodium, a lapping band along its shores; softened and broken up
    float foam = 0.0;
    if (flowing) {
        // (a little where calm, nearly half as it turns steep, all of it
        // where it runs as steep as a normal's y of 0.75)
        float amount = top ? WATER_FOAM * (0.15 + 0.25 * steep + 0.6 * (1.0 - smoothstep(0.75, 0.95, abs(n.y))))
                           : mix(WATER_FOAM * 0.15, WATER_FALL_FOAM, steep);
        float streaks = fluidNoise(c, vec2(1.0, 4.0) * stretch, pixel, 130) * 0.6 + fluidNoise(c + 7.0, vec2(2.0, 8.0) * stretch, pixel, 131) * 0.4;
        foam = smoothstep(1.0 - amount * 0.75, 1.0 - amount * 0.75 + 0.12, streaks + (fluidNoise(c, vec2(8.0, 16.0), pixel, 134) - 0.5) * 0.12);
    }
#if WATER_FOAM_WAVES
    else if (top) {
        foam = waterWave(here, time, pixel) * WATER_WAVE_OPACITY / WATER_FOAM_OPACITY;
    }
#endif
    // (only on still water's top: flowing water's streaks are its own, and
    // still water's sides show where it drops away to lower water - its
    // corners darkened by the block under them, not a shore)
    if (!flowing && top) {
        float away = waterAway(shore, f, shift);
        // a band along the shore, its edge lapping in and out, and a thin
        // line of foam beyond it, washing in and out on its own swell
        float lap = fluidNoise(c + vec2(FLUID_STIR[2]) * FLUID_STEP * time * 4.0, vec2(2.0), pixel, 132);
        float band = (0.2 + (lap - 0.5) * 0.12) * WATER_SHORE_FOAM;
        // (172 swells a day, so they too are where they were when the day's
        // clock starts over)
        float wash = band + (0.1 + 0.04 * sin(time * (6.2831853 * 172.0 / 1200.0) + lap * 6.0)) * WATER_SHORE_FOAM;
        foam = max(foam, (1.0 - smoothstep(band - WATER_PIXEL, band, away)) * 0.8 * WATER_SHORE_OPACITY);
        foam = max(foam, (step(wash, away) - step(wash + 0.06, away)) * step(0.45, lap) * 0.6 * WATER_SHORE_OPACITY);
    }
    // (broken up into bubbles, only where there is any)
    look.foam = foam > 0.0 ? foam * smoothstep(0.2, 0.6, fluidNoise(c, vec2(16.0), pixel, 133) + foam * 0.4) * WATER_FOAM_OPACITY : 0.0;
    // ---- murk: what's under it is taken to lie WATER_MURK_DEPTH below its
    // top - it can't know how deep it is - so the further one's view runs
    // through it to there, the murkier: more at a slant than looking down.
    // Its sides the same colour, but see-through: what's behind them taken
    // to lie only WATER_MURK_SIDE behind, as behind a fall
    float cosine = max(-dot(ray, facing), 0.05);
    look.murk = 1.0 - exp(-WATER_MURK_DEPTH / cosine / WATER_MURK_CLEAR);
    float hides = top ? look.murk : 1.0 - exp(-WATER_MURK_SIDE / cosine / WATER_MURK_CLEAR);
    look.alpha = mix(mix(WATER_ALPHA, WATER_ALPHA_MURK, hides), 0.9, look.foam);
    return look;
}
