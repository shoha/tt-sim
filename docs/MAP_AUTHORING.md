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
| Water model and flow bake (bodies, levels, wet samples, pond mask, the flow map) | `resources/water_body.gd`, `utils/water_geometry.gd`, `utils/water_flow_baker.gd`, `utils/map_water_io.gd` | `ARCHITECTURE.md` "Water model and flow bake", "Map document (map.ttmap)" |
| Water at runtime (merged surface, zones, water as ground, float rule, grid on the water, the water shader) | `utils/water_mesh_builder.gd`, `scenes/terrain/authored_water.gd`, `utils/water_surface.gd`, `scenes/effects/water_zone.gd`, `utils/water_glb_utils.gd`, `shaders/water.gdshader` | `ARCHITECTURE.md` "Authored water at runtime" |
| Carving and wet dressing (channel and basin profiles, reach steps and riffles, confluences, erase, bed and shore surfaces, plants, rocks, the worker) | `utils/water_carve.gd`, `utils/water_edit.gd`, `utils/water_dressing.gd`, `scenes/states/authoring/water_editor.gd` | `ARCHITECTURE.md` "Carving water" |
| Water tool (River and Pond tiles, depth tiles, ribbon preview, Ctrl erase) | `scenes/states/authoring/water_brush.gd`, `water_tool_pane.gd`, `brush_tool.gd` | `UI_SYSTEMS.md` authoring drawer (Water) and "Brushes and gestures" |
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

## Open work

Phases 1-3 were merged to `main` and released as v0.1.28 (2026-09-27) so the two-account
Steam test (above) can run on the release while phase 4 is built. That test remains open,
and phase 4's water (a map document with `splines.json`, `ponds.png` and a baked
`water_flow.png`) has not been sent to a peer over Steam either.

Water follow-ups (phase 4 judgment pass, 2026-09-27):
- In the wetland the ankle stream is so thick with reeds it can read as a reed bed rather
  than water from the home view. (The foam outlines along submerged reed blades went with
  the boulder-line fix, P4b-0; not re-rendered in the wetland.)
- Water adds 0.23-0.26 s to a load: the wet dressing and the water mesh are built on the
  main thread under the loading screen (`PERFORMANCE.md` phase 4 pass).
- Waterfalls between reaches (a riffle is the only step), and bridges and fords (phase 4b).

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
  stays allocated back at the title after any map.

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
- **Phase 4b: spanning water.** Bridges and other crossings (plank bridges, stepping
  stones, stone arches, fords) that snap between two banks, span the gap with walkable
  collision for tokens, and match the palette's painted style; likely generated or
  assembled from treecube-style parts so a bridge fits any width (user note, 2026-09-27).
- **Phase 5:** more starting points. `NewMap` already gives each biome a starting cover
  (groves at the edges, an open glade for the fight).

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
