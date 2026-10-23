// 26.3's copy of assets/minecraft/shaders/include/mcme_clock.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_MCME_CLOCK_GLSL
#define MCME_MCME_CLOCK_GLSL
// The game's time, for a shader that isn't given it but samples the lightmap:
// Sodium's terrain, whose own clock restarts with each region and would part
// what moves at their edges, and Distant Horizons' terrain. core/lightmap.fsh
// hides the tick of the day in the lowest bit of the colours of a few texels -
// a 1/255 step no one sees - and it is rebuilt every tick.

#define MCME_CLOCK_ROW 15     // the texels' row: full sky light
#define MCME_CLOCK_TEXELS 5   // 3 bits each: 15, enough for a day's 24000 ticks

// color, the lightmap's at texel, with its share of the tick of gameTime (the
// day's fraction, Globals' GameTime) in its lowest bits
vec3 mcmeClockEncode(vec3 color, ivec2 texel, float gameTime) {
    if (texel.y != MCME_CLOCK_ROW || texel.x >= MCME_CLOCK_TEXELS) return color;
    uint bits = (uint(gameTime * 24000.0 + 0.5) % 24000u) >> uint(texel.x * 3);
    uvec3 c = uvec3(clamp(color, 0.0, 1.0) * 255.0 + 0.5);
    c = (c & ~1u) | uvec3(bits & 1u, (bits >> 1) & 1u, (bits >> 2) & 1u);
    return vec3(c) / 255.0;
}

// The lightmap's light at uv (0 to 1, as texture() takes it) without the
// clock: filtered as the game's own, from its four texels, with the clock's
// bits cleared from those that hold them. Terrain is lit by this, not the
// texture itself: full sky light without block light is the clock's first
// texel, and a step of 255 flickering with the tick shows on bright faces.
vec4 mcmeLightmap(sampler2D lightmap, vec2 uv) {
    ivec2 size = textureSize(lightmap, 0);
    vec2 st = uv * vec2(size) - 0.5;
    ivec2 t = ivec2(floor(st));
    vec2 f = st - vec2(t);
    vec4 c[4];
    for (int k = 0; k < 4; k++) {
        ivec2 tk = clamp(t + ivec2(k & 1, k >> 1), ivec2(0), size - 1);
        c[k] = texelFetch(lightmap, tk, 0);
        if (tk.y == MCME_CLOCK_ROW && tk.x < MCME_CLOCK_TEXELS) {
            c[k].rgb = vec3(uvec3(c[k].rgb * 255.0 + 0.5) & ~1u) / 255.0;
        }
    }
    return mix(mix(c[0], c[1], f.x), mix(c[2], c[3], f.x), f.y);
}

// the time, in seconds into the day, as vanilla's GameTime * 1200.0
float mcmeClockSeconds(sampler2D lightmap) {
    uint ticks = 0u;
    for (int i = 0; i < MCME_CLOCK_TEXELS; i++) {
        uvec3 c = uvec3(texelFetch(lightmap, ivec2(i, MCME_CLOCK_ROW), 0).rgb * 255.0 + 0.5);
        ticks |= ((c.r & 1u) | ((c.g & 1u) << 1) | ((c.b & 1u) << 2)) << uint(i * 3);
    }
    return float(ticks) / 20.0;
}
#endif
