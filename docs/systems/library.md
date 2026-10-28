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
surfaces without editor imports (`SurfaceStore`) and the library bindings. Step S12a
(2026-10-24): terrain response on a rule (`slope_min_deg` and `response` curves), in GDScript.
Step S4 (2026-10-24): the multi-library registry (official and user libraries, dependencies,
enable and disable), `AssetStore`, the map's `libraries` record with its mismatch dialog, and
the New map dialog grouped by library. Step S5 (2026-10-24): `core` as the nine-biome library
with its surfaces, thumbnails and bindings, proven equal to the plantgen package route.
Step S6 (2026-10-24): the library manager, which the player knows as "Collections" (the word
"library" already means the list of maps on the title): list, card, import through a quarantine,
Verify and Remove. Step S8a (2026-10-25): the asset query (category, subtype, group, tags, size
class, seasons, count, pin, lock files) and the biome designer, [biome_designer.md](biome_designer.md). Step S10 (2026-10-25): `core` ships as the folder `res://libraries/core` and
treecube is gone ("The core library"). Step S9 (2026-10-25): per-season overrides in the compiler
("Seasons (S9)"), and the designer's A/B view, ground look editor and lock UI.

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
| `utils/library/library_query.gd` | `LibraryQuery` | (S8a, pure) The asset query of a rule: filter clauses, shared tag and size filters, the season mode, group order by FNV-1a hash, `count`, `pin`, lock files and the 64-asset cap; the compiler asks it for everything but explicit `ref`s ([biome_designer.md](biome_designer.md) "Model") |
| `utils/library/biome_seasons.gd` | `BiomeSeasons` | (S9, pure) A biome-def as one season sees it (`effective`, `rule_in`): the season's `overrides` and the rules' `seasons` laid over it, the density scale applied; `check` is the reader's words for them; `BiomeCompiler` calls it for every season |
| `utils/library/designer/` | `BiomeDesignerModel` and friends | (S8a) The biome designer's model, patches, curves, catalog and writer; `LibraryRegistry.designer_context`, `serve_draft` and `designer_writable` serve it ([biome_designer.md](biome_designer.md)) |
| `utils/library/library_registry.gd` | `LibraryRegistry` | The only module that lists or reads folders (S4: multi-library): `refresh` / `list` / `info` (what the manager shows), `apply` (compiles every servable library in load order and lays it over the palette), `served`, `record_of`, `assets_used_by(map)`, `resolve_asset_alias` / `resolve_biome_alias`, `is_enabled` / `set_enabled` / `disabled_ids`, `discoverable`, `read_sources`, `compile_folder`, the dev override (`set_dev_override`, settings `[library] dev_path`), `clear` |
| `utils/library/library_resolver.gd`, `library_versions.gd` | `LibraryResolver`, `LibraryVersions` | (S4, pure) Which libraries found on disk can be served and in what order (duplicate ids, disabled libraries, dependency ranges `^1.0` `~1.2` exact and comparators, cycles, depth 4, at most 16 active; `core` is an ordinary folder dependency (S10)); semver parse, compare and range check (prerelease tags ignored) |
| `utils/library/asset_store.gd`, `glb_guard.gd` | `AssetStore`, `GlbGuard` | (S4) The one place a library asset's mesh comes from, keyed by (library id, asset id): lazy GLTFDocument parse from a file path, cached, sha256 and byte count checked for a non-official library, `GlbGuard` (pure) reads the container and every embedded texture's size from its header before any decode; `instance()` dresses a copy with `WindFoliage.apply_material` |
| `utils/library/map_libraries.gd`, `utils/map_library_gate.gd` | `MapLibraries`, `MapLibraryGate` | (S4) What a map says about its libraries (the `libraries` record, the format number, `check` against the served libraries, `without_libraries`, `apply_aliases`) and the step between reading a document and building it (an aliases pass, the mismatch dialog, "Open without those plants") |
| `utils/library/library_groups.gd` | `LibraryGroups` | (S4, pure) The palette's biomes grouped by library for the New map dialog: core first, then by name, a library's default biome first |
| `utils/library/library_partial.gd` | `LibraryPartial` | (multiplayer, pure) The partial library and its wire bundle: `select` / `trim_biome` / `trim_library` / `trim_catalog` (what a map uses of a library), `encode` / `decode` (the `TTLP` bundle, capped before it allocates), `request_problem`, `inspect` (the client's checks of one received library), the error codes |
| `utils/library/library_transfer.gd`, `library_transfer_consent.gd` | `LibraryTransfer`, `LibraryTransferConsent` | (multiplayer) `plan` (what a client asks for), `authorize` / `quote` / `build_bundle` (the host), `verify_and_install` (the client); the consent model (phases, the question's words, the size-cap refusal, progress text) |
| `utils/library/library_from_host.gd` | `LibraryFromHost` | (multiplayer) The cache of collections downloaded from a host: the `.tt-from-host.json` record (`read_record`, `write_record`), `inventory`, `cap_bytes` / `set_cap_mb` (1 GB default), `evict_to_fit` (LRU, spares the open map's), `note_open_map` / `touch` (last used), `remove`, `clear_all`, `covers` (the consent rule), `decide` / `commit` (the all-or-nothing write), `startup` / `migrate_received`. With the registry and the surface cache the module that touches library folders (`test_only_the_registry_lists_folders` names it) |
| `utils/library/library_partial_merge.gd`, `library_transfer_install.gd` | `LibraryPartialMerge`, `LibraryTransferInstall` | (multiplayer, pure / client) The union of a delta partial into a kept one (`merge`, `merge_biome`), and the last step of `verify_and_install` (new, merge, replace, or the player's own copy left alone) |
| `scenes/ui/library_manager/library_cache_section.gd` | `LibraryCacheSection` | The manager's "downloaded from hosts" row: count and size, Clear with its confirmation, the size limit; attached by one line in `LibraryManager` |
| `autoloads/library_transfer_channel.gd`, `scenes/ui/library_transfer_ui.gd` | `LibraryTransferChannel`, `LibraryTransferUi` | (multiplayer) The messages and the client's flow (`AssetManager.library_transfer`), and the question and progress dialogs (the confirmation dialog) |
| `utils/library/library_layer.gd`, `utils/palette_library.gd` | `LibraryLayer.lay`, `PaletteLibrary.install_overlay` | (S10) The merge that lays a compiled library over the palette cache (a biome replaces the base's biome of the same runtime id with its assets; the library's surfaces are added); it reads no file and no GLB. It is what `PaletteOverlay.read_palette` became when treecube's overlay route was deleted. `PaletteLibrary.DEFAULT_ROOT` (`res://libraries`) is a VIRTUAL root: the first read of its palette serves the libraries into it (`get_palette`), `base_for_serving` is the empty base `LibraryRegistry.apply` lays onto |
| `utils/scatter_ground.gd` | `ScatterGround.habit_of` | (S2, S10) The rule's own `habit`, else NO habit (neutral `NO_HABIT`). The legacy key and kind lists (`LegacyHabit`, `EMERGENT_KEYS` ...) were deleted at S10: every shipped rule carries its habit through its role |
| `utils/palette_validator.gd` (+ `palette_surfaces.gd`, `palette_fields.gd`, `palette_asset_files.gd`) | `PaletteValidator` | (S2) `palette_library.gd` was at gdlint's 1000-line cap and is split; the rule whitelist in `PaletteValidator._validate_species` / `_library_fields` keeps `role`, `habit`, `weight` |
| `utils/foliage_library.gd` | `FoliageLibrary` | (S10: the treecube and plantgen-package switch, `[foliage]` settings and the F3 checkbox are gone) `apply(root)` clears the palette and wind caches and serves the libraries (`LibraryRegistry.apply`); `apply_saved()` does it at start-up; `refresh_libraries()` serves again and rebuilds the open map; `analyse` / `adapt_async` / `describe` regenerate a map's scatter from its biome painting when its rows name assets no library serves |
| `utils/library/library_names.gd` | `LibraryNames` | (S6) The ONE place the player-facing word for a library lives: `TITLE_SINGULAR` / `TITLE_PLURAL` (today "Collection" / "Collections"), the helpers every label is built from (`title`, `lower`, `counted`, `article`, the install card's promise line, the manager's caption). A rename is a one-line change; `test_library_manager.gd` fails when a string literal in the manager, importer, title or New map dialog holds the word |
| `utils/library/library_importer.gd` | `LibraryImporter` | (S6, no scene tree) `inspect(path)` judges a `.ttlib`/`.zip` or a folder BEFORE anything is written (the caps, extensions, portable names, links, encrypted entries, case twins, ratio), `stage(plan, progress)` extracts or copies into the quarantine `<libraries>/.incoming/<random>/` (a worker-thread-safe call with a `Progress` for the bar and Cancel), `is_candidate(path)` sniffs a drop, `sweep_incoming`, `discard`, `limits` (a test can lower them) |
| `utils/library/library_install.gd` | `LibraryInstall` | (S6) `examine(folder)` reads a staged folder with `LibraryReader` and compiles it in a dry run through the libraries installed, giving the install card (identity, size, counts, dependencies with their state, warnings, the relation to an installed copy, reserved ids); `install(card, replace)` moves it into `<libraries>/<id>/`; `remove(id)`; `levels_using(id, levels_dir)` (a lazy scan of the saved maps' manifests with `MapDocumentIO.peek_libraries`) |
| `utils/library/library_verify.gd` | `LibraryVerify` | (S6) Verify: `plan(id)`, `check(asset)` (`AssetStore.verify`), `summarize`, one asset at a time so the sheet keeps drawing. Since structures (S3) `plan` also lists `structure:<library>:<id>` and `check` builds that recipe at its default footprint ("Structures" below) |
| `utils/library/library_structures.gd` | `LibraryStructures` | (structures S3, pure) The `structures/` kind: `read` (the index and the recipe texts: caps, id grammar, size limits, `expose` against the recipe's interface, every problem a warning), `recipe_problem` (a recipe is checked before it is built), the paths (`recipe_path`, `thumb_path`, `ref_of`), `index_text`, `entries_of`, `merge_index`, `thumbnail_job` (the render job for the tiles) |
| `utils/library/library_structure_store.gd` | `LibraryStructureStore` | (structures S3) The structures the served libraries offer, by `<library>:<id>`: `structures(library)` (palette rows), `structure(ref)`, `has`, `recipe(ref)` (text and digest, what `StructureRecipes` reads), `used_by(doc)` (a map's references per library); `LibraryRegistry.apply` fills it (`begin`, `register`, `publish`) and it is swapped whole under a mutex, so a worker can read it while libraries are re-served |
| `utils/library/library_hash.gd` | `LibraryHash` | (pure) The short content hash a map records for a library (`of(sources, length)`); moved out of the registry at the structures card, same bytes for a library without structures |
| `scenes/ui/library_manager/` | `LibraryManager`, `LibraryDetail`, `LibraryInstallCard`, `LibraryImportFlow` | (S6) The sheet (list at the left, the selected library's card at the right, Import file... / Import folder... / Done), its card, the install sheet and the one flow behind the picker, the folder picker and a drop (inspect, stage on a worker thread, examine, ask, install, `refresh_all`). All built in code |
| `utils/zip_entry_sizes.gd` | `ZipEntrySizes` | (S6) Gained `read_directory` and `parse_central_records` (flags, method, attributes, sizes) beside the sizes the map reader uses |
| `tools/compile_library_cli.gd` | | Headless: prints or writes the compiled palette JSON of a library folder, or `--contract <file>` |
| `tools/render_jobs/driver.gd` | op `library_dev` | Sets the override for a run and rebuilds the open map |
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
  with a warning) and a `query`: `ref` clauses naming catalog ids or whole groups, and (S8a) filter
  clauses, tags, size classes, a season mode, `count`, `order`, `pin` and lock files, resolved by
  `LibraryQuery` over the library's and its dependencies' catalogs (semantics: [biome_designer.md](biome_designer.md)
  "Model"); a rule with only `ref` clauses compiles as it always did. `near` and `avoid` take a
  `rule` or a `role` (a role expands to every rule of that role), compiled to the palette's
  `species` key; a relation to a rule that was dropped is dropped with a warning.
- **Terrain response (S12a).** Two optional rule fields, additive to contract 1 (the version
  stays 1: an older reader only warns "unknown key" and ignores them, a legacy rule has neither,
  and a rule without them compiles and places byte for byte as before). `slope_min_deg` (0 to
  90, 0 = off) is a band edge: full density from the minimum up to `slope_max_deg`, fading to
  none over `ScatterGenerator.SLOPE_MIN_FADE_DEG` = 5 degrees BELOW the minimum (the +10 degree
  allowance belongs to the maximum only). `response` is an object of axis -> curve, a curve being
  2 to 8 `[x, y]` points, x strictly ascending inside the axis range, y 0 to 1, piecewise linear
  and flat beyond the ends. Axes (`LibraryContracts.RESPONSE_AXES`): `slope` degrees 0 to 90 (the
  angle of the ground normal at the candidate), `height` world metres -500 to 5000 (the ground's
  y, the same `height_at` the footing test reads: absolute height, not height above water),
  `wet` 0 to 1 (the stored wet-dressing shore weight, nonzero only within 2.4 m of water and 0 on
  a map with none), `water_dist` metres 0 to 64 (S12c: the distance from the candidate to the
  nearest water sample, 0 on the water, 64 at and beyond the cap and on a map with no water, from
  a derived grid, scatter.md "Terrain response"; was 0 to 200 and unevaluated before S12c, no
  library used it). The axes and
  `slope_min_deg` multiply and only ever lower the keep, so `density_per_m2` is the density at
  curve value 1 (the candidate supply is sized for it): "denser in the wetland" is a higher
  `density_per_m2` with the curve peaking at 1 there. The reader checks a curve strictly: a
  malformed one (a `water_dist` x past 64 included) is an ERROR (a library fails loudly), an
  unknown axis a warning;
  the lenient `PaletteValidator._library_fields` sorts points by x, clamps y with a warning and
  drops a bad axis with a warning. `LibraryContracts.export_json()` publishes the axes in
  `contract.json` (`response`: `axes`, `min_points`, `max_points`, `unsupported_axes`, empty
  since S12c), and
  `LibraryContracts.response_problem` is the one check both validators use. The compiler copies
  both fields into the compiled rule only when present. Scatter: [scatter.md](scatter.md)
  "Terrain response"; the native library evaluates it too since S12b (`version()` carries
  `curves`, and `water` since S12c; a stale library is refused to GDScript,
  `../PERFORMANCE.md` "Terrain response").
- **Runtime ids (S0 P4).** Core keeps today's ids (`savanna_summer_s1`, assets
  `savanna_summer_s1/Tree_Acacia_v0`); another library `<lib>__<biome>_<season>_s<seed>`, and
  its palette `biome` field is `<lib>__<biome>`. No `/` in a library id, biome name or local
  asset id; no `__` in a library id or biome name; the whole asset id under 160 characters
  (`PaletteLibrary.MAX_ID_LENGTH`; a longer one is skipped with a warning); every season and seed
  gets its own asset prefix (live edits accept an asset only when its prefix is the whole
  biome id).
- **Seasons (S9).** A season is one palette biome, and `BiomeSeasons.effective` (called by
  `BiomeCompiler._compile_biome`) is the biome-def as that season sees it: the season's `overrides`
  (`ground` field by field, `ground_look` deep-merged, `density_scale` per size class, `rules` by key)
  and each rule's own `seasons` (`only`, and a per-season override) laid over it, then the biome's
  `density_scale` applied (the compiler read it from no one before S9). A def without any of them is
  returned as it is, so every shipped library and the frozen goldens compile byte for byte as before.
  A rule override may set the fields of `LibraryContracts.SEASON_RULE_FIELDS` (`density_factor` is
  relative there, 0 removes the rule, `enabled` false too, `query` merges key by key); the reader
  checks the shapes (`BiomeSeasons.check`) and `contract.json` publishes them (`seasons`). There is no
  runtime season concept in the game: the New map dialog lists the season biomes as it lists any biome,
  and a map stores the runtime id (`<biome>_<season>_s<seed>`) of the one it was made on. The designer
  edits all of it ([biome_designer.md](biome_designer.md) "Seasons").
- **Sources and load order (S4).** `res://libraries/*/` (OFFICIAL, derived from the location,
  never read from a library file) then `user://libraries/*/` (the user's: `Paths.LIBRARIES_DIR`,
  a store under the data root, so a GUT run and a `--data-root` run see an empty one) then the developer
  override (`[library] dev_path`, laid over everything and replacing biomes of the same runtime
  id, as it always did). A folder of an official or user library must be named after its id; a
  folder starting with a dot (an import in progress) is not scanned. `core` is the folder
  `res://libraries/core` (S10; "The core library" below): there is no built-in core any more and
  `LibraryRegistry.BUILTIN_VERSION` is gone, so `core: ^1.0` is met by that folder and fails like
  any missing dependency without it. The listing skips `*.import` editor sidecars.
  `LibraryResolver` (pure) decides, and a library that cannot be served is an entry with status
  `error` and `reasons`, never a crash:
  - duplicate ids: an official library beats a user one, among user libraries the folder name
    sorted first wins, the rest are errors naming the winner;
  - `dependencies: [{"id": "core", "version": "^1.0"}]`: the library must be installed, enabled,
    itself available and at a version that satisfies the range (`^1.0`, `~1.2`, `1.2.3`, a
    partial `1.2`, `>=1.0 <2`, `*`; prerelease tags such as `1.0.0-dev` are ignored); chains at
    most 4 deep, no cycles, at most 16 libraries active;
  - load order: dependencies first, core first, then by id, the developer override last; each
    library is compiled with its dependencies' catalogs and surfaces, then laid over the palette
    (`LibraryLayer.lay`, which reads no GLB).
- **Cross-library refs (S4).** A query ref may be `<library id>:<local id>` naming an asset of a
  declared dependency (through that library's `aliases`; a `retired` id is skipped with a
  warning). The asset takes the local id `<library id>__<local id>` in the biome's asset ids
  (`<runtime biome>/core__Tree_Oak_v0`, still one slash) and its GLB stays in the dependency's
  folder (`AssetStore.library_of` says `core`). `lib://<library id>/<surface>` resolves the same
  way for a surface of a dependency. A ref or surface of a library that is not a declared
  dependency is skipped with a warning. A `core:` ref resolves through core's real catalog.
- **Enabling (S4).** `[library] disabled` in settings.cfg lists the ids the user turned off (all
  are on by default; `core` cannot be turned off). `LibraryRegistry.set_enabled(id, on)`
  persists it; a library that needs a disabled one is an error that says so. It takes effect at
  the next `apply()`: `FoliageLibrary.refresh_libraries()` applies and rebuilds the open map (the
  manager UI of step S6 calls it).
- **Bindings (S4).** Only `core` and the developer override may set `bindings` and
  `default_biome` (the names game code looks up: ash, planks, the New map default); another
  library's are ignored so an installed library cannot rebind the game.
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
  (a hand-built test palette) is unchanged byte for byte. `library` is still
  dropped silently: S4 reads the owning library from the id's prefix instead
  (`LibraryIds.library_of`), so the validator did not need to learn it.
- **Habit.** `ScatterGround.plan_role` reads `habit_of(rule)`: the rule's `habit`, else NO habit
  (neutral: not a bank or emergent plant, not arid, not charred). The legacy key and kind lists
  (`LegacyHabit`) were deleted at S10; `test_rule_habit.gd` pins that every rule of the nine
  shipped biomes carries an explicit habit that plans the role the lists gave (the lists live on
  there as reference data). The roles table is authoritative at compile: a rule that omits
  `kind`, `size_class`, `align` or `habit` takes its role's.
- **Paths.** Compiled assets keep a library-relative `file` (the palette contract: relative, no
  `..`, no scheme). The absolute file of each asset is `compiled["paths"]`, joined from the
  folder; nothing `path_join`s an absolute second argument (it concatenates, S0 P5).
- **Merge.** Each compiled biome replaces the palette's biome of the same runtime id together
  with all its `<id>/` assets (`LibraryLayer.lay`), so a developer override of core's
  `savanna_summer_s1` replaces core's. A library's own surfaces are laid into the palette's
  `surfaces` table too (the compiled table is merged over the base's), by name.
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
  ResourceLoader's editor-imported texture, unchanged (only a test fixture has one since S10).
  A library surface's palette entry holds
  `surfaces/<runtime name>/<map>.png` (unique per library, so two libraries' `crystal` never
  collide and the validator's relative-path rule holds); `LibraryRegistry.apply` registers them
  (`SurfaceStore.register_library`) and the store resolves the path to the library file with
  `Image.load_png_from_buffer` over the file's bytes (core's PNGs are raw `importer="keep"` files in the pack; a library file
  is never loaded as a resource), a bake to the formats the import gave the retired installed
  surfaces, a memory cache and the raw disk cache (`user://library_cache`, about 170 MB once all
  36 core surfaces have been baked: the maps are BC7, BC5, BC1 and L8 at 1024 px). Formats (measured on 4.7.2
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
  `SurfaceStore.label_of` reads surface.json `label`, else the id spelled out; the legacy
  `SURFACE_LABELS` table was deleted at S10 and is frozen in `test_library_core_surfaces.gd`),
  `EventsPane`, `GroundPalette.base_water_surfaces` and `NewMapDialog._initial_biome`. The legacy
  constants stay beside them as the documented defaults. NOT converted (other steps' files):
  `ScatterGround.SCORCHED_SURFACES` and `scatter_native.gd` (ash under a fire), and
  `PaletteLibrary.WATER_SURFACE_DEFAULTS` (the per-biome-key bed and shore the validator
  applies); the design lets a biome-def's `ground.water_bed` / `shore` supply them, which the
  installed data does not have.
- **AssetStore (S4).** A served library's assets are registered (`register_library`: the
  absolute GLB, the node, the catalog's `sha256` and `bytes`, whether the library is official)
  and nothing is read. `PaletteLibrary._source_mesh` asks `AssetStore.mesh_for` for an id the
  store serves and loads a plain palette's GLB as before for any other (test palettes);
  `resolve()` still hands
  out a duplicate, and the scatter build still applies `WindFoliage.apply_material` to it, so a
  library material only ever draws with the game's own shaders (glTF cannot carry one;
  `AssetStore.sanitize` makes sure and `instance()` does the dressing for a direct caller). On
  the first ask the file's bytes are read once (64 MiB cap), `GlbGuard.inspect` checks the
  container, refuses any `uri` and reads every embedded PNG or JPEG's size from its header (at
  most 64 images, 4096 px a side, 32M pixels in all) BEFORE GLTFDocument decodes anything, then
  the mesh is parsed with compression off (`AssetStore.FORCE_DISABLE_COMPRESSION`, from a
  buffer, never `ResourceLoader`). A library that is not official must also match the catalog's
  `sha256` and `bytes`, else the asset is refused with a warning once and the refusal is
  cached; the others of that library still load. Official libraries are not hashed on load
  (they ship in the game): `AssetStore.verify` does it for a test or a CLI. A Mutex guards the
  tables because scatter preparation resolves assets on worker threads. `PaletteLibrary.clear_cache`
  clears the store (the registry registers again on its next `apply`).
- **Maps (S4).** `manifest.json` carries `libraries: [{id, version, hash}]` for every library
  whose biome, asset, prop or painted surface the map holds (the prefix of the id names it:
  `LibraryIds.library_of`, `MapLibraries.surface_library`); the writer recomputes it from the
  document at every save with the versions the registry serves, falling back to what the file
  claimed for a library that is not served. The format number is 2 while only `core` is named
  (an older build still opens it) and 3 (`MapDocument.FORMAT_LIBRARIES`) as soon as another
  library is, so a build that does not know libraries refuses the document instead of dropping
  the prefixed plants on its next save. Opening: `MapSourceLoader.load_async` runs
  `MapLibraryGate.run` after the document is read (authoring and play both set
  `MapLibraryGate.ask_dialog`): first `MapLibraries.apply_aliases` renames ids a served library
  renamed (`aliases` in library.json, used only for ids the palette lacks), then
  `MapLibraries.check` compares the record with what is served: a library that is not served
  (not installed, turned off, or failed, with the reason) is MISSING; one served at another
  major version is INCOMPATIBLE; a newer minor or patch opens as it is; a different hash at the
  same version only logs. A mismatch shows a dialog naming each library, the version the map
  was saved with, why it is missing and its author, with "Open without those plants" and
  "Cancel". The first drops those libraries' scatter and prop rows, points their biomes at the
  default biome (`LibraryBindings.default_biome`, else the first core biome), shows a toast and
  leaves the authoring session unsaved so leaving asks; Cancel returns to the title with nothing
  changed (`MapSourceLoader.library_cancelled`). A loader with no `library_choice` (a test, a
  tool) takes "open without" and still shows the toast: never a silent substitution.
  `LibraryRegistry.assets_used_by(map)` answers {library id: sorted asset ids} for the multiplayer
  step that will send only those; `record_of(id)` is the {id, version, hash} a map stores.
- **New map dialog (S4).** `LibraryGroups.group` splits the palette's biomes by owning library:
  core's keep the existing `biome_field` (Bare ground included), every other library that
  supplies a biome gets a `library_fields` field headed by its name with its version and author
  at the end of the line, its default biome first, the season in the label when two share a
  name. One pick spans all the fields. A library's own picture
  (`biomes/thumbs/<biome>.jpg` named by the biome-def's `thumbnail`, listed in the folder) is
  compiled to the palette thumbnail path `thumbnails/<runtime id>.jpg`, which
  `SurfaceStore.register_thumbnails` serves (JPG or PNG decoded as an image, 4 MiB and 4096 px
  at most); without one the strip is painted from the biome's ground alone.
- **Architecture rules** (pinned by `test_library_compile.gd`, `test_surface_store.gd` and
  `test_library_assetstore.gd`): the pure modules (contracts, ids, reader, compiler,
  `SurfaceBake`, `SurfaceReader`, `LibraryBindings`, `LibraryVersions`, `LibraryResolver`,
  `GlbGuard`, `MapLibraries`) use no `FileAccess`, `DirAccess`, `EventBus`, `ResourceLoader` or
  scene tree; only the registry lists folders (the cache writer creates and replaces its own
  files and lists nothing); `SurfaceStore`, `SurfaceCache` and `AssetStore` never call `load()`
  or `preload()`, and `AssetStore` never uses `ResourceLoader` (a library file is bytes, never a
  resource or a script).

## The core library (S5, shipped at S10)

Step S5 (2026-10-24) made `core` the nine-biome library plantgen builds from the sources repo
`D:/dev/tabletop/core-library` (local git, no remote; its README and AGENTS say what it holds).
Step S10 (2026-10-25) ships it with the game and removes treecube: core is the folder
`res://libraries/core` (library.json, assets/ with 268 GLBs and catalog.json, biomes/ with the nine
biome-defs, surfaces/ with 36 sets, thumbnails/ with nine JPGs; 468 files, 175 MB: 34 MB of GLBs,
136 MB of surface PNGs). It is built by plantgen (`out/lib_core_s10`, `--no-treecube`, its
`--check-built` clean) and copied in whole; to ship a rebuild replace the folder and re-run the
import so the sidecars stay constant (see below). Nothing in the scatter, ground, water or fire
code changed for S5: the proof is that the library route reads and places exactly like the package
route (Verification, "Step S5 proof"), now frozen as `tests/fixtures/library_core_golden.json`.

- **Route K (how the files ship).** Every PNG, GLB and JPG under `libraries/core/` has a constant
  sidecar `<file>.import` holding exactly `[remap]`, a blank line and `importer="keep"`: the
  editor does not import the file, an export stores the RAW file in the pack and stores no
  sidecar. One loader path then serves core, user libraries and the developer override
  (`FileAccess`, `Image.load_png_from_buffer`, `GLTFDocument.append_from_buffer`; never `ResourceLoader` and not `Image.load_from_file`, which warns once for a keep file in the editor,
  which answers false for a keep file in a pack and errors in the editor). Verified 2026-10-25 with
  a real `godot --headless --export-pack "Windows Desktop"` (no templates; the presets exclude
  only tests, tools, docs and addons, so `libraries/` ships): a 254 MB pack that holds
  `libraries/core/library.json`, all GLBs, PNGs and JPGs raw and no `.import` entry, no
  `assets/palette`; run with `--main-pack` plus the engine's own extension DLLs beside it, a probe
  scene saw `FoliageLibrary.apply()` serve 9 biomes, 288 palette assets (268 library assets; the
  shared stems repeat per biome) and 36 surfaces with no warning in 109 ms, resolve every one of
  the 288 assets to a mesh in 634 ms, `AssetStore.verify` every GLB's sha256 against the catalog
  with 0 failures, bake a surface and read a thumbnail, and `compile_folder` the folder clean.
  `LibraryRegistry` skips `*.import` when it lists a folder (the editor run shows them, the pack
  does not). `.gitattributes` keeps `libraries/core/**/*.glb`, `*.png` and `*.jpg` in LFS; the
  JSON files and the sidecars are plain git. The surfaces are the SAME bytes as the retired
  `assets/palette` ones, so they dedupe in LFS.
- **Official by location, no built-in core.** `LibraryRegistry` scans `res://libraries` first: a
  folder there is OFFICIAL (never read from the file), listed in the manager as "Built in", with
  no Remove and a switch that cannot turn it off; `core` is the first in load order and what
  `core: ^1.0` dependencies resolve against. `LibraryRegistry.BUILTIN_VERSION`, the built-in info
  entry and the resolver's `builtin` parameter are gone: a game without `libraries/core` serves
  nothing, and a library that needs `core` is an error like any missing dependency. A `core:` ref
  resolves through the real catalog. The New map default biome, the Paint default, the fire's ash
  and the crossings' surfaces read `library.json` (`default_biome` and `bindings`) through
  `LibraryBindings`; the legacy values stay as its defaults for a game with no library.
- **Maps saved under treecube asset ids (documented behaviour).** There are no users and no
  compatibility work. A saved map keeps the biome painting and the seed its scatter came from;
  core keeps the runtime biome ids the treecube palette had (`savanna_summer_s1`), so on load
  `FoliageLibrary.adapt_async` finds scatter rows naming assets no library serves, regenerates the
  rows from the painting under core and says so once ("scatter rebuilt from the biome painting").
  Hand-placed props whose assets are gone are counted and skipped by the build, as for any asset
  a build lacks; a painting that names a biome no library serves regenerates nothing and the map
  draws no plants there. Nothing crashes: the missing ids take the existing skip paths
  (`PaletteLibrary.resolve` warns once per id). `test_foliage_library.gd` pins all three cases.
  The `[foliage]` keys of `settings.cfg` (`library`, `package_path`) are dead: nothing reads
  them and the file is left alone.

Facts of the S5 build (still true of the shipped folder):

- **Asset ids.** The game profile tones one stem differently per biome, so a library asset id
  must be unique and its bytes fixed. A package stem whose GLB bytes are identical in every biome
  that uses it keeps its name (`Bush_BarrelCactus_v0`, 60 ids); every other stem becomes
  `<stem>_<local biome id>` (`Tree_Oak_v0_savanna`, 208 ids, 268 in all). The catalog entry
  carries `package_stem`, the package's own stem; the compiled palette asset id is
  `<runtime biome id>/<library id>` (`savanna_summer_s1/Tree_Oak_v0_savanna`), the package's is
  `<runtime biome id>/<package stem>`. To compare the two routes map a compiled id back with
  `tests/unit/library_route_compare.gd` `package_id` (the catalog's `package_stem`, or the id
  itself when it has none); plantgen's `library_diff_cli --all` does the same through
  `plan.json` `origins`. Nothing in the scatter code reads an id's text, so the renaming moves
  no row (checked byte for byte).
- **Surfaces.** The 36 installed surfaces are `surfaces/<name>/{albedo,normal,orm,height}.png`
  (byte-identical copies of the installed files) plus `surface.json` (`label` as the game shows
  it today, `kind`, `role`, `tile_m`, `albedo_mean_linear` as the palette lists it, so the ground
  look reads the same mean). All nine biome-defs are `surfaces: library`: `ground.surface`,
  `cliff`, `scree`, `water_bed`, `shore`, accents and paths are bare names that resolve to the
  library's own surface (a core surface keeps its bare runtime name, so the compiled palette
  table is the installed one with the library's maps behind each entry). The installed biomes
  name no water surfaces; `water_bed` and `shore` are written from the game's
  `PaletteFields.WATER_SURFACE_DEFAULTS` for the biome, which is what the validator resolved
  anyway. `ground_look` blocks are verbatim.
- **Bindings.** `library.json` `bindings` carries every `LibraryBindings.TABLE` key at its
  legacy value (`fire.ash_surface` ash, `fire.ash_fallback` dirt_peat, `fire.burnt_biome`
  burnt_forest, `crossings.planks/moss/gravel/stone_default/paving` planks, moss, gravel, cliff,
  flagstone, `paint.default` dirt_road_packed, `water.bed` riverbed, `water.shore` mud) and
  `default_biome` `temperate_forest_summer_s1`. A game served by `core` therefore behaves as the
  constants did; `SCORCHED_SURFACES` and `WATER_SURFACE_DEFAULTS` stay code.
- **Thumbnails.** `thumbnails/<local biome id>.jpg` (512 px) named by the biome-def's `thumbnail`;
  the compiler serves each as `thumbnails/<runtime id>.jpg`, the path the palette already used,
  through `SurfaceStore` (`is_library_thumbnail`). Since 2026-10-25 the shipped nine are renders of
  core's own plants (see "Biome thumbnails" below), no longer the treecube Blender renders.
- **Biome thumbnails (2026-10-25).** Two kinds of picture: an ASSET's (`assets/thumbs/<id>.png`, 256 px
  PNG, plantgen's `build_library_cli --thumbs 1` renders each GLB alone) and a BIOME's
  (`thumbnails/<biome>.jpg`, 512 px JPG, shown by the manager, the New map dialog and the designer
  picker). Only the game can draw a biome (real scatter, ground look, light), so the biome pictures
  are rendered by tt-sim: `LibraryThumbnailer` (pure: the plan, the file name, the standard scene,
  the JPG caps, the hash record), `ThumbnailShot` (freezes the wind and the canopy fades, frames the
  camera, grabs the world view) and `tools/render_library_thumbnails.gd` (a render job built in code
  over `tools/render_jobs/run.gd`). The standard scene is a new 100 ft map painted with the biome
  (`NewMap`, map seed and placement seed 1234, the biome's first season), the game camera (fixed
  orthographic, 21.6 degrees) at zoom 20 on the map's centre, wind and fades off, then the centred
  square scaled to 512 px, JPEG quality 0.8 (30 to 55 KB, cap 128 KB; the treecube ones were 10 to
  15 KB). `LibraryWriter.write_thumbnail` writes the file, gives the biome-def its `thumbnail`
  field when it lacks one and moves `stats.file_sha256` and `stats.surface_bytes` of a built
  library. Two runs, and runs from two folders, give identical bytes on this machine (the
  RTX 3080); one savanna render of a cold first run once differed, so judge a build by the second.
  ```
  # A built library folder (plantgen's output), windowed, one window, about 25 s plus 1 s a biome
  godot --path <tt-sim> --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_library_thumbnails.gd -- --library <built folder> [--out <folder>] [--biome a,b] [--season summer] [--list 1]
  # Part of the collection build (plantgen), after the assets, before the zip
  godot --path <plantgen> --resolution 320x200 --script res://tools/build_library_cli.gd -- --library <core-library>/library.json --out <dir> --thumbs 1 --biome-thumbs <tt-sim project>
  ```
  Without `--biome-thumbs` the build copies the library's authored `thumbnails/` (core:
  core-library's), so a build stays reproducible; to refresh core's pictures build once with the
  option, copy `<dir>/thumbnails/*.jpg` into core-library, commit, and ship the folder and
  library.json into `libraries/core`. In the biome designer the header's **Thumbnail** button takes
  the draft's picture on the same standard map (`BiomeDesignerSession.capture_thumbnail`, about
  20 s, the proving ground returns) and saves it through the writer; it is enabled for a user
  library and the developer-override folder (`LibraryThumbnailer.designer_writable`), never for a
  shipped one. `test_library_thumbnailer.gd` pins the pure parts, the writer and the shipped core
  pictures against the caps and the recorded hashes.
- **Asset thumbnails (library update, 2026-10-25).** The shipped core carries one 256 px PNG per
  catalog asset, `assets/thumbs/<asset id>.png` (268 files, 3.2 MB, Git LFS, constant
  `importer="keep"` sidecars), named by the catalog entry's `thumb`, with `stats.thumbs`,
  `stats.thumb_bytes` and every file's sha256 in `stats.file_sha256`. The designer's picker
  (`DesignerCatalog` hands the tile the absolute file, `DesignerAssetTile` draws it) reads them
  through `AssetThumbnails.texture(file)`: decoded from the bytes by `SurfaceStore.thumbnail_image`
  (4 MiB and header-size caps, shrunk to 256 px), trimmed of the render's transparent border,
  cached with a 512-texture LRU, null on any failure so the tile keeps its category icon.
  `test_library_asset_thumbnails.gd` pins files, sizes and hashes.
- **Catalog `roles`.** plantgen's catalog entries carry `roles` (the contract roles of the
  rules that use the asset); `LibraryContracts.CATALOG_ENTRY_KEYS` knows the key, so the nine
  biomes read with no warnings.

## Structures

Card S3 of the structures topic ([structures.md](structures.md); the contract is
`ASSET_PIPELINE.md` section 12). A library may hold buildings as recipes, a kind beside assets,
biomes and surfaces. A library without the folder reads exactly as before and hashes as it did.

Files (all `.json`, `.jpg` and `.txt`, so the extension whitelist is unchanged):

```
structures/index.json              {"format": "ttsim-structures", "format_version": 1, "structures": [entry, ...]}
structures/<id>.structure.json     the recipe: a procgen graph document (plantgen-graph), unmodified
thumbnails/structures/<id>.jpg     the palette tile (512 px, rendered by tt-sim)
structures/pins.txt                core only: "<id> <pipeline md5> <triangles> <procgen md5>"
```

An index entry: `id` (`[a-z][a-z0-9_]*`, at most 48, no `__`; also the file stem), `name`, `family` and
`variant` (a picker groups a family's variants), `tags`, `file` (must be the id's own path),
`default_size_m` `[w, d]`, `min_side_m`, `max_side_m`, `max_area_m2` (the default footprint must fit
them), `plans` (`rect` `l` `t` `u`, the footprint kinds a tool offers), `expose` (interface names the
UI may show; a name the recipe's interface lacks is dropped), `textured` (the recipe declares the
`textured` switch), `thumb`. Missing fields take the defaults (6 x 4 m, 2.5 to 14 m a side, 120 m2).
A reference is `<library id>:<structure id>`, the cross-library grammar; a map stores it in
`Structure.recipe`.

Reading (`LibraryStructures.read`, called by `LibraryReader.read` with the `structures` part of its
sources). Everything is untrusted input and **every problem is a warning**: the structure is left
out, the library still reads and serves. Caps (`LibraryContracts.STRUCTURE_CAPS`, apart from `CAPS`
so the vendored `contract.json` does not change): 128 structures, 256 KB for the index and for a
recipe, 128 nodes and 512 connections in a recipe, 16 `expose` names. A recipe is checked BEFORE
`PlantGraphDocument.from_json` sees it (`recipe_problem`: bytes, JSON, the `plantgen-graph` format,
every node an object with a text id, a type the `ProcgenStructureRegistry` knows and no nested table
in its parameters, connections between known nodes, a well formed interface), because `from_dict`
indexes keys directly. A recipe is data run by a fixed set of node types: a hostile library can be
expensive, not harmful, and GDScript cannot interrupt an evaluation, so the cost is bounded by these
input caps and by the footprint caps of `MapStructureIO`. `StructureRecipes.document` runs the same
check on whatever text it is given.

Serving. `LibraryRegistry.read_sources` reads the files (line ends made LF, so a CRLF checkout digests
like a pack), `_entry_of` keeps the accepted recipes' texts, `_serve` hands them to
`LibraryStructureStore.register`, and `apply` publishes the whole table at the end. A library with
structures and no biome-def (a collection of buildings) is a pool: it lays nothing on the palette and
serves its structures (as an `assets_only` partial does). The index and the recipes are part of the
library hash (`LibraryHash`), so a map records a changed recipe like any other change. The registry's
`info` has `structure_count`; the install card has it, and its change line says "N more buildings".

Maps. `MapLibraries.used_ids` counts the library of every structure's reference, so `record_for`
lists it (format 3 for a library other than core) and the open-time check reports it missing or
incompatible like any other. `LibraryStructureStore.used_by(doc)` is the per-library list of
references; `assets_used_by` stays about palette assets (a structure is none, and a transfer asks for
structures in their own list). "Open without those plants" leaves the structure records in place: they
build a placeholder.

Builder seam. `StructureRecipes` looks a reference up in this order: the test `resolver`, the store,
and only with `procgen_fallback` on (off in the game) procgen's committed recipes.
`StructureRecipes.ensure_served()` makes sure the libraries are served before a worker asks (the first
read of the default palette serves them; `AuthoredLoadPrep` and `AuthoredStructures` call it). A
reference nobody serves, or a recipe that fails to build, builds a **placeholder plot**
(`StructureGeometry`): a pale low slab on the footprint that follows the ground, no collision, no
top, `placeholder` true in the parts and the reason in `problem`. A peer whose transfer is still
running, a removed library and a recipe that fails all show a plot where the building goes, never a
hole; the build key holds the recipe digest, so the plot becomes the building when the library
arrives. (A structure over the 25k hard budget is still refused with nothing built.)

Transfer. A request carries `structures` (the references of the requested library the map uses; at
most 128, checked by `request_problem`). `plan` counts a structure the install lacks like a missing
asset (a copy the player installed is never replaced: the player is told what it lacks), `authorize`
allows only references a served map uses (`usage_of`), and the host's partial (`LibraryPartial.select`,
`LibraryTransfer._files_of`) holds the index cut to the requested structures, their recipes and
tiles, and `partial.structures` in library.json. A partial with structures and no biome is valid
(`LibraryStructureStore.buildings_only`). The client's `inspect` allows exactly those files and reads
every recipe through `LibraryStructures.read` (a recipe that does not pass is an unexpected file), and
`LibraryPartialMerge` unites a delta's index with the kept copy's by id (a clash is refused).

Verify. `LibraryVerify.plan` lists `structure:<ref>` after the assets; `check` builds the recipe at the
entry's default footprint on flat ground and fails it when it does not build (placeholder or
`problem`), builds over 60000 triangles, or takes over 400 ms (`STRUCTURE_MAX_TRIANGLES`,
`STRUCTURE_MAX_MSEC`). Tests: `test_library_structures.gd` (pure), `test_library_structure_store.gd`
(registry, maps, the seam, the placeholder, Verify, core's pins), `test_library_structure_transfer.gd`.

Tiles. tt-sim renders them, because only the game has the real materials:
`tools/render_structure_thumbnails.gd` (the twin of `render_library_thumbnails.gd`) builds the job
`LibraryStructures.thumbnail_job` makes: a new 100 ft meadow, one building at a time at its default
footprint through the editor API (`probes/structures.gd` action `tile`), the camera framed from its
size and wall height, the driver's `thumbnail` op with `structure: true`
(`LibraryWriter.write_structure_thumbnail`); each tile is also a capture in the job's folder. Run it
windowed and short (about 40 s, GPU shared): `godot --path <tt-sim> --windowed --resolution 1920x1080
--position 320,120 --script res://tools/render_structure_thumbnails.gd -- --library <folder with
structures/index.json> [--out <folder to write into>] [--serve 1] [--only a,b] [--list 1]`. For core:
`--library <tt-sim>/libraries/core --out <core-library>`, then copy the tiles to
`libraries/core/thumbnails/structures/`. `--serve 1` lays a not yet installed library over the game first.

Core's starter set is data in the `core-library` repo (`structures/`: thirteen recipes (five at S3, eight added
2026-10-28: timber, chimneyed, terrace-end, hip and flat variants), the index and
`pins.txt`; the tiles in `thumbnails/structures/`), made by `tools/export_core_structures.gd` from
procgen's `ProcgenRecipes` (its `STARTERS` table says per structure how `ProcgenRecipes.building` is
called, every recipe glazed with the `ridge` choice; `--check 1` shows a drift without writing; without it, it re-pins on
purpose). The copy in `libraries/core/structures/` and `libraries/core/thumbnails/structures/` ships
with the game like the rest of core. Updating core's structures: change the recipe in procgen, run the
export tool into `core-library`, re-render the tiles (above), copy both folders over `libraries/core/`,
run `--import` for the `.jpg.import` sidecars and the gate (`test_library_structure_store.gd` compares
the pins).

## Runtime

Nothing is served unless something is installed: with no `res://libraries/*`, no
`user://libraries/*` and no dev override the registry serves nothing and the palette is empty
(no warning storm: the shipped game always has `libraries/core`). The palette at
`PaletteLibrary.DEFAULT_ROOT` (`res://libraries`, a virtual root: no folder of that name holds a
palette.json) is filled by the first read of it (`PaletteLibrary.get_palette` calls
`LibraryRegistry.apply`) or by `FoliageLibrary.apply()` / `apply_saved()` at start-up. `apply(root)`
scans the roots, reads every folder (`LibraryReader`), resolves (`LibraryResolver`), and for each
servable library in load order compiles it through its dependencies, lays it with
`LibraryLayer.lay` and `PaletteLibrary.install_overlay` (no GLB is parsed now, `AssetStore` parses
on first use), then registers its assets, surfaces, thumbnails and (core and the developer
override only) bindings. It clears only the registrations of the root it serves
(`AssetStore.clear_root`, `SurfaceStore.clear_libraries_of`), so the first read of the default
palette by incidental code does not wipe what a scratch root (a test, a tool) has laid. A library
that does not read, resolve or compile changes no cache and is an entry in
`LibraryRegistry.list()` with status `error` and its reasons (`result["errors"]`, a
`push_warning` per line); only a developer override that cannot be served makes `result["ok"]`
false. The map rebuilds on `EventBus.foliage_library_changed` (`FoliageLibrary.refresh_libraries()`
emits it). A refresh keeps an open map's BAKED rows: a rule that changed (S12a found this) only
shows in a map built, or a cell regenerated, after it, so a job that compares two libraries on
one terrain builds the map again under each (`landform.gd new` with the same seed), as
`library_s12a_terrain.json` does. Settings: `[library] dev_path` (the override), `[library]
disabled` (a list of ids). The `compile_library_cli` and `LibraryRegistry.compile_folder` compile
one folder alone, without dependencies.

## Multiplayer

User decision (2026-10-24): non-core libraries transfer automatically in multiplayer, ideally
only the assets a given map uses. The messages and the network rules are in
[../NETWORKING.md](../NETWORKING.md) "Library Transfer"; this is the library side.

- **The flow.** A client loads a map (first load, a map set out from the shelf, a late join) and
  `MapLibraryGate.run` first calls `fetch` (`LibraryTransferChannel.fetch_for_document`). `plan`
  compares the document with what is served and returns requests and blocked libraries; for each
  request the client sends a quote request, the host answers with what it would send, the player
  answers "The host uses the collection X v1.2 by Y (N items, M MB). Download M MB? It stays on
  this computer until you remove it in Collections." (Download or Skip; the question is asked
  ONCE per collection and source hash, see "The cache of downloaded collections"), the bytes
  stream with a progress sheet and Cancel, and `verify_and_install` keeps the collection and
  serves it; a toast says what arrived and that it can be removed any time. The gate then checks
  the map against it. A Skip, a refusal, a cancel or any failure leaves the existing mismatch
  dialog ("Open without those collections" or Cancel).
- **What is asked for (`plan`).** A library the map uses and the client does not have is requested
  (`missing`). A library installed at the same major version but lacking used assets is requested
  only when the installed copy is a from-host one (a copy a host sent, the cache below): then
  `more` (same version; only the MISSING items are asked for, a delta) or `newer` (the map was
  saved with a higher version; the whole request replaces the kept copy). The player's OWN copy is
  never replaced by a host's: at the same version it is blocked (`lacks`), at a lower one blocked
  as `older` (the dialog names what it lacks), and nothing is requested. Never requested, and
  reported with a reason: `core` and official libraries (they ship with the game, every peer runs
  the same version), a disabled or broken library, another major version, a reserved id. The
  request carries the used (or, for a delta, the missing) asset, biome and surface ids, the
  version and hash the map names, the libraries the client has, and for a delta the surfaces it
  already holds (`held_surfaces`, so the host does not send them again).
- **The partial library (`LibraryPartial`).** An ordinary library folder with the SAME id and
  version as the host's, marked by a `partial` block in `library.json` (`format`,
  `source_version`, `source_hash`, `assets`, `biomes`, `surfaces`, `assets_only`, `bytes`). It
  holds: `library.json` (stats, cover, bindings and default biome dropped); `assets/catalog.json`
  with only the used assets, every entry carrying `sha256` and `bytes` recomputed by the host;
  the GLBs of those assets; `biomes/<id>.json` for the biomes the map paints or places plants
  from, each cut to the rules with a used asset (a biome left with none keeps its first rule and
  that rule's first asset so its ground works), with near and avoid relations to cut rules
  removed and the thumbnail dropped; and `surfaces/<name>/` for the library surfaces those
  biomes' `ground` or the map's painting names. A dependency's assets that the map uses
  (`<dep>__<id>`) travel as an `assets_only` partial of that dependency (no biome, served as a
  pool that feeds the dependent's refs) unless the client's `have` satisfies the declared range;
  `core` and official dependencies are never sent; a dependency of a dependency is refused
  ("too deep to send"). The registry reports `partial`, `from_host` (the record) and `received`
  (= has a record) in `list()` / `info()`, so the manager can badge it "From host" and "Partial
  copy"; a map saved while it is served records the host's FULL library hash
  (`partial.source_hash`).
- **Where it lives.** `user://libraries/<id>/`, an ordinary user library, since 2026-10-25 (the
  decision that a collection a host sent is treated like any other: it is served, switched,
  removed, persists across sessions, and is only MARKED from host). The marker is the record file
  `.tt-from-host.json`; see "The cache of downloaded collections". There is no session-only copy,
  no `.received` source in the registry, no Keep step and no precedence rule for a received
  library: the id is a folder, so a host's library can never replace the player's own copy. The
  earlier `user://libraries/.received/` folder is adopted once at start-up
  (`LibraryFromHost.migrate_received`).
- **Safety (`LibraryPartial.inspect`, run on every library of a bundle before anything is
  written, all or nothing).** Caps: at most 4096 files, 8 libraries and 256 MiB in a bundle,
  per-file by extension (json 4 MiB, glb 64 MiB, png 16 MiB, jpg 4 MiB, txt and md 64 KiB), the
  stream header's chunk count and size (`header_ok`), a chunk over `CHUNK_SIZE`; the extension
  whitelist (`LibraryContracts.EXTENSIONS`: no code); portable relative names (no `..`, drive,
  scheme, backslash, device name, case duplicates; reported as `traversal` or `invalid_library`);
  no file the library does not name (`extra_file`); the library id is not `core`, not reserved
  (`legacy`, `draft`, `dev`) and not an official library (`reserved_id`); the folder, `library.json`
  and the request agree (`id_mismatch`); the version has the major the map was saved with
  (`version_mismatch`); a `partial` block is present (`not_partial`); every GLB's size and
  sha256 match the catalog, which must carry both (`bad_hash`), and `GlbGuard` passes it; the
  reader accepts the library; a compile dry-run gives at least one biome (an `assets_only` part
  is exempt). Nothing is loaded as a resource: the files are data, GLBs parse through
  `AssetStore` on first use with the catalog's sha256 checked again.
- **Host side.** `authorize` allows only ids used by the table's live document and the shelf maps;
  `quote` and `build_bundle` serve only a served, non-official library of a compatible major
  version; a bundle is deterministic (sorted paths, sorted JSON keys) so a resumed transfer
  matches.
- **Consent and limits.** A quote over `LibraryTransfer.MAX_REQUEST_BYTES` (256 MB, settable per
  channel as `size_cap_bytes`) is refused with "The host's collections for this map are 310.0 MB,
  over the 256.0 MB limit, so they are not downloaded." and no question.
  `LibraryTransferConsent` holds every phase and word
  (QUOTING, ASKING, RECEIVING, INSTALLING, DONE, SKIPPED, REFUSED, CANCELLED, FAILED). Every word
  that names the content goes through `LibraryNames` (the display word, `count_of` for plurals:
  "1 item", "4 items"), and `test_library_manager.gd` scans the transfer and cache files for a
  literal of the word and for "plants".
- **Mid-session edits.** The host announces a library its table's document starts using
  (`announce_document`, from `LiveEdits` as an edit is recorded); the client takes the same
  request path (`handle_hint`), and a client `LiveEdits` holds ops while a transfer runs. A later
  request for the same collection is a delta that is merged into the kept copy, without a
  question while it is small.
- **Not done.** Prefetching libraries for shelf maps (the question is asked when a map is set out,
  with its loading overlay behind it); a download cut by a reconnect starts over (the next request
  has a new number, so `AssetStreamer`'s resume does not match; resume within a connection works).

## The cache of downloaded collections

Owner decisions (2026-10-25): a collection received from a host is treated like ANY OTHER (it
just works, can be switched off and removed, persists across sessions, and is only marked "From
host" so it can be found for clearing); asking before every download is not the best behaviour,
so the game keeps a content-addressed local cache and asks once. `LibraryFromHost` is that cache.

- **Storage format.** `user://libraries/<id>/` is the whole collection folder (the partial
  library of "Multiplayer": `library.json` with its `partial` block, `assets/catalog.json`,
  the GLBs, `biomes/`, `surfaces/`), the ownership marker `.tt-owned` (SafeDelete may remove it)
  and `.tt-from-host.json`: `{format 1, id, host (the host's player name, "the host" when
  unknown), version, source_hash (the host's FULL library hash, which is also the hash a map
  saved here records), received_at, last_used (unix seconds), assets (the catalog ids held),
  partial, assets_only, auto_delta (true: later small deltas download without a question)}`. The
  record names its own folder or it is ignored; the registry leaves both marker files out of
  the file list (so they never change a hash, a size or a transfer) and the importer drops a file
  of that name from anything the player imports (it cannot pass for a download). An install
  builds `.fromhost-staging-<id>/` beside the target and swaps it in (an earlier copy is set
  aside as `.fromhost-old-<id>` and put back if a later swap fails), all libraries of a bundle
  or none; start-up removes leftovers of a crash.
- **Delta and merge.** A map that needs more of a kept collection (same version and source hash)
  sends a request for the MISSING items only (plus the biomes and surfaces it does not hold). The
  host answers as for any request: a valid partial of just those items. `LibraryPartialMerge.
  merge` unites it with the kept files (library.json's `partial` block widened; catalog entries
  by id, an id in both must carry the same sha256; biome-defs united by rule key with the refs of
  a rule united; files in both must be byte-equal), then the MERGED library goes through
  `LibraryPartial.inspect` like a fresh download (every GLB's hash and size, `GlbGuard`, the
  reader, the compile dry-run). A tampered delta fails the delta's own inspection first; either
  way nothing is written and the kept copy is untouched. If the quote shows another version or
  source hash than the record (the host changed its library since), the client asks again for the
  whole request and the answer REPLACES the kept copy (after a new question).
- **The player's own copy.** The id is a folder: if `<libraries>/<id>` exists without a record it
  is the player's and is never written (`LibraryFromHost.decide` answers `own`; for the asked-for
  library that is an error `own_copy`, for a dependency the player's copy simply serves).
  Installing the whole collection from a file over a from-host one is the ordinary Replace flow
  and always reads as an upgrade; afterwards it is the player's own.
- **Consent.** Asked once per collection id plus source hash. The question names the collection,
  its author, the number of items and the download size (Download / Skip). After a Download the
  record keeps `auto_delta`, so later deltas of the same collection and hash download WITHOUT a
  question while the delta is under `LibraryFromHost.AUTO_DELTA_BYTES` (5 MB; `auto_delta_limit`
  in tests); a bigger delta, another source hash or version, or a cleared cache asks again. A Skip
  is remembered for the session only (`LibraryTransferChannel._skipped`, key `id|hash`; the
  second map in the session does not ask again, the next session does). The 256 MB size-cap
  refusal (no question) is unchanged and also refuses a covered delta.
- **Last used and the size cap.** `MapLibraryGate.run` calls `LibraryFromHost.note_open_map(ids)`:
  it stamps `last_used` of the from-host collections the opened map uses and remembers the ids as
  in use. The cap (`[library] cache_cap_mb` in settings.cfg, 1024 by default, floor 64; the
  manager's "Limit" menu) is checked before each install: the least recently used from-host
  collections that are neither in the bundle nor used by the open map are removed until the new
  bytes fit (`evict_to_fit`). A collection in use is never evicted, so the cache may sit over the
  cap while maps use more than fits.
- **Managing it.** The manager's `LibraryCacheSection` row (visible once something was downloaded,
  attached by one line in `LibraryManager._on_panel_ready`): "N collections downloaded from hosts:
  X of 1.0 GB", the Limit menu and "Clear downloaded collections", which confirms with how many
  collections, how many MB and how many saved maps use them (`MapDocumentIO.peek_libraries`
  through `LibraryInstall.levels_using`, on demand), then removes only records-bearing folders
  (`LibraryFromHost.clear_all` -> `LibraryInstall.remove` -> `SafeDelete.tree`; a junction inside
  stops that folder and is reported, the rest is still cleared). One collection is removed through
  the ordinary Remove, whose confirmation adds that the host asks first when a map needs it again.
  The detail card says "From host: <label>" and, for a partial copy, a "Partial copy" chip with
  "Holds only what the host's maps used." (the switch is live, Show in folder and Remove are
  there, "New biome from this" is not).
- **Behaviour changes of 2026-10-25.** Removed: `LibraryReceivedStore` (and `promote`, `sweep_
  session`, `sweep_leftovers`), the `.received` source and its precedence rule, the Keep toast
  (`offer_keep`, `LibraryTransferChannel.keep`). A newer host version no longer overlays the
  player's own copy for the session: it is blocked as `older` and the player is told.
- **Tests.** `test_library_transfer_install.gd` (kept as a user library, persistence across a
  simulated restart, delta merge, tampered and contradicting deltas, changed host copy, the
  player's own copy, hostile bundles), `test_library_transfer_flow.gd` (the whole flow: consent
  once, delta, Skip per session, changed copy), `test_library_transfer_consent.gd`,
  `test_library_from_host.gd` (inventory, LRU, open-map spare, last used, clear, junction,
  marker, `.received` migration, import cannot forge the record), `test_library_manager.gd`
  (the cache row, Clear, the card, the limit, the word scan), `test_safe_delete.gd`.

## Authoring

The library manager (step S6) is the player's way to see, add, switch off and remove libraries;
the biome designer ([biome_designer.md](biome_designer.md), step S8a; S9 follows). The words the player sees come from `LibraryNames` (today
"Collections"); this section, like the code, says library.

- **Entry points.** The title's masthead has a quiet tool, Collections (`TitleScreen.
  libraries_button`), and the New map dialog a "Manage collections..." link at its footer's
  left (`NewMapDialog.manage_button`, always in view, whatever the fields above scroll). The
  mismatch dialog of a map that names a library this game lacks has a third choice, "Manage
  collections", which answers Cancel (the open returns to the title) and opens the manager over
  it so the library can be added and the map opened again.
- **The sheet** (`LibraryManager`, 1120 wide, the manager's own scrim, shared with a dialog under
  it: one scrim, UI_TASTE G1). The list at the left, one `LibraryRow` per `LibraryRegistry.list()`
  entry (core first): name, version and author, "2 assets, 1 biome · 5 KB" (or, for a library that
  fails, its first reason in one plain sentence), a Built in (official) / Yours / From host chip
  and an on switch in two fixed columns (a library that fails shows the "Needs attention" pill in
  place of the switch; core and a developer override cannot be switched off; a library that needs
  a switched-off one fails and says so). The card at the right (`LibraryDetail`): heading,
  version, author and licence, the origin and state chips (On, Off, Needs attention), the
  description, the reasons first when it fails, Holds / Size / Needs (each dependency with its
  state: met, missing, outside its range, off, failing) / Link / Folder (with Copy path), the
  biomes as the pictures the New map dialog uses (a served library only), every warning the reader
  and the compiler had, then Verify, Show in folder and Remove (the last two only for a library the
  player installed). Footer: the last thing that happened in words and an icon (red with an alert
  icon for an error; the toast draws above the scrim too), Refresh, Import file..., Import
  folder... and Done (the one primary). Full description: docs/UI_SYSTEMS.md "Collections
  Manager" and "Collections manager UX pass" below.
- **Switching, installing, removing** each call `LibraryRegistry.set_enabled` / `LibraryInstall`,
  then `LibraryImportFlow.refresh_all()`: `LibraryRegistry.refresh()` and
  `FoliageLibrary.refresh_libraries()`, which serves the libraries again and emits
  `EventBus.foliage_library_changed`. The open New map dialog listens to it and builds its
  starting-place fields again, keeping the pick when it still exists (a switched-off library's
  field leaves without reopening the dialog); Root rebuilds an open map as for any foliage
  change. A removed library that was switched off is switched on again, so adding it back is not
  a surprise. `LibraryImportFlow.serve_palette = false` makes `refresh_all` only rescan (tests).
- **Remove** (it also deletes the library's baked surface cache, `user://library_cache/<id>/`)
  asks: what is deleted, and how many saved maps name the library
  (`LibraryInstall.levels_using`, read from each `map.ttmap` manifest only, done when the button is
  pressed, never in the background). Those maps then show the mismatch dialog when opened.
- **Verify** hashes every GLB of the selected library against the catalog's `sha256` and `bytes`
  and runs `GlbGuard` over it (`AssetStore.verify`, also for an official library), 6 ms of
  work a frame with a bar, Stop and a line per failing file. A library that is off or failing has
  nothing registered, so it says to turn it on first. Core is verified like any other library (its
  GLBs are files of the pack).
- **Importing** (design 5.5), all of it in `LibraryImporter` and `LibraryInstall`, which have no
  scene tree and are tested with generated zips (`test_library_importer.gd`):
  1. `inspect` reads the zip's central directory (`ZipEntrySizes.read_directory`, which already
     refuses Zip64, an oversized directory and a file that is not a zip) and judges every entry
     BEFORE extracting. Hard limits (`LibraryImporter.default_limits`): 20,000 entries, 1 GiB
     uncompressed, 200 times expansion (per entry over 1 MiB and for the whole archive), a library
     of at most 512 MiB (150 MiB warns), a file at most 1 MiB (JSON), 4 MiB (the catalog), 64 MiB
     (GLB), 48 MiB (PNG, JPG) or 1 MiB (text). Refused: any extension but `.json .glb .png .jpg
     .txt .md` (case ignored, no extension at all), an absolute path or a drive, a backslash, a
     `..` or `.` or empty segment, a Windows device name or a trailing dot or space, a path over 120
     characters or nested deeper than 8, two names that differ only by case (and a name that
     appears twice), a symbolic link (the Unix mode in the high half of the external attribute
     word, or the DOS reparse bit), a device or other non-file mode, an encrypted entry, a method
     other than stored or deflate, sizes that disagree, no `library.json` at the top. `__MACOSX`,
     `.DS_Store`, `Thumbs.db`, `desktop.ini` and a `.git` folder are left out and counted, not
     refused. A zip of the library's own folder (one top folder holding `library.json`) is
     unwrapped. A folder import follows the same rules (links, junk, depth, counts).
  2. `stage` extracts or copies into `<libraries>/.incoming/<random>/` (the registry skips dot
     folders), re-checking each target stays inside it and that every entry reads back at its
     declared size; on any problem or Cancel the folder is deleted. It runs on a worker thread
     (`LibraryImportFlow`) with a `Progress` the sheet polls.
  3. `examine` reads the staged folder (`LibraryReader`), compiles it in a dry run through the
     dependencies installed (a `<lib>:<id>` ref resolves against them), and answers the card:
     identity, counts, size, each dependency's state, every warning, whether the id is reserved
     (`core`, `legacy`, `draft`, `dev`, or an id the game's own libraries hold: refused with no way
     to install) and the relation to an installed copy of the same id.
  4. The install card (`LibraryInstallCard`) shows it and says "This <collection> only contains art
     and settings, never programs." Install moves the folder to `<libraries>/<id>/`; a same-id
     library is replaced only on the explicit Replace (the primary reads "Replace v0.3.1" and the
     text puts both versions side by side), the old folder set aside until the new one is in and
     put back if the move fails. A cancelled or closed card, and a leftover after a crash
     (swept when the manager opens), leave the quarantine empty. `official` is never written by
     an import: it comes from where a library lives.
  5. Drops: `TitleScreen._on_files_dropped` sends a drop to the flow only when
     `LibraryImporter.is_candidate` says a file or folder holds a `library.json` (a zip with a
     `.ttlib` or `.zip` extension, or a folder); everything else still reaches `LibraryImports`,
     the Blender map check. With the manager open the title ignores drops (a scrim is up) and the
     manager takes the first dropped path whatever it is, so a wrong file gets the refusal sheet
     instead of silence.

### Collections manager UX pass (2026-10-25)

The owner reviewed the manager (49 stories, UX-1 to UX-12, plantgen
`docs/library_manager_review/`) and decided the rest; what changed, and where:

- **Needs attention** (UX-4): a failing row is dimmed and shows the pill in the state column
  where the others have the switch (`LibraryRow`; the chip columns are fixed and a test measures
  their x). A second folder with an id already listed is its own row (key `id@folder`, the folder
  in its caption) and Remove leads and is Danger; `LibraryInstall.remove_folder` deletes by folder
  so it never takes the copy that stays. The list top says "2 collections need attention".
- **Plain reasons** (UX-3): `LibraryReasons.explain` turns each raw reason into `{message, action,
  details, kind}`: one sentence ("This collection needs Core 9 or newer; this game has 1.0.") and
  what to do ("Update the game or remove it."), the technical text behind "Show details". No
  `user://` path, `sha256` or JSON in the first line; Verify's file errors are plain too
  (`LibraryVerify.plain_error`).
- **Replace, Reinstall, refuse** (UX-5): `LibraryInstall._check_identity` refuses a file OLDER than
  the installed copy ("This is version 0.2.0; 0.4.0 is installed. Remove the installed one first if
  you want the older version."), the same version is "Reinstall" (a repair), a newer one reads
  "Replace v0.3.1 with v0.4.0" with how many more or fewer assets and biomes it holds
  (`change_line`, counts only). A copy a host sent is exempt: the whole one is an upgrade whatever
  its version.
- **An install that fails** (S24, UX-2): `LibraryInstallCard` goes busy on Install and the flow
  answers `dismiss()` or `show_failure(message, can_retry)`: the error stays on the card in red
  with an icon, Retry when `LibraryInstall.install`'s `retry` says it can work (a refused move, a
  folder that cannot be made, a folder in use; not staged files that are gone) and Close, which
  empties the quarantine; the manager's footer shows it too (`install_failed`), and the toast draws
  above the scrim (`Constants.LAYER_TOAST` 108). Seams for tests: `LibraryInstall.rename_override`
  and `make_dir_override`.
- **Layers** (UX-1): `BiomeDesignerPicker` is on `LAYER_SUBDIALOG` (101), above the manager's scrim
  (it drew under it and left a ghost).
- **Words** (UX-6): no dialog says "plants"; every phrase goes through `LibraryNames`
  (`mismatch_title`, `open_without`, `host_uses_title`, `remove_tail`, `count_of`, `license_text`,
  `drop_hint`, `attention_summary`; `CATALOG_URL`, empty until the owner names a catalogue, hides
  the "Find collections" button). "Built in" is the one term; core's placeholder licence ("TBD
  (...)") reads "Included with the game" (its `library.json` is not edited).
- **The mismatch dialog** (UX-7): `LibraryMismatchDialog`: the link when the map's record (an
  optional `url` of a `libraries` entry, written from the library's own `url`) or the installed copy
  has one, Import file... and Import folder... in place (a successful install ends it with
  `MapLibraryGate.RETRY` and `run` checks the map again), Manage collections opens the manager over
  its own scrim (a frame after the dialog leaves).
- **Discoverability and the card** (UX-9, UX-10): the persistent hint, the install card names the file
  it read and leaves the manager visible, dimmed behind it, the biome strips are three across and
  the sheet taller so core's nine are whole rows at 1600x900, Copy path on the folder row.
- **Verify** (UX-11): Stop works (at least one file a frame) and is tested; Verify all
  (`LibraryVerifyAll`) checks every served collection with a bar and Stop and shows ONE result list.
- **Keyboard** (UX-12): see docs/UI_SYSTEMS.md; `test_library_manager_ux.gd`.
- **Rescan, no file watch** (owner question 8): `LibraryRegistry.disk_signature()` (one directory
  listing per root, two stat calls per user folder, no file read) is compared with the one the last
  `refresh()` saw when the manager opens, when the window regains focus
  (`NOTIFICATION_APPLICATION_FOCUS_IN`) and on Refresh; only a difference (or the button) rescans
  and serves again. Cost with the sheet closed: none. Cost open and idle: none (no timer, no
  per-frame work). A check is about a millisecond for a dozen collections; the rescan it avoids
  reads every `library.json` and `catalog.json`.
- **Extension points** for the cache work and others: `LibraryManager.list_extras` (a box under the
  list), `footer_extras` (a box in the footer), `LibraryDetail.detail_extensions` (callables run at
  the end of `show_library`), and `LibraryCacheSection.attach` (one line in `_on_panel_ready`).
- **Button shadows** (the owner's report): root cause and the audit in docs/UI_SYSTEMS.md "Collections
  Manager" (`ShadowGutter`). The audit found and fixed nine scroll sites: the manager's list and
  card, the designer picker's sections, the New map dialog's fields, the avatar roster's grid, the
  designer's slot list and ground strip, `PaneStack` (every pane of the authoring and Visuals
  drawers and the avatar builder) and the room's shelf. Second pass (2026-10-25): the designer's
  inspector and ground look scrolls (`ShadowGutter.outset`, rows stay put) and every `Foldout` of
  its sections (`Foldout.button_room`, a clip that reaches out by the glass ring's room); the test
  now selects every rule, opens the look editor, the density popup and the Save as dialog, and
  walks the Events pane, the thin and bridge tools. Not instantiated by the test: the avatar
  builder's 3D preview viewport (no buttons), the asset browser's pack tabs (need installed
  packs), the update dialog's scroll beyond its default state and any popup menu (a Window of its
  own, outside the clip walk).

## Verification

- Multiplayer transfer (2026-10-24): `test_library_transfer.gd` (plan for missing, installed,
  older, same-version, other-major, disabled and reserved libraries; request validation;
  authorize; the partial holds only the used assets, rules and surfaces; dependencies;
  quote sizes equal the bundle's; deterministic bundles), `test_library_transfer_install.gd`
  (a good bundle installs, serves and loads through `AssetStore`; wrong sha256 or size, extra
  and stray files, traversal, drive and device paths, extensions, `core`, official and reserved
  ids, id and version mismatch, a full library posing as partial, no hashes, a bad GLB,
  truncation, a header asking for 3 GiB, the total cap, garbage: each refused with its code and
  nothing written; LRU, touch, session sweep, leftovers, promote with and without an importer,
  precedence against an installed library), `test_library_transfer_consent.gd` (the model),
  `test_library_transfer_flow.gd` (the full request, serve, stream and install between two
  channels and two streamer doubles over a message queue, and the failure cases listed in
  NETWORKING.md). Render proof: the question, the progress sheet and the size-cap notice were
  captured from a windowed probe at 1280 by 720 and read (the confirmation dialog's look).
- Step S6 tests: `test_library_importer.gd` (40 checks, no scene: the happy path of a zip, a zip of
  the library's folder, a folder and a parent folder, `is_candidate`, progress and cancel; hostile
  archives written byte by byte by `tests/unit/zip_builder.gd`: zip slip with `..`, absolute and
  drive paths, backslashes, a bomb by ratio before anything is read, a total over the ratio, too
  many entries, a total size and a per-file cap, every non-data extension (`.gd .exe .dll .tscn
  .tres .pck .bat .html .gltf` and none), case of the extension, symbolic-link, reparse and device
  modes, case twins and a repeated name, Windows device names and trailing dots, an over-long
  and a too deep path, no `library.json` or two top folders, an encrypted and an unsupported
  method, disagreeing sizes, a truncated archive cut three ways, junk bytes, an empty file, a
  wrong extension, a damaged entry that fails the stage and cleans up, junk files left out; then
  the card: unreadable libraries, reserved ids (`core`, `legacy`, `draft`, `dev`), an id of an
  official library, a missing, unmet and switched-off dependency, the relation to an installed
  copy, Replace and its rollback guard, install refusing files outside the quarantine and an
  unchecked card, `discard` and `sweep_incoming`, the quarantine never served, `remove`,
  `levels_using`, and a source scan that the importer loads no resource and runs nothing).
  `test_library_manager.gd` (30 checks, the real flow and its worker thread over generated zips:
  the list, badges, switches and core locked, the card and its actions per origin, dependencies,
  a failing library's reasons, switching with persistence and the signal, Remove with its
  confirmation naming the saved maps and the deletion, a switched-off library coming back on after a
  removal, Verify ok, Verify naming a changed file, Verify refusing an off library, an import
  through Install, Cancel leaving nothing, Replace with the installed version in its label, a
  hostile archive and a reserved id refused on the card, a second import ignored while a card is
  open, a drop of a zip, of a stray file and of a folder on the manager, the title's tool and drop
  routing (a library to the flow, a `.glb` and a zip without `library.json` to the map check), the
  New map dialog's link and its rebuild when a library is switched off and on and keeping its
  pick, the missing-library dialog's third choice, the one display-word rule over every file that
  shows it, and both sheets inside a 1280x720 canvas). `test_library_compile.gd` lets the import
  step touch folders (it never discovers libraries) and still forbids it elsewhere.
- Render proof (2026-10-24, `jobs/library_manager.json` with `probes/library_manager.gd`, 1600x900
  and 1280x800, `--full` for the verdict set): core (built in) and a generated user library
  `alienworld` (the test world's, 0.3.1) in the worktree's own `user://libraries`, imports from
  `user://_libmgr_inbox` (a zip of a folder, a newer alienworld, a hostile archive). The list, the
  card of core and of alienworld (description, Holds, Size, Needs met, Link, Folder, its biome as
  the New map picture), Verify's result, the install card of Beta Marsh (a zip of its folder,
  author, licence, 3 assets, core ^1.0 met, the promise line), Beta Marsh installed and selected,
  alienworld switched off ("Off" in the row and the chip), the Replace card (v0.4.0 against
  0.3.1, "Replace v0.3.1"), the refusal of an archive holding a script and a `../` path (Close
  alone, nothing extracted), Remove's confirmation, the New map dialog with its footer link, the
  manager over it and the dialog's field gone after Beta Marsh was switched off. Fits both sizes.
- Step S4 tests: `test_library_registry.gd` (scan order and sources, official derived from the
  location, the manager's list, the built-in core, prefixed ids, a cross-library ref, retired and
  aliased dependency ids, bindings not taken from a user library, duplicates, folder naming, dot
  folders, unmet and missing dependencies, ranges, a broken or disabled dependency, cycles,
  depth, load order, the 16 cap, enable and disable persisted in a scratch settings file,
  aliases, `assets_used_by`, `record_of`, the developer override last, a biome's own thumbnail,
  `refresh_libraries`), `test_library_versions.gd` (ranges, and `LibraryResolver` over plain
  dictionaries), `test_library_assetstore.gd` (lazy parse, the cache, the (library, id) key, a
  hash or byte mismatch refused for a user library and not for an official one, a missing file,
  a missing node, materials replaced, `GlbGuard` on crafted GLBs: texture size from the header,
  uri, counts, JPEG), `test_map_libraries.gd` (the record, check, "open without", aliases, the
  gate, `LibraryGroups`), `test_new_map_dialog_libraries.gd`, additions to
  `test_map_document_io.gd` (format 2 against 3, the record round trip, malformed entries,
  `peek_libraries`), `test_library_ids.gd` and `test_library_reader.gd` (dependencies, refs into
  a dependency, `package_stem`, `sha256` and `bytes`). The two-library world is written at test
  time by `tests/unit/library_world.gd` (`core` official 1.2.0, `alienworld` user 0.3.1
  depending on `core ^1.0`, real GLBs, a catalog with bytes and sha256).
- Render proof (2026-10-24, `jobs/library_s4_two_libraries.json`, half size; a copy of plantgen's
  badlands plants as a user library `alienworld` in the worktree's `user://libraries`): the New
  map dialog shows core's nine biomes and Bare ground, then an "Alien World" field with Red Mesa;
  a 150 ft forest map painted over its right third with `alienworld__red_mesa_summer_s1` draws
  the second library's cacti, snags, boulders and dry grass beside the core forest, and the save
  writes format 3 with `libraries` [alienworld 0.3.1, core 1.0.0] (probe `library_s4.gd`).

- Unit tests: `test_library_ids.gd` (grammar, runtime ids, portable names),
  `test_library_contracts.gd` (S2: roles, habit flags, caps against the palette limits, the
  `export_json` round trip, now with `bindings` and `surface_caps` and without `legacy_habit`),
  `test_rule_habit.gd` (S2, renamed at S10: every shipped rule's explicit habit plans the role the
  retired key lists gave, a rule with no habit has none, the rule's habit decides, the validator's
  `role`/`habit`/`weight` whitelist), `test_library_reader.gd` (the miniature library reads clean; malformed and hostile
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
- Terrain response (S12a): `test_library_response.gd` (the contract's `response_problem` per
  fault and the published axes, the reader's errors and warnings, the compiler carrying the fields
  only when present, the validator's sort, clamp and drops) and `test_scatter_curves.gd` (engine,
  see [scatter.md](scatter.md)). Render proof (2026-10-24, `jobs/library_s12a_terrain.json`,
  half size): the same hilltop map built under `out/lib_slice` and under `out/lib_s12a` (a copy
  with `slope_min_deg` on dry_grass, shrub and acacia_young and a slope curve on acacia): the
  flat-ground acacias are thinned to the few on gentle ground (about half the trees of the
  size 24 view remain), the low dark shrub domes are gone from the gentle ground, and the tall
  dry grass that carpeted the flat is replaced by bare ground and the other grasses, with the
  slope keeping its grass. The same hill, sky and paths. Plantgen: `packaging/library_check.gd`
  (`_check_terrain`), `library_import.gd` and `library_compile.gd` carry the fields and
  `tests/test_library_response.gd` round-trips them; plantgen's vendored `packaging/contract.json`
  was regenerated (it gained only the `response` block).
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
- Step S10 proof (2026-10-25): the shipped `res://libraries/core` is the rebuilt library
  (`out/lib_core_s10`, trimmed meshes, built from the package `out/lib_core_pkg2`). Before the
  overlay code was deleted, `test_library_row_parity` (env vars set to those two folders) passed
  against it (nine biomes, 2074 checks), and the package route's snapshot was frozen into
  `tests/fixtures/library_core_golden.json` (biome fields, rule texts, plan roles, rows at seed
  1234 as `count:md5`, assets table, all by package stem). The test now needs no plantgen folder:
  it serves the shipped core and compares it to the golden, mapped back through the catalog's
  `package_stem` (2061 checks; the digests are Windows' bytes). Rows per biome over the 32 m
  square: alpine meadow 6196, birch woodland 3486, boreal taiga 2228, burnt forest 347, grassland
  meadow 9875, rocky badlands 1117, savanna 4196, temperate forest 4418, wetland riparian 7470.
  `scatter_golden_1234.json` was re-pinned from the shipped core. Render jobs `core_nine_biomes`
  (all nine biomes, home and size 14) and `library_s5_surfaces` (now one route) were read by eye.
  What follows is the S5 record, kept for history (its commands need the plantgen folders and
  the retired overlay code).
- Step S5 proof (2026-10-24, plantgen `out/lib_core` built from `out/lib_core_pkg`, the nine
  biomes, 121 rules, 268 library assets, 288 palette assets, 36 surfaces):

```
godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/compile_library_cli.gd -- --library D:/dev/plantgen/out/lib_core --out <compiled.json> --surfaces 1
godot --headless --path D:/dev/plantgen --script res://tools/library_diff_cli.gd -- --compiled <compiled.json> --package D:/dev/plantgen/out/lib_core_pkg --plan D:/dev/tabletop/core-library/plan.json --all 1
# PowerShell: $env:PLANTGEN_LIB_CORE='D:/dev/plantgen/out/lib_core'; $env:PLANTGEN_LIB_CORE_PKG='D:/dev/plantgen/out/lib_core_pkg'
godot --headless --path D:/dev/tabletop/tt-sim --script res://addons/gut/gut_cmdln.gd -- '-gconfig=tests/.gutconfig.json' -gselect=test_library_row_parity
godot --headless --path D:/dev/tabletop/tt-sim --script res://addons/gut/gut_cmdln.gd -- '-gconfig=tests/.gutconfig.json' -gselect=test_library_core_surfaces
godot --path D:/dev/tabletop/tt-sim --windowed --resolution 1920x1080 --position 320,120 --script res://tools/render_jobs/run.gd -- library_s5_surfaces --full
```

  (1) Warnings: the compile prints 0 `validate_palette` warnings and the registry's `apply` 0
  warnings for the whole library (the reader warned `roles` on all 268 catalog entries until
  `LibraryContracts.CATALOG_ENTRY_KEYS` learned the key). (2) Rules and assets table: the diff
  tool finds 0 differences in all nine biomes (every biome field including the thumbnail path,
  every rule field, every asset id after the `package_stem` mapping) and 0 in the assets table
  (node, wind category, size class, dimensions of 288 assets); the water surfaces the library
  writes explicitly equal the game's defaults for each biome. (3) Rows: `test_library_row_parity`
  generates every biome at seed 1234 over a 32 m square through the package route
  (`overlay_package` of `lib_core_pkg`) and the library route (the dev override) and finds the
  same rules (authoring fields stripped, habit and plan role equal), the same biome fields and
  byte-identical rows after the id mapping: alpine meadow 6196 rows, birch woodland 3486, boreal
  taiga 2228, burnt forest 347, grassland meadow 9875, rocky badlands 1117, savanna 4196,
  temperate forest 4418, wetland riparian 7470 (2074 checks, 21 s). A miniature of the same
  comparison (a core-shaped library with renamed ids, surfaces by name, a thumbnail and bindings,
  against a hand-written package) always runs. (4) Surfaces: `test_library_core_surfaces` bakes
  all 36 sets from their library PNGs and compares them with the editor import (formats, sizes,
  mip counts; normal, ORM and height byte for byte, albedo decoded within 0.1 of 255 on
  average), serves the library over the installed palette and finds every biome's ground, cliff,
  scree, water, accents, paths, look and thumbnail, and the surface table (kind, role, tile,
  mean), equal to the installed route, 132 maps resolved through `SurfaceStore` equal to the
  imported ones, every label as `SURFACE_LABELS` or the spelled-out id gives today, and
  `LibraryBindings` equal to its legacy defaults for all 12 keys. Render job
  `library_s5_surfaces` (savanna, temperate forest and rocky badlands on the terraces landform,
  seed 1234, full size, one run; a_ is the package route with the installed surfaces, b_ the
  library with its own PNGs): the ground alone (plants hidden) differs by 0.06 (badlands), 0.07
  (temperate forest) and 0.03 (savanna, once warmed up) of 255 mean absolute; with plants 0.34,
  0.23 and 0.36 at the home view and 0.38, 0.32 and 1.42 at size 14. The first savanna map of a
  run drew its ground 0.5 of 255 away from every later one (package route against itself 0.455,
  library against itself 0.03; the warmed-up pair of the savanna ground is the 0.03 above, from
  a repeat job), so the 0.68 and 1.42 the first run showed there are a warm-up effect of the
  run, not of the surfaces. Read by eye the a_ and b_ frames are indistinguishable. The plants' share is the
  usual run-to-run noise of two builds (sway, mesh import), which S3 measured at 0.24 to 0.75.
  (5) The asset-id mapping is recorded above (The core library). (6) Thumbnails are copies of
  the installed 512 px JPGs.

## Destructive operations

On 2026-10-24 a recursive delete in the importer emptied a whole disposable worktree (about 4000
tracked files). The trigger was never seen, but the mechanism was reproduced (2026-10-24, a
scratch copy of the pre-guard tree): Godot reads `""` and `"."` as the working directory
(`DirAccess.open("")` opens it; `dir_exists_absolute("")` is true), which in a developer run is
the project. A root that is empty, relative or unset therefore turns "delete the folder `<root>/x`"
into "delete the project's `x`", and `remove_tree("")` or `remove_tree(".")` into "delete the
project". Reproduced on the old code, each in its own scratch project: `remove_tree("")`,
`remove_tree(".")` and the tests' own `World.remove_tree("")` (all 4031 tracked files), an
`incoming_override` of `"."` through `sweep_incoming` (4018), the old received store's
`sweep_leftovers(".")` (4018; the store was replaced by `LibraryFromHost` on 2026-10-25), and, with `user_root` empty, `LibraryInstall.remove("scenes")` / `install(replace)` /
`ReceivedStore.write_library("", "scenes", ...)` (the project's `scenes` folder, 470 files: a
library id is any `[a-z][a-z0-9_-]{1,31}`, so it can be the name of a project folder). A sweep
with `user_root` empty alone only reached `./.incoming`. Not reproduced: how `user_root` got
empty (it is `Paths.LIBRARIES_DIR` at load, `user://libraries/` in every run tried: GUT, `--script`,
`--data-root`).

The fix is at the root, not only a guard:

- **`LibraryPaths`** (`utils/library/library_paths.gd`) is the only thing that turns a configured
  string into a folder the library code may touch. `resolve(path)` returns `{ok, path, error}`:
  an ABSOLUTE, normalised path strictly inside the user data folder (`user://`), else an error.
  Empty, whitespace, relative, `res://`, any `..` segment, a bare drive or root, the user data
  folder itself, its parents, the project folder or a parent of it: all refused. The named roots
  `libraries()` (`LibraryRegistry.user_root`), `incoming()` (`<libraries>/.incoming` or the test
  override), `received()` (`<libraries>/.received`, the old session-only folder, read only to
  adopt it) and `cache()` (`SurfaceCache.root`) resolve the
  configured string each time they are asked, so an unset root fails closed. `child(root, name)`
  accepts one plain segment only (a library id can never carry a separator, `.` or `..`).
- **`SafeDelete`** (`utils/library/safe_delete.gd`) is the ONE recursive delete. `tree(path,
  base)` removes a folder only when: (a) it is strictly inside an allowed base (the four roots
  above, or the base the caller names, resolved the same way; never the base itself);
  (b) it holds the `.tt-owned` marker our code wrote when it created it; (c) neither it, nor a
  folder between the base and it, nor anything inside is a symlink or junction (links are never
  followed, and one inside the tree stops the whole delete before the first file goes);
  (d) it has at most 200,000 entries and 24 levels (`max_entries` for tests); and then it logs
  the count. The tree is walked first (hidden files included: a dot file is hidden on macOS and
  Linux), the marker is deleted last, so a failed delete can be retried. `file(path, base)` is
  the single-file twin. A folder without the marker is refused and reported (`printerr`), never
  deleted. `mark`/`adopt`/`mark_if_only` write the marker.
- **Where the marker is written** (lazily, where our code creates the folder): `stage` writes it
  into the quarantine folder before extracting (a `.tt-owned` inside an archive is dropped as
  junk by `inspect`, so an archive cannot forge one); the staged folder keeps it when `install`
  renames it to `<libraries>/<id>`; `LibraryFromHost.commit` marks `.fromhost-staging-<id>` (the
  folder keeps the marker when it is swapped to `<libraries>/<id>`); `SurfaceCache.write` marks
  `library_cache/<id>`. The registry excludes the root marker and the from-host record from a
  library's file list, so they are never part of a library's hash, size or transfer, and the
  importer drops a `.tt-from-host.json` from an import. Everything that removes a downloaded
  collection (Clear, one Remove, the size-cap eviction) is `LibraryInstall.remove` ->
  `SafeDelete.tree`; `LibraryFromHost.remove` refuses an id whose folder has no record.
- **Migration** (a folder without a marker is never deleted): `LibraryRegistry.refresh()` marks
  every direct child of the user's libraries folder that has a valid library id and a
  `library.json` (a library installed before the marker existed); an old `.received/<id>` folder
  is moved into the libraries folder as a from-host collection when its `<id>.received.json`
  record sits beside it and it passes `LibraryPartial.inspect` (else reported and left); a surface
  cache folder is adopted when it holds nothing but `.ttimg` and `.tmp` files. Anything else
  stays, and `Remove` says "was not put there by the game; delete its folder by hand". Quarantine
  folders made before the marker existed are left by the sweep (`last_sweep_skipped`).
- **Not recursive, but guarded the same way**: the surface cache's replace-a-file, the received
  store's record files, `AssetCacheManager`'s index-driven removals (`SafeDelete.file` against
  `Paths.ASSET_CACHE_DIR`: the index is a file on disk) and `LevelManager.delete_level` /
  `delete_level_folder` (absolute, strictly inside `levels_dir`; an empty path used to list and
  empty the working directory's top level).
- **Tests**: `tests/unit/test_safe_delete.gd` feeds every entry point empty, relative, `.`,
  `..`, `res://`, drive and parent roots, hostile ids, an archive with a forged marker, a
  stranger folder, a junction inside, as and on the way to the folder (made with `mklink /J`),
  an oversized and a too deep tree, and asserts a canary file (marker and all) and the project
  survive. Test cleanup uses `ScratchDir.clear` (`tests/unit/scratch_dir.gd`) or guards its own
  helper with `LibraryPaths.verify`.

Other deletes in the repo (not library code): `Paths._remove_tree` (only a root `test_data_root`
names), the `_remove_tree` copies in `tools/render_jobs/probes/` and `tools/map_size/` (dev
probes, unguarded), `AssetModelCache`/`AssetDownloader`/`AssetManager`/`UpdateManager` single-file
removals of paths the code builds itself. The designer's `LibraryWriter` (S8a) writes and
renames single files and removes its lock file only; any folder delete it adds must use
`SafeDelete`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work". The library steps (S6 onwards: the
manager, the designer) are in plantgen's design doc section 6. **Not built (product gaps, not
bugs):** S47, updating a collection from its link (the manager shows a collection's `url` and
nothing fetches it; an update is a new import by hand), and S48, live reload (the manager rescans
on open, on window focus and on Refresh behind `disk_signature`; there is no file watcher, so a
collection edited on disk while the game runs shows after the next rescan, never on its own).
**Old copies** (2026-10-25): a `.received/<id>` leftover whose collection is installed is reported
once (a `<id>.reported` file beside it remembers, plus the process), and the manager's
`LibraryStaleSection` row offers "Remove old copies" behind a confirmation
(`LibraryFromHost.remove_stale_received`, SafeDelete). Left over: the cache is not
pruned and nothing prewarms it on a worker thread (the first ground draw of a new surface bakes
about 0.2 s on the main thread); `ScatterGround.SCORCHED_SURFACES` and
`PaletteLibrary.WATER_SURFACE_DEFAULTS` still hold their legacy values (their files belong to the
scatter and validator steps); `contract.json` does not yet publish the surface caps (2048 px, 64
surfaces) or `LibraryBindings.TABLE`. Left over from S6: the player-facing name is undecided (one
constant, `LibraryNames`); no "From URL" import and no update link beyond showing a library's
`url` (design 5.5, later); no signing (design open question 8); Verify checks files, not that
every catalog node is at the identity transform (design 2.10 layer 3, the GLB is only opened
when first used); a large import reads on one
worker thread and the examine step (a compile) runs on the main thread, which is fast for a
library of hundreds of assets and not measured past that; the manager does not list what a
failing library's dependents are; the title's Collections tool has no capture in the UI tour yet.
Left over from S4: the authoring panel's Biomes field, which still
lists every biome of every library in one grid without headers; a map opened "without those
plants" keeps the painting of the missing library's areas but regenerates no plants there
(regeneration is offered, not automatic, because it discards scatter hand edits). Left over from
S10 (core shipped, treecube removed): (the nine biome thumbnails were re-rendered from the plantgen
look on 2026-10-25, see "Biome thumbnails"); the surface bake runs on first use (about 0.2 s a
surface on a GPU build, the maps a map uses; the cache then lives in `user://library_cache`, about
170 MB for all 36 surfaces) and the release could ship the baked cache (`SurfaceCache` is plain
bytes) to skip it; `settings.cfg` `[foliage]` keys are dead and left in the user's files; the
`core` library carries `license: CC BY 4.0` (since v0.3.0; `LICENSE.md` and `NOTICE.md` ship beside
`library.json`); `contract.json` in plantgen is regenerated by `compile_library_cli --contract`
(committed there, last vendored with the `seasons` block).

## History

- 2026-10-25: libmgr-ux: the collections manager after the owner's review: the Needs attention
  pill and the fixed chip columns, plain reasons (`LibraryReasons`), the older file refused and
  Reinstall, an install that fails stays on the card with Retry (`LibraryInstall.install` returns
  `code` and `retry`), toasts above every scrim (`LAYER_TOAST` 108) and the picker above the manager
  (`LAYER_SUBDIALOG`), one word and no "plants", the mismatch dialog's link and import
  (`LibraryMismatchDialog`, an optional `url` in a map's `libraries` record), Verify Stop and Verify
  all, the keyboard, rescan on open, focus and Refresh (`disk_signature`), and `ShadowGutter` with
  its audit (`test_shadow_gutter.gd`) after the clipped shadow of Verify. Findings: a GDScript class
  with a static method named `wrap` must call it as `ShadowGutter.wrap` inside itself (the global
  `wrap()` wins); `NOTIFICATION_APPLICATION_FOCUS_IN` reaches every node; a `Control.theme_type_variation`
  lookup in a script run before the tree settles returns the base type's style, so extents are read
  from the `Theme` itself (`ShadowGutter.extents_in_theme`).
- 2026-10-25: libcache: a collection a host sends is an ordinary user library marked from host
  (`LibraryFromHost`, `.tt-from-host.json`), not a session-only copy. Removed:
  `LibraryReceivedStore`, the `.received` source, `LibraryRegistry.received_root`, the Keep toast
  and `promote`, the resolver's received-beats-installed rule. Added: a content-addressed cache
  with delta requests and merge (`LibraryPartialMerge`, `LibraryTransferInstall`), consent asked
  once per collection and source hash (a small delta of an agreed collection downloads without a
  question), a 1 GB size cap with least-recently-used eviction that spares what an open map uses,
  the manager's "downloaded from hosts" row with Clear, the "From host" and "Partial copy" card
  text, migration of a leftover `.received` folder, and every transfer string through
  `LibraryNames` (no "plants", `count_of` for plurals). A host's newer version no longer overlays
  the player's own copy (blocked as `older`). See "The cache of downloaded collections".
- 2026-10-25: step S10, off treecube: `res://libraries/core` ships (route K, see "The core
  library"), `assets/palette` (160 MB: 384 LFS files, the imported palette), `PaletteOverlay`,
  `PaletteLibrary.overlay_package`, `LegacyHabit` and the scatter key lists, the
  `AuthoringPanel.SURFACE_LABELS` table, `LibraryRegistry.BUILTIN_VERSION` and the built-in core
  entry, the resolver's built-in provider, the `[foliage]` package switch with its F3 checkbox and
  the render ops `palette_overlay`, the treecube half of `foliage_library` and the plantgen A/B
  jobs are deleted. `LibraryLayer` holds the merge, `FoliageLibrary` serves and adapts,
  `contract.json` publishes `bindings` and `surface_caps` (and no longer `legacy_habit`), and
  `LibraryReceivedStore.promote` (Keep) goes through `LibraryImporter` (inspect, stage in the
  quarantine) and `LibraryInstall` (examine, install). Tests: deleted `test_palette_overlay.gd`
  (it pinned the overlay's byte-compare and compressed-like logic); rewritten
  `test_palette_builtin.gd`, `test_library_core_surfaces.gd`, `test_library_row_parity.gd`
  (golden), `test_foliage_library.gd`, `test_rule_habit.gd` (was `test_legacy_habit.gd`);
  migrated asset ids and surface paths in 25 more.
- 2026-10-25: step S8a: `LibraryQuery` (the query clauses of design doc 2.6.3 with goldens: the nine
  biomes' rows stay byte-identical), lock files (`biomes/<id>.lock.json`, read by the reader and
  compiler, part of the library hash), `LibraryContracts.QUERY_*` (also in `contract.json` under
  `query`; plantgen's vendored copy needs regenerating), `designer_context`, `serve_draft` and
  `designer_writable` on the registry, `AssetStore.register_missing`, and the biome designer
  ([biome_designer.md](biome_designer.md)).
- 2026-10-24: step S6: the library manager ("Collections"): `LibraryNames` (one display-name
  constant), `LibraryImporter` (inspect a zip or folder against the caps before extracting,
  quarantine, worker-thread stage), `LibraryInstall` (examine with a dry-run compile, install,
  replace, remove, a lazy scan of the maps that use a library), `LibraryVerify`, the manager sheet,
  its card, the install card and `LibraryImportFlow`; the title's Collections tool and drop
  routing, the New map dialog's "Manage collections..." footer link and its live rebuild, the
  missing-library dialog's third choice. Findings: a native Windows file cannot be created under
  a device name, so that rule is tested on archive entries and not on folders; GUT counts
  `push_warning` as an unexpected error; `FoliageLibrary.refresh_libraries()` must follow a
  `PaletteLibrary.clear_cache()` (it does) or a switched-off library's biomes stay in the palette
  (a test that calls only `LibraryRegistry.apply` has to clear the cache itself); the registry's
  built-in core counted EVERY palette asset as its own once another library was served (fixed:
  only ids with no library prefix).

- 2026-10-24: step S5: `core` as the nine-biome library with its 36 surfaces, 9 thumbnails and
  bindings (plantgen `LibrarySurfaces`, the sources repo `core-library`); the registry serves it
  with 0 warnings and the row, rule, asset-table, surface and binding proofs above; the catalog
  key `roles` is known to the reader; `SurfaceStore.is_library_thumbnail`; the row parity test
  loops the nine biomes through `tests/unit/library_route_compare.gd`. Findings: a core library
  needs no id translation in the scatter code (nothing reads an id's text); the first map built
  in a run drew a savanna ground 0.5 of 255 away from its later builds (seen on the package
  route, the first of the job), so a parity capture should not be the first map of its run.

- 2026-10-24: multiplayer transfer of the used library assets: `LibraryPartial`, `LibraryTransfer`,
  `LibraryTransferConsent`, `LibraryTransferChannel` (protocol 1: quote, consent, stream through
  `AssetStreamer`'s pack `_library_parts`, verify, install into `user://libraries/.received/`),
  the registry's `received` source, `MapLibraryGate.run`'s `fetch`, the host's hint for a library
  a live edit starts using. Findings: a library's `hash` covers its JSON only, so a partial
  records the source's hash (`partial.source_hash`) or maps saved on a client would claim a
  different library; `LibraryResolver` needed a rule for a received library beside an installed
  one of the same id; `AssetStreamer` sized its chunk array from the host's header with no cap
  (now capped for library parts) and kept chunks of any size (now `CHUNK_SIZE`); the file was at
  1000 lines, so the file send was split into `_send_bytes_to_peer`.
- 2026-10-24: step S4: `LibraryRegistry` scans `res://libraries` and `user://libraries` besides
  the developer override and serves every library that `LibraryResolver` can (duplicates,
  dependency ranges, cycles, disabled ones; a failing library is an entry with reasons);
  cross-library refs (`<lib>:<id>`) and `lib://` surfaces resolve through declared dependencies;
  `AssetStore` + `GlbGuard` load a library's GLBs lazily, hash-checked unless official, with the
  texture sizes read from the headers first; `PaletteOverlay.read_palette` gained its `lazy`
  form (no GLB parsed at apply); `manifest.json` `libraries` and format 3 (`MapLibraries`), the
  mismatch dialog (`MapLibraryGate`); the New map dialog grouped by library (`LibraryGroups`);
  a biome's own thumbnail served by `SurfaceStore`; reader: dependencies validated,
  `package_stem`, `sha256` and `bytes` checked. Findings: GUT counts a `push_warning` as an
  unexpected error unless the test calls `assert_engine_error` (`push_error` is
  `assert_push_error`); a typed `Array[int]` cannot be assigned a ternary of two array literals.
  `tools/compile_library_cli.gd` prints "Identifier not found: UIManager" noise under `--script`
  (no autoloads) but works: PaletteLibrary alone already does it, it is not new.
- 2026-10-25: step S12c: the `water_dist` axis (metres to the nearest water, 0 to 64, derived
  distance grid cached by the stored dressing's content) in GDScript and natively (`version()`
  `ttscatter 5 curves water`), rows byte-identical; `unsupported_axes` is now empty in
  `contract.json`, the designer's curve editor lists the axis; legacy rules and the golden
  digests unchanged. Render proof `jobs/library_s12c_water_dist.json`.
- 2026-10-24: step S12b: the native scatter library evaluates `slope_min_deg` and the slope,
  height and wet curves (`version()` `ttscatter 4 curves`), rows byte-identical to GDScript's;
  a library built before it is refused to GDScript and fails `test_scatter_native`.
- 2026-10-24: step S12a: rule fields `slope_min_deg` and `response` (slope, height, wet curves;
  water_dist validated and planned, not evaluated) through contract, reader, compiler, validator,
  `ScatterPlan` and `ScatterGenerator` (GDScript only; `ScatterNative` refuses such jobs until
  `curves`); contract stays 1; legacy rules byte-identical (golden digests unchanged).
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
