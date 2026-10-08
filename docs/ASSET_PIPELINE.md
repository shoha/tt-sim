# Asset Pipeline Contract

The interface between the Blender producers (`terrain-paint`, `treecube`, both at
`D:/dev/`) and this consumer. tt-sim owns this file because its loader is what breaks
when the interface drifts. The producer repos link here instead of restating it.

**Change procedure for anything on this page:** edit this file first, then the producer,
then tt-sim, then run a real round trip (see the end). Commit per repo and name this doc
in each commit message.

Detail that belongs to one side stays in that repo:

| Topic | Where |
|-------|-------|
| How terrain-paint bakes, exports collision, writes extras, bakes the flow map | `terrain-paint/docs/baking-export.md`, `terrain-paint/CLAUDE.md` "Water" |
| How terrain-paint reads Geoscatter and writes scatter instances | `terrain-paint/docs/scatter-integration.md` |
| How treecube builds meshes, textures, wind weights and biome packages | `treecube/README.md`, `treecube/docs/tt-sim-wind-weights.md` |
| How treecube paints the tileable terrain surfaces terrain-paint layers use (grass, dirt, cliff) | `treecube/docs/surfaces.md` |
| How figurine builds the avatar parts kit (style, skeleton, painting) | `figurine/docs/design.md` |
| How tt-sim loads a map and post-processes it | `docs/ARCHITECTURE.md` "Map Loading Flow", `utils/glb_utils.gd` and the `*_glb_utils.gd` siblings |
| Lighting extras, foliage AO history, texture packing measurements | `docs/lighting-and-environment.md` |
| Foliage budget, chunking, decimation measurements | `docs/PERFORMANCE.md` |

## 1. The pipeline

```
treecube presets + biomes/*.json
  -> scripts/garden.py / scripts/build_library.py
  -> Geoscatter library  D:/Blender/scatter library/_biomes_/Treecube/<biome>/
  -> painted onto a terrain-paint terrain in Blender (Geoscatter appends the assets into the map .blend)
  -> terrain-paint  Export glTF  (baked materials, -colonly collision, tt_ scene extras, flow map)
  -> map.glb
  -> tt-sim  %APPDATA%/Godot/app_userdata/TTSim/levels/<level>/map.glb
  -> GlbUtils.load_map_async  ->  collision, water, scatter MultiMeshes + wind, lighting extras, duplicate instancing
  -> FoliageDensityController applies the per-user primitive budget at runtime
```

Tokens (asset packs) take a separate path through `AssetManager` and only share the
collision-suffix convention below.

Versions this contract was last verified against: Blender 5.2 (terrain-paint requires
5.2+), Godot 4.7.1, GUT 9.5.0. Blender on this machine:
`C:/Program Files/Blender Foundation/Blender 5.2/blender.exe`.

## 2. Units and axes

- 1 unit = 1 metre, everywhere. tt-sim applies no map scale at runtime.
- glTF and Godot are Y-up. terrain-paint converts Blender Z-up transform data it writes
  by hand (the scatter extras) with translation `(x, y, z) -> (x, z, -y)`, the same rule
  on a quaternion's vector part with `w` unchanged, and scale `(x, y, z) -> (x, z, y)`.
  This was confirmed by probe against Blender's own exporter, not derived from the
  usual "-90 degrees about X" rule; a sign error silently misplaces every instance.
- Map floors sit at Y = 0 (`GameMap.configure_grid()` assumes it). Generated assets
  have their root at the origin.

## 3. Node-name conventions (case-insensitive)

Consumer: `utils/glb_utils.gd` (`COLLISION_SUFFIXES`), `utils/water_glb_utils.gd`.

| Suffix | Meaning in tt-sim | Producer |
|--------|-------------------|----------|
| `-convcolonly`, `-convco` | Convex collision, visual discarded | hand-authored |
| `-convcol` | Convex collision, visual kept | hand-authored |
| `-colonly` | Trimesh collision, visual discarded | terrain-paint generates `<object>-colonly` for every terrain on export (`export_terrain_collision`, default on) |
| `-trimesh`, `-col` | Trimesh collision, visual kept | hand-authored |
| `-water` | Material replaced by the shared animated `shaders/water.gdshader` via `material_override`; whatever material was exported is ignored | terrain-paint "Add Water Plane" (default name `Lake-water`) |
| `-flow` | Never reaches the GLB. Curves terrain-paint bakes into the flow map at export | terrain-paint |

Rules both sides rely on:

- Suffixes are matched longest first. Only the `only` variants strip the visual mesh.
- **Do not name a terrain `<name>-col`.** The name alone hides the mesh on import
  whether or not collision export is on. terrain-paint refuses to auto-generate
  collision for such an object; tt-sim renders it as nothing.
- A Blender `.001` rename breaks recognition (`Plane-colonly.001` is not collision).
  terrain-paint skips auto-collision when the target name already exists rather than
  letting Blender rename it.
- Godot's importer rewrites characters a node name cannot hold, so Blender's
  `Grass.001` arrives as `Grass_001`. tt-sim retries extras lookups with
  `validate_node_name()`; producers should not rely on dots surviving.

### Wind classification by name

Consumer: `WindFoliage.classify_category()` in `utils/wind_foliage.gd`. Runs on the
Blender object name of each scatter instance source.

| Contains | Category |
|----------|----------|
| `rock`, `stone`, `boulder` | never sways (deny list, checked first) |
| `tree`, `oak`, `pine`, `birch`, `branch`, `canopy` | `tree` preset |
| anything else | `grass` preset (deliberately the default, since Geoscatter library names carry no taxonomy keyword) |

treecube names its objects `Tree_*`, `Grass_*`, `Rock_*`, `Stone_*` to land in the right
row. The agreed extension point if the heuristic fails on real content is an explicit
`tt_wind_category` value inside `tt_scatter_instances`, read by terrain-paint via
`obj.get(...)`. Not built yet.

## 4. Scene-level glTF extras

All keys are prefixed `tt_`. terrain-paint writes them by re-opening the exported file
and patching the scene-level `extras` dict (`engine/world_lighting.write_scene_extras`).
It never enables Blender's "Export Custom Properties" (`export_extras`): that option
leaks the addon's own `terrain_paint` PropertyGroup onto every exported node. tt-sim
reads the extras only on the live `user://` GLB path (`load_glb_with_processing`), not on
`res://` PackedScene maps, and stores the parsed dict on the scene root under the meta
key `GlbUtils.SCENE_EXTRAS_META` (`"tt_gltf_scene_extras"`). Every value is untrusted
network input (maps arrive from a host peer); malformed entries are skipped, never
raised.

| Key | Value | Writer | Reader |
|-----|-------|--------|--------|
| `tt_ambient_light_color` | RGB from the World's `Background` node | terrain-paint Export glTF, "Ambient Light" option | `GlbUtils.extract_lighting_config()` into the map-defaults layer |
| `tt_ambient_light_energy` | Background strength | same | same |
| `tt_background_color` | RGB, the flat backdrop the orthographic camera sees past the map (optional) | no producer yet; tt-sim writes it for its own authored maps (`MapSourceLoader.AUTHORED_MAP_LIGHTING`) | same (`background_color`, with `background_mode` = colour) |
| `tt_scatter_instances` | Dictionary: exact Blender object name of the instance-source asset -> array of Y-up transforms | terrain-paint "Scatter Instances" (`engine/scatter_instancing.py`) | `ScatterGlbUtils.process_scatter_instances()` |

Scatter instances contract in full:

- The source asset is exported as an ordinary node with that exact name, wherever
  Blender left it, purely to carry its Mesh and baked material. tt-sim builds one
  `MultiMeshInstance3D` per species per spatial chunk from that Mesh and frees the
  original node so it does not also render once at its Blender transform.
- Every instance terrain-paint writes is built. Thinning happens at runtime through
  `MultiMesh.visible_instance_count` (see budgets below), never at import.
- Node-level extras are not part of the contract. A registered PropertyGroup's fields
  do survive into node extras when `export_extras` is on (confirmed by probe), which is
  why it stays off.
- JSON extras are fine at current sizes. If instance counts grow by an order of
  magnitude, the agreed change is a binary buffer, not a different upstream format.

## 5. Mesh attributes

### COLOR_0 carries wind weights

| Channel | Meaning | Range |
|---------|---------|-------|
| R | sway: whole-plant bend, 0 at the root, 1 at the top | 0..1 |
| G | flutter: secondary tip motion, graded across each leaf card | 0..1 |
| B | phase: desync between limbs, cards, blades | 0..1 |
| A | unused | 1 |

- Producer: treecube writes COLOR_0 on every tree, grass, and flower. Rocks never carry
  it. In Blender the R and G channels also exist as vertex groups `wind_sway` and
  `wind_flutter` for painting; export copies them back.
- Exporter: terrain-paint exports the active colour attribute as COLOR_0 with "export
  all" off (`scatter_instancing.VERTEX_COLOR_EXPORT_KWARGS` inside
  `preserve_vertex_colors_on_export()`). Blender's default mode writes an all-white
  COLOR_0 and demotes the real layer to COLOR_1, which Godot drops.
- **Blender 5.2 exporter bug:** on a multi-material mesh only the first material keeps
  the colour layer; later materials are white-filled (registry key mismatch in
  `io_scene_gltf2/blender/exp/primitive_extract.py`). Both treecube's `export.py` and
  terrain-paint's export context manager patch the registry for the duration of their
  own export. terrain-paint's `PreserveVertexColorsOnExportTest` pins the bug so the
  workaround can be removed when Blender fixes it.
- Consumer: tt-sim's wind shader reads `COLOR` only when `use_vertex_wind` is set, and
  `WindFoliage` sets it per surface from `Mesh.ARRAY_FORMAT_COLOR`. It cannot be inferred
  in-shader because Godot supplies white when a surface has no colour array, which would
  read as full sway everywhere. Without COLOR_0 the shader falls back to
  `max(vertex.y, 0)`, an unnormalised height in metres, so `sway_amplitude` is scaled by
  the mesh AABB height when the vertex path is on.
- Godot quirk: on a mesh with COLOR_0 the runtime importer enables
  `vertex_color_use_as_albedo` on the second surface's material but not the first
  (measured on 4.7.1). A raw import of a tree therefore shows tinted leaves. tt-sim's
  scatter path replaces the material and is unaffected; static props meant for raw
  import should be exported without wind weights.

### Normals and sidedness

- Leaf and grass cards are single quads drawn from both sides with authored normals
  (treecube gives cards the canopy volume's normal). Both renderers negate the shading
  normal on back faces of double-sided geometry, so without correction a card seen from
  behind shades black. treecube's Blender materials use `mix(N, -N, Backfacing)`;
  tt-sim's `wind_foliage.gdshader` variants are `cull_disabled` and undo the flip with
  `if (!FRONT_FACING) NORMAL = -NORMAL;` at the top of `fragment()`. Closed surfaces
  (bark, rock, stems) are unaffected.
- Only TEXCOORD_0 is used.

### Vertex compression (open question)

- On Godot 4.7, 23 flower assets in palette v2 each have one surface imported without
  vertex compression (surface format flag `ARRAY_FLAG_COMPRESS_ATTRIBUTES`, bit 29, clear).
  Their other surface, and every tree and grass surface, is compressed. Example:
  `alpine_meadow_summer_s1/Flower_Poppy_Alpine_summer_12` has 135 vertices on the
  uncompressed surface 0 and 160 on the compressed surface 1.
- The `.glb.import` settings are identical to the trees' (`meshes/force_disable_compression=false`),
  so the difference comes from the meshes themselves. The cause is not yet understood; a
  suspect is something in how treecube exports flowers against trees and grass.
- It matters because a different vertex layout keys a different pipeline. The graphics
  warm-up therefore warms a flower as a second representative
  (`WindFoliage.representative_assets()`), and `WindFoliage.check_layout()` warns in debug
  builds when a palette asset brings a layout neither representative has.
- Resolving the divergence at the source would let the warm-up drop back to one
  representative.

## 6. Materials and textures

- **Only baked, flat PBR materials cross the seam.** terrain-paint's live Mix-Shader
  terrain materials have no glTF form; Export glTF swaps in the baked `_Baked`
  duplicates. Geoscatter assets come from the pre-baked catalog
  (`tools/bake_biome_catalog.py`).
- **Packed ORM.** Occlusion (R), roughness (G), metallic (B) share one image referenced
  by both `metallicRoughnessTexture` and `occlusionTexture`, the convention Godot's
  `ORMMaterial3D` expects. `WindFoliage._build_shader_material()` harvests
  `StandardMaterial3D.metallic_texture` as the packed ORM; a material without one gets
  the shader's `hint_default_white`, which reads as metallic 1.0. treecube therefore
  embeds a constant ORM texture (roughness 0.85, metallic 0, occlusion 1) on every
  material.
- **Foliage AO is baked flat.** Per-asset ray-traced AO darkened every card; terrain-paint
  uses `bake_orm(bake_ao=False)` for foliage and tt-sim only multiplies ambient light by
  the AO channel anyway.
- Albedo, alpha, and normal bakes are 8-bit PNG. Normal maps are OpenGL tangent space,
  no swizzle.
- Leaf cards: glTF `alphaMode MASK`, cutoff 0.5, double-sided.
- **Water planes:** the exported material is ignored. Its `emissiveTexture` (Emission
  Strength 0, no `emissiveFactor`) is the flow map: R and G hold the flow direction in
  the plane's local Blender XY times a 0..1 speed factor, packed `v * 0.5 + 0.5`, sampled
  by the plane's UV with row 0 at v = 0, zero-flow border. Godot imports it as
  `emission_texture` with 8-bit values intact; `WaterGlbUtils.process_water_meshes()`
  lifts it onto the shared material as `water_flow_map` and flags the largest-footprint
  plane with `water_flow_present`. Spec:
  `docs/superpowers/specs/2026-09-23-water-flow-design.md`.
- **Lights** travel as `KHR_lights_punctual` and only when the light object is part of
  the export selection. Blender's "Unitless" mode is preferred; tt-sim's
  `light_intensity_scale` is 1.0 for Unitless and 0.001 to 0.01 for "Standard" exports.
  Blender's factory default scene includes a point lamp whose Watt energy blows out a
  Godot render; clear it before any throwaway export probe.
- glTF has no `WorldEnvironment`. Ambient light is the extras path above; everything
  else in the environment is Godot-side.

## 7. Budgets and scale

- **Foliage primitive budget:** per-user setting `graphics/foliage_budget`, default
  8,000,000, range 2M to 24M, applied at runtime per chunk. Not overridable per map.
  Measured reference map: 52,154 instances across 57 species.
- **Triangle targets:** treecube trees are 4k to 5k triangles by construction (pine about
  10k, the heaviest preset); grass clumps 6; rocks 80 to 1,280. terrain-paint's catalog
  decimation for legacy FloraPaint assets targets 3,000 for wood surfaces and 300 for
  rock, with `--min-island-area 0.02 --min-ratio 0.5` so twig islands are pruned rather
  than trunks collapsed. Leaf cards are never decimated.
- **Game scale.** tt-sim's play camera is orthographic, 13.85 m of view height on a
  1080 px viewport at the home zoom (about 78 px per metre), 22 degrees down, 45 degree
  azimuth, zoom range 2 to 20 m. A 0.95 m leaf card is 74 px tall. Judge textures and
  silhouettes at that scale (`paintkit/src/paintkit/gamescale.py`, `scripts/generate.py
  --render-game`, `tools/texture_sheet.py`), not in close-ups.
- Dense card foliage costs alpha-tested fill more than primitives; see
  `docs/PERFORMANCE.md` before optimising either side.

## 8. Round-trip verification

Nothing on this page counts as done until a real file crosses the seam.

Producer-side probes (headless Godot, no GPU needed for structure):

- `treecube/tools/godot_probe.gd`: what Godot's importer makes of a GLB (surfaces,
  attributes, material flags).
- `GLTFDocument.append_from_buffer()` + `GLTFState.get_json()` from a headless Godot
  process reads extras back exactly as tt-sim will.
- terrain-paint's `tests/run_tests.py` covers the export context managers, collision
  export, scatter instancing, world lighting, and the flow bake.

Consumer-side checks:

- `tests/test_glb_lights.tscn` and the GUT unit tests under `tests/unit/` for the loader
  pieces (`test_*glb*`, `test_wind_foliage*`, `test_scatter*`).
- Visual behaviour (water, wind, tint) needs a real GPU session: the validation bridge
  (`game_reload`, `game_state`, `game_interact`) or `tools/render_map.tscn`.
- Instance totals must agree three ways: what `rebuild_map_assets.py` prints, the GLB
  extras, and the `MAP_LOADED` line `tools/render_map.gd` prints after loading.

The baked FloraPaint catalog on disk
(`D:/Blender/scatter library/_biomes_/Baked/CaseySheep/FloraPaint/`) has been through
three post-bake passes (rock decimation to 300, wood decimation to 3,000 with island
pruning, 99-card grass thinning; see `docs/PERFORMANCE.md`). Each touched
`biome_NN.instances.blend` has a `.pre_decimate.bak` sibling holding the pristine state,
which the decimation tool never refreshes. **Re-baking the catalog undoes all three
passes; re-run them afterwards.** If a map still shows the old tree counts (37k/55k/77k
triangles), trunk-less trees or 99-card clumps, run terrain-paint's
`tools/refresh_map_from_catalog.py` against it. Judge any decimation by island count,
largest-island survival and surface area, never by triangle count alone.

Two export traps that produce a plausible-looking but wrong GLB, both hit on 2026-09-17:

- If Geoscatter fails to import at Blender startup, terrain-paint's export prints only
  `Warning: Scatter Instances: Geoscatter isn't installed`, exits 0, and writes a GLB
  with no scatter objects. Check the export log for that warning and count the scatter
  source nodes in the GLB before installing.
- A map whose terrain bakes are unpacked GENERATED images loses their pixels on a
  background `save_as_mainfile` (the UI save does not), so a refreshed map exports flat
  black terrain. `refresh_map_from_catalog.py` packs unsaved images first; still compare
  the terrain PNGs of a new export against the installed GLB before installing.

Pushing a producer change into an existing level:
`blender --background map.blend --python tools/rebuild_map_assets.py -- out.glb`
(treecube), then copy `out.glb` over the level's `map.glb`. Keep the previous export
beside it (`map.glb.pre-<change>-<date>`) until the new one is verified in-game.

Golden fixtures: treecube's built-in palette (section 9) is committed under
`assets/palette/` and is the first real producer output with a GUT test that loads it,
`tests/unit/test_palette_builtin.gd`: all 180 assets resolve through `PaletteLibrary`, the
wind categories and COLOR_0 presence match the manifest, every swaying surface harvests
albedo and ORM, and one species per biome builds chunks through `build_scatter` (about
0.8 s headless). terrain-paint map exports still have no committed fixture; for them the
manual round trip above remains the gate.

## 9. Built-in palette (treecube -> tt-sim, for in-game map authoring)

A second path from treecube into tt-sim that bypasses Blender maps entirely: treecube
builds a palette of assets, ground surfaces and placement rules that ships inside the
game, and tt-sim's authoring mode places from it. Design:
`docs/superpowers/specs/2026-09-26-in-game-map-authoring-design.md` (local, gitignored).
Status: contract agreed 2026-09-26; the first full palette (8 summer biomes, 180 assets,
14 surfaces, treecube `ad44aa5`) is committed in tt-sim under Git LFS; authoring mode is
in progress.

Producer: `treecube/scripts/build_palette.py` (runs `scripts/garden.py --palette` per
biome and season, sequentially). Consumer: `utils/palette_library.gd` (`PaletteLibrary`),
whose `resolver()` feeds `ScatterGlbUtils.build_scatter()`.

### Layout

```
<palette root>/                 res://assets/palette/ in tt-sim
  palette.json
  assets/<package id>/<object>.glb
  surfaces/<surface>/<surface>_{albedo,normal,orm,height}.png
  thumbnails/<package id>.jpg
```

`<package id>` is `<biome>_<season>_s<seed>` (treecube's `package_basename`). A palette
holds one seed per (biome, season). `<surface>` is the treecube surface preset name
(`grass_alpine`, `sand_red`), not the surface kind (`grass`, `sand`) those presets belong
to.

Asset GLBs follow treecube's per-asset output contract (section 5 and 6 of this doc and
treecube's README "Output contract"): one node named `<object>`, one mesh, COLOR_0 wind
weights on everything that sways, packed constant ORM, two-sided cards. Rocks, deadwood
and cacti carry no COLOR_0.

### `palette.json` (format 1)

```
{
  "format": 1,
  "palette_version": "<treecube commit short sha>",
  "surfaces": {
    "<surface>": {"albedo": "surfaces/<surface>/<surface>_albedo.png", "normal": ...,
                  "orm": ..., "height": ...,
                  "tile_m": <world size of one texture repeat, metres>,
                  "kind": "<treecube surface kind: grass, cliff, gravel, dirt_road, ...>",
                  "role": "ground" | "cliff" | "built"}
  },
  "biomes": [
    {
      "id": "<package id>",
      "biome": "<biome key>", "season": "<season>", "seed": <int>,
      "name": "<plain biome display name, no season>", "climate": "<cold|temperate|warm|dry>",
      "thumbnail": "thumbnails/<package id>.jpg",
      "ground_surface": "<surface>",
      "cliff_surface": "<surface with role cliff>",
      "scree_surface": "<surface with role ground>",
      "water_bed_surface": "<surface with role ground>",
      "shore_surface": "<surface with role ground>",
      "ground_accents": [{"surface": "<surface with role ground>", "coverage": <0..1>,
                          "scale_m": <patch size, metres>}, ...],
      "path_surfaces": ["<surface with role built>", ...],
      "species": [
        {
          "key": "<species key>", "kind": "<tree|grass|flower|rock|deadwood|...>",
          "size_class": "<large|medium|small|ground>",
          "density_per_m2": <target instances per m2 for this species>,
          "min_spacing_m": <float, 0 = none>,
          "slope_max_deg": <true surface angle>,
          "scale_spread": <0..0.9, symmetric +-r>,
          "scale_floor": <float or null>,
          "yaw_random_deg": <float>,
          "align": "upright" | "normal",
          "pattern": {"influence": <0..1>, "scale_influence": <0..1>,
                      "geoscatter_pattern": {<s_pattern1_* settings, prefix stripped>}} | null,
          "clump": {"parents_per_m2": ..., "radius_m": ..., "transition_m": ...,
                    "children_spacing_m": ...} | null,
          "near":  [{"species": "<key>", "distance_m": ..., "transition_m": ..., "influence": <0..1>}],
          "avoid": [ ...same shape... ],
          "assets": ["<asset id>", ...]
        }
      ]
    }
  ],
  "assets": {
    "<asset id>": {"file": "assets/<package id>/<object>.glb", "node": "<object>",
                   "wind_category": "tree" | "grass" | "",
                   "size_class": "...", "dimensions_m": [x, height, depth]}
  }
}
```

Field notes:

- `dimensions_m` is Y-up, in metres: `[x, height, depth]`.
- `min_spacing_m` is the clump's children spacing for a clumped species (the class limit
  distance never applies to clumped layers) and the class limit distance for a random
  species.
- `name` is the plain biome display name; the season is its own field.
- Surface `role` says what the surface is for (added 2026-09-26, phase 3; same format 1,
  since every field is optional to the consumer):
  - `ground`: soft ground under a scatter and at cliff feet (treecube's Ground catalog:
    grass, dirt, sand, gravel, snow, moss, ... and their biome variants), sampled top-down.
  - `cliff`: rock for steep faces (treecube's Rock catalog: `cliff`, `cliff_basalt`,
    `cliff_sandstone`), sampled sideways (biplanar or triplanar, v up the face). Tiles
    keep their beds near-horizontal so a bed line carries across a projection seam.
  - `built`: walkable paving an author paints as paths and courtyards (`cobblestone`,
    `flagstone`, `dirt_road_packed`, `stone_tiles`, `planks`, and biome path variants
    such as a caliche track or sandstone flags), sampled top-down. They
    carry no direction (a painted path runs any way through world-space UVs), which is
    why the rutted, verged `dirt_road` is not in the palette. Walls, roofs and interior
    floors are never palette surfaces.

  tt-sim's Paint tool (P3-6) groups its tiles by role and reads it as behaviour: painted
  `ground` and `built` surfaces cover walkable ground only and yield to the automatic rock
  on steep faces (a path stops at a ledge); painted `cliff` surfaces apply anywhere
  (restyling a face); `built` and painted `cliff` clear the plants under them.

  `kind` is the treecube surface kind the preset belongs to (`cliff` for
  `cliff_basalt`), for grouping in the UI; tt-sim never branches on it.
- `cliff_surface` is the surface the automatic dressing puts on a biome's steep faces
  (tier edges); `scree_surface` the loose ground it puts at their feet. The producer's
  per-biome defaults, judged at game scale on 75 degree tier faces (treecube
  `docs/surfaces.md` "Cliffs, scree and paths in tt-sim"):

  | Biome | `cliff_surface` | `scree_surface` |
  |-------|-----------------|-----------------|
  | temperate_forest, birch_woodland, grassland_meadow, wetland_riparian | `cliff` | `gravel` |
  | alpine_meadow, boreal_taiga | `cliff_basalt` | `gravel` |
  | savanna, rocky_badlands | `cliff_sandstone` | `gravel_sandstone` |

  A painted `cliff` surface always wins over these (phase 3 decision); the biome only
  supplies the default. Painted ground and built surfaces do not cover a face (above).
- `water_bed_surface` and `shore_surface` (added 2026-09-27, phase 4 water; optional) are
  the surfaces the consumer's automatic wet dressing puts under a river or pond's water
  (the bed; painted ground and built surfaces yield to it, so a path stops at the water)
  and on the wet band of bank just above it (the shore: a line along the waterline with
  drifts reaching a couple of metres out, fading into the biome ground). Both are `ground`
  surfaces; the shore should differ from the biome's `ground_surface` to show (the same
  surface draws nothing extra, and the consumer still darkens the wet line). A palette
  without them works: the consumer has its own per-biome defaults, which a producer's
  values replace when present:

  | Biome | `water_bed_surface` | `shore_surface` |
  |-------|---------------------|-----------------|
  | temperate_forest, birch_woodland, boreal_taiga, grassland_meadow, wetland_riparian | `riverbed` | `mud` |
  | alpine_meadow | `riverbed` | `gravel` |
  | savanna | `riverbed` | `sand` |
  | rocky_badlands | `gravel_sandstone` | `gravel_sandstone` |
  | any other biome key | `riverbed` | `mud` |

  (tt-sim's first judged values, `PaletteLibrary.WATER_SURFACE_DEFAULTS`; a default the
  palette lacks as a ground surface is dropped.) Species carry no water field yet: the
  consumer treats a few species keys as water-edge plants (reeds and rushes stand in the
  shallows, willow, poplar and ferns gather on the bank) and keeps cacti off it; a
  producer field for that is future work.
- `ground_accents` (added 2026-09-27, phase 3; optional) are broad patches of other
  ground surfaces the consumer mixes into the biome ground in the shader, so a biome
  floor is not one field of one tile (a temperate forest read as one flat brown in game,
  where the Blender maps it came from carry moss, grass and bare patches). Each entry:
  `surface`, a surface with role `ground` other than the biome's `ground_surface`;
  `coverage`, the share of the biome ground the patches cover (0..1; the entries of one
  biome sum to at most 0.6, so the biome ground stays the ground); `scale_m`, the
  typical patch size across, metres (a noise feature size, 2 to 20 m). Patches are
  soft-edged and irregular; how the mask is made (noise type, edge width, a height
  blend at the edge) is the consumer's choice, as long as the covered share is about
  `coverage` over a large area and a patch is about `scale_m` across. Entries are in
  priority order: a consumer with a layer budget draws the first ones and drops the
  rest. Accents belong to the ground: they appear only where the biome ground would
  show, so the automatic cliff and scree and every painted surface cover them, and
  the plant scatter does not read them. Empty (`[]`) where a biome's ground wants no
  accents; a season whose `ground_surface` differs from the all-year one (winter
  snow) gets no accents unless the producer lists some for it.
- `path_surfaces` (added 2026-09-27, phase 3; optional) is an ordered list of `built`
  surfaces the Paint tool shows first on this biome: the biome-specific path variants
  (a pale caliche track and sandstone flags on red sand, where the generic dirt track
  vanishes and grey flagstone looks pasted on) and the generic ones that suit the
  biome. It orders, it does not filter: every built surface stays paintable on every
  biome, in file order after the listed ones.

  The producer's per-biome values, judged at game scale (treecube `docs/surfaces.md`
  "Ground accents and path variants in tt-sim"), are listed there; the contract
  holds only the rules.
- Crossings (tt-sim phase 4b, 2026-09-27; no new field): the consumer builds plank bridges
  and stepping stones procedurally from existing surfaces. It samples the `built` surface
  named `planks` for the wood (its albedo's board layout is read as clean runs between the
  painted joints, `CrossingGeometry.WOOD_SWATCHES`, so a rebuilt `planks` texture with a
  different board layout needs those rectangles re-measured) and each biome's
  `cliff_surface` for the stones, tinted by the biome's `climate`. A palette without
  `planks` draws untextured wood; one without the biome's cliff falls back to `cliff`.
  Since P4b-3 stepping stones in a `temperate` or `cold` climate also sample the ground
  surface named `moss` on their upward facets (a palette without it gives bare stones).
  Still no new field.
- `geoscatter_pattern` holds Geoscatter's `s_pattern1_*` settings verbatim with the
  prefix stripped (texture dict, sample method, influences, revert flags), minus the
  datablock plumbing (`allow`, `texture_ptr`, `texture_is_unique`). tt-sim's
  `ScatterGenerator` reads only the noise's feature size and shape from it:
  `texture_dict.scale`, `texture_dict.mapping_scale[0]`, `texture_dict.detail` and
  `texture_dict.contrast` (noise frequency = mapping_scale * scale, octaves = detail + 1),
  each falling back to treecube's defaults (2, 0.1, 1, 2) when absent. Everything else
  in it is kept for calibration only. The share removed and the shrink are the
  top-level `influence` and `scale_influence`.

Rules both sides rely on:

- **Rules are targets, not Geoscatter requests.** Densities, spacing and slope are what
  the scatter should deliver (what treecube's `audit_biome.py` measures against), never
  the compensated values treecube writes into Geoscatter presets (`spacing_request`,
  yields, `slope_setting`). tt-sim's generator is its own and calibrates to targets.
  One deliberate exception (P3-7): in game every `slope_max_deg` is read 10 degrees
  higher (`ScatterPlan.SLOPE_ALLOWANCE_DEG`), because tt-sim's automatic rock rule already
  clears steep ground and the Blender-tuned limits stripped trees off gentle raised hills.
  Producers keep writing the true angle.
- **Asset id** = `<package id>/<object>`, i.e. `<biome>_<season>_s<seed>/<object>`;
  the package id is also `biomes[].id`. An id is never reused for a different
  asset. Saved levels reference ids; a level whose id no longer resolves loads without
  those instances and warns, never fails.
- **`wind_category` is explicit.** tt-sim never runs `WindFoliage.classify_category()`
  on palette assets: palette ids contain biome names (`birch_woodland`) that the
  keyword heuristic would misread. This is the explicit category section 3 anticipated.
- **Same version required.** Peers must run the same game build to join (decided
  2026-09-26), so host and clients always hold the same palette. `palette_version`
  exists for diagnostics and for saved levels, not for negotiation.
- Everything read from `palette.json` is validated like network input (it ships with
  the game, but the same loader reads authored map documents that arrive from peers).
- **Surface roles degrade, never fail.** The producer rejects a palette whose surface
  lacks a `kind` or a known `role`, or whose biome names a ground, cliff or scree surface
  that is missing or has the wrong role (`palette_problems()`). The consumer
  (`PaletteLibrary`) is lenient, so an older palette still loads: a missing `role` is
  `ground` silently and an unknown one warns and is treated as `ground`; a missing
  `kind` is `""`; a missing `cliff_surface` falls back silently, and one that names an
  absent or non-cliff surface warns and falls back, to the first `cliff` surface in file
  order (`cliff` in treecube's sorted output) or `""` when there is none; a missing
  `scree_surface` is `""` (the foot keeps the biome ground), and one that names an absent
  or non-ground surface warns and becomes `""`. A missing `water_bed_surface` or
  `shore_surface` takes the consumer's default for the biome key silently (`""` when the
  palette lacks it as a ground surface); one that names an absent or non-ground surface
  warns and takes that default.
- **Accents and path surfaces degrade, never fail.** The producer rejects a
  `ground_accents` entry whose surface is missing, has a role other than `ground` or
  is the biome's own `ground_surface`, whose `coverage` is outside 0..1 or whose
  `scale_m` is not positive, and a biome whose coverages sum over 0.6; and a
  `path_surfaces` name that is missing, listed twice, or has a role other than
  `built` (`palette_problems()`). The consumer is lenient: a missing field is `[]`
  silently; an accent entry that is malformed or names an absent or non-ground
  surface warns and is dropped, coverage is clamped to 0..1 and a missing or
  non-positive `scale_m` becomes 6; a `path_surfaces` name that is absent or not
  `built` warns and is dropped, and a duplicate is ignored.
- Budgets: palette assets obey section 7's triangle targets; the foliage budget applies
  unchanged, since palette scatter builds the same chunked MultiMeshes.

### Import path (decided 2026-09-26, measured on Godot 4.7.1)

**Asset GLBs go through Godot's editor import, and `PaletteLibrary` loads the imported
PackedScene with `ResourceLoader`.** An exported pack holds only the imported `.scn` and
the `.import` remap, never the raw `.glb`, so a `FileAccess` + `GLTFDocument` loader passes
every editor test and finds nothing in a shipped game. Checked by exporting the real
project (`godot --headless --path . --export-pack "Windows Desktop" <tmp>.pck`, which
needs no export templates) and running a probe with that pack as the main pack
(`godot --headless --path <empty dir> --main-pack <tmp>.pck --script <probe>`):
`FileAccess.file_exists` on an asset `.glb` is false, `ResourceLoader.exists` is true,
`palette.json` is present, all 180 assets resolve, all 56 surface maps load, and
`build_scatter` of one species per biome harvests albedo, ORM and vertex wind on every
swaying surface. The alternative, `importer="keep"` in the sidecar, does ship the raw
`.glb` (checked in a scratch project) and was not needed.

Committed `.glb.import` sidecar settings (anything unlisted is Godot's default):

| Setting | Value | Why |
|---------|-------|-----|
| `gltf/embedded_image_handling` | 3, Embed as Uncompressed | See below. The default (1) extracts every texture as a PNG next to the GLB, about 450 extra files per palette. |
| `meshes/generate_lods` | false | Auto LODs decimate leaf cards (section 7: cards are never decimated). |
| `meshes/create_shadow_meshes` | false | Parity with the runtime path, which builds none; the gain on 4k-triangle trees is small and the interaction with the wind vertex shader is unmeasured. |

Why uncompressed embedding rather than VRAM-compressed, mipmapped textures: a game-camera
screenshot pair of temperate_forest's 25 species placed through `build_scatter`
(orthographic, 13.85 m view height, 22 deg down, wind amplitude 0) showed Basis Universal
embedding (VRAM-compressed, mipmapped) fading the small flowers at home zoom: daisies turn
grey and bluebells lose their blue entirely, because their petals are a few texels wide
and alpha-to-coverage cutout loses them in the lower mips. Treecube's flower atlases also
carry black RGB under transparent texels (grass atlases are colour-bled), but dilating
that colour and regenerating mipmaps did not bring the flowers back, so coverage is the
cause, not colour bleed. With embedding 3 the imported textures are the same unmipmapped
RGBA8 `ImageTexture`s the runtime `GLTFDocument` load produces (and that every `user://`
map already renders with); the pair differs only in scattered single pixels on swaying
foliage and shadow edges (1.0% of pixels against a 0.1% run-to-run floor, consistent with
the wind clock's phase at capture), while static rocks and logs are pixel-identical. Mipmapped foliage is worth revisiting once the
alpha cutout keeps its coverage in lower mips (mip-aware alpha scaling in
`wind_foliage.gdshader`, or coverage-preserving mips from the producer); switching is then
a sidecar change (`embedded_image_handling=2`) plus the matching line in the test.

Measured for the choice:

- Structure, all 180 assets loaded both ways: identical surface counts, vertex counts,
  COLOR_0 presence (on every tree and grass surface, on no rock, stone, log or cactus),
  material transparency and cull mode. No palette asset carries a normal map. The
  harvest matches: albedo and the constant ORM (1.00, 0.85, 0.00) on all 191 swaying
  surfaces, `use_vertex_wind` true on each. Godot's COLOR_0-as-albedo quirk (section 5)
  appears identically in both paths and is irrelevant, since the wind material replaces it.
- Load time, temperate_forest (25 assets), cold process: 37 ms imported versus 62 ms
  runtime parse headless; `build_scatter` of the whole biome in a real Vulkan window
  126 ms versus 153 ms. All 180 assets from the exported pack: about 230 ms.
- Exported pack delta for the whole palette: +76.0 MB (65.4 to 141.4 MB): asset `.scn`
  files 22.2 MB (the raw GLBs are 26 MB), surface textures 53.2 MB (albedo 19.6, normal
  19.6, ORM 9.8, height 4.3), thumbnails 0.3 MB, `palette.json` and sidecars 0.5 MB.
- Reimporting the 180 GLBs: about 10 s headless.

Surface maps are imported as textures (`surfaces/*/*.png.import`), all with mipmaps:
albedo VRAM compressed at high quality (BC7: the ground is the largest thing on screen, so
it gets the better format at twice BC1's size; not yet A/B judged against BC1 in a map),
normal VRAM compressed as a normal map (BC5, two channels, Z rebuilt), ORM VRAM compressed
at normal quality (BC1; low-frequency lighting data, half the size of BC7), height
lossless (the 16-bit PNG loads as 8-bit greyscale, kept exact for any height-based blend
at the same 1 byte per texel BC7 would cost) with `detect_3d/compress_to=0` so an editor
session cannot switch it to VRAM compression. Thumbnails keep the default (lossless, no
mipmaps). The authored ground shader (`shaders/authored_ground.gdshaderinc`) samples the
surface maps; see `docs/MAP_AUTHORING.md`.

**Refreshing the palette:** copy treecube's output over `assets/palette/`, keep the
existing sidecars, write the three sidecar settings above into a `.glb.import` for every
new GLB before the first import (otherwise Godot extracts its textures), then
`godot --headless --import --path .`. treecube's `build_palette.py --install` replaces the
`assets/`, `surfaces/` and `thumbnails/` directories wholesale and so deletes every
committed sidecar: restore them straight after with
`git checkout -- ":(glob)assets/palette/**/*.import"` and check `git status` shows only
binaries and `palette.json` changed (palette v2, 2026-09-26, was installed this way).
Before committing, `git lfs status` must list every GLB/PNG/JPG as LFS and only
`palette.json` as Git. Changing a setting in an existing sidecar does not
trigger a reimport on its own; delete the matching `.godot/imported/*.md5` first.
`tests/unit/test_palette_builtin.gd` checks the sidecars and fails on a missed one.

## 10. Avatar kit (figurine -> tt-sim, for player avatar tokens)

A third path: figurine (`D:/dev/figurine`, a Blender 5.2 extension) generates a kit of
painted, skinned parts that ships inside the game, and tt-sim builds a player's avatar
token from it by a small recipe that every peer rebuilds from its own copy of the kit, the
way a `.ttmap` is rebuilt. Design and style: `figurine/docs/design.md`. Status: contract
drafted 2026-10-06 from the avatar probe; the foundation card (2026-10-06) added the
secondary chains, the `build_plus` blend shape with plus stance variants, part layers and
the per-slot triangle caps (tt-sim `2d7aa3e`,
`tools/render_jobs/probes/avatar*.gd`); humans only. Produced: the first kit slice
(figurine e12e8bb, 2026-10-06: `body_a`, `head_round`, `hair_bun`, 21 face cells, two
stances; a figure is 3,908 triangles; its kit.json says `kit_version` `0.1.0+b4f9f4a`);
card B2a (2026-10-06) added the first garments, `top_longsleeve` (slot `top`, now
optional) and `hat_witch` (slot `hat`, `hair_mode` `trimmed`), and the hair's back locks
on the `HairBack` chain; card B2b (2026-10-07) added `skirt_skater` (slot `bottom`, now
optional) and `cloak_trailing` (slot `cloak`), the eight skirt chains (117 bones) and the
drape of the acceptance poses. The skater skirt failed review and is held out of the
shipped kit (figurine `kit.EXPERIMENTAL_BUILDERS`, 2026-10-07) until the bottoms-family
card redesigns it; the skirt chains stay in the skeleton. The readability card
(2026-10-07) rebuilt the head from orthographic blueprints (wider, deeper, a wedge nose),
enlarged the eyes, brows and mouths in the face sheet, cut the body's ink to edges and
seams and raised the head to 0.33 m. The look's rules are in
`figurine/docs/style_sheet.md`.
Consumed: tt-sim `8c30bef` (2026-10-06) loads it, builds figures from recipes on a real
map and from an exported pack; not yet a token (no `BoardTokenFactory` path, no network
sync, no builder UI).

Producer: `figurine/scripts/build_kit.py`. Consumer: `utils/avatar_kit.gd` (`AvatarKit`,
with `avatar_recipe.gd`, `avatar_palette.gd`, `avatar_proportions.gd`, `avatar_shade.gd`)
and `shaders/avatar_figure.gdshader`, which assemble a figure under one `Skeleton3D`.
Install: `tools/install_avatar_kit.gd` copies figurine's `out/kit/` into
`assets/avatar_kit/` and writes the sidecars before the first import. It refuses, copying
nothing, a kit whose `build_report.json` has a `"check"` other than `"full"` (`"fast"`,
`"incremental"` or `"fast+incremental"` mark iteration builds that must never ship); a report
without the field (builds before it) still installs.

### Layout

```
<kit root>/                     res://assets/avatar_kit/ in tt-sim (Git LFS)
  kit.json
  skeleton.glb                  the armature alone, plus the stance clips
  parts/<slot>/<part id>.glb
  faces/face_sheet.png          eye, brow, mouth and mark cells in face space
  thumbnails/<part id>.png
```

Slots, first set: `body`, `head`, `hair`, `hat` (added by the foundation card; the head
stack's outer layer), `top`, `bottom`, `shoes`, `cloak`, `gear`. A
figure has exactly one `body` and one `head` and at most one part in each other slot;
`gear` may repeat with different attach bones.

Required and optional slots (card B1, 2026-10-06; kit.json `slots`, below):

| Slot | Optional | Notes |
|------|----------|-------|
| `body`, `head`, `hair` | never | always filled when the kit has a part for the slot |
| `top` | yes (card B2a, 2026-10-06) | the body carries a complete base outfit (a tee, shorts, socks and sneakers), so a figure with no `top` part wears the body's own tee; a top part replaces it (hiding the body regions its sleeves cover) |
| `bottom` | yes (card B2b, 2026-10-07) | without one the body wears its own shorts; the shipped kit currently has no part here (`skirt_skater`, a mid-thigh bell on the eight skirt chains, is held back for the bottoms-family card), so `parts_by_slot` has no `bottom` key and every figure wears the shorts |
| `shoes` | no, for now | required while the kit has no parts there, which leaves them to the body's own sneakers; when parts ship, they will go optional the same way as `top` |
| `hat`, `cloak`, `gear` | yes | a figure may leave them empty |

A required slot is filled from the kit whenever the kit has a part for it: a recipe that
omits it, names `null` or names a part the kit lacks gets the slot's first part, and the
consumer notes the fallback. An optional slot holds a part only when the recipe names
one the kit has: omitted or `null` means none, and a part the kit lacks also means none
(noted), never a substitute.

### Hats and hair

A hat says what the hair under it does, by `hair_mode` on its kit.json entry:

- `full`: the hair is worn whole (a hat built to sit over every hair, a circlet);
- `trimmed`: the hair is worn without its `hat_trim` surfaces;
- `hidden`: no hair is shown under the hat.

Every hair part lists `regions` (its surfaces, each named by its material, as the body's
are) and `hat_trim`, the regions a trimming hat leaves out (possibly empty: a short cut
that fits under any hat). The consumer drops those surfaces the way it drops the body
regions a part `hides`. A hair part without `hat_trim` (a kit from before this rule) is
hidden under a trimming hat, and a hat without `hair_mode` counts as `hidden`, so a
mismatch never clips. The producer guarantees the layer rule (below), both ways, for
every hat over every hair in the kit with the hat's mode applied (figurine's kit build
assembles each hat over each hair through `part.worn` and checks every stance and
acceptance pose at every proportion corner), and that a hat is a closed shell but for
its mouth (at most one boundary loop once its surfaces are welded), so no hair shows
through a missing face. The first kit's `hair_bun` has the regions `hair` (cap, locks
and the back locks that fall to the nape) and `bun` (the bun and its tie), and
`hat_trim: ["bun"]`; the first hat, `hat_witch` (card B2a), is `trimmed`.

### Skeleton

- One armature for the whole kit (117 bones since card B2b, 2026-10-07: 72 body,
  finger and helper bones plus 45 secondary chain bones, below; 105 from the foundation
  card to B2a). Body and
  finger bones are named as Godot's `SkeletonProfileHumanoid` names them: `Hips`, `Spine`,
  `Chest`, `UpperChest`, `Neck`, `Head`, `LeftShoulder`, `LeftUpperArm`, `LeftLowerArm`,
  `LeftHand`, `LeftUpperLeg`, `LeftLowerLeg`, `LeftFoot`, `LeftToes`, and per hand a
  two-bone thumb (`LeftThumbMetacarpal`, `LeftThumbProximal`), a two-bone index finger
  (`LeftIndexProximal`, `LeftIndexIntermediate`) and a two-bone block that carries the
  middle, ring and little fingers together under the middle finger's names
  (`LeftMiddleProximal`, `LeftMiddleIntermediate`); the profile's distal, ring and little
  bones are not used. The `Right` mirrors of all of them. Metres, +Z up in Blender as
  everywhere in this doc; the rest pose is an A-pose (arms about 45 degrees down, palms
  toward the thighs, thumbs forward), the figure standing on the origin facing -Y in
  Blender (+Z in glTF; with no token rotation tt-sim's play camera sees its left side).
  `kit.json`'s `skeleton` block lists each bone's parent, head, tail and `flex_axis` in
  glTF space, so the consumer has the bone axes without parsing a GLB.
- Joint frames (the bone roll). Every bone's rest orientation means the same thing: local
  Y is the bone's own axis (head to tail) and rotation about it is twist; local X is the
  flex axis, a positive rotation about it is flexion (spine, neck and head pitch forward,
  the clavicle lifts, upper arm and thigh swing forward, elbow, knee and fingers bend,
  wrist bends toward the palm, foot and toes point down, thumb folds across the palm);
  local Z = X x Y is the swing (abduct / adduct) axis. Right bones mirror left bones with X
  negated, so flexion is positive on both sides while Z and Y rotations change sign
  (positive Z abducts a left limb, negative Z a right one; positive Y turns a left limb
  inward). A local rotation is written Swing(flex, abduct) Twist(twist): twist about Y
  first, then a swing whose rotation vector is (flex, 0, abduct). The reference is
  `figurine/figurine/skeleton.py`.
- Helper bones (38): per side `ArmpitHelper1`/`2`/`3`, `UpperArmTwist1`/`2`,
  `ElbowHelper1`/`2`/`3`, `ForearmTwist1`/`2`, `WristHelper1`/`2`/`3`, `GroinHelper1`/`2`/`3`,
  `KneeHelper1`/`2`/`3` (each prefixed `Left` or `Right`; the numbered joint helpers take a
  quarter, a half and three quarters of their joint's swing, the twist bones all of the
  swing and a third or two thirds of the twist). A helper sits on its driver's head with the driver's rest
  frame, is a child of the driver's parent, and its local rotation is Swing(s x the
  driver's swing) Twist(t x the driver's twist) with fixed fractions s and t (for example
  `LeftElbowHelper2`: driver `LeftLowerArm`, s 0.5, t 0). The body is skinned to them so a
  bend turns rings rigidly by a fraction instead of averaging two bones, which holds the
  inside of a bend. `kit.json` marks each with `helper: true`, `driver`, `swing` and
  `twist`. The producer bakes every helper's rotation into each stance clip
  (`skeleton.drive_helpers`), so the consumer plays helpers like any other bone; the
  fields let a consumer drive them at runtime later if it animates the body bones itself.
- Secondary chains (45 bones: 33 since the foundation card, 12 more with card B2b,
  2026-10-07): cloth and hair bones for static posing.
  Nothing moves on the map; a stance sweeps a cloak, a skirt or a ponytail and keeps it clear
  of the body. Each chain is three bones, `<Chain>1` (child of the attach bone), `<Chain>2`,
  `<Chain>3`, hanging down: off `Head`, `HairBack`, `Ponytail`, `LeftTwinTail`,
  `RightTwinTail`; off `Hips`, eight skirt chains every 45 degrees round the waist,
  `SkirtFront`, `LeftFrontSkirt`, `LeftSkirt`, `LeftBackSkirt`, `SkirtBack` and the
  `Right` mirrors of the three left ones (card B2b: four chains 90 degrees apart put the
  cloth blended between two of them on their chord, inside a raised thigh; the roots sit
  at z 0.92, just under a skirt's waistband, and the first bone runs to the knee so a
  mid-thigh hem rides on one bone); off `UpperChest`, `CloakBack`, `LeftCloak`,
  `RightCloak`. Every part
  carries them like the helpers; a part that does not use a chain leaves it inert (no
  weights on it). `kit.json` marks each with `chain` (its drape group: `hair_back`,
  `ponytail`, `twin_tails`, `skirt`, `cloak`) and `attach`. A chain bone takes its attach
  bone's proportion map whole: its R is the attach bone's R (not a stretch along its own
  axis), so cloth skinned to it scales with the body it hangs from. Their joint frames
  follow the rule above with flexion swinging the tail forward. The producer solves every
  chain bone's rotation per stance (figurine `drape.py`: each bone hangs under gravity in
  the world from its posed parent, a stance may sweep a group toward a direction or flare
  it, and each bone turns the least that keeps it and the cloth between neighbouring
  chains, at the cloth's own offset outside the chains, clear of the body at the heavy
  proportion corners; since card B2b the acceptance poses are draped too) and bakes it
  into the clips, so the consumer plays chain bones like any other bone.
- Every part GLB carries the full armature with identical rest and bind poses, so any set
  of parts binds to the one `Skeleton3D` the consumer builds from `skeleton.glb`. A part
  whose armature differs from the kit's is rejected at load, naming the part.
- Up to 4 weights per vertex. Rigid gear (a sword, a satchel) is skinned wholly to its
  attach bone (`extras.figurine_attach`).
- Proportions are per-bone `length` and `girth` factors applied through the bind
  matrices, never through pose scale (the probe found that `Skeleton3D` has no
  inherit-scale switch, so a scaled pose shears children). For bone b with unit axis a,
  length factor f and girth factor g: R_b = f a a^T + g (I - a a^T). New heads chain from
  the root, H'_c = H'_p + R_p (H_c - H_p), then one vertical shift s keeps the soles on
  the ground. The consumer sets each bone's rest origin to H'_b + s and its bind to
  inverse(Rest'_b) M_b, where M_b(v) = H'_b + s + R_b (v - H_b), on a Skin duplicated per
  avatar. Nothing shears down a chain, girth works on any bone, and stances stay valid.
  The reference implementation is `figurine/figurine/proportions.py`. Consumer notes:
  "rest origin" is the global rest, converted to a parent-relative local rest with the
  orientation unchanged; the sole point is (ankle.x, 0, ankle.z) in glTF terms; skin
  binds are named (`use_named_skins`) and Godot's bone order differs from kit.json's, so
  binds are matched by name. A helper bone is listed in no control: it takes its driver's
  length and girth factors (so its R is its driver's, and since it sits on its driver's
  head under the same parent, its map M is exactly its driver's). A chain bone (`chain` set)
  takes its `attach` bone's R whole; its head then chains from its parent as usual, so its
  map is exactly the attach bone's. Finger bones take the
  hand's ranges in the `build` control (listed there explicitly).
- Stances are one-frame glTF animation clips in `skeleton.glb` (`stance_ready`,
  `stance_relaxed`, `stance_heroic`, `stance_casting`, `stance_cheerful`, `stance_sneaky`,
  ...), holding each
  bone's full local rotation (not a delta from rest), body, finger and helper bones alike,
  applied as pose rotations, plus one translation: the `Hips` bone's local position.
  Stances are authored as intents (figurine `pose.py`: line of action, contrapposto,
  two-bone IK for feet and hands, hand shapes, look-at) and the Hips height is part of
  that solve: rotations alone cannot lower a figure, so a bent knee or a lunge needs the
  Hips dropped until the planted foot stands. The clip's Hips track holds the solve at the
  kit's own proportions. A figure with other proportions has other leg lengths, so the
  consumer stands each figure by the ground rule: `kit.json` `stance_info.<stance>.ground`
  lists the stance's ground contacts, each a bone and a point in glTF rest space (the sole
  under the ankle, or under the ball for a raised heel). The consumer poses the skeleton,
  takes the clip's Hips offset from the kit rest for x and z, carries each contact point
  through its bone (bone map M, then the bone's posed global transform relative to its
  new rest) and sets the Hips height so the lowest-standing contact lands on y = 0 (the
  highest required lift wins, so no contact sinks and the others sit on or just above the
  ground). The reference is figurine `pose.ground_hips`. No other bone carries a
  translation. `stance_info.<stance>.hand_shapes` names each hand's shape (`relaxed`,
  `open`, `fist`, `point`, `grip`), informational. Plus variants (the foundation card): a
  hand resting on the hip of a plus-size body sits further out than on the default body, so
  each stance has a second clip fitted to the heaviest body, `<stance>_plus` (hand targets
  moved out by the body surface's own `build_plus` delta, chains draped again), named in
  `stance_info.<stance>.plus` as `{"clip": "<stance>_plus", "shape": "build_plus"}`. A
  figure blends from the stance toward it by that blend shape's weight w (below): each
  bone's local rotation is `stance.slerp(plus, w)` (shortest path), the clip's Hips offset
  lerps by w, and the ground rule then stands the figure on its contacts (the base clip's
  `ground`). w = 0 for builds up to 0.5, so most figures play the base clip unchanged. The
  `_plus` clips are not listed in `stances`. The producer verifies every stance, and a
  set of acceptance poses that are not shipped (an elbow folded 120 degrees, an arm raised
  about 170 degrees, a deep lunge, a knee at hip height, a fist beside the head, a
  two-handed grip), at every proportion corner (figurine `posecheck.py`: joint limits in
  the joint-frame terms above, ground contact, interpenetration, and since the
  crisp-joints card the deformation checks a crisp joint can pass: no skin edge stretched
  past 1.6x, or past 2.8x on the outside of a joint (the limb within a joint's span of
  its pivot along the bone's axis: 10 cm shoulder, 9 elbow, 5 wrist, 17 hip, 10 knee),
  every joint's cross-section at least
  0.7 of rest across the bend and 0.85 along its axis, and no elbow, knee or wrist crease
  passing through itself by more than 3 mm, and the layer check below) so a kit never ships
  a clipping, pinched or floating pose. One contact is allowed by rule (the plus card,
  2026-10-06): a plus-size body's thighs meet, so the body's two thigh pieces may press
  into each other by up to 10 mm (how deep one thigh's vertices sit inside the other), at
  rest and in every pose; every other pair of pieces must not cross at all. A corner's
  pose is the stance blended toward its
  plus variant by that corner's weight, as the consumer blends it. Joints are skinned to fold crisply (a bent limb reads as two straight
  segments meeting at a defined joint), which nothing on the consumer side depends on.
  On Godot 4.7.1 a `Skeleton3D` posed before it enters the tree
  keeps its rest global pose, so `AvatarKit` poses again on `tree_entered` (a test guards
  it). Animation later adds multi-frame clips by the same path, which the token
  `AnimationPlayer` route (`BoardTokenAnimationTree`) already plays.

### Mesh

- Normals are the producer's choice per edge: smooth across skin and soft cloth, hard
  where a form should read as a crisp plane (hair locks, collars and lapels, a cuff, a
  brim). The low-poly look comes from angular, tapered silhouettes, not from faceted
  shading on every surface.
- A whole figure is up to 10,000 triangles (raised from about 6,000 by the foundation card;
  user, 2026-10-06: higher than PS1 is fine; what to take from Crashsune is intentional
  proportions and simple geometry). Triangles go to smooth, deliberate forms and the
  silhouette, never to surface detail, which the textures carry. Caps per slot: `body`
  4,500, `head` 1,500, `hair` 1,500, `top` 1,500, `bottom` 1,200, `cloak` 1,000, `hat` 700,
  `shoes` 600 (a part that replaces the body's sneakers), `gear` 800 per item; the slots of
  one figure together stay under the figure cap. Each part's count is in `kit.json`.
  Measured 2026-10-06 (tt-sim `avatar_kit_look --saved --only budget`, Forward+, vsync off,
  2.5 s windows, medians, indicative: the GPU may be shared): world-viewport GPU time at
  home zoom 3.93 ms with no figures, 3.38 / 3.57 / 3.61 ms with 8 figures of 5.7k / 8.4k /
  9.7k triangles and 3.65 / 3.66 / 3.69 ms with 30; at the closest zoom 1.88 ms empty,
  1.93 / 1.90 / 1.93 ms with 8 and 1.89 / 1.87 / 2.10 ms with 30 (30 x 9.7k is 292k skinned
  triangles). The differences are within run-to-run drift (the empty home sample is the
  slowest), so 10,000 per figure is free at 30 figures; the cap is set by the look (rule 1:
  simple geometry), not by cost. Blend shapes and the 105-bone skeleton were in place for
  the measurement.
- `COLOR_0.R` is the part's light response per vertex: 0 shows the painted texture alone
  (unlit), 1 takes the figure shader's full soft light. The face area is always 0 (anime
  faces stay flat; Crashsune's faces are unlit), hair and cloth sit low (about 0.2-0.4) so
  the paint carries the shading. Since the world-lighting pass (2026-10-07) the consumer
  raises every value off the face to its `light_floor` (1.0) and lights the face at
  `face_light` (0.5), so figures take the scene's light as the terrain does; the attribute
  is still read and matters again if the floor is lowered. G, B and A are reserved (wind if hair or cloth sway is
  added later; the probe's per-vertex outline width if an outline is ever wanted).
- Blend shapes (glTF morph targets, the foundation card). `build_plus` is the high end of
  the `build` control: a real plus-size body rather than a wider one (a fuller belly that
  sits forward and low, softer sides at the waist, wider hips and seat, thighs full all
  round at the top that meet at the inner thigh, full upper arms through the shoulder
  with fuller forearms, bony elbows, knees, wrists and ankles and unchanged hands and
  feet, a fuller chest and upper back, a thicker neck and raised trapezius line; on the
  head and hair, rounder cheeks and a softer jaw; the plus card, 2026-10-06, set the
  amounts). A part carries it
  as a position-only morph target named in the mesh's `extras.targetNames` (no morph
  normals: the palette carries the shading), listed in its kit.json entry's `shapes`. The
  delta is in rest (bind) space, so the bind matrices' proportion maps scale it like any
  vertex, and it combines with the build control's girth factors. kit.json `shapes` maps
  each blend shape to the control that drives it: `{"build_plus": {"control": "build",
  "points": [[0.5, 0.0], [1.0, 1.0]]}}`, the weight a piecewise-linear function of the
  control value, clamped at the ends. The consumer sets each part's blend shape of that name
  to the weight; a part without it ignores it. A garment derived from the body carries the
  same-named shape (figurine `garment.py` gives each vertex the delta of the body point it
  was built from), so every part of a figure changes together.
- Layers (the foundation card). Each part entry has `stack` and `layer`: in the `body` stack
  the body is 0, fitted clothing 1, loose clothing 2, a cloak 3; in the `head` stack the head
  is 0, hair 1, a hat 2. The producer guarantees, at every stance and proportion corner,
  that a part's surface stays outside the parts beneath it in its stack where they overlap
  (within 3 mm, 8 mm inside a joint's fold), not counting body regions a worn part hides
  or geometry tucked into the body by design (figurine `posecheck.layer_problems`), with a
  hat's `hair_mode` applied to the hair (figurine `part.worn`); and the reverse (card
  B2a, 2026-10-06, after a stand-in hat with open crown faces passed the first rule while
  hair showed through): where a part's surface claims to cover others (the mesh node's
  `extras.figurine_covers`, per surface the surfaces beneath it), the covered parts'
  visible vertices stay behind it, each tested along its own normal (the claiming surface
  must not cross that line behind the vertex by more than the same tolerances; a line that
  meets nothing is uncovered by design, a bang below a brim). So the consumer may wear any
  one part per slot together without sorting or clipping logic. Informational for the
  consumer today.
- Garment skin weights (producer-side, card B1): a derived garment takes the body's
  weights only where it lies on the body (within its offset plus 12 mm, normals within
  35 degrees) and inpaints the rest smoothly (figurine `inpaint.py`, after Abdrashitov et
  al. 2023); a chain-hung drop takes no body weight below its cut and moves onto its
  chains as before. Nothing about the GLB changes for the consumer.
- `extras.figurine_double_sided: true` marks a part whose open cards must render both
  faces (hair locks built as planes); every other part is closed and back-face culled.
- Two UV sets, because Godot reads two (`UV`, `UV2`): `TEXCOORD_0` is palette space and
  `TEXCOORD_1` is detail space (below).

### Colour: the gradient palette (TEXCOORD_0)

Colour and most of the shading come from one small palette texture per figure, the
gradient-strip technique (reference: a low-poly character textured entirely from a 64 x 64
sheet of vertical gradients, `figurine/docs/design.md` "Style"). The palette has one
column per colour slot, in this fixed order: `skin`, `hair`, `eyes`, `primary`,
`secondary`, `accent`, `leather`, `metal`. Each column is a vertical gradient from the
slot's shadow colour at v = 0 through its base colour to its highlight at v = 1 (a hue
shift along the way, never toward grey).

- A part's `TEXCOORD_0` u selects the slot (column centre `(slot + 0.5) / 8`) and v places
  each vertex along that slot's gradient. The producer paints shading by v: lighter on
  forms that face up and out, darker in folds, under the chin and toward the inside of a
  limb; hair runs from a deep root to light tips along each lock. So the shading is
  authored per vertex and interpolated, which is what makes a low mesh read soft and
  painted rather than blocky.
- The consumer builds the palette per figure from the recipe's colour picks (each pick a
  colour-set triple), 8 x 64 texels, with no filtering across columns. Recolouring an
  avatar is regenerating this texture; no part carries a mask. Each column interpolates
  in sRGB, shadow to base over the lower half and base to highlight over the upper half,
  each half eased by smoothstep (`kit.json` `palette.interpolation`
  `srgb_smoothstep_halves`); v = 0 is the bottom row (the PNG's last row). The reference
  implementation is `figurine/figurine/palette.py` `build_palette`.
- Hard colour boundaries inside a part (a cuff, a stripe, a collar) are edges in the mesh,
  with the faces on either side mapped to different columns.

### Detail: the painted overlay (TEXCOORD_1)

Each part may embed one `detail` texture (sRGB RGBA), painted by figurine with paintkit's
primitives and mapped by `TEXCOORD_1`. It is composited over the palette colour by its
alpha and carries what a gradient cannot: ink lines (fold lines, hems, finger
separations, trim edges, lash lines), ornaments, patterns, buttons and buckles, and the
hair's sheen as a band of notched, triangular highlights (Crashsune's signature). Detail
is fixed colour and is not recoloured; a pattern that must follow the outfit colour is
built from mesh faces in the palette instead. A part with no detail texture omits
`TEXCOORD_1`. In the GLB the detail texture is the material's `baseColorTexture` with
`texCoord: 1`, and figurine extras sit on the mesh node. Godot may switch on
vertex-colour-as-albedo because `COLOR_0` is present; the consumer replaces the imported
material with its figure shader, so this does not matter.

Resolution: 512 x 512 for the body and head (at 256 the body's ink smeared into
scratch-like marks at close zoom), 256 x 256 for hair and smaller parts.
Import: embedded uncompressed as in section 9, with mipmaps built at load by `AvatarKit`
and a -0.5 mip bias on the detail in the shader (measured 2026-10-06: without mipmaps
the ink stipples and the eyes become sparkle pixels at home zoom; with them home reads
soft and painterly, fine seams and shoe stripes fade, and the bias keeps close-zoom ink
crisp). The face sheet and mask import lossless with mipmaps and `fix_alpha_border`.
Basis compression was not tried. The face rect is also written to kit.json
(`face_rect`), which is what the consumer reads.

### Faces

The head's `extras.figurine_face_rect` (`[u0, v0, u1, v1]`, in glTF / Godot UV terms with
v down) marks the face area in its `TEXCOORD_1`. A face cell is sampled at
`cell_origin + (uv1 - rect.xy) / (rect.zw - rect.xy) * cell_size` with no flip; cells are
stored upright (brow at the top). The head is unlit and its unwrap continuous, so cells
compose wherever face space falls inside 0 to 1.

`face_sheet.png` holds square cells (`cell_px`), `columns` wide, one row per kind in
`row_order` (eyes, brows, mouths, marks; top row first), named in `names`; marks cell 0 is
"none". A cell's RGB is the painted feature and its alpha the coverage. `face_mask.png`
has the same layout: R is the `eyes` weight and G the `hair` weight (`mask_channels`), B
unused. Where a mask channel is above 0 the sheet's RGB is a grey value study, and that
value (the stored 8-bit number over 255, not linearised) is the palette v: the shader
mixes palette(slot, v = sheet.r) in by the mask weight. So irises take the eye colour and
brows the hair colour, with their shading painted in; pupils, sclera, ink, highlights and
blush are fixed colour. Composition order: marks, mouth, eyes, brows. A recipe picks one
cell per kind, so expression lives in the sheet, and a blink later is a cell swap. The
CPU reference is `figurine/figurine/faces.py` `compose_face`.

### `kit.json` (format 1)

```json
{
  "format": 1,
  "kit_version": "<figurine version>+<git hash>",
  "parts": [
    {"id": "top_tunic_a", "slot": "top", "glb": "parts/top/top_tunic_a.glb",
     "slots_used": ["primary", "secondary", "accent", "skin"], "triangles": 410,
     "hides": ["torso"], "tags": ["cloth"]}
  ],
  "face_sheet": {"png": "faces/face_sheet.png", "cell_px": 128,
                 "rows": {"eyes": 8, "brows": 6, "mouths": 8, "marks": 4}},
  "colour_sets": {
    "skin": [["#f2c9a0", "#d9907a", "#fff0dc"]],
    "hair": [], "eyes": [], "cloth": [], "leather": [], "metal": []
  },
  "proportions": {
    "height": {"bones": {"Spine": [0.9, 1.1], "LeftUpperLeg": [0.85, 1.15]}, "default": 0.5}
  },
  "stances": ["stance_ready", "stance_relaxed"]
}
```

The example above is the shape; the producer's own `out/kit/kit.json` is the
authoritative instance. The first kit (figurine e12e8bb) also writes: `palette` (slot
order, size, stops, interpolation), `skeleton` (above, with `flex_axis` and the helper
fields since the rig card), `stance_info` (per stance `ground` and `hand_shapes`, above),
and per part `regions` (for the body), `detail` (whether it has an overlay) and
`double_sided`; since the foundation card also `stack`, `layer` and `shapes` per part,
`chain` and `attach` on chain bones, the top-level `shapes` block and
`stance_info.<stance>.plus`; since card B1 the top-level `slots` block
(`{"hat": {"optional": true}, "hair": {"optional": false}, ...}`, every slot named; a
consumer reading an older kit without it applies the table in "Layout"), `hair_mode` on
hat parts and `regions` and `hat_trim` on hair parts. In `face_sheet`: `mask`,
`mask_channels`, `columns`, `row_order`, `names`. Proportions give `length` and `girth`
ranges per bone, each centred on 1.0; factors from several controls multiply.

A colour is a triple (base, shadow, highlight), authored in sets so that every pick is
harmonious; there is no free colour picker. `hides` names body regions a part covers: the
body carries each region (`torso`, `neck`, `upper_arms`, `forearms`, `hands`, `thighs`,
`shins`, `feet`) as its own surface whose material name is the region, and the consumer
turns covered regions off so nothing pokes through. Proportion controls are normalised 0
to 1 and map linearly onto each listed bone's range (a `Left` bone implies its `Right`
mirror).

### Recipe (an avatar, format 1)

```json
{"format": 1, "kit_version": "...",
 "parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun", "top": "top_tee"},
 "colours": {"skin": 3, "hair": 7, "eyes": 2, "primary": 11, "secondary": 4, "accent": 0},
 "face": {"eyes": 2, "brows": 1, "mouths": 0, "marks": 1},
 "proportions": {"height": 0.6, "build": 0.4, "head": 0.5},
 "stance": "stance_ready"}
```

Colours index into `colour_sets` (`primary`, `secondary` and `accent` index `cloth`). A
recipe naming a part or cell the local kit does not have falls back to that slot's first
entry and logs it, so an older client still shows a figure; an optional slot (`hat`,
`cloak`, `gear`) is the exception and falls back to none. A recipe may omit an optional
slot or name `null` there: `"parts": {"body": "body_a", "head": "head_round", "hair":
"hair_bun", "hat": null}` wears no hat. Recipes from before card B1 resolve as they did
(they always named every slot the kit had, and the kit had no optional parts).

### Rendering notes (consumer side, from the probe)

The detail will live in tt-sim's figure shader and a `docs/systems/` page; recorded here
because they constrain the producer:

- Skinned, not baked: 30 figures cost nothing measurable in Forward+, and a skinned spawn
  is about 0.1 ms against 1.3-1.9 ms to bake. Mobile and Compatibility are unmeasured.
- Godot skins VERTEX, NORMAL and TANGENT before `vertex()`.
- Lighting follows the world (the world-lighting pass, 2026-10-07): four fifths of each
  colour are lit like the terrain (the environment's ambient, sky or colour, plus a soft
  wrapped sun and lamp term) and a fifth shows as painted, the face half and half. The
  painted share is tinted by the environment's ambient through a global shader value, and
  shade under trees comes from a per-figure value from one ray toward the sun (the sun's
  shadow map stipples flat paint, so it is not sampled).
- No geometric outline: ink is painted into the textures (the sticker borders around
  Crashsune's showcase renders are 2D compositing, not geometry). If a hull is ever
  enabled, its pixel width needs `abs(PROJECTION_MATRIX[1][1])` (negative under Vulkan).
- A hidden-from-players avatar needs a dither parameter on the figure material
  (`BoardToken._set_mesh_transparency` only changes StandardMaterial3D), and each avatar
  token has its own collision capsule, which also sizes the selection glow. Both are in
  (the avatar token card, docs/ARCHITECTURE.md "Avatar tokens"): a token carries the recipe
  as written (not resolved) and every peer rebuilds the figure from it and its own kit.

### Round trip

A kit is done when `build_kit.py`'s output, installed under `assets/avatar_kit/`, loads
through `AvatarKit` from an exported pack (section 9's `--main-pack` check), every part
binds to the kit skeleton, and a figure assembled from a recipe renders at home and close
zoom.
