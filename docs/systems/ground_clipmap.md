# The ground clipmap

The composited ground (all layer blending, accents, paths, cobble) is the most expensive part of the
frame on a typical map. `GroundClipmap` (a child of `AuthoredTerrain`) bakes it top down into a
camera-following pyramid of textures and the ground shader reads the bake where it covers a pixel,
keeping the layer blend everywhere else. Cards clipmap1 and clipmap2 (2026-11-09); numbers and the
design history are in `docs/PERFORMANCE.md` "Ground clipmap".

## Model

- **Levels.** Five fixed-density levels, L0 to L4 at 200, 100, 50, 25 and 12.5 texels per metre. Each is a
  toroidal window of 2048 x 2048 texels (8 x 8 tiles of 256) in two RGBA8 textures: lit albedo with AO
  in alpha, then normal.xz and roughness. 32 MB a level; 160 MB with all five. The coarsest level that
  spans the map (with a tile to spare) is static; finer ones follow the view's focus.
- **Held levels.** From the finest the zoom needs (the screen's texels per metre) up to the top; a level
  stops being held 4 s after the view stops needing it. Zoom needs no rebake. The Ground detail setting
  (`GroundClipmapSetting`: 5, 4, 3 or Off) caps how many are held, dropping the sharpest first.
- **Strips.** A window is written a column or row of tiles at a time. A strip viewport renders the
  chunk meshes top down with the bake shader (`authored_ground_bake*.gdshader`, the ground include with
  `GROUND_BAKE_OUT`, two passes), and the frame after a 2D draw copies it into the window with blending
  off. One strip per two frames, coarsest level first. `GroundClipmapPlan` is the pure geometry (blocks,
  next job, blit pieces, patch jobs; unit-tested).
- **Sampling.** `clip_fetch` in `shaders/authored_ground.gdshaderinc`: window uv = world xz / extent
  (toroidal, `repeat_enable`), level = floor(log2(footprint x 200)), a crossfade to the next level above
  the 0.7 fraction, a fade at a window's edge, and a coverage share; at 0.5 or more the pixel reads the
  bake, else the layer blend runs.
- **What stays per pixel.** Steep faces (`n.y` under 0.6), a pixel whose level is more than one octave
  finer than any covered one (unbaked, not held, the eye view, a level cap), a footprint under half a
  texel of L0, a footprint past the top level (full zoom-out: the top level fades out, the windows have
  no mips), the skirt, the fire block and the wet line. The look matches the per-pixel path to a mean of
  0.1 to 0.5 levels; the differences are 1-texel shifts of accent rims.

## Edits

`AuthoredTerrain.ground_edited(sample_rect)` is emitted by `update_ground_region`, `queue_heights` (with
the rule fields' reach), `settle_heights` and `refresh_water_dressing`. The clipmap marks the rectangle
(`clip_hole`, a uniform): at once every pixel inside it uses the layer blend, which reads the live ground,
so an edit shows in the next frame. After `EDIT_QUIET_S` (0.25 s) without edits and without height work,
the strips over the tiles it touched are rebaked (`patch_jobs`: the fewer of columns and rows, each as long
as the block, so tiles outside the edit are rewritten with the same content), the bake materials are
synced to the live ground (uniforms, rebuilt chunk meshes) and the hole closes. An edit over half the grid,
a new ground material, a look rebake or a chunk-count change rebakes everything.

## Switches

- `GroundClipmap.ON_BY_DEFAULT` (play mode only: a clipmap in a `GameMap` with `authoring_mode` frees
  itself), `--ground-clipmap` and `--no-ground-clipmap` on the command line (the first also keeps it in
  authoring), the Ground detail setting (Settings > Graphics, `graphics/ground_detail_levels`).
- Headless runs never attach one (no renderer).
- `CLIP_NO_ANISO`, `CLIP_NO_BLEND`, `CLIP_ONLY`, `CLIP_NO_FAR`, `CLIP_NO_OCTAVE`: measurement defines.
- Render-job probe `tools/render_jobs/probes/clipmap.gd` (on, off, read, await, view, stats, pan,
  pan_ab, cost, cliff, prepare, edit) and the `clip` knob of `perfaudit_gpu.gd`.
