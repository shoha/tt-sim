# The water field

`WaterField` (`utils/water_field.gd`, with `utils/water_field_stroke.gd`) is the production form of
the painter-water-field-spike's recommended architecture: the water of a document as ONE set of
per-sample fields, from which one surface mesh and one shader will draw rivers, ponds, riffles and
falls alike. Stage 1 of 5 (the data model, rules mode only): nothing draws from it and nothing reads
it yet. The old path (`WaterMeshBuilder`, the fall meshes, `WaterSurface`) still does everything.
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
   mesh; the old cells, cascades, fall meshes and frames go.
5. water-hydrology-validation: the plan-time check over `events`.
