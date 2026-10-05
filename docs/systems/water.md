# Water

Authored water (phase 4): rivers and ponds drawn in-game live in the map document as a few
bodies, each flat at one level; the surface, the carve that shapes the ground under them, the
wet dressing on the banks and the flow map are all derived from those bodies and the heights, so
every peer builds the same water from the same few numbers. The authoring bar is one gesture: a
river drawn in one stroke splits itself into flat reaches joined by small rapids, carves its
channel, closes its ends in rounded heads, joins the water it meets and dresses its banks, with
no further control. The visual bar is the water shader's painterly read: luminous shallows, white
water on the riffles and a soft waterline, never a crisp, slightly opaque plane.

Waterfalls (the fall-or-riffle rule, the fall carve, the curtain) are in
[waterfalls.md](waterfalls.md); plank bridges and stepping stones in [crossings.md](crossings.md).
The document entries (`splines.json`, `ponds.png`, `water_flow.png`, their caps and the reader's
rules) are in [../ARCHITECTURE.md](../ARCHITECTURE.md) "Map document (map.ttmap)", Water bullet.
The Water tool's gestures and pane are in [../UI_SYSTEMS.md](../UI_SYSTEMS.md) (authoring
drawer, Water; "Brushes and gestures").

## Map

| File | Class | Role |
|------|-------|------|
| `resources/water_body.gd` | `WaterBody` | One body: stable id, kind (river or pond), depth class, `level_m`; a river's control line, half-widths and speed |
| `resources/map_document.gd` | `MapDocument` | `water_bodies`, `pond_mask`, `water_flow` / `water_flow_size`, `water_dressing` (a derived cache), `next_water_id()` |
| `utils/map_water_io.gd` | `MapWaterIO` | Writes and validates the water entries for `MapDocumentIO` |
| `utils/water_geometry.gd` | `WaterGeometry` | Pure: smoothed courses, areas, levels, wet samples, `reach_ranges`, `nearest_field`, `river_courses` |
| `utils/water_flow_baker.gd` | `WaterFlowBaker` | The flow map bake |
| `utils/water_mesh_builder.gd` | `WaterMeshBuilder` | Pure: the merged surface mesh, `sample_owners`, cascades, zone tiles, `snapshot` |
| `scenes/terrain/authored_water.gd` | `AuthoredWater` | The node under the map root: mesh, surface bodies, zones, `refresh_map()`, the shared fall material |
| `utils/water_surface.gd` | `WaterSurface` | Water as ground: its collision layer, `landing_y`, `floats_at`, `is_submerged`, `surface_below` |
| `scenes/effects/water_zone.gd` | `WaterZone` | Per-body detection slabs for splashes, wakes and the visual sink |
| `utils/water_glb_utils.gd` | `WaterGlbUtils` | `process_water_meshes()`, `apply_water_settings()`, the shared water material and the flow map plane |
| `shaders/water.gdshader` | | The surface shader: `water_flow()`, shallows, foam, the waterline |
| `utils/water_carve.gd` | `WaterCarve` | Pure: cross-section goals, `bed_line`, reach steps, the pond basin, `keeps_rock`, `min_half_width` |
| `utils/water_edit.gd` | `WaterEdit` | Pure model edits: `plan_river`, `join_line`, `touch_rivers`, `erased_bodies`, `model_of` |
| `utils/water_dressing.gd` | `WaterDressing` | The wet dressing rule layer (bed, shore, depth, wet line) |
| `scenes/states/authoring/water_editor.gd` | `WaterEditor` | `AuthoringEditor.water`: the editor API, the worker carve, `refresh`, one history entry per edit |
| `utils/distance_field.gd` | `DistanceField` | Exact Euclidean transform for the basin carve and the dressing |
| `utils/ground_height_field.gd` | `GroundHeightField` | The grid's ground field with the water levels composed in (`raise_to_water`) |
| `utils/scatter_ground.gd` | `ScatterGround` | `wet_factor`: what grows in and by the water |
| `scenes/states/authoring/rock_keeper.gd` | `RockKeeper` | Rocks kept as props through a carve |
| `scenes/states/authoring/water_brush.gd`, `water_tool_pane.gd` | `WaterBrush` | The Water tool (`UI_SYSTEMS.md`) |
| `utils/river_exits.gd` | `RiverExits` | Pure: which river ends leave the map, their course past the edge (drawn or derived), the drawn line's split |
| `utils/river_exit_mesh.gd` | `RiverExitMesh` | Pure: the skirt's channel patch and the water ribbon past the edge |
| `scenes/terrain/skirt_exits.gd`, `skirt_backdrop.gd` | `SkirtExits`, `SkirtBackdrop` | The skirt's channel and ribbon nodes; the opaque skirt's backdrop and fog |

## Model

Phase 4, P4-1 is data and algorithms only; the surface, carve and tool follow. Plan:
`docs/superpowers/plans/2026-09-27-phase4-water.md` (local).

- **Bodies** (`WaterBody`, `resources/water_body.gd`): a river is a control polyline in
  map XZ (first point upstream, so it flows toward the last) with a half-width per point,
  a flow speed and a depth class; a pond is an area painted on the sample grid
  (`MapDocument.pond_mask`, byte = pond id, like the biome masks, so a brush paints,
  erases and undoes it with the existing byte-mask machinery; a polygon would need its
  own editing and boolean operations). Every body is flat: one `level_m`. Depth classes
  map to metres of water below the level (`WaterBody.DEPTH_M`: ankle 0.3, waist 0.9,
  deep 2.0); tokens stand on the bed in ankle and waist water and float in deep water.
  Ids are stable (`MapDocument.next_water_id()` never renumbers).
- **Areas and wet samples** (`WaterGeometry`, `utils/water_geometry.gd`): everything
  derived from a river follows its course, the control line Chaikin-smoothed twice (as
  terrain-paint does). A river's area is within its half-width (at the nearest point of
  the course) plus `RIVER_BANK_M` (1 m) of it; a pond's is its mask samples. A sample is
  wet when it is in a body's area and its ground is below that body's level; overlaps
  take the highest level (`levels()`, `wet_mask()`, `body_area()`, `wet_samples()`).
  `nearest_field()` is the shared per-segment rasteriser (distance, half-width and
  tangent of the nearest segment on any regular grid). Since P4-3 a river's area stops
  flush at an end another river continues from (the next reach of one stroke: its first
  point is this one's last, `flush_ends()`): the half-plane beyond the shared point is cut
  off, so a reach's flat water ends at the crest the carve leaves there instead of hanging
  round it over the riffle below.
- **Level rules:** a river's level is the lowest ground along its centreline minus
  `FREEBOARD_M` (0.15 m), so the surface stays below its banks all along. A stroke over
  sloped ground is split into flat reaches (`reach_ranges()`: no reach spans more than
  `REACH_DROP_M`, 0.5 m, of centreline ground; consecutive reaches share their boundary
  point), each its own river body; a step of 0.75 m or more between reaches is a waterfall
  ([waterfalls.md](waterfalls.md)). A pond's level is the lowest ground on the rim of its
  area minus the freeboard (`pond_rim_level()`).
- **Waterfalls:** the fall-or-riffle rule (`WaterFalls`, `WaterFallPlan`), the lips the plan
  inserts as forced reach boundaries, the face points freed of the reach rule
  (`WaterGeometry.reach_ranges(ground, max_drop, forced, free)`) and everything derived from
  a fall are in [waterfalls.md](waterfalls.md). Nothing about a fall is persisted; it derives
  from `water_bodies` and the heights.
- **Flow bake** (`WaterFlowBaker`, `utils/water_flow_baker.gd`): terrain-paint's
  `flow_bake.py` field ported exactly (nearest-segment tangent per river, inverse-square
  weights within half-width plus bank, speed per body, not renormalised, box mean over
  0.75 m, |F| clamped to 1, then the bank fade: the wet mask box-blurred 3x3
  `max(1, round(3N / 512))` times), with the wet mask read from document heights below
  the per-sample level instead of ray casts. Ponds add no flow. One map-wide flow map per
  map, because the water shader has one flow sampler per level. Resolution: about 4
  texels per metre (`TEXEL_M` 0.25, the default sample spacing), 244 x 244 on a 200 ft
  map; measured ~0.3 s there with three rivers of 40 points (128: 0.12 s, 256: 0.33 s,
  512: 1.2 s), so a bake on stroke release stays interactive. Deterministic; it ships in
  the document and peers never rebake. A fall's face samples (`WaterFalls.footprint()`) count
  as wet, so the bank fade does not cut the flow at a lip.
- **Frame (the contract with `water.gdshader` `water_flow()`):** the authored water mesh
  sits at the map origin with an identity transform and map-normalised UVs,
  u = (x + W/2) / W, v = (z + H/2) / H. Texel (i, j) is Image column i, row j (row 0 is
  the Image's first row, which Godot samples at v near 0); its centre is at
  u = (i + 0.5) / nx, v = (j + 0.5) / nz. R, G = (flow x, -flow z) * 0.5 + 0.5, because
  the shader reads f = rg * 2 - 1 as Blender-style local (x, y) and rotates local
  (f.x, 0, -f.y) through the model matrix. Border texels are still (128, 128).
  `test_water_flow_baker.gd` decodes bakes through a mirror of `water_flow()`.

## Runtime

Phase 4, P4-2: the document's water as a surface in play and in authoring, and water as
ground for tokens, the grid, the measure tool and the drag ruler, on authored and Blender
maps.

- **One merged mesh** (`WaterMeshBuilder`, `utils/water_mesh_builder.gd`, pure): every body
  in one `MeshInstance3D` named `AuthoredWater-water`, because the water shader has one flow
  sampler per level. Identity transform at the map origin, map-normalised UVs (the flow
  map's frame, above). Coverage is on the document's sample grid: each sample belongs to
  the highest body whose area holds it (`sample_owners()`, WaterGeometry's rule), a cell
  (the quad between four samples) is water when any corner is wet, flat at the level of its
  highest wet corner's body, and one more ring of cells is added where all four corners
  stand at or above that level (`MARGIN_CELLS`, tucked under the banks: the edge stays
  buried when the shader's vertex bob lifts it or a bank meets the surface exactly at a
  sample; a cell with a corner below the level outside the body's area is never added, it
  would show an edge in the air). The shader's depth-based shallows and foam draw the
  waterline where ground meets the surface. The sample grid is the resolution because
  coverage is decided per sample. No shadow; `Constants.BOUNDS_EXEMPT_META` like the skirt,
  so camera bounds and the reflection probe measure the ground. A 200 ft map with a three-
  reach river and two ponds: 10,026 vertices, 18,784 triangles.
- **Node** (`AuthoredWater`, `scenes/terrain/authored_water.gd`, under the map root): the
  mesh, whose surface material is a `StandardMaterial3D` carrying the document's flow map
  (`MapDocument.water_flow`) as its emission texture, exactly where
  `WaterGlbUtils.process_water_meshes()` looks for a Blender plane's; per body a surface
  body and a WaterZone (below); `levels` / `wet` per sample and a `version` for the grid.
  `MapSourceLoader.add_authored_water()` builds it in `_build_async` for any document with
  water (authored root or a dressed GLB's root), always in authoring (so the tools and the
  grid have it from the start), then runs `process_water_meshes(root)`.
- **Refresh (authoring):** `AuthoredWater.refresh_map(map_root, doc)` is the entry the carve
  and the Water tool (P4-3, P4-4) call after an edit: the geometry and the flow bake run on
  a `WorkerThreadPool` task from a snapshot of the document (`WaterMeshBuilder.snapshot`),
  the result is swapped in on a later frame (`refreshed`), and the bake is written into the
  document, which ships it. A request while one runs queues; only the newest queued runs.
  Measured on that map: worker build 84 ms, bake 183 ms, main-thread swap 26 ms (mesh,
  concave shapes, zones, material pass).
- **Dressed maps (GLB plus a document with water):** both kinds of mesh share the one water
  material. The flow map comes from the authored mesh whenever it carries one (the document
  has a river), whatever its size; the GLB's planes then render still water. The author drew
  those rivers on top of the Blender map, the newer and explicit intent, and a GLB plane
  covers the whole map, so the old largest-footprint rule would always silence them. A
  document with only ponds carries no flow map and the GLB's river keeps flowing
  (`WaterGlbUtils._flow_map_plane`). `process_water_meshes()` is safe to run twice over one
  tree (`PROCESSED_META`), as a dressed map does (the GLB's load, then the authored water).
- **WaterZone per body:** `WaterZone.create_for_footprint(name, level, tiles)`: the zone's
  origin on the body's surface (so splashes spawn at it) and one slab box per 5 m tile of
  the body's water (`WaterMeshBuilder.ZONE_TILE_M`, the tile's bounds of the body's wet
  cells), hanging below the surface as a Blender plane's zone does. Bodies at different
  levels (river reaches) each detect tokens under their own surface. Splashes, wakes and
  the visual sink are unchanged. A rebuild releases the tokens a replaced zone held
  (`WaterZone.release_bodies`: a freed Area3D does not report its bodies leaving).
- **Water as ground** (`WaterSurface`, `utils/water_surface.gd`): water stays off the terrain
  layer, so brushes, sculpt and paint rays and a wading token's landing see the bed. Its
  surface is collision on its own layer (`WaterSurface.LAYER`, physics layer 3, bit 4): a
  `StaticBody3D` per authored body (its triangles; `FLOATS_META` says whether it floats
  tokens) and one per Blender `-water` plane (`_attach_surface_body`, no float flag). A
  downward ray on `WALKABLE_MASK` (terrain and water) finds max(ground, water surface). A
  ray exactly through a vertex the surface triangles share can slip between them (seen at
  the map origin); `water_below()` retries a millimetre aside and grid sampling is nudged.
- **Float rule** (`WaterSurface.landing_y` / `landing_below`): a token stands on the bed in
  wadeable water and floats in deep water, its base `DRAFT_M` (0.2 m) below the surface,
  never below the bed (walking out onto a bank is continuous). Authored bodies float when
  their depth class is deep (`WaterBody.is_wadeable`); a Blender plane has no class, so it
  floats a token where the water is at least `FLOAT_DEPTH_M` (1.4 m, between waist and deep)
  deep. River (0.59 m) is wadeable. Used by `DraggableToken._find_landing_position` (the
  water cast starts `CAST_CLEARANCE_M` above the token's top, which can be under deep water)
  and `GameMap._resolve_drag_ground` (authored terrain; on a Blender map it answers only
  over water and keeps the cursor-hit height elsewhere). A floating token bobs its visuals
  (`BOB_M` 0.03 m over 2.6 s, a looping tween), decided locally after a landing or a synced
  move (`WaterSurface.floats_at`), so every peer bobs its own copy; the synced position is
  untouched. Network sync is unchanged (the dragging peer is authoritative). A token the
  water hides (`WaterSurface.is_submerged`: base under the surface, less than 10 cm or a
  fifth of its height above it) shows a `SubmergedMarker` ring on the surface over it, also
  decided locally (P4b-0; UI_SYSTEMS.md "Submerged Token Marker").
- **Grid, measure, ruler, cursor:** the ground field is max(ground, water level) on wet
  samples. Authored: `GroundHeightField.from_terrain()` finds the terrain's sibling
  `AuthoredWater` and composes `raise_to_water(heights, levels)` into an RGF texture (R the
  height, G the water flag), recomposed in place when `AuthoredTerrain.height_version` or
  `AuthoredWater.version` changes; without water the terrain's own R32F texture as before.
  GLB: the grid sampling rays hit the surface bodies (Ground field, above). The grid shader
  lifts a pixel it sees under a flagged surface (the bed, a wading token's legs) onto the
  surface along its view ray (`ground_water_at`, a few fixed-point steps; the facet test is
  skipped there) and draws after the water (`GridOverlay.RENDER_PRIORITY`), so squares stay
  continuous across a river. The measure tool, the drop indicator and the drag cursor ray
  use `WALKABLE_MASK`; the drag ruler measures surface to surface
  (`WaterSurface.surface_below`).
- **Cascades (P4-3):** the steps between reaches and free river ends over a channel carved
  lower carry a sheet of water too (`WaterMeshBuilder.cascades()`, see "Reach steps" under
  Authoring).
- **Waterfalls:** a step that is a fall (`WaterFalls.is_fall`) gets no cascade sheet; the
  lip tuck, the curtain / foam ring / mist mesh (`AuthoredWater-falls`), its shader and the
  shared fall material are in [waterfalls.md](waterfalls.md) (Runtime).
- **Shallows in the shader (P4-5):** the refraction offset grows from nothing at the
  waterline over `refraction_depth_fade` (0.3 m of view depth): at full strength in
  millimetres of water it smeared the lit bed dressing of a steep bank facing the camera (an
  ankle stream's far bank) into a pale glassy band. Deeper water refracts as before, on
  Blender water too. The shore foam and the waterline fade apply only where the surface under
  the water is ground (`shore_ground_gate`: its normal from the depth buffer's screen
  derivatives within about 50-70 degrees of up): reeds standing in the water brought the bed
  depth to zero wherever a blade passed under the surface and drew pale foam and see-through
  shards around every clump (wetland renders). The depth-slope foam that wraps rocks and
  tokens (`fwidth` of the bed depth) fires only where the near side of the depth jump comes
  within `EDGE_FOAM_REACH` (0.3 view units, fading from half of it) of the surface (P4b-0):
  it used to trace every underwater silhouette against the bed behind it, so a boulder
  standing in a deep pool drew a thin straight light line down the water from its waterline
  to the bed (the side of its submerged flank, seen on the forest and badlands pools), and
  submerged reed blades and a wading token's legs were outlined the same way. The near side
  is the shallowest of the pixel and its neighbours across the derivative pair (by
  `FRAGCOORD` parity), so both pixels of a silhouette agree.
- **Not yet:** water on a dressed map is only drawn and floated, and the authoring grid of
  a dressed map is sampled once at open.

## Authoring

Phase 4, P4-3: what a river or pond does to the ground, the plants and the rocks, as an
editor API the Water tool (P4-4) calls.

- **API** (`AuthoringEditor.water`, a `WaterEditor`, `scenes/states/authoring/
  water_editor.gd`, part of the editor that shares its ground machinery; world frame):
  `carve_river(points: PackedVector2Array of
  world XZ, upstream first; half_widths (one per point, or one for all); depth_class;
  speed) -> id of the first reach or -1`; `paint_pond_begin(depth_class, press point) ->
  bool`, `paint_pond_dab(from, to, radius)`, `paint_pond_end() -> bool` (a press inside a
  pond extends it); `erase_water_begin() -> bool`, `erase_water_dab(from, to, radius)`,
  `erase_water_end() -> bool`; `cancel_stroke()`. Pond and erase strokes also answer the
  editor's generic `stroke_dab()` / `end_stroke()` / `cancel_stroke()`. `can_carve()` is
  `can_sculpt()` (no carving on a dressed GLB); erasing works on any map with water. A
  refused carve or pond press says why in `last_refusal` (`REFUSED_NO_CARVE`, `_SHORT`,
  `_FULL`, `_IN_WATER`). Each operation is one history entry: the heights diff
  (`HeightStroke.lower_to`, a one-shot carve recorded like a dab), the water model before and
  after (`WaterEdit.model_of`: body copies and the ZSTD pond mask), the wet dressing before and
  after (ZSTD; undo sets it back instead of recomputing it), the props cells it changed and
  the rocks it kept; undo and redo put both sides back exactly. The scatter then regrows over
  the area grown by the shore band. A sculpt stroke (and its undo or redo) on a map with water
  recomputes the dressing (`WaterEditor.refresh(then)`, P4-5): with `use_worker` on a worker
  from a snapshot, like an edit's compute, landing on a later frame (the field, the ground's
  texture, the surface's refresh), and the stroke's rock keeping and regeneration, which read
  the dressing, run as `then` once it lands; `finish_height_work()` lands it at once. In the
  running game a sculpt release by a river went from 118-119 ms to 28-30 ms worst frame.
- **Worker carve (P4-4):** the heavy, pure half of an edit, `WaterEditor.compute(snapshot,
  spec, out)`, runs on a snapshot of the document (`snapshot_of`: grid, heights, seed, bodies,
  pond mask): the carve goals (`WaterCarve`), the heights lowered to them (`lower()`, exactly
  `lower_to`'s rule), the dressing of the result (`WaterDressing.refresh`) and the owner of
  each sample (`WaterMeshBuilder.sample_owners`, for the rock rule). With `use_worker` (set by
  `AuthoringController` for the Water tool) it is a `WorkerThreadPool` task and the document
  is untouched until it lands; without (tests, probes) it runs at once. `_land()` applies it
  over three frames: the water model, `lower_to` with the computed goals, the terrain's
  chunks, collision and plant snap, and the water surface's rebuild (on its own worker); then
  the terrain settle (`_settle()`: its rule fields over the carve); then (`_finish()`) the
  dressing texture (the first water on a map re-plans the ground's layers and refreshes the
  whole ground), rocks, the regeneration request and the history entry. While an edit computes or lands `is_working()` is true, which
  `AuthoringEditor.has_height_work()` includes (a save or an autosave waits);
  `AuthoringEditor.finish_height_work()` (called before any other edit, undo and save) lands
  it at once via `finish_work()`. The same function computes both paths, so the worker result
  is identical to the synchronous one (`test_water_tool.gd`). Measured on a 150 ft map in the
  render job (frames recorded around the release): worst frame 21-42 ms landing a 45 m waist
  river (42 ms only for a map's first water), 12-23 ms for a stream, 17-30 ms for ponds,
  9-22 ms for an erase, against 0.26-0.66 s
  of main thread per edit before (P4-3, 200 ft; `docs/PERFORMANCE.md` "Water tool").
- **Rivers** (`WaterEdit.plan_river`): the line is resampled every 2 m (`RESAMPLE_M`), each
  half-width clamped to at least `WaterCarve.min_half_width()` of its depth class (ankle
  0.44 m, waist 1.33 m, deep 2.96 m: a narrower channel cannot reach its depth without a
  rock-steep shore), split into flat reaches by the ground under the line (P4-1's
  `reach_ranges`, levels by `reach_level`), each a river body with its own id. The order in
  `plan_river`, with the waterfall steps: join (`join_line`), resample, ground (with the
  level-plus-freeboard override under existing water), orient, fine profile, lips, shape,
  reach split ([waterfalls.md](waterfalls.md), Model).
- **Confluences (P4-4, `WaterEdit.join_line`):** a line that starts or ends in existing
  water (`WaterGeometry.is_wet_at`: ground under `level_at()`, the highest level of the
  bodies whose area holds the point) is cut at that water's edge, found by bisection, and
  ends `JOIN_INSET_M` (0.6 m) into it; points in water between dry stretches stay. Under
  existing water `plan_river` reads that water's level plus the freeboard as the ground, so
  the reach that meets it is at its level (an inflow joins flush) or below it (an outflow
  never stands above the pond it leaves), never down on its bed. The carve leaves such an end
  open (no taper, full width into the other water) and the mesh gives it no run-out sheet
  (`WaterMeshBuilder._run_out` skips an end in other water). A line lying all in water makes
  nothing (`REFUSED_IN_WATER`).
- **Cross-section** (`WaterCarve`): every sample within `BANK_REACH_M` (6 m) of the
  waterline gets a goal from its edge offset e (distance to the course minus the
  half-width; a pond: its signed distance to the edge of its painted area): the waterline
  at e = 0 on the level, into the water the shore slope of the depth class (ankle 1:4,
  waist 0.4, deep 0.65; steepened for a narrow channel up to `MAX_SHORE_SLOPE` 0.9, 42
  degrees, so at least `BED_SHARE` of the width is flat bed) down to the bed at level -
  depth, away from it the bank slope (0.33 / 0.45 / 0.6) until it meets the ground. The
  toe is a smooth maximum (0.25 m); the top of the bank eases the cut in over
  `TOP_SOFT_M` (0.3 m: lowered by d^2 (2 - d / k) / k for a wanted cut d, never more than
  asked), so a crest or waterline is never dug below its goal; the last 2 m of the reach fade
  back to the ground. The carve only lowers (`min(start, goal)`). The steepest bank (31
  degrees) and shore (42) stay below the cliff rule's 44, so a channel is never a rock
  trench unless the ground was rock.
- **Reach steps:** the stroke's reaches are carved as one course (their courses joined,
  exactly the lines their areas come from) with a bed line along its arc length
  (`bed_line`): each reach flat at level - depth; toward a shared point the bed rises over a
  pool tail to a crest (`step_shape`: just under the upper level for a full step,
  `CREST_RISE_PER_DROP` x the drop over the bed for a small one, so a 10 cm step in a deep
  river is a low bar, not a weir), and below it a riffle falls at `RIFFLE_SLOPE` 0.3 to the
  lower bed while the bank level follows. The upper reach's area stops flush at the shared
  point, so its pool runs shallow to that line; the riffle carries a cascade sheet
  (`WaterMeshBuilder.cascades()`: 6 cm over the riffle's ground, clamped between the two
  levels, never below a surface falling at 0.3 from the upper level to the lower, over the
  channel from 1 m above the shared point to the riffle's foot). So shallow, the water
  shader draws it as white water, and the flow bake counts it as wet, so it runs
  downstream: a small rapid, not a rock lip. Across its banks (P4-5) the sheet thins to
  nothing at the carve's waterline and sinks under the bank past it
  (`WaterMeshBuilder.CASCADE_EDGE_SLOPE`, over about a sample each side); since the sheet's
  triangles are the ground's own, its visible edge is where the two interpolated surfaces
  cross, a smooth curve whatever the grid. Cut off at the half-width sample by sample, it drew
  the grid's staircase as 0.25 m teeth on any river not along a grid axis. The buried corners
  (`cascades(doc, buried)`) are for the mesh only; the dressing and the flow see the sheet
  where it stands over the ground. River ends inside the map taper their depth
  from zero over a few metres (a spring, a sink), and (P4-4) their width to a rounded head
  (`WaterCarve.head_width`: a quarter ellipse over the longer of the depth taper and 2.2
  half-widths, with at least a 14 cm film of water toward the tip, `_end_depth`), so the
  water closes round the end instead of stopping in a straight shallow line across the
  channel.
- **Falls:** a step `WaterFalls.fall_flags()` marks (the upper reach 0.75 m or more over the
  lower) is carved as a waterfall, not a riffle (`bed_line(..., falls)`): the fall profile,
  the plunge pool and the gorge walls are in [waterfalls.md](waterfalls.md) (Authoring).
- **Erase** (P4-4, `WaterEdit.touch_rivers`, `erased_bodies`): a river whose water the
  eraser touches (its course within the eraser's radius plus the half-width) goes whole: every
  reach of its stroke (`river_chain`: the reaches joined end to end). A reach is never cut
  mid-channel, which left two ends draining into a dry channel (P4-3), and one reach is never
  erased alone: tried first, the reach above then spilled over its crest into the dry riffle
  as a jagged run-out sheet (render `rocky_badlands_summer_s1_k_erased`, first pass). To
  shorten a river, erase it and draw it again. A stream that flows into an erased river (an
  end in its water, `_touch_tributaries`) goes with it: kept, it spilled from its junction
  into the dry channel as a jagged run-out sheet (same render, second pass). A pond loses the mask samples under the eraser (`stamp` reports which
  ponds shrank), is dropped when it has none, and otherwise settles to the lowest ground on
  its new rim (`pond_rim_level`, never higher than before), so its water never stands against
  the erased, still-carved part of its basin. The ground stays carved: Sculpt's Smooth is the
  way to fill a dry channel (the Water pane's hint and the F1 help say so). An end left free
  over a carve lower than its level runs out as before (`_run_out`: the surface falls down
  the channel at `RUN_OUT_SLOPE` 1.2 and trickles on as a 6 cm film for 1.5 m).
- **Ponds:** a pond stroke marks mask samples of no other pond with the pond's id; at the
  end its level is the lowest rim ground less the freeboard (P4-1), the basin carve takes
  the signed distance to the painted area (`DistanceField`, an exact Euclidean transform)
  box-smoothed over 0.5 m twice (the shoreline follows the outline, not the samples'
  staircase), deepens toward the middle by up to 25 % of the depth, and never lowers ground
  outside the painted area below the level (water there would not be the pond's). P4-4: the
  shore is a beach (`WaterCarve.pond_section`): the ground runs at `BEACH_SLOPE` (0.12) for
  a metre above the waterline and 0.6 m below it, then the class's shore slope through a
  rounded brink (`smooth_min` over 0.12 m). P4-3's shore met the water at a 15 cm cut bank
  (the freeboard) and read, on badlands sand, as a crisp elliptical edge standing on the
  ground; a steeper underwater drop after the beach was tried and dropped, because the water
  shader's depth-slope foam draws a slope facing away from the camera as a white line across
  the water. With it the water shader fades the surface in over the first 4 cm of depth
  (`shore_fade_depth`), so the plane never ends in a crisp, slightly opaque edge (the vertex
  bob lifted it through the shore). A pond extended by a second stroke is carved again over
  its whole area as one basin (P4-5): its level is the new rim's, except that rim ground its
  own basin carved (within `BANK_REACH_M` of the old area) counts as at least the old level
  plus the freeboard, and it never rises (`WaterEditor.extended_pond_level`; read from that
  carved ground, every extension sank the pond by the freeboard); and under the water the
  top-of-bank easing fades out over `POND_UNDER_EASE_M` (1.2 m) from the waterline, so the
  old basin's shore is cut away rather than left as a ledge under the new water. Extending a
  pond downhill still lowers it to the new rim.
- **Wet dressing** (`WaterDressing`, a rule layer like cliff and scree, no paint slot,
  following the water wherever it is carved, painted or erased): per sample RGBA8 (`MapDocument
  .water_dressing`, a derived cache the document never saves; the ground shader's
  `water_weights`, bilinear, so the CPU reads exactly what the shader draws): R the bed weight
  (a smoothstep of the depth from 4 cm above the waterline to 10 cm under it, the edge moved
  by noise; 1 on a cascade's riffle); G the shore weight (a core band along the waterline,
  gone by 0.8 m, and noise-driven drifts reaching 2.4 m, both fading with the height over
  the water between 0.3 and 0.8 m, so a high cut bank keeps its ground); B the depth in cm
  (for the plants and a path's ford); A the wet line (1 under the water, falling to 0 over 0.8 m above it and
  with height), which the shader darkens (35 %) and glosses whatever the surface. Distances
  and the level of the nearest water come from `DistanceField` over the water's bounding box
  grown by the shore band. The shader and `TerrainRules.compose_water` (the CPU twin,
  `test_terrain_rules.gd` checks the lines) compose after the cliff: the bed takes its share of
  everything but painted rock, painted ground and built surfaces included as the water
  deepens (`PAINT_WATER_YIELD` 1 times a smoothstep of the depth, B, from `PAINT_FORD_START_M`
  0.05 to `PAINT_FORD_END_M` 0.35: a path runs on into the shallows like a ford and the bed
  shows under it further out; P4-3 yielded at the bed's own edge, a few centimetres above the
  waterline, and on a badlands gravel bank the path read as stopping short of the water),
  then the shore takes its share of the kept ground (paint on a bank stays paint). Each
  ground component hands the bed and shore shares to its dominant biome's
  `water_bed_surface` / `shore_surface` (`GroundLayerTable` `bed_of` / `shore_of`, slots only
  on a map with water; `PaletteLibrary` defaults per biome, contract section 9). A fall's
  face samples are channel samples here too (bed weight 1, wet line 1; the cliff rule still
  wins on the face itself: [waterfalls.md](waterfalls.md)).
- **Plants** (`ScatterGround.wet_factor`, the plan's `ground_role` carrying water bits from
  `ScatterGround.plan_role`): nothing roots in the water (the bed weight clears everything,
  rocks included), except emergent species (reeds, rushes: key rule, `EMERGENT_KEYS`), which
  stand in water up to 0.2-0.4 m and gather at the waterline; on the shore, bank species
  (willow, poplar, ferns: `BANK_KEYS`) gather (x 1 + 1.5 shore, density capped at 1), trees
  keep off the waterline, shrubs keep 30 %, tall cover thins to short cover, flowers thin by
  half, cacti keep out of the whole band, and grass, ground cover and rocks stay. A key rule,
  not a contract field: the palette has one emergent species and a few riparian trees, and a
  producer field would need a treecube rebuild for no visible gain yet. P4-4: a bank
  species' boost above 1 on the shore reaches the generator (`ScatterGround.species_density`
  leaves it uncapped for `EDGE_BANK`), which lets a clumped one (the forest's ferns) grow along
  the water beyond its clumps (`ScatterGenerator._evaluate`: the clump keep becomes at least
  the excess); forest biomes' shore surface is moss (`PaletteLibrary.WATER_SURFACE_DEFAULTS`:
  temperate forest, birch woodland, boreal taiga), since bare mud under a canopy read as a
  scar.
- **Rocks** (`WaterCarve.keeps_rock`): a rock breaking the surface stays (the water's edge
  foam wraps it, which reads well); one whose top is under the surface goes, and so does one
  wider than half the channel (it would dam it); one out of the water stays (rocks survive
  terrain changes). Generated rocks the carve's regeneration would remove are kept as props
  as after a sculpt stroke (`RockKeeper.start(..., dressing_before, keep)`, the rule deciding
  which), and placed rock props in the area are re-bedded by the snap and then dropped by the
  same rule (`WaterEditor._drop_wet_rocks`); undo brings them all back.
- **The Water tool** (`WaterBrush`, `BrushTool` mode for River and Pond tiles, the depth
  tiles, the ribbon preview and Ctrl erase) is documented in `UI_SYSTEMS.md` (authoring
  drawer, Water; "Brushes and gestures").

## Past the map edge

Phase 6, P6-1 (user, 2026-10-05: a river constrained to the play area looks unnatural). A
river that reaches the map edge carries on into the ground skirt as scenery: a channel carved
into the skirt along its continued course with the real water flowing in it, both dissolving
into the backdrop with the skirt. Decoration only, like the skirt: no collision, no grid, no
tokens past the edge. The probe that chose the rendering is P6-0
(`user://render_jobs/p6_probe/VERDICT.md`, `tools/render_jobs/probes/skirt.gd`).

- **Exits** (`RiverExits.exits`): a river body's end within `WaterCarve.EDGE_MARGIN_M` (1 m)
  of the edge (the end the carve already leaves open and untapered), not shared with another
  river's end (the next reach of one stroke). Both ends count: an upstream end at the edge
  comes from somewhere too. Landform recipes' rivers, which end at the edge, get them with no
  change. A drawn line ends where the pointer was let go (`WaterBrush.with_tip`, P6-3): the
  decimation recorded a point only 0.6 m from the last, so the release point was usually
  dropped, and a stroke released 0.36 m inside the edge ended over 1 m inside it with no exit.
  An end at the edge is carved with the river's own cross-section straight on to the edge
  (`WaterCarve.river_goals`): the round cap past the end left the bed on the edge up to 0.1 m
  shallower than the river's.
- **The course past the edge:** the author's when drawn, else derived. The Water tool keeps a
  river stroke going past the edge (`WaterBrush.hit_past_edge`: where the ray finds no ground,
  the pointer meets the height of the last point the line recorded), and
  `WaterEditor.carve_river` splits the line at the map rectangle (`RiverExits.split_line`):
  the part on the map is planned and carved as before, and the points past it (cut at the
  skirt's width and resampled to at most 16) go on the reach whose end met the edge
  (`RiverExits.attach`, by position, whichever way `plan_river` oriented the water), as
  `WaterBody.beyond` (after its last point) or `beyond_up` (before its first), saved in
  `splines.json` (`MapWaterIO`; optional, older builds ignore them). An end with none gets a
  derived continuation (`RiverExits.continuation`): 36 m along the heading of the river's
  smoothed course at its end (turned out of the map to at least 0.45 of the edge's normal
  when it met the edge at a glancing angle) with one smooth bend of 0.4 to 0.7 rad over its
  first half and a gentler one back the other way (0.45 to 0.8 of the first) over its second,
  a meander like a hand-drawn river's (a single bend read as a straight canal on the Valley;
  at 0.2 rad, P6-1's least bend, a seed near it swung the course under 2 m off its heading
  and the Valley's upper-left exit read straight between its walls; now every course swings
  more than 3 m),
  their sides and sizes from the map seed and the body id. Every course, drawn or derived, is then
  carried on along its last heading until it is 43.7 m past the map, where the skirt has
  faded however far its noise stretches the fade (`carried_on`): a drawn course that stopped
  short ended in the open while the skirt still showed. Derived, never saved.
- **The channel** (`RiverExitMesh`): the skirt's 8 rings are too coarse to carry a channel that
  bends, so the skirt columns whose radial lines pass within the channel's footprint (padded
  three columns) are cut out of the skirt (`skip_columns`) and redrawn as a patch with a ring
  every 0.25 m out to 24 m (the sample step, so the cells are square), every 0.5 m to 32 m and
  every metre beyond, out to the course's reach, the skirt's own 8 rings included. Coarser
  rings past 8 m (the first build) drew the waterline as sawtooth teeth with a pale band along
  the banks: the banks shaded smooth (smooth normals) but the water's depth-read shoreline
  traced the long triangles' true contour. That keeps the
  skirt's cost what it was everywhere else (more rings everywhere would multiply the vertices
  of the whole ring for a few metres of river). The patch's outer columns carry no channel and
  their extra vertices lie on the skirt's own edges, so there is no crack. Ring 0 is the map's
  boundary vertices (with the map's normals), so the channel meets the carve at the edge with
  no step. Past it the ground is the river's own cross-section on the edge (the map's boundary
  heights at each offset across the course, `RiverExitMesh.edge_point`; bed and banks, out to
  the half-width plus 3.5 m), carried along the course by the offset across it, lowered with
  the skirt where the skirt falls back to the map floor, eased back to the skirt over its outer
  1.2 m and as the skirt's fade falls from 0.1 to 0.02 (`RiverExits.skirt_alpha`, the shader's
  CPU twin; late, so the river keeps its width into the haze, and settled before the fade
  ends), never above the skirt. P6-1 read the section 0.3 m inside the edge, up to 0.12 m
  deeper than the edge itself: the waterline stepped at the seam (the Valley's right exit, far
  bank) and the ankle stream read deeper and greener past the edge. Beside the mouth the skirt itself eases from the
  carve's height at the edge to the bank's over 2 m (`_unghosted`): a skirt column starting in
  the channel would otherwise roll back up from the bed straight out from the edge, a ghost
  trench beside a river that leaves at an angle. Quads split along the diagonal whose ends
  are closer in height, so the banks follow the channel instead of zigzagging across the
  grid (they drew 0.5 m teeth along the waterline before). Its UV2 carries the wet dressing by height over
  the water (bed from 4 cm above to 10 cm under it, shore up to 0.8 m), routed to the base's
  bed and shore surfaces; within 2 m of the edge the skirt reads the map's own dressing
  texture instead, so the two meet without a seam.
- **The water** (the ribbon): a strip along the course at the reach's level (lowered with the
  skirt like the channel), 0.6 m wider than the waterline either side so the banks cross it in
  the depth texture and the water shader's own shoreline fade and foam draw its edge. Its first
  row lies on the edge, across the course as the channel's section is, at the river's level
  exactly: the in-map mesh's last row there is flat at the level (`_run_out`), so the two meet
  bit for bit. It runs on until a row whose every vertex has a fade of 0 (the fade's noise is
  not monotonic along the course). It draws with the shared water material and fades by the
  skirt's own law (`water.gdshader` `water_skirt_fade`, the same function and seed as the
  skirt, `shaders/skirt_fade.gdshaderinc`): lit water times the fade plus the backdrop times
  the rest, its colour set so that Godot's fog over it gives the skirt's fog times the fade
  (writing FOG would take fog off every water surface); `SkirtBackdrop` keeps the backdrop and
  fog uniforms on the water material too. P6-1 faded its alpha by the share of lit ground left
  in the skirt's blend instead (`skirt_lit_share`, kept in the include): the river's own dark
  colour then outlasted the pale faded ground, and the waist river's tail read as a darker
  stub ending in a point at full zoom-out (P6-3, captured with the ribbon and the channel
  hidden in turn: the water, not the channel). The skirt under it is lit ground
  times the fade plus the backdrop, so the refracted bed went darker, greyer and streaky as
  the skirt faded: the water now takes the backdrop back out of what it refracts and refracts
  less as the fade falls, so it keeps the in-map river's colour and luminosity and dissolves
  by its own alpha alone. Under a low sun the water past the edge glittered white beside an
  in-map river in shade: the cause was the reflection probe, which covered the map plus 10 %,
  so the water past it reflected the open sky's radiance; on an authored map the probe now
  reaches over the skirt (`LevelEnvironmentManager.compute_probe_box`). Shadows were not it:
  the skirt receives them like the map, and making it cast them changed nothing. The in-map water of an end at the
  edge stays at its level out to the edge (`WaterMeshBuilder._run_out`) instead of falling
  away as a run-out sheet, which drew a step against the ribbon. Its flow UVs are the flow map's texels
  just inside the edge at the mouth (the border texels are still water), across the channel by
  the offset, so the edge's flow carries on; in a bend the ripples keep the edge's direction.
- **Ponds and lakes** (P6-4, `PondExits`): a pond painted against the edge was cut off there,
  the look rivers had. An exit is a run of at least two boundary samples on one side of the
  map that are in a pond's mask and wet (under its level): the wet span on the edge. Its basin
  continues as a lobe, derived, never saved. Across, it starts as the edge's own waterline
  offsets either side of the span's middle (the cross-section read on the edge as a river's
  is, `RiverExitMesh.section`); each side runs on along the shoreline's direction at the edge
  (the pond mask's run 2 m inside against its run on the edge, clamped to -0.6..0.8 per metre,
  followed for about 4 m and saturating at 40 % narrower or 60 % wider: a converging shore
  carried on straight met its other side in a point, which the narrow pond's first capture
  showed as a teardrop) and then closes into a rounded end over its last 0.7 half-spans (the
  width times sqrt(1 - t^2) there; an ellipse over the whole length drew the narrow cove's end
  as a point). The length runs from the half-span toward the skirt's fade
  (24 m) by (half-span / 8 m) squared times a seeded factor of 0.5 to 1.5 (map seed, pond id,
  side, run): a narrow touch makes a small cove, a wide one a long bay, and when the share
  reaches 1 an open lake running on past the fade (43.7 m plus the half-span). The first rule,
  1 to 2.5 half-spans, ended the look map's 15 m-wide lake as a 10.7 m cove that never reached
  the haze. The shore
  wobbles by up to 15 % with the seeded value noise (TerrainRules.value_noise) every 7 m, none
  on the edge. Each side stays in its own side's sector of the skirt (the diagonal from the
  corner), so a pond across a corner gets two lobes that meet at the diagonal. In the lobe the
  ground is the edge's cross-section scaled to the lobe's width there, its depth under the
  level shallowing toward the end (times sqrt(1 - (s / length)^2)); past the shore, the edge's banks by the
  distance to the shore (the half-width table searched within the bank's reach), eased to the
  skirt over the outer 1.2 m; lowered with the skirt and eased out with its fade as a river's
  channel is, never above the skirt. It draws in the rivers' patch (the windows, rings, wet
  dressing and normals are theirs; a window may hold a pond and a river). The water is a grid
  over the lobe at the pond's level (lowered with the skirt), its rows every 0.5 m across the
  lobe's width plus the ribbon's 0.6 m margin, a vertex about every metre across (9 to 65), the
  first row on the edge at the level exactly (the in-map pond's water is flat at its level out
  to the boundary samples, so the two meet bit for bit), the last the first past which the
  fade is 0 everywhere or past the lobe's end; it is part of the ribbon surface, with the same
  material, fade and fog. **A pond and a river leaving together:** the river's water is cut
  back where the pond's covers it (`PondExits.clip`: each ribbon triangle clipped against the
  pond water's outline, heights and flow UVs interpolated), so no two water surfaces overlap.
  **Cache:** a pond's water is a piece keyed on the lobe (its id and level through the span,
  the mouth, the cross-section, the half-width tables) and the fade; the window key adds the
  lobe's wet span, length and tables to the boundary heights it already hashes; a river's
  water adds the outlines of the ponds that cut it. An edit away rebuilds nothing.
- **Where it is built:** with the skirt, on AuthoredLoadPrep's worker at load
  (`RiverExitMesh.skirt_parts`) and on AuthoredWater's refresh worker after any water edit,
  which hands the skirt to `AuthoredTerrain.apply_river_exits()` (a rebuild of the skirt mesh
  keeping its material; nothing when no exit was or is there; `RiverExitMesh.has_exits` counts
  a pond on the edge). The skirt's vertex mirror for
  in-place edge updates comes with the parts (`TerrainMeshBuilder.skirt_mirror_of`, read off
  the built arrays on the worker): made from the document on the first edge edit after every
  rebuild, it cost a stroke carved to the edge 34 ms of its ground step (P6-3). **The cache**
  (P6-3): each window's patch and each mouth's ribbon is a piece keyed on what it reads (the
  near mouths' course, section, level and bank, the boundary heights around the window's
  columns, the ring distances in whole micrometres, the fade), and AuthoredWater lends the
  skirt's current exits to its refresh worker, so a water edit rebuilds only the pieces it
  touched (`RiverExitMesh.build`, `p6_perf.gd cache_check`). A sculpt on the edge updates the
  skirt in place during the stroke; its stroke-end water refresh (`WaterEditor.refresh`)
  rebuilds the touched exit alone.
- **The skirt is opaque** (`authored_ground.gdshaderinc` SKIRT): the probe found any
  transparent skirt out of the depth and screen textures, so water over it read the backdrop.
  The fade is in colour; the backdrop and the fog are matched to the environment by
  `SkirtBackdrop` (ARCHITECTURE.md "Ground skirt").

## Verification

- **Unit tests** (`tests/unit/`): `test_water_model.gd` and `test_map_document_water.gd`
  (the bodies and the document entries), `test_water_flow_baker.gd` (bakes decoded through a
  mirror of `water_flow()`), `test_authored_water.gd` and `test_water_zone.gd` (the surface,
  zones, water as ground), `test_glb_utils_water.gd` (the shared material and the forwarded
  settings), `test_water_carve.gd` and `test_water_scatter.gd` (the carve, the dressing, the
  plants and rocks), `test_water_tool.gd` (the worker result identical to the synchronous one,
  undo exact), `test_terrain_rules.gd` (`compose_water` against the shader's lines), shared
  ground builders in `water_fixtures.gd`.
- **Render jobs** (`tools/render_jobs/jobs/`): `water_look.json` (probe `probes/water.gd`:
  `carve`, `pond`, `erase`, `check`, `profile`), `water_tool.json`, and the phase 4 judgment
  set `phase4_judgment_set.json`; past the map edge (phase 6) `p6_probe.json` (P6-0, probe
  `probes/skirt.gd`: water over the skirt, the skirt's blend modes) and `p6_look.json` (P6-1,
  probe `probes/p6.gd`: every exit at home, zoom 20 and zoom 8, fog and sky backdrops, the
  patch, ribbon and skirt hidden in turn); captures and verdicts are indexed in
  [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Verification status".
- **Performance** ([../PERFORMANCE.md](../PERFORMANCE.md)): "Water flow map (2026-09-23)",
  "Authored water surface (2026-09-27, P4-2)", "Water tool: carve on a worker (2026-09-27,
  P4-4)", "In-game authoring phase 4 (water): pinned performance pass (2026-09-27)" and "Phase
  6 (rivers past the map edge): pinned performance pass (2026-10-05)" (jobs `p6_perf_build`,
  `p6_perf_play` and `p6_perf_band`, probe `probes/p6_perf.gd`: the opaque skirt against the
  transparent one, the exits' draw, the load and the refresh). The numbers quoted above from
  render jobs are indicative; the pinned passes are the reference.

## Open work

The list is [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work"; this doc does not repeat it.

## History

- P4-1 (2026-09-27): the model and the flow bake (bodies, areas, levels, reaches, the
  terrain-paint field ported).
- P4-2 (2026-09-27): the merged surface, zones per body, water as ground, the float rule, the
  grid on the water.
- P4-3 (2026-09-27): the carve (cross-section, reach steps and riffles, cascades, basins), the
  wet dressing, plants and rocks, the editor API.
- P4-4 (2026-09-27): the Water tool, the worker carve, confluences, rounded heads, beach
  shores, whole-river erase.
- P4-5: the dressing refresh on a worker, cascade edges across the banks, extended ponds, the
  shallows in the shader.
- P4b-0: the submerged token marker, the edge foam reach, the authored map load on workers.
- Phase 4c (2026-10-04): waterfalls, in [waterfalls.md](waterfalls.md).
- Phase 6 (2026-10-05): rivers past the map edge (P6-0 probe, P6-1 build, P6-2 pinned pass,
  P6-3 edge follow-ups: the release point, the seam and depth at the mouth, the tail's fade,
  the meander, the mirror on the worker and the exit cache).
