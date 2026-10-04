# Crossings

Phase 4b, P4b-1: plank footbridges and stepping stones over water, as document data, geometry
built from it, walkable collision, and an editor API; P4b-2: the Bridge tool and crossings
following later edits. The authoring bar is one line: a stroke drawn roughly from bank to bank
snaps itself to the waterline and the dry ground, picks its own levels, and keeps following the
ground and the water through every later sculpt or water edit, so a crossing never stands on dry
land or in mid-water and the author never re-anchors one by hand. The visual bar is a bridge or a
line of stones that belongs to its biome: clean boards of the palette's planks, stones of the
biome's own rock with its moss on top, read at tabletop zoom.

Plan: `docs/superpowers/plans/2026-09-27-phase4b-bridges.md` (local). The document entry
(`crossings.json`, its caps and the reader's rules) is in
[../ARCHITECTURE.md](../ARCHITECTURE.md) "Map document (map.ttmap)", Crossings bullet. The
Bridge tool's gestures, pane and refusal readout are in [../UI_SYSTEMS.md](../UI_SYSTEMS.md)
(authoring drawer, Bridge; "Brushes and gestures"). The water a crossing reads is
[water.md](water.md); the waterfall it refuses is [waterfalls.md](waterfalls.md).

## Map

| File | Class | Role |
|------|-------|------|
| `resources/crossing.gd` | `Crossing` | One crossing: id, kind, anchors, levels, width, style |
| `resources/map_document.gd` | `MapDocument` | `crossings` (at most 64) |
| `utils/map_crossing_io.gd` | `MapCrossingIO` | Writes and validates `crossings.json` for `MapDocumentIO` |
| `utils/crossing_placement.gd` | `CrossingPlacement` | Pure: snaps a drawn line to the banks, levels, refusals (`fall_near()` among them), `style_at` |
| `utils/crossing_geometry.gd` | `CrossingGeometry` | Pure, worker-safe: planks, stringers, posts, stones, collision strips, `deck_field`, `clearance` |
| `scenes/terrain/authored_crossings.gd` | `AuthoredCrossings` | The node under the map root: per-crossing meshes, collision, materials per style, `warm_materials`, `world_top`, `exclude_of` |
| `scenes/states/authoring/crossing_editor.gd` | `CrossingEditor` | `AuthoringEditor.crossings`: plan, place, replace, remove, `follow(area)` and `restore` |
| `scenes/states/authoring/bridge_brush.gd` | `BridgeBrush` | The Bridge tool (`BrushTool` mode `BRIDGE`): live re-plan, refusal text |
| `scenes/states/authoring/bridge_tool_pane.gd` | | The Bridge pane (`UI_SYSTEMS.md`) |
| `utils/ground_height_field.gd` | `GroundHeightField` | The deck texture the grid shader reads (`get_deck_texture()`), `world_height_at()` with decks |
| `utils/scatter_ground.gd` | `ScatterGround` | Nothing grows under a deck, its stones or the landings (`sampler` times `clearance`) |
| `utils/authored_load_prep.gd` | `AuthoredLoadPrep` | The `CROSSINGS` part built on the load worker |

## Model

- **Model** (`Crossing`, `resources/crossing.gd`; `MapDocument.crossings`, at most 64): a
  stable `id` (1..255), a `kind` (`PLANK` or `STONES`; a stone arch can be a third kind with
  the same fields), the two bank anchors `start` / `end` in map XZ, `levels` (the walking
  surface's height at the start, the middle and the end), `width_m` (deck width 0.8..3 m, or
  a stone's size 0.4..1.2 m) and `style` (the palette biome whose materials it takes, or "").
  Everything else is derived, so a crossing ships as a few numbers and every peer builds the
  same one (seeded by the map seed and the id). Entry: `crossings.json`
  ([../ARCHITECTURE.md](../ARCHITECTURE.md) "Map document (map.ttmap)").
- **Placement** (`CrossingPlacement`, `utils/crossing_placement.gd`, pure): `place(doc, from,
  to, kind, width, style) -> {crossing, refusal}` snaps a drawn line to the banks. It walks the
  line every 0.1 m, reaching 8 m past both ends, marks wet samples (ground below the water
  level, `WaterGeometry.is_wet_at`), joins wet runs over dry gaps under 0.8 m (a bar mid-
  stream), takes the run the line overlaps most (or the nearest within 1 m), refines each
  end to the waterline by bisection and puts the anchor 0.55 m (plank) or 0.35 m (stones)
  onto the dry bank. Levels: a deck's ends stand `DECK_ABOVE_BANK_M` (0.2 m: sill, stringer,
  plank) over the bank ground and its middle arches 6 % of the span (0.12..0.8 m), never
  under 0.45 m over the highest water crossed; stone tops stand 0.15 m over it, clear of the
  `WaterZone` slab (level + 0.05) so a token on a stone is dry. Refusals: `short`,
  `no_water`, `no_bank` (no dry ground in reach, or off the map), `fall` (within 1 m of a
  waterfall, below), `long` (over 24 m).
  `style_at(doc, p)` is the biome painted under a point. It reads document water only; a
  Blender map's own water plane is not a crossing target (the Bridge tool is disabled on a
  dressed map without document water). The walk smooths each river once per call and keeps
  only the run of its course near the walk (`WaterGeometry.river_courses(doc, near)`, which
  `level_at` / `is_wet_at` take as `courses`): 9.2 -> 1.8-2.3 ms per plan on a 42 m river.
- **Falls (phase 4c, P4c-5, 2026-10-04):** `REFUSED_FALL` ("Too close to the waterfall.
  Bridges cross calm water.", `BridgeBrush.FALL`): a line is refused when the deck or stone
  strip comes within `FALL_CLEAR_M` 1 m of a fall of the document (`WaterFalls.falls`), that
  is of its footprint (`WaterFalls.footprint_of`: the face from the lip to its foot across the
  channel) or of its foam ring disc (`WaterFallMesh.ring_radius` of the channel's full width,
  centred `ring_centre()` past the face's foot, `WaterFalls.face_foot`); pure `fall_near()`.
  The zone is the face and the ring each grown by 1 m, not the footprint grown uniformly
  (which would have refused 2 m upstream of the lip); it is generous downstream, about 4 m
  below a waist river's lip (open work). A fall whose lip stands further from the strip than
  any of that reaches is not measured, so a line over calm water costs the `falls()` scan
  alone. A line across the face alone is refused `fall` too, and not `no_water` as planned:
  `level_at` has no flush cut at a reach's end, so the face reads the upper pool's level and
  `is_wet_at` is true there (the leak, [waterfalls.md](waterfalls.md) Runtime). The follow
  rule needed no change: a bridge whose re-snap now lands within the zone is removed with the
  existing toast and comes back on undo (`test_bridge_tool.gd`: a river falling under a bridge
  removes it in the carve's entry). A deck over the lip is not in scope (decided 2026-10-04;
  it can be added later if wanted). Tests: `test_crossings.gd` (a crossing keeps clear of a
  waterfall, and is allowed 2 m upstream); render job `jobs/falls_tools.json` (the red refusal
  and its toast, the upstream bridge placed).

## Runtime

- **Geometry** (`CrossingGeometry`, `utils/crossing_geometry.gd`, pure, worker-safe):
  `build(doc) -> {crossings: [{id, kind, style, wood, stone, collision, top}], deck}`. A plank
  bridge is boxes: planks across the span on the quadratic arch (`deck_y`), one 0.27 m pitch
  apart with jitter in length, offset, yaw, drop and shade; two stringers along the arch
  onto a sill beam bedded in each bank; posts along both edges (2.2 m apart at most) under
  one top rail; pile bents to the bed on a span over 5.5 m where the ground is well below.
  Each wood box maps into one clean board of the palette's `planks` albedo (`WOOD_SWATCHES`),
  grain along its length, so a modelled plank never shows a painted seam. Stepping stones:
  one stride apart (the document's cell, one 5 ft square per step), centred on the span, each
  a flat-topped nine-sided stone (top, chamfer, rounded shoulder near the waterline, a flared
  root under the bed) in flat-shaded facets, the root darkened as wet, sizes varied 0.84-1.14x
  (default size 1.15 m since P4b-2: at 1.05 m they read small at home zoom). Winding is clockwise
  from the front. Collision: a deck's walking surface as a smooth strip (the planks' jitter
  stays visual), a stone's own triangles. `deck_field(doc, crossings)` rasterises the decks'
  walking surface on the sample grid (0.3 m past the edges), `clearance(crossings, p)` is what
  plants keep beside a crossing.
- **Node** (`AuthoredCrossings`, `scenes/terrain/authored_crossings.gd`, under the map root at
  the identity): per crossing `Crossing_<id>` with its `Wood` / `Stones` meshes and one
  `Collision` StaticBody3D on the terrain layer (layer 1, mask 0, not ray-pickable,
  `CROSSING_META` = id). Materials per style: an `ORMMaterial3D` of `planks` tinted by the
  biome's climate (`WOOD_TINTS`: dry country sun-bleached, cold silvered), and of the biome's
  `cliff_surface` triplanar for stones (at 1.4x its tile, so a stone's top shows one stratum
  rather than stripes; the cold biomes' near-black `cliff_basalt` lifted to the boulders' light
  grey by `STONE_SURFACE_TINTS`, P4b-3), vertex colours shading both. In a temperate or cold
  biome a stone's upward facets take the palette's `moss` surface (a second surface of the
  stone mesh, one shared triplanar material), decided per facet in patches by a fixed field
  of the facet's position (`is_moss`, `moss_split`, `MOSS_AMOUNTS` by climate; facets steeper
  than `MOSS_MIN_UP` never), the way treecube's rocks give each face rock or moss, so the
  stones match the palette's mossy boulders. The stone top is a fan to an inner ring plus a
  zigzag band (`STONE_INNER_INSET`), small enough facets for patches rather than pie slices.
  (P4b-2 tinted the rock's vertex colours instead; 8-bit colours can only darken, so the tops
  read dull olive beside the boulders' bright moss: P4b-3 judgment set.) `deck_heights`,
  `version` and `top_y` feed the grid and the drag. `MapSourceLoader.add_authored_crossings()` builds it for any
  document with crossings (in a frame of its own after an authored root's chunks, from the
  worker's `AuthoredLoadPrep.CROSSINGS` part, with its textures requested on background
  threads alongside the ground's; on a dressed GLB's root in `_build_async`), always in
  authoring. Measured: build 3-5 ms for a bridge and three stones; the first node of a
  (kind, style) cost 15-31 ms, which P4b-2 split (probe `crossing.gd first_use`): 3 ms making
  the material (texture loads) and 14-16 ms building its shader, which a BaseMaterial3D does
  when its RID is first asked for. The Bridge tool warms both as it opens
  (`warm_materials(styles)` 0.4 s after the textures start loading on workers, the moss too
  where a style grows it), so a placement's swap is 0.2-1.9 ms. An edit rebuilds every
  crossing's geometry on the main thread, about 2.4 ms each (P4b-3: 3 ms with one crossing,
  13 ms with five); a per-crossing cache would need the ground under each crossing in its key.
  In play the crossings cost nothing measurable and add about 50 ms to a load with four
  (`PERFORMANCE.md` "Phase 4b (crossings): pinned performance pass").
- **Walkable:** tokens land on a deck or a stone like the ground (layer-1 rays); the drag's
  ground cast starts above `AuthoredCrossings.world_top()` as well as the terrain top
  (`GameMap._resolve_drag_ground`), so a drop onto an arch lands on it; tokens cannot pass
  under a bridge. The measure tool, drop indicator and drag ruler hit decks as ground.
- **Grid:** `GroundHeightField` gives the grid shader the decks as a second texture
  (`get_deck_texture()`: the deck field, `NO_DECK` elsewhere), not in the height field: a
  pixel within the tolerance of a deck's surface is on the deck (its own facet is the slope
  test there), everything else sees ground and water as before. Raising the height field to
  the deck lost the grid on the water along the deck's near side, whose bed, seen through the
  water, lies under the deck in XZ. `world_height_at()` includes the decks. Stepping stones
  stand within the grid's tolerance of the water surface and need nothing. A Blender map's
  sampled field includes decks (they are layer 1).
- **Scatter:** nothing grows under a deck or its stones nor on the bank landings 0.9 m past
  each anchor, rocks included (`ScatterGround.sampler` times `CrossingGeometry.clearance`,
  fading back over 0.5 m; the scatter snapshots copy `crossings`). Trees keep a further
  1.2 m back (`CLEAR_TREE_M`) and shrubs and rocks 0.6 m (`CLEAR_SHRUB_M`), so no trunk, bush
  or boulder stands on a landing (P4b-3; a tall canopy further in front can still cover a
  bridge from the camera, which the occlusion fade handles only over tokens). A dressed map's
  own Blender scatter is not cleared under a crossing.
- **Networking:** nothing new: the crossings travel in `map.ttmap`, which is sent whole and
  hashed; every peer builds them from the entry.

## Authoring

- **API** (`AuthoringEditor.crossings`, a `CrossingEditor`,
  `scenes/states/authoring/crossing_editor.gd`; world frame): `plan(kind, from, to, width)
  -> Crossing or null` (the live preview, changes nothing; `last_refusal` says why),
  `place(...) -> id or -1`, `add(crossing) -> id`, `replace(id, crossing) -> bool` (keeps the
  id: re-anchoring), `remove(id) -> bool`, `crossing_at(point, margin) -> id or -1` (a Ctrl
  erase), `list()`, `get_crossing(id)`. Each change is one history entry (the crossing list
  before and after; crossings are replaced whole, never edited in place) and refreshes the
  node and the scatter over the crossing's footprint.
- **Following edits** (P4b-2, `CrossingEditor.follow(area)`, pure core `followed_list(doc,
  area)`): a crossing is anchored to ground and water, so when a sculpt stroke (any tile) or a
  water edit (river carved, pond painted or extended, water erased) changes the document over
  `area`, every crossing whose footprint comes within 1 m of it is snapped again from its own
  two anchors, as if that line were drawn again (same kind, width and style). A snap that still
  makes a crossing replaces it keeping its id (a moved bank, a shorter span, an end climbing a
  raised bank); a snap that makes none removes it (the water is gone, a bank went under, the
  span grew past 24 m), so a crossing never stands on dry ground or in mid-water. A new snap
  within 3 cm and 2 cm of the old one keeps the old object (no nudging). The change is part of
  the causing edit's history entry: `AuthoringEditor._end_height_stroke` and
  `WaterEditor._finish` store `follow()`'s `{before, after, area}` in their record, and their
  undo / redo call `restore(record, redo)` after the heights and water, so one undo puts ground,
  water and crossing back together. `followed(moved, removed)` makes the controller toast a
  removal ("A crossing lost its water and was removed. Undo brings both back.").
- **Tools see through crossings:** the brush's pointer ray and a placed prop's bedding
  exclude the crossing bodies (`AuthoredCrossings.exclude_of`), as does a dressed map's
  ground sampling into document heights (`DressingGround.begin(..., exclude)`); a sculpt
  stroke marches the document's heights and never sees them. Sculpt, Paint and Water edit the
  ground under a bridge.
- **Bridge tool** (`BridgeBrush`, `scenes/states/authoring/bridge_brush.gd`; `BrushTool` mode
  `BRIDGE`): a press starts a line, every 8 cm of pointer travel re-plans it (`plan`, 1.8-2.3
  ms), the release adds the last plan (one entry). Its pointer ray does not skip crossing
  bodies (the other brushes do), so a deck is picked where it is drawn. See UI_SYSTEMS.md
  "Bridge".

## Verification

- **Unit tests** (`tests/unit/`): `test_crossings.gd` (placement, geometry, the fall refusal
  and the 2 m upstream allowance), `test_crossing_editor.gd` (the API, following edits),
  `test_map_document_crossings.gd` (the entry), `test_bridge_tool.gd` (the tool; a river
  falling under a bridge removes it in the carve's entry).
- **Render jobs** (`tools/render_jobs/jobs/`): look passes `crossing_look.json` and
  `bridge_tool.json` (probe `probes/crossing.gd`), `bridge_first_use.json` (the first-use
  cost split), P4b-3's judgment set over every biome `phase4b_judgment_set.json` and the
  re-anchoring check `p4b3_reanchor.json`, and `falls_tools.json` (the fall refusal). Captures
  and verdicts are indexed in [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Verification
  status".
- **Performance** ([../PERFORMANCE.md](../PERFORMANCE.md)): "Phase 4b (crossings): pinned
  performance pass (2026-09-27)", with "Play: crossings shown and hidden in one run".

## Open work

The list is [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work"; this doc does not repeat it
(the generous downstream refusal zone and the stone arch and fords are there).

## History

- P4b-1 (2026-09-27): the model, placement, geometry, node, collision, grid on the deck and
  the editor API.
- P4b-2 (c6d508f): the Bridge tool through real input, crossings following later edits, stone
  size 1.15 m, the first-use cost split.
- P4b-3 (a9cfff1, 77f899e, 12f9114): palette moss on stepping stones, light basalt, trees back
  from the landings, the judgment set, the re-anchor check, the pinned performance pass.
- P4c-5 (4673813, 2026-10-04): the refusal by a waterfall.
