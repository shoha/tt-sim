# Content library

The unit of content for in-game authoring: a LIBRARY is a data-only folder (GLBs, a catalog,
biome definitions, later surfaces) with its own id and version, compiled by tt-sim into exactly
the palette form [palette.md](palette.md) already validates, so scatter, ground, water and fire
need no change. The bar is the one the palette is judged against (plants that read as a place),
plus one rule of its own: a library compiled from files must reproduce the package it was built
from byte for byte before it is allowed to replace anything. The design and the numbers behind
it are plantgen's `docs/library_format_and_module_design.md` (sections 0 to 3, 6 and "S0 probe
results"); this doc holds what is built and the rules the code keeps. Step S1 (2026-10-24):
savanna as a one-biome `core` library, behind an opt-in developer path.

## Map

| File | Class | Role |
|------|-------|------|
| `utils/library/library_contracts.gd` | `LibraryContracts` | The closed vocabulary (contract 1): roles with kind and default size class, class defaults, habit flags and defaults, caps, the key tables the reader warns against, `export_json()` (the `contract.json` plantgen vendors; regenerate with `tools/compile_library_cli.gd --contract <file>`) |
| `utils/library/library_ids.gd` | `LibraryIds` | The id grammar and the one mapping to runtime ids, `runtime_biome`, `runtime_asset`, `biome_field`, `runtime_surface`, `parse_runtime_biome`, `library_of`, `resolve_alias`, the portable-names checks (`path_problems`, `segment_problems`, `case_duplicates`) |
| `utils/library/library_reader.gd` | `LibraryReader` | `read(sources)` over the TEXT of `library.json`, `assets/catalog.json`, `biomes/*.json` and the file list: schema, caps, unknown-key warnings, portable names, existence and exact case; returns `{ok, errors, warnings, library, catalog, catalog_order, biomes}`, never throws |
| `utils/library/biome_compiler.gd` | `BiomeCompiler` | `compile(read, options)`: one palette biome per season and the asset table, with `role`, `habit`, `weight` and `library` riding on each rule; runs `validate_palette` and returns its warnings |
| `utils/library/library_registry.gd` | `LibraryRegistry` | The only module that lists or reads folders: `read_sources`, `compile_folder`, the dev override (`set_dev_override`, settings `[library] dev_path`), `apply` (lays the compiled library over the palette), `served`, `clear` |
| `utils/palette_overlay.gd`, `utils/palette_library.gd` | `PaletteOverlay.read_palette`, `PaletteLibrary.install_overlay` | The existing overlay merge, split so a palette already in memory takes the same path as a package folder (`read` and `overlay_package` call the same code) |
| `utils/foliage_library.gd` | `FoliageLibrary` | `apply()` calls `LibraryRegistry.apply()` last, so the content library is a layer over whichever foliage library is served; `apply_saved()` also reads the persisted dev path |
| `tools/compile_library_cli.gd` | | Headless: prints or writes the compiled palette JSON of a library folder, or `--contract <file>` |
| `tools/render_jobs/driver.gd`, `jobs/library_s1_savanna.json` | op `library_dev` | Sets the override for a run and rebuilds the open map |
| `tests/fixtures/library_savanna/`, `library_savanna_compiled.json`, `library_mini/` | | The savanna JSON (no GLBs) with its frozen compiled golden; a three-asset, two-rule library |

## Model

- **Folder.** `library.json` (format `ttsim-library` 1: id, name, version, contract, ...),
  `assets/catalog.json` (format `ttsim-catalog`: one entry per GLB with id, category, size_class,
  wind_category, dimensions_m, file, node), `biomes/<id>.json` (format `ttsim-biome`: seasons,
  ground names, `ground_look` verbatim, rules). Data only: `.json .glb .png .jpg .txt .md`; the
  reader never loads a library file as a resource.
- **Rules.** Each rule has a closed `role` (`LibraryContracts.ROLES`: it supplies the palette
  `kind`, the default size class and align and a default `habit`), explicit numbers (a missing one
  takes the class default; a missing density takes the class default times `density_factor`
  with a warning) and `query.match[].ref` entries naming catalog ids. Other query clauses
  (category, tags, counts) are warned about and skipped in this build. `near` and `avoid` take a
  `rule` or a `role` (a role expands to every rule of that role), compiled to the palette's
  `species` key; a relation to a rule that was dropped is dropped with a warning.
- **Runtime ids (S0 P4).** Core keeps today's ids (`savanna_summer_s1`, assets
  `savanna_summer_s1/Tree_Acacia_v0`); another library `<lib>__<biome>_<season>_s<seed>`, and
  its palette `biome` field is `<lib>__<biome>`. No `/` in a library id, biome name or local
  asset id; no `__` in a library id or biome name; the whole asset id under 160 characters
  (`PaletteLibrary.MAX_ID_LENGTH`; a longer one is skipped with a warning); every season and seed
  gets its own asset prefix (live edits accept an asset only when its prefix is the whole
  biome id). Seasons expand without overrides in this build.
- **Portable names (S0 P5).** Rejected as reader errors: case-insensitive duplicate ids, files
  or paths; Windows device names (also with an extension); a trailing dot or space; a backslash,
  colon or drive letter; `..`; a path over 120 characters; a catalog file whose exact case is not
  in the file list. Listings are sorted explicitly, never trusted for precedence.
- **Validation layers.** The reader's errors block a library, its warnings (unknown keys,
  unsupported features) do not. `palette.json`'s `validate_palette` is a WHITELIST that silently
  drops unknown keys, so the reader is the only place a typo in a biome-def is caught; every new
  compiled field a later step makes the scatter code read (`role`, `habit` in S2) must be added
  to `_validate_species` in the same step. Until then they live in the compiled result only, and
  the served palette is exactly what a package would give.
- **Paths.** Compiled assets keep a library-relative `file` (the palette contract: relative, no
  `..`, no scheme). The absolute file of each asset is `compiled["paths"]`, joined from the
  folder; nothing `path_join`s an absolute second argument (it concatenates, S0 P5).
- **Merge.** Each compiled biome replaces the palette's biome of the same runtime id together
  with all its `<id>/` assets (the overlay's rule), so a core `savanna_summer_s1` replaces
  treecube's. Surface names resolve against the base palette (`surfaces: legacy`); the library
  carries no surfaces yet.
- **Architecture rules** (pinned by `test_library_compile.gd`): the four pure modules use no
  `FileAccess`, `DirAccess`, `EventBus`, `ResourceLoader` or scene tree; only the registry lists
  folders; nothing in `utils/library/` calls `load()`.

## Runtime

The dev override is OFF by default and nothing changes without it. Set it with settings.cfg
`[library] dev_path="<library folder>"` (read by `FoliageLibrary.apply_saved()` at start-up, so
the first palette read already sees it), or for one run with `LibraryRegistry.set_dev_override()`
(the render-job op `library_dev`, `tools/compile_library_cli.gd`). `FoliageLibrary.apply()` /
`switch()` clear the caches, lay the plantgen package when chosen, then call
`LibraryRegistry.apply(root)`: read and compile the folder, then `PaletteOverlay.read_palette`
and `PaletteLibrary.install_overlay` (the same cache install, wind layout guard included). The
GLBs are parsed by `PaletteOverlay.parse_mesh` (`GLTFDocument`, mesh compression off), the path
the plantgen package route takes. A library that does not read or compile changes no cache and
reports why (`result["error"]`, a `push_warning` from the foliage library). The map rebuilds on
`EventBus.foliage_library_changed` as for the plantgen switch; two switches in quick succession
leave the first one's rows (a pre-existing property of `FoliageLibrary.switch`; the job waits
with `wait_ready` between them).

## Authoring

None yet: the library manager and the biome designer are steps S6 to S9 of the design.

## Verification

- Unit tests: `test_library_ids.gd` (grammar, runtime ids, portable names, contract tables and
  export), `test_library_reader.gd` (the miniature library reads clean; malformed and hostile
  files: unknown keys, newer versions, reserved ids and names, case duplicates, missing and
  wrong-case files, bad roles and numbers, caps), `test_library_compile.gd` (the savanna golden
  with zero `validate_palette` warnings, the mini library under a prefix, role defaults and role
  relations, a missing catalog id, an over-length asset id, two seasons, the registry over a
  scratch palette root, GLB loading, a failing library changes nothing, the architecture
  rules), `test_library_row_parity.gd`.
- Golden: `tests/fixtures/library_savanna_compiled.json` is `compile_library_cli.gd --out` of
  `tests/fixtures/library_savanna` (copy plantgen's `out/lib_slice` JSON files; regenerate the
  golden only after checking the diff below is still 0).
- Parity with the package route (plantgen `out/lib_slice`, built from `out/lib_slice_pkg`),
  all of it outside the repo so it is a command, not part of the gate:

```
godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/compile_library_cli.gd -- --library D:/dev/plantgen/out/lib_slice --out <compiled.json>
godot --headless --path D:/dev/plantgen --script res://tools/library_diff_cli.gd -- --compiled <compiled.json> --package D:/dev/plantgen/out/lib_slice_pkg
# PowerShell: $env:PLANTGEN_LIB_SLICE='D:/dev/plantgen/out/lib_slice'; $env:PLANTGEN_LIB_SLICE_PKG='D:/dev/plantgen/out/lib_slice_pkg'
godot --headless --path D:/dev/tabletop/tt-sim --script res://addons/gut/gut_cmdln.gd -- '-gconfig=tests/.gutconfig.json' -gselect=test_library_row_parity
godot --path D:/dev/tabletop/tt-sim --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_jobs/run.gd -- library_s1_savanna
```

  2026-10-24: the diff tool reports 0 differences (13 rules, 34 assets); the row test passes
  (the same species rules, and byte-identical rows for every asset at seed 1234 over a 32 m
  square, against both `lib_slice_pkg` and the stable `ttsim_package_plantgen_all`); the render
  job's package and library captures (home and size 14) are pixel-identical (mean absolute
  difference 0.000 of 255).

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work". The library steps (S2 onwards:
role and habit flags read by the scatter code, surfaces, the multi-library registry and map
`libraries` record, the manager, the designer) are in plantgen's design doc section 6.

## History

- 2026-10-24: step S1, tt-sim half: `utils/library/`, the dev override, `compile_library_cli`,
  the tests and the `library_dev` render op.
