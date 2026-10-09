#version 330
#extension GL_ARB_separate_shader_objects : require

// 26.3's copy of the shader base's terrain.vsh (the pack's overlay mc26_3,
// see pack.mcmeta): 26.3 compiles shaders to SPIR-V, so #include, not
// #moj_import, a location on every in and out, and gl_VertexIndex. It's also
// compiled with MULTIDRAW_TERRAIN, where the section comes per vertex, and for
// the transparency passes (OIT_*), which have no lightmap. Keep it in step
// with the 26.2 one in assets/.

#include <minecraft:fog.glsl>
#include <minecraft:globals.glsl>
#include <minecraft:projection.glsl>
#include <minecraft:terrainglobals.glsl>
#ifndef MULTIDRAW_TERRAIN
    #include <minecraft:chunksection.glsl>
#endif

layout(location = 0) in vec3 Position;
layout(location = 1) in vec4 Color;
layout(location = 2) in vec2 UV0;
layout(location = 3) in ivec2 UV2;
#ifdef MULTIDRAW_TERRAIN
layout(location = 4) in ivec3 ChunkPosition;
layout(location = 5) in float ChunkVisibility;
#endif

uniform sampler2D Sampler0;
#ifndef OIT_ALPHA_ONLY
uniform sampler2D Sampler2;
#endif

layout(location = 0) out float sphericalVertexDistance;
layout(location = 1) out float cylindricalVertexDistance;
layout(location = 2) out vec4 vertexColor;
layout(location = 3) out float chunkVisibility;

layout(location = 4) out vec4 lightColor;
layout(location = 5) out vec2 texCoord;
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
// water (water.glsl): each corner's brightness, for its shores
layout(location = 15) out vec4 waterLights;
layout(location = 16) out vec4 waterWeights;
layout(location = 17) out vec4 waterHeights;

#include <minecraft:objmc_tools.glsl>
#include <minecraft:water_corner.glsl>

#define MCME_MODELVIEW ModelViewMat
#define MCME_PROJECTION ProjMat
#define MCME_SECONDS (GameTime * 1200.0)
#define MCME_WORLD_POS (Position + vec3(ChunkPosition))
#define MCME_WORLD_POS_64 (Position + vec3(ChunkPosition & 63))
#define MCME_SECTION_CENTRE (vec3(ChunkPosition - CameraBlockPos) + 8.0)
#define MCME_FOG_DISTANCE(p) sphericalVertexDistance = fog_spherical_distance(p); cylindricalVertexDistance = fog_cylindrical_distance(p)
#include <minecraft:mcme_hook_vertex_globals.glsl>

#ifdef OIT_ALPHA_ONLY
// no lightmap in these passes, nor needed: only alpha counts. A hook's look-up
// in it reads white, so hooks needn't know of these passes.
#define minecraft_sample_lightmap(lightMap, uv) vec4(1.0)
#else
vec4 minecraft_sample_lightmap(sampler2D lightMap, ivec2 uv) {
    return texture(lightMap, clamp(uv / 256.0, vec2(0.5 / 16.0), vec2(15.5 / 16.0)));
}
#endif

void main() {
    texCoord2 = UV0;
    transition = 0;
    isCustom = 0;
    noshadow = 0;
    maxLod = 0;
    blendTexture = 0;
    texRect = vec4(0.0);
    Pos = Position + (ChunkPosition - CameraBlockPos) + CameraOffset;
    fluidWorld = MCME_WORLD_POS_64;
    waterCorner(gl_VertexIndex, Color.rgb, Position.y, waterLights, waterWeights, waterHeights);
    vertexColor = Color;
#ifdef OIT_ALPHA_ONLY
    lightColor = vec4(1.0);     // no lightmap in these passes, nor needed: only alpha counts
#else
    lightColor = minecraft_sample_lightmap(Sampler2, UV2);
#endif
    texCoord = UV0;

    //objmc
    #define BLOCK
    #include <minecraft:objmc_main.glsl>
    #include <minecraft:mcme_hook_vertex_main.glsl>

    gl_Position = ProjMat * ModelViewMat * vec4(Pos, 1.0);
    sphericalVertexDistance = fog_spherical_distance(Pos);
    cylindricalVertexDistance = fog_cylindrical_distance(Pos);

    // a section that has just loaded fades in, as in vanilla 26.3
    const float chunkFullyVisibleRange = 16.0;
    chunkVisibility = mix(1.0, ChunkVisibility, clamp((length(Pos) - chunkFullyVisibleRange) / chunkFullyVisibleRange, 0.0, 1.0));
    #include <minecraft:mcme_hook_vertex_end.glsl>
}
