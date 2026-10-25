# Render jobs catalogue

Every job in `jobs/`: what it builds and captures, roughly how long a full build run takes,
and which test levels it keeps. How to run one, the flags and the build / look loop are in
[README.md](README.md); the ops and probe scripts the jobs use are in
[REFERENCE.md](REFERENCE.md). Captures are half size (960x540) unless the run passes
`--full`; a judgment set's final pass, the one its `VERDICT.md` is written from, passes it.

## Jobs

- `jobs/plantgen_ab.json`: treecube against plantgen foliage on one map (about 30 s, keeps no
  level): a new 200 ft alpine map (seed 1234) with the installed palette at home and at size 14,
  then the `foliage_library` op serves `D:/dev/plantgen/out/ttsim_package_plantgen_all` and
  reopens the map in memory (scatter regenerated from the same biome painting) for the same two
  cameras, then back to treecube for a home view that equals the first. Fades off, wind frozen,
  5 captures, 10 PNGs. Edit the `package` path to compare another build.
- `jobs/library_s1_savanna.json`: the content library against the plantgen package it was built
  from (about 30 s, keeps no level): a new 200 ft savanna map (seed 1234) with plantgen's
  `lib_slice_pkg` laid over the installed palette (home, size 14), then the same map with
  `D:/dev/plantgen/out/lib_slice` compiled over the treecube palette by `LibraryRegistry`
  (`library_dev` op), same cameras, then the override cleared (the treecube baseline). Package
  and library captures are pixel-identical (2026-10-24). 3 view pairs plus the baseline, 10
  PNGs. `docs/systems/library.md`.
- `jobs/library_s3_parity.json`: the surface resolver's A/B (about 30 s, keeps no level): savanna
  and rocky badlands, 150 ft terraces landform, seed 1234, fades off, wind frozen, a home view
  and a size-14 view each (4 captures, 8 PNGs). Run it with `--full --out render_jobs/<name>` on
  main before a change to how surface maps load and once after, and compare the `_sub` PNGs
  (`magick compare -metric MAE`): the home views were 0.000 of 255 for the S3 SurfaceStore
  change, the close views within the 0.2 to 0.75 run-to-run noise of main against itself
  (2026-10-24). `docs/systems/library.md`.
- `jobs/plantgen_play.json`: the same switch in play (about 30 s): builds the alpine map, saves
  it as `_reopen_plantgen`, plays it with treecube and again after switching to plantgen (Root
  reloads the table; the load regenerates the rows), then removes the level
  (`render_state.gd cleanup`, which takes every `_reopen_` folder).
- `jobs/authoring_judgment_set.json`: the authoring judgment set: two captures per palette
  biome plus three, each as a window and a raw PNG (21 captures, 42 PNGs, with the 9-biome
  palette installed in October 2026). Every palette biome as a new 200 ft map (seed 1234) at home
  and full zoom-out; a hand-painted composition on bare ground (grassland meadow and
  temperate forest strokes, a thinned path, a cleared glade, placed props) at home, zoom 26
  and full zoom-out; then `INDEX.md`. The Blender reference levels `river` and
  `deciduous_clusters` were dropped on 2026-10-12 (the user's call: obsolete, and the set
  ran into its 900 s timeout); the phase 3 and phase 4 sets lost them the same day.
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
  the home view (with an A/B of the broad edge and so the trampled fringe, `biome_broad_strength` 0 vs 0.8), undo /
  redo of the last stroke. Frame times per stroke (`record`). `jobs/paint_shoulder.json` (about
  30 s) paints the same track alone and runs `paint_check.gd` along it with a zoom-8 capture.
- `jobs/path_shoulder_look.json` (about 65 s): which grasses thin and which flowers gather
  beside a path, on the grassland meadow and then the alpine meadow (`ps03_alpine_home`). A
  new 200 ft grassland meadow at seed 1234, a dirt road (`dirt_road_packed`, radius 1.3)
  painted across it, canopy fade off, the brush cursor and the tool rail (`hide_ui`) hidden;
  captures at home zoom and at zoom 10 on
  the road (the zoom pinned to the screen centre, so runs frame alike). Run it with `--out`
  before and after a ground-role change and compare. Saves no level.
- `jobs/phase3_judgment_set.json`: the phase 3 judgment set (P3-7, about 7 minutes): for
  temperate forest, alpine meadow, rocky badlands and grassland meadow, a new 150 ft map
  (seed 1234) built with the real Sculpt and Paint tools at human speed (a raised hill, a
  two-tier plateau with a Shift-smoothed ramp, a sunken hollow, a track up the ramp in the
  biome's first path surface, a path across a tier edge and a courtyard on the top tier in
  its first stone path surface (`PaletteLibrary.path_surfaces`; badlands: `dirt_road_caliche`
  and `flagstone_sandstone`), three placed props), captured at home zoom, home zoom on the plateau, zoom 26 and full zoom-out, each
  with the grid off and on. 32 captures and `INDEX.md` (the Blender reference levels it played
  last were dropped on 2026-10-12).
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
  and played with tokens wading, floating and standing in the stream (the Blender `river`
  level it played last was dropped on 2026-10-12). The test levels are deleted at the end. 40
  captures and `INDEX.md`.
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
- `jobs/bridge_tool.json`: the Bridge tool (P4b-2, about 70 s) through real input events
  (`gesture`, `input`) on a new 150 ft temperate forest map with a waist-deep river: the pane,
  a plank line previewed near the water and on the far bank then released, a refused line on
  dry ground (hint and toast), stepping stones previewed and placed (and close up), home, Ctrl
  hover and Ctrl+click erase and its undo, a Raise stroke that re-anchors the bridge, a Tier
  stroke that removes the stones with their water (toast) and its undo; `crossing.gd` `bench`,
  `timing` and `list` logged along the way. 17 captures and `INDEX.md`. Saves nothing.
  `jobs/bridge_first_use.json` (about 25 s) times the first-use parts of a crossing node
  (`first_use`) and placements after the tool's warm-up (`bench`).
- `jobs/phase4b_judgment_set.json`: the phase 4b (crossings) judgment set (P4b-3, about 13
  minutes): for every palette biome (`expand_biomes`, `{path}` is the biome's first path
  surface), a new 150 ft map with a waist-deep river, a deep pond and a path across the river,
  then through the real Bridge tool (`gesture`) a plank bridge where the path meets the river,
  stepping stones downstream and a long plank bridge over the pond (over 5.5 m: pile bents);
  authoring captures at home, zoom 8 on the bridge (grid off and on), zoom 5 on the stones and
  zoom 10 on the long bridge; then saved as a `_p4b3_` test level and played with tokens on
  both decks and the stones and one wading beside the bridge (its submerged ring), grid on.
  Last, the phase 4 wetland rebuilt (tier, river, stream, pool, plank path) and re-rendered to
  check the reeds after P4b-0's rock-foam change. Test levels deleted at the end. 76 captures
  (eight biomes) and `INDEX.md`; the verdict is written beside them as `VERDICT.md`.
- `jobs/p4b3_stones_iter.json` (about 55 s): stepping stones over a waist river in alpine,
  grassland and forest at zoom 5 and home, for iterating on the stones' rock and moss.
- `jobs/p4b3_reanchor.json` (about 60 s): a plank bridge, then Smooth passes and a light Raise
  at its banks through the real Sculpt tool, with the crossing list and the ground profile along
  the bridge (`height_profile.gd`) logged after each: how far a re-anchor moves on a gentle
  underwater bank. Saves nothing.
- `jobs/p4b3_perf_build.json` and `jobs/p4b3_perf_play.json`: the phase 4b pinned performance
  pass (`PERFORMANCE.md` "Phase 4b (crossings): pinned performance pass"). The build job makes a
  150 ft forest map with a river, a pond and a path (saved as `_p4b3_perf_water`), then places
  four crossings with the real tool recording frame times around each drag and release, benches
  `plan()` and a place / undo, times a Raise by a bridge, and saves `_p4b3_perf_cross`. The play
  job (run with a temporary pinned `override.cfg`, which it deletes) times warm loads of both
  levels interleaved, samples GPU time with the crossings shown and hidden in one run at home,
  zoom 20 and zoom 8 on a bridge, then each level at home and zoom 20 with tokens, and deletes
  both levels. `perf.gd gpu_state` logs `nvidia-smi` at the start and end of each.
- `jobs/p4c_perf_build.json` and `jobs/p4c_perf_play.json`: the phase 4c pinned performance
  pass (`PERFORMANCE.md` "Phase 4c (waterfalls): pinned performance pass"). The build job makes
  the judgment set's forest map (two-tier step, 13 m hill) with six falls (a waist river over
  the step, an ankle tributary, two ankle streams down the hill flank with `record` windows
  around the strokes and an erase, a deep river off the far edge through `water.gd carve`) and
  saves `_p4c_perf_falls`, then the same sculpt with the five waters on the flat ground, saved
  as `_p4c_perf_riffles`. The play job (run with the pinned `override.cfg`, which it deletes)
  opens the falls level once in authoring for `falls.gd`'s `found:` names, times warm loads of
  both levels interleaved, samples GPU time with the falls mesh shown and hidden
  (`falls_visible`) at home, zoom 8 on the hill and on the tier fall and zoom 20, Water
  Quality Low against High (`quality`; both take `expand` labels, "off ..." and "low ..."),
  then each level at home and zoom 20. The levels are kept (`cleanup_levels.json` deletes
  them).
- `jobs/p4d_perf_build.json` and `jobs/p4d_perf_play.json`: the phase 4d pinned performance
  pass (`PERFORMANCE.md` "Phase 4d (arch and ford): pinned performance pass"). The build job
  makes the P4b-3 map (a curved waist river, a deep pond, a path; saved as `_p4d_perf_water`),
  draws an arch and a ford through the real tool with `record` windows around each drag and
  release, places a plank bridge, stepping stones, a 14.8 m pier arch along the pond and a
  second ford through `crossing.gd place` with `timing` after each (the rebuild cost by
  crossing count), benches plank and arch plans, times a Raise by the arch and saves
  `_p4d_perf_cross` (six crossings). The play job (run with the pinned `override.cfg`, which
  it deletes) times warm loads of both levels interleaved, samples GPU time with the crossings
  shown and hidden at home, zoom 8 on the arch and on the ford and zoom 20, then each level at
  home and zoom 20 with tokens and `mem`. The levels are kept (`cleanup_levels.json` deletes
  them).
- `jobs/p5_perf_open.json`, `jobs/p5_perf_strokes.json` and `jobs/p5_perf_play.json`: the
  phase 5 (starting landforms) pinned performance pass (`PERFORMANCE.md` "Phase 5 (starting
  landforms): pinned performance pass"). Open: `perf.gd author` with each landform in the
  forest at 150 ft (seed 7, three interleaved rounds, flat first) and flat, valley and gorge
  at 100 and 200 ft, `mem` after each, `perf.gd recipe` (the recipe's own ms) at the title;
  strokes: the forest Terraces and flat maps (seed 3) with `record` windows around idle, a
  Raise on the stage, a Smooth across a step, a waist river and its erase, saved as
  `_p5_perf_terraces` / `_p5_perf_flat`; play (deletes the pinned `override.cfg`): warm loads
  of both interleaved, then GPU windows at home and zoom 20, `mem`.
- `jobs/falls_look.json`: the waterfall carve and curtains (P4c-2, P4c-3, about 100 s): a new
  150 ft temperate forest map with a two-tier Tier step and a 14 m Raise hill (real Sculpt
  strokes; the hill's flank runs steep for about 9 m, so the stream down it gets two falls), a
  straight waist river drawn from the step's top toward the camera, an ankle stream from the
  hill's top down its flank toward the camera, and a second waist river carved through the
  editor API (`water.gd carve`) off the step's far edge, away from the camera; `falls.gd
  falls` logs each fall's lip, foot and the carved profile, then the ground is captured with
  the water hidden at home and at zoom 8 on each facing fall's foot, and the water shown at
  home and at zoom 8 on every fall (the tier fall, both hill falls, the away-facing fall's
  lip); then (P4c-4, the falls shader) the tier fall at zoom 6 and 10, two zoom-10 frames
  about 0.25 s of shader time apart (`clock`), Water Quality Low (`quality`), the Swamp
  palette (`palette`), and an indicative GPU A/B of the falls shown and hidden at zoom 8
  (`vsync_off`, `gpu`, `falls_visible`; about 15 s). 15 captures and `INDEX.md`. The
  worked example of the build / look split: the build ends by saving `_p4c_falls_look`
  (kept on purpose; `cleanup_levels` removes it), every camera move is tagged `for` its
  capture and the GPU A/B is `for: "falls_gpu"`. A look run,
  `falls_look --saved --only tier_fall_z8_water,hill_fall1_z8_water`, loads the
  level and takes those two captures at 960x540 in about 15 s (93 s for the full build run);
  `--only falls_gpu` runs the A/B alone.
- `jobs/falls_tools.json`: waterfalls, the tools and play (P4c-5, about 80 s): a new 150 ft
  temperate forest map with a Tier plateau and a waist river drawn over its south edge toward
  the camera (one fall, `falls.gd falls` names its lip, foot and plunge); through real input
  events the Bridge tool refuses a line across the plunge pool just below the fall (red line,
  the fall's message beside the cursor, then as a toast) and places a plank bridge across the
  upper pool 2.5 m upstream of the lip; the Water tool holds a river stroke drawn uphill onto
  the plateau mid-stroke (the ribbon's chevrons point downhill) and cancels it; then the
  level is saved as `_p4c_tools` and played with a token wading in the plunge pool (its
  submerged ring) and one in the upper pool. 8 captures and `INDEX.md`; the test level is
  deleted at the end (`water.gd cleanup` covers `_p4c_*`).
- `jobs/phase4c_judgment_set.json`: the phase 4c (waterfalls) judgment set (P4c-6, about 15
  minutes): for every palette biome (`expand_biomes`), a new 150 ft map (seed 1234) built with
  the real tools at human speed: a two-tier Tier step about 10 m deep and 28 m wide (zigzag
  Tier paths, so the brush covers the whole top; the west shelf one tier high; every river's
  area, half-width plus the 1 m bank, stays clear of the inner tier's side faces, or its flat
  surface hangs down them), a 13 m Raise hill east of it
  (flank 44 degrees, a steep run of about 9 m; placed where it stands clear of every later
  stroke's pointer ray), a waist river over the step's south edge toward the camera (one
  two-tier fall), an ankle tributary from the west shelf over the edge into the main plunge
  pool, an ankle stream down the hill's flank (two hillside falls), and a deep river carved
  through the editor API off the step's north edge, away from the camera (its free head 5 m
  from both brinks: a deep river's area, half-width 2.96 m plus the bank, hangs its surface
  over any brink nearer than 4 m); captured in authoring at home and at zoom 8 on the tier fall (grid off and on), the
  tributary, the hill steps and the away-facing lip, then saved as a `_p4c_` test level and
  played with tokens in the tier fall's plunge pool, on its lip, in the tributary's pool and in
  the away-facing pool, grid on (home and zoom 8). Last, a v0.1.29-style document (`falls.gd
  ramp` and `old_river`: a river over a Tier cliff and one down a 39 degree ramp) captured as
  built and after a save and load in play. 78 captures and `INDEX.md`; the verdict is
  written beside them as `VERDICT.md`. Split into build and look: each biome's template
  starts with `saved` `_p4c_{biome}` (the old document's section with `_p4c_old`), the
  build steps save that level (`replace: true`) and the play section is `for:
  "{biome}_*_play_*"`. The levels are kept after the run for look mode, for example
  `phase4c_judgment_set --saved --only "*_2_tier_z8"` (every biome's tier fall at
  zoom 8, half size, no play; about 9 s per saved level against 100 s to build one: the
  one-biome trial took 170 s to build and 21 s to look), and
  `cleanup_levels` removes them when the task is done. Limit a trial to one biome with the
  template's `biomes` field in a scratch copy of the job.
- `jobs/p4d_probe.json`: the ford bar probe (P4d-0, about 55 s to build, 20 s to look): a
  new 150 ft temperate forest map with a straight waist river and a straight ankle stream,
  saved as `_p4d_probe` and played (`saved` loads it in play, since tokens spawn only
  there); `probes/p4d.gd bar` lays a gravel bar across each (crest 0.2 m and 0.15 m under
  the surface), tokens are dropped on both bars and in the river off the bar, `landing`
  logs the rays at each; captured at home with the grid, zoom 8 on the waist bar (plain,
  grid, water hidden), zoom 8 on the ankle bar, and the waist bar rebuilt 0.35 m deep. 6
  captures and `INDEX.md`; the verdict is written beside them as `VERDICT.md`.
- `jobs/arch_look.json`: the stone arch (P4d-1): a new 150 ft temperate forest map with a
  waist river and a deep pond, saved as `_p4d_arch`; through `crossing.gd place` an arch over
  the river at z = 2 with a plank bridge below it for scale and a long arch with a mid-stream
  pier along the pond; captured at home with the grid, zoom 8 on the river arch (plain, grid,
  water hidden), zoom 6 on it (facets, paving scale, coping stones) and zoom 8 on the pier
  arch. 6 captures and `INDEX.md`; the level is kept for look runs.
- `jobs/pol_trees.json`: trees at close zoom (Polish, 2026-10-05; about 95 s to build, 90 s
  to look): new 150 ft temperate forest (a waist river at x = -9) and boreal taiga maps saved
  as `_pol_forest` and `_pol_taiga`, captured from zoom 20 down to 2 and at full authoring
  zoom-out (`f_out*`, with the grid), with the camera moved back (`_back`), the fade off
  (`_nofade`), the scatter hidden, and the near plane where it was before the canopy hold
  (`_old`: home, zoom 20, zoom-out, the river and its grid at zoom 6); an in-run GPU A/B of
  the fade at zoom 6 in a grove and at home, and of the hold at home (`--only f_gpu`); the
  Thin brush's ring; the forest played with tokens in a grove and in the river and a token
  dragged at home (`p_drag_z13`); Deciduous clusters played read-only (`b_*`); the taiga's
  play-zoom window at home with the fade off, its GPU A/B (`t_gpu`), the Thin ring at home,
  zoom 20 and full zoom-out; a new grassland map at home and zoom 20 (`g_*`, not saved). 43
  captures and `INDEX.md`; the levels are kept. `probes/close_zoom.gd play` tunes the
  play-zoom window in-run. The canopy fade is a setting that defaults off (2026-10-24), so
  the job turns it on with a `play` step (`"enabled": true`) after each map is up; without
  that its captures show the wall of leaves the fade removes. `terrain_events.json` does the
  same for its `collapse_4_gm` and `fall_3_nofade` captures. A new job that captures the
  fade must pass `"enabled": true`.
- `jobs/ford_look.json`: the ford (P4d-2): a new 150 ft temperate forest map with a waist
  river, an ankle stream and a deep river, saved as `_p4d_ford` and played (`saved` loads it
  in play: tokens spawn only there); a ford across the river and one across the stream through
  `crossing.gd place` (the deep river takes none: refused), tokens standing on each and one
  wading downstream; captured at home with the grid, zoom 8 on the waist ford (plain, grid,
  water hidden), zoom 8 on the ankle ford and zoom 6 on the waist ford. 6 captures and
  `INDEX.md`; the level is kept for look runs.
- `jobs/phase4d_judgment_set.json`: the phase 4d (arch and ford) judgment set (P4d-4): for
  every palette biome (`expand_biomes`), a new 150 ft map (seed 1234) with a straight waist
  river at x = -7, a straight ankle stream at x = 8 and a deep pond west of the river (its
  stroke 4 m from the river's waterline, since a pond's water reaches about 3 m past its
  stroke), then through the crossing API an arch, a ford and a plank bridge across the river,
  a ford across the stream and a pier arch along the pond, drawn from x = -10 so no line
  starts in another body's water; captured in authoring at home and at zoom 8 on the arch,
  the ford, the ankle ford and the pier arch, saved as `_p4d_{biome}` and played with tokens
  on the arch's deck, in both fords and on the plank deck, grid on (home, zoom 8 on the arch
  and the ford). 64 captures (eight biomes) and `INDEX.md`; the verdict is written beside them
  as `VERDICT.md`. Split into build and look like the 4c set (`saved` `_p4d_{biome}`, the play
  section `for: "{biome}_*_play_*"`); the levels are kept (`cleanup_levels` removes them).
- `jobs/phase5_{valley,hilltop,terraces,lakeshore,gorge}.json` and
  `jobs/phase5_judgment_set.json`: the starting-landform judgment set (P5-4). One job per
  recipe (about a minute per level to build): new 150 ft maps through `new_map` with the
  `landform` key, three or four temperate forest seeds (a wet draw with a crossing, a wet
  draw without, a dry draw; the hill adds the flank spring) and one seed in another biome
  (alpine meadow, boreal taiga, riverside wetland, rocky badlands, grassland meadow), saved
  as `_p5j_<kind>_<biome>_<seed>`; per level home with the grid, home with the water hidden,
  zoom 8 on the stage (`landform.gd look stage`) and on the crossing, the water or the floor
  (`look crossing`; the hill adds `look summit`); then one wet level played with a token on
  the stage and one on or in the water feature (`for: "<level>_play_*"`). The judgment set
  is the union of the five (the driver has no include op, so the blocks are repeated) for
  the final full-size pass (`--full`); a recipe change rebuilds that recipe's job alone. The verdict is
  written beside the captures as `VERDICT.md`. `landform_look.json` is the P5-2 look (the
  `_p5_` levels), `landform_dialog.json` the new-map dialog's Landform row (P5-3).
- `jobs/arch_ford_tools.json`: the Arch and Ford tiles through the real Bridge tool (P4d-3,
  about 60 s to build, 30 s to look): a new 150 ft temperate forest map (seed 1234) with a
  straight waist river at x = -7 and a deep river carved at x = 8 (`water.gd carve`), saved
  as `_p4d_tools`; then in authoring (`bridge_kind` `arch` / `ford`, `gesture`, `input`) the
  Bridge pane with its four tiles, an arch held across the waist river (the live ghost and
  readout) and released, a ford held across the deep river (the red line and "Too deep to
  ford. Fords cross wadeable water." beside the cursor) and released (the toast), a ford
  placed across the waist river, and Ctrl held over the arch ("Remove stone arch"). 8
  captures and `INDEX.md`. The level is kept for look runs (`cleanup_levels` removes it).
- `jobs/p6_probe.json`: water over the ground skirt (P6-0, about 70 s to build, 3.5 minutes
  for the full look run): a new 150 ft temperate forest map with a straight waist river
  carved through the near edge, saved as `_p6_probe` (kept); then `probes/skirt.gd` states
  (the game today, the dipped skirt, a real or simple water ribbon over it, the skirt shader
  transparent, depth-writing or opaque) each at home zoom panned to the edge, with fog, at
  zoom 20 and at zoom 8 on the mouth, and a GPU A/B (`--only edge_gpu`). 53 captures and
  `INDEX.md`; the verdict is written beside them as `VERDICT.md`.
- `jobs/p6_look.json`: rivers past the map edge (P6-1, build and look). `_p6_look_forest`: a
  new 150 ft temperate forest map with a waist river drawn on past the near edge with a bend
  and an ankle stream drawn to stop at the right edge (a derived continuation);
  `_p6_look_valley`: a Valley landform map (seed 2) whose recipe river ends at both edges.
  Each map zoomed out (`*_overview`, with and without fog), then per exit home zoom panned
  to it, zoom 20 and zoom 8 on the mouth, each with fog off and on; diagnostics with the
  ribbon, the channel patch or the rest of the skirt hidden (`forest_e0_z8_no*`); the valley
  under two sky presets (`valley_outdoor_*`). `_p6_look_ponds` (P6-4): a new 150 ft forest
  map (seed 4321) with a wide deep pond painted against the near edge and a narrow waist pond
  touching the right edge (`look` exits 0, the narrow one, and 1), the same views as the
  rivers' plus `ponds_e*_z8_noribbon` and `ponds_sunset_*` (outdoor_sunset). `probes/p6.gd`
  (`info`, `look` at an exit, `preset`, `show`) does the exits' parts.
- `jobs/p6_perf_build.json`, `jobs/p6_perf_play.json` and `jobs/p6_perf_band.json`: the phase
  6 pinned performance pass (`PERFORMANCE.md` "Phase 6 (rivers past the map edge): pinned
  performance pass"), with `probes/p6_perf.gd`. Build (about 85 s): a 150 ft forest map with a
  waist river drawn past the near edge and an ankle stream past the right edge, saved as
  `_p6_perf_exits` (two exits), `exits_build` and `apply_bench` timed, then `record` windows
  and `water_timing` around a river stopping short of the left edge and its erase and one drawn
  past it and its erase; the same rivers stopping short of the edges saved as `_p6_perf_short`.
  Play (about 5 minutes; run with the pinned `override.cfg`, which it deletes): warm loads of
  both levels interleaved with `mem`, `exits_build` on each, `backdrop_bench`, then GPU windows
  with the skirt opaque and transparent (`shader`, from `user://p6_old_skirt.zip`: `git archive
  --format=zip --output=<that path> 7bde99a shaders/authored_ground.gdshaderinc
  shaders/authored_ground_skirt.gdshader`) and hidden at home, zoom 20 on an exit and zoom 20 on
  the plain left edge, the patch and ribbon shown and hidden, `SkirtBackdrop` on and off, and
  the skirt A/B at full authoring zoom-out. Band (about 2 minutes, pinned too): the probe's band
  variant (the patch opaque, the rest of the ring transparent) against the opaque skirt at the
  same views. The levels are kept (`cleanup_levels.json` deletes them). P6-4: the build job
  (now about 125 s) also saves `_p6_perf_ponds` (`_p6_perf_exits`'s rivers and a wide pond
  painted to the near edge, its stroke in a `record` window); `jobs/p6_perf_ponds_play.json`
  (about 2.5 minutes, the pinned `override.cfg`, which it deletes) times warm loads of it
  against `_p6_perf_exits` and GPU windows at zoom 20 on the pond's edge on both maps, then the
  pond's water shown and hidden and the skirt hidden.
- `jobs/cleanup_levels.json`: `water.gd cleanup` alone (a few seconds): deletes every
  `_p43_`, `_p44_`, `_p45_`, `_p4b_`, `_p4c_`, `_p4d_`, `_p5_`, `_p5j_` and `_p6_` level under
  `user://levels/`, the
  saved levels of the build / look jobs included. Run it when a task's look iterations are
  done.
- `jobs/authparity_look.json`: authoring parity (2026-10-09, about 35 s; `--saved` loads the
  level in play for the two play captures): a new 300 ft grassland meadow saved as
  `_authparity_token` with one avatar token (`authparity.gd save`); reopened in authoring
  (`auth_token`); a 5 m Raise under it, which authoring sets the token on (`auth_raised`);
  saved again with the token at its old height, buried; then played: the load sets it down on
  the raised ground (`play_token`) and full zoom-out shows the whole map with its shadows
  (`play_whole`, MapViewFit). `authparity.gd report` logs each token's base against the
  ground, the zoom limit and the sun's shadow distance. `jobs/authparity_cleanup.json`
  deletes the level.
- `jobs/biglf_look.json` and `jobs/biglf_base.json`: starting landforms on big and long maps
  (LandformGrowth, 2026-10-09; build and look). `biglf_look`: every landform at seeds 1-6 at
  320 ft and 320 x 160 ft (60 new temperate forest maps through `landform.gd new` with a
  `spec` such as `valley_3_320x160`), each saved as `_biglf_<spec>` (`landform.gd save`) and
  captured in authoring at full zoom-out (the whole map), then tiled six seeds to a sheet
  (`probes/contact_sheet.gd`, `sheet_<landform>_<size>.png`). `biglf_base`: the sizes without
  the big-map extras (greened, edged and set like the big ones since round 3), seeds 1-6 at
  250 ft and 200 ft (60 maps, `sheet_<landform>_250` and `_200`), plus two grassland meadow
  maps for the map edge (`_biglf_grass_<spec>`: a flat 300 ft one and a 200 ft hilltop,
  `sheet_grass_edge`: the cover's edge feather, no accent patch on the rim and the skirt
  without any). Build runs with `--full` took 766 s (`biglf_look`) and 620 s
  (`biglf_base`); `--saved` reloads the levels for a look-only run (`--full` for the
  verdict). `jobs/biglf_cleanup.json` (`landform.gd cleanup`) deletes every `_biglf_` level.
- `jobs/grid_ground.json`: the grid on Blender maps' ground (P3-3c, about 50 s):
  `deciduous_clusters`, `river` and the built-in Oak's lab in play with G, the measure
  tool and a token drag's auto-show, the load's grid ground fit and a sampling survey
  logged for each; then `river` opened for dressing with G. 11 captures and `INDEX.md`.
- `jobs/avatar_kit_look.json`: avatar figures from figurine's kit (AvatarKit, about 60 s to
  build, 50 s to look plus 70 s of perf): a new 150 ft temperate forest map with a placed
  oak, saved as `_avatarkit_forest` and played; `probes/avatar_kit.gd` stands figurine's
  three judging recipes in a clearing (the second in the kit's long-sleeved top, the third
  in its witch hat, since figurine card B2a) and one figure under the oak (its shade ray
  meets the crown). Captures at home, close (3.5 m) and closest (2 m), under the oak, hidden from
  players (dither), the outdoor_sunset, outdoor_night and dungeon_dark presets (dungeon also
  with the sun hidden), and an A/B of the detail textures without AvatarKit's mipmaps; then
  GPU and CPU frame times with 0, 8 and 30 figures at home and zoom 20 (`for: "perf"`).
  `avatar_kit.gd cleanup` deletes the `_avatarkit_` level.
- `jobs/avatar_lighting_look.json`: avatar figure lighting (the world-lighting card, about
  60 s to build, 70 s to look): a new 150 ft temperate forest map with a placed oak, saved
  as `_avatarkit_light` and played; three figures in the sunny clearing, one under the oak,
  one in sun beside it and five across the oak's shade. For each look set (`variant`
  `before` and `after`): home, close on the clearing, zoom 5 under the oak, zoom 6 across
  the shade (`*_dapple`), sunset home and close, night home and dungeon (sun hidden) close.
  `jobs/avatar_cleanup.json` deletes the level.
- `jobs/avatar_token_look.json`: avatar tokens (the avatar token card, about 40 s to build,
  20 s to look): a new 150 ft temperate forest map with a placed oak, a waist-deep and a
  deep pond, saved as `_avatartoken_forest` and played; `probes/avatar_token.gd` spawns
  preset avatars as real board tokens (`LevelPlayController.spawn_avatar`): one under the
  oak's crown, one selected in sun and turned 30 degrees, one dropped into each pond. The
  scatter around the oak differs between builds, so when none of the listed sunny points is
  in sun `pair` searches rings around the shaded token (toward the screen's sides) for one,
  and the camera steps find their tokens by name (`look` `name` / `names`, with the pond's
  centre as `at` should a token be missing) rather than by spawn order.
  Captures at home, close (4.5 m) on the pair, the pair with the sunny one hidden from
  players, and zoom 5 on each pond; `report` logs capsules, shade, the submerged cue and
  the occlusion fade's entries; `timing` (`for: "timing"`) logs spawn and shade-ray medians
  with and without `AvatarShadeCache`. `avatar_token.gd cleanup` deletes the level.
  `jobs/avatar_token_profile.json` (about 7 s, from the title screen) runs `profile` twice:
  build, capsule and token creation medians and `set_recipe` per change type (repeated and
  never-seen values).
- `jobs/avatar_builder_look.json`: the avatar builder (the builder polish card, about 35 s
  to build, 30 s to look): a new 100 ft bare-ground map saved as `_avatartoken_builder` and
  played; `probes/avatar_builder.gd` resizes the window to 1438x1221, opens the builder on
  a preset and captures the Pose, Face (the zoomed portrait), Colours, Parts and Shape (the
  proportion sliders, the five body attributes among them) panes, `report`
  logs the panel, preview and pane sizes, the preview's measured bounds and view and the
  stance tiles, `timing` (`for: "builder_timing"`) logs preview and face-tile repaint
  medians; then the builder at 1280x720, and the same recipe as a board token at close
  zoom, turned to the camera, for the lighting comparison. `jobs/avatar_cleanup.json`
  deletes the level (and `_avatarkit_light`).
- `jobs/avatar_library_look.json`: the avatar library (about 37 s): at 1438x1221, the
  title screen with Avatars, the roster on an empty test library and on five seeded
  presets, the builder opened from the roster (Pose and Face panes), then a bare 100 ft
  map saved as `_avatartoken_library` and played with the Add Token browser's Avatar tab
  and a saved avatar placed by its card. It deletes its test library and level at the end;
  the player's `user://avatars/` is never read or written.
- `jobs/ui_primitives_look.json`: the UI primitive fixes (card U1, about 20 s): Settings over
  the title as first opened (the rail underline), on Graphics with its Advanced `Foldout`
  closed and open (the chevron), then a bare 100 ft map saved as `_u1_ui_hud` and played
  (the input hint bar). `probes/ui_primitives.gd report` logs the underline against the
  selected item's centre, the chevron's rect against its title and the hint bar's rect
  against the window. The job deletes `_u1_ui_hud` at the end (`cleanup`).
- `jobs/play_together.json`: the title's Play together card and Resume (50 captures, about 60
  s), over a staged library and staged saved sessions (`probes/ui_play_together.gd`; nothing
  is hosted, joined or written), at 1280x720 and 1920x1080: rest, both hovers and keyboard
  focus; Host's press and flood as a filmstrip held at 0, 50, 70 (`card_press`, the squash's
  deepest), 100 and 200 ms, and Join in place opening at 50, 120, 200 and 300 ms; Join with
  the field empty (its placeholder) and with a code, connecting, a bad code and the version
  gate's failure in the slot under the card; Resume's older-sessions menu open; Host stepped
  back under Settings; dusk rest, hover and error; and the GM's room after Resume, the session
  Resume names (Old Mill and 2 more maps), with Old Mill and with the missing Fen Crossing
  selected (`ui_room.gd host_room` with `notes` and `missing`). After rest and each hover the
  faces' words are hidden for a frame and `contrast` logs paper against the lightest wash
  pixel under them (the bar is 4.5:1; rest reads 4.97 and 5.60). `crop` saves the card up
  close at the window's pixels to `play_together/crops/` beside the captures.
- `jobs/library.json`: the title as the library (16 captures, about 35 s), at 1280x720 and
  1920x1080 (`probes/ui_library.gd`): a staged library of seven maps of every source (one
  Bundled, so its heading shows), Willow Green selected with its detail strip in the morning
  and its "..." menu open (Reload from Blender staged), Violet Fen selected at dusk, New map's
  Advanced open on a custom 300 x 120 ft map (the big-map line) and on 400 ft (refused,
  Generate waits), the import check on a map.glb whose ground floats 1.5 m (one warning), the
  Replace prompt for a smaller map dropped on a dressed level (Keep dressing drops one prop),
  and the empty library. The library and each strip's size are staged; the import files and
  the dressed level live under `user://_library_title_probe/` with the levels folder pointed
  there, and `cleanup` deletes it.
- `jobs/ui_tour.json`: the UI tour (106 captures; about 235 s at half size and 240 s with
  `--full`, timed on `--only` runs, which still run every step but the skipped captures),
  the capture set the `tt-sim-ui-critic` agent judges (`docs/UI_TASTE.md`). It saves a new
  100 ft temperate forest map as `_ui_tour_room` (shown as Mossy Hollow) with a real
  thumbnail of it (`ui_room.gd thumbnail`), then at 1280x720
  and 1920x1080 window sizes (`ui_primitives.gd window`; capture names start with the size):
  the title, keyboard focus on a quiet paper button and on the selected level card, Settings
  on each of its six sections, the new-map dialog, then the session screens, staged by
  `probes/ui_room.gd` with no network (nothing is hosted or joined): the "Opening a
  room..." wait over the title with its step caption in Cancel's band (`opening_room`) and
  with its Cancel offered in that band (`opening_room_cancel`), a map load staged mid-load
  over the title (`map_load_title`, Root's loading overlay on the backdrop sky; nothing is
  loaded), the room (RoomPanel, probes/ui_room.gd from a staged session summary) as the GM
  sees it with four players and a shelf of three maps, Mossy Hollow selected (`room_host`, its thumbnail
  large; the two sample maps paint their placeholders) and End session's confirmation over
  it (`room_end_confirm`), with no map at all (`room_no_map`: a placeholder and Add a map)
  and the Add a map picker over it (`room_add_map`), with a shelf and nothing selected
  (`room_shelf_none`), with a 24-character GM name and a long map name selected
  (`room_long_names`), the join screen as the title's Join Game opens it (`join`, Root's real
  entry point), and the room as a player sees it with Old Mill selected (`room_player`), with
  Fen Crossing, which they do not have, selected (`room_player_lacks`), just joined with
  nothing selected (`room_player_none`) and with an empty shelf (`room_player_empty`); in
  play, the room drawer as the GM sees it with another map selected and Move the table to it
  under the shelf (`room_drawer`), as a player sees it on opening (`room_drawer_player`) and
  with the long GM and map names, the long map selected (`room_drawer_long`); then authoring
  with the tool drawer on Biome and focus on its picked tile (the probe lets a drawer tile
  take focus) and the drawer on Sculpt and Water (`authoring_sculpt`, `authoring_water`),
  then the real map load of the test map caught about 0.4 s after Play
  (`map_load_real`), and in play the same staged map load over the live table (`map_load_table`), the Visuals drawer
  on Sun with nothing changed (no foot) and the same with an unsaved change
  (`play_drawer_unsaved`: the time of day moved 45 minutes, the lake dot, the Sun rail item's
  tooltip shown by a synthetic pointer event, the foot with Revert look and Save look the one
  Primary; the probe then presses Revert look), focus on a quiet glass button, the pause menu, the
  pause menu as the host sees it (`pause_host`: the host-only Move everyone to the room row in
  its own group between separators, shown on a solo pause; it asks nothing, so it is not
  pressed), the pause menu's Return to title danger confirmation with an unsaved token move
  staged, Save first and Cancel focused (`danger`; both confirmations stand on the pause
  menu's scrim in place of its sheet), one toast
  of each kind, the toast a removed token shows with its Undo (`undo_toast`), the Add token
  browser and the avatar builder, and at dusk (19:00 through the Sun pane) the Visuals
  drawer, the browser and the pause menu again. Then the Interface size passes
  (`probes/ui_size.gd`): at 1366x768 (Auto 1.35, an 800 px canvas) and on a 1920x1080 window
  at a fixed 150% (names start `1920x1080@150`, a 1280x720 canvas) the title, Settings on
  Graphics, the new-map dialog as it opens and scrolled to its end, and in play the Visuals
  drawer on Sun and the play hint row between the room drawer and Add token
  (`hints_room_drawer`, wrapping at 150%); at 1280x720 (Auto 1.40) the Interface size
  dropdown open, the Visuals drawer on each pane after Sun (`1280x720_visuals_sky` to
  `_world`), a staged two-segment measure line over the board with the measure tool's
  own keys leading the hint bar (`1280x720_measure`) and the bar just after the tool ends
  (`1280x720_measure_done`). Last, one probe capture of the title at 1720x720 (ultrawide). The
  captures and `INDEX.md`; the level is deleted at the end. Half size makes the 720p captures
  640x360, smaller than any player sees: judge 720p legibility on a `--full` run.
- `jobs/import_thumb.json`: the map library's import (the level core card, about 35 s, no
  map open): `probes/import_thumb.gd check` logs `GlbCheck` on terrain-paint's
  `deciduous_clusters`, `sandyclearing` and `terrain` exports and the built-in Oak's Lab
  (MB, footprint, floor and top, extras, warning codes, the check's time); then imports
  `deciduous_clusters` as `_test_library_thumb` (`MapImport.import_glb`, the offscreen
  thumbnail a headless run cannot draw), `report` copies the saved 320x180 thumbnail to
  `import_thumb.png` in the output folder, and `cleanup` deletes the level and its source
  index entry (and the index file when that leaves it empty).
- `jobs/tool_panes.json`: the tool rail and panes (the tool registry card, about 20 s): a
  new 100 ft temperate forest map (seed 1234, never saved) in authoring, the drawer opened
  from the rail on each registered tool's pane in rail order (`pane_<id>`), the rail with
  the drawer closed (`rail_closed`), then F1 help scrolled to the tools' Map building rows
  (`help_tools`) and to its end (`help_building`). Run it before and after a change to
  `ToolRegistry`, a `ToolDescriptor` or `AuthoringPanel` and compare the drawer's pixels: the
  scene behind the glass moves (wind, water), so judge the pane and rail rects, where an
  unchanged drawer differs by under 32 in every pixel. No level to clean up.
- `jobs/events_pane.json`: the GM's Events pane in play (cards gm-events and gm-events-2a,
  about 50 s, 15 captures): a new 100 ft temperate forest map (seed 1234) saved as
  `_gm_events_table` and played; the Visuals drawer open on Events at 1280x720 and 1920x1080
  (`*_events_open`); at 1280x720 the Biome (first biome picked, the ring hovering under the
  drawer's edge), Paint, Water and Bridge panes (`events_biome`, `events_paint`,
  `events_water`, `events_bridge`); a live Sculpt raise held on the board, the drawer stepped
  aside at the press (`events_sculpt`), released (`events_raised`), the brush put away
  (`events_put_away`), undone through `PlayEvents.undo` (`events_undone`); a 9 m Clear held
  mid-sweep with the canopy open over it (`events_clearing`) and released with its undo toast
  (`events_cleared`); at 1920x1080 Thin held where the drawer stood (`events_brush_out`); the
  pane over outdoor_night with the sun off, the darkest board (`events_night`); and a staged
  player's view (`events_player`: the Visuals drawer concealed, the GM's HUD buttons hidden
  and the GM's toasts dismissed). Its own probe (`probes/events_pane.gd`: save, window, open,
  arm, hover, press, move, release, put_away, undo, redo, player, dismiss, cleanup; the night
  step uses `p6.gd preset` and `avatar_kit.gd sun`) deletes `_gm_events_table` at the end.
- `jobs/terrain_events.json`: the GM's presets with spectacle (card gm-events-2b; about 49 s
  with `--saved --full`, 20 captures). The build phase makes a new 150 ft temperate forest map
  (seed 1234) with a curved waist river, a plank bridge and stepping stones downstream
  (`crossing.gd place`), saves it as
  `_gm_events_spectacle` (`events_pane.gd save`) and plays it; `--saved` loads it in play.
  Its probe (`probes/terrain_events.gd`: look, fire, advance, free, abort, arm, hover,
  report, and `burn {view}`, card F4b-5's debug views of the fire's scorch noise: 1 the specks,
  smoulder and band breaks as RGB, 2 the metres behind the front as bands, the hottest patches
  and the ash, 0 back) fires each event on the GM's side with the TerrainEvents clock held, so the
  filmstrips step it to
  exact times: the bridge at zoom 11 with the camera turned 56 deg (`look` `yaw`) to look west
  up the river, so no crown stands in front of it (`collapse_0_before`, then 0.3, 0.7, 1.1,
  1.6 and 2.1 s: `collapse_1_shudder` to `collapse_5_settle`; at 1.6 s also `collapse_4_gm`,
  the play angle with the bridge at the screen centre under the canopy fade, as a GM sees it)
  and, the clock freed, the river open with the toast and its Undo (`collapse_6_after`).
  `look` sets the zoom at once and centres the point exactly (an eased zoom drifted toward the
  cursor and left the bridge 2 m off centre). Then the densest stand within 18 m of the
  bridge at zoom 16 (`fall_0_before`, then 0.45, 0.95, 1.45, 1.95 and 2.45 s: `fall_1_tip` to
  `fall_5_clear`, and `fall_6_after`); at 1.45 s also `fall_3_nofade`, the canopy fade off (`close_zoom.gd
  fade`), an A/B in which the fallen crowns must match `fall_3_down`. The fire (card
  fire-look) fires 7 m over the same stand with the view raised 4 m (`look` `lift`, so the
  crowns are in frame): `fire_0_before`, then 0.5, 1.2, 1.9, 2.6, 3.4 and 4.2 s (`fire_1_catch`
  to `fire_6_change`), tiled into `sheet_fire.png` (`contact_sheet.gd`), and the after state
  with its toast (`fire_7_after`), then undone. `abort` stops a playing event without its
  change, so a look iteration can fire again on the same stand in one run. The pane captures
  (cards presets-pane-fix, events-followup; 29 captures in all, about 72 s with `--saved
  --full`): with no bridge left, `pane_nobridge` (Drop bridge disabled with its caption;
  `events_pane.gd tile` logs its tooltip); still before any undo, at 1280x720 over the felled
  stand, the GM's two Undo toasts in their events' icons, stacked with aligned edges
  (`pane_toasts_720`, `events_pane.gd toasts`), and a player's view with the two notice chips
  and no Undo (`pane_player_720`, `events_pane.gd player` with `kinds`, then `gm` to restore
  the drawer and buttons); both events then undone through `events_pane.gd undo` (Ctrl+Z's
  path: the trees and the bridge back, no effect played), the camera's near plane logged
  (`eval`, -61.8 m at zoom 11 at either yaw: pulled back over the canopies, so it cuts no
  tree); at 1280x720 and 1920x1080 the pane fresh, with Topple trees armed at 6 m over the
  stand (the ground marks at the falling trees' feet, chip and keys) and put away again
  (`{size}_pane_fresh`, `_topple`, `_putaway`); Drop bridge over the bridge in daylight (the
  chalk inner edge, the chip under the outline) and over the build's stepping stones at map
  x 14 (the chalk_soft ring; `pane_drop_bridge`, `pane_drop_stones`, `events_pane.gd
  hover_crossing`); and both cursors at dusk (`pane_dusk_topple`, `pane_dusk_drop`,
  `ui_primitives.gd dusk`). The level is
  kept for look runs; `jobs/gm_events_cleanup.json` (`events_pane.gd cleanup` alone, a few
  seconds) deletes every `_gm_events_` level when the task is done.
- `jobs/ground_parity.json`: the ground ship's parity check (card 3c, 2026-10-15): round 20's
  final views (treecube `docs/looks/ground20/run20.py`, `job_final.json`) drawn by the game's
  own code from a palette carrying round 20's data (treecube `out/palette_parity`,
  scratch-installed, never committed), with no look probe: grassland seed 1234 at home, zoom
  26, the grass alone and with round 20's road (`dirt_road_packed_r5`, radius 1.2), grassland
  seed 2, savanna at home and zoom 26, birch woodland at home; canopy fade off
  (`close_zoom.gd fade`), cursor hidden and mouse centred as round 20. Its probe
  (`probes/ground_parity.gd`) sets no look: `nocursor`, `only` / `all` (scatter visibility),
  `freeze` / `thaw` (the shader clock held at TIME under 1e-6 through a tiny time rollover,
  so swaying blades and the lo-fi grain take the same pose in every run), `save` / `cleanup`
  (`_gship3c_` levels) and `report`. Every view is captured frozen and again with the
  scatter hidden (`<view>_bare`), so a diff can tell blades from ground; `grassland_again`
  repeats the home view after 1 s of wind (equal when the freeze holds); grassland is saved
  as `_gship3c_grassland`, reopened (`dress`) and captured as `reload_grassland` (the same
  masses and bake when the mass anchors survive; it drew the ground and grass 3-6 levels
  darker until `reopen_dark` found and fixed why), and the job
  deletes the level at its end (`jobs/ground_parity_cleanup.json` does it alone after a
  failed run). About 120 s with `--full`. `ground_parity.gd uniforms` (`ref`: a round 20 job,
  `index`: its `field` step) logs the bake's and the grass's uniforms that differ from round
  20's, the ground's slot vectors and tables, and can save the bake texture.
  `probes/parity_diff.gd` (standalone, a manifest of pairs) prints mean colour, the darkest
  and brightest tenth, the pixels over 2/255 and whether they sit on scatter or ground, and
  writes the diff images.
- `jobs/ground_install.json` and `jobs/ground_install_levels.json`: the ground ship's install
  captures (card 4, 2026-10-15) on the committed ship palette, written straight into treecube
  `out/looks/ground_ship/install/`. `ground_install` imports `D:/dev/tabletop/terrain-paint/
  deciduous_clusters.glb` as `_gship4_glb_` first, then takes ground_parity's views with the
  clean ids (grassland home, zoom 26 and the road on `dirt_road_packed`, seed 2, birch) and the
  zoned biomes seen at home and zoom 26 (savanna, wetland, alpine meadow, temperate forest:
  `{value}` and `{value}_z26`, named by biome id), a grassland with a savanna band painted
  down the middle (`twobiome`, `twobiome_z26`), and a fire in play on a saved grassland
  (`_gship4_fire_`: `fire_before`, `fire_after`, through `probes/terrain_events.gd`). Then a
  job on main's checkout saves a grassland at seed 1234 through main's own `events_pane.gd`
  (`_gm_events_gship4_old`), reopens it and captures it and `_gship4_glb_`;
  `ground_install_levels` adopts that level as `_gship4_old_` (`ground_parity.gd adopt`),
  reopens it here with `rows` (open, saved and live rows and a grass MD5) and `report`,
  captures it and `_gship4_glb_` again, and deletes every `_gship4_` level (`cleanup`, which
  also takes `_gm_events_gship4_old` when `adopt` never ran). Run with `--full`.
- `jobs/reopen_dark.json`: a fresh build against the same map saved and reopened (card
  reopen-dark, 2026-10-15). Grassland seed 1234 at home: `fresh` and `fresh_bare`, then
  `probes/render_state.gd dump` writes the render state to `user://render_jobs/reopen_dark/
  fresh.json` (whatever `--out` says) with the look bake beside it (`.bake_rgb.png`,
  `.bake_a.png`); `fresh_reprobe` after `reprobe` made the reflection probe capture the grown
  scatter; saved as `_reopen_grassland` (`render_state.gd save`), reopened (`dress`):
  `reopen`, `reopen_bare`, the same dump as `reopen.json`, and `reopen_bareprobe` after the
  probe captured the map with its scatter hidden; `render_state.gd diff` writes every key
  whose text differs to `diff.txt`. Then a savanna seed 1234 pair (`savanna_fresh`,
  `savanna_reopen`, `_reopen_savanna`) and `render_state.gd cleanup`, which deletes every
  `_reopen_` level. About 35 s at half size, 65 s with `--full`; compare the pairs with
  `probes/parity_diff.gd`. The dump (environment, lights, camera, viewports, reflection
  probe, global shader parameters, the terrain's chunks, skirt and bake, the scatter per
  species and per node) is the tool for any "the same map draws differently" bug: diff first,
  then bisect by swapping one differing piece.
- `jobs/ground_timing_build.json`, `jobs/ground_timing_play.json` and
  `jobs/ground_timing_cleanup.json`: the ground ship's timing card (2026-10-15,
  `PERFORMANCE.md` "Ground look and grass masses (ground ship, 2026-10-15)"), with
  `probes/ground_timing.gd`. Each runs on main before the ship too (pass the job's absolute path
  with `--path` at that checkout, the probe copied in): the probe names its levels
  `_timing_head_` or `_timing_base_` by whether `GroundLookBake` exists and skips the look
  configurations on the base. Build (about 90 s): new grassland and savanna maps at seed 1234
  timed (`perf.gd author`) and saved, two more opens of each, then four 3 m dabs on the
  grassland level (badlands, then grassland back, twice) in `record` windows with a
  `regen_watch`. Play (about 11 minutes on the ship; run with the pinned `override.cfg`, which
  it deletes): the levels played G, S, S, G after a warm-up load of each; per visit `bake_info`,
  then a `sweep` at home and at zoom 26 (13 configurations: the look on, gated off, without rims,
  plain accent shapes, the tuft gate off, masses hidden, scatter hidden, the half-built
  `ground_std` reference, and the pre-ship ground and foliage includes swapped in from the
  checkout at the sweep's `base` path), `bake_gpu` at the real size and at 2048 px, a `rebake`
  in a `record` window, `mem` before and after `bake_free`; last, two salted cold compiles of
  the bake shader. Until the optimization card `perf.gd ground_std` threw at `tile_m` on its
  first call (the uniform was gone) and left a half-built, untextured StandardMaterial3D that
  later calls applied: those runs' first `std` window was not the reference. It now builds the
  base surface from layer 0 of the layer arrays, whole, on its first call. Cleanup deletes every
  `_timing_` level.
- `jobs/ground_opt_build.json`, `jobs/ground_opt_parity.json`, `jobs/ground_opt_parity_bare.json`
  and `jobs/ground_opt_timing.json`: the ground optimization card (2026-10-15, `PERFORMANCE.md`
  "Ground look and grass masses", "Optimizations"). Build (about 55 s): `_timing_head_` grassland,
  road (grassland plus round 20's road), savanna, taiga and mixed (taiga with a grassland stroke)
  levels. Parity: each level opened, each view captured at full size with the clock frozen, with
  the res:// ground include and then with the include at the `base` checkout swapped in through
  `Shader.code` (and again with the new one, the control), then `probes/png_parity.gd -- <folder>
  _new _old` diffs the pairs. Compare captures of one run only: two runs of the same levels differ
  in most views, and with the scatter shown two captures of one code differ in tens of scattered
  pixels, so exactness is read off the scatter-hidden `_sub` captures (the `_bare` job). Timing:
  two 3 m dabs on the grassland level (badlands, then grassland back) with the stamp materials
  kept, then the level reopened and the same two with them dropped before each stroke
  (`stamps_fresh`, the old behaviour), each in a `record` window with the bake's MD5 after it;
  then grassland, taiga, grassland, taiga played, a `sweep` at home and zoom 26 of the new and the
  base include, with and without scatter, and the `ground_std` reference.
- `jobs/firefeat_build.json`, `jobs/firefeat_look.json` and `jobs/firefeat_cleanup.json`:
  persistent ground fire's look (fire cards F3, F4a and the production port;
  `probes/fire.gd`; `docs/systems/fire.md`). Build (about 100 s): a new 200 ft temperate forest
  (seed 1234), fire laid with the real Fire tool (three `flames` passes of radius 4 across the
  map and a shorter fourth, then a curved `blaze` line of radius 2 across the view; south of
  them an author-laid fire, a scrubbed blob and a curving line), saved as `_firefeat_look`
  (267 fires shown, the book ready). Look (rewritten by card fire-prod-c3; card F4b-1's look,
  `_new` beside `_old` sheets with the smoke's colour probes and the lights' falloff diffs, is in
  its history up to f4ac41b9): that level with the clock held for each capture (`fire_ab.gd
  hold`), under the probe's sun keys (`day` the level's own sky at 14:00, `night` outdoor_night
  at 23:00, `sunset` outdoor_sunset at 19:00): `day_z8` and `night_z8` (zoom 8 over the blaze),
  `day_home`, `night_home` and `sunset_z20`; then night motion bursts at z8 and home
  (`motion_<view>_0` to `_23`: the probe's `scale` 0.25 and `burst` of 24 grabs 1/24 s apart,
  half a drawing apart at 12 drawings a second, their engine times in
  `motion_<view>_times.txt`; a `capture` step takes about 0.4 s, too slow for a strip). The
  sheets put production beside round 6 of the reference fit ("production | r6"): `sheet_close`
  (day and night z8), `sheet_far` (day and night home, sunset z20), `sheet_zoom` (the middle of
  the z8 views), `sheet_motion_z8` and `sheet_motion_home` (production only). The r6 frames are
  the spike's `render_jobs/ref_fit_r6_sim/<view>_sim.png` (branch spike-flipbook at de7f3d16, its
  user dir `TTSim_spike_flipbook`), copied once by hand into `user://render_jobs/fire_r6_ref/`
  (no absolute path is committed; a missing one leaves its tile blank). Since card
  fire-prod-c5b the glow is the game's own (`EnvironmentGlow`, round 6's), so the night aura and
  day bloom compare too. `sheet_pdiff` (`fire_ab.gd` `load` and `pdiff`): r6 | production | the
  difference x4 per view, the mean and RMS in the log; on 2026-10-18 means 10.9-11.9 (RMS
  30-34) at z8 and home and 7.6 (20.0) at sunset z20, about production's own frame against
  itself 0.24 s later (night z8 burst frames 0 and 23: 10.2, RMS 31.9), the difference on the
  flame shapes (the per-fire seed re-rolls each drawing), the trees' sway and the smoke's lobes.
  `pdiff`'s `width` takes both frames down first (a low-pass compare). Card fire-prod-c5c added
  the burning map under the `hell` and `ethereal` presets (`hell_home`, `hell_z8`,
  `ethereal_home`, `ethereal_z8`), each with a `_oldglow` twin on the same held frame (`glow.gd
  shot` with the old glow variant), in `sheet_presets` (production left, old glow right; no r6
  frame exists for those presets); `--only "hell_*,ethereal_*"` runs just those.
  It writes to `render_jobs/firefeat_look`. The probe's `info` logs the fires shown and planned,
  the fire book's state and the ground bake's bytes and frame (8,128,512 bytes over 63 m on this
  level); `scale` sets `Engine.time_scale` (the shaders' clock and a burst's spacing follow it).
  Cleanup deletes every `_firefeat_` level.
- `jobs/firefeat_look_mobile.json`: night_home on `_firefeat_look` with the clock held, under the
  renderer the run starts with (card fire-prod-c5b, about 25 s). Run it twice: with
  `--rendering-method mobile` (writes `render_jobs/firefeat_look_mobile`) and with
  `--rendering-method gl_compatibility --out render_jobs/firefeat_look_compat`; `glow.gd report`
  logs the renderer and the glow it got (Mobile: intensity 1.0, bloom 0.015 at night). Each run
  writes `sheet_renderers` into `firefeat_look_mobile`: Forward+ (firefeat_look's) | r6, then
  Mobile | Compatibility, complete after both runs. On 2026-10-18 Mobile matched Forward+ (the
  aura a little softer); Compatibility drew no flames, only the smoke and the lights' pools, on a
  pale grey ground (the authored ground shader fails there on `textureGather`).
- `jobs/firefeat_glow.json`: the game's glow on a map with no fire (card fire-prod-c5b;
  `probes/glow.gd`; about 90 s). Build: a 150 m temperate forest (seed 1234) with a river and a
  pond, saved as `_firefeat_glow`; look: `<sky>_<home|z8>` under the fire
  probe's sun keys `day` (the level's own environment), `sunset`, `night`, `hell` and `ethereal`,
  then `glow0_home` and `glow2_home` (the Color pane's Glow slider at 0 and 2 through
  `glow.gd env`). The sheets put an old set beside the new: run once with `--out
  render_jobs/firefeat_glow_old` before a glow change, then again with no flag after;
  `sheet_<sky>` (home over z8) and `sheet_slider` (0, the preset's value, 2), old left.
  `stats.txt` (`glow.gd stats`, card fire-prod-c5c): per view old | new, the mean luma, mean
  saturation, contrast (the luma's standard deviation) and the luma's 50th and 98th percentiles,
  and new - old (the old set's full-size frames taken down to the run's size), then the slider's
  lift over no glow. Its last step, `glow.gd cleanup {folder: "_firefeat_glow"}`, deletes only
  that level (`fire.gd cleanup` would take `_firefeat_look` too), so every run builds it afresh
  (`--saved` finds no level). For a calibration, `glow.gd shot` with `specs` captures named glow
  variants ("+key=value" suffixes on `new` or `old`, `glow.gd variant`) on one frame, and `stats`
  compares them; card C5c's scratch jobs did that on a kept `_firefeat_glow` with `--saved`.
- `jobs/firefeat_line.json`: the Fire tool's Line shape (cards F5, F5b, F5c; about 220 s). Run once
  per window size (`expand` over 1920x1080 and 1280x720, the critic's size; names start with
  the size): a 200 ft temperate forest (seed 1234) with a meadow painted over its east half
  (the strokes leave the brush at 9 m, flow 2); the Fire tool picked from the rail
  (`fire_pane`: the help and the Area ring at 9 m), a real Tab key (`input` op, `"key":
  "tab"`) switches it to Line (`pane_after_tab`: the Line tile follows, the Line ring at its
  band's width), then a Blaze line at radius 2.5 is drawn with real input (`gesture`) from the
  meadow into the forest: `line_drag` mid-drag (the ember ribbon, zoom 22), `laid_day_z22`
  (after `fire.gd profile`, which logs the mask along and across the laid line against
  `FireBrush.line_reach`), a Ctrl line held over part of it at zoom 8 with two put-out
  interiors on the same drag (`erase_drag_a`, the ash plum-grey; `erase_drag_b`, the lake: an
  `eval` set `FireBrush.put_out_tint`, then a redraw; since card F5h the put-out has no
  interior and that property is gone, so the two frames match), and a second line held at night
  (`line_drag_night`) and under the sunset preset (`line_drag_dusk`), each dropped with Esc;
  `sheet_1920` and `sheet_720` (the six drags and lays), and `sheet_water` (the Water pane and
  river drag before | after from `firefeat_line_pane` run with `--out
  render_jobs/firefeat_line/water_before` and `water_after`). The 720p gesture lands off the job's
  points (the 3D view renders at 1371x771 there), so read its profile's offsets loosely. It
  saves no level, so it leaves none.
- `jobs/firefeat_line_pane.json`: the Water and Fire panes and a Water river held mid-drag
  (`river_drag`, zoom 22, dropped with Esc) at full size on a 100 ft map (cards F5, F5b; about
  26 s), for a before | after check of a pane or ribbon change: run with `--out
  render_jobs/<name>_before` before the change and `_after` after, then diff the pane rect
  with `probes/avatar_diff.gd` (the foliage behind the glass moves with the wind: pixels over
  8 there are the background; a pane change shows over 32; the ribbon lies over swaying trees,
  so compare a crop of it by eye, `avatar_diff.gd crop`). Saves no level.
- `jobs/firefeat_line_tool.json`: the shared line tool, river beside fire line (card F5e; about
  265 s at `--full`; replaces card F5d's `firefeat_variants`). At 1280x720 on firefeat_line's
  map (a 200 ft temperate forest, seed 1234, a meadow over its east half): the Water pane at
  River and the Fire pane after a real Tab (Line, Blaze picked), each pane's size as an `eval`
  (authoring has no hint bar: the tool hint row is play's, the Events pane's);
  every brush's ring at rest and with Ctrl held over the bright meadow at zoom
  22 (`ring_<tool>_rest`, `ring_<tool>_erase` for biome, thin_clear, sculpt, paint, place, water
  and fire; Bridge draws its own cursor); then with a 2.5 m brush each line tool's cursor at
  rest (`river_rest`, `fire_rest`) and the same curve held mid-drag from the meadow into the
  forest past the dark pine, by day (`river_lay_day`, `fire_lay_day`, and under the even fill,
  option E, `*_lay_day_E`: an `eval` sets each brush's `fill`), at 1920x1080 (`river_lay_1080`,
  `fire_lay_1080`) and under outdoor_night (`river_lay_night`, `fire_lay_night`, `*_night_E`),
  each dropped with Esc; then a river carved along a second curve and the Blaze line laid, and
  at zoom 8 by day and night Ctrl held at rest and a Ctrl line held over the flames
  (`fire_put_out_rest_*`, `fire_put_out_*`) and across the river (`river_erase_rest_*`,
  `river_erase_*`), each cancelled with Esc. Every frame carries a fire.gd label. Sheets:
  `sheet_one_look_R` and `sheet_one_look_E` (river | fire per row under each fill),
  `sheet_panes` (Water | Fire), and before | after
  sheets against `render_jobs/firefeat_line_tool_before_f5h` (a run of the job with `--out`
  before card F5h): `sheet_rings_before_after` (per brush: rest before, after, Ctrl before,
  after), `sheet_erase_before_after`, `sheet_lay_1080_before_after`. Saves no level.
- `jobs/firefeat_path.json`: Start a fire's Path shape (cards F6 to F6c; about 275 s built at
  half size). Build: the 200 ft temperate map with the meadow stripes east of x 0 (as
  firefeat_line_tool's), authoring River and Line of fire (Line and Blaze picked by clicks on
  the Fire pane's tiles, `events_pane.gd click_tile`, so the pane shows what the brush does)
  held mid-drag on one curve from the forest into the meadow at zoom 22 (`one_tool_*`) and
  each at rest (`rest_*`), saved as `_firefeat_path` and played. Look: Start a fire's pane at
  Circle, real Tabs with the pane open and closed (an eval logs the shape and that no GUI
  control took focus), the Path ring at rest, mid-drag over the forest and over the meadow,
  Esc keeping it armed; the Path's three hues (`ochre_B_*`, `ochre_C_*`, A the default's
  `path_drag_*`; the mode's `hue` set by eval) with the River and the Line of fire on the same
  curve by day, at night and at 1280x720 (`ochre_river_*`, `ochre_fire_line_*`, `night_*`;
  the Events pane's Fire picked by its tiles, `fire_line_pane`); a path over the meadow alone
  refused whole (`path_drag_refused_*`, the chip logged), the panes at Path and at Circle and a
  drag at 1280x720 (`*_720`, full size); then a path fire on the same curve (the probe's `fire`
  kind `path`) at 0.7, 1.6 and 2.6 s and after (settled, 9 s after the clock is freed), by day
  and at 23:00. Sheets: `sheet_one_tool` (River | Line of fire | Path, card F6b's above card
  F6c's, from `render_jobs/firefeat_path_before_f6c`), `sheet_rest` (before | now),
  `sheet_taper` (the trees-to-ground change cropped at 1080 and 720, before | now),
  `sheet_ochre_A`, `_B`, `_C` (day, night, a 720 crop over the golden meadow) and
  `sheet_ochre_compare` (A | B | C | River | Line of fire in those three rows),
  `sheet_fire_pane`, `sheet_night_three`, `sheet_today_now` (the circle's pane and ring before
  card F6's UI | now), `sheet_cursor`, `sheet_cursor_before_now`, `sheet_720`, `sheet_motion`,
  `sheet_after_before_now`. `ribbon_pixels.gd` reads a ribbon's luminance and its contrast
  over the golden meadow and over grass from a capture and its `_sub`. Delete the level with
  `jobs/firefeat_path_cleanup.json` (the probe's `delete_level`: `_firefeat_path` only).
- `jobs/firefeat_handover.json`: a fire's handover from its motion to its map change (card
  F6b), on `_firefeat_path` (`--saved` after a firefeat_path build; about 45 s). A path fire
  with the clock held to 2.6, 3.0, 3.5, 4.0, 4.5 and 5.0 s, then free (`tl_path_f*` about every
  0.5 to 3 s until settled), then a circle fire at map (-8, -6), 4 m, held to 2 and 3 s, then
  free (`tl_circle_*`); each capture after a `status` line in log.txt (the probe's: wall
  clock, event clock, change made, char alpha, played and landed, the scatter regenerating
  and growing, the ground look's restamp wait and bakes, the ash weight and scatter rows
  under named pixels), and F6B| lines in the raw output when the change is made and cells
  land. Its first step logs straight 8 m lines with no burnable tree (`treeless`). Sheets
  `sheet_handover_path`, `sheet_handover_circle` and `sheet_handover_before_now` (the path's
  f1 and f3 to f7 against `render_jobs/firefeat_handover_before_f6c`, the run before card
  F6c's char drift). Saves nothing;
  each fire is undone.
- `jobs/firefeat_cue.json`: the drag ruler's "In fire" cue and the fire's sound (cards F7a and
  F7b; about 40 s). A new 100 ft meadow (seed 4242) with a radius-3 disc of flames at (6.5, 0),
  saved as `_firefeat_cue` and played. `probes/fire_sound.gd` logs the fire's sound players, their
  gains and three SFX bus peak readings before the fire, with it in view and after the view pans
  away (`look_at` (-15, 0), 2.5 s); a second of settling before the first hold (on one F7a run the
  hold set no drag target). Holds a token mid-drag over the fire (`cue_in_fire`, the label text
  logged) and off it (`cue_outside`). Its last step deletes exactly `_firefeat_cue` (an `eval` of
  `LevelManager.delete_level_folder`), not the other `_firefeat_` levels.
- `jobs/firefeat_sound_zoom.json`: the fire's sound at every zoom (card F7c; about 47 s). A new
  100 ft meadow (seed 4242) in authoring with a radius-4 band of flames along x -4..12 (two
  clusters); nothing is saved, so there is no level to clean up. `probes/fire_sound.gd` logs the
  camera's size and place, the clusters nearest the view's middle with their distance from its
  axis, each player's place, gain, target and pan, and the SFX bus at the home view, at zoom 8
  and zoom 2 over the burning point farthest from every cluster's centroid (its `aim` action,
  `target` "gap"), at zoom 2 3 m off the largest cluster's centroid and on it, and 1.5 m and
  12 m past the flames' east edge (`target` "edge"). One capture, `zoom2_gap`.
- `jobs/sound_check.json`: the authoring tools' sounds in the running game (card brushland-sound;
  about 45 s). A new 100 ft meadow (seed 4242) in authoring, never saved: a Biome dab (a tap), a
  10 m Biome stroke, a 10 m Paint stroke, a Place click (a real input `gesture`), undo, redo, a
  12 m River and an 8 m plank Bridge across it. `probes/authoring_sound.gd` (`listen`, then a
  `mark` per step, `stop`) logs every sound AudioManager plays with its take and time, every
  request by name and count, the SFX bus's loudest peak, how many frames read above -200 dB and
  its peak over the step's last 0.5 s. One capture, `sound_check_end`. Its first and last steps
  delete `_sound_check_` in case a run ever saved one.
- `jobs/fire_smoke_book.json`: bakes the persistent fire's smoke book once, offline (card
  fire-prod-c5a; `probes/fire_smoke_book.gd`; `tools/fire_sim/README.md`). In the real window (a
  headless run draws nothing) it draws `tools/fire_sim/fire_smoke_book_bake.gdshader` into one
  SubViewport atlas of 8 x 6 tiles (`FireSmokeBook`'s 2 seeds of 24 frames), reads it back after
  the frame that draws it, slices it into 48 RGBA8 layers of 128 x 160 and saves
  `res://assets/fire/fire_smoke_book.res` with `FLAG_COMPRESS` (3,409,542 bytes, Git LFS), then
  reloads it to check the round trip; `report` logs the book's `problem()`, the file's size and
  the round trip. A scratch job's `reference` (another bake shader's path, such as the spike's
  own) is baked the same way and compared layer by layer: on 2026-10-17 all 3,932,160 bytes
  equalled the spike's. It overwrites the shipped asset, so run it only to re-bake.
- `jobs/fire_perf_play.json`: the persistent fire's pinned performance pass (card F4b-2;
  docs/PERFORMANCE.md "Fire (F4): pinned performance pass"; `probes/fire_perf.gd`). Drop the
  pinned `override.cfg` in first (the job removes it at startup) and run on a quiet machine.
  Build (tagged `build`, about 100 s): a new 200 ft temperate forest (seed 1234), three
  `flames` passes of radius 4 across about a third of the map and a curved `blaze` line across
  the view, saved as `_firefeat_perf`. Then, vsync off, an in-run A/B of 6 s windows per view
  (home, zoom 8 over the blaze, zoom 20, the camera's own widest zoom, and zoom 30, past the
  camera's limits; since card fire-prod-c3 there is no LOD, so every zoom draws the same fires) by
  day and under `outdoor_night` (fire.gd's sun keys): the fire on and off (flames, ground term,
  smoke and lights) on / off / on / off, and at home and zoom 20 each part off in turn
  (`config no_flames`, `no_glow`, `no_smoke`, `no_lights`) in a palindrome; the field's
  per-frame script time (`cpu`) and a 4 m brush dab's refresh (`refresh`); then five more
  passes burn the rest of the map and home, zoom 20 and zoom 30 are measured again near the
  cap, day and night. `--saved` skips the build. It deletes `_firefeat_perf` at the end.
  Card F4b-3 ran it before and after its shader changes in one session (`--out
  render_jobs/fire_perf_before`, `render_jobs/fire_perf_after`), card F4b-4 before and after
  its bakes and worker (`render_jobs/fire_perf_bake_before`, `render_jobs/fire_perf_bake_after`).
  Since F4b-4 the `refresh` line gives the dab at once on the main thread (`FireField.use_worker`
  off: the whole refresh, its re-plan and heat re-splat) and on the worker (the main thread's
  launch and landing, and the worker's own time). Its numbers so far measured the fire before
  the production port (PERFORMANCE.md "Fire (F4)"). Since card fire-prod-c7b it takes zoom 20
  straight after home and zoom 8 after zoom 20: a view's camera pose depends on the view before it
  (PERFORMANCE.md "Fire, production port (C7, 2026-10-18)"), so its zoom 20 and zoom 8 poses
  differ from the F4 runs'.
- `jobs/fire_c7a_aba.json`, `jobs/fire_c7a_parts.json`, `jobs/fire_c7a_parts2.json`: the
  production fire's pinned timing (cards fire-prod-c7a and c7b; `probes/fire_perf.gd`;
  PERFORMANCE.md "Fire, production port (C7, 2026-10-18)"). Each builds fire_perf_play's map
  without saving it (no level to delete); drop the pinned `override.cfg` in first. `fire_c7a_aba`
  (about 450 s): third and whole, day and night, home and zoom 20, the fire on / off / off / on,
  memory at no fire, third and whole, `cpu`, four on | off pdiff rows and `sheet_onoff`; it ran
  identically on main and production. `fire_c7a_parts` (about 950 s): each part off in a palindrome
  at home and zoom 20, then zoom 8 and the widest zoom (`fire_perf.gd view zout`), the stroke's
  `refresh`, `bake_gpu` (the sim bake's redraw on the GPU, dab and whole) and `book {do
  release|load}` with memory; since c7b home and zoom 20 come first and a zoom 20 shot comes
  before the stroke section's home, so no home or zoom 20 follows zoom 8 or the widest.
  `fire_c7a_parts2` (about 790 s): the per-part palindromes at the A-B-A's poses, `bake_gpu`, the
  book with memory. Parse a log's windows with a script like C7a's `parse_c7a.gd` (kept with the
  card's notes): it groups `perf <view> <variant>` lines and prints on minus off and each part.
- `jobs/fire_c7b_glow.json`: the game's glow timed in run (card fire-prod-c7b, about 405 s;
  `probes/glow.gd variant`). Drop the pinned `override.cfg` in first. Builds firefeat_glow's map
  (no fire; not saved), then at day and night home and zoom 20 a palindrome of the glow old (main's
  before card fire-prod-c5b: the preset's intensity, strength and bloom over Godot's Environment
  defaults), new (`EnvironmentGlow`) and off; then a 200 ft forest burning its "third" and the same
  at night home and zoom 20. The `eval` lines log the camera holder, size, offset, the SubViewport's
  size and the cursor before each view. The second map's strokes start from the camera the first
  map left (181 fires shown, not fire_c7a_aba's 223).
- Per-term and before/after shader A/B (card F4b-3; `probes/fire_ab.gd`): a job written for the
  task (kept out of `jobs/`, as its variant file is) builds `_firefeat_perf` with
  fire_perf_play's build steps (or loads `_firefeat_look --saved`) and `patch`es variants of the
  ground's fire term (`shaders/fire_glow.gdshaderinc`, inlined into the ground shader), the
  flames (`shaders/fire_flames.gdshader`) and the smoke (`shaders/fire_smoke_book.gdshader`) from
  a JSON file, in a palindrome of perf.gd windows; or holds the clock (`hold`), grabs the frame
  under main's sources and under the working tree's (`grab`), keeps an earlier capture or a
  reference frame (`load {tag, path}`, card fire-prod-c4: round 6's frames against
  production's), and writes the pixel metrics and a before | after | diff x4 row (`pdiff`,
  which takes the larger of two frames down to the smaller; `sheet`). Main's sources for a
  "before" variant: `git -C D:/dev/tabletop/tt-sim archive --format=zip --output=<scratch>/before.zip
  HEAD <shader paths>`, read as `<scratch>/before.zip:shaders/<file>` (`git show --output`
  writes no blob). The fragment shader rejects `return`, so a variant cannot cut fragment()
  short that way. Card F4b-4's two bake actions (a "before" broad noise bake, and a re-bake at
  other densities) went with the static and fine bakes in card fire-prod-c4; they are in the
  probe's history up to f4ac41b9, and PERFORMANCE.md "Bakes and a worker (F4b-4)" holds what
  they measured.
- `jobs/fire_first_burn.json`: the first burnt-forest op on a fresh map (card F4b-2;
  `probes/fire_perf.gd first_burn`): a new 200 ft temperate map, the palette's burnt biome
  painted over a 4 m disc with nothing armed (a peer's case), the dab's milliseconds, the ground
  layers before and after and the layer arrays' sync; then a second map with the Fire tool's
  warm-up (`warm`) first (the host's case). `perf.gd author` logs each load. Since card
  fire-prod-c3 each line also gives the fire book's state with its load (threaded, request to
  landing) and upload (main thread) milliseconds: 66.9 and 4.2 ms on 2026-10-17. About 30 s.
- `jobs/fire_shards.json`: debug views of the grey shards and straight-edged wedges on burnt
  ground (card F4b-2; `probes/fire_shards.gd`) on `_firefeat_look` (build it with
  `firefeat_build` first) at the day zs view: everything, the ground alone (its chunks and
  skirt), with the fire's ground term off, with shadows off, with the screen-space effects off,
  and everything but the ground, tiled in `sheet_debug.png`; `chunks` logs the chunk meshes'
  formats and their largest UV-to-XZ gap. Then the ground alone with its shader's code swapped in
  memory for debug views of its outputs (`debug`: 1 lit grey, 2 unlit, 3 the shading normal, 4
  the geometric normal, 5 the fire's char weight, 6 the sim fire bake's albedo tile as RGB (the
  char's weight, the dried band's mix and the scorch; card fire-prod-c4; F4b-5 read the static
  bake's first tile and F4b-2 the mask and the two rasters), 7 the
  ground's albedo before the fire, 8 the fire's emission alone; `sheet_debug2.png`, and
  `sheet_debug3.png` the lower half of 2 and 5-8), and `sheet_before_after.png` from
  `firefeat_look --only "day_zs_new,sunset_zs_new"` run into `render_jobs/fire_shards_before` and
  `render_jobs/fire_shards_after` (left before, right after).

## Caveats

- **The judgment set assumes palette content.** Its composition strokes use the palette ids
  `temperate_forest_summer_s1` and `grassland_meadow_summer_s1`, and it places the species
  `oak`, `log` and `boulder` from `temperate_forest_summer_s1` and `boulder` from
  `alpine_meadow_summer_s1`. A missing species or biome in a `place` step is skipped with a
  `no species ... not placed` log line. A paint stroke is not guarded the same way: it hands
  the unknown id to the brush, so after a palette change check the log and the composition
  images, and update the ids in the job. The per-biome captures follow whatever palette is installed, so
  the capture count changes with the palette.
- **No judgment set loads a Blender reference level any more** (2026-10-12). `grid_ground`,
  `mobile_maps`, `p4b_cue` and `pol_trees` still play `user://levels/river` or
  `user://levels/deciduous_clusters` and need them to exist; their `play` and `dress` steps
  only read them.
- `jobs/token_ghost.json` (about 80 s, keeps no level): the token ghost on the plantgen package at
  taiga and temperate forest, home zoom (8 avatar tokens, the first selected) and zoom 5 (three
  tokens), in three modes: `none` (ghost and occlusion fade off: the problem), `ghost_only`
  (the ghost alone: the stress case, where the ghost does all the work) and `shipped` (ghost plus
  occlusion fade, canopy fade off). 12 captures. Edit the `package` path to use another build.
- `jobs/token_ghost_perf.json` (about 80 s): the same two maps with 32 avatar tokens on screen
  (the token cap), vsync off, GPU median and draw calls for `none`, `full` (ghost, no budget),
  `capped` (ghost at the 16-token budget), repeated to show drift. Numbers in
  `docs/PERFORMANCE.md` "Token ghost".
- `jobs/token_ghost_self.json`, `token_ghost_self_grass.json`, `token_ghost_self_temperate.json`
  (about 25 s each, taiga, open meadow and temperate forest): a large multi-part pack token
  (`token_ghost.gd` probe `spawn_big`: body, head, bloom and four legs, scale 1.5, 0.7 and 2) beside
  three avatars. Captures `big_none` (no ghost), `big_ghost_only` (the fix) and `big_before_fix`
  (`bound_extent` zeroed through `ghost_params`: the old behaviour in the same run); taiga also has
  `avatars_*` and `home_*` pairs. The ghost must not draw on the token itself in the open and must
  draw on the legs a bush or trunk covers. Docs: `docs/PERFORMANCE.md` "Token ghost: self-occlusion".
