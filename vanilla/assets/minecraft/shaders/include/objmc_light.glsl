//objmc
//https://github.com/Godlander/objmc

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
    float vertical = sign(normal.y) * 0.3 + 0.7;
    float horizontal = abs(normal.z) * 0.25 + 0.5;
    float brightness = mix(horizontal, vertical, abs(normal.y));
    color *= vec4(vec3(brightness), 1.0);
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