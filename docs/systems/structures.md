# Structures

Status: data layer (card S1), build (card S2) and the library kind (card S3), 2026-10-28, topic
`structures`. A structure is a building recorded as a library recipe plus the author's inputs; every
peer rebuilds it, as walls, crossings and avatar tokens are. S1 added the record, the
`structures.json` entry of `map.ttmap`, the editor's data calls, the live edit and the fingerprint key.
S2 builds the record into the game: geometry, the nodes and their collision, the worker prep, scatter
clearance, a simple material split and the plan rules. S3 makes recipes a library kind (a
`structures/` folder, index, registry, partial bundles, Verify, tiles; core ships five, thirteen since the street-split follow-up), swaps the
temporary resolver for the registry and shows a placeholder plot where a recipe is missing. S4 adds
the Building tool (palette strip, ghost lot, click and drag, turn, re-roll, removal, live edit: "The
tool" below); S5 adds selection, handles, the door edge, variants and the bar ("Editing a
building"). The design is the
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
`core:townhouse` and `core:townhouse_trimmed`, and, since the street-split follow-up (2026-10-28,
branch `structures-starters`), eight more that widen the palette: `townhouse_timber` (a guild house),
`townhouse_chimneyed` (stacks at the ridge's ends, the party walls of a terrace), `townhouse_end`
(a terrace-end house whose ridge defaults across, a gable to the front, sides to 20 m),
`townhouse_hip`, `townhouse_flat`, `cottage_hip`, `house_hip` and `house_flat` (plain stone with
0.9 m windows). Families: cottage, house, townhouse. Every recipe is glazed and exposes `ridge`
(procgen's layout choice: 0 the longer side, 1 the eave to the front, 2 a gable to it; none on a flat
roof). Each has an index entry (name, family and variant, default and limit sizes, exposed
parameters, tile) and a line in `pins.txt`. Lookup order: the test
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
- **Materials.** `StructureMaterials.make(kind, role, style, root)`, one per triple, shared by every
  structure and by street lots (see "Look"). Panes are unshaded flat vertex colours (a shaded pane
  went black on the side away from the sun); modelled `stone` (coping, the plot) stays an
  `ORMMaterial3D` with the role tint.
- **Fingerprint.** `MapFingerprint`'s `structures` key now has its `node <name> <verts> <aabb>` lines
  (the part S1 left a seam for).

## Look

Card S6 (2026-10-28). The bar is the suite's painterly one: a few bold soft-edged shapes, luminous
colour, suggestion over literal detail, nothing grey. Three parts, no new asset:

- **Per building palette** (`StructurePaint`, `StructureLook.ROOF_PALETTE` / `WALL_LEANS`). A
  structure's seed and id draw (a 32-bit integer mix, the same on every peer) one roof tile colour
  from six (terracotta, clay, slate, thatch, moss, heather; weights 4, 2, 3, 2, 1.5, 0.7) with a small
  value and warmth jitter, and one wall lean from five (cream, rose, ochre, sage, cool pale).
  `StructureGeometry.build_one` bakes them into the mesh arrays: roof vertex colour = tile colour times
  the slab's own tone, wall, trim and chimney vertex colour times the lean; `parts.palette` names the
  roof colour. The alpha carries a height the shaders grade by: roofs 0 at the eave to 1 at the
  ridge of that building's roof, walls height above the building's foot in sixteenths of a metre.
  Panes and leaves stay as procgen made them. A street (`WallGeometry._row_surfaces`) does the same
  per LOT: roles and lots come from the provenance paths (`street_row_2/left/lot0/roof_gable_4`:
  `StructureLook.role_of_tag_path` / `lot_of_tag_path`, since the lots are sub-graphs), the roofs
  are split off the planks into their own `roof` part (`WallGeometry.ROOF_PART`, a `Roof` mesh in
  `AuthoredWalls`) and each lot is painted from the street's seed and its lot path. Fences, walls and
  the old Building kind keep their materials.
- **Roof shader** (`shaders/structure_roof.gdshader`). Tiles are suggested from the face normal and
  the object position, so it needs no UVs and serves gable, hip and flat roofs: courses 0.42 m deep
  across the slope with a soft shadow under each lip, tiles 0.62 m wide offset every other course,
  each tile a little lighter or darker and warmer or cooler, joints barely there (fading to nothing
  when a course is under about two pixels), a deeper cooler eave grading to a paler ridge, and broad
  warm and cool patches (one 3D value noise).
- **Wall shader** (`shaders/structure_wall.gdshader`). The baked masonry set or the library's planks
  times the rock or climate tint times the vertex colour, the hue then replaced 75 % by warm cream
  (times the texture's luminance, so the stones' light and dark stay) for masonry and lifted for
  timber, a cooler damper foot, paler toward the eaves, broad warm and cool washes.
- **Light** (`shaders/structure_painterly.gdshaderinc`, shared; probe A, 2026-10-28: the plants'
  model at a building's albedo). The crowns' rules from `wind_foliage_include.gdshaderinc`: the
  published `foliage_sun` drives a sun-ward albedo ramp (a deeper lavender shade tint away from the
  sun), `light()` is a wide soft N.L band over a tinted shade floor (no lifted fill; a cast shadow
  pulls the lit tone 70 % of the way), and ambient is kept at 0.5 under a full sun (the crowns keep
  0.25) so shade holds its colour. Broad value masses (`s_mass`, soft-edged, from the existing
  noise), a grass-green bounce and dark in the first 0.9 m of wall (`contact_amount`), a faint warm
  rim. Directional lights only (others add lambert). Specular is off. No `lit` window glow yet.

Budget: no extra texture reads over the old materials, one noise per fragment, no uniform branches;
the shaders use only built-ins and a custom `light()`, which the Compatibility and Mobile renderers
take (not run on either, as with the other tt-sim shaders judged on Forward+). Measured cost is in
PERFORMANCE.md "Structures: the painterly look". Tunables are the shader uniforms and the constants
in `StructureMaterials` and `StructureLook`.

## Dressing

Probe B (2026-10-28, branch `probe-b`): a building is settled into its place by a yard,
`StructureDressing` (`utils/structure_dressing.gd`), built beside the building's meshes in
`StructureGeometry.build_one` and carried in `parts.dressing` (not in `digest_of`, so no pin moved, and
not in the building's triangle budget). A pure function of the record, the recipe's door
(`ProcgenBuildingLayout.door_opening()`, else the middle of edge 0) and the ground; the random stream
is `StructurePaint.mix(seed, id)`, so every peer derives the same yard, a re-roll draws a new one and
nothing is stored. Two meshes per structure (`dressing_ground`, `dressing_props` under the
`Structure_<id>` node; no collision):

- **Ground** (alpha blended over the terrain, no shadow, `StructureMaterials.dressing_ground`): a soft
  worn-earth skirt from just inside the wall line out to a wobbling 0.7 to 2 m (wider at the door) that
  covers the hard ring the scatter clearing leaves, and a path from the door that sways and fades (a
  pale paved apron for a townhouse). It lies 5 to 8 cm above the terrain's own triangles
  (`ScatterGenerator.triangle_height`, not the bilinear `ground_at`, which buried it).
- **Props** (opaque vertex-colour blobs, blades and slabs, `StructureMaterials.dressing_props`): by
  family, from the recipe id (`cottage*`, `townhouse*`, else house): a cottage gets flower shrubs,
  stepping stones, tufts and, half the time, a woodpile; a house shrubs, boulders, tufts and a step; a
  townhouse a paved step and two planters. Nothing within 1.5 m of the door. At most 11 clusters; about
  250 to 650 triangles and 2 draw calls per building.
- **Key.** `key_of` also holds the ground in a ring 1.6 m past the walls and along the door's path, so a
  sculpt beside a house redraws its yard; `StructureDressing.enabled` (also in the key) is the A/B switch of
  `jobs/structures_dressing_perf.json`.
- **Not done:** the water around a yard is not known to the worker (the ground snapshot holds heights
  only), so a yard beside a pond can reach into it; the yard does not look at neighbours (a path can
  run into the next house of a terrace); wall-foot moss was not built (a shader band would touch the wall shader; the skirt and plants already
  hide the foot line).

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
replaced the Wall tool's Building tile (`Wall.Kind.BUILDING` and its code were deleted in card S8,
"Splitting a street" below). Like the other tools it is a descriptor (`scenes/states/authoring/tools/structure_tool.gd`), a brush
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
- **Not in this card.** Selection and editing are card S5 (next section); non-rectangular plans
  (`plans` in the entry) are not offered yet; the rise animation of a laid building is a look card.
  The Building kind and its pane fields were retired in card S8.

## Editing a building

Card S5 (2026-10-28): a building laid is edited by direct gestures with the same tool. The rules
are pure (`utils/structure_edit.gd`, `StructureEdit`), the gesture state is `StructureBrush`, the
drawing is `StructureSelectionView`, the edits are `StructureEditor`, and the bar is
`StructureToolPane`.

- **Select.** A click on a building selects it (a tint and outline, the height ring, the door mark,
  a round dot at each corner and a diamond tab beside each side). A building is what the pointer's
  ray meets (`BrushTool.structure_under_pointer`: its roof or wall; the brush's ordinary ray
  excludes structures, so it would land on the ground behind the roof), else the building whose plan
  holds the ground point. While one is selected no lot follows the pointer, and hovering another
  building outlines it (no lot ghost over a building either: a click there selects). Escape, a click
  on bare ground (which only lets go, it lays nothing), `Done` in the bar, or another tool lets
  go. A new lot is not selected when laid.
- **Handles are picked on the screen** (20 px of the dot, corners ahead of tabs), not on the ground,
  because a house in front of a handle hides the ground behind it. The pure fallback picks in map
  metres (tests, probes).
- **Corner dot: resize.** A rectangle (any turn: the rules work in the plan's own frame, x along
  edge 0) keeps its square corners as structgen's plan editor does (`StructPlan.move_point` with
  `keep_axes`): the opposite corner stays, the sizes snap to 0.5 m and clamp **per axis** to the
  recipe's `min_side_m`, `max_side_m` and `max_area_m2` (`StructurePlacement.clamp_size`), and a
  corner never folds over its opposite one. Shift moves that corner alone (the plan leaves the
  square; ProcgenPlan's rules still hold). A plan the rules or the ground refuse (water, a steep
  bank, another building: the lot rules, the structure itself not counting) is **walked back along
  the drag** (ten bisections) to the last plan that stands: never an error.
- **Side tab: push, or the door.** A drag pushes that side out or in (the neighbouring sides grow
  or shrink, corners stay square; same clamps). A plain click (under 6 px) on a tab other than the
  front makes that side the front: `StructureEdit.front_to` rotates the point order so the chosen
  edge is edge 0 and the door side follows (the building is otherwise the same). The bar's `Door to
  the next side` does `front_to(1)`.
- **Body: move.** A drag carries the building by the pointer (offsets snap to 0.25 m); a spot that
  is not legal settles on the nearest legal one in rings (as a new lot does), and the building stays
  put when nowhere within reach is legal.
- **Clamps show, never speak.** Under a drag the outline is the drag's plan at once and a readout
  gives the size in the level's units. A handle the rules stopped turns warm (amber) with a thin
  line to where the pointer is asking; no error text. The one hint is over a side tab ("Click: door
  here. Drag: push this side.").
- **Live edit.** The building itself follows a drag about ten times a second
  (`StructureEditor.preview`: no history entry, the worker builds latest-wins), the release records
  the whole gesture as one entry that undoes to the list from before the first preview
  (`edit(changed, label, before)`), and Escape or a right click mid-drag puts the document back. The
  `structures` live edit carries the release, never a drag frame.
- **Keys.** Q and E turn the selected building about its middle (15 degrees, Shift a quarter; the
  nearest legal ground if the turned plan would not stand, else a toast), R redraws it (the next seed
  of the series), Ctrl+D copies it beside itself (same recipe, seed, parameters and style; the copy
  becomes the selection; `StructureEdit.beside`), Delete or a right click over it removes it.
  `BrushMode` gained `has_selection`, `duplicates` and `duplicate` for these, and `BrushTool.decide`
  takes `selected` (Escape lets go) and `duplicates` (Ctrl+D).
- **The bar** replaces the palette while a building is selected (`StructureToolPane.show_selection`):
  the building's name, **Style** tiles (the other recipes of its family in its library:
  `StructureEdit.variants_of`; `StructureEditor.swap_recipe` keeps the footprint, brought within the
  new recipe's sides by `refit`, the seed, and the parameters the new recipe also declares), a
  stepper for each of **floors** (0 reads Auto, the recipe's own), **roof pitch** (5 degree notches,
  15 to 55) and **chimneys** (`StructureEdit.PARAM_STEPS`), each only where the index entry's
  `expose` lists it and the recipe declares it (so the stone house has no floors and no variants, the
  plain cottage no chimneys), then Door to the next side, Redraw, Copy, Remove and Done. A stepped
  value equal to the recipe's default is not stored. Each press is one history entry; the bar is
  shown again from the record after it, and when the brush sees the selected record change (an undo,
  a peer). Not offered: wall height (floors cover it), window width, and a colour or biome style (the
  record's `style` is the biome under it; the look is card S6's). The GM's Events pane has the
  gestures and keys but no bar.
- **Not offered yet:** a turn ring, wings (L, T, U), edge handles that insert points, the rise
  animation.

## Splitting a street

Card S8 (2026-10-28): `Wall.Kind.BUILDING` is deleted (see [walls.md](walls.md) "Buildings: the kind
is gone"; an old map's `"building"` wall is skipped with a warning), and a generated street becomes
editable buildings through **Split into buildings**: click a street with the Wall tool, press the
pane's button. `WallEditor.split_street` lays one Structure record per lot (`StructureEditor.lay_all`)
and removes the street, as one history group (one undo restores the street and removes the records).
The planning is pure (`utils/street_split.gd`, `StreetSplit.plan`):

- **Where.** The lots are `WallGeometry.row_lots` (the street's own recipe seed and parameters), so a
  record stands where its building did. The footprint is the lot's rectangle, its front (edge 0) the
  street side and wound positive (a street's right side comes wound the other way, so its corners
  are reordered, not rotated), its sides clamped to the matched recipe's `min_side_m`, `max_side_m` and
  `max_area_m2` (scaled to the map as the Building tool does), points snapped to 1 cm. A lot whose
  record the writer would refuse is skipped and counted (`WallEditor.last_split_skipped`). No ground
  or crowding check is made: the street already stood there, and a split must not drop buildings
  silently. The record's `style` is the biome under it, as the tool's.
- **Which recipe.** `StreetSplit.match_row` scores each structure of the core library (else every
  served one) against what the street's species drew for the lot (`walls`, `roof`, `style`, `trim`,
  `chimneys`): a named facade style that is the row's family or tag +6 (a plain lot or a cottage lot
  takes any plain "house" at +4), walls of the row's tags +3 (the other material -1), the roof +1, a
  chimney, shutters, quoins and trim +1 or +2 where the row has them and the lot was dressed with
  them (the same tag without the lot's dressing the same amount less), and a townhouse for a lot that
  is not one -4. The best score wins; a tie is broken by the lot's seed, so a street is not one house
  repeated; under 4 nothing resembles the lot and the seed picks from the whole table. With the
  starter set: a plain stone lot is the stone house, plain timber the cottage, a tall terrace front
  or guild house the (trimmed, when it was dressed) townhouse, a village timber lot the chimneyed
  cottage, and a village stone lot the stone house or the chimneyed cottage by its seed.
- **Seed and look.** The record's `seed_value` is the lot's own building seed (derived from the map
  seed, the wall id and seed, the side and the index; folded into 0..`Structure.MAX_SEED`).
  `params` holds the lot's height and roof pitch, and window width, chimney count and textured
  masonry where the recipe declares them, clamped to its range, only where they differ from its
  default. A split is a function of the document and the library: the same street always splits into
  the same records.
- **Ids and limits.** The records take the lowest free ids; a document that cannot hold them
  (`MAX_STRUCTURES`) refuses the whole split and keeps the street.

Widened 2026-10-28 (the starters card): the roof weighs +3 (as much as the walls, so a hip or flat lot
takes a hip or flat recipe while one exists), a recipe tagged "end" gets +1 for a lot whose gable
faces the street (`ridge` 2) and -1 for one whose eave does, and the record's `params` also carry the
lot's `ridge` (1 the eave to the street, 2 a gable to it) wherever the recipe declares it. With the
thirteen: a plain stone lot under a hip or flat roof is `house_hip` or `house_flat`, a timber cottage
lot under a hip `cottage_hip`, a tall lot under a hip or flat roof `townhouse_hip` or
`townhouse_flat`, a timber guild house `townhouse_timber`, and a dressed terrace house with stacks at
the party walls `townhouse_chimneyed` (or `townhouse_end` when its gable faces the street). The
Structure tool's bar steps `ridge` too (Auto, Eave, Gable) on a recipe that exposes it.

What a split still loses, honestly (render job `street_split`, a terrace and a village street before
and after; before the widening the terrace came out gable-end to the street, hip roofs became
gables and the party-wall chimneys were gone): the buildings stand on the same plots at the same
heights and pitches, with the same walls (stone, textured stone, timber), the lot's roof kind and
ridge direction and a roof tile colour per building, but
- the **yards** (the village's fences, the cottages' low walls) are not structure records and go;
- the **trim** (shutters, sills, door frames) follows what the picked recipe offers, not what the lot
  drew, and a lot whose species gives a flat-roofed cottage or a shuttered timber townhouse still
  gets the nearest recipe;
- facade windows follow the recipe, not the species' window width unless the recipe exposes it
  (`house_hip` and `house_flat` do).

The footprints, heights, roofs and count are close; the silhouette is a recognisable cousin of the
street's rather than the same buildings, and the terrace keeps its eaves and party-wall stacks.

## Not yet

- Window glow: procgen's `glazing` node has a `lit` share, but the recipes do not expose it, so no
  window glows yet (card S6 asked for it "if cheap"; it needs a recipe parameter or a stamp, a
  procgen request). The look pass on three biomes (S6 judged one: temperate forest).
- Cross-platform digests (the pins were taken on Windows only; card S9).

## Tests and render job

`tests/unit/test_map_document_structures.gd` (the record and the map entry) and
`tests/unit/test_structure_build.gd` (recipes, geometry, key, budgets, nodes, collision, scatter
clearance, asynchronous edits, load prep, fingerprint, the plan rules), both in the authoring subset.
`tests/fixtures/structure_digests.txt` pins `<ref> <md5> <triangles>` for the starter set at a 6 x 4 m
plan, seed 5, flat ground (`StructureGeometry.digest_of`: every mesh's kind, role, vertices, normals,
UVs, colours and indices, the collision and the top). A recipe change in procgen, the role table, the
pane colours, the split or the painted palette (`StructurePaint`) moves them on purpose (card S6 did, by
baking the tile colours into the vertex colours; `libraries/core/structures/pins.txt` moved with them): the test prints the new lines; regenerate the file and say
why in the commit. The render job `tools/render_jobs/jobs/structure_basic.json` (probe
`probes/structures.gd`) lays a street, a chimneyed cottage, a trimmed townhouse, a townhouse on an L plan
and a stone house in a new unsaved map and captures the home and two close views; it logs how many
scatter rows stand inside a footprint (0 after the fix above).

Card S4: `tests/unit/test_structure_tool.gd` (authoring subset: plans and size clamps, the ground
rules and the nearest legal spot, the editor's lot and re-roll, the brush's state machine and its
input table, the eased ghost, the palette pane, the registration, the live edit and a save and
reload of what a gesture laid) and the render job `tools/render_jobs/jobs/structure_tool.json`
(`render_jobs/JOBS.md`).

Card S5: `tests/unit/test_structure_select.gd` (authoring subset: the handles and the pick, a
corner and a side dragged with their clamps, a turned house, Shift, water and neighbours walking a
drag back, the door edge, a move and a turn, the stepped parameters, the variants, each edit as one
undoable history entry and a live edit, the brush's select, drag, abort and keys, the pane's bar and
the input table) and the render job `tools/render_jobs/jobs/structure_select.json` (probe
`probes/structure_select.gd`: a roof click, a hovered tab, a corner dragged past the clamp, the door
click, the bar's buttons; keeps no level; three captures). The driver's `input` op takes a third
number in `at`, the height to aim at (0: the ground under a roof, where a handle is drawn). The five
tiles under `thumbnails/structures/` were re-rendered with `structure_thumbs` after the glazing
change (2026-10-28: panes and door leaves show).

Card S3: `test_library_structures.gd`, `test_library_structure_store.gd` and
`test_library_structure_transfer.gd` (authoring subset; [library.md](library.md) "Structures" lists
what each covers). The pins now also live with the data: `libraries/core/structures/pins.txt` (`<id>
<pipeline md5> <triangles> <procgen md5>`, the first three agree with the fixture above, and
`test_library_structure_store.gd` compares them). The tiles are rendered by
`tools/render_structure_thumbnails.gd` (the render job `structure_thumbs`, kept no level).
