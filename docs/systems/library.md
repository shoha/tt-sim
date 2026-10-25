# Content library

The unit of content for in-game authoring: a LIBRARY is a data-only folder (GLBs, a catalog,
biome definitions, surfaces) with its own id and version, compiled by tt-sim into exactly
the palette form [palette.md](palette.md) already validates, so scatter, ground, water and fire
need no change. The bar is the one the palette is judged against (plants that read as a place),
plus one rule of its own: a library compiled from files must reproduce the package it was built
from byte for byte before it is allowed to replace anything. The design and the numbers behind
it are plantgen's `docs/library_format_and_module_design.md` (sections 0 to 3, 6 and "S0 probe
results"); this doc holds what is built and the rules the code keeps. Step S1 (2026-10-24):
savanna as a one-biome `core` library, behind an opt-in developer path. Step S3 (2026-10-24):
surfaces without editor imports (`SurfaceStore`) and the library bindings.

## Map

| File | Class | Role |
|------|-------|------|
| `utils/library/library_contracts.gd` | `LibraryContracts` | The closed vocabulary (contract 1): roles with kind and default size class, class defaults, habit flags and defaults, caps, the key tables the reader warns against, `export_json()` (the `contract.json` plantgen vendors; regenerate with `tools/compile_library_cli.gd --contract <file>`) |
| `utils/library/library_ids.gd` | `LibraryIds` | The id grammar and the one mapping to runtime ids, `runtime_biome`, `runtime_asset`, `biome_field`, `runtime_surface`, `parse_runtime_biome`, `library_of`, `resolve_alias`, the portable-names checks (`path_problems`, `segment_problems`, `case_duplicates`) |
| `utils/library/library_reader.gd` | `LibraryReader` | `read(sources)` over the TEXT of `library.json`, `assets/catalog.json`, `biomes/*.json` and the file list: schema, caps, unknown-key warnings, portable names, existence and exact case; returns `{ok, errors, warnings, library, catalog, catalog_order, biomes}`, never throws |
| `utils/library/biome_compiler.gd` | `BiomeCompiler` | `compile(read, options)`: one palette biome per season and the asset table, with `role`, `habit`, `weight` and `library` riding on each rule; the palette's `surfaces` are the base table plus the library's own (S3); runs `validate_palette` and returns its warnings |
| `utils/library/surface_bake.gd`, `surface_reader.gd` | `SurfaceBake`, `SurfaceReader` | (S3, pure) `surface.json` and PNG-header checks (`check_info`, `check_png`: sizes 4 to 2048, bit depth 8 or 16, a normal map with colour channels), the bake of a decoded PNG to the imported formats (`bake`, `format_of`, `data_size`), the palette entry of a library surface (`palette_entry`), and the reader of the `surfaces/` folder |
| `utils/library/surface_cache.gd` | `SurfaceCache` | (S3) The raw `TTIMG` cache under `user://library_cache/<library id>/<hash>/<surface>_<map>.ttimg`: header (magic, version, engine string, format, size, mips, length, SHA-256) plus `Image.get_data()`; never a resource |
| `utils/library/surface_store.gd` | `SurfaceStore` | (S3) The one place the ground, crossings, swatches and biome thumbnails get a surface's maps: `texture(root, relative)`, `image(root, relative)`, `available`, `texture_of` / `image_of(root, name or lib:// ref, kind)`, `runtime_name` / `ref_of` (the `lib://<library id>/<name>` convention), `register_library`, `label_of`, `load_set(folder)` and `load_installed(root, name)` (the two forms, for the equality test) |
| `utils/library/library_bindings.gd` | `LibraryBindings` | (S3) The named things code needs (`fire.ash_surface`, `fire.ash_fallback`, `fire.burnt_biome`, `crossings.planks/moss/gravel/stone_default/paving`, `paint.default`, `water.bed/shore`, `default_biome`) with the legacy values as defaults; `value(key)` answers from the served libraries, else the default |
| `utils/library/library_registry.gd` | `LibraryRegistry` | The only module that lists or reads folders: `read_sources`, `compile_folder`, the dev override (`set_dev_override`, settings `[library] dev_path`), `apply` (lays the compiled library over the palette), `served`, `clear` |
| `utils/palette_overlay.gd`, `utils/palette_library.gd` | `PaletteOverlay.read_palette`, `PaletteLibrary.install_overlay` | The existing overlay merge, split so a palette already in memory takes the same path as a package folder (`read` and `overlay_package` call the same code) |
| `utils/legacy_habit.gd` | `LegacyHabit` | (S2) The legacy key and kind lists (`EMERGENT_KEYS`, `BANK_KEYS`, `CHARRED_KEYS`, `ARID_KINDS`) in one place, `for_key(key, kind)` and `export_table()` (published in `contract.json` as `legacy_habit`, so plantgen's importer derives a rule's explicit habit from the same lists). `ScatterGround.habit_of(rule)` returns the rule's own `habit`, else this |
| `utils/palette_validator.gd` (+ `palette_surfaces.gd`, `palette_fields.gd`, `palette_asset_files.gd`) | `PaletteValidator` | (S2) `palette_library.gd` was at gdlint's 1000-line cap and is split; the rule whitelist in `PaletteValidator._validate_species` / `_library_fields` keeps `role`, `habit`, `weight` |
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
  compiled field a later step makes the scatter code read must be added to `_validate_species`
  in the same step. Since S2 the whitelist keeps `role` (a `LibraryContracts` role), `habit`
  (`{water: ""|"bank"|"emergent"|"arid", charred: bool}`: the role's habit with the rule's own
  flags over it, present whenever the rule has a role or a habit) and `weight` (0 to 1000); a
  bad value warns and is dropped, an absent one never warns, and a rule with none of the three
  (treecube's palette, plantgen's package) is unchanged byte for byte. `library` is still
  dropped silently (nothing reads it before S4).
- **Habit.** `ScatterGround.plan_role` reads `habit_of(rule)`: the rule's `habit`, else the
  LEGACY lists of `LegacyHabit` (keys of reeds, willows and snags, kind `cactus`). The lists stay
  for legacy palettes only; a library rule never needs them. `test_legacy_habit.gd` pins that
  the fallback, an explicit habit built from `LegacyHabit.for_key` and the pre-S2 algorithm give
  the same role for every rule of the nine built-in biomes. The roles table is authoritative at
  compile: a rule that omits `kind`, `size_class`, `align` or `habit` takes its role's.
- **Paths.** Compiled assets keep a library-relative `file` (the palette contract: relative, no
  `..`, no scheme). The absolute file of each asset is `compiled["paths"]`, joined from the
  folder; nothing `path_join`s an absolute second argument (it concatenates, S0 P5).
- **Merge.** Each compiled biome replaces the palette's biome of the same runtime id together
  with all its `<id>/` assets (the overlay's rule), so a core `savanna_summer_s1` replaces
  treecube's. A library's own surfaces are laid into the palette's `surfaces` table too
  (`PaletteOverlay.read_palette` merges the compiled table over the base's, which it holds
  unchanged), by name, so a core `ash` replaces treecube's.
- **Surfaces (S3).** `surfaces/<name>/{albedo,normal,orm,height}.png` plus `surface.json`
  (`label`, `kind`, `role` ground / cliff / built, `tile_m` 0.001 to 10000 required,
  `albedo_mean_linear` optional). The reader (`SurfaceReader`) checks the folder: names
  `[a-z][a-z0-9_]*` without `__` or a device name, at most 64 surfaces, albedo required (another
  missing map warns and is drawn as a flat stand-in), every PNG header read by the registry (first
  33 bytes: signature, IHDR, 4 to 2048 px a side, 8 or 16 bit, a normal map needs colour
  channels; a size other than 1024 warns, since the ground arrays hold one size per kind and draw a
  mismatched kind uncompressed), a stray file warns. A biome-def's `surfaces` is `legacy` (names
  are the installed palette's, the default) or `library` (a name that is one of the library's own
  surfaces, or a `lib://<library id>/<name>` reference, resolves to its runtime name; any other
  plain name is the palette's; a name in neither warns and the validator blanks it); any other
  value warns and reads as `legacy`. Runtime surface names are bare for core and
  `<lib>__<name>` otherwise (`LibraryIds.runtime_surface`); `lib://<library id>/<name>` is a
  STRING CONVENTION only (`LibraryIds.surface_ref` / `parse_surface_ref`, `SurfaceStore.runtime_name`
  / `ref_of`), not a registered scheme: the palette itself stores runtime names, and every
  `SurfaceStore` entry point and `GroundPalette` surface lookup takes either form.
- **SurfaceStore.** A legacy palette path (`surfaces/ash/ash_albedo.png` under the root) is
  ResourceLoader's editor-imported texture, unchanged. A library surface's palette entry holds
  `surfaces/<runtime name>/<map>.png` (unique per library, so two libraries' `crystal` never
  collide and the validator's relative-path rule holds); `LibraryRegistry.apply` registers them
  (`SurfaceStore.register_library`) and the store resolves the path to the library file: an
  editor import when the file is a `res://` file that has one (`ResourceLoader.exists(file,
  "Texture2D")`, the pack's `core`), else `Image.load_from_file`, a bake to the formats the import
  gives the installed surfaces, a memory cache and the raw disk cache. Formats (measured on 4.7.2
  against ash, cliff and grass_savanna, `test_surface_store.gd`): albedo BPTC (BC7, format 22,
  from sRGB), normal RGTC (BC5, 21, renormalised mips), ORM S3TC (BC1, 17, from RGB: the S0
  probe's GENERIC source picks RG for an ORM with no blue), height L8 (0); every map with the
  full mip chain. Normal, ORM and height are byte-identical to the import; albedo is the same
  format and size with a few block bytes different (148 of 1.4 million on ash) and decodes to the
  same 8-bit colours. Bake cost (1024 px, S0): about 0.21 s a surface, BC7 95 percent of it;
  nothing is baked when a library is served, only the maps a ground, a swatch or a thumbnail asks
  for, then about 18 ms a surface from the cache.
- **The raw cache.** `user://library_cache/<library id>/<hash>/<surface>_<map>.ttimg`: `TTIMG`,
  version, the engine version string and hash (a different engine ignores the file, bakes anew
  and replaces it), format, size, mips, data length, the data's SHA-256, then
  `Image.get_data()`. `<hash>` is a SHA-256 of the surface name and its map files' own hashes, so
  an edited PNG gets a new folder. Read with `FileAccess` and `Image.create_from_data` after the
  header, the size the format implies and the digest all check; never a `.res`, never loaded with
  `ResourceLoader` (a `.res` can carry a script). Old hash folders are not pruned yet.
- **Bindings (S3).** `library.json` `bindings` (and `default_biome`) replace the constants that
  named surfaces and biomes in code: `LibraryBindings.TABLE` lists each key with its legacy value
  (`fire.ash_surface` `ash`, `fire.ash_fallback` `dirt_peat`, `fire.burnt_biome` `burnt_forest`,
  `crossings.planks` / `moss` / `gravel` / `stone_default` / `paving`, `paint.default`
  `dirt_road_packed`, `water.bed` / `shore` `riverbed` / `mud`, `default_biome`
  `temperate_forest_summer_s1`). `LibraryRegistry.apply` flattens a library's bindings to runtime
  names (a surface it defines becomes its runtime name, a biome its palette `biome` field,
  `default_biome` a local or a runtime biome id the first season of) and `LibraryBindings.value`
  answers from the served libraries, else the default, so a game with no library, or a library
  that binds nothing, behaves as it did. Converted: `FireSweep.plan_for` and
  `FireEditor.forest_slots` (ash, fallback, burnt biome), `AuthoredCrossings` (planks, moss,
  gravel, stone default, paving default), `AuthoringPanel` (the Paint tool's first surface, labels:
  `SurfaceStore.label_of` reads surface.json `label` before the legacy `SURFACE_LABELS`),
  `EventsPane`, `GroundPalette.base_water_surfaces` and `NewMapDialog._initial_biome`. The legacy
  constants stay beside them as the documented defaults. NOT converted (other steps' files):
  `ScatterGround.SCORCHED_SURFACES` and `scatter_native.gd` (ash under a fire), and
  `PaletteLibrary.WATER_SURFACE_DEFAULTS` (the per-biome-key bed and shore the validator
  applies); the design lets a biome-def's `ground.water_bed` / `shore` supply them, which the
  installed data does not have.
- **Architecture rules** (pinned by `test_library_compile.gd` and `test_surface_store.gd`): the
  pure modules (contracts, ids, reader, compiler, `SurfaceBake`, `SurfaceReader`,
  `LibraryBindings`) use no `FileAccess`, `DirAccess`, `EventBus`, `ResourceLoader` or scene
  tree; only the registry lists folders (the cache writer creates and replaces its own files and
  lists nothing); `SurfaceStore` and `SurfaceCache` never call `load()` or `preload()` and use an
  import only for `res://` files.

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

- Unit tests: `test_library_ids.gd` (grammar, runtime ids, portable names),
  `test_library_contracts.gd` (S2: roles, habit flags, caps against the palette limits, the
  `export_json` round trip with `legacy_habit`), `test_legacy_habit.gd` (S2: identical plan roles
  by fallback and by habit for every built-in rule, the rule's habit beating the lists, the
  validator's `role`/`habit`/`weight` whitelist), `test_library_reader.gd` (the miniature library reads clean; malformed and hostile
  files: unknown keys, newer versions, reserved ids and names, case duplicates, missing and
  wrong-case files, bad roles and numbers, caps), `test_library_compile.gd` (the savanna golden
  with zero `validate_palette` warnings, the mini library under a prefix, role defaults and role
  relations, a missing catalog id, an over-length asset id, two seasons, the registry over a
  scratch palette root, GLB loading, a failing library changes nothing, the architecture
  rules), `test_library_row_parity.gd`, `test_surface_store.gd` (S3: the surface.json and PNG
  header checks and hostile files; the bake's formats against the editor import of the installed
  `ash` surface, byte for byte for normal, ORM and height and by decoded colour for albedo; the
  cache hit on a second load, a cache of another engine ignored and replaced, damaged caches
  refused; hostile reader and compiler inputs; the registry serving a fixture library's surfaces
  to `GroundPalette`, `GroundLayerArrays` and the label; the bindings' defaults against the
  legacy constants and a served library's overrides; the architecture rules). Fixture:
  `tests/fixtures/library_surfaces/` (JSON and 16 px PNGs). `test_ground_look`,
  `test_biome_thumbnail`, `test_swatch_textures` and `test_ground_layer_*` are unchanged.
- Surface parity (2026-10-24, `jobs/library_s3_parity.json`, windowed, full size): savanna and
  rocky badlands on the terraces landform, seed 1234, legacy surfaces through the resolver
  against the same job on main before the change. Mean absolute difference of the raw 3D
  captures: the two home views 0.000 of 255 (savanna 0.0002, badlands 0), the two size-14 views
  0.47 and 0.20 of 255; two runs of main against each other differ by 0.75 and 0.24 on those
  same close views (scatter and sway noise), so the change is inside the run-to-run noise. A
  library-supplied surface (`D:/dev/plantgen/out/lib_slice` with two installed PNG sets copied in
  as `crimson_dust` and `night_rock`, `surfaces: library`) draws: the basalt cliff and the new
  ground replace the sandstone and the savanna grass, 9.4 MB of raw cache written.
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

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work". The library steps (S4 onwards: the
multi-library registry and map `libraries` record, the manager, the designer) are in plantgen's
design doc section 6. Left over from S3: a library biome's thumbnail (`biomes/thumbs/*.jpg`) is
not served by `SurfaceStore` (a library biome still names a palette thumbnail); the cache is not
pruned and nothing prewarms it on a worker thread (the first ground draw of a new surface bakes
about 0.2 s on the main thread); `ScatterGround.SCORCHED_SURFACES` and
`PaletteLibrary.WATER_SURFACE_DEFAULTS` still hold their legacy values (their files belong to the
scatter and validator steps); `contract.json` does not yet publish the surface caps (2048 px, 64
surfaces) or `LibraryBindings.TABLE`.

## History

- 2026-10-24: step S3: `SurfaceStore` (+ `SurfaceBake`, `SurfaceReader`, `SurfaceCache`) loads a
  library's PNG surfaces without editor imports into the imported formats, with a raw
  engine-versioned cache; `GroundPalette`, `GroundLayerArrays`, `SwatchTextures` and
  `BiomeThumbnail` read every surface map through it (legacy paths keep the editor import);
  the reader validates `surfaces/`, the compiler resolves `surfaces: library` references by name
  and `lib://` convention; `LibraryBindings` replaces the fire, crossing, paint, water and
  default-biome constants with fallbacks equal to them. Findings: ORM must bake from sRGB or RGB
  channels (GENERIC picks RG for an ORM with no blue, format 21 instead of the import's 17);
  albedo differs from the import in a few block bytes but not in decoded colour.
- 2026-10-24: step S2: `palette_library.gd` (1000 lines, the lint cap) split into
  `PaletteFields`, `PaletteSurfaces`, `PaletteValidator`, `PaletteAssetFiles` (320 lines left,
  every public name kept); the rule whitelist keeps `role`, `habit`, `weight`;
  `ScatterGround.plan_role` reads the rule's habit with `LegacyHabit` as the fallback; the
  `contract.json` export gained `legacy_habit`. Checked on plantgen's `out/lib_core` (nine
  biomes, 121 rules, 288 assets): 0 `validate_palette` warnings, every rule equal to the package
  rule but for `assets`, `role`, `habit`, `weight`, `library`, and 0 plan-role mismatches.

- 2026-10-24: step S1, tt-sim half: `utils/library/`, the dev override, `compile_library_cli`,
  the tests and the `library_dev` render op.
