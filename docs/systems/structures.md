# Structures

Status: data layer (card S1), build (card S2) and the library kind (card S3), 2026-10-28, topic
`structures`. A structure is a building recorded as a library recipe plus the author's inputs; every
peer rebuilds it, as walls, crossings and avatar tokens are. S1 added the record, the
`structures.json` entry of `map.ttmap`, the editor's data calls, the live edit and the fingerprint key.
S2 builds the record into the game: geometry, the nodes and their collision, the worker prep, scatter
clearance, a simple material split and the plan rules. S3 makes recipes a library kind (a
`structures/` folder, index, registry, partial bundles, Verify, tiles; core ships five), swaps the
temporary resolver for the registry and shows a placeholder plot where a recipe is missing. S4 adds
the Building tool (palette strip, ghost lot, click and drag, turn, re-roll, removal, live edit: "The
tool" below); the cards that add handles and variants grow this page. The design is the
gitignored `docs/plans/2026-10-28-structures/design.md`; the contract with procgen and structgen is
`ASSET_PIPELINE.md` section 12.

## Data

`Structure` (`resources/structure.gd`) is one structure in `MapDocument.structures` (at most
`MAX_STRUCTURES` = 128):

| Field | Meaning |
|-------|---------|
| `id` | 1..255, stable, unique in the document |
| `recipe` | `<library id>:<structure id>`, the cross-library reference grammar (`LibraryIds`: library `[a-z][a-z0-9_-]{1,31}`, structure `[a-z][a-z0-9_]*` without `__`); at most 100 characters. Whether the recipe exists is the registry's question at build time |
| `footprint` | the closed plan polygon in map XZ metres, 3 to 24 points, `PackedVector2Array` (float32); edge 0 (point 0 to point 1) is the front and carries the door |
| `seed_value` | 0..1e9, stored, never derived from an engine hash |
| `params` | only the values that differ from the recipe's interface defaults: at most 16 entries, name `[a-z][a-z0-9_]*` (32 characters), a bool or a finite number within 1e6, rounded to 0.01 |
| `style` | palette biome id whose rock tints the walls, or "" (as `Wall.style`) |

There is no transform and no baked mesh. Position and rotation are the points, and height is read
from the document's ground when built (the Build card), exactly as a wall's is.

## The map entry

`MapStructureIO` (`utils/map_structure_io.gd`) owns `structures.json`, in the way `MapWallIO` owns
`walls.json`; `MapDocumentIO` owns the archive, the 1 MB entry cap and the warning log:

```
{"version": 1, "structures": [
  {"footprint": [[-3.0, -2.0], [3.0, -2.0], [3.0, 2.0], [-3.0, 2.0]],
   "id": 1, "params": {"floors": 2.0, "height": 2.6}, "recipe": "core:cottage",
   "seed": 482113907, "style": ""}]}
```

- **Reading is untrusted.** A structure is skipped with a warning when: its id is outside 1..255 or
  repeated; the recipe is not a well formed `<library>:<structure>`; the footprint has fewer than 3
  or more than 24 points (checked on the raw list before any point is built), a point NaN, Inf or
  off the map, or a bounding box wider than `MAX_SPAN_M` (64 m); the plan rules refuse it (below);
  the seed is not a whole number in 0..1e9; params are not an object of at most 16 well named
  numbers and bools; the style is not a short string. Lists past 128 are cut with one warning.
  `structure_problem()` is the one rule set, shared by the reader, the writer and the editor.
- **The writer refuses** a document breaking any rule (`MapDocumentIO.write` fails, as for walls).
  A document with no structure writes no entry; an older build ignores the entry (and drops the
  buildings on its next save, accepted as for walls).
- **Byte-identical re-save.** The text is written with sorted keys and the default float
  precision. Footprint points are float32, which print with 14 digits and parse back to the same
  float32 (measured 2026-10-28 in the design probe: 0 mismatches in 20000 points, while float64
  values mismatched 1838 times), so they are never rounded by the I/O. Numeric params are float64
  and are rounded to 0.01 on every read and write. `test_map_document_structures.gd` checks the
  entry's bytes across a save and load, and 40 random plans (snapped and unsnapped).
- **The plan rules** are procgen's `ProcgenPlan.problems()` (pin `0ff1712`), the rules structgen
  edits by: at least 3 and at most 24 points, no side under 0.5 m, no two sides that do not meet
  closer than 0.3 m or crossing, no corner under 15 degrees, wound the way the presets are (signed
  area positive, x right and z down) and at least 2 m2. `MapStructureIO._plan_problem()` returns the
  first problem, after the record's own caps (count, finite, on the map, span), so a bow tie, a
  sliver, a 0.3 m wall, a plan wound the wrong way or a 1 m square are skipped with a warning by the
  reader and refused by the writer and the editor.

`MapLibraries.record_for` and `LibraryRegistry.assets_used_by` do not count structure refs yet
(the library card does that); a map with a non-core recipe will then list its library.

## Editor and history

`StructureEditor` (`scenes/states/authoring/structure_editor.gd`, `AuthoringEditor.structures`):
`list()`, `get_structure()`, `add()` (a new id is taken from `MapDocument.next_structure_id()`; an
existing id replaces; -1 with `last_refusal` `full` or `invalid`), `remove()` and `apply_list()`.
Every change is one history entry holding the whole list before and after. `apply_list()` is the
one method the history's undo and redo and a live edit call: it sets the document's list, brings the
map's `AuthoredStructures` up to it (below) and asks the scatter to regrow over the footprints that
changed. `follow(area)` and `restore(record)` make the nodes follow a sculpt or water edit of the
ground under them: `HeightEditor` and `WaterEditor` record them in their history entries beside the
walls' and crossings', and `LiveEditCodec` and `LiveEditReader` carry the record to peers.

## Recipes

`StructureRecipes` (`utils/structure_recipes.gd`) turns a reference into a recipe document. Since S3
the recipes are a library kind ([library.md](library.md) "Structures"): `LibraryStructureStore`
(filled by `LibraryRegistry.apply`) holds each served library's structures by `<library>:<id>`, and
`StructureRecipes` asks it. The `core` library ships the starter set as data (`libraries/core/
structures/`, built from procgen's recipes by `tools/export_core_structures.gd`): `core:stone_house`
(the building recipe, gable roof, stone), `core:cottage` (timber), `core:cottage_chimneyed`,
`core:townhouse` and `core:townhouse_trimmed`, each with an index entry (name, family and variant,
default and limit sizes, exposed parameters, tile) and a line in `pins.txt`. Lookup order: the test
`resolver` (a `Callable(ref) -> {"text": recipe JSON}`), the store, then, only with
`procgen_fallback` on (off in the game), procgen's committed `recipes/` folder. Parsing refuses a
text over the recipe caps (`LibraryStructures.recipe_problem`), then the digest (sha256 of the
text), the interface clamp (`clamp_params`: a name the recipe does not declare is dropped, a number
is clamped to its min and max) and the thread safety live here. Every call parses a fresh
document, so an evaluation never shares one; the store is replaced whole under a mutex, so a
worker reads a consistent table while libraries are re-served. `ensure_served()` (main thread) makes
sure the libraries are served first.

A reference nobody serves (a transfer still running, a removed library) or a recipe that fails to
build gives a **placeholder plot**: a pale slab 15 cm above the ground on the footprint, following
the ground, no collision, `top` NONE, parts `placeholder` true and `problem` saying why. The recipe
digest is in the key, so the plot becomes the building when the recipe arrives.

## Geometry

`StructureGeometry` (`utils/structure_geometry.gd`) is pure and safe on a worker: record, recipe and
the document's ground go into `evaluate_structure(doc, inputs, true)` and come back as parts in the
map frame. The footprint is the closed plan guide (`ProcgenPlan.to_guide`), the stored seed is the
evaluation seed (no engine hash), the params are the record's clamped, plus `textured` = 1 where
the recipe declares it (`StructureGeometry.textured`, on, as for walls). Parts per structure:

- `meshes`: one entry per (material role, surface kind): `kind` (`masonry`, `stone`, `wood`, `glass`),
  `role`, `arrays` (with tangents, as `WallGeometry`) and `tags`, the per-vertex provenance ids;
  `tag_table` holds the paths (node id, then slot path). The tags are kept, not dropped as walls drop
  them; `AuthoredStructures.provenance_at()` answers which node made a triangle.
- `collision` faces and `top` (the recipe's walkable surface: a closed hull plus a solid roof),
  `openings` (doors and windows as oriented boxes) and `layout` (the final `ProcgenBuildingLayout`:
  volumes, openings with slot provenance). Nothing reads layout or openings in play yet (no vision or
  navigation exists); they are kept so a later rule can treat a building as a blocker with doors as its
  portals.
- `problem` (why nothing was built: invalid record, unknown recipe, a recipe error, over budget) and
  `warning` (over the soft budget). A refused structure has empty parts and `top` -INF, not a crash.

**Roles** (`StructureLook`): the node type that made a vertex gives its role: `building_walls`,
`building_timber`, `facade` wall; `roof_gable`, `roof_hip`, `roof_flat` roof; `facade_trim`, `cornice`,
`quoins` trim; `roof_furniture` chimney. A roof is its own material only where its surface is planks
(`wood`): a gable's end triangles are masonry and a flat roof's coping is stone, and they stay wall.
A fifth role, `opening`, is procgen's `glazing` node (surface kind `glass`, tags
`<glazing id>/<opening path>/pane|leaf`, flat vertex colours): the recipes build hollow walls, and
the core recipes are exported with glazing on (`tools/export_core_structures.gd`), so every window
has a pane and every door a leaf; street rows are built with `glazing` 1 too (`AuthoredWalls` draws
their `glass` kind unshaded). tt-sim draws no quads of its own. Roles split a surface by triangle (the role of
its first vertex) and keep vertex order, so quad tangents stay valid.

**Budgets** (design.md): a structure over `SOFT_TRIANGLES` 12000 builds and warns, over
`HARD_TRIANGLES` 25000 is refused with a reason (`parts.problem`; `AuthoredStructures` logs it once and
keeps it in `notes`). Measured 2026-10-28 (headless, one thread): the starter set at 6 x 4 m is 316,
1112, 1520, 880 and 2514 triangles (stone house, cottage, chimneyed cottage, townhouse, trimmed
townhouse; textured stone, panes included); a 40 x 20 m trimmed townhouse in modelled stone is 48k
triangles (refused, 200 ms to find out). The per-map 150k budget is not enforced.

**Key and clearance.** `key_of()` hashes the recipe digest, reference, footprint, params (as sorted
JSON), seed, style, `textured`, the mesh format version and the ground sampled along the outline and
across the inside (every 0.5 m, a coarser grid past 2048 samples). A single sample bump between
the grid points can miss (the grid is 0.5 m, the document's samples 0.25 m); a sculpt covers many.
`clearance_crossings()` turns every footprint into strips (a Crossing is a width and two anchors, the
shape both scatter paths already clear by): rows along the front edge every 0.75 m across the plan,
cut where the polygon is, so an L plan leaves its notch open, shortened so the clearing reaches about
0.35 m past the walls. `ScatterGround.sampler` and `ScatterNative` add them to the walls' and
crossings'; `ScatterRegen.snapshot` and `RockKeep.snapshot` carry `structures` to their workers (the
first draft of this card forgot, and the plants grew through the houses: measured 86 rows inside
footprints, then 0 with the copy).

## Nodes

`AuthoredStructures` (`scenes/terrain/authored_structures.gd`), a child of the map root like
`AuthoredWalls`, identity transform. Per structure a `Structure_<id>` node holds a MeshInstance3D per
mesh (`wall_masonry`, `roof_wood`, `trim_stone`, `chimney_stone`, `opening_glass`, ...) and a
`Collision` StaticBody3D (terrain layer, meta `tt_structure` = id) built from the recipe's faces, so
a token lands on a roof or a wall top as on the ground; `exclude_of(root)` lists the bodies for
the ground tools (`BrushTool`, the dressing sampler and `GameMap`'s drop height skip or include them as
for walls).

- **Load.** `AuthoredLoadPrep` has the part `STRUCTURES` (`StructureGeometry.build`), one worker task;
  `MapSourceLoader._create_authored_root_async` makes the nodes in a frame after the walls
  (`add_authored_structures`). `AuthoredStructures.create()` seeds the key and the cache from the
  worker's parts.
- **Edit.** `refresh(doc)` compares each key with the key its node was built from. A changed
  structure is built on a `WorkerThreadPool` task from a copy of the record and a ground snapshot
  (`ground_snapshot`: size, spacing and the shared height array, so a sculpt cannot race it); the old
  node stays until the new one is ready (`_process` lands it, `built` is emitted; `flush()` waits for
  all, for tests and tools). Newest edit wins: a structure edited again while its build runs has the
  older job forgotten (its task finishes and is dropped), and an edit back to what is on show cancels
  the build. Built parts are kept by key (48 of them), so an undo or redo makes its node at once.
  `refresh(doc, false)` builds on the calling thread.
- **Materials.** The wall materials of `AuthoredWalls` (rock by style, the masonry tile tinted by the
  rock's mean colour, planks by climate) with `StructureLook.ROLE_TINTS` over them: a warm terracotta
  roof over the planks, a lifted light trim, chimney stone as it is. Panes are unshaded flat
  vertex colours (a shaded pane went black on the side away from the sun). This is the simplest split;
  card S6 owns the painterly role table and a roof tile surface.
- **Fingerprint.** `MapFingerprint`'s `structures` key now has its `node <name> <verts> <aabb>` lines
  (the part S1 left a seam for).

## Live edit and fingerprint

- The live-edit kind `"structures"` (`LiveEditCodec`, `LiveEditReader`) carries
  `[structure JSON forms, area]`, the whole list, as walls do; the reader runs
  `MapStructureIO.parse_list`, so a hostile peer's list is refused with the same rules as a file.
  It takes no direction: an undo is the same op with the list before. 128 structures are at most
  about 128 KB of JSON-shaped values, sent once per committed edit, never per drag frame.
- `MapFingerprint` has the key `structures`: `record <id> <recipe> <sha prefix of the record's
  JSON>` per document record (moves with any change of footprint, seed, param, style or recipe),
  plus `node <name> <verts> <aabb>` per child of `AuthoredStructures` (the nodes are built, so
  both parts run; a build still in flight has no node line yet). Design note: the design named only
  the node part; the record part is what makes the key useful before a build lands.

## The tool

Card S4 (2026-10-28): the **Building tool** (`StructureTool`, rail id `structure`, icon `home`),
registered after the Wall tool in map building and, as a live brush, in the GM's Events pane. It
replaces the Wall tool's Building tile (`Wall.Kind.BUILDING` and its code stay until card S8). Like
the other tools it is a descriptor (`scenes/states/authoring/tools/structure_tool.gd`), a brush
mode (`structure_brush.gd`), a pane (`structure_tool_pane.gd`) and a test; its placement rules are
pure (`utils/structure_placement.gd`).

- **Palette strip.** `StructureToolPane`: a tile per structure the served libraries offer
  (`LibraryStructureStore.structures()`), grouped by family under the family's name, each tile the
  library's rendered picture (`StructureThumbnail`, a paper square when there is none) and the
  structure's name, the first preselected, and a Mix afresh button. A tile sets the brush's `ref` and
  picks the tool again (as the Wall tool's tiles do, so a brush put down with RMB comes back).
- **Ghost lot.** With a structure picked, the pointer carries a ghost: the footprint on the ground
  (faintly filled), the recipe's default height as a ring over it, the door bar and tick on the
  front edge, a readout ("Cottage  20 x 13 ft", in the level's units). Its size is the index
  entry's `default_size_m` times a scale the bracket keys step (0.6 to 2.5, a notch of 1.1),
  clamped to the entry's `min_side_m`, `max_side_m` and `max_area_m2`. At turn 0 the front faces +Z
  (the home camera); Q and E turn it 15 degrees (Shift a quarter turn).
- **Legal ground, eased.** `StructurePlacement.lot_problem`: no sampled point under water
  (`WaterGeometry.is_wet_at`), no sampled slope over 0.445 (the 24 degree bank procgen's mesh check
  was run on), inside the map, 0.4 m clear of every structure standing. The ghost does not turn red
  over bad ground: `nearest_legal` looks in rings of 1 m out to 7 m for the closest legal spot on
  the 0.5 m grid and the ghost slides there (an exponential ease, 22 per second, straight there the
  first frame). Only when nothing within reach is legal does it turn warm and say why beside the
  cursor, and a release then lays nothing and toasts the same words. The search is a function of the
  snapped centre alone, so the ghost and the click after it agree.
- **Click and drag.** A press and release moving less than 0.75 m lays the ghost's lot. A drag is the
  corner-to-corner gesture: the press is one corner, the pointer the opposite, the rectangle turned
  by the current turn; its size clamps to the entry's range and the ghost shows the clamp (a drag
  held past the largest size grows no further), and the whole rectangle settles on the nearest legal
  spot. The release lays it as one history entry (`StructureEditor.add`; the seed shown is the seed
  laid, then the brush takes the next in a fixed series, so each lot differs). The new record's
  style is the biome under it. RMB or Escape during a drag drops it.
- **Remove, re-roll.** RMB or Delete over a structure removes it (the brush `picks`; the footprint
  under the pointer is outlined while hovering), Ctrl and a click does too; R re-rolls the structure
  under the pointer (`StructureEditor.reroll`, one history entry, the next seed of the series) or,
  over bare ground, draws the next lot afresh. Tooltips, the F1 help rows and the pane's hint say
  these keys.
- **Peers and play.** Every edit is one history entry holding the list before and after, so the
  existing `structures` live edit carries it (`LiveEditCodec.op_of`, tested end to end from a
  gesture). The Events pane lists the brush like the Wall tool's: the tiles as `structure_pane`
  (`EventsPane.structure_selected`, `structure_reroll_requested`), the hint bar rows in
  `PlayEvents.hints_for`.
- **Not in this card.** Select by click, corner and edge handles, the turn ring, the door edge,
  variant tiles and the floors stepper are card S5; non-rectangular plans (`plans` in the entry)
  are not offered yet; the rise animation of a laid building and the retirement of the Building
  kind and its pane fields are card S8 and a look card.

## Not yet

- Handles, variants, a floors stepper (card S5); retiring `Wall.Kind.BUILDING` (card S8).
- The tiles under `thumbnails/structures/` are from before the glazing change (card S5 re-renders
  them with the `structure_thumbs` job).
- The painterly roles (a roof tile texture, slate, window glow), the look pass on three biomes, the
  frame cost of a 20-structure town (card S6; PERFORMANCE.md has no structure line until it is
  measured with the pinned procedure).
- Cross-platform digests (the pins were taken on Windows only; card S9).

## Tests and render job

`tests/unit/test_map_document_structures.gd` (the record and the map entry) and
`tests/unit/test_structure_build.gd` (recipes, geometry, key, budgets, nodes, collision, scatter
clearance, asynchronous edits, load prep, fingerprint, the plan rules), both in the authoring subset.
`tests/fixtures/structure_digests.txt` pins `<ref> <md5> <triangles>` for the starter set at a 6 x 4 m
plan, seed 5, flat ground (`StructureGeometry.digest_of`: every mesh's kind, role, vertices, normals,
UVs, colours and indices, the collision and the top). A recipe change in procgen, the role table, the
pane colours or the split moves them on purpose: the test prints the new lines; regenerate the file and say
why in the commit. The render job `tools/render_jobs/jobs/structure_basic.json` (probe
`probes/structures.gd`) lays a street, a chimneyed cottage, a trimmed townhouse, a townhouse on an L plan
and a stone house in a new unsaved map and captures the home and two close views; it logs how many
scatter rows stand inside a footprint (0 after the fix above).

Card S4: `tests/unit/test_structure_tool.gd` (authoring subset: plans and size clamps, the ground
rules and the nearest legal spot, the editor's lot and re-roll, the brush's state machine and its
input table, the eased ghost, the palette pane, the registration, the live edit and a save and
reload of what a gesture laid) and the render job `tools/render_jobs/jobs/structure_tool.json`
(`render_jobs/JOBS.md`).

Card S3: `test_library_structures.gd`, `test_library_structure_store.gd` and
`test_library_structure_transfer.gd` (authoring subset; [library.md](library.md) "Structures" lists
what each covers). The pins now also live with the data: `libraries/core/structures/pins.txt` (`<id>
<pipeline md5> <triangles> <procgen md5>`, the first three agree with the fixture above, and
`test_library_structure_store.gd` compares them). The tiles are rendered by
`tools/render_structure_thumbnails.gd` (the render job `structure_thumbs`, kept no level).
