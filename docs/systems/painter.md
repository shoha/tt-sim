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
  albedo texture for a cut-out. Trees (`PainterPlantRoles.of` returns `{}`) keep their materials;
  a tree-category asset named bush, shrub or hedge (the core forest's bushes sway as trees) is a
  leaf mass and is painted (painter-trees-polish: Classic, they stayed summer green in winter and
  black in grimdark). Logs and stumps (the `bark` role) shade with the stems' `bark-` numbers.
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
solid, flower, crown) and a tone role by the words of the asset's OWN name (painter-trees-fix2:
the biome prefix was read too, so every `grassland_meadow_summer_s1/...` asset matched "grass" and
a meadow's stones were painted as tufts); the scatter template's `flower` flag wins.
Grass and flowers light like the ground they stand on: lit unless cast shadowed or the sun is at
the horizon (no middle step for a low sun), with light and shadow read at the tuft's foot
(`LIGHT_VERTEX` dropped to the root; ground cover casts nothing, so no shadow leaves its caster).
Each tuft is darker at its base and toward its rim (`TUFT_RIM`, by the distance from its axis
over its mesh box's half width) and a step lighter or darker than its neighbours (`TUFT_STEP`),
so a bed of the core meadow's broad-bladed grass reads as rounded scallops, not one flat strip.
A wide tuft (`TUFT_WIDE`: half as wide as tall or more; core's meadow grass is three vertical cards
through its axis, UV.x across, UV.y 1 at the foot, every normal straight up) is not cut by its
texture's teeth but by `TUFT_DABS` (6) round dabs laid on each card as a mound (`tuft_dab`,
painter-plants-fix3): the outline is their upper arcs with a brushed rim, each dab darker at its
foot and its own value and variant; a card's layout varies smoothly with its direction (a stepped
hash split a card at its seam). Flowers keep their texture's petals.
Thinning is the sheet's: `keep-grass` (0.6) and `keep-flower` (0.4) in groups of a slow world
noise, both in the colour and the shadow pass (winter 0.45 and 0.25: fewer tufts stand above the
snow).

A crown-kind plant (shrubs, hedges, ferns) is lit as one rounded form broken
into lobes (`bush_lobe`, a world Voronoi) whose outline breaks between them (`bush_cut`).
Core's card-built bushes (`Bush_BerryBush`, `Bush_Bush_`: long arching leaf straps) are not drawn
here at all (painter-bushes): three shader rounds on their own cards read as splayed shards, then,
painted on an envelope with Voronoi lobes (painter-trees-fix2), as faceted artichokes, and cost
0.07 to 0.11 ms more. The painted trees' host draws them as crowns ("Trees", Bushes below).

Snow on plants: the stand-ins take the sheet's `crown-deposit` (0 but in winter) as `frost`, in the
snow's own two steps (the drift role on the ground's ramp): a tuft's dabs each take a crescent cap
(`TUFT_CAP` of the dab at full frost, its lower rim part way to the snow's shade) and its foot lies
under a scalloped bury line (`TUFT_BURY` of its height), so straw shows as scalloped bands between
snow (painter-plants-fix3: the old cap, the tuft's top by its height fraction ragged by a 3 m^-1
noise, painted the top in the ground's snow and left only the straw under a jagged line: flat
angular shards at eye level); a bush's or a leaf mass's up-facing lobes, a rock's or log's up faces.
Winter's grass is a warm straw (`grass` oklch 0.67 0.062 72) with a small lit lift and a shade
that keeps its own hue over the violet pull (`grass-shade-keep` 1.8, above 1): a muted russet in
shade, where the full pull read as grey-lilac ghosts at eye level. Its variants spread wide
(`grass-hue-spread` 22, `grass-value-spread` 0.06; the defaults 12 and 0.035 are the sheet's
plain spreads), so a tuft's dabs range from russet to pale straw.

The foliage AA swap (`WindFoliage`, the eye view's alpha-to-coverage) collects stand-ins through
`WindFoliage.META_STAND_IN`: it swaps the original wind material in their place, so a painted
material survives entering and leaving the eye view (`test_painter_surfaces.gd`).

## Trees

Card A2a (painter-a2a, painter-a2a2) draws the painted trees: under Painted the scatter's mapped
tree rows are grown by the painter's own generator and drawn by its block-in and stroke shaders in
place of the GLB trees, which come back exactly when the look leaves Painted. Grow-in motion, the
eye view's levels, rim trees, far meshes and fog are a later card's (A2b).

Bushes (painter-bushes). Core's card-built bushes (`Bush_BerryBush`, `Bush_Bush_` in
`species.json`'s asset table, species `bush`, not a grown species) are drawn by the same host as
crowns with no skeleton: `PainterTreeBush` lays a dome and two or three lobes as leaf pads (the
crowns' own `_pad` masses, one form group lit about the bush's middle) in the asset mesh's AABB at
the row's scale (85 % of it; a bush waits for its asset to resolve). Its pads take a lower root
floor (`min_roots` 6 a dome, 4 a lobe; spacing 0.7), so the village's 64 bushes hold 1001 roots,
about 63 level-1 strokes a bush. Its colour is the sheet's bush (`bush-value`, `bush-chroma` of the
leaf, `PainterTreeTones` row "bush" after the species), on a crown's ramp, so it frosts, gilds and
darkens with the trees. Bushes sit in their own 15 m cells whose nodes instance smaller blocks (4
spheres of 16 x 9, 9 stroke slots; no limb ribbon), never in a tree's eight neighbouring forms, and
the tree row's texel 3 w is 2, so the token window never takes a bush whole. Measured against the
tip's card bushes (interleaved, 1920x1080, vsync off, GPU medians): village eye -0.45 ms, home
-1.0, forest tokens -0.75 to -0.78, forest home -0.95 (before the 16 x 9 sphere; that change is
unmeasured).

painter-plants-fix3 laid a large bush (across radius 0.7 m or more) as a dark core and up to seven
clumps, eight pads; painter-plants-fix4 measured that a pad's block-in (drawn in the camera's and the
sun's passes) costs about 0.001 ms at the village's home view where a level-1 stroke costs almost
nothing, so a large bush is now four pads, one block instance: three clumps (0.52 of its radius,
0.36 to 0.9 m) standing round its foot and overlapping round its axis, and one on its top, no core,
each its own form group, so the light turns clump by clump and the snow lies on each clump's top;
3 roots a clump, 48 level-1 strokes. A small bush's lobes are their own forms too (its snow lay as
one pale lens). Village: 50 bushes, 199 pads, 2492 strokes (the tip's small layout 166 pads, 3108).
`PainterTreeBush.shell` false lays every bush small (an A/B switch; `clump_roots` likewise).
Berry and flowering bushes are their own species rows (`bush_berry`: `Bush_BerryBush`;
`bush_flower`: `Bush_FloweringBush`, `Bush_BushWithWildflowers`, which were plant cards before;
`PainterTreeSpecies.BUSHES`) whose leaf strokes carry round trim-colour marks in bunches (red
berries, rose flowers), as the rowan's berries. Cost against b684d777 (painter-plants-fix4: the
tip's plant, selector and solid shaders and the small layout swapped in at run time, interleaved
A B A B, 1920x1080, vsync off, GPU medians): village home summer +0.17 to +0.20 ms, home winter
+0.13 to +0.15, eye summer +0.00 to +0.01, eye winter +0.01 to +0.04; forest tokens summer and winter
+0.00, forest home summer +0.04 to +0.07. The bushes cost nothing (tip shaders with the new layout:
+0.00 at village home summer); all of the excess is the tuft path, and not its dab test: the same
shader with the dabs switched off cost the same (+0.15 to +0.2 at home), and moving the layout to the
vertex stage, four dabs and no sines, packing the varyings did not move it. Over the +0.05 budget at
the village's home view; open for the owner. Also open: at sun 20 and token zoom a large bush's
clumps show broad pale and dark bands with straight edges (the block-in's tone steps on each
clump's smooth pad; larger with the four-pad layout), which the strokes do not break.

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
  stems to a dark brown). Keyframed crown numbers light a crown with its mood and sun
  (painter-trees-polish): `crown-lit-lift` and `crown-lit-chroma` make the lit step lighter and
  richer where `crown-lit-pull` turns it toward the light's hue (a low summer sun gilds it, the
  last dusk sun turns it apricot, not the olive that read as summer trees on a violet floor; a
  conifer's needles take `NEEDLE_LIT_SHARE` 0.5 of the pull, a full one read khaki),
  `crown-shade-lift` keeps a dark mood's shade a step lighter (grimdark) or deepens a pale one
  (winter), and `crown-deposit` is the `deposit` uniform: the share of a crown's up side the frost
  takes (winter 0.55: snow caps on the crowns, shelves on the needles). A stem's shade depth is its species' less `bark-shade-lift` (0.1;
  painter-a2a4, with `bark-shade-pull` down to 0.04), so summer trunks read a warm mid brown with
  darker furrows rather than a near-black. `tree-cast` is the sun's cast step on a tree (`cast_amount`), lighter at
  a low sun and in the dark moods; the limbs' material takes a near-neutral cast tint
  (`PainterTrees.BARK_CAST_TINT`), since a stem stands in its own crown's shadow and the crowns'
  cool tint made it maroon. Print the ramps with a tone printer before a render (painter-a2a3's
  `tree_tones.gd` pattern). Winter's bare trees and limb snow are later: in phase 1 a deciduous
  tree keeps its leaves in winter, a frosted green with snow caps (`crown-deposit`).
- Canopy: `CameraController.CANOPY_CLEARANCE` (20 m) stands over the tallest grown painted tree
  (poplar 16.74 m at age 0.95; the GLB trees reach 16 m) plus `BOUND_GROW`;
  `test_painter_trees_draw` grows every species and fails if one outgrows it. The block-in's
  crown masses fade by a world noise of about half a metre with a light screen dither on each
  piece's rim (a plain 1 px dither read as halftone grain over a token).
- The token window (painter-a2a4, painter-a2a5, painter-token-window): the include reads
  OcclusionFadeManager's token texture and screen tiles as the plants do (the tile's list in the
  camera's pass, the plain loop otherwise), but CLEARS instead of dithering to `min_alpha`, for
  parts nearer the camera than a token (up to `TREE_TOKEN_BEHIND_LEAF`, 0.6 of the zone radius,
  behind its centre for foliage; `TREE_TOKEN_BEHIND`, a quarter, for wood: a full radius cut the
  trunk just behind a token). painter-token-window: the previous cut (every part along one
  scalloped circle at about 0.8 to 0.9 of the radius) framed the ground behind in one light state
  and read as a glass dome (a pale disc at sun 45, a dark one at sun 20, in winter and grimdark).
  Now a STROKE goes whole: its vertex stage (`tree_token_stroke`) loops the tiles under the
  stroke's screen box and collapses the quad when the stroke's nearest point lies inside the rim,
  which a world noise sets per token between `TREE_TOKEN_EDGE_LO` and `_HI` (0.76 to 0.9 R, lobes
  `TREE_TOKEN_LOBE_M` 0.9 m or half the radius for a small token) plus the stroke's own key
  (+-0.05), so the rim is a ragged run of leaf dabs. Ground shadow dabs are never cut. The block-in
  masses and limbs are cut per fragment (`tree_token_frag`) `TREE_TOKEN_MASS_PAD` (0.1) further
  out, at most the radius (the tiles are binned by it). The vertex stage computes FRAGCOORD's tile
  as `(clip.xy / clip.w * 0.5 + 0.5) * VIEWPORT_SIZE` with no row flip (measured: a flip left the
  strokes over the token). Measured against the circle at 1920x1080 (vsync off, interleaved): tokens
  view -0.18 ms, home -0.08, far -0.09; shadow and visible primitives unchanged. Still open: a small
  token cut into a trunk shows a nearly round hole (the limb is one mass).
  A tree goes whole (painter-trees-fix2, `tree_token_crown`): when a token's window reaches into a
  crown by at least `TREE_TOKEN_CROWN_SHARE` (0.5) of its radius and the crown's radius is under
  `TREE_TOKEN_CROWN_MAX` (2.6) zone radii, every stroke and block-in mass of that tree but its
  ground dabs is collapsed in the vertex stage (camera pass only; its shadow stays). The test reads
  the tree row's crown form centre and radii (`tree_tex` texels 3 and 4) against every token of the
  plain list (a crown's centre may lie outside the token's tiles), once per tree, so all parts
  decide alike. It is for a small tree in front of a large token: the window used to take a
  birch's middle and limbs and leave its fringe floating beside Venusaur, and a crown taken alone
  would leave a bare trunk. A crown much wider than the zone (the oak over Venusaur, any tree over
  an Eevee) keeps the plain rim. A bush (texel 3 w 2, below) is never taken whole: the window
  thins it stroke by stroke and cuts its pads as a crown's. Letting the whole crown
  cast (`shadow_simple` 1) was tried for the window and dropped: it shaded nothing inside it (the
  crowns' shadows fall aside at sun 45). It runs after the canopy fades and only in the
  camera's pass (the sun's pass keeps the whole crown's shadow). Both shaders must hand their own
  view-space point to `tree_fades`: the stroke shader and, since painter-a2a5, the block-in
  (`skip_vertex_transform`, VERTEX and NORMAL in view space). The block-in wrote POSITION alone
  before, so Godot's VERTEX was the mesh's unit sphere or ribbon block at the tree's FOOT: masses
  and limbs over a token were tested at the foot and stayed as dark pieces, and the canopy fades,
  the haze depth and the received sun shadow of the block-in read the foot too.
  `test_painter_trees_draw` checks the binding, the VERTEX write and both loops in every tree
  shader.
- One hand (painter-trees-polish): every broadleaf crown and the spruce paint with the oak's
  scalloped `lobed` brush (`tree_roles.json`; the lime's heart-shaped `scale`, the poplar's and
  rowan's `flick`, the spruce's `spray` and the birch's small `round` read as a second, cruder hand
  or as confetti); the birch is fewer, larger dabs in a yellow-green (the spike's lemon was the
  brightest thing on the map); the willow keeps its strands. The block-in's crown masses are 8 x 5
  spheres whose facets and polygon outline showed as flat slabs between the strokes of the
  sparser species: their outline breaks into lobes by a world noise where they turn from the eye
  (`MASS_RIM_BREAK`, camera pass only; no geometry added).
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
glow, lanterns, ornament, metal and water keep Classic (card painter-a3b, owner decision
D5: sheet-driven); the yards' dressing (props and ground skirt) has its own two painted shaders
since card painter-buildings-fix2. Since card painter-manner-b the prototype's hand-drawn manner (procgen's piece
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
  0.45) in the `drift` role's colour; both shaders share `painter_structure_common.gdshaderinc`
  for the picks and the fallback's snow patches (the hand-drawn manner's blanket and strips:
  "Roof snow with a body" below).
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
- **Roof snow with a body (card painter-roof-snow, 2026-11-13; look-pending).** Owner verdict:
  the flat winter patches had no volume. While the sheet's `roof-snow` is above 0 (winter 0.45,
  now how deep it lies) and `PainterMannerHost.snow_body` is on (the default; false is the tip's
  winter, an A/B switch), the host builds per structure on its worker `PainterMannerSnow`'s strips
  (code 9, one `MannerSnow` child that casts no shadow, wandered with the building): a rounded
  lip along every eave and verge (flush on the slope about 0.4 m in, a lit top 0.24 m proud at full
  hold, a nose 0.11 m past the edge, an underside tucked under it; thickness and reach swell along
  the edge), a ridge or hip cap per slope whose crest meets its partner's midway, a cushion on each
  chimney cap and a wedge on each window sill; thatch holds the most (1.0), turf 0.9, wood and
  shingle 0.75, tile and slate 0.7. The manner shader lays the whole roof under a blanket
  (`snow_layer`: deeper toward the ridge, in broad heaps and within half a metre of the strips,
  thinner on steep and sun-facing runs via the `foliage_sun` global, a scalloped and brushed line
  between deep and thin); where it is thin the roof's strongest strokes are bare and crisp (tile
  dashes red, slate dashes dark), elsewhere marks keep 8 %. Strips take the snow's ramp whole, lit
  by their own normals (lit top, blue underside), darker at the foot and under the nose; the snow
  ramp is now the `drift` role under the ground's ramp numbers (`PainterBuildings.snow_ramp`), the
  ground snow's strong blue shade, in both building shaders. A thatch eave's teeth stay bare
  (they read as icicles). A mood without roof snow builds and adds nothing (a test; no strips, no
  worker time, every new shader term behind `snow > 0`); a re-tone into winter builds the strips
  from the kept dress job on a worker, out of winter frees them. Triangles: 400 to 482 a house
  (stone 400, thatched 460, half-timber 480: 1,340 for the three core houses, main pass +1,336
  measured), shadow pass unchanged; strips 1.2-3.2 ms a house on the worker, install unchanged
  (1.05-1.2 ms median). Cost (one interleaved sitting, winter sun 20, 1920x1080, vsync off, order
  Classic before after after before before after Classic, after minus before per adjacent pair,
  three pairs; the sitting drifted about +0.2 ms from first to last sample): 3 houses home +0.04,
  -0.01, +0.02; mid +0.01, 0.00, 0.00; far -0.02, 0.00, +0.02; eye +0.03, 0.00, -0.01 ms; 12
  houses home +0.04, -0.02, 0.00; mid +0.07, -0.01, -0.01; far +0.01, -0.02, 0.00; eye +0.02,
  0.00, +0.02: the median of the three pairs at most +0.02 at every view, within the +0.05
  budget and the noise floor (one pair +0.07 at mid 12, its other two -0.01). Frames:
  `docs/research/2026-11-09-prototypes/compare/painter_snow/`. Open: a soft blue light patch where
  a sunlit slope sits at the lit threshold (the light's wobble, not the snow); tile's show-through
  dashes read regular in rows; no drift against chimneys or dormers yet.
- **Buildings fix (card painter-buildings-fix, 2026-11-13; look-pending).** A critic failed the
  combined look on five points; the thatch cottage is the reference. (1) Winter roofs: under the
  blanket the roof's own marks are hidden whole (`hide` 1; the 8 % left read as dirt and drew the
  thatch's course bands and ruled lines as a faint grid); `snow_layer` is replaced by `snow_thin`,
  which bares the roof's strokes only in a few broken, wavering runs just above the eave's lip
  (taller on steep or sun-facing slopes, none at the verges, where tile dashes read as flecks);
  the blanket carries its own broad washes (`p_wash`, lighter and bluer, along the eave) and its
  light turns softly (a wider light step on snow, the wobble taken from the washes). Strips: the
  eave lip overhangs 0.19 m and hangs in scallops (up to 0.09 m, about one a metre, a segment
  each 0.3 m of eave, 0.5 m of verge), the underside darker blue; ridge caps 0.28 m high, 0.5 m
  down each slope; each chimney gets a drift collar where its stack meets the roof, heaped on the
  uphill side (16 triangles). (2) Stone walls: `p_stones`, dry-brushed stones per course (each
  course its own stone length, each stone its own inset per side, an edge the dry brush breaks,
  its own tone and value from the piece's accent), a few dark joint strokes, one broad stroke
  along a course here and there. (3) Dabs and the light's wobble on a piece with a record come
  from its own frame, stretched along its strokes (along the courses on a wall, down the fall line
  on a roof) and from two separate noises, so a roof blotch is a few brushed patches without a
  ring and a tree's shadow on a wall breaks into strokes along the courses (`f_tune.y` 0.7 there);
  a roof slope's light step is a little softer and its wobble half as far. (4) Half-timber: each
  beam bows across itself up to 5.5 cm between its ends and its brushed edge wanders up to 3 cm
  (same cut, no new triangles); window frames and door cases widen by 0.6 of a beam's brush;
  plaster carries stronger dry-brush washes over a slow value drift. (5) Grimdark's flatness is in
  the crowns and the ground, not the buildings (their roles keep their colours). Triangles: main
  pass unchanged (three houses 11,842, shadow 5,098), winter strips 750-950 a house (thatched
  748, porch 752, dormered 828, hip 944), +876 visible at home for three houses over the roof-snow
  card's. Cost (one interleaved sitting, sun 20, 1920x1080, vsync off, the tip's shader against
  this one on the same meshes, order tip new new tip in summer then winter, each the mean of its
  pair): summer home/mid/far/eye +0.03/+0.02/+0.00/+0.01 ms for 3 houses, +0.00/+0.01/+0.01/+0.01
  for 12; winter -0.01/+0.00/-0.00/+0.03 for 3, -0.00/+0.01/+0.01/+0.02 for 12. Winter's eye
  overrun over Classic (+0.24 to +0.25 ms here) is not the snow: the strips and the snow terms
  switched off (`snow_body` false) cost the same within 0.01 ms; it is the hand-drawn shading
  itself at the eye. Frames: `docs/research/2026-11-09-prototypes/compare/painter_final2/`.
- **Buildings fix 2 (card painter-buildings-fix2, 2026-11-13; look-pending).** Owner verdict on
  the roof snow: thicker along the borders than in the middle, a tray. (1) Every roof slope whose
  edges are an eave, two sides (verge or hip) and a ridge or an apex lies under one blanket mesh
  (`PainterMannerBlanket`, code 10, on the snow child): 0.3 m times the material's hold and a
  steepness factor in the middle, tapering over 1.3 m to 3.5 cm at a verge and to 0.12 m times
  hold at the eave, piling 30 % toward the top, with a 25 % sag keyed to the world; its normals
  follow the grid, so the light makes the lit top and the shade rolling off toward the edges, and
  the thin edges are a little cooler (a shade from thinness). The eave has a modest rounded lip
  (0.16 m over, scallops to 0.08 m, a blue tucked underside), a verge a small roll, a ridge or hip
  one rounded crest where the two thick halves meet. A dormer's and a porch's roof pieces (no
  edges in their records) get them from their frame. Other roofs keep the lips and caps.
  Chimney collars sit on the blanket (smaller: 0.14 m, 1.4 half-widths); a strip's foot is only
  slightly darker. Under the blanket no roof mark shows anywhere (`snow_thin` is gone), so tile
  and slate dashes no longer fleck the snow. `PainterMannerSnow.blanket` false is the tip's
  strips (an A/B switch). (2) The yard's dressing is painted: its props (`painter_yard.gdshader`)
  take one of four ramps by their Classic colour (leaf, stone, timber, rose flowers), a lobe noise
  turning the light inside each faceted shape, snow caps in winter; its ground skirt and path
  (`painter_yard_ground.gdshader`) are one flat wash of the path tone with a brushed scalloped
  edge (Classic's long alpha fade read as an airbrushed warm halo), mostly gone under winter's
  snow. `PainterBuildings.paint_yard` false leaves them Classic. (3) Stone walls: a tree's
  dappled light moves its edge per stone; roof slopes and the blanket count a point as in cast
  shadow under 0.3 of the light (a twig's partial shadow drew dark X marks) and their light
  wobble is laid in patches along the courses (vertical streaks read as smears). Snow triangles
  a house (headless): thatch 700, stone 640, timber 784, hip 828, dormer 1034, porch 1422 (the
  strips were about 480-950); in the village the main pass draws 170 fewer primitives in winter
  than the strips (3 houses), the shadow pass is identical (the snow casts none). The snow builds
  in 3-7 ms a house on the worker; nothing runs per frame. Cost (one interleaved sitting,
  1920x1080, vsync off, sun 20, order tip new Classic-yard new tip, each the mean of its pair;
  indicative, shared GPU, pairs 0.00-0.11 ms apart): new over the tip at home, mid, far, eye
  +0.02, +0.04, +0.00, -0.00 ms for 3 houses and -0.00, -0.01, -0.01, -0.02 for 12 in summer;
  -0.02, -0.03, -0.01, -0.00 and -0.01, -0.02, -0.01, +0.02 in winter. The painted yard alone
  (against Classic's yard) is 0.00 to 0.03 ms cheaper in every view but two (winter far and eye
  for 12, where it is 0.06 and 0.03 dearer, within the pair spread). Open: the yard props still
  read faceted; broad pale patches along the stone courses at eye level; vertical hairlines on
  the timber and dormered houses' plaster (likely T-junction cracks at the openings,
  undiagnosed); the dormered house's chimney pad reads as a white square frame.
- **Buildings fix 3 (card painter-buildings-fix3, 2026-11-13; look-pending).** (1) Yard props:
  the yard shader no longer flips its normal by FRONT_FACING. The dressing soup's shapes wind
  the other way (their outer faces are back faces), so the flip lit and capped every prop from
  inside: its top had n.y < 0 and never took snow. The authored normals point outward and are used
  as they are. A blob (a leaf or stone prop that is not flat) takes the crown hand: it is cut
  where its interpolated radial normal faces the eye less than 0.3 plus 0.32 times a ridged-noise
  seam (a round, scalloped outline; the shadow pass cuts the same from the light), its light turns
  by a lobe noise (0.5) and its seams darken. Winter snow caps it by the radial n.y with a
  scalloped edge; stones, lids and steps cap whole, tuft blades in patches. Triangles unchanged.
  (2) Blanket: broad strokes run down the fall line (a mass noise 0.55 by 0.36 per m, dragged),
  with hollows toward the snow's mid blue (0.26) and swells warm-white (the lit tone times
  (1, 0.975, 0.9) at 0.6); the small washes are softer (0.3 dark, 0.5 light). A verge's roll
  normal turns halfway (`ROLL_TURN` 0.5) and the taper's normals lean back toward the slope's by
  `THIN_FLAT` 0.5 times its thinness, so the porch's shaded verge no longer catches a bright
  shoulder. A chimney's cushion has upright normals and its collar the slope's; a stack whose
  collar would reach past the slope's top (at the ridge, where the plane runs on into the air:
  the dormered house's "white square frame") gets no collar. (3) Plaster hairlines were
  T-junctions: a wall vertex lying inside another face's long upright edge (the half-timber
  pier edges, with Ts at the sill and head heights) moved apart from it under the wander, 4.6 to
  16.6 mm. `PainterMannerMesh._wall_ts` finds each wall vertex lying inside an upright wall edge
  of 0.5 m or more (5 cm plan buckets) and `_close_ts` puts it back on its moved edge, in the draw
  and the shadow arrays; upright gaps measure 0 after. Level Ts are not searched (all edges cost
  about 30 ms more a house); the worst level gap left is 23 mm on the half-timber plaster and
  7.8 mm at the stone walls' eaves. (4) Stone: where the stones are drawn, the wall's light dabs
  (laid along the courses) and the course wash give way to each stone's own light and dark, so a
  pale patch is one stone with brushed edges; far views are unchanged. (5) Beams: a finer rim
  wander (7 per m) and a lighter outer lip of wandering width, both close up only. Cost (one
  interleaved sitting, 1920x1080, vsync off, sun 20, order tip new new tip per mood, the tip's
  shaders swapped in at run time on the same meshes; indicative): new over the tip at home, mid,
  far, eye +0.04, +0.01, +0.01, +0.02 ms for 3 houses and +0.00, +0.00, +0.02, +0.01 for 12 in
  summer; -0.00, -0.02, +0.00, -0.00 and +0.01, +0.01, -0.00, +0.01 in winter. Primitives and
  draw calls are identical in every view, main and shadow. The T search adds 1-7 ms a wall mesh
  headless (half-timber plaster 15-23 ms against 13-16); nothing runs per frame. Open: level T
  gaps; a diagonal pale cast-light streak across several stones at eye level; the beams still
  read near straight at eye distance; the red bloom spikes stay small pyramids. Frames:
  `docs/research/2026-11-09-prototypes/compare/painter_final5/`; numbers in
  `docs/plans/handoffs/painter-a1.md` "Buildings fix 3".
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
