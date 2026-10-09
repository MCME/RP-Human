// 26.3's copy of assets/minecraft/shaders/include/mcme_hook_vertex_globals.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_HOOK_VERTEX_GLOBALS_GLSL
#define MCME_MCME_HOOK_VERTEX_GLOBALS_GLSL
// Hook: a pack's own declarations for the terrain vertex shader - its outs,
// its #moj_imports, its functions. Imported at global scope after objmc_tools,
// in vanilla's terrain.vsh and Sodium's block_layer_opaque.vsh alike.
//
// A pack overrides this file to add terrain features of its own; this empty
// one is the shader base's (ResourcePackScripts/shaderBase). Import with the
// namespace (<minecraft:...>), as Sodium's shaders are in another one.
//
// Set for every hook: MCME_MODELVIEW, MCME_SECONDS, MCME_WORLD_POS,
// MCME_WORLD_POS_64, MCME_SECTION_CENTRE, MCME_FOG_DISTANCE(pos);
// MCME_SODIUM and MCME_REGION under Sodium. See docs/shader-base.md.
#endif
