#version 150

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:globals.glsl>
#moj_import <minecraft:chunksection.glsl>
// (no minecraft:light.glsl: 26.2 terrain pipelines don't provide the Lighting
// UBO it declares, and the BLOCK branch of objmc_light.glsl doesn't need it)

uniform sampler2D Sampler0;

in float sphericalVertexDistance;
in float cylindricalVertexDistance;
in vec4 vertexColor;

in vec4 lightColor;
in vec2 texCoord;
in vec2 texCoord2;
in vec3 Pos;
in float transition;

flat in int isCustom;
flat in int noshadow;
flat in int maxLod;
flat in int blendTexture;
flat in vec4 texRect;
// BEGIN COMMENTED 1.21.4 BLOCK-LIGHTING VARYINGS
// flat in float baseBrightness;
// flat in float aoIntensity;
// flat in float customModelNormalShading;
// flat in float underShadowStrength;
// END COMMENTED 1.21.4 BLOCK-LIGHTING VARYINGS

out vec4 fragColor;

// objmc cutout edges, see main(): the alpha the edge sits at - higher thins
// the leaves - and how much of the soft rim it gets in the distance is drawn -
// lower is softer, but lets more of whatever was drawn before (the sky) show
// through.
#define OBJMC_EDGE_CUTOFF 0.5
#define OBJMC_EDGE_KEEP 0.3

// (param renamed sampler -> source: the 26.2 shader compiler rejects `sampler`
// as an identifier, matching vanilla 26.2's naming)
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

    float mipLevelLow = floor(mipLevelExact);
    float mipLevelHigh = mipLevelLow + 1.0;
    float mipBlend = fract(mipLevelExact);

    const vec2 offsets[4] = vec2[](
    vec2(0.125, 0.375),
    vec2(-0.125, -0.375),
    vec2(0.375, -0.125),
    vec2(-0.375, 0.125)
    );

    vec4 rgssColorLow = vec4(0.0);
    vec4 rgssColorHigh = vec4(0.0);
    for (int i = 0; i < 4; ++i) {
        vec2 sampleUV = uv + offsets[i] * pixelSize;
        rgssColorLow += textureLod(source, sampleUV, mipLevelLow);
        rgssColorHigh += textureLod(source, sampleUV, mipLevelHigh);
    }
    rgssColorLow *= 0.25;
    rgssColorHigh *= 0.25;

    vec4 rgssColor = mix(rgssColorLow, rgssColorHigh, mipBlend);

    vec4 nearestColor = sampleNearest(source, uv, pixelSize, du, dv, texelScreenSize);

    return mix(nearestColor, rgssColor, blendFactor);
}

// An objmc model's texture sits in one atlas sprite with its geometry data, and
// is only padded against that data bleeding in for maxLod mip levels (see
// objmc_main.glsl). Sampled like vanilla, but with the gradients shortened so
// the mip level never goes past maxLod; with no padding at all, full size only.
vec4 sampleCustom(vec2 uv, vec2 du, vec2 dv) {
    if (maxLod <= 0)
        return texelFetch(Sampler0, ivec2(uv * textureSize(Sampler0, 0)), 0);
    vec2 pixelSize = 1.0f / TextureSize;
    vec2 texelScreenSize = sqrt(du * du + dv * dv);
    float footprint = max(length(du / pixelSize), length(dv / pixelSize));
    float limit = exp2(float(maxLod));
    if (footprint > limit) {
        du *= limit / footprint;
        dv *= limit / footprint;
    }
    // The texture's left and right edges are its atlas sprite's, so filtering
    // there blends in the neighbouring sprite - the more, the coarser the mip
    // level. Keep the sample a filter footprint (plus sampleNearest's half
    // texel) inside the texture's rectangle, at most its middle.
    vec2 margin = min(vec2(0.5 + min(footprint, limit)) * pixelSize,
                      (texRect.zw - texRect.xy) * 0.5);
    uv = clamp(uv, texRect.xy + margin, texRect.zw - margin);
    return sampleNearest(Sampler0, uv, pixelSize, du, dv, texelScreenSize);
}

vec4 sampleColor(vec2 uv) {
    // Taken before branching: derivatives are undefined in divergent control flow.
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    if (isCustom == 1)
        return sampleCustom(uv, du, dv);
    return UseRgss == 1 ? sampleRGSS(Sampler0, uv, 1.0f / TextureSize) : sampleNearest(Sampler0, uv, 1.0f / TextureSize);
}

void main() {
    vec4 color = mix(sampleColor(texCoord), sampleColor(texCoord2), transition);

    //custom lighting
    #define BLOCK
    #moj_import<objmc_light.glsl>

    // objmc faces always land in the translucent layer: their UVs cover a
    // pointer pixel whose alpha is a row number. Sampling gives a cutout
    // texture's edge a band of partly transparent pixels - sampleNearest
    // blends across texel borders, mip levels average texels - which that
    // layer blends but still writes to depth, so it shows whatever was drawn
    // before (the sky) instead of what lies behind. Up close, where a texel
    // spans more than a screen pixel, the edge is cut hard, exactly along the
    // texture's own pixels. Further off, where texels shrink below a pixel and
    // a hard cut would shimmer, it is sharpened to a one-pixel soft rim whose
    // faintest part is dropped.
    // Taken before any discard and outside any branch: derivatives are
    // undefined next to a discarded pixel, which blackens every edge.
    float alphaWidth = max(fwidth(color.a), 1.0 / 255.0);
    float texelsPerPixel = max(length(dFdx(texCoord) * TextureSize), length(dFdy(texCoord) * TextureSize));
    if (isCustom == 1 && maxLod > 0 && blendTexture == 0) {
        float hard = step(OBJMC_EDGE_CUTOFF, color.a);
        float soft = clamp((color.a - OBJMC_EDGE_CUTOFF) / alphaWidth + 0.5, 0.0, 1.0);
        color.a = mix(hard, soft, clamp(texelsPerPixel - 1.0, 0.0, 1.0));
        if (color.a < OBJMC_EDGE_KEEP) {
            discard;
        }
    }

#ifdef ALPHA_CUTOUT
    if (color.a < ALPHA_CUTOUT) {
        discard;
    }
#endif
    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
}
