# Starting landforms

The landform a new map opens with (phase 5, 2026-10-04): Flat, Valley, Hilltop, Terraces,
Lakeshore or Gorge, picked in the new-map dialog beside the size and the biome. The bar: a
newcomer picks a size, a biome and a landform, presses Create, and the map that opens is
already a place, with ground that has a shape, often water that runs and a way across it, and
an open stage for the fight, all in the biome's own materials and all made of the same tiers,
rivers, ponds and crossings the tools make, so every part can be sculpted, carved, erased or
moved on. One rule governs every recipe (user, 2026-10-04): **no sameness.** Having
everything appear in every map is distracting; not everywhere has a river and not every river
a crossing, and every draw, wet or dry, must be a complete and beautiful map on its own. The
look is painterly: a few bold landforms, never a noise-field terrain. The same seed gives the
same map; a different seed gives a sibling, not a stranger.

Plan: `docs/plans/2026-10-04-phase5-starting-landforms.md` (local; a "done" paragraph per
task). The tiers a recipe writes are the Sculpt tool's own (`HeightBrush.tier_goal`,
[../ARCHITECTURE.md](../ARCHITECTURE.md) "Authoring Flow"); the water it carves is
[water.md](water.md) and [waterfalls.md](waterfalls.md); the crossings it places are
[crossings.md](crossings.md). The dialog's Landform row is in
[../UI_SYSTEMS.md](../UI_SYSTEMS.md) "New map dialog".

## Map

| File | Class | Role |
|------|-------|------|
| `utils/starting_landform.gd` | `StartingLandform` | Pure static: `KINDS`, `NAMES`, `CAPTIONS`, `DEFAULT`, `apply(doc, kind, seed, biome_id, root)`, the seeded frame (`stream`, `size_scale`, `heading`, `VIEW` / `NEAR`) and the shared steps every recipe composes |
| `utils/landform_recipes.gd` | `LandformRecipes` | The Valley (`valley`, `valley_frame`, `valley_stage`, `bluff_side_of`, `wash_surface`) |
| `utils/landform_hilltop.gd` | `LandformHilltop` | The Hilltop (`hilltop`, `hilltop_frame`, `crown_of`, `ledge_of`, `shoulder_stage`) |
| `utils/landform_terraces.gd` | `LandformTerraces` | The Terraces (`terraces`, `terraces_frame`, `plateaus_of`, `terraces_stage`) |
| `utils/landform_lakeshore.gd` | `LandformLakeshore` | The Lakeshore (`lakeshore`, `lakeshore_frame`, `allowed_corners`) |
| `utils/landform_gorge.gd` | `LandformGorge` | The Gorge (`gorge`, `gorge_frame`, `gorge_stage`) |
| `utils/landform_growth.gd` | `LandformGrowth` | Big and long maps: `room`, `is_long`, `long_dir`, `turned`, `grow` (the extras: tarn, meadow, knoll), `knoll`, `tarn` |
| `utils/landform_placement.gd` | `LandformPlacement` | Where the extras stand and the open ground's paint: `find_spot`, `meadow_surface`, `paint_open`, `paint_sparse` (every new map's thin cover and edge band greened), `wood` (a recipe's per-seed wood) |
| `utils/new_map.gd` | `NewMap` | `create(..., landform, depth_ft)` runs the recipe before the cover; `from_spec(spec)`; `opening_status(spec)`; `paint_starting_cover(doc, biome, centre, glade, clearings, wood)` centres the glade on the stage, opens the clearings, thins the groves by the recipe's wood (`wood_density`) and feathers the cover at the map edge (`edge_feather`, `edge_keep`) |
| `scenes/terrain/terrain_skirt.gd` | `TerrainSkirt` | The skirt's material; `edge_surface` (the painted surface covering the map's edge, which the skirt continues instead of the base) |
| `scenes/states/authoring/new_map_dialog.gd` | `NewMapDialog` | The Landform tile row and its caption; the spec's `landform` |
| `scenes/states/authoring/authoring_controller.gd` | `AuthoringController` | Opens a new map from `NewMap.from_spec(spec)` under the loading line `NewMap.opening_status(spec)` |
| `scenes/ui/help_overlay.gd` | | The F1 "New map" row |
| `assets/icons/ui/landform-<kind>.svg` | | Six glyphs in the house 24 px white-stroke style |
| `tools/render_jobs/probes/landform.gd` | | Render-job probe: `new` (with `depth` or a `spec` string), `report`, `look` (stage, water, floor, summit, steepest, fall, crossing), `save` and `cleanup` of `_biglf_` levels |
| `tools/render_jobs/probes/contact_sheet.gd` | | Tiles a job's captures into one sheet (seeds side by side) |
| `tools/render_jobs/jobs/landform_*.json`, `phase5_*.json`, `p5_perf_*.json`, `biglf_*.json` | | The look, dialog, judgment-set, performance and big-map jobs (Verification) |

## Model

- **Apply** (`StartingLandform.apply`, pure): runs the recipe for a kind on a flat document
  of the map's size and returns `{"stage": Vector2, "report": String}`: the stage is where the
  glade goes (map XZ metres), the report says what the seed drew, naming any refusal in plain
  words. Flat and an unknown kind change nothing. A recipe writes only ordinary document data
  (heights, carved water bodies, crossings, painted surface weights) through the same pure
  functions the tools use; no history entry, so a new map starts clean. `WaterDressing.refresh`
  runs once per recipe, at the end.
- **The seeded frame.** Every draw comes from a `RandomNumberGenerator` seeded from the map
  seed xor one constant per feature (`stream(seed, feature)`: `STREAM_FRAME`,
  `STREAM_FEATURES`, `STREAM_RIVER`, `STREAM_TRIBUTARY`, `STREAM_CROSSING`), as
  `CrossingFord` does for its stones, so the frame, the feature draws, a river's wobble, the
  tributary and the crossing each have their own stream and a change in one feature's draw
  does not shuffle the others (a new feature draw is appended last to its stream, as the
  Valley's bluff was in P5-4). Metres are written for a 150 ft map (`REFERENCE_EXTENT_M`
  45.72) and depths and falls scale by `size_scale()`: 0.8 / 1.0 / 1.2 at 100 / 150 / 200 ft,
  so a landform keeps its proportions without a small map becoming a pit; widths and
  positions are shares of the half extent. `heading(rng)` is one of eight 45 degree headings.
  The seed varies the shape too (heading, offset, bend, the hill's side, the lake's corner)
  within bounds that keep the recipe recognisable. `size_scale()` is capped at 1.7 (about
  1.68 at 320 ft; the cap was 1.5, reached at 275 ft, until big maps grew). A map that is not
  square composes on its shorter side (`half_extent()`, `size_scale()`).
- **Big and long maps** (`LandformGrowth`, 2026-10-09). The recipes compose one place on the
  square of the shorter side, sized for maps up to 250 ft; past that, or longer than wide, a
  map has room (`room()`: 0 for a square map of 250 ft or less, so those draw exactly as
  before; 1 at 320 ft or at 2:1). The recipes spend it on their own shapes, from
  `STREAM_SHAPES`: a long map's Valley, Gorge and Terraces run along it (`turned()` turns a
  heading within 60 degrees of square to the length a quarter), the Valley may meander
  (`MEANDER_CHANCE` 0.65 at full room: a second bend upstream, the other way, 30-48 degrees)
  and its river widens (`RIVER_GROWTH` 0.4 of its half-width), the Gorge draws its second bend
  again (`SECOND_BEND_GROWTH` 0.6) and spreads it over the long half, the Terraces may gain a
  step (`EXTRA_STEP_CHANCE` 0.7; three steps spread over half the span either side) and
  spread their steps along a long map (`span_of`), the Hilltop sits toward one end of a long
  map with its second hill toward the other (`toward_end`), and the Lakeshore's lake takes
  any corner or side of a long map's own extent (`wide_frame`, as on a wide map, since
  2026-10-10). Then `apply()` runs `grow()`: one extra with chance
  `room`, a second with 0.85 `room`, drawn by weight from the landform's palette (`PALETTES`:
  mostly a tarn or a meadow, a knoll least) from `STREAM_EXTRAS` salted by the landform, each
  placed by `LandformPlacement.find_spot` (48 seeded candidates; clear of the stage, the
  crossings, the water, the recipe's `keepout` and the other extras, on ground flat within
  0.6 m; scored about midway from the stage to the edge, well inside the edge, near the
  recipe's features and rivers by its tie, high or low by its lean, toward a long map's
  ends). Open ground (a meadow, a knoll's crown over 0.95 of its radius, a tarn's shore, and
  the recipe's own `open` features: the Hilltop's upper slopes, the Lakeshore's shore, the
  Valley's floor unless a dry wash dresses it) is painted with the biome's meadow surface
  (`meadow_surface`: its grass or moss accent; none on a grass or sand ground) and, as discs,
  comes back as `clearings`, which `NewMap.paint_starting_cover` opens (`clearing_density`).
  On a map with room the cover noise's copses grow by up to `COVER_FEATURE_GROWTH` 0.5, so a
  big forest keeps a few bold shapes, and after the cover is painted
  `LandformPlacement.paint_sparse` greens its thin parts (cover density 0.45 down to 0.18) in
  bold noise-shaped patches (`SPARSE_FEATURE_M` 14 m at 150 ft, never under 12 m) on every
  new map with a meadow surface, whatever its size (round 3: on big maps only until then, and
  the same landforms at 200 and 250 ft sat on brown forest floor and read muddy beside the
  320 ft ones). Why open ground: the first look
  (`biglf_look`, half size) found that from the whole-map view a forest's trees hide a big
  map's relief (a 5 m knoll, the hill, the terraces' steps), so what reads is water and
  bright open ground; the second found the forest floor between thin cover (a valley's
  camera-side slope, the uplands between groves) reading as brown dirt, the hilltop seeds
  alike, and knolls lost under trees (hence the greening, more tarns and meadows, fewer
  knolls with wider crowns).
- **The map edge** (2026-10-09; play shows the whole map). Every new map's cover feathers out
  at its edge (`NewMap.edge_feather`: to none over a quarter of the shorter half extent, 3-12
  m, so 7.6 m at 200 ft, 9.5 m at 250 and 12 m at 320; its depth ragged by the cover noise),
  so the scatter ends in a ragged fringe rather than a straight line (a grassland's tall grass
  stopped dead at it). Trees answer the density late, so a forest's groves keep their edge.
  On a biome with a meadow surface `paint_sparse` greens the band as the cover goes (whole
  where the feather keeps under 0.35 of the cover, none from 0.9), so the edge itself is all
  meadow, and the skirt continues the painted surface that covers the map's edge
  (`TerrainSkirt.edge_surface`: a mean weight of at least 0.6 over the edge samples; the
  shader's `skirt_ground_mask`), else the base: a forest map fades out on grass rather than
  a brown forest-floor halo. The ground accents shrink away inside the same band (the ground
  shader's `accent_edge_m`, ragged by its own noise) and the skirt draws none, so no
  grassland savanna patch sits on a rim or floats in the haze as an orange blotch. History:
  the first edge (round 2) feathered over a tenth (2-6 m) and shrank the skirt's accents a
  few metres past the edge; round 3 found the forest maps ringed by a brown halo and orange
  blobs at grassland rims and corners.
- **Facing the camera** (P5-4, commit 0bcda1d): the fixed camera (`game_map.tscn`'s Camera3D)
  stands at +x, +z and looks along (-1, -1) in map XZ at a 45 degree yaw, pitched 21.6
  degrees down. `VIEW` (-0.707, -0.707) is that look direction and `NEAR` (0.707, 0.707) the
  direction from a feature toward the camera; anything a recipe wants "facing the camera"
  (a stage side, a fall's face, a gorge's heading, a bluff's bank) composes with these and
  never with an axis. The P5-2 recipes assumed the camera looked along -z, so the hill's stage
  sat on its side, a gorge at heading 45 ran straight along the view and the valley's bluff
  stood on the back-facing near bank (the P5-4 verdict).
- **Shared steps** (`StartingLandform`): `nearest_on` and `along` give a polyline's distance
  field and arc position, so a bent axis gives smooth ground; `trough_shape(distance,
  floor_half, rim)` is 1 on the floor and a cosine fall to 0 at the rim; `bump(t)` a rounded
  hill with no crease at the foot; `warp_noise` a low-frequency noise for warping an outline;
  `disc_distance` (a warped disc, periodic so a shore has no seam) and `box_distance` (a
  rounded rectangle) give signed distances to an outline; `tier_inset(distance)` turns one
  into the `inset` `HeightBrush.tier_goal` wants (measured from `TIER_SOFTEN_M` outside its
  ring), so a recipe's plateau is the Sculpt tool's own Tier terrace: a 66 degree rock face, a
  rounded grassy lip, a flat top exactly on a 5 ft tier, a concave scree foot; `write_heights`
  writes a height function over every sample, clamped to `MAX_ABS_HEIGHT_M`; `map_line` clips
  a polyline to the map and resamples it; `wobbled` pushes a course across itself by a seeded
  wobble (one wave per `WOBBLE_WAVE_M` 14 m); `carve_river` plans, carves and adds a river as
  the Water tool does (`WaterEdit.plan_river`, `WaterCarve.river_goals`, `WaterEditor.lower`,
  `with_bodies`), so falls form by the waterfall rule wherever a course crosses a tier or a
  steep flank; `carve_pond` stamps a pond over a mask as the Water tool's pond stroke does
  (the level is the lowest rim ground less the freeboard, so the heights around it must be
  final first); `restore_outside` puts back ground a river's bank reach
  (`WaterCarve.BANK_REACH_M`) slumped beyond the channel and its bank, only ever raising (a
  slope cut through high ground is right for a stroke across a hillside, wrong for a stream
  along a ravine wall); `place_crossing` draws a crossing `CROSSING_DRAW_M` 3.5 m either side
  of the water's centreline through `CrossingPlacement.place` and gives it the id
  `CrossingEditor.add` would; `span_crossing` stands a crossing on two chosen dry anchors (an
  arch rim to rim, whose waterline anchors would stand on the ravine floor) with
  `CrossingPlacement.levels_for` and the same refusals; `straightest` picks where a course
  runs straightest among candidates (where a crossing goes), and `straightest_wet` (P5-7)
  among those `WaterGeometry.is_wet_at` says lie under water, so a crossing is never drawn
  where the carve left the course dry (the lake's, valley's and terraces' crossings use it;
  the hill's stones skip dry points the same way); `paint_line` paints a surface
  along a polyline with a soft edge (a dry wash). A refused crossing leaves the document as it
  was and is named in the report: never a broken map.
- **Valley** (`LandformRecipes.valley`; caption "A broad valley; often a river runs down it";
  the default): a broad trough across the whole map along one of eight headings through a
  point up to `VALLEY_OFFSET_SHARE` 0.25 of the half extent off the centre, bent once by
  `VALLEY_BEND_DEG` 8-25 degrees within `VALLEY_BEND_REACH_SHARE` a third of the half extent
  downstream of the centre's foot. `VALLEY_DEPTH_M` 3.5 m deep (2.5 m in P5-1 read only as a
  sunken channel from the home camera), its floor `VALLEY_FLOOR_SHARE` a third of the half
  extent either side of the axis (a third of the map wide), the cosine slope rising to the
  rim at `VALLEY_RIM_SHARE` 0.6 (0.72 in P5-1), the floor tilting `VALLEY_FALL_M` 1.0 m along
  the axis so a river down it has reaches and riffles. Draws: a waist river
  (`VALLEY_RIVER_CHANCE` 0.7, half-width `RIVER_HALF_WIDTH_M` 1.5 m, wobbling within
  `RIVER_WOBBLE_SHARE` a tenth of the floor's width); given the river an ankle tributary off
  the outer slope (`VALLEY_TRIBUTARY_CHANCE` 0.4, rising `TRIBUTARY_SLOPE_SHARE` 0.6 up the
  slope) and a crossing where the river runs straightest near the stage
  (`VALLEY_CROSSING_CHANCE` 0.5; stepping stones at `VALLEY_STONES_CHANCE` 0.4, else a ford);
  without a river a dry wash of the biome's scree surface along the floor
  (`VALLEY_WASH_CHANCE` 0.5, `WASH_WIDTH_SHARE` 0.35 of the floor); and a bluff
  (`VALLEY_BLUFF_CHANCE` 0.5, P5-4): one bank stands one tier over the slope behind a rock
  face cut with `tier_goal` along the rim line, wobbled `BLUFF_WOBBLE_M` 2 m, its toe on the
  rim, the other bank keeping the cosine slope, so the valley reads as a place without
  becoming a gorge. `bluff_side_of` puts it on the far bank (the `VIEW` side) of a valley
  crossing the view and on the outer bank (away from the stage) of one running within
  `BLUFF_ALONG_DEG` 30 degrees of the view. Stage: on the inner bank of the bend,
  `STAGE_BANK_SHARE` 0.7 of the floor's half-width off the axis, within
  `STAGE_REACH_SHARE` 0.5 of the half extent of the centre.
- **Hilltop** (`LandformHilltop.hilltop`; "A rounded hill, often with a rock-lipped crown"):
  a cosine bump of `HILL_RADIUS_SHARE` 0.45 of the half extent, `HILL_HEIGHT_M` 4.5 m, its
  centre up to `HILL_OFFSET_SHARE` 0.3 off the centre along one of eight headings. Draws: a
  crown (`CROWN_CHANCE` 0.85 since P5-4b, was 0.7): a flat tier on the summit raised with
  `tier_goal` over a warped disc of `CROWN_RADIUS_SHARE` 0.38 of the hill's radius
  (`CROWN_WARP` 0.12, at least `CROWN_TOP_MIN_M` 4 m of flat top), on the tier nearest the
  hill's height, the hill beneath scaled so the face is a full tier all round; a second hill
  of half the height on the far side (`SECOND_HILL_CHANCE` 0.3); a spring stream
  (`STREAM_CHANCE` 0.5, ankle): with a crown a pool on the crown (the line starts
  `POOL_INSIDE_M` 3 m inside the outline, so the first reach is the pool) spilling over the
  crown's face in the phase 4c tier fall and on down the flank, without one an ankle stream
  rising `STREAM_SUMMIT_SHARE` 0.25 of the radius from the summit, either way running
  `STREAM_AZIMUTH_DEG` 60-90 degrees off `NEAR` so the fall shows in profile and the stream
  never crosses the stage; stepping stones over it below the foot (`STONES_CHANCE` 0.4). A
  crownless hill is never a bare mound: it gets the second hill when it drew neither the
  second hill nor the stream (P5-4), and always a flank ledge (P5-4b): the ground above a line
  `LEDGE_HEIGHT_SHARE` 0.33 of the way up raised to the next tier with `tier_goal` over an arc
  of `LEDGE_ARC_DEG` 90-130 degrees about `NEAR` (60-100 until P5-7, whose narrow end read
  weakly), only ever raising. On a ledged hill the stream's window is
  `stream_azimuth_window`: its start moves out to the arc's half-span plus
  `LEDGE_STREAM_CLEAR_M` 2 m along the ledge's line (the bench's soft edge, the channel and its
  wobble) when that is past 60 degrees, at least `LEDGE_STREAM_SPAN_DEG` 10 wide, so a stream
  never crosses the bench (at 150 ft the widest arc gives 83-93 degrees; at 100 ft up to
  95-105, a little past side-on). Stage: on the shoulder
  toward the camera, `STAGE_SHOULDER_SHARE` 0.55 of the radius out, past the crown's toe
  (`STAGE_CROWN_TOE_M` 1 m) or at the ledge's foot (`STAGE_LEDGE_TOE_M` 1.5 m), within half
  the half extent of the centre. The setting (round 3, `STREAM_SETTING`; every seed had read
  as a dense forest diamond round a green hill): on a wide map (`LandformGrowth.is_wide`, the
  shorter side 60 m or more: 200 ft and up, not long) the hill stands
  `HILL_WIDE_OFFSET_SHARE` 0.3-0.5 of the half extent toward a heading of its own: the seed
  times `WIDE_TURN` (the golden ratio's fraction) turns, any azimuth, so a random seed's
  heading is as even as a draw and seeds close in number stand far apart (any five in a row
  at least 52 degrees, six 32; `setting_of`). Until 2026-10-10 it was the frame's eight
  headings: at 250 ft seeds 1 and 4 drew the same 315 and near-equal setting draws, so their
  hills stood within half a metre and the maps read alike; a uniform draw from the setting
  stream, tried first, put seeds 1, 5 and 6 within 17 degrees. The second hill stands as far
  the other way; the open crown on a map with room covers `HILL_OPEN_RANGE` 0.45-0.95 of
  the radius; and at every size the wood (`LandformPlacement.wood`, `NewMap.wood_density`)
  keeps 0.4-1.0 of the groves' density over the glade's and with `WOOD_LEAN_CHANCE` 0.6
  gathers them toward a seeded side, the far side opening by 0.55-0.9.
- **Terraces** (`LandformTerraces.terraces`; "Tiers stepping down across the map"): two or
  three tiers (`THREE_CHANCE` 0.5) stepping down along one of eight headings, the lowest the
  base ground and each higher one a rounded-corner plateau (corners `CORNER_M` 4-8 m, edge
  wobbled `WOBBLE_M` 1.5 m) raised one 5 ft tier over the one below with `tier_goal`; the top
  terrace's edge at `TOP_EDGE_SHARE` a third of the way across, the next `STEP_SHARE` two
  thirds further; each plateau `WIDTH_STEP_M` 3 m narrower across than the one below
  (`WIDTH_SHARE` 1.15 for the lowest raised one), so a corner or two shows. Draws: a waist
  river crossing the steps square on (`RIVER_CHANCE` 0.6), falling at each step; given the
  river, a plank bridge on the top terrace (`BRIDGE_CHANCE` 0.5) `BRIDGE_BACK_M` 5 m uphill of
  its edge. Stage: on the middle terrace, or `STAGE_DOWN_SHARE` 0.3 of the half extent down
  the lower one when there are two, `STAGE_RIVER_M` 6 m from the river toward the axis. Over
  three steps (a big map's extra step), or two on a wide or long map, the river jogs
  `JOG_SHARE` 0.16 of the half extent (at least `JOG_MIN_M` 9 m, three river widths) across
  the heading at every other step, away from the axis and the stage, crossing each step
  square on within `JOG_SQUARE_M` 3 m of its edge (`river_line`; round 3, where seed 5 at
  320 ft ran straight up the map over three falls in a line; 2026-10-10, where seed 5 at
  200 and 250 ft still did over two, the bridge in the same line, a 320 x 160 ft map's
  3.9 m jog read as none and a 6.1 m one at 250 ft as a kink). A 150 ft map keeps its
  straight river over two steps.
- **Lakeshore** (`LandformLakeshore.lakeshore`; "A deep lake over one corner, its shore the
  stage"): a deep pond over a disc of `LAKE_RADIUS_SHARE` 0.45 of the half extent centred
  `LAKE_CENTRE_SHARE` 0.5 of it toward a corner (0.55 before P5-4), its shore warped
  `LAKE_WARP` 0.15 of the radius, carved with `carve_pond`; the ground rises `LAKE_RISE_M`
  1.5 m away from the shore over `LAKE_RISE_RUN_SHARE` 0.9 of the half extent, so the lake
  sits in the map's low corner. The corner is drawn from `allowed_corners()`, the three that
  are not the camera's own (the `NEAR` corner, (1, 1), where the lake lay at the bottom of the
  view cut by the foreground; P5-4b), weighted by `corner_weights` (P5-7): the far corner
  (-1, -1) `FAR_CORNER_WEIGHT` 0.6, each side corner `SIDE_CORNER_WEIGHT` 0.2. The home camera
  shows about 24.6 m of ground across at 1920x1080 against a 45.7 m map, so a side lake is
  placed from `VIEW` rather than by a share: its centre at most `LAKE_SIDE_SCREEN_M` 6 m across
  the view (`ACROSS`, toward the corner's side) and `LAKE_SIDE_DEPTH_SHARE` 0.4 of the half
  extent up it, a smaller lake of `LAKE_SIDE_RADIUS_SHARE` 0.3 (6.9 m at 150 ft) beside the
  stage, its islet scaled with it. (A 0.38 share pull, the first P5-7 try, still left the
  centre 14.2 m across against the frame's 12.3 m half-width.) The P5-7 render: seeds 14 and
  29 show the whole lake in the home frame. The lake is the water, so a dry draw has it too. Draws:
  an islet (`ISLET_CHANCE` 0.3), a small hill `ISLET_RADIUS_M` 5 m shaped before the pond is
  stamped so the mask leaves it dry, its top `ISLET_TOP_OVER_M` 0.5 m over the water; a
  feeding ankle stream from the far side (`STREAM_CHANCE` 0.5) approaching
  `STREAM_AZIMUTH_DEG` 35-70 degrees off the stage's line and ending `STREAM_IN_M` 1 m inside
  the shore, where `plan_river` joins it at the waterline; stepping stones over it
  (`STONES_CHANCE` 0.4) at least `STONES_SHORE_M` 5 m back from the shore. Stage: on the shore
  nearest the map's centre, `STAGE_SHORE_M` 4 m back from the waterline. The setting (round
  3, `STREAM_SETTING`; every seed had read as a lake at the back with forest elsewhere): on a
  wide map (200 ft and up) or a long one (since 2026-10-10: a 320 x 160 ft map's 48.8 m
  shorter side is under the wide threshold, and its far-corner frame kept the lake at the back
  on 4 of 6 seeds) the corner draw above gives way to `wide_frame`: the lake takes any
  of `WIDE_PLACES` alike, the four corners and the four sides' middles (the home frame no
  longer bounds it: the whole map is what reads), with `LARGE_LAKE_CHANCE` 0.35 a lake of
  `LARGE_LAKE_SHARE` 0.6 of the half extent, its centre its radius plus `LAKE_EDGE_SHARE` 0.05
  of the half extent in from each edge it lies toward, on a long map's own extent. At every
  size: a shore meadow (`SHORE_MEADOW_CHANCE` 0.55), a clearing 0.85 of the lake's radius
  across on the shore 20-80 degrees off the stage's line, returned in `clearings` and greened
  by `paint_sparse`; and the wood as the Hilltop's (0.45-1.0, leaning with chance 0.5).
- **Gorge** (`LandformGorge.gorge`; "A ravine with rock walls winding across the map"): a
  ravine one or two tiers deep (`TWO_TIERS_CHANCE` 0.5; two only on a map at least
  `TWO_TIERS_MIN_EXTENT_M` 45 m wide, 150 ft and up) cut downward with `tier_goal` from the
  rim at the base height: a rounded grassy rim, a 66 degree rock face, a flat floor
  `FLOOR_M` 6-9 m wide (`TWO_TIER_FLOOR_EXTRA_M` 3 m wider when two tiers deep, since the
  21.6 degree pitch hides 7.6 m of floor behind a 3 m near rim), tilting `FALL_M` 1.5 m along
  its length. Its axis takes one of `HEADINGS` (six of eight: every heading but 45 and 225,
  the camera's diagonal, so the far wall and the floor face the camera) through a point up to
  `OFFSET_SHARE` 0.15 off the centre, bent by `BEND_DEG` 15-35 degrees and, half the time,
  bent back further on (`SECOND_BEND_CHANCE` 0.5). Draws: an ankle stream along the floor
  (`STREAM_CHANCE` 0.7) pushed `STREAM_FAR_SHARE` 0.7 of the floor's half-width toward the far
  wall where the ravine crosses the view (0.45 before P5-4), the walls put back beyond it with
  `restore_outside` (`WALL_KEEP_M` 0.5 m), else a dry wash of the biome's scree surface; given
  the stream a stone arch rim to rim near the middle (`ARCH_CHANCE` 0.4) through
  `span_crossing`, its feet `ARCH_FOOT_M` 1.5 m back from the lips. Stage: on the rim on the
  camera's side (`NEAR`) by the arch or the ravine's middle, `STAGE_RIM_M` 1.5 m back from the
  rim.
- **Flat**: unchanged (caption "Level ground, yours to shape").
- **The stage and the glade.** `NewMap.create` paints the starting cover with the glade
  (`COVER_GLADE_RADIUS` 0.35 of the half extent) centred on the recipe's stage rather than the
  map's middle; the groves still grow toward the map's edges. A recipe may return a line glade
  instead (`"glade": {"line", "half_width", "rise"}`, P5-7): `paint_starting_cover` then paints
  the glade's density within `half_width` of the line and brings the groves back over the next
  `rise` metres (`NewMap.line_density`). The Valley returns its axis, the floor's half-width and
  the slope's width to the rim, so the floor and river stay open and the far slope keeps its
  groves. The bank facing the camera (`NewMap.glade_density`: `near`, counted whole from a dot
  of `GLADE_NEAR_FULL_DOT` 0.65 with it) stays thin, since a 10 m tree hides about 25 m of
  ground behind it from the 21.6 degree home camera: the glade reaches
  `GLADE_NEAR_OPEN_SHARE` 2.5 slope widths out (about 9 m past the rim at 150 ft), that band
  is capped at `GLADE_NEAR_CAP` 0.1 whatever the cover noise (at the glade's own density the
  noise still raised copses of tall trees there), and the groves beyond come back to
  `GLADE_NEAR_EDGE` 0.15 of theirs. The other recipes keep the round glade. The P5-7 render:
  the floor and river of forest seeds 3, 2 and 1234 read from home. The water clears its own plants and the cliff, lip and scree rules dress the
  tiers, as they do for a tool's stroke.
- **Draws as measured** (24 surveyed seeds at 150 ft, the P5-4 verdict): valley rivers 19,
  bluffs 16; hill crowns 19, streams 9, stones 4; terraces rivers 19, bridges 8; lake streams
  16, stones 4; gorge streams 12, arches 7. The unit tests hold each chance within a window
  over 40 seeds and check that no draw breaks the map.

## Runtime

- **The open path.** `AuthoringController` emits the loading line
  `NewMap.opening_status(spec)` ("Shaping the valley..." for a landform other than Flat,
  "Building the map..." otherwise), then builds the document with `NewMapBuild` (P5-8:
  `NewMap.from_spec(spec)` on a `WorkerThreadPool` task, polled once a frame under the loading
  screen; the seed is drawn and the palette cache filled on the main thread first, the only
  shared state the recipe touches; on the calling thread under the headless dummy renderer,
  `GlbUtils.threaded_loads_safe`) and hands it to `MapSourceLoader.build_async("", doc)`.
  `from_spec` reads `{size_ft, biome_id, seed, landform}` (each
  optional: 100 ft, bare ground, a fresh seed, Flat) and calls `create`, which makes the flat
  document, applies the recipe and then paints the cover around its stage, all before the
  controller opens the map. The document is ordinary data by then, so the load path
  (`MapSourceLoader`, `AuthoredLoadPrep` on workers: water geometry, wet dressing, crossings)
  opens it as it would a saved map with sculpted ground, water and crossings; nothing at
  runtime knows a landform made it, and a saved landform map is an ordinary `map.ttmap`.
- **Costs.** P5-0's pure timings at 150 ft: a heights pass 69 ms, `plan_river` 1.5 ms,
  `river_goals` 56 ms, `lower` 1.5 ms, `WaterDressing.refresh` 96 ms, a crossing 3.3 ms; the
  Valley 254 ms per apply (P5-2: 180-340 ms for every recipe). The P5-5 pinned pass: a landform adds 85-325 ms to a 150 ft
  open of about 0.7 s and the recipe accounts for all of it, because it ran on the main
  thread in the frame that starts the open (worst frame under the loading screen 500-700 ms
  against Flat's 335-448 ms); a 200 ft gorge opened in 1.5 s with one 1.2 s frame. Since P5-8
  the recipe runs on a worker: worst frame 220-290 ms for every 150 ft landform and Flat alike
  (the load's own main-thread work), 517 ms for a 200 ft gorge. Memory in authoring within
  10 MB of Flat's. A shaped map strokes like a flat one (medians within 0.1 ms). In play the terraces
  level costs about 0.2 ms of GPU and 80 ms on a warm load, most likely its river and falls.

## Authoring

- **The dialog** (`NewMapDialog`, P5-3; [../UI_SYSTEMS.md](../UI_SYSTEMS.md) "New map
  dialog"): a Landform tile row under the biome grid, one glyph tile per `KINDS` entry in that
  order (ids `landform_<kind>`, icons `landform-<kind>.svg`, labels `NAMES`), and a caption
  under it that is the chosen kind's `CAPTIONS` entry. A caption describes the landform, never
  the draw, so an author is not promised a ford this seed did not draw. The default is
  `DEFAULT` (Valley) with a biome and Flat with Bare ground; picking a biome again brings back
  the landform shown before, unless the author picked one in between. The spec gains
  `landform`. F1's "New map" row: "Pick a size, a biome and a landform; the seed draws the
  water and the way across".
- **Everything is editable.** A recipe writes only what the tools write, with no history
  entry: the tiers are Sculpt tiers (Raise, Smooth, Flatten, Tier work on them as on any
  stroke), the rivers and ponds are Water tool bodies (Ctrl erases a river whole; a new river
  joins them as a confluence), the crossings are Bridge tool crossings (Ctrl erases one; they
  follow later sculpt and water edits), the wash is a painted surface. Not in scope (decided
  2026-10-04): a landform on a dressed Blender map, landform parameters (the tools are for
  that), a random-landform roll beyond the seed, several rivers per landform.
- **Harness:** the render-job driver's `new_map` op takes a `landform` key (default `flat`, so
  older jobs keep their ground); `probes/landform.gd` opens a landform map, logs the recipe's
  report and points the camera at its parts.

## Verification

- **Unit tests** (`tests/unit/`): `test_starting_landform.gd` (the kinds' names and captions,
  Flat changes nothing, the same seed gives a byte-identical map, seeds turn the axis, the
  trough's depth scales with size and the rim stays at the base, 40 seeds draw rivers near
  their chance and never break the map, the bluff is one tier on one bank only, the tributary
  joins the river, a dry draw paints a wash of the scree surface, the glade centres on the
  stage), `test_landform_hilltop.gd` (determinism, heading, the summit and a flat crown on a
  tier, 40-seed chances, no crown is never a bare mound, a crownless hill's flank ledge
  toward the camera, the crown pool spills over the face in a fall, cost),
  `test_landform_terraces.gd` (determinism, heading, dry draws on flat tiers with rock faces
  between, 40-seed chances, cost), `test_landform_lakeshore.gd` (determinism, the corner, never
  the camera's corner, one deep lake below its rim with the stage and islet dry, 40-seed
  chances, cost), `test_landform_gorge.gd` (determinism, heading, a dry floor tiers below the
  rim behind rock walls, 40-seed chances, cost), `test_authoring_open.gd` (a landform tile per
  kind, the default follows the biome, a pick sets the spec and caption, the icons load,
  `opening_status` names the landform), `test_landform_growth.gd` (room, the long map's turn
  and spread, the extras, open ground; since round 3 the greening on every map with the edge
  all meadow and the skirt continuing it, the band's depth, the wood, wide hills and lakes
  toward any side, the terraces' jog), `test_ground_accents.gd` (the accents' edge band, the
  skirt drawing none and continuing a painted edge). Phase 5 took the suite from 1890 to 1929
  tests.
- **Render jobs** (`tools/render_jobs/jobs/`, described in
  [../../tools/render_jobs/JOBS.md](../../tools/render_jobs/JOBS.md)): `landform_look.json`
  (P5-1 and P5-2: each landform in two biomes at home and zoom 8, water hidden and shown, the
  `_p5_` levels), `landform_dialog.json` (P5-3: the dialog with each tile and its caption),
  `phase5_valley/hilltop/terraces/lakeshore/gorge.json` and their union
  `phase5_judgment_set.json` (P5-4: 20 levels `_p5j_<kind>_<biome>_<seed>`, 103 captures; the
  verdict `VERDICT.md` and the captures in `user://render_jobs/phase5_judgment_set/`, the
  half-size iterations in `phase5_<kind>/`, the dialog in `landform_dialog/`), and the pinned
  pass `p5_perf_open.json`, `p5_perf_strokes.json`, `p5_perf_play.json`.
  `cleanup_levels.json` removes the `_p5_` and `_p5j_` levels. The verdict is summarised in
  [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Verification status".
- **Performance** ([../PERFORMANCE.md](../PERFORMANCE.md)): "Phase 5 (starting landforms):
  pinned performance pass (2026-10-04)", with "Opening a new map", "The first strokes on a
  shaped map" and "Play".

## Open work

The list is [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work", "Landform follow-ups";
this doc does not repeat it.

## History

- P5-0 (2026-10-04, no commit): the open path timed through the pure functions (a scratch
  probe); the recipe's water stays before the open.
- P5-1 (aaa3231): `StartingLandform`, the shared steps and the Valley; `NewMap.create`'s
  `landform`, `paint_starting_cover`'s centre, `NewMap.from_spec`; `probes/landform.gd`,
  `jobs/landform_look.json`.
- P5-3 (b226cfb): the dialog's Landform row, the glyphs, the caption, the default,
  `NewMap.opening_status`, the F1 row, the driver's `landform` key, `jobs/landform_dialog.json`.
- P5-2 (469c0d2): Hilltop, Terraces, Lakeshore and Gorge; `disc_distance`, `box_distance`,
  `tier_inset`, `carve_pond`, `restore_outside`, `span_crossing`; the Valley at 3.5 m with
  the rim at 0.6.
- P5-4 (4bf7ea9, 2c11229, 43fbcab, a46b3e4, 0bcda1d, 353a6ae): the judgment set and its
  fixes: gorge headings across the view, two tiers from 150 ft, the stream at the far wall;
  the hill's crown pool and fall with the stage on the camera's shoulder, no bare mound; the
  lake centre at 0.5; the Valley's bluff; the camera fix (`VIEW` / `NEAR`); the `phase5_*`
  jobs.
- P5-5 (1ff484e): the pinned performance pass (`p5_perf_*` jobs, `PERFORMANCE.md`).
- P5-4b (8092d17): a flank ledge on crownless hills (crown chance 0.85), the lake away from
  the camera's corner, `cleanup_levels` covers `_p5_` and `_p5j_`.
- P5-6: these docs.
- P5-7 (b22df32, ce1877c, e85f7a2, fd717d5, f88781e, ad7e803): the lake's far corner
  weighted 0.6 and a side lake placed inside the home frame; `straightest_wet` for every
  crossing; the ledge arc 90-130 with `stream_azimuth_window`; the Valley's line glade with a
  thin camera-side bank. Unit tests: the far corner most common and
  no centre in the camera's quadrant, no stones refused over the drawn lake seeds at 100 and
  150 ft, no `no_water` over 40 valley seeds, the stream never crosses the bench over 40
  crownless seeds, the valley floor's centreline open and its rim dense.
- Big landforms (381c39a, 3ac5d88; 2026-10-09): `LandformGrowth`, `LandformPlacement`, the
  edge feather, `biglf_look` / `biglf_base`. Round 3: the greening at every size, the edge
  band 3-12 m and greened, the skirt continuing the edge's surface, the accents out of the
  band, the Hilltop's and Lakeshore's setting, the terraces' jog.
- P5-8: the new-map document built on a worker under the loading screen (`NewMapBuild`); the
  thread-safety audit (only the palette cache and the global RNG were shared, both now touched
  on the main thread first); `test_new_map_build.gd` (threaded and synchronous builds
  byte-identical for a 200 ft gorge and a 150 ft valley); `p5_perf_open` re-run.
