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
| `kind` | `STONE` or `FENCE` |
| `points` | the line's vertices in map XZ (2 to 64; sides at least 0.3 m, line at most 120 m) |
| `closed` | the last point joins back to the first (needs three points) |
| `height_m` | height above the ground (stone 0.4 to 2.0, fence 0.5 to 2.0) |
| `style` | palette biome id whose rock a stone wall takes ("" for the default) |

No height is stored along the line: the wall reads the document's ground when it is built.

`map.ttmap` gets a `walls.json` entry (`MapWallIO`, `{"version": 1, "walls": [...]}`), validated like
`crossings.json`: a bad wall is skipped with a warning on read and refused on write. An older build
ignores the entry and loads the map without walls. `MapDocumentIO.ENTRY_CAPS` holds its 1 MB cap.

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

## Buildings (2026-10-27)

`Wall.Kind.BUILDING` is a closed rectangle of four points (`MapWallIO` refuses anything else: sides
2 to 24 m, corners square within 0.02 of the cosine), built by procgen's `building.json` (stone walls
with a level top and a door in the first side, a gable roof of planks, stone gable ends;
`height_m` is the wall height, default 2.4 m). The node has a stone mesh, a wood mesh (the roof) and
one collision body: the walls' hull split at the door plus a solid roof, so tokens stand on the roof
(the door is not walkable: there is no floor). Scatter clears over the whole footprint.

The brush draws a building from two opposite corners (press one, drag to the other; Ctrl+click
erases it, picked anywhere over its footprint). `WallEditor.building_corners(a, b, yaw)` makes the
rectangle: its first side runs from `a` along the turn (`yaw`, radians from the map's X axis) and
carries the door. Q and E turn the next footprint 15 degrees (Shift: 90) through
`BrushMode.rotates()` / `rotate()` and the brush's `TURN_LEFT` / `TURN_RIGHT` actions; before the
press an idle ghost of 4 by 3 m shows the turn and the door side, while dragging the rectangle is
filled faintly on the ground with its outline, top, posts, a door bar and the size. A drag whose
sides come under 2 m is refused with a line saying so. Verified with the `building_tool` render job
(idle ghost, turned ghost, drag, laid, save and reload, a token on the roof).

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

Species (2026-10-27): a street carries a `preset` (`walls.json` `preset` 0 to 4, rows only) picked on
the pane's Street tiles (shown only while Street is picked): Mixed, Terrace, Guild houses, Village (fenced
yards), Cottages (low stone-walled yards). A species replaces the lot sizes, spacing, heights, roofs and
yards (procgen `ProcgenRow.PRESETS`); the setback and side stay the street's. Scatter clears under each
plot, yard included. Verified with the `street_species` render job (the tiles and a street of each
species, the village's fences visible).

Not yet: breaking a street into individual buildings, corner plots, and a yard that is not fence or
low wall (gardens, trees), plus finer control than the species.

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
