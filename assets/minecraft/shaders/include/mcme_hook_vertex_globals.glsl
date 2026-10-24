// Hook: a pack's own declarations for the terrain vertex shader - its outs,
// its #moj_imports, its functions. Imported at global scope after objmc_tools,
// in vanilla's terrain.vsh and Sodium's block_layer_opaque.vsh alike.
//
// A pack overrides this file to add terrain features of its own; this empty
// one is the shader base's (ResourcePackScripts/shaderBase). Import with the
// namespace (<minecraft:...>), as Sodium's shaders are in another one.
//
// Set for every hook: MCME_MODELVIEW, MCME_SECONDS, MCME_WORLD_POS,
// MCME_WORLD_POS_64, MCME_SECTION_CENTRE, MCME_FOG_DISTANCE(pos);
// MCME_SODIUM and MCME_REGION under Sodium. See docs/shader-base.md.

// RP-Human: the fog blocks and clouds (fog_block.glsl) trace the view
// from the eye, which isn't where Pos puts the camera: view bobbing and the
// tilt on being hurt move it in the camera's matrices. fogEye is the eye's
// place in Pos's terms - where the view's matrices bring every ray together:
// the point that ProjMat * ModelViewMat sends to x = y = w = 0.
flat out vec3 fogEye;

// ...and lit as if under the open sky, by the day's light and any lamp's, so
// that it doesn't darken in the shade - under an overhang, in a cave - as
// its faces would, each lit by the block beside it (FOG_OPEN).
out vec4 fogLight;

vec3 fogEyeOf(mat4 m) {
    vec4 r0 = vec4(m[0][0], m[1][0], m[2][0], m[3][0]);
    vec4 r1 = vec4(m[0][1], m[1][1], m[2][1], m[3][1]);
    vec4 r3 = vec4(m[0][3], m[1][3], m[2][3], m[3][3]);
    return inverse(transpose(mat3(r0.xyz, r1.xyz, r3.xyz))) * -vec3(r0.w, r1.w, r3.w);
}

// A fog cloud's faces (fog_block.glsl) are drawn a hair further from the eye
// than they are, so that where one lies on a block's face - the cloud's
// blocks fill whatever stands in it - the block's face hides it, rather than
// the two flickering through each other. Further by a share of the distance,
// as depth's precision is: 0.1% to 0.2%, 5 to 10 thousandths of a block 5
// blocks away - how much by the block's place in its cloud, the same over
// each face, so that two clouds that overlap, whose blocks there are in
// different places in each, don't flicker through each other either: one
// is drawn behind the other, in all but one block in 16. Told by the texel
// at the corner, or the one before it (Sodium's texture coordinates can be a
// texel off): all but clear (alpha 1) and blue's bits 2 to 4 the cloud's
// (FOG_CLOUD).
#define FOG_CLOUD_PUSH 0.001

float fogCloudPush(sampler2D atlas, vec2 uv) {
    ivec2 t = ivec2(floor(uv * vec2(textureSize(atlas, 0))));
    for (int k = 0; k < 2; k++) {
        ivec4 c = ivec4(texelFetch(atlas, t - ivec2(k), 0) * 255.0 + 0.5);
        if (c.a != 1 || ((c.b >> 2) & 7) != 2) continue;
        uint h = uint(((c.r >> 2) & 7) + 5 * ((c.g >> 2) & 7) + 25 * ((c.b >> 5) & 7)) * 2654435761u;
        h ^= h >> 15;
        h *= 0x5bd1e995u;
        h ^= h >> 13;
        return FOG_CLOUD_PUSH * (1.0 + float(h & 15u) / 15.0);
    }
    return 0.0;
}
