#version 330
#extension GL_ARB_separate_shader_objects : require

// 26.3's copy of the shader base's terrain.fsh (see terrain.vsh). In 26.3
// translucent terrain is drawn three times when the game sorts transparency
// itself (OIT_*): twice for its alpha only, then for its colour. Water has to
// come out with the same alpha in all three, so it is worked out in full each
// time. Keep it in step with the 26.2 one in assets/.

#include <minecraft:fog.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:texture_sampling.glsl>
#include <minecraft:oit.glsl>
#include <minecraft:terrainglobals.glsl>

uniform sampler2D Sampler0;

layout(location = 0) in float sphericalVertexDistance;
layout(location = 1) in float cylindricalVertexDistance;
layout(location = 2) in vec4 vertexColor;
layout(location = 3) in float chunkVisibility;

layout(location = 4) in vec4 lightColor;
layout(location = 5) in vec2 texCoord;
layout(location = 6) in vec2 texCoord2;
layout(location = 7) in vec3 Pos;
layout(location = 8) in float transition;

layout(location = 9) flat in int isCustom;
layout(location = 10) flat in int noshadow;
layout(location = 11) flat in int maxLod;
layout(location = 12) flat in int blendTexture;
layout(location = 13) flat in vec4 texRect;
// the fluids (fluid.glsl)
layout(location = 14) in vec3 fluidWorld;
layout(location = 15) in vec4 waterLights;
layout(location = 16) in vec4 waterWeights;
layout(location = 17) in vec4 waterHeights;

#ifndef OIT_ALPHA_ONLY
layout(location = 0) out vec4 fragColor;
#endif

#include <minecraft:objmc_fragment.glsl>

// the fluids: the water for every pack, the modules the pack turned on
// (lava, ice), and a pack's own in its hooks
#include <minecraft:fluid.glsl>
#include <minecraft:water_config.glsl>
#include <minecraft:water.glsl>
#include <minecraft:mcme_modules.glsl>
#include <minecraft:mcme_lite.glsl>

// The pack's own terrain features (see terrain.vsh)
#define MCME_SECONDS (GameTime * 1200.0)
#define MCME_TEXCOORD texCoord
#define MCME_ATLAS_SIZE vec2(TextureSize)
#define MCME_FOG_START FogRenderDistanceStart
#define MCME_FOG_COLOR FogColor
#include <minecraft:mcme_hook_fragment_globals.glsl>

vec4 sampleColor(vec2 uv) {
    // Taken before branching: derivatives are undefined in divergent control flow.
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    if (isCustom == 1)
        return sampleCustom(uv, du, dv, vec2(TextureSize));
    return UseRgss == 1 ? sampleRGSS(Sampler0, uv, 1.0f / TextureSize) : sampleNearest(Sampler0, uv, 1.0f / TextureSize);
}

vec4 calculateFinalColor(vec4 color) {
    #ifdef OIT_ACCUMULATE
    color = sampleColorForAccumulation(color);
    vec4 fogColor = vec4(FogColor.rgb * color.a, FogColor.a);
    #else
    vec4 fogColor = FogColor;
    #endif
    return apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, fogColor);
}

void main() {
    vec4 color = mix(sampleColor(texCoord), sampleColor(texCoord2), transition);

    //custom lighting
    #define BLOCK
    #include <minecraft:objmc_light.glsl>

    // the fluids: which one this face is, if any, and where on it - taken
    // before branching, as it needs derivatives
    FluidFrame fluidHere = fluidFrame(fluidWorld, Pos, texCoord);
    WaterShore shore = waterShore(waterLights, waterWeights, waterHeights);
#ifdef MCME_LITE
    int fluid = -1;     // the Lite zip: fluids as their textures
#else
    int fluid = isCustom == 0 ? fluidKind(Sampler0, texCoord) : -1;
#endif
    // water: its colour and light as ever, its pattern and opacity its own
    if (fluid == WATER_STILL || fluid == WATER_FLOWING) {
        WaterLook water = waterLook(fluid, fluidHere, MCME_SECONDS, shore);
        vec3 lit = waterTint(vertexColor.rgb) * lightColor.rgb;
        color = vec4(mix(waterMurky(lit, water.murk) * water.shade, WATER_FOAM_COLOR * lightColor.rgb, water.foam), water.alpha);
    }

    #include <minecraft:mcme_modules_main.glsl>
    #include <minecraft:mcme_hook_fragment_main.glsl>
    #ifndef OIT_ALPHA_ONLY
    // A chunk that has just loaded fades in from the fog colour, as in vanilla.
    color = mix(FogColor * vec4(1, 1, 1, color.a), color, chunkVisibility);
    #endif

    objmcEdges(color, texCoord, vec2(TextureSize));

#ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
#endif

    #ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, color.a);
    #else
    fragColor = calculateFinalColor(color);
    #endif
}
