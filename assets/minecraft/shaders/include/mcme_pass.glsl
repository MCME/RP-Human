// Which fluid kinds (fluid.glsl's FLUID_) the terrain pass this shader is
// compiled for can draw, as bits: imported at the end of mcme_modules.glsl,
// which says, for each pack, those of its solid, cutout and translucent passes.
//
// The game compiles the terrain shaders once for each pass, and sends each
// face to one by its texture's transparency (fluid_signature.py's
// pass_kinds): vanilla and Sodium give the cutout pass an ALPHA_CUTOUT of
// 0.5, the translucent pass 0.1 or 0.01, the solid pass none. A fluid's code
// slows every face of a pass it is compiled into, even those that never run
// it - the water halved the frame rate in front of grass, in the cutout pass
// - so the base draws water and the modules only under MCME_PASS_HAS, and a
// pass with no fluid at all doesn't look for one. A pack's hooks can guard
// their own fluids' code the same way, and a feature of their own by the
// pass it is drawn in (MCME_TRANSLUCENT_PASS...). In the cutout pass with
// no fluid, a block's texel the cutout drops goes before any other work,
// hooks included.

// Which pass this is, and the alpha it cuts at (0 in the solid pass)
#ifndef ALPHA_CUTOUT
const float MCME_PASS_CUTOUT = 0.0;
#else
const float MCME_PASS_CUTOUT = ALPHA_CUTOUT;
#endif
const bool MCME_SOLID_PASS = MCME_PASS_CUTOUT == 0.0;
const bool MCME_CUTOUT_PASS = MCME_PASS_CUTOUT >= 0.3;
const bool MCME_TRANSLUCENT_PASS = !MCME_SOLID_PASS && !MCME_CUTOUT_PASS;

const uint MCME_PASS_KINDS = MCME_SOLID_PASS ? MCME_SOLID_KINDS : MCME_CUTOUT_PASS ? MCME_CUTOUT_KINDS : MCME_TRANSLUCENT_KINDS;

#define MCME_PASS_HAS(kind) (((MCME_PASS_KINDS >> uint(kind)) & 1u) != 0u)
