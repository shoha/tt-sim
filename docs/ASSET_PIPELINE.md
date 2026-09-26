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
  silhouettes at that scale (`treecube/gamescale.py`, `scripts/generate.py
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

Not yet in place: committed golden GLB fixtures from each producer with a GUT test that
loads them. That is the intended mechanical guard for drift; until it exists, the manual
round trip above is the gate.

## 9. Built-in palette (treecube -> tt-sim, for in-game map authoring)

A second path from treecube into tt-sim that bypasses Blender maps entirely: treecube
builds a palette of assets, ground surfaces and placement rules that ships inside the
game, and tt-sim's authoring mode places from it. Design:
`docs/superpowers/specs/2026-09-26-in-game-map-authoring-design.md` (local, gitignored).
Status: contract agreed 2026-09-26; producer and consumer in progress.

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
                  "tile_m": <world size of one texture repeat, metres>}
  },
  "biomes": [
    {
      "id": "<package id>",
      "biome": "<biome key>", "season": "<season>", "seed": <int>,
      "name": "<plain biome display name, no season>", "climate": "<cold|temperate|warm|dry>",
      "thumbnail": "thumbnails/<package id>.jpg",
      "ground_surface": "<surface>",
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
- `geoscatter_pattern` holds Geoscatter's `s_pattern1_*` settings verbatim with the
  prefix stripped (texture dict, sample method, influences, revert flags), minus the
  datablock plumbing (`allow`, `texture_ptr`, `texture_is_unique`). tt-sim keeps it
  for calibration only and does not interpret it.

Rules both sides rely on:

- **Rules are targets, not Geoscatter requests.** Densities, spacing and slope are what
  the scatter should deliver (what treecube's `audit_biome.py` measures against), never
  the compensated values treecube writes into Geoscatter presets (`spacing_request`,
  yields, `slope_setting`). tt-sim's generator is its own and calibrates to targets.
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
- Budgets: palette assets obey section 7's triangle targets; the foliage budget applies
  unchanged, since palette scatter builds the same chunked MultiMeshes.
