// RP-Human's own terrain features, hooked into the shader base's terrain
// fragment shaders - vanilla's and Sodium's (ResourcePackScripts/shaderBase,
// docs/shader-base.md). The base's fluid.glsl, which the fog block builds on,
// is imported.

// the fog blocks and clouds, traced from the eye (mcme_hook_vertex_globals.glsl)
flat in vec3 fogEye;
in vec4 fogLight;
#moj_import <minecraft:fog_block_config.glsl>
#moj_import <minecraft:fog_block.glsl>
