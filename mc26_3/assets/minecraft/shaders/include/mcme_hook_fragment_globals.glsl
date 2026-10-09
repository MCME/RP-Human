// 26.3's copy of assets/minecraft/shaders/include/mcme_hook_fragment_globals.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_HOOK_FRAGMENT_GLOBALS_GLSL
#define MCME_MCME_HOOK_FRAGMENT_GLOBALS_GLSL
// Hook: a pack's own declarations for the terrain fragment shader - its ins,
// its #moj_imports, its functions. Imported at global scope after
// objmc_fragment, in vanilla's terrain.fsh and Sodium's block_layer_opaque.fsh.
//
// A pack overrides this file; this empty one is the shader base's. Set for it:
// MCME_SECONDS (seconds into the day, seamless under Sodium too),
// MCME_TEXCOORD, MCME_ATLAS_SIZE, MCME_FOG_START, MCME_FOG_COLOR (a vec4);
// MCME_SODIUM and MCME_REGION
// under Sodium. Sampler0 is the block atlas in both. fluid.glsl is imported.
// See docs/shader-base.md.
#endif
