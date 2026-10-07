#version 330 core

// Sodium 0.9.2's chunk vertex shader with objmc added, so that the vanilla
// pack's objmc models show with Sodium too. Sodium's own work is unchanged;
// objmc_main.glsl is shared with vanilla's terrain.vsh, Sodium's names mapped
// onto vanilla's below. Sodium's shaders are internal to it: compare against
// the jar's assets/sodium/shaders on every Sodium update.
//
// Sodium's includes are copied beside these (shaders/include) and must be
// re-copied with them: vanilla resolves every #moj_import in every pack shader
// whether or not Sodium is there, and one it can't find fails the whole pack.
// Never #include them instead: Sodium compiles through vanilla's preprocessor,
// which only expands #moj_import.

#moj_import <sodium:globals.glsl>
#moj_import <sodium:fog.glsl>
#moj_import <sodium:chunk_vertex.glsl>

out vec2 v_TexCoord;

#ifdef USE_FOG
out vec2 v_FragDistance;
out float fadeFactor;
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

uniform sampler2D u_LightTex; // The light map texture sampler

// objmc: the block atlas, which holds each model's geometry. Sodium's v_Color
// is split into its colour and light, as objmc lights its models itself.
uniform sampler2D u_BlockTex;
out vec4 vertexColor;
out vec4 lightColor;
out vec2 texCoord2;
out vec3 Pos;
out float transition;
flat out int isCustom;
flat out int noshadow;
flat out int maxLod;
flat out int blendTexture;
flat out vec4 texRect;
// the fluids (fluid.glsl): the position, mod 64 blocks
out vec3 fluidWorld;
// water (water.glsl): each corner's brightness - with its smooth lighting's
// occlusion - for its shores
out vec4 waterLights;
out vec4 waterWeights;
out vec4 waterHeights;

#define Sampler0 u_BlockTex
#moj_import <minecraft:objmc_tools.glsl>
#moj_import <minecraft:water_corner.glsl>

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
#moj_import <minecraft:mcme_hook_vertex_globals.glsl>

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
    waterCorner(gl_VertexID, _vert_color.rgb, Pos.y, waterLights, waterWeights, waterHeights);

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
#moj_import <minecraft:objmc_main.glsl>
#moj_import <minecraft:mcme_hook_vertex_main.glsl>
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
#moj_import <minecraft:mcme_hook_vertex_end.glsl>
}
