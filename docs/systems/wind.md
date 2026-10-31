# Wind

Design for one global wind that every moving thing in a level reads: plants and grass, rain, snow,
wind streaks, windmills, banners, awnings and weathervanes. Written 2026-10-30 on branch
`wind_design` after the owner's decision "Build a global wind. We should also reconcile the windy
weather effect along with rain and snow to interact with this global wind." Priority: core systems
and performance before new styles. The bar it is judged against is the suite's: motion that reads
at tabletop zoom (a gust you can watch cross a meadow, not a uniform shimmer), painterly, lively,
and never the same wind everywhere (`AGENTS.md` at the suite root, "Guiding principle").

Status (2026-10-30): phase (a) DONE on branch `wind_a` (see "Phase (a) as built" below); phase
(b) particles DONE on branch `wind_b` (see "Phase (b) as built", after phase (a)'s section); phases
(c) mills and cloth, (d) decor, (e) GM controls, (f) optional are NOT STARTED, and
the rest of this document is still the design they build from. The default wind now blows toward
(0.707, 0, -0.707), not -z (owner, 2026-10-30; mentions of -z in the sections below are the
phase (a) text). Where the design and the code
disagree, the code is right and the section below says so. Every number marked "start" is a tuning
start; the ones phase (a) tuned are listed below, the rest wait for their phase's render round.

## 1. Inventory: what moves today

There is no global wind value. Four independent wind-like things exist, and they disagree about
which way the wind blows.

| Consumer | Where | Direction it uses | Time source | Parameters come from |
|---|---|---|---|---|
| Plant sway and gusts (grass, trees, decor climbers) | `shaders/wind_foliage_include.gdshaderinc:226-264` (sway), `:209-218` (gust field) | `uniform vec2 wind_direction = (0.857, 0.514)` (x, z), `:64`; never set from GDScript (grep: no `set_shader_parameter("wind_direction"`) | Godot `TIME` (per peer, wraps) | per-material uniforms set once from `WindFoliage.PRESETS` (`utils/wind_foliage.gd:44-77`, applied at `:308-312`); `sway_speed` and `sway_amplitude` re-tunable live through `LevelEnvironmentManager._tune_wind_materials` (`level_environment_manager.gd:236-243`) |
| Rain and snow slant | `scenes/effects/weather_renderer.gd:335-342` | `WIND_DIRECTION = (0.707, 0, -0.707)` (`:10`), to the right of the default view | engine particle time | `gravity = base + WIND_DIRECTION * wind_intensity * STRENGTH` (6.0 rain, 2.0 snow, `:13-14`), set only when `apply_weather` runs |
| Wind streak particles | `weather_renderer.gd:206-254` | the same vector typed again as a literal (`:215`), so a change to the const would not reach it | engine particle time | fixed 6-10 m/s, 200 particles, on only while `wind_intensity > 0` (`:322-324`) |
| Windmill cap and sails | `scenes/terrain/mill_motion.gd` | `WIND_FROM = (0.2, 0, 1)` (`:20`), the wind comes FROM there | accumulated `delta` | constants `SPIN_RAD_S 0.29`, sway `0.12 rad` at `0.13 rad/s` (`:22-26`), a per-building spread from the seed (`:44-52`) |

Three different directions (shader, weather, mill) and three different clocks. The mill file and
`structures.md:593-602` already say this is a placeholder ("tt-sim has no global wind value").

Other motion, for completeness:

- **Plant categories.** `WindFoliage.PRESETS` holds three: `tree`, `grass`, `climber` (`wind_foliage.gd:44-77`).
  `classify_category` returns only `tree`, `grass` or the empty string for rocks (`:258-269`); the
  climber preset is assigned to structure decor through the decor row's `wind_category`
  (`scenes/terrain/authored_structures.gd:660-718`). There is no separate bush or flower category
  in code; both fall in `grass` (flowers) or `tree` (by name keyword). The design below names the
  three that exist.
- **Per-level tuning.** `FoliageSettings` keeps four values: tree and grass sway speed and amplitude
  (`resources/foliage_settings.gd:9-14`). Climber is not tunable per level.
- **Structure decor plants** (ivy, window planters) are baked into one node per building, dressed with
  `WindFoliage.apply_material(..., "climber")` (`structures.md:944-966`). They already use the
  foliage shader, so they get the global wind for free once the shader reads it.
- **Water** animates on raw `TIME` and a flow bake (`shaders/water.gdshader:383-406`); not wind aware.
  Out of scope here (see section 6).
- **Sky and fog.** The sky is a static panorama (`utils/environment_presets.gd:75`, `PanoramaSkyMaterial`)
  and fog is an `Environment` density tween (`weather_renderer.gd:371-401`), so there is nothing
  that drifts. The sky is not rotated on purpose (the HDRI's lit clouds are baked to its sun).
- **Cloth and vanes.** Weathervane, awning and banner ornaments exist (`utils/structure_ornaments.gd:26`,
  kinds `vane`, `awning`, `banner`; at most one vane or banner per building, `:303-305`) and are static.
  Their parts use the `cloth` and `metal` surface kinds with `structure_ornament.gdshader`
  (`utils/structure_materials.gd:98-117`, `utils/structure_look.gd:30-33`). No flags exist.
- **Lightning, puddles, rain ripples:** none exist (grep over `scenes/`, `utils/`, `shaders/`).
  The design leaves room for them and changes nothing there.

### Cost today

| Item | Cost | Source |
|---|---|---|
| Foliage sway | vertex-stage only: one `sin` for sway, two `sin` plus a `smoothstep` for the gust, one more `sin` for flutter on vertex-weighted meshes; no extra draw calls (wind is the material the MultiMesh already draws with) | `wind_foliage_include.gdshaderinc:209-264` |
| Foliage uniforms | about 8 wind uniforms per `ShaderMaterial` (one per species and category), set once at build; live tuning is `set_shader_parameter` on every cached material (a loop, only on slider moves) | `wind_foliage.gd:308-312`, `level_environment_manager.gd:208-215` |
| Weather particles | rain 1000, snow 600, wind 200 GPU particles (`weather_renderer.gd:99,153,210`); `_process` runs only while an emitter emits (`:67-77`) and moves three emitters and grows three AABBs | `weather_renderer.gd` |
| Windmill | two transforms per frame per visible mill; stops off screen | `mill_motion.gd:65-92` |
| Global shader params | precedent: `canopy_fade_*` (4 vec4) are published each frame but only when changed | `scenes/states/playing/canopy_fade.gd:150-163`, `project.godot` `[shader_globals]` |

Two faults found while reading, both fixed by this design:

1. **Gusts are not the same on two screens.** The gust field is a function of per-peer `TIME`
   (`wind_foliage_include.gdshaderinc:215-216`), so two players watching one table see fronts at
   different places. Today nothing is synced, and nothing needs to be (plants only), but it is
   the property we want ("wind must look the same for every peer").
2. **`TIME` wraps.** The project sets no `rendering/limits/time/time_rollover_secs` (grep of
   `project.godot`), so the engine default (3600 s) applies and every `TIME`-driven phase jumps once
   an hour. The wind clock below is computed in double precision on the CPU and wrapped per
   frequency, so it never jumps.

## 2. The model

### 2.1 State

One small value type, owned by a new autoload `Wind` (`autoloads/wind.gd`, registered beside the
others at `project.godot` `[autoload]`, line 29-43). It holds the current `WindState` and the
published uniforms, and ticks in `_process`.

```
class_name WindState extends RefCounted
var dir_angle: float      # radians in the map plane (x, z); the direction the wind blows TOWARD
var speed: float          # mean speed, m/s
var gust_amp: float       # 0..1, how far gusts rise above and fall below the mean
var gust_ripple: float    # 0..1, extra fast short-wavelength ripple (storm only)
var veer_amp: float       # radians, slow swing of the direction about dir_angle
var veer_period: float    # seconds
var sway_scale: float     # multiplier on every plant's sway amplitude (1.0 = today's look)
var seed: int             # phases the veer and the fronts; from the level (see 3)
```

`WindState` is built from the level's weather settings by a pure table
(`WindPresets.state_for(strength: float, direction_override: float, seed: int) -> WindState`) and
is immutable once built; a change makes a new one and the autoload blends from the old (see 2.5).

### 2.2 The function

```
static func wind_at(state: WindState, pos: Vector3, t: float) -> Vector3
static func gust_at(state: WindState, pos: Vector3, t: float) -> float   # 0..1, same shape the shader uses
static func direction_at(state: WindState, t: float) -> float            # veered angle
```

Rules:

- **Pure.** The result depends only on `state`, `pos` (x and z) and `t`. No node, no tree, no
  randomness except `state.seed` through fixed phase offsets.
- **Same shape as the shader's gust** (`wind_foliage_include.gdshaderinc:209-218`): two sines with
  12 m and 19 m wavelengths travelling along the direction, a small cross-wind term so fronts are
  not straight lines, then `smoothstep(-0.2, 0.9, wave)`. Reusing it keeps the first phase's look
  identical at calm. A third term, the ripple (7 m wavelength, 9 m/s front speed), is added
  scaled by `gust_ripple`, so a storm has fast streaks running through slower swells.
- **Front speed is constant** (3.0 m/s, today's `gust_speed`, `:66`; ripple 9 m/s) and does NOT
  depend on the preset. Reason: with a time-dependent phase `phi = omega * t`, changing `omega`
  when the GM changes the preset makes `phi` jump on every peer. Keeping omega fixed and
  scaling only amplitudes makes the field continuous through any preset change. Storm reads as
  stronger through lean, ripple and particles, not through faster fronts. This is a deliberate
  trade-off; open question 3 asks if it is acceptable.
- **Veer** is `dir_angle + veer_amp * sin(TAU * t / veer_period + seed_phase)`: slow (60 to 240 s),
  continuous, a pure function of time.
- **No allocation.** Returns a `Vector3` (a value type), the state is reused, no arrays or
  dictionaries are built per call. The autoload calls `wind_at` for at most a handful of points a
  frame (the view centre for particles, one per visible mill); it is not called per plant. Plants
  evaluate the same field on the GPU.

### 2.3 Wind clock

`Wind.clock()` returns seconds as a double:
`Time.get_unix_time_from_system() - EPOCH` with `EPOCH` a fixed constant (2026-01-01 UTC), see
section 3 for why. The CPU computes each phase in double precision and wraps it:

```
phase_a = fposmod(t * K1 * FRONT_SPEED, TAU)      # 12 m front
phase_b = fposmod(t * K2 * FRONT_SPEED * 0.8, TAU)  # 19 m front
phase_c = fposmod(t * K3 * RIPPLE_SPEED, TAU)       # 7 m ripple
```

The shader never receives a large time, so float32 precision does not degrade over a long
session (a unix time near 1.8e9 would have none left). Each phase wraps on its own period, so
there is no seam: the wave is `sin(along * k - phase)` and `phase` is already reduced mod TAU.

### 2.4 Shader interface (global uniforms)

Declared in `project.godot` `[shader_globals]` with calm defaults (so any scene without the
autoload ticking, such as structure previews and thumbnail shots, renders calm wind), read by
`wind_foliage_include.gdshaderinc` and, later, the cloth shader:

| Name | Type | Contents | Updated |
|---|---|---|---|
| `wind_dir` | `vec4` | x, z unit direction (veered), mean speed m/s, `sway_scale * motion_scale` | each frame while veering or blending; else on change |
| `wind_phase` | `vec4` | `phase_a`, `phase_b`, `phase_c`, flutter phase (fast, wrapped) | each frame while any consumer is visible; skipped when `motion_scale == 0` |
| `wind_gust` | `vec4` | `gust_amp`, `gust_ripple`, 0, 0 (two spare) | on change (preset or blend step) |

Three `vec4`, so three `global_shader_parameter_set` calls, each pushed only when the value
changed (the `canopy_fade.gd:150-163` pattern). This lands in one global uniform buffer upload per
frame. Budget: under 0.1 ms CPU per frame (the autoload tick plus three sets), zero extra draw
calls, no per-instance data, no per-material `set_shader_parameter` after startup.

In the shader, the per-material `wind_direction` and `gust_speed` uniforms are removed
(`gust_strength`, `sway_speed`,
`sway_amplitude`, `flutter_*` stay as the per-category character). The sway amplitude becomes
`sway_amplitude * wind_dir.w`, the lean in a gust uses the global direction, and the gust envelope
uses `wind_phase` and `wind_gust` instead of `time * gust_speed`. Per-plant oscillation
(`time * sway_speed + phase`, `:233`) stays on `TIME`: it is a local jitter, each plant a different
phase, and does not need to agree between peers.

Per-category response. Add `wind_response` to `WindFoliage.PRESETS` (start: tree 1.0, grass 1.25,
climber 0.6) so one `sway_scale` moves a meadow more than an oak and ivy stays held by its wall.
This is a new preset key, set once at build like the others.

### 2.5 Presets, one dial

The weather document already has a wind intensity, 0 to 1 (`WeatherSettings.wind_intensity`,
`resources/weather_settings.gd:19`, a "Wind" tile in `WeatherPane`, `weather_pane.gd:11-16`). It
stays the single strength dial; presets are named stops on it, so levels saved today keep their
meaning with no migration (and the owner's rule is that migration is not needed anyway).

| Preset | Strength | Speed m/s | Gust amp | Ripple | Sway scale | Veer (rad / period s) | Reads as |
|---|---|---|---|---|---|---|---|
| calm | 0.00 | 1.5 | 0.35 | 0 | 1.0 | 0 | today's look, exactly |
| breezy | 0.33 | 4 | 0.55 | 0 | 1.5 | 0.10 / 150 | meadow ripples, canopy nods, banners lift |
| windy | 0.66 | 8 | 0.75 | 0.25 | 2.2 | 0.20 / 110 | clear fronts, trees lean, rain slants |
| storm | 1.00 | 14 | 1.00 | 0.70 | 3.2 | 0.35 / 80 | heavy lean, ripples, sails fast, rain near 35 degrees |

Between stops the table interpolates linearly (and `smoothstep` on the ripple so it fades in
late). All start values; the dials most worth tuning live are sway scale, gust amp and the
direction. Hard caps: the sway offset after scaling must stay under about 0.35 m at a tree tip
and 0.12 m at a grass tip (tip heights in the assets are about 6 m and 0.3 m), else crowns
shear, which the existing "bend, not translate" droop (`:259-262`) only partly hides.

Blending: when the target state changes, `Wind` eases `speed`, `gust_amp`, `gust_ripple`,
`sway_scale` and the direction toward the new values over 2.5 s with an exponential approach
(the existing weather transition is 1.0 s, `weather_renderer.gd:8`; wind should lag precipitation).
Because phases do not depend on the state, the blend never pops. The blend itself is local; every
peer reaches the same target from the same message and ends identical.

### 2.6 Reconciling the weather effects

The "Wind" tile stops being a separate fixed-direction effect. It becomes the strength dial. Rain,
snow and wind streaks all read the wind whether or not the Wind tile is on:

- **Rain.** Today: `gravity += WIND_DIRECTION * wind_intensity * 6.0` (`weather_renderer.gd:339`).
  New: each rain frame the renderer (already ticking in `_process` while emitting) samples
  `wind_at` at the view centre and sets the process material's `direction` so the streak slants
  by `tan(slant) = clamp(wind_speed * 0.045, 0, 0.7)` (about 4 degrees calm, 20 at windy, 32 at
  storm; start), plus a gust factor (speed rises by up to `gust_amp * 0.4` inside a gust, so
  streaks lean harder as a front passes). `particle_flag_align_y` already aligns the streak to
  velocity (`:115`), so the lean shows without mesh changes. Material parameters change at most
  10 times a second (smoothed), not 60.
- **Snow.** Horizontal drift is half the wind speed (start; flakes lag), capped at 4 m/s;
  `turbulence_noise_strength` (`:166`, now 1.0) becomes `1 + 2.5 * gust_amp * strength` so it
  swirls more in gusts; amount stays. Clumping in a gust is approximated by the same turbulence
  rise, not by spatial density (see the next point).
- **Wind streaks.** Direction and speed come from `wind_at`; visible above strength 0.15, amount
  scaling with strength (start 40 to 200). Today's fixed 6-10 m/s becomes `2 + speed` m/s.
  The duplicated literal at `:215` goes away. The streak lives at 2 m above the view centre
  (`:265`); in a gust it brightens (alpha curve scaled by `gust_at`).
- **Spatial coherence is the plant shader's job.** CPU-set particle parameters sample one point
  (the view centre) so a rain front does not visibly cross the screen. A custom particles shader
  reading the same globals would make streaks and flakes bend in the same waves as the grass.
  This is an optional follow-up to phase (b), because `ParticleProcessMaterial` collision hide-on-contact
  (`:130`, `:186`) would need re-implementing and that is not obviously cheap.
- **Fog and cloud drift.** Fog is only a density tween, so there is nothing to drift. If fog later
  becomes volumetric with a density texture, its scroll takes `wind_dir`; not done now.
- **Not changed:** the fog density tween, emission box and AABB growth, rain collision, amounts,
  the transition tweens. Puddle, ripple and lightning effects do not exist; if added they keep
  their own parameters and may read `Wind` for lean only.

## 3. Synchronisation in play-together

Wind must match on every screen with no per-frame traffic. The wind is a pure function of the
clock, the seed and the settings, so the only things that cross the network are the settings.

What the code provides today:

| Need | Existing mechanism | Evidence |
|---|---|---|
| Live setting edit by the GM | the Weather pane emits `weather_changed(overrides)`; the controller applies it, copies it into `active_level_data.weather` and queues `{"weather_overrides": overrides}` for the host's visual broadcast | `gameplay_menu_controller.gd:549-558` |
| Reaching clients | `NetworkGameSync.broadcast_visual_settings` (RPC to all, batched by the queue) | `network_game_sync.gd:144-158` |
| Late joiner | the same call patches the stored level snapshot with `LevelVisualState.patch_level_dict`, so a joiner later receives the current `weather_overrides` | `network_game_sync.gd:160-166`, `resources/level_visual_state.gd:41-49` (the key is in `LEVEL_DICT_MIRROR_KEYS`) |
| Applying on load | `MapSourceLoader` applies `level.weather.to_dict()` to the fresh renderer; `apply_visual_state` re-applies on revert | `map_source_loader.gd:655-659`, `level_play_controller.gd:316` |
| A synced clock | none. The only clocks are local (`Time.get_ticks_msec`, `network_game_sync.gd:364`) | grep of `autoloads/` |

So the weather settings already travel to everyone, including late joiners. What must be added:

1. **A clock peers agree on.** Recommended: `Time.get_unix_time_from_system()` on every machine.
   No traffic and nothing for a late joiner to learn. Error equals the skew between two OS clocks,
   normally under a second with the OS's time sync on; with the front moving 3 m/s that is a shift
   of a few metres, not noticeable. Fallback if testing shows large skew: the host adds a one-time
   `wind_clock_offset` to the join snapshot (`host_unix - client_unix` at join, with half the
   round trip subtracted), and `Wind.clock()` adds it. That is one number once, not a stream.
2. **A seed.** `wind_seed: int` in `WeatherSettings` (new key beside the four intensities), default 0
   meaning "derive from the level": `hash(level_folder_name)`. It phases the veer and the fronts
   so two levels never share a wind. Carried by the same `weather_overrides` dictionary, so it
   reaches clients and joiners with no new plumbing.
3. **A direction override.** `wind_direction_deg: float` in `WeatherSettings`, `-1` = use the
   default direction (see open question 1). Same dictionary again.

`WeatherSettings.KEYS` (`weather_settings.gd:9-14`) drives `to_dict`/`from_dict` as floats, so the
two new keys are added there; `wind_seed` is stored as a float in the dictionary and cast to `int`
at the edge (floats hold integers exactly to 2^24; limit the seed to 24 bits). Tests that pin the
key list (`test_level_data_typed_settings.gd`, `test_visual_sub_settings.gd`,
`test_weather_pane.gd`) change with it.

The wind clock is not paused on the host's pause (there is none) and not tied to the map: a table
that reloads a level picks up the same wind mid-stream, which is correct.

Sail angle, plant per-card oscillation and veer phases are local or pure and need no sync. Mill
sail speed follows the synced wind speed, but the angle itself is cosmetic and local (it already is,
`mill_motion.gd:37-40`), so two screens show the same speed at different angles. Acceptable.

## 4. Consumers and migration plan

Six phases (a to f), each shippable on its own, each measured. Order is by value and risk.

| Phase | Touches | New or changed files | Test | Cost budget |
|---|---|---|---|---|
| a. Wind autoload and global uniforms; plants read them | Wind system, foliage shaders | new `autoloads/wind.gd`, `utils/wind_state.gd`, `utils/wind_presets.gd`; edit `project.godot`, `wind_foliage_include.gdshaderinc`, `utils/wind_foliage.gd` (`wind_response`, drop `wind_direction` use), the three `wind_foliage_debug_*` shaders if they include the sway | pure unit tests of `wind_at`/`gust_at`/table; a probe printing `global_shader_parameter_get` after `Wind` ticks; render job calm A/B against main | tick plus 3 sets under 0.1 ms CPU, 0 draws; foliage vertex cost unchanged to within noise |
| b. Weather particles read the wind | weather renderer | edit `weather_renderer.gd` (remove `WIND_DIRECTION`, the literal at `:215`, `RAIN_WIND_STRENGTH`, `SNOW_WIND_STRENGTH`), `weather_settings.gd` keys | unit: slant function, snow drift function; render job windy/storm rain and snow | `_process` already runs while emitting; add one `wind_at` and at most 10 material writes per second |
| c. Mills, cloth, vanes | structures | edit `mill_motion.gd` (read `Wind`), new `shaders/structure_cloth.gdshader` (or a define in `structure_ornament.gdshader`), `structure_materials.gd` (`cloth` kind picks it), new `scenes/terrain/vane_motion.gd` and a split like `StructureMill.split` for `ornament/vane`, `authored_structures.gd` | unit: sail rate function, vane yaw function; render jobs: banner, awning, vane, mill at windy | 0 added draws for cloth (material swap); one `MeshInstance3D` per vane, one transform per frame; cloth is vertex-only |
| d. Structure decor plants | decor | nothing structural; set `climber` `wind_response`, check the baked decor `mesh_height` override still holds | render job: ivy manor at calm and storm | none |
| e. GM controls and document fields | UI, document | `weather_pane.gd` (preset chips, direction, seed), `weather_settings.gd`, `LevelVisualState` mirror (already mirrors the whole `weather_overrides`), Settings entry for wind motion | existing pane tests extended; two-instance sync probe | none per frame |
| f. Optional | smoke, motes | `fire_smoke*.gdshader` lean, dust motes | render | measured per effect |

### a. Autoload and uniforms (first phase)

Add `Wind` as an autoload with `current: WindState`, `set_target(state)`, `clock()`, and a
`_process(delta)` that blends, computes the three vec4 in double precision, and publishes changed
values. `set_target` is called from `GameMap.apply_weather_overrides` (`game_map.gd:859-862`) and
from `MapSourceLoader` (`:655-659`), the two places that already receive `level.weather`; the
renderer-less path (a level with no weather renderer yet) still sets the wind. `clear_weather`
(`game_map.gd:871-876`) sets calm.

Look identity at calm: with `calm` the new globals must reproduce today's field. Today's
`wind_direction` (0.857, 0.514) and `gust_speed 3.0` are the calm defaults of the globals, and
`sway_scale 1.0` multiplies nothing. The one visible difference is that the gust now agrees between
peers and no longer jumps at the hourly `TIME` wrap. Verify with a render job at calm pose on
main versus the branch at a fixed `Wind.clock()` override (a test hook, `Wind.set_clock_override`),
since `TIME` makes two runs of main differ from each other and "byte identical" is only
possible when the clock is pinned. Expect pixel differences only where the phase differs because
the old gust used a `TIME` near 0 at launch; pin the old shader's `TIME` by the hot-swap method
([PERFORMANCE.md](../PERFORMANCE.md) "In-run shader A/B by hot-swapping `Shader.code`").

`LevelEnvironmentManager` needs no change: `_tune_wind_materials` keeps handling the four
per-level sway values (`:236-243`). The Foliage sliders now scale the calm base, and the wind
multiplies on top.

### b. Weather particles

Described in 2.6. Order inside the renderer's `_process`: the view centre is already computed
(`weather_renderer.gd:259-262`); add `var w := Wind.wind_at(center, Wind.clock())` and push to the
three materials through one helper `_apply_wind_to_emitters(w)` throttled to 10 Hz. The Wind tile
turns the streak emitter on above strength 0.15; rain and snow slant regardless of the tile.

### c. Mills, cloth, vanes

- **Mill.** `SPIN_RAD_S` stops being a constant. Target rate `0.29 * clamp(speed / 1.5, 0.3, 3.0)`
  rad/s (calm 0.29 as today; storm 0.87, about 7 s a turn, slow enough not to strobe at 60 fps),
  smoothed with a 2 s exponential. The cap's facing target is `facing_angle(axis, -wind_dir)`,
  turned at no more than 0.3 rad/s, so it follows veer and GM changes without snapping; the existing
  sway (`:25-26`, `:73`) is kept and scaled by gust. The edge-on problem noted in the file header
  (the weather's direction put the wheel edge-on to the default camera) is real: if the wind
  comes across the screen the sails vanish. Mitigation: the mill clamps its yaw to within 50 degrees
  of the camera-friendly bearing `(0.2, 0, 1)` (today's `WIND_FROM`), so a mill always shows its
  sails three-quarter on. Open question 2.
- **Cloth shader.** `cloth` surface parts (banners, awnings, the windmill's sail cloth) get a vertex
  sway: weight is the distance from the part's attachment, offset along the wind in object space
  (`inverse(mat3(MODEL_MATRIX)) * wind`), a travelling sine along the cloth with phase from
  `wind_phase.w`, amplitude `0.06 m * speed / 4` capped at 0.25 m, gust lifts the free edge. The
  weight source must be checked when the phase starts: either a vertex colour channel the build
  already writes (probe `StructureOrnaments` meshes) or a new custom channel. Banners stream
  fully, awnings flap lightly (weight 0.25 of a banner). A flag-like penant gets the same.
  `metal` is not swayed; a swaying `metal` part would be the vane.
- **Vane.** A `VaneMotion` node like `MillMotion`: a yaw pivot at the vane's post, cut out of the
  ornament mesh by the part name (like `StructureMill.split`, `structures.md:576-584`), turning to
  `-wind_dir` with a 1.2 s lag and a small wobble scaled by gust. Because it is a pure function of
  the synced wind plus a fixed lag, two screens show the same pointing within the lag.
  One `MeshInstance3D` per vane, at most one vane or banner roof top per building
  (`structure_ornaments.gd:303-305`).

### d. Decor plants

The climber preset already runs through the foliage shader, so phase (a) moves ivy and planters.
Check three things in the render round: `wind_response` 0.6 keeps ivy from detaching at storm;
the baked decor still takes `mesh_height` from vertex red (`structures.md:951-956`); the direction
is the same on every wall (it already is in the structure frame, and the global wind is the world
frame, a small visible change to note in the doc).

### e. GM controls and document

The control is the Weather pane in the level edit panel (`weather_pane.gd`; the Events pane is for
terrain events and has no weather). Change the Wind tile's row into: preset chips (Calm, Breezy,
Windy, Storm; they set the strength to 0, 0.33, 0.66, 1.0), the strength slider (existing), a
direction dial or compass row with an Auto toggle (`wind_direction_deg = -1`), and a seed
"reroll" in a small advanced row. Live editing, undo (Cancel restores the snapshot), broadcast and
late joiners ride the existing `weather_changed` path unchanged. The Settings menu gets a "Wind
motion" slider, 0 to 100 percent (see section 5).

### f. Optional

Chimney smoke lean (`fire_smoke*.gdshader` take `wind_dir` for a drift vector, a few lines), dust
motes drifting with the wind, a faint chop on water (`water.gdshader` wave amplitude times a
`wind_dir.z`-derived factor). Each is independently measured and none blocks the others.

### Phase (a) as built (2026-10-30, branch `wind_a`)

Owner decisions of 2026-10-30 applied: the default direction is toward -z, rain and snow will
always slant with the wind (phase b), windmills will follow the wind clamped to 50 degrees of the
camera-friendly bearing (phase c), the gust front speed is constant.

What exists:

- **`autoloads/wind.gd`** (`Wind`, registered last in `[autoload]`): `state` (the immutable
  `WindState` being drawn), `target`, `set_preset(name)`, `set_from_weather(settings, level_key)`,
  `apply_weather_dict(dict, level_key)` (a sparse dictionary keeps the other keys), `wind_at(pos)`,
  `direction_at(pos)` (unit, y = 0), `clock()`, `set_clock_override(s)` / `clear_clock_override()` /
  `is_clock_pinned()` (the pinned clock render jobs and tests use; `steady.freeze_wind` and
  `ThumbnailShot` pin it at 0 and release it), `snap()`, `publish(t)`, `set_wind_motion(v)` and
  `motion_scale()`. `_process` eases `state` toward `target` over 2.5 s (exponential) and publishes.
- **`utils/wind_state.gd`, `utils/wind_presets.gd`, `utils/wind_model.gd`**: the pure parts, no scene
  tree. `WindPresets.STOPS` is the table of 2.5 (linear between stops, the ripple eased);
  `WindModel.wind_at`, `gust_at`, `direction_at`, `phases(t)` and `uniforms(state, t, motion)`.
- **Globals** in `project.godot` `[shader_globals]` with calm defaults: `wind_dir` (x, z unit
  direction, mean speed, sway scale), `wind_phase` (three front phases, the fourth unused), `wind_gust`
  (gust amplitude, ripple, the seed's phase, **motion scale**). Each is set only when its value
  changed (counted in `Wind.publish_count`); the phases change every frame, the others on a change.
- **Plant shaders** (`wind_foliage_include.gdshaderinc`, which every variant including burn and the
  debug ones shares): the per-material `wind_direction` and `gust_speed` uniforms are gone; the gust
  field is `wind_gust_field(xz)`, the same two sines as before plus the storm ripple, reading the
  globals; `gust_strength` is now the calm value and rises with `wind_gust.x / 0.35` (capped at 1.2);
  sway, lean and flutter scale by the motion scale. A new per-category uniform `wind_response`
  (`WindFoliage.PRESETS`) says how far a category follows the sway scale: the amplitude factor is
  `1 + (sway_scale - 1) * wind_response`, so calm is untouched.
- **WeatherSettings**: `wind_seed` (float in the dictionary, 24 bits, 0 = unseeded; with a level
  key it derives from the level folder name) and `wind_direction_deg` (-1 = the default, -z). Old
  saved levels load with those defaults. `GameMap.apply_weather_overrides` feeds the wind (also
  when no weather renderer exists), `clear_weather` sets calm.
- **Accessibility**: `UiMotion.reduced()` is polled once a second; the player's `[graphics]
  wind_motion` setting (default 1.0, loaded at startup, `Wind.set_wind_motion`; UI is phase e)
  multiplies amplitudes. Motion scale 0 holds every plant at its rest pose and stops the phase
  publishing. It scales amplitudes only, never the clock.
- **Tests**: `tests/unit/test_wind_model.gd`, `tests/unit/test_wind_autoload.gd`. Render job
  `jobs/wind_a_look.json` (presets at two pinned clocks, a cost probe) and `jobs/wind_a_ab.json`
  (the calm A/B), probe `probes/wind.gd` (`set`, `report`, `cost`).

Deviations from the design, and what was learned:

1. **Motion scale lives in `wind_gust.w`, not in `wind_dir.w`.** `wind_dir.w` is the preset's
   sway scale alone, so a category's `wind_response` can blend it toward 1 without also blending a
   motion scale of 0 toward 1.
2. **Front speeds are not both 3 m/s.** The first front moves at 3 m/s, the second (19 m) at 0.8 of
   it, as the shader always did. So the field is not one rigid translation; the unit test checks the
   first front's phase and that the field repeats exactly after 380 s, when both have completed
   whole cycles.
3. **Tree `wind_response` is 0.5, not 1.0.** In the render round a storm (sway scale 3.2, gust 1.0)
   on trees sheared crown leaf cards off their limbs (a lone card stretched across the frame).
   At 0.5 the trees lean 1.6x at windy and 2.1x at storm and the shear is gone; grass keeps 1.25
   (a blade tip moves only centimetres) and climbers 0.6. The cap of 0.35 m at a tree tip in 2.5
   was not met by the code even at calm (an authored tip at 6 m moves up to 0.8 m with a gust), so
   it was not enforced; judge by the render. The gust gain is capped at 1.2 times `gust_strength`.
4. **The calm look is the old look only with the old direction.** The design kept the plant gust
   direction (0.857, 0.514) at calm; the owner's default of -z changes it. The A/B was run with
   `wind_direction_deg` 30.94 (the old direction), the wind frozen (clock 0, sway and flutter speeds 0).
   Result: mean channel difference 0.007 at home zoom, 0.15 to 0.26 at close zoom, against 0.12 to
   0.24 between two runs of the same code, so the shader change matches main within the renderer's
   run-to-run noise. Per-peer `TIME` no longer decides where a front is.
5. **`global_shader_parameter_get` returns null outside the editor** (the engine logs "should never
   be used outside the editor"), so the probe reports `Wind._published`, the last value pushed.
6. **`steady.freeze_wind` and `ThumbnailShot`** zeroed `gust_speed`; that uniform no longer exists,
   so they pin the wind clock at 0 instead (and keep zeroing `sway_speed` and `flutter_speed`).
   Biome thumbnails therefore take the default -z gust at clock 0, not the old direction.
7. **Not done in phase (a), as the design says**: nothing in the weather renderer or the mill reads
   the wind yet, and per-plant sway (`sin(TIME * sway_speed + phase)`) still reads `TIME`, so it keeps
   its hourly wrap. `Wind.debug_disable` and `Wind.debug_state` of 5 and 6 were not built; the
   pinned clock and `probes/wind.gd set` cover the tuning use.

How the look reads (renders in `render_jobs/wind_a_look`, forest map, calm, windy and storm at two
clocks 6 s apart, default -z and +x): trees lean together, by different amounts across the view, and
the lean moves between the two clocks (a front passed); the storm reads stronger by lean and
shear, not by faster fronts, as designed. Grass is too small on this map's view for individual
blades to read as a wave at tabletop zoom: the travelling gust reads on the tree crowns, and a
meadow-only map should be judged next. With the default -z direction the lean runs along the
view axis, so crowns appear to rise and sink more than to swing sideways; a direction with a lateral
component (the owner's call, open question 1 again) would show gusts more clearly. Two stills
cannot prove travel: a 20 s capture is still the judgment to make in phase (b).

### Phase (b) as built (2026-10-30, branch `wind_b`)

Owner decisions applied: the default direction is the weather particles' old one, toward
(0.707, 0, -0.707), so rain slant and gusts read against the camera and the plants (open question 1
is settled; the mills' clamp in 4c still applies when phase (c) lands); rain and snow follow the wind
whether or not the Wind tile is on; the wind streaks are a view of the same wind.

What exists:

- **The default direction is defined once**: `WindPresets.DEFAULT_DIR_ANGLE = -PI / 4`, with
  `default_direction()` (unit vector) and `default_direction_deg()` (315) derived from it;
  `WindState`'s default and the weather renderer's streak emitter read it. `-1` in
  `wind_direction_deg` still means "the default", so saved levels keep their meaning (they now
  blow toward the diagonal where they blew toward -z).
- **`utils/wind_particles.gd` (`WindParticles`)**: the pure functions (rain slant, direction and
  gravity, snow drift, gravity and turbulence, streak speed and ratio, smoothing, the change rule)
  and their constants. Tested by `tests/unit/test_wind_particles.gd`, which also holds the guard that
  no weather script keeps a literal wind vector.
- **`WeatherRenderer`** loses `WIND_DIRECTION`, `RAIN_WIND_STRENGTH`, `SNOW_WIND_STRENGTH` and the
  duplicated literal in the streak emitter. `_process` calls `wind_due(delta)` and, at most every
  0.1 s, samples `Wind.wind_at` and the local gust at the view centre, scaled by the motion scale,
  and `step_wind` smooths it (0.4 s) and writes the materials only when it moved (0.15 m/s or gust
  0.04). Constants as designed: rain `tan = clamp(speed * 0.045, 0, 0.7)`; snow drift half the wind,
  capped at 4 m/s; streak speed `2 + 0.6 * speed`.
- **Reduce-motion and `wind_motion`** scale the sampled wind, so lean, drift, gust turbulence and the
  streaks fade out together; rain and snow still fall at their normal speed (tested and captured).
- **Clouds, fog, sky**: nothing drifts today, so nothing was added (as the card says).

Deviations and what was learned:

1. **Streak speed is `2 + 0.6 * speed`, not `2 + speed`.** At the design's rate a storm streak ran
   12 to 18 m/s, crossing the whole emission box in under 3 s; at 0.6 it reads as drifting wisps.
2. **The Wind tile sets the streak amount (0.2..1), not a threshold.** The tile and the wind strength
   are the same dial, so "visible in proportion to wind speed, hidden at calm" is the tile's intensity
   itself; the 0.15 threshold of 2.6 was dropped. The streaks brighten with the local gust
   (alpha 0.28..0.52).
3. **Reduce-motion hides the streaks and straightens the rain** (card item 6), where 2.6 had left a
   static slant. Rain and snow keep falling at full speed.
4. **One sample for the whole screen.** The wind is read at the view centre, so a gust leans all the
   rain at once; the spatial wave in the plants does not reach the rain. The optional particle shader
   would fix it and was not attempted.
5. **Snow drift goes through gravity**, the one parameter that survives collision hide-on-contact:
   the horizontal acceleration is the drift speed, and the flakes' damping (0.5 to 1.5) makes the
   terminal drift 0.7 to 2 times that, so flakes differ from each other.
6. **The phase (a) captures changed with the default direction**: against the earlier run of
   `wind_a_look` (forest map), mean channel difference at home zoom 5.2 and 4.6 (calm, clocks 0 and 6),
   10.3 and 10.9 (windy), 12.0 and 13.4 (storm), and 0.6 for the two close captures that set
   `dir_deg` 0 explicitly (run-to-run noise). Trees now lean across the view as well as along it.

How the look reads (render job `wind_b_look`, `grassland_meadow_summer_s1`, 150 ft, zoom 10, calm,
windy and storm at wind clocks 0 and 6, plus a live-clock series of four stills 1.5 s apart; the
harness captures stills only, so the 12 to 20 s moving capture was replaced by those):
- Rain, calm: nearly vertical, a few degrees. Windy: a clear lean of about 20 degrees, still orderly.
  Storm: about 30 degrees and the live series shows the lean breathing between roughly 15 and 35
  degrees as gusts pass; strong but not chaotic. Motion 0: vertical at full fall speed.
- Snow, calm: sparse flakes falling slowly. Windy and storm: flakes drift off along the wind, a loose
  swirl in the storm; the 600 flakes spread thin over a large view, so the drift reads weakly at
  zoom 22 and well at zoom 10. Honest verdict: good at windy, a little sparse at storm.
- Streaks: faint thin wisps, readable at storm along the wind direction; at windy they are few. They
  do not compete with the plants. Hidden at calm and at motion 0.
- At zoom 22 (the map's wide view) all three are close to invisible (the rain boxes are 0.02 m
  wide); that was already so before this phase and was not changed.

### Phase (c) as built (2026-10-30, branch `wind_c`)

Windmills, cloth (banners, pennants, awnings) and the weathervane follow the global wind.

What exists:

- **`utils/structure_wind.gd` (`StructureWind`)**: the pure parts and their constants, tested by
  `tests/unit/test_structure_wind.gd`: `mill_cap_offset(wind_toward, centre)` (the turn from the
  camera-friendly bearing onto the wind's source, clamped to `MILL_CONE_RAD`), `mill_speed(speed)`
  (`0.12 + 0.045 * speed`, capped at 1.1 rad/s), `ease_toward` / `ease_angle` (exponential, time
  constant `EASE_SECONDS` 2 s, the short way round across +-180), `vane_step` (a damped spring,
  omega 2.6 rad/s, zeta 0.35, substeps of 0.02 s) and `vane_wobble(gust, speed)`.
- **Mills** (`MillMotion`): the cap yaw is `facing(WIND_FROM) + offset`, the offset eased toward
  `mill_cap_offset(wind, WIND_FROM) * motion`; the sails turn at `eased mill_speed(|wind|) * motion`
  times the building's +-25 percent factor. The wind is sampled (`Wind.wind_at` at the node) every
  `StructureWind.SAMPLE_SECONDS` (0.1 s, staggered per building); a mill starts in the pose the wind
  asks for, so it never swings into place. Motion scale 0 (reduce-motion, `wind_motion` 0) eases the
  sails to a stop and the cap onto `WIND_FROM`; between 0 and 1 it scales both.
- **Cloth** (`StructureCloth`, `shaders/structure_ornament.gdshader`): see structures.md "Cloth in
  the wind". A vertex branch (`S_WIND`, hooked in `structure_painterly.gdshaderinc`) reads the global
  `wind_dir` / `wind_phase` / `wind_gust` (the gust field is a copy of `wind_gust_field`, term for
  term) and moves each vertex by its weight: a lean downwind that rises with the local gust and
  the wind speed, plus a flutter across and along the wind (an awning flaps up and down). Everything
  scales by `wind_gust.w`, so reduce-motion and `wind_motion` still the cloth at no CPU cost.
- **Weathervane** (`StructureVane`, `VaneMotion`): see structures.md "Weathervane". The arrow
  assembly is a spring on the yaw toward the wind's source, the gust pushing the target a few
  degrees. Motion scale 0 holds the built pose.

Deviations and what was learned:

1. **The cone is 30 degrees, not 50.** The first render round showed the default diagonal wind
   (from bearing 135 degrees) pinning the cap at the 50 degree edge, 84 degrees off face-on to the
   default camera: the sails were a hairline. At 30 degrees the default pins the cap 64 degrees off
   face-on, a sail still about half its width (the later rounds read well). `WIND_FROM` is the
   centre as decided; the owner may want the cone or the centre moved (open question).
2. **The cloth weight is in the second UV set, not vertex colour red.** The colour array is in
   `digest_of`, so the weight rides in `ARRAY_TEX_UV2` (x metres of reach, y lean), which the digest
   does not hash: `tests/fixtures/structure_digests.txt` did not move.
3. **The crossbars stay put.** The card listed the cross pieces in the vane's pivot; a weathervane's
   cross is the compass and does not turn, so only the shaft, arrow and tail do (the base, pole,
   crossbars and balls are static).
4. **The vane is split at node creation, not in `build_one`**, so `parts.meshes` and the digest are
   untouched (a vane split in the build would reorder the digest's meshes).
5. **Cloth displacement never follows the normal**: the two faces of a sheet and its extruded edges
   share vertex positions but not normals, and a normal-driven flutter splits them. Directions
   come from the wind and the up axis only.
6. **Wind sampling is every 0.1 s**, not every frame: per frame it cost 5.5 us a mill and 7.4 us a
   vane, sampled it costs 2.8 and 2.7 us (see PERFORMANCE.md "Wind").
7. The structure's transform is the identity (`AuthoredStructures` sits at the map origin), so the
   cloth shader moves vertices in object space with a world-space wind; a rotated host would need the
   model matrix's inverse.

How the look reads (render jobs `wind_c_look` to `wind_c_look4`; a village of keep, townhouse,
cottage and two windmills laid across the view, calm, windy and storm at wind clocks 0 and 2):
- **Mills: good.** At the wide view both caps face the clamped direction three-quarter on, sails
  readable, none edge-on; calm and storm differ in sail speed (stills cannot show it).
- **Vane: good.** The arrow points left, into a wind blowing right, at both calm and storm; the
  tail fin sits downwind. Calm and storm look alike by design (the default direction does not
  change with strength); the wobble and the spring cannot be judged from stills.
- **Awning: subtle.** At zoom 5 the storm awning shows a slight shear and a lifted hem against the
  calm one; at the home zoom it is not readable. Banners and pennants on the keep were not in
  frame in any capture (they sit on the back corners of the roof), so their lean is not verified
  by eye, only by the weight tests. Amplitudes were raised once (lean 0.12 + 0.34 gust, flutter
  0.04 + 0.12 gust, both times a strength of 0.25 + speed / 10) after the third round. Honest
  verdict: correct and safe, but cloth at tabletop zoom reads as little more than a twitch; if the
  owner wants it legible at home zoom the amplitudes can be doubled without structural change (two
  constants in the shader).

## 5. Look, tuning and accessibility

### How gusts should read

At the default zoom the eye needs to see a front, not a shimmer: a bright-to-dark band of leaning
grass about 6 to 10 m wide (half of the 12 m wavelength) moving across the meadow at about 3 m/s
(crossing a 40 m view in 13 s), trees nodding a beat after the grass (their `sway_frequency` phase
is the lower 0.15 against grass 0.4, `wind_foliage.gd:49,59`), banners snapping as it passes,
rain leaning harder inside it, and calm between fronts (the `smoothstep` threshold gives bursts with
quiet gaps, `wind_foliage_include.gdshaderinc:217`). Storm adds the 7 m ripples inside the swells so
it never looks like the whole forest rocking in unison. Seed offsets and the veer keep two maps from
sharing a pattern. Judge by a 20 s capture at windy, not a still frame.

### Starting values and what to tune live

| Quantity | Calm | Windy | Storm | Live? |
|---|---|---|---|---|
| Mean speed m/s | 1.5 | 8 | 14 | derived from strength |
| Gust amplitude | 0.35 | 0.75 | 1.0 | yes (render-job parameter, later a debug row) |
| Sway scale | 1.0 | 2.2 | 3.2 | yes |
| Rain slant (degrees) | 4 | 20 | 32 | yes, constants in `WindPresets` |
| Front speed m/s | 3 | 3 | 3 (ripple 9) | no, fixed by the sync argument |
| Direction | default | default | default, veer 0.35 rad | yes (GM) |

Tuning goes through a debug override on the autoload (`Wind.debug_state`) that the render-job
runner and the F3 overlay can set, so a look can be dialled without rebuilding.

### Accessibility

- **OS reduce-motion.** `UiMotion.reduced()` (`utils/ui_motion.gd:15`) reads
  `DisplayServer.accessibility_should_reduce_animation()`. Today it is used only by UI
  and by `MillMotion` (`mill_motion.gd:52,88`); the foliage shaders ignore it. `Wind` polls it
  once per second (cheap, avoids a stale value after the user flips the OS setting) and sets
  `motion_scale = 0` when true. At zero: sway, lean, flutter and gust modulation are multiplied
  out by `wind_dir.w` (plants stand still), `wind_phase` publishing stops, cloth hangs, sails stop
  and the cap and vane are set to the target once, with no easing. Rain and snow still fall
  and still slant (a static slant, no gusts), because they are the weather, not decoration; wind
  streak particles are off.
- **A setting to scale wind motion.** A `[graphics] wind_motion` float, 0 to 1, default 1, saved
  with the other graphics values in `user://settings.cfg` and applied by the same loader pattern
  as `canopy_fade_enabled` (`visual_effects_controller.gd:182-190`). Effective
  `motion_scale = 0 if reduced else wind_motion`. It scales amplitudes only, never the clock,
  so peers stay in step whatever each player prefers (their screens differ in amplitude, not in
  phase). This is a per-player value, not a level field.
- **Frame cost of zero.** At `motion_scale == 0` the autoload skips phase publishing.

## 6. Risks and open questions

Risks, in order of concern:

1. **Foliage look drift.** The shader edit touches every plant. Mitigation: phase (a) is gated on a
   pinned-clock A/B at calm; a debug toggle (`Wind.debug_disable`) restores the old constant field for
   one run. The four `wind_foliage_debug_*` shaders and `wind_foliage_burn.gdshader` have their
   own `TIME` use (grep: all include `TIME`); check each still compiles and the sway stays in step,
   because the burn variant keeps its own `vertex()` (`wind_foliage_main.gdshaderinc:6-7`).
2. **Storm shear on tall assets.** `sway_scale 3.2` on a 6 m tree tip is about 0.6 m before the cap.
   The cap in 2.5 handles it; tune per category with `wind_response`.
3. **Particle collision.** The optional follow-up to phase (b) (a particles shader for coherent rain) may not preserve
   hide-on-contact. It stays optional until probed.
4. **Clock skew** between peers exceeding a few seconds. The offset fallback in section 3 is small.
5. **Warm-up.** Changing the foliage shaders changes the pipeline cache; `graphics_warmup` and
   the warm-up tests (`test_graphics_warmup_samples.gd`) must be rerun.

Open questions for the owner (only the ones that need a decision):

1. **Default direction.** Calm keeps today's plant gust direction toward (0.857, 0.514) so phase (a)
   changes nothing. Which direction should the world's default wind blow? Across the screen (toward
   (0.707, 0, -0.707), what the weather particles use) makes rain slant most readable but turns
   mills edge-on; toward -z (from the camera side) keeps mills three-quarter but rain slants
   diagonally. Recommendation: toward -z with a clamp on the mill (section 4c), decided in the
   phase (b) render round.
2. **Mills follow the wind exactly, or stay readable?** Recommendation: clamp to 50 degrees
   of the camera-friendly bearing, so a storm turns the sails faster but never edge-on.
3. **Constant front speed.** Storm gusts travel at the same 3 m/s as calm gusts and look stronger
   by lean, ripple and particles only (the price of staying pure and continuous, 2.2). If the
   owner wants faster storm fronts, the cost is a stamped `(t0, phase0)` pair in the weather
   document and a visible nudge for peers on each slider tick.
4. **Do rain and snow always slant** even when the Wind tile is off? Recommendation: yes
   (wind belongs to the whole level; "no wind" is the Calm preset). The alternative keeps today's
   behaviour, where precipitation falls straight unless the tile is on.

## 7. Recommendation and first phase

Do phase (a) first, alone: it gives every plant one wind, makes gusts agree between screens, fixes
the hourly `TIME` jump, and costs one autoload, three global uniforms and a small shader edit, with
no look change at calm and no UI. It is the foundation the other phases read. Estimated size:
about 400 lines of GDScript (autoload, `WindState`, presets, tests), about 60 lines of shader
change, one render job, one performance section appended to `PERFORMANCE.md`; roughly one to two
working days including the pinned-clock A/B. Phase (b) next (rain and snow, about 150 lines), then
(e) (controls and fields, so the GM can use it), then (c) (the visible payoff in structures), then
(d) and (f).

## Verification (planned)

- Unit: `tests/unit/test_wind_model.gd` (purity: same inputs same output; continuity through a
  preset change; phase wrap at `t` near 1e9; gust 0..1 range; veer bounds; table monotonic in
  strength), `test_wind_presets.gd` (stop values and interpolation), `test_weather_settings` (new
  keys round trip, old dictionaries load), `test_mill_motion` (rate function, clamp).
- Probe: a render-job probe that ticks `Wind`, reads the three globals back with
  `RenderingServer.global_shader_parameter_get` (the `render_state.gd` probe already lists globals,
  `tools/render_jobs/probes/render_state.gd:82-83`) and checks the reduce-motion path.
- Look: render jobs at calm, windy, storm with a pinned clock; a 20 s capture for gust travel.
- Performance: per [PERFORMANCE.md](../PERFORMANCE.md) "How to measure without fooling yourself":
  pinned viewport, vsync off, in-run toggle (`Wind.debug_disable`), compare deltas within one run.

## History

- 2026-10-30: design written (branch `wind_design`), no code.
- 2026-10-30: phase (a) built on branch `wind_a` (autoload, pure model, global uniforms, plant
  shaders, reduce-motion and wind-motion scale, tests, render and cost measurements).
- 2026-10-30: phase (b) built on branch `wind_b` (default direction toward 0.707, 0, -0.707, defined
  once; rain, snow and the wind streaks follow the wind; tests; look and cost measured).
