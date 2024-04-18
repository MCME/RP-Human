//objmc
//https://github.com/Godlander/objmc



#define MIP_FADE (0.99)
#define BASE_BRIGHTNESS (0.88)
#define AO_INTENSIITY (0.68)
#define CUSTOM_MODEL_NORMAL_SHADING (0.9)
#define UNDER_SHADOW_STRENGTH (1.0)
#define DISTANCE_DENSITY (1.8)

//default lighting
if (isCustom == 0) {color *= vertexColor * lightColor * ColorModulator;}
//custom lighting
else if (noshadow == 0) {
    //normal from position derivatives
    vec3 normal = normalize(cross(dFdx(Pos), dFdy(Pos)));


    //block lighting
    #ifdef BLOCK
    float angleShading;
	//Very top most faces
    if ((normal.y) > 0.5) {
        angleShading =  normal.y * 0.06 + 0.01;
    }
	//Vert bottom most faces
    else if ((normal.y) < -0.4) {
        angleShading =  normal.y * 0.05 - 0.01  - (1 - UNDER_SHADOW_STRENGTH * underShadowStrength);
    }
	//side faces
	else if ((normal.y) < -0.3) {
        angleShading =  abs(normal.y) * 0.06 + 0.04;
    }
	else if ((normal.y) < 0.3) {
        angleShading =  abs(normal.y) * 0.06 + 0.09;
    }
    else {
        angleShading =  (1 + normal.y) * 0.06 + 0.04;
    }
    float brightness = BASE_BRIGHTNESS * baseBrightness + angleShading;
    color *= vec4(vec3(mix(1.0,brightness,CUSTOM_MODEL_NORMAL_SHADING * customModelNormalShading)), 1.0);
    if (vertexColor.r > 0.92){
        color *= vec4(0.92);
    }
    else {
        color *= mix(vec4(1.0),vertexColor,AO_INTENSIITY * aoIntensity);
    }
    color *= vec4(1.0,1.0,1.0,DISTANCE_DENSITY * distanceDensity);
    if (color.a < MIP_FADE * customMipFade) discard; //keep high to prevent weird black pixels on non leaf block leaf textures
    #endif

    //entity lighting
    #ifdef ENTITY
    //flip normal for gui
    if (isGUI == 1) normal.y *= -1;
    color *= minecraft_mix_light(Light0_Direction, Light1_Direction, normal, overlayColor);
    #endif

    color *= lightColor * ColorModulator;
}