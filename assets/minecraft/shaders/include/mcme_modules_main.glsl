// The shader base's modules the pack turned on (mcme_modules.glsl), drawn
// over their own faces: in the terrain fragment shaders' main(), after the
// water, before the pack's hooks - which may still draw over them. The base
// has told which fluid the face is (fluid), where on it (fluidHere) and its
// corners' occlusion (shore).

#ifdef MCME_MODULE_LAVA
// lava: its own light, with only the game's shading of its sides
if (fluid == LAVA_STILL || fluid == LAVA_FLOWING) {
    color = vec4(lavaColor(fluid, fluidHere, MCME_SECONDS) * mix(vec3(1.0), vertexColor.rgb, LAVA_SHADING), 1.0);
}
#endif

#ifdef MCME_MODULE_ICE
// ice: seen into, lit and shaded as any block - its frost by its face's own
// shade, not the occlusion that puts it there
if (fluid == ICE) {
    IceLook ice = iceLook(fluidHere, MCME_SECONDS, shore);
    vec3 open = vertexColor.rgb / max(max(vertexColor.r, max(vertexColor.g, vertexColor.b)), 1.0e-3) * shore.open;
    color = vec4(ice.color * mix(vertexColor.rgb, open, ice.frost) * lightColor.rgb, ice.alpha);
}
#endif
