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
| `utils/palette_library.gd` | `PaletteLibrary` | Static, cached per root, default root `res://assets/palette`. Reads `palette.json` lazily on first use; the read access, `resolver()` and `resolve()`. The public names (the constants, `validate_palette`) are unchanged by the S2 split below |
| `utils/palette_validator.gd`, `palette_surfaces.gd`, `palette_fields.gd` | `PaletteValidator extends PaletteSurfaces extends PaletteFields` | The validation, split out of `PaletteLibrary` in step S2: `PaletteFields` the constants and the untrusted-value checks, `PaletteSurfaces` the surfaces table and a biome's ground fields, `PaletteValidator` assets, biomes and rules (the whitelist of rule fields is `_validate_species`); `PaletteLibrary` re-exports the constants and `validate_palette` delegates |
| `utils/palette_asset_files.gd` | `PaletteAssetFiles` | `load_mesh` / `load_scene`: an asset GLB's Mesh from the imported scene or a runtime parse |
| `utils/legacy_habit.gd` | `LegacyHabit` | The legacy key and kind lists (emergent, bank, arid, charred) and `for_key`; the fallback for a rule with no `habit` |
| `assets/palette/` | | The built-in palette: `palette.json`, the asset GLBs and their committed `.glb.import` sidecars |
| `utils/scatter_glb_utils.gd` | `ScatterGlbUtils` | `build_scatter()`, the resolver-driven scatter core that `process_scatter_instances()` wraps for GLB maps |
| `utils/wind_foliage.gd` | `WindFoliage` | `apply_material`, which mutates surface materials in place; `classify_category()`; `reset_caches()` (the warm-up representatives) |
| `utils/palette_overlay.gd` | `PaletteOverlay` | A built package folder laid over the loaded palette (`PaletteLibrary.overlay_package`) |
| `utils/library/surface_store.gd` | `SurfaceStore` | (S3) Where every consumer gets a surface map: `GroundPalette.load_texture`, `GroundLayerArrays.surface_image`, `SwatchTextures.palette_thumbnail` and `BiomeThumbnail` call it. An installed palette's path is the editor import, unchanged; a content library's surface is baked from its PNGs to the same formats ([library.md](library.md)) |
| `utils/foliage_library.gd` | `FoliageLibrary` | The runtime choice between the installed palette and a plantgen package (below); it also layers the developer content library ([library.md](library.md)) last |

## Foliage library (treecube or plantgen)

Added 2026-10-23 so two foliage libraries can be compared in the running game. `treecube` (the
default) is the installed palette; `plantgen` is a package built by `D:/dev/plantgen/tools/
build_ttsim_package_cli.gd`, a folder in `build_palette.py`'s shape that stays outside the repo.

- Setting: `user://settings.cfg` section `foliage`, keys `library` (`treecube` or `plantgen`) and
  `package_path` (the package folder, empty by default; a dev setting with no menu row). The F3
  debug panel's "Foliage library: plantgen" checkbox exists only when `package_path` holds a
  `palette.json`; checking it serves the package, unchecking it the installed palette, and the
  choice is persisted. Root applies the saved choice at startup, before the graphics warm-up.
- `FoliageLibrary.apply()` is the one place that applies a choice: it clears `PaletteLibrary`'s
  caches and `WindFoliage.reset_caches()` (the warm-up representatives and the layout guard key on
  the default palette), then for plantgen lays the package over every biome with
  `PaletteLibrary.overlay_package`. The overlay has no undo of its own and needs none: it only
  replaces cached palette entries, so clearing the cache is the removal and the installed palette
  reloads lazily. A missing or unreadable package changes nothing (or falls back to treecube)
  and says why. `switch()` is `apply()` plus the setting plus `EventBus.foliage_library_changed`.
- The open map rebuilds on that signal (`Root._on_foliage_library_changed`): authoring calls
  `AuthoringController.reopen_async()`, which rebuilds the map from the document in memory (the
  camera is untouched, the active tool, selected biome and unsaved state carry over, the undo
  history is dropped because its entries point at the old nodes); a solo table reloads its level
  through `play_level` (tokens are set out again from the level's saved placements); a networked
  table is only told to reload, since a reload clears every peer's table.
- Saved maps hold scatter rows keyed by asset id, and the libraries name their assets
  differently (installed `alpine_meadow_summer_s1/Bush_Round_summer_04`, package
  `alpine_meadow_summer_s1/Bush_Bush_v0`; only the rocks, whose GLBs are byte-identical, share
  ids), so a map saved under one library has rows the other cannot resolve. The rows are derived data: the document keeps the biome painting and the seed.
  `FoliageLibrary.adapt_async()` (called by `MapSourceLoader.load_async` and by the reopen)
  regenerates `doc.scatter` and its mass anchors from the painting under the active library
  whenever any scatter asset is missing from the palette, on a worker over a snapshot, through
  the same `ScatterRegen.run` (native where built) the brushes use; it announces this once with a
  toast. A map that resolves is left alone, so treecube keeps its authored rows. What is lost is
  hand work in the scatter itself (erased plants return, which only matters to a map edited by
  hand); hand-placed props are not regenerated, and the ones the library lacks are skipped by the
  build like any missing asset and counted in the toast. Saving while plantgen is served writes
  the regenerated rows, so keep the compared map's saved copy untouched (the A/B jobs never save).
- Render jobs: the op `foliage_library {name, package, fades_off}` and the jobs
  `plantgen_ab.json` (authoring, same cameras before and after) and `plantgen_play.json`
  (play); [../../tools/render_jobs/REFERENCE.md](../../tools/render_jobs/REFERENCE.md).

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
- Surface maps are uniform per kind (contract section 9 "Surface map uniformity"): every
  albedo, normal, ORM and height map is 1024x1024 with full mips in one imported format per
  kind (BC7, BC5, BC1, uncompressed L8), so a map's surfaces stack into `Texture2DArray`s
  as they are. treecube's `build_palette.py` refuses a surface that breaks it.

## Verification

- `tests/unit/test_palette_builtin.gd` guards the `.glb.import` sidecars and the surface
  maps' `.png.import` sidecars (one compression and mip setting per map kind).
- `tests/unit/test_palette_library.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
