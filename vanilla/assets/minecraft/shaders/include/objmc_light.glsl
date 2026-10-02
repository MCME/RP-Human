//objmc
//https://github.com/Godlander/objmc

// How much of the client's ambient occlusion objmc models get: 0 none, 1 all.
#define OBJMC_AO_STRENGTH 0.75
// How much brighter texels are spared from it, keeping highlights: 0 none.
// Above 0 the texture's bright spots keep their brightness in shade, which
// shows its tiling across a canopy.
#define OBJMC_AO_HIGHLIGHTS 0.0
// Overall brightness of objmc models, before the lightmap: 1.0 unchanged.
#define OBJMC_BRIGHTNESS 1.0
// The occlusion the client gives a face nothing occludes, when its block has a
// full collision box (leaves): such a block counts itself as one of the four
// samples it averages, 0.2 against 1.0 for open air. Divided out, so open
// leaves are at full brightness and shade has the whole range; other blocks
// reach 1 earlier and are capped there.
#define OBJMC_AO_OPEN 0.7
// The same for upward faces. Their carriers lie flat (objmc.py's CARRIER_FLAT)
// so the client occludes them from the layer above, which stands in for the
// block itself: open is 1.0 there. Lower brightens canopy tops, cutting their
// lightest shading first; higher darkens them evenly.
#define OBJMC_AO_OPEN_UP 1.1

//default lighting
if (isCustom == 0) {
#ifndef EMISSIVE
    color *= lightColor;
#endif
    color *= vertexColor;
}
//custom lighting
else if (noshadow == 0) {
    //normal from position derivatives
    vec3 normal = normalize(cross(dFdx(Pos), dFdy(Pos)));

    //block lighting
#ifdef BLOCK
    // Vanilla's face shading - up 1.0, down 0.5, north/south 0.8, east/west
    // 0.6 - blended by the true normal, as Sodium shades an .obj.
    vec3 n2 = normal * normal;
    float brightness = n2.x * 0.6 + n2.z * 0.8 + n2.y * (normal.y > 0.0 ? 1.0 : 0.5);
    color *= vec4(vec3(brightness), 1.0);

    // Ambient occlusion. The client works it out for each corner of the
    // carrier element's face - which sits where the real face does, see
    // objmc.py's carrier - from the blocks around, and bakes it into
    // vertexColor along with that face's own cardinal shading. The carrier
    // faces the true normal's dominant axis (objmc.py's classify_direction), so
    // that shading is divided back out, leaving the occlusion. Capped at 1, so
    // a mismatch only weakens it.
    vec3 an = abs(normal);
    bool facesUp = an.y >= an.x && an.y >= an.z && normal.y > 0.0;
#ifdef SODIUM
    // Sodium shades a face that isn't along an axis by its true normal,
    // blending each axis's shade as `brightness` above does.
    float carrierShade = brightness;
#else
    float carrierShade = (an.y >= an.x && an.y >= an.z) ? (normal.y > 0.0 ? 1.0 : 0.5)
                       : (an.x >= an.z ? 0.6 : 0.8);
#endif
    float open = facesUp ? OBJMC_AO_OPEN_UP : OBJMC_AO_OPEN;
    float occlusion = clamp(vertexColor.r / carrierShade / open, 0.0, 1.0);
    // Bright texels are darkened less, so a texture's highlights keep their
    // contrast in shade instead of sinking with the rest.
    float highlight = max(color.r, max(color.g, color.b));
    color.rgb *= mix(mix(1.0, occlusion, OBJMC_AO_STRENGTH), 1.0, OBJMC_AO_HIGHLIGHTS * highlight);
    color.rgb *= OBJMC_BRIGHTNESS;
#endif

// BEGIN COMMENTED 1.21.4 BLOCK-LIGHTING RESTORATION
// The following code is intentionally disabled. It documents the lighting
// code that was previously added for the 1.21.4 metadata/varying contract.
// It must remain commented because terrain.vsh, terrain.fsh, and
// objmc_main.glsl are restored to the 26.2 interface above.
// #define BASE_BRIGHTNESS (0.88)
// #define AO_INTENSITY (0.68)
// #define CUSTOM_MODEL_NORMAL_SHADING (0.9)
// #define UNDER_SHADOW_STRENGTH (1.0)
// flat out/in float baseBrightness;
// flat out/in float aoIntensity;
// flat out/in float customModelNormalShading;
// flat out/in float underShadowStrength;
// float angleShading;
// if (normal.y > 0.5) {
//     angleShading = normal.y * 0.06 + 0.01;
// } else if (normal.y < -0.4) {
//     if (vertexColor.r > 0.5) {
//         angleShading = normal.y * 0.36 + 0.01;
//     } else {
//         angleShading = normal.y * 0.05 - 0.01
//             - (1.0 - UNDER_SHADOW_STRENGTH * underShadowStrength);
//     }
// } else if (normal.y < -0.3) {
//     angleShading = abs(normal.y) * 0.06 + 0.04;
// } else if (normal.y < 0.3) {
//     angleShading = abs(normal.y) * 0.06 + 0.09;
// } else {
//     angleShading = (1.0 + normal.y) * 0.06 + 0.04;
// }
// float brightness = BASE_BRIGHTNESS * baseBrightness + angleShading;
// color *= vec4(vec3(mix(1.0, brightness,
//     CUSTOM_MODEL_NORMAL_SHADING * customModelNormalShading)), 1.0);
// if (vertexColor.r > 0.92) {
//     color *= vec4(0.92);
// } else {
//     color *= mix(vec4(1.0), vertexColor, AO_INTENSITY * aoIntensity);
// }
// END COMMENTED 1.21.4 BLOCK-LIGHTING RESTORATION

    color *= lightColor;
}