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

`WallTool` (`tools/wall_tool.gd`, authoring only), `WallBrush` (gesture and ghost), `WallToolPane`
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

## Not yet

- Scatter (plants, rocks) is not cleared under a wall (crossings clear it; the native scatter
  reads crossings only).
- No wall in play or Events panes (the tool is authoring only); no collapse or other events.
- A fence blocks nothing and a stone wall is a surface to stand on, not a barrier tokens cannot
  cross: blocking movement is a game rule decision still to make.
- The look is the module's first pass (brick-regular, pale); the wood UVs are the copied swatch
  table (see procgen's README cleanup list).
- The procgen switch (`ProcgenCrossing.enabled`) does not affect walls: they always use the module.
