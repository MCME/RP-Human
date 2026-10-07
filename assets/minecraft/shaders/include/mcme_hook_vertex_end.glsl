// Hook: a pack's own code at the very end of the terrain vertex shader's
// main(), once gl_Position and the fog distance are set - e.g. to fog a face
// as one thing with MCME_FOG_DISTANCE(its centre).
//
// A pack overrides this file; this empty one is the shader base's. See
// mcme_hook_vertex_globals.glsl and docs/shader-base.md.
