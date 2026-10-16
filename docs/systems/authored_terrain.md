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
| `utils/ground_layers.gd` | `GroundLayers` | Pure rules of the index ground: the per-map layer list (stable append, compaction, overflow past 64), the routing table by biome slot, per-layer flags and tiles |
| `scenes/terrain/ground_layer_binding.gd` | `GroundLayerBinding` | Binds the layer arrays, the routing rows, the four index maps and the broad edge on the ground material (`AuthoredTerrain.layer_binding()`) |
| `utils/ground_layer_arrays.gd` | `GroundLayerArrays` | The four `Texture2DArray`s (albedo, normal, ORM, height) of a map's layers, capacity 16 / 32 / 64 |
| `utils/ground_broad_tint.gd` | `GroundBroadTint` | The broad edge's one tint map (ground layers G4): the premultiplied tint plane, its filtered map, and the shader's CPU twin |
| `utils/ground_layer_table.gd` | `GroundLayerTable` | The old 8-slot table; nothing draws from it since G4 (its overflow and coverage helpers are still used; removed in ground layers card G5) |
| `utils/terrain_rules.gd` | `TerrainRules` | The self-dressing rules; `compose_paint`, `PAINT_CLIFF_YIELD` |
| `utils/ground_accents.gd` | `GroundAccents` | Broad patches of each biome's `ground_accents` |
| `utils/scatter_ground.gd` | `ScatterGround` | The same rules for the plants |
| `utils/height_stroke.gd`, `utils/height_brush.gd` | `HeightStroke`, `HeightBrush` | Sculpt strokes and their rules |
| `utils/ground_snap.gd` | `GroundSnap` | Plants and props follow the ground |
| `utils/scatter_rows.gd` | `ScatterRows` | `row_keys` |
| `scenes/terrain/ground_look_bake.gd` | `GroundLookBake` | The ground look's owner (child of `AuthoredTerrain`, made only when a biome of the map carries a `ground_look`): one bake per looked biome, the ground's and skirt's look tables, the grass's tuft uniforms, the sun |
| `utils/ground_look_uniforms.gd` | `GroundLookUniforms` | A merged look as uniforms: `NAMES` (the contract's r20 names), `bake_params`, `tuft_params`, `plan` (slots per biome row and layer), `ground_tables`, `ref_linear`, `opaque_mean_linear` |
| `utils/ground_mass_stamps.gd` | `GroundMassStamps` | The grass masses' shade and lift stamped into the bake |
| `shaders/ground_light_field.gdshaderinc`, `shaders/ground_light_field_bake.gdshader` | | The zones and painted light (bake only), the decode and cap (ground), the tuft shading (grass, `wind_foliage_main`) |

## Model

- Geometry: shared border vertices and grid-wide normals; it lives in the pure
  `TerrainMeshBuilder`.
- Collision: a layer-1 `StaticBody3D` with a `HeightMapShape3D` scaled by the sample step.
- Scatter row identity is X, Z and scale, never Y (`ScatterRows.row_keys`), and the generator
  reads heights on the terrain's triangles (`ScatterGenerator.triangle_height`).
- Ground layers (index form since ground layers G3, 2026-10-13; design in
  `docs/plans/2026-10-11-ground-layers/design.md`): every palette surface the map uses (the
  base at layer 0, painted surfaces, each biome's ground, cliff, scree, bed, shore and accents)
  is one layer of four per-map `Texture2DArray`s. The order is stable for a session (new
  surfaces append; painting never rebinds) and compacted at the next load; capacity grows 16,
  32, 64 (`GroundLayers.MAX_LAYERS`), so no surface or accent is dropped for want of a slot.
  The shader reads the document's own bytes as index maps (biome slots and density, R8; the
  painted surfaces' top-4 index and weight planes, RGBA8) with `textureGather` at the texel
  corner, weights each corner bilinearly, and keeps the four strongest (layer, weight)
  candidates per pixel. A routing table by biome slot (row 0 the base) names each biome's
  ground, rule and accent layers; a biome on the base surface draws as the base, and the base
  row takes the most covered such biome's rules and accents (the slot table's rule, kept for
  parity). `update_ground_region` replaces the index maps whole (native copies) and appends
  layers for a new biome or surface. Cost: `PERFORMANCE.md` "Ground shader: index layers".
- Broad edge (one tint map since ground layers G4, `GroundBroadTint`): the soft few-metre
  recolouring that fades a biome's ground into the base beside it and seats a trampled path.
  The tinted components are the biome grounds (weight 1; not a biome drawn as the base) and
  the painted built surfaces (`TRAMPLE_WEIGHT` 0.55), with no slot limit. Per sample a CPU
  mirror (RGBAF) holds them premultiplied (rgb = the sum of weight x coverage x the surface's
  linear mean colour, the last mip of its albedo; a = the sum of weight x coverage); it is
  box-filtered by `BROAD_FACTOR` 14 (3.5 m per texel) into `broad_tint_map` (RGBA half floats)
  and read with one cubic B-spline. The shader takes away the pixel's own components (each
  biome corner and painted built entry: weight x smoothstep(0.2, 0.8, its fine weight), its
  colour from `layer_tint[64]`) and recolours toward the mean colour of what is left by
  `biome_broad_strength` 0.8 x smoothstep(0, `biome_broad_full` 0.4, what is left), by
  luminance as before. So a biome tints the base beside it but not itself, a path tints the
  forest it crosses, and where two non-base biomes both fully cover their broad tints cancel
  (their border is the fine frayed edge; the slot table cast each biome's colour a few metres
  onto the other, which one premultiplied map cannot represent). Painted weight wins here
  too: the tint fades out by the same smoothstep of the pixel's painted total, so a painted
  stroke keeps its colour (painted snow beside the taiga stays white; under G3 the taiga's
  halo, recoloured by the snow's luminance, cast it cream). `update_ground_region` recomputes
  the mirror over the edited rectangle and refilters it whole (native); a table change that
  recolours a component already drawn recomputes it whole. `GroundBroadTint.tint_at` is the
  shader's CPU twin; `test_ground_broad_tint.gd` checks both and the shader's constants.
- The terrain dresses itself, always on: rock on steep faces, scree at concave feet, a grassy
  lip (`TerrainRules`, mirrored as shader constants and kept in sync by
  `test_terrain_rules.gd`; per-vertex curvature and steepness in UV2), and side projections
  below n.y 0.72.
- Each biome's ground carries broad patches of its palette `ground_accents` (`GroundAccents`:
  a lattice-texture noise mask, up to three per biome row; the plants ignore them).
- Painted weight wins, except that painted ground and built surfaces yield to the rock on
  faces (`TerrainRules.compose_paint`, `PAINT_CLIFF_YIELD`; painted cliff-role rock holds).
  Plants follow the same rules (`ScatterGround`).
- A mesh that decorates beyond the map sets `Constants.BOUNDS_EXEMPT_META` so the bounds walks
  skip it.

### Ground look

Round 20 of the treecube ground looks pass, ported in ground ship card 3b (contract:
[ASSET_PIPELINE.md](../ASSET_PIPELINE.md) section 9 "Ground look and grass masses"). A biome
whose palette entry carries a `ground_look` draws colour zones under a painted light, rims at
its accent patches and paths, shaped accent patches, and tufts and grass masses that take the
zone colour; a palette without one draws exactly today's ground and grass (checked: the bare
ground of grassland and savanna at seed 1234 renders bit-identical to main's).

- **Bake.** `GroundLookBake` gives each looked biome on the map a slot (at most
  `GroundLookUniforms.SLOTS`, 4; a fifth draws today's ground with a warning) and bakes each
  slot once into a SubViewport over the map plus 24 m at 10 texels per metre (max 2048 px,
  square-root RGBA8): the zone colour times the light over the biome's light reference
  (`ref_surface`'s `albedo_mean_linear`, measured from the texture when absent) and the light's
  luminance. Zones and light are shifted by `GroundZones.seed_offset(map_seed)`. The grass
  masses' shade and lift are stamped over it from the anchored instances (`GroundMassStamps`),
  toward the sun.
- **Several biomes.** Each biome is baked whole and on its own; the ground blends them by its
  own biome weights. Per pixel, the share of its biome components that carry a look mixes
  today's ground (variation, no cap) with the looked one (zones, cap), so a looked biome painted
  on an unlooked base, or a fire's burnt forest (no look) on a looked one, keeps each side as it
  should be. Per-sample values (brush, light reference, which layer is zoned) come from the
  layer's slot (`look_layer_slots`: `zones.layers`, else the row's ground); pixel-wide values
  (the cap, the rims' strength and colour, the path band) from the pixel's dominant looked
  component; the accent shape and accent rim width from each accent's own row. Known limits:
  a surface that is one looked biome's ground and another biome's accent is zoned everywhere;
  a ground surface shared by two looked biomes takes the first's brush; a skirt whose edge is
  painted is not zoned.
- **When.** `AuthoredTerrain.build()` rebakes (map open, resize); a re-tabling
  `update_ground_region()` (a new biome painted, a fire) re-plans the slots and bakes only when
  the set of looked biomes changed (the bake does not depend on the biome maps); an applied
  scatter regeneration restamps the masses after 0.5 s of quiet and once growth ends; a sun
  direction change (the first `DirectionalLight3D`, polled per frame) reapplies the grass's lit
  side and restamps. All of it in play and in authoring alike.
- **Grass.** The materials of a looked biome's species of kind `grass` get the tuft and mass
  uniforms, the biome's bake and rect, the sun and their own `zone_tuft_ref` (the texture's
  opaque mean). The uniforms live in `wind_foliage_main.gdshaderinc`, not the shared include, so
  `wind_foliage_burn.gdshader` gains none; `INSTANCE_CUSTOM.x` stays the burn slot. A Blender
  map's grass is never bound (every gate stays 0).
- **Accent noise.** The CPU's bare-opening noise (`ScatterMass.bare_keep`) keeps round 20's
  form, without `accent_shape.edge_scale` (the GPU's patch ramp uses it): parity means doing
  what round 20 did.
- **Dropped from the probe:** the per-fragment light field and `light_field_follow`, the unbaked
  path (`light_field_baked` 0), the dry drift, the 2B rim widths, `accent_blend_width`, and the
  mass chroma, knee, straw and rust uniforms (none in the contract).
- **Warm-up.** The bake shader is in `GraphicsWarmup.COVERED_SHADERS`. A mass MultiMesh's
  `use_custom_data` is per-instance data in the instance buffer, not a pipeline variant, so the
  warmer needs no custom-data twin (from the renderer's design; not timed, card 5 times warm-up).

## Authoring

- After a height edit call `queue_heights(sample_rect)` + `process_heights(budget)` (in-place
  vertex updates), `settle_heights()` when the edit ends, and `update_collision()` once (not
  per frame: 2.3 ms; mid-stroke the brush uses `TerrainMeshBuilder.raycast` through
  `AuthoringEditor.raycast_ground`).
- Sculpt strokes are `AuthoringEditor.begin_height_stroke()` (`HeightStroke`, rules in
  `HeightBrush`); plants and props follow through `GroundSnap` + `AuthoredScatter.move_rows`.
  The Sculpt tool's operations are in [authoring.md](authoring.md).
- After a mask or paint edit call `update_ground_region(sample_rect)`, which replaces the index
  maps, recomputes the broad weights of that rectangle and never rebuilds the material. The
  Paint tool claims up to `MapDocument.PAINT_SURFACE_LIMIT` (= `MAX_SURFACES`, 64) surfaces.

## Verification

Unit tests in `tests/unit/`: `test_authored_terrain.gd`, `test_terrain_rules.gd` (keeps
`TerrainRules` and the shader constants in sync), `test_ground_layers.gd`,
`test_ground_layer_binding.gd`, `test_ground_layers_index.gd`, `test_ground_accents.gd`, `test_scatter_ground_rules.gd`, `test_height_sculpt.gd`,
`test_authoring_sculpt.gd`, `test_ground_look.gd` (the round 20 uniforms, gates off without a
look, two biomes' slots).

## Open work

See [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work".

## History

- 2026-10-09: map and rules moved here from `AGENTS.md` Key Conventions.
- 2026-10-13: ground layers G3, the index ground: per-map layer arrays and the document's
  index maps replace the eight weight-map slots; parity with the slot table's look checked by
  today-against-G3 captures (identical where the slot table could draw everything).
