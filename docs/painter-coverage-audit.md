# Painted coverage audit (2026-11-18, main 4f1b82b8, card painter-audit-board)

Question: which asset classes have no Painted form, so they draw the same (Classic) in both looks.
Method: read code only (no render, no Godot run). `painter/painter_surfaces.gd` (what the host
binds), `painter/plant_roles.gd`, `painter/painter_buildings.gd` (KINDS and WALL_LAYERS),
`painter/painter_scene.gd`, `painter/render_style.gd`, `scenes/effects/fire_variants.gd`,
`scenes/board_token/token_toon.gd`, the core catalog (`libraries/core/assets/catalog.json`, 293
assets: 83 ground_cover, 51 bush, 43 rock, 42 flower, 42 tree, 32 deadwood; 211 structure
recipes), and the 2026-11-15 matrix (`docs/research/2026-11-09-prototypes/compare/
painter_final25_coverage/matrix.md`, main 5b3c08f0), re-checked row by row against current code.
Status: yes (painted form, how), partial (what is missing), no (identical in both looks).
Severity is how visible the gap is at tabletop zoom (orbit) and at eye level: H, M, L.

The roadmap's default criterion "every Classic asset class has a painted form" is NOT met: the
classes marked no or partial below are still Classic. The look is nonetheless the default (owner,
2026-11-16).

## Terrain and scatter

| Class | Painted form | Status | How (verified in code) |
|---|---|---|---|
| Ground, paths, shore, cliffs, biome ground (dry, ash, earth, char) | yes | yes | `painter_ground.gdshader` as `material_override` on every chunk and the skirt (`PainterSurfaces._dress`) |
| Skirt, river channel patch at the map edge | yes | yes | same override; the patch since painter-edges |
| Trees the painter grows (birch, oak, lime, poplar, spruce, pine, willow, sapling, rowan; 8 species rows, 12 asset rows in `species.json`) | yes | yes | stroke and block-in shaders (`PainterTrees`) |
| Acacia, palm, dead tree, cactus tree | yes | yes | by surface: `*_Bark` a solid, the rest a leaf mass (`PainterPlantRoles.for_surface`) |
| Bushes, shrubs, hedges, ferns, berry and flowering bushes | yes | yes | KIND_CROWN, trees' crown ramp |
| Agave, barrel cactus, dead shrub, ivy, moss, planters | yes | yes | KIND_MASS or solid in cactus, bark or charcoal role |
| Flowers, grass, sprigs, stubble, litter | yes | yes | KIND_FLOWER, KIND_GRASS, KIND_SOLID (litter), dry-grass role in dry biomes |
| Rocks, boulders, logs, stumps, branches | yes | yes | KIND_SOLID, stone or bark or charcoal role |
| EyeRim (eye-view hedges and copses) | yes | yes | the rim is an `AuthoredScatter`, bound by `_on_map_child` and `_on_scatter_shown` |
| Library asset whose surface is neither a wind ShaderMaterial nor a BaseMaterial3D | no | no | `stand_in_of` returns null: the surface keeps its own material (low: core has none known) |
| Library asset whose name matches no rule | stone fallback | partial | `PainterPlantRoles.of` ends `still -> stone`, `swaying -> leaf mass`: a user-library prop or plant gets a stone or leaf tone whatever it is |
| Legacy GLB maps (a `map.glb` with no `AuthoredTerrain` or `AuthoredScatter`) | sky, light, water, ground, trees, scatter and named props (PainterGlbMap, 2026-11-18) | yes, with listed limits | `_bind` finds only the authoring nodes; `PainterGlbMap` scans the rest of `LevelMap` over frames (docs/systems/painter.md "GLB maps"); verified on a fixture world |
| Field plants: village orchard trees, garden flowers and shrubs, hedged boundaries, crops (`AuthoredFieldPlants`) | yes | yes | since painter-village-parity (2026-11-18) the layer answers like a scatter (`rows_by_asset`, `resolved_species`, `cells_applied`, `species_added`) and `PainterSurfaces` binds it as a plant source: its mapped trees and bushes are drawn by `PainterTrees`, the rest wear the plants' stand-ins (its meshes are its own, not the scatter's, so it reports the ones it resolved) |
| Clipmap ground bake | not checked | open | `painter_surfaces.gd` header still says "the clipmap keeps baking the Classic ground underneath"; `ground_clipmap*` and `authored_ground_*_looked` shaders exist; not verified what shows beyond the chunks |

## Structures and village layers

| Class | Painted form | Status | How (verified in code) |
|---|---|---|---|
| Procgen structures: walls, roofs, timber, stone, chimneys, trim, ornament wood, bark, cloth, canopy leaf | yes | yes | `PainterBuildings.KINDS` (manner strokes where records exist, A3b mass look otherwise) |
| Yards (dressing props and ground) | yes | yes | `YARD` shaders |
| Street rows, drawn walls, village boundaries, crossings (timber, stones, arch, ford) | yes | yes | `WALL_LAYERS`, `wall_part_key`, `crossing_stone` role |
| Round and profile roofs, Taper pieces (windmill cap, wizard tower, spire) | mass look only | partial | no procgen records, so no hand-drawn strokes (roadmap A queue item 7; per docs, not re-read in procgen) |
| Panes, lantern glass, glow halos, door and ornament metal, water parts of a structure | no | no | no KINDS row, kept Classic by decision (they are lights and ironwork) |
| `decor_baked` (a structure's baked decor plants: ivy, planters, flower boxes) | yes | yes | since painter-village-parity `PainterVillage` swaps each surface of the baked mesh for the plants' stand-in (solid kind, bark or leaf role), shared per original material; the non-bakable decor MultiMeshes (`decor_<asset>`) are not covered |
| Settlement furnishings (`AuthoredSettlements`: crates, barrels, carts, laundry, signposts, lamp posts, wells, haystacks, baked per cell) | yes | yes | since painter-village-parity the `prop:*` surfaces (not glass) wear `painter_prop.gdshader` (`PainterVillage`): sheet ramps chosen by the procgen paint, winter snow caps; `prop:glass`, glow and water parts stay Classic by decision; cloth no longer sways in the wind |
| Structure destruction (burn, ruin) | pending | no | `PainterBuildings.take/set_burn/drop` exist; no event drives them on main; branch `painter-structure-fire` is in review, not merged |

## Water, fire, sky, weather, tokens, UI

| Class | Painted form | Status | How (verified in code) |
|---|---|---|---|
| Rivers, ponds, falls, GLB `-water` meshes | yes | yes | `PainterWater` swaps the shader of the two shared materials (`water_material`, `fall_material`) |
| Splash, ripple, dust, sparkle bursts (`splash_burst`, `dust_burst`, `sparkle_burst`, water_zone) | no | no | no look switch in these scripts |
| Fire: event puffs, smoke, ground burn | yes | yes | `FireVariants` edits of the three shaders; painted ground takes the fire bake (`mirror_glow`); painted trees burn |
| Fire flames (`fire_flames`) | shared | yes | already a 12 Hz flipbook, same in both by decision |
| Sky, sun, ambient, glow, fog colour | yes | yes | `PainterScene`: painter_sky, five moods; fog presence stays the preset's |
| Eye-view sky and skirt fade | yes | yes | `EyeSky`, `skirt_backdrop.gd` reads the painted sky |
| Weather particles and fog overlay (rain, snow) | no | no | `weather_renderer.gd` has no look switch; only the fog colour follows the mood |
| Indoor and effect presets (indoor_neutral, both dungeons, cave, tavern, underwater, hell, ethereal, none, bright_editor) | none | no | `MOOD_FOR_PRESET` maps them to "": the whole level always draws Classic |
| Pack tokens | yes | yes | `TokenToon`, its own Settings row (`token_shading`, default painted), same in both looks |
| Avatar tokens (figurine) | shared | yes | `avatar_figure` shader, one form for both looks |
| Token ghost, covered-token pins | yes | yes | `TokenGhost.painted` wash parameters |
| Grid overlay, measure tool, selection glow and indicator, pings | shared | one form | no look switch (`grid_overlay`, `selection_glow`, `selected_indicator` shaders); how they read on the painted ground is not verified |
| Post effects (pixelate, lofi, sharpen) | shared | one form | player options, not look classes |
| In-game UI | yes | yes | the painted theme is its own system (paper, glass), not tied to Look |

## Ranked gaps (visibility at tabletop zoom and eye level)

1. **Indoor and effect presets always Classic (H, whole level).** Nine presets (dungeons, cave,
   tavern, hell, underwater, ethereal) never get a mood, so every such level draws Classic, and
   Classic cannot be retired while they exist. Not an asset class but the largest single
   Classic surface. Needs a mood design per preset (a look decision), not an asset card.
2. **Legacy GLB maps: CLOSED 2026-11-18 (card painter-glb-parity, `PainterGlbMap`; docs/systems/painter.md
   "GLB maps").** An imported `map.glb` now gets painted ground (zone read from the baked albedo),
   painted trees (scatter chunks become PainterTrees rows), plant and solid stand-ins for the other
   scatter species and painted props by material or node name. What it leaves as authored (lights,
   glass, ironwork, unnamed textured surfaces, multi-surface terrain, no skirt and no contact pools
   on GLB ground) is listed there. Verified by render on a test-only fixture world, not a real
   Blender map.
3. ~~**Settlement furnishings and `decor_baked`**~~ CLOSED (card painter-village-parity,
   2026-11-18): `PainterVillage`, `painter_prop.gdshader`; `docs/systems/painter.md` "Village
   furnishings". Left Classic by decision: glass, glow, water; the non-bakable decor MultiMeshes.
4. ~~**Field plants**~~ CLOSED (same card): `AuthoredFieldPlants` is a plant source of
   `PainterSurfaces` and `PainterTrees`.
5. **Weather and bursts (M, only while active).** Rain and snow particles, splash, dust and sparkle
   bursts have no painted form; falling snow over a painted winter is the most visible. Small
   shader cards, but the look judgement (stepped, brush-edged particles) is the work.

Below the line: round and profile roofs and Taper pieces (M, a few landmarks, needs procgen
records), panes and metal (L, by design), user-library fallbacks (L), grid and selection overlays
(L, shared UI).

## Could not verify without a render

- Anything about how a Classic-form class reads next to the painted ones (the seam, not the code).
- Legacy GLB maps: only the binding code was read; no GLB map was loaded.
- (Settled by painter-village-parity: `AuthoredFieldPlants` resolves its own meshes, not the scatter's.)
- The clipmap's far ground under Painted and eye-level read of the overlays (grid, pings, measure).
- Round and profile roofs: status is taken from the docs and matrix, procgen was not re-read.
- macOS and AMD/Intel (see `painter-roadmap.md` open items); Linux only via llvmpipe.
