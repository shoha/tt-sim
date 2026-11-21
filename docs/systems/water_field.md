# The water field

`WaterField` (`utils/water_field.gd`, with `utils/water_field_stroke.gd`) is the production form of
the painter-water-field-spike's recommended architecture: the water of a document as ONE set of
per-sample fields, from which one surface mesh and one shader draw rivers, ponds, riffles and
falls alike. Stage 1 (the data model, rules mode only) is in main. The combined branch
`painter-water-field-v2` (look-pending, unmerged; it joins the painted-field line to foot3, the native
ports and the conditioner) is stages 1 and 2 plus the native edit path and plan-time conditioning:
the Painted look draws from the field ("Drawing it" below), the field's per-edit passes are native
("Edit latency and the native path"), and a drawn river is conditioned before it is stored
("Conditioning"). Gameplay (`WaterSurface`, zones, walkability, ripples) and Classic still read the
old path (`WaterMeshBuilder`, the fall meshes).
Why the field: eight of the old path's ten seam classes (painter-fall-spike C1-C10) come from
composing separately derived parts; one surface has none of those joins. Evidence and the
alternatives that lost: `docs/plans/handoffs/painter-water-field-spike.md`.

## Model

One water height `w` per sample of the document's grid (`WaterGeometry.DRY` = -INF where no body
holds the sample):

- A river stroke (`RiverProfile.strokes`, the reaches chained) gives every sample within its area
  (half-width, narrowed at a tapered head, plus `RIVER_BANK_M`) the profile's bank level at the
  sample's arc: flat over a reach, eased over a riffle, stepping down a fall's face with the carve.
  A fall is the steep part of the same surface; there is no curtain mesh, no frame and no
  ballistic arc (the arc lies under the carved face on every fall of the spike's map).
- A pond gives its mask its level. Where bodies overlap the highest wins (`owner` says which).
- A river's water that its carve does not hold is `spill` (`SPILL_BANK` beyond the channel,
  `SPILL_POND` over a lower pond): it stands at most a slope above its neighbours (1.2 m/m on a bank,
  0.3 m/m into a pond), so a river ends in a pond on a ramp. The result is the greatest surface under
  those caps (order independent).
- A bank sample standing more than `BANK_HOLD_M` (0.3 m) over its own ground stays dry (no flat ear
  beside a lip).
- Undermined stations (`RiverProfile.stations`: the ground no longer holds the water) in a run of at
  most 2.1 m between held stations are a dip the water bridges at its level; a longer run, or one
  at the stroke's end, is a film (`FILM_M`) over the dug bed inside the channel, and an event.
- A junction is not undermined (card painter-water-junctions; water.md "Junctions"): a station
  whose bank or bed lies in other water standing at its level (from 0.1 m under it to 0.3 m over
  it: another body, or another pass of the same stroke) is held by that water. The two are one
  bed, so a crossing, a join, a fork, a pond over a stream, a self-crossing and the inside of a
  tight bend keep their level and raise no `film_run` or `bridged_run`. The rule lives in
  `RiverProfile.stations` (GDScript, the bank test's inputs); no field channel and no native pass
  was added, and `ttscatter`'s version did not move. `stations().junction` and
  `WaterJunctions.find(doc)` say where. The shader needs no record of a mouth: one bed at one
  level gives the depth one zero contour, so `shore` has no waterline across a mouth ("Marks and
  the one shoreline" below); the cross-fade of two flow frames is a later card.
- The lateral foot tongue: foot foam and riffle white fade by `LATERAL_FADE` toward the channel edge.

Derived per sample (arrays of the grid's size, row-major, `index = z * size.x + x`, sample (0, 0) at
`origin`): `depth` (w - ground, -INF dry, negative on the two buried outer rings that let a mesh
end), `energy` (white water 0..1), `steep` (curtain share 0..1 from the surface slope), `shore`
(signed metres to the waterline, positive in the water, clamped at 4 m), `river` (flow share),
`spill`, `calm` and `owner`.

## Edits: the dirty rect

`WaterField.build(doc)` is `update(doc, whole grid)`, so a full and an incremental build cannot
differ in what they compute. `update(doc, dirty)` redoes the samples in `dirty` and whatever their
change reaches, and returns the rect to refresh. The caller's `dirty` is
`WaterField.rect_of_bodies(doc, bodies)` for the changed bodies as they were (asked before the
edit) and as they are (after it) merged, or the edited ground's rect grown by `INFLUENCE_M` (3 m).
A river reach in `bodies` stands for its whole stroke: the stroke's arc, taper and tables depend on
every reach.

Bit-for-bit equality with a full build holds because every stage is a function of a bounded
neighbourhood: strokes and ponds per sample (the stroke's field is clipped to the rect,
`RiverProfile.field(doc, reach, clip)`); spill as the unique greatest fixpoint under its caps,
recomputed over the connected spill samples that touch the rect; depth, rings, slopes and energy
within `RING_MARGIN` of what changed; shore from the exact distance transform of the boundary
samples within `SHORE_MARGIN`. The transform's tie-breaks are exact in any window only for a sample
step that is a power of two (0.25 m is). `tests/unit/test_water_field.gd` checks equality after a
stroke removal, a level change, a pond removal and ground edits.

Timings (headless GDScript, canonical 61 m map, 245 x 245 samples, 31 bodies, 2026-11-19): full
build about 200 ms (bodies 75, spill 25, derive 45, shore 55); update 16 to 50 ms for a pond, a short
stroke or a ground edit and 25 to 85 ms for a whole long stroke (the biggest stroke's rect is 55 x 138
samples; about 40 percent of the time is the shore transform).

### Edit latency and the native path

Headless, same map, debug DLL, shared machine (medians, 9 runs): GDScript only, a full build 275 ms and
a 60 x 40 update 52 ms; with the library (`ScatterNative.CAPABILITY_WFIELD`) a full build 43 ms,
16 x 16 0.8 ms, 60 x 40 6 ms, a whole stroke's rect (87 x 87) 12 ms. The mesh builder 48 -> 0.4 ms and
the two texture buffers 25 -> 0.2 ms. Nothing changes in the output: the goldens, update equals build
and native equals GDScript (`tests/unit/test_water_field_native.gd`) all hold bit for bit.

- Native (`native/src/water_field.cpp`, `water_field_mesh.cpp`; `utils/water_field_native.gd` packs the
  arrays and constants by name, so they stay in WaterField): `_spill_pass`, `_derive`, `_shore`
  (distance transform and marching-triangles contour included), `RiverProfile.field`'s raster,
  `WaterFieldStroke.foot_seams` (`water_foot_seams`, through `WaterFieldNative.foot_seams`),
  `WaterFieldMesh.build` with the marks' CUSTOM2 in the same call (`water_mesh`'s `c2`) and
  `PainterWaterField`'s texture packing (`WaterFieldNative.pack_textures`). The library's
  `version()` carries `wfield2` since the seam pass and `c2` (`ScatterNative.CAPABILITY_WFIELD`): a
  library with only the first passes (`wfield`) is not used for the field at all, so a stale build
  runs the GDScript twins instead of missing an array.
  Each is ported expression for expression, every intermediate in the type GDScript holds it in,
  and the GDScript stays the reference and the fallback (`ScatterNative.force_gdscript_wfield`).
- GDScript levers (also in the fallback): a stroke whose control points (grown by its widest half-width,
  the bank and a metre) miss the dirty rect is skipped before its profile is built; each stroke's
  `WaterFieldStroke.table` is kept in `_tables` while the profile's shape and the reaches' speeds
  stand (39 KB on the canonical map); `RiverProfile.level_at` is `at().x` without the bed and the
  taper (the table reads it every 5 cm); the riffle white is written from its sparse sources instead of
  gathered by a 28-wide window per entry; `_reset` of the whole grid is bulk fills.
- What is left in a 60 x 40 update (native, about 6 ms): the strokes' profile, stations and per-sample
  write (`_put_stroke`, `stations`), all GDScript. A full build: `_put_stroke` 19 ms, stations 8,
  table 4.5, profiles 4, ponds 2, native passes 5.
- Card painter-water-editcost (2026-11-21; the falls verdict map, level w of painter-water-climb-2:
  245 x 245 samples, 22 bodies, 11 strokes; one stroke's update over its rect of 49 x 113; headless,
  lane held, 20 rounds, median / worst; `tools/render_jobs/local/painter-water-editcost/cost.gd`
  times every phase): main ec129b01 a full build 64.3 / 77.9 ms, an update 11.5 / 16.6, the mesh
  1.06 / 1.21; after it 52.4 / 54.9, 8.6 / 8.7 and 0.53 / 0.71. The foot seam pass went 8.79 to 0.06
  ms in a build and 2.71 to 0.03 in an update (its GDScript twin, pair-wise and inline, 3.02 and
  1.15); the marks' second mesh call is gone (0.5 ms a mesh). What is left in that update: the
  per-sample stroke write (`_put_stroke`) 3.9 ms, `RiverProfile.stations` 1.7, the profiles 0.7, the
  reset 0.7, the raster 0.4, the shore 0.4; in a build `_put_stroke` 23.4, stations 11.5, the table
  4.5, the profiles 4.3, ponds 2.1, the raster 1.9, the shore 1.8, the events 1.1. The next step is a
  native port of `_put_stroke` (its head taper, the lateral coordinate's segment search and the
  tables); nothing smaller is left above 1 ms. Every array (field channels, marks, the mesh with
  CUSTOM2, both texture buffers, both paths, after a build and after every stroke's update) is the
  same as main's on the verdict map, the canonical fixture and every corpus map.
- In a real window (combined branch, debug DLL, f1 fall, `PainterWaterField.update_rect` as the edit
  signals call it; medians of 11): 16 x 16 samples 5.8 ms, 60 x 40 8.4 ms, 87 x 87 12.7 ms of CPU
  (field 4.4 / 7.0 / 11.3, mesh 1.0, both texture uploads queued 0.4), and the next frame ends 0.9 ms
  after the call returns (idle frame 2.2 ms, GPU 1.70 to 1.72 ms before and after: no hitch shows in
  the viewport's GPU time; the upload itself is not isolated). The foot3 shader's cost against main
  (docs/PERFORMANCE.md in-run A/B, 7 kept rounds): +0.066 ms at the fall close view (main 2.22 ms),
  +0.042 ms wide (main 3.46 ms); with the lip card's single flow-map fetch +0.058 and +0.033 (same run: field-v2 +0.077 and +0.032).
- Rules for the native path: nothing in a native pass may differ from its GDScript twin by a bit
  (`tests/unit/test_water_field_native.gd` is the arbiter and covers the foot, `ew` and exact
  waterline arrays); a pass that gains an array adds it to the packed dictionary in
  `utils/water_field_native.gd` and to the test; `RiverProfile.field` calls `ScatterNative` directly
  and must not name `WaterFieldNative` (`test_boot_graph` stays at 349). The foot coordinate is
  computed in GDScript (`WaterFieldStroke.table`, with the drop scale); native only copies it.

## Events: inconsistencies as data

The field never connects water the map leaves apart. `events` (sorted, rebuilt with the field) lists
what a validation card should offer the author to fix:

| kind | meaning | canonical map |
|------|---------|---------------|
| `film_run` | a stretch longer than the bridge whose ground no longer holds its water (`pos`, `length`, `body`) | 1 on the `st` stroke (st_o; 3 before the junction rule, two were its hairpins' insides) |
| `bridged_run` | a short dip the water bridges (information) | 7 |
| `end_near_water` | an open stroke end within 2 m of other water 0.3 m or more above or below (`other_body`, `gap_m`, `level_gap`) | f4: the stream head of body 7, 3.96 m above the deep pond (body 29) |
| `climb` | a stretch of a stroke's reaches whose stored level stands over the lowest level upstream of it by more than the dead band (`pos` where it begins, `reach`, `rise_m`): "Water does not climb" below | 3 on the `st` stroke (its three walls; the fixture was stored before the rule) |

`spill` and `calm` stay readable per sample. A later card adds the plan-time hydrology graph and the
authoring markers; the renderer never guesses.

## Drawing it

`WaterFieldMesh` (`utils/water_field_mesh.gd`) turns a field into one indexed grid mesh (one vertex
per sample, shared by every cell, a ring of buried cells at the edge); `PainterWaterField`
(`painter/painter_water_field.gd`, owned by `PainterWater`) hosts it per painted map and redoes a
dirty rect per edit (`ground_edited`, `AuthoredWater.refreshed`, `rect_of_bodies`; the mesh is
rebuilt whole: 48 ms in GDScript, 0.4 ms native). Vertex contract: CUSTOM0 = (depth, energy, shore distance, steep),
CUSTOM1 = (lateral coordinate, FIELD_FLAG -7, foot flag: 1 within `WaterFieldStroke.FOOT_RANGE_M` of a
fall's foot (the shader fetches the foot coordinate only there), spill mark: 1 a ramp into a pond,
0.5 a bank's thin spill, 0.125 a film). The shader (`painter_water.gdshader`, field branch) reads those instead of
the depth buffer, so the wash, the shoreline, the lap and the white are the model's.

White water is one shape language over the surface: bold flow-carried blobs on the flat
(energy thresholds a stretched noise: cover x smoothstep(0.08, 0.2, energy), the noise only read
where energy is above the floor), and on a fall's face (steep share above 0.05) tongues in the
flow's frame: about 0.28 m columns, each its own width and length, blue glass between. Round 2
compared three face treatments by eye: the spike's noise streaks (a white block with blobs), threads
along the surface's downhill direction, and tongues; tongues read as a falling curtain. A
direction taken per fragment from the surface normal made `dot(p, d)` a maze: the frame is the flow
map's. WaterField rules added in round 2: the ramp of a river into a lower pond keeps
`RAMP_KEEP` (0.2) of its white (on it and within two samples), and has no curtain share (steep is
0 on spill samples and on thin water, under `RAMP_FLAT_M`, beside them): a face of the carve is a
stroke's own sample. Films (undermined water the bridge does not span) draw as mid-depth water
(`FILM_COLUMN_M`), not as the 3 cm they are. The old curtain, `painter_fall_white.gdshaderinc` and
the painted fall mesh's white are deleted; the falls mesh keeps its mist.

Known against main (verdict frames and `metrics.jsonl` in
`docs/research/2026-11-09-prototypes/compare/painter_final83_water_field_painted2/`): seams solved
(lip and foot dW 0.00 to 0.05), ponds calmer; the foot's luminance step (dL) is larger than main's,
f1_t and f1_z show a few holes on the face glass, st_o's lower pool is shallow water (0.15 to
0.5 m) so it reads pale teal where main reads deep blue, and the GPU cost is +0.09 ms at the fall
close view and +0.06 ms wide.

## The exact waterline and the foot rules

The exact waterline: `WaterField.ew` is the surface height per sample as the mesh draws it, and with
`WaterField.exact_shore` (a static switch, on) `shore` is the signed distance to the zero contour of
the depth along grid edges (`WaterFieldContour`, marching triangles), so a bank fades on the terrain's
own line and not the 0.25 m grid's. The mesh's y is `ew`, the depth texture's `fld_a.r` is
`ew - ground` on wet samples (dry ones hold `DEPTH_FLOOR`). Update equals build bit for bit with `ew`.

The foot coordinate: `WaterField.foot` is the signed arc distance to the nearest fall's foot (negative
on the face, positive in the plunge pool), written within `FOOT_RANGE_M` (4 m) of it and across the
pond samples a plunge lands on (a pond has no stroke to own them). It is divided by
`clamp(drop / FOOT_DROP_REF, FOOT_SCALE_MIN, 1)` (3 m, 0.45), so the shader's rules, fixed lengths in
the coordinate, are shorter in metres on a low fall. It rides `fld_b.b` premultiplied by its weight
`fld_b.a` (divided back in the shader), gated by the mesh flag CUSTOM1.z.

Foot seams (card painter-water-climb-2, look-pending). Two falls of one stroke less than twice
`FOOT_RANGE_M` apart share the pool between them: the coordinate is the upper fall's (positive)
up to midway between the two feet and the lower fall's (negative) from there, a jump across zero
between two neighbouring samples (+7.1 to -7.3 on the verdict map's stepped stream). The texture's
linear filter draws every value between the two, the foot's own among them, so the white floor,
the tongues and the veil drew across the calm pool as a ruled white hairline about 3 cm wide,
straight along the seam: the "straight white hairline across the pool" at stpool_z3 and st_w, one
between every two falls, and by the same mechanism the white rungs of a stepped ramp seen from
above. It was not the brink, a reach boundary or the mesh's edge: `DBG_FALL` shows the zone's red
and the foot's contours packed into that one line, `ABL_NOWHITE` leaves only the veil's trace.
`WaterFieldStroke.foot_seams` (switch `foot_seams_cleared`) clears the coordinate on every sample
that has a neighbour of the other sign more than `FOOT_SEAM_JUMP` (2) away, both sides, so no
2 x 2 filter footprint holds the two signs, whatever the seam's angle to the grid and whether one
stroke or two meet there; each side then ends as the coordinate ends at its range (weight 0). The
strokes write `_foot_raw`, `foot` is made from it over the dirty rect grown by one sample (a
function of a 3 x 3 neighbourhood: update equals build). A fall with no other foot in range is
untouched, bit for bit. Cost: the test is symmetric, so the pass (card painter-water-editcost)
tests each pair of neighbours once, from its first sample against the four ahead of it, only where
a sample holds a foot: over the whole grid inside the union of the fall strokes' areas (row spans,
overlaps once), over a dirty rect inside the rect grown by one sample, clearing only the rect. It
runs natively (`water_foot_seams`; the GDScript is the twin): 0.06 ms a build and 0.03 ms an update
on the verdict map (76 samples cleared), where the first pass, an 8-neighbour call per sample, took
8.8 and 2.7 ms. Its oracle is that first definition (`water_corpus_cases.seam_rule`):
`test_water_corpus` asserts every corpus map clears exactly its samples, and
`test_water_field_native` a random grid of both signs, native, GDScript and the rule, over the
whole grid and three rects.

The shader's foot rules, all smooth functions of it (no rule ends on a line): the lower face's white
floor ramps in over `FOOT_FACE_M` above the foot (its line broken by a slow noise), the tongues below
the foot are a smooth value noise across the flow (`FOOT_TONGUE_FREQ`, length up to `FOOT_TONGUE_M`)
that drifts on the master clock (`FOOT_DRIFT_S`; the one clock is `PainterWater.clock_t`, handed
each frame as `p_clock` to the field surface's material AND to the fall material whose mist puffs
step on it since 2026-11-21, so a render job that sets it with the time scale at 0 pins every moving
thing of the painted water: `tools/render_jobs/README.md`), the veil (a milky glaze that tints and thickens the
water, never covers it) reaches `FOOT_VEIL_M` and the white's edge is widened over its whole reach, so
a calm pool shows blue at the foot. The pool's tint floor follows the water's own depth
(`POOL_DEPTH_K` column per metre past 6 cm) so a thin stream pool reads deep and a lip stays shallow.
The lap ribbon reads the signed shore distance averaged over a cross of taps `LAP_SMOOTH_M` out (it
rounds a ledge's corner and drops a thin shelf's finger: the claws the exact contour drew), the exact
one still drives the wash, fade and floor. Known: the dL guardrail at the foot is 2 to 3 times main's
(the white-to-pool transition is a shape, not a plateau), the lip's is 1.2 to 2 times; a straight pit
edge in a stream's pool (st_o, stpool_z3) is the terrain's (the tier sculpt's rectilinear cliff, the dry
capture shows it), not the field's or the shader's.

## The lateral coordinate (card painter-water-curl)

`WaterField.lateral` is the signed distance across the owning stroke's course (`_lateral_of`: the
distance `d` with the sign of cross(segment, sample - segment start), so one side is positive along
the whole stroke and the value is continuous through a bend), written beside `flow_u` where the
stroke owns the sample and 0 elsewhere. It rides CUSTOM1.x (the slot the unread "river share" held;
the native mesh builder copies its "river" array unchanged, `WaterFieldNative` passes `lateral`
under that key, so no DLL change). The shader's `across_u` is that coordinate blended in by the arc
coordinate's weight (`smoothstep(0.2, 0.9, fld_b.g)`, the same ownership as `uf`), and the world
projection `dot(p, across_dir)` elsewhere (ponds, the flat). The tongue columns, the blob and streak
lateral coordinate, the foot tongues and `fd_in`'s noise read it. Why: `across_dir` is the baked flow
map's perpendicular per fragment, which at a stepped stream stands about 43 degrees off the stroke;
`dot(p, a(p))` multiplies a slow drift of `a` by |p| (the fall's distance from the world origin), so
the columns and the lap drew as arches (the sideways curl at st_o). No per-fragment direction (the
flow map's, the surface normal, a screen-derivative gradient of the arc) avoids it; a stored
coordinate does.

The soft brink (card painter-water-lip, look-pending): a fall's white is built down the face, not
stamped at the lip. `WaterFieldStroke.table` writes the `core` as a thin brink line (`BRINK_M` 0.5 m
ramp to `BRINK_PEAK` 0.4 at the lip) and a face that starts at `FACE_TOP` (0.3: a few bright columns
over glass) and builds to the full sheet over `FACE_RAMP` (0.65) of the face's length; the foot foam
decays faster (`FOOT_DECAY_M` 0.4 + 0.2 per metre of drop). The old 0.9 plateau for 0.6 m above the lip
drew an opaque white block under the lip at close zoom. The shader gives the brink's white a wide
gradient edge (above the face where `fd` is under -1 and the steep share is low), the face floor starts
1.4 m above the foot, tongues reach 0.35 m and the veil 1.5 m (glaze 0.24, alpha 0.48), so the pool
keeps more calm blue in a tight frame. The flow-map texel (`fld_b`) is fetched once per fragment (the
foot and the white's flow coordinate share it). Changing these constants moves the energy goldens
(`water_field_transects.json`, regenerated); native is unaffected (the table stays GDScript).

## Marks and the one shoreline (cards painter-water-mouths, painter-water-shoreline; look-pending)

**The white at the water's edge is one function of one distance.** `shore` is the signed distance
to the zero contour of the depth of ALL the water (one pass over the whole field, not per body).
Since the junction work stands the water at one level over one bed wherever water meets water, the
depth has no zero across a stream's mouth in a pond, a join, a crossing or a pond over a stream:
the union's waterline simply does not pass there. The lap ribbon (`painter_water.gdshader`,
"shore_foam") reads that distance and nothing else on the field, so it opens at a mouth by itself,
turns each land corner as one line and runs on along a neck's banks. No rule knows about mouths.

The inventory that led here (2026-11-20; every term that draws white or pale at an edge, the data
it reads and that data's grain):

| Term | Reads | Grain | State |
|---|---|---|---|
| lap ribbon and outer dashes | `shore` (bicubic, plus a 4-tap smoothed copy), the depth-over-distance slope | per sample, filtered, one field for all water | the only edge white on the field |
| the lap's cut on the ramp flag (main) | CUSTOM1.w enum 0 / 0.125 / 0.5 / 1 | per sample, hard, interpolated; written per stroke | removed: stepped ring and ticks at a mouth, an uneven cut along every stream bank (0.5 is over the 0.45 threshold, so every bank band cut the lap by where a vertex fell) |
| the lap's bank cut and mouth fade (card painter-water-mouths) | `bank` share, `mouth` distance | per stroke geometry, continuous | removed: no lap within 0.9 m of a mouth line, so a pond's neck and every land corner lost it |
| depth wrap (`edge_foam`) | `fwidth` of the depth buffer behind the surface | per pixel, screen space | kept for objects only: on the field it needs the scene to stand above the field's own ground |
| film column | `film` share | per stroke, 0/1 | kept (tint, not white) |
| bank-spill fade of the wash | `bank` share, depth | per stroke geometry, continuous | kept (alpha of thin shed water, not white) |
| ramp white (`RAMP_KEEP`), fall foot, tongues | `energy`, `foot`, `lateral` | per stroke tables | not edge white; untouched |

Three structures were compared on corpus f_into_pond, f_pond_over_stream, s1_fall_pond and the
canonical pond's neck, native crops (`cmp_structures.png` in
`docs/research/2026-11-09-prototypes/compare/painter_final110_water_shoreline/`): (A) per-body
marks plus the mouth fade, with the ribbon tapered in width instead of coverage: the neck and the
corners still lose their lap, because the rule itself removes it; (B) the lap from `shore` alone:
one continuous line round every corner, the neck's lap as on main; (C) the shoreline as a drawn
ribbon along the extracted contour: not built, since `shore` already is the exact distance to that
contour (`WaterFieldContour`), so a ribbon would draw the same line and add a mesh, its rebuild per
edit and its sorting against the surface, for an arc coordinate the lap does not use today. B won
by look and by count: it removes two rules, one channel and the mouth finder, and adds none.

`WaterFieldMarks` (`utils/water_field_marks.gd`, `WaterField.marks`) keeps the two continuous
channels the wash still reads, on CUSTOM2 of the mesh (x repeats the depth and w the film, unread):

- `film` (y): 1 on a stroke's film, else 0. `bank` (z): the thin water a bank sheds, rising from 0 at
  the channel's edge to 1 over 0.25 m beyond it (a function of the distance across the stroke).

The `mouth` distance, the per-sample stroke id (`chan`), the mouth-line finder and the grown update
rect are gone. CUSTOM1.w still carries the old enum, unread by the shipped shader: it is what lets
main's shader text draw main's look on this mesh for an exact A/B, and goes with the next native
version.

**The wrap is for objects.** The depth-slope white (`edge_foam`) also fired on the bed's own
silhouette: a crisp hairline along a straight carved bank and a tick past each land corner, a
second mechanism drawing the edge the lap already draws. On the field it is now multiplied by a
lift test: the scene point behind the fragment against the field's own bed where the view ray
lands (`fld_a.r` at the hit point, one bilinear fetch, only where a wrap is present), from
`WRAP_LIFT_LO` 0.06 m to `WRAP_LIFT_HI` 0.16 m. A carved bank has no lift; a token's legs and a
rock do (checked with a token standing in a pond: its wrap is unchanged). Known remainder: at the
foot of a near-vertical cliff (corpus s1_fall_pond) the bilinear bed is off by more than the
threshold and a thin line still draws along the wall.

Tests (`test_water_field_marks.gd`): the marks in range and deterministic, update equals build
(marks and `shore`) after ground edits, level changes and each stroke's removal, CUSTOM2 the same on
both mesh paths; and the shoreline's invariant: along a stream's centre line through eleven corpus
meetings (stream into pond, through a pond, two inflows, pond chain, pond over stream, fall into
pond, tributary, crossing) `shore` never comes within the lap's reach (0.6 m) of a waterline.
Native: the marks are written in GDScript (the stroke's per-sample write is GDScript too); the
native mesh builder takes `film` and `bank` beside its other arrays and returns CUSTOM2 as `c2`,
(depth, film, bank, film) per vertex, in the one call (card painter-water-editcost, `ttscatter 10`;
it was a second call with the marks in c0's slots, 0.5 ms more per mesh rebuild).

Known defect of the one distance (measured 2026-11-20, not fixed: a native change): the shore pass
measures each sample to the crossing and contour piece of its NEAREST BOUNDARY SAMPLE only, and
where two boundary samples tie it can take the one whose crossing lies further, so `shore` reads up
to 0.18 m long on the second row of samples from a bank: steps of 0.33 m (corpus flat, 71 pairs)
and 0.43 m (steps, 23 pairs) between neighbours 0.25 m apart, at notches of the bank; beyond
`EXACT_M` up to 0.13 m long along whole columns. A true distance steps at most 0.25 m. The fix:
in `water_shore` (native and the `_shore` twin) compare the candidates of every boundary sample in
the 3 by 3 round the nearest one (their crossings, and within `EXACT_M` their contour pieces), bump
`version()`, regenerate the shore goldens, and tighten the test's two-step bound to one step.

Attributed, not this card's: the ladder of white rungs on a fall's ramp into a pond seen from above
(corpus s1_fall_pond, top, zoom 8) is on main too and goes only with `ABL_NOWHITE` (not with the
lap or the wrap off): it is the fall face's tongue columns (the energy white), not an edge mark.
The faint arc across a ring's closure (f_loop) is in the wash, as before.

## What the sample grid shows through (card painter-water-fielddata, attribution only)

Measured 2026-11-21 on the falls verdict map and the corpus, with every mark switched off, with the
shader's `DBG_DATA` and `DBG_LAP` views and with headless dumps of the channels. Nothing was changed.

- **A stroke's stored levels can climb, and the field draws the climb as a wall of water.** The
  stepped stream of the falls map (one stroke, 16 reaches) runs over three tier walls: its reach
  levels go 1.03, 0.58, 0.14, -0.15, then UP 0.08, 0.49, 0.95, down to -0.15, up to 0.94, down to
  -0.15, up to 1.14, down to -0.15 (the plan keeps such a course as drawn rather than cut a gorge:
  "Conditioning" below). Each pool below a fall therefore has water standing 1.1 to 1.3 m higher
  just downstream. Across the course the higher pass wins its samples, so between two neighbouring
  samples `w` steps 1.29 m with deep water on both sides (st_o's pool, z = -10.75: 1.139 at
  x = 23.23, -0.148 at x = 23.48, ground 0.82 and -0.56, steep 1, slope white 0.6, both held, no
  spill flag). That step follows the samples the higher pass owns, so it is a staircase in plan:
  the "teal stair steps", the "straight top" and the "white tick" in the pool below the stepped
  stream's fall are the far edge of that higher water seen from its own side. It is the mesh, read
  per pixel: the same per vertex, with the film and bank marks off and under either of two repairs
  of the spill sample's surface (drawn at the upper level extended, or draped 4 cm over its
  ground), neither of which touches it. No change to the field's filters or the shader's wash
  removes it: the rule that does is "Water does not climb" below (card painter-water-climb).
- **The square white blocks in the lap on a steep pond bank are the lap on a one-sample shelf.**
  Where a stream's bank line survives under a pond (a land wedge's end face, straight and on the
  grid) the water over it is shallow for its distance from the waterline, so the lap's slope share
  is 0 there and the ribbon is drawn with its crisp 3 cm edge, one sample wide, beside banks whose
  share is 1 and whose ribbon is a wide brushed band. The cross of four shore taps is not the
  cause (the block stays with the plain bicubic distance), nor is the bank-shed water the wash
  hides (measuring `shore` to the visible waterline instead moves the block a little and changes
  4 to 9 percent of the pixels of the falls frames).
  Measured again 2026-11-21 (card painter-water-lap, nothing built): at the two corpus blocks
  the middle row and column of a field dump show a bank that is gentle for a whole metre, not one
  sample. `f_pond_over_stream`, across the bank at z = -33.70: depth 0.036, 0.117, 0.245, 0.392,
  0.539 at shore 0.22, 0.46, 0.71, 0.97, 1.22 (depth over distance 0.16 to 0.44, all under the
  share's start of 0.5). `f_two_inflows`, along the wedge's end face at x = 10.90: seven samples
  3 to 4 cm deep in a straight row (z = -36.76 to -35.26) at shore 0.14 to 0.20, then 0.23 m
  deep; across it 0.041, 0.109, 0.186, 0.279 at shore 0.20, 0.45, 0.70, 0.95. The first wet row
  therefore sits at a distance inside the range of the lap's threshold (0.05 to 0.26 m, set by
  the bite noise, a blob about 0.4 m across), with the crisp edge of share 0 and a distance that
  is flat along a straight face: where the bite is high the white covers the first row, where it
  is low it stops short, and the patch between is the block. One row and one column were read
  per site, so a bank of share 1 a few samples along the shoreline is not ruled out (`DBG_LAP`
  shows share above 0 toward the streams' own banks). Three shader structures for the share were
  drawn beside the shipped one (`lap_structures_corpus.png`): the slope from the means of the
  0.4 m cross the smoothed waterline already reads (no new fetch) and the larger of that and the
  local slope both leave the blocks as they are; the slope from a cross twice as wide removes
  the block at the first site and weakens it at the other two, but thins the lap to a faint
  band, adds four fetches near every shore and changes 2.2 to 4.2 percent of the pixels of every
  frame by more than 8 levels (f1_o 2.6 percent, max 155). None won. Not tried: the bite's range
  or its frame (it is isotropic in the world, so a blob is as long along the shore as across).
- A mouth's bands and a ring's closure showed no step on the sample grid: soft contours of the
  depth through the wash's bands.

Evidence: `D:/dev/tabletop/docs/research/2026-11-09-prototypes/compare/painter_final114_water_fielddata/`.

## Conditioning

The events above are what a stroke can leave behind; conditioning removes the ones plan time can fix and turns the rest into
hints. Parts, all pure: `WaterCourseFit` (Douglas-Peucker, loop trim, penalised least squares,
displacement capped at 0.5 half-widths after thinning, width slope limit), `WaterConditioner`
(`fit_levels`: lattice 0.05 m, cummin so water is only lowered, dead band 0.25 m swept from the
outlet upstream, min reach 2 m, falls kept; `solve_tree` for the river and pond tree, ponds pinned),
`WaterPorts` (`end_decision`, `graph`, `audit`, the dig-aware `refit_stroke`), `WaterRefit`
(`refit`: reverse climbing runs, solve, re-carve), `WaterHints` (the records and their text).
Parameters: dead band 0.25 m is the knee of the sweep (0.10: 24 reaches, 0.76 m largest lowering;
0.25: 21, 0.86 m; 0.50: 20, 1.21 m on the canonical map). Measured on the canonical fixture by the
spike: rises 9 to 0, film runs 3 to 0, falls 8 to 5, field_rise 4.53 to 0.09 m, wet cells 5019 to
4087; plan_river 8.95 to 10.47 ms (the end join plans a second time when an end joins), tree solve
0.65 ms. Rules to keep: condition BEFORE the carve (a doc-level solve on a carved map raised perched
edges 33 to 45, so `refit` carves again); conditioning runs once on the authoring peer and the
bodies are stored; a plan that would cut a gorge is never forced: it is kept as drawn and said
(`blocked_cut`, `over_hill`, `perched_head`) when as drawn it only descends, and cut to its
descending part when it climbs (next section). Known limits: a re-drawn stroke's levels barely
stabilise (spread 0.37 to 0.35 m, only the reach count settles); the dig refit trades film for
drained stretch; `refit` has no cut limit (next section).
Tests: `test_water_conditioner.gd` (the units, the fuzzer, the tables), `test_water_condition_
pipeline.gd` (plan_river on and off, the report, hints, the editor's undo and redo and worker,
`refit_document` and `refit_water`, water does not climb).

## Water does not climb (card painter-water-climb, look-pending)

The rule: along a stored stroke, in its flow direction, no reach stands over the lowest reach
upstream of it. Whatever the author draws becomes a river that descends, a pool, a fall or an honest
end, never water standing up a rise.

Where the climb came from (measured 2026-11-21). The only leak was a BLOCKED plan: the running
minimum asks the carve to cut a ridge down to the pool before it, `condition_ranges` refuses a cut
over `CUT_LIMIT_M` (1.5 m), and `plan_river` then stored the unconditioned plan, whose reach levels
follow the ground up the ridge. The verdict map's "stepped stream" is that case: its three `tier`
strokes are U-shaped paths whose arms are 20, 12 and 5.5 m apart, so they raise three WALLS, not
tiers, and the stream crosses them (stored climb 1.30 m; the canonical fixture, the same recipe,
1.22 m). Nothing else climbs: 56 corpus strokes 0, 79 strokes of 60 fuzz maps 0 (one blocked plan,
descending), the verdict map's other eight strokes 0. The perched-head case of the tests
(`head_near_pond`) also climbed, 3.38 m in nine reaches: its line starts on the tier's ramp.

What a blocked plan becomes now (`WaterEdit._descending`, switch `WaterEdit.stop_at_rise`):

- as drawn it only descends: kept as drawn, as before; a rise within the dead band drops onto the
  lowest level upstream (0.2 m of climb still draws as a step along the samples);
- as drawn it climbs (`WaterConditioner.climbs`): the line is split at its troughs and crests
  (`WaterConditioner.monotone_parts`: a crest heads the part that descends from it, a trough ends
  the part that descends into it, a climbing part holds the reaches between and is turned round
  so it runs down from its crest; a line drawn uphill the whole way is one climb, turned whole).
  `plan_river` returns the longest part that descends as drawn, planned again as a stroke of its
  own (conditioned, its ends joined or tapered), and lists the other parts in `report.rest` as
  lines that each run downhill. The author's ground is never cut for any of it. The hint
  `stopped_at_rise` says the line was split (`report.stopped`, `kept_m`, `drawn_m`).

The gesture is not lost (card painter-water-climb-2). `plan_river` returns one chain to about
twenty callers, so the parts land in the editor: `WaterEditor.carve_river` hands `report.rest` to
the edit's worker (`_compute_rest`), which plans each part on the snapshot as it stands with the
parts before it carved, carves it and adds it, at most `WaterEdit.MAX_PIECES` (8), a part's own
rest queued behind. A part that ends in the pool of a part before it takes that pool's level (it
ends in the tapered tail, where the carved ground is the pool's surface, and would stand 0.15 m
under it). A part the plan refuses (too short to hold water) is dropped, and so is a part whose
own plan would cut more than `WaterEdit.REST_CUT_M` (0.5 m, one reach's span) into the drawn
ground: planned alone, a part over a 1.6 m wall levels the crest to its pool with a cut just
under the 1.5 m limit that blocked the whole line (measured on the test walls: 2.72 m of ground
removed against 1.44 m for the longest part alone), which is the gorge the rule exists to
refuse. `WaterEditor.last_report` says how many landed (`pieces`) and the metres dropped
(`dropped_m`). One job, one landing, ONE history entry: undo removes every part. The test walls
(a 25 m line over three walls, `test_a_gesture_over_walls_lands_every_part_in_one_entry`): more
than the longest part lands, no stored climb, the pools at the feet one level, no cut more than
0.5 m deeper than the longest part's own. On the verdict map's line over its walls two parts
land (view `walls_w`): the stream off the last wall and a flat reach on that wall's terrace that
shares its head; the walls north of it stay dry and whole. Callers of `plan_river` other than
the editor (tests, the corpus builder) still land the one part. Not done: a part that reaches
the map edge gets no skirt course of its own (only the first part's ends are attached,
`RiverExits.attach`), the toast is said at plan time, before the worker knows what was dropped,
and `WaterRefit.refit` still reverses and cuts (it should use `monotone_parts` too).

Stored documents are drawn as stored: the field reports each climb as a `climb` event and a re-fit
removes it. Two structures were compared on the stored verdict map before the plan rule was
chosen (`cmp_structures.png` in the evidence folder): today's `refit` (climbing runs reversed,
then the tree solve and the re-carve) leaves no climb but CUTS THE WALLS: the solve lowers the
reversed reaches to the pool and the carve follows, a gorge of 1.3 m the plan itself refuses, with
pale film slabs beside it; dropping the climbing reaches (a dry sill, a head at the crest) keeps
the falls but the kept tail 0.2 m over its pool and the untapered head at the crest still step
along the samples. Open: `refit` should apply the plan's rule (drop what climbs, never cut past
`CUT_LIMIT_M`) instead of reversing and cutting.

Evidence: `D:/dev/tabletop/docs/research/2026-11-09-prototypes/compare/painter_final116_water_climb/`.

## Debug

`WaterField.debug_image()` is a false-colour image (ground, depth, steepness, energy, shore) for a
probe to save as a PNG. There is no overlay toggle yet (a toggle would touch the authoring UI; the
render card adds it with the mesh).

## Tests and fixtures

`tests/unit/test_water_field.gd`; `tests/fixtures/water_field_canonical.ttmap` (the spike's 61 m
canonical map rebuilt by its build job on main's code; 163 KB), `tests/fixtures/water_field_transects.json`
(w, depth and energy every 0.25 m along the lines of f1, f2, f5 and st; regenerate through
`regenerate_goldens` only for a deliberate change of the model).

## Staged plan

1. water-field-model (this doc): the data model.
2. water-field-painted: `WaterFieldMesh` and the field shader replace the painted water and curtain.
3. water-field-white: the foam look.
4. water-field-gameplay: `WaterSurface`, walkability, zones and ripples read `w`; Classic gets the
   mesh; the old cells, cascades, fall meshes and frames go. Deletable once stage 4 lands (the
   Painted path no longer reads them after stage 2): `WaterFallFrames` and the frame channels
   (CUSTOM0/1) of `WaterMeshBuilder` and `WaterFallMesh`, `WaterFallMesh`'s curtain and ring (the
   mist stays or moves), the legacy branch of `painter_water.gdshader` (depth-buffer shore, lap and
   white, kept for Blender maps' water planes), and `painter_waterfall.gdshader`'s curtain code.
5. water-hydrology-validation: the plan-time check over `events`. Done as water-condition: the
   plan-time conditioner, hints and re-fit above; the markers drawn on the map for the hints are not
   built (the toast says them).
