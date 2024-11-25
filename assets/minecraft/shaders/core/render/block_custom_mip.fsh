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
#define MIP_DISTANCE_NEAR (25.0)
#define MIP_DISTANCE_FAR (50.0)

out vec4 fragColor;

void main() {
    //vec4 color = mix(texture(Sampler0, texCoord), texture(Sampler0, texCoord2), transition);
    vec2 atlasSize = textureSize(Sampler0, 0);

    vec4 color;

    if(USE_CUSTOM_MIP) {

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


        color = vertexDistance < MIP_DISTANCE_NEAR ? texture(Sampler0, texCoord) : 
                    vertexDistance < MIP_DISTANCE_FAR  ? texture(Sampler0, vec2(mippedCoordX,mippedCoordY)) : 
                                                        texture(Sampler0, vec2(doubleMippedCoordX,doubleMippedCoordY));
    } else {
        color = texture(Sampler0, texCoord);
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