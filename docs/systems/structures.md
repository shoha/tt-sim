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
  and `walkable` (2026-10-29, topic `stilt_collision`): the extra faces `StructureWalkable` derives
  from the tags, see "Collision of raised parts" below (not in `digest_of`),
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

**Collision of raised parts** (2026-10-29, topic `stilt_collision`). Established empirically first:
procgen's `collision` is the walls' hull and roof only; its Stilts and Gallery nodes "add no
collision", so a stilt house's deck, stair and platform, a stabbur's raised floor and a porch,
balcony or gallery deck let a dropped token fall to the ground, and the piles did not block. A token
lands by a downcast from its top on the terrain layer (`WaterSurface.landing_below`), so anything
solid on that layer is standable. `StructureWalkable` (`utils/structure_walkable.gd`, pure) reads
the per-vertex tags every build already carries and adds the pieces to the same `Collision` body
(`parts.walkable`, merged in `AuthoredStructures._structure_node`), so the ground tools and the
Building tool skip them as they skip the walls (`exclude_of`):

- walkable, upward faces only (a token under a deck is not caught by its underside):
  `stilt/slab/<k>`, `stilt/deck`, `stilt/stair/tread<k>`, `porch/deck`, `porch/plinth`,
  `balcony<k>/deck`, `gallery/deck` (the slot path after the node id; `WALKABLE_PATTERN`);
- blocking, every face: `stilt/pile/<k>`, `stilt/pad/<k>`, `stilt/cap/<k>` (`BLOCKING_PATTERN`);
- visual only: rails, posts, braces, bearers, stringers, ladder rungs, hoods, brackets and roofs.

The stair is walkable by its treads (a stepped surface, no ramp). A ladder is not walkable. About
200 triangles for a stilt house (mostly piles), 2 for a porch. The wall hull is unchanged, so
the pinned `collision` digests did not move; a new tag in procgen needs a line in the two patterns
and a case in `tests/unit/test_structure_walkable.gd`.

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
- **Balance and panes** (look integration, 2026-10-28). The crowns' lavender shade, tuned for leaves,
  made shaded stone mauve-grey and slate deep violet, so a wall material overrides the shared
  uniforms (`StructureMaterials._balance_wall`: a sandy-olive shade tint and floor, stone lit gain
  1.24/1.18/1.08, timber 1.5/1.38/1.15 with a honey `cream_amount` 0.5 and warm bias) and the roof
  material a lighter, less violet shade and eave (`_roof`); slate is `(0.50, 0.62, 0.64)`. Panes and
  leaves use `shaders/structure_pane.gdshader` (`StructureMaterials.pane`, also the street lots'
  glass): unshaded as before, but a cool pane (blue at least as strong as red; amber glow and
  wooden leaves are left alone) is scaled to a mid tone and pulled 40 % toward one sky teal with a
  breath of warm reflected light, so panes keep their variety but stop reading as pale stickers.
- **Ink and clump patches** (card structures-ink, 2026-10-28). Two shared terms in
  `structure_painterly.gdshaderinc`, both free of mesh data and texture reads. `s_ink` is the plants'
  silhouette ink (`foliage_view_ink`) at a building's scale: the albedo is multiplied toward a deep
  plum (`ink_tint`) where the geometry normal turns from the camera (a fresnel term) and along
  creases, found from `fwidth` of the view-space normal (a wall corner, a roof fold, about a pixel
  wide); roofs add a little at the eave lip (`COLOR.a` near 0). A true silhouette against sky or
  ground is not found (that would need a depth read or an inverted hull, and the meshes have split
  vertices), so a flat-faced building gets ink at its corners and folds, not round its outline.
  `s_break` is the clump octave: one more 3D value noise at about tree-clump scale (0.22 to 0.3 per
  metre) shifting hue in soft blotches (damp sage to warm ochre), on walls instead of the old fine
  mottle (walls at a near-constant value, `value` 0.12, so they never darken; roofs 0.58) and on
  roofs beside the existing patch. Walls use the soft ink (`softness` 1: a light lavender, little
  on grazing faces; roofs keep the deep plum). Palette: timber lifted (`TIMBER_LIFT`,
  `TIMBER_CREAM` 0.6), stone shade a light cream-lavender (floor 0.31/0.27/0.36) with its lit gain
  raised to 1.42/1.35/1.2 and a cooler-cream warm bias, slate now a teal-slate
  `(0.46, 0.62, 0.59)`. Tunables: `ink_tint`, `ink_silhouette`, `ink_crease`, `break_amount`.
- **Handmade starters.** The core starters are generated with procgen's `handmade` option
  (`tools/export_core_structures.gd`: `wonk` 0.7 default and exposed, `fringe` 0.35 m on the two
  timber gable cottages, window bars on): bowed ridges and eaves, leaning, tapering walls, a shaggy
  thatch eave. `top_y` is the highest point of the displaced roof, so a token landing on the ridge
  centre can stand a hand below it.

Budget: no extra texture reads over the old materials, one noise per fragment, no uniform branches;
the shaders use only built-ins and a custom `light()`, which the Compatibility and Mobile renderers
take (not run on either, as with the other tt-sim shaders judged on Forward+). Measured cost is in
PERFORMANCE.md "Structures: the painterly look". Tunables are the shader uniforms and the constants
in `StructureMaterials` and `StructureLook`.

## Styles (architecture styles card 1, 2026-10-29)

Procgen's building styles (`procgen/recipes/building_styles/*.json`, `docs/building_generation.md`
"Building styles and material kinds"; design `procgen/docs/architecture_styles.md`) put new surface
KINDS into a recipe, which tt-sim shades; the geometry is the old board and masonry walls and gable,
hip and flat roofs.

- **Kinds to materials** (`StructureMaterials.make`, one shared material per kind and role): walls
  `plaster`, `adobe`, `brick`, `log` are one shader, `structure_style_wall.gdshader`, with a `pattern`
  uniform and no textures (the colour is the vertex colour; the pattern comes from the position and
  the face normal, so a rotated building keeps it): plaster is a soft lime wash with trowel marks,
  rain streaks and a lost-plaster patch near the foot; adobe the same rounder and earthier with
  baked layers and a darker packed-earth top on a flat roof; brick small courses and a stylised
  chunky size with per-brick value and warmth, a light mortar and a shadow under every course; log a
  horizontal round of 0.3 m with a dark seam, a lit belly and a grain. Pattern details fade where a
  course is under about two pixels. `boards` is the planks (`_timber`) under a kind the gable ends
  share. Roofs: `tile` (and the old `wood`) the tile shader; `slate`, `shingle`, `thatch`, `turf`
  are `structure_style_roof.gdshader` (`pattern` uniform, the roof shader's slope axes): small cool
  slates, scalloped shingles, shaggy straw strands in bundles greening toward the eave, and broad
  green turf with tufts, a sprinkle of wildflowers and soil edges. Both shaders are in
  `GraphicsWarmup.COVERED_SHADERS`; one noise per fragment, no textures. The roofing kinds are
  `StructureLook.ROOF_KINDS`; a roof surface of any other kind (a plaster gable end, an adobe flat
  roof) is drawn as a wall (`material_role`).
- **Palette hints** (`StructureLook.palette_hints`, `StructurePaint.palette_of(seed, id, hints)`): a
  style's wall, roof and accent tones are written on the recipe's Output node (`palette_wall`,
  `palette_roof`, `palette_accent`, hex lists). With hints the roof colour is drawn from the style's
  roof list (the palette name is `style`) and wall meshes get a wall tone from its wall list in
  place of the lean (kept under each face's slight variation: fully for the textured kinds with a
  gain of 1.7, 30 percent for plaster, adobe, brick and log so boards under a wash do not stripe).
  A recipe without hints is painted exactly as before. The accent list is carried but not used yet.
- **Starters**: ten core structures from the styles (`tools/export_core_structures.gd` STARTERS
  entries with a `bundle` and a `seed`: the style's drawn recipe, default size, culture tags and
  exposed controls come from the style file): stucco villa, adobe house, slate-roofed stone house and
  alpine chalet (family `house`), thatched cottage, log cabin and turf-roof longhouse (`cottage`),
  brick terrace house and canal house (`townhouse`), barn (`farm`). Culture tags: `mediterranean`,
  `desert`, `highland`, `english`, `alpine`, `nordic`, `dutch`, `farm`. The Structure tool groups by
  family as before; a culture filter is not built. Render job `structures_styles` lays the ten among
  meadow plants (probe action `styles`).

### Round plans (styles integration, 2026-10-28)

Five core structures are regular polygons, built by procgen's `ProcgenRecipesRound` (`STARTERS`
entries with a `round` table: a `kind` or `make` options, and `sides` / `radius` / `radius_min` /
`radius_max` over the kind's `info`): `roundhouse` (thatched, 8 sides, family `roundhouse`),
`round_hut` (timber, 12 sides, `roundhouse`), `watchtower` (square, pyramid roof, family `tower`),
`tower_hex` (6 sides, cone roof, `tower`), `dome_hall` (10 sides, stone, dome, family `hall`).
Adding one is one table entry; the exporter writes the rest.

- **Data.** The index entry has `plans: ["round"]` (`LibraryContracts.STRUCTURE_PLANS`, which is
  procgen's `ProcgenStructureIndex.PLANS`, as plantgen's validator reads it), the tags `round` and
  `regional`, a `sides` key (the polygon's corner count, `ProcgenStructureIndex.sides_of`; a legacy
  `sides:<n>` tag is read when there is no key, and the reader fills the key in), and sizes that are DIAMETERS: `default_size_m` is
  `[2 r, 2 r]`, `min_side_m` and `max_side_m` the least and largest diameter (twice the kind's
  `radius_min` and `radius_max`), `max_area_m2` the square of the largest. A footprint is
  `StructurePlacement.round_plan(centre, radius, yaw, sides)`: `ProcgenPlan.regular_polygon` with the
  front (edge 0, the door) facing +Z at turn 0, so every plan is a valid polygon by construction
  (the sizes keep every side at least 0.5 m).
- **Pins.** A round starter is pinned at its own default polygon, not the 6 by 4 m rectangle
  (`StructurePlacement.pin_plan(row)`; `tests/fixtures/structure_digests.txt` and `pins.txt` hold the
  same digest and triangle count): roundhouse 1234 triangles, hut 864, watchtower 528, hex tower 724,
  dome hall 1302.
- **The tool.** The ghost is the polygon (`StructurePlacement.lot_plan` with `sides_of(row)`); a click
  lays it at the nearest legal spot, a press-and-drag draws it from its middle outward (the press is
  the centre, the pointer the rim; the radius clamps to the row), the bracket keys scale it, Q and E
  turn it. `clamp_size` returns one square diameter for a round row. The selection's handles are the
  polygon's corners and side tabs, and a drag of either is a UNIFORM SCALE about the middle
  (`StructureEdit._round_scaled`): the radius is the pointer's distance (a corner), or the pointer's
  distance along the side's normal (a tab), snapped to 0.5 m on the diameter and clamped to the row,
  keeping the turn and the middle; Shift changes nothing, the shape is fixed and always a valid
  polygon. A click on a side tab still makes that side the front (the door), a body drag moves it,
  Q and E turn it. `fits_row` and `refit` read the circumradius for a round row.
- **Streets.** A street's lots are rectangles, so `StreetSplit.candidates` never offers a row tagged
  `round`, and a `regional` row only for a street of its region (below).

### Regions in a street split (styles integration, 2026-10-28)

`StreetSplit.region_of(doc, wall)` names a street's region tags: the palette biome under its middle
(`BIOME_REGIONS`: savanna `desert`, `mediterranean`; rocky badlands `desert`; alpine meadow `alpine`;
boreal taiga `nordic`, `alpine`; birch woodland `nordic`; wetland `dutch`), else, when the biome names
none, its species' (`SPECIES_REGIONS`: terrace `english`, `dutch`; guild houses `dutch`; village and
cottages `english`; mixed none, so a default street is what it was). A `regional` row whose tags hold
a region tag joins the candidates. A biome region in `EXCLUSIVE_REGIONS` (`desert`, `mediterranean`,
`alpine`, `nordic`) REPLACES the generic set (a savanna street is adobe houses and stucco villas); a
flavour region (`english`, `dutch`) joins it and a joining row scores `W_REGION` (4) more, so an
English village gets thatched cottages and slate houses among its stone houses. All of it is a function of
the document and the street, so a split stays deterministic.

### Stacked, kit and ruin starters (styles integration 2, 2026-10-28)

Nine more core structures put procgen's cards 3 and 6 into the palette (`STARTERS` entries; the
table also takes `style_patch`, a deep merge over the style file, `kit_index` (one of the style's
`kit` patches, always drawn), `tags_add`, `tags_drop` and `expose_add`):

- **Stacked and flat-roof kit.** `tudor_townhouse` (family `townhouse`, variant "Tudor, jettied": a
  plaster ground floor, a jettied timber storey with dark beams and joist ends, a third storey by
  chance; exposes `jetty`; tags `tudor`, `english`, `jetty`, `beams`), `pueblo` (family `house`:
  stepped, rounded terraces, vigas, a ladder), `adobe_parapet` and `adobe_rounded` (`house`: the
  adobe style's second and third `kit` patches, a parapet, and rounded corners with vigas).
- **Ruins.** Family `ruin`, tags `ruin` and `regional`, and `ruin` exposed (0 to 1): `ruin_cottage`
  (slate-house style, textured stone), `ruin_chapel` (a longer, steeper stone house at 0.45, so both
  gable ends and part of the roof stand), `ruin_townhouse` (the canal house in brick, gable to the
  street), `ruin_barn` (timber boards), `ruin_tower` (an octagon from `ProcgenRecipesRound.make`
  with `ruin`, plan kind round). A ruin recipe has no glazing, chimneys or trim by design. An L plan
  is not offered by the tool, so there is no "ruined L townhouse"; any rectangle works.
- **Sizes.** Every starter was built at its least and largest footprints (least side by the longest
  allowed, three seeds each, `StructureGeometry.build_one`): all build with no problem, 600 to
  4600 triangles, 12 to 60 ms. A jetty or a set-back stays inside the plan's rules (the plan is the
  ground storey; an upper storey that overhangs is not part of the footprint check).
- **Look.** A new role `frame` (`StructureLook.FRAME`; node types `beams`, `vigas`, `roof_props`)
  keeps procgen's own timber tone (`StructurePaint`): beams were painted the plaster's wall tone
  before, so half-timber vanished. Moss (`ProcgenRuin.MOSS_TINT`, a multiplied green) is read back
  from the colour (`StructurePaint.moss_of`) and kept under a style's wall tone, and the wall shaders
  pull a mossy vertex toward a bright green (`s_moss_of` / `s_mossy` in
  `structure_painterly.gdshaderinc`; `structure_wall` applies it after its cream, `structure_style_wall`
  on the vertex colour). Moss is procgen's tint on the foot of the walls (1 m) and the rubble.
- **The tool.** `ruin` and `jetty` are steppers (`STEPPED`; `PARAM_STEPS` 0.1 each, a ruin reads in
  percent, a jetty in metres), offered when the row exposes them. The `ruin` family is its own tile
  group; the selection's Style tiles swap among the four rectangular ruins (`variants_of` offers only
  rows of the same plan kind, since a swap keeps the footprint: the round tower has no Style tiles).
- **Streets.** `StreetSplit.RUIN_TAG`: a split never picks a row tagged `ruin`, whatever region
  tags it carries. The tudor townhouse (`english`) and the desert adobe and pueblo rows join their
  regions' candidates like the other regional rows.
- **Render job** `structures_styles2` (probe action `styles2`, lots in `structures.gd` STYLES2_LOTS;
  a step's `lots` lays a comparison instead): two rows of five on a meadow. Captures from
  2026-10-28 are in `docs/plans/2026-10-28-structures/captures/styles2/` (not tracked).

### Styles 3: profile roofs, towers, battlements, gables, arches (2026-10-28)

Thirteen more core structures (50 in all) from procgen's architecture-styles cards 4 and 5, each one
`STARTERS` entry with a `bundle` and a `seed` (the footprint at the pin is still the 6 by 4 m
rectangle; a tower or pagoda recipe builds at it, and a corner or side tower stands OUTSIDE the main
plan, so the footprint rules govern the main building only). Triangles at the pin: `gambrel_barn`
(family `farm`) 1064, `mansard_townhouse` (`townhouse`) 3108, `dutch_canal_house` (stepped gable,
`townhouse`) 3702, `dutch_bell_house` (bell gable) 3678, `minka` (`house`) 1800, `half_hip_cottage`
(`cottage`) 1170, `saltbox_house` (`cottage`) 1716, `chapel` (`hall`, side bell tower and spire) 3863,
`market_hall` (`hall`, arcade) 2036, `chinese_hall` (`hall`) 1416, `pagoda_tower` (`tower`) 2284,
`castle_keep` (`castle`, four corner turrets, battlements) 3292, `gatehouse` (`castle`, twin towers) 3052.
The two Dutch rows are the style's first and third `kit` patches (`kit_index`). Culture tags come from
the styles: `dutch`, `american`, `french`, `english`, `colonial`, `japanese`, `chinese`, `medieval`.
Exposed controls are what each style lists and its drawn recipe declares (height, floors, roof pitch,
chimneys, ridge, wonk, fringe); the roof-form numbers (`sweep`, `tiers`, `break`) are fixed per draw
and NOT on the interface, so the Structure tool does not offer them.

- **Look fixes.** `StructureLook.NODE_ROLES` had no `roof_profile` or `roof_round`: gambrel, mansard,
  half-hip, saltbox, upswept and pagoda roofs, and every cone, dome and spire over a round plan or
  tower, were painted and shaded as WALLS. Both are the `roof` role now, so their roof kind (tile,
  slate, shingle, thatch) shades them; a pagoda's `body_role` `plaster`, a gable end's `plaster` and a
  castle's `stone` roof slabs stay walls (`material_role`). The roundhouse, hut, watchtower, hex tower
  and dome hall pins moved for that. Slate leans toward teal (`StructureMaterials.SLATE_TONE_SHIFT`,
  the roof shader's `tone_shift`; the styles' slate tones are navy blue greys). The style brick is
  weathered toward a rosy brown (`brick_weather`). Moss on a style wall (brick, plaster, adobe): the
  shaders read moss from the colour as green over red and blue, which a red or orange wall with
  procgen's multiplied green never shows, so `StructurePaint` bakes the green in and lets a building's
  strongest moss climb its first metre (`MOSS_FULL_M`, `MOSS_CLIMB_M`), because procgen puts moss on the
  lowest strip of a brick wall only. Boards get no moss (procgen's Ruin node puts none on timber).
- **Tiles.** `LibraryStructures.default_height` counts a tower's `extra` and roof and a pagoda's tiers,
  so a tall building is framed whole. The tiles are in `thumbnails/structures/`.
- **Streets.** `StreetSplit.FARM_TAG`: a row tagged `farm` (the barns) never joins a street, whatever
  its region tags (the gambrel barn is `dutch` and would join a canal street). The Dutch canal rows
  join `dutch` streets and the half-hip cottage `english` ones; the rest (mansard, minka, chapel,
  castle, pagoda, halls, saltbox) have no region a street gives, so they are for the Building tool.
- **Render job** `structures_styles3` (probe action `styles3`, lots STYLES3_LOTS): three rows on a
  320 ft meadow (the map side limit is 320 ft, so 13 buildings need three rows), nine captures.
  Captures are in `docs/plans/2026-10-28-structures/captures/styles3/` (not tracked).

### Styles 7: half-timber framing (2026-10-29, branch `framing`)

Four more core structures (54 in all) from procgen's Framing node (architecture-styles card 7), each
a `STARTERS` entry whose `style_patch` pins the framing pattern: `half_timber_house` (`house`,
braces) 1574 triangles at the pin, `tudor_framed` (`townhouse`, jettied, cross bracing; `english`
added to its tags) 3174 (3018 before procgen 0983204 closed the soffit under a jetty), `herringbone_cottage` (`cottage`, ochre plaster, herringbone) 1734 and
`close_studded_house` (`house`, panels at 0.6 m studs) 1542. All four are `regional` and `english`,
so they join English streets. The look fix: the node type `framing` is the `frame` role
(`StructureLook.NODE_ROLES`; before, its posts, rails and braces were painted as plaster walls
and the half-timber vanished), so the timber keeps procgen's dark oak tone over the plaster.
The plaster tones are warmer creams than the styles' (the shaded face of a pale cream reads mauve).
Render job `structures_framing` (five houses in a row, the beams-based Tudor for comparison).

### Styles 9: porches, galleries and dormers (2026-10-29, branch `gallery`)

Four more core structures (58 in all) from procgen's Gallery and Dormer nodes (architecture-styles
cards 9a, 9b), each a `STARTERS` entry whose `style_patch` pins the feature so the draw always has
it: `porch_cottage` (`cottage`, american, a pent porch over the door with balusters, a gable
dormer) 1898 triangles at the pin, `veranda_cottage` (the same style, a veranda along the front
with a panel rail, no dormers) 1700, `inn_gallery` (`inn`, two floors, an upper gallery on posts,
`english` added to its tags so it joins English streets) 1482 and `dormered_house` (`house`,
steep slate roof, a gable dormer over the front, `french` added) 1092. All four are `regional`.
The look fix: both node types emit parts of several roles, so `StructureLook.role_of_slot` reads
the slot path after the node id: a gallery's deck, posts, brackets and rails are `frame` (its
`.../roof` and hood roofs are `roof`, its plinth `trim`), a dormer's `roof<j>` is `roof` (the
main roof's tile), its `sill` and `head` are `trim`, its `pane` an `opening` and its `wall` a wall.
`role_of_tag_path` (street rows) passes the segments after the node's name the same way. The wall
tones of `inn_gallery` and `dormered_house` are warm creams, as the framed houses'. The inn's
footprint default is 9 by 5 m; at the 6 by 4 m pin it still builds (two floors, gallery and all).
Render jobs `structures_gallery` (the row, one close-up each) and `gallery_thumbs` (tiles at yaw 180
so the feature faces the camera).

### Styles 10: houses on stilts (2026-10-29, branch `stilts`)

Three more core structures (61 at that point) from procgen's Stilts node (architecture-styles card 10):
`stilt_house` (the `stilt_house` style, posts with cross or diagonal bracing, a veranda deck and a
stair) 1690 triangles at the 6 by 4 m pin, `lake_dwelling` (reed thatch, a panel-railed deck)
2100, and `stabbur` (a Nordic log granary on stone staddles under a turf roof, a short stair)
1210; on a 0.25 slope they grow to 1726, 2148 and 1258 (the piles are cut to the ground under each
corner and sink 0.3 m below it, so none hangs). All three are `regional` and none carries a region
tag a street asks for (the styles' tags are `tropical`, `lake` and `nordic`; the stabbur is also
`farm`), so a street split never picks one and the Building tool is where they are placed. The
look fix: `StructureLook` gives the `stilts` node type the `frame` role (slab, bearers, piles,
braces, stair, ladder and deck keep procgen's timber tone) and `role_of_slot` reads the part after
`stilt/`: `pad` (a footing under a post) and `cap` (a staddle's cap) are `trim`. A staddle's shaft
is a `pile` and keeps its stone kind, drawn as stone. The `family` of the stabbur is `granary`, so
it is not offered as a variant of a house. The magenta flecks the procgen contact sheet shows on
the thatch and turf roofs are ProcgenSketch's backface mark, not a fault: every triangle of the
three built structures has a winding that agrees with its vertex normals (probed on the final
meshes), no vertex colour is magenta, and the real shaders show none from any of four yaws.
Render jobs `structures_stilts` (row and close-ups), `structures_stilts_yaws` (the same three at
yaw 90, 180 and 270) and `stilts_thumbs` (tiles at yaw 180, which shows the stair).

### Styles 11: courtyards (2026-10-29, branch `courtyard_rows`)

Three more core structures (64 in all) from procgen's courtyard styles (architecture-styles card 11):
`coaching_inn` (a galleried inn round a paved yard), `siheyuan` (a courtyard house) and `hof_farm`
(barn wings round a farmyard), family `courtyard`, all `regional` (so no street split picks one;
`inn` and `farm` come from the style's own tags). A click lays one at its default size and a drag
sizes it, the same Building tool path as any row; only the row's numbers differ: `default_size_m`
14 by 12 m (the hof 16 by 14), `min_side_m` 9, `max_side_m` 24 (hof 26) and `max_area_m2` 330
(hof 380), taken from the styles' `size`. procgen builds the courtyard plan only from 9 by 8 m up
(below that it shows the plain building), and `min_side_m` 9 on both sides keeps every lot above
it: a drag below the minimum clamps up to 9 by 9 (`StructurePlacement.clamp_size`), it never
fails; a drag past the area limit scales both sides down together (24 by 24 asked gives 18.2 by
18.2). The pin footprint is the one thing that assumed 6 by 4 m: that rectangle is below the
courtyard minimum, so pinning there would pin the plain building. `StructurePlacement.pin_plan`
now returns the default rectangle for a row whose `min_side_m` is 8 or more
(`PIN_DEFAULT_MIN_SIDE_M`; the other rows' least sides are at most 6.8 m, so no existing pin
moved); the exporter passes it the row. Triangles at the default size: coaching inn 6400, siheyuan
3108, hof farm 6296 (soft budget 12000). `tests/unit/test_courtyard_rows.gd` holds the checks
(regional tags and limits, street split, pin plan, clamps, a built courtyard at default and at the
least size). Known procgen gap: the roofs of abutting wings interpenetrate at the corners. Render
jobs `courtyard_rows` (the three at default size and at the minimum) and `courtyard_thumbs`
(tiles at yaw 0, so the gate faces the camera).

### Toon styles (2026-10-30, branch `toon_look`)

Eight bright "toon town" structures from procgen's `docs/toon_styles.md` (72 core structures at
that time, 83 now): `toon_clinic`, `toon_shop`, `toon_gym`, `toon_lab` (12-gon), `toon_cafe`, `toon_cottage`,
`toon_lighthouse` (8-gon) and `toon_hall`, family `toon`, all `regional` (no street split picks
one), with the style's tags (`toon`, `bright`, `saturated`, `flat_colour`, the building type). The
two round ones are listed with plan `round` and `sides` (the exporter reads the polygon from
`ProcgenRecipesToon.footprint(style)`, `_round_style_spec`) and pin at their default radius. The
hall row sets `min_side_m` 6: the style's own `size` has min_side 7 under a 10 by 6 default, which
the index reader refuses (an unreadable row made the recipe "unknown"; procgen-side data).

Host support: the `trim` surface kind is the accent tone. `StructureLook.palette_hints` reads
`palette_accent` beside the wall and roof lists; `StructurePaint.palette_of` draws one roof tone and
one accent tone per building from its seed (`mix(h, 53)`; no list gives a timber brown) and paints
every `trim`-kind piece in it, under the piece's grey brightness shade, whatever its role (a dome
with `roof_role: trim` is a roof by node but an accent by kind, so it skips the roof grade). The
plaster wall shader draws it (`StructureMaterials.make`). The Roof Cap node (`roof_cap`) is trim
by default; `role_of_slot` makes `cap/dome` and `cap/cone` roof, `cap/inner` wall and `cap/glass`
an opening. Nothing desaturates a toon colour: the roof tile shader multiplies the vertex colour
by a soft pattern and a lit gain, and `tests/unit/test_toon_look.gd` holds the painted roofs above
saturation 0.5 at value 0.7. The adobe wall's mud-roof tone for up-facing faces is now gentle
(0.95, 0.91, 0.86 and half the patches), since every up face, a parapet's cap included, takes it.
Render jobs `toon_look` (the family on a 160 m map; lots must stand within about 25 m of the map
centre, wider ones are refused) and `toon_look_thumbs` (the regenerated tiles). `dormered_house`
takes dormer width 1.5 and wall height 1.2 in the exporter's style patch.

### The style range and windmills (2026-10-30, branch `range_look`)

Eleven more structures from procgen's `docs/style_range.md` and `architecture_styles.md` section 8
(83 core structures in all), all `regional`: `windmill_tower` (12-gon) and `windmill_dutch`
(8-gon), family `windmill`; `flemish_stepped` and `hanseatic` (crow-stepped gables, family
`townhouse`); `porthole_cafe` and `lantern_cottage` (round and octagonal windows, glass tone), and
`toon_clinic_wing` and `toon_gym_lobby` (family `toon`); `ivy_manor` (`house`), `bartizan_keep`
(`castle`) and `chapel_rose` (`hall`), which carry procgen ornaments in the recipe (a player's
Decorate row still adds more). The windmills are round styles (`_round_style_spec`), sizes from
the style. Render jobs `range_look` and `range_look_thumbs`; the `rounds` probe action takes `lots`.

Look verdicts: the pane shader no longer washes a violet tint (green under red) to sky teal
(`structure_pane.gdshader`; warm, rose, sea and cool were already right). The windmill's Sails node
is role FRAME (the timber's own honey tone; the sails, gallery, curb and rail are `wood`) and its
`cloth` slot is TRIM (a pale canvas in the plaster kind, never the brick's red). Round-window rings
and spandrels need nothing: the ring takes the style's `ring_role` and the spandrels are wall.

**Windmills turn.** `StructureMill.split` (pure, called by `StructureGeometry.build_one` after the
walkable faces) cuts the WHEEL (every triangle whose first vertex is tagged `sails/...`) and the CAP
(ROOF-role triangles lying wholly above the top of `windmill/curb`) out of `parts.meshes` into
`parts.mill` (`wheel`, `cap`, `hub`, `axis`, `centre`, `curb_top`). The hub is the centroid of the
`sails/hub` vertices; the axis is the horizontal direction from the centre of the `windmill/curb`
ring to the hub (the contract's outward normal turned by `yaw`, as procgen put the hub there, so the
host needs no yaw); the cap turns about the vertical through that centre. Collision, the walkable
faces and `top` are made from the whole building and do not change. `digest_of` and
`triangle_count` cover `meshes` plus the mill, so only the two windmills' pins differ in kind;
no existing pin moved (`FORMAT_VERSION` 4 only renews cache keys).

**Pin a47d686 (2026-10-30, branch `pins_final`).** Procgen's polish round moved fourteen digests: the
windmills (tapered towers, Sails follow), the eight toon styles and `toon_clinic_wing` and
`toon_gym_lobby` (glass tone per style, wider toon windows) and `ivy_manor` and `bartizan_keep`
(ivy blankets, ornament placement). `toon_gym_court` (a pent canopy and a stepped parapet,
`regional`, family `toon`) is the 84th core structure. Tiles of all fifteen were regenerated; the
windmills have more headroom.
`AuthoredStructures.mill_node` builds a `MillMotion` (`scenes/terrain/mill_motion.gd`) named `Mill`
at the centre, holding the cap meshes (`cap_<role>_<kind>`) and the child `Wheel` at the hub holding
the sail meshes (`wheel_...`); the meshes keep their map-frame vertices and sit at minus the pivot.
Two transforms change per frame and no mesh is rebuilt: the wheel about the axis at about 0.29 rad/s
(22 s a turn, +-25 percent per building by id) and the cap's yaw, set to face `MillMotion.WIND_FROM`
with a gentle sway. tt-sim has no global wind value (the weather renderer's wind particles use a
fixed direction and plants sway on their own shader parameters), so the speed is constant; the
weather's direction was not used because it put the wheel edge-on to the default camera. A
`VisibleOnScreenNotifier3D` stops `_process` off screen, and `UiMotion.reduced()` (the OS setting;
there is no in-game one) keeps the wheel still. `provenance_at` finds a mesh under the pivots by name.
Tests: `tests/unit/test_structure_mill.gd`.

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
- **Clearance** (look integration, 2026-10-28). The worker's ground snapshot
  (`StructureGeometry.ground_snapshot`) now carries private copies of the water bodies, the pond
  mask and every structure's footprint. A yard never reaches into water or another structure: the
  skirt's reach is pulled in (x 0.6, up to four times, to at least 0.35 m) until its edge is dry and
  0.35 m clear of the neighbouring footprints, the path stops at water or a neighbour (0.4 m), and
  plants, rocks and planters are skipped when their centre is wet or within 1 m
  (`NEIGHBOUR_CLEAR_M`) of another footprint (only footprints within 14 m are considered). The key
  also holds those footprints and whether the ring around the walls is wet, so moving a neighbour or
  a pond redraws the yard. The skirt has a deeper drip line at the wall and an alpha of 0.9 out to
  72 % of its reach so it reads against green ground in shade. Props near water are placed by
  their centre only, so a large shrub can overhang a shore by a few tens of centimetres.
- **Not done:** wall-foot moss was not built (a shader band would touch the wall shader; the skirt
  and plants already hide the foot line).

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
- **Palette round 2 (card building_ui2, 2026-10-30).** The pane is a drawer of key facts, the
  gestures live on the hint bar:
  - *Filter chips* (`StructurePalette.CHIPS`: Home, Farm, Inn, Castle, Church, Shop, Ruin, Toon,
    Regional, Stone, Timber, Thatch) above the tiles, multi-select, with the search box and a Clear
    (with the tally, "14 of 72"). A chip matches a row by its family or one of its tags. Chips of one
    group (kind, look, material) widen the choice, chips of different groups narrow it; a chip's count is
    what it would show given the search and the other groups' chips, and a chip that would show nothing
    is greyed. All pure (`passes_chips`, `chip_counts`, `toggled`).
  - *Tiles* are 80 px pictures (a "Small tiles" switch gives 48 px, remembered in the settings
    file's [ui] section); the column count follows the pane width (`StructurePalette.tile_metrics`,
    two at least, refit on `resized`). A hover card (`StructureCard`, a top-level plaque on the board beside
    the drawer, shown 0.12 s after the pointer rests) gives a 128 px picture, the name, the family
    and a few tags, and the starting size; tiles carry no tooltip.
  - *Key caps, not prose.* While the brush is down the hint bar (`InputHints`, the app's key-chip
    bar, bottom centre) carries the tool's keys: `ToolDescriptor.key_hints(brush)`, lit by
    `AuthoringController.refresh_tool_hints()` (on pick, on put-away, when the rows change).
    `StructureHints` holds the rows (Click, Drag, Q / E, R, Del; with a building selected Drag, Q / E, R,
    Ctrl+D, Del, Esc) and drops each key once its gesture was done once (`StructureBrush.gesture_done`
    -> `StructureHints.mark`, kept in the settings file per user; `reset(true)` forgets). The pane and
    selection hints are one short line.
  - *Live note beside the ghost.* `StructureNote.live` gives `{text, level}`: BLOCKED (red: the
    `refusal_text` words, a release lays nothing and toasts them as before), NOTE (amber: the lot
    was eased off water, a bank, the map edge or a building - `StructurePlacement.nearest_legal`'s new
    `why` - or held to the recipe's size range, stated in the level's units), else none. It is worked
    out once per input change (`StructureBrush._refresh_note` keys on the problem, the why, the asked
    and given sizes and the units), not per frame; the ghost's lines wear the level's colour and the
    note stacks under the name and size chip (`StructurePlanView.draw_pills`).
  - *GM Events pane.* It lists the tool and, since this card, wires the selection bar too
    (`StructureTool.connect_selection(brush, pane, hints_changed)`, called by
    `PlayEvents._wire_structure_bar` once per pane), so a click on a building in play shows the
    steppers, Decorate row and style tiles as in authoring. The brush is GameMap's, shared with
    authoring: whichever pane was built or armed last owns the selection connections.
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

## Ornaments (card ornaments_ui, 2026-10-30)

A selected building's bar has a **Decorate** row (`StructureOrnamentsSection`, in the selection
bar between the steppers and the Style tiles): nine chips for procgen's ornament kinds (Ivy,
Corner turret, Buttresses, Rose window, Weathervane, Hanging sign, Flower boxes, Awning, Banners),
**Surprise me** (a seeded set of two or three for the building's theme: fort, chapel, shop or home,
from its name, family and tags; each press is another draw), **Clear**, and, while ivy is on, one
slider for how much. A click is one history entry (`StructureEditor.set_ornaments`) and the standing
building follows at once, like any edit.

- **Storage:** no new field. Two reserved `Structure.params` entries, `ornaments` (a bit mask,
  bit i for `StructureOrnaments.KIND_BITS[i]`: never reorder, a saved map stores the bits) and
  `ivy_amount` (0.2 to 1.0, absent for the default 0.55), so a set saves in `structures.json`,
  undoes, copies, restyles (`StructureEdit.kept_params` keeps the reserved names), reaches every
  peer in the "structures" live edit and moves the build key, by the paths a stepped parameter
  uses. `StructureRecipes.clamp_params` drops the names from the recipe's inputs.
- **Build:** `StructureGeometry.build_one` calls `StructureOrnaments.apply(recipe, params, seed)`,
  which adds one Ornament node per kind to that build's own copy of the recipe document
  (`ProcgenRecipesOrnaments.apply_to_document`: ground kinds read the ground storey's Facade, top
  kinds the top storey's, a vane the roof furniture; a kind the style already draws is skipped).
  Sign, awning and banners take a colour from a small jewel palette drawn from the structure's
  seed (`paint_of`, a plain integer hash, the same on every peer).
- **Greyed chips:** a ruin (a ruin recipe), a courtyard ring and a recipe with no layout take none
  (`problem_for`; the tooltip says why); a kind the building's style already draws shows on and
  locked. A kind that finds no room (a rose window on a low cottage, a turret where towers stand)
  adds nothing and its chip stays on: the build does not report it back yet.
- **Look:** the ornament node's parts take the new role `ornament` (`StructureLook.ORNAMENT`) only
  for the soft and small surface kinds (`leaf`, `leaf_b`, `cloth`, `metal`, `wood`, `glass`);
  its hard parts (a turret, buttresses) are in the wall's own kind and become `wall`, so they match
  the building. Ornament meshes keep procgen's vertex colours and draw with
  `shaders/structure_ornament.gdshader` (painterly light, both sides; `StructureMaterials.ornament`
  tints leaf green, cloth bright and metal warm gold). `StructurePaint` leaves their colour alone.
- **Tests and render:** `tests/unit/test_structure_ornaments.gd`; render jobs `ornaments_ui_look`
  (cottage, townhouse, keep, chapel before and after) and `ornaments_ui_bar` (the bar and the
  live preview through the real pane); the probe's `tile` action takes `ornaments` and `ivy`, the
  select probe's `bar` presses `ornament` and `surprise`.

### Decor plants (card plant_decor, 2026-10-30, branch `plant_decor`)

Ivy and flower boxes are plants where the library has them. procgen's ornaments emit **anchor
records** (`ProcgenOrnaments.anchors`; fields in procgen `docs/architecture_styles.md` section 8:
`kind` ivy or box, `origin`, `normal`, `along`, `up`, `width`, `height`, `depth`, `seed`,
`exclusions` [x0,y0,x1,y1] in patch coordinates); a library whose catalog carries decor assets
(`placement.scatter` false with a `mount` of `wall` or `sill` and a `size_m`: plantgen's
`Bush_IvyWall_S/M/L_v0..2`, 1.2x1.2, 1.6x2.0 and 2.2x2.6 m patches, `Bush_IvyStrip_N/W_v0..2`
(0.5 and 0.8 x 2.2 m), `Bush_IvyBand_S/M_v0..1` (1.2 x 0.5 and 1.8 x 0.6 m), and
`Flower_WindowPlanter_W08/W12/W16_v0..1`, 0.8, 1.2 and 1.6 m wide) gets a plant on each anchor.

- **Switch.** `StructureGeometry.build_one(doc, structure, decor)` (also `build`, `key_of`, `keys_of`,
  `keys_memoised`; default false) asks procgen for `soft: "anchors"` through
  `StructureOrnaments.soften(recipe)`, which sets it on every Ornament node of that build's own
  recipe copy (the player's and the style's own: `ivy_manor`'s ivy too). The blobs are then NOT in
  `meshes`. `AuthoredStructures` (and `AuthoredLoadPrep`) pass `decor` true only when
  `StructureDecor.available(root)`: the palette's `AssetStore.decor_rows` hold an ivy and a planter.
  Without them (a library lacking the assets, a scratch library in a test, `AuthoredStructures.plants`
  false) the build is what it was and procgen draws the flat blobs: that is the **fallback**. `decor`
  is part of `key_of`; `FORMAT_VERSION` is 5. Every pinned digest (`structure_digests.txt`) is made
  with decor false and is untouched; `parts.anchors`, `parts.decor` and the `placed_kinds` merged with
  the anchors' kinds (an ivy or box that found room has an anchor and no tag) are not in `digest_of`.
- **Registry.** `LibraryRegistry._serve` registers each served library's decor rows
  (`StructureDecor.rows_of(library, catalog)`) with `AssetStore.register_decor`: GLBs under the id
  `decor:<library>:<local>`, rows from `AssetStore.decor_rows(root)`; `assets_of` does not list them.
  `LibraryContracts.scatters(entry)` is false for a decor entry and `LibraryQuery.candidates` skips
  it, so no biome rule selects one (test `test_the_scatter_never_selects_a_decor_asset`).
- **Placement** (`StructureDecor.placements`, pure): ivy takes the smallest class that covers the
  patch (one variant by the anchor's seed), uniform scale from the larger of width and height
  ratio, clamped 0.75 to 1; a patch wider or taller than the largest class is tiled. The
  transform is `Transform3D(Basis(along, up, normal) * s, origin)`
  (ivy: origin at the foot centre of the patch; the asset's origin is its foot centre). A planter
  takes the class nearest the box's width, uniform scale 0.8 to 1.25, at the anchor's origin (the
  centre of the trough's top). Every placement carries `extent` (class size times scale: what it
  covers on the wall).
- **Window clearance** (card plant_decor2, 2026-10-30). The baked assets cannot honour exclusions
  (option (a): no runtime climber in tt-sim) and their leaves overhang the patch by about 0.1 m a
  side, so a patch with openings is cut around them instead: `StructureDecor.free_rects` grows each
  opening by `OPENING_MARGIN` (0.10 m since plant_decor3; 0.2 m before, which left little room, and
  a leaf may now just touch a frame) and returns the free rectangles of the
  patch (the wall beside a window as one tall rectangle, the bands above and below it as short
  ones). Each rectangle is filled on its own (`_fit`): the extent of every plant lies inside it.
  **Shapes** (plant_decor3, 2026-10-30): the ivy assets come in three shapes by patch aspect
  (`shape_of`: width over height at most 0.5 strip, at least 2.0 band, else square): the squares
  `Bush_IvyWall_S/M/L`, the pier strips `Bush_IvyStrip_N` (0.5 x 2.2) and `_W` (0.8 x 2.2), the bands
  `Bush_IvyBand_S` (1.2 x 0.5) and `_M` (1.8 x 0.6, under sills and over doors). A free rectangle
  tries the shape of its own aspect first (`shape_for`: tall narrow strips, wide short bands, else
  squares), then the others when none fits. Within a shape `_best_layout` picks the class and a grid
  of up to `MAX_COLUMNS` by `MAX_STACK` plants for the most covered extent (weighted by scale; more
  plants must cover `FIT_GAIN` 1.08 more), each shrunk uniformly to `FIT_MIN_SCALE` (0.6, was 0.4)
  at the least; neighbours are spaced evenly edge to edge and may overlap by `MAX_OVERLAP` (25
  percent), and a rectangle nothing fits in stays bare. So no plant extent meets a grown opening
  (tests `test_no_plant_reaches_an_opening_grown_by_the_margin`,
  `test_shaped_plants_never_reach_an_opening_grown_by_the_margin`). Patches with no opening tile
  with the squares as before. Measured (render job `plant_decor3_look`, round 2): window glass
  stays clear on cottage, ivy_manor, keep and townhouse; ivy leaf luminance against the bushes
  beside it 67 percent on ivy_manor and 69 on the keep (61 and 66 before the leaf colour lift).
- **Triangle cap.** `StructureDecor.MAX_TRIANGLES` (3,000, ivy and planters together):
  `AuthoredStructures._add_decor` counts each placed asset's triangles (`_triangles_of`, full-detail
  index arrays) and `StructureDecor.cap_triangles` drops plants until the total fits: ivy before
  planters (a flower box is cheap and reads as lived in), the smallest wall area first, then the
  highest, the survivors keeping their order.
- **Nodes.** `AuthoredStructures._add_decor`: one `MultiMeshInstance3D` per decor asset per
  structure (`decor_<local>`), shadows off, the mesh dressed with `WindFoliage.apply_material` for
  the asset's wind category (`climber`) and shared by every structure of the node, meta
  `wind_foliage_category`. They are children of the structure's node, so they are freed, rebuilt
  and cached with it; nothing new is stored (the ornaments mask and `ivy_amount` already are, and
  the amount reshapes the anchors' patches).
- **Cost** (core, seed 5, one decorated building, after plant_decor2): 1,536 (cottage) to 2,976
  (ivy_manor) triangles of plants against about 300 of blobs, 12 to 16 surfaces (leaf and bark per
  asset) in 6 to 8 multimeshes (before: 2,256 to 4,704 triangles, 8 to 10 surfaces, 4 to 5
  multimeshes), outside the structure's 12,000 triangle budget. `climber` wind: a low sway with a
  quick flutter, no base darkening.
- **Why the ivy was dark** (measured, plant_decor2). The leaf colours and the preset were fine. The
  painted foliage light (`wind_foliage_painted`) lights a card by N.L of its smooth normal, and the
  climber's normals were mostly horizontal (`normal_up_bias` 0.4: out of the wall), so on a vertical
  wall most cards sat in the shade half of the ramp, a flat dark green beside the bushes' upward
  normals. Fixed at the cause in plantgen (`species_wall.gd`): `normal_up_bias` 2.5 on `Ivy wall`
  (every facing catches the sun) and a leaf colour a little lighter and more yellow (0.44, 0.70,
  0.24; shade 0.16, 0.40, 0.17). Rendered mean luminance of the ivy leaves against the bush leaves
  beside them: 54 percent before (cottage) and 39 percent (ivy_manor), 57 percent after on
  ivy_manor (normals alone took the cottage to 65 percent).
- **Tests and render:** `tests/unit/test_structure_decor.gd`; render job `plant_decor_look` (the
  probe's `tile` takes `decor` false for the blobs).

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
## Determinism

Every peer rebuilds a structure from its recipe, so the build must agree across machines. The pins
(`tests/fixtures/structure_digests.txt`, procgen's `tests/expected_building_digests.txt`, the
self-check digests) were taken on Windows; card S9 (2026-10-28) checks the other platforms.

**Result, 2026-10-28 (workflow run 40805097469, branch `ci/determinism`):** all 79 pinned cases (64
procgen building and street cases, the self-check sample and bridge, 13 starter structures) equal the
Windows pins on Windows, Linux x86_64 (ubuntu-latest), macOS arm64 and macOS x86_64 under Rosetta, all
with the official 4.7.2 binary. The earlier Linux difference (2 of 57 cases) was float noise in values
that are 0 in exact arithmetic (about 1e-17 from `cos` of a quarter turn); it is gone since procgen
flushes its output (`PlantGeometry.flushed`, under 1e-9 becomes 0) and the digests round vertices to
0.1 mm (`ProcgenBuildingCases.digest`, `StructureGeometry.digest_of`, the self-check). Rule: nothing
authoritative reads building geometry bit-for-bit.

**The check.** `tools/determinism_report.gd` rebuilds every pinned case on the machine it runs on and
prints one line each: `MATCH <kind> <name> <digest> <triangles>`, or `DIFF ... got <digest> pinned
<digest>` followed by a `parts:` line; it uses the same digest functions as the tests and exits 1 on a
DIFF. Run it as `godot --headless --path <project> --script res://tools/determinism_report.gd` (`--
--parts` adds the parts line to every case, to diff two machines' output). A `parts:` line hashes each
piece of the digest (8 hex): `v` vertices, `n` normals, `uv`, `c` colours, `i` indices, `coll`
collision, `top`, `open` openings; `vq`, `nq`, `uvq`, `collq` are the same rounded to a millimetre,
`vf` is the vertices with every float under 1e-9 flushed to 0, and `tiny` counts the vertex floats
that are not 0 but under 1e-9. A raw part that differs while its `q` or `f` part agrees with the
Windows line moved by libm noise; a differing triangle count or index hash is a real divergence (a
`floor` or `ceil` flipped at a boundary: a different window count, a roof off by a bay).

**The workflow.** `.github/workflows/determinism.yml` is its own workflow: no job of `build.yml` needs
it and it needs none, so it cannot block, delay or publish a release (promote it into `build.yml` as a
job the signing jobs wait for only if the owner wants that). It starts on `workflow_dispatch` (test a
CI change with `gh workflow run Determinism --ref ci/<topic>`) and on a push to `main` that touches
`procgen`, `libraries/core/structures/`, the structure scripts, the fixture, the report or the
workflow itself. It needs the secret `PROCGEN_READ_TOKEN` (the `procgen-submodule` action) and the LFS
objects (restored from the shared Actions cache; with pointer files the core library is not served
and the report sees only five references with no recipes, 10 triangles each). Cost: about 3 minutes
on Linux and Windows, 9 on macOS (the Rosetta leg alone is 2).

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

Card building_ui2: `tests/unit/test_building_ui2.gd` (chips, counts, tile measures, the card's
words, the hint rows and their fade, the settings round trip, the live note's mapping, `nearest_legal`'s
`why`, the pane's chips and columns, `connect_selection`) and the render job
`tools/render_jobs/jobs/building_ui2.json` (probe `probes/building_ui2.gd`; a meadow with a pond,
nine captures; keeps no level, but clears the run's hint memory).
