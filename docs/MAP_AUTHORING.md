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
| First-use pipeline warm-up | `utils/pipeline_warmer.gd` | `PERFORMANCE.md` |
| Same-version join gate | `utils/version_gate.gd` | `NETWORKING.md` "Same-version gate" |
| Render-job harness (1920x1080 judgment renders) | `tools/render_jobs/` | `tools/render_jobs/README.md` |

## Verification status

Verified in the running game (host, validation bridge and render jobs): new-map flow for
all eight palette biomes, save / reload / Edit map, autosave recovery, the three brushes
on a bare 200 ft map, dressing Blender maps (River, Deciduous clusters: live erase of
their scatter matches what a player's load builds), play-time loading of GLB-only,
ttmap-only and dressed levels with exact instance counts.

Unit-tested only (not yet over real Steam): the version gate's lobby-data and host
rejection paths, client download of `map.ttmap`, the map-hash cache refresh, and the
download-signal fix (pushed to `main` as a08b639). Needs a two-account test, e.g. on the
Steam `testing` branch that every `main` push deploys to.

Performance: every frame time taken during development was on a GPU contended by another
game, so treat them as indicative. CPU-side numbers that hold: a 200 ft map loads in about
0.5 s warm / 1.1 s cold (headless), longest load frame 70-84 ms; a brush dab's main-thread
work is at most ~6 ms; four-cell regeneration shows its first cell in ~20 ms and finishes in
~155 ms on worker threads; the first stroke's pipeline hitch moved under the loading screen
(115 ms -> 23-26 ms). A pinned-procedure pass (`PERFORMANCE.md`) is still owed.

## Open work

Before merging `in-game-authoring` into `main`:
- The two-account Steam test above.
- A pinned-procedure performance pass, including the ground shader (about 1.4x a
  StandardMaterial3D ground), the broad edge and the skirt, and memory for resolving all
  180 palette species when authoring opens.
- Merging `main` will conflict in `map_download_coordinator.gd` and `download_queue.gd`:
  `main` has the minimal download-signal hotfix, this branch rewrote the same handlers;
  keep this branch's versions (they already take the fifth argument).

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

## Roadmap

- **Phase 3:** sculpt (raise, lower, smooth, flatten) and tier brushes snapping to whole
  tiers (default one cell, 5 ft); surface painting with the palette ground kinds and
  terrain-paint's slope / height / curvature rules ported to the ground shader (it already
  takes up to 4 layers; phase 3 extends to 8). Known constraints: the grid overlay
  filters to a floor band at Y = 0 and needs a height-aware mode for tiers; planar UVs
  stretch on steep slopes (needs triplanar or slope-aware mapping there).
  `AuthoredTerrain.rebuild_chunks()` / `update_collision()` and the document's height
  field are already in place.
- **Phase 4:** river, road and shore splines that carve, paint, clear scatter and bake a
  flow map in terrain-paint's format (`splines.json` is reserved in the document).
- **Phase 5:** more starting points. `NewMap` already gives each biome a starting cover
  (groves at the edges, an open glade for the fight).
