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
| `expand_biomes` | `template` (array of steps) | Insert `template` once per biome in the installed palette (`PaletteLibrary.biomes()`), with `{biome}` replaced by the biome id and `{name}` by its display name, anywhere in the template's strings. |

### Camera

| Op | Fields | What it does |
|---|---|---|
| `home` | none | Reset the camera to its home view. |
| `zoom` | `size` (optional) | With `size`, set the target orthographic size (it eases there, so follow with a `wait`). Without it, zoom out 60 steps, which reaches full zoom-out. |
| `look_at` | `at` ([x, z] world metres) | Pan so the screen centre looks at that ground point. |

### Authoring edits

| Op | Fields | What it does |
|---|---|---|
| `stroke` | `points` ([[x, z], ...] world metres), `mode` (`paint` default, `thin`, `clear`), `biome` (for `paint`), `radius` (default 4.0), `flow` (default 1.0), `speed` (m/s along the path, default 6.0), `hold` (s to hold at the end, default 0), `keep_active` (default false) | Paint a brush stroke through the real brush tool, moving the pointer along the polyline at `speed`. `paint` uses the biome tool with `biome`; `thin` uses the thin tool; `clear` is the thin tool with Ctrl held. `keep_active` releases the press and finishes the gesture without deactivating the brush. |
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
