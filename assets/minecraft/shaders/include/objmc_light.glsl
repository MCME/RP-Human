//objmc
//https://github.com/Godlander/objmc

//default lighting
if (isCustom == 0) {color *= vertexColor * lightColor * ColorModulator;}
//custom lighting
else if (noshadow == 0) {
    //normal from position derivatives
    vec3 normal = normalize(cross(dFdx(Pos), dFdy(Pos)));

    //block lighting
    #ifdef BLOCK
    float vertical = sign(normal.y) * 0.22 + 0.5;
    float horizontal = abs(normal.z) * 0.15 + 0.7;
	float undershadow =  abs(normal.y);
	if ((normal.y) < 0.7) {
	    undershadow = undershadow * 0.69;
	}
    float brightness = 0.03 + mix(horizontal, vertical, undershadow);
    color *= vec4(vec3(brightness), 1.0);
    #endif
	

    //entity lighting
    #ifdef ENTITY
    //flip normal for gui
    if (isGUI == 1) normal.y *= -1;
    color *= minecraft_mix_light(Light0_Direction, Light1_Direction, normal, overlayColor);
    #endif
    vec4 lightColor2 = lightColor;
	// Assuming lightColor2 is an RGB vec4 representing the light color
	vec3 lightColorRGB = lightColor2.rgb;

	// Calculate the luminance of the fragment color
	float luminance = dot(lightColor.rgb, vec3(0.199, 0.587, 0.414));

	// Define a factor to control the amount of darkening in darker areas
	float darkeningFactor = 0.4; // Adjust this factor as needed

	// Apply darkening only in darker areas (luminance < threshold)
	if (luminance < 20.0) {
		lightColorRGB *= darkeningFactor;
	}

	// Reconstruct the final color with the modified lightColor2
	//lightColor2.rgb = lightColorRGB;
	//lightColor2.w *= 1.8;
    color *= lightColor2 * ColorModulator;
}