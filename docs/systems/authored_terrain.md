# Authored terrain

The ground of a map built without `map.glb`, made from a `MapDocument`: chunked meshes,
collision, and a ground shader that blends the palette's surfaces and dresses the terrain by
its own shape. The long form is [../ARCHITECTURE.md](../ARCHITECTURE.md) "Authored terrain".
This doc holds the system's map and the rules the code keeps (moved from `AGENTS.md` Key
Conventions on 2026-10-09).

## Map

| File | Class | Role |
|------|-------|------|
| `scenes/terrain/authored_terrain.gd` | `AuthoredTerrain` | `create(doc)`: one `MeshInstance3D` per 10 m `ScatterChunker` cell, the collision body and the ground material; `queue_heights`, `process_heights`, `settle_heights`, `update_collision`, `update_ground_region`, `update_biome_region` |
| `utils/terrain_mesh_builder.gd` | `TerrainMeshBuilder` | Pure geometry; `raycast` |
| `utils/scatter_chunker.gd` | `ScatterChunker` | The 10 m cells |
| `shaders/authored_ground.gdshader` | | The opaque ground: tiles the palette `base_surface` with triangle-grid anti-tiling |
| `shaders/authored_ground.gdshaderinc` | | The shader body, shared by the opaque ground and the skirt |
| `shaders/authored_ground_skirt.gdshader`, `scenes/terrain/terrain_skirt.gd` | `TerrainSkirt` | The transparent skirt that fades the map into the backdrop |
| `utils/ground_layer_table.gd` | `GroundLayerTable` | The table of up to 8 layer slots |
| `utils/terrain_rules.gd` | `TerrainRules` | The self-dressing rules; `compose_paint`, `PAINT_CLIFF_YIELD` |
| `utils/ground_accents.gd` | `GroundAccents` | Broad patches of each biome's `ground_accents` |
| `utils/scatter_ground.gd` | `ScatterGround` | The same rules for the plants |
| `utils/height_stroke.gd`, `utils/height_brush.gd` | `HeightStroke`, `HeightBrush` | Sculpt strokes and their rules |
| `utils/ground_snap.gd` | `GroundSnap` | Plants and props follow the ground |
| `utils/scatter_rows.gd` | `ScatterRows` | `row_keys` |

## Model

- Geometry: shared border vertices and grid-wide normals; it lives in the pure
  `TerrainMeshBuilder`.
- Collision: a layer-1 `StaticBody3D` with a `HeightMapShape3D` scaled by the sample step.
- Scatter row identity is X, Z and scale, never Y (`ScatterRows.row_keys`), and the generator
  reads heights on the terrain's triangles (`ScatterGenerator.triangle_height`).
- Ground layers: one table of up to 8 layer slots (`GroundLayerTable`: painted surfaces,
  painted biomes' ground, each biome's cliff and scree) blends over the base from two RGBA8
  `DrawableTexture2D` weight maps.
- The terrain dresses itself, always on: rock on steep faces, scree at concave feet, a grassy
  lip (`TerrainRules`, mirrored as shader constants and kept in sync by
  `test_terrain_rules.gd`; per-vertex curvature and steepness in UV2), and side projections
  below n.y 0.72.
- Each biome's ground carries broad patches of its palette `ground_accents` (`GroundAccents`:
  a lattice-texture noise mask, slots after every other surface; the plants ignore them).
- Painted weight wins, except that painted ground and built surfaces yield to the rock on
  faces (`TerrainRules.compose_paint`, `PAINT_CLIFF_YIELD`; painted cliff-role rock holds).
  Plants follow the same rules (`ScatterGround`).
- A mesh that decorates beyond the map sets `Constants.BOUNDS_EXEMPT_META` so the bounds walks
  skip it.

## Authoring

- After a height edit call `queue_heights(sample_rect)` + `process_heights(budget)` (in-place
  vertex updates), `settle_heights()` when the edit ends, and `update_collision()` once (not
  per frame: 2.3 ms; mid-stroke the brush uses `TerrainMeshBuilder.raycast` through
  `AuthoringEditor.raycast_ground`).
- Sculpt strokes are `AuthoringEditor.begin_height_stroke()` (`HeightStroke`, rules in
  `HeightBrush`); plants and props follow through `GroundSnap` + `AuthoredScatter.move_rows`.
  The Sculpt tool's operations are in [authoring.md](authoring.md).
- After a mask or paint edit call `update_ground_region(sample_rect)`, which blits only those
  texels and never rebuilds the material.

## Verification

Unit tests in `tests/unit/`: `test_authored_terrain.gd`, `test_terrain_rules.gd` (keeps
`TerrainRules` and the shader constants in sync), `test_ground_layers.gd`,
`test_ground_accents.gd`, `test_scatter_ground_rules.gd`, `test_height_sculpt.gd`,
`test_authoring_sculpt.gd`.

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
