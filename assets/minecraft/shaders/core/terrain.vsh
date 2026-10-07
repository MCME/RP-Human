#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:globals.glsl>
#moj_import <minecraft:chunksection.glsl>
#moj_import <minecraft:projection.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;

uniform sampler2D Sampler0;
uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec4 vertexColor;

out vec4 lightColor;
out vec2 texCoord;
out vec2 texCoord2;
out vec3 Pos;
out float transition;

flat out int isCustom;
flat out int noshadow;
flat out int maxLod;
flat out int blendTexture;
flat out vec4 texRect;
// BEGIN COMMENTED 1.21.4 BLOCK-LIGHTING VARYINGS
// flat out float baseBrightness;
// flat out float aoIntensity;
// flat out float customModelNormalShading;
// flat out float underShadowStrength;
// END COMMENTED 1.21.4 BLOCK-LIGHTING VARYINGS

// the fluids (fluid.glsl): the position, mod 64 blocks
out vec3 fluidWorld;
// water (water.glsl): each corner's brightness, for its shores
out vec4 waterLights;
out vec4 waterWeights;
out vec4 waterHeights;

#moj_import <objmc_tools.glsl>
#moj_import <minecraft:water_corner.glsl>

// The pack's own terrain features hook in through the mcme_hook_*.glsl files,
// shared with Sodium's block_layer_opaque.vsh. These say what the hooks need
// in terms that hold for both.
#define MCME_MODELVIEW ModelViewMat
#define MCME_PROJECTION ProjMat
#define MCME_SECONDS (GameTime * 1200.0)
#define MCME_WORLD_POS (Position + vec3(ChunkPosition))
#define MCME_WORLD_POS_64 (Position + vec3(ChunkPosition & 63))
#define MCME_SECTION_CENTRE (vec3(ChunkPosition - CameraBlockPos) + 8.0)
#define MCME_FOG_DISTANCE(p) sphericalVertexDistance = fog_spherical_distance(p); cylindricalVertexDistance = fog_cylindrical_distance(p)
#moj_import <minecraft:mcme_hook_vertex_globals.glsl>

vec4 minecraft_sample_lightmap(sampler2D lightMap, ivec2 uv) {
    return texture(lightMap, clamp(uv / 256.0, vec2(0.5 / 16.0), vec2(15.5 / 16.0)));
}

void main() {
    texCoord2 = UV0;
    transition = 0;
    isCustom = 0;
    noshadow = 0;
    maxLod = 0;
    blendTexture = 0;
    texRect = vec4(0.0);
    // BEGIN COMMENTED 1.21.4 BLOCK-LIGHTING DEFAULTS
    // baseBrightness = 1.0;
    // aoIntensity = 1.0;
    // customModelNormalShading = 1.0;
    // underShadowStrength = 1.0;
    // END COMMENTED 1.21.4 BLOCK-LIGHTING DEFAULTS
    Pos = Position + (ChunkPosition - CameraBlockPos) + CameraOffset;
    fluidWorld = MCME_WORLD_POS_64;
    waterCorner(gl_VertexID, Color.rgb, Position.y, waterLights, waterWeights, waterHeights);
    vertexColor = Color;
    lightColor = minecraft_sample_lightmap(Sampler2, UV2);
    texCoord = UV0;
    
    //objmc
    #define BLOCK
    #moj_import <objmc_main.glsl>
    #moj_import <minecraft:mcme_hook_vertex_main.glsl>

    gl_Position = ProjMat * ModelViewMat * vec4(Pos, 1.0);
    sphericalVertexDistance = fog_spherical_distance(Pos);
    cylindricalVertexDistance = fog_cylindrical_distance(Pos);
    #moj_import <minecraft:mcme_hook_vertex_end.glsl>
}
