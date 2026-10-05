# Waterfalls

A river drawn across a steep drop falls there by itself, a small drop stays a riffle, and there
is no control: that is the authoring bar, and the rule that decides it is made in two places
that agree by construction, at plan time from the ground profile under the stroke and at runtime
from the bodies' levels and the ground as it is. Nothing about a fall is persisted; the curtain,
the plunge pool, the wet rock, the flow and the crossing refusal all derive from `WaterFalls`
on every peer. The visual bar is a painterly fall at tabletop zoom: a white roll at the brink, a
curtain of streaks that fall with the water, glowing froth at the foot and one soft cloud of mist
hugging the pool; a thin hillside stream reads as a white ribbon, never as glass, and the rock it
falls over reads wet from the lip to the pool.

The water it belongs to is [water.md](water.md); the bridge refusal is in
[crossings.md](crossings.md). The Water tool's ribbon (an uphill stroke reversed as it is drawn,
`WaterBrush.flow_line`) is in [../UI_SYSTEMS.md](../UI_SYSTEMS.md) (authoring drawer, Water).

## Map

| File | Class | Role |
|------|-------|------|
| `utils/water_falls.gd` | `WaterFalls` | Pure: the rule and the runtime derivation: `is_drop`, `is_fall`, `falls`, `drops`, `fall_flags`, `footprint`, `footprint_of`, `face_foot`, `on_face`, `pool_point`, `steepest_within`, `fall_target`, `fall_spacing`, `face_search`, `plunge_length`, `plunge_depth`; `FALL_MIN_DROP_M`, `FALL_FACE_SLOPE`, the `PLUNGE_*` depth and length constants |
| `utils/water_fall_plan.gd` | `WaterFallPlan` | Pure: the plan-time half: `is_uphill`, `orient`, `fine_profile`, `drop_runs`, `plan_lips`, `shape_line`; `FALL_SLOPE`, `SHOULDER_*`, `LIP_MARGIN_M`, `MERGE_M`, `SETBACK_REACHES`, `PLUNGE_WIDEN` |
| `utils/water_edit.gd` | `WaterEdit` | `plan_river` runs the plan half in order; `join_line` treats face points as dry and moves an end on the face to the pool |
| `utils/water_geometry.gd` | `WaterGeometry` | `reach_ranges(ground, max_drop, forced, free)`: lips as forced boundaries, face points free of the reach rule |
| `utils/water_carve.gd` | `WaterCarve` | `bed_line(..., falls)`, `step_shape(..., full)`, `fall_shape`, `fall_profile`, `fall_foot`, `fall_gorge`; `CREST_M`, `FALL_LIP_M`, `FALL_LIP_WIDTH_M`, `FALL_BANK_SLOPE`, `FALL_BANK_REACH_M` |
| `utils/water_fall_mesh.gd` | `WaterFallMesh` | Pure: every fall's curtain, foam ring and mist in one mesh: `crest_widths`, `trajectory`, `width_code`, `ring_radius`, `ring_centre`, `MESH_NAME`; the vertex contract is its header |
| `utils/water_mesh_builder.gd` | `WaterMeshBuilder` | `cascades()` skips a fall, `fall_cells()` tucks the lip cells, `build()`'s `"falls"` and `"falls_aabb"` keys |
| `scenes/terrain/authored_water.gd` | `AuthoredWater` | The `AuthoredWater-falls` instance, `fall_material()`, `warm_fall_material()`, `get_falls_instance()`, `FALLS_RENDER_PRIORITY` |
| `shaders/waterfall.gdshader` | | The curtain / ring / mist shader, branching on COLOR.g |
| `utils/water_glb_utils.gd` | `WaterGlbUtils` | `apply_water_settings()` forwards `FALL_SETTINGS_KEYS` onto the fall material |
| `utils/water_dressing.gd`, `utils/water_flow_baker.gd` | `WaterDressing`, `WaterFlowBaker` | The face footprint as channel and wet samples |
| `utils/crossing_placement.gd` | `CrossingPlacement` | `REFUSED_FALL`, `fall_near()` ([crossings.md](crossings.md)) |
| `utils/graphics_warmup.gd` | `GraphicsWarmup` | The `"falls"` warm-up sample from `warmup_falls_document()`; the shader in `COVERED_SHADERS` |

## Model

- **The rule (phase 4c, P4c-1, 2026-10-04; `WaterFalls` and `WaterFallPlan`,
  `utils/water_falls.gd` and `utils/water_fall_plan.gd`, pure):** a river drawn across a steep
  drop falls there by itself, a small drop stays a riffle, and there is no control. The decision
  is made in two places that agree by construction. At plan time (`WaterEdit.plan_river`) the
  ground along the resampled line is sampled every sample step (0.25 m: the "fine profile",
  `WaterFallPlan.fine_profile()`). A drop run (`WaterFallPlan.drop_runs()`) is a maximal run of
  steps falling at `WaterFallPlan.FALL_SLOPE` 0.5 or more (26.6 degrees, just above the
  steepest a riffle can be carved, `RIFFLE_SLOPE` 0.3 x 1.5 at its smoothstep peak), grown
  upstream over the rounded shoulder and downstream over the toe (while the step still falls
  at 0.05 per metre and keeps easing, at most `WaterFallPlan.SHOULDER_M` 1 m, so a tier's lip
  sits at the top edge and not 0.7 m down the shoulder), that loses `WaterFalls.FALL_MIN_DROP_M`
  0.75 m or more in all (about half a 5 ft tier, clear of `REACH_DROP_M`). Each run becomes n
  falls of about one tier each (`WaterFalls.fall_target()`, never under 1 m): n =
  clamp(round(total / target), 1, min(floor(usable / spacing), floor(total / 0.75))), so lips
  really are at least `WaterFalls.fall_spacing()` apart (4 m, or three half-widths); lip 0 is
  the brink, lip j where the profile first crosses top - j x total / n. A lip never lies within
  half a spacing of a free stroke end (a spring starts in its first pool; an end in other water,
  a confluence, gets no margin, so a tributary off a tier straight into a river still falls),
  within `WaterFallPlan.LIP_MARGIN_M` 1 m of either end, or off the map. Each lip is inserted
  as a control point and a forced reach boundary, and the points of its drop run are "free" of
  the reach rule (`WaterGeometry.reach_ranges(ground, max_drop, forced, free)`: a free point
  does not count toward its reach's span), so the reach below a lip takes in the whole face and
  the pool under it, and its level is that pool's lowest ground minus the freeboard: the carve
  takes the slope away. Every other segment changing ground (falling or rising) by more than
  `REACH_DROP_M` is subdivided, so no step that is not a fall reaches 0.75 m (a 0.6 m steep
  bump is two riffle steps). Orientation: a stroke whose last point stands 0.75 m or more
  above its first is reversed (`WaterFallPlan.is_uphill()`, `WaterFallPlan.orient()`), so water
  always runs downhill and falls face downstream; a flat or gently rising stroke keeps its
  drawn direction, and a hump inside a stroke is never a fall (a negative drop stays as it
  was). The order in `plan_river`: join (`join_line`), resample, ground (with the
  level-plus-freeboard override under existing water), orient, fine profile, lips
  (`WaterFallPlan.plan_lips`), shape (`WaterFallPlan.shape_line`: lips, foot and plunge points,
  subdivision), reach split. The plunge point is data, not carve: below each lip
  `WaterFallPlan.shape_line()` inserts a point of the channel's own width at the carved face's
  foot (`WaterCarve.fall_foot`) and a point `WaterFallPlan.PLUNGE_WIDEN` 1.35 wider half the
  plunge length past it (`WaterFalls.plunge_length()`: 1.5 m per metre of drop, clamped 1.5 to
  4 m), neither when the widened point would run into the next lip or the end; so the face
  keeps the stroke's width and only the pool below it widens (areas follow half-widths, so a
  widened carve outside the area would leave a dry hole under the level). On a diagonal tier
  crossing the lip is set back upstream until its cross-line stands clear (the set-back, under
  "The fall carve" in Authoring). A stroke with no drop run and no 2 m segment changing by more
  than `REACH_DROP_M` plans byte-identically to v0.1.29 (`test_water_falls.gd`). Measured: a
  61 m map with a 35 degree hillside 56 m long and a waist stroke down it gives 14 reaches and
  13 falls (caps 32 rivers, 64 bodies); a 7 m, 35 degree hill gives 2 falls of about 3.5 m,
  lips 5 m apart. Falls form only between reaches of one stroke; a tributary dropping off a
  tier into a river carries its own fall, its last reach the short stub at the main river's
  level, so the curtain lands in the main water, which is its plunge pool. A river drawn out
  of a pond over an edge falls by the same rule; an automatic pond spill is later work. Known
  edge (for the judgment set): noisy ground within 0.5 m of a cliff can leave the level step
  just under 0.75 m, so the runtime rule sees a riffle where the plan placed a fall.
- **Falls at runtime:** reaches joined end to end (the upper's last point is the lower's
  first, as `WaterMeshBuilder.cascades()` pairs them) are a drop when the upper level stands
  0.75 m or more over the lower (`is_drop()`, from the levels alone; `fall_flags(bodies)` gives
  the carve one byte per shared point, since the ground is not carved yet) and a fall when,
  besides, the ground along the lower course within `face_search()` of the joint (drop /
  `FALL_FACE_SLOPE` + 1 m + half-width + `RIVER_BANK_M`, since a set-back lip can sit a reach
  upstream of the tier edge) has a stretch at `FALL_FACE_SLOPE` or steeper (tan 44 degrees,
  `TerrainRules.CLIFF_START_DEG`, the cliff rule's start, so every fall face reads as rock;
  `is_fall()`). New carves pass both; on a hill `is_fall` is false until the carve steepens the
  face; a v0.1.29 document gets a curtain only where its carved ground is cliff-steep and
  keeps its draped riffle sheet elsewhere, its stored flow bake used as it is. `falls(doc)`
  lists every fall ({upper_index, lower_index, lip, dir, half_width, top, bottom, face_run,
  plunge}; `face_run` is drop / `FALL_FACE_SLOPE`, not the carved foot: use
  `WaterCarve.fall_foot`) and `footprint(doc)` the face samples within the half-width of the
  lower course from the lip to `face_foot()` (where the centreline ground first reaches the
  lower level); the mesh, dressing, flow bake and crossings all derive from these. Nothing is
  persisted: falls derive from `water_bodies` (the inserted lip, foot and plunge points are
  ordinary points and half-widths) and the heights, so there is no `KNOWN_ENTRIES` change and
  no format bump, `map.ttmap` travels and is hashed as before, and every peer derives
  identical falls. Erasing a river (whole, `river_chain`) takes its falls with it; the ground
  keeps the lip notch, face and plunge basin as a dry rock step, which Smooth fills. A sculpt
  stroke by a fall re-evaluates `is_fall` on the new ground through the post-sculpt refresh:
  smoothing a face below the cliff slope turns the step back into a draped cascade (smoothing
  the face alone may leave the curtain until the pool edge is smoothed too, since
  `face_search` catches the brush's own shoulder); sculpting never creates a fall (the bodies
  do not change): to make a new cliff fall, erase the river and draw it again.

## Runtime

Phase 4c, P4c-3 and P4c-4, 2026-10-04: a step that is a fall (`WaterFalls.is_fall`) gets no
cascade sheet, because a height field cannot stand forward of a face; the curtain is separate
geometry with its own shader and one shared material.

- **Lip tuck:** `cascades()` skips the pair, and the flat cells straddling the lip line, which
  would stick one sample out over the face at the upper level, become sheet cells whose dry
  samples within `LIP_TUCK_SAMPLES` 1.5 samples downstream of the lip line sink
  `CASCADE_TUCK_M` 5 cm under the ground (`fall_cells()`; the curtain's lip roll hides the
  tucked quad).
- **Curtain, foam ring and mist geometry:** `WaterFallMesh` (`utils/water_fall_mesh.gd`, pure)
  builds every fall's curtain, foam ring and mist into one mesh at the map origin
  (`WaterMeshBuilder.build()`'s `"falls"` and `"falls_aabb"` keys, on the same refresh worker
  and covered on load by `AuthoredLoadPrep`'s WATER part). Layout, in brief: one ribbon per
  fall across the wetted width at the crest (`crest_widths()`: the ground read outward along
  the lip line every 5 cm until it stands at the upper level, each side its own; a dry,
  uncarved crest takes half the half-width), a column every 0.2 m and shared rows at 0, 0.03,
  0.06 and 0.09 m of fall, then every 0.12 m, plus the pool level and 3 cm below it (a strip
  the foam ring covers). Each column (`trajectory()`) runs level over the brink for
  `LIP_ROLL_M` 0.3 m, then falls ballistically with a horizontal speed of 0.8 + 0.6 x the
  river's speed, floored `FALL_CLEARANCE_M` 8 cm in front of the higher of the carved face
  (`WaterCarve.fall_shape` along the lower course) and the document's ground under it, so it
  hugs a curved face and never cuts rock, and never rises above the upper level; it meets the
  lower level about 1.1-1.7 m from the lip, before the carved foot. The foam ring is a flat
  disc of 64 rim vertices and a centre, `RING_WIDTH_FACTOR` 1.1 x the crest width across (at
  1.4 the disc stood over a waist river's banks), `RING_LIFT_M` 1 cm over the pool (the shader
  adds only the bob), centred where the middle column meets the pool plus `RING_FORWARD` 0.3
  radii downstream. The mist is 3 to 5 packed billboard quads (all four vertices at the
  centre, the corner offset in UV2), half-size 0.35 to 1.2 m by width and drop, placed by a
  golden-ratio sequence (no RNG, so every peer and every rebuild gets the same mesh) over the
  lowest third of the face and the pool, plus one high puff on falls of 1.2 m or more whose
  top clears the brink (the cue an away-facing fall keeps); the mesh's `custom_aabb` grows by
  the largest puff x 1.3 + 0.9 m for the shader's rise and growth. The vertex contract (UV,
  UV2, COLOR.r edge fade, COLOR.g kind 0 curtain / 0.5 ring / 1 mist, COLOR.b puff seed,
  outward normals, clockwise from the front) is the class header.
- **Node:** `AuthoredWater-falls` (`WaterFallMesh.MESH_NAME`), a sibling `MeshInstance3D`
  whose name deliberately does not end in `-water`, so `WaterGlbUtils.process_water_meshes()`
  leaves it alone; no shadow, no collision (a token dropped on it lands by the downward ray on
  the face, the lip pool or the plunge pool, as on a Tier face: P4c-0 probe e found Jolt
  treats carved 63-75 degree faces and the tier profile alike), `BOUNDS_EXEMPT_META`; built
  in `refresh_work`, swapped in by `apply()`, `get_falls_instance()`.
- **Shader** (`shaders/waterfall.gdshader`: `blend_mix`, `depth_draw_opaque`,
  `cull_disabled`, no screen texture) branches on COLOR.g. Curtain: aeration from a solid
  white roll over the first 0.6 m of fall, whitening over the lowest 35 %, a base air share of
  0.25 plus air entrained on the way down, and streaks of gradient noise sampled in (across,
  fall time) space, t_fall = sqrt(2 v / g), scrolled by the clock, so a feature falls with the
  water, accelerating and lengthening; translucent glass between the streaks (the shore and
  water tints lifted 30 % toward the foam, alpha `glass_alpha` 0.6 up to the foam colour's),
  ragged side edges eating into COLOR.r, alpha fading to nothing over the 0.1 m above the pool
  level (UV2.y against the world height), the streaks' analytic derivative tilting the normal,
  roughness 0.45 on the glass to 0.85 on the foam, and `foam_glow` emission 0.18 (the tier
  face shadows itself and the froth read grey without it). P4c-6b/6c (commits 6f7f810,
  3d7c80e): the lip is scalloped (`lip_run`, `LIP_SCALLOP_*`), the sides and bottom torn
  (`EDGE_BITE` 0.5, `BOTTOM_TAPER` 0.2, `BOTTOM_TEAR_M` 0.3), the foam glows through
  `foam_glow_color()` with `FOAM_SHADOW_TINT`, the ring's arcs follow a bounded two-phase flow
  map, the mist is one soft-rimmed cloud hugging the pool (`MIST_RISE_MAX_M` 0.6), and the
  mesh writes the wetted crest width into the curtain's COLOR.a (`WaterFallMesh.width_code`,
  width / 8) so the shader blends narrow falls (1 - smoothstep(`NARROW_WIDTH_M` 1.2,
  `WIDE_WIDTH_M` 3.0, width)) toward `NARROW_BASE_AIR` 0.55, an alpha floor and a shallower
  bite, so a thin hillside stream reads as a white ribbon, not glass. No `FRONT_FACING` flip:
  Godot already flips a `cull_disabled` back face's normal before `fragment()` (probe d), so
  an away-facing fall is lit from the viewer's side like a facing one; a flip inverts it.
  Ring: polar churn advected outward from the foot (0.3 radii upstream of the centre), density
  1 there to 0 by 0.9 radii, a slow pulse, riding the water shader's exact bob. Mist: a vertex
  billboard from UV2 (the probe c form), each puff rising 0.9 m and growing 1.3 x over a 4 s
  cycle at its own phase (COLOR.b), soft noise puffs at `mist_alpha` 0.35, faded where the
  scene is within 0.25 m behind them (`hint_depth_texture`; a second depth-reading material
  adds nothing measurable while the water is present, probe c), and discarded at Water
  Quality Low (`water_quality_skip_fine_detail`, which also drops the fine noise octave of
  the streaks and the churn).
- **The fall material and its uniforms:** `water_color`, `shore_color`, `foam_color`,
  `wave_speed`, `bob_height`, `flow_strength` and `foam_strength` are declared under exactly
  `water.gdshader`'s names, and `WaterGlbUtils.apply_water_settings()` forwards them
  (`FALL_SETTINGS_KEYS`) onto the one shared material, `AuthoredWater.fall_material()` (made
  on first use, so a level load restyles the falls), so a palette or motion tile restyles
  falls live and over the network with no new LevelData field. The material is shared and
  static: tools never set per-instance parameters on it.
- **Ordering:** `FALLS_RENDER_PRIORITY` 1, between the water material (0) and the
  `SubmergedMarker` (2) and `GridOverlay` (10). P4c-0 probe (a) found that at an equal
  priority the water (alpha 1, `depth_draw_opaque`) does not merely sort unreliably against
  the curtain: it erases it entirely, above the water line too; at priority 1 the curtain
  shows above the surface and, blended over it, below, so the 3 cm overlap under the pool
  level is a strip about 2 px tall under the foam ring, and `render_priority` is the primary
  sort key between separate instances. The curtain is never in `hint_screen_texture` (the
  opaque pass only, probe b), so the pool's refraction cannot double it and the falls shader
  needs no screen copy. The grid draws cells over the curtain wherever the ground behind it is
  within the grid's tolerance (the curtain is not in the depth buffer; the plunge pool, raised
  to the water, qualifies); accepted, since most of a 0.75 m or higher curtain stands in front
  of the steep face where the grid already fades.
- **Dressing and flow bake footprint:** the face samples `WaterFalls.footprint()` (within the
  half-width of the lower course from the lip to `face_foot()`) are channel samples in
  `WaterDressing.field_of` (bed weight 1, wet line 1; the cliff rule still wins on the face
  itself through `TerrainRules.compose_water`, so the rock reads wet from the lip to the pool)
  and count as wet in `WaterFlowBaker`, so the bank fade does not cut the flow at the lip and
  the pool above runs into the pool below; the curtain itself never reads the flow map.
- **Warm-up coverage:** the Water tool warms the material as it is selected
  (`AuthoredWater.warm_fall_material()` from `AuthoringController`, as the Bridge tool warms
  the crossing materials, since a first RID costs about 15 ms), the shader is in
  `GraphicsWarmup.COVERED_SHADERS`, and the first-launch warm-up draws a second "falls"
  sample (`warmup_samples()`) built from `warmup_falls_document()`: a 20 x 20 map with a tier
  one tier high across it and a waist river planned and carved down it as the Water tool
  would, so the sample carries the real vertex layout. Measured (150 ft map, 9 bodies, 4
  falls): the second river's water build 158 ms, bake 157 ms, swap 18 ms; four falls shown
  against hidden at zoom 8, GPU deltas 0.05-0.2 ms, inside drift (indicative; the pinned pass
  is `PERFORMANCE.md`).
- **The `level_at` leak past the lip:** `WaterGeometry.level_at` has no flush cut at a reach's
  end, so within the half-width plus the bank of a lip the face reads the upper pool's level
  and `is_wet_at` is true on the rock. Two workarounds (P4c-5): `CrossingPlacement` refuses a
  line across the face as `fall` instead of letting it pass as a crossing of water, and
  `WaterEdit.join_line` treats face points as dry (`WaterFalls.on_face`: within the half-width
  of the lower course from the lip to `WaterCarve.fall_foot`) and moves a dry end on the face
  to the plunge pool `JOIN_INSET_M` past the carved foot (`WaterFalls.pool_point`), so a
  tributary drawn into a fall ends in its pool, not on the rock. If other tools start reading
  the face as wet, a flush cut in `level_at` is the real fix.

## Authoring

There is no fall tool: the Water tool's River stroke plans its own lips (`WaterEdit.plan_river`,
Model above) and the carve below shapes the face. Erasing the river takes its falls with it, a
sculpt stroke by a fall re-evaluates `is_fall` on the new ground, and sculpting never creates one
("Falls at runtime", above).

- **The fall carve (phase 4c, P4c-2 and P4c-2b, 2026-10-04):** a step `WaterFalls.fall_flags()`
  marks (the upper reach 0.75 m or more over the lower, the drop test alone: the ground is not
  carved yet) is carved as a waterfall, not a riffle (`bed_line(..., falls)`, one byte per
  shared point, passed through `WaterEditor.compute`). The pool tail still rises to the full
  crest (`CREST_M` 5 cm under the upper level whatever the depth: `step_shape(..., full)`
  skips the small-step `CREST_RISE_PER_DROP` rule, so a fall is never a low bar), and below
  the lip the bed follows `fall_shape(x, upper, lower, depth)`: bed = max(crest -
  `fall_profile`(x, rise), plunge bed + basin). `fall_profile` is the tier profile upside down
  (`HeightBrush.soft_tier_offset` with a harder lip, `FALL_LIP_M` 0.1 over `FALL_LIP_WIDTH_M`
  0.25 against a tier's 0.25 over 0.5, the tier face angle `TIER_FACE_DEG` 74 and the same
  `TIER_SOFTEN_M` tent, so the face reads as rock at the default spacing and does not saw on a
  diagonal: 74 degrees in the middle of a long face, 66 after the tent on a short one); it runs
  from the crest down to the plunge bed, `WaterFalls.plunge_depth()` (0.3 per metre of drop,
  clamped 0.2 to 0.9 m) under the lower bed. The plunge pool is deepest at the face's foot,
  `fall_foot(drop, depth)` = `fall_run`(drop + `CREST_M` + depth + plunge depth) along the
  lower course from the lip (about 2.0 m for a tier-high waist fall, 2.5 m for a 3.4 m ankle
  fall), and shallows back to the bed over `plunge_length()`; the end taper carries a plunge
  pool past its lift (`bed_line` scales it with the depth left) instead of filling it in. The
  bank level follows the same profile a crest's height above the bed and is clamped at the
  lower level, so the face runs straight across the whole cut and under the lower level runs
  on down to the plunge bed through the channel's steepened shore (the plan's bank stepping
  over the face run alone made `section()` shelve the channel into a V; dropped). Side walls
  (P4c-2b): the first hillside render swept the face sideways at the ordinary bank slope out
  to `BANK_REACH_M`, a rock wall about 8 m wide for a 1.1 m stream; now across the face
  stretch the bank rises at `FALL_BANK_SLOPE` 1.4 (54 degrees, rock by the cliff rule, where
  the ordinary banks are 18 to 31) and is cut no further out than `FALL_BANK_REACH_M` 4 m
  (the fade before it still `BANK_FADE_M`), blended by `gorge` = `fall_gorge(x, drop, depth)`:
  1 from the lip to the foot, fading to 0 over the plunge length with the basin, so the rock
  bowl at the foot opens into the pool's ordinary banks, and above the lip rising with the
  pool tail. `bed_line` returns Vector3(bank, bed, gorge), and `section()` and
  `blend_with_ground()` take `gorge` (default 0: a riffle's banks are byte-identical to
  before). Measured on the hillside notch: rock outside the water under one channel width per
  side, two tight notches on the flank and no dome; the tier chute unchanged. Over a Tier
  cliff the lip stands at the brink (`WaterFallPlan.plan_lips`), the profile lies along the
  tier's own face and the carve cuts a notch `CREST_M` under the upper pool across the
  channel, the face itself a hand's breadth deeper, then the plunge pool at its foot; outside
  the channel and its banks the face is left as it was (test: under 5 cm of change outside the
  notch). Reading as rock: the face is steeper than the cliff rule's 44 degrees, so
  `TerrainRules.compose_water` gives it full rock over the bed, and the wet line darkens and
  glosses it; the lip top under 5 cm of water stays bed. The diagonal lip set-back
  (`WaterFallPlan._setback`, at plan time): a lip planned on a diagonal tier crossing slides
  upstream, at most `WaterFallPlan.SETBACK_REACHES` 3 reaches (half-width plus bank) and never
  past the lip margins, to the first arc whose whole cross-line square to the flow (the
  half-width plus the bank either side, every sample step) stands on ground at or above the
  level a reach ending there would take, so the notch is cut square to the flow and no
  upper-level water hangs past a diagonal brink (the P4-3 artifact of cutting the upper area
  square to the river rather than along the tier edge); a cross-line that can never stand
  clear within reach, as on a hill flank, leaves the lip at the brink. Carving still only
  lowers (`min(start, goal)`): lip heights come from the existing ground (a pool's level is
  its reach's lowest ground minus the freeboard, and the lip is that lowest point), over a
  tier the face is already there, on a natural slope the face comes from lowering everything
  below the lip down to the lower pool, and gentle ground, where a proud ledge would need
  raising, stays a riffle by the rule. Known edges: `section()`'s `MAX_SHORE_SLOPE` caps how
  much of the plunge depth a narrow channel's centreline reaches (ankle, half-width 0.55:
  about 0.5 m of the planned 0.9; left as is); the crease where a face emerges from a natural
  slope is grid-sampled and zigzags 0.10-0.14 m at 10-60 degrees off the axes (not seen on
  screen at the rendered angles). A second river drawn across a fall's face carves its own
  channel through it by the ordinary rules.
- **Crossings:** a bridge or stepping-stone line within 1 m of a fall's face or foam ring is
  refused (`CrossingPlacement.REFUSED_FALL`, P4c-5); the rule and its zone are in
  [crossings.md](crossings.md) (Model, "Falls").

## Verification

- **Unit tests** (`tests/unit/`): `test_water_falls.gd` (the rule and the plan; a stroke with
  no drop run plans byte-identically to v0.1.29), `test_water_carve.gd` (the profile, the
  walls, rock across the hillside channel, a notch not a quarry, the plunge depth, a tier face
  changed only in the notch, no saw), `test_water_tool.gd` (a fall stroke lands the same from
  the worker and undoes exactly), `test_water_fall_mesh.gd` (the curtain, ring and mist
  geometry), `test_authored_water.gd` (the lip tuck and the falls instance),
  `test_glb_utils_water.gd` (every forwarded key is a uniform; a palette change reaches the
  fall material), `test_graphics_warmup.gd` (the falls sample), `test_crossings.gd` (a
  crossing keeps clear of a waterfall, and is allowed 2 m upstream), `test_bridge_tool.gd` (a
  river falling under a bridge removes it in the carve's entry); shared ground builders in
  `water_fixtures.gd`.
- **Render jobs** (`tools/render_jobs/jobs/`): look pass `falls_look.json` (probe
  `probes/falls.gd`: `falls`, `look`, `falls_visible`, `quality`, `clock`, `palette`),
  `falls_tools.json` (the red refusal and its toast, the upstream bridge placed), and the
  judgment set `phase4c_judgment_set.json`; captures and verdicts are indexed in
  [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Verification status" (Waterfalls).
- **Performance** ([../PERFORMANCE.md](../PERFORMANCE.md)): the P4c-4 numbers above (build,
  bake, swap, the GPU delta of four falls) are indicative render-job readings; the pinned pass
  is "Phase 4c (waterfalls): pinned performance pass" there (`jobs/p4c_perf_build.json`,
  `jobs/p4c_perf_play.json`: the falls mesh costs at most 0.05 ms GPU at zoom 8, Low saves
  0.01-0.04 ms, six falls plus six extra reaches add about 170 ms to a warm load).

## Open work

The list is [../MAP_AUTHORING.md](../MAP_AUTHORING.md) "Open work"; this doc does not repeat it
(the automatic pond spill, a deck over the lip and the `level_at` flush cut are there or
decided against above).

## History

- P4c-0 (2026-10-04): probes a to e (render priority against the water, the screen texture,
  the mist billboard form, `FRONT_FACING`, Jolt on carved faces).
- P4c-1 (87c64c5): the fall-or-riffle rule and the river plan.
- P4c-2 (ea846eb), P4c-2b (7596f6f): the carve, fall profile and plunge pool; the tight rock
  notch on hillsides and the plunge widening in the pool.
- P4c-3 (a16365f): curtain, foam ring and mist geometry, the lip tuck, dressing and flow.
- P4c-4 (57cc538): the falls shader, warm-up and settings.
- P4c-5 (4673813): the tools and play: the crossing refusal, `join_line` on the face, the
  ribbon reversed for an uphill stroke.
- P4c-6 (c99d1ad), P4c-6b (6f7f810), P4c-6c (3d7c80e): the judgment set and its fixes; the
  scalloped lip, torn edges and cloud mist; width-scaled aeration, soft pool mist, white brink
  bar.
