# Render jobs

A scripted harness that drives the real game (main scene, real window, real frames) through
a list of steps from a JSON job file: open new maps or existing levels in authoring, paint
strokes, place props, move the camera, and capture both the composited window and the raw
3D SubViewport as PNGs, with an `INDEX.md` listing every capture. It exists so judgment
passes on authoring visuals (what a biome looks like out of the box, what a hand-painted
composition looks like at game zoom, how it compares with the Blender reference maps) can be
re-run identically after a change instead of being rebuilt by hand each time. It needs no
validation bridge, no Python and no shell script: one `godot` command runs the job and quits.

This page is the quick reference. [REFERENCE.md](REFERENCE.md) holds the job file format,
every op and probe script, the capture readers and the caveats; [JOBS.md](JOBS.md) is the
catalogue of the jobs in `jobs/`.

## Running a job

One fixed command form, so it is approved once; only the job and the flags change:

```
godot --path D:/dev/tt-sim --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_jobs/run.gd -- <job> [flags]
```

Do not pass `--headless`: captures need real pixels. `run.gd` loads the main scene, waits
about 3 seconds for it to settle, forces the window onto the primary screen at 1920x1080
(REFERENCE.md "Why 1920x1080 is forced") and adds `driver.gd`, which runs the steps. The
run takes as long as its steps (`dressing_smoke` about 15 s, a judgment set several
minutes) and quits by itself when the last step is done or `timeout_s` passes.

Progress lines start with `RJ|`. A PreToolUse hook (`.claude/hooks/godot_output.sh`) shows
an agent only the job line (with the output folder's absolute path), each capture with its
image sizes, flags, saved-level loads, measurements (`gpu`, `record`) and probe results,
errors with their `at:` lines, and the end (`done in`, or `TIMEOUT` / `HANG` after the last
step line). The whole output is kept in `.godot/last_godot_output.txt`; every step is also
in the job's own `log.txt`.

## Flags

Arguments after `--`:

- `<job>`: a path to a JSON job file, or the name of one under `res://tools/render_jobs/jobs/`
  (the `.json` is optional).
- `--full`: captures at the window's size (1920x1080), for a final verdict. Without it every
  capture, window and `_sub`, is saved at half size (960x540), about a quarter of the tokens
  to read. A capture step's own `scale` wins over both (perf jobs pin 0.5;
  `avatar_probe.json`'s pixel-diff twins pin 1.0).
- `--saved`: skip every step tagged `"phase": "build"` and, where the first of them was, load
  the job's saved level instead (the `saved` key or op). The level must have been built by a
  run without the flag; a missing one stops the job.
- `--only <names>` (or `--only=<names>`): comma-separated capture names, `*` and `?`
  wildcards allowed (quote them in a shell: `--only "*_2_tier_z8"`). Only the matching
  `capture` steps run; a step tagged `"phase": "look"` with a `for` runs only when a capture
  it serves runs. Untagged steps always run.
- `--out <dir>` (or `--out=<dir>`): overrides the job's `out_dir`.
- `--warm-graphics`: force the first-launch graphics warm-up (`GraphicsWarmup.FORCE_ARG`).
  The editor binary skips it otherwise, so a job run from it never sees the warm-up unless
  it passes this. Start such a job with `wait_title`.
- `--half`: accepted and ignored. It was the half-size flag before half size became the
  default (2026-10-09), so older commands still run.

## Where captures land

- The job's `out_dir`, or `--out` when given. A path that is already absolute (`user://...`,
  `res://...`, `D:/...`) is used as is; a relative one resolves under `user://`
  (`--out render_jobs/verify` writes to `user://render_jobs/verify`). With neither,
  `user://render_jobs/<job file name>/`, for example `user://render_jobs/dressing_smoke/`.
- `user://` is `%APPDATA%/Godot/app_userdata/TTSim/`; the job line prints the absolute folder.
- Each capture writes `<name>.png` (the composited window, including the lo-fi pass) and
  `<name>_sub.png` (the raw 3D SubViewport); with no map open, `<name>.png` alone. Its
  `captured` line logs both image sizes and the camera size, so a wrong size shows.
- `log.txt` gets one line per step and per result; it is appended to, not replaced, so delete
  it between runs into the same folder if you want a clean log. The `index` op writes
  `INDEX.md`.
- The pixel readers (`sample_pixels.gd`, `probes/avatar_diff.gd`) take coordinates in the
  PNG's own pixels: halve coordinates read off a full-size capture (REFERENCE.md "Capture
  readers").

## Build once, look many

A job that builds a map (new map, strokes, carves, bakes) before its captures pays that build
on every run: 60-95 s for one map, 13-17 minutes for the eight-biome judgment sets. Shader
and mesh-constant iteration does not need the rebuild, so a job can split its steps into two
phases (REFERENCE.md "Tagging a job for build and look") and run in look mode:

1. **Build run** (no flags): the job runs as written. Its build steps end with a `water.gd
   save` into a `_<task>_` test level (`_p4c_falls_look`, `_p4c_{biome}`), with `"replace":
   true` so a rebuild overwrites the last one. The saved levels are kept on purpose.
2. **Look runs**: `--saved --only <captures>`. The build steps are skipped, the saved level
   is loaded in their place (`dress` by default, so the look steps find the authoring
   controller they expect), and only the named captures and the look steps serving them run.
   `falls_look` drops from 93 s to 15 s for two captures; the judgment set from about 100 s
   per biome to about 9 s.
3. A carve, plan or terrain change (anything the saved document bakes in) needs a new build
   run; a shader, material or mesh-constant change does not. Full-size captures (`--full`)
   are for the final verdict.
4. `jobs/cleanup_levels.json` (`water.gd cleanup`) deletes every `_p43_` to `_p4d_`, `_p5_`,
   `_p5j_` and `_p6_` test level when the task is done; JOBS.md names each job's own cleanup.

## Levels, hangs and the process check

The harness itself never saves a level. The `title` op switches state directly, bypassing the
leave prompt, and `no_autosave` stops the authoring autosave timer, so `user://levels/_autosave`
and existing level folders are only ever read. Use `no_autosave` after every `new_map` or
`dress` in a job that paints. The only writes under `user://levels/` are the explicit `save`
steps a job carries (`water.gd`, `crossing.gd` and the avatar probes), into `_<task>_` test
folders, and the only deletes are their `cleanup` actions.

A hung run kills itself (`hang_s`, REFERENCE.md "Job file format"): `timeout_s` is checked on
the main thread, which a hang blocks, and on Windows stopping the shell task that launched
Godot (TaskStop, or the Bash tool's own timeout) does not stop Godot. A hung Mobile-renderer
run in September 2026 kept its window and GPU context for 26 minutes after its task was
"stopped", contending with every later run. After every job, check from PowerShell:

```
Get-Process godot* -ErrorAction SilentlyContinue
```

and stop anything listed with `Stop-Process -Id <id>`. Frame and GPU timings from a job are
indicative only (REFERENCE.md "Caveats").
