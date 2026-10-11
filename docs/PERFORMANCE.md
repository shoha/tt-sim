# Performance

Measured findings for tt-sim's renderer, and the procedure that produced them. Read
this before attempting any rendering optimisation -- several obvious-looking ideas are
already known dead ends, with numbers.

## Where the frame goes

Dense forest map ("Sandy Clearing"), 1920x1080, vsync disabled, deterministic camera
pose (Home), RTX 3080. Isolated with the in-game render toggles (F3, then digits 1-9).

| Isolation | frame_ms | Delta |
| --- | --- | --- |
| Baseline | 14.46 | -- |
| Foliage hidden | 3.46 | -16.3M primitives, -11.00 ms (-76%) |
| Sun shadows off | 8.58 | -5.88 ms (-41%) |
| Grass not casting | 11.93 | -2.53 ms (-17%) |
| Trees not casting | 12.17 | -2.29 ms (-16%) |
| Trivial foliage shader | 12.77 | -1.69 ms (-12%) |
| Terrain not casting | 14.43 | -0.03 ms (free) |

Foliage is 76% of the frame and 16.3M of 19.36M visible-pass primitives. A bare-terrain
map renders in 1.58 ms with 46K primitives.

A `MultiMeshInstance3D` is frustum-culled as a **single AABB**, and foliage is one
MultiMesh per species spanning the whole map. If any part of a species is on screen,
every instance is vertex-processed: visible-pass primitives read an identical 19,361,510
at every camera pose tried, and panning changed nothing. **Total instance count per map
is the cost driver, not density per unit area and not what is in frame.**
**Superseded by spatial chunking (see "Spatial foliage chunking" below): this was true for
every map before chunking landed, and is now only the worst case, reached at full
zoom-out.**

## The foliage primitive budget

`utils/foliage_budget.gd` defines `PRIMITIVE_BUDGET` (8,000,000) as the DEFAULT of a
per-user setting, `graphics/foliage_budget` in `user://settings.cfg`, ranging 2,000,000 to
24,000,000 and adjustable in Settings > Graphics. Import
(`ScatterGlbUtils.process_scatter_instances()`) no longer thins anything -- it builds every
scatter instance and shuffles each chunk so any prefix of it is a spatially even sample.
The budget is applied at runtime, live in both directions with no map reload, by
`FoliageDensityController.apply()`, which writes `MultiMesh.visible_instance_count` on
every scatter chunk to keep the visible total within the player's configured value.
Allocation keeps an equal instance fraction per species, not equal visual weight -- see
"Real-map validation" below for what that costs the map's landmark trees in practice.

The default is derived from one scene on one GPU. The frame-time table above (16.3M
foliage primitives, -76%) used the in-game debug toggle's definition of "foliage", which
excludes rock scatter -- but the budget covers scatter of every kind, rock included. The
real total the budget has to bound, measured by running the actual pipeline against the
real GLB, is **19,170,768 primitives** (see below). Both figures are correct for what they
measure: 16.3M is still the right number for the frame-time table, captured with that
toggle; 19.17M is the right number for what `PRIMITIVE_BUDGET` bounds. 8M is **41.7%** of
19.17M, not "roughly half" as an earlier estimate against the narrower toggle figure put
it. Whether 8M suits hardware weaker than the RTX 3080 it was measured on is no longer an
open question the default has to answer alone -- the per-user setting resolves it: each
player raises or lowers their own budget in Settings > Graphics to fit their own machine.
The budget is still deliberately not overridable per level: a map cannot opt out of the
cap, only the player's own setting moves it, the same way for every map.

Only `user://` imported maps are affected. `load_map()`'s `res://` branch never calls
the scatter pipeline, so built-in maps are untouched. **Known gap:**
`MeshInstancingUtils.process_duplicate_mesh_instancing()` (`utils/glb_utils.gd`, called
after every scatter-pipeline call site) runs AFTER `ScatterGlbUtils.process_scatter_instances()`,
so any foliage arriving through the duplicate-collapse path is not bounded by this budget
at all -- not yet addressed.

### The budget as a per-user runtime setting

Measured on the reference map (Sandy Clearing), building every scatter instance at import
instead of thinning to `PRIMITIVE_BUDGET` there costs **+6.8 ms and +1.4 MB** of import
time and memory, for only **37 extra nodes** (1,335 to 1,372) -- the additional instances
mostly land in cells that already exist, rather than creating new ones. That is the price
of moving the budget from an import-time, one-shot decision to a runtime dial: every
instance has to exist so the dial can reveal or hide any of them without a reimport.

The setting is per-user and deliberately **not networked** -- a host and its clients may
run different densities to suit their own hardware. This is safe because scatter foliage
carries no collision, so peers disagreeing about how much of it is visible cannot desync
anything.

Verified in-game: with the setting at its minimum (2,000,000), loading the reference map
gave **162,587 visible primitives and 844 visible draw calls**. This is a functional
confirmation that the setting is applied end to end, from the config value through
`visible_instance_count` to what the renderer actually draws -- **not a timing
measurement**: it was read at a 1920x2043 viewport (not the pinned 1920x1080 used
elsewhere in this document) with the GPU contended by an unrelated application, so no
frame-time or FPS number from this sample would be comparable to anything else here.

### Real-map validation (Sandy Clearing, 112 MB)

Ran the real pipeline against the actual Sandy Clearing GLB, not a synthetic test fixture.
This predates the per-user density setting and exercised `plan()`/thinning as it ran at
import at the time; the allocation arithmetic is unchanged, but
`FoliageDensityController.apply()` now invokes it at runtime instead (see above) -- the
instance-count and primitive-count findings below remain accurate.

- **Real scatter load: 19,170,768 primitives across 52,154 instances in 57 species.** (The
  16.3M figure above is the in-game debug toggle's narrower "foliage" definition, which
  excludes rock scatter; this total is what the budget itself actually bounds.)
- **Three tree species hold 12,511,854 primitives -- 65% of all scatter cost -- in just
  225 instances (0.4% of all scattered instances)**, at 37,382 / 54,865 / 76,856
  primitives per instance. A typical game tree is 2,000-10,000 primitives. This is the
  single most actionable performance finding in this document, and it points at content,
  not code: three authored assets are one to two orders of magnitude heavier than they
  need to be.
- Consequence: 225 trees alone are **156% of the 8M budget** by themselves. The ceiling
  for trees at 8M is 144 instances (64% of 225), reachable only by deleting every other
  scattered instance on the map to leave the entire budget for trees. Keeping all 225
  needs ~19.2M, i.e. no thinning at all. **This map cannot be made cheap by any budget
  policy at any threshold; only lighter tree assets can fix it.**
- End-to-end pipeline verification: the budget fired, 21,736 instances were built exactly
  matching what `plan()` promised, totaling 7,957,006 primitives (under the 8M cap), the
  `FOLIAGE_BUDGET_REPORT_META` report was set on the scene, and zero template nodes were
  left unfreed.

**Unverified: the frame-time effect of the budget on this map.** The validator MCP bridge
could not activate the title screen's buttons to get from title into a loaded level --
clicks in both screen and viewport coordinate spaces, and Enter on the focused button,
all failed, and this was confirmed not to be an artifact of the measurement harness
itself. This is the second time this bridge limitation has cost a measurement. Do not
treat any frame-time number for this budget as measured until that path is fixed -- the
primitive-count and pipeline-correctness numbers above are measured; the frame-time
consequence of applying them is not.

**Update (2026-09-14): that blocker is gone.** `game_click_control` targets a Control by
name and converts viewport space to window space itself, which is what the raw-coordinate
attempts above were failing to do. This measurement can now be retaken.

## Spatial foliage chunking

A `MultiMeshInstance3D` is frustum-culled as a single AABB. Foliage was one map-wide
MultiMesh per species, so every instance was vertex-processed whenever any part of that
species was on screen. All the figures below come from a probe that replays the real
allocation and chunking logic -- `FoliageBudget.plan`, the allocator that
`FoliageDensityController.apply()` now runs at runtime, and
`ScatterChunker.bucket_by_cell`, which `process_scatter_instances` still runs
at import to split each species into cells -- against the real map, then counts per camera
zoom which chunk AABBs intersect the view.
At the unchunked baseline (one bucket per species) that probe puts every camera zoom at
the same **57 nodes and 7,957,006 primitives** -- the number does not move, because one
AABB per species is always drawn regardless of what the camera can actually see. That is
the premise the whole sub-project rests on.

Why chunking can help at all: the camera is orthographic, so `camera.size` is the
vertical world extent of what it sees, and the scatter footprint is a 50 x 50 world-unit
square. At a 16:9 screen aspect, visible ground area is a small and shrinking fraction of
that footprint as the player zooms in -- these are lower bounds, since the 45-degree
isometric view makes the true visible ground footprint deeper than the vertical extent
alone suggests:

| `camera.size` | Visible ground | % of the 50x50 footprint |
| --- | --- | --- |
| 2.0 (max zoom in) | 3.6 x 2.0 | 0.3% |
| 5.0 | 8.9 x 5.0 | 1.8% |
| 10.0 | 17.8 x 10.0 | 7.1% |
| 20.0 (max zoom out) | 35.6 x 20.0 | 28.4% |

One map-wide AABB per species cannot exploit any of that headroom; splitting into chunks
is what lets frustum culling discard the part of the footprint the player cannot see.

The map has a literal clearing at its centre: zero surviving scatter instances within
plus or minus 10 units of the origin (16% of the map area), and only 4.8% of instances
within plus or minus 15 units. The Home camera pose sits in that clearing. So at close
zoom, chunking culls 100% of foliage where the unchunked build processes all 7,957,006
primitives. A coarse per-species AABB covers the clearing even though nothing is in it;
fine chunks around an empty clearing are culled outright.

The sweep (nodes, then visible draws/primitives per camera zoom, across the 50 x 50
reference map). **This is the exploratory chunk-size comparison -- geometric figures,
counts of which chunk AABBs the probe found intersecting the view, NOT rendered output
from a GPU.** It is not evidence that chunking helps; it is only a way to compare chunk
sizes against each other (see the rendered measurements below for whether chunking helps
at all):

| chunk size | nodes | zoom 2 | zoom 5 | zoom 10 | zoom 20 |
| --- | --- | --- | --- | --- | --- |
| unchunked | 57 | 57 / 7,957,006 | 57 / 7,957,006 | 57 / 7,957,006 | 57 / 7,957,006 |
| 25 | 199 | 137 / 4,094,814 | 150 / 6,283,242 | 174 / 7,610,722 | 176 / 7,843,338 |
| 15 | 656 | 0 / 0 | 2 / 4,320 | 14 / 1,151,794 | 284 / 6,222,732 |
| 10 | 1335 | 0 / 0 | 0 / 0 | 17 / 431,868 | 731 / 5,932,752 |
| 8 | 1885 | 0 / 0 | 0 / 0 | 3 / 586,032 | 831 / 6,143,696 |
| 5 | 2747 | 0 / 0 | 0 / 0 | 4 / 147,376 | 1193 / 5,310,072 |

The chosen value is **10.0**. The geometric sweep above first favoured it over 25 (barely
better than unchunked while tripling node count) and over 15 (10 saves 62% more primitives
at typical play zoom for three more draw calls, which is where players spend their time;
15 only wins at full zoom-out, where the primitive budget rather than chunking is the
binding constraint). Size 5 was originally passed over on a fear that its extra draw calls
at full zoom-out would cost more than they bought. Chunk sizes 10 and 5 have since been
rendered (see below), and 10 is confirmed as the right value -- but not for the originally
feared reason; see the rendered comparison for the nuance. 25 and 15 remain geometric-only.

**The geometric figures above are not accurate in absolute terms, and must not be read as
predictions of rendered numbers.** The geometric sweep predicted 431,868 visible
primitives at zoom 10 for chunk size 10; the rendered measurement below shows 5,242,617
visible primitives at the comparable Home pose -- over 12x higher. Two reasons: the
geometric probe counted only foliage chunk AABBs, while the rendered `visible_primitives`
column includes terrain, tokens, water and everything else on screen; and the probe's
view-box model was too small for the isometric projection, which sees further than the
vertical `camera.size` extent alone suggests. The sweep remains useful for what it was
built for -- comparing chunk sizes against each other, where this systematic error
largely cancels out -- and that comparison is how size 10 was chosen. It is not useful,
and was never validated, as an absolute prediction of rendered primitive counts, draw
calls, or frame time.

### Rendered measurement: chunking vs. unchunked (Sandy Clearing, real render)

The validator bridge's title-screen click blocker, which previously prevented any
rendered measurement here, is fixed. This is a real render, on the real Sandy Clearing
map, 1920x1080 viewport pinned via `override.cfg` with `aspect="keep"` (confirmed via the
perf log's `viewport_width`/`viewport_height` columns), vsync disabled, RTX 3080, debug
build via the validator bridge. Both configurations were measured at two camera poses,
Home and full zoom-out, each pose sampled within a single run and segmented by the log's
`camera_zoom` column.

**Unchunked**, obtained through the real code path by setting the chunk size to 0, which
`bucket_by_cell` maps to a single bucket per species (this is byte-for-byte the
pre-chunking one-MultiMesh-per-species behaviour, not a simulation of it):

| pose | frame_ms | FPS | visible prims | visible draws | shadow prims | shadow draws |
| --- | --- | --- | --- | --- | --- | --- |
| Home, zoom 13.85 | 9.62 | 104.5 | 8,147,748 | 88 | 6,591,594 | 47 |
| max zoom out, zoom 20 | 13.42 | 75.8 | 8,159,600 | 89 | 6,603,446 | 48 |

**Chunked at 10 world units** (the shipped value):

| pose | frame_ms | FPS | visible prims | visible draws | shadow prims | shadow draws |
| --- | --- | --- | --- | --- | --- | --- |
| Home, zoom 13.85 | 8.41 | 119.6 | 5,242,617 | 767 | 4,421,617 | 264 |
| max zoom out, zoom 20 | 11.12 | 91.7 | 7,273,964 | 1,145 | 5,980,046 | 370 |

What this confirms:

1. **The premise is confirmed in a rendered build.** Unchunked visible primitives are
   8,147,748 at Home and 8,159,600 at full zoom-out -- essentially identical despite a
   large change in what is on screen. That is "one AABB per species is always drawn",
   now measured rather than argued.
2. **Chunking is a win at both poses.** Home goes 9.62 -> 8.41 ms, a 1.21 ms / 12.6%
   improvement (104.5 -> 119.6 FPS). Full zoom-out goes 13.42 -> 11.12 ms, a 2.30 ms /
   17.1% improvement (75.8 -> 91.7 FPS).
3. **The draw-call risk did not materialise, and this reverses the previously stated
   open risk.** The worry was that roughly 731 extra draw calls at full zoom-out might
   cost more than the primitives they save. Measured, full zoom-out goes from 89 to 1,145
   visible draw calls -- 13x more -- and still gets 2.30 ms FASTER, the LARGER of the two
   improvements. The risk was tested and disproven.
4. **Chunking enables shadow-cascade frustum culling.** Shadow-pass primitives fall from
   6,591,594 to 4,421,617 at Home, a 33% reduction, while shadow draw calls rise 47 ->
   264. Chunking lets whole chunk AABBs be discarded from the shadow cascades by frustum
   culling -- a different mechanism from the `directional_shadow_max_distance` knob, which
   was re-tested against this chunked build and remains inert (byte-identical shadow
   primitives at 30 and 100 units). See the "Known dead ends" entry for
   `directional_shadow_max_distance` below.

### Rendered measurement: chunk size 5 vs. 10 (Sandy Clearing, real render)

Same conditions as above, Home pose only. Each configuration sampled its own
foliage-hidden reference within the same run, so configurations are compared by foliage
cost (foliage-on frame time minus the reference) rather than by absolute frame time -- see
"How to measure without fooling yourself" below for why absolute frame time is not
comparable across sessions; the 5.27 ms figure for chunk 10 here is from a later session
than the 8.41 ms figure above and the two must not be compared directly, only the
within-session deltas below are meaningful:

| config | frame_ms (foliage on) | reference (foliage off) | foliage cost | visible prims | visible draws | shadow prims | shadow draws |
| --- | --- | --- | --- | --- | --- | --- | --- |
| chunk 10 (shipped) | 5.27 | 2.47 | 2.80 ms | 5,242,617 | 767 | 4,421,617 | 264 |
| chunk 5 | 5.20 | 2.43 | 2.77 ms | 4,683,736 | 1,361 | 4,011,580 | 411 |

Chunk 5 cuts visible primitives by 11% and adds 77% more draw calls, and the two effects
cancel: foliage cost differs by 0.03 ms, about 1%, within noise. Combined with chunk 5
costing 2,747 nodes against 1,335 and more processing time at load (see "Map load cost"
below), **10 is confirmed as the right value on measured grounds.**

The nuance matters: the earlier reasoning for preferring 10 was that size 5's extra draw
calls would cost more than they bought. That specific fear was wrong -- the draw calls did
not hurt, consistent with the unchunked-vs-10 comparison above already showing chunk 10's
own extra draw calls costing nothing. But the conclusion holds anyway, for a different
measured reason: size 5's primitive saving simply does not convert into frame time. Both
things are true at once, and only the second one still argues for 10.

### Map load cost (Sandy Clearing, headless)

**Measured.** The design that proposed chunking named load time as a user-visible cost a
frame-time win does not excuse. Timed headless (so unaffected by GPU state), instrumenting
`ScatterGlbUtils.process_scatter_instances` against the same map with a fresh scene each
time, minimum of three repetitions per configuration (the robust estimator here -- run
times are noisy run to run; one outlier hit 542 ms):

| chunk | nodes | scatter processing |
| --- | --- | --- |
| unchunked | 57 | 88.1 ms |
| 25 | 199 | 89.5 ms |
| 10 (shipped) | 1335 | 101.7 ms |
| 5 | 2747 | 112.6 ms |

Chunking at 10 costs **+13.6 ms** against a GLB parse of roughly 2,474 ms for this 112 MB
map -- about **0.5% of map load time**. Negligible.

## Occlusion fade: token data as a shared texture (2026-09-14)

Before: `OcclusionFadeManager._update_token_uniforms()` pushed three uniform arrays
(`token_count`, `token_positions[32]`, `token_radii[32]`) to every converted
ShaderMaterial -- one per map surface plus every tree species material -- every second
physics frame, and every surface got its own ShaderMaterial even when several surfaces
shared one source StandardMaterial3D.

After: token data is packed into one 32x1 RGBAF `ImageTexture` (pixel i = world x, y, z,
fade radius) bound once per material as `occlusion_tokens`, updated with
`ImageTexture.update()` once per tick; the count is the global shader parameter
`occlusion_token_count` (declared in `project.godot`) -- Godot global shader parameters
have no array types, which is why the data is a texture and only the count is a global.
Converted materials are deduplicated by source StandardMaterial3D. Ticks where no token
moved skip the GPU update entirely. Collision AABBs are cached per shape. `enable_occlusion`
now defaults to `false` and is set explicitly, per material, by `OcclusionFadeManager` on
every material it converts or registers -- see the gate-fix note below and the "Known dead
ends" bullet on process-global shader parameters.

Measured (coordinator, 2026-09-14, re-measured after the gate fix in ec2e24e): Sandy
Clearing via `tests/test_play_level.tscn`, 1920x1080 pinned with override.cfg, vsync off,
Home camera pose, 2 static tokens, 14 converted materials, samples with elapsed_s > 5,
primitives identical in every run (24,543,623 with foliage, 3,725,814 with foliage hidden):

| Run | Build | foliage on frame_ms | foliage off frame_ms (in-run reference) | foliage cost (delta) | occlusion tick ms (foliage on) | draw_calls (on/off) |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | before (9c96f04) | 10.72 | 8.37 | 2.35 | 0.0609 | 1191 / 474 |
| B1 | texture, before gate fix (1730e08) | 10.91 | 8.37 | 2.54 | 0.0375 | 1189 / 472 |
| A2 | before (9c96f04), repeat | 10.79 | 8.36 | 2.43 | 0.0609 | 1191 / 474 |
| B2 | texture + opt-in gate (9268723) | 10.81 | 8.37 | 2.44 | 0.0391 | 1189 / 472 |

The A-A spread (two runs of the same build) is 0.08 ms of foliage cost; that is this
session's noise floor for the delta. B1's +0.19 ms over A1 was outside that spread and was
a real regression: moving the token count to a process-global left `enable_occlusion`
(default true) as the only gate on grass foliage materials the manager never registers, so
every grass fragment ran the fade loop. The first draft of this section called that
difference noise by citing the cross-session absolute-frame-time drift figure instead of
comparing deltas against the in-run reference -- exactly the mistake rule 4 below warns
against; it is recorded here so the next reader does not repeat it.

B2, with the opt-in gate, sits inside the A spread: the per-fragment `texelFetch` on
registered tree materials is not measurable on this scene. The CPU-side occlusion tick
fell from 0.061 to 0.039 ms; on static tokens nearly all of that is the skip-if-unchanged
path (entries are still collected each tick), so roughly a third off is the static-token best case. The
texture's own benefit (one upload instead of three uniform-array uploads per converted
material) applies on ticks where tokens move and scales with the number of converted
materials; it was not isolated on this 14-material scene. Draw calls fell by 2 from
material sharing.

Related change, same session: the sky-preset cache and the 100 ms live-broadcast
throttle (`VisualBroadcastThrottle`) were verified behaviourally at runtime rather than
frame-time measured, since the cost they remove was a one-off re-bake/RPC per edit tick,
not a steady-state cost.

### Close-zoom canopy fade (Polish, 2026-10-05)

The cause of "the camera cuts into tree canopies at close zoom" was both candidates. The
camera's offset scaled with the zoom (`_update_camera_offset`), so its near plane (0.001 in
front of a camera 3.5 m above the ground at zoom 6, 1.4 m at zoom 2) sliced every canopy
near the bottom of the frame flat: crowns cut off birch trunks, round bushes shown hollow.
It already does this at the home zoom for the tallest trees at the bottom edge (a 15 m pine
there is culled whole; `pol_trees` `f_a_z13` against `f_a_z13_back`). Moving the camera
back along its view axis (`probes/close_zoom.gd back`, same frame) removes the cut and shows
the second cause: below about zoom 10 the canopies between the camera and the view centre
fill the frame with leaf cards (`f_a_z6_nofade`).

The fix:

- `CameraController._hold_near_plane_over_canopies` pulls the near plane back behind the
  camera (a negative `near`; the camera stays where it was) until the bottom corners' ray
  origins, which lie on it, stand `CANOPY_CLEARANCE` (24 m) above the highest ground, at
  every zoom. Nothing is sliced or culled any more, including at the home zoom and above
  (the 15 m pine is back in `f_a_z13`; in a dense forest the home frame now shows the trees
  standing near its bottom edge, which the old cut had removed so that the frame read as a
  clearing). A first version backed the camera itself off along
  its view axis instead; that is not free here, because the sun's shadows (fixed 100 m max
  distance in play, fade from 80 m, cascade splits measured from the camera) and the
  presets' exponential fog are measured from the camera: frozen-clock captures at home
  (scratch job, `falls.gd clock 0`) showed the top of the frame up to 11 levels brighter
  with the camera 50 m back, and within 1-2 levels of the old frame with `near` at -50.
  Rays from `project_ray_origin` now start on that plane, behind the camera:
  `is_mouse_over_token`'s ray and the measure tool's grew to 1000 m (the play camera's top
  edge at zoom 20 is now about 116 m from its ray origin; it was 57 m). Measured near values:
  -61 m at home, -59 at zoom 20, -63 at zoom 6, -64 at zoom 2, -53 at a 150 ft map's full
  authoring zoom-out (size 39.3), far 1000 throughout. A token drag through DragAndDrop3D
  resolves to the same ground cell with the old and the new near, and `is_mouse_over_token`
  finds the same token.
- The foliage shader dissolves the canopies in front of the view-centre ground over a soft
  round window in the middle of the screen (`apply_canopy_fade` in
  `wind_foliage_include.gdshaderinc`, globals from `CanopyFade`), at every play zoom (the
  user approved the fade at home, 2026-10-05): a depth band from 0.5 m in front of the
  centre ground over 0.35 x size; at play zooms (home to 20) strength 0.9 and a small window,
  full inside 0.2 x size of the centre ray and gone past 0.55 x size; below home it ramps to
  the close-zoom clearing (strength 1, 0.3 to 0.75 x size) by 0.55 of the home size; past
  zoom 20 it fades away, gone by 30 (authoring's whole-map views show no fade). Chosen by
  eye on the forest and taiga maps against strength 0.55 to 1 and windows from 0.1/0.42 to
  0.25/0.65 x size (`close_zoom.gd play`): the smaller ones left the taiga's home a wall of
  pines with a few gaps, 0.25/0.65 began to show a field of bare trunks. At the home zoom the
  taiga now opens a soft window onto the ground and its boulder, a handful of trunks
  standing in it, with whole pines framing it; the forest's home reads its floor and river;
  a sparse grassland map looks as before.
  Leaf cards drop out card by card and limbs limb by limb (key: the authored phase,
  COLOR.b); the trunk (authored flutter 0) always stays, and the shadow pass is left alone,
  so the forest floor keeps its dappled light. Trees at the frame's edges stay whole and
  frame the clearing. `WindFoliage.canopy_part` tells bark from leaf cards by the source
  material's transparency.

Cost, indicative (user's RTX 3080, in-run A/B with `close_zoom.gd fade` / `near` / `hold`,
`pol_trees --only f_gpu`, not the pinned procedure, GPU contended, p90 noisy): the trees the
near plane used to cut away are now drawn, so the hold itself costs what they cost: at the
home zoom 4.38 ms GPU median with the hold against 4.21 with the old near (+0.17 ms); at zoom
6 in a temperate forest grove 2.08 ms with the old near and no fade, 2.40 / 2.43 with the
hold and no fade, 2.58 / 2.62 with the hold and the fade. The fade itself is +0.05 to +0.2 ms
where it is on (an earlier run: 2.16 / 2.26 against 2.12 / 2.14) and nothing at the home zoom
(4.38 against 4.34, before the play-zoom fade). With the play-zoom window, at home in the
taiga the fade saves GPU time (on 4.26 / 4.41 ms against off 4.57 / 4.51: fewer leaf cards
shaded). The CPU side is one layer-1 ray per frame up to zoom 30 and three global parameter
writes only when a value changes.

## Per-frame idle and drag work removed (2026-09-15)

What changed (branch `review/perf-medium`): the invisible tilt-shift quad under the camera
and its per-frame raycast plus DoF write are deleted; `handle_zoom()` skips its size lerp,
cursor correction and offset update when the camera is already at its target; drag-and-drop
and the measure tool record the latest pointer position on input and raycast at most once
per frame in `_process` (drag-and-drop's `_process` now runs only while dragging);
`WaterRippleRegistry.flush_disturbances()` is the single owner of the water uniform push
(once per frame while anything is submerged, one cleared push after the last exit, silent
otherwise, freed bodies pruned); weather and volume-overlay `_process` loops run only while
they have work; the grid drag highlight writes its parameters only on change; the token
input gate checks hover and event type before the permission lookup; the drop indicator
poses a prebuilt landing circle and rebuilds its dotted line only when the token moved more
than 1 mm.

Measured (coordinator, 2026-09-15): Sandy Clearing via `tests/test_play_level.tscn`,
1920x1080 pinned with override.cfg (which also disables vsync; `root.gd` does not run in the
test scene, so `settings.cfg`'s vsync flag is not applied there), Home pose, 2 static
tokens, B/A/B in one session (branch, main, branch), samples with `elapsed_s` 6-44 (idle)
and 49-78 (a held drag started through the bridge with edge pan disabled), primitives
identical across runs (24,543,623 idle, 24,546,111 drag). The GPU was shared with desktop
applications at 40-70% utilisation throughout, so wall-clock frame time drifted by more
than the changes could move it:

| Run | idle frame_ms | idle process_ms | idle camera_update_ms | drag frame_ms | drag camera_update_ms | drag grid_overlay_ms |
|---|---|---|---|---|---|---|
| B1 branch | 15.38 | 17.13 | 0.024 | 14.79 | 0.013 | 0.013 |
| A1 main | 13.15 | 15.89 | 0.035 | 13.85 | 0.027 | 0.011 |
| B2 branch | 12.88 | 15.43 | 0.025 | 12.98 | 0.015 | 0.016 |

Reading: B1 versus B2 (same build) differ by 2.5 ms, which is the session's drift, so the
wall-clock columns cannot resolve sub-millisecond CPU savings on this GPU-bound scene, and
this section claims no frame-time win from them. The camera monitor is the one stable
signal: 0.035 -> 0.024/0.025 ms idle and 0.027 -> 0.013/0.015 ms during a drag, consistent
across both branch runs, which is the idle-zoom skip. The other changes remove work that
was demonstrably redundant (per-event raycasts collapsing into one per frame, uniform
pushes with nothing submerged, ImmediateMesh rebuilds with nothing moved) and were verified
behaviourally at runtime (drag, drop indicator, water, undo) rather than by frame time.
Method note: the log now carries a `process_time_avg_ms` column (main-thread
`Performance.TIME_PROCESS`, no GPU or vsync wait) appended after the toggle columns; it is
the column to compare for CPU-side changes when the frame is GPU-bound or vsync-capped.
`Performance.TIME_PROCESS` covers `_process` callbacks only -- not `_input`/
`_unhandled_input`, `_physics_process`, tweens, or signal handlers -- so input-gate changes
need a different probe.

## Foliage backlight (2026-09-16)

Task 7 (commit af68909) added a `backlight` uniform to the wind foliage shaders, written
to Godot's `BACKLIGHT` built-in, and shipped it with `WindFoliage.PRESETS["tree"]["backlight"]
== 0.3` and the same for `"grass"` (`utils/wind_foliage.gd`); this section's decision then
changed both presets to 0.0. This section measures its frame-time cost and records the
shipped-value decision.

Setup: Sandy Clearing via `tests/test_play_level.tscn`, 1920x1080 pinned with
`override.cfg` (`aspect="keep"`, plus `display/window/vsync/vsync_mode=0` -- `root.gd`
does not run in the test scene, so `user://settings.cfg`'s vsync flag, which was `true`,
is never applied there; the project has no vsync override of its own, so the override.cfg
key was the only way to get vsync off for this scene), Home camera pose (zoom 13.85), F3
overlay open, GPU idle before the run (6% utilization, 47 C, 210 MHz) and then fully
occupied by this same Godot instance throughout (99%, 76 C, 1560 MHz) -- a single-process
load, not contention from another application. Two probe scripts written to
`user://` (`_bl_on.gd` / `_bl_off.gd`), each setting `backlight` to 0.3 / 0.0 on all 47
materials from `WindFoliage.collect_foliage_shader_materials(...)`, confirmed by their
return count every time. Sequence within one run: off, wait ~25 s, on, wait ~25 s, off,
wait ~25 s, on (held for the rest of the run while screenshots/logs were read). One
screenshot captured in each state, both at Home pose and again after zooming toward the
tree canopy (zoom 10.85).

`primitives` (24,671,017), `visible_primitives` (13,306,433), `visible_draw_calls` (849),
`shadow_primitives` (11,360,848), and `shadow_draw_calls` (311) were identical across
every sample in the entire run -- expected, since flipping a shader uniform does not
change geometry, and confirming the camera pose never drifted.

Samples (median `frame_time_avg_ms`, rows with `elapsed_s > 5` within each window,
excluding the transition frame at each toggle):

| Window | elapsed_s range | n samples | median frame_time_avg_ms |
| --- | --- | --- | --- |
| off (1st) | 5-24 | 74 | 9.855 |
| on (1st) | 27-49 | 86 | 9.805 |
| off (2nd) | 53-75 | 86 | 9.810 |
| on (2nd) | 78-160 | 322 | 9.800 |

Off average: 9.8325 ms. On average: 9.8025 ms. **Delta (on minus off): -0.03 ms** -- on
was marginally faster than off, i.e. the cost is not distinguishable from this session's
noise floor and is well under the 0.3 ms decision threshold.

Screenshots: at the Home pose, and again zoomed toward the canopy (zoom 10.85), the
off/on pairs were visually indistinguishable -- no perceptible rim-light/backlit-leaves
effect and no washed-out look either. The Home pose's foreground is dominated by two
large boulders with the canopy small and distant, and the sun angle at this pose does not
put much foliage into backlit silhouette, so 0.3 has no visible payoff here even though it
also costs nothing measurable.

**Decision: ship `backlight` at 0.0 for both presets.** The frame-time half of the rule
passed (delta far under 0.3 ms) but the visual half did not (no perceptible improvement at
the Home pose in either framing tried), and the rule requires both. `utils/wind_foliage.gd`
now sets `PRESETS["tree"]["backlight"]` and `PRESETS["grass"]["backlight"]` to 0.0; the
`BACKLIGHT` shader wiring, the uniform, and the existing tests (which only assert the
value is within 0..1) are unchanged, so a future re-measurement at a pose/sun angle where
the effect reads better can revisit the value with no code changes needed beyond the
constant.

**Addendum: a later verification at a canopy framing did find a visible effect.** A
follow-up measurement at zoom 14.85 (closer to the canopy than either framing tried above)
with `backlight` set back to 0.3 measured +2.2% foliage-band mean luminance from frames
saved to disk; frame time was not re-measured in that pass. The shipped constant stays 0.0
-- this result did not reopen the decision above -- but it is the number to start from if
this value is revisited: a real effect exists at close canopy framing, it was just too
small to see at the two poses this section originally tried.

## Tree trunk and rock decimation in the asset catalog (2026-09-18)

The "Real-map validation" finding above -- three tree species at 37k / 55k / 77k
primitives per instance are 65% of the map's scatter cost, and only lighter assets can
fix it -- was acted on in terrain-paint, not here: `tools/decimate_baked_catalog.py`
gained a `--material-pattern` flag, the FloraPaint catalog's `Wood_material_*` surfaces
were decimated toward 3,000 and `Rock_material_*` toward 300, and Sandy Clearing was
refreshed and re-exported. Leaf cards are untouched. The trunks floor out well above
3,000 (they are thousands of tiny twig islands that Collapse cannot merge): the three
trees are now 9,012 / 19,148 / 31,740 per instance, and the map's scatter load went from
19,170,768 to 9,473,704 primitives across the same 52,154 instances.

Measured in one session, `tests/test_play_level.tscn` through the validation bridge,
1920x1080 pinned via `override.cfg`, vsync off, RTX 3080 idle beforehand (1% utilisation,
44 C), Home pose (zoom 13.85), 40 s windows, old and new `map.glb` swapped on disk and
reloaded with R in the same process, A/B/A order:

| Map | Budget | frame_ms | primitives | visible | shadow | visible draws |
| --- | --- | --- | --- | --- | --- | --- |
| Old | 24M (all instances) | 10.83 | 24,549,059 | 13,306,433 | 11,238,892 | 849 |
| New | 24M (all instances) | 8.90 then 8.66 | 10,776,490 | 6,527,062 | 4,245,698 | 849 |
| Old | 8M (default) | 5.71 / 5.86 | 9,877,485 | 5,314,192 | 4,559,565 | 805 |
| New | 8M (default) | 7.79 | 9,122,526 | 5,510,620 | 3,608,178 | 840 |

Two readings, and they are not in tension:
- **Same content, all instances shown: 2.0 ms faster (-18%)**, with visible primitives
  halved and shadow-pass primitives down 62%. This is the like-for-like effect of the
  lighter assets; the two New@24M samples bracket the Old sample in time, so it is not
  drift.
- **At the default 8M budget the new map is 2 ms slower**, because the budget is spent
  differently: the old map could only show 42% of its instances under 8M, the new one
  shows about 84%. Twice the grass and leaf-litter instances on screen is more
  alpha-tested fill (see "Grass no longer casts shadows" for why fill, not primitive
  count, is what dense card foliage costs). That is the fidelity the budget was meant to
  buy; a player who wants the old frame time gets it by lowering the slider, now with
  the trees intact.

Screenshots at the Home pose and two focused poses showed intact leaf cards, smooth
decimated branches and no double-applied displacement (the catalog trees carry
`DISPLACE` + `SIMPLE_DEFORM` modifiers, which the first version of the decimator would
have baked in twice). The old export is kept beside the level as
`map.glb.pre-decimate-2026-09-18`.

### Correction: the first decimation pass had deleted the trunks

The tree numbers in the section above (9,012 / 19,148 / 31,740 per instance, 8.90 ms)
were measured on broken assets. A plain Collapse toward 3,000 triangles on these
twig-heavy trunks spends its whole budget on the few large smooth islands: the trunk
island was crushed to nothing, two thirds of the twig islands were deleted, and the
wood surface area went UP (folded geometry) -- all while the triangle total looked like
a sensible result. Reported by the user as "the trunks are not visible at all, the
branches are". terrain-paint's `decimate_object_mesh` now prunes sub-pixel twig islands
(`--min-island-area 0.02`) and clamps the Collapse ratio (`--min-ratio 0.5`); the
catalog was restored from its pristine backups and re-run. Corrected assets: 18,635 /
25,554 / 22,713 triangles per tree, trunks intact (verified by island analysis against
the backup and by screenshots in-game), scatter total 9,499,495 primitives. Home pose
with every instance drawn, same setup as above but a separate session so not directly
comparable in absolute terms: **8.09 ms**, 11,267,232 primitives, 6,563,904 visible,
4,699,598 shadow. The thinning A/B below was run on the broken trees; its delta is a
fill effect on grass and is unaffected, but its absolute numbers carry the missing
trunks. The pre-fix export is kept beside the level as
`map.glb.pre-trunkfix-2026-09-18`.

### Final assets vs. original export, same session (2026-09-18)

The like-for-like number for the finished catalog work (rocks to 300, trunks pruned and
clamped, the three 99-card grass clumps thinned), against the untouched export from the
same morning, in ONE session: final map loaded first, original swapped in and reloaded
with R, final swapped back and reloaded, 24M budget applied through a probe after each
load so every instance is drawn, 1920x1080, vsync off, GPU idle beforehand.

| Pose | Original export | Final export (A, then A again) |
| --- | --- | --- |
| Home (zoom 13.85) | 10.63 ms, 24.5M prims, 13.3M visible, 11.2M shadow | 8.06 / 8.10 ms, 11.3M prims, 6.6M visible, 4.7M shadow |
| Grass field (12, 0, 16) | 10.22 ms, 27.2M prims, 13.1M visible, 14.2M shadow | 7.26 / 7.28 ms, 11.9M prims, 6.0M visible, 5.9M shadow |

**-2.5 ms at Home (-24%) and -2.9 ms at the grass field (-29%)**, with the two final-map
legs agreeing within 0.04 ms, so none of it is drift. Identical instance sets in every
row (52,154), so the difference is the assets alone. At the default 8M budget the final
map now shows about 90% of its instances instead of 42%, so a player on defaults sees
denser foliage at a similar frame time rather than the same foliage faster.

## Grass card thinning in the asset catalog (2026-09-18)

Follow-up to the decimation above, aimed at fill rather than primitives. Measured from
the glb's real triangle areas, Sandy Clearing's grass amounted to 63 "layers" of
alpha-tested card area per unit of ground, and three species (`FP_Grass_043/044/045`,
99 single-quad cards per clump, ~1,400 instances each at 2x scale) were 33 of those
layers from 12% of the grass instances. terrain-paint's catalog tool gained
`--max-cards`, which keeps an evenly spaced subset of a clump's cards; those three
species went 99 -> 33 cards, the map's grass card area 63 -> 42 layers, and scatter
primitives 9.47M -> 8.91M. Same measurement setup as the section above (one session,
old/new `map.glb` swapped and reloaded with R, 1920x1080, vsync off, 24M budget applied
through a probe so every instance is drawn), A/B/A order, plus a second pose focused on
the grass field at (12, 0, 16):

| Pose | Map | frame_ms | visible primitives | shadow primitives |
| --- | --- | --- | --- | --- |
| Home (zoom 13.85) | pre-thin | 8.98 | 6,527,062 | 4,245,698 |
| Home | thinned | 7.85 then 7.86 | 6,116,410 | 4,245,698 |
| Grass field (zoom 13.85) | pre-thin | 8.12 | 4,295,662 | 5,199,686 |
| Grass field | thinned | 6.95 then 6.94 | 4,016,614 | 5,199,686 |

**1.1 to 1.2 ms faster at both poses (-13% / -14%)** for a 6% drop in visible
primitives, which is the fill signature: the saving is card area, not geometry. Grass
already casts no shadows, so shadow primitives are byte-identical. Screenshots at the
grass-field pose before and after are near-identical at play zoom; the thinned clumps
read very slightly sparser. `FP_Grass_039` (50 cards) is the next candidate if grass
fill needs to come down further. The pre-thin export is kept beside the level as
`map.glb.pre-thin-2026-09-18`.

Two observations from this session that are not about the assets:
- The first attempt hung the game: ~26 s into logging at the Home pose, the process
  stopped responding to Windows messages and to the bridge, spun two cores with the GPU
  at 0%, and the perf log stopped. No error was printed. Killed and relaunched, the
  identical map, pose and budget then ran clean for 90 s at the default budget, 90 s at
  24M, and through the whole A/B/A after that. Not reproduced, so not diagnosed; noted
  here so a second occurrence is recognised as a pattern rather than a one-off.
- After an R reload in `test_play_level.tscn`, the default-budget density came up lower
  than on the initial load (3.6M visible primitives at the Home pose after reload vs
  5.5M on first load, same map, same budget), for both maps alike. It did not affect
  the 24M comparisons above, which re-apply the budget explicitly, but it means
  default-budget numbers taken after an R reload are not comparable with first-load
  ones.

## Authored scatter rebuilds (2026-09-26)

`AuthoredScatter` rebuilds single 10 m cells while a brush paints (see
`docs/ARCHITECTURE.md` "Authored scatter"). Measured on temperate forest, the densest
biome, on a 200 ft map; CPU numbers headless unless marked, render numbers from a real
Vulkan window while another application held the GPU at 80-99% (so frame times are not
usable, and the GPU figure is an in-run ratio, not an absolute).

| What | Cost |
| --- | --- |
| Worker: regenerate one fully painted cell, all species (`ScatterRegen.run`, 790-850 rows) | 48-57 ms, one thread (T2 measured about 36 ms on a quieter machine) |
| Worker: one halo-only cell (relation species only) | 2-7 ms |
| Four-cell dab (radius 3.5 m at a cell corner) | 16 one-cell jobs, 360-400 ms serial; at most 4 run at once |
| Main thread: apply one dense cell (821 rows) into a fully painted map, with grow-in split | 2.5-3.8 ms |
| Main thread: full budget re-plan over the map (999 nodes), skipped while under budget | 5.9 ms |
| Main thread: `build_all` of the whole painted map (30,763 rows, 999 nodes), species resolved | 95-100 ms (real render and headless alike) |
| Main thread: resolve one species after its scene loaded (duplicate + wind material) | up to 10 ms (resolved one per frame) |
| Main thread: resolve a whole biome synchronously, cold (25 asset GLBs) | 0.9-2.1 s (real render; why species load on threads) |
| End to end, real render, species warm: four-cell dab request -> first cell applied / last / grown in | 20 ms / 155 ms / 373 ms |
| End to end, real render, first dab right after the biome is registered (loads in flight) | first apply 254 ms, settled 1.25 s |
| GPU: `grow` instance uniform in the wind shader, fully painted map, interleaved A/B (n=145 each) | 5.079 ms with, 5.109 ms without: no measurable cost |

The main-thread apply stays a few milliseconds because only the rebuilt cells' nodes are
built and the density budget is re-planned map-wide only when the map is (or becomes) over
budget; `FoliageBudget.plan` thins every species by one ratio, so over budget there is no
cheaper correct update than the full re-plan. A cell painted exactly edge to edge also
regenerates its eight neighbours in full: their instances within one sample step of the
edge read the repainted samples through the bilinear lookup. A brush dab rarely lines up
with cell edges, so this only matters for rectangular fills.

Refuted while measuring: a fresh MultiMesh filled with `set_instance_transform()` does not
stall on a GPU readback in the real renderer (200 MultiMeshes x 30 instances: 1.7-2.8 ms
per-instance calls, 1.8-3.0 ms through `MultiMesh.buffer`, real render; 0.9-1.4 ms and
1.1 ms headless). An early 7.4 s `build_all` was the probe waiting on 25 threaded GLB loads
it had just started, not the build.

## First-use pipeline compilation in authoring (2026-09-26)

The first forest stroke on a fresh map stalled for three frames. The pipeline monitors
(`Performance.PIPELINE_COMPILATIONS_*`, logged per frame) located it: MESH compilations
jumped 3 -> 21 -> 33 in the frames right after the biome was picked, before any species had
resolved or been drawn. They are load-time compilations: the first palette GLB to load
compiles the pipelines of its imported materials, and all 180 built-in species share the
same 30 (preparing the whole palette afterwards compiled none). SURFACE compilations
(14 -> 26, the wind shader's) followed at the first draw of the new cells.

Fix: authoring loads the whole palette from the moment a map opens
(`AuthoredScatter.prepare_biome()` for every palette biome in
`AuthoringController._open_async`), and the loading screen waits for the first species
(at most 2 s) plus three frames, so the one-time mesh compilations land under it; every
resolved species is drawn once, invisibly, for two frames (`PipelineWarmer`: one instance
at a thousandth of its size just under the ground at the view centre, a real chunk node so
the shadow and cull settings match), which moves the surface compilations to resolve time,
one species per frame. The rest of the palette resolves in about 4 s at one species per
frame with no frame over 25 ms after the first two. Real render, 1920x1080, vsync on, GPU
not contended in these runs (median 14 ms), the same session order for before and after:

| First stroke on a new bare map | Before: worst frames | After: worst frame |
| --- | --- | --- |
| Temperate forest, stroke starts with the pick (worst case) | 115, 46, 49 ms | 23 ms, no compilations |
| Same, Godot shader and pipeline caches disabled via `override.cfg` | 103, 71, 93 ms | 27 ms |
| Alpine meadow right after (pipelines already shared) | 44 ms | 36 ms |
| Opening the map (loading screen up) | not recorded | 130, 36, 50, 103 ms compile frames under the loading screen |

The NVIDIA driver's own shader cache stayed on (it cannot be disabled per process without
touching the user's system), so a first-ever run on a clean machine is slower than the
"caches disabled" row; the earlier ~550 ms report was not reproduced. The alpine stroke's
remaining 36-44 ms frames are species resolution and cell rebuilds, not pipelines.

## First-launch graphics warm-up (2026-09-29)

On a cold shader and pipeline cache (first launch, a new engine, a GPU driver update), a
map's first load compiled the wind, ground and water shaders and their pipelines on the main
thread: single frames of 3.45 s and 4.3 s on Metal, long enough for macOS to mark the window
"Not Responding". Remeasured here (no warm-up, all caches cleared, forest map): 4635.1 and
4574.1 ms worst frame.

The fix is a "Preparing graphics" screen before the title screen (`GraphicsWarmupScreen`,
`Root.State.WARMING_UP`; policy and helpers in `utils/graphics_warmup.gd`). It does the
compile work once, in three phases, each arranged so the main thread never waits on it:

- **COMPILE**: one covered shader per frame, `load()` plus `get_rid()`. Spatial and
  canvas_item shaders start their compile on the WorkerThreadPool; starting all of them in
  one frame cost a 510 ms frame, so it is one per frame. A `texture_blit` shader
  (`texel_copy_blit`) compiles synchronously on whichever thread asks: 475-490 ms of main
  thread in every run, so COMPILE only loads it and the BUILD worker compiles it
  (`GraphicsWarmup.compiles_on_worker`).
- **BUILD**: one `Thread` collects the samples (terrain, water and foliage representatives,
  from the real builders: asset loads and material builds included) and creates a
  RenderingServer mesh for each. `mesh_create_from_surfaces` waits for the mesh's pipelines on
  the calling thread, so those waits happen on the worker.
- **DRAW**: each built sample drawn for a frame, invisibly, in a SubViewport set up like the
  game world (camera, light, environment, MSAA, debanding), through `PipelineWarmer`, which
  covers the draw-time variants. A pipeline is keyed by the framebuffer format as well as the
  shader and vertex layout, hence the matching setup.

**Skip rules** (`GraphicsWarmup.should_run_for`): `--warm-graphics` after `--` forces it.
Otherwise it never runs headless, in the editor binary, or on the Compatibility renderer, and
it runs when the key in `user://graphics_warmup.cfg` differs from `GraphicsWarmup.cache_key()`.
The key hashes the engine version, the rendering method, the OS version, the GPU and (on
Windows and Linux) its driver, and the source of every covered shader and every file it
includes. On macOS Godot reports no driver information; the Metal compiler and its caches
belong to the OS, so the OS version stands in for the driver there, and a macOS update re-runs
the warm-up. On Windows and Linux an OS update also re-runs it, one extra warm-up that costs
time only. A new shader must be listed as
covered or excluded (AGENTS.md "Adding Features", **New shader**; a test enforces it).

### Measured (Apple M1 Max, macOS 26, Godot 4.7.2, Metal 4.0, Forward Mobile)

Vsync on, all caches cleared before each cold run: `user://shader_cache` plus
`com.apple.metal`, `com.apple.metalfe` and `com.apple.gpuarchiver` under
`$(getconf DARWIN_USER_CACHE_DIR)org.godotengine.godot`. Every launch opened a 1280x720 window.
Plain launches stay at that size. The render-job harness (`tools/render_jobs/run.gd`, run with
`--warm-graphics`) resizes the window to 1920x1080 at `RJ| started`, during BUILD. So in harness
runs, COMPILE ran at 1280x720, and DRAW and every map load ran at 1920x1080.

Machine state, all on 2026-09-30 EDT. "In use" means the user was using the machine (video
playback); those runs were taken before 20:30. "Idle" means it was left alone: 20:30-20:46 and
21:10-21:11. "Unrecorded" marks the first runs (19:53-19:57), whose state was not noted and
which are treated as in use. "Instrumented" marks runs with temporary per-frame prints and
timers in the screen (since reverted); they are diagnostics, not budget measurements. Every
number is a worst frame (ms) per run. The budgets were 250 ms per warm-up phase and 600 ms per
map load.

| What | Worst frames (ms) | Machine |
| --- | --- | --- |
| COMPILE, harness, before the fix | 487, 480; instrumented 489, 479 | unrecorded |
| COMPILE, harness | 18, 19, 27, 24, 23, 28 | in use |
| COMPILE, harness | 15, 25, 14, 15, 33, 19, 14, 15, 22, 18, 13, 13 (last 3 with weather disabled) | idle |
| COMPILE, plain launch (no harness) | 1588, 666, 1257 | in use |
| COMPILE, plain launch (no harness) | 888, 942, 1317, 748, 937 | idle |
| First frame, plain launch, warm-up skipped (not forced, editor binary) | 828.4, 808.8 | idle |
| First frame, same timer, warm-up forced | 785.1 | idle |
| BUILD, harness, before | 214, 305; instrumented 565, 400 | unrecorded |
| BUILD, harness | 492, 308, 94 | in use |
| BUILD, harness | 160, 456, 412, 342, 212, 45 | idle |
| BUILD, harness, window resize disabled | 39, 41, 41 | in use |
| BUILD, harness, window resize disabled | 40, 39, 40 | idle |
| BUILD, plain launch (no harness) | 18, 18, 19 | in use |
| BUILD, plain launch (no harness) | 9, 16, 10, 11, 28 | idle |
| DRAW, harness, before | 22, 22; instrumented 24, 24 | unrecorded |
| DRAW, harness | 21-27 (n=18) | in use and idle |
| DRAW, harness, weather warmed (reverted) | 905, 815, 699 | unrecorded |
| load_bare after the warm-up, before | 560.4; instrumented 839.0, 577.2 | unrecorded |
| load_bare after the warm-up | 706.8, 693.2, 739.3, 690.9, 784.8, 677.1 | in use |
| load_bare after the warm-up | 708.5, 706.8, 674.7 | idle |
| load_forest after the warm-up, before | 724.4 | unrecorded |
| load_forest after the warm-up | 768.5, 892.7, 505.0, 898.8, 725.1, 904.5, 800.6 | idle |
| load_forest after the warm-up, weather disabled | 566.6, 681.8, 683.7, 769.8 | idle |
| load_forest after the warm-up, weather warmed (reverted) | 1069.8, 647.2, 646.4 | unrecorded |
| load_forest, no warm-up (cold) | 4635.1, 4574.1 | idle |
| load_bare, warm caches | 422.0 | unrecorded |
| load_bare, warm caches | 418.6, 422.1, 419.8 | idle |
| load_forest, warm caches | 419.4, 419.3, 416.4 | idle |
| load_forest, warm caches, weather disabled | 408.8, 410.6 | idle |

The "first frame" rows come from a scratch SceneTree script, not committed. It loads the main
scene and times every main-loop frame from the first, so the title screen is up when the
warm-up is skipped. Two load_forest runs (800.6, and weather-disabled 769.8) ran their warm-up
in a separate plain launch before the harness load. All the others warmed in the same process.
The 769.8 run's log does not record the weather flag. Its pipeline totals do: 21 surface and 0
draw compiles, the same as both warm runs with weather disabled. Every run with weather on had
2 draw compiles.

The whole warm-up takes 9.7-10.9 s through the harness (n=18; BUILD is almost all of it) and
9.2-12.1 s in a plain launch (n=8).

What the rows mean:

- **COMPILE** met its budget **under the harness only**, once `texel_copy_blit` moved to the
  worker. The worker then spent 700-750 ms on that shader with no main frame over 30 ms. Every
  plain launch, which is what a player gets, misses 250 ms in COMPILE (666-1588 ms in use,
  748-1317 ms idle). The cause is the cold first window frame (below), not shader work.
- **BUILD**'s spike was the harness, not the warm-up. It came right after `RJ| started`, every
  time, which is when `run.gd` resizes the window to 1920x1080 and repositions it, and BUILD
  happens to be running at that moment. With those three lines disabled, BUILD is 39-41 ms; with
  no harness, 9-19 ms. Nothing was changed for it.
- **Quitting during BUILD hung for good** (found while measuring: still alive 60 s after
  `--quit-after`, with the main thread in `pthread_join` and the worker waiting on the
  RenderingServer). The worker's RenderingServer calls wait for the main thread to flush them,
  so `_exit_tree` now calls `RenderingServer.force_sync()` until the thread is done. Such a
  quit now exits. The worker checks for the cancel after the texture_blit compile and between
  samples, but not inside the sample collection itself. A quit in the middle of collecting
  still waits for it to finish: 17 s wall clock for the whole run in the one measured case,
  which was before the post-compile check was added.
- **DRAW** never came near its budget, so the planned mitigation for it was not needed.
- **A plain launch's first window frame costs about 0.8 s on a cold cache, with or without the
  warm-up.** With the warm-up skipped (editor binary, not forced) and every cache cleared,
  frame 1 is 828.4 and 808.8 ms, while the title screen comes up. That frame compiles 1 canvas,
  2 surface and 1 specialization pipeline. The same timer with the warm-up forced gives
  785.1 ms (2 canvas). In a normal launch the warm-up screen's own tracker counts that frame as
  COMPILE's worst (666-1588 ms in use, 748-1317 ms idle; 2 canvas and 2 mesh compiles). With
  the warm-up's 3D viewport disabled it is still 716 and 757 ms (in use; the screen's 2D overlay
  still drew). So the warm-up does not cause it. It is the first draw on a cold Metal cache,
  and it is over 250 ms either way. It hides from the screen's tracker when a SceneTree
  script drives the launch, as the harness and the scratch timer both do. In the forced
  scratch run, the timer saw 785.1 ms in frame 1, but the tracker reported a COMPILE worst of
  33 ms.
- **Map loads after the warm-up miss the 600 ms budget**: 675-785 ms bare and 505-905 ms
  forest, against 4.6 s without the warm-up and a ~420 ms floor with warm caches (that floor is
  the load itself, not compiles). Part of the gap above the floor is attributed. First, the
  weather: `WeatherRenderer` builds rain, snow and wind `GPUParticles3D` on every map load,
  and none of their shaders is warmed. With weather disabled, cold-after-warm-up load_forest is
  566.6-769.8 ms, still over 600 in 3 of 4 runs (warm 408.8, 410.6), and the load adds 3
  `ParticlesShaderRD` entries to `user://shader_cache`. Second, two `SceneForwardMobileShaderRD`
  entries appear even without weather. They are not identified yet (the cache files are
  binary). The rest is spread over the load's first frames: frame 2 is 682 ms cold against
  228 ms warm with only +1 canvas and +2 surface pipelines, so on Metal some of the cost is
  not counted by the pipeline monitors.
- **Warming the weather in DRAW was tried and reverted.** The screen instanced a
  `WeatherRenderer` in `%WarmupViewport`, called `setup()` and `apply_weather()` with rain,
  snow and wind at 1.0, and held DRAW for 8 drawn frames. It did move the weather out of the
  load: the load then added 0 draw compiles, against 2 before. But DRAW gained two main-thread
  frames of 452-905 ms in every run (worst 905, 815, 699 ms; DRAW 1375-1416 ms in total, against
  a 21-27 ms worst before). The load's worst frame did not improve (1069.8, 647.2, 646.4 ms).
  Its time in frames over 100 ms fell from 1583-2037 ms (the idle runs before) to 1151-1368 ms,
  saving 0.4-0.7 s, while DRAW's two stalls cost 1.3-1.4 s. That is a net loss, and it freezes
  a screen that has to stay responsive. The stalls are most likely the particle process shaders
  compiling on the main thread (not confirmed). Building the weather on BUILD's worker was not
  tried. It may not help, because the worker's RenderingServer calls only run when the main
  thread flushes them. The machine state for these 3 runs was not recorded.
- **load_bare before and after the fixes are not an A/B.** The before values (560.4, 577.2,
  plus 839.0 instrumented) and the after values (675-785) come from different sessions with
  different instrumentation and machine load. The ranges overlap, and no in-run A/B was done,
  so they show neither a regression nor an improvement.
- **"7 RIDs of type Texture were leaked"** at exit comes from the harness's map-load runs, on
  `main` as well as on this branch, with the warm-up or without it. It is not from the
  warm-up.

Not measured: an exported build (no export templates installed locally; the skip rules differ
there, since the editor rule no longer applies), Windows and Linux. The relaunch check
(`load_bare` 422.0 ms with the caches kept, no `GraphicsWarmup:` lines) proves the editor-binary
skip only. The marker skip is covered by `test_graphics_warmup.gd` and has not been seen in a
real launch.

## Mobile renderer hang (2026-09-26): one occurrence, not reproduced

macOS runs the Mobile renderer (`rendering_method.macos="mobile"`), so a load that hangs
under `--rendering-method mobile` would hang Mac players. One run did: `dressing_look`
under Mobile on `authoring-phase3` (working tree between 2e0401e and a8ea4bd, shader
include already final) stopped at its first map, a new 200 ft alpine meadow map, after
"Applied map default environment" and before `wait_ready` finished. The process was "Not
Responding" with its CPU time flat at about 20 s for 26 minutes: the main thread was
blocked in a wait (not spinning, not compiling). It survived because stopping the shell
task does not stop Godot on Windows; the render-job watchdog (`hang_s`) now kills such a
run and logs the step it hung in.

It was not reproduced. Same machine, RTX 3080, Mobile, all with plants:

| Branch | Runs | Result |
| --- | --- | --- |
| `authoring-phase3` d8e9064 | about 55 authored map opens (8 biomes, 100 and 200 ft, fresh process and repeated in one process), 9 Blender-map loads in play, 2 opened for dressing; `dressing_look` twice in full; Godot shader and pipeline caches disabled; window minimized during the load; three instances at once; the 2e0401e ground include swapped in | all loaded and drew |
| `main` 18c25b4 (the `testing` build) | 17 authored map opens, 4 Blender-map loads in play, 1 dressing | all loaded and drew |
| `authoring-phase3`, Forward+ | 17 opens, 4 plays, 1 dressing (one run alongside two Mobile runs) | all loaded |

Ruled out by those runs: the wind foliage shaders and `PipelineWarmer` under Mobile
(every run compiles and warms them), cold shader and pipeline caches, the ground shader's
dynamic `layer_count` loops (the P3-4 probe drew them under Mobile), MultiMesh counts at
full 200 ft density, GPU contention between instances. Not ruled out: a rare deadlock
between the main thread and the threaded palette loads (`load_threaded_get` in
`AuthoredScatter`, `WorkerThreadPool` waits) or a driver wait, which the flat CPU time
fits; a stack of the hung process would decide it, and no debugger was on the machine.
Not tested: real Mac hardware (Metal). `jobs/mobile_maps.json` is the regression check.

## In-game authoring: pinned performance pass (2026-09-26)

The pass owed before merging `in-game-authoring`: play-time cost of authored maps against
Blender maps, the ground shader and its parts, brush strokes and regeneration, the
authoring loading screen and palette memory, and load times.

**How.** RTX 3080 idle before the session (4 %, P8, 44 C, only desktop processes). Every
number comes from the render-job harness (`tools/render_jobs/run.gd`, a real 1920x1080
window, viewport 1920x1080 confirmed in every sample) with `override.cfg` pinning the
viewport (`aspect="keep"`, removed by the job at startup), vsync off at runtime
(`vsync_off`) for frame-time windows, default graphics settings (`shadow_quality` at its
default Soft Ultra for the session; the user's own settings file restored afterwards) and
the default 8M foliage budget. The new probe `tools/render_jobs/probes/perf.gd` samples
every frame between `start` and `stop`: wall-clock CPU frame time and the world
viewport's GPU time, reported as n / median / p95 / worst; `info` reads the world
viewport's render info and counts scatter MultiMesh instances; `mem` reads the engine
monitors plus the process working set; `play`, `author` and `dress` time a load. Debug
build. Test levels: `_perf_forest` (temperate forest painted at full density over a
whole 200 ft map, seed 1234, 31,305 rows) and `_perf_densest` (grassland meadow the same
way, 43,433 rows; the densest biome by rows: wetland 39,896, birch 31,894, alpine 30,992,
temperate 31,305, savanna 21,856, boreal 19,413, badlands 8,873); both deleted afterwards.

### Play-time frame time

Each level loaded in one process in the order forest, densest, deciduous, river, then
again in reverse; 8 s windows at the camera home (zoom 13.85) and at max play zoom (20).
GPU ms, median / p95 / worst (n), both rounds:

| Level | Instances (nodes) | Home: draws, prims | Home GPU r1 / r2 | Zoom 20: draws, prims | Zoom 20 GPU r1 / r2 |
| --- | --- | --- | --- | --- | --- |
| `_perf_forest` (authored) | 31,305 (1,015) | 717, 1.79M (shadow 438, 0.58M) | 5.12 / 5.66 / 6.27 (1398); 5.47 / 5.99 / 6.58 (1294) | 1,111, 2.66M (shadow 594, 0.75M) | 6.36 / 6.85 / 7.42 (1134); 6.50 / 7.04 / 7.63 (1104) |
| `_perf_densest` (authored) | 43,433 (1,002) | 595, 3.29M (shadow 146, 0.16M) | 5.32 / 5.82 / 6.44 (1329); 5.34 / 5.92 / 6.49 (1318) | 930, 4.77M (shadow 191, 0.20M) | 6.65 / 7.15 / 7.67 (1082); 6.67 / 7.16 / 7.70 (1075) |
| `deciduous_clusters` (Blender) | 11,267 (469) | 384, 0.81M (shadow 170, 0.49M) | 2.68 / 3.16 / 3.51 (2424); 2.71 / 3.19 / 3.58 (2407) | 559, 1.21M (shadow 227, 0.59M) | 4.36 / 4.85 / 5.46 (1591); 4.42 / 4.90 / 5.53 (1572) |
| `river` (Blender) | no scatter MultiMesh | 22, 46K | 1.24 / 1.67 / 1.86 (4493); 1.25 / 1.68 / 2.02 (4476) | 22, 46K | 0.93 / 0.94 / 0.95 (5517); 0.93 / 0.94 / 0.94 (5484) |

CPU frame time tracks GPU plus about 0.55 ms (forest home 5.67 / 6.21 / 9.03 ms, zoom 20
6.92 / 7.40 / 8.03 ms). Drift between rounds is 0.01-0.06 ms on every level but the forest
at home (+0.36 ms, same geometry), so read the forest's two rounds as its range. Both
authored maps sit under the 8M budget, so every instance is drawn (3.15M and 5.94M
instance primitives).

**Verdict: no authored-map overhead; cost follows content.** A fully painted 200 ft map
carries 2.8x (forest) to 3.9x (grassland) the instances of the Blender deciduous map and
costs about 2x its GPU time at home and 1.5x at zoom 20, i.e. somewhat less per instance.
The heaviest authored case is 6.7 ms GPU at max play zoom, 150 fps with vsync off. The
river level has no MultiMesh scatter, so it is a ground-and-water reference, not like
content.

### Ground shader

A new bare 200 ft map in authoring (grass base, no scatter), all toggles in-run and
interleaved (two repetitions), 5 s windows. The StandardMaterial3D is built from the ground
material's own albedo, normal and ORM textures at the same tile size and set as
`material_override` on the 64 chunks. Biome layers are painted straight into the document
masks and pushed with `update_biome_region`: 1 = the whole map one forest layer, 4 = four
surfaces (forest floor, pine duff, red sand, alpine grass) in quadrants meeting at the view
centre, mix = the four in a 1 m checker at half density (the synthetic worst case), 0 = the
layer count forced to 0 (the bare-map path). Broad edge off = the shader hot-swapped
without its `apply_broad_edge()` call. Two runs of the same job (the StandardMaterial3D and
0-layer rows from the first, the layer and broad-edge rows from the second, whose 0-layer
reading, 2.00 ms home and 2.48 ms zoomed out, matches the first's within 0.02 ms). GPU ms,
median / p95 / worst (n), second repetition of each run (the first repetition ran up to
0.15 ms lower across its rows while clocks settled):

| Configuration | Home (zoom 13.85) | vs L0 | Full authoring zoom-out (52.4) | vs L0 |
| --- | --- | --- | --- | --- |
| StandardMaterial3D ground | 1.46 / 1.95 / 2.13 (2478) | -0.56 ms | 2.18 / 2.67 / 2.84 (1821) | -0.31 ms |
| Ground shader, 0 layers | 2.02 / 2.50 / 2.68 (1921) | -- | 2.49 / 2.98 / 3.46 (1631) | -- |
| 1 layer, whole view | 2.52 / 3.03 / 3.47 (1602) | +0.52 ms | 2.52 / 3.02 / 3.51 (1606) | +0.04 ms |
| 4 layers, quadrants | 2.45 / 2.96 / 3.43 (1637) | +0.45 ms | 2.54 / 3.03 / 3.54 (1599) | +0.05 ms |
| 4 layers, 1 m checker at half density | 3.74 / 4.28 / 4.90 (1140) | +1.74 ms | 3.25 / 3.75 / 4.23 (1294) | +0.77 ms |
| 4 layers quadrants, broad edge off / on | 2.36 / 2.47 (n 1698 / 1634) | broad +0.11 ms | 2.50 / 2.54 (n 1621 / 1593) | broad +0.04 ms |
| checker, broad edge off / on | 3.52 / 3.71 (n 1204 / 1147) | broad +0.19 ms | 3.13 / 3.23 (n 1330 / 1296) | broad +0.10 ms |

The ground shader is **1.38x** a StandardMaterial3D with the same textures at home, +0.56
ms (first repetition 1.31x, +0.43 ms), which confirms T3's ~1.4x on an idle GPU. A painted
layer adds about 0.5 ms at home whether one or four are bound; the checker worst case is
1.9x. The broad edge costs 0.04-0.11 ms on real paint (0.19 ms on the checker): cheap for
what it does to the look, keep. At full zoom-out the whole map is a small part of the
screen, so layers barely register there.

### Ground skirt, and a fix

At home the skirt is off screen (on/off identical within 0.02 ms). At full authoring
zoom-out it covered most of the frame and cost more than the whole map: GPU 2.48 ms with it,
1.24 ms without (three interleaved repetitions each, n about 1,620 and 2,830 per window).
More than half of the ring lies past the noise-stretched fade (alpha exactly 0) and still
ran every texture fetch. **Fix:** under `GROUND_SKIRT` the fragment computes the skirt alpha
first and discards pixels at 0 before any texture work; every fetch after it uses the
explicit gradients taken above it, so no helper lanes are needed. Measured in-run by
hot-swapping the shader, three interleaved repetitions of original / discard / off:

| Skirt at zoom 52.4 | GPU median / p95 / worst (n) |
| --- | --- |
| Original | 2.487 / 2.970 / 3.467 (1622); 2.484 / 2.970 / 3.477 (1622); 2.483 / 2.968 / 3.445 (1630) |
| Discard past the fade | 2.153 / 2.612 / 3.065 (1838); 2.169 / 2.628 / 3.092 (1820); 2.170 / 2.628 / 3.078 (1826) |
| Skirt hidden | 1.232 / 1.664 / 1.741 (2842); 1.247 / 1.677 / 1.752 (2836); 1.242 / 1.666 / 1.771 (2828) |

-0.32 ms, a quarter of the skirt's cost, and the two captures are bit-identical (every
pixel of the raw SubViewport equal). In play (fixed shader, painted forest, zoom 20) the
skirt costs nothing with the camera centred and 0.63 ms (edge, 4.14 vs 3.50 ms) to 0.70 ms
(corner, 3.31 vs 2.61 ms) panned to the map's edge. What remains is the full ground shader
over the faded part of the ring; cheaper shading there would change the look, so it stays.

### Authoring: strokes, regeneration, opening

Zoom 26, vsync off, 4 m brush at 6 m/s along a 156 m serpentine (26 s), each followed by its
regeneration tail (until nothing regenerates or grows). CPU frame time, median / p95 /
worst (n):

| What | CPU frame ms | GPU ms median |
| --- | --- | --- |
| Idle, bare map | 2.84 / 3.34 / 3.89 (1373) | 2.37 |
| Biome stroke (temperate forest) on the bare map | 3.76 / 4.46 / 6.09 (6895) | 3.22 |
| Its regeneration tail | 4.34 / 4.89 / 5.41 (105) | 3.82 |
| Idle, `_perf_forest` opened in authoring | 7.80 / 8.29 / 8.90 (508) | 7.10 |
| Thin stroke over the full forest | 7.51 / 8.18 / 12.32 (3453) | 6.95 |
| Its regeneration tail | 6.87 / 7.52 / 9.67 (62) | 6.29 |
| Biome stroke (grassland) over the full forest | 6.88 / 7.60 / 10.56 (3712) | 6.29 |
| Its regeneration tail | 7.03 / 8.00 / 18.33 (62) | 6.41 |

No stroke frame over 12.3 ms and no tail frame over 18.3 ms: strokes and their
regeneration stay smooth. Whole-map regeneration (a new temperate forest map growing its
starting cover while the palette resolves, vsync on): done 1.05 s after the loading screen
drops, frames 14.7 / 22.1 / 30.3 ms (176).

Opening a new 200 ft map (vsync on): loading screen 1.15-1.37 s over five opens, one frame
of 770-955 ms under it (the first frame of the new GameMap and the palette's shared
pipelines), then all 180 palette species resolve in 2.93-2.94 s at one per frame with no
frame over 30 ms. Opening `_perf_forest` for dressing (vsync off): loading screen 0.73 s,
palette resolved 1.24 s later.

### Memory

Separate processes, readings after the load settled. Static is Godot's allocator, video is
`RENDER_VIDEO_MEM_USED` (textures include render targets and the shadow atlas), working set
and private bytes from the OS:

| State | Static (peak) | Video (textures) | Working set (peak) | Private |
| --- | --- | --- | --- | --- |
| Title, fresh process | 173 MB (185) | 152 MB (92) | 628 MB (632) | 1,306 MB |
| Authoring open, all 180 species resolved | 218 MB (361) | 1,604 MB (1,474) | 897 MB (904) | 2,804 MB |
| Playing `_perf_forest` | 217 MB (481) | 1,481 MB (1,374) | 885 MB (949) | 2,793 MB |
| Playing `deciduous_clusters` | 208 MB (488) | 1,504 MB (1,419) | 778 MB (956) | 2,687 MB |

Resolving the whole palette costs about 100 MB of video memory over playing an authored map
with 25 species, and the same working set: not a concern. The authored map loads with a
lower static peak than the Blender map. Back at the title after any map (authored or
Blender alike) 750-870 MB of video memory stays allocated; not specific to authoring and
not investigated here.

### Load times

From the title, vsync on (as a player loads), first load in a fresh process, then four
warm loads in the same process, interleaved across the four levels:

| Level | Cold | Warm (4) | Worst frame, cold / warm |
| --- | --- | --- | --- |
| `_perf_forest` | 1,780 ms (1,676-1,783 over five fresh processes) | 1,260 / 1,264 / 1,279 / 1,281 ms | 611 / 167-173 ms |
| `_perf_densest` | 1,320 ms (first in process) | 1,307 / 1,318 / 1,320 / 1,346 ms | 250 / 243-248 ms |
| `deciduous_clusters` | 748 ms | 733 / 733 / 736 / 739 ms | 170 / 167-187 ms |
| `river` | 1,971 ms | 1,862 / 1,886 / 1,920 / 1,925 ms | 443 / 246-259 ms |

The one 580-630 ms frame on the first load of a process happens for Blender maps too
(627 ms on deciduous in its own process). Reloading while playing with vsync off takes
447 ms for the forest (356-368 ms deciduous, 1.5 s river), so most of the authored map's
1.27 s from the title is frames waited at 60 Hz: the loader polls threaded loads once per
frame and builds within `MapSourceLoader.FRAME_BUDGET_USEC` (8 ms) per frame, about 66
frames against deciduous's 29. **Verdict:** between the two Blender maps; acceptable. If it
matters later, a larger per-frame budget while the loading screen is up would cut roughly
0.3-0.5 s (not tried: it trades loading-screen smoothness and needs an A/B across runs).

## Sculpting (2026-09-26, P3-3a)

The height pipeline behind the Sculpt tool (no UI yet; see `docs/ARCHITECTURE.md`
"Authored terrain" and "Authoring Flow"). **How:** the render-job harness
(`tools/render_jobs/jobs/sculpt_pipeline.json`, probe `probes/sculpt.gd`), a real
1920x1080 window with a 1920x1080 viewport, vsync off, debug build, strokes driven through
`AuthoringEditor` over real frames on a new 200 ft temperate forest map (seed 1234, its
starting cover: 8.5k rows, the densest 10 m cell 424). The GPU was not checked for other
load, so absolute frame times are indicative; every comparison below was made in one run.
Frame times are CPU wall clock between frames; the per-part numbers are
`AuthoringEditor.last_*_usec`.

**Terrain: in place, not rebuilt.** 9 chunks under a 12 m brush, every sample nudged,
alternating one per frame (12 each, one run):

| Update | Call, median / p95 | Frame it lands in, median |
| --- | --- | --- |
| `rebuild_chunks` (new ArrayMesh per chunk) | 7.10 / 7.33 ms | 13.89 ms |
| In place (`queue_heights` + `process_heights`, `surface_update_vertex_region` of the edited rows) | 5.03 / 5.11 ms | 11.74 ms |

A 12 m brush covers whole chunks, so that is the smallest gain; the in-place cost follows
the edited samples (about 0.5 us each, normals and tangent included), a rebuild the chunks
touched (0.8 ms each). Per-frame terrain part during strokes, median: 3 m flatten 0.40 ms,
4 m raise 0.63 ms (rebuild: about 3.2 ms for its 4 chunks), 5 m 0.91 ms, 6 m smooth 1.20
ms, 8 m 2.33 ms, 12 m 4.26 ms (the 4 ms budget; the rest carries to the next frame). A 5 m
stroke on the map edge costs 3.95 ms instead of 0.91: the skirt refresh rebuilds the whole
ring every frame (about 3 ms, `build_skirt_arrays`); an in-place ring update would remove
it if edge sculpting turns out common.

**Collision: not per frame.** In the running game (not headless, where the same update is
0.4 ms):

| What | Median |
| --- | --- |
| `update_collision()`: the whole 245 x 245 `HeightMapShape3D` | 2.30 ms |
| One 41 x 41 chunk-sized shape on its own body (probe) | 0.07 ms |
| Per-chunk shapes, 64 in one body: the chunks under a 4 m / 8 m / 12 m brush | 1.86 / 3.89 / 3.89 ms |
| Per-chunk shapes, one body per chunk: same | 1.85 / 3.78 / 3.79 ms |
| `TerrainMeshBuilder.raycast` (CPU walk of the triangles), camera rays | 0.02 ms; 0.08-0.23 ms per stroke frame |

Per-chunk collision was rejected: an edited chunk cost about 0.45 ms whichever way the
shapes were grouped (six times the lone test shape; not explained further). The brush's
ray marches the document instead and agrees with the physics ray (200 random rays: same
point within 5 mm, same facet normal); the collision is rebuilt once when the stroke ends,
inside `end_stroke` (2.9-3.8 ms for 3-8 m strokes, 9.5 ms for 12 m, which also finishes
the leftover terrain and snapping work).

**Plants and props on the moving ground.** Snapping the densest cell (424 rows, every row
moved: Y, and the arc turn of normal-aligned species) takes 2.1 ms, about 5 us per row
with the transform upload (`move_rows`, no rebuild). Per stroke frame, median / p95: 4 m
1.22 / 1.68 ms (103 rows), 8 m 1.33 / 1.41 ms, 12 m 2.73 / 3.65 ms (352 rows; the 2.5 ms
budget, at least one cell per frame).

**Strokes.** Frame time median / p95 / worst (n), and the whole `flush()` median:

| Stroke | Frames | flush |
| --- | --- | --- |
| Raise, 4 m brush at 6 m/s, 43 m serpentine | 3.29 / 3.81 / 7.23 ms (2592) | 1.88 ms |
| Raise, 12 m brush at 4 m/s, 44 m | 11.60 / 12.70 / 15.88 ms (921) | 7.13 ms |
| Raise, 8 m, a 7 m hill (a capture fell mid-stroke) | 6.45 / 6.73 ms (720) | 3.73 ms |
| Lower, 5 m, a 3.5 m hollow | 3.95 / 5.51 / 7.67 ms (518) | 1.46 ms |
| Smooth, 6 m | 5.00 / 5.29 / 5.77 ms (1224) | 2.04 ms |
| Flatten, 3 m | 4.25 / 5.53 / 5.94 ms (623) | 0.78 ms |
| Tier stub, 5 m | 4.95 / 5.33 / 6.84 ms (605) | 2.56 ms |
| Raise, 5 m on the map edge (skirt refresh) | 7.63 / 8.01 / 9.09 ms (392) | 5.72 ms |

**Worst stroke frame: 15.88 ms** (12 m brush over the forest): dab 2.79, terrain 4.01 (16
chunks), snap 2.82 (350 rows), ray 0.14 ms, collision 0; the rest is the frame itself
(the forest renders in about 2-4 ms here). With the collision in the frame the same stroke
ran 13.4 ms median, 14.8 ms p95 (whole map rebuilt every frame, 2.4 ms) and 15.5 ms
median, 18.8 ms worst (per-chunk shapes, 4.3 ms). A capture during
a stroke costs about 1 s (the PNG save) and lands in that stroke's worst frame, so the
job measures strokes without one.

**Regeneration after a stroke** (reach + 2 steps, on workers): every stroke grew exactly
the instances it added and shrank exactly those it removed (the 7 m hill: 10 removed by
the slope rule, 0 regrown; smooth: 6 added; the tier stub: 31 removed), so no unchanged
plant pops. Tail frames median 2-5 ms, worst 20-27 ms for 3-8 m strokes and 38.7 ms after
the 12 m one (its 16 regenerated cells landing: the existing per-cell apply cost, see
"Authored scatter rebuilds").

**Camera.** Raising the ground top by 8 m used to move the picture 130 px at the home zoom
(69 px at zoom 26) because the near-plane guard scaled the camera's base offset, which is
not its view axis; it now moves back along the view axis: 0 px.

## Ground shader: 8 layers, rules, steep faces (2026-09-26, P3-4)

The layer table (8 slots), the automatic cliff and scree rules and the side projections on
steep faces (`docs/ARCHITECTURE.md` "Authored terrain"). **How:** render-job harness,
`jobs/perf_ground_layers.json` with the probes `ground_perf.gd` and `perf.gd`: 1920x1080
window, viewport pinned by a temporary `override.cfg` (removed by the job), vsync off, home
view (zoom 13.85), a new bare 200 ft map (no scatter), every configuration interleaved in
one run, 4 s windows, two repetitions. `std` is the StandardMaterial3D ground with the
base surface's textures (the reference: 0.84-0.95 ms in every window of the run, so no
drift), `old` the ground shader before P3-4 hot-swapped in (it reads none of the new
uniforms and draws the base alone), `new` the current shader. RTX 3080; the GPU was not
checked for other load beyond the stable reference. GPU ms, median of each window:

| Scene | std | old | new | new - old |
| --- | --- | --- | --- | --- |
| Flat bare map (0 layers on screen) | 0.84 / 0.92 | 1.40 / 1.44 | 1.67 / 1.69 | +0.26 ms |
| 4 biome grounds in quadrants (4 layers) | 0.91 / 0.94 | (1.40, base only) | 2.40 / 2.43 | +0.73 over flat |
| 8 painted surfaces in 3 m strips (8 layers) | 0.91 / 0.93 | | 2.13 / 2.14 | +0.46 over flat |
| 8 painted, 1 m checker at half weight over 4 biomes (worst) | 0.93 / 0.94 | | 3.24 / 3.25 | +1.57 over flat |
| 6 concentric tiers, 48 % of ground rays steeper than the side threshold | 0.93 / 0.95 | 1.53 / 1.55 | 2.25 / 2.26 | +0.72 ms |

**The trade.** The fixed cost of the machinery (rule check, per-vertex fields, the 8-slot
blend) is +0.26 ms at 1080p on flat, unpainted ground, the ground shader going from 1.6x to
1.9x the StandardMaterial3D. Real paint costs what the old shader's layers cost (a layer
present at a pixel costs its own fetches; the old 4-layer shader measured +0.45-0.52 ms for
1-4 layers in the pinned pass above). Cliff faces cost +0.72 ms when they fill half the
screen, which no real map does at the game camera; a typical tier or hill is a few percent
of the pixels. What that buys: rock faces with level beds instead of 4x stretched streaks,
scree, lips, and paint over all of it, with no toggle. Kept.

**What was measured on the way.** The first version stored all nine surface samples per
pixel (plus three per-projection samples each, and a large projection struct), as the
4-layer shader stored five: flat 2.26-2.31 ms (+0.85 over old), 4 layers 3.0, the checker
4.3-4.4, terraces 2.54. Register pressure, not fetches, since flat ground samples one
surface either way. The fix: a single-surface fast path, two passes for blends (heights
only to find the top score, then full samples of the surfaces in the band accumulated
directly), side-plane frames built lazily, and constant-index rule routing (a dynamically
indexed local array spills). Flat 1.76, 4 layers 2.46, checker 3.32, terraces 2.33. Then the
slot loops bounded by the `layer_count` uniform instead of unrolled to 8
(`SLOT_LOOP_END`; the sampler array index stays dynamically uniform): flat -0.02 to -0.07
ms, terraces -0.1, the rest equal (`jobs/perf_ground_ab.json`, `ground_perf.gd variant`).

**Sculpting with the rule fields and the sloped skirt** (`jobs/sculpt_pipeline.json`, same
procedure as "Sculpting" below; CPU frame time median, strokes as there). Recomputing the
curvature and steepness fields on every dab (a box mean 1.5 m around each dab rect) put 5-10
ms into each stroke frame (8 m hill 13.2 ms, 12 m 21.8), and the skirt, now 9 rings, cost
about 11 ms to rebuild per frame of an edge stroke (edge 5 m 19.7 ms). Now the fields are
recomputed once in `settle_heights()` (stroke end, undo, cancel) and the skirt is updated in
place for the boundary samples touched: 8 m hill 6.46 ms, 5 m hollow 3.98, 6 m smooth
4.94, 3 m flatten 4.04, 5 m tier stub 4.74, 5 m on the map edge 6.45 (terrain part 2.63),
continuous 4 m 3.63 (P3-3a: 3.3), continuous 12 m 11.89 (worst 32.9: the first edit of
the edge builds the skirt's vertex copy, about 20 ms, once per map). `end_stroke` now
carries the field pass: 6-20 ms for 3-8 m strokes, 44 ms after a 43 m long 12 m stroke; the
settling rebuild of the chunks it changed then spreads over the following frames within the
4 ms budget. Mid-stroke the cliff follows the live normals; scree and lip appear at the
settle, with the regenerated plants.

## Ground accents (2026-09-27)

Setup: RTX 3080, GPU checked idle first (`nvidia-smi`: 0 %, P8, 40 C), 1920x1080 window and
SubViewport through the render harness, vsync off, world-viewport GPU time
(`gpu` op, 3 s per sample, medians), in-run interleaved. A new 150 ft temperate forest map
(seed 1234) at the home view with two accents injected into the palette (moss 0.22 at 7 m,
grass 0.14 at 5 m; palette v5 was not installed yet), toggled with `accent_components` 0 / on
(scratchpad jobs `p37d/accents_perf*.json`).

| Configuration | Off (ms) | On (ms) | Delta |
|---|---|---|---|
| Home view with plants | 2.69 / 2.86 | 3.14 / 3.25 | +0.45 / +0.38 |
| Home view, scatter hidden (bare full-screen ground) | 2.03 / 2.07 | 2.61 / 2.63 | +0.58 / +0.56 |

- The shader with accents off costs what the pre-accent shader did (bare view 2.031 against
  2.034 for the previous commit's include swapped in, `ground_perf.gd shader`, second pair;
  the first pair sat in warm-up drift): nothing is paid until a biome lists accents.
- Most of the cost is drawing a second surface where patches meet the ground (the two-pass
  height blend at every edge pixel), not the mask: a variant whose mask draws a coarser
  pattern with more edge (one fetch, 50 % coverage) cost more (+0.73 / +0.75), and one whose
  loop runs without the mask (`share = 0`) cost +0.05.
- The noise was first the ground's hashed `value_noise` (four pcg2d hashes per octave):
  +0.68 / +0.64 / +0.65 on the bare view. The 32 x 32 lattice texture read with one bilinear
  fetch per octave took it to +0.56 / +0.58. Fetching all three octaves unconditionally
  instead of skipping the finer ones where the result is already decided measured the same
  or slightly slower (+0.60 / +0.60), so the early-outs stay. Dynamic indexing of the
  per-component weights was checked too (a constant-index variant: same cost).

## In-game authoring phase 3: pinned performance pass (2026-09-27)

The phase 3 pass: authored maps with relief in play, the ground shader with the whole phase 3
feature set on screen, Sculpt and Paint strokes and their stroke-end work, and loading and
memory for a relief map against a flat one.

**How.** RTX 3080 checked idle before every job (`nvidia-smi`: 17 %, P8, 39-43 C, desktop
processes only). Render-job harness (`tools/render_jobs/run.gd`, a real 1920x1080 window,
viewport 1920x1080 in every sample) with `override.cfg` pinning the viewport (removed by each
job at startup), vsync off at runtime (`vsync_off`) for frame-time windows and on for load
times, the user's graphics settings unchanged (shadow quality 2, SSAO on, 8M foliage budget),
debug build. `perf.gd` samples every frame (CPU wall clock, world-viewport GPU time) and
reports median / p95 / worst (n). Test levels built with the real Sculpt and Paint tools at
human speed exactly as `jobs/phase3_judgment_set.json` builds them (150 ft, seed 1234: a
raised hill, a two-tier plateau with a Shift-smoothed ramp, a sunken hollow cut with Ctrl, a
track up the ramp in the biome's first path surface, a stone path across a tier edge and a
courtyard on the top tier, three props) and saved: `_p39_forest` (temperate forest, 4,503
instances in 515 nodes) and `_p39_badlands` (rocky badlands, 1,363 in 381); and flat twins,
`_p39_forest_flat` (4,689 in 527) and `_p39_badlands_flat` (1,418 in 386): the same new map,
paint and props with no sculpting. All four deleted afterwards. Jobs in the session
scratchpad (`p39/*.json`); `probes/sculpt.gd` now also reports end_stroke and the stroke's
tail by part.

### Play-time frame time

Each level played in one process in the order forest, forest flat, badlands, badlands flat,
deciduous, then in reverse; 8 s windows at the camera home (zoom 13.85) and at max play zoom
(20). GPU ms, median / p95 / worst (n), both rounds; CPU frame median:

| Level | Home: draws, prims (shadow) | Home GPU r1 / r2 | CPU | Zoom 20: draws, prims (shadow) | Zoom 20 GPU r1 / r2 | CPU |
| --- | --- | --- | --- | --- | --- | --- |
| `_p39_forest` (relief) | 491, 426K (217, 262K) | 3.17 / 3.76 / 4.14 (2088); 3.57 / 3.83 / 4.22 (1961) | 3.80 / 4.15 | 675, 574K (269, 299K) | 3.90 / 4.28 / 4.57 (1841); 3.93 / 4.31 / 4.63 (1817) | 4.39 / 4.45 |
| `_p39_forest_flat` | 512, 477K (219, 257K) | 3.81 / 4.21 / 4.49 (1875); 3.84 / 4.25 / 4.54 (1869) | 4.32 / 4.34 | 700, 632K (274, 294K) | 4.04 / 4.44 / 4.70 (1770); 4.08 / 4.48 / 4.76 (1755) | 4.57 / 4.62 |
| `_p39_badlands` (relief) | 233, 264K (129, 290K) | 2.83 / 3.41 / 3.77 (2234); 2.85 / 3.43 / 3.89 (2222) | 3.52 / 3.54 | 336, 348K (171, 360K) | 2.78 / 3.33 / 3.73 (2269); 2.80 / 3.36 / 3.71 (2251) | 3.46 / 3.50 |
| `_p39_badlands_flat` | 236, 270K (119, 253K) | 2.60 / 3.26 / 3.54 (2390); 2.63 / 3.27 / 3.55 (2373) | 3.22 / 3.25 | 342, 365K (162, 330K) | 2.50 / 3.04 / 3.41 (2465); 2.53 / 3.10 / 3.51 (2445) | 3.11 / 3.14 |
| `deciduous_clusters` (Blender, 11,267 instances) | 384, 805K (170, 486K) | 2.17 / 2.69 / 3.13 (2768); 2.19 / 2.72 / 3.13 (2755) | 2.72 / 2.74 | 559, 1.21M (227, 593K) | 4.06 / 4.47 / 4.75 (1755); 4.15 / 4.53 / 4.82 (1731) | 4.61 / 4.67 |

Drift between rounds is +0.02 to +0.09 ms everywhere except the relief forest at home (+0.40
ms, identical draws and primitives), the same pattern as the phase 2 pass's forest at home;
read its two rounds as its range.

**Verdict: relief costs little, and cost still follows content.** The badlands relief map is
+0.23 ms at home and +0.28 ms at zoom 20 over its flat twin while drawing 4 % fewer
instances: that is the ground shader's rock faces, scree and lips (below). The forest relief
map is cheaper than its flat twin (-0.27 to -0.64 ms at home, -0.14 at zoom 20): the face
and footing rules keep large trees off the tier faces and rims (186 fewer instances, 51K
fewer primitives at home), so the canopy fill that dominates a forest frame goes down. The
heaviest authored case here is 4.1 ms GPU median at zoom 20 (245 fps). Against phase 2: these 150 ft
judgment maps carry 4.5K and 1.4K instances where phase 2's fully painted 200 ft maps
carried 31K to 43K (6.4-6.7 ms at zoom 20 in that session), so absolute times are not
comparable; `deciduous_clusters` is the cross-session anchor and ran 5-19 % faster in this
session (2.17-2.19 against 2.68-2.71 ms at home, 4.06-4.15 against 4.36-4.42 at zoom 20).
Per instance an authored map costs more than the Blender map at home (the relief forest at
3.2-3.6 ms for 4.5K instances against deciduous at 2.2 ms for 11.3K): most of that is the
ground shader, which on these lightly scattered maps is the largest single cost.

### Ground shader

The relief maps opened in authoring, all configurations interleaved in one run, two
repetitions, 4 s windows. Views: the plateau (home zoom looking at the two tiers, courtyard,
track and ramp: 14.7 % of the ground rays steeper than the side-projection threshold), the
flat view (home zoom on the map's south-east corner: accents, biome ground, a tier face at
the top edge and the skirt; 11.0 % steep) and the whole map at zoom 20 (10.1 %). `std` is the
StandardMaterial3D ground with the base surface's textures (`perf.gd ground_std`), `old` the
ground include from before P3-4 (`user://p34_old_ground.zip`: phase 2's shader, which reads
none of the phase 3 uniforms and draws the base surface alone), `new` the current shader;
`bare` hides the scatter. GPU ms, median of each window, rep 1 / rep 2 (n about 2,300-2,600
std, 1,700-1,800 old, 1,000-1,300 new):

| Map, view | bare std | bare old | bare new | new - old | full frame old / new | new - old |
| --- | --- | --- | --- | --- | --- | --- |
| Forest, plateau | 0.98 / 1.05 | 1.64 / 1.66 | 3.12 / 3.44 | +1.48 / +1.78 | 2.15 / 3.74; 2.16 / 3.78 | +1.59 / +1.62 |
| Forest, flat view | 1.16 / 1.17 | 1.61 / 1.60 | 2.58 / 2.59 | +0.98 / +0.99 | 2.05 / 2.81; 2.05 / 2.81 | +0.76 |
| Forest, zoom 20 | 1.11 / 1.13 | 1.59 / 1.60 | 2.97 / 2.97 | +1.39 / +1.37 | 2.60 / 3.86; 2.60 / 3.87 | +1.26 / +1.27 |
| Badlands, plateau | 1.03 / 1.05 | 1.66 / 1.68 | 2.97 / 2.97 | +1.30 / +1.30 | 1.67 / 2.91; 1.68 / 2.91 | +1.24 / +1.23 |
| Badlands, flat view | 1.12 / 1.14 | 1.57 / 1.57 | 2.54 / 2.41 | +0.97 / +0.84 | 1.57 / 2.36; 1.59 / 2.38 | +0.79 |
| Badlands, zoom 20 | 1.11 / 1.12 | 1.57 / 1.58 | 2.83 / 2.84 | +1.26 / +1.26 | 1.69 / 2.86; 1.69 / 2.85 | +1.17 / +1.16 |

Where the phase 3 part goes, plateau view, scatter hidden, a second run (`ground_perf.gd
variant`: accents off = the accent loop compiled out, sides off = the side projections'
weight forced to 0; both change the look, they only attribute the cost):

| Map | new | accents off | sides off | both off | old |
| --- | --- | --- | --- | --- | --- |
| Forest | 2.96 / 3.14 | 2.55 / 2.65 | 2.77 / 2.82 | 2.44 / 2.48 | 1.66 / 1.66 |
| Badlands | 2.95 / 2.97 | 2.59 / 2.60 | 2.65 / 2.67 | 2.44 / 2.42 | 1.66 / 1.66 |

Against phase 2's numbers: its pinned pass measured the base-only shader at std +0.56 ms at
home and a painted biome layer at +0.45-0.52 ms more; here the base-only shader is std
+0.43-0.66 ms (the same) and the full phase 3 ground is old +0.84-0.99 ms on a mostly flat
view and +1.26-1.78 ms on relief, so phase 3 adds roughly +0.3-0.5 ms over a phase 2 painted
map where the ground is flat and +0.8-1.3 ms where tiers fill the view. On the plateau that
extra splits into the ground accents 0.36-0.50 ms (the two-surface blend along patch edges,
see "Ground accents"), the side projections on faces 0.19-0.32 ms (15 % of the pixels), and
about 0.8 ms for the 8-slot table with its biome grounds, the cliff and scree rules, the
painted paths and the broad edge. **Verdict: kept, no fix.** The ground's phase 3 part alone
is 27-43 % of the frame on these lightly scattered maps, but the whole frame stays under 4 ms
at 1080p; no part of it has a
look-neutral saving left (the accent and layer passes were already tuned in P3-4 and the
accents pass). If a lower quality tier is ever needed, accents and side projections are the
two separable costs.

### Authoring: strokes and stroke-end work

The real tools at human speed while building the test levels (150 ft, zoom 20, vsync off;
`record`), CPU frame ms median / worst (n); the stroke's worst frame is its release frame
(end_stroke) unless noted:

| Stroke | Frames | Its tail (regeneration, rocks) |
| --- | --- | --- |
| Forest idle | 3.9 / 4.8 (771) | |
| Forest, Raise hill, 5 m | 4.6 / 10.3 (1011) | 4.4 / 6.2 (162) |
| Forest, Tier, 3.5 m, 36 m path | 4.5 / 22.8 (2838) | 4.4 / 13.0 (204) |
| Forest, Tier on top, 2.2 m | 4.4 / 11.9 (1014) | 4.4 / 6.9 (153) |
| Forest, Shift ramp, 2.5 m | 4.4 / 9.1 (3143) | 4.3 / 6.8 (215) |
| Forest, Ctrl cut tier, 3.5 m | 4.4 / 17.8 (763) | 4.3 / 6.9 (168) |
| Forest, Paint track, 1.3 m | 4.4 / 14.6 (2910), worst at the first dab | 4.3 / 7.4 (225) |
| Forest, Paint path and courtyard, 1.1 / 1.6 m | 4.4 / 12.2 (1445); 4.4 / 7.2 (1547) | 4.4 / 5.7; 4.4 / 6.1 |
| Badlands, Raise hill, 5 m | 3.5 / 9.4 (1317) | 2.8 / 11.2 (324) |
| Badlands, Tier, 3.5 m | 3.1 / 20.7 (4061) | 3.0 / 12.2 (326) |
| Badlands, Paint track, 1.3 m | 3.4 / 13.2 (3575), first dab | 3.3 / 5.4 (185) |

Continuous strokes through `AuthoringEditor` on a new 200 ft temperate forest map (seed 1234,
its starting cover: 8,563 rows) at home zoom (`probes/sculpt.gd`, the same strokes as
"Sculpting" and P3-4). Frames median / p95 / worst (n); end_stroke and its parts (the rest of
end_stroke is the rock keeping's start: two height snapshots and the species lists); the
tail's rock keeping on the main thread:

| Stroke | Frames | end_stroke | Tail |
| --- | --- | --- | --- |
| Raise, 4 m at 6 m/s, 156 m serpentine | 4.06 / 4.55 / 8.05 (2113); flush 1.89 | 19.5 ms: fields 15.2, collision 2.5 | median 4.05 (195); cells applied 39.5 ms in all |
| Raise, 12 m at 4 m/s, 44 m (first stroke reaching the edge) | 11.59 / 12.72 / 65.77 (912); 11.58 / 12.77 / 67.29 (916) | 35.2-55.0 ms: fields 25.1-25.7, terrain 0-21.0 (the last dab's chunks), snap 3.6-5.0, collision 2.4-2.6 | median 3.4-3.6; cells applied 50-53 ms in all |
| Same after the fix below | 11.59 / 12.79 / 20.91 (917) | 56.3 ms (same parts) | median 3.34 |
| Tier, 3.5 m along a 40 m path | 4.17 / 4.65 / 8.92 (3238) | 24.4 ms: fields 7.8, terrain 3.2, snap 2.8, collision 2.4, rock start about 8 | 4 rocks kept (worker 339 ms, main 12.2 ms); 165 instances removed, 2 added |
| Tier stub, 5 m | 4.72 / 5.78 / 10.75 (631) | 12.1 ms: fields 3.4, collision 2.4, snap 1.6, terrain 1.2 | 2 rocks kept (worker 195 ms, main 4.8 ms) |
| Raise hill, 8 m | 6.28 / 6.80 / 7.77 (755) | 10.5 ms: fields 6.4, collision 2.5 | |
| Paint (real tool), 4 m, road / moss | 4.4 / 14.5 (2046); 4.4 / 11.8 (2058) | | 4.4 / 7.0; 4.4 / 5.0 |
| Paint (real tool), 12 m, cobblestone | 10.3 / 22.6 (1039), first dab 18.9 | | 4.0 / 7.1 (356) |

The tail's own worst frame in the `sculpt.gd` rows is the release frame inflated by the
probe (it snapshots every row's key in that frame, 17-20 ms for 8.5K rows); the release
frames measured with the real tool are the ones above: 10-23 ms. Continuous strokes match the
earlier passes (4 m 3.6-4.1 ms, 12 m 11.6-11.9 ms median). **Where stroke-end time goes:**
the rule-field recompute over the stroke's bounding rectangle (3-8 ms for local strokes,
15 ms for a 156 m serpentine, 25 ms for a 12 m brush over half the map), the collision
rebuild (2.4-2.6 ms, every stroke), the last frame's leftover chunks and snapping, and the
rock keeping's start (up to about 8 ms for a long tier through rocks); the rock keeping's
finish (5-12 ms) and the regenerated cells (40-53 ms spread over the tail, no tail frame over
13 ms with the real tool) land over the following frames. The one stroke-end frame over
33 ms is the 12 m brush's (40-60 ms); spreading the field pass over frames would fix it
but is not a small change, so it stays (P3-4 recorded the same, 44 ms).

**Fix: the skirt's vertex copy at open.** The first stroke frame that reached the map edge on
a map built the skirt's CPU vertex copy (`TerrainMeshBuilder.skirt_vertex_mirror`), measured
directly at 45.3-46.6 ms on a 200 ft map (976 boundary samples, 10 rings), and it made the 12
m stroke's worst frame 65.8-67.3 ms (terrain part 58-59 ms). `AuthoringController._install`
now builds it (`AuthoredTerrain.refresh_skirt()` with nothing queued) under the loading screen
for any sculptable map. Same run order, before / after: the first edge stroke's worst frame
67.29 -> 20.91 ms (terrain part 58.94 -> 12.41 ms), medians unchanged (11.58 / 11.59), the
skirt's geometry untouched (the copy is built from the same heights the mesh was); the
loading screen takes the 45 ms instead.

### Load time and memory

From the title, vsync on (as a player loads). One process: the relief forest first (cold),
then three interleaved warm rounds; plus the first load of a fresh process for each level in
its own process (the memory runs):

| Level | Cold, own process | Warm (3) | Worst frame, warm |
| --- | --- | --- | --- |
| `_p39_forest` (relief) | 1,591 ms (1,532 first in the load run) | 1,108 / 1,111 / 1,135 ms | 228-247 ms |
| `_p39_forest_flat` | 1,589 ms | 1,091 / 1,115 / 1,127 ms | 185-271 ms |
| `_p39_badlands` (relief) | 1,471 ms | 952 / 996 / 1,008 ms | 183-245 ms |
| `_p39_badlands_flat` | | 964 / 983 / 997 ms | 233-259 ms |
| `deciduous_clusters` | 1,332 ms | 937 / 967 / 969 ms | 229-258 ms |

Memory after the load settled, one process per level (static is Godot's allocator, video is
`RENDER_VIDEO_MEM_USED`, working set and private bytes from the OS):

| State | Static (peak) | Video (textures) | Working set (peak) | Private |
| --- | --- | --- | --- | --- |
| Title, fresh process | 224 MB (250) | 150 MB (94) | 730 MB (736) | 1,091 MB |
| Playing `_p39_forest` | 255 MB (563) | 1,523 MB (1,403) | 987 MB (1,085) | 2,853 MB |
| Playing `_p39_forest_flat` | 256 MB (535) | 1,523 MB (1,403) | 984 MB (1,058) | 2,911 MB |
| Playing `_p39_badlands` | 252 MB (541) | 1,500 MB (1,380) | 976 MB (1,061) | 2,911 MB |
| Playing `deciduous_clusters` | 258 MB (530) | 1,502 MB (1,420) | 873 MB (1,052) | 2,783 MB |

**Verdict: relief adds nothing measurable to loading or memory** (relief against flat twin:
warm loads within 2 %, video memory identical, static and working set within 3 MB; the
heights were in the document either way). An authored 150 ft map loads in 0.95-1.14 s warm,
0-21 % over the Blender deciduous map in this session (whose warm load took 937-969 ms here
against 733-739 ms in the phase 2 session: cross-session, not a regression finding). The
first load in a process still has one 590-660 ms frame, Blender maps too.

## Known dead ends -- do not revisit without new evidence

- **Uploading scatter MultiMesh transforms through `MultiMesh.buffer`** instead of one
  `set_instance_transform()` per instance (2026-09-15). Headless, timing
  `ScatterGlbUtils.process_scatter_instances` on the real Sandy Clearing map, two process
  launches x five reps each: loop 119.7 ms median, buffer 144.8 ms median, medians
  non-overlapping across both launches (raw samples overlap: loop max 148.3 ms, buffer min
  137.9 ms). Twelve GDScript `PackedFloat32Array` writes per instance cost more than one native call;
  the per-call RenderingServer overhead the idea was meant to avoid is not where the time
  goes. Reverted in cfec47c. If the 52k-instance build ever needs to shrink, move the whole
  build onto the worker thread that already parses the GLB rather than changing the upload.

- **General triangle budgets.** 420x the geometry cost only 9.2x the frame time. Raw
  triangle count is not the binding constraint; foliage instance count is.
- **Terrain decimation.** Terrain not casting shadows saved 0.03 ms. Terrain is free.
- **Distance-based LOD, billboards, impostors keyed on camera distance.** The camera is
  orthographic, so apparent size does not shrink with depth -- degrading distant foliage
  is *more* visible here than in a perspective game. The orthographic-correct
  reformulation would be zoom-based, driven by `camera.size` (zoom-based foliage density
  and orthographic billboards/impostors, tracked as sub-projects C2 and C3). Neither is
  being pursued: chunking delivered the win they were intended to chase -- without the
  visual-fidelity trade either would have required -- and did so most strongly at full
  zoom-out, precisely the regime C2 targeted. Frame time on the reference map is now
  5.27 ms at the Home pose. The remaining open risk this section used to name -- whether
  `FoliageBudget.PRIMITIVE_BUDGET` suits weaker hardware -- is resolved by the per-user
  `graphics/foliage_budget` setting rather than by further validation here (see "The
  foliage primitive budget" above): each player tunes their own value instead of the
  project needing one default to fit every machine.
- **Automatic mesh LOD.** Godot picks one LOD per MultiMesh node, not per instance, and
  orthographic screen coverage does not vary with distance.
- **Occlusion culling.** A `MultiMeshInstance3D` cannot be an occludee in the bake
  workflow, and all foliage here is MultiMesh.
- **PCF shadow filter tuning.** Measured at 0.6 ms. Not worth touching.
- **Shortening `directional_shadow_max_distance`.** Swept 100/50/30 twice, once before
  chunking and once after, and both sweeps found shadow-pass primitives byte-identical
  across all values tested -- 15,586,440 unchunked (pre-chunking build) and 4,421,617
  chunked (30 vs. 100, this session's re-test on the shipped chunk-10 build; frame time
  5.30 ms vs. 5.27 ms, within noise; shadow draw calls 264 in both cases). **Every caster
  really is already inside 30 units, and the lever does nothing. This is now verified
  twice.** An earlier version of this entry hypothesised that the first null result was an
  artefact of unchunked geometry -- one map-wide AABB per species intersecting every
  shadow cascade regardless of distance -- and that chunking would unblock the lever. That
  hypothesis was tested directly and is WRONG, not merely unconfirmed: chunking changed
  nothing about the distance lever's effect. What chunking DOES do -- cut shadow-pass
  primitives 33% (6,591,594 -> 4,421,617 at the Home pose, see "Spatial foliage chunking"
  above) -- is a separate mechanism, frustum culling of whole chunk AABBs out of the
  cascades, and must not be conflated with the distance knob; that reduction happens with
  `directional_shadow_max_distance` untouched. Caveat: the old 15,586,440 figure predates
  the foliage primitive budget (`utils/foliage_budget.gd`), which roughly halved foliage
  primitives in between, so it is NOT directly comparable to the 6,591,594 unchunked figure
  measured here. Recorded in `level_environment_manager.gd`.
- **`alpha_to_coverage` for the shadow pass.** Does not help (godotengine/godot#84242).
- **`visibility_range` to skip distant foliage.** Hidden instances stop casting
  directional shadows entirely (godotengine/godot#98993), which changes lighting.
- **A process-global shader parameter cannot gate per material.** Moving
  `occlusion_token_count` to a global shader parameter left `enable_occlusion` (default
  true) as the only per-material gate, and every grass material the manager never
  registers ran the fade loop unconditionally. Anything that used to rely on a
  per-material default of zero needs an explicit per-material opt-in; fixed in ec2e24e by
  defaulting `enable_occlusion` to false and having `OcclusionFadeManager` set it true on
  every material it converts or registers.

Grass no longer casts shadows (measured -16% of frame time): Godot runs the shadow
pass's `fragment()` with the same code as the colour pass (godot-proposals#4443), and
the foliage shader's alpha-cutout `discard` disables early-Z for that draw, so dense
overlapping grass pays full fragment cost per covered sample. A base-dark/tip-light
albedo gradient in `WindFoliage.apply_material` replaces the contact darkening the real
shadow used to provide.

## How to measure without fooling yourself

Four separate instrument failures produced four wrong conclusions during this work.
All four are avoidable:

1. **Pin the viewport.** `project.godot` sets `window/stretch/aspect="expand"`, so a
   window taller than 16:9 inflates the SubViewport (height = 1920 / window_aspect). A
   0.94-aspect window gave 1920x2043 = 3.92 MP and turned a healthy 58.8 FPS into 3.7.
   Identical primitives and draw calls at both sizes -- the cliff is pure fill cost.
   Always record `viewport_width`/`viewport_height` (CSV columns 20/21) alongside any
   FPS number, and never compare across different viewports.
2. **Disable vsync.** It is on by default, so healthy runs sit at ~17 ms with unknown
   headroom. A comparison at the cap cannot detect a regression, and neither can one at
   a fill-bound floor.
3. **Compare only within a single run.** GPU clock throttling drifts absolute frame
   times badly across a session: the same scene and pose read 1.48x slower after a few
   hours, cleanly multiplicative across three configurations. A cross-run A/B shows
   several ms of pure drift. An unexplained uniform offset across every configuration is
   drift, not a regression -- check that before blaming the change.
4. **Absolute frame times are not comparable across sessions.** The identical shipped
   configuration, same map, same pose, byte-identical geometry (5,242,617 visible
   primitives every time), measured 8.41 ms in one session, 5.27 ms in a later session
   with the GPU verified idle (10% utilisation, 47 C, P8), and 123.98 ms while an
   unrelated game held the GPU at 99% utilisation. The 15x case was caught only because
   the foliage-hidden reference sample also collapsed (2.47 ms -> 59.58 ms) with
   primitive counts unchanged -- a uniform slowdown across all content with identical
   geometry means the device, not the code, changed. Practical rule: check GPU
   utilisation (`nvidia-smi` or equivalent) before measuring, always capture an in-run
   reference configuration, and compare configurations by their delta against that
   reference rather than by absolute milliseconds.

Working procedure. Write an untracked `override.cfg` in the project root (Godot reads it
at runtime and it survives `git checkout`, so both branches measure identically):

```
[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
```

`aspect="keep"` pins the SubViewport regardless of window shape. Disabling vsync must
happen in `user://settings.cfg`, not here: `scenes/root.gd` applies saved graphics
settings at boot and overrides `override.cfg`. **Exception:** `tests/test_play_level.tscn`
never runs `root.gd`, so `user://settings.cfg`'s vsync flag is never applied there --
measuring through that scene needs vsync disabled in `override.cfg` itself, with
`display/window/vsync/vsync_mode=0` added to the `[display]` block above (see "Foliage
backlight (2026-09-16)" for a worked example). Then per run: load the level, press
**Home** for a deterministic camera pose, press **F3** (perf logging only starts when
the overlay is open), wait ~30 s, and read `user://perf_logs/` filtering `elapsed_s > 5`.
Confirm `primitives` and `draw_calls` match between samples before comparing them; if
they differ, the camera differed and the pair is invalid.

The validator bridge can now drive this end to end, including the title-screen navigation
that previously blocked it: `game_state` reports `viewport.window_size`,
`viewport.viewport_size` and `viewport.hovered_control`; and `hovered_control` is how you
confirm a click landed where intended. Prefer `game_click_control`, which targets a named
Control and converts coordinate spaces itself, over raw `game_click`. See `AGENTS.md`'s
Validation Bridge troubleshooting list for the coordinate-space detail rather than
duplicating it here -- an earlier version of this paragraph duplicated it and got it
backwards, which is why it now only points.

Prefer the F3 digit toggles to A/B *inside* one run, then group the CSV by the
`toggle_*` columns -- that is immune to drift. When a change cannot be toggled at
runtime (a const, a project setting, another branch), measure a stable reference
configuration in every run ("foliage hidden" works well) and compare ratios rather than
absolute numbers.

**Delete `override.cfg` and restore `user://settings.cfg` afterwards.** Stop the game as
soon as a measurement finishes -- an idle instance throttles the next run.

Caveats that apply to every number here: these come from a debug build driven through
the validator bridge, not an exported release build, and background `godot --headless`
test runs contend for CPU. Quiesce other work before measuring.

### In-run shader A/B by hot-swapping `Shader.code`

For a shader or material change, the `override.cfg` procedure above still needs a
restart per build and is exposed to clock drift between runs. A handful of
`@run user://*.gd` probes (static `run(base)`, driven through `game_interact`) give a
same-run, same-camera A/B in one batch instead. Used for the water shader rework on
2026-09-23:

- **Hot-swap the shader.** Export the old source with `git show HEAD:shaders/x.gdshader`
  to `user://`, then from a probe set
  `<shared material>.shader.code = FileAccess.get_file_as_string("user://x_old.gdshader")`
  and swap back with the `res://` file. The shared material recompiles in place and global
  uniforms keep working. The first sample after a swap can carry the recompile hitch
  (10 ms seen once), so take a second reading.
- **Vsync and GPU time at runtime.** `DisplayServer.window_set_vsync_mode(VSYNC_DISABLED)`
  and `RenderingServer.viewport_set_measure_render_time(sub.get_viewport_rid(), true)`, then
  read `viewport_get_measured_render_time_gpu(rid)` on the SubViewport. That is a
  single-frame sample, not an average, so read it several times.
- **Quality tiers.** `RenderingServer.global_shader_parameter_set("water_quality_skip_*",
  true)` from a probe flips Low quality without touching Settings.
- **Zoom for fill-cost cases.** `find_child("CameraController", true, false).set("_target_zoom", 7.0)`
  from plain `game_eval`; setting `camera_node.size` directly is overwritten by the
  controller's smoothing.
- Probes live in the user data dir (`%APPDATA%/Godot/app_userdata/TTSim/`), never in the
  repo; delete them afterwards. Alternate old/new at least twice.

## Water flow map (2026-09-23)

The flow-map advection added to `shaders/water.gdshader` (ripples, caustics and foam
now cross-fade two displaced evaluations of each noise field when a plane carries a
baked flow map) needed its GPU cost measured against the pre-change shader across all
three Water Quality tiers, per the "measure, never estimate" rule.

Setup: River level (its `Lake-water` plane carries a flow map) via the validator bridge,
1920x1080 window and viewport (from `game_state`), vsync disabled
(`DisplayServer.window_set_vsync_mode`), zoom 7.0 so the water fills the screen, RTX
3080. `RenderingServer.viewport_get_measured_render_time_gpu()` on the game's single
SubViewport gives the whole viewport's GPU time; with the water filling the screen the
delta between the pre- and post-change shader isolates the water's own cost. The
pre-change shader text was saved to `user://water_before.gdshader`
(`WaterGlbUtils._get_water_material().shader.code` was hot-swapped between it and
`res://shaders/water.gdshader` in place, avoiding a scene reload between samples). Per
tier: two old/new swap pairs, five GPU readings per swap, the first reading after each
swap discarded (it carries the shader recompile hitch), leaving 8 kept readings per
side; the table reports the median of those 8.

| Tier | Old median GPU ms | New median GPU ms | Delta |
| --- | --- | --- | --- |
| High | 1.2135 | 1.3045 | +0.091 ms |
| Medium | 1.2025 | 1.2465 | +0.044 ms |
| Low | 1.1665 | 1.2645 | +0.098 ms |

**Gate: pass on every tier, no code change needed.** `scenes/ui/settings_menu.gd` derives
both `water_quality_skip_*` globals from `quality == WaterQuality.LOW` alone, so Medium
and High run the exact same water shader configuration (the fine-detail octave and
caustics run on both) and only Low skips anything; the default tier is Medium. The
0.044 ms (Medium) vs 0.091 ms (High) spread between two shader-identical configurations
is therefore measurement noise, not a real difference -- both are compared against the
same 0.3 ms threshold. The default tier costs +0.044 ms; quoting the worst-case reading
across tiers, High's +0.091 ms, it is still well inside the threshold, so the
`water_ripple()` coarse-second-phase mitigation described in the flow-map design doc was
not applied. Low reads slightly higher again despite skipping the most code, another
noise-level difference between sampling sessions -- all three deltas are under a tenth
of a millisecond, an order of magnitude under the gate.

## Authored water surface (2026-09-27, P4-2)

The merged authored water mesh (`AuthoredWater`, ARCHITECTURE.md "Authored water at
runtime") over a sculpted authored map in play: its whole GPU cost, water shown against
water hidden in one run.

**How.** RTX 3080 idle before the job (`nvidia-smi`: 1 %, P8, 39 C, 210 MHz). Render-job
harness, 1920x1080 window and viewport, `override.cfg` pinning the viewport (removed by the
job at startup), vsync off (`vsync_off`), debug build, the user's graphics settings
(Water Quality default). Test level `_p42_water` (deleted afterwards): a 200 ft grassland
meadow (10,285 scatter instances) on a slope, a river of three flat reaches (ankle, waist,
deep; 3.6-5.6 m wide), a deep pond (12 m across) and a waist-deep basin, built by
`probes/water.gd build` (10,026 vertices, 18,784 triangles, one flow map of 244 x 244).
`probes/water.gd water` hides and shows every water mesh; `perf.gd start / stop` 4 s windows,
on / off / on / off at each view. GPU ms, median (p95):

| View | Water on #1 | off #1 | on #2 | off #2 | Delta |
| --- | --- | --- | --- | --- | --- |
| Home (zoom 13.85; river and pond in a corner) | 2.90 (3.31) | 2.77 (3.22) | 3.08 (3.53) | 2.81 (3.27) | +0.13 / +0.27 |
| Zoom 9 over the river (water across the screen) | 3.17 (3.88) | 2.80 (3.26) | 3.19 (3.66) | 2.80 (3.27) | +0.38 / +0.39 |
| Zoom 20 (whole map) | 3.70 (4.19) | 3.44 (3.93) | 3.71 (4.55) | 3.45 (3.94) | +0.26 / +0.26 |

**Verdict: kept.** The water costs what its screen coverage costs, as the Blender plane
does: every water pixel pays the shader's depth and screen prepass reads, 0.13-0.27 ms at
home where a corner of the view is water, 0.26 ms for the whole map at zoom 20 and 0.38 ms
with a river across the screen at zoom 9 (the 0.3 ms flow-map gate was for the flow
advection alone, measured above; this is the whole surface). The tucked margin under the
banks costs nothing visible: those fragments fail the depth test before shading. The
per-body collision and zones add no frame cost (static bodies, one Area3D per body). Main
thread outside the frame: the authoring refresh's swap (mesh, concave shapes, zones) took
26 ms; the build (84 ms) and the flow bake (183 ms) run on a worker.

## Water tool: carve on a worker (2026-09-27, P4-4)

Main-thread cost of a water edit, before and after moving its heavy, pure half onto a worker
(`WaterEditor.compute()`; `systems/water.md` Authoring, "Worker carve"). Indicative
render-job numbers (1920x1080 window, vsync on, debug build, not the pinned procedure): the
question is how long the view freezes, not a GPU delta.

**Before (P4-3, synchronous, 200 ft temperate forest map tilted 2.5 %, `WaterEditor.timings`
per part, `probes/water.gd`):**

| Edit | Main thread | Largest parts |
| --- | --- | --- |
| 60 m waist river, 3 reaches | 308 ms | goals 106, dressing 112, terrain work 30, dressing upload 34, settle 20 |
| 25 m deep river, 2 reaches | 274 ms | dressing 165, goals 50, rock rule (sample owners) 34 |
| 4.5 m waist pond | 259 ms | dressing 175, rock rule 41, goals 27 |
| erase across a river | 662 ms | dressing 172, rock rule 37, the rest in the erase's own dabs and cuts |

**After (the Water tool at human speed through the harness, `jobs/water_tool.json`, 150 ft
maps tilted 2 %; `record` around each release; worst frame, median 7.6-8.4 ms):**

| Edit | Grassland | Badlands | Forest |
| --- | --- | --- | --- |
| 45 m waist river (release to landed) | 41.6 ms | 21.0 ms | 27.2 ms |
| ankle stream joining it (drawing and landing) | 23.4 ms | 17.1 ms | 12.2 ms |
| deep pool and a two-stroke pond | 30.3 ms | 17.2 ms | 16.9 ms |
| erase one river | 22.0 ms | 9.8 ms | 9.4 ms |

The river lands over three frames (grassland: 24.7, 22.0 and 41.6 ms): the document and
ground (lower_to, terrain chunks, collision, snap), the terrain settle (rule fields), then the
dressing texture, rocks, regeneration request and history. The 41.6 ms is the first water on
the map: the ground re-plans its layers and refreshes every chunk's weights for the new bed
and shore surfaces, once per map; later edits' last frame is under 25 ms. The water surface's
own swap (26 ms, P4-2) lands a few frames later. Undo and redo no longer recompute the
dressing (it is stored compressed in the entry). A sculpt stroke on a map with water
recomputed the dressing on the main thread at its release (about 110-175 ms on a 200 ft map,
`WaterEditor.refresh`); since P4-5 it runs on the same worker (below).

## In-game authoring phase 4 (water): pinned performance pass (2026-09-27)

The phase 4 pass: authored maps with water in play against the same maps without it, the
water shader's cost with the merged authored mesh, frame times of every water gesture and of
a sculpt stroke by the water, loading and memory.

**How.** RTX 3080 checked idle before each measuring job (`nvidia-smi`: 0-2 %, 48-51 C).
Render-job harness (a real 1920x1080 window, viewport 1920x1080 in every sample),
`override.cfg` pinning the viewport for the play pass (removed by the job at startup), vsync
off at runtime for frame-time windows (`vsync_off`) and on for load times, the user's graphics
settings, debug build. Test levels built with the real tools at human speed as
`jobs/phase4_judgment_set.json` builds them (150 ft, seed 1234, tilted 2 %: a two-step tier, a
winding waist river of 2 reaches, an ankle stream joining it, a deep pool, a pond in two
strokes, a path across the river, three props), each saved twice: before any water
(`_p45_forest_dry`, `_p45_wetland_dry`) and after (`_p45_forest_wet`, `_p45_wetland_wet`:
5 bodies; the wetland's reeds stand in the water). All four deleted afterwards. Jobs in the
session scratchpad (`p45/perf_*.json`, using the harness's new `expand` op over level
folders).

### Play-time frame time

Each level played in one process in the order forest wet, forest dry, wetland wet, wetland
dry, `river` (Blender, read-only), then in reverse; 8 s windows at the camera home (zoom
13.85) and at max play zoom (20). GPU ms, median / p95 (n) round 1; round 2 median:

| Level | Instances (home prims) | Home GPU r1 | r2 | Zoom 20 GPU r1 | r2 |
| --- | --- | --- | --- | --- | --- |
| `_p45_forest_wet` | 4,194 (383K) | 4.56 / 5.67 (1579) | 4.52 | 4.62 / 5.62 (1560) | 4.52 |
| `_p45_forest_dry` | 4,689 (470K) | 3.71 / 5.19 (1703) | 4.25 | 4.37 / 5.45 (1641) | 4.44 |
| `_p45_wetland_wet` | 6,122 (396K) | 3.98 / 5.38 (1614) | 4.48 | 4.82 / 5.76 (1478) | 4.85 |
| `_p45_wetland_dry` | 6,007 (470K) | 4.35 / 4.75 (1661) | 4.33 | 4.78 / 5.76 (1497) | 4.75 |
| `river` (Blender) | 0 scatter (46K) | 0.93 / 1.80 (4782) | | 0.75 / 1.17 (5667) | |

CPU frame medians 4.7-5.6 ms on the authored maps. The GPU series in this session are
bimodal (medians of the same configuration move by up to 0.5 ms between rounds while p95
barely moves), so read each pair of rounds as a range. **Verdict: water costs about what its
pixels cost, and nothing else.** The wet maps draw fewer instances and primitives than their
dry twins (the channels clear plants) and still run 0.1-0.3 ms slower where the rounds agree
(forest zoom 20 +0.08-0.25 ms, wetland zoom 20 +0.04-0.10 ms); every map stays under 4.9 ms
GPU median at max play zoom.

### Water shader with the merged authored mesh

The wet levels in play, every water mesh shown and hidden in one run (`probes/water.gd
water`), on / off / on / off, 4 s windows. GPU median ms:

| Level, view | On #1 | Off #1 | On #2 | Off #2 | Delta |
| --- | --- | --- | --- | --- | --- |
| Forest, home (river, stream, pool, pond in view) | 4.61 | 4.45 | 4.73 | 4.46 | +0.16 / +0.27 |
| Forest, zoom 9 over the river | 4.45 | 4.17 | 4.43 | 4.18 | +0.27 / +0.25 |
| Forest, zoom 20 (whole map) | 4.65 | 4.45 | 4.65 | 4.44 | +0.20 / +0.21 |
| Wetland, zoom 9 over the river | 3.65 | 3.43 | 3.63 | 3.43 | +0.22 / +0.20 |
| Wetland, home | 3.99 | 4.22 | 4.02 | 3.77 | bimodal (means +0.15 / +0.24) |
| Wetland, zoom 20 | 4.35 | 4.74 | 4.42 | 4.70 | bimodal (means +0.09 / +0.08) |

**Verdict: kept.** The whole authored water, flow advection, refraction, the P4-5 refraction
fade and shoreline gate included, is 0.2-0.3 ms at 1080p wherever it is in view, the same as
P4-2 measured before the tool existed (0.13-0.39 ms). The shader's P4-5 additions are a
screen-derivative normal and two smoothsteps per water pixel, with no extra texture reads.

### Authoring: water gestures and sculpt by the water

The real tools at human speed while building the test levels (150 ft, zoom 20, vsync off;
`record` from the press to the landed edit and its regeneration), CPU frame ms median / worst
(n). The worst frame is the landing (P4-4's three-frame land) or the water surface's swap:

| Gesture | Forest | Wetland |
| --- | --- | --- |
| Idle | 5.1 / 9.1 (588) | 5.3 / 6.7 (568) |
| Waist river, 45 m, 2 reaches (the map's first water) | 5.1 / 27.3 (2688) | 5.4 / 29.3 (2575) |
| Ankle stream joining it | 5.2 / 21.4 (1588) | 5.4 / 28.0 (1501) |
| Deep pool | 5.3 / 23.7 (555) | 5.4 / 28.6 (496) |
| Pond in two strokes | 5.3 / 25.5 (1269) | 5.4 / 27.3 (1198) |
| Erase (Ctrl, the stream) | 5.3 / 28.8 (327) | 5.6 / 24.6 (309) |
| Raise stroke on the river's bank (dressing on the worker) | 5.6 / 27.6 (638) | 5.4 / 24.1 (551) |

Sculpt by the water, before / after the P4-5 move (grassland, 150 ft, the same editor with
`use_worker` off and on alternately, Raise and Smooth strokes by the river): worst frame
118.6 / 119.1 ms synchronous, 28.0 / 30.3 ms on the worker, medians 8.0-8.2 ms either way
(vsync on). **No water gesture's frame now exceeds 30 ms**; the medians sit within 0.5 ms of
idle.

### Load time and memory

From the title, vsync on, one process: forest wet first (cold in the process), then three
interleaved warm rounds:

| Level | First in process | Warm (3) | Worst frame, warm |
| --- | --- | --- | --- |
| `_p45_forest_wet` | 1,295 ms | 987 / 964 / 966 ms | 193-194 ms |
| `_p45_forest_dry` | | 707 / 706 / 713 ms | 170-173 ms |
| `_p45_wetland_wet` | | 956 / 962 / 931 ms | 193-196 ms |
| `_p45_wetland_dry` | | 729 / 737 / 723 ms | 168-174 ms |
| `river` (Blender) | | 1,868 / 1,831 / 1,847 ms | 169-177 ms |

Memory after the load settled, one fresh process per level:

| State | Static (peak) | Video (textures) | Working set (peak) | Private |
| --- | --- | --- | --- | --- |
| Title, fresh process | 238 MB (266) | 141 MB (92) | 749 MB (757) | 1,111 MB |
| Playing `_p45_forest_wet` | 271 MB (335) | 1,525 MB (1,403) | 1,027 MB (1,039) | 2,889 MB |
| Playing `_p45_forest_dry` | 269 MB (337) | 1,519 MB (1,398) | 1,012 MB (1,022) | 2,872 MB |
| Playing `_p45_wetland_wet` | 271 MB (343) | 1,511 MB (1,398) | 1,025 MB (1,040) | 2,894 MB |
| Playing `_p45_wetland_dry` | 270 MB (341) | 1,505 MB (1,393) | 1,014 MB (1,028) | 2,883 MB |

**Verdict: water adds about 0.23-0.26 s to a warm load and nothing that matters to memory**
(+1-2 MB static, +5-6 MB video, +11-15 MB working set). The load delta is main-thread work
under the loading screen, two frames of about 100 and 190 ms in the wet loads' tail
(p95 104 ms against 34 ms dry): by the code path, `AuthoredTerrain` computing the wet
dressing (`WaterDressing.refresh`, a derived cache the document never saves; 110-175 ms
measured in authoring) and `AuthoredWater.create` building the merged mesh, collision and
zones synchronously. Not split further here; moving both onto the loader's worker (the
dressing could also ship in the document) is the follow-up if loads matter. An authored
150 ft map with water still loads faster than the Blender `river` level. (Done in P4b-0,
next section.)

## P4b-0: authored map load on workers (2026-09-27)

Profile first, then move. `jobs/p4b_load.json` builds a 150 ft rocky badlands map (seed
1234, tilted 2 %) with the real tools, saves it before any water (`_p4b_dry`) and after a
waist river, an ankle stream, a deep pool and a two-stroke pond (`_p4b_wet`: 5 bodies, 6,677
surface vertices), then from the title runs `probes/p4b.gd load_profile` (each part of the
load's main-thread work on that document, 7 runs, median) and plays wet first (warm-up),
then wet / dry interleaved three times (`perf.gd play`: title to loading screen gone, vsync
on). RTX 3080, 1920x1080 window, debug build, the user's settings; the GPU may have been
shared, but these are CPU-side numbers. Both levels deleted by the job.

**Where the time went (before).** Main thread, one frame each unless noted:

| Part | ms |
| --- | --- |
| `AuthoredTerrain.create` (no chunks), wet map | 224 |
| of it: the wet dressing (`WaterDressing.refresh`) | 114 |
| `AuthoredTerrain.create`, same map without water | 107 |
| of it: skirt arrays 33, rule fields 24, layer plan and weights 8, collision 0.2 | |
| `AuthoredWater.create` | 100 |
| of it: the merged mesh and bodies (`WaterMeshBuilder.build`) | 85 |
| of it: the nodes (surface mesh, collision faces, zones) | 15 |
| flow texture; `process_water_meshes`; the grid's ground field | 0.0; 0.3; 2.6 |
| chunk meshes (arrays and `ArrayMesh`), spread over frames within the 8 ms budget | about 16 |

So water's share was the dressing and the water mesh build, 199 ms of pure data work, plus
15 ms of nodes; the dry terrain spent 57 ms on pure arrays too.

**Change.** `AuthoredLoadPrep` runs the pure parts on worker threads while the ground
textures load (ARCHITECTURE.md Map Loading Flow): the dressing, the water geometry, the rule
fields with every chunk's arrays, and the skirt arrays, one task each; the main thread keeps
node and resource creation (no texture is made on a worker: safe headless too).

**After.** `load_profile`: the workers take 119-121 ms wall (the dressing is the longest
task); the main thread's terrain build is 48 ms (224 before) and the chunks from prepared
arrays add 3 ms for the whole map (16 before); the water's nodes are 14 ms (100 before).

| Warm load from the title | Before (two runs) | After |
| --- | --- | --- |
| `_p4b_wet` | 862 / 855 / 855, 857 / 856 / 859 ms | 692 / 703 / 685 ms |
| `_p4b_dry` | 623 / 656 / 620, 663 / 672 / 648 ms | 588 / 615 / 605 ms |
| Water's share | +210-235 ms | +85-100 ms |
| Load frames p95, wet | 102-114 ms | 21-25 ms |
| Worst load frame, wet / dry | 190-196 / 167-181 ms | 166-174 / 167-169 ms (first wet 214) |

**Verdict: kept.** Water's main-thread load work is down from about 214 ms to 14 ms and its
wall-clock cost from 0.21-0.24 s to 0.09-0.10 s (the rest is the loading screen waiting for
the dressing worker); dry authored maps load 30-50 ms faster too. The 165-175 ms worst frame
that remains is in every load, dry and Blender maps included (PERFORMANCE phase 4 pass:
`river` 169-177 ms), so it is not water's; not investigated here. Numbers from one session;
treat the wall times as indicative, the main-thread parts as solid (7-run medians, spread
under 2 %).

## Phase 4b (crossings): pinned performance pass (2026-09-27)

What crossings cost in play (GPU with them shown and hidden in one run), on loading, and in
authoring (the Bridge tool's preview per pointer move, a placement's release, a sculpt that
makes a bridge follow).

**How.** Render jobs `jobs/p4b3_perf_build.json` and `jobs/p4b3_perf_play.json`. The build job
makes a 150 ft temperate forest map (seed 1234) with a waist river, a deep pond and a packed
dirt path, saves it as `_p4b3_perf_water`, then places four crossings through the real Bridge
tool (input events: a plank bridge where the path meets the river, stepping stones, a 7.2 m
bridge over the pond with pile bents, a second plank bridge) and saves `_p4b3_perf_cross`. The
play job ran with a temporary pinned `override.cfg` (viewport 1920x1080 in every sample,
`aspect="keep"`, removed by the job at startup), vsync off at runtime for frame windows and on
for loads, the user's graphics settings, a debug build. RTX 3080. `perf.gd gpu_state` logs
`nvidia-smi` from inside the run: 15-16 % at the title with vsync on (the game's own title
screen; no other heavy GPU load), 58-85 % once vsync was off (the game itself). The in-run A/B
is drift-immune; absolute milliseconds from this session are indicative only. Both levels
deleted by the job.

### Play: crossings shown and hidden in one run

`_p4b3_perf_cross` in play with seven tokens (on both decks, the stones, the long bridge,
wading), every crossing's meshes hidden and shown (`crossing.gd visible`, collision kept), on /
off / on / off, 6 s windows each. GPU median ms:

| View | On #1 | Off #1 | On #2 | Off #2 | Crossings |
| --- | --- | --- | --- | --- | --- |
| Home (zoom 13.85, all four in view; 512 draws, 448K prims) | 4.591 | 4.666 | 4.627 | 4.679 | -0.05 to -0.08 ms |
| Zoom 20 (whole map) | 4.937 | 4.924 | 4.917 | 4.954 | +0.01 / -0.04 ms (noise) |
| Zoom 8 on the path bridge | 4.294 | 4.375 | 4.296 | 4.374 | -0.08 ms |

CPU medians moved the same way (4.63-5.43 ms). **Verdict: crossings cost nothing measurable
in play; showing them is slightly cheaper**, because a deck covers water, whose shader costs
more per pixel than the planks' `ORMMaterial3D`. Four crossings add four draw calls and a few
thousand triangles (1,320-2,160 vertices per plank bridge, 729 for three stones).

The two levels played one after the other, same camera, 8 s windows, GPU median ms: home 4.692
without crossings, 4.604 with; zoom 20 4.992 without, 4.888 with (the crossing level has 35
fewer scatter instances, cleared at the landings; same draw count).

### Load time

From the title, vsync on, one process: `_p4b3_perf_cross` first (cold in the process: 1,053
ms, worst frame 319 ms), then three interleaved warm rounds:

| Level | Warm (3) | Worst frame, warm |
| --- | --- | --- |
| `_p4b3_perf_water` | 742 / 717 / 716 ms | 166-175 ms |
| `_p4b3_perf_cross` | 785 / 760 / 785 ms | 173-181 ms |

**Four crossings add 45-69 ms to a warm load** (mean 52 ms): their geometry is built on the
load's worker (`AuthoredLoadPrep`), their three textures (planks, cliff rock, moss) are
requested with the ground's, and their nodes are made in a frame of their own; the worst frame
is the same 165-180 ms frame every authored and Blender load has (P4b-0). Memory in play with
crossings: static 298 MB, video 1,559 MB, working set 1,214 MB, in line with the phase 4 wet
maps.

### Authoring: the Bridge tool

The build job's `record` windows at zoom 10-14, vsync off, CPU frame ms median / worst (n):

| Gesture | Frames |
| --- | --- |
| Idle | 5.0 / 6.8 (776) |
| Drawing a plank line across the river (preview re-planned every 8 cm) | 4.8 / 8.7 (524) |
| Its release (placed) | 4.8 / 12.7 (308) |
| Drawing stepping stones / release | 4.7 / 6.5 (483); 4.6 / 13.8 (317) |
| Drawing the 12 m line over the pond / release (3rd crossing) | 4.7 / 7.1 (616); 4.7 / 17.0 (311) |
| A 4th crossing, drawn and released | 4.2 / 19.0 (896) |
| A Raise stroke on a bridge's bank (the bridge follows) | 4.6 / 23.6 (754) |

A plan (the preview per pointer move) costs 3.0-3.7 ms on this map (river, pond and path;
`bench`: plank 3.08 median, stones 3.52 over 20 runs), so drawing a line never shows in the
frame times. **A placement's cost grows with the crossings already on the map:** every crossing
edit rebuilds all of them on the main thread (`AuthoredCrossings.refresh`), about 2.4 ms per
crossing: the refresh took 3.05 ms with one crossing, 4.3 with two, 8.6 with three, 10.9 with
four and 12.8-13.3 with five (a whole `place` 17-18 ms, its undo 11 ms). Fine at a handful;
a map near the 64-crossing cap would hitch about 150 ms per placement. Rebuilding only the
changed crossing needs a key that includes the ground under it (a sculpt can change a bridge's
piles and a stone's root without changing its fields), so it is left as open work
(MAP_AUTHORING.md).

## Phase 4c (waterfalls): pinned performance pass (2026-10-04)

What falls cost in play (the falls mesh shown and hidden in one run, Water Quality Low against
High), on loading (a map with falls against a twin without), and in authoring (the stream
strokes that make falls, an erase).

**How.** Render jobs `jobs/p4c_perf_build.json` and `jobs/p4c_perf_play.json`. The build job
makes a 150 ft temperate forest map (seed 1234) with the judgment set's two-tier step and 13 m
Raise hill, then a waist river over the step facing the camera, an ankle tributary off the
step's west shelf, two ankle streams down the hill's near flank (real Water tool strokes at
human speed, `record` windows around the hill strokes and an erase) and a deep river off the
step's far edge (`water.gd carve`, the synchronous editor API): six falls (`falls.gd`: the
tier fall 3.05 m of drop, the tributary 1.52 m, three on the hill of 3.5, 3.4 and 6.5 m, the
away-facing one 3.0 m; faces 64-74 degrees), saved as `_p4c_perf_falls` (11 bodies). Then the
same sculpt with the same five waters drawn on the flat ground south of the step, saved as
`_p4c_perf_riffles` (5 bodies, no falls). The play job ran with the pinned `override.cfg`
(viewport 1920x1080 in every sample, removed by the job at startup), vsync off at runtime for
frame windows and on for loads, the user's graphics settings (Water Quality High), a debug
build. RTX 3080, idle before the build (`nvidia-smi`: 0 %, 41 C, P8). Both levels are kept
for `--saved` reruns; `jobs/cleanup_levels.json` deletes them.

### Play: the falls mesh shown and hidden in one run

`_p4c_perf_falls` in play with four tokens (in the tier fall's plunge pool, on its lip, in a
hill stream, in the away-facing river), the one `AuthoredWater-falls` mesh hidden and shown
(`falls.gd falls_visible`; the water stays), on / off / on / off, 6 s windows. GPU median ms:

| View | On #1 | Off #1 | On #2 | Off #2 | Falls mesh |
| --- | --- | --- | --- | --- | --- |
| Home (zoom 13.85, all six in view; 464 draws, 380K prims) | 3.858 | 3.930 | 3.973 | 3.981 | -0.07 / -0.01 (noise: the CPU median drifted 4.40 to 4.63 over the four windows) |
| Zoom 8 on the hill (three falls; 177 draws, 162K prims) | 2.438 | 2.414 | 2.439 | 2.413 | +0.024 / +0.026 |
| Zoom 8 on the tier fall (247 draws, 237K prims) | 3.430 | 3.378 | 3.434 | 3.384 | +0.052 / +0.050 |
| Zoom 20 (whole map; 623 draws, 493K prims) | 3.893 | 3.884 | 3.900 | 3.883 | +0.009 / +0.017 |

**Verdict: the curtains, foam rings and mist cost 0.05 ms at most, at zoom 8 on the widest
fall, and nothing measurable at home or at zoom 20**, against the plan's targets of 0.1 ms
per fall in view at zoom 8 and 0.3 ms at home. The whole falls mesh is one draw call.

Water Quality Low (the shader's second octave, the mist and the pool's refraction off;
`falls.gd quality`) against High, high / low / high / low in the same run, GPU median ms:

| View | High #1 | Low #1 | High #2 | Low #2 | Low saves |
| --- | --- | --- | --- | --- | --- |
| Home | 4.047 | 4.020 | 4.057 | 4.014 | 0.03-0.04 ms |
| Zoom 8 on the tier fall | 3.437 | 3.423 | 3.436 | 3.430 | 0.01 ms |

Low is a visual tier here, not a performance one, as it was for the water shader in phase 4:
the cost is the pixels, and there are few of them.

The two levels played one after the other (8 s windows, no tokens), GPU median ms:
`_p4c_perf_riffles` home 3.661 (484 draws, 411K prims), zoom 20 3.698; `_p4c_perf_falls` home
3.987 (451 draws, 368K prims), zoom 20 3.925. The falls level reads 0.23-0.33 ms slower with
fewer primitives. The in-run A/B puts at most 0.05 ms of that on the falls mesh; the rest is
the water itself (eleven bodies against five, 2,869 bed samples against 2,164, so more water
surface in view, and the water shader is the dearest pixel on the map) plus drift (the falls
level was measured last, the GPU at 72 C, P0, 83 % utilisation at the end). Not separated
further.

### Load time and memory

From the title, vsync on, one process: `_p4c_perf_falls` opened in authoring first
(`perf.gd dress`, for `falls.gd`'s `found:` names: loading screen 2,826 ms, worst frame
857 ms, the process's first open with the palette resolve), then three interleaved warm play
rounds:

| Level | Warm (3) | Worst frame, warm |
| --- | --- | --- |
| `_p4c_perf_riffles` (5 bodies, no falls) | 1,137 / 1,108 / 1,113 ms | 165-170 ms |
| `_p4c_perf_falls` (11 bodies, 6 falls) | 1,281 / 1,287 / 1,286 ms | 164-166 ms |

**Six falls and six more reaches add about 170 ms to a warm load** (mean 1,285 against
1,119 ms); the worst frame is the same 165-175 ms frame every authored load has (P4b-0). The
falls' own share is not separated from the extra bodies' here: the curtain mesh is built on
the load's worker (`AuthoredLoadPrep`'s WATER part) with the water surface, and
`WaterFalls.falls()` is O(bodies^2) with about 20 height reads per pair, so the main-thread
share should be small. A twin with the same eleven bodies on gentle ground would settle it,
if loads come to matter. Memory in play: static 300.9 MB, video 1,649 MB, working set
1,249 MB (peak 1,370) with the falls; 300.3 / 1,649 / 1,295 MB without. Nothing to see.

### Authoring: strokes that make falls, and an erase

The build job's `record` windows at zoom 20, vsync off, CPU frame ms median / worst (n):

| Gesture | Falls map (hill flank) | Twin (flat ground) |
| --- | --- | --- |
| Idle | 4.0 / 6.9 (994) | |
| An ankle stream 13 m down the flank (two falls) / the same length on the flat | 4.4 / 22.6 (1266) | 4.3 / 20.2 (1370) |
| Its erase (Ctrl at the press) | 4.4 / 22.1 (1172) | 4.4 / 18.0 (1285) |
| A second ankle stream down the flank (one 6.5 m fall) | 4.4 / 22.2 (1320) | |
| A deep 13 m river through `water.gd carve` (synchronous editor API, not the tool) | 4.4 / 628 (328) | 4.3 / 356 (358) |

**A stroke that makes falls lands in the same frame budget as one that does not** (worst
22-23 ms against 18-20 ms, inside phase 4's 21-29 ms): the fall plan (the fine profile, the
lips, the set-back) runs in `plan_river` on the main thread at release, the carve on the
worker, as before. The probe carve is the synchronous path (the whole plan, carve, refresh
and regeneration in one frame), so its 356 and 628 ms are not what the tool costs; the 270 ms
between them is the fall profile, plunge pool and gorge walls over 13 m of deep river against
a flat channel, an upper bound on the worker's extra work. The map's first falls (the tier
river and the tributary) were drawn before the record windows, so the first use of the fall
material (warmed when the Water tool opens, P4c-4) is not in these numbers.

## Phase 4d (arch and ford): pinned performance pass (2026-10-04)

What the two new crossing kinds cost in play (GPU with every crossing shown and hidden in one
run), on loading (a level with six crossings against the same level without), and in
authoring (an arch and a ford drawn through the Bridge tool, the per-placement rebuild with
one to seven crossings on the map, a sculpt that makes them all follow).

**How.** Render jobs `jobs/p4d_perf_build.json` and `jobs/p4d_perf_play.json`. The build job
makes the P4b-3 map (150 ft temperate forest, seed 1234: a curved waist river at radius 1.8,
a deep pond, a packed dirt path), saves it as `_p4d_perf_water`, then with the UI hidden and
vsync off draws an arch through the real Bridge tool where the path meets the river
(`bridge_kind arch`, a held gesture, a recorded release; 5.4 m span) and a ford across the
river 21 m downstream (4.3 m), and places through `crossing.gd place` a plank bridge (4.6 m),
stepping stones (three), an arch along the pond's long axis (14.8 m, so a pier) and a second
ford, `crossing.gd timing` after each; `bench` for plank and arch plans; a Raise stroke on
the arch's bank; saved as `_p4d_perf_cross` (six crossings). The play job ran with the pinned
`override.cfg` (viewport 1920x1080 in every sample, removed by the job at startup), vsync off
at runtime for frame windows and on for loads, the user's graphics settings, a debug build.
RTX 3080. `perf.gd gpu_state` at each run's start read 34 % (build) and 29 % (play) at the
title with vsync on, more than the earlier passes' 15-26 %, but at idle clocks (P5 495 MHz,
P8 420 MHz; 41-46 C), so the percentage is the game's own title frame at a low clock rather
than another load; 82 %, 70 C, P0 at the play run's end (the game itself). The in-run A/B is
drift-immune; absolute milliseconds are indicative. Both levels are kept for `--saved` reruns
(`cleanup_levels.json` deletes them).

### Play: crossings shown and hidden in one run

`_p4d_perf_cross` in play with four tokens (on the arch's deck, wading in the ford, on the
plank deck, on a stone), every crossing's meshes hidden and shown (`crossing.gd visible`,
collision kept), on / off / on / off, 6 s windows. GPU median ms:

| View | On #1 | Off #1 | On #2 | Off #2 | Crossings |
| --- | --- | --- | --- | --- | --- |
| Home (zoom 13.85, all six in view; 498 draws, 430K prims) | 3.374 | 3.643 | 3.531 | 3.665 | -0.13 to -0.27 ms (the CPU median drifted 4.02 to 4.46 over the four windows, so the smaller figure is the honest one) |
| Zoom 8 on the arch (279 draws, 273K prims) | 3.314 | 3.417 | 3.324 | 3.420 | -0.10 / -0.10 ms |
| Zoom 8 on the ford (225 draws, 219K prims) | 3.153 | 3.195 | 3.153 | 3.211 | -0.04 / -0.06 ms |
| Zoom 20 (whole map; 565 draws, 454K prims) | 3.177 | 3.231 | 3.168 | 3.250 | -0.05 / -0.08 ms |

**Verdict: the arch and the ford cost nothing measurable in play; showing the crossings is
0.05-0.13 ms cheaper than hiding them**, as in phase 4b, because a deck or an arch covers
water pixels, and the water shader is the dearest pixel on the map. The ford shows the
smallest delta because its bar lies under the surface and hides no water. Six crossings are
six draw calls; surface 0 of each (`crossing.gd report`): the 5.4 m arch 1,696 vertices of
stone, the pier arch 3,604, a ford 196-203 of gravel, the plank bridge 1,320, the stones 729.

The two levels played one after the other, same camera and tokens, 8 s windows, GPU median
ms: home 3.766 without crossings (493 draws, 431K prims), 3.626 with (498 draws, 430K); zoom
20 3.959 without (694 draws, 591K), 3.866 with (698 draws, 590K). The crossing level reads
0.09-0.14 ms cheaper with 60 fewer scatter instances (cleared at the landings); it was
measured second, the GPU at P0 and 70 C by the end.

### Load time and memory

From the title, vsync on, one process: `_p4d_perf_cross` first (cold in the process: 1,629
ms, worst frame 561 ms), then three interleaved warm rounds:

| Level | Warm (3) | Worst frame, warm |
| --- | --- | --- |
| `_p4d_perf_water` | 1,142 / 1,154 / 1,147 ms | 175-191 ms |
| `_p4d_perf_cross` (two arches, two fords, planks, stones) | 1,185 / 1,174 / 1,144 ms | 176-186 ms |

**Six crossings, two of them arches, add about 20 ms to a warm load** (mean 1,168 against
1,148 ms; per round -3 to +43 ms, so inside the round-to-round spread), less than the 52 ms
four plank-and-stone crossings cost in phase 4b against a 720 ms base. Their geometry is
built on the load's worker (`AuthoredLoadPrep`); in play `crossing.gd report` shows build
0 ms and a 32.4 ms swap, the six nodes entering the tree in one frame, inside the same
165-190 ms worst frame every authored load has (P4b-0). Memory in play with the crossings:
static 307.3 MB, video 1,580.5 MB, working set 1,245 MB (peak 1,394); at the end of the run
static 307.6 / video 1,573.2 / working set 1,288 MB without, 308.8 / 1,580.7 / 1,306 MB with.
The arch's and ford's textures are about 7 MB of video memory.

### Authoring: the Bridge tool with four kinds

The build job's `record` windows at zoom 10, vsync off, CPU frame ms median / worst (n):

| Gesture | Frames |
| --- | --- |
| Idle | 4.2 / 7.1 (934) |
| Drawing an arch across the river (preview re-planned per move) | 4.3 / 5.9 (590) |
| Its release (placed; the map's first crossing) | 4.2 / 12.5 (356) |
| Drawing a ford across the river / release (second crossing) | 4.0 / 5.8 (587); 3.6 / 20.2 (397) |
| A Raise stroke on the arch's bank (six crossings follow) | 4.0 / 53.5 (859) |

A plan costs the same for every kind (`bench`, 20 runs: plank 3.11 ms median, 3.04-3.54;
arch 3.46, 3.04-4.66; phase 4b: plank 3.08, stones 3.52), so drawing an arch or a ford never
shows in the frame times. **The placement is where the new kinds cost: every crossing edit
rebuilds all of them on the main thread (`AuthoredCrossings.refresh`), and an arch or a ford
costs two to four times a plank bridge.** The refresh (build + swap) by crossing count, each
row adding the named crossing:

| Crossings on the map | Refresh ms | Build | Swap | Whole `place` |
| --- | --- | --- | --- | --- |
| 1: the 5.4 m arch | 6.0 | 4.8 | 1.2 | (tool release, worst frame 12.5) |
| 2: + a ford | 12.4 | 10.3 | 2.1 | (tool release, worst frame 20.2) |
| 3: + a plank bridge | 14.9 | 12.6 | 2.3 | 20.8 |
| 4: + stepping stones | 15.9 | 13.1 | 2.8 | 21.4 |
| 5: + the 14.8 m pier arch | 26.2 | 21.8 | 4.3 | 31.9 |
| 6: + a second ford | 33.8 | 28.6 | 5.2 | 40.7 |
| 7: + a bench plank / arch (then undone) | 37.0 / 38.9 | 31.2 / 32.4 | 5.8 / 6.4 | 42.2 / 43.0; undo 37.0 / 33.5 |

Build increments per kind: the short arch 4.8 ms, the pier arch 8.7, a ford 5.5-6.7, a plank
bridge 2.3, three stones 0.5; the swap grows about 0.9 ms per crossing. A ford's build costs
more than a plank bridge's for a tenth of the vertices; where that goes was not profiled here.
The Raise stroke by the arch's bank refreshed all six in 32.3 ms (build 26.9) on top of the
sculpt's own regeneration, the 53.5 ms frame above (phase 4b: 23.6 ms with four plank-and-stone
crossings).

**Cache decision: the per-crossing geometry cache (open since P4b-3) is due now.** The line
set for this pass was 25 ms of main-thread work for a placement with six crossings on the
map; the sixth placement's refresh took 33.8 ms (40.7 ms for the whole place), a seventh 37-39
ms, an undo 34-37 ms, and a sculpt beside one crossing 53.5 ms in a frame. The mean is now
5.6 ms per crossing against phase 4b's 2.4, so the 64-crossing cap would hitch about 360 ms
per placement. The cache is keyed on each crossing's fields and the ground under it (a sculpt
moves piles, abutments, stones and a ford's bar without changing the fields), rebuilds only
the crossings whose key changed, and is not built in this pass (MAP_AUTHORING.md "Open work").

### Per-crossing rebuild cache (P4d-5b)

Built the same day (`CrossingCache`, `utils/crossing_cache.gd`; `AuthoredCrossings.refresh`).
Per crossing a 32-bit key over its fields, the document's seed and grid, the heights over
`CrossingGeometry.clear_bounds` plus one sample, and the water that can reach the bounds (the
rivers near them by id, level, points and half-widths; the pond mask over the bounds and the
ponds marked in it). A refresh builds only the crossings whose key differs from the one their
node holds, frees the nodes of crossings that left, and recomputes the deck field and `top_y`
only when some node changed. A load seeds the keys from the document its worker built from, so
the first edit after a load rebuilds nothing it need not. The keys for six crossings cost
0.07-0.30 ms per refresh on the 150 ft map (0.147 ms for six arches on the 100 ft test map,
`test_crossing_cache.gd`). Same job (`jobs/p4d_perf_build.json`), same machine, one run; the
refresh is keys + build + swap:

| Crossings on the map | Refresh ms before | Refresh ms after (keys / build / swap) | Whole `place` before -> after |
| --- | --- | --- | --- |
| 1: the 5.4 m arch | 6.0 | 6.0 (0.07 / 3.8 / 2.1) | tool release, worst frame 12.5 -> 16.2 |
| 2: + a ford | 12.4 | 6.9 (0.12 / 5.0 / 1.9) | tool release, worst frame 20.2 -> 14.2 |
| 3: + a plank bridge | 14.9 | 3.8 (0.18 / 1.8 / 1.8) | 20.8 -> 9.2 |
| 4: + stepping stones | 15.9 | 3.2 (0.25 / 0.7 / 2.3) | 21.4 -> 8.8 |
| 5: + the 14.8 m pier arch | 26.2 | 13.3 (0.26 / 7.6 / 5.4) | 31.9 -> 19.3 |
| 6: + a second ford | 33.8 | 9.8 (0.30 / 5.2 / 4.4) | 40.7 -> 15.4 |
| 7: + a bench plank / arch (then undone) | 37.0 / 38.9 | 6.4 / 10.7 (build 1.8 / 4.0, swap 4.3 / 6.3) | 42.2 / 43.0 -> 11.5 / 15.0; undo 37.0 / 33.5 -> 4.4 / 4.5 |

Every placement rebuilt one crossing of the map's count (`rebuilt 1 of N` in the probe's
`timing` line); an undo of a placement rebuilt none (the freed node and the deck field only).
The Raise stroke by the arch's bank rebuilt 3 of 6 (the arch, whose anchors followed, and the
plank bridge and near ford, whose ground rectangles the stroke's changed samples reached):
18.7 ms (keys 0.30, build 12.4, swap 6.0) against 32.3 before, and the window's worst frame
40.4 ms against 53.5. Record windows, CPU frame ms median / worst (n): idle 4.1 / 7.8 (964),
arch drag 4.1 / 5.5 (611), arch release 4.1 / 16.2 (365), ford drag 3.9 / 5.4 (602), ford
release 3.6 / 14.2 (409), sculpt by the arch 4.0 / 40.4 (895).

**Verdict: met.** A placement with six crossings on the map is 9.8 ms of refresh (15.4 ms for
the whole place) against the 12 ms line and 33.8 before; a placement's cost no longer grows
with the map's crossing count, only with the kind placed (a ford 5-7 ms, the pier arch 13).
What remains is the one crossing's own build (the ford's 5 ms for 200 vertices is still
unprofiled) and the swap, which is now the larger share for stone meshes (4.4-6.3 ms for one
arch or ford node: `moss_split` walks every facet in GDScript, then the mesh and concave shape
upload); both are the next targets if a placement needs to go under a frame.

### Swap and ford build (2026-10-05)

Profiled headless first (the `_p4d_` forest level's five crossings, medians of 15): the swap's
largest share was not `moss_split` but the deck field, re-rasterised over every deck on the map
for every placement whatever its kind (3.05 ms for five crossings, a `local_of` and a
`sample_to_world` through the document's methods per sample); then `moss_split` (0.52 ms for
the 5.4 m arch, 1.06 for the pier arch). The ford's build was its 280 bar samples' `level_at`
(10 us each against the river course) and `ground_at` (3 us). Fixes, all byte-identical (the
parts' and the moss split's digests before and after): the deck field changes only with a deck
(a placed deck added onto it, `CrossingGeometry.deck_field_add`; re-rasterised when one left or
was rebuilt; untouched for a ford or stones) and reads the grid once (3.05 -> 0.60 ms; adding
the pier arch 0.35); `moss_split` inline (0.52 -> 0.16, 1.06 -> 0.34); the ford's samples read
in two batches (`WaterGeometry.grounds_at`, `levels_along`: rivers cut per run of four rows) and
the facet, face and quad loops without per-item arrays (a waist ford 4.46 -> 1.60 ms headless).

`jobs/p4d_perf_build.json`, same settings as the P4d-5b table, one run (the second, after both
commits); refresh = keys / build / swap:

| Crossings on the map | P4d-5b | After |
| --- | --- | --- |
| 1: the 5.4 m arch | 6.0 (0.07 / 3.8 / 2.1) | 5.14 (0.08 / 3.90 / 1.15) |
| 2: + a ford | 6.9 (0.12 / 5.0 / 1.9) | 2.80 (0.16 / 1.84 / 0.80) |
| 3: + a plank bridge | 3.8 (0.18 / 1.8 / 1.8) | 2.68 (0.19 / 2.08 / 0.40) |
| 4: + stepping stones | 3.2 (0.25 / 0.7 / 2.3) | 1.21 (0.23 / 0.29 / 0.68) |
| 5: + the 14.8 m pier arch | 13.3 (0.26 / 7.6 / 5.4) | 9.95 (0.27 / 8.20 / 1.47) |
| 6: + a second ford | 9.8 (0.30 / 5.2 / 4.4) | 3.00 (0.32 / 1.84 / 0.83) |
| 7: bench plank / arch | 6.4 / 10.7 (swap 4.3 / 6.3) | 2.56 / 5.34 (swap 0.35 / 0.99); undo 4.4 / 4.5 -> 1.37 / 1.20 |

The sculpt by the arch (3 of 6 rebuilt): 18.7 -> 10.2 ms (swap 6.0 -> 2.4), its window's worst
frame 40.4 -> 28.6-30.2 ms (two runs). Release windows' worst frames: arch 16.2 -> 16.1 (32.1 in
the first run, its first crossing), ford 14.2 -> 10.9-11.0. **Verdict: met.** Every placement's
swap is 0.35-1.5 ms (target 2) and a ford's build 1.84 ms in game (target 2). An arch's own
build (3.9 ms, the pier arch 7.5-8.2) is now most of a placement and the next target: the
refresh's builds onto a worker, as the water refresh does.

## Phase 5 (starting landforms): pinned performance pass (2026-10-04)

What a starting landform costs: the open time of a new map per landform against Flat (the
recipe runs on the main thread before the map is built), the first strokes on a shaped map
against a flat one, and a landform map in play.

**How.** Render jobs `jobs/p5_perf_open.json`, `jobs/p5_perf_strokes.json` and
`jobs/p5_perf_play.json`, one process each, run in that order with the pinned `override.cfg`
(viewport 1920x1080 in every sample; the play job removed it at startup), the user's graphics
settings, a debug build, RTX 3080. Opens and loads with vsync on (timed by the probe's
`Watch`), stroke and GPU windows with vsync off. The open job uses `perf.gd author` (now
taking `landform`) and the new `perf.gd recipe`, which times `NewMap.create` with the landform
against Flat on the main thread three times each, from the title between opens so it never
lands in a timed frame. `perf.gd gpu_state` at each run's start, at the title with vsync on:
38 % P8 255 MHz (open), 33 % P8 240 MHz (strokes), 36 % P8 270 MHz (play); idle clocks, the
same title-frame reading as phase 4d's 29-34 %, not another load. At the ends: 26 % P5 (open),
82 % and 84 % P0 1935 MHz (strokes and play, the game itself with vsync off). In-run
comparisons hold; absolute milliseconds are indicative.

### Opening a new map

Temperate forest, seed 7 (wet draws for the valley, hilltop and gorge, a dry terraces, a lake
without a stream), from the title, three rounds of the six landforms interleaved (Flat first
in each round). Loading screen is `perf.gd author`'s Create-to-drop time; the worst frame is
the worst under the loading screen; the recipe is `perf.gd recipe`'s median difference
(create with the landform minus create with Flat, both on the main thread):

| 150 ft | Loading screen ms (rounds 1 / 2 / 3) | Worst frame ms | Recipe ms | Warm mean against Flat |
| --- | --- | --- | --- | --- |
| Flat | 2,005 (cold, first in process) / 771 / 658 | 905 / 448 / 335 | 0 (create 86) | 715 |
| Valley | 1,093 / 961 / 939 | 618 / 596 / 588 | 298 | +235 |
| Hilltop | 1,089 / 906 / 854 | 855 / 546 / 542 | 210 | +165 |
| Terraces | 893 / 799 / 799 | 609 / 504 / 500 | 154 | +84 |
| Lakeshore | 1,099 / 1,037 / 1,041 | 700 / 700 / 695 | 297 | +324 |
| Gorge | 1,167 / 972 / 1,051 | 924 / 621 / 629 | 306 | +297 |

Once each at the other sizes (warm, the same process, after the three rounds):

| Size | Flat | Valley | Gorge |
| --- | --- | --- | --- |
| 100 ft: loading screen / worst frame / recipe | 584 / 285 / 0 (create 38) | 846 / 493 / 162 | 891 / 542 / 177 |
| 200 ft: loading screen / worst frame / recipe | 787 / 526 / 0 (create 152) | 1,372 / 846 / 453 | 1,538 / 1,183 / 501 |

**Verdict: a landform adds 85-325 ms to a 150 ft open of about 0.7 s, and the recipe accounts
for all of it.** The open grows by roughly the recipe's own time (the terraces' dry draw is
the cheapest at 154 ms; the valley, lake and gorge cost about 300 ms each, in line with P5-0's
pure timings of 180-340 ms), and the worst frame under the
loading screen grows with it (500-700 ms against Flat's 335-448 warm), because the recipe runs
in the frame that starts the open. The recipe grows with the map's area a little slower than
the area (150 to 200 ft is 1.78x the area; the valley 1.52x, the gorge 1.64x), so at 200 ft a
gorge opens in 1.5 s with one 1.2 s frame. The loading screen is up and names the landform
("Shaping the gorge..."), so it reads as a pause, not a hitch; if 200 ft opens matter, the
recipe can move onto the loader's worker (it writes only the document). Flat's own
`NewMap.create` (the starting cover paint) is 38 / 86 / 152 ms by size. Round 1's Flat was
the process's first open (2.0 s, a 905 ms frame), so the warm comparison uses rounds 2 and 3;
Flat's two warm opens differ by 113 ms, which bounds the noise in the table's last column.
`perf.gd author`'s second line (palette resolved and regeneration done) did not log in this
run: the job leaves for the title 1 s after `wait_ready` settles, before the whole palette has
resolved, so the starting cover's regeneration was not timed separately here.

Memory in authoring after each open (static / video): Flat 304-309 / 1,641-1,644 MB, the
landforms 305-313 / 1,644-1,654 MB (the lake and gorge highest by 5-10 MB of buffers and
textures); static creeps about 9 MB over the run's 24 opens whatever the landform. Working set
on round 1: 1,098 MB after Flat (the first open) rising to 1,198 MB after the gorge, the
process growing rather than a per-landform cost.

**P5-8 (2026-10-05): the document on a worker.** `NewMapBuild` now runs `NewMap.from_spec`
(the recipe and the starting cover) on a `WorkerThreadPool` task once the loading screen is up,
and the controller waits for it a frame at a time. The same job re-run, the same settings
(no `override.cfg` this time; the window's 1920x1080 viewport); `gpu_state` 35 % P8 300 MHz at
the start, 28 % P5 at the end. Worst frame under the loading screen, before (P5-5) and after:

| 150 ft | Worst frame ms before (rounds 1 / 2 / 3) | After | Loading screen ms after |
| --- | --- | --- | --- |
| Flat | 905 / 448 / 335 | 900 (cold) / 521 / 225 | 2,064 / 796 / 677 |
| Valley | 618 / 596 / 588 | 278 / 225 / 244 | 1,025 / 952 / 976 |
| Hilltop | 855 / 546 / 542 | 277 / 223 / 227 | 812 / 779 / 751 |
| Terraces | 609 / 504 / 500 | 288 / 226 / 230 | 731 / 674 / 689 |
| Lakeshore | 700 / 700 / 695 | 285 / 277 / 226 | 831 / 808 / 803 |
| Gorge | 924 / 621 / 629 | 289 / 226 / 225 | 988 / 918 / 869 |

| Size: worst frame before -> after (loading screen after) | Flat | Valley | Gorge |
| --- | --- | --- | --- |
| 100 ft | 285 -> 237 (605) | 493 -> 282 (764) | 542 -> 281 (758) |
| 200 ft | 526 -> 282 (740) | 846 -> 276 (1,292) | 1,183 -> 517 (1,229) |

The recipe timings match P5-5's (`perf.gd recipe` still times `NewMap.create` on the main
thread: 200 ft valley 536 ms, gorge 495 ms). **Verdict: the recipe no longer lands in a frame,
but the open still has one 220-290 ms frame, and the 200 ft gorge one of 517 ms; the 150 ms
target is not met by this change.** The 220-290 ms frame is the load's own main-thread work
after the document (a warm Flat open has it too, at 225 ms, now that its starting-cover paint
of 86-152 ms is off the main thread as well), so it is the next target, not the landform. The
200 ft gorge's 517 ms is one sample; P5-5's gorge-minus-recipe frame (about 680 ms against
Flat's 526) had the same excess, so it is most likely the gorge's larger water and crossing
install on the main thread rather than noise. Opens are 100-300 ms shorter end to end, mostly
from the overlap of the worker with the loading screen's own frames.

### The first strokes on a shaped map

Forest seed 3 at 150 ft: Terraces (three tiers stepping down along z, faces near z = -8 and
z = +7, the stage at (-0.5, 0) on the middle tier, the recipe's river with two falls at
x = -6) and the Flat map, the same strokes on both. UI hidden, zoom 20, vsync off: a Raise on
the stage (radius 4, held 2 s), a Smooth across the north step at x = 1 (on Flat the same
spot), a waist river from (6, -12) to (6, 8) (on the terraces it falls once, at (6.0, -8.27):
`falls.gd falls` lists it after the recipe's two), then its erase. `record` windows, CPU frame
ms median / worst (n), each including its `wait_ready` tail:

| Stroke | Terraces | Flat |
| --- | --- | --- |
| Idle 4 s | 3.9 / 5.1 (1017) | 4.1 / 5.4 (947) |
| Raise on the stage | 4.2 / 9.4 (705) | 4.2 / 8.3 (670) |
| Smooth across a tier face | 4.3 / 15.1 (926) | 4.2 / 7.4 (919) |
| Waist river across a step (one fall) | 4.3 / 12.3 (1505) | 4.2 / 21.4 (1425) |
| Its erase | 4.4 / 10.9 (1410) | 4.4 / 8.9 (1352) |

**Verdict: a shaped map strokes like a flat one.** Medians match within 0.1 ms; the worst
frames are one-off stroke-end frames (regeneration and the carve's swap) of 9-21 ms on either
map, the Smooth over a tier face the only one clearly dearer on the terraces (15.1 against
7.4 ms; one sample each, and where the frame goes was not profiled), and
the river's worst frame lower on the terraces (12.3 against 21.4), so stroke-end variance is
larger than the landform's effect. Memory after the strokes: static 307.6 / video 1,654.2 MB /
working set 1,198 MB (terraces), 307.3 / 1,650.0 / 1,200 MB (flat).

### Play

The two saved levels (`_p5_perf_terraces`, `_p5_perf_flat`, each with the stroke results and
the river erased). Loads from the title with vsync on: terraces first (cold in the process,
1,671 ms, worst frame 656 ms), then three warm rounds interleaved:

| Level | Warm (3) | Worst frame, warm |
| --- | --- | --- |
| `_p5_perf_flat` | 1,058 / 1,062 / 1,054 ms | 407 / 198 / 199 ms |
| `_p5_perf_terraces` | 1,155 / 1,133 / 1,136 ms | 270 / 285 / 288 ms |

Then each level twice, interleaved (flat, terraces, flat, terraces), home and zoom 20, 8 s
windows, vsync off. GPU median ms (CPU median):

| View | Flat #1 | Terraces #1 | Flat #2 | Terraces #2 | Terraces against Flat |
| --- | --- | --- | --- | --- | --- |
| Home (flat 500 draws, 476K prims; terraces 437, 386K) | 3.204 (3.70) | 3.545 (4.08) | 3.356 (3.87) | 3.567 (4.09) | +0.21 to +0.34 ms |
| Zoom 20 (flat 676 draws, 628K; terraces 648, 551K) | 3.637 (4.17) | 3.865 (4.41) | 3.708 (4.25) | 3.885 (4.51) | +0.18 to +0.23 ms |

**Verdict: the terraces level costs about 0.2 ms of GPU in play and 80 ms on a warm load,
small, and most likely the recipe's water rather than the shape.** It draws fewer objects and
primitives than the flat level (the tiers' faces and the river's footprint carry 516 fewer
scatter instances), so the extra GPU time is most likely pixels: the recipe's river and two
falls, whose water shader is the dearest pixel on the map (phase 4b and 4d), against a flat
map with no water. The flat level drifted up 0.07-0.15 ms between its two windows while the
terraces held, so the smaller deltas are the honest ones. The warm load's +80 ms and its
worst frame (270-288 ms against 198 ms) were not broken down; the water and falls are the
level's only extra content. Memory in play:
static 293.5-294.5 / video 1,527.2 MB / working set 1,254-1,276 MB (flat), 295.2-296.0 /
1,536.1 / 1,283-1,291 MB (terraces; 9 MB of textures more, the water and falls).

## Phase 6 (rivers past the map edge): pinned performance pass (2026-10-05)

What phase 6 costs: the ground skirt made opaque with a colour fade (it was transparent),
the per-exit channel patch and water ribbon, `SkirtBackdrop` polling the environment every
frame, the exit geometry built on the load and refresh workers, and the main thread's
`apply_river_exits` after a water edit. See `docs/systems/water.md` "Past the map edge".

**How.** Render jobs `jobs/p6_perf_build.json`, `jobs/p6_perf_play.json` and
`jobs/p6_perf_band.json`, one process each, run in that order, with the new probe
`probes/p6_perf.gd`. The build job makes two 150 ft temperate forest maps (seed 1234) with
the same two rivers: on `_p6_perf_exits` a waist river drawn on past the near edge with a
bend and an ankle stream drawn past the right edge (two drawn exits: patch 14,875 and
13,125 vertices, ribbon 711 and 387; the skirt itself 6,588), on `_p6_perf_short` the same
strokes stopping about 2.4 m short of the edges (no exit); then, on the first, `record`
windows around a waist river drawn to the left edge and its erase against one stopping
short. The play and band jobs ran with the pinned `override.cfg` (viewport 1920x1080 in every
sample, removed by the job at startup), vsync on for loads and off for frame windows, the
user's graphics settings, a debug build, RTX 3080. The skirt A/B hot-swaps the skirt
material's shader in the run (`p6_perf.gd shader`): `opaque` is the game's, `transparent`
the skirt before phase 6 (the wrapper and ground include of 7bde99a, read from a `git
archive` zip, the include inlined); the material is shared with the channel patch, so the
patch swaps with it. `perf.gd gpu_state` at each run's start, at the title with vsync on: 34
% P8 300 MHz (build), 35 % P8 225 MHz (play), 37 % P8 255 MHz (band): idle clocks, the game's
own title frame as in phases 4d and 5, not another load. At the ends 85-98 % P0 1605-1935 MHz,
the game itself with vsync off. In-run comparisons hold; absolute milliseconds are indicative.
Both levels are kept (`cleanup_levels.json` deletes them).

### The skirt: opaque against transparent in one run

`_p6_perf_exits` in play, 5 s windows, opaque / transparent / opaque / transparent, then
the skirt hidden as the reference. GPU median ms (n 1,240-2,160 per window):

| View | Opaque #1 | Transparent #1 | Opaque #2 | Transparent #2 | Skirt hidden | Opaque against transparent |
| --- | --- | --- | --- | --- | --- | --- |
| Home (zoom 13.85; 496 draws, 492K prims) | 3.339 | 3.405 | 3.386 | 3.399 | 3.405 | -0.01 to -0.07 ms (the skirt is off screen) |
| Zoom 20 panned to the waist river's exit (385 draws, 368K) | 2.914 | 2.553 | 2.921 | 2.556 | 1.769 | +0.36 ms |
| Zoom 20 panned to the left edge, no exit (363 draws, 374K) | 2.994 | 2.673 | 2.990 | 2.679 | 2.300 | +0.31 / +0.32 ms |
| Full authoring zoom-out (zoom 39.28, the 150 ft map's; 841 draws, 709K) | 3.656 | 3.150 | 3.668 | 3.156 | 2.316 | +0.51 ms |

**Verdict: the opaque skirt costs 0.31-0.36 ms of GPU at max play zoom panned to an edge,
on frames of about 3 ms, and 0.51 ms at full authoring zoom-out; nothing at home.** It
roughly doubles the skirt's own cost: at the plain edge the skirt is 0.37 ms transparent and
0.69 ms opaque, at full zoom-out 0.83 against 1.35 ms. How the difference splits between the
pass (the opaque ring goes through the depth prepass and the opaque pass, the transparent one
drew once after them with no depth write) and the shader's own extra work (the backdrop, the
fog, the channel dressing) was not measured. The P6-0 probe's indicative +0.3-0.45 ms panned
to an edge holds.

**The band variant (the probe's suggestion: opaque only around the exits).** Measured
without a code change: `p6_perf.gd shader band` keeps the opaque material on the channel
patch and draws the rest of the ring with the transparent shader through a surface
override. Its own run, the same views, GPU median ms:

| View | Opaque #1 / #2 | Band #1 / #2 | Transparent #1 / #2 |
| --- | --- | --- | --- |
| Zoom 20 on the exit | 2.732 / 2.927 | 2.827 / 2.857 | 2.559 / 2.557 |
| Zoom 20 on the left edge, no exit | 2.972 / 2.977 | 2.647 / 2.644 | (2.673 / 2.679 in the play run) |
| Full authoring zoom-out | 3.677 / 3.680 | 3.420 / 3.424 | (3.150 / 3.156 in the play run) |

(The exit view's first opaque window, the first after `vsync_off`, read 0.2 ms below the
second; the second is the comparable one.) The band gives back all of the opaque cost at a
plain edge (0.33 ms), half at full zoom-out (0.26 ms) and 0.07 ms at an exit, where the
patch is most of the visible ring. **Decision: keep the opaque skirt everywhere.** The
threshold set for trying the band was about 0.3 ms at an edge without an exit, and the
skirt is at it (0.31-0.33 ms in two runs), not clearly past it; the band would put two
blend modes side by side around every exit, and the fade's match under depth fog, sky
backdrops and the dither fallback was tuned for the opaque one alone (P6-1), so the seam
risk is a look cost paid near every river, for a third of a millisecond on 3 ms frames.
If a lower-end target needs the time back, the band is measured and its probe is in place.

### The exits' own draw

At zoom 20 on the waist river's exit, opaque skirt, the channel patch and the ribbon shown
and hidden (`p6.gd show`), on / off / on / off: 2.921 / 2.006 / 2.928 / 2.015 ms GPU, and the
ribbon alone hidden 2.873 ms. **The ribbon costs about 0.05 ms; the patch and ribbon 0.91
ms**, but hiding the patch leaves its columns out of the skirt (they are cut from the ring
and redrawn by the patch), so that figure is the whole cost of drawing that part of the
ring, not the extra over a plain skirt. The upper bound on the extra: the whole skirt costs
1.15 ms at the exit view (2.92 against 1.77 hidden) and 0.69 ms at the plain edge view, so
an exit in view adds at most about 0.45 ms at max play zoom, less what the framing differs.
Draw calls: the patch and the ribbon are one each per map, whatever the exit count.

### SkirtBackdrop

CPU frame median at zoom 20 on the exit with its per-frame sync on / off / on / off: 3.441 /
3.441 / 3.440 / 3.440 ms (GPU 2.926-2.931). Timed directly (`p6_perf.gd backdrop_bench`, 5,000
calls on the play map's node, two materials): **3.6 microseconds per frame** when nothing
changed (the steady state: the uniforms dictionary built and compared), 7.0 when every
uniform is set. Nothing to fix.

### Load time and memory

From the title, vsync on, one process: `_p6_perf_exits` first (cold in the process: 2,050
ms, worst frame 643 ms), then three interleaved warm rounds:

| Level | Warm (3) | Worst frame, warm |
| --- | --- | --- |
| `_p6_perf_short` (no exit) | 1,076 / 1,095 / 1,080 ms | 207 / 200 / 201 ms |
| `_p6_perf_exits` (two exits) | 1,650 / 1,631 / 1,632 ms | 310 / 200 / 206 ms |

**Two exits add about 550 ms to a warm load (1,638 against 1,084 ms mean), all of it on a
worker: the worst frame does not move.** `RiverExitMesh.skirt_parts` (`p6_perf.gd
exits_build`, run on the main thread to time it): 33.3 ms for the skirt alone on the short
map, 335.8 ms with the waist exit alone, 593-599 ms with both, so about 280 ms per exit,
and it is the load's longest worker task, so the loading screen waits for it. The exits do
not reach a frame (P4b-0's worker load holds), but the time is high for 14K vertices per
exit and is the first target if loads matter (MAP_AUTHORING.md "Open work", edge
follow-ups). Memory in play: static 307.4-309.2 / video 1,522.4 MB (buffers 46.7) without
exits, 310.4-312.2 / 1,523.7 MB (buffers 48.0) with them: about 3 MB of static memory and
1.3 MB of vertex buffers; the working set (1,166-1,230 against 1,201-1,222 MB) is inside
its drift.

### Authoring: a river drawn to the edge, and its erase

The build job's `record` windows on `_p6_perf_exits` at zoom 24, vsync off, CPU frame ms
median / worst (n), two runs of the job (the first run's map had one exit, the ankle
stream's stroke stopping short of the edge; the second, the table's, two):

| Gesture | Run 2 | Run 1 |
| --- | --- | --- |
| Idle 4 s | 3.8 / 4.6 (1044) | 3.8 / 4.5 (1044) |
| A waist river stopping 3.4 m short of the left edge | 4.0 / 23.9 (997) | 4.1 / 28.1 (985) |
| Its erase | 4.3 / 22.1 (950) | 4.1 / 20.5 (948) |
| The same river drawn past the left edge (a third exit) | 4.2 / 45.3 (1478) | 4.2 / 45.3 (1494) |
| Its erase (the exit goes) | 4.2 / 21.7 (977) | 4.3 / 23.0 (960) |

The refresh after each (`p6_perf.gd water_timing`): the worker's build (water mesh and skirt
parts) 697 / 692 ms for the short stroke and its erase with two exits on the map, 913 ms after
the stroke to the edge (three exits), 699 ms after its erase; 408 ms after the first stroke
of the map (one exit); the main-thread swap 18.0-22.3 ms in every case. `apply_river_exits`
timed alone (`apply_bench`, the skirt rebuilt with the map's parts): 1.5 ms with one exit,
2.3 ms with two. **Verdict: the exits cost the main thread about 2 ms per refresh, inside a
swap that did not change (18-22 ms); their worker time, about 280 ms per exit on the map,
is rebuilt on every water edit while any exit exists, so a water edit on a map with exits
lands 0.3-0.6 s later than on one without, under no frame.** The one dearer frame is the
stroke that reaches the edge: 45.3 ms in both runs against 24-28 ms for the stroke that stops
short. Its main-thread parts put it in the carve's ground step (`ground` 41.8 ms, 48.2 for
the ankle stream to the right edge, against 5.6-14.3 ms for strokes inside the map), which
also updates the skirt's edge in place when the carve reaches the boundary; that is the
likely cause and was not profiled further.

### Edge follow-ups (P6-3, 2026-10-05)

Two fixes, measured with `jobs/p6_perf_build.json` (now also `cache_check` and
`mirror_bench`; `water_timing` adds the terrain's last in-place skirt refresh), the same
settings as above, one process per run, `gpu_state` 31-36 % P8 270-315 MHz at the start and
84-85 % P0 1920-1935 MHz at the end. "Before" is a run of this job at the start of P6-3 (the
look fixes in, neither of these): its numbers match P6-2's.

**The 45 ms frame of a stroke carved to the edge** was the skirt's CPU vertex mirror:
`refresh_skirt()` made it from the document (`TerrainMeshBuilder.skirt_vertex_mirror`, 34.0 ms
on the main thread) on the first edge edit after every skirt rebuild, and a water refresh
with exits rebuilds the skirt. The mirror now comes with the skirt parts, read off the built
arrays on the worker (`skirt_mirror_of`, 3.4 ms); the in-place refresh itself is 1.7-2.1 ms.

**The exits rebuilt on every water edit** are now cached per window and per mouth
(`RiverExitMesh.build`; `systems/water.md` "Past the map edge"). Its first in-game run missed
every piece: the ring distances, hashed as doubles, gave different keys on the worker and
the main thread though equal to nine decimals (`cache_check`); they enter the key in whole
micrometres now, and `cache_check` finds 0 of 4 pieces to rebuild.

| `_p6_perf_exits`, zoom 24 | Before: CPU ms median / worst (n) | After | Worker build, before -> after |
| --- | --- | --- | --- |
| Idle 4 s | 3.8 / 4.9 (1029) | 3.8 / 4.7 (1037) | - |
| Waist river stopping 3.4 m short of the left edge | 4.2 / 23.3 (968) | 4.1 / 23.6 (988) | 669 -> 105 ms |
| Its erase | 4.3 / 22.0 (935) | 4.2 / 29.3 (944) | 704 -> 99 ms |
| The same river drawn past the left edge (a third exit) | 4.2 / 46.3 (1470) | 4.2 / 30.9 (1465) | 885 -> 300 ms |
| Its erase | 4.2 / 22.8 (968) | 4.2 / 29.5 (963) | 694 -> 106 ms |

The carve's ground step for the stroke to the left edge: 42.5 -> 7.3 ms (8.1 in the run with
the mirror fix alone, whose worst frame was 26.1 ms); for the ankle stream to the right edge
48.5 -> 14.0-15.3 ms. The worker build is the water mesh plus the skirt parts; the bake
(113-163 ms) and the main-thread swap (18-22 ms) did not change. `skirt_parts` on the
two-exit map: 593-605 ms built from nothing (a load), 51.5 ms with the skirt's own exits lent
and nothing changed (0 pieces built): the skirt ring and its mirror. **Verdict: an edit away
from the exits lands its water 0.55-0.6 s sooner, one that adds an exit builds only that
exit, and the stroke to the edge's worst frame is back with the others'.** The two erases'
worst frames rose from 22-23 to 29-30 ms in the after run (one sample each); the refresh now
lands about 0.6 s sooner, inside the stroke's other end-of-stroke work rather than after it,
which is the likely reason; not profiled. The exit geometry after P6-3's look fixes: patch
27,625 and ribbon 1,179 vertices for the two exits (P6-2: 28,000 and 1,098; the ribbon runs
on to a fade of 0). A load still builds every exit (the cache helps refreshes only).

### Ponds past the edge (P6-4, 2026-10-05)

`jobs/p6_perf_build.json` now ends with a third map, `_p6_perf_ponds`: `_p6_perf_exits`'s two
rivers and a wide deep pond painted against the near edge (radius 4 m, a 14.5 m wet span; its
lobe, by the seed, an open lake: 50.9 m). `jobs/p6_perf_ponds_play.json` (new, about 2.5
minutes, the pinned `override.cfg`, which it deletes) loads `_p6_perf_exits` and
`_p6_perf_ponds` in turn and measures both at zoom 20 panned to the pond's edge (look_at
-13.5, 27). `gpu_state` 38-39 % P8 255 MHz at each start, 85-96 % P0 1665-1950 MHz at the ends.
Measured before the lobe's end got its own rounding (P6-4's last look fix, which changes only
the half-width table; not re-run).

- **Build (worker):** `skirt_parts` 866-872 ms against 611 ms for the two rivers alone, so
  **about 260 ms per pond exit**, a river exit's cost (the patch is the cost: 12,625 more patch
  vertices, 986 more water vertices). Cached with nothing changed: 57.9 ms (51.4 without the
  pond), 0 pieces built; `cache_check` 0 of 5 across threads. `apply_river_exits` 3.2 ms
  (2.2). Painting the pond to the edge: worst frame 25.4 ms over 1,389 (the rivers' strokes
  24-30 ms in the same run), its refresh's worker build 709 ms (the new exit built), the swap
  22.9 ms.
- **Load:** warm, three interleaved rounds, 1,665 / 1,681 / 1,687 ms without the pond and
  1,901 / 1,883 / 1,955 ms with it: **about +235 ms, on the worker; the worst frame does not
  move** (198-208 against 203-206 ms). Static memory +2.7 MB, vertex buffers +0.7 MB.
- **Draw at the edge:** zoom 20 on the pond's edge, GPU median, two loads of each map in turn:
  2.738 / 2.846 ms without the pond, 3.016 / 3.035 ms with it (the view's own draw count fell,
  299 to 258, where the pond replaced plants): **about +0.23 ms**. The pond's water shown /
  hidden / shown / hidden: 3.038 / 2.907 / 3.068 / 2.910 ms, so the water past the edge (the
  one ribbon surface, the rivers' water in it) is about 0.14 ms of it; the whole skirt hidden
  1.556 ms.

### Erase frame and the stroke's patch (2026-10-05)

**The erase's 29-30 ms frame held.** `jobs/p6_perf_build.json`, two clean runs before the fix
(one more, run while another session rendered, idle median 35 ms, discarded): the short river's
erase 29.7 / 29.7 ms worst, the edge river's erase 24.9 / 30.4, the strokes 23.2-27.3 and
32.1-33.7. `water_timing` now splits the main-thread swap (`AuthoredWater.last_swap_parts`):
18-24 ms of it was `mesh`, 13.7-16.1 ms, all of it `surface_set_material` on the carrier
material that hands the flow texture to `process_water_meshes`. A BaseMaterial3D's generated
shader is shared by the materials with its feature set and freed with the last of them; each
swap freed the old carrier and so the shader, and the new carrier built it again. The same
level loaded from disk paid 0.3 ms (a carrier from the load kept it alive), which is why a
dressed session (`jobs/pol_p6_erase.json`) never showed it and a new map
(`jobs/pol_p6_newmap.json`) always did. One carrier is now kept for the session
(`AuthoredWater._keep_carrier_shader`), warmed as the Water tool opens (`warm_flow_carrier`).

| `_p6_perf_exits`, zoom 24, CPU worst ms | Before (two runs) | After (two runs) |
| --- | --- | --- |
| Waist river stopping 3.4 m short of the left edge | 23.2 / 27.3 | 11.6 / 10.5 |
| Its erase | 29.7 / 29.7 | 9.0 / 11.7 |
| The same river drawn past the left edge | 33.7 / 32.1 | 15.4 / 13.3 |
| Its erase | 24.9 / 30.4 | 10.0 / 12.7 |
| A deep pond painted to the near edge | 28.8 / 25.9 | 20.9 / 21.9 |

The swap 18.3-25.7 -> 4.6-10.2 ms (`mesh` 0.3-0.6; what is left is the surfaces' concave
shapes, 2-5 ms, and `apply_river_exits`, 1.6-3.2). Medians 4.8-5.3 ms in every window of both
(idle 4.8-5.1, against 3.8 in the P6-3 runs; the close-zoom canopy work landed in between). The
first stroke of a new map still has one 22-23 ms frame, the carve's own ground and dressing
upload (`ground` 9-15, `dressing_upload` 18-20 ms), not the swap.

**The stroke's patch.** During a sculpt stroke on the edge the exits' patch now moves with the
in-place skirt (`SkirtExits.update_channel_in_place`, `systems/water.md` "Past the map edge"):
1.8 ms headless for the 18 columns of a 4.5 m strip in one call (normals re-encoded only where
they change: an inner column's ring 0), so a dab's own few columns cost well under that.

## Map size sweep (2026-10-09)

What a bigger authored map costs, to set the custom-size range: the worst-case look (forest
Terraces seed 3: a river with two falls and a plank crossing at every size; every sample
painted with two of eight ground surfaces; the forest filled to density 255) at 200, 250,
300, 350, 400 and 400 x 200 ft. Tooling and commands: `tools/map_size/README.md`. Sizes over
320 ft and the non-square map needed two patches that were reverted afterwards
(`MapDocument.MAX_SIZE_CELLS` 64 -> 80, a `depth_ft` key in `NewMap.from_spec`). Debug
build, RTX 3080, window 1920x1080 (the play job with the pinned `override.cfg`), vsync off for
frame windows. **The GPU was not idle**: `perf.gd gpu_state` read 89-91 % at P3 780 MHz on the
title at the start of both jobs (earlier passes read 29-38 % at P8), so absolute times are
indicative; compare rows within the table.

| Size (ft) | Samples | Document build ms | Open ms | Fill regen ms | ttmap MB (sent) | 4 peers s | Static / video / WS MB, authoring |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 200 | 245 x 245 | 794 | 3,658 (cold) | 5,698 | 1.10 | 4.4 | 370 / 1,674 / 1,480 |
| 250 | 306 x 306 | 1,129 | 2,437 | 7,036 | 1.73 | 6.9 | 382 / 1,678 / 1,564 |
| 300 | 367 x 367 | 1,524 | 3,124 | 8,863 | 2.48 | 9.9 | 395 / 1,681 / 1,589 |
| 350 | 428 x 428 | 2,001 | 3,493 | 10,772 | 3.38 | 13.5 | 411 / 1,687 / 1,635 |
| 400 | 489 x 489 | 2,567 | 4,067 | 14,331 | 4.44 | 17.7 | 430 / 1,702 / 1,640 |
| 400 x 200 | 489 x 245 | 1,261 | 2,707 | 8,678 | 2.22 | 8.9 | 389 / 1,680 / 1,544 |

Document build: `gen.gd time`, `NewMap.from_spec` headless on one thread, median of three (it
runs on a worker under the loading screen in the game; Flat alone is 197-754 ms). Open: the
loading screen from Create to drop (`perf.gd author`). Fill regen: `paint` and `fill` to
`wait_ready` (the whole scatter regenerated at full density). ttmap: the saved level's
`map.ttmap`; zstd gains nothing on it, so it is also what `AssetStreamer` sends, and "4 peers"
is four sends in turn at 1 MiB/s. Everything grows close to linearly with the area. Rows at
400 ft: 120,360, the largest asset 21,926, far from the 1M / 200K caps.

Play and authoring, GPU median ms (CPU median), one run, levels interleaved, 200 ft again at
the end; whole-map zoom in play via `dump.gd fit_zoom`:

| Size (ft) | Warm load ms | Home | Zoom 20 | Play whole map | Authoring whole map | Whole-map prims / draws | Foliage shown |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 200 | 2,638 / 2,799 | 11.0 (12.7) | 14.2 (15.1) | 11.2 (12.4) | 17.1 (18.0) | 3.0M / 1,555 | 100 % |
| 250 | 2,754 / 2,941 | 11.7 (12.7) | 13.8 (14.6) | 12.8 (13.6) | 34.4 (38.2) | 4.8M / 2,052 | 100 % |
| 300 | 3,324 / 3,547 | 12.7 (13.4) | 15.1 (15.9) | 14.3 (15.0) | 45.9 (65.9) | 6.9M / 3,137 | 100 % |
| 350 | 3,741 / 3,888 | 6.1 (11.9) | 12.7 (13.3) | 13.9 (14.7) | 44.3 (65.5) | 8.4M / 4,403 | 89 % |
| 400 | 4,329 / 4,292 | 5.4 (11.4) | 12.4 (13.3) | 13.1 (16.6) | 51.1 (69.0) | 8.6M / 5,736 | 67 % |
| 400 x 200 | 3,306 / 3,567 | 11.6 (12.4) | 13.8 (14.6) | 14.5 (15.2) | 38.3 (65.1) | 6.2M / 3,004 | 100 % |
| 200 again | | 6.0 (6.8) | 13.5 (14.3) | 7.9 (12.0) | 17.9 (18.7) | | |

**Verdict: in play at the table camera a bigger map costs nothing measurable; the builder's
whole-map view and the foliage budget are what grow.** Home and zoom 20 draw 1.3-1.8M and
2.1-3.0M primitives at every size (chunked foliage, the play view capped at 20), and their
times show no trend; the 200 ft drift check held at zoom 20 (14.2 -> 13.5) but not at Home
(11.0 -> 6.0), so Home differences here are contention noise. Loads stay under 4.5 s and
memory grows by about 56 MB static from 200 to 400 ft. The whole-map view grows with the
area until the default 8M foliage budget caps it (from about 330 ft a full forest is thinned
map-wide: 89 % shown at 350, 67 % at 400). Authoring at that view costs 2-3x play at the same
primitives and is CPU-bound from 300 ft (65-69 ms), unprofiled. Above 320 ft the document
format refuses the map (64 cells), and an older peer would too. The recommendation drawn
from this (custom sizes up to 250 ft recommended, 320 ft hard) is in the v0.2 evaluation's
size probe.

## Painted backdrop (2026-10-10, indicative)

The full-screen backdrop shader the title, the room and a map load stand on
(`PaintedBackdrop`, `shaders/ui_backdrop.gdshader`; UI_SYSTEMS.md "Painted backdrop"). The
title at a 1920x1080 window, the real library, the backdrop shown / hidden / shown in one run
(`probes/backdrop.gd gpu_start` / `gpu_stop` / `shown`, sampling the window viewport's own GPU
time every frame for 2.5 s, vsync off; the `gpu` op samples the 3D world's viewport, which the
title has not got). RTX 3080, debug build, other sessions running net tests on the CPU at the
time, so absolute times are indicative. GPU median ms (p10 / p90, frames):

| Backdrop | Shown #1 | Hidden | Shown #2 |
| --- | --- | --- | --- |
| Title, 1920x1080 | 0.259 (0.258 / 0.281, 3,483) | 0.123 (0.122 / 0.124, 5,018) | 0.260 (0.258 / 0.261, 3,913) |
| Title, 1920x1080, round 2 shapes | 0.283 (0.282 / 0.285, 3,586) | 0.128 (0.127 / 0.129, 4,816) | 0.284 (0.283 / 0.285, 3,533) |

**About 0.14 ms of GPU for the whole screen at 1080p**, steady across the two shown windows;
**about 0.16 ms** with round 2's shapes (the distant range, the halo's bloom and three poplars,
the legibility zones gone; same procedure, 2026-10-10). Since card calm-gradients (2026-10-10)
the backdrop is a plain three-stop gradient with no scenery, so these numbers are an upper
bound; it has not been re-measured.
It draws only outside play (a hidden backdrop draws nothing), so it never costs the table a
frame; during a map load the loading overlay's backdrop and the title's under it both draw
until the title is freed.
