# Rock prototype

A test of rock that varies by world position on a single blockstate, giving a
result like connected textures without extra blockstates. It is not part of
the pack: Minecraft ignores this folder.

`make_rock_prototype.py` builds a separate resource pack that turns
`honeycomb_block` into this rock. Each face's look comes from the terrain
shader, which hashes and noises the world position:

- a stone variant per block, turned or mirrored
- discoloured and mossy patches
- strata lines that bend, thicken and break off at their own intervals, but
  never fold back on themselves
- weathering streaks down the sides
- clustered cracks
- faint, lighter wear along exposed edges

The edge wear works because the model can tell what the shader can't. Thin
strips along each face's edges are culled by the block beyond that edge, so a
strip shows only where both sides of its edge are open. The vertex shader lifts
the strips just off their faces so they don't z-fight them.

## Building

Needs Python 3 with Pillow:

    python prototypes/rock/make_rock_prototype.py [output folder]

The output defaults to `.minecraft/resourcepacks/RP-rock-prototype`. Load it
above the vanilla pack. The script reads the terrain shaders from `vanilla/`
and the stone textures from `assets/`, so rebuild it after either changes.
Everything you can tune is in `TUNE` at the top of the script.

## Limitations

- Vanilla's terrain shader only; Sodium's shaders aren't patched.
- The edge strips add up to 24 faces per block. A strip also renders, hidden,
  behind a solid neighbour whenever the block beyond its edge is open. On open
  rock surfaces that's roughly 5 times the faces. Reduce it before using this
  on real terrain.
- Where a top edge and a side edge are both worn, their strips overlap in the
  corner's 4×4 texels and one wins, so the wear can show a small seam there.
