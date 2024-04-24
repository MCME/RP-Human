#version 150

#moj_import <light.glsl>
#moj_import <fog.glsl>
uniform sampler2D Sampler0;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;

in float vertexDistance;
in vec4 vertexColor;
in vec4 lightColor;
in vec2 texCoord;
in vec2 texCoord2;
in vec3 Pos;
in float transition;

flat in int isCustom;
flat in int noshadow;

flat in float customMipFade;
flat in float baseBrightness;
flat in float aoIntensity;
flat in float customModelNormalShading;
flat in float underShadowStrength;
flat in float distanceDensity;

#define USE_CUSTOM_MIP (true)
#define MIP_DISTANCE_NEAR (30.0)
#define MIP_DISTANCE_FAR (80.0)
#define MIP_DISTANCE_VERY_FAR (100.0)

out vec4 fragColor;

vec4 applyEdgeFilterAndMipmapping(sampler2D Sampler0, vec2 mipCoord, vec2 atlasSize) {
    vec2 textureSize = atlasSize;

	// Initialize variables for blending
	vec4 blendedColor = vec4(0.0);
	float totalAlpha = 0.0;

	// Loop through neighboring pixels for blending
	for (float dx = -1.0; dx <= 1.0; dx++) {
		for (float dy = -1.0; dy <= 1.0; dy++) {
			vec2 offset = vec2(dx, dy) / textureSize; // Adjust offset to match texture coordinates
			vec4 neighborColor = texture(Sampler0, mipCoord + offset);

			// Accumulate alpha values for blending
			float alpha = neighborColor.a;
			blendedColor += neighborColor * alpha;
			totalAlpha += alpha;
		}
	}

	// Normalize the blended color
	if (totalAlpha > 0.0) {
		blendedColor /= totalAlpha;
	}

	return blendedColor;
}


void main() {
    //vec4 color = mix(texture(Sampler0, texCoord), texture(Sampler0, texCoord2), transition);
    vec2 atlasSize = textureSize(Sampler0, 0);

    vec4 color;
	color = texture(Sampler0, texCoord);
	if (color.a > 0.8) color;
	else{
		vec2 mipCoord = texCoord;
		float mipDist = vertexDistance;
		color = texture(Sampler0, mipCoord);

		float coordX = floor(texCoord.x * atlasSize.x);
		bool isEvenX = int(coordX) % 2 == 0;
		float mippedCoordX = isEvenX ? texCoord.x : texCoord.x - (1 / atlasSize.x);

		bool isMippedEvenX = int(coordX / 2) % 2 == 0;
		float doubleMippedCoordX = isMippedEvenX ? mippedCoordX : mippedCoordX - (2 / atlasSize.x);

		//--------------------------------------------------------------------------------

		float coordY = floor(texCoord.y * atlasSize.y);
		bool isEvenY = int(coordY) % 2 == 0;
		float mippedCoordY = isEvenY ? texCoord.y : texCoord.y - (1 / atlasSize.y);

		bool isMippedEvenY = int(coordY / 2) % 2 == 0;
		float doubleMippedCoordY = isMippedEvenY ? mippedCoordY : mippedCoordY - (2 / atlasSize.y);
		
		//--------------------------------------------------------------------------------
		color = vertexDistance > MIP_DISTANCE_FAR ? texture(Sampler0, vec2(doubleMippedCoordX,doubleMippedCoordY)) : 
					vertexDistance > MIP_DISTANCE_NEAR  ? texture(Sampler0, vec2(mippedCoordX,mippedCoordY)) : 
														texture(Sampler0, texCoord);
		
		//color = applyEdgeFilterAndMipmapping(Sampler0, mipCoord, atlasSize);


	}

    //color = vec4(mippedCoordX,mippedCoordX,mippedCoordX,1.0);
    //fragColor = color;

    //custom lighting
    #define BLOCK
    #moj_import<objmc_light.glsl>

    if (color.a < 0.1) discard;
    fragColor = linear_fog(color, vertexDistance, FogStart, FogEnd, FogColor);
    //fragColor = vertexColor;
}