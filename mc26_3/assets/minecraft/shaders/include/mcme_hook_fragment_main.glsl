// 26.3's copy of assets/minecraft/shaders/include/mcme_hook_fragment_main.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_HOOK_FRAGMENT_MAIN_GLSL
#define MCME_MCME_HOOK_FRAGMENT_MAIN_GLSL
// The base has told which fluid the face is (fluid) and where on it
// (fluidHere), and drawn its water.
// the fog blocks and clouds: the fog the view passes through behind the face,
// lit by the light alone - no shading of its faces, which would show them -
// and as if under the open sky, as much as FOG_OPEN says
if (fluid == FOG_BLOCK) {
    vec4 fog = fogLook(fluidHere, fogEye, Sampler0, MCME_TEXCOORD, MCME_SECONDS, MCME_FOG_COLOR.rgb);
    color = vec4(fog.rgb * mix(lightColor.rgb, fogLight.rgb, FOG_OPEN), fog.a);
}
// ...kept down to 1% opacity, as Sodium keeps every translucent face: vanilla
// drops translucent terrain under 10% (its translucent_terrain pipeline's
// ALPHA_CUTOUT), which would cut this thin fog's soft edges away, face by
// face, into hard-edged blocks. Every other face keeps the pass's own.
#if defined(ALPHA_CUTOUT) && !defined(MCME_SODIUM)
float mcmeCutout = ALPHA_CUTOUT;
#undef ALPHA_CUTOUT
#define ALPHA_CUTOUT (fluid == FOG_BLOCK ? 0.01 : mcmeCutout)
#endif
#endif
