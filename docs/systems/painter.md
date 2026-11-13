# The painted look

The painted look draws a level in the painter's style: one sheet of tones, chosen together, owns
the light, and later the ground, plants, trees and buildings. It ships beside Classic, the game's
usual look, which stays the default and the fallback for weak GPUs and for presets no mood paints
yet (owner, 2026-11-12). Phase 1 card A1 (painter-a1) landed the light; card A1b paints the
ground and the GLB scatter (plants, rocks, logs); cards A2 and A3 grow the painted trees; card A3b
paints the buildings' walls, roofs and timber from the sheet (owner decision D5, 2026-11-12).
The plan is `D:/dev/tabletop/docs/research/2026-11-12-painter-integration-plan.md`; the spike it
came from is the local branch `painterspike` (handoff `docs/plans/handoffs/painterspike.md`).

## What exists

| Piece | File | What it does |
|---|---|---|
| `RenderStyle` | `painter/render_style.gd` | The effective style: the Settings choice, the level's `look` field, the preset-to-mood table. Tiny, and the only painter script the start-up compiles |
| `PainterSheet` | `painter/sheet.gd` | Parses, lints and compiles a `.sheet`; the pure resolver `tone(sheet, mood, role, elevation)`, `number(...)`, `tones(...)`; OKLCH helpers |
| `core.sheet` | `painter/sheets/core.sheet` | The shipped tones: moods summer, dusk, grimdark, winter, autumn |
| `PainterScene` | `painter/painter_scene.gd` | The scene host: takes the level's Environment and sun under Painted, restores them exactly when it lets go |
| painted sky | `painter/shaders/painter_sky.gdshader` | A sky shader: horizon to zenith, a glow toward the level's sun, the far ground below the horizon |
| `PainterTones` | `painter/painter_tones.gd` | The pure tone ramp: a role's shade, middle and lit colours in two variants |
| `PainterSurfaces` | `painter/painter_surfaces.gd` | The surface host: swaps the ground's and the scatter's materials for painted ones and back |
| `PainterGroundRoles` | `painter/ground_roles.gd` | The pure surface-id and biome-id to ground-role table (meadow, floor, path, rock, shore) |
| `PainterPlantRoles` | `painter/plant_roles.gd` | The pure asset-id to plant kind and tone role table; trees get none |
| `PainterBrushes` | `painter/painter_brushes.gd` | The ground's three brush-mark layers, built once in code |
| painted ground, plant, solid | `painter/shaders/painter_ground.gdshader`, `painter_plant.gdshader`, `painter_solid.gdshader` | The ground's block-in and marks; the selector light on swaying and on still scatter (`painter_selector.gdshaderinc`, `painter_noise.gdshaderinc`) |
| `PainterTreeSpecies` | `painter/trees/tree_species.gd`, `species.json` | Which scatter trees are grown (asset table), each species' form data, a row's age, openness and seed |
| tree generator | `painter/trees/tree_skeleton.gd`, `tree_crown.gd`, `tree_growth.gd`, `tree_base.gd`, `tree_mass.gd` | `PainterTreeGrowth.tree(...)`: the skeleton and crown masses of one tree (the spike's family14) |
| `PainterTreePack` | `painter/trees/tree_pack.gd` | A tree's masses packed as data texels for the painted tree shaders (the spike's PPainter13) |
| `PainterTrees` | `painter/trees/painter_trees.gd` | The painted trees' host: grows, installs and draws the mapped tree rows, hides and restores the GLB trees |
| tree tones, meshes, brushes | `painter/trees/tree_tones.gd` (+ `tree_roles.json`), `tree_meshes.gd`, `tree_brushes.gd` | The palette and role_params textures, the shared instanced blocks, the 14 brush layers |
| painted tree shaders | `painter/shaders/painter_tree_stroke.gdshader`, `painter_tree_blockin.gdshader`, `painter_tree.gdshaderinc` (+ `painter/trees/tree_uniforms.json`) | The spike's stroke and block-in passes on tt-sim's wind, sun and fades |
| `PainterBuildings` | `painter/painter_buildings.gd` | The buildings' host: stand-ins on the structures' wall, roof, timber and stone parts, toned from the sheet, and back |
| painted structure shader | `painter/shaders/painter_structure.gdshader` | The selector light on a structure part: three sheet tones, a pattern per material, dabs, fold ink |

`LevelEnvironmentManager` owns one `PainterScene`, loaded by path (`PAINTER_SCENE`) the first time a
level is drawn Painted, so neither the start-up nor a Classic level compiles the painter
(`test_boot_graph.gd` checks that only `render_style.gd` of `painter/` is in the start-up graph).
`.sheet` files ship through the export presets' `include_filter` (`painter/sheets/*.sheet`).

## The switch

The effective style, `RenderStyle.resolve(look, preset, choice)`:

1. The local Settings choice, Settings > Graphics > Look (`graphics/look`, `RenderStyle.choice`):
   Classic (the default) or Painted overrides every map; Map's choice follows the level.
2. The level's `look` field, `LevelData.look`: `{}` (Classic) or `{"style": "classic"|"painted",
   "sheet": "" (core), "mood": "" (the preset's)}`. It travels in the level dict like
   `environment_preset`, so a late joiner gets it in the level snapshot. There is no authoring
   control for it yet; a map's look is set in its level data.
3. The environment preset: `RenderStyle.MOOD_FOR_PRESET` maps each of the 18 presets to a mood, or
   to "" for the indoor and effect presets (indoor_neutral, both dungeons, cave, tavern,
   underwater, hell, ethereal, none, bright_editor); those always draw Classic. A look's own mood
   wins over the preset's. `test_render_style.gd` asserts the table covers every preset.

Painted is visual only: it changes no state that play, collision or the network read, and a peer
on Classic sees the same map in the other look. The Settings row is per player and never
networked. The quality presets (`QualityPreset`, [graphics_quality.md](graphics_quality.md)) do not
set the Look row; a tier that forces Classic on weak GPUs is card A5's.

## Who owns the light

Owner, 2026-11-12: time of day, the sun controls and the 18 presets stay user controls; the
sheet interpolates tones by sun height per mood; the painted renderer reads the sun, never the
other way round.

Under Painted, `PainterScene.take` writes, from the mood's tones at the level sun's elevation:

- the sun's colour and energy (`sun`, `sun-energy`), and `shadow_blur` 1.0 (at the level sun's
  2.0 the soft filter detaches the shadow of a thin overhang by about 0.25 m: the spike's eave
  probe, 2026-11-12; `SUN_SHADOW_BIAS` and `SUN_SHADOW_NORMAL_BIAS` are not touched);
- the sky: `BG_SKY` with the painted sky (`sky` the zenith, `horizon`, the sun's colour as its
  glow, the far ground below the horizon: `ground` pulled 45 % into `haze` in OKLab), which is
  also what the ground skirt fades into (`SkirtBackdrop`, the `painter_sky` meta);
- the ambient light, from colour (`ambient`, `ambient-energy`);
- the tonemap: linear, exposure 1, white 1, so a sheet colour reaches the screen as written;
  glow, SSAO and colour adjustments off;
- the fog's colour (`haze`). Whether there is fog, and how dense, stays the preset's and the
  weather's (weather fog and the eye view are card A4).

The sun's direction, shadows on or off, softness, darkness, the time of day and the map's own
lights stay the level's. The Classic sun colour and energy controls do nothing under Painted.

Events, not polling: the manager releases the painted state before each Classic write and takes
it again after, in `apply_level_environment`, `apply_environment_settings` (the preset or its
overrides), `apply_sun_settings` (the sun, the time of day) and `apply_rendering_toggles` (also
the way a Settings Apply reaches the live map), plus `apply_render_style()` and `set_look()`.
Because what `take` remembers is always the Classic state, leaving Painted puts every property
back to the bit (`test_painter_scene.gd` compares every stored Environment and DirectionalLight3D
property before and after a round trip). The foliage sun (`FoliageLight`) and the water and
figure ambient uniforms are re-published after each change.

## The sheet

Text in the spike's dialect: `/* comments */`, `name: value;` declarations, colours as
`oklch(L C H)` (L may be a percent) or `#rrggbb`, `var(--token)` references to tokens set in a
`:world { }` block (top level, or inside a mood to override).

```
:world { --meadow: oklch(0.72 0.135 131); }
@mood summer {
  @key high 60 { sun: oklch(0.98 0.022 92); sun-energy: 1.05; ... }
  @key low 6 { ... }
  @key night -8 { ... }
}
```

- Moods: `PainterSheet.MOODS` (summer, dusk, grimdark, winter, autumn); a sheet must define each.
- Keyframes: `high`, `low`, `night`, each with its sun elevation in degrees, ascending from night
  to high. Every keyframe sets every role.
- Colour roles (`COLOR_ROLES`): `sun`, `sky`, `horizon`, `ambient`, `haze` light the scene;
  `ground`, `leaf`, `bark`, `stone`, `path` and the roofs `roof-clay`, `roof-slate`,
  `roof-shingle`, `roof-turf`, `roof-thatch` are for the painters of later cards (roof tones are
  named entries, never a hue the code classifies). Numbers (`NUMBER_PROPS`): `sun-energy`,
  `ambient-energy`.
- Resolution: the two keyframes either side of the elevation, smoothstep in elevation, blended in
  OKLCH (lightness and chroma straight, hue the short way round; a near-grey end, chroma under
  0.02, takes the other end's hue). Past the end keyframes the end holds.
  `test_painter_sheet.gd` walks every mood and role from -20 to 90 degrees in quarter-degree
  steps and fails on any step over 0.02 in OKLab (about one just-noticeable difference).
- The lint (`PainterSheet.lint`) rejects unknown moods, unknown roles, missing moods, keyframes or
  roles, keyframes out of order and values that are not colours or numbers. `load_sheet` refuses
  a sheet that fails it.

- Defaults (`DEFAULT_ROLES`, `DEFAULT_NUMBERS`): the surfaces' other tones (`floor`, `shore`,
  `grass`, `drift`, `litter`, the four `flower-*`) and numbers (the tone ramp, the ground's own
  ramp, the plants' steps and thinning, the ground's marks). A keyframe may set one; else the
  mood's `:world` block, else the sheet's `:world` (which holds the summer day's). The lint
  rejects a name in a `:world` that is neither a `--token` nor a default.

Every mood has all three keyframes (card A1b authored dusk's, grimdark's, winter's and autumn's
`low` and `night`); `PainterSheet.HIGH_ONLY`, the lint's allow-list for a mood with one keyframe,
is empty.

## Surfaces

Under Painted, `PainterSurfaces` (owned by `LevelEnvironmentManager`, loaded by path the first
time a level is drawn Painted) swaps materials on the live map and swaps them back exactly:

- The ground: every `TerrainChunk*` and the `TerrainSkirt` get a `material_override` of the
  painted ground shader (the skirt melts into the painted sky's far ground). The stored override,
  null included, goes back on release.
- The scatter: each GLB species' mesh surfaces (`AuthoredScatter.resolved_species()`; every cell
  node shares its species' mesh, so one swap covers every cell). A swaying asset's wind material is
  duplicated with the painted plant shader, so wind, the fades and the grow-in come from the same
  includes and uniforms; a still one (rock, log, litter) gets the painted solid shader with its
  albedo texture for a cut-out. Trees (`PainterPlantRoles.of` returns `{}`) keep their materials.
- Chunks built later and species added later are painted as they arrive: the terrain's
  `child_entered_tree`, the scatter's `cells_applied` and `species_added`, and `ground_edited`
  (which rebuilds the zone texture). No polling, no per-frame work.

Ground roles. `PainterGroundRoles.surface_role(id)` sorts a surface id by its `_`-separated words
(first rule wins: rock, shore, floor, path, meadow; anything else is meadow), and
`biome_role(id)` sorts a biome the same way. `test_painter_surfaces.gd` checks that every core
surface resolves and that each core biome's role equals its own ground surface's. The zone
texture (`PainterSurfaces.zone_image`, RGBA8 per map cell, box-blurred) holds the meadow share,
the path share, the rock share and wet ground (shore), from the map document's base surface,
biome slots and surface weights. Real role data is still to come: a `paint_role` per surface in
the library (and a biome's role read from its ground surface) would replace the word rules.

Shade ramp. `PainterTones.steps` draws a role's shade from `shade-keep` of its own chroma plus a
pull of `shade-pull` toward `shade-hue` (the ground reads `ground-shade-keep`, grass and flowers
`grass-shade-keep`; 1, the default, is the spike's ramp). A full keep under a large pull swings a
grey role (a path, snow, a log) to a saturated shade and cancels a role opposite the shade hue to
grey; a low keep under a small pull gives every role one shade family. Card painter-a1c used it
for dusk's lilac shade (keep 0.2 on the ground, 0 on grass) and the quieter night shades.

Plant roles. `PainterPlantRoles.of(asset_id, wind_category, flower)` gives a kind (mass, grass,
solid, flower) and a tone role by asset-id words; the scatter template's `flower` flag wins.
Grass and flowers light like the ground they stand on: lit unless cast shadowed or the sun is at
the horizon (no middle step for a low sun), with light and shadow read at the tuft's foot
(`LIGHT_VERTEX` dropped to the root, the only light-point shift in the painted shaders; ground
cover casts nothing, so no shadow leaves its caster).
Thinning is the sheet's: `keep-grass` (0.6) and `keep-flower` (0.4) in groups of a slow world
noise, both in the colour and the shadow pass.

The foliage AA swap (`WindFoliage`, the eye view's alpha-to-coverage) collects stand-ins through
`WindFoliage.META_STAND_IN`: it swaps the original wind material in their place, so a painted
material survives entering and leaving the eye view (`test_painter_surfaces.gd`).

## Trees

Card A2a (painter-a2a, painter-a2a2) draws the painted trees: under Painted the scatter's mapped
tree rows are grown by the painter's own generator and drawn by its block-in and stroke shaders in
place of the GLB trees, which come back exactly when the look leaves Painted. Grow-in motion, the
eye view's levels, rim trees, far meshes and fog are a later card's (A2b).

- The host, `PainterTrees` (`painter/trees/painter_trees.gd`), is made by PainterSurfaces (by
  path) and driven by its events: paint() on a Painted state, sync() on the scatter's
  `cells_applied` and `species_added`, release() on leaving. It hides the mapped species' GLB chunk
  nodes (and any built later, by `child_entered_tree`) and shows exactly those again. New rows grow
  on the WorkerThreadPool in chunks of 12, nearest the camera first, and install about 2 ms a frame
  through one-shot `process_frame` callbacks; an erase frees the tree's row at once. The only value
  read each frame is the camera's size, for the stroke level (no zoom signal exists).
- The draw (the spike's layout): cells of 5 m, five MultiMeshInstance3D a cell on the shared meshes
  of `PainterTreeMeshes` (sphere block, round 19's limb ribbon, stroke levels 0..2). The block-in
  casts the sun's shadow (crowns cast a broad-lobed swollen shape in the sun's pass); strokes cast
  none. Both receive it as a tone step in light() (`tree_cast`: no lookup shift, only the threshold
  wiggle by the sheet's `cut`). Level l shows while |clamp(lod, 0, 2) - l| < 0.999, lod = 1 -
  log2(camera size / 13.85).
- The shaders (`painter_tree_stroke.gdshader`, `painter_tree_blockin.gdshader`, shared
  `painter_tree.gdshaderinc`) are the spike's final composed code, sliced, with tt-sim's wind
  globals (the gust is WindModel's field), the `foliage_sun` global for the light's direction, the
  canopy fades by whole strokes and masses (stems stay) and the token occlusion fade (its binding
  copied from the scatter's own tree material). The spike's untone is gone: the Painted tonemap is
  linear at exposure 1, so the palette reaches the screen as written. The eye view's levels are
  pinned off (`e_far` 1). `tree_uniforms.json` holds the summer values the spike set on every
  other uniform. The field map (`field16`) has no tt-sim source yet: a neutral texel.
- Tones (`PainterTreeTones`, `tree_roles.json`): one style row per species role (leaf, bark, trim,
  a conifer's evergreen), plus the deposit and the ground; each keeps the spike's own colour and
  moves as the sheet's role (`leaf`, `bark`, the default role `needle`, keyframed per mood) stands
  from the spike world's colour of that role: lightness and chroma by ratio (a chroma gain by its
  square root), hue the short way, so species never share one green, a dark mood narrows their
  spread instead of pushing the darkest to black, and every mood and sun moves them. A species
  keeps its own shade depth and lit numbers (moved from the summer midday), but its shade's hue,
  pull and keep are the sheet's: `crown-shade-hue`, `crown-shade-pull`, `crown-shade-keep` and
  `crown-lit-pull` for a crown, the mood's `shade-hue` with `bark-shade-pull` and
  `bark-shade-keep` for a stem (painter-a2a3: the spike's per-species pulls toward 305 cancelled a
  green crown to grey and swung brown bark to maroon; summer crowns now shade to a deep teal green,
  stems to a dark brown). A stem's shade depth is its species' less `bark-shade-lift` (0.1;
  painter-a2a4, with `bark-shade-pull` down to 0.04), so summer trunks read a warm mid brown with
  darker furrows rather than a near-black. `tree-cast` is the sun's cast step on a tree (`cast_amount`), lighter at
  a low sun and in the dark moods; the limbs' material takes a near-neutral cast tint
  (`PainterTrees.BARK_CAST_TINT`), since a stem stands in its own crown's shadow and the crowns'
  cool tint made it maroon. Print the ramps with a tone printer before a render (painter-a2a3's
  `tree_tones.gd` pattern). Winter's bare trees and snow loads are later: in phase 1 a deciduous
  tree keeps its leaves in winter, a pale frosted green.
- Canopy: `CameraController.CANOPY_CLEARANCE` (20 m) stands over the tallest grown painted tree
  (poplar 16.74 m at age 0.95; the GLB trees reach 16 m) plus `BOUND_GROW`;
  `test_painter_trees_draw` grows every species and fails if one outgrows it. The block-in's
  crown masses fade by a world noise of about half a metre with a light screen dither on each
  piece's rim (a plain 1 px dither read as halftone grain over a token).
- The token window (painter-a2a4, painter-a2a5): `tree_token_fade` in the include reads
  OcclusionFadeManager's token texture and screen tiles as the plants do (the tile's list in the
  camera's pass, the plain loop otherwise), but CLEARS instead of dithering to `min_alpha`: a
  fragment nearer the camera than a token (up to one zone radius behind its centre) whose screen
  offset lies inside `TREE_TOKEN_CORE` (0.75) of the zone radius is discarded, and between 0.75
  and 1 it goes by its fade key (a stroke's own key, a stem stroke's `TREE_TOKEN_STEM_KEY` 0.5, a
  mass's or limb's world-noise key), so the crown opens in a round window over the token. Every
  part clears: strokes, masses, limbs and trunks. It runs after the canopy fades and only in the
  camera's pass (the sun's pass keeps the whole crown's shadow). Both shaders must hand their own
  view-space point to `tree_fades`: the stroke shader and, since painter-a2a5, the block-in
  (`skip_vertex_transform`, VERTEX and NORMAL in view space). The block-in wrote POSITION alone
  before, so Godot's VERTEX was the mesh's unit sphere or ribbon block at the tree's FOOT: masses
  and limbs over a token were tested at the foot and stayed as dark pieces, and the canopy fades,
  the haze depth and the received sun shadow of the block-in read the foot too.
  `test_painter_trees_draw` checks the binding, the VERTEX write and both loops in every tree
  shader.
- A grazing sun (painter-a2a4): the long bands across the floor at a 3 degree sun were
  `painter_ground`'s turned-from-the-sun step, not the trees' shadows (they stayed with the
  shadows off and the trees hidden); the step and its wiggle scale with the sun's height under
  `TURN_SUN_FULL` (0.34, sin 20 degrees), unchanged at 20 degrees and above.

- Species (`species.json`, data): the asset table, group -> species: Oak oak, Birch birch,
  Broadleaf lime, Poplar poplar, Spruce and Pine spruce, Willow willow, Sapling rowan (young).
  Acacia, Cactus, Palm and DeadTree stay GLB. Each species' form props are the ones the spike's
  sheet (`glade_ttsim.sheet`) resolved, written by the card's dump of the spike; `scotspine` is
  in the data but no asset maps to it yet. It ships through the export presets' `include_filter`
  (`painter/trees/*.json`), as the sheets do.
- A row's tree is pure in the row: the species from the asset id, the age from the row's scale
  (0.6 at scale 1, 1.2 per unit, 0.25..0.95; saplings 0.28, 0.5, 0.15..0.42), the openness from
  the biome density at the point plus a slow world noise (the spike counted neighbouring rows,
  which made a tree change when one beside it was painted), and the seed an integer hash of the
  position in centimetres. So a brush never changes a tree it did not touch, and every peer grows
  the same one.
- The generator is the spike's code (family5's helpers, family14's skeleton and crown, PPainter12
  and 13's pack), split into files under the line cap and renamed, not rewritten:
  `test_painter_trees.gd` grows 24 of the spike's own trees and compares the packed bytes with
  the spike's (`tests/fixtures/painter_tree_spike.json`, Windows bytes), and keeps a golden digest
  per species, seed and age (`painter_tree_digests.json`, snapped to 1e-4; delete it and run the
  script to write it again, deliberately).
- Visual only: nothing in play (collision, line of sight, navigation) reads a grown mass, so float
  drift between platforms moves pixels, never play.
- Cost (headless, indicative, the 24-thread dev machine): one tree grows and packs in 1 to 10 ms on
  the main thread (willow and old oak the dearest, up to 5300 texels); 107 trees in chunks of 12 on
  the worker pool take 123 ms wall.

## Buildings

Under Painted, the procgen structures (`AuthoredStructures`, the authored houses, walls and
mills) wear the painted structure shader on their walls, roofs, timber and stone; their panes,
glow, lanterns, ornament, metal, dressing and water keep Classic (card painter-a3b, owner decision
D5: sheet-driven). Since card painter-manner-b the prototype's hand-drawn manner (procgen's piece
records: wobble, lean, strokes along each piece) is drawn over that by default, and the A3b look
below is the fallback for a structure without records. The aim is the spike's route A: broad
coloured masses, a few accents, shadow-lit by the sheet's sun.

- **The host.** `PainterSurfaces` makes one `PainterBuildings`, loaded by path (`BUILDINGS`) the
  first time it paints, and hands it every painted state; `buildings()` returns it (null until
  then, so a level never drawn Painted never builds one). It follows events, never polls: the
  map's `child_entered_tree` finds a later `AuthoredStructures`, and that node's
  `child_entered_tree` dresses each `Structure_<id>` as it is built (structures are built whole
  and then added, so the parts are there when the event fires) and after every rebuild.
- **The swap.** Each part is a `MeshInstance3D` named `<role>_<kind>` (mill parts with a `cap_`,
  `wheel_` or `vane_` prefix) whose ArrayMesh surface holds the shared Classic material. The host
  sets `material_override` to a stand-in ShaderMaterial, one per kind and tagged with
  `PainterBuildings.META`, and keeps the override it found; `release()` puts that exact value back
  and disconnects. The shared surface materials are never touched. `KINDS` maps a part name to
  `[sheet role, pattern, family, pick]`; a `roof_<x>` with no row of its own (a plaster gable end)
  takes `wall_<x>`'s, and a name with no row keeps Classic.
- **Roles.** Walls: `plaster` (also adobe), `wall-stone` (masonry, stone, stone trim and
  chimneys), `wall-log`, `wall-boards` (boards, wood); brick takes `roof-clay` with the stone
  pattern. Roofs: `roof-thatch`, `roof-slate`, `roof-shingle`, `roof-turf`; a tile or wood roof
  carries the four `PICK_ROLES` ramps and the shader picks one per vertex from the recipe's
  paint colour (the spike's `_roof_tone`: grey to slate, red-orange to clay, brown to shingle,
  green to turf). Every frame, trim, opening and door of wood takes `timber`. The wall roles and
  `timber` are new in `core.sheet` (sheet `:world`, every mood's `:world` and night keyframes).
- **Tones.** `PainterBuildings.ramp(sheet, mood, role, elevation, family)` is the same two-variant
  ramp as `PainterTones` with a building family's numbers (`shape_of`): walls turn their shade hue
  by `wall-shade-turn` and take `wall-pull` (stone `stone-pull`) of the mood's shade pull, a
  `wall-shade-lift` less deep; roofs take `roof-pull` and `roof-shade-lift`; timber turns by
  `timber-shade-turn` and takes `timber-pull` (a brown pulled toward a violet shade goes through
  red to maroon). Every role takes `building-lit` of the mood's lit lift and pull (a pale wall
  under the full lift is white), and the lit step moves chroma toward `lit-hue` as a vector
  (`lit_step`), since turning a blue slate's hue toward a yellow lit hue split it into teal and
  pink. A new elevation re-tones the same materials.
- **The shader.** `painter_structure.gdshader` is the selector light (`painter_selector`'s model
  on a structure): ALBEDO white, no ambient, `light()` picks shade, middle or lit by the sun's N.L
  steps (`tone_lo`, `tone_hi` from the sheet) and steps to shade under a cast shadow. The fragment
  mixes the two variants by a world noise and adds soft dabs, and a pattern per material: roofs an
  eave band and a ridge light, thatch strands, turf tufts, broken courses for tile, slate and
  shingle; walls a contact shade at the foot, stone blocks, log seams, board joints, plaster
  streaks. Every line fades with its pixel footprint (`fwidth`), and a fold ink darkens hard
  creases. Houses still cast and receive the engine's shadows.
- **Cost.** It adds no geometry (the three test-village houses: 20 painted parts, 13 materials,
  5818 triangles). In-run A/B on the village at 1920x1080, vsync off, indicative only (shared
  GPU): painted buildings 3.84 and 4.04 ms, Classic buildings 4.03 and 4.09 ms, no measurable
  cost.
- **Accents and snow (card painter-manner-b).** A door's or shutter's tone comes from its recipe
  paint (pick 3, `ACCENT_ROLES`): wood and dull paint stay `timber`, a red or orange paint takes
  `roof-clay`, a green `roof-turf`, a blue `roof-slate`, so Classic's red doors and orange shutters
  keep an accent in every mood. Roofs lie under snow by the sheet's `roof-snow` (0 but in winter,
  0.6) in the `drift` role's colour; both shaders share `painter_structure_common.gdshaderinc`
  for the picks and the snow.
- **The hand-drawn manner (the default since card painter-manner-b).** `PainterBuildings.hand_drawn`
  (true) puts `PainterMannerHost` on every structure procgen gives manner records for; a structure
  without records keeps the look above, the fallback (false draws every structure that way, for
  an A/B). Per structure, on a worker: the records, the meshes (`PainterMannerMesh.build`: the recipe mesh cut on roofs, gables and the
  ridge every metre, every vertex moved by one smooth field per building: a lean that grows with
  height, bowing and wobbling eaves and ridges; a thatch eave's teeth; each beam cut in two or
  four along its axis and widened by a wandering brush width; a door leaf and its panels lean)
  and the collider (`PainterMannerMesh.collider`: the collision faces under the same field, the
  ones above the walls cut like the roof). On the main thread, one step a frame (about 1 ms
  each): the part's own node draws the cut mesh in `painter_structure_manner.gdshader` and casts
  no shadow, a `MannerShadow` child casts the recipe topology (wandered) only where the part cast
  in Classic (opening frames and shutters cast none), a Classic part (panes, metal) takes the
  wandered mesh in place; then the collision shape is swapped for the moved faces.
  `restore_all()` puts back every mesh, override, cast setting and shape. The shader draws the
  prototype's stroke families from the piece frame (`UV2` metres, `CUSTOM0` [u_len, v_len, code,
  accent]): ruled lines inside each face edge at least about two pixels wide (eave dark, verges
  and ridge pale), a few broad washes on plaster, broad dry marks per stone course, strokes and
  course lines on thatch, dashes on tile and slate, a beam's brush rim, a door's planks, grain
  and brace.
- **One evaluation (card painter-manner-c).** While the painted look is on (`PainterBuildings.paint`
  sets `StructureGeometry.manner_records`, `release()` clears it) `build_one` sets procgen's
  `ProcgenStructureInputs.manner` on the evaluation it already makes and keeps the records as
  parts `manner` (the mesh, digest, roles, walkable faces, cloth and mills are unchanged with the
  flag: a test builds eight recipes both ways, and the whole gate passed with it forced on;
  procgen tags the pieces with sub-paths such as `walls_3/wall/side0`, and every lookup keys on
  the node id). `AuthoredStructures.built_parts(id)` hands the host the cached parts and
  `PainterMannerSource.of_parts` reads them, so the host never evaluates again. A structure built
  while the look was Classic (or whose parts left the 48-entry cache) has no records, and
  `PainterMannerSource.evaluate` evaluates it again on the worker, the fallback. Measured
  (headless, main thread, median of 6 interleaved builds): recording adds 2-23 ms to a build
  (stone house 1.9, house_hip 5.3, thatched cottage 8.7, inn_gallery 11.2, half-timber 13.6,
  dutch_bell_house 22.9) against the 40-76 ms a second evaluation took; records 16-224 KB
  serialized a house (about a third of its mesh arrays), held only in the cache. A Classic level
  pays neither.
- **The records' new data (card painter-manner-c; look-pending).** Hip faces (`shape` hip_*) carry
  their taper (the hip's run along the eave a metre up the slope, sixteenths in CUSTOM0.w's whole
  part), so the ruled side lines follow the hips; a wall face's `course` (a boarded wall's
  `board_width`) rides in CUSTOM0.z's fraction and spaces the stone, log and board marks; flat
  roofs (code 8) get ruled lines all round and their material's marks; dormer and hood roofs
  (`roof_part`) draw as roof slopes, gallery and porch `block`s, `step`s and other fitted trim as
  boxes. A wall's trim (`side`, `proud` >= 0) stands at least 3 cm off its wall
  (`MIN_PROUD_M`, `_stand_off`), since the uncut wall strays a few centimetres from the field its
  trim follows. A door leans away from its leaf's hinge (`door_dir`). A piece with no record
  (round and profile roofs, a Taper's pieces: windmills, wizard tower, crystal spire) keeps the A3b
  patterns on the same wandered mesh, so it meets its neighbours without a seam. Look: stone gets
  scattered inset dabs on two blocks in five plus broad marks and ticks per course; slate a few
  long thin dashes; thatch strokes of uneven length and width; plaster's light washes weaker;
  beams a darker, wider brush rim; ruled lines at least three pixels and fading from 16 cm a pixel.
  Sheet: wall-stone oklch(0.80 0.042 80), stone-pull 0.3, building-lit 0.5, winter roof-snow 0.45.
  Cost: the shader dropped two 3D noises a fragment (the light's wobble and the second patch
  octave reuse the dab noise), every stroke noise is 2D (four hashes, not eight), and no stroke
  is drawn past 30 cm a pixel. Measured (one interleaved sitting, order Classic B B Classic,
  summer 45, 1920x1080, vsync off, each the mean of its pair; Classic drifted 0.00-0.08 ms
  between its samples, B's pairs 0.00-0.04 apart): hand-drawn minus Classic for 3 houses home
  +0.03, mid -0.01, far -0.01, eye +0.13 ms; for 12 houses +0.00, +0.02, +0.02, eye +0.12. The
  eye view with 3 houses stays over the +0.1 budget by about 0.03 ms (card painter-manner-b:
  +0.15), most of it the painted shading on screen-filling walls. Main pass +5,844 primitives
  for three houses (11,842 drawn against 5,998), shadow pass equal to Classic in the same pose.
  Per house on a worker: mesh build 68-71 ms median (max 90) with no second evaluation (records
  from the parts: eval 0.15 ms); install 1.0-1.1 ms median, max 2.5, but the first install after
  the look turns Painted took 35-42 ms (one frame, not investigated: likely the threaded shader
  load's wait or its first material); 0.59 MB of mesh arrays a house, about 67 KB of records.
- **Coverage (card painter-manner-c, 12 recipes, `compare/painter_manner_c/gallery/`).** Drawn in
  the manner: hip, dormered, inn gallery, barn, porch cottage, ruin cottage (rubble falls back),
  watchtower; falling back per piece without a seam: windmill_dutch (all of it, Taper), the
  roundhouse's round roof and the minka's profile roof (plain smooth straw, no strokes or teeth:
  the weakest), no broken building seen. house_flat and log_cabin were not identified with
  certainty in the frames.
- **Its cost (card painter-manner-b, one interleaved sitting, 1920x1080, vsync off, summer sun
  45, order Classic A3b B B A3b Classic, each the mean of its pair; indicative, shared GPU, the
  pairs 0.0-0.06 ms apart).** B over Classic buildings (under the painted look): home, mid, far,
  eye +0.07, +0.06, +0.04, +0.15 ms for 3 houses and +0.06, +0.02, +0.03, +0.18 for 12; over A3b
  0.00, +0.02, +0.01, +0.04 and +0.09, +0.03, +0.03, +0.07. The eye views carry most of it, and
  most of that is the painted shader itself (A3b +0.11 over Classic there). Main pass +5.8k
  primitives for 3 houses (11,842 drawn against the recipe's 5,998), +23.3k for 12; shadow pass
  identical to A3b and Classic in the same views (the probe's +1.5k came from opening parts made
  to cast). Build 67-71 ms median a structure on a worker (max 97) after the 55-67 ms
  evaluation; install 1.0-1.1 ms median (max 2.8) and the collider 0.9-1.0 ms, in separate
  frames; 0.59 MB of mesh arrays a house. Numbers and the gap probe: `docs/plans/handoffs/
  painter-a1.md` "Manner B".
- **Gaps.** Streets and settlement ground are not painted here; neither shader is in
  `GraphicsWarmup` (the manner's is loaded on a loader thread when the host is made, so its parse
  is off the main thread, but its first draw still compiles it).
- **Manner probe (card painter-manner, 2026-11-13; look-pending, default OFF).** Three ways to
  bring back the prototype's hand-drawn manner from procgen's manner records (procgen branch
  `procgen-manner`, not pinned: at tt-sim's pin there are no records and the probe changes
  nothing), behind `PainterBuildings.manner_mode` ("" = the look above; "a", "b", "c"),
  `painter/buildings/manner_*.gd` and `painter/shaders/painter_structure_manner.gdshader`. All
  three share one mesh pass (PainterMannerMesh): the recipe mesh moved by one smooth field per
  building (a lean that grows with height, bowing and wobbling eaves and ridges), roofs, gables
  and the ridge cut every metre so the field bends them, a thatch eave's teeth, per-vertex piece
  coordinates for the shader; the shadow pass keeps the recipe topology (wandered, SHADOWS_ONLY).
  A adds the strokes as geometry, B draws them in the fragment shader from the piece frame, C
  bakes the face strokes once into a texture per building. Measured on the 12-house village in
  one interleaved sitting (1920x1080, vsync off, indicative): every candidate within about
  +0.07 ms of the A3b look at home, mid, far and eye views for 3 and for 12 houses (the noise
  floor about 0.05 ms); main-pass triangles for the three test houses 1.60x the recipe for B and C,
  3.8x for A; build on a worker 40-50 ms (B, C) and 75 ms (A) per building plus a second recipe
  evaluation (about 55 ms, gone if build_one kept the records); install on the main thread about
  1 ms (B) to 2.7 ms (C, max); about 0.3 MB a building (B), 0.6 (A), 1.2 (C, the texture). Numbers,
  captures and the recommendation: `docs/plans/handoffs/painter-a1.md` "Manner probe"; frames
  under `docs/research/2026-11-09-prototypes/compare/painter_manner/`. The owner chose B
  (2026-11-13); A and C (`PainterMannerStrokes`, `PainterMannerBake`, shader modes 0, 2 and 3)
  were deleted (card painter-manner-b) and B became the default (above).

## The painted state signal

`LevelEnvironmentManager.painted_look_changed(state: Dictionary)` is emitted when the painted state
changes: `{sheet, mood, elevation}` while Painted, `{}` on leaving it (Classic, a new level, the
manager's `clear()`). It is deduplicated, so a sun or preset write that leaves the three alone does
not emit. `PainterSurfaces` follows it to paint, re-tone or release, and passes it on to the trees'
and buildings' hosts; later painters should follow the same signal rather than the manager's apply
calls.

## How to add a mood

1. Add its name to `PainterSheet.MOODS` (and to `HIGH_ONLY` only while it has one keyframe).
2. Write its `@mood` block in `core.sheet` with all three keyframes, judged by render at about 60,
   20 and 3 degrees and at night (the `painter_a1_moods` job is the template: Classic and Painted
   side by side, the village, the level's own sun controls).
3. Point the presets it paints at it in `RenderStyle.MOOD_FOR_PRESET`.
4. Run `test_painter_sheet.gd` and `test_render_style.gd`.

## Verification

- Unit: `test_painter_sheet.gd` (lint, resolver, continuity), `test_render_style.gd` (table,
  precedence, the Settings row, the level codec, the late-join snapshot), `test_painter_scene.gd`
  (take, follow the sun and the preset, the exact round trip), `test_painter_surfaces.gd` (ground
  and plant roles cover core, the paint and release round trip, later chunks and species, the AA
  swap exemption, tones and thinning from the sheet, the zone image, the signal),
  `test_painter_buildings.gd` (the swap and exact restore, re-tone, a structure built later,
  leaving Painted, the roof pick, shaded walls and timber and slate across moods),
  `test_boot_graph.gd`.
- Buildings look: card painter-a3b's job (`tools/render_jobs/local/painter-a3b/`, copied beside
  its captures in `compare/painter_a3b/`).
- Look: the render jobs of cards painter-a1, painter-a1b and painter-a1c
  (`tools/render_jobs/local/painter-a1/`, `local/painter-a1b/`, `local/painter-a1c/`, not
  committed); their captures are in `D:/dev/tabletop/docs/research/2026-11-09-prototypes/compare/`
  `painter_a1/`, `painter_a1b/` and `painter_a1c/`.
