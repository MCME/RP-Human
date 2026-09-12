//objmc
//https://github.com/Godlander/objmc

// This include is intentionally limited to the BLOCK/terrain path. Entity,
// item, GUI, hand, display, and armor branches are not part of shaders_sort.

isCustom = 0;
transition = 0;
int corner = gl_VertexID % 4;
ivec2 atlasSize = textureSize(Sampler0, 0);
vec2 onepixel = 1.0 / atlasSize;
ivec2 uv = ivec2(UV0 * atlasSize);
vec3 posoffset = vec3(0.0);
int headerheight = 0;
ivec4 t[16];

t[0] = ivec4(texelFetch(Sampler0, uv, 0) * 255.0 + 0.5);
ivec2 uvoffset = ivec2(t[0].r * 256 + t[0].g, t[0].b * 256 + t[0].a);
ivec2 topleft = uv - uvoffset;
ivec4 marker = ivec4(texelFetch(Sampler0, topleft, 0) * 255.0 + 0.5);

if (marker == ivec4(12, 34, 56, 255)) {
    isCustom = 1;
    for (int i = 1; i < 16; i++) {
        t[i] = getmeta(topleft, i);
    }

    ivec2 size = ivec2(t[1].r * 256 + t[1].g, t[1].b * 256 + t[7].r);
    int nvertices = t[2].r * 16777216 + t[2].g * 65536 + t[2].b * 256 + t[7].g;
    int nframes = max(t[3].r * 65536 + t[3].g * 256 + t[3].b, 1);
    int ntextures = max(t[3].a, 1);
    float duration = max(t[4].r * 65536 + t[4].g * 256 + t[4].b, 1);
    bool autoplay = getb(t[4].a, 6);
    ivec2 easing = ivec2(getb(t[4].a, 4, 2), getb(t[4].a, 2, 2));
    int vph = t[5].r * 256 + t[5].g;
    int vth = t[5].b * 256 + t[7].b;
    noshadow = getb(t[6].r, 7, 1);
    bvec3 visibility = bvec3(getb(t[6].r, 4), getb(t[6].r, 3), getb(t[6].r, 2));

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
        headerheight = 2 + int(ceil(nvertices * 0.25 / size.x));
        int height = headerheight + size.y * ntextures;
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

    Pos = subgroupQuadBroadcast(Pos, 2) + posoffset;
    vec2 uvjit = vec2(onepixel.x * 0.0001 * corner, onepixel.y * 0.0001 * ((corner + 1) % 4));
    vec2 texuvpx = texCoord * size;

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
        ivec4 aaf = ivec4(texelFetch(Sampler0, topleft + ivec2(5, 1), 0) * 255.0 + 0.5);
        int nbands = min(aaf.g, 15);
        if (nbands > 0) {
            ivec4 m4 = ivec4(texelFetch(Sampler0, topleft + ivec2(4, 1), 0) * 255.0 + 0.5);
            float ft = max(float(m4.r * 65536 + m4.g * 256 + m4.b), 1.0);
            float vmid = (subgroupQuadBroadcast(texCoord.y, 0) + subgroupQuadBroadcast(texCoord.y, 2))
                       * 0.5 * float(size.y);
            float dy = 0.0;
            float dy2 = 0.0;
            bool inBand = false;
            for (int b = 0; b < nbands; b++) {
                ivec4 m6 = ivec4(texelFetch(Sampler0, topleft + ivec2(6 + 2 * b, 1), 0) * 255.0 + 0.5);
                ivec4 m7 = ivec4(texelFetch(Sampler0, topleft + ivec2(7 + 2 * b, 1), 0) * 255.0 + 0.5);
                int y0 = m6.r * 256 + m6.g;
                int fH = m6.b * 256 + m7.r;
                int fc = max(m7.g, 1);
                if (vmid > float(y0) && vmid < float(y0 + fH)) {
                    int tf = int(texTime / ft) % fc;
                    int tn = (tf + 1) % fc;
                    dy = float(-tf * fH);
                    dy2 = float(-tn * fH);
                    inBand = true;
                    break;
                }
            }
            texCoord = (vec2(topleft.x, topleft.y + headerheight) + texuvpx + vec2(0.0, dy)) / atlasSize + uvjit;
            texCoord2 = (vec2(topleft.x, topleft.y + headerheight) + texuvpx + vec2(0.0, dy2)) / atlasSize + uvjit;
            transition = (inBand && ((aaf.r & 1) == 1)) ? fract(texTime / ft) : 0.0;
        } else {
            texCoord = (vec2(topleft.x, topleft.y + headerheight) + texuvpx) / atlasSize + uvjit;
        }
    }
}
