# Walls and fences

Status: first slice (2026-10-26, branch `procgen-walls`). A Wall tool in map building lays dry-stone
walls and post and rail fences along a line; they are saved in the map, follow the ground, and a
stone wall can be stood on. The look is the shared procgen module's first pass and is meant to be
refined later (docs/systems/procgen.md).

## Data

`Wall` (`resources/wall.gd`) is one wall in `MapDocument.walls` (at most `MAX_WALLS` = 64):

| Field | Meaning |
|-------|---------|
| `id` | 1..255, stable, unique; seeds the variation with the map seed |
| `kind` | `STONE`, `FENCE` or `ROW` (a street, below); `walls.json` names them `stone`, `fence`, `row` |
| `points` | the line's vertices in map XZ (2 to 64; sides at least 0.3 m, line at most 120 m) |
| `closed` | the last point joins back to the first (needs three points) |
| `height_m` | height above the ground (stone 0.4 to 2.0, fence 0.5 to 2.0) |
| `style` | palette biome id whose rock a stone wall takes ("" for the default) |

No height is stored along the line: the wall reads the document's ground when it is built.

`map.ttmap` gets a `walls.json` entry (`MapWallIO`, `{"version": 1, "walls": [...]}`), validated like
`crossings.json`: a bad wall is skipped with a warning on read and refused on write. An older build
ignores the entry and loads the map without walls. `MapDocumentIO.ENTRY_CAPS` holds its 1 MB cap.
A `"building"` entry (the kind removed in card S8, below) is skipped with a warning that names the
Structure tool, like any other unknown kind (`MapWallIO.REMOVED_KINDS`); there is no migration.

## Geometry

`WallGeometry` (`utils/wall_geometry.gd`) adapts a `Wall` to the procgen module's `stone_wall.json`
and `wood_fence.json` recipes (a polyline guide, the wall's `height` as the exposed parameter, the
document's ground as the environment). It returns mesh arrays in the map frame (`stone` or `wood`),
the collision faces and the top, safe on any thread; `AuthoredLoadPrep` builds them on a worker at
load. `WallGeometry.key_of` keys a wall by its fields, the map seed and the ground sampled every
0.5 m along its line, so `AuthoredWalls.refresh` rebuilds only the walls whose ground changed.

## Nodes

`AuthoredWalls` (`scenes/terrain/authored_walls.gd`) sits under the map root like `AuthoredCrossings`:
per wall a `Wall_<id>` node with a `Stone` or `Wood` mesh and, for stone, a `Collision`
StaticBody3D on the terrain layer (meta `tt_wall`). Tokens land on a wall's coping as on the ground;
a fence has no collision. The ground tools skip wall bodies (`exclude_of`), the drag ground cast
starts above `world_top()`. Materials: the biome's cliff rock with the palette moss on upward facets
(coping carries moss keys), the planks tinted by climate for a fence; both reuse
`AuthoredCrossings` material rules.

## Tool

`WallTool` (`tools/wall_tool.gd`, authoring and play), `WallBrush` (gesture and ghost), `WallToolPane`
(Stone and Fence tiles), `WallEditor` (`AuthoringEditor.walls`, one history entry per change).

- Drag along the ground to lay a side. A drag that starts within 0.6 m of the free end of an open
  wall of the same kind extends it (from either end); one that also ends within 0.6 m of the wall's
  other end closes the loop. So a polyline is a chain of drags.
- Shift + wheel or `[` and `]` set the height of the next new wall.
- Ctrl + click removes the wall under the cursor.
- Sculpt and water edits call `walls.follow(area)`, which refreshes nearby walls in the same history
  entry (undo refreshes them again).
- Network: a `"walls"` live edit kind (`LiveEditCodec`, `LiveEditReader`) carries the list as JSON,
  validated by `MapWallIO.parse_list`. `MapFingerprint` has a `walls` key.

## Buildings: the kind is gone (card S8, 2026-10-28)

`Wall.Kind.BUILDING` (a closed rectangle drawn from two corners, with a style of walls and roof) was
the first single building. The Structure tool replaced it (card S4, [structures.md](structures.md)
"The tool"), and card S8 deleted it: the enum value, its recipe path and style swap in
`WallGeometry` (`ProcgenRecipes.building` is no longer called from the Wall code), the rectangle
planner (`WallEditor.building_corners`, the building plan and pick), its validation and JSON in
`MapWallIO`, the brush's yaw, idle ghost, readouts and `building_style`, and the pane's Walls and
Roof rows (and the Events pane's `wall_style_selected`). `Wall.Kind` is now `STONE`, `FENCE`, `ROW`
(`KIND_NAMES` `stone`, `fence`, `row`). A street still draws its lots' footprints with the door mark
(`WallBrush._draw_footprint`), now from plain corner lists.

Old maps: a `walls.json` entry of kind `"building"` is skipped when the map loads, with a warning
("a \"building\" wall is no longer a kind (single buildings are made with the Structure tool)"), and
the rest of the map loads; the next save has no such entry. Any other kind value (wrong case, a
number, an object) is skipped the same way as before. There is no migration (the suite has no real
users): a map's old buildings are re-laid with the Building tool. A street's variation seed still
counts its kind as 3 (`WallGeometry.ROW_SEED_KIND`), so streets laid before the removal keep the
same buildings.

## Streets (2026-10-27)

`Wall.Kind.ROW` is a street of varied buildings along an open line, one record for the whole row
(procgen's `street_row.json`, `ProcgenRow`): its `points` are the street's centre line, `height_m` is
the setback of the fronts from it (1.5 to 10 m, default 3), `side` which side the buildings stand on
(0 left, 1 right, 2 both) and `seed_value` varies them (`walls.json` carries `seed` and `side` for
rows only). The buildings are never stored: `WallGeometry.row_lots` makes the lots exactly as the
recipe does (same node seed and parameters), for the ghost, the pick and the scatter clearing.

Drawn like a wall: drag along the street's line, and start the next drag at its end for a bend or a
longer street (an extended street keeps its mix; the lots before the new end do not change). A
street needs 6 m. Q and E pick the side for the next street, R mixes it afresh: over a street already
laid it remixes that one (one history entry, "Reroll row"), else it changes the seed the next street
gets (`BrushMode.rerolls()` / `reroll()`, the brush's `REROLL` action). Shift+wheel or the bracket keys
set the setback. The ghost is the street's line and each building's footprint with its door mark, the
readout says how many buildings and which side. Ctrl+click picks a street over any of its buildings.
Cost (procgen docs): about 1000 triangles a building, 13 buildings on 40 m in 48 ms. Scatter clears
under each building. Verified with the `street_tool` render job (drag, laid in two drags, remixed,
reloaded in play).

Species (2026-10-27, eleven since batch_c): a street carries a `preset` (`walls.json` `preset` 0 to
10, rows only; the index into `ProcgenStreetSpecies.NAMES`, see `StreetSpeciesInfo`) picked on
the pane's Street tiles (shown only while Street is picked): Mixed, Terrace, Guild houses, Village (fenced
yards), Cottages (low stone-walled yards), then Pueblo, Villas, Alpine, Canal, Tudor and Minka
(`docs/systems/villages.md` phase 0 has the numbering). A species replaces the lot sizes, spacing, heights, roofs and
yards, and since procgen `82073db` also each lot's walls (stone, textured, timber), roof (gable, hip, flat) and
facade style (windows, floors), all drawn from species data (procgen `ProcgenStreetSpecies`,
`recipes/species/*.json`); the setback and side stay the street's. Scatter clears under each
plot, yard included. Verified with the `street_species` render job (the tiles and a street of each
species, the village's fences visible).

Look (card S6, 2026-10-28): a street's lots wear the structures' look. `WallGeometry` splits a
row's roofs off its planks (found from each vertex's provenance path, `StructureLook.role_of_tag_path`)
into a `roof` part, which `AuthoredWalls` draws as a `Roof` mesh with the structures' roof tile shader,
and paints every lot from the street's seed (a roof tile colour and a wall lean, `StructurePaint`); the
masonry and timber use the structures' wall shader (`StructureMaterials`). Fences and stone walls
are unchanged. `docs/systems/structures.md` "Look" has the details.

Split into buildings (card S8, 2026-10-28): a click (a press that ends within 0.25 m of where it
began) on a street picks it (outlined in gold; Escape, a right click, a click on bare ground or
putting the tool down lets go), and the pane then shows "Split into buildings" and "Done". Split
replaces the street with one Structure record per lot and removes the street, as one history entry
(a group: the structures laid, then the street removed, so one undo brings the street back and
leaves no building; the live edit codec sends the two parts as a "structures" and a "walls" op).
`WallEditor.split_street(id)` does it and returns the number of buildings, or -1 with a refusal (not
a street, no building to stand in for it, too many structures for the document, `MAX_STRUCTURES`).
How a lot becomes a record, and what it loses, is in [structures.md](structures.md) "Splitting a
street". The brush's picked street is `WallBrush.selected_id` (`selection_changed`), a mode that
holds a selection takes Escape (`BrushMode.has_selection`). The Events pane (the GM's live brush)
has no Split button.

Not yet: corner plots, and a yard that is not fence or low wall (gardens, trees), plus finer
control than the species.

## Textured masonry (on by default since 2026-10-27)

`WallGeometry.textured` (a static, true) asks procgen's `textured` option of the stone wall, building
and street recipes: the courses are faces with UVs in metres (a `masonry` surface, `AuthoredWalls`
`Masonry` mesh) wearing a baked tileable set (`assets/textures/masonry/`: albedo, normal, ORM; raw PNGs,
importer keep; `MasonryTextures`, a 3 by 1.2 m tile shown 1.5 times larger, tinted from the rock's mean
colour with `WALL_MASONRY_LIFT`, a stronger lift for basalt) in place of modelled blocks. The coping
(its ends culled), the door's lintel course, yard walls' coping and the collision hull are unchanged.
The set is baked by plantgen's `tools/bake_masonry_cli.gd` (rerun it and copy the three PNGs to change
the look); the modelled blocks stay behind `textured = false`. Triangles: a building 284 (was 2220), a
mixed street of 13 on 40 m 2430 (was 11 160), a terrace 4586 (was 28 138). Judged beside the palette
boulders on alpine, badlands and forest (`wall_masonry`, `building_masonry` render jobs). The key of a
wall includes the switch, so flipping it needs a rebuild (`AuthoredWalls.refresh`).

## In play

The GM's Events pane lists the Wall brush (`EventsPane.wall_pane`, the kind tiles, its header hidden;
`PlayEvents` hints; `wall_kind_selected` sets the brush kind). A wall laid there is an ordinary live
edit (`"walls"` op) that reaches every peer, with the Undo toast the other brushes give. Verified
with the `wall_play` render job (pane, two sides laid, the toasts).

## Not yet

- Scatter clears along every side (`WallGeometry.clearance_crossings`: each side is fed to the
  crossing clearance, GDScript and the native span list alike; no C++ change). The clearance is the
  crossing's, so it also keeps 0.9 m past each end of a side.
- No wall event (a collapse or the like).
- A fence blocks nothing and a stone wall is a surface to stand on, not a barrier tokens cannot
  cross: blocking movement is a game rule decision still to make.
- The look: the module's courses and blocks (procgen look pass, 2026-10-27) with a wall tint
  (`AuthoredWalls.WALL_STONE_TINT`, per-surface `WALL_SURFACE_TINTS` for basalt and sandstone)
  judged beside the palette boulders on alpine, badlands and forest (`wall_colour` render job). The
  wood UVs are the copied swatch table (see procgen's README cleanup list).
- The procgen switch (`ProcgenCrossing.enabled`) does not affect walls: they always use the module.
- Next (2026-10-27): door and window parts, street species that pick building styles, more roofs
  and walls, interiors (deferred), wall events (the break-a-street-into-buildings action is built,
  card S8). The design
  notes and the see-through check that guards every recipe are in plantgen
  `docs/structures_design.md` section 17; the state at the end of the session is in plantgen
  `docs/agents_open_work.md`.
