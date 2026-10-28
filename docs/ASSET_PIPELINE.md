# Asset Pipeline Contract

The interface between the Blender producers (`terrain-paint`, `treecube`, both at
`D:/dev/tabletop/`) and this consumer. tt-sim owns this file because its loader is what breaks
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

- 1 unit = 1 metre, everywhere. tt-sim applies no map scale at runtime (a level's
  legacy `map_scale` and `map_offset` are still read for old levels; section 11).
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
  `StandardMaterial3D.metallic_texture` as the packed ORM and sets the shader's
  `has_orm_texture`. A material without one gets the sampler's `hint_default_white`
  (occlusion 1, roughness 1), but since 2026-10-12 the wind shaders take metallic 0 when
  `has_orm_texture` is off; before that the white read as metallic 1.0 and such an asset
  rendered black (found by treecube's kit probe). treecube still embeds a constant ORM
  texture (roughness 0.85, metallic 0, occlusion 1) on every material, so its assets
  render as before.
- **Foliage AO is baked flat.** Per-asset ray-traced AO darkened every card; terrain-paint
  uses `bake_orm(bake_ao=False)` for foliage and tt-sim only multiplies ambient light by
  the AO channel anyway.
- Albedo, alpha, and normal bakes are 8-bit PNG. Normal maps are OpenGL tangent space,
  no swizzle.
- Leaf cards: glTF `alphaMode MASK`, cutoff 0.5, double-sided.
- **Painted foliage light (decided 2026-10-12).** treecube writes the glTF material extra
  `{"tt_foliage_light": "painted"}` on the leaf material (`<asset>_Tree_Leaf`) of trees whose
  leaf cells are flat-painted: broadleaf clump cells (oak, birch, bush, poplar, acacia and
  willow, and their saplings and young trees; acacia and willow from treecube 1a9c552) and
  conifer frond cells (`canopy.mode` "conifer": every pine-based species with a
  canopy, i.e. the boreal and temperate pines, the young pine and the alpine dwarf pine).
  Trees with the canopy off (dead trees, the burnt forest's charred snag) never carry it. A
  conifer frond is a 14-triangle drooping roof strip whose normals rise from facing out at
  its root to facing the sky at its tip; the painted light's ramp is what turns those into
  lit skirt edges over darker bands. **Palms and ferns (treecube `palms-ferns`, rounds 1 to 3c,
  2026-10-13 to 14, approved by the user 2026-10-14; palette treecube 66866b3):** treecube also writes the extra on
  the palm frond material (`<asset>_Palm_Frond`: the savanna palm and the wetland short palm)
  and the fern frond material (`<asset>_Fern_Frond`: the temperate forest and wetland fern and
  the birch woodland and boreal taiga small fern), whose fronds are then painted as leaflet
  strokes on a lighter rib that merge into one body near it and part into soft, rounded-notched
  fingers at the margin (round 3), one flat tone with a feathered edge (`frond_style`
  "painted"). Each frond carries "tilt" normals, as the conifer fronds do (round 2,
  2026-10-13): facing the frond's heading, rising from the root to the tip, each edge leaning
  toward its own side, so every frond has a lit and a shaded side. A palm (round 3, 2026-10-13:
  a full head of 8 to 12 broad fronds set by the golden angle plus 1 to 4 old fronds hanging under
  it, each three vertices across with its two wings hanging below the rib) rises from facing up
  at the root (60 degrees) to facing out at the tip (10 to 14), so the crown's top reads lit over
  darker hanging tips; its old fronds face out and a little up (round 3b: 35 to 5 degrees) and
  take the right half of the frond texture (two fronds side by side on U: the live frond on 0 to
  0.5, the old one on 0.5 to 1; one material, one texture, 512 x 512). A fern (round 3: a big
  fern's crown of fronds rising steeply and arching over; round 3b: a small fern's low, flat
  rosette of 4 to 6 fronds evenly round its centre) from 15 or 20 degrees at the root to 70 at
  the tip. Ferns stay in the "grass" wind category, so
  tt-sim's grass `base_darken` still applies to them; treecube paints a quarter of it out of the
  fern texture (round 2: half), so the fern keeps a darker heart under lit tips. Palms stay
  "tree" and carry a shade floor (below). Same nodes, meshes, attributes and material count as
  before; the fuller crowns cost triangles (the savanna palm 394 against 301 before, the
  wetland short palm 312 against 268), the ferns stay at or under their old counts.
  tt-sim shades flagged leaf cards with its painted light
  (the normals carry the value). Absent means today's shading; every non-leaf material carries
  no extra (pines carried none until treecube 12fee28, acacias and willows none until treecube
  1a9c552, both 2026-10-12). Godot 4.7 keeps it as the material's
  `extras` metadata through both the palette's editor import (sidecars as in section 9)
  and a runtime `GLTFDocument` load (headless probe, 2026-10-12). No GLB structure
  changes: same nodes, meshes, attributes and material count.
- **Painted shade floor (decided 2026-10-12; treecube writes it from 83d9e06, tt-sim honours
  it from the same palette install, `FoliageLight.shade_floor()`).** A leaf material that carries `tt_foliage_light` "painted"
  may also carry the glTF material extra `{"tt_foliage_shade": [r, g, b]}`: three linear
  floats, 0 to 1, not sRGB and not a colour, which tt-sim sets as that material's
  `foliage_paint_shade` uniform (`shaders/wind_foliage_include.gdshaderinc`, default
  `(0.065, 0.19, 0.1)`). That uniform is the painted light's shade floor: the shade end of
  the sun ramp, a per-channel multiplier of the sun's colour on the side of the crown that
  faces away from it (`DIFFUSE_LIGHT += LIGHT_COLOR / PI * mix(foliage_paint_shade,
  foliage_paint_lit, k)`), so the shade the player sees is the albedo times
  `foliage_shade_tint` times this floor, plus the quarter of the ambient the cards keep. It
  lets a warm species (the savanna shrub, the badlands sage shrub, later autumn leaves) keep a
  warm or grey shade instead of the shared green one. Absent by default, and absent means
  the uniform's default; it is ignored on a material without `tt_foliage_light` "painted"
  (the plain wind shader has no painted light), and treecube never writes it on one. No
  other uniform changes with it; the value treecube writes is the one its runtime probe
  judged (`treecube/out/looks/colour_fix/shade_probe.gd`, values listed in treecube
  `docs/looks/colour_plan.md` and `docs/looks/biome_identity.md`). Shipped values (palette
  treecube 26e031a): the savanna shrub (0.1, 0.17, 0.14), the badlands sage shrub (0.15, 0.13,
  0.19), every birch (0.12, 0.28, 0.1), the savanna acacia and young acacia (0.15, 0.16,
  0.06), the badlands acacia (0.15, 0.13, 0.19) and the wetland willow (0.12, 0.24, 0.22).
  Palette treecube 66866b3 adds the savanna palm (round 3b: 0.12, 0.22, 0.08, a warm deep green
  under its warm-lit lime, set apart from the acacia's warmer floor; round 3 was 0.09, 0.17, 0.16
  and fell to a grey-olive) and the wetland short palm (round 3c, as approved: 0.07, 0.16, 0.1, a
  warm deep olive-teal under its deep teal-green, which reads green first and stays darker and
  more saturated than the willow; round 3b's 0.03, 0.14, 0.17 under a blue teal read navy); its
  ferns carry none.
  tt-sim treats it as untrusted input: anything but a list of
  exactly three finite numbers is ignored with a warning, and a channel outside 0..1 is
  clamped with one. The floor is a per-material shader parameter on the wind
  `ShaderMaterial` that `WindFoliage.apply_material()` builds for each source material, so it
  survives the antialiasing swap and two species never share it. Godot keeps the list as an
  `Array` of floats through the editor import (`test_foliage_light.gd` reads the installed
  palette's values back).
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

Golden fixtures: plantgen's shipped core library (`libraries/core`, section 9's palette form
compiled from it) is the committed producer output with a GUT test that loads it,
`tests/unit/test_palette_builtin.gd`: every asset resolves through `PaletteLibrary`, the wind
categories and COLOR_0 presence match the catalog, every swaying surface harvests its albedo, and
one species per biome builds chunks through `build_scatter` (treecube's palette, which this test
pinned until 2026-10-25, is gone). terrain-paint map exports still have no committed fixture; for
them the manual round trip above remains the gate.

## 9. The palette form (treecube, historically; plantgen's core library since 2026-10-25)

> **Status 2026-10-25 (step S10).** treecube's palette is no longer shipped: `assets/palette/`,
> `PaletteOverlay`, `PaletteLibrary.overlay_package` and the foliage-library switch were deleted,
> and the palette the game serves is compiled in memory from the content libraries, the shipped
> `res://libraries/core` first (`docs/systems/library.md`, `docs/systems/palette.md`). What this
> section still holds is the FORM of `palette.json` that `PaletteLibrary.validate_palette` reads
> (the compiler writes exactly it), the surface-map uniformity rules and the history of the
> treecube path. The "Layout", "Import path" and "Refreshing the palette" parts below describe the
> retired treecube install (editor-imported `.glb`/`.png`, `.import` sidecars, `build_palette.py
> --install`) and are kept as history; core's files are `importer="keep"` raw files instead.

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

A second producer, plantgen (`D:/dev/plantgen`, `tools/build_ttsim_package_cli.gd`), writes a
package in this same shape (`palette.json` format 1, `assets/<biome id>/*.glb`, the same nine biome
ids and species keys, its own asset names) into a folder outside the repo. Until 2026-10-25 the
consumer served it instead of the installed palette when the dev setting `foliage/package_path`
named it (`FoliageLibrary`, `PaletteLibrary.overlay_package`); that route is retired: plantgen's
output now ships as the content library `core` (`docs/systems/library.md`), which keeps each
biome's id and species keys so authored maps keep their painting and rules. Scatter rows a map
saved under one asset set names an asset the served libraries lack are regenerated from the biome
painting at load, never migrated.

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
                  "role": "ground" | "cliff" | "built",
                  "albedo_mean_linear": [r, g, b]}
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
      "ground_look": {"ref_surface": "<surface with role ground>", "zones": {...},
                      "strokes": {...}, "brush": {...}, "light": {...}, "tuft": {...},
                      "mass": {...}, "rim": {...}, "accent_shape": {...}},
      "species": [
        {
          "key": "<species key>", "kind": "<tree|grass|flower|rock|deadwood|...>",
          "keep_colour": <bool, optional, default false>,
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
                    "children_spacing_m": ..., "mass": 0 | 1, <mass fields>} | null,
          "near":  [{"species": "<key>", "distance_m": ..., "transition_m": ..., "influence": <0..1>}],
          "avoid": [ ...same shape... ],
          "avoid_bare": <0..1 accent-noise units, optional, default 0 = off>,
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
  species. A rule clumped only through a palette-only species block (Ground look and grass
  masses, below) keeps its Geoscatter-derived value, as round 20 did.
- `keep_colour` (bool, optional, default false): the species draws in its own colours and the
  ground look's zone tuft colour never applies to it (`GroundLookBake` skips the rule when it
  binds the tuft uniforms). Placement and grass masses are unchanged. treecube writes it for
  rosette-habit grass species such as the bromeliad and the sword-leaf rosette, but only in a
  zoned biome (one with a `ground_look`), where it applies the species' palette-only block: the
  rocky badlands carry no ground look, so their sword rosette ships without the flag (treecube
  0818ee7, `palette.py` `_with_palette_block`) and draws in its own colours all the same.
- `avoid_bare` (float 0..1, optional, default 0 = off; added 2026-10-22): the species keeps off
  its biome's `ground_accents` patches (below). None stands where the ground shader draws a
  patch, soft edge included, and it fades back in over this many accent-noise units outside
  the drawn edge, the unit of the clump field `bare` (Ground look and grass masses, below).
  Clump `bare` keeps all of a biome's grass off the patches; `avoid_bare` keeps one species of
  any kind off them, so a bromeliad stays off the wetland's mud while the reeds and sedge,
  which belong there, grow in it. Keep it small: a noise margin has no fixed width in metres
  (on the wetland's 5 m patches the noise rose 0.04 to 0.25 units per metre across a drawn
  edge, p10 to p90), and where the noise runs just under its threshold a wide margin thins
  turf metres from any patch. Measured on new wetland maps (seeds 1 to 10 and 1234, tt-sim
  2026-10-22): without the field 12.9% of bromeliads stood on drawn mud, with any value none;
  0.01 costs about 1% of the species' density on turf, nearly all of it within 0.2 m of the
  mud, 0.02 about 2% within about 0.5 m, and 0.08 about 9% with a quarter of that beyond
  0.5 m. The species also loses what stood on the patches, so a producer that wants the same
  count raises `density_per_m2` by that share. The consumer clamps it to 0..1; the producer
  rejects values outside it.
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
  show, so the automatic cliff and scree and every painted surface cover them. The plant
  scatter reads them only where a rule asks: a mass rule's clump `bare` keeps the biome's
  grass off the patches and a species' `avoid_bare` keeps that species off them, both
  through the consumer's CPU twin of the shader's patch mask (`ScatterMass.bare_params`);
  otherwise a moss patch under a forest is forest floor to the scatter. Empty (`[]`)
  where a biome's ground wants no
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
- Fire (added 2026-10-10 for terrain events in play; no new field, same format 1). A GM's
  fire is a surface op (scorched ground), a mask op (a clear, or the burnt biome) and a
  parametric effect; the palette supplies the first two:
  - **`ash`**, a surface with kind `ash` and role `ground`: scorched ground, warm grey-umber
    ash with soft charcoal patches. Being `ground` it keeps the plants under it like any
    painted ground (it covers walkable ground only and yields to the automatic rock), so a
    fire pairs it with a clear or with the burnt biome; it never clears plants itself.
  - **`burnt_forest`**, a biome (package `burnt_forest_summer_s1`, name "Burnt Forest",
    climate `temperate`, `ground_surface` `ash`): charred standing snags with a few broken
    limbs, charred stumps, fallen charred logs and branches, char litter and sooty stones.
    Nothing in it is green and it lists no flowers. The snags are trees without a canopy
    (`wind_category` `tree`, a slow trunk sway, like the badlands' dead snags); the
    deadwood and stones are static; the litter is `grass` with zero weights, as every
    litter asset. It carries the usual ground accents and path surfaces, and no water
    fields (the consumer's "any other biome key" defaults apply).

  What tt-sim may assume: a palette from this version on holds both names with those
  roles. An older palette lacks them, which is never an error: a fire op falls back to a
  ground surface it has (`dirt_peat` is the judged stand-in) and to a clear. The burnt
  biome is the last entry of `biomes`: the producer lists the landscape biomes first,
  sorted by key, and event biomes after them, so the biome indices and the first entries
  the authoring pickers show do not move. Biome order is otherwise not part of the
  contract, and neither are the burnt biome's species keys or asset ids beyond the asset
  id rule below.
- `geoscatter_pattern` holds Geoscatter's `s_pattern1_*` settings verbatim with the
  prefix stripped (texture dict, sample method, influences, revert flags), minus the
  datablock plumbing (`allow`, `texture_ptr`, `texture_is_unique`). tt-sim's
  `ScatterGenerator` reads only the noise's feature size and shape from it:
  `texture_dict.scale`, `texture_dict.mapping_scale[0]`, `texture_dict.detail` and
  `texture_dict.contrast` (noise frequency = mapping_scale * scale, octaves = detail + 1),
  each falling back to treecube's defaults (2, 0.1, 1, 2) when absent. Everything else
  in it is kept for calibration only. The share removed and the shrink are the
  top-level `influence` and `scale_influence`.
- Ground look and grass masses (added 2026-10-15, the ground ship; same format 1, every field
  optional): a biome's `ground_look`, a species `clump`'s mass fields and a surface's
  `albedo_mean_linear`, specified in "Ground look and grass masses" below. Zones are drawn
  per biome from `ground_look` and the map seed; a level stores no zone field.

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
- **Ground looks and mass fields degrade, never fail.** The producer rejects
  (`palette_problems()`) a `ground_look` key that is not in the key table below (the
  run-time keys and the probe's dropped fields included), a value of the wrong type or
  array length or outside its range, a `ground_look` without `ref_surface` or
  `zones.colors_linear`, a `ref_surface` or `zones.layers` name that is missing or not a
  `ground` surface, a `rim.surfaces` name that is missing or is neither `ground` nor `built`,
  a clump mass field out of its range, a `parent_group` whose rules disagree on the swathe
  fields, and `follow` or a `zone_*` clump field in a biome without a `ground_look`; and a
  surface whose `albedo_mean_linear` is not three values in 0..1. The consumer is lenient,
  so an older or partial palette still loads: an unknown key or a value of the wrong type
  warns and takes the base value, an out-of-range value is clamped, a missing
  `ref_surface` (or one that names an absent or non-ground surface) warns and takes the
  biome's `ground_surface`, a `ground_look` without `zones.colors_linear` warns and is
  ignored (the biome draws today's ground), a `zones.layers` or `rim.surfaces` name that
  does not resolve warns and is dropped, a mass field is ignored without `mass` 1, and
  `follow` or a `zone_*` clump field is ignored in a biome without a `ground_look`. A
  missing `albedo_mean_linear` is computed from the imported albedo silently.
- Budgets: palette assets obey section 7's triangle targets; the foliage budget applies
  unchanged, since palette scatter builds the same chunked MultiMeshes.

### Ground look and grass masses (contract 2026-10-15)

The ground ship (branches `ground-ship` in treecube and tt-sim) adds three optional pieces to
format 1: a biome's `ground_look` (colour zones, painted light, grass-mass shading), mass
fields on a species `clump`, and a surface's `albedo_mean_linear`. Absent means today's
behaviour exactly: a palette without them draws today's ground and grass, and a biome
without a `ground_look` keeps today's ground. The values are round 20 of the ground looks
pass, preserved in treecube `docs/looks/ground20/` (`ground_look_r20.json`, written by
`dump20.py`; its README says how).

**Where the values live.** tt-sim holds the base values (`GroundLook.BASE`, the Base column
below). The palette's `ground_look` holds only the biome's own overrides of them, so every
value lives once. Colours are linear, as the shaders take them. Event biomes
(`burnt_forest`) carry no `ground_look`, and the records of `rocky_badlands`,
`boreal_taiga` and `burnt_forest` stay byte-identical to the palette before the ground ship.

**Biome `ground_look`** (object; absent = today's ground and grass for that biome). Its keys
are grouped in sub-objects; a key is the probe's shader uniform name without its prefix.

- `ref_surface`: the `ground` surface whose mean albedo (`albedo_mean_linear`) is the
  biome's light reference: the zone colours and the light are multipliers over it.
- `zones`: three or four turf colours (`colors_linear`: zone 0 the base, 1 to 3 laid over it
  in order) in low-frequency, domain-warped world-space shapes, `scale_m` across, covering
  `cover` of the map, drawn `stretch` times longer along `angle`, with ragged edges whose
  width varies along the boundary. The triples are per zone 1 to 3. `layers` names the
  ground surfaces the zones colour; empty colours the biome's ground surface.
- `strokes`: zone edges resolved as interleaved brush strokes (a hue jump) rather than a
  crossfade.
- `brush`: what a zoned ground layer keeps of its own texture: its luminance over its mean,
  raised to `contrast`, and `hue` of its own hue (`mean` 0 is the plain brush).
- `light`: the painted light: soft lit and shaded pools about `scale_m` across with their
  tints, broad soft streaks (the savanna's ripples with `streak_ripple` 1), eased above
  `knee` toward `cap` with the saturation held under `sat_cap`.
- `tuft`: each grass tuft takes its zone's hue at its own luminance, `step` over its ground.
- `mass`: a tuft placed as part of a grass mass (a `clump` with `mass` 1) steps over fine
  cover and reads as one body, darker at its base and lit at its top and on its sunward
  side (`contrast` below 0 keeps `tuft.contrast`); the ground under a mass takes a soft
  shade and lift.
- `rim`: a soft dark rim where the biome ground meets the listed accent and path surfaces
  (`surfaces`, up to four; none draws no rim).
- `accent_shape`: the shape of the biome's `ground_accents` patches.

Zones are drawn per biome from `ground_look` and the map seed: the level's `map_seed` shifts
the zones and the light by an offset of a few hundred metres, so two maps of one biome
differ, and a level stores no zone field. The scatter reads the same zones as the ground (a
mass rule's `follow`, `zone_keep` and `zone_family`), so the masses follow the ground.

The key table is generated from `ground_look_r20.json`, never typed by hand. Key is the
contract key (sub-object and name); r20 name is the uniform or setting the probe used; Base
is the consumer's value when a biome's `ground_look` omits the key. A Base marked (shader) is
not in round 20's base settings but the shader's own default, which leaves that feature off;
"required" keys have no base. Triples are RGB colours or per-zone values (zones 1 to 3); an
angle is in radians.

| Key | r20 name | Type | Range | Base |
|---|---|---|---|---|
| `ref_surface` | `ref_surface` | string | a `ground` surface | required |
| `zones.colors_linear` | `zone_color_0` .. `zone_color_3` | [3][3] or [4][3] float | 0..1 | required |
| `zones.strength` | `zone_strength` | float | 0..1 | 1.0 |
| `zones.cover` | `zone_cover` | [3] float | 0..1 | [0.0, 0.0, 0.0] (shader) |
| `zones.scale_m` | `zone_scale_m` | [3] float | > 0 m | [12.0, 9.0, 6.0] (shader) |
| `zones.edge` | `zone_edge` | [3] float | > 0 | [0.045, 0.04, 0.035] |
| `zones.stretch` | `zone_stretch` | float | >= 1 | 1.0 |
| `zones.stretch_k` | `zone_stretch_k` | [3] float | > 0 | [1.0, 1.0, 1.0] |
| `zones.angle` | `zone_angle` | float | any, rad | 0.0 |
| `zones.angle_k` | `zone_angle_k` | [3] float | any, rad | [0.0, 0.0, 0.0] |
| `zones.warp` | `zone_warp` | float | >= 0 | 0.55 |
| `zones.rag` | `zone_rag` | float | 0..1 | 0.12 |
| `zones.rag_m` | `zone_rag_m` | float | > 0 m | 2.2 |
| `zones.nest` | `zone_nest` | float | 0..1 | 0.0 |
| `zones.edge_vary` | `zone_edge_vary` | float | 0..1 | 0.4 |
| `zones.edge_vary_m` | `zone_edge_vary_m` | float | > 0 m | 24.0 (shader) |
| `zones.shade_warm` | `zone_shade_warm` | [3] float | > 0 | [1.04, 0.92, 0.84] |
| `zones.oklab` | `zone_oklab` | float | 0, 1 or 2 | 2.0 |
| `zones.layers` | `zone_layers` | [<= 4] string | `ground` surfaces | [] |
| `strokes.on` | `zone_stroke` | float | 0..1 | 1.0 |
| `strokes.m` | `zone_stroke_m` | float | > 0 m | 1.6 |
| `strokes.len` | `zone_stroke_len` | float | >= 1 | 3.5 |
| `strokes.edge` | `zone_stroke_edge` | float | >= 1 | 5.0 |
| `strokes.soft_lo` | `zone_stroke_soft_lo` | float | 0..1 | 0.08 |
| `strokes.soft_hi` | `zone_stroke_soft_hi` | float | 0..1 | 0.3 |
| `strokes.soft_m` | `zone_stroke_soft_m` | float | > 0 m | 9.0 |
| `brush.contrast` | `zone_brush_contrast` | float | >= 0 | 0.4 |
| `brush.hue` | `zone_brush_hue` | float | 0..1 | 0.08 |
| `brush.key` | `zone_brush_key` | float | >= 0 | 0.85 |
| `brush.mean` | `zone_brush_mean` | float | >= 0 | 0.0 (shader) |
| `light.strength` | `light_field_strength` | float | 0..1 | 1.0 |
| `light.key` | `light_field_key` | float | > 0 | 1.0 |
| `light.scale_m` | `light_field_scale_m` | float | > 0 m | 6.0 |
| `light.cover` | `light_field_cover` | float | 0..1 | 0.32 |
| `light.lift` | `light_field_lift` | float | >= 0 | 0.36 |
| `light.lit_tint` | `light_field_lit_tint` | [3] float | > 0 | [1.03, 1.0, 0.86] |
| `light.shade` | `light_field_shade` | float | 0..1 | 0.36 |
| `light.shade_tint` | `light_field_shade_tint` | [3] float | > 0 | [0.96, 0.99, 0.98] |
| `light.streak` | `light_field_streak` | float | >= 0 | 0.04 |
| `light.streak_m` | `light_field_streak_m` | float | > 0 m | 2.2 |
| `light.streak_stretch` | `light_field_streak_stretch` | float | >= 1 | 3.0 |
| `light.streak_angle` | `light_field_streak_angle` | float | any, rad | 0.5 |
| `light.streak_ripple` | `light_field_streak_ripple` | float | 0..1 | 0.0 |
| `light.streak_cover` | `light_field_streak_cover` | float | 0..1 | 0.6 |
| `light.knee` | `light_field_knee` | float | 0..1 | 0.5 |
| `light.cap` | `light_field_cap` | float | 0..1 | 0.85 |
| `light.sat_cap` | `light_field_sat_cap` | float | 0..1 | 0.88 |
| `light.broad` | `light_field_broad` | float | 0..1 | 0.35 |
| `light.stretch` | `light_field_stretch` | float | >= 1 | 1.0 |
| `light.crisp` | `light_field_crisp` | float | 0..1 | 0.35 |
| `light.ripple_curve` | `light_field_ripple_curve` | float | 0..1 | 0.0 |
| `tuft.strength` | `zone_tuft_strength` | float | 0..1 | 1.0 |
| `tuft.step` | `zone_tuft_step` | float | > 0 | 2.35 |
| `tuft.contrast` | `zone_tuft_contrast` | float | >= 0 | 0.7 |
| `tuft.hue` | `zone_tuft_hue` | float | 0..1 | 0.3 |
| `tuft.knee` | `zone_tuft_knee` | float | 0..1 | 0.55 |
| `tuft.cap` | `zone_tuft_cap` | float | 0..1 | 0.82 |
| `tuft.capped` | `zone_tuft_capped` | float | 0 or 1 | 1.0 |
| `mass.step` | `zone_mass_step` | float | > 0 | 1.18 |
| `mass.sat` | `zone_mass_sat` | float | > 0 | 1.25 |
| `mass.lit` | `zone_mass_lit` | float | 0..1 | 0.25 |
| `mass.lit_m` | `zone_mass_lit_m` | float | > 0 m | 2.0 |
| `mass.contrast` | `zone_mass_contrast` | float | any | 0.3 |
| `mass.base` | `zone_mass_base` | float | > 0 | 0.7 |
| `mass.tip` | `zone_mass_tip` | float | > 0 | 1.25 |
| `mass.h_m` | `zone_mass_h_m` | float | > 0 m | 0.8 |
| `mass.own` | `zone_mass_own` | float | 0..1 | 0.0 |
| `mass.up_pow` | `zone_mass_up_pow` | float | > 0 | 1.0 |
| `mass.shade` | `mass_shade` | float | 0..0.9 | 0.12 |
| `mass.shade_size` | `mass_shade_size` | float | > 0 | 0.9 |
| `mass.shade_push` | `mass_shade_push` | float | >= 0 | 0.9 |
| `mass.lift` | `mass_lift` | float | 0..0.2 | 0.03 |
| `mass.lift_size` | `mass_lift_size` | float | > 0 | 1.0 |
| `mass.lift_push` | `mass_lift_push` | float | >= 0 | 0.25 |
| `rim.surfaces` | `rim_surfaces` | [<= 4] string | `ground` or `built` surfaces | [] (no rim) |
| `rim.accent_rim_m` | `accent_rim_m` | float | >= 0 m | 0.15 |
| `rim.path_rim_m` | `path_rim_m` | float | >= 0 m | 0.2 |
| `rim.strength` | `rim_strength` | float | 0..1 | 0.6 |
| `rim.wobble` | `rim_wobble` | float | 0..1 | 0.6 |
| `rim.gap` | `rim_gap` | float | 0..1 | 0.45 |
| `rim.path_blend_width` | `path_blend_width` | float | >= 0 | 0.06 |
| `rim.color_linear` | `rim_color` | [3] float | 0..1 | [0.1789, 0.0835, 0.0174] |
| `rim.accent_core_m` | `accent_core_m` | float | >= 0 m | 0.0 (shader) |
| `rim.core_dark` | `core_dark` | float | 0..1 | 0.0 (shader) |
| `rim.accent_tint` | `accent_tint` | [3] float | > 0 | [1.0, 1.0, 1.0] (shader) |
| `accent_shape.stretch` | `accent_stretch` | float | >= 1 | 1.8 |
| `accent_shape.stretch_angle` | `accent_stretch_angle` | float | any, rad | 0.6 |
| `accent_shape.break` | `accent_break` | float | 0..1 | 0.4 |
| `accent_shape.edge_scale` | `accent_edge_scale` | float | > 0 | 1.0 (shader) |

Set by the consumer at run time, not contract keys: the baked texture, its rect and the
baked flag (`light_field_tex`, `light_field_rect`, `light_field_baked`); the zoned flag
(`light_field_zoned`, on for every biome with a `ground_look`); the bake's density
(`texels_per_m`, 10 in round 20); the seed offset (`zone_seed_m`, from `map_seed`); the
mass light direction (`zone_mass_lit_dir`, from the sun); the tuft reference
(`zone_tuft_ref`, each grass material's mean); and the light reference (`light_field_ref`,
the `albedo_mean_linear` of `ref_surface`). The probe's dry drift (`light_field_dry`,
`light_field_dry_scale_m`, `light_field_dry_tint`: off in all six zoned biomes) and its
other dead uniforms are not part of the format.

**Species `clump`, mass fields** (read only with `mass` 1; the consumer clamps, the producer
rejects out-of-range values):

| Field | Type, range | Absent | Meaning |
|---|---|---|---|
| `mass` | 0 or 1 | 0 | the rule's clumps join into masses; each row carries its parent (the mass anchor) |
| `stretch` | >= 1 | 1 | each clump an ellipse of the same area, `stretch` times longer than wide |
| `angle_deg`, `angle_jitter_deg` | degrees; jitter 0..180 | 0, 0 | the long axis, and each parent's turn from it |
| `edge_shrink` | 0..1 | 0.2 (`ScatterGenerator.CLUMP_SCALE_SHRINK`) | scale lost at the rim |
| `radius_jitter` | 0..0.9 | 0.25 (`ScatterPlan.CLUMP_RADIUS_JITTER`) | each parent's radius spread |
| `core_scale` | >= 1 | 1 | tuft width at the centre (a dome falling to the rim) |
| `core_height` | > 0 | `core_scale` | tuft height at the centre |
| `core_height_m` | >= 0 m | 0 (no cap) | cap on a grown tuft's height |
| `core_hold` | 0..0.95 | 0 | the core's growth held over this share of the reach |
| `follow` | 0 or 1 | 0 | the long axis runs along the nearest zone edge (needs a `ground_look`) |
| `parent_group` | int >= 0 | 0 (own parents) | the rules of one group share their parents |
| `parent_spacing_m` | >= 0 m | 0 | the parents' own spacing |
| `bare` | >= 0, accent-noise units | 0 | the biome's grass keeps off the ground-accent openings |
| `shoulder_m` | >= 0 m | 0 | a mass stands back from where its ground thins |
| `zone_keep` | [4] float 0..1 | [1, 1, 1, 1] | the share of parents kept in each zone |
| `zone_family` | [4] int 0..3 | [0, 1, 2, 3] | each zone's family; the zones of one family count as one hue |
| `zone_core`, `zone_share`, `zone_fill` | 0..1 | 0 (off) | the family weight a parent needs, the family weight a child needs, and the share of a swathe's fill points on its family (the core ring strict in openings) |

`zone_keep` and `zone_family` are four-element arrays (the probe's `zone_keep0..3` and
`zone_kin0..3`). A field that is present means its value: `edge_shrink` or `radius_jitter`
0 is 0, not the default (the probe read 0 as "use the default"; no round 20 rule sets
either to 0). The swathe fields, on which the rules of one `parent_group` must agree, are
`parents_per_m2`, `radius_m`, `stretch`, `angle_deg`, `angle_jitter_deg`, `follow`,
`radius_jitter`, `mass`, `bare`, `parent_spacing_m`, `shoulder_m`, `zone_keep`,
`zone_family`, `zone_core`, `zone_share` and `zone_fill`. The probe's `core_thin`,
`core_keep`, `zone_hue`, `zone_depth_m`, `zone_clip` and `zone_stroked` are not part of the
format (the zone tests always use the stroked zones).

The producer writes the in-game placement (a mass rule's `clump`, and `density_per_m2` and
`pattern.influence` where the in-game look differs from the Blender one) from a palette-only
species block in its biome file, applied over the Geoscatter-derived entry, so Geoscatter
presets and Blender maps are unchanged. In `palette.json` they are the species' ordinary
fields.

**Surface `albedo_mean_linear`** (optional, [3] float 0..1): the mean linear albedo of the
surface's albedo map (each texel decoded from sRGB, RGB averaged over the whole map, as
treecube `docs/looks/ground20/refs8.py` measured it). The consumer computes it from the
imported texture when absent. It is read as a biome's light reference through
`ground_look.ref_surface`.

**Saved levels: mass anchors.** A level gains one optional entry (like the erase and fire
entries): per asset id, one (dx, dz) offset in metres per instance row of that asset, in row
order, from the row to its mass anchor; a row with no anchor in an anchored asset is
written (0, 0), its own anchor. It is validated on load: the count must equal the asset's
rows and every offset must lie within the rule's reach (checked where the palette is known,
in the map loader, with 0.01 m slack for float32 rounding; the level parser only bounds
offsets at 1000 m); an entry that fails is dropped with a warning. A level without it (an older level) loads with each tuft taking its
zone's hue where it stands and no mass shading. Anchors are saved rather than recomputed on
load, so a saved level does not depend on today's placement rules.

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

### Surface map uniformity (decided 2026-10-11)

**Every palette surface's maps of one kind have the same size, the same mip chain and the
same imported format**, because the index-based ground (`docs/plans/2026-10-11-ground-layers/`)
stacks one map's surfaces into four `Texture2DArray`s (albedo, normal, ORM, height), and an
array layer must match the others in size, mip count and format. Today, measured on all 26
surfaces (2026-10-11):

| Map | Producer PNG (treecube) | Imported (tt-sim sidecar) | VRAM per surface |
|-----|-------------------------|---------------------------|------------------|
| albedo | 1024x1024, 8-bit RGB | BC7 (`BPTC_RGBA`), full mips | 1.40 MB |
| normal | 1024x1024, 8-bit RGB | BC5 (`RGTC_RG`), full mips | 1.40 MB |
| orm | 1024x1024, 8-bit RGB | BC1 (`DXT1`), full mips | 0.70 MB |
| height | 1024x1024, 16-bit greyscale | uncompressed L8, full mips | 1.40 MB |

`Texture2DArray.create_from_images` takes the imported images as they are, so no conversion
runs at load. Who checks what: the producer writes every map square at 1024 with the PNG
layout above, and treecube's `build_palette.py` refuses a palette whose surface breaks it
(`surface_map_problems()`, run before `--install`); the consumer owns the import, and
`tests/unit/test_palette_builtin.gd` fails on a sidecar whose compression or mipmap settings
differ from the committed ones. A change of size or format is a contract change: all
surfaces move together, in one palette install. `PaletteLibrary` will resize a stray map
to the array's size with a warning rather than reject it (planned with the ground-layers
binding, card G3), so a map
still draws, but a shipped palette never relies on that.

**Refreshing the palette:** copy treecube's output over `assets/palette/`, keep the
existing sidecars, write the three sidecar settings above into a `.glb.import` for every
new GLB before the first import (otherwise Godot extracts its textures), then
`godot --headless --import --path .`. treecube's `build_palette.py --install` replaces the
`assets/`, `surfaces/` and `thumbnails/` directories wholesale and so deletes every
committed sidecar: restore them straight after with
`git checkout -- ":(glob)assets/palette/**/*.import"` and check `git status` shows only
binaries and `palette.json` changed (palette v2, 2026-09-26, was installed this way); run it
again if a sidecar is still missing, since once it restored only part of the files.
**When asset ids change** (treecube renumbers variants, or a species gains or loses one),
reconcile the sidecars before the first import: delete every restored `.glb.import` whose
GLB is gone, and give every GLB without one a minimal sidecar holding the three settings
above (`[remap]` with `importer="scene"` and `importer_version=1`, then `[params]` with
`meshes/generate_lods=false`, `meshes/create_shadow_meshes=false`,
`meshes/force_disable_compression=false` and `gltf/embedded_image_handling=3`); the import
fills in the rest and the uid. A GLB imported without one gets Godot's defaults (extracted
textures, LODs, shadow meshes), and its `.godot/imported` copy must then be deleted with its
`.md5` before a corrected sidecar takes. Then grep `tests/` for pinned asset ids
(`_summer_\d\d`) and move them to ids the new palette has.
Before committing, `git lfs status` must list every GLB/PNG/JPG as LFS and only
`palette.json` as Git. Changing a setting in an existing sidecar does not
trigger a reimport on its own; delete the matching `.godot/imported/*.md5` first.
`tests/unit/test_palette_builtin.gd` checks the sidecars and fails on a missed one.
Refreshed 2026-10-11 with treecube f03e63f (the A2 broadleaf clump crowns; `palette_version`
`0e0b6d6-dirty`), which also replaced 20 ground-cover ids in alpine meadow and birch
woodland: new GLBs got the three settings in a minimal sidecar before the import, and the
removed ids' sidecars were deleted (PERFORMANCE.md "Broadleaf clump crowns"). Refreshed
again 2026-10-11 with treecube 1c3904c (stable garden ids, every listed species present, the
same A2 crowns; `palette_version` `7bcc4f6-dirty`, 201 assets, 26 surfaces unchanged): every
asset id changed once, so 131 sidecars were deleted and 133 minimal ones written before the
import, as the step above describes. No saved map was migrated.
Refreshed 2026-10-12 with treecube 51318f0 (the round 6 broadleaf crowns, whose shade is a deep
saturated green; `palette_version` `970777b-dirty`, 201 assets, ids and files unchanged, every
sidecar restored), together with round 6's four painted-light defaults in
`shaders/wind_foliage_include.gdshaderinc` (`foliage_shade_tint`, `foliage_shade_add`,
`foliage_paint_shade`, `foliage_paint_band`), which the crowns are painted for.
Refreshed 2026-10-12 with treecube 12fee28 (looks refinement 2: the pines' tiered crown of
drooping roof fronds, now painted materials; `palette_version` `c53993a-dirty`, 201 assets,
ids unchanged, every sidecar restored). The 8 pine GLBs changed (alpine meadow's dwarf pine,
the taiga's four pines and two young pines, the forest's pine), with about 80 % fewer
triangles and narrower bounds (a taiga pine about 5 m across instead of 6, the young pine
1.7 m instead of 3.4). The other 37 tree GLBs changed only in their node's
`extras.treecube.canopy` parameter record, which gained the new `conifer_*` keys; their
binary chunks (geometry and textures) and materials are byte-identical. No code change.
Refreshed 2026-10-12 with treecube 83d9e06 (the species-colour pass and its fix round;
`palette_version` `e9bb6cc-dirty`, 201 assets, ids unchanged, 26 surfaces byte-identical, every
sidecar restored by the first checkout; `git status` checked twice, the same 103 GLBs,
`palette.json` and the 9 thumbnails both times). The 103 GLBs differ by colour only (leaf and
grass albedo, materials) and the burnt forest's are byte-identical. Nine painted leaf
materials carry the new `tt_foliage_shade` extra (section 6 "Painted shade floor"): the
savanna shrub 0.2, 0.15, 0.06, the badlands sage shrub 0.15, 0.13, 0.19, and every birch
(birch woodland's four and its sapling, the taiga's and the temperate forest's) 0.12, 0.28,
0.1, which `FoliageLight.shade_floor()` honours from the same commit. Home captures at seed
1234 match treecube's runtime-probe frames (`treecube/out/looks/colour_fix/after_*.png`) in
mean colour and darkest and brightest tenth within about 2 of 255.
Refreshed 2026-10-12 with treecube 26e031a (looks refinement 4, biome identity: treecube
1a9c552's umbrella acacias, painted willow curtain, crooked oak limbs and blue-sage savanna
shrub, with 1a9c552's wind-bent alpine dwarf pine reverted; `palette_version`
`26e031a-dirty`, 201 assets, ids unchanged, 26 surfaces byte-identical, every sidecar restored
by the first checkout; `git status` checked twice, the same 12 GLBs, `palette.json` (version
and 11 asset bounds) and the 9 thumbnails both times). The alpine dwarf pine GLB is
byte-identical to the one it replaced. The 12 GLBs: the savanna acacia, young acacia and shrub,
the badlands acacia, the wetland's three willows, and the oaks (temperate forest's two and its
sapling, birch woodland's and grassland's). The acacias and willows now carry
`tt_foliage_light` "painted" and a `tt_foliage_shade` floor (section 6), the shrub's floor
changed; the acacias and willows are cheaper (a willow about 5,100 triangles, was about 6,200),
the oaks within about 250 triangles of before. No code change.
Refreshed 2026-10-12 with treecube 958dbbe (looks refinement 5, grass variety: the `clump`,
`sprig`, `seed` and `fine` card styles, per-species drift patterns, a summer-lime grassland and a
cool wetland; `palette_version` `88f407e-dirty`, 201 assets, 26 surfaces byte-identical). 46
grass asset ids changed in eight biomes (treecube `docs/looks/grass.md` "Ids"; a script checked
that every changed id is a grass species' asset and that no surface, biome or palette rule key
changed), so the renamed-ids step ran: the first checkout restored every sidecar, the 46 removed
ids' sidecars were deleted and 46 minimal ones written before the import, and stale
`.godot/imported` copies of the new names from the maker's scratch installs were deleted with
their `.md5` first. `git status` checked twice: 46 GLBs and sidecars removed, 46 of each added,
22 GLBs modified (8 in their binary chunk, the savanna's fine grass and the wetland's reeds; 14 in
their JSON chunk only), 9 thumbnails and `palette.json`. After the import every new sidecar had
its uid and the three settings, and no texture was extracted. Three tests pinned temperate
forest's `Grass_Short_summer_18` and now pin `Grass_Clump_summer_17`. The grassland's folded
clumps (`grass`) now stand about 1 m, past `ScatterGround.TALL_COVER_M`, so they are tall cover
and thin beside paths like its seed grass; `test_scatter_ground_rules.gd` now expects that and
takes the `sprig` as the meadow's short cover. Home captures at seed 1234
(canopy fade off) match the maker's frames in mean colour and darkest and brightest tenth within
about 2 of 255 (PERFORMANCE.md "Grass variety"). No saved map was migrated.
Refreshed 2026-10-12 with treecube e30c00a (looks refinement 6, flowers: painted flower heads on
crossed cards and the stemless `flower_carpet` ground cover placed in drifts; `palette_version`
`cca5604-dirty`, 201 assets, 26 surfaces byte-identical; treecube `docs/looks/flowers.md`). 11
flower asset ids changed in five biomes (alpine meadow, birch woodland, grassland meadow, temperate
forest, wetland); a script checked that no other id changed, that only flower GLBs differ in
content, and that `biomes` gained no new key (temperate forest's species key `bluebell` is kept,
now a carpet, because `test_authored_scatter.gd` pins it). The renamed-ids step ran: the first
checkout restored every sidecar, the 11 removed ids' sidecars were deleted and 11 minimal ones
written before the import, and 26 stale `.godot/imported` files of the new names (scene and
`.md5`, from the maker's scratch installs) were deleted first. `git status` checked twice: 11
GLBs and sidecars removed, 11 of each added, 13 flower GLBs modified, 9 thumbnails and
`palette.json`. After the import every new sidecar had its uid and the three settings, and no
texture was extracted. No test pinned a changed id. Birch woodland's ground weight total rose by
1, so its grass and litter densities drop slightly. The carpets take the standard wind shader
(`wind_category` `grass`), not the painted light. Home captures at seed 1234 (canopy fade off,
grassland also at zoom 26) match the maker's frames in mean colour and darkest and brightest tenth
within 0.5 of 255 (PERFORMANCE.md "Flowers"). No saved map was migrated.
Refreshed 2026-10-12 with treecube f06aa49 (looks refinement 7, rocks: stacked-slab boulders,
planar-cut medium rocks and stones with no crack lines and faint moss, warm sandstone in the
badlands and savanna, and a thicker dead tree without twig fuzz; `palette_version`
`9b8118e-dirty`, 201 assets, ids unchanged, 26 surfaces byte-identical; treecube
`docs/looks/rocks.md`). A script checked before the install that every asset, biome and surface
record kept its id and that the GLBs that differ are exactly every landscape biome's `Rock_*` and
`Stone_*` (41) and the badlands and savanna `Tree_Dead` (2): 43 files, where rocks.md counts 40
for the same set. The 19 burnt forest GLBs are byte-identical. Every sidecar was restored by the
first checkout; `git status` checked twice, the same 43 GLBs, `palette.json` and the 9 thumbnails
both times; the import touched those 52 files and extracted no texture. The rocks keep the
standard shader (no wind) and carry no new extra (rocks.md's proposed `tt_rock_shade` is not in
these GLBs). No test pinned a rock's bounds. Home captures at seed 1234 (canopy fade off) for
alpine meadow, rocky badlands and savanna match the maker's frames in mean colour and darkest and
brightest tenth within 0.2 of 255; the badlands map at seed 1234 scatters seven dead trees (the
savanna none), and one seen at home zoom reads as a lone leaning snag. No code change.
Refreshed 2026-10-13 with treecube 1c05fb0 (looks refinement 8, ground surfaces: treecube
`docs/looks/surfaces_pass.md`; `palette_version` `4d48c81-dirty`, 201 assets, ids and GLBs
unchanged, 29 surfaces). Three new ground surfaces, `grass_meadow`, `grass_forest` and
`grass_birch`, and a fresher `grass_alpine` (its albedo only; normal, ORM and height
byte-identical). Biome records: grassland ground `grass_meadow` with accents `grass` 0.16 @ 11 m
and `grass_alpine` 0.08 @ 8 m; birch ground `grass_birch` with `grass_forest` 0.14 @ 11 m and
`forest_floor` 0.08 @ 10 m; alpine accent `grass_birch` 0.14 @ 11 m; savanna `dirt` 0.10 @ 9 m;
temperate forest's grass accent `grass_forest`. A script checked all of that before the install,
and that the burnt forest's record, its 19 GLBs and `ash`, `dirt`, `dirt_peat` are
byte-identical. Every sidecar was restored by the first checkout; `git status` checked twice,
the same `palette.json`, `grass_alpine_albedo.png`, 9 thumbnails and 12 new PNGs both times.
The 12 new maps got sidecars holding the committed `[params]` (from `grass`'s) before the first
import, after stale `.godot/imported/grass_{meadow,forest,birch}_*` copies from the maker's
scratch rounds were deleted; they import as BC7, BC5, BC1 and L8, 1024 square, 10 mips, like
every other surface. `test_palette_builtin.gd` now counts 29 surfaces. Two consequences until
the index ground (card G3): each new accent is a surface of its own, so on the eight-slot
`GroundLayerTable` a map with two or more biomes drops accents it used to draw (one-biome new
maps still fit; `test_ground_layers.gd` and `test_fire_event.gd` now expect the drops, and the
fire and live-edit fixtures moved from base `grass` to `grass_birch`, birch's ground), and with no biome on `grass` a saved map on base `grass` takes the wetland's base
dressing. Home captures at seed 1234 (canopy fade off) for grassland meadow, birch woodland and
alpine meadow match the maker's frames in mean colour and darkest and brightest tenth within 0.7
of 255. No saved map was migrated. The pass's accent-edge proposals for G3 are filed in
`docs/plans/2026-10-11-ground-layers/design.md`.
Refreshed 2026-10-13 with treecube 3adda15 (the reworked rocks, reviewed over three rounds;
`palette_version` `c37bda0-dirty`, 201 assets, ids unchanged, 29 surfaces byte-identical). A
script checked before the install that the asset, biome and surface records kept their ids, that
`biomes` and `surfaces` are equal to the installed ones, and that the 41 GLBs that differ are
exactly every landscape biome's `Rock_*` and `Stone_*` (alpine meadow 10, rocky badlands 7,
savanna 6, grassland meadow 5, boreal taiga 4, temperate forest 4, wetland 3, birch woodland 2);
the 19 burnt forest GLBs are byte-identical (its thumbnail is re-rendered with the other eight).
In `palette.json` 35 asset records changed, only in their bounds (`dimensions_m`). Every sidecar was
restored by the first checkout; `git status` checked twice, the same 41 GLBs, `palette.json` and
the 9 thumbnails both times; the import touched those 51 files and extracted no texture. The rocks
keep the standard shader and carry no new extra. `assets/palette/assets` went from 24.17 MB to
22.90 MB, smaller although the faceted forms carry a real chamfer (the maker counts a faceted
medium rock at about 310 triangles, was about 90). Home captures at seed 1234 (canopy fade off) for
alpine meadow, rocky badlands and savanna match the maker's frames
(`treecube/out/looks/rocks_rework3/new_*.png`) in mean colour and darkest and brightest tenth
within 0.001 of 1.0; the placed rocks sit where they did, rotated differently per run, and the
foliage sways. No code change, no saved map migrated.
Refreshed 2026-10-16 with treecube 6bc37ea (the burnt forest's lighter charred wood, the user's
"lighter brown wood" decision; 9 packages, 201 assets, 36 surfaces, ids unchanged). Exactly 15
files changed against the installed tree, as the maker's parity listing said: the 13 charred wood
GLBs (snags, conifer snags, high stumps, logs, branches and the stump), the burnt forest's
thumbnail and `palette.json`, where only `palette_version` differs. Every sidecar was restored by
the first checkout; `git status` showed only those 15 files before and after the import, and
`git lfs status` listed the GLBs and the JPG as LFS and `palette.json` as Git. The label
`6bc37ea-dirty` comes from untracked inspiration PNGs in the treecube checkout that do not reach
the output; nothing in tt-sim compares `palette_version` (it is stamped into new maps and read
back, and `test_palette_builtin.gd` only requires it non-empty). No code change, no saved map migrated.
Refreshed 2026-10-13 with treecube 20d9451 (the grass rework, flowers and grass grounds, four
review rounds: treecube `docs/looks/grass_flowers.md`; `palette_version` `3cd0fc3-dirty`, 201
assets, 29 surfaces, ids unchanged). A script checked before the install that the asset, biome and
surface ids are identical, that no species, biome or asset key is new (only each rule's `clump`,
`near`, `pattern`, `density_per_m2` and `min_spacing_m` values changed, in six biomes), that all
every `Rock_*`, `Stone_*` and `Tree_Dead` GLB is byte-identical, that the 19 burnt forest GLBs, its
biome record and `ash`, `dirt` and `dirt_peat` are byte-identical (its thumbnail is re-rendered
with the other eight), and that the 78 GLBs that differ are exactly the `Grass_*` (54) and
`Flower_*` (24) of eight biomes. The six grass grounds (`grass`, `grass_meadow`, `grass_savanna`,
`grass_forest`, `grass_birch`, `grass_alpine`) got new maps (all four of each) and `tile_m` 4
instead of 2; nothing in tt-sim assumed 2 m (the shader, `GroundLayerBinding` and the crossings
read `tile_m` from the palette). Every sidecar was restored by the first checkout; `git status`
checked twice, the same 78 GLBs, 24 surface PNGs, `palette.json` and 9 thumbnails (112 files) both
times; the import reimported those 111 binaries and extracted no texture, `git lfs status` lists
every GLB, PNG and JPG as LFS and only `palette.json` as Git. The grass is much shorter (the
meadow's tall grass 1.45 to 0.58 m, its clumps 1.06 to 0.38 m, the savanna's dry grass 1.30 to
0.76 m), so `ScatterGround.TALL_COVER_M` (0.75 m) now makes the meadow's grasses short cover and
its daisy (0.77 m) tall cover: `test_scatter_ground_rules.gd` expects that, with the savanna's seed
grass and dry grass as the tall grass. (Since then a grass clump has its own line,
`ScatterGround.GRASS_TALL_COVER_M` 0.34 m, so the meadow's grass thins beside paths again;
ARCHITECTURE.md "Terraces and paths stay legible".) The stemmed flowers keep a surface in the uncompressed
vertex layout, but the stemless `Flower_Carpet_*` no longer has it, so
`WindFoliage.pick_representatives()` now takes the first stemmed flower (a carpet only when there
is none) for the graphics warm-up. Home captures at seed 1234 (canopy fade off) for grassland
meadow, savanna, wetland and alpine meadow match the maker's frames
(`treecube/out/looks/grass_flowers4/new_*.png`) in mean colour within 4.5 of 255 (two within 1.2),
and show the darkest and brightest tenth up to 8 apart; the gap is the maker's, not the
install's: its round 4 swapped only the `Grass_*` and `Flower_*` GLBs into a worktree with the old
`palette.json` and old ground maps and the old rocks, so flower drifts, the ground and the rocks
differ by design. No saved map was migrated.
Refreshed 2026-10-14 with treecube 66866b3 (palms and ferns in the painted style, rounds 1 to
3c, approved by the user 2026-10-14: treecube `docs/looks/palms_ferns.md`; built from main
f67d3bb, `palette_version` `f67d3bb-dirty`, 201 assets, 29 surfaces, ids unchanged). A script
checked before the install that the asset, biome and surface ids are identical, that the 8 GLBs
that differ are exactly the palms and ferns (the savanna's `Palm_Tall`, the wetland's
`Palm_Short` and two `Fern`, the temperate forest's `Fern`, and the `Fern_Small` of birch
woodland (one) and the taiga (two)), that the only `palette.json` change is those 8 records'
`dimensions_m`, and that every other GLB, the burnt forest's 19 GLBs and biome record, and every
surface map are byte-identical (the thumbnails are re-rendered). The first build took its
surfaces from treecube's default `out/surfaces/`, which held later, unshipped ground work: all
24 maps of the six grass grounds differed. The palette was rebuilt with `--surfaces` pointed at
the installed `assets/palette/surfaces/` (the same `<name>/<name>_<channel>.png` layout), and
then every map matched; build from the shipped maps whenever `out/surfaces/` may hold work in
progress. Every sidecar was restored by the first checkout; `git status` checked twice, the same
8 GLBs, `palette.json` and 9 thumbnails (18 files) both times; the import reimported those 17
binaries and extracted no texture, and `git lfs status` lists every GLB and JPG as LFS and only
`palette.json` as Git. The frond materials carry `tt_foliage_light` "painted" and the palms their
shade floors (section 6; the savanna palm 394 triangles, the wetland short palm 312, the ferns 35
to 81). The palms stand lower (the savanna palm 7.86 to 7.04 m, the wetland short palm 4.52 to
4.09 m) and the ferns spread wider and flatter (the big ferns 1.4 to 1.8 m across, were about
0.75, and 0.52 to 0.62 m high; the small ferns 0.15 to 0.22 m high, were 0.24 to 0.30), all
under `ScatterGround.TALL_COVER_M`, so no fern changes role; no test pinned their bounds.
Captures at seed 1234 (canopy fade off, and at zoom 9 and 5 the close-zoom canopy fade too): the
savanna's one palm at that seed (near the east edge) draws whole, a leaning scaled trunk under
broad lime fronds lit on top over darker undersides with an olive old frond hanging; the
wetland's short palms read teal-green, not navy, among the pale willows, as in the maker's frame
(`treecube/out/looks/palms_ferns3c/new_palm_wetland.png`, compared by eye); the ferns draw as
teal frond strokes; no texture is missing. No code change, no saved map migrated.
Refreshed 2026-10-15 with treecube 020bbdc (the ground ship: round 20's ground look and grass
masses, this section's `ground_look`, mass fields and `albedo_mean_linear`; `palette_version`
`020bbdc`, 9 packages, 201 assets, 36 surfaces). Six biomes are zoned (carry a `ground_look`):
grassland meadow, savanna, birch woodland, wetland riparian, alpine meadow and temperate
forest; the boreal taiga, rocky badlands and burnt forest carry none and draw as before. The
pre-install check (treecube `out/ground_ship_card2b_tools/parity.py`) found no asset id change;
51 GLBs differ from the previous install (Grass 41, Rock 7, Stone 3, all in the zoned packages,
each byte-identical to round 20's palette) and every other GLB is byte-identical; the burnt
forest, taiga and badlands records are identical. Seven surfaces are new (`dirt_mud`,
`dirt_opening`, `forest_floor_litter`, `grass_glade`, `grass_wetland`, `gravel_scree`,
`sand_savanna`, all of role ground) and six keep their ids with new maps
(`dirt_road_caliche`, `dirt_road_packed`, `grass_alpine`, `grass_birch`, `grass_meadow`,
`grass_savanna`); every surface gains `albedo_mean_linear`. The zoned biomes' accents moved to
the clean ids (grassland `dirt_opening`, savanna `sand_savanna`, birch `forest_floor_litter`,
wetland `dirt_mud`, alpine `gravel_scree`, temperate forest `moss` and `grass_glade`) and the
wetland's ground is `grass_wetland` (was `grass`), so no biome's ground is `grass` any more (a
saved map on base `grass` no longer borrows the wetland's base dressing). Install: `build_palette.py --no-build
--install`, the tracked sidecars restored by checkout, a sidecar for each of the 28 new maps
with `grass`'s `[params]` per channel, then the import; the three untouched biomes' re-rendered
thumbnails were left at their committed copies. `git lfs status` lists every PNG, GLB and JPG
as LFS and only `palette.json` and the new `.import` sidecars as Git. At seed 1234 only the
six zoned biomes' grass rows moved (`tests/fixtures/scatter_golden_1234.json` re-pinned: 34
assets; the taiga, badlands and burnt forest digests unchanged). In the grassland and the
savanna the massed grass now delivers about a third to a half of its palette density
(`test_scatter_generator_calibration.gd` pins those six ratios), and generating a whole flat
200 ft map on one thread takes 19.3 s for the savanna and 11.9 s for the grassland (the taiga
1.0 s), past that test's 15 s regression guard, which was left failing for a decision. Captures
(treecube `out/looks/ground_ship/install/`, `jobs/ground_install.json` and
`ground_install_levels.json`): the round 20 look holds against round 20's frames (mean colour
within 6.5 levels, mostly where the renamed accents moved; birch within 0.2), a level saved by
main's build reopens with its rows and takes the zones, and a Blender GLB level draws as on
main.
Refreshed 2026-10-21 with treecube 0818ee7 (the species merge: four looks the user approved on
the review board and chose to ship together, "All four", 2026-10-21: the rocky badlands' sword
rosette (round 12 T3), the flowering bush (C7 with colour L4) in birch woodland and grassland
meadow, the alpine bellflower (round 7), and alpine meadow's magenta carpet turned gold;
`palette_version` `0818ee7-dirty`, 9 packages, 213 assets, 36 surfaces). The pre-install parity
(treecube `out/flow/rosette_ship/install_I1_parity.txt`) found the package, biome and surface ids
and their order unchanged and 12 asset records added, none removed or changed:
`Rosette_Sword_summer_20..22` (rocky badlands), `Bush_Flowering_summer_23..25` (birch woodland),
`Bush_Flowering_summer_22..24` (grassland meadow) and `Flower_Bellflower_summer_24..26` (alpine
meadow). One GLB changed, `alpine_meadow_summer_s1/Flower_Carpet_Magenta_summer_23.glb`, now gold
under its old id. In the rules, the badlands' `dry_grass` and `dry_tall` avoid the rosette by
1 m and four densities differ in the last bit only. Every burnt forest GLB, `ash`, `dirt`,
`dirt_peat` and every surface map are byte-identical. Install: `build_palette.py --no-build
--install`, the tracked sidecars restored by the first checkout, the re-rendered thumbnails of
the five untouched biomes (taiga, burnt forest, savanna, temperate forest, wetland) put back at
their committed copies, a minimal sidecar for each of the 12 new GLBs, then the import, which
gave each its uid and the three settings and extracted no texture. `git status` checked twice:
one GLB, `palette.json` and four thumbnails modified, 12 GLBs and their sidecars added; `git lfs
status` lists the GLBs and JPGs as LFS and `palette.json` and the sidecars as Git. The rosette's
`keep_colour` does not reach the palette (this section's `keep_colour` field), so
`PaletteLibrary` reads it as false; it changes nothing in the badlands, which bind no tuft
colour. At seed 1234 only
those four biomes' rows moved (`tests/fixtures/scatter_golden_1234.json` re-pinned: the new
species' rows, and neighbours' rows in the same biomes: birch's round bushes, a log and the
sapling, grassland's round bushes and a medium rock, the badlands' six grass rows; the taiga,
savanna, temperate forest, wetland and burnt forest digests unchanged). The rosette is sparse:
none in the golden's 24 m square, 9 plants in an 80 m square at full painted density (about 5 %
of its 0.0264 per square metre). `test_scatter_generator_calibration.gd` measures it delivering
0.047 of that density, under its floor of 0.091 (0.55 of the plan's packing cap, 0.165: the
clump of 0.075 parents per square metre, 0.9 m radius and children 1.2 m apart cannot hold the
density, and five avoid relations thin it further). The user kept that sparse look over a denser
badlands ("Keep as approved", 2026-10-21), so the test pins the rosette's ratio at 0.047 with the
grass masses' 15 percent, until treecube states the density the rosette delivers. Bench check
(treecube `out/bench/rosette_install`, `_bell`, `_bush`, each round's `install_diff.txt`): the
installed palette's `_sub` frames equal the overlay's, through which the user approved the looks,
on every view of the badlands and the grassland; alpine's turned views differ on 13 to 16 pixels by
one level, and birch's frames, bare ones included, only in a 64 px band at the right edge. No code
change, no saved map migrated.
Refreshed again 2026-10-21 with treecube 936bbbe (the rosette's honest density, approved by the
user on the review board, item `rosette-density`: "Install it"; `palette_version` `936bbbe-dirty`,
213 assets, 36 surfaces). Only `palette.json` was copied: every GLB and surface map is
byte-identical, the nine re-rendered thumbnails differ only by render noise and stay at their
committed copies, and the one rule change is the sword rosette's: no clump, `density_per_m2`
0.0264 to 0.001344 and `min_spacing_m` 1.2 to 0.8. The plan had modelled the old rule correctly
(treecube `out/flow/rosette-density/handoff.md`: parents 1.008 of their target, clump membership
0.116 against 0.118 modelled, the five avoids keeping 0.039 against 0.035): it asked for a density
no field at 1.2 m spacing could pack. Placed singly at random, the rosette now delivers 1.03 of its
target over 12 seeds (8.9 per 80 m square against 9.4 before), so the calibration test's pin is
gone and it sits in the random band. At seed 1234 only the badlands' six grass rows moved (the
grass now avoids the rosette at its real density) and the golden square holds one rosette.
Refreshed 2026-10-22 with treecube 1931dac (the wetland bromeliad, approved by the user on the
review board: round 4's L2 look and placement P2 "more"; `palette_version` `1931dac-dirty`, 9
packages, 216 assets, 36 surfaces). The pre-install parity (treecube
`out/flow/bromeliad/install_parity.txt`) found the package, biome and surface ids and their order
unchanged and three asset records added, none removed or changed:
`wetland_riparian_summer_s1/Bromeliad_summer_24..26`. The wetland's species list gains `bromeliad`
between `log` and `reeds` (kind grass, small, random, density 0.034425, spacing 0.8 m, avoiding
willow by 4.1 m, poplar 2.1, palm_short 2.4 and bush 1.5 with a 0.5 m transition, `keep_colour`,
and `avoid_bare` 0.01, the field above); four wetland densities differ in the last bit only. Every
other GLB, every burnt forest file, `ash`, `dirt`, `dirt_peat` and every surface map are
byte-identical. Install: `build_palette.py --no-build --install`, the tracked sidecars restored by
checkout, the eight untouched biomes' re-rendered thumbnails put back at their committed copies
(the wetland's new one keeps: its lineup now holds the bromeliad), a minimal sidecar for each of
the three new GLBs, then the import (uid and the three settings, no texture extracted). `git lfs
status` lists the GLBs and the JPG as LFS and `palette.json` and the sidecars as Git. At seed 1234
only the wetland moved (`tests/fixtures/scatter_golden_1234.json` re-pinned): eleven bromeliad rows
appear and the fallen log drops from five rows to two, because random spaced species of one size
class share a Matern field (`ScatterPlan._plan_groups`) and the bromeliad joins the log's. The
bromeliad delivers 0.58 of its palette density in `test_scatter_generator_calibration.gd` (0.67 on
its 200 ft map; treecube's bench measured 0.75 at full paint over 200 seeds): its canopy avoids and
the mud take that share, and the density was raised for the mud by the approved factor, not to meet
the band, so the test pins the ratio at 0.578 with the grass masses' 15 percent. Bench check
(treecube `out/flow/bromeliad/install_sheets/`, job `bromeliad_install.json`): at the home view of
map seeds 1234, 1 and 2 the installed palette draws the scene the user approved through P2's
overlay, the bromeliads at or near P2's spots (in view: P2 3, 4 and 11, installed 4, 5 and 10);
the one P2 bromeliad that stood on drawn mud (seed 2) is gone and no installed one stands on mud.

## 10. Avatar kit (figurine -> tt-sim, for player avatar tokens)

A third path: figurine (`D:/dev/tabletop/figurine`, a Blender 5.2 extension) generates a kit of
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
seams and raised the head to 0.33 m. The body-template card (2026-10-08) rebuilt the
body as one connected fixed-topology mesh with per-side regions, a hide buffer, the
five body-attribute shape keys and a shared neck ring with the head (the sections
"Regions and hiding" and "Shape keys" below). The look's rules are in
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
  The body-template card (2026-10-08) moved the hip joints down 3 cm (hip 0.75 m, knee
  0.43) for slightly shorter legs, the pelvis above them taller by the same, so every
  other bone and chain root kept its height.
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
  two-handed grip), at every proportion corner (the eight corners of height, build and
  head, the default, and since the body-template card each attribute's two ends and six
  combinations, 25 in all; figurine `posecheck.py`: joint limits in
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
- The body is one connected mesh of fixed topology (the body-template card,
  2026-10-08; figurine `bodymesh.py`): every vertex and face keeps its index in every
  primitive across recipes, proportions and shape keys, so hide masks, region ids, paint
  and (the next card) garment bindings all key off the same stable index. The arms leave
  the torso through an armhole ring and the legs through a groin loop (no limb root is
  buried inside the torso any more), the hands are continuous with the forearms (a palm,
  a knuckle ring, an index finger, a three-finger block divided by ink, a thumb), the
  shoes continue the shins, and the neck ends at a 20-vertex throat ring that the head
  mesh shares vertex for vertex (same positions, same `Head` weights, the same normals
  in both GLBs), so the two parts meet without a seam. Its primitives are the regions
  below; its two UV sets are fixed per face (the palette slot and gradient v on
  `TEXCOORD_0`, the detail island on `TEXCOORD_1`), so the layout is part of the
  contract: a kit whose body changes topology bumps `kit_version` and regenerates every
  part built on it.
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
- Shape keys (glTF morph targets; the foundation card, extended by the body-template
  card, 2026-10-08). The body carries six, each a real per-vertex delta on the fixed
  mesh, and every garment derived from the body carries the same six (the delta of the
  body point it was built from), so a figure's parts change together:

  | Key | Control (recipe `proportions`) | Weight over the control (kit.json `shapes` points) | What it moves |
  |---|---|---|---|
  | `build_plus` | `build` | 0 up to 0.5, rising to 1 at 1 | the plus-size body (below) |
  | `frame` | `frame` | -1 at 0, 0 at 0.5, +1 at 1 | slender to broad: the ribcage's breadth, a touch of limb thickness |
  | `shoulders` | `shoulders` | -1 at 0, 0 at 0.5, +1 at 1 | narrow to broad: the shoulder line out at the acromion; the `shoulders` control also lengthens the clavicles (`proportions`), which carries the arms out |
  | `hips` | `hips` | -1 at 0, 0 at 0.5, +1 at 1 | narrow to wide: the pelvis at the sides, a little on the seat and the tops of the thighs |
  | `chest` | `chest` | -0.35 at 0, 0 at 0.5, +1 at 1 | flat to full: two soft mounds forward on the chest |
  | `waist` | `waist` | -0.6 at 0, 0 at 0.5, +1 at 1 | straight to defined: the waist pulled in at the sides and the small of the back |

  The attribute keys' weights are signed: the consumer sets the blend shape to the
  piecewise-linear value as given, negative included (Godot's `set_blend_shape_value`
  takes any float). The default of every control is 0.5, the modelled body; any
  combination of the five attributes is valid and the producer checks every stance at
  each attribute's two ends and a set of combinations. Names are the attributes, never a
  gender (figurine `docs/design.md`). An old recipe without the attribute controls is the
  default body. `build_plus` is the high end of
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
harmonious; there is no free colour picker. `hides` names body regions a part covers
(the next section). Proportion controls are normalised 0 to 1 and map linearly onto
each listed bone's range (a `Left` bone implies its `Right` mirror); a control with no
bones (`frame`, `hips`, `chest`, `waist`) drives a shape key alone.

### Regions and hiding

Every body face carries a named region (the body-template card, 2026-10-08): its
primitive's material name, which is also the surface's name. The regions, in the GLB's
primitive order:

`hips` (the pelvis from the groin loop up to the waist, the shorts), `torso` (waist to
the neckline, the tee), `neck` (never hidden), `upper_arm_l`, `forearm_l`, `hand_l`,
`upper_arm_r`, `forearm_r`, `hand_r`, `thigh_l`, `shin_l`, `foot_l`, `thigh_r`,
`shin_r`, `foot_r`. The body's kit.json entry lists them (`regions`), and a part's
`hides` names the ones it covers completely; the consumer drops a hidden region's faces
so nothing pokes through a garment.

The one-ring buffer: a hidden region keeps a ring of faces at each boundary where a
neighbouring region still shows, so a garment's opening never shows a hollow edge. The
body's entry carries `region_rings`: per region, `runs`, its faces grouped by ring band
as `[start, count]` pairs in the primitive's triangle order (consecutive from 0), and
`keep`, a list of `[run, [neighbour regions]]`: that run stays visible while the region
is hidden if any of the named neighbours is visible (`head` is always visible). For
example `upper_arm_l` keeps its first run (the armhole band) while `torso` shows and its
last run while `forearm_l` shows; `torso` also keeps its two armhole runs while either
upper arm shows. The consumer builds the hidden mesh by filtering each primitive's
index buffer to the kept runs (an all-hidden primitive is dropped). A consumer that
ignores `region_rings` and drops whole primitives still shows a correct figure with the
first kit's garments, which cover their regions' boundaries.

### Recipe (an avatar, format 1)

```json
{"format": 1, "kit_version": "...",
 "parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun", "top": "top_tee"},
 "colours": {"skin": 3, "hair": 7, "eyes": 2, "primary": 11, "secondary": 4, "accent": 0},
 "face": {"eyes": 2, "brows": 1, "mouths": 0, "marks": 1},
 "proportions": {"height": 0.6, "build": 0.4, "head": 0.5,
                 "frame": 0.5, "shoulders": 0.7, "hips": 0.3, "chest": 0.5, "waist": 0.6},
 "stance": "stance_ready"}
```

The five body attributes (`frame`, `shoulders`, `hips`, `chest`, `waist`; the
body-template card) are proportion controls like the others: 0 to 1, 0.5 the modelled
body, each driving its shape key (and `shoulders` the clavicle length); a recipe that
omits them (every recipe before the card) gets 0.5. The builder shows them as
attribute-named sliders ("Frame: Slender to Broad", "Shoulders: Narrow to Broad",
"Hips: Narrow to Wide", "Chest: Flat to Full", "Waist: Straight to Defined") and
Surprise me draws each independently.

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

## 11. Importing a map GLB (the library's Import, Replace map and Reload from Blender)

How a terrain-paint export (or any glTF Binary map) enters a player's library, decided for
the v0.2 map flow on 2026-10-09. Consumer: `utils/glb_check.gd` (`GlbCheck`, the check),
`utils/map_import.gd` (`MapImport`, import and replace), `utils/import_sources.gd`
(`ImportSources`, the source index), `utils/dressing_reconcile.gd` (`DressingReconcile`,
Keep dressing). Tests: `tests/unit/test_glb_check.gd`, `tests/unit/test_map_import.gd`.

**What is accepted.** One self-contained `.glb` (glTF Binary, version 2). Everything is
refused with one sentence, before anything is written:

| File | Refusal |
|------|---------|
| `.gltf` | its buffers and textures are separate files, and a level bundles one file |
| `.tscn` / `.scn` | a Godot scene, not a map export |
| a `.glb` whose buffers or images name a file by URI (not `data:`) | those files would not travel with the level |
| anything else, or a file without the GLB header | not a glTF Binary export |

terrain-paint's Export glTF already writes this form (textures packed). Nothing else about
the file is required: the extras (section 4), names (section 3) and attributes (section 5)
are read as they are for any map.

**The check, shown before anything is written** (`GlbCheck.check`, pure, reads only the
GLB's JSON chunk, so a 50 MB map is checked in milliseconds):

- file and size in MB;
- the footprint in metres and feet (X by Z) and the floor height, from each mesh's
  POSITION accessor `min`/`max` carried through the node transforms. The instance-source
  nodes named in `tt_scatter_instances` are left out: tt-sim frees them on load, and
  Blender may have left them anywhere;
- what the extras hold: ambient light, background colour, scatter species and instance
  counts, and any keys tt-sim does not read;
- mesh, collision (section 3 suffixes), `-water`, light and image counts.

**Warnings never block.** The author reads them and imports anyway if they choose.

| Warning | When | Why |
|---------|------|-----|
| units | the longer side is under 3 m or over 1,000 m | section 2: 1 unit = 1 m; a centimetre export is 100x off |
| floor | the lowest point is more than 0.5 m above Y = 0, or the whole map is below it, or the lowest point is deeper than 10 m | section 2: floors sit at Y = 0, where the table grid is; a carved pond or river bed below 0 is normal and does not warn |
| streaming budget | the file is over 32 MB | every joining player downloads it once, one peer at a time at about 1 MB/s compressed (`docs/NETWORKING.md`; a 20.5 MB map took about 13 s per peer) |
| no ground | no mesh has bounds | nothing to stand tokens on |

**Import** makes a new level folder (named after the file, or after its folder when the
file is `map.glb`), copies the file to `map.glb` before writing `level.json`, so
`level.json` never names a file that is not there, records the source path in the local
index, and renders the card's thumbnail offscreen from the table camera's angle
(`LevelThumbnail`; none under the headless renderer, and any later Save replaces it).

**`map_scale` and `map_offset` are legacy.** An import never moves or scales the map: it
plays at 1 unit = 1 m with the floor at Y = 0 (section 2). Both fields are still read
and applied for old levels that set them, but `level.json` carries them only when they
are not identity, so no new import or new map writes them.

**Source index.** `import_sources.cfg` under the data root (`Paths.import_sources_path()`),
beside `levels/`, never inside a level folder: it is local to this machine and is never
listed, duplicated or streamed. One section per level folder: the source path and the
import time. Deleting a level forgets its entry. **Updated in Blender** is a comparison of
two files, not a stored time: the source file is newer than the level's `map.glb` copy.

**Replace map** (a picked file) and **Reload from Blender** (the remembered source) run the
same check, then the author chooses:

- **Keep dressing**: the level's `map.ttmap`, if it dresses the GLB (`has_base_map`), stays.
  Its heights are the GLB's ground and are refit from the new collision on the next open and
  at every play load (`MapSourceLoader.fit_dressing_ground_async`), which also sets the
  generated rows down on it. Props and generated rows outside the new footprint are dropped
  and counted, and the painted biome cover outside it is cleared; a map that reaches past
  the document grows it (every per-sample layer carried by position; the baked flow map is
  cleared). Props keep their saved height. A level whose ground was built in tt-sim (a
  document without `has_base_map`) can only Start fresh.
- **Start fresh**: the old document is kept as `map.ttmap.bak` (never streamed: the level
  map whitelist is `map.glb` and `map.ttmap` only) and the level is a plain Blender map.

Either way `map.glb` is written first, then the document, then `level.json`; tokens and
the level's look are untouched, and the index records the new source.

**Round trip.** `test_map_import.gd` imports a GLB written by `GLTFDocument` (with
`tt_scatter_instances` patched into the scene extras as terrain-paint does), replaces it
with a smaller one under a dressing document, and loads the result through
`GlbUtils.load_map`: the footprint the check reported matches the loaded ground's bounds.
A real terrain-paint export has not yet been through it; the first one through the
library's Import is the producer-side check.

## 12. Structures (partly built 2026-10-28)

Status per part. **Built (card S1):** the map entry `structures.json`, the `Structure` record, its
validation, the live edit and the fingerprint key (the **Map** bullet below; model and rules in
`systems/structures.md`). **Built (card S2):** the build (`StructureGeometry`, `AuthoredStructures`,
worker prep, collision, scatter clearance), the plan rules (`ProcgenPlan` in the map reader), the
triangle budgets (12k soft, 25k hard, enforced per structure), a first role table and pinned digests
of the starter set at `tests/fixtures/structure_digests.txt`; recipes come from procgen's
`recipes/` folder through a temporary resolver. **Proposed, not built:** the library kind, the
determinism gate on every platform, the painterly role table and the per-map budget. The full
design is the gitignored `docs/plans/2026-10-28-structures/design.md`.

Producers: procgen (the generator core), structgen (the editor); consumer: tt-sim. Buildings are
NOT exported as GLBs: a structure is a recipe plus inputs that every peer rebuilds.

- **Recipe.** A `.structure.json` in the procgen graph format (`plantgen-graph`). Its document
  `interface` is the parameter contract (name, default, min, max); a node param `"@name"` binds
  to it. structgen's custom footprint (the Guide node's `host_footprint` param) is a preview
  default only; tt-sim ignores it.
- **Inputs tt-sim supplies** (`ProcgenStructureInputs`): `guide` a closed polygon in map XZ
  metres (3 to 24 points, simple, edge 0 is the front and carries the door, winding as
  `ProcgenGuide.plan_area` defines), `params` (only values that differ from the defaults),
  `env` the map's ground, `seed_value` an integer stored with the structure (never derived from
  a Variant `hash`).
- **Outputs tt-sim reads** (`evaluate_structure(..., with_layout)`): surfaces of kind `stone`,
  `masonry` (UVs in metres, textured form) and `wood`; per-vertex provenance `tags` into
  `tag_table` (node id, then slot path); `collision` faces, `top`, `openings` and the final layout
  (volumes, openings with slot provenance). Triangle winding clockwise, meshes closed (the
  `ProcgenMeshCheck` rule). Material roles are derived from the node type of a tag's node:
  wall, roof, trim, chimney, opening (one table, shared by structgen's palette and tt-sim).
- **Library.** `structures/index.json` (format `ttsim-structures` 1), `structures/<id>.structure.json`,
  `thumbnails/structures/<id>.jpg`; core adds `structures/pins.txt` (an md5 digest and triangle
  count per structure at its default footprint). Not part of `assets/catalog.json`.
- **Map (built).** `structures.json` in `map.ttmap`: `{"version": 1, "structures": [{id,
  recipe: "<library>:<id>", footprint, seed, params, style}]}`. `id` 1..255 and unique; at most
  128 structures and 1 MB; `recipe` a `LibraryIds` reference (library id, structure id
  `[a-z][a-z0-9_]*` without `__`); `footprint` 3 to 24 `[x, z]` points in map metres, finite, on
  the map, at most 64 m across, edge 0 the front, and accepted by `ProcgenPlan.problems()` (simple,
  wound positively, sides at least 0.5 m, corners at least 15 degrees, at least 2 m2); `seed` a whole number 0..1e9; `params` at most 16 entries, each a bool or a
  finite number within 1e6 rounded to 0.01; `style` a short string. Footprint points are float32
  values (the editor snaps them to 1 cm) and the file is byte-identical across a load and a save.
  A bad record is skipped with a warning; the writer refuses a bad document. The same list
  travels as the live-edit kind `structures` (whole list, validated by the same reader). The
  `libraries` record will name the libraries whose recipes the map uses (library card, not
  built); `MapFingerprint` has the key `structures`. Code: `Structure`, `MapStructureIO`,
  `StructureEditor`; hub: `systems/structures.md`.
- **Determinism.** The same recipe, inputs and seed must build the same mesh on every peer. Measured
  on Windows only: repeated and worker-thread builds give identical digests (12 cases). Linux
  is covered for the self-check samples; the 42 building digests are not yet run on every
  shipped platform. Nothing authoritative may depend on bit-equality of a built structure.
- **Budgets.** Per structure 12k triangles soft (a warning), 25k hard (refused with a reason; built
  in S2); per map about 150k (proposal, not enforced); textured masonry is the default for core;
  evaluation of a starter structure is 2 to 45 ms.
- **Roles (first table, S2).** Material roles come from the node type of a vertex's tag: wall
  (`building_walls`, `building_timber`, `facade`), roof (`roof_gable`, `roof_hip`, `roof_flat`; its
  own material only where the surface is planks), trim (`facade_trim`, `cornice`, `quoins`), chimney
  (`roof_furniture`). tt-sim adds a pane (opening) quad in the middle of each opening box, since the
  recipes' walls are hollow. The table is `StructureLook`; the painterly version is card S6.
- **Round trip.** A structure change is done when a recipe from a library folder builds through
  tt-sim's `StructureGeometry` with its pinned digest, a token stands on its roof, and the map
  saves and reloads with the same fingerprint (`test_structure_build.gd` does all three for the
  starter set).
