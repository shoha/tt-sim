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

## Known dead ends -- do not revisit without new evidence

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
settings at boot and overrides `override.cfg`. Then per run: load the level, press
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
