# Biome designer

A visual tool in the map builder, available to every player, for shaping how a place grows: a
biome's rules (which plants, how dense, how spaced, where on slopes, heights and shores, what they
grow near and away from) are edited on a test map and the real scatter solver, the real ground and
the real renderer redraw within a fraction of a second. The bar is the one the palette is judged
against (plants that read as a place), plus this tool's own: the designer never shows anything the
game would not place, because it runs the game's scatter on the game's ground, and an edit that is
not valid is refused by the same validators the library reader and the palette run, with their
words, beside the field it concerns. Design: plantgen's `docs/library_format_and_module_design.md`
section 4 (the mockups and the interactions); this doc holds what is built (step S8a, 2026-10-24
and 25) and the rules the code keeps. The library it edits: [library.md](library.md).

## Map

| File | Class | Role |
|------|-------|------|
| `utils/library/library_query.gd` | `LibraryQuery` | (pure) The asset query of a rule: filter clauses, shared filters, season mode, group order by FNV-1a hash, `count`, `pin`, the 64-asset cap, lock files, `why_not` |
| `utils/library/designer/biome_designer_model.gd` | `BiomeDesignerModel` | (pure) The editable draft of one biome-def: rule, query and lock commands with undo and redo, validation, compile, dirty, save |
| `utils/library/designer/designer_patch.gd` | `DesignerPatch` | (pure) Reversible edits of the draft (set, erase, insert, remove, move by path) with the inverse each returns: the undo stack holds the bytes an edit changed |
| `utils/library/designer/designer_response_edits.gd`, `designer_biome_edits.gd` | `DesignerResponseEdits`, `DesignerBiomeEdits` | (pure) Static commands over a model: response curves and `slope_min_deg`; ground surfaces, accents, paths, ground look, density scale, seasons, name |
| `utils/library/designer/response_curve.gd` | `ResponseCurve` | (pure) The curve editor's model: presets (flat, ramp up, ramp down, bell, band), add, remove, move with snapping and the contract's limits, the engine's sampling |
| `utils/library/designer/designer_validation.gd` | `DesignerValidation` | (pure) Sorts the validators' lines into per rule, per field and general |
| `utils/library/designer/designer_catalog.gd`, `designer_slots.gd`, `designer_budget.gd`, `designer_picking.gd` | `DesignerCatalog`, `DesignerSlots`, `DesignerBudget`, `DesignerPicking` | (pure) The picker's groups and filters; the slot groups, role words and the role a new rule starts as; the budget estimate; which plant is under the pointer |
| `utils/library/designer/library_writer.gd` | `LibraryWriter` | The files the designer writes: `biomes/<id>.json`, the lock file, a new user collection that depends on its source (`create_collection`, `rebase_biome`) |
| `utils/library/library_registry.gd` | `LibraryRegistry` | `designer_context(library)` (what a model is built over), `serve_draft(compiled, context)` (lays a draft over the palette without rescanning), `designer_writable(library, source)` |
| `utils/proving_ground.gd` | `ProvingGround` | The fixed 150 ft test map built from the authoring document API (`build(runtime biome id)`, `layout(doc)`) |
| `utils/scatter_regen.gd`, `utils/scatter_refresh.gd` | `ScatterRegen`, `ScatterRefresh` | `replace_biome` (which species an edit can change), `request_region(..., only)`, `cancel_all`; `ScatterRefresh.biome` (re-register, clear removed assets, request those species), `cancel`, `left`, `counts` |
| `scenes/states/authoring/designer/biome_designer_entry.gd` | `BiomeDesignerEntry` | The way in: `prepare` (open, compile, lay over the palette, build Root's request), `designable`, `new_from` (copy a core biome into a collection of the player's) |
| `scenes/states/authoring/designer/biome_designer_session.gd` | `BiomeDesignerSession` | The live half: debounce, compile, `serve_draft`, `ScatterRefresh.biome`, progress, cancel, season, selection, the budget, the timings of each edit |
| `scenes/states/authoring/designer/biome_designer_host.gd` | `BiomeDesignerHost` | Puts the designer into an `AuthoringController`: hides the tool drawer, builds the session and screen, Save, Save as, Revert, Leave, the keyboard, picking a plant by click, restoring the libraries |
| `scenes/ui/biome_designer/` | `DesignerUI` and one script per panel | `designer_ui` (layout), `designer_header`, `budget_meter`, `asset_picker` + `asset_tile`, `slot_list` + `slot_row` + `slot_chip`, `rule_inspector` + `rule_query_section` + `rule_response_section` + `curve_editor` + `rule_habit_section`, `ground_strip`, `collection_dialog`, `designer_picker` (the title's sheet), `designer_rows` (row builders) |
| `scenes/states/authoring/authoring_controller.gd` | | `designer` (the host), `leave_now()`; the designer request skips the autosave offer and never starts the autosave timer |
| `scenes/root.gd`, `autoloads/event_bus.gd`, `scenes/states/title_screen/title_screen.gd` | | `EventBus.biome_designer_requested(library, biome)`, Root's handler, the title's "Design a biome" tool |
| `tools/render_jobs/probes/designer.gd`, `jobs/designer_smoke.json`, `designer_flow.json`, `designer_perf.json` | | The render jobs and their probe |

## Model

- **A draft, never the palette.** `BiomeDesignerModel` holds a copy of the biome-def (`def`), the
  lock entries (`locks`), and the `LibraryRegistry.designer_context` it was built over (the library's
  `LibraryReader` result, its dependencies, its folder and hash). Every edit is `apply_edit(label, ops,
  merge_tag)`: `DesignerPatch` ops applied to `def`, the inverse pushed on the undo stack (200 deep).
  An edit made with `merge` (a slider being dragged) folds into the previous one when it is the same
  field within 800 ms, so a drag is one undo step. `is_dirty()` compares the hash of `def` and
  `locks` with their saved state, so undoing to the saved state is clean again.
- **Commands.** Rules: `add_rule(role, query, key)` (class defaults written explicitly, after the last
  rule of its role), `remove_rule` (near and avoid entries naming it go in the same edit),
  `duplicate_rule`, `move_rule`, `rename_rule` (relations follow), `set_field` (null erases), `set_role`
  (a size class that was the old role's default goes), `set_size_class`. Queries: `set_query`,
  `set_query_field`, `add_clause`, `add_ref`, `remove_clause`, `set_pin`. Locks: `set_locked`.
  Response: `DesignerResponseEdits.set_curve / add_point / remove_point / move_point / set_preset /
  set_slope_min`. The biome: `DesignerBiomeEdits.set_ground / set_accents / set_paths /
  set_ground_look / set_density_scale / set_seasons / set_info`.
- **Validation on every edit.** `model.validation()` runs `LibraryReader.check_biome` on the draft and
  adds the last compile's warnings (BiomeCompiler's, and `validate_palette`'s prefixed `palette:`);
  `DesignerValidation` files each line under its rule and field (`for_field`, `has_error`). A draft with
  errors is not compiled: the map keeps the last good rules, the header says how many problems, the rule's
  chip carries a mark and the inspector lists the lines. The designer never invents a message.
- **Compile on edit.** `model.compile()` is `BiomeCompiler.compile` over a read result whose biomes
  are the draft (one palette biome per season) and whose locks are the draft's. It is not threaded:
  measured 6.5 to 7.4 ms for core's temperate forest (18 rules), plus 2 ms to lay it over the palette.
- **Saving.** `save()` writes `biomes/<id>.json` (sorted keys, tab indent, whole numbers as integers,
  atomic rename) and, when rules are locked, `biomes/<id>.lock.json`; refused for a draft with errors.
  Only a user library and the developer-override folder are writable, and never `core`
  (`LibraryRegistry.designer_writable`: its biome-defs are built by plantgen, and the next export would
  overwrite a save). A read-only library opens to experiment; Save is disabled and **Save as new
  collection** creates the copy (`LibraryWriter.create_collection`): a user library with its own id and
  name (`DesignerCollectionDialog.id_for`: lower-case words, 2 to 32 characters, unique), an empty
  catalog, the biome-def with every `ref` and `pin` prefixed `<source id>:`, the source's own surfaces
  named `lib://<source id>/<name>` and `surfaces: library`, and a dependency on the source
  (`^major.minor`). The copy's plants stay in the source's folder (S4's dependency mechanism).
- **The asset query** (`LibraryQuery`, design doc 2.6.3; `ref` behaviour unchanged byte for byte, the nine
  biomes' rows still equal the package route's):
  1. Candidates are the entries of the library and of its declared dependencies (a dependency's entry
     takes the local id `<library>__<id>`, a retired id is left out), sorted by local id, so the catalog
     file's order never matters.
  2. A `ref` clause is explicit and listed order is kept; a ref that names a GROUP (not an entry) expands
     to the group's variants.
  3. Any other clause is a filter: `category`, `subtype`, `group`, `ids`, `role` (the roles the catalog
     says an asset is used as), `library`, AND-ed inside the clause, OR-ed across clauses. The query's
     `tags_all`, `tags_any`, `tags_none` and `size_class` apply to the filtered matches, and `seasons`
     (`auto`, the default) drops an asset whose `seasons` is not empty and lacks the season being compiled
     (`any` keeps all).
  4. The survivors are grouped by the catalog `group` (an entry without one is a group of its own, a
     dependency's key is `<library>:<group>`) and ordered by `order`: `hash` (the default:
     `fnv1a32("<biome id>/<rule key>|<group>")`, ties by group id), `id`, or `explicit` (the position the
     clause's `ids` list gives).
  5. `pin` names assets or groups whose groups come first, in pin order, with all their variants and
     whatever the filters say; then the first `count` other groups (`"all"` by default).
  6. The result is every variant of every taken group, by local id inside a group, at most 64 assets
     (a warning when cut). The compiler appends it after the `ref`s and de-duplicates.
  7. **Locks.** `biomes/<id>.lock.json` (format `ttsim-biome-lock`, `rules: {"<season>/<rule key>":
     {query: hash, assets: [refs]}}`) replaces steps 3 to 6 for a rule while the hash of its query
     (`LibraryQuery.query_hash`, whole floats as integers) still matches and every ref still resolves;
     otherwise it warns and resolves again. A lock changes the library's hash. The reader reads locks as
     warnings only (a bad one is ignored). `set_locked` freezes the current selection in every season;
     Save writes the lock of every locked rule from the query as it is then.
  The reader checks every clause and filter (unknown keys warn, bad values are errors); the contract
  (`LibraryContracts.QUERY_*`, exported in `contract.json` `query`) names the clause keys, orders, season
  modes and the cap.
- **The proving ground** (`ProvingGround.build(runtime biome id)`, 150 ft = 45.72 m, 183 x 183 samples,
  seed 1234, the biome painted at full density): a **slope dome** in the north-west corner (slope 0 at
  the summit to 60 degrees at the foot, `height = (-ln cos kR + ln cos kr) / k`, 6 m high, radius 9.1 m: each
  ring is one slope, so the slope response, `slope_min_deg` and the rock gathering at a scree foot show as
  rings); a **ridge** in the north-east (cos squared across, up to about 45 degrees on its flanks, 3.4 m);
  a **path band** across the middle (the biome's first path surface, 2.4 m); a **river** along the south
  with banks and the wet dressing (`StartingLandform.carve_river`; the bank and emergent habits, the wet
  curve); and a flat **meadow** between them split into three painted **density zones** (full, half, a
  fifth). Pure document work (a worker may build it); `NewMap.from_spec` builds it for a spec carrying
  `proving_ground`. `layout(doc)` names every region in metres.
- **Regeneration** (`ScatterRefresh.biome`): after `LibraryRegistry.serve_draft` lays the compile over the
  palette, `ScatterRegen.replace_biome` registers the new rules and returns the species an edit can
  change: the rules that changed or are new, and every species that READS one (`needs`: a relation's
  target, the owners of a clearance field, of its own spacing field and of its clump parent field; the
  spaced random species of one size class share one field, so they place against each other), grown to a
  fixed point, plus the readers of a removed rule. `request_region(bounds, false, -1, {biome: indices})`
  queues the whole map for exactly those; assets no rule places any more are shrunk out first
  (`drop_assets`). Partial regeneration gives the same rows as regenerating the whole biome from scratch
  (`test_scatter_refresh.gd`: a tree density edit, a ground cover edit, a slope curve plus `slope_min_deg`,
  a removed rule). A change to the ground (`ground`, `ground_look`, `density_scale`) rebuilds the open map
  from its document instead (`AuthoringController.reopen_async`, after 0.6 s), because the terrain reads
  those at build time. `cancel` drops the queue and makes jobs in flight stale; the map then shows a mix
  of old and new rules until "regenerate all".
- **Budget** (`DesignerBudget`): instances per 100 ft tile (929 m2) times the catalog's LOD0 triangles,
  scaled to a 200 ft map (four tiles) against the player's foliage primitive budget (`FoliageBudget`,
  default 8M): amber at 60 percent, red at the budget; draw calls estimated as species times occupied
  10 m cells, next to the world viewport's own draw calls and render time.

## Runtime

`EventBus.biome_designer_requested(library, biome)` (the title's picker, "Save as new collection") reaches
Root, which calls `BiomeDesignerEntry.prepare`: it opens the model, compiles it, lays the draft over the
palette (the proving ground's ground comes from the palette biome, so this happens before the map is
built) and returns the authoring request `{level, new_map: {proving_ground: runtime id}, designer:
{model}}`. Root begins authoring with it; `AuthoringController` builds the map through `NewMapBuild`,
and when it opens attaches `BiomeDesignerHost`. The host zooms the camera out to the whole proving
ground, hides the tool drawer and adds `DesignerUI` to the controller's layer. The designer session never
touches the author's maps: the autosave is not offered, recovered, discarded or started; Leave asks only
about the biome and goes back to the title without a map prompt; leaving (or the host being torn down)
puts the served libraries back (`FoliageLibrary.apply` of the current choice).

## Authoring

The screen (all of it through the theme: glass leaf over the live map, `Sheet`, `Chip`, `Caption`,
`PropertyRow`, `Foldout`; no colour, font or margin of its own):

- **Header**: the biome and its collection, an unsaved dot, the season picker (one proving ground per
  season; the scrub slider is S9), Undo, Redo, Save (the screen's one primary), Save as..., Revert, Leave;
  below, the budget meter, the regeneration progress with Cancel ("Regenerating: 12 of 36 cells", then
  "Updated in 137 ms"), and the validators' count.
- **Left**: the asset picker (search, category chips, a Tags foldout, one tile per group with its LOD0
  triangles coloured by the asset budget and a badge counting the rules that use it; Add, Pin and New rule
  for the chosen tile, double-click adds, tiles drag) over the slot list (ten slots: canopy, understory,
  shrubs, tall grass, grass, ferns, flowers, rocks, deadwood, props; every slot is shown even when empty;
  a chip is a rule with its asset count, a mark for a validator complaint and a lock icon; right-click:
  duplicate, remove, lock; "+" starts a rule of the slot's role; an asset dropped on a chip adds it, with
  Shift pins it; on a slot's header starts a rule from it; a chip dragged to another slot changes its role).
  Thumbnails come from the catalog's `thumb` when a library ships one (the core catalog has none yet: the
  tile shows its category's icon).
- **Centre**: the map. Clicking a plant selects its rule (`DesignerPicking`: each instance is a line from its
  foot to its top, the nearest within 22 px wins); Ctrl+Z, Ctrl+Shift+Z, Ctrl+Y, Ctrl+S, Delete (the selected
  rule), Escape (leave).
- **Right**: the rule inspector: name, role, class, lock, duplicate, remove, the validators' lines;
  Placement (weight, density on a log slider, spacing, slope steepest, slope gentlest, size variation, turn;
  a value that differs from the class default is marked and resets with a right-click); Mix of the class;
  Assets (the matched groups with pins, the query as removable chips, add a category/subtype filter or the
  rule's role, tags, size class, count, order, season mode, and the near misses with the one condition each
  fails); Terrain response (slope, height, wetness and distance-to-water curves in `CurveEditor`: drag a point, double-click to
  add, right-click or Delete to remove, Shift for free movement, a preset menu); Habit, clump and company
  (water habit, charred, align, clump presets with their four numbers, near and avoid relations to a rule or
  a role).
- **Ground strip**: ground, cliff, scree, water bed and shore pickers, accents and paths as chips with "+"
  (a `lib://` reference reads as the surface it names); Look... is a disabled stub (S9).
- **Entry**: the title's **Design a biome** tool opens `BiomeDesignerPicker`: your biomes (user collections)
  with Design, and the biomes of the collections that ship (core) with **Make my own copy...** (names the
  new collection, copies the biome, opens the copy) and Try it (opens read-only).

## Verification

Unit tests: `test_library_query.gd` (determinism, order independent of catalog order, golden hash order,
count, pin, cap, locks, dependencies, group refs, compiler integration, reader checks),
`test_biome_designer_model.gd` (commands and undo, validation per field, compile, dirty, save, locks, the
new collection, the pure modules touch no files), `test_designer_patch.gd`, `test_response_curve.gd`,
`test_curve_editor.gd`, `test_proving_ground.gd`, `test_scatter_refresh.gd` (partial equals full),
`test_biome_designer_entry.gd` (the picker's list, prepare, new from core, an edit and an undo, a removal and
the budget, an invalid draft, a season switch, all on real maps and a real scatter), `test_biome_designer_ui.gd`
(every panel). Render jobs (`tools/render_jobs/JOBS.md`): `designer_smoke` (the whole screen at 1600x900 and
1280x800, a click on a plant, a slope band curve before, after and undone, a ground change),
`designer_flow` (title, picker, name, copy, edit, save, find it again), `designer_perf`.

Edit to scatter, measured 2026-10-25 on this machine's shared GPU (windowed, vsync off, native generator,
debounce 0, 36 cells of 10 m on the proving ground with 14.6k instances; indicative): compile 6.5 to 7.4 ms,
lay over 2 ms, request 3 ms; the new rows on the map after
median 160 ms for a tree density edit (12 of 18 species regenerated), 86 ms for a ground cover rule, 72 ms
for a response curve on a small-class rule, 83 ms for removing a rule (88 ms undoing it); 70 ms for
regenerating all 18 rules unchanged. Against regenerating the whole biome after the same edit the partial
request saves nothing for a tree edit (158 ms both: the cost is landing the changed rows) and 14 percent for
a ground cover edit (86 against 100 ms). The target (a single-rule edit interactive, under a second) is met by
a wide margin; the debounce adds 120 ms. The regeneration is worker-threaded already (`AuthoredScatter`), so
the compile stays on the main thread.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work". What the next designer steps (S8b, S9) take
up: the A/B split view and the season scrub with per-season overrides (the compiler still ignores
`seasons[].overrides` and a rule's `seasons`); the ground look editor (the strip passes `ground_look`
through untouched); thumbnails (S9: the tiles show category icons); the manager's own entry
("Design a biome" is on the title only); hover highlight and the density-heat, slope-map and role
overlays; "Request asset" (`wanted.json`); the lock file's editing UI beyond the per-rule toggle; the
exporting a library from the designer (the manager does it). (The `water_dist` response axis landed
in S12c: `ResponseCurve.axes()` lists it, since `LibraryContracts.RESPONSE_UNSUPPORTED` is empty.)

## History

- 2026-10-25: step S8a: the query clauses of design doc 2.6.3 (compiler, reader, contract, goldens), the
  model with undo, the proving ground, partial regeneration, the panels, the title entry, three render
  jobs.
