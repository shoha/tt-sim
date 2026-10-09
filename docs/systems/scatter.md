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
`test_pipeline_warmer.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
