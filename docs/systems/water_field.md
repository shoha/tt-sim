# The water field

`WaterField` (`utils/water_field.gd`, with `utils/water_field_stroke.gd`) is the production form of
the painter-water-field-spike's recommended architecture: the water of a document as ONE set of
per-sample fields, from which one surface mesh and one shader draw rivers, ponds, riffles and
falls alike. Stage 1 (the data model, rules mode only) is in main; stage 2 (this branch, look-pending,
unmerged: "Drawing it" below) makes the Painted look draw from it. Gameplay (`WaterSurface`, zones,
walkability, ripples) and Classic still read the old path (`WaterMeshBuilder`, the fall meshes).
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
samples; about 40 percent of the time is the shore transform). If an edit must be under 50 ms for the
longest strokes, port the shore transform and the stroke rasteriser to the scatter DLL; not needed
for the stage-1 data model.

## Events: inconsistencies as data

The field never connects water the map leaves apart. `events` (sorted, rebuilt with the field) lists
what a validation card should offer the author to fix:

| kind | meaning | canonical map |
|------|---------|---------------|
| `film_run` | a stretch longer than the bridge whose ground no longer holds its water (`pos`, `length`, `body`) | 3 on the `st` stroke (st_o) |
| `bridged_run` | a short dip the water bridges (information) | 7 |
| `end_near_water` | an open stroke end within 2 m of other water 0.3 m or more above or below (`other_body`, `gap_m`, `level_gap`) | f4: the stream head of body 7, 3.96 m above the deep pond (body 29) |

`spill` and `calm` stay readable per sample. A later card adds the plan-time hydrology graph and the
authoring markers; the renderer never guesses.

## Drawing it (card painter-water-field-painted, look-pending, unmerged)

`WaterFieldMesh` (`utils/water_field_mesh.gd`) turns a field into one indexed grid mesh (one vertex
per sample, shared by every cell, a ring of buried cells at the edge); `PainterWaterField`
(`painter/painter_water_field.gd`, owned by `PainterWater`) hosts it per painted map and redoes a
dirty rect per edit (`ground_edited`, `AuthoredWater.refreshed`, `rect_of_bodies`; the mesh is
rebuilt whole, about 50 ms). Vertex contract: CUSTOM0 = (depth, energy, shore distance, steep),
CUSTOM1 = (river share, FIELD_FLAG -7, foot flag: 1 within `WaterFieldStroke.FOOT_RANGE_M` of a
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

## The exact waterline and the foot rules (cards painter-water-foot2 and -foot3, look-pending, unmerged)

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

The shader's foot rules, all smooth functions of it (no rule ends on a line): the lower face's white
floor ramps in over `FOOT_FACE_M` above the foot (its line broken by a slow noise), the tongues below
the foot are a smooth value noise across the flow (`FOOT_TONGUE_FREQ`, length up to `FOOT_TONGUE_M`)
that drifts on the master clock (`FOOT_DRIFT_S`), the veil (a milky glaze that tints and thickens the
water, never covers it) reaches `FOOT_VEIL_M` and the white's edge is widened over its whole reach, so
a calm pool shows blue at the foot. The pool's tint floor follows the water's own depth
(`POOL_DEPTH_K` column per metre past 6 cm) so a thin stream pool reads deep and a lip stays shallow.
The lap ribbon reads the signed shore distance averaged over a cross of taps `LAP_SMOOTH_M` out (it
rounds a ledge's corner and drops a thin shelf's finger: the claws the exact contour drew), the exact
one still drives the wash, fade and floor. Known: the dL guardrail at the foot is 2 to 3 times main's
(the white-to-pool transition is a shape, not a plateau), the lip's is 1.2 to 2 times; a straight pit
edge in a stream's pool (st_o, stpool_z3) is the terrain's (the tier sculpt's rectilinear cliff, the dry
capture shows it), not the field's or the shader's.

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
5. water-hydrology-validation: the plan-time check over `events`.
