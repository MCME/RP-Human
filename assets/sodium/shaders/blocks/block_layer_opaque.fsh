#version 330 core

// Sodium 0.9.2's chunk fragment shader with objmc added (see
// block_layer_opaque.vsh). Sodium's own work is unchanged: its v_Color, the
// vertex colour times the light, is objmc_light.glsl's vertexColor and
// lightColor multiplied in for every face that isn't objmc's.

#moj_import <sodium:globals.glsl>
#moj_import <sodium:fog.glsl>
#moj_import <sodium:chunk_material.glsl>

in vec2 v_TexCoord; // The interpolated block texture coordinates
in vec2 v_FragDistance; // The fragment's distance from the camera (cylindrical and spherical)
in float fadeFactor;

// objmc
in vec4 vertexColor;
in vec4 lightColor;
in vec2 texCoord2;
in vec3 Pos;
in float transition;
flat in int isCustom;
flat in int noshadow;
flat in int maxLod;
flat in int blendTexture;
flat in vec4 texRect;
// the fluids (fluid.glsl)
in vec3 fluidWorld;
in vec4 waterLights;
in vec4 waterWeights;
in vec4 waterHeights;

uniform sampler2D u_BlockTex; // The block texture
// the light map, for the time of day core/lightmap.fsh hides in it
// (mcme_clock.glsl): Sodium's own clock restarts with each region, which
// would part whatever moves at their edges
uniform sampler2D u_LightTex;

out vec4 fragColor; // The output fragment for the color framebuffer

vec4 sampleNearest(sampler2D source, vec2 uv, vec2 pixelSize, vec2 du, vec2 dv, vec2 texelScreenSize) {
    // Convert our UV back up to texel coordinates and find out how far over we are from the center of each pixel
    vec2 uvTexelCoords = uv / pixelSize;
    vec2 texelCenter = round(uvTexelCoords) - 0.5f;
    vec2 texelOffset = uvTexelCoords - texelCenter;

    // Move our offset closer to the texel center based on texel size on screen
    texelOffset = (texelOffset - 0.5f) * pixelSize / texelScreenSize + 0.5f;
    texelOffset = clamp(texelOffset, 0.0f, 1.0f);

    uv = (texelCenter + texelOffset) * pixelSize;
    return textureGrad(source, uv, du, dv);
}

vec4 sampleNearest(sampler2D source, vec2 uv, vec2 pixelSize) {
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    vec2 texelScreenSize = sqrt(du * du + dv * dv);
    return sampleNearest(source, uv, pixelSize, du, dv, texelScreenSize);
}

// Rotated Grid Super-Sampling
vec4 sampleRGSS(sampler2D source, vec2 uv, vec2 pixelSize) {
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);

    vec2 texelScreenSize = sqrt(du * du + dv * dv);
    float maxTexelSize = max(texelScreenSize.x, texelScreenSize.y);

    float minPixelSize = min(pixelSize.x, pixelSize.y);

    float transitionStart = minPixelSize * 1.0;
    float transitionEnd = minPixelSize * 2.0;
    float blendFactor = smoothstep(transitionStart, transitionEnd, maxTexelSize);

    float duLength = length(du);
    float dvLength = length(dv);
    float minDerivative = min(duLength, dvLength);
    float maxDerivative = max(duLength, dvLength);

    float effectiveDerivative = sqrt(minDerivative * maxDerivative);

    float mipLevelExact = max(0.0, log2(effectiveDerivative / minPixelSize));

    const vec2 offsets[4] = vec2[](
    vec2(0.125, 0.375),
    vec2(-0.125, -0.375),
    vec2(0.375, -0.125),
    vec2(-0.375, 0.125)
    );

    vec4 rgssColor = vec4(0.0);
    for (int i = 0; i < 4; ++i) {
        vec2 sampleUV = uv + offsets[i] * pixelSize;
        rgssColor += textureLod(source, sampleUV, mipLevelExact);
    }
    rgssColor *= 0.25;

    vec4 nearestColor = sampleNearest(source, uv, pixelSize, du, dv, texelScreenSize);

    return mix(nearestColor, rgssColor, blendFactor);
}

#define Sampler0 u_BlockTex
#moj_import <minecraft:objmc_fragment.glsl>

// the fluids: the water for every pack, the modules the pack turned on
// (lava, ice), and a pack's own in its hooks
#moj_import <minecraft:mcme_clock.glsl>
#moj_import <minecraft:fluid.glsl>
#moj_import <minecraft:water_config.glsl>
#moj_import <minecraft:water.glsl>
#moj_import <minecraft:mcme_modules.glsl>
#moj_import <minecraft:mcme_lite.glsl>

// The pack's own terrain features (see block_layer_opaque.vsh)
#define MCME_SODIUM
#define MCME_SECONDS mcmeClockSeconds(u_LightTex)
#define MCME_REGION vec3(128.0, 64.0, 128.0)
#define MCME_TEXCOORD v_TexCoord
#define MCME_ATLAS_SIZE (1.0 / u_TexelSize)
#define MCME_FOG_START u_RenderFog.x
#define MCME_FOG_COLOR u_FogColor
#moj_import <minecraft:mcme_hook_fragment_globals.glsl>

vec4 sampleColor(vec2 uv) {
    // Taken before branching: derivatives are undefined in divergent control flow.
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    if (isCustom == 1)
        return sampleCustom(uv, du, dv, 1.0 / u_TexelSize);
    return u_UseRGSS ? sampleRGSS(u_BlockTex, uv, u_TexelSize) : sampleNearest(u_BlockTex, uv, u_TexelSize);
}

void main() {
    vec4 color = mix(sampleColor(v_TexCoord), sampleColor(texCoord2), transition);

    // Apply per-vertex color modulator - objmc's lighting for its models
#define BLOCK
#define SODIUM
#moj_import <minecraft:objmc_light.glsl>

    // the fluids: which one this face is, if any, and where on it - taken
    // before branching, as it needs derivatives
    FluidFrame fluidHere = fluidFrame(fluidWorld, Pos, v_TexCoord);
    WaterShore shore = waterShore(waterLights, waterWeights, waterHeights);
#ifdef MCME_LITE
    int fluid = -1;     // the Lite zip: fluids as their textures
#else
    int fluid = isCustom == 0 ? fluidKind(u_BlockTex, v_TexCoord) : -1;
#endif
    // water: its colour and light as ever, its pattern and opacity its own;
    // foam along its shores, from smooth lighting
    if (fluid == WATER_STILL || fluid == WATER_FLOWING) {
        WaterLook water = waterLook(fluid, fluidHere, MCME_SECONDS, shore);
        vec3 lit = waterTint(vertexColor.rgb) * lightColor.rgb;
        color = vec4(mix(waterMurky(lit, water.murk) * water.shade, WATER_FOAM_COLOR * lightColor.rgb, water.foam), water.alpha);
    }

#moj_import <minecraft:mcme_modules_main.glsl>
#moj_import <minecraft:mcme_hook_fragment_main.glsl>

    objmcEdges(color, v_TexCoord, 1.0 / u_TexelSize);

#ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
#endif

    fragColor = _linearFog(color, v_FragDistance, u_FogColor, u_EnvironmentFog, u_RenderFog, fadeFactor);
}
