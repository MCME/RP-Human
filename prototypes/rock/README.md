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

It also turns `dead_horn_coral_block` into the same stone under layers of
webbing: matted and loose threads, piled into concave corners, with sludge,
drips, hanging threads, egg sacs, the odd orb web and a poisonous tint in
places.

The edge wear works because the model can tell what the shader can't. Thin
strips along each face's edges are culled by the block beyond that edge, so a
strip shows only where both sides of its edge are open. The vertex shader lifts
the strips just off their faces so they don't z-fight them.

The fire eye that was tried out here now lives in RP-Mordor.

## Building

Needs Python 3 with Pillow:

    python prototypes/rock/make_rock_prototype.py [--base pack] [output folder]

The output defaults to `.minecraft/resourcepacks/RP-rock-prototype`. The
materials hook into the terrain shaders through the hooks of ResourcePackScripts'
shared shader base (`shaderBase/`, see its `docs/shader-base.md`), so load the
pack above the shader base and this repository. Its hooks replace the pack's,
so it adds to the pack's own: `--base` names another pack to add to instead,
for example RP-Mordor, with its fire eye and lava. The script also reads the
stone textures from `assets/`, so rebuild it after either changes. Everything
you can tune is in `TUNE` at the top of the script.

The materials themselves are shader includes the script writes:
`rockproto_config.glsl` (`TUNE`), `rockproto_main.glsl` (the vertex part) and
`rockproto.glsl` (the colours), shared by vanilla's terrain shaders and
Sodium's block shaders.

## Sodium

Sodium tells its shaders no position in the world, only within the vertex's
region of 128 × 64 × 128 blocks. Under Sodium every pattern is fitted to that
region and repeats with it, seamlessly, so:

- the whole look repeats every 128 blocks across and 64 up
- the strata dip along the nearest axis (east for the default 30°), their
  slope rounded to rise a whole multiple of 64 blocks across a region (the
  default 0.5 rises exactly 64), and don't drift
- matted webbing's fibres run along the face's axes rather than at angles
- streaks and drips can stop short where they cross a region's top or bottom

## Limitations

- The edge strips add up to 24 faces per block. A strip also renders, hidden,
  behind a solid neighbour whenever the block beyond its edge is open. On open
  rock surfaces that's roughly 5 times the faces. Reduce it before using this
  on real terrain.
- Where a top edge and a side edge are both worn, their strips overlap in the
  corner's 4×4 texels and one wins, so the wear can show a small seam there.
- Iris shader packs replace the terrain shaders, so none of this shows under
  them.
