# Scatter

The plants and rocks of an authored map: the generator that turns a palette biome and painted
density into document rows, and the node that builds those rows into instanced meshes and
rebuilds them cell by cell as an author paints. The long form is
[../ARCHITECTURE.md](../ARCHITECTURE.md) "Scatter generator" and "Authored scatter"; the
performance side is [../PERFORMANCE.md](../PERFORMANCE.md). This doc holds the system's map and
the rules the code keeps (moved from `AGENTS.md` Key Conventions on 2026-10-09).

## Map

| File | Class | Role |
|------|-------|------|
| `utils/scatter_generator.gd` | `ScatterGenerator` | Pure statics. `generate()` turns a palette biome plus density, height and normal Callables into document rows for a set of 10 m chunk cells; `document_fields()` and `generate_for_document()` adapt a `MapDocument` |
| `utils/scatter_plan.gd` | `ScatterPlan` | The sampling plan and the density calibration models: `DENSITY_RESPONSE`, `additive_clumps`, `CLUMP_SATURATION` |
| `utils/authored_scatter.gd` | `AuthoredScatter` | Node3D under `LevelMap` that builds an authored map's palette scatter: `build_all(rows)`, `set_cells(rows_by_cell)`, `attach_document()`, `request_region(rect)`, `species_added` |
| `utils/scatter_regen.gd` | `ScatterRegen` | Regenerates the touched cells on `WorkerThreadPool` |
| `utils/pipeline_warmer.gd` | `PipelineWarmer` | Draws each resolved species once, invisibly |
| `utils/scatter_mass.gd` | `ScatterMass` | Grass masses (a clump with `mass` 1, `ScatterPlan.MASS_FIELDS`): ellipse membership, core growth, zone keeps, bare openings, shoulders, and the mass anchors (collect, custom data, the level's anchors entry) |
| `utils/ground_look.gd` | `GroundLook` | A biome's `ground_look`: `BASE` (every contract key) and the lenient merge `PaletteLibrary` keeps on the biome |
| `utils/ground_zones.gd` | `GroundZones` | The per-biome, per-seed zone record (read-only, carried on each mass plan entry) and the CPU twin of the ground shader's zone functions |
| `utils/map_anchors_io.gd` | `MapAnchorsIO` | The optional `mass_anchors.json` entry of `map.ttmap` |

## Model

- Chunk output must stay region-independent: every random choice comes from a hash of (map
  seed, biome, field, bucket, index), never from iteration order or a shared RNG, and spacing
  is resolved by Matern III on that global field. `test_scatter_generator.gd` compares a chunk
  alone, with neighbours and in the whole map byte for byte.
- Thinning (paint, pattern, slope, clumps, relations) happens after spacing, so painted
  density thins even a saturated packing.
- Paint enters through a per-size-class response (`ScatterPlan.DENSITY_RESPONSE`): trees lead,
  ground cover lags, and all are exactly 1 at full paint so the palette calibration holds.
- Overlapping clumps add up (`ScatterPlan.additive_clumps`, capped at `CLUMP_SATURATION`
  overlaps), so dense ground cover forms drifts.
- Grass masses (ground ship, contract section 9 "Ground look and grass masses"): a clump with
  `mass` 1 keeps the union of its clumps, may be an ellipse turned per parent (or along the
  zone edges with `follow`), grows its core tufts into one mound, and drops whole swathes by
  the zones the ground draws. The zones come from the biome's `ground_look` and the map seed
  (`GroundZones.record`, `seed_offset`), built once per plan and read by the workers; no level
  stores a zone field. A palette without the mass fields grows exactly the rows it grew before
  (`test_scatter_mass.gd` pins every built-in biome's rows at seed 1234: first written on main's
  code path; re-pinned at the ship palette's install, where the six zoned biomes' grass moved
  and the taiga, badlands and burnt forest, which carry no mass fields, kept main's rows).
- Each mass row carries its anchor (the clump parent) beside the rows, keyed by the row's saved
  (x, z): the generator fills `ScatterRegen.run`'s "anchors" (passed through the result, never
  a static table: the round 10 probe kept one, written from `WorkerThreadPool` threads, and one
  of its runs died silently; cause unconfirmed, 2026-10-14), `AuthoredScatter.mass_anchors`
  merges them and every MultiMesh it builds (settled, growing and shrinking nodes) writes
  `Color(0, dx, dz, 1)` into the instance's custom data (`.x` stays free for the burn shader).
  A level saves them as the optional `mass_anchors.json` entry; `MapSourceLoader` validates it
  against the rows and each rule's reach and drops a bad asset's anchors with a warning. GLB
  scatter (`BaseScatterEraser`) and the pipeline warm-up never carry anchors.
- Every chunk node an authored scatter builds (`ScatterGlbUtils.build_chunk`: settled, growing,
  shrinking) draws on `LevelEnvironmentManager.SCATTER_RENDER_LAYER`, which the level's
  reflection probe leaves out: the probe captures once when a map opens, before a new map's
  cover grows in but after a reopened level's is built, and a probe that saw the scatter drew
  reopened ground and grass 3-6 levels darker (2026-10-15). A Blender map's own scatter stays
  on layer 1.

## Runtime

- `AuthoredScatter` builds with `build_all(rows)` at load and `set_cells(rows_by_cell)` per
  10 m cell, with one always-suffixed `<asset>_MultiMesh_c<x>_<z>` node per (asset, cell).
- Species resolve once and rebuilds never create materials. A species first painted
  mid-session emits `species_added`: pass it to `GameMap.adopt_foliage_materials()` and
  `LevelEnvironmentManager.add_wind_materials()`.
- Never rebuild authored cells through `build_scatter()`.
- Authoring prepares every palette biome as a map opens (the first palette mesh load compiles
  the pipelines all species share, under the loading screen), and each resolved species is
  drawn once invisibly by `PipelineWarmer`; see [../PERFORMANCE.md](../PERFORMANCE.md)
  "First-use pipeline compilation in authoring".

## Authoring

Brushes call `attach_document()` + `request_region(rect)`, which regenerates the touched cells
plus the relation halo on `WorkerThreadPool` via `ScatterRegen` (latest request wins per cell)
and grows new instances in (the `grow` instance uniform in every wind shader variant). Removed
scatter shrinks out ([authoring.md](authoring.md)).

## Verification

Unit tests in `tests/unit/`: `test_scatter_generator.gd` (region independence, byte for byte),
`test_scatter_generator_calibration.gd`, `test_scatter_build.gd`,
`test_scatter_ground_rules.gd`, `test_scatter_chunker.gd`, `test_authored_scatter.gd`,
`test_pipeline_warmer.gd`, `test_scatter_mass.gd`.

`test_scatter_mass.gd`'s golden rows (`tests/fixtures/scatter_golden_1234.json`) run on Windows
only, where the pre-push gate runs them; elsewhere the test is pending. The digest hashes raw
float bytes and the platforms' maths libraries differ in the last bit: CI on Linux (run
38845734590, after the ground ship's push on 2026-10-15) generated other bytes for six of nine
biomes, the taiga and the trees included, though no mass field touches them (9980dfbc).

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
