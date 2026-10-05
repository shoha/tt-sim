# Crossings

Four kinds of crossing over water, as document data, geometry built from it, walkable
collision, and an editor API: plank footbridges and stepping stones (phase 4b, P4b-1; the
Bridge tool and crossings following later edits, P4b-2), the stone arch and the ford (phase
4d, 2026-10-04). The authoring bar is one line: a stroke drawn roughly from bank to bank snaps
itself to the waterline and the dry ground, picks its own levels, and keeps following the
ground and the water through every later sculpt or water edit, so a crossing never stands on
dry land or in mid-water and the author never re-anchors one by hand. A ford adds one more
bar: it crosses wadeable water only, and a token wading it is never hidden (the bar stands
ankle deep under the surface). The visual bar is a crossing that belongs to its biome: clean
boards of the palette's planks, stones and masonry of the biome's own rock with its moss on
top, a deck paved in the biome's own flags, read at tabletop zoom.

Plans: `docs/superpowers/plans/2026-09-27-phase4b-bridges.md` and
`docs/plans/2026-10-04-phase4d-arch-and-ford.md` (both local). The document entry
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
| `utils/crossing_geometry.gd` | `CrossingGeometry` | Pure, worker-safe: planks, stringers, posts, stones, collision strips, `deck_field`, `clearance`; `build_one` dispatches by kind |
| `utils/crossing_arch.gd` | `CrossingArch` | Pure, worker-safe: the stone arch (abutments, barrel, spandrels, pier, parapets, paving slab); `layout`, `intrados_at`, `has_pier` |
| `utils/crossing_ford.gd` | `CrossingFord` | Pure, worker-safe: the ford's gravel bar, landings and marker stones; `flow_at`, `downstream_side`, `stone_layout` |
| `utils/crossing_cache.gd` | `CrossingCache` | Pure: per-crossing rebuild keys over the fields, the ground and the water under a crossing; `plan`, `key_of` |
| `scenes/terrain/authored_crossings.gd` | `AuthoredCrossings` | The node under the map root: per-crossing meshes, collision, materials per style (wood, stone, moss, paving, gravel), `warm_materials`, `world_top`, `exclude_of` |
| `scenes/states/authoring/crossing_editor.gd` | `CrossingEditor` | `AuthoringEditor.crossings`: plan, place, replace, remove, `follow(area)` and `restore` |
| `scenes/states/authoring/bridge_brush.gd` | `BridgeBrush` | The Bridge tool (`BrushTool` mode `BRIDGE`): live re-plan, refusal text |
| `scenes/states/authoring/bridge_tool_pane.gd` | | The Bridge pane (`UI_SYSTEMS.md`) |
| `utils/ground_height_field.gd` | `GroundHeightField` | The deck texture the grid shader reads (`get_deck_texture()`), `world_height_at()` with decks |
| `utils/scatter_ground.gd` | `ScatterGround` | Nothing grows under a deck, its stones or the landings (`sampler` times `clearance`) |
| `utils/authored_load_prep.gd` | `AuthoredLoadPrep` | The `CROSSINGS` part built on the load worker |

## Model

- **Model** (`Crossing`, `resources/crossing.gd`; `MapDocument.crossings`, at most 64): a
  stable `id` (1..255), a `kind` (`PLANK`, `STONES`, `ARCH` or `FORD`; `KIND_NAMES`
  "plank", "stones", "arch", "ford" in the entry; `is_deck()` is PLANK or ARCH, the kinds
  with a walking deck), the two bank anchors `start` / `end` in map XZ, `levels` (the walking
  surface's height at the start, the middle and the end), `width_m` and `style` (the palette
  biome whose materials it takes, or ""). Width by kind (`MIN_WIDTH_M` / `MAX_WIDTH_M` /
  `DEFAULT_WIDTH_M`): a plank deck 0.8..3.0 m (default 1.5), a stone's size 0.4..1.2 m
  (1.15), an arch deck 1.2..3.0 m (2.0), a ford's bar 1.5..4.0 m (2.5; a ford's width runs
  along the river, the span across it). Everything else is derived, so a crossing ships as a
  few numbers and every peer builds the same one (seeded by the map seed and the id). Entry:
  `crossings.json` ([../ARCHITECTURE.md](../ARCHITECTURE.md) "Map document (map.ttmap)"); a
  v0.1.30 build drops an arch or ford entry with a warning and keeps the rest.
- **Placement** (`CrossingPlacement`, `utils/crossing_placement.gd`, pure): `place(doc, from,
  to, kind, width, style) -> {crossing, refusal}` snaps a drawn line to the banks. It walks the
  line every 0.1 m, reaching 8 m past both ends, marks wet samples (ground below the water
  level, `WaterGeometry.is_wet_at`), joins wet runs over dry gaps under 0.8 m (a bar mid-
  stream), takes the run the line overlaps most (or the nearest within 1 m), refines each
  end to the waterline by bisection and puts the anchor `BANK_INSET_M` onto the dry bank:
  0.55 m (plank), 0.35 m (stones), 0.8 m (arch: its abutment), 0.35 m (ford). Levels: a
  plank deck's ends stand `DECK_ABOVE_BANK_M` (0.2 m: sill, stringer, plank) over the bank
  ground and its middle arches `DECK_RISE_PER_M` 6 % of the span (0.12..0.8 m), never under
  0.45 m over the highest water crossed; stone tops stand 0.15 m over it, clear of the
  `WaterZone` slab (level + 0.05) so a token on a stone is dry; the arch's and the ford's
  levels are below. Refusals: `short`, `no_water`, `no_bank` (no dry ground in reach, or off
  the map), `deep` (a ford over water that is not wadeable, below), `fall` (within 1 m of a
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
- **Arch levels (phase 4d, P4d-1):** a segmental arch, never a semicircle (decided
  2026-10-04: a semicircle over a 6 m span stands 3 m tall and hides its own water from the
  camera). The ends stand `ARCH_DECK_ABOVE_BANK_M` 0.35 m over the bank ground (the abutment
  cap plus the deck slab); the middle rises `ARCH_RISE_PER_M` 10 % of the span, clamped
  `ARCH_MIN_RISE_M`..`ARCH_MAX_RISE_M` 0.3..1.5 m, over the mean of the ends, and never less
  than the highest water crossed plus `ARCH_CLEAR_M` 0.5 m plus `CrossingArch.BARREL_THICK_M`
  0.35 m, so the barrel's underside at mid-span keeps 0.5 m clear of the water. A span over
  `CrossingArch.PIER_MIN_SPAN_M` 9 m gets two arches on a mid-stream pier. The planks' old
  `ARCH_RISE_PER_M` was renamed `DECK_RISE_PER_M` for this.
- **Ford levels and the `deep` refusal (phase 4d, P4d-2):** a ford is derived geometry over
  the document's own bed, no height edit. Its ends are the bank ground itself (no deck) and
  its middle is the lowest water level the run crosses minus `FORD_DEPTH_M` 0.15 m: the
  gravel bar's crest, ankle deep (the P4d-0 probe: at 0.15 m a 0.3 m token is never flagged
  submerged, at 0.2 m by a hair; at 0.35 m the bar vanishes under the shader). The decision
  with the user: a ford over waist water raises its crest to ankle depth rather than only
  marking the line. `REFUSED_DEEP` ("Too deep to ford. Fords cross wadeable water.",
  `BridgeBrush` reason `deep`) refuses a ford when `deep_at` is true for any sample of the wet
  run: the point lies in the area of some body whose depth class is not wadeable
  (`WaterBody.is_wadeable`) with the ground below that body's level. Every body holding the
  point counts, not only the one whose level shows, so a deep channel carved under a shallow
  river's surface is deep. Checked inside the wet-run walk, before the fall test.

## Runtime

- **Geometry** (`CrossingGeometry`, `utils/crossing_geometry.gd`, pure, worker-safe):
  `build(doc) -> {crossings: [{id, kind, style, wood, stone, paving, gravel, collision, top}],
  deck}`; `build_one(doc, crossing)` branches on kind and hands the arch to `CrossingArch` and
  the ford to `CrossingFord`, keeping the shared pieces (`point`, `deck_y`, `rng_for`,
  `stone`, the mesh builder, `deck_collision`, `faces_of`). A plank bridge is boxes: planks across the span on the quadratic arch (`deck_y`), one 0.27 m pitch
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
  walking surface on the sample grid (0.3 m past the edges) for every deck kind
  (`is_deck()`: plank and arch), `clearance(crossings, p)` is what plants keep beside a
  crossing (the plank clearances for an arch, the stones' for a ford).
- **Arch** (`CrossingArch`, `utils/crossing_arch.gd`, phase 4d, P4d-1 and P4d-4; pure,
  worker-safe): a masonry arch bridge in a few bold flat-shaded parts, never fussy masonry. An
  abutment at each end, a block from `ABUTMENT_BACK_M` 0.35 m behind the anchor to
  `ABUTMENT_FACE_M` 0.6 m toward the water, bedded `ABUTMENT_BURY_M` 0.4 m under the lowest
  ground beneath it, its cap `DECK_THICK_M` 0.12 m under the deck. Between the abutment faces
  the barrel: a parabolic intrados springing `SPRING_DROP_M` 0.3 m below each cap to the crown
  `BARREL_THICK_M` 0.35 m under `deck_y` at the arch's centre, faceted `BARREL_SEGMENTS` 16
  along and `BARREL_ACROSS` 6 across, with a ring of voussoirs `RING_M` 0.28 m deep along it
  on each spandrel face, graded spandrel walls up to the deck (`WALL_LOW_SHADE` 0.74 at the
  ring to `WALL_SHADE` 0.88), and a stone lip at deck level outside the parapets. Over
  `PIER_MIN_SPAN_M` 9 m two arches stand on a pier `PIER_W_M` 0.9 m thick at mid-span, from
  the bed to the springing, its cap `PIER_FREEBOARD_M` 0.15 m over the water, with cutwater
  noses `PIER_NOSE_M` 0.55 m past the deck's width on both sides and a cap course
  `PIER_CAP_H_M` 0.14 m overhanging `PIER_CAP_OVERHANG_M` 0.05 m; the deck stays one `deck_y`
  curve. Parapets along both edges, `PARAPET_W_M` 0.25 m thick and `PARAPET_H_M` 0.45 m
  high, `PARAPET_INSET_M` 0.05 m in from the deck edge, each topped by a coping course of
  stones `COPING_STONE_M` 0.55 m long (a joint at the crown, `COPING_GAP_M` 0.035 m dark
  joints, `COPING_SHADE_JITTER` 0.07) and each stone keyed for moss as one (a moss key thrown
  `MOSS_KEY_THROW_M` 7 m from its centre in the UVs, which `AuthoredCrossings.moss_split`
  reads as the facet's field position; one continuous coping read as a green stripe in the
  first look). The copings, the lip and the abutment and pier caps face up and take the moss
  in damp climates as the stepping stones do; walls and intrados never. The deck is a paving
  slab between the parapets, its own mesh, UV-mapped in world metres so no seam shows at the
  abutments. Vertex colours: the intrados darkest (`INTRADOS_SHADE` 0.58) and cool, caps and
  copings `CAP_SHADE` 1.0, every facet jittered `SHADE_JITTER` 0.05, masonry within `DAMP_M`
  0.3 m over the water darkened toward `WET_SHADE` 0.55 and the feet under the water level
  plus `WET_ABOVE_M` 0.12 m wet like a stone's root, a warm cast `WARM` (1.0, 0.975, 0.93) on
  sunlit stone and a cool one `COOL` (0.9, 0.95, 1.0) under the barrel. Three surfaces in the
  node's mesh: stone, moss, paving. Collision is the deck strip alone (`deck_collision`; a
  token dropped on a parapet lands on the deck, as on a plank bridge's rail). The 5.4 m arch
  is 1,696 vertices of stone, the 14.8 m pier arch 3,604.
- **Ford** (`CrossingFord`, `utils/crossing_ford.gd`, phase 4d, P4d-2 and P4d-4; pure,
  worker-safe): a gravel bar across the channel, no height edit. One smooth grid of `ACROSS` 7
  rows sampled every `STEP_M` 0.25 m along the span from `LANDING_M` 1.2 m before the start
  anchor to 1.2 m past the end. Wet samples (ground under the water) take the crest, the water
  level minus `FORD_DEPTH_M` with `NOISE_M` 0.03 m of height noise, falling to the bed over the
  outer `SHOULDER_M` 0.6 m of each side and never above the level minus `SURFACE_CLEAR_M`
  0.05 m; across the bar the crest holds over the downstream `CREST_SHARE` 0.4 of the width
  and dips `CROSS_DROP_M` 0.12 m toward the upstream edge, so the water shader's depth foam
  (a band a few tenths of a metre deep: the P4d-0 probe) draws a bright line along the
  downstream lip fading upstream, a riffle with an edge where a flat bar made one even wash.
  Dry samples are the landings: a `PAD_M` 0.03 m gravel skin over the ground fading out over
  the last `LANDING_FADE_M` 0.4 m, the rim sunk `RIM_SINK_M` 0.02 m so the terrain hides the
  seam (a coplanar strip draws as a pale rectangle), each landing narrowing past its anchor as
  a rounded tongue to `END_WIDTH_SHARE` 0.3 of the width with edges wandering `EDGE_WOBBLE_M`
  0.09 m along a slow wave (`EDGE_WOBBLE_FREQ` 2.7), so the pad reads trodden. Vertex colour
  runs from `DRY_SHADE` 1.0 on the landings to `WET_SHADE` 0.58 at the crest, with a damp
  tide-line `DAMP_M` 0.12 m over the water (`DAMP_SHARE` 0.7), `END_SHADE` 0.85 at a landing's
  far end and `SIDE_SHADE` 0.8 at its rims. Marker stones along the downstream edge
  (`downstream_side`: the side the river flows to at mid-span by `flow_at`, the left over a
  pond), `STONE_EDGE_M` 0.1 m inside it: `STONES_MIN`..`STONES_MAX` 3..5 by the width (one per
  `STONE_PER_M` 0.8 m), `STONE_M` 0.62-0.78 m across, one stride apart but never under
  `STONE_MIN_PITCH_M` 0.7 m, fewer where the wet run has no room (`STONES_NARROW` 2 on a
  narrow stream), tops `STONE_ABOVE_M` 0.12 m over the water, built by `CrossingGeometry.stone`
  so they match the stepping stones and take the moss; each one breaking the surface takes
  the shader's edge foam by itself. Winding is `PlaneMesh`'s, clockwise seen from above (the
  probe's first bar was culled from above while its collision still landed tokens). Collision
  is the bar's own triangles (crest and landings) plus the stones', so a wading token walks on
  the bar; no deck field: the grid lies on the water surface over a ford as over any wadeable
  water. Materials: the biome's gravel (`AuthoredCrossings.gravel_surface`: `gravel_sandstone`
  with a sandstone cliff, else `gravel`) triplanar at `GRAVEL_TILE_SCALE` 1.0, tinted
  `GRAVEL_TINT` (0.9, 0.88, 0.84), the sandstone gravel darker and duller by
  `GRAVEL_SURFACE_TINTS` (0.76, 0.7, 0.64) since at full tint the landings vanished on the
  badlands sand and read as a red-orange splat on the savanna's grass; the stones take the
  stone and moss materials. A ford is 196-203 vertices of gravel.
- **Node** (`AuthoredCrossings`, `scenes/terrain/authored_crossings.gd`, under the map root at
  the identity): per crossing `Crossing_<id>` with its meshes by kind (a plank bridge's wood, a
  stone or arch mesh with its stone, moss and, for an arch, paving surfaces, a ford's gravel
  and stones) and one `Collision` StaticBody3D on the terrain layer (layer 1, mask 0, not
  ray-pickable, `CROSSING_META` = id). Materials per style: an `ORMMaterial3D` of `planks`
  tinted by the biome's climate (`WOOD_TINTS`: dry country sun-bleached, cold silvered), and
  of the biome's `cliff_surface` triplanar for stones and masonry (at 1.4x its tile, so a
  stone's top shows one stratum rather than stripes; the cold biomes' near-black
  `cliff_basalt` lifted to the boulders' light grey by `STONE_SURFACE_TINTS`, P4b-3), a paving
  material of the biome's first paved path surface among `PAVING_SURFACES` (`flagstone`,
  `flagstone_sandstone`, `cobblestone`, `stone_tiles`, in the biome's own order; the stone
  material when it has none) for an arch's deck, and the gravel material above for a ford,
  vertex colours shading all of them. In a temperate or cold
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
  when its RID is first asked for. The Bridge tool warms them all as it opens
  (`warm_materials(styles)` 0.4 s after the textures start loading on workers: wood, stone,
  paving, gravel, and the moss where a style grows it), so a placement's swap is 0.2-1.9 ms
  for planks and stones (4.4-6.3 ms for an arch or ford node before the 2026-10-05 follow-up,
  below). An edit rebuilds, on the main
  thread, only the crossings whose geometry inputs changed (P4d-5b, `CrossingCache`,
  `utils/crossing_cache.gd`): per crossing a key hashing its fields, the document's seed and
  grid, the heights over `clear_bounds` plus one sample, and the water that can reach the
  bounds (rivers near them by id, level, points and half-widths; the pond mask over them and
  the ponds marked in it). `refresh(doc)` keeps the node whose key matches, builds the rest
  (`build_one`), frees the nodes of crossings that left, and recomputes the deck field,
  `top_y` and `version` only when some node changed; `create()` seeds the keys from the
  document the load's worker built from. A placement thus builds one crossing (a ford 5-7 ms,
  the pier arch 13, planks or stones 3-4; 33.8 ms for a sixth placement before), a sculpt
  rebuilds the crossings whose ground rectangle it touched, a water edit the crossings its
  bodies reach (`PERFORMANCE.md` "Per-crossing rebuild cache (P4d-5b)"; `builds`,
  `last_rebuilt` and `keys()` on the node are for tests and the probe).
  The swap and the ford's build were profiled on 2026-10-05 (headless, the `_p4d_` forest
  level): most of an arch or ford placement's swap was the deck field, re-rasterised over
  every deck on the map whatever kind was placed (3.05 ms for five crossings; per sample a
  `local_of` and a `sample_to_world` through the document's methods), then `moss_split`
  (0.5 ms for the 5.4 m arch, 1.1 ms for the pier arch). Now the node keeps which crossings
  are decks (`_decks`) and the field changes only with a deck: re-rasterised when a deck
  left or was rebuilt, a placed deck added onto it (`CrossingGeometry.deck_field_add`, the
  same values, since a sample keeps its highest deck), untouched for a ford or stones; the
  rasteriser reads the grid once (3.05 -> 0.60 ms for the five, 0.35 ms to add the pier arch);
  `moss_split` decides the facets inline with no centre for a facet too steep for moss
  (0.52 -> 0.16 ms, 1.06 -> 0.34). The ford's build was its 280 samples' `level_at` (10 us
  each against the river course) and `ground_at` (3 us, the grid through the document's
  methods): `CrossingFord._bar` now lays out its samples first and reads them in two batches,
  `WaterGeometry.grounds_at` and `levels_along` (each run of four rows asks the river cut to
  the segments near its own box, `_course_near`, so the values are level_at's), and the
  stones' wet-run walk does the same: a 2.5 m waist ford 4.46 -> 1.93 ms, the ankle ford 3.04
  -> 1.26. The geometry is byte-identical (the parts' and moss split's digests before and
  after; `test_crossing_cache.gd` compares the batches with the per-point calls and the
  incremental deck field with a full build). In play the crossings
  cost nothing measurable and add about 50 ms to a load with four (`PERFORMANCE.md` "Phase 4b
  (crossings): pinned performance pass").
- **Walkable:** tokens land on a deck, a stone or a ford's bar like the ground (layer-1 rays;
  on the bar the float rule stands a token ankle deep with no submerged ring); the drag's
  ground cast starts above `AuthoredCrossings.world_top()` as well as the terrain top
  (`GameMap._resolve_drag_ground`), so a drop onto an arch lands on it; tokens cannot pass
  under a bridge. The measure tool, drop indicator and drag ruler hit decks as ground.
- **Grid:** `GroundHeightField` gives the grid shader the decks as a second texture
  (`get_deck_texture()`: the deck field, `NO_DECK` elsewhere), not in the height field: a
  pixel within the tolerance of a deck's surface is on the deck (its own facet is the slope
  test there), everything else sees ground and water as before. Raising the height field to
  the deck lost the grid on the water along the deck's near side, whose bed, seen through the
  water, lies under the deck in XZ. `world_height_at()` includes the decks (plank and arch).
  Stepping stones stand within the grid's tolerance of the water surface and need nothing; a
  ford adds nothing either, the grid lies on the water over its bar as over any wadeable
  water. A Blender map's sampled field includes decks (they are layer 1).
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
  removal ("A crossing lost its water and was removed. Undo brings both back."). A river
  deepened under a ford (a deep tributary carved into it) removes the ford the same way, since
  its re-snap is refused `deep`, and undo brings both back. `follow` also refreshes the node
  when no anchor moved but the edit touched a crossing's bounds (P4d-5c): a sculpt that
  changes the bed under a bridge's piles, a stone's root or a ford's bar without moving an
  anchor rebuilds that crossing, and the cache (Runtime, Node) makes it cost only the
  crossings whose ground changed.
- **Tools see through crossings:** the brush's pointer ray and a placed prop's bedding
  exclude the crossing bodies (`AuthoredCrossings.exclude_of`), as does a dressed map's
  ground sampling into document heights (`DressingGround.begin(..., exclude)`); a sculpt
  stroke marches the document's heights and never sees them. Sculpt, Paint and Water edit the
  ground under a bridge.
- **Bridge tool** (`BridgeBrush`, `scenes/states/authoring/bridge_brush.gd`; `BrushTool` mode
  `BRIDGE`): a press starts a line, every 8 cm of pointer travel re-plans it (`plan`, 1.8-2.3
  ms; 3.1-3.5 ms for any kind on the P4d-5 map), the release adds the last plan (one entry).
  Its pointer ray does not skip crossing bodies (the other brushes do), so a deck is picked
  where it is drawn. Four tiles in the pane (P4d-3, `KIND_TILES`, one column each): Planks,
  Stones, Arch (`building-bridge.svg`, id `bridge_arch`) and Ford (`ford.svg`, id
  `bridge_ford`); `KIND_LABELS` and `widths` per kind feed the Shift+wheel readout and the
  Ctrl-hover pill ("Remove stone arch"), the ghost takes `GRAVEL_TINT` for a ford and a deck
  band for decks and fords. The hint adds "Arches and fords cross calm water too; a ford needs
  wadeable water."; a ford over deep water draws the red line with "Too deep to ford. Fords
  cross wadeable water." beside the cursor and the same toast on release (`reason()` for
  `deep`). Through the tool a waist river at radius 1.5 takes a 2.0 m arch (span 4.6 m) and a
  2.5 m ford (span 3.7 m). F1 has a row per kind ("Arch (Bridge)", "Ford (Bridge)"); the
  render-job driver's `bridge_kind` resolves any `KIND_NAMES` entry. See UI_SYSTEMS.md
  "Bridge".

## Verification

- **Unit tests** (`tests/unit/`): `test_crossings.gd` (placement, geometry, the fall refusal
  and the 2 m upstream allowance; phase 4d: the arch's levels stand over the banks and clear
  the water, its three surfaces on one deck, a long arch gets a pier and keeps one deck
  curve, the ford's levels sit under the water with its ends on the banks, a ford is refused
  on deep water, the ford's parts (a gravel bar under the surface with landings and marker
  stones), an arch node carries stone, moss and paving and a ford node gravel, stone and
  moss), `test_crossing_editor.gd` (the API, following edits; a river deepened under a ford
  removes it and undo restores it), `test_map_document_crossings.gd` (the entry; an arch and a
  ford round-trip with their width ranges), `test_bridge_tool.gd` (the tool; a river falling
  under a bridge removes it in the carve's entry; an arch and a ford take the picked kind,
  Ctrl hover over a ford names it, follow keeps a crossing nothing changed under and
  re-anchors keeping the id when a bank moves), `test_crossing_cache.gd` (the key follows the
  fields, the ground and the water under the crossing and nothing else; a placement builds
  one crossing; undo and redo through `restore` rebuild the followed crossing once; the keys
  for six arches on the 100 ft map cost 0.147 ms). Phase 4d took the suite from 1862 to 1889
  tests.
- **Render jobs** (`tools/render_jobs/jobs/`): look passes `crossing_look.json` and
  `bridge_tool.json` (probe `probes/crossing.gd`), `bridge_first_use.json` (the first-use
  cost split), P4b-3's judgment set over every biome `phase4b_judgment_set.json` and the
  re-anchoring check `p4b3_reanchor.json`, and `falls_tools.json` (the fall refusal). Phase
  4d: `p4d_probe.json` (P4d-0, the ford bar probe `probes/p4d.gd`: a bare gravel bar laid
  0.2 / 0.15 / 0.35 m under the surface, tokens on it, the rays; its verdict set
  `FORD_DEPTH_M`), `arch_look.json` (an arch over the waist river and a pier arch over the
  pond in the forest, zoom 8 and 6, grid, water hidden), `ford_look.json` (a ford over the
  waist river and the ankle stream, played with tokens wading them, grid, water hidden),
  `arch_ford_tools.json` (the four tiles, an arch held and placed, a ford refused on the deep
  river with the pill and the toast, a ford placed, Ctrl hover), the judgment set over every
  biome `phase4d_judgment_set.json` (verdict `VERDICT.md` beside its captures) and the pinned
  pass `p4d_perf_build.json` / `p4d_perf_play.json`. Captures and verdicts are indexed in
  [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Verification status"; the jobs are described in
  [../../tools/render_jobs/README.md](../../tools/render_jobs/README.md).
- **Performance** ([../PERFORMANCE.md](../PERFORMANCE.md)): "Phase 4b (crossings): pinned
  performance pass (2026-09-27)", with "Play: crossings shown and hidden in one run", and
  "Phase 4d (arch and ford): pinned performance pass (2026-10-04)" (crossings shown are
  0.05-0.13 ms cheaper than hidden at every view; six crossings add about 20 ms to a warm
  load and 7 MB of video memory; plans 3.1-3.5 ms for any kind; the rebuild cost by crossing
  count, 33.8 ms for a sixth placement, which decided the cache) with its subsection
  "Per-crossing rebuild cache (P4d-5b)" (9.8 ms for the same placement after; a Raise beside
  the arch rebuilt 3 of 6 in 18.7 ms against 32.3).

## Open work

The list is [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work"; this doc does not repeat it
(the generous downstream refusal zone, the ford's underwater read, the single-node swap cost
and crossings over a Blender map's own water are there).

## History

- P4b-1 (2026-09-27): the model, placement, geometry, node, collision, grid on the deck and
  the editor API.
- P4b-2 (c6d508f): the Bridge tool through real input, crossings following later edits, stone
  size 1.15 m, the first-use cost split.
- P4b-3 (a9cfff1, 77f899e, 12f9114): palette moss on stepping stones, light basalt, trees back
  from the landings, the judgment set, the re-anchor check, the pinned performance pass.
- P4c-5 (4673813, 2026-10-04): the refusal by a waterfall.
- P4d-0 (7a3c153, 2026-10-04): the ford bar probe (`probes/p4d.gd`, `jobs/p4d_probe.json`):
  `FORD_DEPTH_M` 0.15, the bar's own cues, the strip's winding.
- P4d-1 (9e6f092): the stone arch kind: `Crossing.Kind.ARCH`, `is_arch()`, `is_deck()`,
  the arch levels, `CrossingArch`, the paving material, `jobs/arch_look.json`.
- P4d-2 (475991e): the ford kind: `Crossing.Kind.FORD`, `is_ford()`, `FORD_DEPTH_M`,
  `REFUSED_DEEP` and `deep_at`, `CrossingFord`, the gravel material, `jobs/ford_look.json`.
- P4d-3 (ea48b4e): the Arch and Ford tiles, hints, F1 rows, the driver's `bridge_kind` for
  any kind, `jobs/arch_ford_tools.json`.
- P4d-4 (5e689d0, 052873f): the judgment set over every biome and its fixes: coping stones
  keyed for moss, the ford's crest profile and rounded landings, larger marker stones,
  voussoirs and graded spandrels, the cutwater pier, the sandstone gravel tint.
- P4d-5 (2a93d03): the pinned performance pass (`jobs/p4d_perf_build.json` /
  `p4d_perf_play.json`) and the cache decision.
- P4d-5b (68564cd): the per-crossing rebuild cache (`CrossingCache`).
- P4d-5c (fc0db95): `follow` refreshes the crossings whose ground changed when no anchor
  moved.
