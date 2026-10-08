// The water's settings (water.glsl). See water.glsl for what it is.

#define WATER_PIXEL (1.0 / 16.0)     // its pixels' size, in blocks, as a 16px texture's

// ripples, in layers under the surface as the lava's are
#define WATER_LAYERS 3               // how many (up to 6)
#define WATER_FLOW_LAYERS 2          // ...under flowing water's streaks, each costs a fifth of its time
#define WATER_LAYER_DEPTH 0.3        // how far apart they are, in blocks
#define WATER_RIPPLE 0.16            // how much they lighten and darken it
#define WATER_CREST 0.22             // how bright the light caught on their crests is
#define WATER_STREAK 0.3             // how bright the streaks along flowing water are where it runs steep, and falls
#define WATER_STREAK_CALM 0.05       // ...and where it barely slopes (up to two levels' drop over a block)
#define WATER_FLOW_CALM 0.35         // how much of the ripples' light and dark shows there, 0 to 1

// a test colour for the water, in place of its biome's: uncomment, set, and
// reload the resource packs (F3+T). Only for trying colours out: the build
// refuses a pack whose copy of this file was changed
//#define WATER_TEST_COLOR 0x3F76E4

// how fast it moves, in whole steps of 64 blocks a day (0.053 blocks a
// second), so that it is back where it started when the day's clock starts over
#define WATER_STIR 2                 // still water's drift
#define WATER_FLOW_STEPS 12          // flowing water, on top (0.64 a second; diagonally 1.41 times that)
#define WATER_FALL_STEPS 30          // water falling down a side (1.6 a second)

// still water's top: a light chop, small waves running across it every way
// (their lengths and ways: water.glsl's WATER_WIND_WAVES)
#define WATER_WIND_COUNT 8           // how many of them (up to 12), largest first: each costs as much
#define WATER_WIND_RIPPLE 0.13       // how much they lighten and darken it
#define WATER_WIND_CREST 0.16        // how high on them light catches (WATER_CREST), -0.5 to 0.5
#define WATER_WIND_SPEED 0.17        // how fast, of real water's waves their size
#define WATER_WIND_SHARP 1.8         // how sharp their crests are, against their troughs (1 or more)
#define WATER_WIND_LAYERS 0          // how many of the ripples' layers still show under them
#define WATER_WIND_STEEP 0.35        // how steep, for the sheen and opacity
#define WATER_WIND_DRAG 0.12         // how far each pushes the smaller about, in blocks
#define WATER_WIND_BEND 1.6          // how far their crests are bent about, in blocks
#define WATER_WIND_SWAY 3.0          // ...and swayed about, over tens of blocks
#define WATER_WIND_TWIST 2.0         // ...and each twisted its own way, in crests
#define WATER_WIND_GUSTS 0.6         // how much calmer each wave is in the calm patches between gusts, 0 to 1
#define WATER_SHEEN 0.18             // how much lighter their faces turned from you are, catching the sky

// murk: what's under it is taken to lie WATER_MURK_DEPTH below its top, as it
// can't know - so it is murkier the further one's view runs through it to there
#define WATER_MURK_DEPTH 1.5         // how deep what's under it is taken to be, in blocks
#define WATER_MURK_SIDE 1.0          // ...and behind its sides, setting only how see-through they are: under
                                     // a block, so that falls and the water's edges show what's behind them
#define WATER_MURK_CLEAR 1.1         // how far one sees through it before it's mostly (63%) murk, in blocks
#define WATER_MURK_SHADE 0.7         // how dark murk is, of the water's own colour (its biome's) - it's brightened
                                     // to start with, so that looked straight down on it is the biome's colour
#define WATER_MURK_RICH 1.1          // how much richer its colour is: 1 the same, more deeper-coloured

#define WATER_ALPHA 0.5              // how opaque it is with no murk, foam aside
#define WATER_ALPHA_MURK 0.98        // ...and all murk

// foam, white water: all of it blended in, no more than WATER_FOAM_OPACITY
#define WATER_FOAM_OPACITY 0.5
#define WATER_FOAM 0.3               // on flowing water's top, 0 to 1, more where it runs steeper
#define WATER_FALL_FOAM 0.4          // on falls
#define WATER_SHORE_FOAM 1.0         // along its shores - with Sodium only, see water.glsl
#define WATER_SHORE_OPACITY 0.45     // ...how strong it shows there, 0 to 1
#define WATER_FOAM_COLOR vec3(0.92, 0.95, 0.96)

// small waves now and then on still water: a crest of foam crossing it,
// always from the west, or the north-west, a trail of foam behind it
#define WATER_FOAM_WAVES 0           // 1 to have them, 0 not
#define WATER_WAVE_SPACING 8.0       // at most one at a time in each square this wide, in blocks (a power of two)
#define WATER_WAVES 0.25             // in how many of them, 0 to 1
#define WATER_WAVE_TRAVEL 4.0        // how far each crosses, in blocks (under WATER_WAVE_SPACING)
#define WATER_WAVE_TRAIL 1.6         // how long the trail behind it is, in blocks
#define WATER_WAVE_OPACITY 0.75      // how opaque its foam is at most
