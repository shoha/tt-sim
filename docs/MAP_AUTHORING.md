# In-game map authoring

A GM can build a battle map inside tt-sim: pick a size and a starting biome, then paint
biomes, thin and clear, and place hero props, seeing the map exactly as players will.
Blender (terrain-paint + treecube + Geoscatter) stays a first-class path; the in-game
tools add to it, and can also dress a Blender map.

The bar, from the suite `CLAUDE.md`: intuitive and accessible tools for beautiful and
expressive maps. A newcomer gets something beautiful from the first few strokes; an
experienced author never hits a ceiling. The reference for in-game simplicity is Tiny
Glade: direct gestures instead of forms, a world that responds with its own detail.

This file is the hub. Detailed behaviour lives in the docs linked from the table below;
this file keeps the decisions, the verification status and the open work, which have no
other committed home.

## Decisions (with the user, 2026-09-26)

- **Map size:** tabletop battle maps, 100 x 100 ft typical, 200 x 200 ft maximum (about
  30 m and 61 m). New maps are 20, 30 or 40 cells of 5 ft, centred on the origin so the
  grid aligns by construction.
- **Who and when:** host/GM only, offline only, in a separate authoring state. No editing
  during play, so no live edit sync. A session receives a finished, saved map.
- **Same version to join:** peers must run exactly the host's game version
  (`VersionGate`, checked from Steam lobby data before connecting and again by the host).
  This is what keeps the built-in palette identical across peers.
- **Palette storage:** the built-in treecube palette (~80 MB) is in Git LFS; CI restores
  LFS objects from the Actions cache (GitHub Free LFS bandwidth is 10 GiB a month and runs
  out otherwise). See `.gitattributes` and `.github/workflows/build.yml`.
- **Height tiers are wanted** (phase 3): terracing that snaps to whole tiers so elevation
  reads for play.
- **Dependencies:** a GDExtension would be acceptable, but none is needed: a 200 ft
  heightfield rebuilds a 10 m chunk in under 1 ms in GDScript.
- **Plants ship baked:** a saved map stores placed instances, not rules, so every peer
  loads exactly what the author saw. The painted masks are kept only for re-editing.
- **Visual reference (2026-10-04):** painterly, Studio Ghibli; bright, lively and
  beautiful. Effects (water, falls, spray, weather) are a few bold soft-edged shapes in
  luminous colour, never fine grey noise. Given during the waterfall look pass; applies to
  everything after it. The suite `CLAUDE.md` carries the same rule.
- **No sameness (2026-10-04, phase 5):** having everything appear in every map is
  distracting; each space should feel unique and beautiful. Not everywhere has a river,
  not every river has a crossing. A starting landform is a shape plus a small palette of
  features the seed draws from, and every draw must stand on its own (judged with the
  water off as well as on). The suite `CLAUDE.md` carries the same rule for every
  generator.

## Where each system is documented

| System | Code | Documented in |
|--------|------|---------------|
| Built-in palette (treecube -> tt-sim contract, import path) | `utils/palette_library.gd`, `assets/palette/` | `ASSET_PIPELINE.md` section 9 |
| Palette build (producer side) | `treecube/scripts/build_palette.py`, `treecube/treecube/palette.py` | treecube `README.md` "Palette for tt-sim" |
| Map document `map.ttmap` (format, caps, atomic write) | `resources/map_document.gd`, `utils/map_document_io.gd` | `ARCHITECTURE.md` "Map document (map.ttmap)" |
| Scatter generator (Matern III spacing, clumps, relations, density response) | `utils/scatter_generator.gd`, `utils/scatter_plan.gd` | `ARCHITECTURE.md` "Scatter generator" |
| Incremental scatter (per-cell rebuilds, worker regeneration, grow-in, shrink-out) | `utils/authored_scatter.gd`, `utils/scatter_regen.gd`, `utils/scatter_shrink.gd` | `ARCHITECTURE.md` "Authored scatter", `PERFORMANCE.md` |
| Terrain and ground (chunks, collision, mosaic anti-tiling, biome ground, broad edge, skirt) | `scenes/terrain/authored_terrain.gd`, `utils/terrain_mesh_builder.gd`, `utils/biome_ground_layers.gd`, `shaders/authored_ground*.gdshader*` | `ARCHITECTURE.md` "Authored terrain" |
| Loading and networking (glb / ttmap / both, erase filter, map hashes) | `scenes/states/playing/level_loader.gd`, `MapSourceLoader`, `utils/map_file_hash.gd` | `ARCHITECTURE.md` Map Loading Flow, `NETWORKING.md` |
| Authoring state (controller, session, save, autosave, new map) | `scenes/states/authoring/`, `utils/new_map.gd` | `ARCHITECTURE.md` "Authoring Flow", `UI_SYSTEMS.md` authoring drawer |
| Brushes, gestures, undo | `scenes/states/authoring/brush_tool.gd`, `authoring_editor.gd`, `authoring_history.gd`, `utils/mask_brush.gd`, `utils/mask_stroke.gd`, `utils/base_scatter_eraser.gd` | `UI_SYSTEMS.md` "Brushes and gestures", `ARCHITECTURE.md` "Authoring Flow" (Brushes) |
| Water model and flow bake (bodies, levels, wet samples, pond mask, the flow map) | `resources/water_body.gd`, `utils/water_geometry.gd`, `utils/water_flow_baker.gd`, `utils/map_water_io.gd` | `systems/water.md` (Model), `ARCHITECTURE.md` "Map document (map.ttmap)" |
| Water at runtime (merged surface, zones, water as ground, float rule, grid on the water, the water shader) | `utils/water_mesh_builder.gd`, `scenes/terrain/authored_water.gd`, `utils/water_surface.gd`, `scenes/effects/water_zone.gd`, `utils/water_glb_utils.gd`, `shaders/water.gdshader` | `systems/water.md` (Runtime) |
| Carving and wet dressing (channel and basin profiles, reach steps and riffles, confluences, erase, bed and shore surfaces, plants, rocks, the worker) | `utils/water_carve.gd`, `utils/water_edit.gd`, `utils/water_dressing.gd`, `scenes/states/authoring/water_editor.gd` | `systems/water.md` (Authoring) |
| Waterfalls (the fall-or-riffle rule, lips and plunge points in the plan, the fall profile and gorge walls in the carve, the curtain / foam ring / mist mesh and shader, the shared fall material, the crossing refusal) | `utils/water_falls.gd`, `utils/water_fall_plan.gd`, `utils/water_fall_mesh.gd`, `shaders/waterfall.gdshader`, and the fall parts of `water_edit.gd`, `water_geometry.gd`, `water_carve.gd`, `water_mesh_builder.gd`, `authored_water.gd`, `water_glb_utils.gd`, `crossing_placement.gd` | `systems/waterfalls.md` |
| Water tool (River and Pond tiles, depth tiles, ribbon preview, Ctrl erase) | `scenes/states/authoring/water_brush.gd`, `water_tool_pane.gd`, `brush_tool.gd` | `UI_SYSTEMS.md` authoring drawer (Water) and "Brushes and gestures" |
| Crossings (plank bridges, stepping stones, stone arches, fords: model, snapping to banks, geometry, collision, grid on the deck, editor API, following later edits, the per-crossing rebuild cache) | `resources/crossing.gd`, `utils/crossing_placement.gd`, `utils/crossing_geometry.gd`, `utils/crossing_arch.gd`, `utils/crossing_ford.gd`, `utils/crossing_cache.gd`, `utils/map_crossing_io.gd`, `scenes/terrain/authored_crossings.gd`, `scenes/states/authoring/crossing_editor.gd` | `systems/crossings.md`, `ARCHITECTURE.md` "Map document (map.ttmap)" |
| Bridge tool (Planks, Stones, Arch and Ford tiles, live preview, refusal hint, Ctrl erase) | `scenes/states/authoring/bridge_brush.gd`, `bridge_tool_pane.gd`, `brush_tool.gd` | `UI_SYSTEMS.md` authoring drawer (Bridge) and "Brushes and gestures" |
| Starting landforms (Valley, Hilltop, Terraces, Lakeshore, Gorge: the seeded frame, the shared steps, each recipe's shape and feature chances, the stage, the open path, the dialog's Landform row) | `utils/starting_landform.gd`, `utils/landform_recipes.gd`, `utils/landform_hilltop.gd`, `utils/landform_terraces.gd`, `utils/landform_lakeshore.gd`, `utils/landform_gorge.gd`, `utils/new_map.gd`, `scenes/states/authoring/new_map_dialog.gd` | `systems/landforms.md`, `UI_SYSTEMS.md` "New map dialog" |
| Submerged token marker (the ring on the water over a hidden token, drag preview) | `scenes/board_token/submerged_marker.gd`, `shaders/submerged_marker.gdshader`, `utils/water_surface.gd` | `UI_SYSTEMS.md` "Submerged Token Marker" |
| Authored map load on workers (dressing, water geometry, rule fields, chunk and skirt arrays, crossings) | `utils/authored_load_prep.gd`, `MapSourceLoader` | `ARCHITECTURE.md` Map Loading Flow, `PERFORMANCE.md` "P4b-0: authored map load on workers" |
| First-use pipeline warm-up | `utils/pipeline_warmer.gd` | `PERFORMANCE.md` |
| Same-version join gate | `utils/version_gate.gd` | `NETWORKING.md` "Same-version gate" |
| Render-job harness (1920x1080 judgment renders) | `tools/render_jobs/` | `tools/render_jobs/README.md` |

## Verification status

Verified in the running game (host, validation bridge and render jobs): new-map flow for
all eight palette biomes, save / reload / Edit map, autosave recovery, the three brushes
on a bare 200 ft map, dressing Blender maps (River, Deciduous clusters: live erase of
their scatter matches what a player's load builds), play-time loading of GLB-only,
ttmap-only and dressed levels with exact instance counts.

Dressed-map ground (phase 3 P3-0, render jobs on Deciduous clusters, 2026-09-26): before
the fix a Biome stroke over its dip generated every row at Y = 0 while the GLB ground lay
up to 1.18 m lower (1,343 rows, mean |dY| 0.98 m). Dressed documents now sample the GLB
collision into their heights on open (`ARCHITECTURE.md` "Dressing ground"); the same stroke
gives mean |dY| 0.001 m, worst 0.018 m (bilinear heights against the collision triangles),
and normal-aligned rows sit 3.8 deg from the ground normal (their random lean) instead of
7.2. A flat-0 document saved before the fix reopened with 1,607 rows settled onto the
ground and the session unsaved. Unit-tested against a synthetic ramp and step.

Water (phase 4) verified in the running game (render jobs `water_look`, `water_tool`,
`phase4_judgment_set`, 2026-09-27): rivers drawn at human speed with the Water tool carve,
split into reaches with riffles, join each other at confluences and flow the drawn way;
ponds paint, extend and settle; Ctrl erases whole rivers and pond area with undo / redo;
wet dressing (beds, shores, moss on forest banks, reeds in the wetland) and plants yield to
the water; paths stop at the bank and resume across; the grid lies on the water surface on
authored and Blender maps; saved levels play with tokens wading on the bed (ankle, waist)
and floating in deep water, in four biomes and on the Blender `river` level. Unit-tested
only: the flow bake's frame against the shader's decode, `splines.json` / `ponds.png` /
`water_flow.png` round trips and caps, the worker carve's equality with the synchronous one,
and water on a dressed map beyond erasing (the render jobs never dress a map with water).

Phase 4 follow-ups (P4b-0, 2026-09-27, render job `p4b_badlands`, before and after in
`user://render_jobs/p4b_badlands_before` / `_after`): the faint straight line by a boulder in
a deep pool was the water shader's rock foam tracing the boulder's submerged flank against
the bed (gone with edge foam off in the same frame; now limited to where the rock comes
within a few centimetres of the surface, `EDGE_FOAM_REACH`); a painted path now runs into the
shallows and fades under the water (`PAINT_FORD_*`) instead of yielding a few centimetres
above the waterline, which on the badlands gravel bank read as a gap. The near bank of a
crossing still ends at the bank's lip on screen: the camera cannot see that bank's
underwater slope, so the Paint brush (and the author) cannot paint it either. Small tokens
the water hides (standing on the bed, less than 10 cm or a fifth of their height out) now show
a ring on the surface above them (`SubmergedMarker`, UI_SYSTEMS.md "Submerged Token Marker"):
render job `p4b_cue` (captures in `user://render_jobs/p4b_cue`) shows it on wading tokens at
home, zoom 10 and max play zoom, none on floating or ankle-deep tokens, following a held drag
to its landing, gone when the token is carried onto the bank, and on the Blender `river` level;
the rule and the marker are unit-tested (`test_submerged_cue.gd`).

Crossings (P4b-1, 2026-09-27, render job `crossing_look`, captures in
`user://render_jobs/crossing_look`): a plank bridge and a line of stepping stones placed
through the crossing API (no Bridge tool yet, P4b-2) over a waist-deep river in temperate
forest and rocky badlands, each snapped from a short line on the water to both banks; in
authoring and after a save and play load, tokens stand on the deck (at its arch, 0.49 m, and
at its bank end) and on the stones (dry, no submerged cue), a token wades beside the bridge,
the drag resolver lands on the deck, and the grid runs across the deck and the stones and
stays continuous on the water up to the deck's edge. Badlands takes sun-bleached planks and
sandstone stones, the forest warm planks and grey rock. Unit-tested: the document entry
(round trip, caps, refusals, malformed input), the snapping rule and its refusals, the
geometry (arch, stride, winding, collision, determinism), tokens landing and brush rays
seeing the bed in physics, the grid's deck texture, the scatter clearance, the load's worker
part and the editor's undo / redo. Not rendered: a crossing on a dressed Blender map (its
water plane is not a crossing target; only document water is). The long bridge with pile
bents and the other six biomes' styles were rendered in P4b-3 (below).

Bridge tool (P4b-2, 2026-09-27, render job `bridge_tool`, captures in
`user://render_jobs/bridge_tool`): driven through real input events (mouse motion, press,
release, Ctrl key) on a 150 ft temperate forest map with a waist-deep river: the pane; a
plank line previewed from the bank (the ghost appears as the line nears the water) and on
the far bank, then placed; a line on dry ground drawn red with "No water to cross here..."
beside the cursor and the same toast on release; stepping stones previewed and placed; Ctrl
hover outlining the bridge red ("Remove plank bridge"), Ctrl+click removing it and undo
bringing it back; a Raise stroke on the far bank re-anchoring the bridge (same id; end 0.2 ->
0.5 m, span 4.85 -> 4.74 m); a Tier stroke filling the river under the stones removing them
with the toast, and one undo bringing ground, water and stones back. Unit-tested
(`test_bridge_tool.gd`): the gesture and its refusals, BrushTool's Bridge mode, the follow
rule (unchanged, re-anchored, removed by an erase and by a sculpt, untouched by a far edit;
undo / redo in the causing entry), the courses cut near a walk answering the same, the
warm-up surfaces, the moss tint. Placement cost (render job `bridge_first_use`, not pinned): a
plan (the preview per pointer move) 9.2 -> 1.8-2.3 ms; a first placement 28 -> 6.6-9 ms
(the first-use material and shader, 17 ms, now warmed when the tool opens); later
placements 7-9 ms, release frames under 12 ms.

Phase 4b judgment (P4b-3, 2026-09-27, render job `phase4b_judgment_set`, captures and
`VERDICT.md` in `user://render_jobs/phase4b_judgment_set`, the run before the fixes in
`phase4b_judgment_set_before`): in every one of the eight palette biomes a plank bridge placed
with the real Bridge tool where a path in the biome's first path surface meets a waist-deep
river, stepping stones downstream and a 7.2 m bridge over a deep pond (pile bents), in
authoring and in play with tokens on both decks and on the stones, a wading token with its
submerged ring beside the bridge, grid on. Every biome's crossings snap to both banks, carry
tokens and the grid, and take their biome's wood tint and rock. Fixed from the verdict: the
stones' moss is now the palette's moss surface on up-facing facets in patches (was a
vertex-colour tint that read dull olive beside the palette's mossy boulders); the cold biomes'
basalt stones are lifted to the boulders' light grey (they read as black holes in the water);
trees keep 1.2 m and shrubs and rocks 0.6 m further back from a crossing, so no trunk or bush
stands on a landing (this does not stop a tall canopy well in front of a bridge from covering
it from the fixed camera: open work below); the Bridge tool's drawn line has a solid keyline
and a heavier refused line. The phase 4 wetland rebuilt and re-rendered: no foam
outlines on the reeds standing in the river (P4b-0's rock-foam change holds). Re-anchoring on a
gentle underwater bank: render job `p4b3_reanchor` (findings in `VERDICT.md`).

Waterfalls (phase 4c, P4c-1 to P4c-5, 2026-10-04, render jobs `falls_look` and `falls_tools`,
captures in `user://render_jobs/falls_look` / `falls_tools`): on a 150 ft temperate forest map
a waist river over a two-tier step facing the camera, an ankle stream down a Raise hill's flank
(two hillside falls) and a second waist river off the step's far edge, facing away.
`falls_look` (15 captures, about 94 s) shows the carved ground with the water hidden (rock to
the brink, a concave chute into a small rock bowl, a gravel bed, no saw, no upper water
hanging past the brink; on the hill flank two tight notches, no dome) and with it shown (the
curtain from the brink to the pool without cutting rock, no draped sheet, no lip quad; a
white roll at the lip, darker streak bands, the bottom melting into the churn; the foam ring
densest at the foot and inside the river; faint mist at the foot and one puff over the
brink; the away-facing fall's white roll over its brink, with normal lighting on the
curtain's back), two frames about 0.25 s apart with the shader clock frozen (the streaks move
down, further near the pool than near the lip), Water Quality Low (no mist, one noise
octave) and the Swamp palette recolouring the falls with the pool, plus an indicative GPU
A/B of the falls node shown against hidden at zoom 8 (deltas 0.05-0.2 ms, inside drift).
`falls_tools` (8 captures, 63 s) drives the Bridge and Water tools through real input events:
a line across the plunge pool drawn red with "Too close to the waterfall. Bridges cross calm
water." beside the cursor and the same toast on release; a plank bridge previewed and placed
about 2.5 m upstream of the lip; a river stroke drawn uphill whose ribbon chevrons point
downhill; and in play a token wading in the plunge pool with its submerged ring and another
in the upper pool under the bridge. Unit-tested (`test_water_falls.gd`, `test_water_carve.gd`,
`test_water_fall_mesh.gd`, `test_authored_water.gd`, `test_water_tool.gd`,
`test_crossings.gd`, `test_bridge_tool.gd`, `test_glb_utils_water.gd`): the rule and the plan
(a tier stroke falls once at the brink, a hill gives spaced falls of a tier each, a gentle
slope plans as in v0.1.29, the pool widens below the face and not the face, uphill is
reversed and flat keeps its direction, down-then-up has no upward fall, a tributary off a
tier falls into the river, old documents fall only where the ground is steep); the carve (the
profile is the tier face with a harder lip, the walls steepen down the face and relax past
the pool, a hillside face is rock across the channel and cuts a notch not a quarry, the
plunge pool sits the plunge depth below the bed, a tier crossing changes the face only in the
notch, diagonal faces do not saw); the mesh (the curtain clears the rock and never rises over
the upper level, covers the wetted crest, normals face outward and triangles wind clockwise,
the mist stands at the pool with one high puff at the lip, no fall builds nothing, the flow
runs through the lip and down the face, no cascade sheet drapes a face, lip cells are tucked,
the falls node is built and left alone by the water pass, the Water tool warm makes the fall
material once, a refresh rebuilds the falls on the worker and drops them with the water); the
settings (every forwarded fall key is a waterfall shader uniform, a palette change reaches
the fall material); the tools (a fall stroke lands the same from the worker and undoes
exactly, a tributary drawn into a fall's face ends in its pool, erasing a river with falls
keeps the notch and undo brings them back, tokens land in the plunge pool and on the lip,
smoothing a fall's face turns it back into a draped sheet, an uphill stroke previews its flow
downhill, a crossing keeps clear of a waterfall, a river falling under a bridge removes it in
the carve's entry). Measured in the job (P4c-3, not pinned): the second river's water build
158 ms, bake 157 ms, swap 18 ms (150 ft map, 9 bodies, 4 falls). Not rendered before the
judgment set: the other six biomes' palettes and the v0.1.29 fixture before and after.

Phase 4c judgment (P4c-6, render job `phase4c_judgment_set`, captures and `VERDICT.md` in
`user://render_jobs/phase4c_judgment_set`, the pre-fix run in `_before`, the post-fix-3
re-render in `phase4c_iter3`; verdict 2026-10-04): in every
one of the eight palette biomes a 150 ft map (seed 1234) with a two-tier Tier step and a
waist river over it facing the camera, a Raise hill with an ankle stream down its flank
(hillside steps), a tributary falling into the main river and a deep river falling away from
the camera, captured in authoring and in play at home and at zoom 8 on each fall, with tokens
in a plunge pool and on the lip and the grid on, plus a v0.1.29 fixture document rendered
before and after. Questions the earlier renders left for it: the lip roll reads as a crisp
white rectangle at the brink and may be too strong; the glass between the streaks is subtle
at tabletop zoom; whether the brink beside the curtain reads grassy (the convex-lip rule
hands back 60 % of the rock on the shoulders; the fallback is a fall-lip term in the
dressing); thresholds, plunge size and mist density; whether grid cells show on the white
roll (the fix would be a grid-shader test, not an ordering change). Verdict: ready. The
carve and the rule are biome-independent (the same five falls to the centimetre in all
eight); rock to the brink everywhere with no grassy hand-back, so no fall-lip dressing
term; the ring at 1.1 x the crest width is right; the grid never draws on the curtain; the
off-axis crease is not visible on screen; the v0.1.29 fixture gets a curtain over its
tier cliff and keeps the riffle sheet on its ramp, before and after a save and load. Three
geometry faults fixed in P4c-6 (`c99d1ad`): the curtain ran out along a bank another
river's cut had shaved to a hair under the level (`crest_widths` now stops at the
waterline); unreached rows lay along the bank where the lower course bends right after
the fall (the trace stops 0.5 m past the carved foot); the curtain was an opaque white
sheet with a solid cap and the mist discs were wider than their streams (shader constants
lowered, puffs capped at half the fall's width). Left after P4c-6 and taken up in P4c-6b:
the lip row a straight bright line, the side edges dead straight, the mist radial ovals.
Known and not the falls': forest canopies cover falls from the fixed camera; savanna's
sandstone a notch too orange.

Phase 4d judgment (P4d-4, render job `phase4d_judgment_set`, captures and `VERDICT.md` in
`user://render_jobs/phase4d_judgment_set`, the pre-fix run in `_before`, the fixes judged at
half size in `phase4d_iter1` and `phase4d_iter2`; verdict 2026-10-04): in every one of the
eight palette biomes a 150 ft map (seed 1234) with a straight waist river, a straight ankle
stream and a deep pond, and through the crossing API a 2 m arch across the river (span 4.59,
levels 0.35 / 0.81 / 0.35), a 2.5 m ford across it (crest 0.30 under a 0.15 level), a 2 m
ford across the ankle stream, a 1.5 m plank bridge for scale and a 2.4 m arch along the pond
(span 11.33, a mid-stream pier), the same five to the centimetre in all eight biomes;
captured in authoring at home and at zoom 8 on each crossing and in play with tokens on the
arch's deck, wading both fords and on the plank deck, grid on (64 captures). Verdict: ready.
The arch reads from home as a stone bridge in the biome's own rock with its own paving and,
in the damp climates, moss in patches along the copings, and at zoom 8 as a few bold parts;
the ford reads at home as its marker stones with a bright foam line beside them and two worn
pads on the banks, and a token wades it ankle to shin deep and is never hidden; the pond arch
on its pier is the set's best single object in every biome. Fixed from the verdict: the
coping is a course of stones each keyed for moss as one (the moss was a continuous green
stripe), the ford's crest holds downstream and dips upstream so the shader's depth foam draws
a line along the downstream lip, the landings are rounded wandering tongues (were hard-edged
rectangles), marker stones 0.62-0.78 m with two on a narrow stream (were small and crowded),
voussoirs, graded spandrels, damp masonry and warm and cool casts on the arch (its grey read
flat), cutwater noses and a cap course on the pier (a single-colour block), and a darker
tint for the sandstone gravel (the landings vanished on the badlands sand and were a
red-orange splat on the savanna). Open, none blocking: the gravel never shows through the
water (the ford's underwater read is foam alone: shader work), an ankle-stream ford is
dominated by its two 2 m landings, the savanna's red pads are the loudest of the set, the
coping's moss is random per stone rather than a coarse field, and canopies hide the pond arch
in the forest biomes (camera, known). Earlier phase 4d renders: `p4d_probe` (P4d-0, the bare
bar's verdict in `user://render_jobs/p4d_probe/VERDICT.md`), `arch_look` and `ford_look`
(P4d-1, P4d-2), `arch_ford_tools` (P4d-3: the four tiles, the ford refused on deep water with
"Too deep to ford. Fords cross wadeable water." beside the cursor and as a toast, Ctrl hover
"Remove stone arch"), each in its `user://render_jobs/` folder.

Phase 5 judgment (P5-4, render job `phase5_judgment_set`, the union of `phase5_valley`,
`phase5_hilltop`, `phase5_terraces`, `phase5_lakeshore` and `phase5_gorge`; captures and
`VERDICT.md` in `user://render_jobs/phase5_judgment_set`, the half-size iterations per recipe
in `phase5_<kind>`; verdict 2026-10-04): every landform as a new 150 ft map through the
driver's `new_map` with the `landform` key, three or four temperate forest seeds per recipe (a
wet draw with a crossing, a wet draw without, a dry draw) and one in another biome (alpine
meadow, boreal taiga, riverside wetland, rocky badlands, grassland meadow), saved as
`_p5j_<kind>_<biome>_<seed>` (20 levels); captured at home with the grid, at home with the
water hidden, at zoom 8 on the stage and on the crossing, the water or the floor, and one wet
level per recipe in play with a token on the stage and one at the water (103 captures).
Verdict: ready. The hill with its crown pool spilling in a fall, the terraces with their
stepped falls and plank bridge, and the gorge with its arch rim to rim and its stream along
the far wall each read as a place from the home camera, the lake reads with its wavy shore
and islet, and every draw stands on its own with the water hidden; the valley is the quiet
one, a valley with a river, a ford and a rock bluff in open grass but a dark dip under forest
canopy. No draw broken, no refusal in the set. The fault the captures found: the recipes
assumed the camera looks along -z, where it looks along (-1, -1) at a 45 degree yaw, so the
hill's stage sat on its side, a gorge ran along the view and the valley's bluff stood on the
back-facing bank; fixed with `StartingLandform.VIEW` / `NEAR` as the one rule for anything
facing the camera (0bcda1d). Fixed from the verdict as well: gorge headings across the view,
two tiers only from 150 ft and the stream at the far wall (4bf7ea9); the hill's spring a pool
on the crown that falls off the face, the stage on the camera-facing shoulder, never a bare
mound (2c11229); the lake centre at 0.5 of the half extent (43fbcab); the valley's one-tier
bluff on the far bank (a46b3e4); then in P5-4b (8092d17) a flank ledge on every crownless hill
with the crown chance at 0.85 (seed 12's two plain mounds were the set's weakest draw), and
the lake's corner drawn from the three that are not the camera's own. Open, none blocking:
the valley under forest canopy, a lake in a side corner at the frame's edge, lake stones
refusing `no_water` on some seeds (Open work, "Landform follow-ups"). Earlier phase 5 renders:
`landform_look` (P5-1, P5-2: the `_p5_` levels) and `landform_dialog` (P5-3: the six tiles and
the caption), each in its `user://render_jobs/` folder.

Unit-tested only (not yet over real Steam): the version gate's lobby-data and host
rejection paths, client download of `map.ttmap`, the map-hash cache refresh, and the
download-signal fix (pushed to `main` as a08b639). Needs a two-account test, e.g. on the
Steam `testing` branch that every `main` push deploys to.

Performance: the pinned-procedure pass is done (`PERFORMANCE.md` "In-game authoring: pinned
performance pass", 2026-09-26, idle RTX 3080, 1920x1080, vsync off, default settings). A
fully painted 200 ft map plays at 5.1-5.5 ms GPU at home and 6.4-6.7 ms at max play zoom
(temperate forest 31,305 instances; grassland, the densest biome, 43,433), about 2x the
Blender deciduous map, which carries a third of the instances: no authored-specific
overhead. The ground shader is 1.31-1.38x a StandardMaterial3D ground (+0.4-0.6 ms), a
painted layer adds about 0.5 ms, the broad edge 0.04-0.11 ms; the skirt costs 0.6-0.7 ms at
max play zoom at the map edge and 0.9 ms at full authoring zoom-out after a no-look-change
fix (was 1.24 ms). Brush strokes: CPU frame median 3.8 ms on a bare map and 6.9-7.5 ms over
a fully painted forest, worst stroke frame 12.3 ms, worst regeneration-tail frame 18.3 ms. Opening a map: 1.15-1.37 s loading screen, then all 180 palette
species resolve in 2.9 s with no frame over 30 ms, for about 100 MB more video memory than
playing an authored map. Loads from the title: 1.27 s warm / 1.78 s cold for the painted
forest, between deciduous clusters (0.74 s) and river (1.9 s). Phase 3 pass (`PERFORMANCE.md`
"In-game authoring phase 3: pinned performance pass", 2026-09-27, 150 ft forest and badlands
maps built like the judgment set, each against a flat twin): relief costs little in play
(badlands +0.23-0.28 ms GPU; the forest relief map is cheaper than its twin because trees
keep off the tier faces) and adds nothing to loading or memory; every map stays under 4.1 ms
GPU at max play zoom. The ground shader with the whole phase 3 set costs +0.84-0.99 ms over
phase 2's base-only shader on flat ground and +1.26-1.78 ms where tiers fill the view (accents
0.36-0.49, side projections 0.19-0.32, the 8-slot table and rules about 0.8). Sculpt and Paint
strokes run at 4.4 ms median CPU (11.6 ms with a 12 m brush); release frames are 10-23 ms,
40-60 ms after a 12 m stroke (the rule-field pass); the skirt's 45 ms vertex copy, which hit
the first stroke to reach the map edge, is now built under the loading screen. Phase 4 pass
(`PERFORMANCE.md` "In-game authoring phase 4 (water): pinned performance pass", 2026-09-27,
150 ft forest and wetland maps against their twins before water): water costs about its
pixels in play (the merged mesh 0.2-0.3 ms GPU in view; every map under 4.9 ms at max play
zoom), every water gesture and a sculpt by the water keep medians within 0.5 ms of idle with
worst frames of 21-29 ms, and water adds 0.23-0.26 s to a warm load and 1-15 MB of memory.
P4b-0 moved the load's pure data work (wet dressing, water geometry, rule fields, chunk and
skirt arrays) onto workers: water's main-thread load work 214 -> 14 ms, its share of a warm
load 0.21-0.24 -> 0.09-0.10 s, dry authored maps 30-50 ms faster (`PERFORMANCE.md` "P4b-0:
authored map load on workers"). Phase 4b pass (`PERFORMANCE.md` "Phase 4b (crossings): pinned
performance pass", 2026-09-27, a 150 ft forest map with four crossings against its twin
without): crossings cost nothing measurable in play (shown against hidden in one run, -0.08 to
+0.01 ms GPU: a deck covers dearer water pixels), add 45-69 ms to a warm load, and the Bridge
tool keeps frame medians at idle (4.2-4.8 ms) with release frames of 12.7-19 ms; a crossing
edit rebuilds only the crossings whose fields, ground or water changed (P4d-5b, `PERFORMANCE.md`
"Per-crossing rebuild cache": a placement with six crossings on the map 9.8 ms of refresh
against 33.8 before).

## Open work

Phases 1-3 were released as v0.1.28 (2026-09-27); phases 4 and 4b (water, crossings, the
submerged-token ring, worker-thread loading) as v0.1.29 (2026-09-28); phase 4c (waterfalls,
the system docs pilot) as v0.1.30 (2026-10-04); phase 4d (the stone arch, fords, the
per-crossing rebuild cache) as v0.1.31 (2026-10-04). Releases stay patch bumps until the
whole map maker is finished, then the minor version goes up (user, 2026-09-27). The
two-account Steam test (above) is still open and is best run on v0.1.31: it now also covers
an arch and a ford reaching a peer, a token wading the ford, and a document
with `splines.json`, `ponds.png`, a baked `water_flow.png` and `crossings.json` reaching a
peer, tokens on a deck, the submerged ring on a client, and a waterfall's curtain built
on both peers from the same reaches.

Water follow-ups (phase 4 judgment pass, 2026-09-27):
- In the wetland the ankle stream is so thick with reeds it can read as a reed bed rather
  than water from the home view. (The foam outlines along submerged reed blades went with
  the boulder-line fix, P4b-0; confirmed in the wetland re-render of the P4b-3 judgment set.)

Waterfall follow-ups (phase 4c, P4c-1 to P4c-5, 2026-10-04; none blocking):
- `WaterGeometry.level_at` has no flush cut at a reach's end, so within the half-width plus
  the bank of a lip the fall's face reads the upper pool's level and `is_wet_at` is true on
  the rock. Worked around twice (P4c-5): `CrossingPlacement` refuses a line across the face as
  `fall`, and `WaterEdit.join_line` treats face points as dry (`WaterFalls.on_face`). If another
  tool starts reading the face as wet, a flush cut in `level_at` is the real fix.
- The carve's crease where a face emerges from a natural slope is grid-sampled and zigzags
  0.10-0.14 m at 10-60 degrees off the axes (P4c-2; not seen on screen at the rendered angles).
- Noisy ground within 0.5 m of a cliff can leave the level step just under 0.75 m, so the
  runtime rule sees a riffle where the plan placed a fall (P4c-1; for the judgment set).
- Narrow channels do not reach the full plunge depth: `section()`'s `MAX_SHORE_SLOPE` caps how
  much of it the centreline reaches (ankle, half-width 0.55: about 0.5 m of the planned
  0.9 m). Left as is (P4c-2).
- Smoothing a fall's face alone may leave its curtain until the pool edge is smoothed too
  (`WaterFalls.face_search` catches the brush's own shoulder; P4c-5).
- The fall refusal zone for crossings is generous downstream: about 4 m below a waist river's
  lip (the footprint plus the foam ring disc plus 1 m; P4c-5).
- Pond spills over an edge (an automatic outflow) are later work; today a river drawn out of
  a pond over the edge falls by the same rule as any other (decided 2026-10-04).
- A bridge over the lip (a deck spanning a fall) is not in scope; any crossing within 1 m of
  a fall is refused. It can be added later if wanted (decided 2026-10-04).

Crossing follow-ups (after P4b-3, 2026-09-27, and phase 4d, 2026-10-04; later work, none
blocking):
- Crossings on a dressed Blender map's own water (deferred to a terrain-paint integration
  sprint, 2026-10-04): its water plane is not a crossing target
  (the snapping reads document water; the Bridge tool is disabled there with a tooltip unless
  the document has water), and its Blender scatter is not cleared under a crossing.
- The ford's gravel never shows through the water: its underwater read is the shader's foam
  alone (the water hides anything 0.25 m down; the crest profile turns the wash into a
  gradient with an edge, as far as the mesh can take it). A foam band keyed to the ford, or
  more transmission in the shallows, is `water.gdshader` work (P4d-4).
- A ford on an ankle stream is dominated by its two 2 m landings around a 1.1 m stripe; a
  landing narrower than the bar on a narrow stream would help (P4d-4).
- The savanna's ford pads are red earth on yellow grass, the loudest of the set, in the tone
  of the biome's own bank strips; a plain `gravel` surface there would be quieter but less its
  own. Left as the biome's red earth (P4d-4).
- The arch coping's moss decision is random per stone (a thrown key), so the pattern does not
  relate to position the way the stepping stones' field does; it reads right, but a field at a
  coarser scale along the parapet would be the principled version (P4d-4).
- A single arch or ford node's swap is 4.4-6.3 ms (`moss_split` walks every facet in
  GDScript, then the mesh and concave-shape upload), and a ford's build is 5 ms for 200
  vertices, unprofiled; both are the next targets if a placement needs to go under a frame
  (P4d-5, P4d-5b). The per-crossing cache itself is done (P4d-5b): a placement costs its own
  crossing whatever the map's count (6-13 ms by kind, 3-4 ms for planks and stones).
- A painted path through the shallows stays what it is (P4b-0 lets it run into the water): it
  gives the look on ankle water but no passage over waist water, which the ford kind does.
- Forest canopies in front of a crossing can hide it from the fixed camera (a 6 m canopy
  covers ground up to about 15 m behind it at the 21.6 degree view): in play the occlusion
  fade opens a hole over the tokens on it, not over the deck. Candidate: count a crossing's
  deck as a fade focus in play, or let the author Thin in front of it (works today).
- Savanna's stepping stones share badlands' sandstone and read a notch more orange than the
  savanna's grey-brown boulders (a per-biome stone tint, like the basalt lift, would settle it).
- The grid on the brown deck is low contrast (review note; left as is: it matches the ground).
- Palette boulders can stand in the water beside a bridge deck (their centres keep 0.95 m
  from the footprint, a large boulder's body can still touch the rail); judged acceptable.

Landform follow-ups (phase 5, P5-4 to P5-5, 2026-10-04; none blocking; `systems/landforms.md`):
- The valley under forest canopy reads weakly from home: the canopies hide most of its floor
  and it reads as a dark dip with a river in it. The canopy read is a `NewMap` glade matter
  (a thinner canopy over the stage's reach, or a wider glade), not the recipe's.
- A crownless hill's flank ledge (P5-4b) reads weakly when the seed draws a narrow arc
  (`LEDGE_ARC_DEG` 60-100 degrees); the crown chance went to 0.85 so the draw is rarer.
- A lake in a side corner (the two corners beside the camera's own) sits at the frame's edge;
  the far corner reads best. Favouring the far corner, or pulling side lakes toward the
  centre, is the next step.
- On some lake seeds (surveyed seed 14) the stepping stones refuse `no_water`: the stream's
  straightest point lies where the carve left no water. A wet-water check on the candidates
  before choosing would avoid it (the draw is skipped, the map stays whole).
- A 200 ft gorge opens in 1.5 s with one 1.2 s frame, because the recipe runs on the main
  thread in the frame that starts the open (`PERFORMANCE.md` "Phase 5 (starting landforms)").
  The recipe writes only the document, so it could move onto the loader's worker.

Follow-ups:
- A quick brush pass still gives few trees in sparse biomes (temperate forest targets 0.02
  trees per m2); tall grass still covers most of a forest floor (density / card size).
- Host re-saves during a session are not re-broadcast with new map hashes (authoring is
  offline, so this only matters if that changes).
- DebugRenderToggles (F3) are not set up in authoring; the map-name field has not been
  exercised with real typing.
- Palette foliage ships uncompressed and unmipmapped because mips lost small flowers;
  treecube can now build coverage-preserving mips, but a GLB carries one level, so
  re-enabling compression needs shader-side alpha scaling or a KTX2/DDS path.
- Canopy-top fading over tokens in play (a side effect of the brush canopy fade) was not
  rendered in play.
- In the harness verification run the savanna new map's home shot came out at camera
  size 35.02 where every other biome's is 13.85 (the earlier run had 13.9); the camera
  home or zoom state can leak between maps. Not yet investigated.
- `tools/` (including `tools/render_jobs/`) is not excluded by the export presets, so dev
  scripts ship in builds.
- Performance leftovers from the pinned pass (`PERFORMANCE.md`), none blocking: an authored
  map's load from the title is mostly frames waited at 60 Hz (66 against a Blender map's 29;
  a larger per-frame build budget under the loading screen could save 0.3-0.5 s); the first
  load in a process has one 580-630 ms frame (Blender maps too); 750-870 MB of video memory
  stays allocated back at the title after any map. Every warm load, authored or Blender, dry
  or wet, still has one 165-175 ms frame (not water's; P4b-0 did not look into it), and the
  wet dressing worker (about 115 ms on a 150 ft map) is now what a water map's loading
  screen waits on.
- Each token leaves one orphan Node3D at exit (`--verbose`: "Leaked instance: Node3D", one
  per token played, with or without the submerged cue; seen while checking P4b-0). Not
  diagnosed.

## Roadmap

- **Phase 3 (done, 2026-09-27):** Sculpt (Raise, Smooth, Flatten, Tier with rock-cliff
  edges snapping to 5 ft tiers), Paint (ground, rock and built surfaces; paint yields to
  rock on faces; biome path variants listed first), an 8-slot ground shader with automatic
  cliff / scree / lip rules, biplanar faces and biome ground accents, a height-aware grid
  on authored and Blender maps, tokens landing on the right tier, plants and props with a
  footing rule, and rocks that survive sculpting as tilted props. Decisions: tier edges are
  rock cliffs; the terrain dresses itself automatically and painting overrides it except on
  cliff faces; rocks are kept, never added, when sculpting changes the ground under them.
- **Phase 4: water (done, 2026-09-27).** Carve rivers, streams, ponds and shores with a gesture: the stroke
  lowers a channel, paints its bed and banks, clears scatter, places the water surface and
  bakes a flow map in terrain-paint's format (`splines.json` is reserved in the document).
  The water shader, flow maps, token wakes and ripples already exist, so this is mostly
  tooling (user note, 2026-09-27). Paths already stop at rock faces; a river crossing a
  painted path should do the same. Decisions (2026-09-27): a Water tool with River (draw a
  line: carves a channel, lays bed and banks, fills it with water flowing along the line)
  and Pond / lake (paint an area: a basin with still water at a level), Ctrl erases water;
  depth chosen per stroke (tokens stand on the bed in wadeable water and float at the
  surface in deep water); the grid lies on the water surface so squares stay continuous
  across rivers (on Blender maps too). Built on `authoring-phase4`: the water model and flow
  bake (P4-1), the surface in play and authoring (P4-2), carving and dressing (P4-3), and the
  Water tool (P4-4: River and Pond tiles with Ankle / Waist / Deep, a ribbon preview, rounded
  river heads, confluences that join existing water at its level, Ctrl erasing a river whole
  (every reach of its stroke), soft pond beaches, mossy forest banks, and the carve on a worker so a release
  never freezes the view). Decided in P4-4: a dressed Blender map can only erase water
  painted over it (carving needs the document's ground); erased water leaves its channel
  carved, and Sculpt's Smooth is the way to fill it. P4-5 (judgment, performance, docs):
  riffle sheets meet their banks on a smooth line instead of the sample grid's sawtooth; a
  pond extended by a second stroke keeps its level and is carved as one basin (no ledge);
  the water shader's refraction fades in from the waterline (no glassy band on steep stream
  banks) and its shore foam and waterline fade apply only where ground meets the water (no
  pale shards around reeds); a sculpt stroke by the water computes the wet dressing on a
  worker (worst frame 118 -> 28 ms); the harness's test token is an ordinary one (the
  "bright blobs" on the water in earlier renders were its emissive light globe). Judgment
  set: `tools/render_jobs/jobs/phase4_judgment_set.json`; pinned pass: `PERFORMANCE.md` "In-game
  authoring phase 4 (water): pinned performance pass".
- **Phase 4b: spanning water (done, 2026-09-27).** Bridges and other crossings (plank bridges, stepping
  stones, stone arches, fords) that snap between two banks, span the gap with walkable
  collision for tokens, and match the palette's painted style; likely generated or
  assembled from treecube-style parts so a bridge fits any width (user note, 2026-09-27).
  Decisions (2026-09-27): plank footbridge and stepping stones first, stone arch later;
  drag a line across water and the crossing snaps its ends to the banks and sizes itself;
  tokens stand on decks and stones, the grid runs across the deck, tokens cannot pass under
  a bridge. P4b-1 (done): the model (`crossings.json`), the snapping rule, procedural
  geometry from the palette's planks and each biome's rock, layer-1 collision, the grid on
  the deck, scatter clearing and the editor API. P4b-2 (done): the Bridge tool (its own rail
  item; drag a line, live preview, refusals in plain words, Ctrl erase, width on Shift+wheel)
  and crossings following sculpt and water edits in the same undo entry. P4b-3 (done): the
  judgment set in all eight biomes (the stones' moss as the palette's moss surface, basalt
  stones lifted to the boulders' grey, trees and shrubs kept back from landings, a readable
  drawn line), the pinned performance pass (`PERFORMANCE.md` "Phase 4b (crossings): pinned
  performance pass") and these docs. Phase 4b is done (2026-09-27); the stone arch and fords
  followed in phase 4d (below); crossings over a Blender map's own water are later work (Open
  work above).
- **Phase 4c: waterfalls (done, 2026-10-04).** Waterfalls: a
  river drawn across any steep drop falls there by itself, with no new control (small drops
  stay riffles). Over a Tier cliff the water uses the existing rock face; on a steep natural
  slope the carve cuts a rock lip with a plunge pool below, so a river down a hillside steps
  in falls. Decisions (2026-10-04): falls are automatic and form over Tier cliffs and steep
  natural slopes alike; a stroke drawn uphill is flipped so water always runs downhill and
  falls face downstream, and the ribbon's chevrons show the real direction; any crossing
  within 1 m of a fall is refused in plain words, a deck over the lip is not in scope; ponds
  spilling over an edge are later work (a pond outflow is a river drawn from the pond over
  the edge, which confluences already support and which falls by the same rule). Plan:
  `docs/plans/2026-10-04-phase4c-waterfalls.md` (local; its "done" sections record what was
  built). P4c-0 (done): throwaway Godot probes settled the render ordering (at an equal
  priority the water erases the curtain, so the fall material sits strictly above the
  water's), the screen texture (it never holds a transparent curtain), billboards and the
  depth copy's cost, two-sided lighting (no normal flip) and Jolt landing on carved faces.
  P4c-1 (done): the rule and the plan (`WaterFalls`: the fine profile along the stroke, drop
  runs of 0.75 m or more at a slope a riffle cannot follow, lips at least a spacing apart as
  forced reach boundaries with the face free of the reach rule, uphill strokes reversed, the
  diagonal lip set-back, the widened plunge-pool point, gentle strokes byte-identical to
  v0.1.29). P4c-2 and 2b (done): the carve (the tier profile upside down with a harder lip,
  a plunge pool deepest at the face's foot, and gorge side walls at 54 degrees so a hillside
  fall cuts a tight rock notch where the first render cut an 8 m rock wall for a 1 m stream).
  P4c-3 (done): the curtain, foam ring and mist mesh (`WaterFallMesh`), the
  `AuthoredWater-falls` node, no cascade sheet over a face, the face in the wet dressing and
  the flow bake. P4c-4 (done): the falls shader (a white roll at the lip, streaks that
  accelerate in fall-time space, a churn ring on the pool, depth-faded mist, a Low quality
  tier), the one shared fall material restyled by the Water pane's palette and motion tiles
  with no new field, the warm-up. P4c-5 (done): the fall refusal for crossings, a tributary
  ending on a face joins the plunge pool, the ribbon follows the real direction, the Water
  and Bridge hints and the F1 "Waterfall" row. P4c-6: the judgment set in all eight biomes
  (`tools/render_jobs/jobs/phase4c_judgment_set.json`; Verification status above). P4c-7:
  the pinned performance pass (`PERFORMANCE.md`). P4c-8: these docs. Crossings over a dressed
  Blender map's own water are deferred to a separate terrain-paint integration sprint.
- **Phase 4d: the stone arch and fords (done, 2026-10-04).** The remaining crossings: a
  masonry arch bridge and a gravel ford, drawn with the same one line and following later
  edits like the planks and stones. Decisions (2026-10-04, "your recommendations make sense,
  continue"): a segmental arch, not a semicircle (a semicircle over a 6 m span stands 3 m
  tall and hides its own water from the camera); the ford as a derived crossing kind, not a
  painted path (a path gives the look on ankle water but no passage over waist water, and the
  crossing model is what makes a ford follow later edits); a ford over waist water raises its
  crest to ankle depth (0.15 m under the surface) so a token wades it and is never hidden;
  the `building-bridge.svg` glyph for the arch and a new `ford.svg`; not in scope: a deck over
  a waterfall's lip, crossings on a Blender map's own water, a ford that moves the bed, rails
  or lanterns, water animated through the arch. Plan:
  `docs/plans/2026-10-04-phase4d-arch-and-ford.md` (local; a "done" paragraph per task).
  P4d-0 (done): the ford bar probe (`FORD_DEPTH_M` 0.15; a bare submerged bar reads as one
  pale wash, so the ford needs its own cues). P4d-1 (done): the arch kind (`CrossingArch`:
  abutments, a parabolic barrel, spandrels, a pier over 9 m, parapets, a paved deck in the
  biome's first paved path surface). P4d-2 (done): the ford kind (`CrossingFord`: the bar,
  landings and marker stones, the biome's gravel, the `deep` refusal). P4d-3 (done): the Arch
  and Ford tiles, hints and F1 rows. P4d-4 (done): the judgment set in all eight biomes
  (coping stones keyed for moss, the ford's crest profile and rounded landings, larger marker
  stones, voussoirs and graded spandrels, a cutwater pier, a darker sandstone gravel;
  Verification status above). P4d-5 (done): the pinned performance pass (`PERFORMANCE.md`
  "Phase 4d (arch and ford): pinned performance pass": the kinds cost nothing in play; a
  placement rebuilt every crossing at 5.6 ms each, 33.8 ms with six), which brought the
  per-crossing rebuild cache forward: P4d-5b (done, `CrossingCache`: 9.8 ms for the same
  placement) and P4d-5c (`follow` refreshes the crossings whose ground changed when no anchor
  moved). P4d-6: these docs.
- **Phase 5: starting landforms (done, 2026-10-04).** A new map opens with a landform picked
  in the dialog beside the size and the biome: Flat, Valley, Hilltop, Terraces, Lakeshore or
  Gorge, each a pure recipe run on the document before the map opens, writing heights, carved
  water, a crossing and the stage (where the glade goes) as the ordinary data the tools edit.
  Decisions (2026-10-04, "the choices make sense"): six landforms as tiles under the biome
  row, Valley the default (Flat on Bare ground), a crossing only where the seed draws one; and
  the user's rule for every recipe, no sameness: a landform is a shape plus a small palette of
  features with chances, not every valley has a river nor every river a crossing, every draw
  (judged with the water hidden too) is a complete map on its own, and the shape varies with
  the seed (heading, offset, bend, the hill's side, the lake's corner) within bounds that keep
  it recognisable; the caption describes the landform, never the draw; no history entry; not
  in scope: a landform on a dressed Blender map, landform parameters, several rivers per
  landform. Plan: `docs/plans/2026-10-04-phase5-starting-landforms.md` (local; a "done"
  paragraph per task); system doc `docs/systems/landforms.md`. P5-0 (done): the open path
  timed through the pure functions (the recipe's water stays before the open). P5-1 (done,
  aaa3231): `StartingLandform`, the seeded frame and shared steps, the Valley, `NewMap` taking a
  landform and centring the glade on the stage. P5-3 (done, b226cfb): the dialog's Landform row,
  glyphs and caption, the loading line, the F1 row. P5-2 (done, 469c0d2): Hilltop, Terraces,
  Lakeshore and Gorge, the Valley deepened to 3.5 m. P5-4 (done, 4bf7ea9, 2c11229, 43fbcab,
  a46b3e4, 0bcda1d, 353a6ae): the judgment set and its fixes, among them the camera fix
  (`VIEW` / `NEAR`), the hill's crown pool fall and the Valley's bluff (Verification status
  above). P5-5 (done, 1ff484e): the pinned performance pass (`PERFORMANCE.md` "Phase 5
  (starting landforms)": a landform adds 85-325 ms to a 150 ft open; a shaped map strokes like
  a flat one). P5-4b (done, 8092d17): a flank ledge on crownless hills, the lake away from the
  camera's corner. P5-6: these docs.
- **Before the minor version bump ("map maker finished"):** not yet fully scoped with the
  user. Candidates on record: phases 4c, 4d and 5 (all done), and the Steam two-account test
  passing on an authored map with water and crossings (still open). Confirm the list with the
  user before planning it.

## Future ideas (user notes, 2026-09-27)

Broader than map authoring; recorded here so they are not lost.

- **Tree clipping when zooming in.** At close zoom the camera can cut into tree canopies.
  Candidate: extend the occlusion-fade (obstruction) shader, which already dissolves
  canopies over tokens and under the brush ring, to also fade canopy fragments close to the
  camera's near plane or within a distance of the view ray, so zooming in reveals the
  ground instead of slicing a tree. Start by confirming whether the cut is the near plane
  (orthographic camera offset) or canopies simply filling the view.
- **Player avatar tokens in the house style.** Let users create avatar models for their own
  player tokens that match the painted style: light on detail, heavy on customisability
  (body plan, proportions, palette, clothing and gear pieces, a few expressive features),
  under the same guiding principle of beautiful and expressive. Likely a treecube-style
  parametric generator (Blender side for authoring, or an in-game builder in the spirit of
  this authoring mode), exporting through the asset-pack token path.
