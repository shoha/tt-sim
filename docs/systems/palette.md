# Built-in palette

What in-game authoring paints from: treecube's biomes, species, ground surfaces and placement
rules, shipped inside tt-sim under `assets/palette/` (Git LFS) and installed by treecube's
`scripts/build_palette.py`. The contract with the producer is
[../ASSET_PIPELINE.md](../ASSET_PIPELINE.md) section 9; the producer side is treecube's
`README.md` "Palette for tt-sim". This doc holds the system's map and the rules the code keeps
(moved from `AGENTS.md` Key Conventions on 2026-10-09).

## Map

| File | Class | Role |
|------|-------|------|
| `utils/palette_library.gd` | `PaletteLibrary` | Static, cached per root, default root `res://assets/palette`. Reads `palette.json` lazily on first use; the read access, `resolver()` and `resolve()` |
| `assets/palette/` | | The built-in palette: `palette.json`, the asset GLBs and their committed `.glb.import` sidecars |
| `utils/scatter_glb_utils.gd` | `ScatterGlbUtils` | `build_scatter()`, the resolver-driven scatter core that `process_scatter_instances()` wraps for GLB maps |
| `utils/wind_foliage.gd` | `WindFoliage` | `apply_material`, which mutates surface materials in place; `classify_category()` |

## Model

- `PaletteLibrary` validates `palette.json` like network input: caps, malformed entries
  skipped with a warning, never raises. No palette is an empty palette.
- Read access: `biomes()`, `biome()`, `species()`, `surfaces()`, `asset()`,
  `ground_accents()`, `path_surfaces()`. The last two are optional per-biome fields; a palette
  without them reads `[]` silently.
- `resolve()` returns a fresh `Mesh.duplicate()` per call, because `WindFoliage.apply_material`
  mutates surface materials in place. It takes the wind category from the manifest, never from
  `classify_category()`.

## Runtime

- `PaletteLibrary.resolver()` plugs into `ScatterGlbUtils.build_scatter()`, the
  resolver-driven core that `process_scatter_instances()` wraps for GLB maps.
- Asset GLBs load through `ResourceLoader` (the editor import; an export ships no raw `.glb`)
  with the committed `.glb.import` sidecars: textures embedded uncompressed, no LODs, no shadow
  meshes.
- After a palette refresh, write those sidecars before the first import (contract section 9
  "Import path").

## Verification

- `tests/unit/test_palette_builtin.gd` guards the `.glb.import` sidecars.
- `tests/unit/test_palette_library.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
