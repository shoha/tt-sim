# Render jobs

A scripted harness that drives the real game (main scene, real window, real frames) through
a list of steps from a JSON job file: open new maps or existing levels in authoring, paint
strokes, place props, move the camera, and capture both the composited window and the raw
3D SubViewport as PNGs, with an `INDEX.md` listing every capture. It exists so judgment
passes on authoring visuals (what a biome looks like out of the box, what a hand-painted
composition looks like at game zoom, how it compares with the Blender reference maps) can
be re-run identically after a change instead of being rebuilt by hand each time.

It needs no validation bridge, no Python, and no shell script: one `godot` command runs
the job and quits.

## Running a job

```
godot --path D:/dev/tt-sim --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_jobs/run.gd -- authoring_judgment_set
```

Arguments after `--`:

- `<job>`: a path to a JSON job file, or the name of one under
  `res://tools/render_jobs/jobs/` (the `.json` is optional).
- `--out <dir>` (or `--out=<dir>`), optional: overrides the job's `out_dir`.

Do not pass `--headless`: captures need real pixels. The run takes as long as the job's
steps (the judgment set is about 6 minutes) and quits by itself when the last step is done
or `timeout_s` passes. Progress lines are printed with the prefix `RJ|`.

A hung run kills itself (see `hang_s` below). This matters because `timeout_s` is checked
on the main thread, which a hang blocks, and on Windows stopping the shell task that
launched Godot (Claude Code's TaskStop, or the Bash tool's own timeout) does not stop the
Godot process: a hung Mobile-renderer run in September 2026 kept its window and GPU context
alive for 26 minutes after its task was "stopped", contending with every later run. If a
`Godot_v4.7.1-stable_win64` process is still listed after a job, stop it by id.

`run.gd` loads the main scene, waits about 3 seconds for it to settle, then forces the
window onto the primary screen at 1920x1080 and adds `driver.gd`, which runs the steps.

## Where outputs go

- The job's `out_dir`, or `--out` when given. A path that is already absolute (`user://...`,
  `res://...`, `D:/...`) is used as is; a relative one resolves under `user://`
  (`--out render_jobs/verify` writes to `user://render_jobs/verify`).
- With neither, `user://render_jobs/<job file name>/`, for example
  `user://render_jobs/authoring_judgment_set/`.

`user://` is `%APPDATA%/Godot/app_userdata/TTSim/`. Each capture writes `<name>.png` (the
composited window, including the lo-fi pass) and `<name>_sub.png` (the raw 3D SubViewport).
`log.txt` gets one line per step and per result; it is appended to, not replaced, so delete
it between runs into the same folder if you want a clean log.

The harness never saves a level. The `title` op switches state directly, bypassing the
leave prompt, and `no_autosave` stops the authoring autosave timer, so
`user://levels/_autosave` and existing level folders are only ever read. Use `no_autosave`
after every `new_map` or `dress` in a job that paints.

## Why 1920x1080 is forced

On the user's portrait monitor the `--resolution` flag alone produced odd window sizes (the
window was clamped or rescaled to fit the screen), so captures from different runs did not
match. `run.gd` sets the window to 1920x1080 on the primary screen after the scene loads,
and every capture log line records the actual image sizes so a wrong size is visible.

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
| `out_dir` | `user://render_jobs/<job name>` | Output folder (see above). `--out` overrides it. |
| `timeout_s` | 300 | Hard stop in seconds from launch; the run quits even if steps remain. |
| `hang_s` | 60 | Watchdog: when no frame completes for this many seconds, log a `HANG:` line (stderr and `log.txt`) and kill the process. The same watchdog kills a run still alive 30 s past `timeout_s`. The last `step` line before the `HANG` line is the step that hung. |
| `remove_override` | false | Delete `res://override.cfg` right after startup (the engine has already read it). Use it when you drop in a temporary `override.cfg` for one run (for example to pin a setting), so the file never outlives the run. The harness never creates one itself. |

Every step has an `op`. Steps that finish immediately advance on the same frame; `wait`,
`wait_ready`, `stroke`, `capture` and `gpu` take several frames. An unknown op logs
`unknown op` and is skipped.

### State and maps

| Op | Fields | What it does |
|---|---|---|
| `title` | none | Switch to the title state (`change_state(0)`), without the leave prompt and without saving. |
| `new_map` | `biome` (palette biome id, `""` for bare ground), `size` (ft, default 200), `seed` (default 1234) | Open a new map in authoring, as the New map dialog does. |
| `dress` | `folder` (level folder under `user://levels/`) | Open an existing level in authoring; a GLB-only level opens as a dressing layer. Nothing is written unless something saves. |
| `play` | `folder` | Load that level folder and play it (`_on_play_level_requested`). |
| `wait_ready` | `settle` (s, default 2.0) | Wait until the map has loaded, authoring is open, and the scatter is neither regenerating nor growing, then `settle` more seconds; the timer restarts whenever any of those is busy again. |
| `wait` | `s` (default 1.0) | Wait that many seconds. |
| `no_autosave` | none | Stop and disconnect the authoring autosave timer. |
| `hide_ui` | `hide` (default true) | Hide (or with `false`, show) the authoring panel. |
| `expand_ab` | `configs` (array of ground shader versions), `label`, `s` (default 3.0) | An in-run ground shader A/B: per config, swap the terrain's shader (`probes/ground_perf.gd` `shader`; `"std"` draws the chunks with `perf.gd`'s StandardMaterial3D instead), wait 0.5 s and sample GPU time for `s` seconds (`perf.gd` `start` / `stop`). Run `vsync_off` first. |
| `expand` | `template` (array of steps), `values` (array) | Insert `template` once per entry of `values`, in order, with `{value}` replaced by it anywhere in the template's strings (level folders, for example, where `expand_biomes` only takes palette biomes). |
| `expand_biomes` | `template` (array of steps), `biomes` (optional array of biome ids) | Insert `template` once per biome in the installed palette (`PaletteLibrary.biomes()`, palette order; only the ids in `biomes` when given), with `{biome}` replaced by the biome id and `{name}` by its display name, anywhere in the template's strings. |

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

### Capture and output

| Op | Fields | What it does |
|---|---|---|
| `capture` | `name`, `desc` (caption for the index) | After the next frame is drawn, save `<name>_sub.png` (raw SubViewport) and `<name>.png` (window) and log both sizes and the camera size. |
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
| `reflection_probe.gd` | `visible` (default true) | Show or hide the level reflection probe; logs its box and the environment's SSIL/SDFGI/glow/fog/tonemap switches. |
| `grid.gd` | `visible` | Log, and optionally set, the grid overlay's visibility directly (bypasses the grid policy; fine for a render session only). |
| `scatter_warm.gd` | `warm` (bool), `use_biome`, `tool`, `select` | Toggle `AuthoredScatter.warm_pipelines`; choose the brush biome and/or the biome tool without painting. Logs pipeline compilation counts. |
| `prepare_biomes.gd` | `all` (bool) | `all: true` starts preparing every palette biome on the authoring scatter; a later call without it reports whether preparation finished and how long it took. |
| `additive_clumps.gd` | `additive` (default true) | Set the static `ScatterPlan.additive_clumps` switch for an A/B; call it before painting. |
| `ground_check.gd` | `action` (`survey` or `rows`, default `rows`), `near` ([x, z, r]) | Layer-1 downcasts against the opened map. `survey`: one ray per document sample (timed), misses, ground and document height ranges, the 10 m cell with most relief, layer-1 bodies. `rows`: each scatter row's Y against the ground under it (mean and worst \|dY\|, rows off by > 0.1 m) and the mean angle between row up and ground normal for normal-aligned and upright assets. Used for the dressed-map ground fix (P3-0). |
| `grid_ground.gd` | `action` plus its fields (see the script header) | The grid on a Blender map's ground (P3-3c). `survey` samples the loaded map's layer-1 collision at each of `spacings` and logs ray time, misses and the interpolation error against the collision at `n` random points, plus the share of the ground near Y = 0; `fit` logs the last grid ground fit (play and authoring); `grid` logs the overlay's ground state; `key_g` presses G; `measure` and `drag` turn the measure tool and a token drag's grid auto-show on or off; `token_at` lists tokens; `play_res` plays a built-in `res://` level. |
| `sculpt.gd` | `action` plus its fields (see the script header) | The sculpt pipeline (P3-3a), driven through `AuthoringEditor` since there is no Sculpt tool yet. `stroke` runs a height stroke over real frames (`sculpt`: raise / lower / smooth / flatten / tier; the step's own `op` is `call`) and logs frame times, the worst frame and its breakdown (ray, dab, terrain, collision, snap, rows moved, chunks), `end_stroke`'s cost by part (terrain, collision, snap, rule fields), then the regeneration tail with its parts summed and its worst frame's parts (terrain settling, collision, snap, rock keeping, cells applied) and the plants grown and shrunk against the instances really added and removed (the tail's first frame also carries the probe's own key snapshot, 17-20 ms on 8.5K rows); `compare` times whole-chunk rebuilds against in-place updates; `collision` times the collision rebuild and the CPU ray march; `snap_dense` times snapping the densest cell; `check` tests rays, rows, in-place chunks, AABBs and the near plane; `view_shift` measures how far the view moves when the terrain top rises; `look_bottom` puts a point at the bottom edge. A capture during a stroke lands in its worst frame (about 1 s for the PNG), so measure strokes without one. |
| `perf.gd` | `action` plus its fields (see the script header) | Performance passes: `start` / `stop` sample every frame's CPU frame time and world-viewport GPU time and log n / median / p95 / worst (run `vsync_off` first); `info` logs visible and shadow draw calls and primitives plus scatter instance counts; `mem` logs engine memory monitors (`ws: true` adds the process working set via one powershell call); `play` / `author` / `dress` time a load, the loading screen and the palette resolve; `scatter`, `ground_std`, `broad`, `layers`, `skirt` toggle ground and scatter configurations for in-run A/Bs. Used for `PERFORMANCE.md` "In-game authoring: pinned performance pass". |

| `terrain_shapes.gd` | `action` plus its fields (see the script header) | The automatic dressing (P3-4) without Sculpt or Paint tools: `plateau` (stacked 1.524 m tiers with one-sample faces and an optional rounded lip), `hill`, `hollow` write the document heights and refresh terrain, collision, plants and ground like an undo; `path` / `area` paint a surface into the document; `stats` counts samples by rule weight (TerrainRules). |
| `water.gd` | `action` plus its fields (see the script header) | Authored water at runtime (P4-2) without the carve or Water tool: `build` writes a sloped map with a three-reach river, a deep pond and a waist basin into the open document and refreshes terrain, plants and water; `save` writes it as a `_p42_*` test level; in play `tokens` spawns tokens, `drag` drags one through DragAndDrop3D, `report` logs each token's base, bed, surface and float state, `points` / `measure` log beds, surfaces, landings, the grid field, the drag resolver and the measure tool's rays; `water` hides or shows every water mesh (GPU A/B); `scan` finds a Blender map's water and names points for later steps (`"found:deep"`); `look` pans to a point; `state` logs the water nodes and the grid field. P4-3, through the `AuthoringEditor` water API: `tilt` slopes the open map; `carve` carves a river (`points`, `half_width`, `depth`, `speed`; logs its reaches and timings and names each step between reaches `"found:c<n>_joint<k>"`); `pond` paints a pond (`points`, `radius`, `depth`); `erase` erases water (`points`, `radius`); `check` logs the bodies, the dressing's coverage, plants standing in the water and the ground layers; `profile` logs ground and depth along every river; `joints` names every reach step drawn so far (any tool) `"found:joint<k>"` (P4-5); `save` also takes `_p43_*`, `_p44_*` and `_p45_*` folders and `cleanup` deletes every such folder. `tokens` takes `assets` ([[pack, id]]) or else spawns the first cached asset that is not a light (P4-5: the first one used to be `misc/lightglobe`, an emissive globe with its own light, whose glow read as blown-out bright blobs on the water in every capture with tokens). |
| `water_params.gd` | `params` ({uniform: value}), `shader` (`"current"` or a zip path), `glow` (bool), `sun_pitch` (degrees) | Water shader A/Bs (P4-5) on the shared water material: set uniforms (logs the old values); swap in `shaders/water.gdshader` from a zip made with `git archive --format=zip --output=<path> <commit> shaders/water.gdshader` (an older shader) or put the current one back; turn the environment's glow off or on; set the sun's elevation. Call it after a level load (a load re-applies the level's water settings). |
| `p4b.gd` | `action` plus its fields (see the script header) | Phase 4b follow-ups (P4b-0): `line` logs ground, water level, depth, the wet dressing (bed, shore, wet line) and a surface's painted weight at points along a line on the open authoring map (the path-meets-water fix); in play `cues` logs every token's height, base, the surface over it and whether its submerged cue shows, `hold` picks a token up through DragAndDrop3D and holds it over a point (edge pan off, since it reads the real cursor) for a mid-drag capture, `drop` releases it; `load_profile` (from the title) times each main-thread part of loading a level's `map.ttmap` (terrain wet and dry and its parts, the wet dressing, the water mesh and nodes, the workers' share and what is left on the main thread with their output). |
| `crossing.gd` | `action` plus its fields (see the script header) | Crossings (P4b-1) through the `AuthoringEditor.crossings` API, since there is no Bridge tool yet: `place` (`kind` `plank` or `stones`, `from`, `to`, `width`) snaps a line across the water to the banks and logs the id or refusal, anchors, span, levels, style and times, naming `"found:c<id>_mid"`, `_a`, `_b` and `_stone<k>`; `report` lists the crossing nodes; `undo`; `save` writes a `_p4b1_` test level and `cleanup` deletes every `_p4b1_*` folder; `look`, and in play `tokens` and `points` (water.gd's, with `found:` names resolved). |
| `paint_check.gd` | `points` ([[x, z], ...]), `r` (default 0.75) | The Paint tool (P3-6): at each point the document's painted weights, what the ground lets grow there (`ScatterGround`: open, rock and scree shares), the scatter rows within `r` by asset and the nearest row's distance, to tell a plant left on a path by the rules from one on its shoulder. |
| `rocks.gd` | `action` (`check` default, `survey`), `near` ([x, z, r]), `within`, `top` | Rocks survive terrain changes (P3-7, `RockKeep`): `check` logs the rock props (kept or placed), any standing above its bed (`GroundSnap.bed_under`), their tilt, generated rocks inside a rock prop (twins), rock rows and props within `near`, and the last stroke's keeping (count, main-thread and worker time); `survey` lists the 10 m cells near the centre with most rock rows, to aim strokes at a boulder field. |
| `height_profile.gd` | `from`, `to` ([x, z]), `n` (default 21) | The authoring map's ground height at `n` points along a line (`AuthoringEditor.ground_height_at`) and the steepest slope between them, for checking a sculpt stroke numerically (tier tops on whole tiers, a face's width, a ramp's slope, a pit's floor). |
| `ground_perf.gd` | `action` plus its fields (see the script header) | Ground shader A/Bs: `shader` swaps the terrain material to the current include or one read from `user://p34_<version>_ground.zip` (made with `git archive`); `variant` builds a text-replaced copy of the current include; `paint` writes eight painted surfaces as strips or a half-weight checker; `terraces` fills the view with tiers; `fraction` reports the share of steep ground pixels. |

`sample_pixels.gd` (this folder) is a standalone reader for captures, not a probe:

```
godot --headless --path D:/dev/tt-sim --script res://tools/render_jobs/sample_pixels.gd -- <x> <y0> <y1> <step> <png>...
```

prints the mean colour of 9x9 boxes down one column of each PNG, for comparing captures
numerically (for example where a fade or a tint band starts).

## Jobs

- `jobs/authoring_judgment_set.json`: the authoring judgment set: two captures per palette
  biome plus seven, each as a window and a raw PNG (23 captures, 46 PNGs, with the 8-biome
  palette installed in September 2026; about 4 to 6 minutes). Every palette biome as a new 200 ft map (seed 1234) at home
  and full zoom-out; a hand-painted composition on bare ground (grassland meadow and
  temperate forest strokes, a thinned path, a cleared glade, placed props) at home, zoom 26
  and full zoom-out; the Blender reference levels `river` and `deciduous_clusters` opened in
  authoring at home and full zoom-out; then `INDEX.md`.
- `jobs/sculpt_pipeline.json`: the sculpt pipeline check (P3-3a, about 100 s): a new temperate
  forest map with three placed props; a 6-7 m hill (8 m brush), a hollow, smooth, flatten, a
  tier stub and an edge raise, each followed by its regeneration; the rebuild / in-place
  comparison; continuous 4 m and 12 m strokes for frame times; `check` after the edits; the
  hill at the bottom edge of the screen at zoom 13.85 and 8 (near plane); 10 captures and
  `INDEX.md`. Numbers for `docs/PERFORMANCE.md` "Sculpting".

- `jobs/sculpt_look.json`: the Sculpt tool look pass (P3-5, about 2.5 minutes): human-speed
  strokes through the real tool on a new 150 ft temperate forest map (a raised hill, a tier
  from the ground, a second tier from its top, the first tier extended from its edge, a
  sunken tier with Ctrl, a Shift-smoothed ramp, a flatten), with hover captures of the Tier
  readout, a capture mid-stroke, height profiles, a cancelled stroke and undo / redo checked
  by profile; then the same strokes on a rocky badlands map with the grid on (G). Frame
  times per stroke (`record`). 19 captures and `INDEX.md`.
- `jobs/paint_look.json`: the Paint tool look pass (P3-6, about 3 minutes): a new 150 ft
  grassland meadow with a two-tier plateau and a Shift-smoothed ramp (Sculpt tool), then
  human-speed Paint strokes: a winding dirt track from the low ground up the ramp (captured
  still pressed and after release), a flagstone courtyard on tier 2, a cobblestone path
  across tier 1's south edge (it stops at the face and resumes on top), tier 1's east face
  restyled with basalt, part of the track erased with Ctrl; close-ups at zoom 10, the grid,
  the home view (with an A/B of the trampled fringe, `paint_broad_strength` 0 vs 0.35), undo /
  redo of the last stroke. Frame times per stroke (`record`). `jobs/paint_shoulder.json` (about
  30 s) paints the same track alone and runs `paint_check.gd` along it with a zoom-8 capture.
- `jobs/phase3_judgment_set.json`: the phase 3 judgment set (P3-7, about 7 minutes): for
  temperate forest, alpine meadow, rocky badlands and grassland meadow, a new 150 ft map
  (seed 1234) built with the real Sculpt and Paint tools at human speed (a raised hill, a
  two-tier plateau with a Shift-smoothed ramp, a sunken hollow, a track up the ramp in the
  biome's first path surface, a path across a tier edge and a courtyard on the top tier in
  its first stone path surface (`PaletteLibrary.path_surfaces`; badlands: `dirt_road_caliche`
  and `flagstone_sandstone`), three placed props), captured at home zoom, home zoom on the plateau, zoom 26 and full zoom-out, each
  with the grid off and on; then `deciduous_clusters` and `river` in play (read-only) at home
  (grid off and on) and full zoom-out. 38 captures and `INDEX.md`.
- `jobs/rocks_survive.json`: rocks survive terrain changes (P3-7, about 80 s): on new 150 ft
  alpine meadow and rocky badlands maps, a Tier stroke through the densest boulder field near
  the centre (before, still pressed, after, close up), on alpine a Flatten back over the new
  face, and a gentle Raise hill under another group of rocks, with `rocks.gd` checks (kept
  rocks, floating, tilt, twins) after each. 16 captures and `INDEX.md`.
  `jobs/rocks_survey.json` (about 12 s) runs `rocks.gd survey` on both maps to pick the spots.
- `jobs/dressing_look.json`: the automatic dressing judgment set (P3-4, about 75 s): new 200 ft
  maps in temperate forest, alpine meadow and rocky badlands (the three cliff surfaces) with a
  two-tier plateau, a 6 m hill and a sunken hollow, at home and zoom 7 on each, then a painted
  cobblestone path and flagstone courtyard across the plateau; 18 captures and `INDEX.md`.
- `jobs/perf_ground_layers.json`: the pinned ground shader cost (P3-4): StandardMaterial3D,
  the pre-P3-4 shader and the current one, interleaved, on a bare map, 4 biome layers, 8
  painted strips, the 8-surface half-weight checker and screen-filling terraces. Needs
  `user://p34_old_ground.zip` (see `ground_perf.gd`) and a temporary pinned `override.cfg`
  (`remove_override` deletes it). `jobs/perf_ground_ab.json` is the shorter A/B used to
  pick the loop form.
- `jobs/dressing_smoke.json`: the fastest dressing check (about 15 s, two captures of one
  temperate forest map with the three shapes), for iterating on the shader.
- `jobs/mobile_check.json`: a bare 100 ft map shaped and painted under
  `--rendering-method mobile`, to check the ground shader in the Mobile renderer.
- `jobs/mobile_maps.json`: the Mobile renderer with scatter (about 40 s): a new 200 ft
  temperate forest map, the Blender levels `deciduous_clusters` and `river` in play, and
  `river` opened for dressing, one capture each. Run it with `--rendering-method mobile`
  after any change to foliage, scatter or pipeline warm-up; its first map open is where
  the one hang seen under Mobile stopped (docs/PERFORMANCE.md "Mobile renderer hang").
- `jobs/water_look.json`: carving and dressing water (P4-3, about 2.5 minutes): for
  temperate forest, grassland meadow and rocky badlands, a new 200 ft map tilted 2.5 %
  with a painted track, a winding waist-deep river in three reaches, a deep river and a
  pond (`probes/water.gd`), captured before and after at home, zoom 9 on the crossing, a
  reach step, the pond and the deep river, and zoom 34; on badlands the grid, an erase at
  the crossing and its undo, then the level saved as `_p43_badlands` and played with tokens
  wading and floating; the test level is deleted at the end. 26 captures and `INDEX.md`.
- `jobs/water_tool.json`: the Water tool look pass (P4-4, about 4.5 minutes): for grassland
  meadow, rocky badlands and temperate forest, a new 150 ft map tilted 2 %, then human-speed
  Water strokes through the real tool: a winding waist-deep river (captured still pressed:
  the ribbon), a cancelled stroke, an ankle stream joining it, a deep pool, a pond in two
  strokes; home view, zoom 9 on the confluence, the river's head, the pool and the pond, the
  grid, an erase with Ctrl (held, done, undone), then the level saved as `_p44_<biome>` and
  played with tokens wading and floating; frame times around each release (`record`). The
  test levels are deleted at the end. 42 captures and `INDEX.md`.
- `jobs/phase4_judgment_set.json`: the phase 4 (water) judgment set (P4-5, about 12
  minutes): for temperate forest, grassland meadow, rocky badlands and riverside wetland, a new
  150 ft map (seed 1234) tilted 2 % and built with the real tools at human speed: a tier north
  of the middle, a winding waist-deep river passing below its face, an ankle stream joining
  it, a deep pool, a pond painted in two strokes, a path in the biome's first path surface
  crossing the river, three placed props; captured at home zoom, zoom 26 and full zoom-out
  with the grid off and on and at zoom 9 on the crossing, then saved as a `_p45_` test level
  and played with tokens wading, floating and standing in the stream; then the Blender
  `river` level in play (read-only). The test levels are deleted at the end. 42 captures and
  `INDEX.md`.
- `jobs/p4b_badlands.json`: the badlands follow-ups (P4b-0, about 1 minute): a new 150 ft
  rocky badlands map built like the phase 4 judgment set (river, stream, deep pool, caliche
  path; no tier, pond or props), captured at home, on the crossing at zoom 9 and 7 and on the
  deep pool at zoom 7. Run it with `--out` before and after a change.
  `jobs/p4b_badlands_probe.json` is the diagnosis run: the path's paint and wet dressing
  along its line (`p4b.gd line`), the crossing with the water hidden, and the pool with the
  rock foam off and the water hidden.
- `jobs/p4b_cue.json`: the submerged token cue (P4b-0, about 80 s): the badlands map above
  saved as `_p4b_badlands` and played with tokens wading, floating and in the stream (home,
  max play zoom, zoom 10), a token held over the river mid-drag, dropped in and carried out
  onto the bank; then the Blender `river` level with tokens in its water (read-only). The
  test level is deleted at the end (`water.gd cleanup` covers `_p4b_*`).
- `jobs/p4b_load.json`: authored map loading with and without water (P4b-0, about 100 s):
  the badlands map saved before (`_p4b_dry`) and after its water (`_p4b_wet`), `p4b.gd
  load_profile` on the wet one, then warm play loads (`perf.gd play`) wet first, then wet /
  dry interleaved three times. Both levels are deleted at the end. Numbers in
  `docs/PERFORMANCE.md` "P4b-0: authored map load on workers".
- `jobs/crossing_look.json`: crossings (P4b-1, about 100 s): for temperate forest and rocky
  badlands, a new 150 ft map with a waist-deep river, a plank bridge and stepping stones
  placed with `probes/crossing.gd` (a short line on the water each), captured at home and
  zoom 8 with the grid off and on, then saved as a `_p4b1_` test level and played with
  tokens on the deck, at its end, on the stones and wading beside the bridge, grid on. The
  test levels are deleted at the end. 13 captures and `INDEX.md`. `jobs/crossing_iter.json`
  (about 35 s) is the quick check used while iterating: the badlands map's bridge and stones
  at zoom 8 with the grid, and the stones at zoom 4.
- `jobs/grid_ground.json`: the grid on Blender maps' ground (P3-3c, about 50 s):
  `deciduous_clusters`, `river` and the built-in Oak's lab in play with G, the measure
  tool and a token drag's auto-show, the load's grid ground fit and a sampling survey
  logged for each; then `river` opened for dressing with G. 11 captures and `INDEX.md`.

## Caveats

- **Frame and GPU timings from a job are not measurements.** The window shares the GPU with
  everything else on the machine (the user may be gaming), and clocks throttle under
  sustained load, so numbers from `record` and `gpu` drift between runs. For any
  performance claim follow `docs/PERFORMANCE.md` "How to measure without fooling
  yourself" (pinned viewport, vsync off, in-run A/B, drift checks).
- **The judgment set assumes palette content.** Its composition strokes use the palette ids
  `temperate_forest_summer_s1` and `grassland_meadow_summer_s1`, and it places the species
  `oak`, `log` and `boulder` from `temperate_forest_summer_s1` and `boulder` from
  `alpine_meadow_summer_s1`. A missing species or biome in a `place` step is skipped with a
  `no species ... not placed` log line. A paint stroke is not guarded the same way: it hands
  the unknown id to the brush, so after a palette change check the log and the composition
  images, and update the ids in the job. The per-biome captures follow whatever palette is installed, so
  the capture count changes with the palette.
- **The Blender reference levels must exist** as `user://levels/river` and
  `user://levels/deciduous_clusters`; the `dress` steps only read them.
- Positions in `stroke`, `place` and `look_at` are world metres on the map plane (x, z),
  centred on the map; a 200 ft map spans about -30 to 30.
- The driver pokes private members of the game (`_begin_authoring`, `_autosave_timer`,
  `_pressed`, `_reset_camera_to_home` and so on). A rename in the game breaks the matching
  op with a script error in the log; fix the driver alongside the rename.
