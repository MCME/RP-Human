// Hook: a pack's own code in the terrain fragment shader's main(), right after
// objmc's lighting and before the alpha cutout and fog. `color` is the lit
// colour, the base's water already drawn into it; vertexColor, lightColor and
// Pos are in scope, and for a pack's own fluids fluid and fluidHere
// (fluid.glsl: which fluid the face is, if any, and where on it) and shore
// (water.glsl: its corners' smooth-lighting occlusion). Nothing has been
// discarded yet, so derivatives (dFdx, fwidth) still work outside branches.
//
// A pack overrides this file; this empty one is the shader base's. See
// mcme_hook_fragment_globals.glsl and docs/shader-base.md.
