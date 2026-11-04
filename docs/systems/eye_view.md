# The eye view (street level)

The play camera that stands on the ground at a walker's eye and looks around: a perspective camera 1.6 m
(times the map scale) above the ground, in the same game as the orbit view, with its own painted sky, a fog
that hides the map's end, foliage that never walls the frame, a middle ground past the edge and a hint bar
row of its own. The bar it is judged against is the orbit view's: every allowed view must meet the home
view's look (owner verdict CQ1), and a map has no front (CQ3), so every side of every map must look good from
the eye, with the sun fixed in the world (CQ2). It is a play view (CQ5): the move, measure, ruler, sun and
pin tools work there, and authoring is an orbit-only tool (SL2). The decisions are in
`docs/plans/2026-11-02-camera/decisions.md` (gitignored; verdicts are cited by id below).

## Map

| File | Class | Role |
|------|-------|------|
| `scenes/states/playing/eye_view.gd` | `EyeView` | The view mode (`ViewMode`): takes over the single Camera3D and the CameraHolder, walks, grabs, glides, sweeps against collision, owns the sky, the glide and the rim switch |
| `utils/eye_rig.gd` | `EyeRig` | Pure maths: eye height, walk velocity and step, lens clamp and notch, bounds clamp, ground hit, grab pan, glide step, collision slide helpers |
| `utils/eye_collider.gd` | `EyeCollider` | A sphere swept in segments against the map's terrain-layer bodies; slides along what it meets |
| `scenes/states/playing/eye_sky.gd` | `EyeSky` | Installs the painted sky and the depth fog in the level's Environment while the eye is on, restores every field on leaving |
| `utils/street_sky_look.gd` | `StreetSkyLook` | The per-biome look table, `fog_range`, `map_reach`, `sun_angles`, `dominant_biome` |
| `shaders/street_sky.gdshader` | | The sky shader: gradient, warm band, cumulus banks and cloudlets, up to four ridge layers |
| `utils/eye_canopy.gd` | `EyeCanopy` | Pure foliage maths of the eye: near fade, focus window, ghost range, eye light, near grass; mirrored in `shaders/wind_foliage_include.gdshaderinc` and `wind_foliage_main.gdshaderinc` |
| `scenes/states/playing/canopy_fade.gd` | `CanopyFade` | Publishes `canopy_eye` and `eye_grass` (perspective camera) beside the orbit view's fade globals |
| `utils/eye_rim.gd` | `EyeRim` | Hedgerows and copses past the map edge: the pure plan and the `EyeRim` node |
| `scenes/terrain/skirt_backdrop.gd` | `SkirtBackdrop` | Fades the skirt and the water to the sky's foot colour; `EYE_HOLD_M` holds the fade at the eye |
| `scenes/states/playing/eye_glide.gd`, `utils/eye_glide_rig.gd` | `EyeGlide`, `EyeGlideRig` | The glide between the orbit view and the eye: state, frozen-frame veil, and the dolly-zoom maths |
| `scenes/states/playing/camera_view.gd`, `camera_controller.gd` | `CameraView`, `CameraController` | `enter_street`, `leave_street`, `toggle_street` (V, F9, tilt past home); `leave_eye`; `set_view_mode` |
| `utils/camera_rig.gd` | `CameraRig` | `is_street_key`, `STREET_PULL_DEG`, `play_hints(street)` (the two hint rows) |
| `utils/view_ground.gd` | `ViewGround` | Play tools at the eye: the ground under the cursor, the point ahead of the eye |
| `utils/eye_shadow.gd` | `EyeShadow` | The sun's shadow max distance fitted to the map from where the eye stands |
| `scenes/states/playing/map_view_fit.gd` | `MapViewFit` | Tells the eye the map's dominant biome and seed (`_set_eye_sky`) and the document bounds |
| `autoloads/ui_manager.gd`, `scenes/ui/input_hints.gd` | `UIManager.set_street_hints`, `InputHints.set_street` | The street hint row |

## Model

**Entry and exit.** Entering stands the foot at the ground point under the screen centre and keeps the yaw. The
orbit camera, holder, yaw pivot and pitch are remembered; leaving puts them back, with any turn made at the eye
applied about the orbit pivot, so the orbit view returns as it was. At the eye the camera is perspective, near
0.05, far 600 (`FAR_PLANE`), the holder stands on the foot and the camera sits `EyeRig.eye_height` above it, so
Q / E turn the eye in place. The pitch range widens to look 35 degrees up and 60 down (`PITCH_MIN` -35,
`PITCH_MAX` 60; entry pitch 6). The world viewport is raised to MSAA 4x while here
(`GameMap.eye_view_antialiasing`). `sky_custom_fov` is 0 (the orthographic view uses 2 degrees).

**Controls as shipped.**

| Input | Effect |
|-------|--------|
| V (bare key) | Step down to the street and back up with the glide. Not while authoring (SL1) |
| F9 | The same toggle, a debug key; also works in authoring |
| Flatter tilt at home (compass arrow, or an Alt + drag pulled `STREET_PULL_DEG` 8 below home) | The same step down (SL1). At the eye the steepest look down (the steeper arrow at pitch 60) climbs back up |
| Home | Glides out and runs the orbit's Home on landing |
| O | Leaves the eye (orbit pose restored), then toggles top-down |
| WASD, Shift | Walk relative to the facing at 5 m/s, Shift runs at 10 (SL3), eased with `WALK_ACCEL` |
| Left, middle or right drag on the ground | Grab: the ground point under the cursor stays under it. A ray flatter than 6 degrees below the horizon grabs nothing |
| Double-click ground | Glides the foot there; on a token, to 1.5 m short of it |
| Wheel | The lens: vertical field of view 40 to 75, default 60, 3 degrees a notch, eased (SL4) |
| Q / E, Alt + Q / E, Alt + drag | Turn about the eye (the brush owns Q / E when one is out); Alt + drag vertical tilts |

The foot stays 1.5 m inside the map (the document's whole extent, else the orbit bounds; SL5), the eye follows
the ground's height, eased. Walls and doors stop the eye (SL6, `EyeCollider`: a sphere of 0.55 m times the map
scale, swept in steps of at most its radius against the terrain-layer bodies of structures, walls and crossings,
the authored ground's own body excluded; tokens, grass, scatter and tree crowns have no body). There are no
interiors. A camera shake from a token drop is added on top of the pose.

**The painted sky and the fog (`EyeSky`, `StreetSkyLook`).** While the eye is the camera the level's Environment
gets `street_sky.gdshader` and a depth fog whose colour is the biome's foot colour; leaving restores every field.
Only a flat colour or an HDRI (`PanoramaSkyMaterial`) is stood in for (`EyeSky.can_paint`); a gradient sky is left
alone. The shader returns exactly what it replaces in the cubemap pass, so ambient light and reflections are
unchanged by construction (the verdict rounds are SK1, SK2 variant B, ES1, ES2). `EyeSky.sync` runs every frame the
eye is on: it notices a re-applied environment (the Sky pane, presets, weather) and puts the painted sky back. Godot
4.7 resets `fog_density` when `fog_mode` is assigned, so the mode is set first.

- The look table (`StreetSkyLook.LOOKS`): `default` plus the nine core biomes (`temperate_forest`,
  `birch_woodland`, `boreal_taiga`, `burnt_forest`, `grassland_meadow`, `rocky_badlands`, `savanna`,
  `wetland_riparian`, `alpine_meadow`). Each look is five colours (zenith, horizon haze, far, near, foot) and
  numbers (ridge `height_deg`, lattice `noise_seed` and `noise_period`, tree-crown height `teeth_deg`, crowns per
  turn `teeth_freq` and shape `tree_shape`), plus optional extras defaulted in `COMMON` (cloud cover, haze, mist, sun glow, a second cloud
  layer, snow). A biome id carrying a season and variant (`temperate_forest_summer_s1`) finds its look by the longest
  key it starts with; the map seed shifts the lattice seed (`posmod(seed, 61) * 0.31`) so two maps of one biome have
  different skylines. The ranges are checked in `test_street_sky_look.gd`.
- The fog is scaled to the map (ES2): `StreetSkyLook.map_reach(eye, bounds)` is the ground distance from the eye to
  the farthest corner of the walking area, and `fog_range(reach)` begins at `0.75 * reach` and ends at `1.5 * reach`
  (`FOG_BEGIN_REACH`, `FOG_END_REACH`). 25 m and 85 m (`FOG_BEGIN_M`, `FOG_END_M`, the owner's first figures) are only
  the floors, and the end is always at least 60 m past the begin. So a small valley keeps its detail clear and a
  large map is hazed toward its far edge, where the ground melts into the ridge foot. `EyeView` sets `sky.reach`
  every frame; the depth is rewritten only when it moved by 0.05 m, so walking does not touch the environment.
  `fog_offset` moves both out by the camera's distance from what it looks at, nonzero only during the glide.
- The foot colour is also the fog colour and the colour the skirt and the water fade to (`SkirtBackdrop` reads the
  shader's `foot_on` and `foot_color`), so grass, skirt, fog and ridge foot are one tone. At the eye the skirt's fade
  holds for `SkirtBackdrop.EYE_HOLD_M` (14 m, the shader's `skirt_hold_m`) past the edge and still ends at
  `skirt_fade_m` (24 m): the ground runs on past the edge and fades near the ridge foot instead of laying a veil
  whose straight boundary follows the edge line. The orbit view's fade is unchanged (hold 0).
- `tools/eyesky_radiance_probe.gd` proved the lighting equivalence: HDRI base, diffuse, rough metal and mirror
  spheres 0.0000 mean byte difference against the old sky. A flat-colour level has one difference (its reflection
  source is the flat colour, diffuse within 1 LSB). A level's own ReflectionProbe is not re-rendered.

**The rim (`EyeRim`).** A new map's cover feathers out over the last 3 to 12 m inside its edge, so the orbit view
fades out on grass; at the eye that band, the skirt and the sky's foot are an empty plane up to the ridges. The rim
gives it a middle ground (CQ3, ED1) without touching the orbit view: past the edge, on the skirt, hidden in the
orbit view. The plan is pure (`EyeRim.plan`): each side is cut into 10 m slots (`SLOT_M`); the map seed picks per
slot a gap (30 percent), a hedge (35 percent, a loose row of shrubs 2 to 5 m out, 1.8 m apart) or a copse (the
rest: 2 to 5 trees 4 to 10 m out within 3.5 m of a centre, with 1 to 3 shrubs at their feet). Species come from the
dominant biome by kind and size (large trees, medium shrubs and understory), so a biome with no large trees makes
shrub clumps, one with no shrubs makes hedges of trees, one with neither none. Slots by a river that runs out past
the edge stay open (`RiverExits.exits`, `RIVER_CLEAR_M` 5 plus the half width). Heights follow the skirt's fall
(`TerrainMeshBuilder.skirt_height`). The node is an `AuthoredScatter` named `EyeRim` under `LevelMap`, made the first
time the eye opens on a map and only hidden after; the plan is rebuilt from the document on each opening, so an edit
to the edge or the biome is followed. A map with no document gets none.

**The canopy (`EyeCanopy`).** The orbit view tells the foliage how far the camera is by the orthographic size; a
perspective camera has no such number, so the eye publishes its position and the map scale (`canopy_eye`, w is the
scale, 0 means not the eye view) and the shaders fade by distance from the eye. A shader acts only in the camera's own
pass (the fragment's camera within `PASS_TOLERANCE_M` 0.25 of the eye), so shadows are untouched. Distances scale by
the map scale. The terms:

- Near fade: a leaf card or limb inside 1.2 m is gone, thinned out to 4.0 m, card by card; trunks stay. It does not
  depend on the Settings "Canopy fade" switch (`NEAR_FULL_M`, `NEAR_NONE_M`).
- Focus window: the existing canopy window, centred on the ground the centre ray meets (8 m ahead when it misses),
  with the eye-to-focus distance standing in for the orthographic size. Only when the Settings switch is on.
- Ghost range: a token ghost fades from 30 m, gone by 50 m.
- Eye light (FO1): at street level the crown's underside and far side were near black. In the eye's pass a tree's painted
  card lifts its shade end to 0.3 of its lit tone (`SHADE_FLOOR`), keeps its ambient, and glows warm where the sun
  shines through it toward the eye (`GLOW_START` 0.1 to `GLOW_FULL` 0.85 of the view-ray dot with the sun); bark and
  plain cards gain 0.35 of their albedo. Grass and the orbit view are untouched.
- Near grass (EG1): a tuft within 9 m (full inside 1.5 m) thins tuft by tuft, takes 18 percent of its own grey, deepens
  from a cool dark foot to a tip at 0.88, tapers at the tip and steps its value per tuft; warm blades (dry gold,
  straw) keep their colour and gain a warm foot and a glowing tip. The `eye_grass` global is the map scale at the eye
  and 0 otherwise. The constants are in `lighting-and-environment.md` "The eye view's near grass".
- `test_eye_canopy.gd` holds the GDScript mirror and the shader constants together.

**The glide (`EyeGlide`, `EyeGlideRig`).** Entering and leaving are a dolly zoom (SL1, EN1, EN2): a perspective
camera on the home view's axis `V / (2 tan 1 degree)` back (974 m on the hamlet) with a 2 degree field of view, which
draws the home picture, dropping onto the eye in 1.3 s with `d(q) = (d0 + 3) e^(-lam q) - 3` and
`fov = min(lens, 2 atan(V / 2d))`, while the pitch and height blend onto the eye's over q 0.45 to 1. Companions per
frame: near 0.05, far `max(600, d + 300)`, `EyeSky.fog_offset = d`. The owner asked for no fog dip in the middle
(EN2). Each end is a dissolve of a frozen frame (`EyeGlide.freeze_veil`, a window read-back as an `EyeGlideVeil`
TextureRect under the world viewport layer, 0.25 s): the orbit's grey skirt haze and the eye's foot-coloured fog
differ in one frame, and the switch waits one frame so the veil has been drawn (first glide frame change 15.7 against
0.2 with the veil). A frame that stalls advances the glide by at most 0.05 s. Any key, pan press, wheel notch,
compass button or Alt + drag lands the glide at its target pose before it acts. `EyeGlide.allowed()` is false (the
change is instant) when `EyeGlide.enabled` is off or the operating system asks for reduced motion
(`UiMotion.reduced`). There is no "Smooth view change" setting (SV1: skip); `enabled` is the switch it would set.
`CameraController.leave_eye` is instant; authoring never glides.

**The hint row (HN1).** `EyeView.activate` calls `UIManager.set_street_hints(true, brush_owns_turn_keys)` and
`deactivate` calls it with false, which swaps the play base hints through `InputHints.set_street` between
`CameraRig.play_hints(false)` (Esc Pause, WASD Pan, Scroll Zoom, Q E Turn view, Alt + drag Tilt, Reset camera, M
Measure, Grid, F1 Help) and the street row (`play_hints(true)`: Esc Pause, WASD Walk, Shift + WASD Run, Scroll Lens,
Q E Turn view, F9 or V Leave, M Measure, F1 Help; no Home, no grid, no Alt + drag). The run chip is "Shift + WASD", not
"Shift", because a token drag lays a "Shift" free-move hint on that key and removes it again. The view is remembered
in `InputHints`, so a controls-profile change and the next map's default hints come out right, and an empty bar (not
playing) stays empty. `GameplayMenuController._exit_tree` resets it. The bar's own padding is a separate verdict (HB1,
HB2).

**Picking and play tools.** The drag target under a perspective camera is the first ground the cursor ray meets on
the height field (`ViewGround`); a ray flatter than 6 degrees below the horizon names no ground. "The view centre on
the ground" (new token landing, the sun ring, the grid's fade centre) is the point 5 m ahead of the eye
(`ViewGround.AHEAD_M`). The weather box is 20 m around the eye; overlay lines use `CameraRig.screen_segment` /
`screen_runs` so nothing behind the eye is drawn. The sun's shadow max distance is fitted to the map from the eye
(`EyeShadow`).

## Runtime

Nothing here is saved or networked: the view is local to each player (CQ6) and every peer builds its own sky, rim and
fog from the map document (biome ids and slots, seed, extent, river exits). `CameraController` owns an `EyeView`
(`controller.eye`); `MapViewFit` names the dominant biome and seed and passes the document bounds whenever the map is
fit, whichever view is active. Per frame (`EyeView.process`): sync the sky field of view, step the glide or the lens and
the walk, clamp the foot, ease the ground height, place the camera and publish the canopy globals. The sky shader
compiles on the first entry (not in the graphics warm-up).

## Authoring

The eye is a play view. `GameMap.setup_authoring` calls `CameraController.leave_eye()` (SL2); V and the tilt refuse
in authoring, F9 does not. Nothing in the document records the eye. The look is tuned by editing the
`StreetSkyLook.LOOKS` table and by the biome the map's slots name; there is no in-game control for it.

## Verification

Unit tests: `tests/unit/test_eye_view.gd` (rig, walk, bounds, hint row, F9), `test_eye_collider.gd`,
`test_eye_glide.gd` (21 tests, the glide, V and the tilt), `test_eye_sky.gd`, `test_street_sky_look.gd`,
`test_eye_canopy.gd`, `test_canopy_fade.gd`, `test_eye_rim.gd` (species, plan, `near_line`; `EyeRim.show` and `plan_for`
have no test), `test_eye_pick.gd`, `test_view_ground.gd`, `test_eye_shadow.gd`, `test_input_hints.gd`.

Render jobs (`tools/render_jobs/JOBS.md`): the `el_*` eye-level look round, `eyeedge_*`, `eyefoliage_*`, `eyegrass_*`,
`eyehints_look`, `streetdoors_*`, and the older `eye_view_*`, `eye_glide_*`, `eyepick_*`, `es_*`, `ep_*` (eye
performance); probes `eye_view.gd`, `eye_glide.gd`, `eye_look.gd`, `eye_perf.gd`; `tools/eyelook_sheets.gd` for contact
sheets; `tools/eyesky_radiance_probe.gd` for the lighting equivalence.

Numbers: [../PERFORMANCE.md](../PERFORMANCE.md) "Eye view frame cost", "Eye foliage light" and "Near grass at the eye".
The lighting figures are in [../lighting-and-environment.md](../lighting-and-environment.md) "The eye view's painted
sky and edge fog" and "The eye view's near grass"; the controls table in [../CONVENTIONS.md](../CONVENTIONS.md) "Camera System" > "Controls".

## Open work

The map hub owns the list: [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work". Eye-specific items: a thin white
streak beside a bank when looking up 15 degrees (savanna, yaw 225 and 315) belongs to the high cloudlet layer and goes
when `cloud2_cover` is 0 (card eyeedge); `EyeSky._still_ours` calls `StreetSkyLook.look_for` every frame (a dictionary
merge) and `EyeView` reads the environment twice a frame; `EyeRim.show` and `plan_for` and the street-hint wiring
(`GameplayMenuController`) lack direct tests (audit1, 2026-11-03).

## History

- Eye rig, collider, picking and canopy fade (cards eyeview, eyecollide, eyepick, 2026-11-02).
- `1b9fa113` painted sky and edge fog (eyesky, SK2 B), `9580d24f` fog scaled to the map and per-biome tuning (eyesky2, ES2).
- `1fc7adbd` the glide (eyeglide, SL1, EN1, EN2); `59be26e1` the eye's shadow fit (eyeperf).
- `36d5374b` the street hint row (eyehints, HN1); `d1810087` eye foliage light (eyefoliage, FO1).
- `0824ed81` the rim and the skirt hold (eyeedge, ED1); `9f5768be`, `b25c80fc` near grass (eyegrass, EG1).
