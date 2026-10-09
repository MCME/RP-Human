// 26.3's copy of assets/minecraft/shaders/include/fog.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_FOG_GLSL
#define MCME_FOG_GLSL

layout(std140) uniform Fog {
    vec4 FogColor;
    float FogEnvironmentalStart;
    float FogEnvironmentalEnd;
    float FogRenderDistanceStart;
    float FogRenderDistanceEnd;
    float FogSkyEnd;
    float FogCloudsEnd;
};

float linear_fog_value(float vertexDistance, float fogStart, float fogEnd) {
    if (vertexDistance <= fogStart) {
        return 0.0;
    } else if (vertexDistance >= fogEnd) {
        return 1.0;
    }
    return (vertexDistance - fogStart) / (fogEnd - fogStart);
}

// MCME has no fog in the open: neither the render distance's, which hides the
// far terrain, nor 26.x's haze over the land (its "environmental" fog in air,
// at least 768 blocks deep even in rain). It keeps the fog that ends near:
// under water (96 blocks at most), in lava (1, or 5 resisting fire), in
// powder snow (2), blinded or in darkness - and the Nether's (96). It goes by
// where the game's own environmental fog ends, whatever the shader passes:
// the sky passes its own distances.
float total_fog_value(float sphericalVertexDistance, float cylindricalVertexDistance, float environmentalStart, float environmentalEnd, float renderDistanceStart, float renderDistanceEnd) {
    float near = 1.0 - smoothstep(96.0, 160.0, FogEnvironmentalEnd);
    return linear_fog_value(sphericalVertexDistance, environmentalStart, environmentalEnd) * near;
}

vec4 apply_fog(vec4 inColor, float sphericalVertexDistance, float cylindricalVertexDistance, float environmentalStart, float environmentalEnd, float renderDistanceStart, float renderDistanceEnd, vec4 fogColor) {
    float fogValue = total_fog_value(sphericalVertexDistance, cylindricalVertexDistance, environmentalStart, environmentalEnd, renderDistanceStart, renderDistanceEnd);
    return vec4(mix(inColor.rgb, fogColor.rgb, fogValue * fogColor.a), inColor.a);
}

float fog_spherical_distance(vec3 pos) {
    return length(pos);
}

float fog_cylindrical_distance(vec3 pos) {
    float distXZ = length(pos.xz);
    float distY = abs(pos.y);
    return max(distXZ, distY);
}
#endif
