# Palette

What in-game authoring paints from: biomes, species, ground surfaces and placement rules, served
from the content libraries (the shipped `core`, built by plantgen, under `res://libraries/core`,
Git LFS: [library.md](library.md)). The palette FORM, `palette.json`'s shape the validator reads,
is still [../ASSET_PIPELINE.md](../ASSET_PIPELINE.md) section 9 (the producer was treecube until
2026-10-25; now the library compiler writes it in memory). This doc holds the system's map and
the rules the code keeps (moved from `AGENTS.md` Key Conventions on 2026-10-09).

## Map

| File | Class | Role |
|------|-------|------|
| `utils/palette_library.gd` | `PaletteLibrary` | Static, cached per root; the default root `res://libraries` is virtual and served by `LibraryRegistry` on first use, any other root is read from its `palette.json` (how tests build palettes). The read access, `resolver()` and `resolve()`. The public names (the constants, `validate_palette`) are unchanged by the S2 split below |
| `utils/palette_validator.gd`, `palette_surfaces.gd`, `palette_fields.gd` | `PaletteValidator extends PaletteSurfaces extends PaletteFields` | The validation, split out of `PaletteLibrary` in step S2: `PaletteFields` the constants and the untrusted-value checks, `PaletteSurfaces` the surfaces table and a biome's ground fields, `PaletteValidator` assets, biomes and rules (the whitelist of rule fields is `_validate_species`); `PaletteLibrary` re-exports the constants and `validate_palette` delegates |
| `utils/palette_asset_files.gd` | `PaletteAssetFiles` | `load_mesh` / `load_scene`: an asset GLB's Mesh from the imported scene or a runtime parse |
| `libraries/core/` | | The shipped core library (GLBs, catalog, biome-defs, surfaces, thumbnails; `importer="keep"` sidecars so the raw files ship in the pack) |
| `utils/scatter_glb_utils.gd` | `ScatterGlbUtils` | `build_scatter()`, the resolver-driven scatter core that `process_scatter_instances()` wraps for GLB maps |
| `utils/wind_foliage.gd` | `WindFoliage` | `apply_material`, which mutates surface materials in place; `classify_category()`; `reset_caches()` (the warm-up representatives) |
| `utils/library/library_layer.gd` | `LibraryLayer` | Lays a compiled content library over the palette cache without parsing any GLB (`lay`; S10 moved it out of the deleted `PaletteOverlay`) |
| `utils/library/asset_store.gd` | `AssetStore` | (S4) The mesh of an asset a content library supplies, keyed by (library id, asset id): `PaletteLibrary._source_mesh` asks it for any id it serves (`AssetStore.serves`), and loads a plain palette's GLB for the rest (test palettes). Lazy GLTFDocument parse from a file path, sha256-checked for a non-official library ([library.md](library.md) "AssetStore"); `PaletteLibrary.clear_cache` clears it |
| `utils/library/surface_store.gd` | `SurfaceStore` | (S3) Where every consumer gets a surface map: `GroundPalette.load_texture`, `GroundLayerArrays.surface_image`, `SwatchTextures.palette_thumbnail` and `BiomeThumbnail` call it. A plain palette's path is the editor import, unchanged; a content library's surface (core's too) is baked from its raw PNGs to the same formats ([library.md](library.md)) |
| `utils/foliage_library.gd` | `FoliageLibrary` | Serves the content libraries (official, user, the developer override: [library.md](library.md)) into the palette and adapts a map to them (below); `refresh_libraries()` serves them again |

## Serving the palette (since S10, 2026-10-25)

The palette is no longer a folder in the repo. `PaletteLibrary.DEFAULT_ROOT` (`res://libraries`)
is a virtual root: whatever `LibraryRegistry` serves (the OFFICIAL libraries under
`res://libraries`, led by `core`, then the user's and the developer override) is compiled and laid
into the cache of that root on the first read, or when `FoliageLibrary.apply()` /
`apply_saved()` runs (Root does it at start-up, before the graphics warm-up). The whole story is
[library.md](library.md), "The core library". treecube's installed palette (`assets/palette/`, its
imported GLBs, surfaces and thumbnails, the F3 "Foliage library" checkbox, the `[foliage]`
package switch and the plantgen-package overlay) was deleted; the history of how the two were
compared is in git and in [../ASSET_PIPELINE.md](../ASSET_PIPELINE.md) sections 9 and 14 (marked
historical).

- `FoliageLibrary.apply(root)` clears `PaletteLibrary`'s caches and `WindFoliage.reset_caches()`
  (the warm-up representatives and the layout guard key on the default palette) and serves the
  libraries again. A library that cannot be served changes nothing and says why (an entry with
  status error in the manager, a warning in the log). `refresh_libraries()` is `apply()` plus
  `EventBus.foliage_library_changed`.
- The open map rebuilds on that signal (`Root._on_foliage_library_changed`): authoring calls
  `AuthoringController.reopen_async()`, which rebuilds the map from the document in memory (the
  camera is untouched, the active tool, selected biome and unsaved state carry over, the undo
  history is dropped because its entries point at the old nodes); a solo table reloads its level
  through `play_level` (tokens are set out again from the level's saved placements); a networked
  table is only told to reload, since a reload clears every peer's table.
- Saved maps hold scatter rows keyed by asset id. The rows are derived data: the document keeps
  the biome painting and the seed. `FoliageLibrary.adapt_async()` (called by
  `MapSourceLoader.load_async` and by the reopen) regenerates `doc.scatter` and its mass anchors
  from the painting under the served libraries whenever any scatter asset is missing from the
  palette (a map saved under treecube's ids, a removed library), on a worker over a snapshot,
  through the same `ScatterRegen.run` (native where built) the brushes use; it announces this once
  with a toast. A map that resolves is left alone. What is lost is hand work in the scatter itself;
  hand-placed props are not regenerated, and the ones no library has are skipped by the build like
  any missing asset and counted in the toast. A painting naming a biome nobody serves grows
  nothing. No compatibility work exists for treecube-era ids (no users, user decision 2026-10-25).
- Render jobs: the op `foliage_library {fades_off}` re-serves the libraries and rebuilds an open
  map; `library_dev {path}` sets the developer override (core against a dev folder is the
  A/B now); [../../tools/render_jobs/REFERENCE.md](../../tools/render_jobs/REFERENCE.md).

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
- Asset GLBs load through `AssetStore` (`GLTFDocument` over the file's bytes, from the pack or a
  folder; `ResourceLoader` is never used for a library file). They are `importer="keep"` files in
  the pack, so there is no import step and no `.glb.import` settings to keep.
- Surface maps are uniform per kind (contract section 9 "Surface map uniformity"): every
  albedo, normal, ORM and height map is 1024x1024 with full mips in one baked format per kind
  (BC7, BC5, BC1, uncompressed L8; `SurfaceBake`), so a map's surfaces stack into
  `Texture2DArray`s as they are. The surface reader refuses a set that breaks it.

## Verification

- `tests/unit/test_palette_builtin.gd` guards the shipped core as the served palette: counts, roles,
  the constant keep sidecar beside every PNG, GLB and JPG, every asset resolving with its wind
  data, a species per biome building chunks.
- `tests/unit/test_library_row_parity.gd` pins the nine biomes' rows to the frozen package route.
- `tests/unit/test_palette_library.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
- 2026-10-25: step S10: treecube's installed palette, `PaletteOverlay`, the foliage-library
  switch and `LegacyHabit` deleted; the palette is what the libraries serve.
