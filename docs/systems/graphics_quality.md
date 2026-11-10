# Graphics quality: presets, the first-run pick and eye view smoothing

Settings > Graphics opens with a **Quality** row: one choice that sets four existing rows (Shadow
quality, Shadow cascades, Ambient occlusion, Render scale) to a measured set, so a player on a weak
GPU does not have to know which four of the tab's levers matter. Under it, behind a project setting
that is off by default, the game can measure the computer once on the first run and pick the
preset itself. Card autoquality (2026-11-10); the numbers and the captures are in
`docs/PERFORMANCE.md` "Quality presets and the first-run pick".

## Model

- **Presets** (`QualityPreset`, `utils/quality/quality_preset.gd`). Rows only, no hidden state:
  | Preset | Shadow quality | Shadow cascades | Ambient occlusion | Render scale |
  |---|---|---|---|---|
  | High (the defaults; a fast card sees the same pixels as before) | Soft High | Blended | on | 100 % |
  | Low | Soft High | Unblended | off | 100 % |
  | Lowest (the floor) | Soft High | Unblended | off | 75 % (FSR) |
  Low keeps Soft High shadows on purpose: Soft Low draws a fine hatch in the penumbrae and Hard
  moves 5 to 10 % of the pixels, while cascades and AO together take 20 to 25 % of the frame off and
  change the image about as little as AO alone. Lowest adds FSR 75 %, the biggest single lever, and is
  the floor: nothing below it looks broken.
- **The row.** `SettingsQuality` (`scenes/ui/settings_quality.gd`, loaded by path from
  `SettingsMenu`) shows the preset whose rows match the four controls, else **Custom** (a disabled
  item: the player reaches it by changing a row, not by picking it). Picking a preset sets the four
  controls; they stay editable and Apply saves them like any other change. The row reads only the
  controls, so a hand-edited `settings.cfg` shows as whatever it matches.
- **The pick** (`QualityAuto`, `utils/quality/quality_auto.gd`). Once per install: only while
  `settings.cfg` has neither `[quality] auto_done` nor a `[graphics]` section (a player who ever
  saved graphics settings has chosen). `QualityBench` (`utils/quality/quality_bench.gd`) draws a
  fixed forest scene (64 m ground, 30,000 ground-cover cards, 260 trees, the shipped defaults, the
  warm-up's home camera) in a SubViewport at the window's pixel size, with LoadPacing's cover (vsync
  off) so the GPU clocks up, ramps 500 ms and until no pipeline has compiled for 400 ms (a compile
  while sampling starts the ramp again), then reads the GPU time of at least 30 frames over 800 ms
  and reports the median. Its meshes are built on a thread and its pipelines are pre-compiled, so it
  adds no compile hitch. `predicted_ms()` turns that into the filled 200 ft map's home view at the
  defaults (`GAME_PER_BENCH` 2.28, measured), and `decide()` reads a table:
  - High while the prediction is at most 80 % of the 60 fps budget (13.4 ms): the rest is headroom
    for tokens, the full zoom-out and the CPU;
  - Low while Low's frame (`LOW_RATIO` 0.78 of it) fits 16.7 ms, so up to 21.4 ms;
  - else Lowest.
  A NaN, zero or failed measurement falls back on the adapter type only: integrated gives Low,
  virtual or CPU gives Lowest, anything else High. The pick writes `[quality]` (`auto_done`,
  `auto_preset`, `auto_predicted_ms`, `auto_bench_ms`, `auto_adapter_type`, `auto_rule`) and, only
  for Low or Lowest, the four rows, so a fast card's file holds no graphics rows and later default
  changes still reach it. It applies the rows at once (later maps read them).
- **Re-detect** (beside the Quality row) runs the same bench from Settings, with no popup, and its
  thresholds lean 10 % toward the preset in use (`HYSTERESIS`), so a card on a boundary does not flip
  between two presets from run to run. The note under the row says "Chosen for this computer." while
  the rows still match the recorded pick, and what happened when a measurement failed.
- **Eye view smoothing** (`FoliageEdges.eye_smoothing`, `graphics/eye_smoothing`, a CheckButton below
  Foliage edges, on by default). The eye view raises MSAA to 4x (`VisualEffectsController.
  effective_antialiasing_level`); off keeps the Antialiasing setting there. It is not in the presets:
  Low already brings the eye view under budget on the 1060 estimate, and the steps it leaves on
  trunks and leaf edges are visible at eye height.

## Where it runs

- `Root` starts the pick through `OnDemand.quality_pick()` when the title is quiet: from
  `_on_warmup_finished` (a first launch's warm-up done, no door waiting) or after
  `_compile_shaders_behind` (later launches; the pick waits for `GraphicsWarmup.behind_running()` and
  1.5 s more). `_ensure_table` aborts it when a door into a map opens: nothing is written and the
  next launch tries again. Headless runs never pick.
- None of the quality scripts is on the start-up graph (`tests/unit/test_boot_graph.gd`): the pick
  and the Settings row are loaded by path on first use, and `OnDemand.quality_pick()` returns null
  without loading anything while the flag is off.

## Switches

- **The flag: `tt_sim/graphics/auto_quality`** (project setting, default false = the game as before:
  no measurement, no pick, the presets and Re-detect still in Settings). To ship the pick, add to
  `project.godot`:
  ```
  [tt_sim]

  graphics/auto_quality=true
  ```
  For one exported build, the same lines in an `override.cfg` beside the exe.
- `--quality-bench-scale=<f>` (user argument) multiplies the bench's viewport size, to emulate a
  slower card on a fast one: on an RTX 3080 at 1920x1080, 1 picks High, 1.9 to 2 Low, 3 Lowest.

## Not verified

Open before the flag flips: on an exported first launch the bench reads about 35 % higher than in
the editor-run calibration (its frames take about 14 ms there, so the GPU clocks stay low; the cause
is not found). The pick errs one preset low near a threshold until that is fixed or
`GAME_PER_BENCH` is calibrated from the exported reading (`docs/PERFORMANCE.md`).

No weak GPU, AMD or Intel driver, or macOS (Metal, Forward Mobile) was measured: the thresholds are
derived from an RTX 3080 and the minspec2 estimate. `RenderingServer.viewport_get_measured_render_
time_gpu` reads 0 on drivers without timestamp queries; the pick then falls back on the adapter type.
