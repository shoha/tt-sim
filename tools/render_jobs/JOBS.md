# Render jobs catalogue

Every job in `jobs/`: what it builds and captures, roughly how long a full build run takes,
and which test levels it keeps. How to run one, the flags and the build / look loop are in
[README.md](README.md); the ops and probe scripts the jobs use are in
[REFERENCE.md](REFERENCE.md). Captures are half size (960x540) unless the run passes
`--full`; a judgment set's final pass, the one its `VERDICT.md` is written from, passes it.

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
  play-zoom window in-run.
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
- `jobs/ui_tour.json`: the UI tour (about 130 s at half size, 140 s with `--full`), the
  capture set the `tt-sim-ui-critic` agent judges (`docs/UI_TASTE.md`). It saves a new
  100 ft temperate forest map as `_ui_tour_room` (shown as Mossy Hollow), then at 1280x720
  and 1920x1080 window sizes (`ui_primitives.gd window`; capture names start with the size):
  the title, keyboard focus on a quiet paper button and on the selected level card, Settings
  on each of its six sections, the new-map dialog, the host lobby (shown without hosting,
  with a sample room code and three sample players), the join screen, authoring with the
  tool drawer on Biome and focus on its picked tile (the probe lets a drawer tile take
  focus), then in play the Visuals drawer on Sun, focus on a quiet glass button, the pause
  menu, the Remove token danger confirmation, one toast of each kind, the Add Token browser
  and the avatar builder, and at dusk (19:00 through the Sun pane) the Visuals drawer, the
  browser and the pause menu again. Last, one probe capture of the title at 1720x720
  (ultrawide). 49 captures and `INDEX.md`; the level is deleted at the end. Half size makes
  the 720p captures 640x360, smaller than any player sees: judge 720p legibility on a
  `--full` run.
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

## Caveats

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
