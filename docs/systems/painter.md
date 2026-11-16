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
| `PainterBrushes` | `painter/painter_brushes.gd` | The ground's three brush-mark layers; the generator, loaded baked (below) |
| `PainterBaked` | `painter/painter_baked.gd`, `painter/baked/*.res`, `tools/bake_painter.gd` | The brush masks and tuft layouts as saved images, loaded instead of drawn (see "Baked textures") |
| `PainterWarmup` | `painter/painter_warmup.gd` | Compiles the painter's shaders and pipelines on worker threads before the first Painted draw (see "Warm-up") |
| painted ground, plant, solid | `painter/shaders/painter_ground.gdshader`, `painter_plant.gdshader`, `painter_solid.gdshader` | The ground's block-in and marks; the selector light on swaying and on still scatter (`painter_selector.gdshaderinc`, `painter_noise.gdshaderinc`) |
| `PainterTreeSpecies` | `painter/trees/tree_species.gd`, `species.json` | Which scatter trees are grown (asset table), each species' form data, a row's age, openness and seed |
| tree generator | `painter/trees/tree_skeleton.gd`, `tree_crown.gd`, `tree_growth.gd`, `tree_base.gd`, `tree_mass.gd` | `PainterTreeGrowth.tree(...)`: the skeleton and crown masses of one tree (the spike's family14) |
| `PainterTreePack` | `painter/trees/tree_pack.gd` | A tree's masses packed as data texels for the painted tree shaders (the spike's PPainter13) |
| `PainterTrees` | `painter/trees/painter_trees.gd` | The painted trees' host: grows, installs and draws the mapped tree rows, hides and restores the GLB trees |
| tree tones, meshes, brushes | `painter/trees/tree_tones.gd` (+ `tree_roles.json`), `tree_meshes.gd`, `tree_brushes.gd` | The palette and role_params textures, the shared instanced blocks, the 14 brush layers |
| `PainterConiferVariants` | `painter/trees/conifer_variants.gd` | A conifer's needle variants (extra evergreen style rows) and the neighbour-aware pick of one per tree |
| painted tree shaders | `painter/shaders/painter_tree_stroke.gdshader`, `painter_tree_blockin.gdshader` (and their `_bare` variants, one body each: `painter_tree_{stroke,blockin}_body.gdshaderinc`), `painter_tree.gdshaderinc` (+ `painter/trees/tree_uniforms.json`) | The spike's stroke and block-in passes on tt-sim's wind, sun and fades |
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
texture (`PainterSurfaces.zone_image`, RGBA8 per map cell, box-blurred; about 43 ms on a 245 x 245
map, was 144, and it runs on every Painted level load and ground edit) holds the meadow share,
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
texture's teeth but by four round dabs laid on each card as a mound (`tuft_dab`,
painter-plants-fix3): the outline is their upper arcs with a brushed rim, each dab darker at its
foot and its own value and variant. The layouts are drawn once, not tested per fragment
(painter-cost-stripes): `PainterTuftAtlas` (`painter/painter_tuft_atlas.gd`) draws 16 of them into a
texture array (32 px a layer: the cut as a distance field, the dab's hash, the point's place in its
dab), one array per tuft aspect rounded to powers of 1.35 (core's 13 meadow aspects make 4, about
30 ms each on the first painted look), and PainterSurfaces sets it on every wide grass stand-in
(`tuft_atlas`). The vertex stage picks a card's layer from the tuft's seed and the card's
direction (`tuft_card`); the fragment reads it in one fetch and never fetches the tuft's own
texture, so a card costs what the texture's cut did. Why: the dab test in the fragment, from three
flat vec4 varyings a card, cost 0.10 to 0.13 ms at the village's home view even with the test
skipped at run time (its presence alone, measured by a run-time switch in one shader), the
varyings 0.05 more in winter; running it, the early discard and the forced alpha cost nothing.
The distance field also rounds the rim's points (the per-fragment dabs read as pointed leaves at
eye level). Flowers keep their texture's petals.
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
spheres of 16 x 9, 10 stroke slots; no limb ribbon), never in a tree's eight neighbouring forms, and
the tree row's texel 3 w is 2 (a bush thins as a crown does, never as wood). Measured against the
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
(The ring-of-clumps layout above is superseded by painter-look-bushes round 3 below; the `shell`
switch is gone, `PainterTreeBush.clump_roots` stays as the pad-roots switch.)
Berry and flowering bushes are their own species rows (`bush_berry`: `Bush_BerryBush`;
`bush_flower`: `Bush_FloweringBush`, `Bush_BushWithWildflowers`, which were plant cards before;
`PainterTreeSpecies.BUSHES`) whose leaf strokes carry round trim-colour marks in bunches (red
berries, rose flowers), as the rowan's berries. Cost against b684d777 (painter-plants-fix4: the
tip's plant, selector and solid shaders and the small layout swapped in at run time, interleaved
A B A B, 1920x1080, vsync off, GPU medians): village home summer +0.17 to +0.20 ms, home winter
+0.13 to +0.15, eye summer +0.00 to +0.01, eye winter +0.01 to +0.04; forest tokens summer and winter
+0.00, forest home summer +0.04 to +0.07. The bushes cost nothing (tip shaders with the new layout:
+0.00 at village home summer); all of the excess was the tuft path. painter-cost-stripes bisected it
(one sitting, the plant shader swapped at run time: tip, tip on the branch's selector, plus the
varyings, the branch with the dab test skipped by a uniform, without the early discard, without
the forced alpha): the step is the dab test's presence in the shader, not its running (see
"Surfaces": the dab layouts are now `PainterTuftAtlas`' texture array). After it, against
b684d777's plant shader: village home summer +0.02 to +0.05, home winter +0.00 to +0.03, eye
-0.01 to +0.02, forest tokens and home +0.00.

A bush's clump is shaded with a dab edge (painter-cost-stripes): its tone steps ran as straight
parallel bands across each smooth pad (striped beach balls at every zoom). The block-in marks a
bush's masses (`v_bseed` 2 from the row's texel 3 w) and gives them the same one noise at a dab's
size (`BUSH_DAB_F` 4.6 per metre) as strong as a stroke's tone jitter (`BUSH_DAB_JIT` 0.7), so
light and shade meet in a broken, scalloped edge; the snow cap's edge takes the same noise
(`BUSH_SNOW_JIT` 0.9) and breaks into a cluster of white dabs, not one flat ellipse. Oaks and the
other crowns are unchanged; forest tokens summer 20: old block-in 4.649 / new 4.614 ms (no cost).
Open: the patches read a little as camouflage blotches at token zoom (larger than a stroke), and
winter bushes carry little snow at sun 45.

painter-look-bushes (look-pending, two rounds): a bush's block-in keeps its lit plane, but its
tone wobble is a few broad lobes (`BUSH_DAB_F` 1.8 per metre, jitter 0.8), so light and shade meet
in big soft scallops, not mottle (round 1's dark under-mass cap lost the sunlit mass and is
gone); its outline breaks into ragged lobes (`BUSH_RIM_BREAK`, `BUSH_RIM_F`, camera pass, bush
masses only) and its foot is ragged under `BUSH_FOOT_H` with a bounce floor on its tone. Fewer,
larger dabs: a clump has 5 roots (6 and 4 for a small bush's dome and lobes; spacing 0.5, leaf
`stroke` 0.5, value-spread 0.06, hue-spread 14), 10 slots an instance; the forest's 65 bushes
hold 1488 roots (was 812 at 11c834b1, 2087 in round 1), against 34184 tree roots. Berry marks are
`mark` 0.32 at `mark-size` 0.62. The sheet's `bush-value` and `bush-chroma` are 0.99 and 0.95. A
bush's winter is the species' `dry-share` (tree_roles.json, 0 an evergreen) of the sheet's
`leaf-turn` toward `dry-leaf` (`PainterTreeTones._bush_dried`, hue `dry-turn`, lightness
`dry-lift`): `bush` golden ochre, `bush_flower` straw, `bush_berry` rust, each apart from the
oaks' russet and the trunks. No bush drops its leaves (no skeleton to leave a twig mass).

Round 3 (the owner: bushes "read as spheres placed on top of each other, like ice cream scoops in a
cone"): the scoops were three equal clumps round the foot and one on top, each its own form group,
so each took its own lit cap. A bush is now ONE mass (`PainterTreeBush.masses`): four unequal,
overlapping, rotated and tilted pads in one form group (`FORM` 1; the light runs across the seams as
over one mound): a wide low body (longer one way, `HEIGHT_SHARE` 0.82 of its box tall), two flank
lobes (one low and wide, one higher and smaller) and a small flat shoulder. Nothing stands on
anything, so no horizontal seam runs round it; it is wider than tall. The body takes 6 roots, the
others 4 (9 slots of `BUSH_SLOT_PER_INST` 10; an odd root count wastes a slot), and `BUSH_RIM_BREAK`
is 0.65. Forest: 65 bushes, 260 pads, 1317 roots (was 1488). Cost, interleaved, 1920x1080, vsync
off, GPU medians, painted minus classic: forest tokens summer +0.06, +0.08, +0.09 (round 2:
+0.12), tokens winter -0.53, forest home summer -0.59, home winter -1.11.

painter-look-eyebush (look-pending): at the eye view a bush shaded by another form (a crown, a rock
pile, a building: `form_occ`'s analytic shade) filled the frame as one flat deepest-teal mass, since
every shaded fragment and stroke took `crown_cast18` (0.1), the ramp's lowest step, and a bush under
the forest's crowns is shaded more often than not (measured with a debug tint on the block-in: the
near bush at eye45 was cast-flagged over its whole visible face while its light was about 0.7, and
its strokes, with the block-in hidden, were 300 px dabs of one tone). A bush's shade is now a value
structure: `bush_cast_tone(q, n_y)` (painter_tree.gdshaderinc) gives the deepest step on the
underside, deep and mid teal in broad lobes on the sides and a mid sky-lit teal on the tops, with
q the block-in's dab wobble (`wob`, 1.8 per metre) and, for a stroke, the same noise at its anchor
(`BUSH_CAST_F`) mixed with its own draw, so the dabs and the block-in agree. Strokes know a bush
through the pad's pack flag 1024 (`"bush"` param of `PainterTreeBush._pad`; `PainterTreePack`
header), no new texel. Crowns and rocks are untouched, and a sunlit bush is unchanged (the table
frames match). Nothing is tuned by distance: the dab size is world-metric, so a distance sweep
(0.5 to 8 m from the bush's edge) shows the same lobes with no pop between stroke levels. Tried
and dropped: breaking the shade edge by nudging `form_occ`'s origin with the lobe noise (straight
analytic shadow edges stay a slab on a near bush): any dependence of that origin on the noise cost
+0.07 to +0.10 ms in the forest views, measured, although an in-run toggle showed the nudge itself
free (a compile-level cost), so it is not in. Cost, interleaved painted minus classic, 1920x1080,
vsync off, GPU medians: forest tokens summer +0.45 against +0.45 on main in the same sitting, home
summer +0.07 to +0.12 against +0.06.

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
  log2(camera size / 13.85). The stroke levels' blocks (`PainterTreeMeshes.strokes`) are one
  triangle per stroke (UV 0..2, the fragment discards outside the unit square) and the vertex stage
  drops a mark the density, thinning or season rule removes before it derives anything
  (painter-perf-strokes: -0.10 to -0.19 ms at the tokens, forest and taiga views, -14 % camera-pass
  primitives in the village). The block-in's sphere is 6 x 3 (`PainterTreePack.ELL_SEGS`,
  `ELL_RINGS`; 36 triangles, inflated by `ELL_FIT` 1.146 on x and z to keep the volume; a bush's
  stays 16 x 9): its cost follows triangles and overdraw, not vertex work, in both passes
  (painter-perf-shadow: -0.1 to -0.4 ms at 1080p).
- The shaders (`painter_tree_stroke.gdshader`, `painter_tree_blockin.gdshader`, shared
  `painter_tree.gdshaderinc`) are the spike's final composed code, sliced, with tt-sim's wind
  globals (the gust is WindModel's field), the `foliage_sun` global for the light's direction, the
  canopy fades by whole strokes and masses (stems stay). The spike's untone is gone: the Painted tonemap is
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
  `tree_tones.gd` pattern).
- Needle variants (card painter-look-taiga, 2026-11-15; critic: the taiga's spruces were one teal
  family). A conifer species has one evergreen row, so every spruce of a level drew in one colour.
  `PainterTreeTones.row_table` now gives a conifer `PainterConiferVariants.count()` (5) evergreen
  rows (`evergreen`, `evergreen_1` .. `evergreen_4`: 8 more rows in all, of the 64), each the species' row
  moved by `SHIFTS` (hue, lightness, chroma, extra lit pull): the deep teal, a blue-green, a fresh
  yellow-green, a warm deep green and a teal whose tips turn gold (a lit pull toward the mood's
  `lit-hue`, with extra lit chroma, since a pull at the needles' low chroma read khaki). A shift
  takes the share the mood's `needle` chroma has of the summer midday's, so winter, dusk and night
  narrow the family. `PainterTrees._tables` writes one of them into each conifer's row-map column 8
  (`PainterConiferVariants.assign`: trees in key order, each takes the variant least held by the
  placed trees within 9 m, a nearer one weighing more, the seed's own on a tie), so no two near
  spruces wear the same needles. No shader changed: the row map already names the row. Painted
  summer taiga frames: `docs/research` painter_final22_taiga.
- The forest floor (`floor`, the ground role the taiga and jungle paint, and a forest's under its
  crowns) was `oklch(0.60 0.085 112)` in every mood that did not set its own: an olive-khaki that
  read dull and muddy at the taiga's home view. The summer keys set it (high `0.67 0.130 130`, low
  `0.63 0.115 112`): a luminous moss green between the meadow's green and a gold. Other moods keep
  the world's (winter and dusk set their own already). The temperate forest test map's ground frames
  (home and zoom 5) are unchanged but for its spruce.
- A bare season (card painter-winter-trees, 2026-11-13; owner: "for winter: broadleaf trees should
  move towards the prototype"). The sheet's `leaf-keep` (1 in leaf, winter 0.15) is the share of
  its leaf clumps a broadleaf keeps; each species falls by its leaf role's `fall`
  (`tree_roles.json`: oak 0.9, rowan 0.95, lime 1.05, poplar 1.1, willow 1.15, birch 1.2), so in
  winter an oak keeps about a quarter of its clumps, a rowan a fifth, a lime a tenth, a willow two
  in a hundred and a birch none; conifers and bushes have no fall. PainterTreeTones writes the drop
  ((1 - leaf-keep) x fall) into the leaf row's role_params row 6 w. The shaders decide per CLUMP
  (`tree_leaf_fallen`: a hash of the mass seed against the drop, in the stroke shader's vertex
  stage and the block-in's), so a clump's strokes and its painted shadow strokes go together and
  the stroke count is unchanged (a dropped stroke collapses to a point). A tree that drops draws
  no solid crown: its block-in leaf masses are gone in both passes (round 1 kept them: pom-poms on
  a bare tree), so the crown's solid sun shadow goes and the kept clumps' shadow strokes dapple
  the ground; a kept clump draws `TREE_DRY_STROKES` (0.45) of its strokes, drawn in toward its
  middle by `TREE_DRY_SHRINK` (0.75: at 1 a clump without its block-in read as a hollow ring, at
  0.55 as a round seed ball), with the burial test off (its neighbours have fallen). Its limbs are
  drawn in the bare wood's manner (`limb_r19` with the bare flag: twigs at least `twig_px19` wide,
  cut by `bare_limb17` 0.008 m, three times that far off) and twigs tinted toward the leaf row (the
  dry leaf), with `limb_snow17` 1 (snow ridges on level limbs, times `deposit`). Those three values
  are `tree_uniforms.json`'s "bare" section; in leaf the materials keep the leaf values (0.024, 1,
  0), so an always-bare tree in summer draws as before. The drop's code lives only in the BARE
  SHADER VARIANTS (card painter-winter-trees2): the stroke and block-in bodies are
  `painter_tree_{stroke,blockin}_body.gdshaderinc`, included by `painter_tree_stroke.gdshader` and
  `painter_tree_blockin.gdshader` (in leaf: `drop` and `fallen` are constants, the `leaf_fall`
  uniform and the drop helpers do not exist) and by `*_bare.gdshader` (`#define TREE_BARE`). With
  the drop in every season behind a uniform, the summer eye view cost +0.23 ms over the tip (its
  locals live across the whole vertex stage); with the variants, summer is tip -0.13 (eye), +0.03
  (home), +0.01 (tokens) and winter -0.54, -0.66, -1.26 ms (GPU median, 1920x1080). While
  leaf-keep is under 1, PainterTrees.retone puts the bare variants and values on the materials
  (swapping a shader only when the season changes: a swap compiles once), `leaf_fall` 1 and
  `crown_occ` 0 (a whole broadleaf crown form no longer shades its own kept clumps and limbs).
  Colours: `leaf-turn` (winter 1) turns a kept leaf
  toward the sheet's `dry-leaf` (lightness and chroma by the species' ratio to the spike's leaf,
  hue plus the role's `dry-turn`: oak -6 russet, rowan -22 red, lime 16, poplar 22, birch 24 and
  willow 28 golden). A dry leaf is thin and lit through, so its shade (`_dry_shape`, after the
  sheet's crown shade numbers) keeps `dry-shade-lift` (winter 0.15) more of its lightness
  (`shade-depth` is the share of the lightness the shade KEEPS, `PainterTones.steps`), its own
  chroma by `dry-shade-keep` (1) and pulls `dry-shade-pull` (0.3) to the crowns' shade hue, each by
  leaf-turn: winter oak shade / mid / lit #653f2a / #955f3b / #b37e4a. (painter-winter-trees took
  the lift off shade-depth: the kept clumps' shade halves baked near-black, oak #070304, and every
  larger "lift" made them darker; the crown's keep 0.6 and blue pull alone greyed the dry shade
  to mauve, #504749.) The bushes keep the sheet's leaf.
  `needle-snow` (winter 1.6) multiplies the evergreen rows' `settle`: heavier snow on the boughs.
  Autumn and summer are unchanged (leaf-keep 1, leaf-turn 0, needle-snow 1). The eye view's rim
  (`utils/eye_rim.gd`: hedges and copses on the skirt, an AuthoredScatter made on entering the eye
  view) is painted since painter-look-winter (below). Open: close up (zoom 9) a kept clump reads as a
  dense round ball of dabs, some a ring; the prototype's bare crowns carry a fine twig mass where
  ours show limbs and sparse twigs; the willow's winter look is unseen (no core map grows one
  without water: willows come only from wetland_riparian).
- Continuous wood (painter-look-wood, 2026-11-15; owner: "a branch at the very top is much
  thicker than the trunk below it", "noticeable discontinuities in the trunks/branches"). Cause,
  measured from the skeleton's own radii (`tests/unit/test_painter_tree_wood.gd` is the probe):
  (1) the block-in closed every strand to a point over the last 22 percent of its length
  (`smoothstep(0.78, 1, along)`), whatever its length, so a twenty-node trunk narrowed to nothing
  over its last four nodes under the limbs that leave it there: limbs up to 4.9 times as wide as
  the trunk at their joint (1280 where it had closed on a fork). The point now closes over the
  strand's last segment at most (`point_from`), and a strand that limbs leave from its last node
  keeps its width there (pack header flag 16, `forked`, set by PainterTreeGrowth). (2) The shader
  swelled every limb 1.6 times at its base on top of the pack's own collar, so limbs began up to
  1.47 times as wide as their parent: removed from the shader; PainterTreeSkeleton._collars bakes
  the flare (FLARE 1.6, never past FLARE_MAX 0.92 of the parent's width at the joint, a node a
  little way out, limbs of 5 cm or more) for every order. (3) The pipe model takes a heavy limb's
  whole area off the trunk at its node: the trunk above stood at 0.21 to 0.35 of the width below
  it. PainterTreeSkeleton._steady raises each strand from base to tip so no node narrows by more
  than 1 - NARROW_MIN (0.62). The bare-season minimum pixel width is not a cause: `limb_px18` and
  `limb_wide18` are 0 in every material and a twig's 0.65 px floor is under its own radius
  (0.016 m) until about 27 m in the eye view, never in the orbit view. The test checks joints
  (child at most 0.95 of the parent), the narrowing floor and the drawn width at the joint on every
  species, three ages, three seeds. Digests moved: `painter_tree_spike.json` (texels, sha) and
  `painter_tree_digests.json` re-pinned; test_painter_baked unchanged. Cost (GPU, painted minus
  classic, 3 interleaved samples, 1920x1080): forest tokens summer +0.098 ms (main +0.126), winter
  -0.521 (main -0.517), forest home summer -0.586 (main -0.596).
- Saplings, sticks, stubs and roots (painter-look-wood2, 2026-11-15; critic read of the winter wood
  frames; evidence `docs/research/2026-11-09-prototypes/compare/painter_final21_wood/notes.md`).
  Square-cut, floating pink sticks beside a dark pole were three shader causes in the block-in's
  twig manner: the dry-brush breaks (`twig_break19`) cut a stick a few pixels wide into floating
  pieces; the twig colour (the leaf's) painted every twig salmon at any size; and `thick_end` kept
  every strand blunt whose tip was over 0.4 to 0.7 of its base, which the skeleton's least widths
  made true of every sapling leader, unbranched stick and dead stub. Breaks fade by 4 px of the
  twig's base width (`w_px`; use `abs(PROJECTION_MATRIX[1][1])`: it is negative in the viewport) and
  never touch a twig's first and last eighth, the colour fades by 7 px, and only flag 16 keeps a
  blunt end. In the skeleton: a limb's least width is 0.75 of a thin parent's (`LEAST_STICK` 0.011),
  a stem's 0.012; `_forks` gives the stem's co-dominant forks the stem's width at its top (the
  straight one `FORK_LEAD` 0.72, the rest by the pipe law, tapering to `FORK_TIP`); the stem
  narrows by at most 1 - `NARROW_STEM` (0.8) per node; buttress roots are four points that bend
  down and end under the ground. Lime and poplar bark are warm (chroma 0.044) and lime has furrow
  marks. Digests re-pinned. (The seam where a trunk meets its forks was left open; painter-look-wood3
  below.)
- The trunk-to-crown ring (painter-look-wood3, 2026-11-15; evidence
  `docs/research/2026-11-09-prototypes/compare/painter_final22_wood/notes.md`). A debug tint
  (stem red, a strand's first eighth green) showed the cause: the stem strand ended in a flat,
  low dome exactly at its last node; every fork began there too, as a flared "cuff" (green) of its
  own bark pattern, with a clean straight line between them; and the old oak's stem stood at 0.54
  against forks of 0.39 and 0.23 to 0.31 (the pipe law's slender forks). Fixes: (1) a strand that
  limbs leave from its last node (flag 16, not a twig) runs on past it by half its width (vertex
  `cap_ext19`) and ends in a torn brush-end in the fragment stage (`w_cap`, in `v_form` above 3.5:
  tongues of different lengths over about 1.4 widths, a noise on the across axis) instead of the
  dome; a thick limb (radius over 0.1) starts the same distance inside its parent, hidden behind it,
  so the trunk and forks overlap in a broken edge where they met in a line. (2) `_shoulder`
  (skeleton): where two or more forks leave the last node the stem's top comes down to its widest
  fork over `FORK_JOIN` (0.9) over the last nodes (at most 1 - `NARROW_STEM` per node; the limbs
  there and what they carry are re-capped). (3) The forks after the lead share `FORK_REST` (0.9) of
  the stem's area, not what the lead leaves. (4) Variety: the fork count is the species' plus
  -1..+1 by seed and each fork's spread and length are drawn, so the flat-topped trees are not one
  umbrella; a sapling bends by seed (`young` x 3 to 7 percent of its height, a third of that on a
  whorled conifer). Per-fragment cost: one noise pair on a capped strand's tail only; the winter
  forest A/B (3 pairs) painted minus classic -0.016 ms. Digests and the spike fixture re-pinned.
- The eye view's rim (painter-look-winter): PainterSurfaces follows a scatter added to the map after
  the paint (`child_entered_tree` on the map root, `_bind_scatter`), so EyeRim's scatter gets the same
  painted plants and, through PainterTrees, painted trees and bushes (`PainterTrees.wanted` skips a
  scatter that is not `visible`, and its `visibility_changed` re-syncs: the rim's trees are drawn only
  while the eye view shows it, and cost nothing in the orbit view). Classic is untouched. The snow
  ground in winter (sheet `high` key: `ground-lit-pull` 0, `ground-lit-lift` 0.03, wider hue spread,
  lighter `ground-shade-*`): the default lit pull toward the sun's hue 95 carried the blue ground
  through green to a mint; the same numbers drive the snow on plants (`frost`) and the roofs' snow.
- Canopy: `CameraController.CANOPY_CLEARANCE` (20 m) stands over the tallest grown painted tree
  (poplar 16.74 m at age 0.95; the GLB trees reach 16 m) plus `BOUND_GROW`;
  `test_painter_trees_draw` grows every species and fails if one outgrows it. The block-in's
  crown masses fade by a world noise of about half a metre with a light screen dither on each
  piece's rim (a plain 1 px dither read as halftone grain over a token).
- A covered token in Painted (painter-look-ghost, 2026-11-15; it replaced the token fade of
  painter-look-fade, which replaced the token windows of painter-a2a4, a2a5 and trees-fix2). Painted
  cuts nothing away for a token: no stroke thins, no mass is discarded, no limb tapers, and the
  per-token occlusion fade is gone from the whole game (`docs/PERFORMANCE.md` "Occlusion fade
  removed"). Owner verdict 2026-11-15: a hole in the canopy is disorienting; players need to find and
  select their tokens. A covered token is found through the Token ghost (`TokenGhost`,
  `shaders/token_ghost.gdshader`): its silhouette reads through the strokes and block-ins because
  they are in the depth buffer like any opaque surface. Painted gives the ghost its own wash
  (`TokenGhost.PAINTED_PARAMS`, set by `LevelEnvironmentManager._publish_painted` through
  `TokenGhost.set_painted`) a warm cream wash with a dark teal rim; painter-look-ghost2
  (2026-11-15, look-pending) replaced that, in both looks, with ONE line round the outer silhouette
  of the covered part (owner: "just the outermost edges would be lined": no fill, no part edges, no
  translucent model): a dark outer line with a thin light one inside it in the token's most vivid
  non-green colour (`TokenGhost.Style.DOUBLE`; gold when selected or hovered), drawn by a mask pass
  plus a pushed-out line pass (`shaders/token_ghost_mark.gdshader`, `shaders/token_ghost.gdshader`;
  `docs/PERFORMANCE.md` "Token ghost outline"). Frames: `compare/painter_final24_ghost2/`
  (`notes.md`); the older ones `compare/painter_final20_ghost/`. Both tree shaders
  still hand their own view-space point to `tree_fades` (the canopy fades; `skip_vertex_transform`,
  VERTEX and NORMAL in view space; the block-in wrote POSITION alone before painter-a2a5, so Godot's
  VERTEX was the mesh's unit block at the tree's FOOT). `test_painter_trees_draw` checks that no
  token-thinning code or uniform is left in the include or the two bodies, and `test_token_ghost`
  checks the line variants and the mask pass. Open: a thin line over a bright crown is easy to miss
  for a small token until it is selected or hovered (the map pin, now shown at every pitch, is the
  other way to find it).
- One hand (painter-trees-polish): every broadleaf crown and the spruce paint with the oak's
  scalloped `lobed` brush (`tree_roles.json`; the lime's heart-shaped `scale`, the poplar's and
  rowan's `flick`, the spruce's `spray` and the birch's small `round` read as a second, cruder hand
  or as confetti); the birch is fewer, larger dabs in a yellow-green (the spike's lemon was the
  brightest thing on the map); the willow keeps its strands. The block-in's crown masses are spheres (8 x 5 then, 6 x 3
  since painter-perf-shadow) whose facets and polygon outline showed as flat slabs between the strokes of the
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
- Frame cost (card painter-perf-forest, 2026-11-14; table in `docs/PERFORMANCE.md` "Painted
  forest cost"): Painted is vertex-bound, not fill-bound (a quarter of the stroke area costs the
  same). At the forest tokens view the strokes are the dearest part (2.24 ms of 4.60), at the home
  views the block-in (1.25 forest, 1.79 taiga, half of it its shadow pass). Two cuts shipped: a
  stroke whose root normal faces more than 120 degrees from the camera is not built (`back10`
  -0.5 in `tree_uniforms.json`, -0.14 ms at tokens, no visible change), and a tree no token's
  fade can reach skips the token test's loops (`tree_token_near`, from the tree's box in
  `tree_tex` texels 5 and 6, `PainterTreePack.BOUND_PAD` 2.5 m).
- View cull (painter-perf-cull): the per-tree view cull of the strokes (`tree_view_box`, the
  uniform `view_cull`, default 1 in the shader; 2 draws only the trees it would cull, a
  diagnostic; 0 is off) is ON: a tree whose box is outside the view collapses in the vertex
  stage. `tree_tex` texels 5 and 6 hold the masses' own box (centre, half extents); the token
  pre-test adds `TREE_BOX_PAD` (2.5, pinned to `PainterTreePack.BOUND_PAD` by a test, as is the
  cells' `PainterTrees.BOUND_GROW`), the cull its own margin: `view_margin` (1 m) plus
  `TREE_VIEW_MARGIN_PX` (8 px of the stroke's own size, so a perspective far view gets a wider
  one). A willow's strand masses can draw strokes round their spindle outside the ellipsoid, so
  the box takes the strand cylinder and its bend in (`tree_pack.gd`, aabb only).
  `tests/unit/test_painter_trees_cull.gd` pins the box over every species, age and openness and
  a GDScript twin of the shader's extent math. The margin is not a proven bound on stroke reach
  (it rests on cull-on equal to cull-off at 0.5 m in five forest views and the village; no eye
  view was captured with it on). Forest tokens summer -0.78 ms, winter -0.40, taiga home -0.16,
  forest home -0.05 to -0.11, village -0.10. The crown-edge strokes the earlier cull seemed to
  drop were the trees' own sway: see the harness note below.
- The slot table (painter-perf-derive, -taiga, -buried; `PainterTreePack`, `PainterTreeBurial`):
  it holds the ellipsoid slots (two roots a slot, `ROOTS`; the second root is named by the y texel,
  -1 = the next root, else -(2 + root)) and the strand slots, with three things left out of it. (1) No
  bark slots while `PainterTreePack.BARK_STROKES` is false: the shipped stroke uniforms carry `wood19` = 1
  in every season, which kills every bark stroke in the shader after its derive, and those slots were
  40 % (forest) to 60 % (taiga) of a tree's instance vertices, all dead. A test pins the constant to
  `tree_uniforms.json`'s `wood19`: if `wood19` is ever turned off, flip the constant and re-pin
  `tests/fixtures/painter_tree_digests.json` (`pack(masses, seed, shadow_k, wide, bough_r, bark, bury)`
  takes the three switches; the spike port test packs with `bough_r` 0, `bark` true and `bury` false, to
  match the spike's bytes). (2) No thin bough inside a spruce's crown (`BOUGH_R` 0.1). (3)
  The roots the shader's own burial test kills (`bury10`: a root inside one of its clump's four listed
  neighbours, tested on the root's position in the tree frame before the wind, so no camera or wind
  dependence; 6 to 11 % of roots, lime 19 %) are listed by `PainterTreeBurial.dead_roots`
  (`painter/trees/tree_burial.gd`) and their slots go LAST in the table. The tree dictionary carries
  `n_slots`, `n_live` (the live prefix) and `buried_roots`; the tree row's texel 7 z holds `n_live`
  (`tree_row(..., live)`), and the stroke body's loop bound (`n_run`) reads it in leaf (texel 1 z in a bare
  season). `PainterTrees._slot_units(d)` is `n_live` in leaf and `n_slots` in a bare season: a bare
  season draws the whole table, since a kept clump has no burial test, so winter cost is unchanged by it.
  A season flip makes the stroke instances again (`_restroke()`, about 2 ms for 127 trees);
  `set_live_counts(false)` draws every slot (the A/B switch). Bushes are not split (`pack_bush`, their
  `n_live` equals `n_slots`; `BUSH_SLOT_PER_INST` 10 holds a large bush's 20 roots). `PainterTreePack.BURY_MARGIN`
  is -1 (exactly the shader's test, pixel-equal); 0 or more also lists the roots inside ANY other leaf clump
  with its axes shortened by that many metres: -0.07 ms at 0.15 and -0.14 ms at 0.0 at taiga home, but those
  roots draw today, so it is an owner look decision and off. Changing it needs a digest re-pin.
- Frame cost since (table in `docs/PERFORMANCE.md` "Painted perf round" and its "Round 2"): the stroke
  vertex stage is wave-divergence bound, so only contiguous dead runs pay (the bark slots out of the table,
  the buried roots last, the spruce's boughs unpacked). Final Painted minus Classic at main 472259bc: forest
  tokens summer +0.03 ms, tokens winter -0.54, forest home -0.55 summer and -1.16 winter, taiga home +0.65
  summer and +0.21 winter, village home -0.47 and -0.87 (3 houses), -0.27 and -0.74 (12 houses), village
  eye -1.26 and -1.88 (the taiga is the one place Painted still trails). Where the rest is: the stroke vertex stage's derive from the data
  textures (0.70 ms of the tokens view's strokes, repeated per vertex, hence the one-triangle
  block) and the block-in's shadow cast. Frame CPU is not where Painted loses (script 0.24 to
  0.31 ms and render CPU 0.6 to 0.86 ms in both looks). Dead ends: the strokes in the alpha pass
  (no depth prepass: +1.5 to +2.5 ms), the cull on the block-in (cost what it saved), skipping the
  form-occlusion ray (0.007 ms), point sprites for the strokes (slower than the triangle; declaring
  `POINT_SIZE` slows the whole shader), a shadow-only caster node, a shadow cull, a shorter shadow
  distance or a single cascade (0, or Classic gains the same), thinning the level-2 strokes
  (`thin2`: no saving).
- Measuring painted trees: the render jobs' `wind freeze` stops them since painter-perf-cold
  (`Steady.freeze_wind`, `tools/render_jobs/steady.gd`, also zeroes `wind_strength`, the painted tree
  shaders' amplitude, on each material whose shader declares it; the plants' `sway_speed` and
  `flutter_speed` as before). Two frames of one Painted state then differ over 24/255 only in the
  animated tokens (about 2157 px at tokens_20, half size); no per-material `uniform` probe step is needed.
  While `wind freeze` is on the driver freezes again before every capture, so materials made since
  (a Painted look change makes new ones) are held too.

## Baked textures

The ground's three brush masks (`PainterBrushes`), the trees' fourteen (`PainterTreeBrushes`) and the
grass tufts' five dab layouts (`PainterTuftAtlas`) are pure functions of their code; drawing them in
GDScript took about 0.5 s on the first Painted level of a session. `PainterBaked`
(`painter/painter_baked.gd`) loads them from `painter/baked/*.res` (about 0.6 MB: `ground_brushes`,
`tree_brushes`, `tuft_<size>` x 5; each array's layers stacked in one Image, the mipmaps cut again at
load), and a name with no file is drawn by the generator, so the files are a cache, never the source.
`.gitattributes` marks them `-text` (binary). The bake rule: anyone who changes a brush or a tuft
layout runs `godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/bake_painter.gd` and
commits the files, or `tests/unit/test_painter_baked.gd` (bytes and mipmaps equal the generators) fails.
The first Painted forest load in a fresh windowed process (debug) went from 3.33 to 3.36 s to 2.83 to
3.11 s.

## Warm-up

`PainterWarmup` (`painter/painter_warmup.gd`) compiles the painter's shaders before the first Painted
draw, off the main thread: a coordinator thread loads the painter scripts and the default sheet, then
six threads make one one-triangle RenderingServer mesh per (painter shader, vertex layout) on a bare
`ShaderMaterial`, which compiles the surface pipelines there (the mechanism `GraphicsWarmup` uses).
Two groups: BASE (the summer shaders and the sky) and BARE (the two leaf-drop tree shaders of a bare
season). The layouts are `LAYOUT_*` slot lists, pure data with no palette or scene state (a version
that took them from live producers segfaulted on a cold cache against the main thread loading the
same palette: do not reintroduce shared state). The script names no painter script, so loading it
compiles none.

- Who starts it: Root behind the title when the Look choice can paint (`_start_painter_warmup`,
  after the precompile and the first-launch warm-up); Settings Apply (`RenderStyle.start_warmup`).
  The title's run is LITE (`PainterWarmup.lite_title`, phase `LITE_DONE`, not ready): it loads the
  scripts and the default sheet and compiles every covered shader (`GraphicsWarmup.compile_shaders`),
  and makes no sample meshes. The one FULL run (one tiny mesh per shader and vertex layout, 6 threads)
  is made once per world, BEFORE the Painted apply: `LevelEnvironmentManager.apply_level_environment`
  sets `_world_stale`, the first Painted check after it (`_painter_warm`) calls `request(true)` and
  returns false until `is_ready`; `_apply_render_style` holds the Painted apply (`_warmup_held`, polled
  each frame), `LevelLoader` keeps the loading overlay up while `painter_pending()`, and an interactive
  switch (Settings Apply, `set_look`, the Level Editor's toggle) keeps the current look until it is
  ready. A `request(true)` while a run is on queues one more behind it (`_again`; `is_ready` is false
  meanwhile). A Classic session never loads it; a Settings Apply into a Classic level still marks the
  world stale, so the toggle requests the full run and holds the look until it is ready. Headless:
  `available()` is false and `is_ready` true, so no test sees a change. Why the order matters: a full
  run at the title followed by a second one over the level stalled the main thread 1.3 s (the workers
  against the RenderingDevice) and left the level's first draws 57 surface pipelines to compile in two
  frames of 1.0 to 1.1 s; one full run over the level's own world, finished before the apply, leaves
  none. Caches off, first Painted level: worst covered frame 1429 to 1521 ms before, 237 to 251 ms
  after; the Classic to Painted toggle 1539 to 243 ms; warm caches 207 to 213 ms (the load until the
  overlay lifts is 0.2 s longer warm, 2.3 to 2.4 s, and about 5 s cold). A second level in one session
  with the caches off still recompiles (a test-setup artefact: nothing is reused).
- Test: `tests/unit/test_painter_warmup.gd` (every `painter/shaders/*.gdshader` is in
  `covered_shaders()`, the copied shader constants equal the owners', each layout makes the format
  measured on a live level). A new painter shader must be added to `PainterWarmup`; the test fails
  until it is.
- Measured (debug build, warm caches, forest, `docs/PERFORMANCE.md` "Painted perf round"): the
  Classic to Painted switch's worst frame 764 to 831 ms -> 161 to 206 ms, the first Painted level load
  3.2 s -> 2.1 to 2.9 s, its worst covered frame 1.1 s -> 0.35 to 0.39 s. With the pipeline caches
  off (a first launch or a new driver) the first level's worst covered frame was 1.1 to 1.5 s until the
  warm-up's order changed (above: 0.24 to 0.25 s now). An exported release build was not measured.
- One-offs left on the first Painted install: the painter scripts' GDScript compile (about 0.5 s
  debug; the warm-up's coordinator thread now loads them off the main thread) and `ground+plant retone` (about 130 ms the first
  time). House builds with manner records cost +27 to 45 % in procgen's recording, not in `painter/`.

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
- **Buildings fix 4 (card painter-buildings-fix4, 2026-11-13; look-pending).** (1) The mason's
  hand: a building whose walls are at least half masonry, stone or rubble gets
  `PainterMannerMesh.hand_frame` (its centre, long axis, half size and top) in its wander field,
  and `hand_at` adds to `wander_at`, so the draw, the shadow caster, the collider and the snow all
  move alike: a lean that grows with height (0.12 m per 3 m, a slow plan noise), a bulge mid-wall
  (0.06 m), and a sag toward the long axis' ends of 0.09 m at the eave and 0.15 m at the ridge
  (piecewise in height). Those walls are cut every 1.1 m in their own plane so the hand bends them
  (`WALL_SEG_M`); their T closing is skipped (the gaps stay under about 3 mm) and the T search runs
  on the source before the cut (on the cut mesh it cost 44 ms a stone house; 27.5 ms after,
  headless). The shadow caster of a cut part is inset 4 cm along its normals so the bent draw does
  not shade itself. The shader adds quoins (irregular corner stones) on the stone pattern, a
  contact shade whose reach wanders (0.55 to 1.45 of `contact_m`) so the base line wobbles, and
  wandering courses. `PainterMannerHost.hand` is a static A/B switch. The "scalloped dark blot" at
  the slate roof's right end is the big tree's crown shadow (it stays with the building's shadows
  off and follows the crown when the camera turns), not a mesh fault; the dump shows no vertex past
  the slopes' ends. (2) Roof snow: the eave's thickness 0.12 to 0.22 m, its overhang 0.16 to 0.2 m
  and droop 0.08 to 0.1 m, the sag 0.25 to 0.4; a crown dome of 0.18 toward the middle of the run
  along the eave that fades to a hip end's apex (it stood up as spikes there); a lee of up to 0.15
  heavier (a slow swell keyed to the world, so two slopes agree at a ridge); the blanket's columns
  each 0.5 m along the eave instead of 1.2 (`PainterMannerBlanket.step_s`, a static A/B switch;
  the test house's strips 1004 triangles), with the lip's scallops one each 1.6 m. In the shader the light's steps are softer on the
  blanket (0.15 against 0.06), the lit band carries a continuous N.L modelling, the sky lifts the
  shaded blanket 0.4 toward its mid tone (the eye-level blue slab), and the fall-line hollow is
  tamed (0.17 at 0.54-0.7; the dormered house's big hollow is now a soft patch). The chimney collar
  skip of fix 3 is confirmed at full size. (3) Eye level, shader only: the ruled lines gain a
  4.5 per m wobble (0.05), the beam rim a slow wander (0.32) and a lip of wandering width.
  (4) Yard: `StructureDressingShapes.soup_dot` (the blooms) now has radial normals and paint alpha
  0.5, which marks a bloom for the yard shader: it is cut round as a blob (at 0.12, no seam), so
  the red pyramids read as soft dabs. The lime shrubs are yard props (they go with the props
  hidden), not Bush_* plants; their lit side breaks into darker leaf dabs and the seams darken
  0.7. `retone` no longer errors on the snow strips of a structure rebuilt since (a freed
  instance in a typed variable). (5) Cost (one interleaved sitting as fix 3's, tip new new tip
  per mood, the tip's shaders, `hand` off and `step_s` 1.2 at run time): new over the tip at
  home, mid, far, eye +0.05, +0.04, +0.03, +0.00 ms for 3 houses and +0.00, +0.06, +0.04, +0.03 for
  12 in summer; +0.03, +0.02, -0.00, +0.03 and +0.01, +0.02, +0.04, +0.04 in winter. Draw
  triangles of the 12 houses 47254 to 52136 (the stone walls' cuts); shadow 20342 both, shadow
  primitives identical in every measured view. Builds run on the worker pool: in-game medians
  83-129 ms with the tip's settings as high as the new (12 builds at once share the pool); install
  median 1.0-1.3 ms, max under 1.8 ms on every rebuild, but the first install after a level loads
  had one at 44.9 ms (the card's 59.8 ms): a one-time warm-up, likely the first manner material
  and its shader's threaded load, not split-timed. Open: the stone walls still read near vertical
  at the corners; a pale lit wash on the stone wall at eye level; the timber eave and braces read
  near straight. Frames: `docs/research/2026-11-09-prototypes/compare/painter_final7/`; numbers in
  `docs/plans/handoffs/painter-a1.md` "Buildings fix 4".
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
- **Houses' look (card painter-look-houses, 2026-11-15; look-pending).** A stone or slate material
  carries the leaf's ramp in `ramps` 6 to 11 (`PainterBuildings.MOSS_ROLE`), a picked slate tile
  roof uses its turf pick (slot 18): the manner shader lays moss up a stone wall from its foot in
  ragged tongues, small lichen dabs on single stones and broad ones on slate, a warm straw lit
  side on stone, and a bolder verge and ridge line on slate. A thatch tooth under snow is a short,
  ragged, snow-topped stub (no dark tip). The blanket's default hold is 0.85 and its steepness
  floor 0.8 (tile and slate roofs read thicker). Beams bow up to 9 cm (`BEAM_BOW_M`). The yard's
  leaf blobs take a softer lit top, blooms are smaller dabs and mostly snowed in winter.
- **Houses' look 2 (card painter-look-houses2, 2026-11-15; look-pending).** Shader and ramps only
  (`painter_structure_manner.gdshader`, `PainterBuildings`); no mesh, sheet or procgen change.
  (1) A slate roof (`pattern` 6, or a tile or shingle roof whose paint picks slate, which is what
  the stone house wears: its `roof_wood` is a shingle pattern with the slate tone) is laid slate by
  slate: rows 26 cm high, slates 36 cm wide and staggered, each its own value (the ramp's two
  variants), a few weathered to the shingle's brown (a picked roof's slot 12) or lichened to the
  turf's green, the foot of each row in shade and its lower edge lit; the broad lichen patches of
  the last card (they never reached this roof) are quieter (0.3). A ridge cap 0.21 m down each
  slope (edge wandering), cut every 0.6 m with a dark line under it, takes the clay's ramp (slot 0
  of a picked roof, slot 12 of a plain slate material, which gains the clay as a third role).
  (2) Plaster: its sun side leans warm and its shade cool, and a few broad washes (a 4 m by 2.6 m
  noise on the wall's own frame) push a stretch warm peach and the next cool blue, with a warm
  bounce at the wall's foot, a colour change across the wall rather than a value one (multipliers
  on the lit, mid and shade colours, as the stone's straw lit side is). (3) Chimneys are two new
  pick modes, `PICK_STACK` 6 (`chimney_masonry`, `chimney_brick`) and `PICK_CAP` 7
  (`chimney_stone`: the cap and pots), whose material carries the stone, the leaf and the clay as
  its ramps. A stack is brick (clay, 42 % of places, by a hash of where it stands, so a cap and
  its stack agree) or stone, laid in staggered bricks by world height, a pale collar a hand
  below its crown, soot under the cap and a dark foot; the cap is stone, the pots terracotta; sun
  side warm, shade cool. A stack's record frame has `u` up it, so `f.x` is its height. (4) A tree's
  shadow on a painted roof is a tint (0.55 of the shade) thinned by the brush wobble with a wide
  ragged edge (`f_cast`), not a crisp dark shape; a wall's cast edge is a little wider. Not done:
  the winter tufts at eye level (scatter plants, another card's) and the stone wall's pale
  cast-light streak (smaller, still there).
- **Houses' look 3 (card painter-look-houses3, 2026-11-15; look-pending).** Shader, the manner
  host and one mesh step; no sheet or procgen change. (0) **Per-building numbers.**
  `PainterMannerHost.building_seed(structure id)` gives two hashes (0 to 1) set on every part mesh
  and snow child of a structure as the instance uniform `bld` (the materials stay shared; a
  position hash is not stable across a building, and the parts' transforms are identity, so the
  node origin does not tell buildings apart). The shader uses `bld.x` for a door's and shutters'
  paint (a paint of timber or clay takes timber 30 %, clay 28 %, slate blue 22 %, turf green 20 %
  by building), a chimney's brick or stone (brick below 0.42), the plaster's and stone's warm or
  cool lean; `bld.y` for a wooden roof's tone (slate 40 %, shingle 42 %, turf 18 %), the stone's
  and straw's value shift (0.5 of the variant) and a tile roof's (0.2). A part with none set takes
  0.5. (1) **Slate is one painted mass, not tiles.** A broad sweep (a 5 by 3 m value noise, plus a
  smaller one) carries the colour: a lit end, a deep blue end, the clay's rose laid over its upper
  part (`mauve` 0.32), few soft row suggestions (a row's foot in shade where a row noise is high),
  a slab joint on one slate in five, lichen in streaks along the rows (0.24) and a warm patch of
  the shingle's brown as one wash; the per-slate recolour and the dash on every slate are gone (the
  shingle's dash pass skips slate). The ridge cap is 0.4 m down each slope, soft edged, one
  variant of the clay along the whole ridge, laid over the slate at 0.75 (a warm roll, not a red
  stripe); the slate's verge and ridge lines are no longer bolder than other roofs'. A slate
  roof's sun side is warm, its body and shade a bluer violet. (2) **Stone has colour.** Each
  stone leans warm sandstone to cool blue-violet by its own p_stones shift (`stone_z`), a broad
  wash (a 3 by 2.2 m noise) leans a stretch and `bld.x` the building; in the shade the joints are
  deeper and the pale stones lift further (`stony`), and the shade is a bluer violet. (3) **Winter
  roofs show their colour.** Where the snow is thin the blanket is cut away (`discard`, a ragged
  edge from two noises) and the roof piece beneath takes its own colour back (its `cover` from
  the same mask, which reads only world position and the roof frame without the accent, so the two
  agree): tongues of 0.2 to 1.1 m down from the ridge, in 15 % of the run, and ragged stretches
  along a gable's edge. Round bare patches and eave teeth were tried and dropped (holes with a
  rim, small stickers). The bare roof takes a lift of light (0.5) so a shaded patch is not a dark
  olive hole. The snow's brush washes are broad (1.3 m rows, 4.2 m cells), not 0.5 m dashes.
  (4) **Chimneys** grow in plan by `PainterMannerMesh.CHIMNEY_SCALE` 1.35 plus up to
  `CHIMNEY_VARY` 0.4 by building (stack, cap and pots about each piece's own middle, the height
  unchanged; the shadow mesh and the snow strips keep the recipe size). A brick stack keeps its red
  in the sun (the clay's lit step is a pale cream) and takes a warm or cool lean by building.
  (5) Brown roofs' own dark dabs are halved (damp stains; the tree-shadow tint is untouched);
  plaster's washes are taller (0.85 m rows) and its shade leans peach, not grey-pink. Not done:
  the slate roof's curled right edge (mesh: the verge's wander), chimney height and the snow
  plate over a grown cap (procgen's chimney size, `snow` strips), the stone wall's pale
  cast-light streak and the semi-transparent stone corner base (mesh).
- **Winter roofs show their colour (card painter-look-roofs-winter, 2026-11-15; look-pending).**
  Shader, the snow mesh and the host's snow material; no sheet or procgen change. (1) **The
  blanket carries its roof.** The snow child draws with its own material (`roof_snow`, pick mode
  `PainterBuildings.PICK_SNOW` 8, `PainterMannerHost.SNOW_KEY`), whose ramps are the four picked
  roofs' and the thatch's (30 slots: every manner material now holds `MANNER_RAMP_SLOTS`, the A3b
  and yard shaders 24). `PainterMannerSnow._roof_tones` reads each roof record's mesh kind
  (`roof_tile`, `_wood`, `_thatch`, `_slate`, `_shingle`, `_turf`) and its first vertex's paint and
  lays them in the blanket's vertex colour (rgb the paint, alpha the kind in eighths,
  `ROOF_MESH_KINDS`; strips and caps stay white = no kind); the shader's vertex step turns that
  into `v_tone` with the roof piece's own rules (tile by hue, a wooden roof's slate, shingle or
  turf by `bld.y`). (2) **No cut-away, no rim.** The blanket no longer discards: where the snow is
  thin it is drawn in its roof's ramp, feathered by the noises that thin it (`cover`), and the
  roof piece under it is plain snow again (one mask evaluation instead of two). Bare strokes: long
  tongues down from the ridge (0.25 to 1.5 m, their tips wandering, about 40 % of the run), ragged
  stretches of each gable edge, and broken dry strokes above the eave (never the lip's edge, at
  most 62 % bare). Under them `thin`, a veil (0.08 to 0.58): long soft streaks down the fall line,
  more toward the eave and the verges, through which the roof's colour shows in the whole snow. The
  snow takes a faint cast of its roof (warm over clay, thatch and shingle, cool over slate and
  turf), and where a roof shows its ramp is lifted (`bare_tint`: the straw pale cream to gold, the
  slate clearer blue, the shingle warmer). (3) **Stone** in winter takes warm sandstone on its lit
  faces and a blue-violet shade (`snow > 0`). (4) The chimney snow plate is sized to the grown cap
  (`PainterMannerMesh.chimney_growth`, shared by the mesh and `PainterMannerSnow._pads`).
  Cost (pinned A/B against the pre-card shader on the same meshes, `painter_final22_roofs/cost`):
  winter home 12 -0.04 ms, home 3 0.00, eye 0.00; summer within noise. Not done: slate is still a
  grey-blue slab with a dark band at the ridge (the sheet's winter slate is dull); the tongues'
  lower edge is a smooth wavy fade, so a roof reads as painted bands more than bare tiles; every
  tongue's colour is flat apart from a few dabs; a bare tongue keeps the blanket's rounded shading
  (it stands as a raised plateau), not the roof's plane; thatch gold leans mustard.

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
