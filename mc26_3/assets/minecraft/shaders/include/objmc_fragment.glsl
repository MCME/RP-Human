// 26.3's copy of assets/minecraft/shaders/include/objmc_fragment.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_OBJMC_FRAGMENT_GLSL
#define MCME_OBJMC_FRAGMENT_GLSL
// objmc's part of the terrain fragment shader, shared by vanilla's terrain.fsh
// and Sodium's block_layer_opaque.fsh (in assets/sodium). The includer
// provides Sampler0 (the block atlas), the varyings isCustom, maxLod,
// blendTexture and texRect, and sampleNearest(source, uv, pixelSize, du, dv,
// texelScreenSize).

// objmc cutout edges, see objmcEdges: the alpha the edge sits at - higher
// thins the leaves - and how much of the soft rim it gets in the distance is
// drawn - lower is softer, but lets more of whatever was drawn before (the
// sky) show through.
#define OBJMC_EDGE_CUTOFF 0.5
#define OBJMC_EDGE_KEEP 0.3

// An objmc model's texture sits in one atlas sprite with its geometry data, and
// is only padded against that data bleeding in for maxLod mip levels (see
// objmc_main.glsl). Sampled like vanilla, but with the gradients shortened so
// the mip level never goes past maxLod; with no padding at all, full size only.
vec4 sampleCustom(vec2 uv, vec2 du, vec2 dv, vec2 atlasSize) {
    if (maxLod <= 0)
        return texelFetch(Sampler0, ivec2(uv * textureSize(Sampler0, 0)), 0);
    vec2 pixelSize = 1.0f / atlasSize;
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

// objmc faces always land in the translucent layer: their UVs cover a pointer
// pixel whose alpha is below 255 (objmc.py's POINTER_ALPHA). Sampling gives a
// cutout texture's edge a band of partly transparent pixels - sampleNearest
// blends across texel borders, mip levels average texels - which that layer
// blends but still writes to depth, so it shows whatever was drawn before (the
// sky) instead of what lies behind. Up close, where a texel spans more than a
// screen pixel, the edge is cut hard, exactly along the texture's own pixels.
// Further off, where texels shrink below a pixel and a hard cut would shimmer,
// it is sharpened to a one-pixel soft rim whose faintest part is dropped.
//
// Call it for every fragment, outside any branch and before any discard:
// derivatives are undefined next to a discarded pixel, which blackens every
// edge.
void objmcEdges(inout vec4 color, vec2 uv, vec2 atlasSize) {
    float alphaWidth = max(fwidth(color.a), 1.0 / 255.0);
    float texelsPerPixel = max(length(dFdx(uv) * atlasSize), length(dFdy(uv) * atlasSize));
    if (isCustom == 1 && maxLod > 0 && blendTexture == 0) {
        float hard = step(OBJMC_EDGE_CUTOFF, color.a);
        float soft = clamp((color.a - OBJMC_EDGE_CUTOFF) / alphaWidth + 0.5, 0.0, 1.0);
        color.a = mix(hard, soft, clamp(texelsPerPixel - 1.0, 0.0, 1.0));
        if (color.a < OBJMC_EDGE_KEEP) {
            discard;
        }
    }
}
#endif
