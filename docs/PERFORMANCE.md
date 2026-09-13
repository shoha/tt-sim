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

`utils/foliage_budget.gd` caps total scatter primitives per map at `PRIMITIVE_BUDGET`
(8,000,000) and thins any imported map that exceeds it, proportionally across species,
by seeded shuffle. `ScatterGlbUtils.process_scatter_instances()` applies it;
`level_loader.gd` shows the player one toast when it fires. Allocation keeps an equal
instance fraction per species, not equal visual weight -- see "Real-map validation"
below for what that costs the map's landmark trees in practice.

The threshold is **provisional** -- derived from one scene on one GPU. The frame-time
table above (16.3M foliage primitives, -76%) used the in-game debug toggle's definition
of "foliage", which excludes rock scatter -- but the budget covers scatter of every kind,
rock included. The real total the budget has to bound, measured by running the actual
pipeline against the real GLB, is **19,170,768 primitives** (see below). Both figures are
correct for what they measure: 16.3M is still the right number for the frame-time table,
captured with that toggle; 19.17M is the right number for what `PRIMITIVE_BUDGET` bounds.
8M is **41.7%** of 19.17M, not "roughly half" as an earlier estimate against the narrower
toggle figure put it. This needs validating on slower hardware before release -- the
mechanism is the deliverable, the threshold is a tunable. The budget is deliberately not
overridable per level: a budget a map can opt out of does not bound anything.

Only `user://` imported maps are affected. `load_map()`'s `res://` branch never calls
the scatter pipeline, so built-in maps are untouched. **Known gap:**
`MeshInstancingUtils.process_duplicate_mesh_instancing()` (`utils/glb_utils.gd`, called
after every scatter-pipeline call site) runs AFTER `ScatterGlbUtils.process_scatter_instances()`,
so any foliage arriving through the duplicate-collapse path is not bounded by this budget
at all -- not yet addressed.

### Real-map validation (Sandy Clearing, 112 MB)

Ran the real pipeline against the actual Sandy Clearing GLB, not a synthetic test fixture.

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

## Spatial foliage chunking

A `MultiMeshInstance3D` is frustum-culled as a single AABB. Foliage was one map-wide
MultiMesh per species, so every instance was vertex-processed whenever any part of that
species was on screen. All the figures below come from a probe that replays the real
pipeline -- `FoliageBudget.plan`, `FoliageBudget.select_indices` and
`ScatterChunker.bucket_by_cell`, the same functions `process_scatter_instances` calls --
against the real map, then counts per camera zoom which chunk AABBs intersect the view.
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
reference map). **These are geometric figures -- counts of which chunk AABBs the probe
found intersecting the view -- not rendered output from a GPU:**

| chunk size | nodes | zoom 2 | zoom 5 | zoom 10 | zoom 20 |
| --- | --- | --- | --- | --- | --- |
| unchunked | 57 | 57 / 7,957,006 | 57 / 7,957,006 | 57 / 7,957,006 | 57 / 7,957,006 |
| 25 | 199 | 137 / 4,094,814 | 150 / 6,283,242 | 174 / 7,610,722 | 176 / 7,843,338 |
| 15 | 656 | 0 / 0 | 2 / 4,320 | 14 / 1,151,794 | 284 / 6,222,732 |
| 10 | 1335 | 0 / 0 | 0 / 0 | 17 / 431,868 | 731 / 5,932,752 |
| 8 | 1885 | 0 / 0 | 0 / 0 | 3 / 586,032 | 831 / 6,143,696 |
| 5 | 2747 | 0 / 0 | 0 / 0 | 4 / 147,376 | 1193 / 5,310,072 |

The chosen value is **10.0**, for these reasons: 25 is dominated (barely better than
unchunked while tripling node count); 5 adds 1,136 draw calls over baseline at full
zoom-out to save 33% of primitives, the trade most likely to cost more than it buys; and
between 15 and 10, 10 saves 62% more primitives at typical play zoom for three more draw
calls, which is where players spend their time. 15 is better only at full zoom-out, where
both figures are large and the primitive budget rather than chunking is the binding
constraint.

**Frame time was NOT measured.** The validator MCP bridge cannot activate the title
screen's buttons -- clicks at window coordinates, clicks at 1920x1080-space coordinates,
Enter on the focused button, and Tab-then-Enter were all tried across two sessions, and
it was confirmed not to be caused by the measurement harness. So no rendered before/after
exists. The sweep figures are geometric: exact about what culling can discard, silent
about what it costs. The open risk to name is the 731 draw calls at full zoom-out.

**The shadow-cascade hypothesis is still untested.** The existing entry below concludes
that shortening `directional_shadow_max_distance` does nothing because "every caster is
already inside 30 units" from shadow primitives being byte-identical at 15,586,440 across
100 / 50 / 30. The hypothesis was that this was an artefact of one map-wide AABB per
species intersecting every shadow cascade, so nothing could be culled -- and that chunking
might unlock it. Measuring `shadow_primitives` needs a real render, which the bridge could
not provide. Chunking has now landed; re-testing the shadow-distance lever against a
chunked build is an open follow-up.

**Map load time was NOT measured.** The design that proposed chunking named load time as
a user-visible cost a frame-time win does not excuse, and that cost has not been
measured on this branch. What is known by inspection: per-instance work is unchanged
(the same transforms are read and the same number of `MultiMesh.set_instance_transform`
calls happen either way), and the added cost is roughly 1,278 extra `MultiMesh`
allocations and node additions on the reference map (1,335 chunk nodes built vs. 57
species before chunking), so it is expected to be small -- but expected is not measured.

## Known dead ends -- do not revisit without new evidence

- **General triangle budgets.** 420x the geometry cost only 9.2x the frame time. Raw
  triangle count is not the binding constraint; foliage instance count is.
- **Terrain decimation.** Terrain not casting shadows saved 0.03 ms. Terrain is free.
- **Distance-based LOD, billboards, impostors keyed on camera distance.** The camera is
  orthographic, so apparent size does not shrink with depth -- degrading distant foliage
  is *more* visible here than in a perspective game. The orthographic-correct
  reformulation is zoom-based, driven by `camera.size`. Not yet attempted.
- **Automatic mesh LOD.** Godot picks one LOD per MultiMesh node, not per instance, and
  orthographic screen coverage does not vary with distance.
- **Occlusion culling.** A `MultiMeshInstance3D` cannot be an occludee in the bake
  workflow, and all foliage here is MultiMesh.
- **PCF shadow filter tuning.** Measured at 0.6 ms. Not worth touching.
- **Shortening `directional_shadow_max_distance`.** Swept 100/50/30: shadow-pass
  primitives were byte-identical at 15,586,440 for all three, because every caster is
  already inside 30 units -- this may have been an artefact of one map-wide AABB per
  species intersecting every shadow cascade. Spatial chunking has now landed; re-testing
  this lever against a chunked build is an open follow-up. Recorded in
  `level_environment_manager.gd`.
- **`alpha_to_coverage` for the shadow pass.** Does not help (godotengine/godot#84242).
- **`visibility_range` to skip distant foliage.** Hidden instances stop casting
  directional shadows entirely (godotengine/godot#98993), which changes lighting.

Grass no longer casts shadows (measured -16% of frame time): Godot runs the shadow
pass's `fragment()` with the same code as the colour pass (godot-proposals#4443), and
the foliage shader's alpha-cutout `discard` disables early-Z for that draw, so dense
overlapping grass pays full fragment cost per covered sample. A base-dark/tip-light
albedo gradient in `WindFoliage.apply_material` replaces the contact darkening the real
shadow used to provide.

## How to measure without fooling yourself

Three separate instrument failures produced three wrong conclusions during this work.
All three are avoidable:

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
settings at boot and overrides `override.cfg`. Then per run: load the level, press
**Home** for a deterministic camera pose, press **F3** (perf logging only starts when
the overlay is open), wait ~30 s, and read `user://perf_logs/` filtering `elapsed_s > 5`.
Confirm `primitives` and `draw_calls` match between samples before comparing them; if
they differ, the camera differed and the pair is invalid.

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
