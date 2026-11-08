// 26.3's copy of assets/minecraft/shaders/include/fog_block_config.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_FOG_BLOCK_CONFIG_GLSL
#define MCME_FOG_BLOCK_CONFIG_GLSL
// The fog's settings (fog_block.glsl): the fog blocks, thin and thick, and the
// fog clouds. See fog_block.glsl for what they are. Paths of
// the Dead's thin fog is much rarer, much thinner and greener than RP-Mordor's,
// whose values are noted where they differ.

#define FOG_PIXEL (1.0 / 16.0)       // its pixels' size, in blocks, as a 16px texture's

// How thick each is, as vec3(density, most, patchy):
// - density: how thick it is where it is thickest, per block of fog looked through
// - most: the most it hides, 0 to 1, so the world always shows through it
// - patchy: how much of it is clear, between its wisps, 0 to 1
#define FOG_THICK_BLOCK vec3(1.6, 0.8, 0.5)      // block/fog_thick (Mordor's fog block: vec3(1.0, 0.8, 0.55))
#define FOG_THIN_SHARE 0.5                        // block/fog: the thick block's wisps, moving with them, but this share as thick...
#define FOG_THIN_MOST 0.5                         // ...and hiding at most this much, 0 to 1 (its own were vec3(0.8, 0.5, 0.68))
#define FOG_CLOUD_LOOK vec3(1.2, 0.55, 0.62)     // block/fog_cloud

#define FOG_WISP 2.0                 // how big its wisps are, roughly, in blocks (a power of two)
#define FOG_SAMPLES 2.0              // how many times it is looked at per block of it the view goes through (the more, the smoother and the dearer), at most 4 in each block
#define FOG_SETTLE 0.4             // how much thinner it is at the top of a block or cloud than at its bottom, 0 to 1

// The clouds' shape: a dome of fog rising from the block placed, its edge
// eaten into unevenly
#define FOG_CLOUD_SIZE vec3(2.4, 4.4, 2.4)    // its radii, in blocks, east-west, up and north-south: at most 2.4, 4.4 (the higher, the narrower its top must be)
#define FOG_CLOUD_ROUGH 1.2          // how far in its edge is eaten, at most, in blocks
#define FOG_CLOUD_SOFT 0.9           // how far in from its edge it takes to thicken, in blocks

// how it drifts: from the west, as the water's waves, in whole steps of 64
// blocks a day (0.053 blocks a second), so that it is back where it started
// when the day's clock starts over
#define FOG_DRIFT 6                  // its wisps (0.32 a second)
#define FOG_CHURN 2                  // how fast they change, against the drift

#define FOG_COLOR vec3(0.66, 0.8, 0.66)    // a pale green, as the Dead's ghost blocks (Mordor: vec3(0.8, 0.81, 0.82))
#define FOG_TINT 0.15                // how much it takes the sky's colour, 0 to 1
#define FOG_OPEN 1.0                 // how much it is lit as if under the open sky, 0 to 1: at 1 it doesn't darken in the shade or underground, only at night and away from lamps
#define FOG_CLEAR 1.5                // it thins out round the camera within this, in blocks
#endif
