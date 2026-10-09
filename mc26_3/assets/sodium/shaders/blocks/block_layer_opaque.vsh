#version 330
#extension GL_ARB_separate_shader_objects : require

// 26.3's copy of the shader base's block_layer_opaque.vsh (the pack's overlay
// mc26_3, see pack.mcmeta), on Sodium 0.9.2 for 26.3: Sodium compiles through
// 26.3's shaderc to SPIR-V too, so #include, not #moj_import, a location on
// every in and out, and gl_VertexIndex. It's also compiled for 26.3's
// transparency passes (OIT_*), as vanilla's terrain is. Keep it in step with
// the 26.2 one in assets/.

#include <sodium:globals.glsl>
#include <sodium:fog.glsl>
#include <sodium:chunk_vertex.glsl>

layout(location = 1) out vec2 v_TexCoord;

#ifdef USE_FOG
layout(location = 2) out vec2 v_FragDistance;
layout(location = 3) out float fadeFactor;
#endif

uniform isamplerBuffer u_SectionTimeInfo;

#ifdef VULKAN
layout(push_constant) uniform PC {
    vec3 u_RegionOffset;
    int u_CurrentTime;
    uint u_RegionID;
};
#else
uniform vec3 u_RegionOffset;
uniform int u_CurrentTime;
uniform uint u_RegionID;
#endif

// The light map texture sampler. Sodium binds it in every pass, so it's kept
// in the alpha-only ones too, where Sodium's own shader leaves it out.
uniform sampler2D u_LightTex;

// objmc: the block atlas, which holds each model's geometry. Sodium's v_Color
// is split into its colour and light, as objmc lights its models itself.
uniform sampler2D u_BlockTex;
layout(location = 4) out vec4 vertexColor;
layout(location = 5) out vec4 lightColor;
layout(location = 6) out vec2 texCoord2;
layout(location = 7) out vec3 Pos;
layout(location = 8) out float transition;
layout(location = 9) flat out int isCustom;
layout(location = 10) flat out int noshadow;
layout(location = 11) flat out int maxLod;
layout(location = 12) flat out int blendTexture;
layout(location = 13) flat out vec4 texRect;
// the fluids (fluid.glsl): the position, mod 64 blocks
layout(location = 14) out vec3 fluidWorld;
// water (water.glsl): each corner's brightness - with its smooth lighting's
// occlusion - for its shores
layout(location = 15) out vec4 waterLights;
layout(location = 16) out vec4 waterWeights;
layout(location = 17) out vec4 waterHeights;
// a pack's hooks' own (mcme_hook_vertex_globals.glsl) are numbered from 18, as
// in vanilla's terrain.vsh

#define Sampler0 u_BlockTex
#include <minecraft:objmc_tools.glsl>
#include <minecraft:water_corner.glsl>

// The pack's own terrain features, as in vanilla's terrain.vsh. Sodium knows
// positions only within a region of 128 x 64 x 128 blocks, and its clock is
// milliseconds since the region was made.
#define MCME_SODIUM
#define MCME_REGION vec3(128.0, 64.0, 128.0)
#define MCME_MODELVIEW u_ModelViewMatrix
#define MCME_PROJECTION u_ProjectionMatrix
#define MCME_SECONDS (float(u_CurrentTime) / 1000.0)
#define MCME_WORLD_POS (_vert_position + _get_draw_translation(_draw_id))
// regions lie on the world's grid of 128 x 64 x 128 blocks, so this matches
// vanilla's
#define MCME_WORLD_POS_64 (_vert_position + mod(_get_draw_translation(_draw_id), 64.0))
#define MCME_SECTION_CENTRE (translation + 8.0)
#ifdef USE_FOG
#define MCME_FOG_DISTANCE(p) v_FragDistance = getFragDistance(p)
#else
#define MCME_FOG_DISTANCE(p)
#endif
#include <minecraft:mcme_hook_vertex_globals.glsl>

uvec3 _get_relative_chunk_coord(uint pos) {
    // Packing scheme is defined by LocalSectionIndex
    return uvec3(pos) >> uvec3(5u, 0u, 2u) & uvec3(7u, 3u, 7u);
}

vec3 _get_draw_translation(uint pos) {
    return _get_relative_chunk_coord(pos) * vec3(16.0);
}

void main() {
    _vert_init();

    // Transform the chunk-local vertex position into world model space
    vec3 translation = u_RegionOffset + _get_draw_translation(_draw_id);
    Pos = _vert_position + translation;
    fluidWorld = MCME_WORLD_POS_64;
    waterCorner(gl_VertexIndex, _vert_color.rgb, _vert_position.y, waterLights, waterWeights, waterHeights);

    vertexColor = _vert_color;
    lightColor = texture(u_LightTex, _vert_tex_light_coord);
    v_TexCoord = (_vert_tex_diffuse_coord_bias * u_TexCoordShrink) + _vert_tex_diffuse_coord; // FMA for precision
    texCoord2 = v_TexCoord;
    noshadow = 0;
    maxLod = 0;
    blendTexture = 0;
    texRect = vec4(0.0);

    // objmc, in Sodium's terms. A carrier's texture coordinate is read before
    // Sodium's shrink: its rounding keeps it inside the pointer pixel.
#define UV0 _vert_tex_diffuse_coord
#define OBJMC_UV_BIAS _vert_tex_diffuse_coord_bias
#define Position _vert_position
#define OBJMC_SECTION_OFFSET translation
#define texCoord v_TexCoord
#define GameTime 0.0
#define BLOCK
#include <minecraft:objmc_main.glsl>
#include <minecraft:mcme_hook_vertex_main.glsl>
#undef texCoord

#ifdef USE_FOG
    v_FragDistance = getFragDistance(Pos);

    int chunkId = int(_draw_id);
    int chunkFade = texelFetch(u_SectionTimeInfo, int((u_RegionID * 256u) + uint(chunkId))).r;
    int fadeTime = u_CurrentTime - chunkFade;
    float elapsed = float(fadeTime);
    float fade = clamp(float(u_CurrentTime - chunkFade) * u_FadePeriodInv, 0.0, 1.0);
    fadeFactor = (chunkFade < 0) ? 1.0 : fade;
#endif

    // Transform the vertex position into model-view-projection space
    gl_Position = u_ProjectionMatrix * u_ModelViewMatrix * vec4(Pos, 1.0);
#include <minecraft:mcme_hook_vertex_end.glsl>
}
