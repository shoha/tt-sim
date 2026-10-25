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
and 25; step S9, 2026-10-25: seasons, the A/B split view, the ground look editor, the lock UI) and
the rules the code keeps. The library it edits: [library.md](library.md).

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
| `utils/library/biome_seasons.gd` | `BiomeSeasons` | (S9, pure) A biome-def as ONE season sees it (`effective`): the season's `overrides` and the rules' own `seasons` laid over it, the biome's density scale applied; the validators' lines for them (`check`); `BiomeCompiler` calls it per season |
| `utils/library/designer/designer_season_edits.gd` | `DesignerSeasonEdits` | (S9, pure) The season commands: add, remove, seed; a season's ground, ground look and density scale; a rule's change in a season and its presence; clear; the counts the panels show |
| `utils/library/designer/designer_look_edits.gd`, `designer_look_fields.gd` | `DesignerLookEdits`, `DesignerLookFields` | (S9, pure) The ground look editor's model (a field of the biome's look or of a season's override, the library's value, reset, zone colours in linear light, the words about a field) and the table of the rows it offers |
| `utils/library/designer/designer_locks.gd` | `DesignerLocks` | (S9, pure) Lock commands and words: lock a rule or the biome, `state` (locked, stale query, stale catalog), `refresh`, `summary` |
| `utils/library/designer/designer_split.gd`, `designer_reference.gd`, `designer_focus.gd` | `DesignerSplit`, `DesignerReference`, `DesignerFocus` | (S9) The A/B painting of one document (which samples belong to the draft, the cells a divider move crosses), what the draft can be compared with (the saved version compiled under its own runtime id, a sibling season, another biome), and "show only this rule" (hides scatter nodes) |
| `utils/library/designer/library_writer.gd` | `LibraryWriter` | The files the designer writes: `biomes/<id>.json`, the lock file, a new user collection that depends on its source (`create_collection`, `rebase_biome`) |
| `utils/library/library_registry.gd` | `LibraryRegistry` | `designer_context(library)` (what a model is built over), `serve_draft(compiled, context)` (lays a draft over the palette without rescanning), `designer_writable(library, source)` |
| `utils/proving_ground.gd` | `ProvingGround` | The fixed 150 ft test map built from the authoring document API (`build(runtime biome id)`, `layout(doc)`) |
| `utils/scatter_regen.gd`, `utils/scatter_refresh.gd` | `ScatterRegen`, `ScatterRefresh` | `replace_biome` (which species an edit can change), `request_region(..., only)`, `cancel_all`; `ScatterRefresh.biome` (re-register, clear removed assets, request those species), `cancel`, `left`, `counts` |
| `scenes/states/authoring/designer/biome_designer_entry.gd` | `BiomeDesignerEntry` | The way in: `prepare` (open, compile, lay over the palette, build Root's request), `designable`, `new_from` (copy a core biome into a collection of the player's) |
| `scenes/states/authoring/designer/biome_designer_session.gd` | `BiomeDesignerSession` | The live half: debounce, compile, `serve_draft`, `ScatterRefresh.biome`, progress, cancel, selection, the budget, the timings of each edit; since S9 the season on the map (`set_season`, the proving ground rebuilt when seasons differ in ground), the look re-bake (`_refresh_look`), the edit target (`edit_season`) and the focus |
| `scenes/states/authoring/designer/biome_designer_compare.gd` | `BiomeDesignerCompare` | (S9) The A/B view: `start(reference)`, `stop`, `move_divider`, the screen-to-ground mapping of the divider |
| `scenes/states/authoring/designer/biome_designer_host.gd` | `BiomeDesignerHost` | Puts the designer into an `AuthoringController`: hides the tool drawer, builds the session and screen, Save, Save as, Revert, Leave, the keyboard, picking a plant by click, restoring the libraries |
| `scenes/ui/biome_designer/` | `DesignerUI` and one script per panel | `designer_ui` (layout), `designer_header`, `budget_meter`, `asset_picker` + `asset_tile`, `slot_list` + `slot_row` + `slot_chip`, `rule_inspector` + `rule_query_section` + `rule_response_section` + `curve_editor` + `rule_habit_section`, `ground_strip`, `collection_dialog`, `designer_picker` (the title's sheet), `designer_rows` (row builders); S9: `rule_season_section`, `look_editor`, `density_popup`, `compare_overlay`, `picker_hint` |
| `scenes/states/authoring/authoring_controller.gd` | | `designer` (the host), `leave_now()`; the designer request skips the autosave offer and never starts the autosave timer |
| `scenes/root.gd`, `autoloads/event_bus.gd`, `scenes/states/title_screen/title_screen.gd` | | `EventBus.biome_designer_requested(library, biome)`, Root's handler, the title's "Design a biome" tool |
| `tools/render_jobs/probes/designer.gd`, `jobs/designer_smoke.json`, `designer_flow.json`, `designer_perf.json` | | The render jobs and their probe |
| `tools/render_jobs/probes/designer_s9.gd`, `jobs/designer_s9_ab.json`, `designer_s9_seasons.json`, `designer_s9_look.json`, `designer_s9_misc.json` | | (S9) The A/B, season, look editor, lock, show-only and picker-hint jobs and their probe |
| `scenes/ui/library_manager/library_detail.gd`, `library_manager.gd`, `scenes/ui/biome_designer/designer_picker.gd` | | (S9) The manager card's "New biome from this..." opens `BiomeDesignerPicker.show_over(parent, library_id)`, the title's sheet filtered to that library, with the same copy flow |

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
  a removed rule). A change to the season's ground (surfaces, accents, paths) rebuilds the open map from
  its document instead (`AuthoringController.reopen_async`, after 0.6 s), because the terrain reads those
  at build time; a change to the ground LOOK does not (see "Ground look" below). `cancel` drops the queue
  and makes jobs in flight stale; the map then shows a mix of old and new rules until "regenerate all".
- **Budget** (`DesignerBudget`): instances per 100 ft tile (929 m2) times the catalog's LOD0 triangles,
  scaled to a 200 ft map (four tiles) against the player's foliage primitive budget (`FoliageBudget`,
  default 8M): amber at 60 percent, red at the budget; draw calls estimated as species times occupied
  10 m cells, next to the world viewport's own draw calls and render time. In the A/B view only the
  draft's plants count, over the share of the map they stand on, so the numbers stay per 100 ft tile.
- **Seasons (S9; design doc 2.6.5).** A season is a palette biome of its own (`<biome>_<season>_s<seed>`);
  the compiler used to expand them without overrides. `BiomeSeasons.effective(def, season)` now makes the
  def ONE season sees before `BiomeCompiler` reads it, so the compiler has no season code of its own and a
  def with no overrides, no rule `seasons` and no `density_scale` is returned as it is (byte-identical
  palette, pinned by `test_biome_seasons` and the frozen goldens). Two places hold an override, applied in
  this order: the season's `overrides` (`ground` field by field with null erasing a field, `ground_look`
  deep-merged over the biome's, `density_scale` per class merged over the biome's, `rules`: {rule key:
  override}) and the rule's own `seasons` (`{"only": [season ids]}`, and `{"<season>": override}`). A rule
  override sets any of `LibraryContracts.SEASON_RULE_FIELDS` (the numbers, `response`, `habit`, `align`,
  `keep_colour`; `query` merged key by key over the rule's query, its `match` replacing the list; `enabled`
  false removes the rule from the season); `density_factor` is RELATIVE there (it multiplies the density
  the rule compiles to, an explicit `density_per_m2` or the class default times the rule's own factor) and 0
  removes the rule. The biome's `density_scale` (the compiler ignored it before S9) multiplies every rule of
  its class the same way. The reader checks all of it (`BiomeSeasons.check`: a malformed override is an
  error in the rule's words, an unknown key, rule or season a warning; the "overrides are not applied"
  warning is gone) and `contract.json` carries `seasons` (`max`, `override_keys`, `rule_fields`; plantgen's
  vendored copy tolerates extra keys). Queries and locks read the season's rule (`BiomeSeasons.rule_in`),
  so a season that changes a query has its own lock hash. The `New map` dialog needs nothing: a season's
  biome is a biome, so a summer and a winter with different looks are two tiles as before.
  Designer side: `DesignerSeasonEdits` (add a season with the next seed, remove one with every override
  that named it, seed, a season's ground field, look and density scale, a rule's change in a season, its
  presence, clear, the counts). The header's dropdown names each season with how many changes it has, a
  scrub slider walks them, the Seasons menu adds, removes and clears. `session.set_season` lays the
  season's biome on the document and regenerates the map for it; when the two seasons differ in their
  ground (`_ground_differs`: surfaces, accents, paths) the proving ground is built again for the new
  biome (`ProvingGround.build` and `reopen_async(replacement)`), else the same map is kept. The ground
  strip's "Applies to" (`session.edit_season`, also followed by the look editor and the density popup)
  points every ground edit at the biome or at one season; a picker left at "As biome" has no override.
- **A/B (S9; design doc 4.4).** One proving ground, two biomes: `DesignerSplit` paints the draft in biome
  slot 1 on one side of a divider and the reference in slot 2 on the other, so the real scatter generates
  both, the ground draws each biome's own surfaces, accents and look (each looked biome takes a
  `GroundLookBake` slot, at most four per map), and the camera, seed and terrain are the same by
  construction, with no second map or viewport (so the extra memory is one biome's plants; the assets of a
  reference compiled from the saved version are a second asset id over the same GLB). The divider is a
  ground line perpendicular to the camera's right vector: the game camera is fixed and orthographic, so it
  is a vertical line on the screen, mapped by `BiomeDesignerCompare.viewport_x` / `t_at_viewport_x`
  through the camera and `DesignerCompareOverlay` draws and drags it. A move repaints only the samples the
  divider crossed and asks `request_region` (live, nearest first) for only the 10 m cells it crossed
  (`DesignerSplit.cells_crossed`), throttled to one request per 0.12 s while dragging, then once on release.
  The reference (`DesignerReference.options`) is the SAVED version of the biome (the draft as last saved,
  compiled under a runtime id of its own, seed 9000 up, so both stand in the palette at once), another
  SEASON of the draft (it follows the draft's edits: both are regenerated) or ANOTHER BIOME of any served
  library. Switching the draft's season keeps the reference; choosing the reference as the draft's season
  turns the view off. Picking a plant on the reference's side selects nothing.
- **Ground look (S9).** `DesignerLookFields` is the table of the editor's rows (the contract's groups: zones
  with their colours, painted light, brush, strokes, grass tufts, grass masses, rims, accent patches; each
  slider inside `GroundLook.RANGES`, pinned by a test) and `DesignerLookEdits` reads and writes a field of the
  biome's look or of one season's override, with the library's value (the saved def's) for the mark and the
  per-field reset, zone colours kept in linear light as the contract says and shown in sRGB, and the
  consumer's own words (`GroundLook.validate`'s warnings and a per-field range or shape check). An edit
  reaches the map in place: the session lays the draft over the palette and
  `AuthoredTerrain.refresh_ground_look()` bakes `GroundLookBake` again (one GPU pass per looked biome, the
  grass binds the new tuft and mass colours), with no map rebuild. When the zone SHAPES the scatter reads
  (`GroundZones.record`: patch scales, cover, warp, strokes, accent shape) moved too, the plants are
  regenerated for that biome (the grass masses place against the zones), which colours and light do not
  need. The editor says the game draws the ground look of at most four biomes per map
  (`GroundLookUniforms.SLOTS`; a fifth draws the plain ground, S0 finding) and how many this proving ground
  uses (one, two in the A/B view).
- **Locks (S9).** `DesignerLocks`: a lock freezes which assets a rule's query picks in each season it grows
  in (the refs and the hash of the query as that season sees it); `state` says `unlocked`, `locked`,
  `stale_query` (the query changed after the lock: the compiler ignores it and warns) or `stale_catalog`
  (the catalogs would now give other plants than the lock holds), with the refs held and now; `set_all`
  locks or releases the whole biome in one step; `refresh` takes a stale lock again; `summary` counts them.
  Save writes `biomes/<id>.lock.json` through `LibraryWriter` for the locks of rules and seasons that still
  exist, and removes the file when none is left. A rule whose query only names assets has nothing to freeze
  (the lock holds no picked asset and the words say so).
- **Show only this rule (S9).** `DesignerFocus` hides the scatter nodes of every asset the chosen rule does
  not place (`visible` of the settled and growing MultiMesh nodes; no row, cell or picking changes) and the
  session applies it again after each regeneration. It stands in for the hover outline of design doc 4.3,
  which needs the scatter's shaders: it follows the selection, and clearing it shows everything.

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

- **Header**: the biome and its collection, an unsaved dot, the season dropdown (each season with its
  number of changes) with the scrub slider and the **Seasons** menu (add a season, remove the one on the map,
  clear its changes), the **A/B** menu (off, the saved version, the other seasons, Another biome >), Undo,
  Redo, Save (the screen's one primary), Save as..., Revert, Leave; below, the budget meter, the regeneration
  progress with Cancel ("Regenerating: 12 of 36 cells", then "Updated in 137 ms"), and the validators' count.
  With A/B on, a vertical divider with a grip crosses the map ("Draft" over its left, the reference's name
  over its right); drag it, the plants and the ground follow.
- **Left**: the asset picker (search, category chips, a Tags foldout, one tile per group with its LOD0
  triangles coloured by the asset budget and a badge counting the rules that use it; Add, Pin and New rule
  for the chosen tile, double-click adds, tiles drag) over the slot list (ten slots: canopy, understory,
  shrubs, tall grass, grass, ferns, flowers, rocks, deadwood, props; every slot is shown even when empty;
  a chip is a rule with its asset count, a mark for a validator complaint and a lock icon; right-click:
  duplicate, remove, lock; "+" starts a rule of the slot's role; an asset dropped on a chip adds it, with
  Shift pins it; on a slot's header starts a rule from it; a chip dragged to another slot changes its role).
  The slots' header counts the locked rules (and the stale ones) with **Lock all** and **Unlock all**; a
  locked chip carries the floppy mark, a stale lock the warning triangle. Thumbnails come from the
  catalog's `thumb` when a library ships one. When the filters match nothing the tiles give way to the
  picker's empty state (`DesignerPickerHint`): what to relax (each picked tag, category, the search, the
  slot's role, with how many groups it would then show; `DesignerCatalog.relax`) and **Request asset**,
  which copies a line describing the missing plant to the clipboard (`DesignerCatalog.request_text`; the
  game has no network to send it with, so a `wanted.json` round trip is for plantgen's side).
- **Centre**: the map. Clicking a plant selects its rule (`DesignerPicking`: each instance is a line from its
  foot to its top, the nearest within 22 px wins); Ctrl+Z, Ctrl+Shift+Z, Ctrl+Y, Ctrl+S, Delete (the selected
  rule), Escape (leave).
- **Right**: the rule inspector: name, role, class, lock, **Show only this** (a toggle that follows the
  selection), duplicate, remove, the words about the rule's lock (with **Lock again** when it is stale),
  the validators' lines;
  Placement (weight, density on a log slider, spacing, slope steepest, slope gentlest, size variation, turn;
  a value that differs from the class default is marked and resets with a right-click); Mix of the class;
  Assets (the matched groups with pins, the query as removable chips, add a category/subtype filter or the
  rule's role, tags, size class, count, order, season mode, and the near misses with the one condition each
  fails); Terrain response (slope, height, wetness and distance-to-water curves in `CurveEditor`: drag a point, double-click to
  add, right-click or Delete to remove, Shift for free movement, a preset menu); Habit, clump and company
  (water habit, charred, align, clump presets with their four numbers, near and avoid relations to a rule or
  a role); Seasons (`DesignerSeasonSection`: a check per season for where the rule grows, then for the
  season on the map its density multiplier, weight, spacing and steepest slope, marked when they differ from
  the rule's own, right-click to take one away, and a button to clear the rule's changes there).
- **Ground strip**: "Applies to" (every season, or one season only: then the pickers show that season and
  write its override), ground, cliff, scree, water bed and shore pickers, accents and paths as chips with "+"
  (a `lib://` reference reads as the surface it names; a season's chips replace the biome's, "same as every
  season" takes the override away), **Density...** (`DesignerDensityPopup`: a multiplier for each size
  class, for the biome or the season) and **Look...**, which puts the ground look editor
  (`DesignerLookEditor`) in the inspector's place until Done: a foldout per contract group, a slider per
  number, three for a triple, a colour picker for a colour, the zone colours (three or four), a mark on a
  field that differs from the library's with a right-click reset, Reset all, the validators' lines about the
  look, the four-biomes note, and "Add a ground look" for a biome that has none. The strip scrolls
  (`GROUND_HEIGHT`) when the window is too small for its rows, so it never pushes the panels out.
- **Entry**: the title's **Design a biome** tool opens `BiomeDesignerPicker`: your biomes (user collections)
  with Design, and the biomes of the collections that ship (core) with **Make my own copy...** (names the
  new collection, copies the biome, opens the copy) and Try it (opens read-only). The collections manager's
  card (S9) has **New biome from this...** for a library served from a folder with biomes (not one a host
  sent): the same sheet listing that library's biomes, each with Design (a library of yours) or Try it, and
  the copy button.

## Verification

Unit tests: `test_library_query.gd` (determinism, order independent of catalog order, golden hash order,
count, pin, cap, locks, dependencies, group refs, compiler integration, reader checks),
`test_biome_designer_model.gd` (commands and undo, validation per field, compile, dirty, save, locks, the
new collection, the pure modules touch no files), `test_designer_patch.gd`, `test_response_curve.gd`,
`test_curve_editor.gd`, `test_proving_ground.gd`, `test_scatter_refresh.gd` (partial equals full),
`test_biome_designer_entry.gd` (the picker's list, prepare, new from core, an edit and an undo, a removal and
the budget, an invalid draft, a season switch, all on real maps and a real scatter), `test_biome_designer_ui.gd`
(every panel). S9: `test_biome_seasons.gd` (the season compile: no overrides is byte-identical, a season
compiles to its own runtime biome with its ground, look, density scale, rule fields and presence, the
reader's words), `test_biome_designer_seasons.gd` (the season commands with undo, summary, clear, queries
and locks per season), `test_designer_look_edits.gd` (every editor row sits inside the contract's range, a
field of the biome's look or a season's, reset to the library's, zone colours in linear light, the words
about a field), `test_designer_split.gd` (the A/B painting band by band equals painting from scratch, the
cells a move crosses, the saved version compiled under its own id), `test_designer_locks.gd` (states, stale
lock, Lock all, the lock file Save writes), `test_biome_designer_ab.gd` (the view on a real map and scatter:
both biomes grow on their own sides, the divider moves plants, off gives the map back, edits keep
regenerating the draft's side, the saved version beside an edited draft, the budget, a season's overrides
reaching the plants, the focus), `test_biome_designer_s9_ui.gd` (every S9 panel). Render jobs
(`tools/render_jobs/JOBS.md`): `designer_smoke` (the whole screen at 1600x900 and
1280x800, a click on a plant, a slope band curve before, after and undone, a ground change),
`designer_flow` (title, picker, name, copy, edit, save, find it again), `designer_perf`; S9:
`designer_s9_ab`, `designer_s9_seasons`, `designer_s9_look`, `designer_s9_misc`, `designer_s9_perf`.

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

S9 latencies (same conditions, `designer_s9_perf`; to the new rows on the map): a tree edit with three
seasons 184 ms (the three seasons compile in 16.6 ms; the edit regenerates only the season on the map); a
look colour or light edit 64 ms (compile 7, lay over 2, the CPU side of the bake 8.7 ms, then one GPU pass
that the next frame shows; no plants regenerated), a zone-shape edit 120 ms (the plants that read the
zones are regenerated too); A/B on 554 ms the first time (the reference's species load) and 266 ms after,
off 227 ms; one divider move 200 to 360 ms for 15 to 30 cells (the nearest first, so the part under the
pointer shows in the first frames); a season switch 390 to 560 ms (the whole map regenerates for the new
biome; 470 ms when the ground differs and the proving ground is built again). All under a second.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work". What is left after S9: the density-heat,
slope-map and role overlays on the map; a true hover outline of a rule's plants (the scatter's shaders would
need an outline pass; "Show only this" stands in); a `wanted.json` written into the draft library (Request
asset copies a line to the clipboard); exporting a library from the designer (the manager does it); the A/B
view against a user's own open map ("judge in my map"); per-season ground look COLOUR overrides carry the
whole zone colour list (a season that changes one colour stores all of them); the A/B view's saved-version
reference registers a second asset id over the same GLB (a second mesh parse per species while it is on);
the ground strip scrolls at 1280 wide, where its second row (the paths) is below the fold. (The `water_dist` response axis landed in S12c:
`ResponseCurve.axes()` lists it, since `LibraryContracts.RESPONSE_UNSUPPORTED` is empty.)

## History

- 2026-10-25: step S9: per-season overrides (`BiomeSeasons`, the reader's checks, the contract's `seasons`,
  `density_scale` applied), the season scrub and menus, the A/B split view (one map, two biomes, a
  draggable divider), the ground look editor with an in-place re-bake, the lock UI (states, Lock all,
  Lock again), the manager's "New biome from this...", "Show only this", the picker's empty state with
  "Request asset", the ground strip's "Applies to", Density... and its scroll, five render jobs.
- 2026-10-25: step S8a: the query clauses of design doc 2.6.3 (compiler, reader, contract, goldens), the
  model with undo, the proving ground, partial regeneration, the panels, the title entry, three render
  jobs.
