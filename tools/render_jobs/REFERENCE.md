# Render jobs reference

The job file format, every op, the probe scripts for `call`, the capture readers and the
harness's caveats. How to run a job, the flags, where captures land and the build / look
loop are in [README.md](README.md); the jobs themselves are catalogued in
[JOBS.md](JOBS.md).

## Why 1920x1080 is forced

On the user's portrait monitor the `--resolution` flag alone produced odd window sizes (the
window was clamped or rescaled to fit the screen), so captures from different runs did not
match. `run.gd` sets the window to 1920x1080 on the primary screen after the scene loads,
and every capture log line records the actual image sizes so a wrong size is visible.
Captures are then halved to 960x540 unless the run passes `--full`. A job that needs another
size resizes the window in a step after that (`ui_primitives.gd` or `avatar_builder.gd`
`window`); 1280x720 and 1720x720 both took on the primary screen (`ui_tour`, 2026-10-09).
The UI scales with the window (stretch mode `canvas_items`, aspect `expand`), so the 1080p
virtual canvas stays 1080 high: a 1720x720 window is a 2580x1080 canvas.

## Tagging a job for build and look

The build / look loop is in README.md "Build once, look many". Tagging a job:
`"phase": "build"` on every step that shapes the document (and the `look_at` / `zoom` /
`wait` that set up the strokes' view), `"phase": "look", "for": "<capture>"` on a camera
move, probe toggle or wait that serves one capture (a comma list or a wildcard when it
serves several: `"for": "{biome}_*_play_*"` on a play section), nothing on steps that must
run either way (`no_autosave`, `env.gd`, `falls.gd falls` for its `found:` names,
`hide_ui`, a toggle that restores state, `title`). A `saved` op (or the top-level `saved`
key) names the level to load; inside an `expand_biomes` template it is one level per
biome.

## Job file format

```json
{
  "out_dir": "render_jobs/my_run",
  "timeout_s": 900,
  "remove_override": false,
  "steps": [ {"op": "wait", "s": 1.0}, ... ]
}
```

Top-level keys:

| Key | Default | Meaning |
|---|---|---|
| `steps` | required | Array of step objects, run in order, each over one or more frames. |
| `out_dir` | `user://render_jobs/<job name>` | Output folder (README.md "Where captures land"). `--out` overrides it. |
| `timeout_s` | 300 | Hard stop in seconds from launch; the run quits even if steps remain. |
| `hang_s` | 60 | Watchdog: when no frame completes for this many seconds, log a `HANG:` line (stderr and `log.txt`) and kill the process. The same watchdog kills a run still alive 30 s past `timeout_s`. The last `step` line before the `HANG` line is the step that hung. |
| `remove_override` | false | Delete `res://override.cfg` right after startup (the engine has already read it). Use it when you drop in a temporary `override.cfg` for one run (for example to pin a setting), so the file never outlives the run. The harness never creates one itself. |
| `saved` | none | `{"folder": "<level folder>", "load": "dress" or "play" (default `dress`), "settle": 2.0}`: the saved level `--saved` loads in place of the job's build steps (README.md "Build once, look many"). The `saved` op declares the same from inside the steps (per expansion). |

Every step has an `op`. Steps that finish immediately advance on the same frame; `wait`,
`wait_ready`, `stroke`, `capture` and `gpu` take several frames. An unknown op logs
`unknown op` and is skipped. Any step may also carry:

| Field | Meaning |
|---|---|
| `phase` | `"build"`: skipped by `--saved` (the saved level is loaded where the first skipped build step was). `"look"`: skipped by `--only` when its `for` serves no capture that runs. Absent: the step always runs. |
| `for` | On a `"phase": "look"` step: the capture names it serves, comma-separated, `*` and `?` wildcards allowed. The step runs when any capture in the job matching an entry is taken by `--only`, or when an `--only` pattern matches an entry directly (a name that is no capture, say `falls_gpu` on a GPU A/B). |
| `scale` | On a `capture`: the image scale, which wins over the run's default (0.5, or 1.0 with `--full`). Perf jobs pin 0.5; a pixel-exact diff pins 1.0 (`avatar_probe.json`'s twins). |

A skipped step logs `skip <op> (<reason>)`.

### State and maps

| Op | Fields | What it does |
|---|---|---|
| `title` | none | Switch to the title state (`change_state(0)`), without the leave prompt and without saving. |
| `wait_title` | none | Wait until the title state is current: the first-launch graphics warm-up (`Root.State.WARMING_UP`) has handed over. Put it first in any job that may boot into the warm-up. |
| `new_map` | `biome` (palette biome id, `""` for bare ground), `size` (ft, default 200), `seed` (default 1234), `landform` (a `StartingLandform.KINDS` id, default `flat`) | Open a new map in authoring, as the New map dialog does. The default `flat` keeps older jobs on the ground they were written for. |
| `dress` | `folder` (level folder under `user://levels/`) | Open an existing level in authoring; a GLB-only level opens as a dressing layer. Nothing is written unless something saves. |
| `play` | `folder` | Load that level folder and play it (`_on_play_level_requested`). |
| `wait_ready` | `settle` (s, default 2.0) | Wait until the map has loaded, authoring is open, and the scatter is neither regenerating nor growing, then `settle` more seconds; the timer restarts whenever any of those is busy again. |
| `wait` | `s` (default 1.0) | Wait that many seconds. |
| `no_autosave` | none | Stop and disconnect the authoring autosave timer. |
| `hide_ui` | `hide` (default true) | Hide (or with `false`, show) the authoring panel. |
| `expand_ab` | `configs` (array of ground shader versions), `label`, `s` (default 3.0) | An in-run ground shader A/B: per config, swap the terrain's shader (`probes/ground_perf.gd` `shader`; `"std"` draws the chunks with `perf.gd`'s StandardMaterial3D instead), wait 0.5 s and sample GPU time for `s` seconds (`perf.gd` `start` / `stop`). Run `vsync_off` first. |
| `expand` | `template` (array of steps), `values` (array) | Insert `template` once per entry of `values`, in order, with `{value}` replaced by it anywhere in the template's strings (level folders, for example, where `expand_biomes` only takes palette biomes). |
| `expand_biomes` | `template` (array of steps), `biomes` (optional array of biome ids) | Insert `template` once per biome in the installed palette (`PaletteLibrary.biomes()`, palette order; only the ids in `biomes` when given), with `{biome}` replaced by the biome id, `{name}` by its display name and `{path}` by its first path surface (`dirt` when it lists none), anywhere in the template's strings. |
| `saved` | `folder`, `load` (`dress` default, `play`), `settle` (default 2.0) | Declare the saved level that `--saved` loads (with `wait_ready` after it) in place of the build steps that follow, until the next `saved`. Does nothing without `--saved`. Put it first in an `expand_biomes` template (`"folder": "_p4c_{biome}"`) so each biome loads its own level. |

### Camera

| Op | Fields | What it does |
|---|---|---|
| `home` | none | Reset the camera to its home view. |
| `zoom` | `size` (optional) | With `size`, set the target orthographic size (it eases there, so follow with a `wait`). Without it, zoom out 60 steps, which reaches full zoom-out. |
| `look_at` | `at` ([x, z] world metres) | Pan so the screen centre looks at that ground point. |

### Authoring edits

| Op | Fields | What it does |
|---|---|---|
| `stroke` | `points` ([[x, z], ...] world metres), `curve` (default false: a Catmull-Rom curve through the points, as a hand draws, instead of straight runs), `mode` (`paint` default, `thin`, `clear`, `sculpt`, `surface`, `water`: `shape` `river` or `pond`, `depth` `ankle` / `waist` / `deep`, `flow_speed`, `ctrl` erases), `biome` (for `paint`), `tile` (for `sculpt`: `raise` default, `smooth`, `flatten`, `tier`), `surface` (for `surface`: a palette surface, picked as its Paint tile is), `ctrl` / `shift` (for `sculpt`, and `ctrl` for `surface`, which erases paint: held at the press), `radius` (default 4.0), `flow` (default 1.0), `speed` (m/s along the path, default 6.0), `hold` (s to hold at the end, default 0), `keep_active` (default false), `release` (default true) | Paint a brush stroke through the real brush tool, moving the pointer along the polyline at `speed`. `paint` uses the biome tool with `biome`; `thin` uses the thin tool; `clear` is the thin tool with Ctrl held; `sculpt` picks the Sculpt tile as the panel does. On sculptable ground the pointer aims at the ground's current height. `keep_active` releases the press and finishes the gesture without deactivating the brush; `release: false` leaves the stroke held at the end point (it keeps dabbing there) for a capture mid-stroke, until a `release` step. |
| `release` | none | Ends a stroke left held by `release: false`, keeping the brush active. |
| `cancel` | none | Cancels a stroke left held by `release: false`, as a right click does (a river being drawn is dropped). |
| `hover` | `at` ([x, z]), `tile` (default `tier`), `radius`, `ctrl` | The Sculpt tool with `tile` over `at`, not pressed, Ctrl as given: the cursor and its Tier / Flatten readout as an author sees them before pressing. |
| `place` | `biome`, `species`, `at` ([x, z]) | Place one prop of that biome's species at the point and commit it. If the biome or species is not in the palette, logs `no species <s> in <b>; not placed` and carries on. |
| `bridge_kind` | `kind` (`plank` default, `stones`, `arch`, `ford`: any `Crossing.KIND_NAMES` entry) | Pick that Bridge tile (P4b-2, P4d-3): the Bridge tool becomes the active tool with that kind. An unknown name logs and picks `plank`. |
| `gesture` | `points` ([[x, z], ...]), `speed` (m/s, default 4.0), `ctrl` (held throughout), `press` (default true), `release` (default true), `hold` (s at the end) | A left-button drag through real input events (`Input.parse_input_event`: motion, press, motion along the points, release), so the whole path from GameMap's `_input` through `BrushTool.decide()` runs. Each point is aimed at the top walkable surface there (a downward layer-1 ray: ground, deck or stone), where a real pointer over what is drawn would be. `release: false` stops still pressed for a capture; a later `gesture` with `press: false` carries the drag on, or an `input` release ends it. |
| `input` | `events` (one per frame): `{"type": "move", "at"}`, `{"type": "press" / "release", "at", "button" ("left", "right")}`, `{"type": "key", "key" ("ctrl", "escape"), "pressed"}`; mouse events take `ctrl` | Single real input events, as `gesture` sends them: hovers with Ctrl, clicks, key presses. |

### Capture and output

| Op | Fields | What it does |
|---|---|---|
| `capture` | `name`, `desc` (caption for the index), `scale` (default 0.5, or 1.0 with `--full`; the step's own value wins) | After the next frame is drawn, save `<name>_sub.png` (raw SubViewport) and `<name>.png` (window), resized by `scale` (Lanczos) when it is not 1, and log both sizes and the camera size. With no map open (a dialog over the title) only `<name>.png` is written. `--only` skips captures whose `name` matches none of its patterns. |
| `index` | `title`, `intro` | Write `INDEX.md` in the output folder: title, intro, then a table row per capture so far (window image, raw image, camera size, caption). |

### Measurement

| Op | Fields | What it does |
|---|---|---|
| `vsync_off` | none | Disable vsync and turn on render-time measurement for the world viewport. Needed before `gpu`. |
| `gpu` | `name`, `s` (default 2.0) | After a 0.3 s settle, sample the world viewport's GPU render time every frame for `s` seconds and log median, p10, p90 and sample count. |
| `record` | `on` (default true), `name` (default `rec`) | Start recording CPU frame times; `on: false` stops, logs frame count, median and worst, and writes `<name>_frames.txt` with one line per frame (frame time, pipeline compilation counters, process time). |

### Escape hatches

| Op | Fields | What it does |
|---|---|---|
| `eval` | `expr` | Run a Godot `Expression` with the main scene (`Root`) as base instance and log the result, for example `_game_map.get_brush_tool().deactivate()`. Expressions cannot assign. |
| `call` | `script` (a `res://` path), plus any fields the script reads | Load the script and call its static `run(root: Node, step: Dictionary) -> String`, logging the returned string. If the script fails to load, the rest of the job is skipped. |

## Probe scripts for `call`

In `probes/`. Each is a static `run(base, step)`; every field is optional.

| Script | Fields | Effect |
|---|---|---|
| `env.gd` | `color` ([r, g, b]), `mouse` ([x, y]), `recentre` (bool), `skirt` (bool) | Flat background colour; the cursor position zoom-toward-cursor uses (the judgment set pins it to the screen centre so zoom-out is repeatable); camera clamp to fitted map bounds on or off; terrain skirt visibility. |
| `ground_params.gd` | `params` ({uniform: value}), `broad_factor` (int) | Set ground shader uniforms for an in-run A/B; rebuild the broad weight texture at a different box-filter factor. |
| `tree_fade.gd` | `params` ({uniform: value}), `factor` (float) | Set occlusion-fade uniforms on every registered tree material; set the brush's canopy fade radius factor (0 turns it off). |
| `close_zoom.gd` | `action` (`camera` default, `back`, `fade`), `d`, `on` | Trees at close zoom (Polish): `camera` logs the camera's size, position, near and far, the ray origins' heights (on the near plane, so where it cuts) and the centre ray's distance from them to y = 0; `back` moves the camera `d` metres along its view axis (same orthographic frame; negative moves it nearer); `near` sets the camera's near (`near`, default 0.001: the plane before the canopy hold, for an A/B; a zoom restores the hold); `shadow` logs the sun's shadow distance and splits, and sets the distance (`max`); `fade` turns the close-zoom canopy fade off (`canopy_part` 0 on every foliage material that takes part) and back on for exactly those. |
| `reflection_probe.gd` | `visible` (default true) | Show or hide the level reflection probe; logs its box and the environment's SSIL/SDFGI/glow/fog/tonemap switches. |
| `grid.gd` | `visible` | Log, and optionally set, the grid overlay's visibility directly (bypasses the grid policy; fine for a render session only). |
| `scatter_warm.gd` | `warm` (bool), `use_biome`, `tool`, `select` | Toggle `AuthoredScatter.warm_pipelines`; choose the brush biome and/or the biome tool without painting. Logs pipeline compilation counts. |
| `prepare_biomes.gd` | `all` (bool) | `all: true` starts preparing every palette biome on the authoring scatter; a later call without it reports whether preparation finished and how long it took. |
| `additive_clumps.gd` | `additive` (default true) | Set the static `ScatterPlan.additive_clumps` switch for an A/B; call it before painting. |
| `ground_check.gd` | `action` (`survey` or `rows`, default `rows`), `near` ([x, z, r]) | Layer-1 downcasts against the opened map. `survey`: one ray per document sample (timed), misses, ground and document height ranges, the 10 m cell with most relief, layer-1 bodies. `rows`: each scatter row's Y against the ground under it (mean and worst \|dY\|, rows off by > 0.1 m) and the mean angle between row up and ground normal for normal-aligned and upright assets. Used for the dressed-map ground fix (P3-0). |
| `grid_ground.gd` | `action` plus its fields (see the script header) | The grid on a Blender map's ground (P3-3c). `survey` samples the loaded map's layer-1 collision at each of `spacings` and logs ray time, misses and the interpolation error against the collision at `n` random points, plus the share of the ground near Y = 0; `fit` logs the last grid ground fit (play and authoring); `grid` logs the overlay's ground state; `key_g` presses G; `measure` and `drag` turn the measure tool and a token drag's grid auto-show on or off; `token_at` lists tokens; `play_res` plays a built-in `res://` level. |
| `sculpt.gd` | `action` plus its fields (see the script header) | The sculpt pipeline (P3-3a), driven through `AuthoringEditor` since there is no Sculpt tool yet. `stroke` runs a height stroke over real frames (`sculpt`: raise / lower / smooth / flatten / tier; the step's own `op` is `call`) and logs frame times, the worst frame and its breakdown (ray, dab, terrain, collision, snap, rows moved, chunks), `end_stroke`'s cost by part (terrain, collision, snap, rule fields), then the regeneration tail with its parts summed and its worst frame's parts (terrain settling, collision, snap, rock keeping, cells applied) and the plants grown and shrunk against the instances really added and removed (the tail's first frame also carries the probe's own key snapshot, 17-20 ms on 8.5K rows); `compare` times whole-chunk rebuilds against in-place updates; `collision` times the collision rebuild and the CPU ray march; `snap_dense` times snapping the densest cell; `check` tests rays, rows, in-place chunks, AABBs and the near plane; `view_shift` measures how far the view moves when the terrain top rises; `look_bottom` puts a point at the bottom edge. A capture during a stroke lands in its worst frame (about 1 s for the PNG), so measure strokes without one. |
| `perf.gd` | `action` plus its fields (see the script header) | Performance passes: `start` / `stop` sample every frame's CPU frame time and world-viewport GPU time and log n / median / p95 / worst (run `vsync_off` first); `info` logs visible and shadow draw calls and primitives plus scatter instance counts; `mem` logs engine memory monitors (`ws: true` adds the process working set via one powershell call); `play` / `author` / `dress` time a load, the loading screen and the palette resolve; `scatter`, `ground_std`, `broad`, `layers`, `skirt` toggle ground and scatter configurations for in-run A/Bs; `gpu_state` logs one `nvidia-smi` query (utilisation, temperature, P-state, clock) as the pinned procedure's idle check (P4b-3). Used for `PERFORMANCE.md` "In-game authoring: pinned performance pass". |
| `terrain_shapes.gd` | `action` plus its fields (see the script header) | The automatic dressing (P3-4) without Sculpt or Paint tools: `plateau` (stacked 1.524 m tiers with one-sample faces and an optional rounded lip), `hill`, `hollow` write the document heights and refresh terrain, collision, plants and ground like an undo; `path` / `area` paint a surface into the document; `stats` counts samples by rule weight (TerrainRules). |
| `water.gd` | `action` plus its fields (see the script header) | Authored water at runtime (P4-2) without the carve or Water tool: `build` writes a sloped map with a three-reach river, a deep pond and a waist basin into the open document and refreshes terrain, plants and water; `save` writes it as a `_p42_*` test level; in play `tokens` spawns tokens, `drag` drags one through DragAndDrop3D, `report` logs each token's base, bed, surface and float state, `points` / `measure` log beds, surfaces, landings, the grid field, the drag resolver and the measure tool's rays; `water` hides or shows every water mesh (GPU A/B); `scan` finds a Blender map's water and names points for later steps (`"found:deep"`); `look` pans to a point; `state` logs the water nodes and the grid field. P4-3, through the `AuthoringEditor` water API: `tilt` slopes the open map; `carve` carves a river (`points`, `half_width`, `depth`, `speed`; logs its reaches and timings and names each step between reaches `"found:c<n>_joint<k>"`); `pond` paints a pond (`points`, `radius`, `depth`); `erase` erases water (`points`, `radius`); `check` logs the bodies, the dressing's coverage, plants standing in the water and the ground layers; `profile` logs ground and depth along every river; `joints` names every reach step drawn so far (any tool) `"found:joint<k>"` (P4-5); `save` also takes `_p43_*`, `_p44_*` and `_p45_*` folders and `cleanup` deletes every such folder. `tokens` takes `assets` ([[pack, id]]) or else spawns the first cached asset that is not a light (P4-5: the first one used to be `misc/lightglobe`, an emissive globe with its own light, whose glow read as blown-out bright blobs on the water in every capture with tokens). |
| `water_params.gd` | `params` ({uniform: value}), `shader` (`"current"` or a zip path), `glow` (bool), `sun_pitch` (degrees) | Water shader A/Bs (P4-5) on the shared water material: set uniforms (logs the old values); swap in `shaders/water.gdshader` from a zip made with `git archive --format=zip --output=<path> <commit> shaders/water.gdshader` (an older shader) or put the current one back; turn the environment's glow off or on; set the sun's elevation. Call it after a level load (a load re-applies the level's water settings). |
| `p4b.gd` | `action` plus its fields (see the script header) | Phase 4b follow-ups (P4b-0): `line` logs ground, water level, depth, the wet dressing (bed, shore, wet line) and a surface's painted weight at points along a line on the open authoring map (the path-meets-water fix); in play `cues` logs every token's height, base, the surface over it and whether its submerged cue shows, `hold` picks a token up through DragAndDrop3D and holds it over a point (edge pan off, since it reads the real cursor) for a mid-drag capture, `drop` releases it; `load_profile` (from the title) times each main-thread part of loading a level's `map.ttmap` (terrain wet and dry and its parts, the wet dressing, the water mesh and nodes, the workers' share and what is left on the main thread with their output). |
| `crossing.gd` | `action` plus its fields (see the script header) | Crossings (P4b-1) through the `AuthoringEditor.crossings` API: `place` (`kind` `plank` or `stones`, `from`, `to`, `width`) snaps a line across the water to the banks and logs the id or refusal, anchors, span, levels, style and times, naming `"found:c<id>_mid"`, `_a`, `_b` and `_stone<k>`; `report` lists the crossing nodes; `undo`; `save` writes a `_p4b1_` test level and `cleanup` deletes every `_p4b1_*` folder; `look`, and in play `tokens` and `points` (water.gd's, with `found:` names resolved). P4b-2: `list` logs every crossing (id, kind, anchors, levels, width) and names its `found:` points; `timing` the Bridge tool's last plan and the last edit's refresh, build and swap; `bench` (`kind`, `from`, `to`, `runs`) times `plan()` and one place and undo; `first_use` (`kind`, `from`, `to`, `style`) times a crossing node's first-use parts for a style (material, shader, mesh, body, entering the tree). P4b-3: `list` names stones too; `visible` shows or hides every crossing's meshes (a GPU A/B; `"off ..."` labels from `expand` hide); `save` and `cleanup` also take `_p4b3_` folders. |
| `falls.gd` | `action` (`falls`, `look`, `falls_visible`, `quality`, `clock`, `palette`) plus its fields | Waterfalls (P4c-2): `falls` logs every fall the open document derives (`WaterFalls.falls`: reaches, lip, direction, drop, half-width, the carved face foot and plunge pool, the steepest slope, the ground along the lower course from the lip every quarter metre) and names `"found:fall<k>_lip"`, `_foot` and `_plunge` for `look` and any point field; `look` pans to a point (found: resolved). P4c-4: `falls_visible` (`visible`) shows or hides the falls meshes alone (a GPU A/B with the water kept); `quality` (`low`) sets the Water Quality globals; `clock` (`scale`) sets `Engine.time_scale` (0 freezes the shader clock for a capture; the driver's `wait` runs on scaled time, so set 1 before one); `palette` (`name`) applies a `WaterPresets` palette to the water and the falls. P4c-6: `tokens` (`points`, `assets`) is water.gd's `tokens` with this probe's `found:` names resolved (a token in a fall's plunge pool or on its lip); `ramp` (`at`, `rise`, `face_slope`, `back_slope`, `half_length`) raises a block of ground with a 39 degree east face (under the cliff rule); `old_river` (`points`, `half_width`, `depth`) makes a river as v0.1.29 did (the frozen `plan_river` from `test_water_falls.gd`, every step carved as a riffle through `WaterCarve.river_goals` with zero flags) and logs which of its steps the current rule reads as falls. |
| `p4d.gd` | `action` (`bar`, `remove`, `landing`) plus its fields (see the script header) | The ford bar probe (P4d-0): `bar` (`from`, `to`, `width`, `depth`, `name`) lays a gravel strip across a river under the map root, its crest `depth` under the water level where the ground is below that and sunk under the ground elsewhere, with the palette's gravel surface, a shadow and terrain-layer collision, in authoring or in play; `remove` frees it; `landing` (`at`) logs the terrain and walkable hits, the water, `WaterSurface.landing_below`, the grid field, the drag resolver and whether a 0.3 m token there counts as submerged. |
| `p6_perf.gd` | `action` (`shader`, `backdrop`, `backdrop_bench`, `exits_build`, `apply_bench`, `water_timing`) plus its fields (see the script header) | The phase 6 pinned pass (P6-2): `shader` swaps the skirt material between the game's opaque shader, the pre-phase-6 transparent one (from a `git archive` zip) and the band variant (patch opaque, ring transparent through a surface override); `backdrop` turns `SkirtBackdrop`'s per-frame sync on or off and `backdrop_bench` times `sync()`; `exits_build` times `RiverExitMesh.skirt_parts` on the open map and logs the vertex counts; `apply_bench` times `AuthoredTerrain.apply_river_exits`; `water_timing` logs the last water refresh's worker build, bake and main-thread swap and the editor's parts. |
| `skirt.gd` | `action` (`dip`, `undip`, `ribbon`, `ribbon_visible`, `skirt_depth`, `fog`, `info`, `state`) plus its fields (see the script header) | Water over the ground skirt (P6-0): `dip` rebuilds `TerrainSkirt` with more rings and carries the river's edge cross-section out along a line; `ribbon` lays a water strip there (`real`: the water shader with ALPHA times the skirt's fade; `simple`: no depth or screen reads), one render priority above the skirt by default; `skirt_depth` hot-swaps the skirt shader (`never` the game's, `always`, `prepass`, opaque `dither` / `dissolve` / `tint`), writing each variant to `user://render_jobs/p6_probe/`; `fog` turns depth fog on or off; `state` sets a named combination (`STATES`) for one capture. |
| `landform.gd` | `action` (`new`, `report`, `look`) plus its fields (see the script header) | Starting landforms (P5-1, P5-4): `new` (`biome`, `size`, `seed`, `landform`) opens a new map through the controller with the landform in the spec and logs the recipe's report; `report` recomputes the report for the open map (a saved level answers too); `look` (`at`) pans so the screen centre looks at a point or a named part: `stage`, `water`, `floor`, `summit`, `steepest`, `fall` or `crossing`, correcting the parallax of ground below y = 0. See `docs/systems/landforms.md`. |
| `paint_check.gd` | `points` ([[x, z], ...]), `r` (default 0.75) | The Paint tool (P3-6): at each point the document's painted weights, what the ground lets grow there (`ScatterGround`: open, rock and scree shares), the scatter rows within `r` by asset and the nearest row's distance, to tell a plant left on a path by the rules from one on its shoulder. |
| `rocks.gd` | `action` (`check` default, `survey`), `near` ([x, z, r]), `within`, `top` | Rocks survive terrain changes (P3-7, `RockKeep`): `check` logs the rock props (kept or placed), any standing above its bed (`GroundSnap.bed_under`), their tilt, generated rocks inside a rock prop (twins), rock rows and props within `near`, and the last stroke's keeping (count, main-thread and worker time); `survey` lists the 10 m cells near the centre with most rock rows, to aim strokes at a boulder field. |
| `height_profile.gd` | `from`, `to` ([x, z]), `n` (default 21) | The authoring map's ground height at `n` points along a line (`AuthoringEditor.ground_height_at`) and the steepest slope between them, for checking a sculpt stroke numerically (tier tops on whole tiers, a face's width, a ramp's slope, a pit's floor). |
| `ground_perf.gd` | `action` plus its fields (see the script header) | Ground shader A/Bs: `shader` swaps the terrain material to the current include or one read from `user://p34_<version>_ground.zip` (made with `git archive`); `variant` builds a text-replaced copy of the current include; `paint` writes eight painted surfaces as strips or a half-weight checker; `terraces` fills the view with tiers; `fraction` reports the share of steep ground pixels. |
| `avatar_kit.gd` | `action` plus its fields (see the script header) | Avatar figures from figurine's kit through AvatarKit: `place` stands figurine's three judging recipes in a row along the screen's right axis, `canopy` adds one at the first of `points` whose shade ray meets a canopy, `spawn` places `count` for frame times, `look` pans to a figure at a height, `shade` re-takes the shade rays and says what blocks each, `hidden` dithers one, `params` sets figure shader uniforms, `variant` sets a named look set (`before` / `after` the world-lighting pass), `near` adds one at the first of `points` in sun, `add` one at a point, `env` logs the environment's ambient and the sun, `sun` hides or shows the sun, `mipmaps` toggles AvatarKit's detail mipmaps; `save` / `cleanup` (all, or one `folder`) for `_avatarkit_` levels. |
| `avatar_token.gd` | `action` plus its fields (see the script header) | Avatar tokens in play: `pair` spawns a preset under a canopy and a selected one in sun (a ring search when the listed sunny points are shaded), `spawn_at` drops one onto whatever is under a point (water too), `look` (a token by name, index or the pair's midpoint), `hide` (hidden from players, by name or index), `report` (capsule, shade, submerged cue, occlusion fade entries), `timing` (spawn and shade-ray medians, walked and cached), `profile` (build and `set_recipe` medians per change type, off the board); `save` / `cleanup` for `_avatartoken_` levels. |
| `avatar_library.gd` | `action` plus its fields (see the script header) | The avatar library: `use` points the running game's library at a `user://_avatarlib_<dir>/` test directory (and seeds it from presets), `roster` opens the title screen's roster, `edit` opens the builder from it, `close`, `browser` opens the Add Token browser, `place` presses a saved avatar's card in the Avatar tab, `report`, `cleanup` deletes every `_avatarlib_` directory and points the library back at `user://avatars/`. |
| `avatar_builder.gd` | `action` plus its fields (see the script header) | The avatar builder in play: `window` resizes the game window, `open` opens the builder on a preset, `pane` selects a rail pane, `report` (panel, preview and pane sizes, measured bounds and view, stance tile sizes), `timing` (preview `set_recipe` and face-tile repaint medians), `close`, `spawn` (the preset as a token turned to the camera). |
| `ui_primitives.gd` | `action` plus its fields (see the script header) | UI captures (card U1 and the UI tour): `settings` (`section`), `foldout`, `close_settings`, `report` (rail underline, Foldout chevron, hint bar rects); `window` (`size` [w, h] or `"WxH"`, `content_scale`) resizes the window and logs the size it took; `host_lobby` shows the host lobby without hosting (sample code and players) and `close_host_lobby`; `drawer` (`which` `authoring` or `visuals`, `pane`, `open`); `toasts`; `danger`; `dismiss`; `browser` (`open`); `save` (`folder`, `name`) and `cleanup` for `_u1_ui_` and `_ui_tour_` levels. |

## Capture readers

Standalone scripts that read PNGs after a run, not probes. Their coordinates are the PNG's
own pixels: a default capture is 960x540 and a `--full` one 1920x1080, so coordinates read
off one size are wrong on the other. Each prints the image size it read and flags
coordinates outside the image instead of clamping them silently.

`sample_pixels.gd` (this folder):

```
godot --headless --path D:/dev/tt-sim --script res://tools/render_jobs/sample_pixels.gd -- <x> <y0> <y1> <step> <png>...
```

prints the mean colour of 9x9 boxes down one column of each PNG, for comparing captures
numerically (for example where a fade or a tint band starts). Half size suits it: a box
then covers 18x18 window pixels.

`probes/avatar_diff.gd` (`-- <a.png> <b.png> <x0> <y0> <x1> <y1> [mask.png]`, or `-- crop
<in.png> <x> <y> <w> <h> <out.png> [scale]`) diffs two captures inside a rectangle: the mean
channel difference and the pixels over 8 and over 32. It is pixel-exact, so it needs
full-size captures (halving averages a one-pixel difference away); `avatar_probe.json` pins
its twin captures at `scale` 1.0 for it.

## Caveats

- **Frame and GPU timings from a job are not measurements.** The window shares the GPU with
  everything else on the machine (the user may be gaming), and clocks throttle under
  sustained load, so numbers from `record` and `gpu` drift between runs. For any
  performance claim follow `docs/PERFORMANCE.md` "How to measure without fooling
  yourself" (pinned viewport, vsync off, in-run A/B, drift checks).
- Positions in `stroke`, `place` and `look_at` are world metres on the map plane (x, z),
  centred on the map; a 200 ft map spans about -30 to 30.
- The driver pokes private members of the game (`_begin_authoring`, `_autosave_timer`,
  `_pressed`, `_reset_camera_to_home` and so on). A rename in the game breaks the matching
  op with a script error in the log; fix the driver alongside the rename.
