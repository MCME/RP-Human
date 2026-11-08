// Hook: a pack's own code at the very end of the terrain vertex shader's
// main(), once gl_Position and the fog distance are set - e.g. to fog a face
// as one thing with MCME_FOG_DISTANCE(its centre).
//
// A pack overrides this file; this empty one is the shader base's. See
// mcme_hook_vertex_globals.glsl and docs/shader-base.md.

// RP-Human: the eye, for the fog (see mcme_hook_vertex_globals.glsl)
fogEye = fogEyeOf(MCME_PROJECTION * MCME_MODELVIEW);
// ...its light under the open sky: the lightmap at this block light and the
// full sky's
#ifdef MCME_SODIUM
fogLight = texture(u_LightTex, vec2(_vert_tex_light_coord.x, 15.5 / 16.0));
#else
fogLight = minecraft_sample_lightmap(Sampler2, ivec2(UV2.x, 248));
#endif
// ...and a fog cloud's faces pushed back (see there)
float fogPush = fogCloudPush(Sampler0, texCoord2);
if (fogPush > 0.0) {
    gl_Position = MCME_PROJECTION * MCME_MODELVIEW * vec4(fogEye + (Pos - fogEye) * (1.0 + fogPush), 1.0);
}
