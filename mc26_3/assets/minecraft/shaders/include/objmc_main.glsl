// 26.3's copy of assets/minecraft/shaders/include/objmc_main.glsl, translated by ResourcePackScripts' shader_base.py: don't edit it.
#ifndef MCME_OBJMC_MAIN_GLSL
#define MCME_OBJMC_MAIN_GLSL
//objmc
//https://github.com/Godlander/objmc

// This include is intentionally limited to the BLOCK/terrain path. Entity,
// item, GUI, hand, display, and armor branches are not part of shaders_sort.
//
// Shared by vanilla's terrain.vsh and Sodium's block_layer_opaque.vsh (in
// assets/sodium). Sodium's names are mapped onto vanilla's with #defines;
// OBJMC_SECTION_OFFSET and OBJMC_UV_BIAS are set there.

#ifndef OBJMC_SECTION_OFFSET
// From a vertex's section-local position to its place relative to the camera.
#define OBJMC_SECTION_OFFSET ((ChunkPosition - CameraBlockPos) + CameraOffset)
#endif

isCustom = 0;
// The carrier vertex where the client put it, random block offset included.
vec3 carrierPos = Pos;
transition = 0;
ivec2 atlasSize = textureSize(Sampler0, 0);
vec2 onepixel = 1.0 / atlasSize;
// Which corner of its carrier face this vertex is, from its UV: a carrier's UVs
// span 0.1 to 0.9 of its pointer pixel, and the client gives face vertex 0 the
// (min u, min v) corner, 1 (min u, max v), 2 (max u, max v), 3 (max u, min v)
// (26.2's CuboidFace.UVs). Not gl_VertexID % 4: a section's vertices start
// wherever its shared buffer had room, so that is off by a different 0-3 per
// section, changing whenever the section is rebuilt - which keeps the shape
// but moves the client's per-corner occlusion onto the wrong corners.
#ifdef OBJMC_UV_BIAS
// Sodium rounds a texture coordinate and moves it a step towards its face's
// centre, keeping which side it came from: +1 below the centre, -1 above.
bvec2 uvHigh = lessThan(OBJMC_UV_BIAS, vec2(0.0));
#else
bvec2 uvHigh = greaterThan(fract(UV0 * atlasSize), vec2(0.5));
#endif
int corner = uvHigh.x ? (uvHigh.y ? 2 : 3) : (uvHigh.y ? 1 : 0);
ivec2 uv = ivec2(UV0 * atlasSize);
vec3 posoffset = vec3(0.0);
int headerheight = 0;
ivec4 t[16];

t[0] = ivec4(texelFetch(Sampler0, uv, 0) * 255.0 + 0.5);
// A face pointer holds its own column and row in the bake, 12 bits each in
// red, green and blue; its alpha is a constant (objmc.py's POINTER_ALPHA).
ivec2 uvoffset = ivec2(t[0].r * 16 + (t[0].g >> 4), (t[0].g & 15) * 256 + t[0].b);
ivec2 topleft = uv - uvoffset;
// Every texel decodes to some offset, so only a texel with the pointer's alpha
// counts - no opaque or cutout texture has it - and only one leading to a
// header's marker.
ivec4 marker = t[0].a == 254
    ? ivec4(texelFetch(Sampler0, topleft, 0) * 255.0 + 0.5)
    : ivec4(0);

if (marker == ivec4(12, 34, 56, 255)) {
    isCustom = 1;
    for (int i = 1; i < 16; i++) {
        t[i] = getmeta(topleft, i);
    }

    ivec2 size = ivec2(t[1].r * 256 + t[1].g, t[1].b * 256 + t[7].r);
    int nvertices = t[2].r * 16777216 + t[2].g * 65536 + t[2].b * 256 + t[7].g;
    int nframes = max(t[3].r * 65536 + t[3].g * 256 + t[3].b, 1);
    // 255 is written for 1, keeping the pixel opaque (objmc.py's POINTER_ALPHA).
    int ntextures = t[3].a == 255 ? 1 : max(t[3].a, 1);
    float duration = max(t[4].r * 65536 + t[4].g * 256 + t[4].b, 1);
    bool autoplay = getb(t[4].a, 6);
    ivec2 easing = ivec2(getb(t[4].a, 4, 2), getb(t[4].a, 2, 2));
    int vph = t[5].r * 256 + t[5].g;
    // A bake narrower than 16 texels ends before t[8], which then reads from
    // whatever sprite lies next to it in the atlas: ignore t[8] and on there.
    bool wideHeader = size.x >= 16;
    int vth = t[5].b * 256 + t[7].b;
    noshadow = getb(t[6].r, 7, 1);
    bvec3 visibility = bvec3(getb(t[6].r, 4), getb(t[6].r, 3), getb(t[6].r, 2));
    // Mip levels the texture is padded for (objmc.py --mipmap). The fragment
    // shader samples the texture no smaller than this.
    maxLod = min(t[6].g, 4);
    // Whether the texture has partly transparent texels of its own, whose
    // alpha terrain.fsh leaves alone rather than sharpening its edges.
    blendTexture = t[6].b & 1;

    float time = GameTime * 24000.0;
    float texTime = GameTime * 24000.0;
    int tcolor = 0;

    if (!visibility.x) {
        Pos = vec3(0.0);
        posoffset = vec3(0.0);
    } else {
        int frame;
        if (autoplay && tcolor >= 32768) {
            int start = tcolor - 32768;
            int elapsed = (int(time) % 24000 - start + 24000) % 24000;
            frame = min(elapsed, nframes - 1);
            time = (elapsed >= nframes - 1) ? float(frame) : float(elapsed) + fract(time);
        } else {
            time = autoplay ? time + duration : tcolor;
            frame = int(time * nframes / duration) % nframes;
        }

        int id = (((uvoffset.y - 2) * size.x) + uvoffset.x) * 4 + corner;
        id += frame * nvertices;
        // headerheight is the texture's first row, height the data's. Padded
        // for mipmapping, the texture starts on a 2^maxLod row boundary with at
        // least one such block of repeated edge rows either side (objmc.py's
        // texture_layout), so no mip level up to maxLod mixes the data in.
        headerheight = 2 + int(ceil(nvertices * 0.25 / size.x));
        int height = headerheight + size.y * ntextures;
        if (wideHeader && t[8].r == 2) {
            // Layout 2 (objmc_merge.py): the texture is shared by every model
            // baked onto this sprite and sits above this model's block, t[8].gb
            // rows up; the data follows the pointers directly.
            height = headerheight;
            headerheight = -(t[8].g * 256 + t[8].b);
        } else if (maxLod > 0) {
            int block = 1 << maxLod;
            headerheight = (headerheight + 2 * block - 1) / block * block;
            height = (headerheight + size.y * ntextures + block - 1) / block * block + block;
        }
        ivec2 index = getvert(topleft, size.x, height + vph + vth, id);
        posoffset = getpos(topleft, size.x, height, index.x);

        if (nframes > 1) {
            int nids = nframes * nvertices;
            id = (id + nvertices) % nids;
            index = getvert(topleft, size.x, height + vph + vth, id);
            vec3 posoffset2 = getpos(topleft, size.x, height, index.x);
            transition = fract(time * nframes / duration);
            switch (easing.x) {
                case 1:
                    posoffset = mix(posoffset, posoffset2, transition);
                    break;
                case 2:
                    transition = transition < 0.5
                        ? 4.0 * transition * transition * transition
                        : 1.0 - pow(-2.0 * transition + 2.0, 3.0) * 0.5;
                    posoffset = mix(posoffset, posoffset2, transition);
                    break;
                case 3:
                    id = (id + nvertices) % nids;
                    index = getvert(topleft, size.x, height + vph + vth, id);
                    vec3 posoffset3 = getpos(topleft, size.x, height, index.x);
                    id = (id + nvertices) % nids;
                    index = getvert(topleft, size.x, height + vph + vth, id);
                    vec3 posoffset4 = getpos(topleft, size.x, height, index.x);
                    posoffset = bezier(posoffset, posoffset2, posoffset3, posoffset4, transition);
                    break;
            }
        }
        transition = 0.0;
        texCoord = getuv(topleft, size.x, height + vph, index.y);
    }

    // Every corner of a carrier element sits strictly inside its block (see
    // objmc.py's CARRIER_MARGIN), so the block's integer cell is identical
    // for all 4 corners of a face. That
    // replaces subgroupQuadBroadcast, whose "quad" grouping is only
    // spec-guaranteed for fragment-shader 2x2 pixel quads.
    //
    // Floor the raw section-local Position, NOT Pos: Pos already contains
    // CameraOffset (the camera's fractional block position), so flooring it
    // moves the cell boundary every frame the camera moves and the model
    // snaps by a block. Position is camera-independent; the camera-relative
    // terms are whole-block shifts (plus CameraOffset) added afterwards.
    vec3 blockOrigin = floor(Position) + OBJMC_SECTION_OFFSET;
    Pos = blockOrigin + vec3(0.5) + posoffset;
    // Centred carriers (objmc.py's --centred, t[9].r = 1) sit at the block's
    // centre plus the random offset the client gives blocks like ferns; the
    // model goes where the client put its carrier, keeping that offset.
    if (wideHeader && t[9].r == 1) {
        Pos = carrierPos + posoffset;
    }
    vec2 uvjit = vec2(onepixel.x * 0.0001 * corner, onepixel.y * 0.0001 * ((corner + 1) % 4));
    vec2 texuvpx = texCoord * size;
    // A face UV that reaches exactly 0 or `size` rounds, after the fragment
    // shader's uv*textureSize truncation, to one texel past the baked
    // texture's true edge - clipping a thin strip off every polygon that maps
    // to the edge of its source texture. Keep it strictly inside instead.
    texuvpx = clamp(texuvpx, vec2(0.01), vec2(size) - vec2(0.01));
    // The texture's rectangle in the atlas (all frames, for ntextures > 1),
    // which the fragment shader keeps its filtering inside.
    texRect = vec4(vec2(topleft.x, topleft.y + headerheight),
                   vec2(topleft.x + size.x, topleft.y + headerheight + size.y * ntextures))
            / vec4(atlasSize, atlasSize);

    if (ntextures > 1) {
        ivec4 texmeta = ivec4(texelFetch(Sampler0, topleft + ivec2(4, 1), 0) * 255.0 + 0.5);
        ivec4 texflags = ivec4(texelFetch(Sampler0, topleft + ivec2(5, 1), 0) * 255.0 + 0.5);
        float texFrametime = max(float(texmeta.r * 65536 + texmeta.g * 256 + texmeta.b), 1.0);
        bool texFade = (texflags.r & 1) == 1;
        int texframe = int(texTime / texFrametime) % ntextures;
        int texnext = (texframe + 1) % ntextures;
        vec2 base = vec2(topleft.x, topleft.y + headerheight + texframe * size.y);
        vec2 base2 = vec2(topleft.x, topleft.y + headerheight + texnext * size.y);
        texCoord = (base + texuvpx) / atlasSize + uvjit;
        texCoord2 = (base2 + texuvpx) / atlasSize + uvjit;
        transition = texFade ? fract(texTime / texFrametime) : 0.0;
    } else {
        texCoord = (vec2(topleft.x, topleft.y + headerheight) + texuvpx) / atlasSize + uvjit;
    }
}
#endif
