# Scatter

The plants and rocks of an authored map: the generator that turns a palette biome and painted
density into document rows, and the node that builds those rows into instanced meshes and
rebuilds them cell by cell as an author paints. The long form is
[../ARCHITECTURE.md](../ARCHITECTURE.md) "Scatter generator" and "Authored scatter"; the
performance side is [../PERFORMANCE.md](../PERFORMANCE.md). This doc holds the system's map and
the rules the code keeps (moved from `AGENTS.md` Key Conventions on 2026-10-09).

## Map

| File | Class | Role |
|------|-------|------|
| `utils/scatter_generator.gd` | `ScatterGenerator` | Pure statics. `generate()` turns a palette biome plus density, height and normal Callables into document rows for a set of 10 m chunk cells; `document_fields()` and `generate_for_document()` adapt a `MapDocument` |
| `utils/scatter_plan.gd` | `ScatterPlan` | The sampling plan and the density calibration models: `DENSITY_RESPONSE`, `additive_clumps`, `CLUMP_SATURATION` |
| `utils/authored_scatter.gd` | `AuthoredScatter` | Node3D under `LevelMap` that builds an authored map's palette scatter: `build_all(rows)`, `set_cells(rows_by_cell)`, `attach_document()`, `request_region(rect)`, `species_added` |
| `utils/scatter_regen.gd` | `ScatterRegen` | Regenerates the touched cells on `WorkerThreadPool` |
| `utils/scatter_native.gd` | `ScatterNative` | The one door to the native generator (`native/`, GDExtension class `TTScatterNative`): packs a job's biome once, runs it natively when the library is built, counts outcomes; see "Native path" |
| `utils/pipeline_warmer.gd` | `PipelineWarmer` | Draws each resolved species once, invisibly |
| `utils/scatter_mass.gd` | `ScatterMass` | Grass masses (a clump with `mass` 1, `ScatterPlan.MASS_FIELDS`): ellipse membership, core growth, zone keeps, bare openings, shoulders, and the mass anchors (collect, custom data, the level's anchors entry) |
| `utils/ground_look.gd` | `GroundLook` | A biome's `ground_look`: `BASE` (every contract key) and the lenient merge `PaletteLibrary` keeps on the biome |
| `utils/ground_zones.gd` | `GroundZones` | The per-biome, per-seed zone record (read-only, carried on each mass plan entry) and the CPU twin of the ground shader's zone functions |
| `utils/map_anchors_io.gd` | `MapAnchorsIO` | The optional `mass_anchors.json` entry of `map.ttmap` |

## Model

- Chunk output must stay region-independent: every random choice comes from a hash of (map
  seed, biome, field, bucket, index), never from iteration order or a shared RNG, and spacing
  is resolved by Matern III on that global field. `test_scatter_generator.gd` compares a chunk
  alone, with neighbours and in the whole map byte for byte.
- Thinning (paint, pattern, slope, clumps, relations) happens after spacing, so painted
  density thins even a saturated packing.
- Paint enters through a per-size-class response (`ScatterPlan.DENSITY_RESPONSE`): trees lead,
  ground cover lags, and all are exactly 1 at full paint so the palette calibration holds.
- Overlapping clumps add up (`ScatterPlan.additive_clumps`, capped at `CLUMP_SATURATION`
  overlaps), so dense ground cover forms drifts.
- Terrain response (content library step S12a, 2026-10-24; fields in
  [library.md](library.md) "Terrain response"): a rule may carry `slope_min_deg` and
  `response` curves on the `slope`, `height` and `wet` axes. They are one more keep in
  `ScatterGenerator._evaluate`, after the slope-maximum block and before footing, behind
  `entry.has_response`: a legacy rule never runs the block, so its arithmetic and rows are
  exactly as before (the golden digests are unchanged). `_terrain_keep` multiplies the slope
  minimum band (full from the minimum up, none `SLOPE_MIN_FADE_DEG` = 5 below it, no allowance)
  and each axis' `ScatterPlan.curve_value` (piecewise linear, flat beyond the ends, 0..1); the
  product only lowers the keep, so the candidate supply is still sized for `density_per_m2`,
  which is the density at curve value 1 ("denser in the wet" means a higher `density_per_m2`
  and a curve that peaks at 1 there). Every axis is a pure function of the point (the angle of
  `normal_at`, `height_at`, the stored shore weight `wet_at`), so region independence holds
  (`test_scatter_curves.gd`). The curves multiply with the painted density, the rock and scree
  terms of `ScatterGround` and the landform; they do not replace them. `water_dist` is validated
  and planned (`curve_water_dist`) but not evaluated: it needs a distance grid (S12c) and warns
  once per rule when planned.
- Native (S12b): the library evaluates the same block (`scatter_gen.cpp` `terrain_keep` and
  `curve_value`, expression for expression, after the slope-maximum block and behind
  `Entry::has_response`; `Ground::wet_at` reads the whole-document shore weight like
  `ScatterTerrain.wet_sampler`) and `version()` is `ttscatter 4 curves`. The plan keys
  (`slope_min`, `slope_min_cos`, `curve_slope`, `curve_height`, `curve_wet`, `has_response`) are
  keyed reads with neutral defaults, so a legacy plan loads as before. A library without the
  word `curves` (built before S12b; `native/bin` is gitignored and survives a pull) would load
  and silently ignore those keys, so `ScatterNative._refusal(species)` sends a job with
  evaluated terrain response to GDScript (fallback reason `curves`) and
  `test_scatter_native.gd` fails (it does not pend) until the library is rebuilt. Cost
  (`PERFORMANCE.md` "Terrain response"): under 1 percent of the library's time, about 20 ns a
  candidate that reaches the block; a curved probe-cell job is 20.7 ms native against 768 ms in
  GDScript. Parity: `test_scatter_native.gd` (curves on terraces and rolling ground, dry and with
  a shore weight, each kind alone, region independence) and the valley and lakeshore whole maps
  with curved rules in `test_scatter_native_landforms_dry.gd` and `_wet.gd`, rows and anchors
  byte-identical to forced GDScript.
- Grass masses (ground ship, contract section 9 "Ground look and grass masses"): a clump with
  `mass` 1 keeps the union of its clumps, may be an ellipse turned per parent (or along the
  zone edges with `follow`), grows its core tufts into one mound, and drops whole swathes by
  the zones the ground draws. The zones come from the biome's `ground_look` and the map seed
  (`GroundZones.record`, `seed_offset`), built once per plan and read by the workers; no level
  stores a zone field. A palette without the mass fields grows exactly the rows it grew before
  (`test_scatter_mass.gd` pins every built-in biome's rows at seed 1234: first written on main's
  code path; re-pinned at the ship palette's install, where the six zoned biomes' grass moved
  and the taiga, badlands and burnt forest, which carry no mass fields, kept main's rows).
- Each mass row carries its anchor (the clump parent) beside the rows, keyed by the row's saved
  (x, z): the generator fills `ScatterRegen.run`'s "anchors" (passed through the result, never
  a static table: the round 10 probe kept one, written from `WorkerThreadPool` threads, and one
  of its runs died silently; cause unconfirmed, 2026-10-14), `AuthoredScatter.mass_anchors`
  merges them and every MultiMesh it builds (settled, growing and shrinking nodes) writes
  `Color(0, dx, dz, 1)` into the instance's custom data (`.x` stays free for the burn shader).
  A level saves them as the optional `mass_anchors.json` entry; `MapSourceLoader` validates it
  against the rows and each rule's reach and drops a bad asset's anchors with a warning. GLB
  scatter (`BaseScatterEraser`) and the pipeline warm-up never carry anchors. The generator
  snaps each offset to the 0.1 mm the entry is written with (`ScatterMass.collect`,
  `MapAnchorsIO.snap`), as it snaps the rows, so a session and the same level reopened (or a
  peer) draw the same offsets bit for bit; unsnapped, a mass on a `GroundMassStamps` grid line
  regrouped on reopening and its shade stamp moved (2026-10-15).
- Every chunk node an authored scatter builds (`ScatterGlbUtils.build_chunk`: settled, growing,
  shrinking) draws on `LevelEnvironmentManager.SCATTER_RENDER_LAYER`, which the level's
  reflection probe leaves out: the probe captures once when a map opens, before a new map's
  cover grows in but after a reopened level's is built, and a probe that saw the scatter drew
  reopened ground and grass 3-6 levels darker (2026-10-15). A side effect: the probe's
  reflections, water's among them, no longer show an authored map's scatter on a reopened
  level; a new map's never did. A Blender map's own scatter stays on layer 1.

## Runtime

- `AuthoredScatter` builds with `build_all(rows)` at load and `set_cells(rows_by_cell)` per
  10 m cell, with one always-suffixed `<asset>_MultiMesh_c<x>_<z>` node per (asset, cell).
- Species resolve once and rebuilds never create materials. A species first painted
  mid-session emits `species_added`: pass it to `GameMap.adopt_foliage_materials()` and
  `LevelEnvironmentManager.add_wind_materials()`.
- Never rebuild authored cells through `build_scatter()`.
- Authoring prepares every palette biome as a map opens (the first palette mesh load compiles
  the pipelines all species share, under the loading screen), and each resolved species is
  drawn once invisibly by `PipelineWarmer`; see [../PERFORMANCE.md](../PERFORMANCE.md)
  "First-use pipeline compilation in authoring".

## Authoring

Brushes call `attach_document()` + `request_region(rect)`, which regenerates the touched cells
plus the relation halo on `WorkerThreadPool` via `ScatterRegen` (latest request wins per cell)
and grows new instances in ("Arrival motion" below). Removed
scatter shrinks out ([authoring.md](authoring.md)), including rows a later apply drops while
they are still growing in (from the size they reached).

A biome stroke's frames are live requests (`request_region(rect, true)`, from
`AuthoringEditor.flush()`). Under latest-wins alone nothing under a brush that is still down
ever lands, so a live cell also gets lead jobs: its dirty work restricted to the species
outside the ground class. Species resolve large to ground and only look at earlier ones, so a
lead job's rows are exactly what the full job gives them, at a few ms per species where a
painted cell's ground cover costs hundreds. Lead results show provisionally (never current,
never cancelled; one out per cell, at most one per 100 ms, only while requests keep coming),
and the cell's full job still lands under latest-wins, so the final rows are unchanged. Trees,
shrubs and rocks appear about 0.2-0.4 s after the press; the ground cover follows with the full
job after the brush lifts or moves on. Other callers (undo, live edits, sculpt, crossings, fire)
send ordinary requests and keep latest-wins alone. `AuthoredScatter.live_applies` turns it off
for measurement. Card brush-latency, numbers in [PERFORMANCE.md](../PERFORMANCE.md) "Brush
latency".

Where jobs run natively (below), a painted cell's whole job costs about 20 ms, so lead jobs are
whole (`ScatterRegen.whole_leads`, set by `AuthoredScatter.attach_document` from
`ScatterNative.active()`; card native-cover): a lead job carries every dirty species, ground
cover included, and is the cell's full job, only protected. It takes the cell off pending, is
accepted when it lands current and shows provisionally when stale; while the brush is on a cell
it gets no other job. The ground cover grows in under the brush, raised at each landing; rows
that stay keep their keys (no regrowth) and rows a landing drops shrink out (about 1 % of the
ground rows in a stroke, more in a held dab). The GDScript path keeps the restricted lead jobs.

Landing (`ScatterApply`, `utils/scatter_apply.gd`; card native-cover round 2). Finished jobs
land on the main thread by cost, not count: a cell lands only the newest of its waiting results
(`ScatterRegen.landed()` frees a cell for its next lead as soon as one finishes on its worker, so
an older result still waiting is dropped, never shown in sequence); waiting results land nearest
`ScatterRegen.focus` (the latest live request) first; each frame lands results until
`ScatterApply.BUDGET_USEC` (2 ms) of rebuild time is spent, judged from the rows a result
carries at the measured cost per row, and always at least one; a provisional landing that
changes no rows is skipped, and so is one outside the brush rectangle that changes at most
`NEAR_NOTHING_ROWS` (2). Most whole-lead landings change nothing (773 of 888 in a measured
stroke), which is where round 1's frame cost went. The rebuild itself (`AuthoredScatter`,
`lean_rebuild`) leaves an asset whose rows are unchanged alone, keeps each asset's row keys
with its rows instead of recomputing them, and merges finished grow-ins of one asset into the
cell's node together (`MERGE_BATCH` 3, or when none is still growing) rather than one rebuild
each. Numbers in [PERFORMANCE.md](../PERFORMANCE.md) "Ground cover under the brush".

### Arrival motion

How new rows arrive and removed ones leave (`ScatterArrival`, `utils/scatter_arrival.gd`; card
motion, the user's pick "STAGED + LIFE" from the brushland feel probe, 2026-10-20):

- **Staged.** On a brush landing each species waits by its palette size class: large at once,
  medium 0.12 s, small 0.24 s, ground cover 0.36 s (`STAGE_STEP`; an unknown class counts as
  medium). The painted thing arrives first and the floor answers. Shrink-outs are staged the same
  way. A direct `set_cells()` (a prop placed or removed, an undo of props) is not staged, so a
  rock the Place tool puts down shows under the cursor at once.
- **Life.** Plants grow with a back-out ease over 0.42 s that peaks about 10 percent over full
  size, each instance after a ripple delay of 0.06 s per metre from the brush centre, at most
  0.35 s. Each wind instance works its own size out in the vertex shader
  (`shaders/wind_foliage_grow.gdshaderinc`: `grow_wave`, `grow_clock`, `grow_scale()`, included
  by `wind_foliage_main.gdshaderinc` and the three debug variants), so the CPU still writes one
  uniform per animating node per frame. Rocks drop in from 0.6x their height (0.3 to 1.2 m) over
  0.32 s, a fall then an 8 percent rebound, each instance through its own MultiMesh transform
  after its own delay (hidden until then, as a zero basis). Removed plants swell and collapse
  over 0.3 s, rippling; removed rocks hop and sink.
- **Brush centres.** Each `ScatterRegen` job carries, per cell, the point its rows ripple from:
  the centre of the request nearest the cell's middle since the cell last landed current. A dab
  ripples from the dab, a stroke from the nearest point of its path (so a trail spreads out
  sideways from where the brush passed, instead of every cell behind the brush waiting out the
  longest ripple); a request that is not live fills only an empty entry. `ScatterApply` passes
  them to `rebuild_cells(rows, animate, centres)`.
- **No restart.** A row's stage and ripple delays are fixed when it first appears: new rows get
  their own grow node and tween, and later landings that keep them leave that node running, so a
  held brush's provisional landings (about every 100 ms per cell) never start a row over. A row
  removed mid-arrival shrinks from the size or height it reached (`ScatterArrival.as_shown`).
- **The burn variant** (`wind_foliage_burn.gdshader`) includes `wind_foliage_include.gdshaderinc`,
  not the main include, and neither changed: it keeps `VERTEX *= grow` and gains no uniform, so a
  tree growing in under a burn material shows at full size at once, as before
  (`test_scatter_arrival.gd` pins that its expanded source never reads the new uniforms).
- Each peer animates its own rebuilds from its own landings; nothing is synced.
  `ScatterArrival.classic` restores the earlier grow-in (all at once, cubic over
  `grow_seconds`, rocks rising) for measurement and side-by-side films only. Numbers in
  [PERFORMANCE.md](../PERFORMANCE.md) "Arrival motion".

## Native path

`ScatterRegen.run` hands each biome of a job to `ScatterNative.run_biome` first (card
native-scatter, 2026-10-20). Where the native library is built, the job runs in C++
(`native/src/`, a port line for line with `scatter_generator.gd`, `scatter_clumps.gd`,
`scatter_mass.gd`, `ground_zones.gd`, `ground_accents.gd`, `terrain_rules.gd`,
`ScatterGround.sampler`, `WaterDressing.sample` and `CrossingGeometry.clearance`) and gives the
same rows and mass anchors bit for bit, about fifty times faster; where it is not (a fresh clone,
a platform whose library failed to load) the job runs in GDScript as before. CI builds the
library for every export platform, checks it on each, and ships it in every export (see
"Building" below).

- **One call per job.** `ScatterNative.pack()` builds the plan (`ScatterPlan.build`), the
  window's grids with document_fields' and the sampler's own GDScript calls (density decode,
  `TerrainRules.sample_fields`, `face_proximity`, painted fields, fringe, the water field and
  the crossings), each species' pattern-noise settings and a constants table read by name; the
  library reads the plan's Dictionaries directly and returns `{rows, anchors, usec}`. No
  Callable crosses; the samplers are native over the packed grids.
- **Exact rows.** godot-cpp's Vector2, Vector3, Quaternion, Basis and Rect2 carry the engine's
  float32 formulas, scalars stay double, `-ffp-contract=off`, no fast-math, and the Windows
  build links the msvcrt runtime the official Godot binary uses (llvm-mingw), so libm gives the
  same last bits. FastNoiseLite is Godot 4.7.2's own header, set up as its resource sets it up.
  `test_scatter_native.gd` checks the noise on every palette setting and the rows of a painted
  cell of every biome and of the five landform maps' whole builds (water, steep faces, a
  crossing); it is pending without the library. Parity is per platform: native against
  GDScript on the same machine, never one platform's rows against another's.
- **Never mixed.** A job runs whole natively or whole in GDScript (later species read earlier
  species' memos). `run_biome` returns null to fall back; `ScatterNative.fallbacks()` counts
  outcomes by reason ("native", "forced", "missing", "grids"), and `force_gdscript` sends every
  job to GDScript for A/B runs and tests. A branch added to the GDScript generator must be ported
  (and its parity cell added to the test) or refused in `ScatterNative._refusal`.
- **No class identifier.** No script names `TTScatterNative`: a missing library would make it
  fail to parse. `ScatterNative` finds it through `ClassDB.class_exists` and `instantiate`.
- **Reentrant.** Each call builds its own context (memos, the edge and anchor slots, the noise
  objects); nothing mutable is static, and the library calls no engine API but Variant reads, so
  any number of WorkerThreadPool tasks may run jobs at once.
- **Building.** `native/SConstruct` builds godot-cpp (submodule, 10.0.0-stable, api 4.7) and the
  library, and writes `native/tt_scatter.gdextension` beside it; both are gitignored, because a
  `.gdextension` whose library is missing prints three errors at every start. Re-import after a
  build (`.godot/extension_list.cfg`). A loaded DLL is locked on Windows: stop every Godot
  process of the project before rebuilding. Removing a built library leaves Godot erroring on the
  stale list until `.godot/extension_list.cfg` is deleted and the project re-imported. Commands in
  `AGENTS.md` "Testing".
- **In CI.** `.github/workflows/native.yml` builds all six libraries (Linux x86_64 on glibc 2.28,
  Windows x86_64 with llvm-mingw on msvcrt, macOS universal; debug and release), each on the C
  runtime its official Godot binary uses, since libm's last bits must match the engine's.
  `native-parity.yml` and build.yml's test job run `test_scatter_native` on all three platforms
  with the official binary, debug and release libraries, and the exports ship the release one
  beside the binary (in `Contents/Frameworks/` on macOS). A Linux library may need no newer
  glibc than Godot's Linux template, or it would not load on the older machines the game runs
  on. The checks and how to test CI changes without publishing: `AGENTS.md` "CI/CD".

## Verification

Unit tests in `tests/unit/`: `test_scatter_generator.gd` (region independence, byte for byte),
`test_scatter_generator_calibration.gd`, `test_scatter_build.gd`,
`test_scatter_ground_rules.gd`, `test_scatter_chunker.gd`, `test_authored_scatter.gd`,
`test_pipeline_warmer.gd`, `test_scatter_mass.gd`, `test_scatter_native.gd` (native against
GDScript; pending without the library), `test_scatter_curves.gd` (S12a: the curve maths, neutral
plan values for legacy rules, identity curves byte-equal to none on two real biomes, a slope
curve's density falling in proportion on an analytic ramp, `slope_min_deg` and its 5 degree fade,
the height and wet axes, axes multiplying, region independence with curves, the document
adapter and the native refusal). Timing: `tools/native_scatter_bench.gd` through
`tools/native_scatter_run.gd` (tasks job, threads, map, counts, curves).

`test_scatter_mass.gd`'s golden rows (`tests/fixtures/scatter_golden_1234.json`) run on Windows
only, where the pre-push gate runs them; elsewhere the test is pending. The digest hashes raw
float bytes and the platforms' maths libraries differ in the last bit: CI on Linux (run
38845734590, after the ground ship's push on 2026-10-15) generated other bytes for six of nine
biomes, the taiga and the trees included, though no mass field touches them (9980dfbc).

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
