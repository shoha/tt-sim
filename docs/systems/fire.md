# Persistent fire

The ground fire an author paints with the Fire tool (`MapDocument.fire_mask`) and every peer
draws from the document: a few big painted fires standing in a burn of dark char, a soft pool of
light under each, a leaning plume of smoke over the largest blazes and short warm lights at dusk
and night. The bar is round 6 of the reference fit, approved for production by the user on
2026-10-17 ("go ahead with production, busyness is fine for now"): fires whose drawings tear and
grow into one another, the flames always the brightest thing in the frame, the char between the
fires kept dark, and nothing that reads as a sticker, a stamp or a straight seam. Decisions and
open work are in [../MAP_AUTHORING.md](../MAP_AUTHORING.md); the Fire tool and its history entries
are in [authoring.md](authoring.md); the production port's plan is
`docs/plans/2026-10-11-fire-features/production.md` (gitignored). The event fire (Start a fire)
is a separate effect; "Runtime" ends with what it still uses.

## Map

| File | Class | Role |
|------|-------|------|
| `scenes/terrain/fire_field.gd` | `FireField` | One per map with a document: the lattice and bands, the stroke path (`blocks_to_replan`, `raster_box`, `cleared_rect`, `resplat`), the heat and pool rasters, the budget, the chunks, `plan_seed`, `plan_digest`; holds and polls the books |
| `scenes/terrain/fire_fires.gd` | `FireFires` | What stands on the lattice: centres, covers, stragglers, the blaze's flames (pure) |
| `scenes/terrain/fire_plan_job.gd` | `FirePlanJob` | A refresh's pure half (re-plan, cluster sums, rasters) on a worker |
| `scenes/terrain/fire_noise_bake.gd` | `FireNoiseBake` | The ground's sim bake: one SubViewport, two RGBA8 tiles |
| `scenes/terrain/fire_clusters.gd` | `FireClusters` | Flame sums on a 3.5 m grid and the hot spots the lights and smoke stand on (pure) |
| `scenes/terrain/fire_lights.gd` | `FireLights` | Up to four shared `OmniLight3D` |
| `scenes/terrain/fire_field_smoke.gd` | `FireFieldSmoke` | One MultiMesh of plumes; the smoke book's load and binding |
| `scenes/effects/fire_look.gd` | `FireLook` | The shared quad and material, instance buffers and bounds, the fire book's lifecycle, the ground's glow binding, the lights' colour, energy, flicker and gate |
| `resources/fire_book.gd` | `FireBook` | The flames' book as a Resource: validation (`problem()`), `create_texture()`, `is_lfs_pointer()` |
| `resources/fire_smoke_book.gd` | `FireSmokeBook` | The smoke's book as a Resource |
| `assets/fire/fire_book.res`, `assets/fire/fire_smoke_book.res` | | The shipped books (Git LFS) |
| `shaders/fire_flames.gdshader` | | The flames, drawn from the book (its header holds the model) |
| `shaders/fire_smoke_book.gdshader` | | The smoke, drawn from the smoke book |
| `shaders/fire_ground_bake.gdshader` | | The sim bake's shader |
| `shaders/fire_glow.gdshaderinc` | | The ground's fire term (`fire_glow`, `fire_sim_bake`), included by `authored_ground.gdshaderinc` |
| `shaders/fire_glow_noise.gdshaderinc` | | The ground fire's integer-hashed noise and fields; its noise also serves the events' scorch and the smoke bake |
| `shaders/fire_noise.gdshaderinc` | | The fire family's noise: the flames' wind gust and the whole event fire |
| `tools/fire_sim/` | | The offline bakes: `bake_fire_book.py`, `pack_fire_book.gd`, `fire_smoke_book_bake.gdshader`, `README.md` |
| `tools/render_jobs/probes/fire_smoke_book.gd` | | The smoke book's windowed bake (job `fire_smoke_book`) |
| `scenes/states/authoring/tools/fire_tool.gd`, `fire_brush.gd`, `fire_tool_pane.gd`, `fire_editor.gd` | `FireTool`, `FireBrush`, `FireToolPane`, `FireEditor` | The Fire tool ([authoring.md](authoring.md) "Tools") |
| `utils/graphics_warmup.gd` | `GraphicsWarmup` | Covers `fire_flames`, `fire_smoke_book` and `fire_ground_bake` |

## Model

### The plan

- **Placement is pure** (`FireField.plan_block`, which hands every block to
  `FireFires.plan_block`): per diff block of the mask (`MaskStroke.BLOCK`, 10 m at the default
  spacing), a jittered lattice at `FLAME_SPACING_M` 0.9 m (`JITTER` 0.45 of it), the mask read
  through a broad warp (`PLACE_WARP`: a 5 m noise moving the read up to 2 m, so a straight pass
  does not stand its fires in rows). A point burns where the read is at least `EMBER_MIN` 40 and
  the ground is neither wet nor steeper than the cliff rule (`STEEP_NORMAL_Y`, a literal);
  bands: embers 40-110, flames 110-200, blaze 200 and up. Where fires stand is derived and never
  saved.
- **FireFires, fewer and bigger fires:** in the flames band a burning point whose score (its
  clump value plus `HEAT_SCORE` 0.15 of the mask's heat) tops every burning point within
  `CENTRE_REACH` 3 lattice points (2.7 m) is a centre and stands one fire at its neighbourhood's
  centroid pulled halfway to its own spot: 1.9-2.9 m tall by clump place and cover, times
  0.9-1.08 by band and 0.92-1.08 by its own draw, 0.9-1.1 of its height wide. An uncovered point
  (no centre within `COVER_REACH` 3) that tops its uncovered neighbours keeps a straggler
  (`SINGLE_SCALE` 0.8-1.15 of the base height, 0.45-0.7 wide), so no burn goes bare and no carpet
  comes back. A blaze point stands FireField's own flame at `SIM_BLAZE_SCALE` 0.6 of its height
  and `SIM_BLAZE_SHARE` 1.05 of that wide, so a blaze merges into one mass; an ember point throws
  a spark at about one point in `SPARK_EVERY` 6. The largest fire is 3.38 m tall and 3.72 m wide
  and stands up to `spill_m` 1.755 m off its block (the farthest measured 0.27 m).
- **The lattice window and its margin:** a decision reads only `FireField.LatticeWindow`, which
  reaches `FireFires.MARGIN` 7 lattice points past the block (a centre's 3, its cover's 3 and
  one), so neighbouring blocks agree on every centre.
- **The per-fire seed:** each entry's seed is `FireField.plan_seed(map seed, ix, iz)`, the map
  seed hashed with each lattice index in turn; the plan is shuffled by it (any prefix is an even
  thinning) and `FireLook.fire_seed` turns it into an integer under 2^24 (exact in a float) in
  `INSTANCE_CUSTOM.w`, which the shader hashes with PCG integer arithmetic for every pick. Not the
  lattice key: `FireField._key(ix, iz)` equals `_key(-ix, -iz)` whenever both are odd (two's
  complement), so a key-drawn seed collided for 17 of 109 fires in a test block and stamped
  point-mirrored neighbours near the map's middle with one drawing. Not `MODEL_MATRIX`: a
  position hash in floats differs across GPUs and transforms.
- **CPU determinism:** integer hashes, polynomial noise, float32 storage, and literal
  cosines and sines for the clump's turns (`CLUMP_TURN_A`, `CLUMP_TURN_B`) and the steep limit, so
  no platform's trig moves a fire.
- **The rasters** (on a grid every `HEAT_STEP_M` 0.5 m from the document's first sample): the
  heat (each fire adds its height under a soft kernel reaching 1 m plus its width; a texel's sum
  over `HEAT_FULL_M` 4.5 is the bed's temperature) and the feet's pools (each adds 1 under a
  narrow kernel reaching 0.4 m plus 0.85 of its width, `POOL_REACH`; about twice a fire's width).
  Each drawn flame carries the heat at its foot. The rasters come from the whole plans, not the
  budget's prefix.
- **The sorted splat:** `resplat` clears the cleared rect and re-splats every block whose
  `raster_box` meets it in row order (`row_order`), not in the Dictionary's insertion order, so
  every texel sums its fires in one order however the plans were made.
- **`plan_digest()`:** SHA-256 of the burning blocks' plans in row order and the rasters' size and
  bytes. A peer that refreshed stroke by stroke and one that rebuilt hold the same digest
  (test_fire_field_plan's refresh-equals-rebuild; `tests/net/enet_live_edits` compares it between
  host, client and late joiner, [../NETWORKING.md](../NETWORKING.md) "ENet scenarios").
- **Budget:** `MAX_FLAMES` 4096 on the whole map, shared by `budget_shares` in proportion to each
  block's burning area (pure, so peers agree). Moot in practice: the look level, a burn over
  much of a 200 ft map, shows 267 fires. There is no LOD: every zoom draws the same fires.

### The stroke path

- `refresh(sample_rect)` re-plans `blocks_to_replan`: every block within `PLACE_WARP.y +
  (FireFires.MARGIN + JITTER) x FLAME_SPACING_M` = 8.7 m of the changed samples (2.4 m before the
  port, which the old placement's reach needed; a search of 328 dabs found no plan change past the
  old reach, so the new bound is the rigorous one rather than a measured need).
- The rasters are cleared over `cleared_rect`: the touched blocks' `raster_box` grown `HEAT_GROW`
  13 texels (6.5 m), which covers `FireFires.heat_reach_m` 6.48 m (1.755 m off the block plus the
  widest fire's 4.72 m kernel); then the sorted splat above.
- `_land` redraws every chunk whose `FEET_GROW` box (5 texels: `spill_m` and the bilinear read's
  next texel) meets the cleared rect, since its fires' foot heat may have changed.
- The sim bake is redrawn over the blocks plus `BAKE_REACH_M` 8 m (`bake_region`: the cleared
  rect, the rasters' B-spline and the ground's mask reads).
- **The worker:** with `use_worker` (the authoring and play-time editors set it, as for the
  water) the pure half runs as a `FirePlanJob` on a `WorkerThreadPool` task from a snapshot of the
  document and lands on a later frame; refreshes asked for meanwhile merge into the next job.
  Tests, probes and a load's rebuild run it at once. Measured on firefeat_build's strokes (a 4 m
  dab, 9 runs, median): 16 blocks re-planned, the worker 168 ms on a third of the map burning and
  172 ms on the whole map (19-20 ms before the port), the main thread 1.94 and 3.01 ms. So a
  stroke's fires appear about a sixth of a second after the dab, and a peer's later still.

### The books

- **FireBook** (`assets/fire/fire_book.res`, format `TTFSIM02`): 385 RGBA8 Images of 96 x 128
  with stored mips: 8 sequences of 48 drawings in three classes (`class_first` (0, 3, 5, 8):
  narrow tongue, medium, wide mass) and a tiling tear tile at layer 384; `seq_bounds` (each
  sequence's baked bounds in the tile's UV), `drawings` 48, `tear_layer` 384, `source_sha256`.
  Images, not a Texture2DArray, because Images serialise from a headless run. 12,252,468 bytes
  (`FLAG_COMPRESS`; the mips a third of it); a headless load 59 ms.
- **The bake:** `tools/fire_sim/bake_fire_book.py`, round 6's small 2D fire simulation, run with
  Blender 5.2's bundled Python and its numpy (dev only, never shipped): `--out` required,
  `--sheets` optional, `--only` with it; about 86 s; an 18,923,704-byte `.bin` byte-equal to the
  spike's (sha256 834da0ba...). `tools/fire_sim/pack_fire_book.gd --in <bin>` refuses another
  magic, another tile, more than 16 sequences, unsorted classes, a size not matching its header
  or other than 385 layers, builds the mips (15 ms) and saves the resource.
  `tools/fire_sim/README.md` has the commands, the sheets to read and the checks.
- **FireSmokeBook** (`assets/fire/fire_smoke_book.res`, format `TTSMOKE1`): 48 RGBA8 Images of
  128 x 160, no mips: 2 seeds of 24 frames, each seed a closed 12 s loop of the whole column's
  silhouette, over the frame's domain `DOMAIN` (1.8, -0.45, 4.15) at the rise and width it was
  baked at (FireFieldSmoke's). 3,409,542 bytes. Baked once in a real window (a headless run
  draws nothing) by job `fire_smoke_book` from `tools/fire_sim/fire_smoke_book_bake.gdshader`,
  byte-equal to the spike's runtime bake; this removed the runtime readback and a warm-up shader.
- **Git LFS and export:** `.gitattributes` routes `assets/fire/**` to LFS. A clone without LFS
  holds a pointer: the load fails, one error ("fire book missing or an LFS pointer: run git lfs
  pull") and the flames and smoke stay invisible; `test_fire_book` and `test_fire_smoke_book`
  fail loudly. The export presets take all resources and exclude `tools/*`; `--export-pack`
  stores both books and nothing from `tools/`. Runtime code never reads a raw `.bin`.
- **Lifecycle:** `FireLook.request_book` starts a threaded `ResourceLoader` load on a live field's
  first non-empty plan (a field entering the tree planned, or landing a plan) or when the Fire
  tool is armed (`FireTool`); `poll_book` (each live FireField's `_process`) checks it, and on
  the main thread the book is validated (`problem()`), its `Texture2DArray` built
  (`create_from_images`, no CPU mips) and bound (`flipbook`, `seq_bounds` padded to 16,
  `class_first`, `drawings`, `tear_layer`). The smoke's book rides the same calls
  (FireFieldSmoke's `request_book`, `poll_book`, `finish_book`, `release_book`). Live fields are
  counted (`hold_book`, `drop_book`); the last FireField's exit releases both: the samplers are
  nulled, the textures freed, and a load still in flight is waited for and dropped. In the game:
  load 66.9 ms (threaded, request to landing), upload 4.2 ms (main thread). Until a book is bound
  `drawings` (or the smoke's `frames`) is 0 and every quad collapses, so nothing draws.

### The flames

`shaders/fire_flames.gdshader` (spike-flipbook de7f3d16's `fire_sim` shader and its melt pass
folded into one, every tuning uniform a const at round 6's value). One camera-facing quad per
fire, in a MultiMesh per burning block, its texels square, tightened to the sequence's baked
bounds and cut into `FireLook.ROW_CUTS` 4 rows that the shader moves to lean it. A layer holds
what the draw thresholds: R the flame field (0.5 at the edge), G the material's heat, B the
sparks, A a soft halo; one fetch a pixel, the edge thresholded crisp at any size, the colour
banded on the heat (`AGE_STOPS`: white-yellow, cream, yellow, orange, red) with no rim. The
consts: `DRAWING_RATE` 12 drawings a second (`RATE_JITTER` 0.08); a fire's class by its width
share (`CLASS_SHARE` 0.8 and 1.0: stragglers take the lively narrow tongues, fires and blaze
flames the masses); size `SIZE_JITTER` 0.87-1.13; height, width and lean `SHAPE_JITTER` (0.25,
0.18, 0.15), whole on a hot blaze fire, half otherwise; the tear tile `TEAR_SCALE` 2.5 repeats
(at `TEAR_REF_H` 2.2 m), `TEAR_AMP` (0.1, 0.22), rising `TEAR_TURNS` 2 tiles a loop so the loop
closes; the far form over `TEAR_FAR` 0.5-1.0 book texels a pixel (the tear eases to coarse lumps,
the book read up to `FAR_BLUR` 1.5 mips coarser, the bands `FAR_SOFT` 0.025 softer), so the colour
streaks calm to lobes at the default zoom; the halo cut at `HALO_CUT` 0.08, `DAY_HALO` 0.2 of it
by day; `NIGHT_GLOW` 0.25 and `DAY_CORE` 0.2 (a hot merged fire blooms by day as at night);
`NIGHT_GATE` below sunset's low sun; the depth melt `PROXIMITY_FADE` 0.35 and
`OCCLUDE_TOLERANCE` 0.25; `HDR_BOOST` and `HALO_STRENGTH` 1. Its uniforms are the book's and
`wind` (`FireLook.wind_for`). Unshaded, premultiplied, no depth test or write. `FireLook.bounds`
holds each chunk's every quad at the shader's jitter maxima in the camera's frame (about 1.05 h
half wide plus 0.74 h of lean, 2.97 h up the screen; a spark's rise, drift and wobble); the
`QUAD_*` consts mirror the shader and test_fire_look reads the shader's source to check them.

### The ground

The fire term of the authored ground shader (`fire_glow.gdshaderinc`, its header holds the
model): dark char between the fires (the albedo replaced by a painted brown-black field with
bold near-black shapes and `FIRE_ASH_SHARE` 0.25 of soft grey ash, matte, normals straight up),
dried and browned grass in a band of wandering width outside it, and under each fire a soft
round pool of light (`FIRE_POOL_LIGHT`) with a few faint lobes and cracks, its low tail cut so
every pool ends in dark ground. No ember cores: round 5's, even faint, drew red stripes between
the fires. The breathing is one slow sine (`FIRE_BREATHE` 1.9 rad/s, about 0.3 Hz) on the whole
glow. Everything that does not change with time is the **sim bake** (`FireNoiseBake`): one 2D
SubViewport (`fire_ground_bake.gdshader`) over the map and `MARGIN_M` 1 m round it, two RGBA8
tiles side by side at `SIM_PER_M` 16 texels a metre (at most `MAX_PX` 2048 a side): the albedo
terms (the char's weight, the dried band's mix, the scorch, the char's tone) and the glow terms
(the glow before its breathing, stored as `sqrt(glow / FIRE_SIM_GLOW_MAX)` with
`FIRE_SIM_GLOW_MAX` 2, and the breathing's phase). Each texel works the static fields out from the
mask (R8), the heat and pool rasters (RG8) and the broad noise, the fine noise inline, then
`fire_sim_bake`. Drawn whole once, then only over a refresh's `bake_region`, never cleared. The
ground reads one fetch where nothing burns or dries and two where it burns, with no noise or
hashing per pixel. 8,128,512 bytes on a 200 ft map (7.75 MiB; the spike's 14.5 MB held the old
bakes beside it).

### The clusters

`FireClusters` (pure) sums each re-planned block's flame heights on a `CELL_M` 3.5 m grid (kept
per block, merged in block row order, so every peer and every refresh history agree) and finds
the hot spots: a burning cell whose 3 x 3 sum tops every burning neighbour's, so a small fire is
one cluster and a map-wide burn has one per hot spot at least two cells apart (connected
components made the look level's passes one cluster with one light at its middle). Re-planning
one block changes only the clusters within two cells of it. A cluster's size is its flames'
heights squared, summed (about their drawn area), so a blaze's big flames outweigh a wide field
of small ones. The lights and the smoke stand on the largest.

### The smoke

`FireFieldSmoke` raises one plume over each of up to `FireClusters.MAX_SMOKE` 8 of the largest
clusters holding at least `SMOKE_MIN_SIZE` 8 m2 of blaze (ranked by all their flames, so the
biggest fire is the biggest smoker): one quad a column (`PER_SITE` 1) standing on its source and
turning about the world's up axis to face the camera, its unit the cluster's tallest flame
(scaled down for a small cluster), its source `BORN_AT` 0.95 up, `RISE` 3.4 tall, `LEAN` 0.45 down
the map's wind, `WIDTH` (0.3, 0.64). `shaders/fire_smoke_book.gdshader` cross-fades the book's
frames on the column's own clock (`LIFE_S` 10 s, each column within `LIFE_VARY` 0.1) and tones
them live by the sun and the night (lavender-grey by day, a rose foot and darker crown at night,
pink-lavender with a bluer crown at sunset); it is drawn before the flames (render priority -1)
and adds an amber glow at its foot. Its bounds are `FireSmokeBook.DOMAIN` plus the wind's lean.
One buffer is written when the blocks re-plan; nothing runs per frame.

### The lights

`FireLights`: at most `FireClusters.MAX_LIGHTS` 4 shared `OmniLight3D`, no shadows, over the
largest burning clusters,
`RISE_SHARE` 0.7 of the cluster's tallest flame above its centroid within 1.4-2.4 m,
`FireLook.LIGHT_COLOR`, `LIGHT_ENERGY` 18 (0.6 of it over the smallest), **range 8 m with a decay
of 1.4** (`RANGE_M`, `DECAY`). Round 6's own pools carry the burn, so the lights only warm the
ground under and round each fire and leave the char between dark; main's 15 m lights (decay 0.75)
had washed that char a warm orange-brown at night. Shown only while the sun is low
(`FireLook.light_gate` of `FoliageLight.last_sun`, `LIGHT_GATE` 0.1-0.35: off by day, full at
dusk and night); a slow flicker (`FLICKER_DEPTH` 0.22 at 1.7 and 4.3 rad/s) is the only
per-frame work. A lit cluster keeps its light across a re-plan (`FireClusters.keep_slots`). The
painted foliage eases each such light toward a cap (`FOLIAGE_NEAR_CAP` in
`wind_foliage_include.gdshaderinc`), so a canopy beside the fire turns a golden olive rather than
neon. The game adds no other omni light to a scene (only a Blender map's own lamps can), so the
four fit the Mobile renderer's eight per mesh; the env manager skips a FireField when it collects
the map's own lights (counted, they turned the level's sun off in "auto" mode). The rounds that
chose the falloff (ranges 7, 12, 15 and 20 under pixel probes) are in `FireLights`' header.

## Runtime

- `MapSourceLoader` adds one `FireField` under the map root for a document (authoring and play;
  the play-time editor shares it), built whole by `rebuild()` (a load, a late joiner's catch-up)
  and refreshed by `refresh(sample_rect)` (strokes, live ops). Its children, made with the first
  fire: the chunks (`MultiMeshInstance3D` per burning block, one shared material and quad),
  `FireNoiseBake`, `FireLights` and `FireFieldSmoke`. Every peer builds the same plans, rasters
  and fires from the document; the clocks (the drawings, the smoke's loop, the breathing, the
  flicker) are each peer's own.
- A chunk's instance data is one buffer (`FireLook.instance_buffer`): a scale-only basis at the
  foot, then (seed, intensity, kind plus the foot's heat times `FOOT_SHARE` 0.99, the integer
  seed). The first `count` entries of a block's plan show; the buffer is sorted back to front
  along the camera's fixed forward axis once (the camera only pans and zooms).
- The ground binding: `FireLook.bind_glow(ground, sim_map, sim_rect)` sets the terrain
  material's `fire_sim_map`, `fire_sim_rect` and `fire_present` once the bake is drawn
  (`FireNoiseBake.baked`); a field leaving the tree nulls `fire_sim_map` when it was the last
  live field or the terrain holds its own bake, and binds again if it comes back.
- **Warm-up:** `GraphicsWarmup.COVERED_SHADERS` lists `fire_flames`, `fire_smoke_book` and
  `fire_ground_bake` (and the event fire's `fire_smoke`); the port's removed shaders are gone
  from it (test_fire_field_plan checks). Editing `fire_glow.gdshaderinc` re-runs a player's
  first-launch warm-up once, by design.
- **Mobile and Compatibility:** Mac runs the Mobile renderer by default. The books are RGBA8
  arrays without VRAM compression (data, not colour; the flames' with mips), which Metal takes;
  the four lights fit Mobile's eight. The halo round the flames is the game's own glow
  (`EnvironmentGlow`, docs/lighting-and-environment.md "Glow/Bloom"), round 6's screen glow made
  the glow of every map since card fire-prod-c5b, with its intensity doubled on Mobile.
  `jobs/firefeat_look_mobile.json` (2026-10-18, half size): on Mobile, night home shows the
  flames, pools and halos as Forward+ does, the aura a little softer. On **Compatibility** the
  flames do not draw at all (no shader error in the log) and so no halo either; the smoke draws
  (a darker red-orange) and the lights leave faint pools, while the authored ground itself fails
  there (`authored_ground.gdshaderinc` `textureGather` is not in GLES3; the map shows pale grey)
  and the scatter runs out of shader instance variables. Compatibility is not a supported fire
  renderer yet (docs/MAP_AUTHORING.md open work); card fire-prod-c7 takes the verdict captures.
- **The event fire** (Start a fire: `IgniteMode`, `TerrainEvents._burn`, `FireSweep`) is
  untouched by the port and keeps its own look: `EventPuffs`' banded tongues (`band_flames`, the
  `FlameAtlas` flipbook its other branch) on the ground ring and the crowns,
  `event_puff.gdshader`, `GroundBurn` (`ground_burn.gdshader`, on `fire_glow_noise.gdshaderinc`'s
  noise), `SmokePuffs` (`fire_smoke.gdshader`) and `wind_foliage_burn`, the rest on
  `fire_noise.gdshaderinc`. It writes the burnt biome and the ash, never `fire_mask`, so it shares
  nothing at runtime with the persistent fire ([authoring.md](authoring.md) "Live edits").

## Authoring

The Fire tool (`FireTool`, `FireBrush`, `FireToolPane`: Embers 96, Flames 176, Blaze 255;
`FireEditor` behind `AuthoringEditor.begin_fire_stroke`) writes `fire_mask` through a
`MaskStroke` in `MaskBrush.FIRE`; a lay is one "Lay fire" history group (the fire, the burnt
forest only over forest, the ash) and Ctrl puts fire out ("Put out fire", the ash and snags
stay). `AuthoringEditor.apply_mask_diff` calls `refresh_fire` for any diff that writes
`fire_mask`, which refreshes the field over the diff's samples; undo and live ops take the same
path. Arming the tool requests the fire book, so the first stroke's fires have their drawings.
The same brush is a GM brush in play (card F2), its ops `mask` ops. The tool, its pane, its
history parts and its live ops: [authoring.md](authoring.md) "Tools" and "Live edits".

## Verification

Unit tests in `tests/unit/` (all in the authoring subset):

- `test_fire_book.gd`, `test_fire_smoke_book.gd`: the books are checked out (not LFS pointers),
  their layers' count, format, size and mips, `class_first`, bounds and tear layer; each smoke
  seed's loop closes, baked at FireFieldSmoke's rise and width over `DOMAIN`; the textures build
  and are freed with their last reference; FireFieldSmoke binds its book.
- `test_fire_fires.gd`: a centre tops its 2.7 m neighbourhood and no two stand within it; every
  burning flames-band point is covered, a straggler or beside a higher uncovered one; the blaze's
  flames at 0.6 and 1.05; sizes, spill and kernel reach within `HEAT_GROW` and `FEET_GROW`;
  neighbouring blocks' windows agree.
- `test_fire_field_plan.gd`: the plan, the bands, the budget, the rasters, the trig literals,
  refresh-equals-rebuild (ten hard dabs inside, on and across block lines beside fires up to 3 m
  tall: digest, plans, raster bytes, shown counts and every chunk's buffer equal a fresh
  rebuild), the warm-up list, the bake's frame at `SIM_PER_M`, the redraw region at
  `BAKE_REACH_M`, the bake as two RGBA8 tiles (8,128,512 bytes on 200 ft), a worker refresh
  landing what the main thread plans.
- `test_fire_look.gd`: the book is asked for only by a field in the tree with fire, bound with 48
  drawings, tear layer 384 and 16 bounds, and let go (with the smoke's) on the last field's exit;
  the bounds hold every corner of every quad at the jitter maxima for three camera axes; the
  buffer is back to front; every fire carries its own exact integer seed.
- `test_fire_clusters.gd`: the clusters and hot spots, the lights' attenuation, range 8 and decay
  1.4, the smoke's bounds holding the book's frame at the widest lean.
- `test_fire_stroke.gd`, `test_map_document_fire.gd`: the Fire tool's history entries and the
  document's `fire.png`; `test_live_map_edits.gd` runs the fire on the worker for host, peer and
  reload. Over ENet: `tests/net/enet_live_edits` compares `plan_digest` on every op and for the
  late joiner.

Render jobs (`tools/render_jobs/JOBS.md`): `firefeat_build`, `firefeat_look` (production | r6
sheets, held clock, motion bursts) and `firefeat_cleanup`; `fire_mask` (lay and put out);
`fire_shards` (debug view 6 the sim bake's albedo tile); `fire_first_burn` (the book's load and
upload ms); `fire_perf_play`; `fire_smoke_book` (the smoke book's bake). Performance:
[../PERFORMANCE.md](../PERFORMANCE.md) "Fire (F4): pinned performance pass" and its subsections
measured the look before the port; the production fire's pinned numbers come in a section of
their own (card fire-prod-c7).

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-11: the Fire tool and `fire_mask` with a placeholder look (card F1, e6ac5998); the ash
  clears small plants (2bd7b0aa).
- 2026-10-16: the Fire brush in play and its live ops (F2, f794511a); banded-tongue flames, the
  base fire, the char and its lobes (F4a rounds 1-4, dfc7d879 to ed6696c9); lights and a
  leaning plume (F4b-1 rounds 1-5, 4e6d62f2 to 86f387d5); the first-burn hitch and the pinned
  pass (F4b-2, 291d5f4e, 6bdfc4fd); a cost pass (F4b-3, 3bf3ea59); the ground's static and fine
  bakes and the re-plan worker (F4b-4, d1bbc8d7); the smoke's warp and the scorch on the integer
  hash (F4b-5, e6a6fcb2).
- 2026-10-17: the reference fit's round 6 on branch spike-flipbook (de7f3d16, not merged)
  approved for production.
- 2026-10-17 to 18, the production port on branch fire-sim: the fire book as a resource (C1,
  cd9a684b); FireFires' placement, the 8.7 m reach, the sorted splat and `plan_digest` (C2,
  e5d80a83); the flames from the book, the per-fire integer seed, the LOD removed (C3, 6424f379);
  the ground's sim bake alone (C4, e7b7b4bf); the smoke book and the 8 m lights (C5a, acfe9654);
  this doc and the sweep for the old fire's names (C6).
