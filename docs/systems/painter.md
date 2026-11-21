# The painted look

The painted look draws a level in the painter's style: one sheet of tones, chosen together, owns
the light, and later the ground, plants, trees and buildings. It is the default look (owner,
2026-11-16, card painter-default-flip, for everyone); Classic, the game's earlier look, stays
selectable and is still what a level on a preset no mood paints draws (first built beside Classic,
owner 2026-11-12). Phase 1 card A1 (painter-a1) landed the light; card A1b paints the
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
| painted sky | `painter/shaders/painter_sky.gdshader` | A sky shader: horizon to zenith, a glow toward the level's sun, the far ground below the horizon; at the eye, cloud banks and a far hill band (see "The eye backdrop") |
| `PainterBackdrop` | `painter/painter_backdrop.gd` | The pure eye-backdrop tones: the hill ranges, the tree-line and the clouds from the mood's own tones |
| `PainterTones` | `painter/painter_tones.gd` | The pure tone ramp: a role's shade, middle and lit colours in two variants |
| `PainterSurfaces` | `painter/painter_surfaces.gd` | The surface host: swaps the ground's and the scatter's materials for painted ones and back |
| `PainterFields` | `painter/painter_fields.gd`, `painter/shaders/painter_field.gdshaderinc` | The village fields: the soil bed and crop rows in the ground, the crops' own tone, the hedges' species (see "Fields") |
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
| `PainterWater` | `painter/painter_water.gd` | The water's host: swaps the shader of the shared water and fall materials and back (see "Water") |
| painted water, fall | `painter/shaders/painter_water.gdshader`, `painter_waterfall.gdshader` | A depth-banded wash with a stroke lattice, a shore lap ribbon and token arcs; the fall's chunky streaks |

`LevelEnvironmentManager` owns one `PainterScene`, loaded by path (`PAINTER_SCENE`) the first time a
level is drawn Painted, so neither the start-up nor a Classic level compiles the painter
(`test_boot_graph.gd` checks that only `render_style.gd` of `painter/` is in the start-up graph).
`.sheet` files ship through the export presets' `include_filter` (`painter/sheets/*.sheet`).

## The switch

The effective style, `RenderStyle.resolve(look, preset, choice)`:

1. The local Settings choice, Settings > Graphics > Look (`graphics/look`, `RenderStyle.choice`):
   Painted (the default) or Classic overrides every map; Map's choice follows the level.
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
set the Look row, and so neither does the first-run weak-GPU pick (`QualityAuto.record` writes the
four preset rows and no `look`): a weak GPU keeps the default Painted look, which measured at or
below Classic in 10 of 12 views (`PERFORMANCE.md` "Painted vs Classic"); no tier forces Classic, and
Classic is one Look row away.

**The default and a stored choice (card painter-default-flip).** `RenderStyle.DEFAULT_CHOICE` is
Painted: a fresh install, a settings file with no `look` key, and a file that only holds other rows
(a weak-GPU pick's) all resolve to Painted. Every Settings save writes `graphics/look` with the other
rows, so before the flip `look=0` sat in the file of anyone who ever pressed Apply, whether or not
they chose it, and could not be told from a chosen Classic. `RenderStyle.store` therefore writes
`graphics/look_v=2` beside the choice, and `RenderStyle.stored` reads an unversioned Classic as
the old default (Painted), a versioned Classic as a choice, and an unversioned Painted or Map's
choice as a choice (they were never defaults). Nothing is rewritten at start-up. Cost: a tester who
chose Classic before the flip and saved is switched once and picks Classic again. A map's own
`LevelData.look` loads unchanged; a new map (`AuthoringController.new_level`) carries
`{"style": "painted"}`, which only Map's choice reads. Headless runs and CI: `PainterWarmup` is a
no-op there (`available()` false), and the static `RenderStyle.choice` starts Painted, so a test
that needs Classic pins `RenderStyle.choice` itself. The painter's process-wide state (the two shared
water materials, `FireLook.glow_mirrors`, the fire and ghost painted flags, `RenderStyle.choice`,
`FoliageLight.last_sun`, the A/B flags) is put back to a fresh process's before every test script by
the GUT pre-run hook (`tests/gut_pre_run.gd`, `PainterStateReset`), so no script depends on which ran
before it (painter-test-reset: shards in reverse and rotated order, 8 and 2 shards, 0 failures). Render jobs have no Look knob: they read the
settings file of the user folder they run in, so a folder with no stored look renders Painted now.

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
texture (`PainterZoneMaps.zone_image`, RGBA8 per map cell, box-blurred) holds the meadow share,
the path share, the rock share and wet ground (shore), from the map document's base surface,
biome slots and surface weights. Real role data is still to come: a `paint_role` per surface in
the library (and a biome's role read from its ground surface) would replace the word rules.

Zone maps per edit (card painter-zone-dirty-rect, 2026-11-21). `PainterZoneMaps` keeps the zone map,
the char map and the biome zone map with their textures. A texel is a pure function of the PLAN
(`PainterZoneMaps.plan`: the grid's size, the roles' channel tables, the base surface's role, which
arrays the document has, the dominant dry biome) and the samples within `ZONE_BLUR` of it, so an
edit's `ground_edited` rectangle grown by `ZONE_BLUR` is recomputed from the samples around it and
blitted into the kept images (`update`); a changed plan, a first paint and a terrain build (the
skirt entering) rebuild whole (`build`, the same region functions over the whole grid). One
`ImageTexture` per map, shared by the ground and the skirt, updated in place; a new one only for
another size or format. `test_painter_zone_maps.gd` proves update == build bit for bit (centre,
edges, corners, overlapping edits, paint alone, a changed plan). The path slot map is rebound
only when the surface ids, the base surface or the weights changed (a copy of them is kept: a
packed array is shared by assignment in Godot 4.7, measured), and `cliff_surface` counts biome
cells natively. Torture map (245 x 245), zone work per sculpt step: 43.1 ms -> 2.7 ms on the
plain map (of the 43: zone_image 39.7, cliff_surface 4.0, shade field 1.6), 90.6 -> 3.9 ms once
a path and a forest are painted (paths 26.5 of it); a held sculpt stroke's frames median / worst
48.8 / 78.2 -> 14.0 / 37.2 ms. Still whole: a Painted load or look switch (41 ms plain, 62 ms
painted), a water edit (`refresh_water_dressing` emits the whole grid), a new surface or biome, a
dominant biome won or lost, and the path slot map on every Paint edit of surfaces (14 ms painted).

Path surfaces and cliffs (card painter-ground-surfaces, 2026-11-18; look-pending). Under the path
role every path surface painted alike, one sand-coloured stroked band, and cliff faces were the stone
role's shade, which the ground's full violet pull swings to dark purple. `PainterGroundPaths`
(`painter/painter_ground_paths.gd`):

- **Slots.** Each path-role surface of the map (the base first, then the document's surfaces; at
  most 8) takes a slot with its own tone and pattern. The tone is the sheet's `path` moved toward the
  surface's measured colour (the library's `albedo_mean_linear` as OKLCH): lightness by 0.6 of its
  difference from `PATH_REF` (about packed dirt), chroma by its ratio to 0.8 power (clamped 0.55 to
  2: at 0.35 the stone paths read cool grey-lilac), hue by half its difference as far as the
  surface has a hue; the sheet's `path-own` scales it (1). So in summer a cobble is a warm grey
  L 0.73 C about 0.035, a dirt road a tan L 0.81 C 0.08, a sandstone flag a honey L 0.84 C 0.065,
  caliche a cream L 0.88; every mood still moves them as the path. The
  pattern is the surface's kind by its words (`PainterGroundRoles.path_kind`: dirt, cobble, plates,
  tiles, gravel, planks; dirt for an unknown). The slot map (R8, nearest, the slot whose box-blurred
  weight is largest, 255 none) exists only when two or more slots are painted; else `path_only`.
- **Patterns** (`path_pattern` in the shader, the block-in only, each stone one flat colour like a
  mark): cobbles are round dabs in courses (0.38 by 0.34 m cells; a squarer dab read as brick
  courses), flagstones plates of a jittered grid
  (0.95 m, the seam where the second-nearest centre is nearly as near), tiles a 0.7 m grid, gravel
  pebble dots on a 0.2 m grid, planks 0.3 m boards along x. The courses wander with a slow warp; a
  seam is `SEAM_DARK` deeper; each stone's hash moves the path's edge, so the edge is whole stones.
  A stone under three pixels fades to the flat block-in. A path mark over a patterned path is
  dropped (one slot read for the winning mark only); the dirt kind keeps the stroked band.
- **Cliffs.** The rock role's tone is `stone` turned `cliff-turn` (-8 degrees, warmer), chroma
  times `cliff-chroma` (1.5), lifted `cliff-lift`, then moved toward the map's main biome's cliff
  surface from `CLIFF_REF` (the core grey cliff), so a badlands cliff is a pale sandstone and a
  basalt one darker. Its shade takes `cliff-pull` (0.25) of the ground's pull and `cliff-shade-lift`
  (0.12) more depth (`PainterTones.ramp`'s `pull` and `shade_lift`): a warm grey stone in shade
  (round 1, -16, 1.8 and 0.4, read rosy mauve). Under winter the stone is blue, and a badlands cliff
  followed it as a blue band on the orange ground: a mood's `cliff-own` (winter 0.85, else 0) moves
  the cliff's chroma and hue that share of the way, in OKLab's a-b plane, to the bare rock's own (the
  surface's colour as the summer cliff paints it, at the mood's lightness), so a winter face is warm
  rock under the snow. On a face
  (slope over 0.3 to 0.6) the tone steps in soft strata bands 0.6 m high by the pixel's height, each
  band's top 9 % lighter and its foot 7 % darker (`cliff-strata`); no marks are searched on a face
  (slope over 0.4: laid in XZ they stretched down it as smears). A convex rim (the mean curvature
  from the screen derivatives of the normal and position over 0.5 to 0.9 per metre, broken by a
  brush noise) takes a lit lip of `cliff-edge` (0.22) and a concave foot a darker one.
- **Polish** (card painter-ground-polish, 2026-11-19; look-pending). The lip and foot count only
  where a steep face is near (the slope, or the slope half a metre on by its own screen gradient,
  over 0.12 to 0.3): a shallow crease on a tier's top, where two strokes' round caps meet at a
  notch, bends the normal as fast as a rim but barely tilts it, and drew a thin light line there.
  The lip takes `cliff-warm` (0.5) of a gold tint; the foot (curvature 0.4 to 0.8) goes `cliff-foot`
  (0.65) of the way to its shade colour; a lit face (slope 0.3 to 0.6) goes `cliff-face` (0.35) of
  the way to its shade, a middle value under the lit top (lip and foot alone left a pale sandstone
  face a cream band on the badlands' orange). Under snow (`cliff-snow`, winter 0.85) the lip is a
  cap in the meadow's snow (a wider band, curvature 0.35 to 0.65, in two steps, so its lower edge
  scallops down the face). A path under snow (`path-dust`, winter 0.6) is lifted 0.3 of the way to
  the snow's lightness (`PainterGroundPaths.dusted`; cobble, flagstone and tiles read heavy mid
  grey), its seams 30 % shallower, and its edge beside a snowy meadow or floor dusted with the
  snow in two steps (a stone's hash moves the line).
- Cost: one slot-map fetch on path pixels only (and one for a winning path mark), the pattern's
  hashes there, the curvature's four derivatives everywhere (the polish adds two derivatives of
  the slope and, under snow, one noise); the CPU slot map only when two path surfaces are painted
  (a pass over the weights and one box blur per painted slot). Not yet timed with the pinned
  procedure (the card's bar is 0.4 ms).
- Frames: `D:/dev/tabletop/docs/research/2026-11-09-prototypes/compare/painter_final47_ground_surfaces/`
  (`after_r2/sheet_*.png`: before Painted, after Painted, Classic per row); the polish's in
  `painter_final54_ground_polish/` (`before/`, `after_r1/`, `after_r2/` full size, `sheet_*.png`).

Meadow swathes (card painter-ground-polish, 2026-11-19; look-pending). Classic's meadow carries big
gold-ochre and moss-green patches from its ground textures; the painted meadow was one calm mint
green. `PainterMeadowSwathes` (`painter/painter_meadow_swathes.gd`) gives the meadow role a few bold
soft shapes in its own tone: gold is the mood's `ground` turned `gold-turn` (-34 degrees), chroma
times `gold-chroma` (0.88), lifted `gold-lift` (0.05), never redder than `gold-hue-min` (96: dusk's
and autumn's yellow-green ground turned salmon); moss turned `moss-turn` (-6), `moss-chroma` 1.0,
`moss-lift` -0.05; each on the ground's ramp, so every mood and sun moves them. They lie on one
slow field in the ground shader (two octaves of 2D value noise, about 22 and 9 m, through the
meadow's warp): its highest `gold-share` (0.11) is gold, its lowest `moss-share` (0.10) moss, so the
two never touch. The block-in takes a swathe in three steps over a 0.1 rim of the field and a mark
takes it at its middle, so the edge is brushed; a swathe takes at most `swathe-mix` (0.5) of its tone,
so it reads as a gentle shift in the meadow, not a patch (painter-ground-fire-round3 and round4: the
owner twice found the patches too strong; round 4's probe sheet showed 0.35, 0.5 and 0.65). The
map's seed moves the field and each edge (`seed_of`, bound with the path slots), so maps differ.
Winter's shares are 0 (no swathes on the snow). Cost: two 2D noises on meadow pixels, no fetch; not
timed.

A collapsing building's ember cracks (`painter_building_burn.gdshaderinc` `building_embers`, round 3
and 4): the contour of a warped two-octave field, tapered by a slow gate, never rings; a crack's half
width at its widest is `EMBER_SEAM` (0.07 m) plus `EMBER_SEAM_PX` (3 screen pixels), measured by the
field's and the point's screen derivatives, so it reads at zoom 30 (about 6 to 8 px) and stays a
crack at zoom 8. Where lines crowd on a fallen slab's edge they merge into broken ember patches.

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
eye level).
Grass marks (card painter-grass-mark, 2026-11-19, look-pending; evidence
`docs/research/2026-11-09-prototypes/compare/painter_final74_grass_mark/`). Seen from above, the
three crossed cards collapse to thin spikes (the owner's "sad and spindly"), so under Painted every
wide grass tuft is drawn as ONE MARK instead: `PainterGrassMarks` (`painter/painter_grass_marks.gd`,
owned by PainterSurfaces, synced after each paint, cells event and new species) makes one mark mesh
per species (stroke geometry, `PainterGrassMarks.strokes`, culled by `bounds`) carrying a mark material (the
stand-in duplicated onto `painter_grass_mark.gdshader`, with the stand-in's tones, keep and frost
copied at every sync) and points each cell's `multimesh.mesh` at it; release puts the very same
card mesh back, and the shared card mesh is never edited. Classic, crops (`tuft_blades`) and
narrow tufts (reeds) keep their cards; `PainterGrassMarks.enabled` is the A/B switch. The
shader's vertex stage turns the mark to the view, lifts it toward the eye so no part cuts the
ground, and places the tuft COMBED (the first marks painted it in the fragment stage, see below): 4 or 5 broad strokes (`mark_count`, half width 0.13-0.18 of the reach,
`mark_width`; 7 to 9 thin ones before card painter-grass-mark-perf) rooted along a band across the tuft's upwind side and fanned only a little
(`mark_comb`; a wide fan read as a rosette or clover once the tufts were small), all leaning
downwind along a world lean field (the wind's way turned by a slow noise, so a meadow is combed in
drifts), each from a dark root to a lit tip, toned by a world field the neighbours share (so
overlapping tufts merge into one mass), with no outline and no ring. From the side (below about
45 degrees) the strokes stand up, droop at their tips and stand over a darker lumpy body at the
foot.
The mark's SIZE MODEL (card painter-grass-scale, 2026-11-19, look-pending; the owner's "they read
more like bushes than grass"; evidence `.../compare/painter_final76_grass_scale/`): a tuft is as big
as a real meadow tuft, and a clump core holds more tufts, not bigger ones. The first marks took
their size from the card mesh (0.91 m wide for a 0.39 m tall meadow tuft) times the instance's
scale, which the scatter's mass clumps grow to 2.4 times wide and 0.8 m tall in a core
(`ScatterMass.append_scale`), times 1.4 and a per-tuft 0.78-1.22: core tufts 2 m across with
strokes 0.4-0.7 m wide, the size of the bushes. Now a tuft's REACH (its blades' length) is its own
height (`mark_reach` 1) and at most `mark_reach_max` (0.4 m) times its own size step, and the
instance's FOOTPRINT (the card's half width times the instance's WIDTH scale, which carries the core
growth, times `mark_spread` 0.9) holds about (footprint / reach)^2 times `mark_fill` (1.0) tufts, at
most 8, their roots on a sunflower spiral to half a reach inside its rim, each its own size, turn
and strokes, the nearest on top. A rim tuft is one or two small tufts; a core a patch of up to
eight (the first marks' fragment stage tested a tuft's strokes inside its box, nearest first; the
geometry below orders them by a depth bias). The tone was lifted and warmed with the smaller marks (root value 0.74, tip 1.18,
`mark_warm` 0.16: the grass role is cooler than the floor, which a field of marks shows far more than
the cards' spikes). From above the marks keep 1.6 times keep-grass (`mark_keep`), falling back to
1.2 under snow so winter keeps its sparse straw. It lights itself (`SELECTOR_OWN_LIGHT` guards painter_selector's `light()`): the ramp's lit
colour darkened from root to tip (`mark_value`) as the cards darken theirs, a cast shadow read at
the ground under the fragment. Snow is a tint on the upper strokes, never a disc. Seen from above
the marks keep more tufts than the cards (`mark_keep`, above); tufts within about a metre of a token shrink (the ground's `tok`, copied each frame it changes).
Three ways were probed (a radial fan of blades read as maple leaves from above, a soft mass with
blade tips as moss; the combed strokes were the only one that read as grass from above and at
the eye). The sheet number `grass-mark-pitch` (0 draws the mark at every pitch) is a crossfade:
a pitch P > 0 puts the card surfaces into the mark mesh beside the strokes, and each tuft draws its
cards below about P degrees of camera pitch and its mark above (`grass_mark_on` in
painter_selector, read by both shaders, with a per-tuft band of 5 degrees so the change ripples
instead of popping). Core sets 0 since card painter-grass-mark-geo (the owner's "use the marks
everywhere"); it set 45 before, the cards' leafy patches at the oblique view costing less than the
discard marks did. Cost after the size model (indicative: in-run A/B, two cycles, median GPU ms
at 1920x1080 on the dev machine; cards = marks off, first = the first marks, now = this model): the
home view at zoom 16 cards 2.68/2.69, first 2.69/2.70, now at core's 45 2.71/2.71, now at pitch 0
3.33/3.36; at zoom 30 cards 2.87/3.12, first 2.93/3.15, now at 45 3.07/3.18, now at pitch 0
3.69/3.79; from above at zoom 16 cards 2.33/2.33, first 2.57/2.58, now 2.97/2.97 (the tufts per
instance are the cost: mark_fill 2.5 measured 3.15, mark_keep 1.2 against 1.6 saves only 0.03).
MARK COST AND HEIGHT (card painter-grass-mark-perf, 2026-11-19, look-pending; the owner's "the
performance difference seems big" and "still read too big" at zoom 16): the camera is orthographic
(zoom 16 or 30 is the view's height in metres), so a mark's size against a flower or a token is
the same at every zoom; zoom 16 only shows the tall standing strokes of a core, whose height
followed the instance's height scale (up to 0.8 m times 1.3 for a standing stroke). `mark_height_max`
(0.4 m, times the tuft's own step) now caps it. What the cost is, measured with one-uniform probes
at pitch 0 (in-run A/B, two cycles, median GPU ms; cards = marks off): the stroke loops cost
nothing (a probe that ran every loop and discarded at the end measured the same as no grass),
nor do the three noises (cutting them to one 2D noise measured 0.00), nor does the light (an
unshaded copy saved 0.04 to 0.10 of the 0.2 to 0.3), nor a series for cos and sin, nor
`depth_prepass_alpha`. The cost is the number of pixels the strokes cover counting overdraw: it falls
with fewer and broader strokes, with `mark_fill`, and steeply with `mark_keep` from above (keep 1.0
against 1.6 left +0.05 but a sparse field); the likely cause (not measured directly) is that a
discard shader gets no early depth rejection, so the heavy overlap of cores is paid in full. Defaults now: 4 or 5 strokes of
half width 0.13-0.18, fill 1.0 (these are also the fewer, bolder, painterly marks). Over the cards
(marks at pitch 0 at the home view; from above at the default 45), before then now: home zoom 16
+0.48 then +0.30, zoom 30 +0.61 then +0.33, from above zoom 16 +0.72 then +0.28 (cards 2.62, 3.17
and 2.36 ms; evidence `.../compare/painter_final77_grass_perf/`, probe logs in probe/). That is
above the +0.2 ms bar for making pitch 0 the default, so core kept 45 until the geometry below.
STROKES AS GEOMETRY (card painter-grass-mark-geo, 2026-11-19, look-pending; the owner's "use the
marks everywhere (pitch 0)" and "we need to address the performance"; evidence
`.../compare/painter_final79_grass_geo/`). `PainterGrassMarks.strokes` builds ONE mesh shared by every
instance: `TUFTS` (8) tufts of `STROKES` (5) strokes plus a body fan each, a stroke a tapered ribbon
(`STATIONS` 0, 0.4, 0.75 and a tip: 7 vertices, 5 triangles; UV the place along it and the side, UV2
the tuft and stroke slot, all positions zero) and a body 8 triangles; 8 x (5 x 5 + 8) = 264 triangles an
instance, 352 vertices. The shader (`world_vertex_coords`) is the whole model in `vertex()`: the same
tuft and stroke maths as the fragment version (the sunflower spiral, the comb, the curl and taper),
now per vertex, and every vertex of a slot the instance does not use (a rim tuft has 1 tuft, a core
up to 8; the sheet's keep thins whole instances) is collapsed to the instance's origin; the shadow
pass collapses all of them. The fragment stage only lights (`light()` unchanged), with NO discard, so
the depth test and the depth prepass see opaque triangles and each visible pixel is shaded about once.
The strokes of a mark are coplanar, so their order is a depth bias toward the eye (`TUFT_BIAS` 0.08
m across a patch's tufts, nearest the camera on top, the first tuft on top from straight above;
`STROKE_BIAS` 0.004 m per stroke laid later; a body under its strokes). Tones and the world fields
(`field`, `f_wob`, snow) are read at the vertices (ribbons are small against their 0.6 to 1.1 m
wavelengths). The probes (one job, `dead` = every vertex collapsed): the geometry costs the same as
submitting the collapsed vertices, so stations, tufts, body sides and slot count do not move the cost
(a triangle per stroke, 4 tufts, no bodies all within 0.05 ms); the whole mark cost is the
submission of about 1.1 M vertices, not the pixels. Median GPU ms over the cards (marks at pitch 0 vs
cards, two cycles; the old discard marks at pitch 0 in brackets): home zoom 16 +0.14 to +0.15
(+0.2 to +0.24), home zoom 30 +0.06 to +0.09 (+0.35), from above zoom 16 +0.01 to +0.02 (+0.27)
(cards 2.43/2.62, 3.17/3.19, 2.35/2.36), so pitch 0 is the default. Oblique density and colour
(`mark_side`, the view's `side` weight, 1 at the eye and 0 from above): the pitch-0 marks were
sparse and pale at the home view and the eye, so at the side the sheet's keep is raised 1.45 times,
the footprint is filled 1.5 times (`mark_fill` x), a stroke is 1.35 times broader, the colour
0.78 times as bright and the body a darker, wider mass; from above nothing changes. The size
(`mark_height_max`, reach, fill) is as before.
The old atlas
and tuft paths stay (stage 3 of the spike's plan removes them).
Flowers (card painter-flowers, look-pending): `PainterFlowerHue` reads each surface of a flower
asset once when its stand-in is made. Core's flowers are `_Bark` (stems), `_Leaf` and `_LeafB` (the
blooms: small UV 0..1 cards, three crossed per head or many over a mound); stems and leaves take the
grass ramp, and the bloom surface is drawn whole as painted marks
(`painter/shaders/painter_flower_marks.gdshaderinc`, card painter-flower-marks, look-pending; the
spike painter-flower-spike's option BC, owner's pick 2026-11-20): every head is ONE view-facing
six-petal rosette `flower-head` (0.11 m, times 0.8 to 1.25 and a little of its card's own size) wide,
never under `flower-floor` (5) pixels, its petals two flat planes (a darker and a lit half) round a
centre disc (the mood's `flower-gold`, or an orange between gold and red on a gold bloom, so it
follows every mood; `f_centre`), the card billboarded in every view (orbit and eye). The crossed twin
cards of a single head are collapsed (`PainterFlowerHue.twins_of`: a card whose centre is within
0.35 of its size of an earlier card's; flagged in the second block of rows of the centres texture,
one flag row per vertex row, then the carpet texel in the last row). A clump behaves like one: a
share `flower-thin` (0.2) of the cards left out so the leaves show between, `flower-bud` (0.12) small
(half size) darker buds, the rest at 0.7 to 1.2 of the head, a card in the plant's own colour with
`flower-own` (0.85) or else the plant's one other of the six, never random. The colour is still the one
of six sheet accents (`flower-gold`, `-rose`, `-violet`, `-white`, `-red`, `-blue`) that the texture's
own mean colour sorts into by OKLCH hue (poppy red, bluebell blue, buttercup gold, daisy white, bloom
mound pink or gold, bellflower and lavender violet). A spike (lavender, bells: a long dab box) is a
chain of five florets narrowing to the tip, 0.55 of a head wide and as tall as its box (to 4.5
heads). The earlier look this replaces (card painter-flower-carpet): each mound card turned to the
view and grown to 8 px and 1.7x into one banded dome of up to seven random hues, "pom-poms"; it
read as candy balls and the eye saw them as such. Far zoom: small marks lose colour mass (the
spike's measurement: speckle, smaller and paler than the balls at zoom 16 and 30). Compared in the
look round on the meadow at t16, t30, h16, h30: a raised pixel floor alone (8 px) still speckled,
since a third of the heads are left out; a blend to a cushion won. A bloom mound is a carpet
(`PainterFlowerHue.carpet_of`: at least 12 cards whose top centre is under 0.2 m; core's bloom and
lavender mounds); under the orbit's orthographic camera its marks blend from `flower-far-lo` (0.007
m a pixel, about zoom 7.5) to `flower-far-hi` (0.013, about zoom 14) into one cushion: each mark grows
to 8 px and 1.7x, is drawn 0.3 of the way to the mound's middle and 0.8 up to its top card, brought
0.25 mesh units toward the eye so it lies over the leaves, every card present at full size, shaded
low to high as a dome and cut as a rosette (a spike mound's too). The pixel size is
`2 / (abs(PROJECTION_MATRIX[1][1]) * height)`: the world's viewport is y-flipped, so the unsigned
form came out negative (measured 2026-11-19). Single heads (poppy, daisy) are never pulled. The
eye's perspective keeps marks at their own place. Cost (in-run GPU medians, indicative on the shared
GPU, across runs against the old look): home zoom 16 2.47 and 2.58 ms against 2.45 and 2.50, above
zoom 16 2.55 and 2.59 against 2.46 and 2.49, dense clump (zoom 6) 1.91 against 1.87: the same vertex
count, three more centre fetches and one 3x3 inverse a vertex, within about 0.1 ms. A surface whose name
says neither (a user library's one-atlas flower) keeps the per-pixel petal test, in the accent of
its non-green pixels' mean. `flower-mix` is now the slow field that steps a drift of blooms lighter
or darker. Cost on the meadow (in-run against the old path, 47 flower stand-ins): +0.01 ms at zoom
16, +0.06 at zoom 30, +0.02 at the eye; Painted stays under Classic there.
Thinning is the sheet's: `keep-grass` (0.6) and `keep-flower` (0.8; 0.4 before painter-flowers, when
a flowery meadow read empty) in groups of a slow world noise, both in the colour and the shadow pass
(winter 0.45 and 0.25: fewer tufts stand above the snow). The hand-placed props' layer
(`MapSourceLoader.PROPS_NODE`) is never thinned: `PainterPlantTone.mark_placed` sets the instance
uniform `painter_placed` on its nodes, so what an author places stands.

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

## Grounding

Card painter-grounding (2026-11-15; owner: foliage and tokens felt "on top of the landscape"). The
sun's shadow darkens the ground only along the sun's direction, and every painted shader turns the
engine's ambient off, so nothing darkened the ground right under a crown, round a trunk, a rock or a
wall, or under a token's feet, and no trunk or stone was darker where it met the ground. Two parts
(`PainterOcclusion`, `painter/painter_occlusion.gd`, owned by `PainterSurfaces`):

- **The ground's contact field.** A CPU raster at 0.5 m a texel over the map's extent plus
  `EDGE_PAD_M` (8 m) of empty margin on every side (`field_layout`: the ground reads the field
  with a clamped edge, so a footprint cut by the last row was repeated outward as a thin dark
  streak running off the map below a tree near the edge; card painter-trunk-streak), RG8: r a POOL
  (a crown's projected disc, centred halfway from the trunk to the crown's middle, radius 0.5 of the
  crown's half width plus 0.5 m, for the trees the painter does not grow too; a bush's own disc grown
  a third; a rock's, log's or stump's oriented box rounded by its narrower half, from the scatter's
  instance transforms; a structure's own plan, below), g a CORE (the seam at a trunk's foot, 0.3 m +
  2.5 % of its height, `trunk_seam`; a rock's base 0.22 m, a wall's 0.45 m; card
  painter-tree-ground halved the trunk's and widened the wall's). Each footprint
  is a coverage whose 0.5 contour is its nominal edge (`cover`), the texels keep the maximum. The
  painted ground shader reads it with one fetch (a no-op branch when off) and thresholds it through
  its own brush noise, so a pool is a flat stroke-edged shape, not a blur. The pool was the ground's
  lit tone darkened (`occ-dark`) and leaned a little toward its shade (`occ-shade`) and cool
  (`occ-cool`): shading toward the shade ramp alone read as a grey-violet smudge on the summer path
  (the first try); now it is the shade's own deeper step, in the shade only ("The pool lives in
  the shade" below). The core leans toward the litter tone (`occ-soil`, 0 in winter: the snow's own
  blue). Tokens are the only moving footprints: their feet discs go in a 32-entry uniform array
  (centre, radius from `TokenGhost.body_bounds`, foot height, so a token on a roof stamps nothing on
  the ground below), refreshed by one pass over the token group when one moved, and are drawn as a
  wider pool plus a deeper disc under the feet. Rebuilt 0.3 s after the painted trees install or
  erase (`PainterTrees.changed`), the scatter applies cells, a structure comes or goes or the
  ground is edited: 17-24 ms for 215-317 footprints (forest, village, taiga maps of 200 ft).
- **The pool lives in the shade** (card painter-tree-ground, 2026-11-19; owner: the pools "seem
  to contradict the direction of the light from the shadows"). The pool was mixed toward a tone
  between the lit and the shade colour wherever its footprint lay, so it was a grey disc centred on
  each trunk: darker than the sunlit meadow beside the trunk, and PALER than the cast shadow where
  the two crossed (at sunset each long shadow lightened exactly at its own tree). Now the pool is a
  step below the shade colour (`SHADE_DEEP` 0.8 of it, `occ-dark`, cooled) and is applied only where
  the ground is in shade (the cast shadow, or turned from the sun): what stands on the ground shuts
  out the sky, not the sun, so each shadow is darkest at its root and sunlit ground stays lit.
  `occ-pool` went from 0.42 to 0.85 since it now only deepens shade. The seam keeps 0.6 of its
  weight in the sun (`SEAM_LIT`), full in the shade; a trunk's seam was halved (a metre-wide seam in
  the sun was still a grey plate at zoom 16), a wall's widened to 0.45 m (weak at the walls at zoom
  16 through the yard's wash), and both shaders read the field 0.3 m toward
  the sun (`foliage_sun`, `SEAM_LEAN_M`), so a seam sits more on the side its shadow falls; still
  one fetch. The yard wash reads the seam too (it hid the walls' foot line before). Tokens' wider
  pool follows the same rule; the disc right under their feet does not. Compared side by side
  with four other approaches (the pool moved down-sun and stretched along the shadow: a second,
  rounder shadow, detached from the trunk at a low sun; a litter-tone ring at the ground's own
  value: dirt circles in summer, pink stains on snow; the seam alone: still a small grey plate;
  litter in the sun plus this in the shade): `compare/painter_final58_tree_ground/` (notes.md,
  probe sheets).
- **Pool shapes** (card painter-pool-shapes, 2026-11-18; the coverage sweep's gap 2). A structure's
  pool was its meshes' bounding box grown 0.9 m, and the box held the yard's skirt and path
  (`dressing_ground`, 10-14 m across, 5 m past the door), so a row of houses read as one hard-edged
  teal slab; a tree the painter does not grow (acacia, palm, dead tree: a scatter solid by its bark)
  got its crown's bounding box as a rectangle. Now `PainterFootprint` (`painter/painter_footprint.gd`)
  takes a structure's plan from its collision's lowest faces (vertices within 1.8 m of the lowest:
  the walls' and piles' feet, never the roof's overhang or the yard): their convex hull, fitted by
  the smallest turned rectangle round it, corners rounded so the shape keeps the hull's area (a
  house a rectangle with 0.4 m corners, a round hut, tulou or hex tower about a disc, a castle or a
  gatehouse its whole mass). Its reach past the walls is 0.3 + 0.035 of the plan's size + 0.02 of
  its height (0.4-1.0 m), then +-15 % by the node's name, so a barn is not a hut. A structure
  without collision falls back to its meshes' bounds without the dressing. A solid is a tree when
  its mesh carries a leaf surface beside its bark (`solid_meshes` maps each id to that) or it is
  taller than 2 m and 1.6 times its half width; it gets the painted trees' disc and seam. The yard
  wash (`painter_yard_ground`) reads the same field through the same brushed threshold and deep
  tone, so the shade at a wall's foot shows through it (one fetch per yard fragment; its uniforms
  are set with the ground's). Bake: the structures' pass over the two coverage galleries (32
  structures, headless) went from 29-31 ms to 17.5 ms, the pooled area from 4479 to 2167 m2; the
  hull fit is about 2 ms of it. No per-frame CPU cost. Frames:
  `compare/painter_final43_pool_shapes/`.
- **Base gradients.** A stem (the block-in's bark, `base_dark`, over its lowest 0.9 m) and a scatter
  stone or log (`painter_selector`'s solid branch, over its lowest 45 %) are a step darker at their
  foot, so they grow out of the ground; the heaped snow at a winter trunk's foot still wins.

Sheet numbers (DEFAULT_NUMBERS, `core.sheet`'s :world; winter's :world overrides soil, cool, dark and
shade): `occ-pool` 0.42, `occ-core` 0.8, `occ-dark` 0.9, `occ-soil` 0.5, `occ-cool` 0.05,
`occ-shade` 0.2, `base-dark` 0.28. Classic never loads any of it.

Cost (pinned in-run A/B, 1080p, RTX 3080, GPU ms median, `compare/painter_final25_grounding/cost`):
the look on against off is +0.012 ms on average over 12 pairs (forest tokens, taiga home, village
winter at 12 degrees, 16 tokens; range -0.03 to +0.047, noise about 0.03); main's ground shader
against this branch's with the look off is +0.04 (forest +0.09, taiga -0.01, village +0.035:
one pair each, before any drift). The total over main is about +0.05 ms. Rejected: engine SSAO
(+1.2 to +1.45 ms in all four views, and no visible change: the painted shaders have ambient off, so
the AO term has nothing to darken, even with `ssao_light_affect` 1); ground cover and litter dabs
at object bases belong to the coverage card.

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
  primitives in the village). Level 2 draws 12 of its root's 16 children (`PainterTreeMeshes.L2_CHILDREN`
  and the stroke shader's `L2_CHILDREN`, pinned equal by a test; the first three quarters of each level
  1 child's footprint, the others larger by sqrt(16 / 12), same coverage; painter-perf-veg: -0.12 to
  -0.17 ms at forest tokens and river zoom 8, no visible change at full size). The block-in's sphere is 6 x 3 (`PainterTreePack.ELL_SEGS`,
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

## The cost of a discard (painter-perf-blockin, 2026-11-16)

The block-in's cost was never its geometry or its colour work: it was `discard`. A shader that holds
any `discard` makes the depth pre-pass and the shadow pass run every fragment of its meshes and takes
early-z from the opaque pass. Measured at the taiga home view (GPU, interleaved, in-run Classic
anchor), the mere presence of a discard cost about 0.3 ms and the discards' own noise work about 0.3
ms more; fewer vertices (coarser spheres, shared vertices, fewer dead slots) saved 0 to 0.07 ms, and
a flat-colour fragment stage without discards saved most of the rest.

So a cell's crown masses (node 0) draw with `painter_tree_blockin_fast.gdshader` (`_bare` in a bare
season), the block-in body compiled with `TREE_FAST`: no discard anywhere. The two whole-fragment
kills (a role a species turns off, `rp2.w`, and foliage in a bare season) collapse the mass in the
vertex stage instead; the camera pass's thinning and rim-break dissolves, the bush foot, the ribbon
edge shape and the canopy fade's `tree_fades` are compiled out of it. The masses cast no shadow; a
twin node (`PainterTreeFast.SHADOW_NODE`, index 5 of the cell's nodes) shares node 0's MultiMesh,
draws with the full block-in shader and is SHADOWS_ONLY, so the crown's shadow keeps its eroded edge
and gaps (the sun pass's own discards). The view-centre canopy window (Settings > Canopy fade) that
also forced the full shader was removed on 2026-11-16 (owner decision, review board `d_canopy`), so
a play view always draws the discard-free masses. Only authoring raises a fade now: while a map
brush's window or the Village tool's cut is live (`CanopyFade.live()`, published with w above 0)
`PainterTreeFast.follow_fade` puts the full shader on the camera masses, since those fades are
discards; a shader swap compiles, so it happens only when one starts or ends. An event's tree (`take`) and the limb ribbons keep the full
shaders and one node. Rules for a change to the block-in body: any new `discard` goes inside
`#ifndef TREE_FAST ... #endif` (`tests/unit/test_painter_tree_fast.gd` cuts those regions out and
asserts none is left); a new whole-fragment kill of a mass belongs in the vertex stage's TREE_FAST
block. Measured effect (2026-11-16, `docs/research/2026-11-09-prototypes/compare/painter_final28_perf_blockin/notes.md`):
taiga home summer P-C +0.84 to +0.35, forest tokens summer +0.32 to +0.05, river zoom 8 +0.45 to +0.15.
The look is the same to the eye at full size; the camera pass no longer breaks the crown's outline
into soft lobes where it turns from the eye, so crowns read slightly more solid at their rims.

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
  after the precompile and the first-launch warm-up; with Painted the default, every launch); Settings Apply (`RenderStyle.start_warmup`).
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
  warm-up's order changed (above: 0.24 to 0.25 s now). Exported release build (card painter-level-entry):
  on a cold driver cache the first level still had one frame of 1.2 s (the second, 0.7 s) about 0.28 s
  after the cover lifted: the ground clipmap's strip bake drawing for the first time (not a painter shader;
  it follows the painted look's ground rebake). The first-launch GraphicsWarmup now draws it
  (`GroundClipmapStrips.warm_viewports`, DRAW phase, one a frame): after the lift the worst frame is 40 to 57 ms
  (docs/PERFORMANCE.md "The level-entry frame, found and fixed").
- One-offs left on the first Painted install: the painter scripts' GDScript compile (about 0.5 s
  debug; the warm-up's coordinator thread now loads them off the main thread) and `ground+plant retone` (about 130 ms the first
  time). House builds with manner records cost +27 to 45 % in procgen's recording, not in `painter/`.
- **`ERROR: Invalid Task ID` at `worker_thread_pool.cpp:408`** (painter-loose-ends, 2026-11-16): a
  render job that leaves one map and plays the next while the warm-up's `again` run is still
  building prints it once, with the backtrace `PainterWarmup._work` (the line of
  `RenderingServer.mesh_create_from_surfaces`). It reproduced in the first full job that
  played three saved maps in a row (once, before the second play; batch 2's job with the same
  transitions printed none), so it is a race. Found and fixed (painter-errors-fix, 2026-11-19, from
  the 4.7.2-stable sources): `RenderingServer.directional_soft_shadow_filter_set_quality` clears
  every 3D shader's pipelines even for the tier already set (`_update_shader_quality_settings`,
  `PipelineHashMapRD::clear_pipelines`), and `DebugRenderToggles.refresh` re-applied the saved tier
  at every map load, while the warm-up's workers built that world's pipelines. `clear_pipelines`
  waits on a shader's pending compile tasks without taking their ids out of its table, so a worker's
  `wait_for_pipeline` then waits on a released task: the error at `_work`, or the other way round at
  `debug_render_toggles.gd:272` (both seen). The clear also threw away the pipelines the warm-up had
  just made. Every caller now goes through `SunShadowQuality.set_quality`, which skips the tier in
  force (`test_painter_warmup` fails on a direct call). A real tier change still clears them all.
- **An intermittent access violation in the NVIDIA shader compiler** (`nvgpucomp64.dll`, driver
  32.0.16.2124, exit 0xC0000005) on a first launch: 2 crashes in 51 Painted cold runs of an exported
  build on the shared driver cache, 0 in 38 Classic, 0 in 66 runs with an empty or seeded private
  driver cache. Both were inside the first-launch GraphicsWarmup's COMPILE phase, before any painter
  thread ran, so it is not the painter warm-up's concurrency (card painter-compile-crash,
  docs/PERFORMANCE.md "Cold driver cache, the intermittent compiler crash and the level-entry frame").
  Not reproducible on demand, so no code change; do not "fix" it by cutting PainterWarmup workers
  without a repro.

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
- **Winter snow reads as thick painted snow (card painter-look-roofs-winter2, 2026-11-15;
  look-pending).** Shader only (the blanket, code 10); no mesh, sheet or procgen change. Cause of
  the milky, glossy look, measured by drawing each term away in a debug variant (frames in
  `painter_final23_roofs/diag`): there is no alpha, blend or specular in the shader; the milky,
  see-through snow was `thin`, the roof ramp's veil laid over the whole blanket (0.08 base, up
  to 0.58 at the eave and verges), and the gloss was the blanket's wide light step (`soft` 0.15,
  plus a soft-modelling mix in `light()`) on its rounded mesh. Now: (1) the veil is a few ragged
  streaks (a steep step on a stretched noise, `vein`), strongest at the eave and verges, none
  elsewhere; (2) a bare tongue's edge is a narrow threshold (0.42 to 0.52) on a three-scale dab
  noise (broad dabs stretched along the eave, a drag, a fine rag), with snow flecks inside and
  the roof's own short stroke rows (`p_strokes`, 0.2 m) in the bare part; (3) the blanket's light
  step is 0.06 and the light's turn is shifted by a two-scale dab noise through a steep step
  (`f_tune.z` 0.32), the cast edge by 0.5, so the rounded shading breaks into broad brush dabs,
  and a dry-brush grain (long fine streaks along the eave, fading with `broad`) shows at close
  zoom; (4) winter stone's shade is bluer (`f_shd *= (0.9, 0.93, 1.3)`). Cost (pinned A/B,
  `painter_final23_roofs/cost`, new against the starting shader on the same meshes): winter home
  12 +0.014 ms, winter eye +0.014, winter home 3 +0.015, summer -0.01 to -0.006 (inside the
  +0.02 bound). Not done: thatch gold still leans mustard; the dab blue shade across a large
  thatch or tile slope can read as cloud shadow at close zoom (the grain is a faint horizontal
  tick); slate tongues are dark navy dabs; a bare tongue still keeps the blanket's rounded
  shading; half-timber roofs show little colour; winter walls are bluer but still grey-violet.

## Fire and events (painter-fire, 2026-11-15)

Fire and the terrain events were built against Classic's assets; under Painted they were checked event
by event (findings: `docs/research/2026-11-09-prototypes/compare/painter_final25_fire/findings.md`).

- **Trees an event takes.** A painted tree is a few instances in a 5 m cell's five nodes, so an event
  cannot move or burn it in place. `PainterTrees.take(position, parent, burning)` (the work is in
  `painter/trees/tree_actors.gd`, `PainterTreeActors`) lifts one tree out: its cell is rebuilt without
  it and the tree is drawn by its own five nodes under a pivot Node3D in the event's parent. ForestFall
  and FireSweep find the host through the scatter's meta (`PainterTrees.of`, `HOST_META`, never by
  naming a painter class: the boot graph allows only `render_style.gd`), take the tree where they
  would hide a GLB tree and draw a stand-in, and move the pivot with their own transform maths. A
  burning actor draws with the burn shader variants (`painter_tree_{stroke,blockin}{,_bare}_burn`,
  the `TREE_BURN` define and `painter_tree_burn.gdshaderinc`: `instance uniform float burn`, leaves
  catch from the foot up and turn ember orange then ash, wood chars, the same 0..1.7 scale as
  `FireSweep.burn_progress`). The cell's own materials carry no burn code, so Painted trees cost what
  they did. The host's `sync()` skips held keys; `drop_all(actors)` (the event's `release` and
  `_exit_tree`) frees the pivots and either restores the tree to its cell or, when its row left the
  scatter meanwhile (the change landed), erases it. The four burn shaders are warmed with their group
  (`PainterWarmup`).
- **The persistent fire on the ground.** `FireLook.bind_glow` binds the fire bake to the terrain's own
  material only; `FireLook.mirror_glow(target, source)` registers the painted ground material as a
  mirror (`PainterSurfaces` does so on paint, `unmirror_glow` on release), so the painted ground reads
  the same `fire_present`, `fire_sim_map`, `fire_sim_rect`. `painter_ground.gdshader` includes
  `shaders/fire_glow.gdshaderinc` and `burn_ground()` lays the dried band and scorch on the role colours,
  the char in flat steps of its tone with a noise-broken edge, and a stepped, breathing glow into
  EMISSION: no soft gradients. Classic is unchanged (`glow_mirrors` is empty there).
- **Scorched ground as a role, beside the biome ash.** `PainterGroundRoles` has a ninth role `char`
  (index 8, after coverage's dry, ash and earth; words `ash`, `char`, `charred`, `cinder`,
  `scorched`), toned from the sheet's `floor` ramp reduced to its luminance in a warm tint
  (`char_of`), so it follows the mood and the sun but never reads as moss. It is the scar a fire
  event leaves (the `ash` SURFACE FireSweep stamps), a different thing from the biome role `ash`
  (a burnt-forest biome's own ground, from the stone tone, zone2 map): the scar lies over it.
  `PainterSurfaces.char_image(doc)` makes an R8 map only when the document names an ash surface
  (else null and `char_present` is false), and the shader takes role 8 over everything but a path;
  uniforms `char_map`, `char_present`, `g_lit[18]`, `g_shd[18]`. Burning wood (trunks, limbs) fades
  orange, ember red, charcoal in one smooth fall, not bands (`burn_paint(..., wood, ...)`). Open:
  the burnt biome's snag trees (assets flagged `charred`) still take the sheet's brown bark.
- **The event fire's own shaders.** `FireVariants` (`scenes/effects/fire_variants.gd`) builds Painted
  variants of `event_puff`, `fire_smoke` and `ground_burn` from the originals' source with a list of
  edits (Classic files untouched; `test_painter_fire` checks every edit still matches its text). A
  static flag, set by `LevelEnvironmentManager._publish_painted`, picks the shader when an effect is
  created (`EventPuffs._init`, `SmokePuffs._init`, `GroundBurn`). Painted: time held in 10 Hz steps,
  a warmer yellow flame heart, embers as small firm dabs, the smoke a lilac-warm grey that takes more
  of the sun's colour (the mood reaches it through the light, as it does a crown; no sheet role is
  read), a broader paint patch, the burn's char a warm brown. `fire_flames` already draws a 12 Hz
  flipbook and is left alone. The variants are warmed with the painter's shaders (`PainterWarmup`).
- **Buildings.** `painter_building_burn.gdshaderinc` adds `instance uniform float burn` to
  `painter_structure.gdshader` and `painter_structure_manner.gdshader` (char climbing from the foot in
  flat steps, a red then orange ember band that glows). `PainterBuildings.take(structure)`,
  `set_burn(actor, v)` and `drop(actor)` hand a building's painted parts to an event. A structure's
  parts are nodes already, so no pivot is made. `StructureBurn` (card painter-structure-fire) calls
  it, below.
- **Buildings a fire burns (card painter-structure-fire).** A fire that starts in a forest also takes
  every building whose footprint lies in its circle or along its path (`StructureBurn.find`, at most 8,
  nearest first; a ruin never burns again). `FireSweep` holds a `StructureBurn` beside its trees. Each
  building catches when the ground front reaches its middle (0.8 of the way, plus up to 0.3 s) and
  burns 2.2 to 2.6 s: its `burn` instance uniform goes 0 to 1.7 (`burn_progress`'s scale, so a tree
  and a house beside each other char on one curve), the painter's building burn shader laying char
  from the foot of each part, an ember band at its edge, roofs darkening with the walls (flat
  steps); flames stand in its footprint as the burn climbs (the last is out before the slump, so
  none stands over a lowered roof) and a smoke billow rises over it. At 0.8 of its burn it comes
  down over 1.8 s in rigid charred pieces (card painter-fire-polish; `StructureCollapse`, nothing is
  cut away in a shader any more, so no sky shows through the roof: `building_break` returns false).
  When it catches, a worker cuts its parts (AuthoredStructures' built arrays) by planes in its own
  frame: a stump at 0.24 of its height that stays standing, the ridge, and cuts across about every
  3.2 m (at most three segments, each leaning up to 0.24 rad). Roof triangles, and anything over the
  eave clear of the end walls (a ridge trim, a dormer: `END_BAND_M` 1 m), go to roof slabs (side of
  the ridge, segment); the rest to wall stretches and end walls; every bit is drawn from both faces.
  Each piece is a MeshInstance3D a part surface, wearing that part's material and **its cast_shadow**
  (a hand-drawn part's `MannerShadow` child, the Classic-material shadow caster, is cut too and must
  stay shadows only: drawn, its pieces hid the charred ones under an uncharred copy, card
  painter-fire-polish2), and the burnable pieces join the actor's nodes, so `set_burn` reaches them
  and they start at the building's char. The motion (`StructureCollapse.pose`, pure): the roof sags
  to x 0.3 (slabs hinge at their eave, the middle of the ridge most), then the pieces fall to 0.8
  (gathering speed): a slab turns by its own pitch (`slab_pitch`, from its broad faces' normals) times
  0.9..1.12 and lies low on the heap, a wall topples until its top end is down (outward onto the
  grass, inward onto the stump), then one bounce and rock to rest. The node only shudders and sinks
  4 percent. The `burn` value runs on from 1.7 to 2.7: the charcoal deepens 30 percent and ember
  seams (two flat bands along a brush noise's contour) glow through it, dying to a 0.3 smoulder as
  the pieces rest. Two rounds of layered dust puffs ring the footprint (x 0.3 and 0.78, 1.3 radii
  out: `dust_color`, held in 10 Hz steps like the other painted event variants). The dust is
  `EventPuffs.emit_brush`: a blob whose kind carries a 0.3 marker, which only the Painted
  event-puff variant reads to draw a lit cap, a body and a cool shaded underside with a
  brush-wobbled edge (`FireVariants.EDITS`); tree-fall and every other event's dust is unchanged.
  The charred heap is the stand-in for its ruin until the change lands; a ruin at 0.85 keeps no
  bare rafter (procgen `ProcgenRuin.RAFTERS_GONE_AT` 0.8). The painted `burn` comes from the buildings host
  (`PainterBuildings.HOST_META` on the `AuthoredStructures` node, a WeakRef: `StructureBurn` never
  names a painter class); **under Classic there is no host and nothing of the building plays** (the
  owner's call, 2026-11-18: no more work on Classic): it stands through the fire, the fire's
  change does not wait for it, and it pops to its ruin when the history entry applies, so a Classic
  and a Painted board hold the same map.
  The fire's change waits for the last collapse (`FireSweep.hold_s`, which `TerrainEvents.advance`
  reads), so the ruin never lands mid-slump.
- **The ruin is document state.** The GM's change (`TerrainEvents._burn`) gains a third part in
  the fire's one history entry: `StructureEditor.burn_down` replaces each burnt building's record
  with its ruin, the same footprint, seed and style under the `ruin_*` recipe of core (`StructureRuin`:
  a round plan takes the tower, a barn the barn, a chapel the chapel, a townhouse the townhouse,
  else the cottage; `ruin` raised to 0.85), or removes the building when no ruin fits (a plan that
  is not a rectangle and outside the ruin's sizes). It travels to peers as the ordinary
  `structures` op, a save keeps it, and an undo of the entry (one step) brings the buildings back.
  The ruin recipes are procgen's own (stone, ragged skyline, standing gables, rubble, moss), so the
  walls are not charred: the `char` ash scar the fire lays over the ground round it is. A ruin's
  node carries the meta `StructureRuin.META`. Its roof remnant and bare rafters are painted as the
  recipe's roof kind, as Classic draws them (card painter-roofs-ivy reversed the earlier
  `RUIN_ROOF_BURN` hold at `burn` 1.7: it drew every ruin's roof slab as a black plane). A late joiner
  gets only the ops, as for burnt trees. Cost (2026-11-18, pinned 1920x1080, vsync off, in-run
  interleaved x3, GPU median ms, zoom 8, a village of three houses, the fire frozen at 3.3 s with
  two houses slumping in dust): burning Classic 2.522 / 2.598 / 2.602 (plays no house burn), Painted
  2.040 / 2.091 / 2.094, Painted with the buildings let go (same fire, trees and ground) 2.051 /
  2.059 / 2.057: the burn's own cost is within the noise (about 0.0 ms, -0.01 to +0.04), and Painted
  stays about 0.5 ms under Classic. Calm Classic 1.963 / 1.920 / 1.923, Painted 1.846 / 1.833 /
  1.852. Open: a structure-only ignition (a fire still needs a forest to start), and walls and
  fences.
- **Perf** (2026-11-15, pinned 1920x1080, vsync off, in-run interleaved, GPU median ms). Fire event
  mid-burn, forest at zoom 16: Classic 3.805 / 3.893, Painted on this branch 3.110 / 3.125 (0.7 ms
  under Classic), Painted on main 3.845 / 3.864 (the GLB stand-ins and the painted trees both drew).
  Calm, no fire in the level: Painted minus Classic is +0.13..+0.17 ms in the village and +0.07..+0.12 ms
  in the forest on both the branch and main, the same within the run's 0.03 ms noise: the painted
  ground's fire branch costs nothing where no fire exists.
- **Not done (gaps).** ForestFall does not damage structures; BridgeCollapse cuts only crossings;
  a fire burns buildings (above) but not walls or fences, and the ruin it leaves is core's stone
  `ruin_*` recipe on the same footprint, not a charred rubble document (a procgen task).

## Water

**Update (card painter-water-field-painted, look-pending, unmerged, 2026-11-19):** on a map with
authored terrain the Painted look draws its water as ONE surface from the `WaterField`
(`PainterWaterField`, `WaterFieldMesh`, `painter_water.gdshader`'s field branch,
docs/systems/water_field.md "Drawing it"): AuthoredWater's surface mesh is hidden, a fall is the
steep part of that surface, and the paragraphs below about the curtain's white, the fall frames and
`painter_fall_white.gdshaderinc` describe what that card replaced (a Blender map's water planes and
the river ribbon still take the depth-buffer path described here). `painter_waterfall.gdshader` is
mist only (uniforms `p_foam`, `p_sky`).

Under Painted the water and the falls draw with the painter's shaders (card painter-water,
2026-11-15; the research is `docs/research/2026-11-15-painted-water/report.md`, candidate C1).
`PainterWater` (`painter/painter_water.gd`, loaded by path from `PainterSurfaces` like
`PainterBuildings`) swaps the `shader` of the two SHARED materials, `WaterGlbUtils.water_material()`
and `AuthoredWater.fall_material()`, not a per-mesh override: the shared material reaches every
water mesh, every later rebuild and the river ribbon past the edge, and `process_water_meshes()`
would undo an override. A `ShaderMaterial` keeps its parameters and a mesh its instance uniforms
across a shader swap (probe, 2026-11-15), so the flow map, disturbance points, skirt uniforms and
the level's Motion keys keep working: `painter_water.gdshader` declares Classic's names for them.
The sheet's colours go under `p_` names Classic does not read (so `apply_water_settings()` cannot
fight them); `release()` puts both shaders back, removes the META and sets every `p_` uniform to
null, so the materials are as they were. Classic's `water.gdshader` and `waterfall.gdshader` are not
touched (a copy of the helpers, no shared include).

The look (`painter_water.gdshader`, no screen texture):
- **A wash in three depth bands.** The depth buffer's water column picks shallow, mid and deep
  (`water-shallow`, `water-mid`, `water-deep`) with soft-edged, posterised steps (`BAND_1` 0.2,
  `BAND_2` 0.85, `POSTERISE` 0.6). It is drawn alpha-blended (`water-opacity`) over the opaque
  painted ground, so the ground's brushwork shows through the shallows.
- **A stroke lattice.** World-space, jittered cells (2.4 m) with one stroke per cell at a
  `water-strokes` share, `water-stroke-len` long, along the flow (the flow map) or the wind; each
  cell boils on its own phase (`water-boil` s) and the seed changes only at envelope 0, so it
  never swims with the camera. Strokes fade out by pixel footprint. `stroke_layer(...)` is a clean
  function (coverage, id) another source can replace (card painter-water-c2 prototypes a baked
  atlas). A second, longer layer and the sun-side glint ticks (`water-glints`, kept where a
  stroke's own small tilt reflects the sun) are skipped under the Low water quality.
- **The shore lap.** An iso-depth ribbon of `water-foam-width` m from the depth buffer's column
  gradient (the slope is floored at 0.06; a steep bed, a fall lip, can still thin it, and the
  speckle the C2 prototype saw there did not show in the fall frames).
- **Tokens.** Disturbance points (rings, wakes) are drawn as broken arc strokes, and a token or rock
  standing in the water gets a foam wrap.
- **Light.** `light()` is a lit/shade selector like the ground's: cast shadows (a tree's, a cliff's)
  take the wash toward `p_shade_mul`, which is `SHADE_SHARE` (0.55) of the ground's own shade-to-lit
  ratio, so the water cools with the ground beside it.
- **Winter ice.** `ice-over` (winter: 1) freezes SLOW water (a pond, a lake, not a river or a fall)
  to the `water-ice` wash with a few long cracks, open round every disturbance point, so a token
  never stands on ice. It is visual only: the float and drown rules are unchanged (the report's open
  question; see the card's report).
- **The wet band.** The painted ground darkens and cools in a brushed band along the water's
  edge (`painter_ground.gdshader`, `ground_at`, `WET_EDGE`), from the water weights texture the
  ground already binds.

`painter_waterfall.gdshader` is the fall: unshaded, the same vertex contract as Classic's, chunky
white streaks over the shallow and mid tones, with the sheet's foam. The white over the brink and at
the foot is shared with the water (`painter_fall_white.gdshaderinc`, from the fall frame in
CUSTOM0/CUSTOM1; card painter-fall-frame-foam below), so it has no lip roll and no foam ring of its
own: the ring is Classic's only.

Full-size verdicts (card painter-loose-ends, 2026-11-16, frames in
`compare/painter_final29_loose_ends/`): summer, dusk, night and winter read as the sheet's moods
at zoom 8 and 20, the Low water quality (second layer and glints off) is a plausible plainer
version, the SubmergedMarker ring draws over the water and the fall, the submerged lower body of a
token at eye level is a translucent teal form (not grey), and the river past the map edge carries on
into the skirt. Changes from that pass: the glint is gold (`water-glint` oklch 0.97 0.095 92: the
earlier near-white tick read as a stroke), winter's open water is a luminous slate teal (chroma
about 0.09 to 0.105, not the first grey-teal), and still water takes more strokes than a river
(`share = p_strokes * (1 + 0.9 * (1 - flow_k))`: a pond had three or four dabs in 40 m2, now a
dozen). Open: the in-map ground and the ground skirt differ in tone and brushwork at the map edge (a
hard seam), the river ribbon repeats one stroke row mirrored at the edge, and the shore lap
glitters in small triangles on a pond's steep bank.

Sheet: roles `water-shallow`, `water-mid`, `water-deep`, `water-lit`, `water-shade`, `water-foam`,
`water-glint`, `water-ice`; numbers `water-strokes`, `water-stroke-len`, `water-boil`,
`water-glints`, `water-opacity`, `water-foam-width`, `ice-over`; per-mood overrides in
`core.sheet` (dusk's wash is blue-violet, night's deep and dim, winter's pale).

Cost (pinned, interleaved in-run A/B, vsync off, `viewport_get_measured_render_time_gpu`, RTX 3080,
a 150 m forest with a river, a pond, a fall and a long river along the south edge; Painted vs Classic
water on the same painted ground, medians of two interleaved pairs): summer zoom 8 2.16 vs 2.23 ms,
zoom 20 2.69 vs 2.80, eye 2.87 vs 2.97; winter zoom 8 2.11 vs 2.18, zoom 20 2.60 vs 2.70. Painted is
0.05 to 0.11 ms CHEAPER than Classic in every view (no normal-map reads, no screen texture).

Warm-up: both shaders are in `PainterWarmup` (plain layout and the fall layout).
`test_painter_water.gd` covers the swap, the exact restore, the kept parameters, re-toning, the
fall following and the shade factor.

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

## GLB maps (card painter-glb-parity, 2026-11-18)

A Blender-made `map.glb` loads as plain nodes (MeshInstance3D terrain, props, ScatterGlbUtils
chunks, MeshInstancingUtils MultiMeshes); `PainterGlbMap` (painter/painter_glb_map.gd, made by
path by PainterSurfaces on the first painted map) reads what is there, and `PainterGlbRoles`
(painter/glb_roles.gd, pure) holds the rules. The contract names two OPTIONAL extras
(ASSET_PIPELINE.md "Painter roles", card painter-glb-roles, 2026-11-19): `tt_paint_role`
(`ground-meadow`, `ground-path`, `ground-rock`, `roof`, `bark`, `stone`, `leaf`, `keep`) and
`tt_ground`. `PainterGlbRoles` is their one reader (`extras_of`, `extra_role`, `ground_mark`,
`ground_zone`, `prop_role`'s `extras` argument); precedence is the explicit extra, then the name and
material rules, then the shape and colour rules, and a map without them is read exactly as before.
No producer writes them yet; `tests/unit/glb_roles_fixture.gd` writes a small map that carries them
(test_painter_glb_roles.gd). The bullets below are the rules without extras, with the extras'
overrides noted:

- **Ground.** A single-surface mesh that is wide, shallow and faces up (`is_ground`) gets the
  painted ground shader as `material_override` in the map's world frame (`world_frame`). Its zone
  (meadow, path, rock, shore) is classified on the GPU from the baked albedo (`glb_zone`,
  `glb_classify`: a planar UV fit from `uv_affine`), so the artist's layout stays and the sheet
  supplies tones, brush marks and shade. No texture or UVs that are not one planar map: one role
  by the colour. Extras: `tt_ground` true (or a `ground-*` role) makes any mesh ground, several
  surfaces included (then one role by the first surface's colour, no zone read); `tt_ground` false or
  `keep` makes it never ground; `ground-meadow` is the shader's base zone, `ground-path` and
  `ground-rock` read a one-texel swatch albedo (`ZONE_SWATCH`, `_force_zone`) through the same zone
  read, so no shader changed.
- **Trees.** A scatter chunk of a tree (`wind_foliage_category` "tree") whose name resolves to a
  painted species (`tree_species`: treecube names, then words such as oak, pine) is hidden and its
  instances become PainterTrees rows (`PainterGlbMap.rows_on(map)`, scaled by mesh height over the
  species' nominal height, `tree_scale`). Other scatter species get the authored scatter's
  plant or solid stand-ins through `PainterSurfaces.swap_surface`.
- **Props.** A MeshInstance3D (or a duplicate MultiMesh) gets a painted solid stand-in per surface
  in the sheet role its material or node name says (`prop_role`: roof, bark, stone, leaf; else
  by colour when untextured). A `tt_paint_role` on the material, node or mesh (that order) names the
  role outright (`roof` is `roof-clay`) or `keep`; scatter chunks and trees ignore the extras.
- **Left as authored** (listed per node by `left_as_authored()`): lights, glass, ironwork, water
  (PainterWater owns it), textured surfaces whose names say nothing, terrain of several surfaces
  or non-planar UVs, nodes with a material override, hidden nodes, StaticBody3D, authored layers.
  No skirt and no contact-occlusion pools on GLB ground (`map_extent` is zero without
  AuthoredTerrain); tokens' feet discs do reach it.
- **Cost.** The scan runs `STEP_US` (3 ms) of main thread a frame, never at level entry;
  `complete()` finishes it for tests. The ground shader's `ground_plain` (GROUND on LAYOUT_PLAIN)
  is a warm-up sample. Classic never creates the host; `release()` puts every material, override
  and chunk back exactly (test_painter_glb_map.gd).

## Coverage (card painter-coverage, 2026-11-15)

The audit of Classic against Painted is `docs/research/2026-11-09-prototypes/compare/
painter_final25_coverage/matrix.md`; the current, code-read class-by-class audit and its ranked gaps
(main 4f1b82b8, 2026-11-18) is `docs/painter-coverage-audit.md`. What the card filled:

- **Biome ground and tufts.** Three more ground roles, `dry` (savanna), `ash` (burnt forest) and
  `earth` (rocky badlands), and the plant roles `dry-grass` and `cactus`, are DERIVED
  (`PainterGroundRoles.DERIVED`): at tone time from a keyframed role (`ground`, `stone`, `path`,
  `grass`, `leaf`) moved by sheet numbers `<name>-hue`, `-chroma` and `-lift` in `:world`, so
  they follow every mood and sun with no per-keyframe lines. The ground shader reads them from
  a second zone texture (`zone2_map`: r dry, g ash, b earth, built by
  `PainterSurfaces.biome_zone_image`, null on a map with no dry biome, so such a map pays nothing).
- **Trees the painter does not grow** (acacia, palm, dead tree) are painted by surface
  (`PainterPlantRoles.for_surface`: material name `*_Bark` is a solid in the bark role, the rest a
  leaf mass); cactus and barrel cactus are solids in the cactus role, agave a mass, a dead shrub
  a bark mass. `WindFoliage` now copies the GLB material's name onto its shader material
  (Classic reads nothing from it).
- **A dry map's whole ground.** When one dry biome holds at least a quarter of the map and more
  cells than any other biome (`PainterSurfaces._dominant_channel`), the second zone texture is 1
  everywhere its biome is not displaced by another biome, density ignored, and the base surface's
  shore (a savanna's or badlands' base is sand) is dropped from the zone map: a savanna reads
  golden straw, the badlands baked terracotta, a burnt forest dark brown-grey char. A map with a
  small patch of a dry biome keeps the density pull; a map with no dry biome has no second texture
  and draws exactly as before.
- **Wall layers.** `AuthoredWalls` (drawn walls, wall rows, street lots), `AuthoredBoundaries` and
  `AuthoredCrossings` wear the structures' stand-ins by part name (`PainterBuildings.wall_part_key`:
  a crossing's `Wood` is timber, `Stones`, `Arch` and `Ford` the stone ramp); the toon styles' trim
  kinds (`wall_trim`, `frame_trim`, `door_trim`, `trim_plaster`, `frame_plaster`, `frame_stone`)
  and the `ornament_wood`, `ornament_bark`, `ornament_cloth` and `canopy_leaf` parts have KINDS rows.
  Metal (`door_metal`, `ornament_metal`) and glass stay Classic by earlier decision.
- **Burnt forest, loose ends** (card painter-loose-ends, 2026-11-16; frames
  `compare/painter_final29_loose_ends/`). The ash ground was retuned to hue 48, chroma x1.9, lift
  -0.27 (a warm ember brown, not the mauve of the first retune), and the burnt forest's dead wood
  (the DeadTree snags, logs, stumps, sticks, dead shrubs: any bark-role asset whose biome folder
  has the ground role `ash`) is the `charcoal` role (`PainterPlantRoles.CHARCOAL_ROLE`, DERIVED
  from `bark` by `charcoal-hue 45`, `-chroma 0.45`, `-lift -0.2`), so the trunks read as char against
  the ash instead of honey wood on brown ground. `for_surface` returns it for a `charred` entry's
  bark surface; other biomes' snags and logs keep the bark role.
- **Crossings** (timber `Wood`, `Stones`, `Arch`, `Ford`) were captured over a river at full size:
  all four are painted and match the painted water and ground. Their stone took the wall-stone tone,
  pale cream and bleached against sand banks; fixed in card painter-edges (below).
- **Crossing stone and the map edge** (card painter-edges, 2026-11-16; frames
  `compare/painter_final32_edges/before` and `after`, notes.md there).
  - The stepping stones, the arch and the ford's slabs (`Stones`, `Arch`, `Ford`) are the kind
    `crossing_stone`, role `crossing-stone`: `PainterBuildings.crossing_tone()` derives it from
    `wall-stone` by the sheet numbers `crossing-turn` (hue turned, degrees), `crossing-chroma` (a
    factor) and `crossing-value` (a lightness factor; relative, so night's cool stone stays cool),
    now -14, 0.8, 0.76: a warm grey that parts from sand banks and water in summer, dusk, winter and
    night. The timber `Wood` keeps its trim_wood.
  - A river that leaves the map draws its channel patch (the skirt's `Channel` child, which carries
    the skirt ring's Classic material) as a dark, unbrushed olive rectangle against the painted ground:
    `PainterSurfaces._dress` now dresses it with the painted skirt material too (UV is the map-frame
    XZ), so the seam at the edge is gone. No ground shader change.
  - The water's outer shore dashes thin out on a steep bank (`dash_gate`, slope 0.6 to 1.4): they
    broke into small glitter triangles because the gradient changes per mesh triangle. Partly
    helps; the lap band itself still shows triangle shards on a steep pond bank (open: cap the
    slope used for `d_h`).
  - Round 2 (card painter-edges2, frames `after2`, `after3`): the skirt now takes the terrain's wet-bank
    texture too (`_bind_wet`; it clamps at the map's edge, so the bank band runs on along the patch
    instead of ending in a hard line). The row of mirrored white dabs across a river at the map edge
    is gone: the shore effects keyed to a shallow column (depth-slope wrap, lap dashes, the ice rim,
    the wash's shoreline alpha) fade within a metre of the map's edge (`edge_band` in
    painter_water.gdshader; `p_exit` is set by `SkirtExits.ribbon_material`, so a map with no river
    exit is untouched). `d_h = column_raw / min(slope, 1.0)` for the pond's glitter was tried and
    changed nothing visible, so it was dropped; the shards on a steep pond bank remain (the bed's
    depth, per terrain triangle, is the likely source).
  - Round 3 (card painter-water-edge3, frames `painter_final36_water_edge3/before`, `after`): the hairline
    across a river at the map edge was not a gap (a probe of the in-map mesh and the ribbon showed both
    reach the edge row, level and collinear) but the flow map: its border texels were forced still, so the
    in-map water's last cell (UVs run to the edge) read as still water, which the painted water draws as
    ice in winter (`still` in the ice term) and as a different stroke field in summer, and Classic as a
    sliver. `WaterFlowBaker._encode` now repeats the flow of the texel inside it on the border
    (`EDGE_INSET_TEXELS`), so the flow holds to the edge (maps saved before keep the old bytes until the
    water is next baked). The `edge_band` ramp is now 0.3 to 2.2 m (it was 0.4 to 1.1: over a metre the
    bank foam and the pale shallows thickened abruptly as the fade began, which read as a step). On a
    steep bank the lap's edge softens (`steep`, slope 0.5 to 1.3) and the outer dashes are cut off from
    slope 0.9 (`dash_gate` 0.35 to 0.9) and drawn as soft dabs, so the pond's shards thin out; a steep
    river bank loses some of its dashes too. The ribbon fades through a
    pale turquoise before the green.
- **Fall lip (card painter-fall-lip, 2026-11-18, look-pending).** Measured cause: the carve's crest
  sill was `CREST_M`, 5 cm under the upper level, and `blend_with_ground` eases a small cut
  (TOP_SOFT_M) while the tier plateau stands about 15 cm over the level beside the channel, so the
  sill rose to ground height: the wetted width at the lip was 74 to 80 percent of the channel on waist
  falls (1.11 of 1.5 half width, 1.61 of 2.0), 73 percent on a tall ankle fall and a dry crest (the
  `DRY_CREST_SHARE` fallback, 50 percent) on a short ankle fall, and the pool above ended 0.3 to 0.5 m
  short of the lip. A mesh cannot draw water outside the ground's crossing (the ground is opaque), so
  the fix is in the carve: `WaterCarve.fall_crest_depth()` keeps a fall's crest the channel's depth
  under the level, between 5 cm and `FALL_CREST_DEPTH_M` (12 cm), in `step_shape`, `fall_shape` and
  `fall_foot`. New carves only (a saved map keeps its ground). After it the lip is 88 and 91 percent of
  the channel on the waist and wide falls (1.33 of 1.5, 1.82 of 2.0) and 85 percent on the tall ankle
  fall (0.47); the short ankle fall's lip (0.31 of 0.55, a 1.1 m channel whose lip row mixes with the
  first face row) still funnels over its last 0.7 m, but the pool now runs into the curtain. `WaterFallMesh` is unchanged (a first try
  of mesh lead-in rows and a brink edge fade moved the wetted width by under 3 percent and was
  dropped).
- **Fall continuity and the pond's tan band (card painter-fall-continuity, 2026-11-18, look-pending;
  frames `compare/painter_final46_fall_continuity/`, notes there).** Three causes, each probed. (1)
  The tan band across a pond: a river drawn first and a pond dug over its end later keeps its level
  (-0.15) 0.83 m over the pond's (-0.985); the highest level owned every sample the two areas
  shared, so the river stood over the pond as a slab and the camera saw the bed under its edge (the
  band narrowed with pitch as a riser does). Now a river whose last point lies on a lower pond's
  mask feeds it (`WaterGeometry.fed_ponds()`): the pond owns its mask in `levels()`, `level_at()`
  and `WaterMeshBuilder.sample_owners()` (so tokens float at the pond's level there too), and the
  surface falls from the river's level to the pond's at `CASCADE_SLOPE` where the river enters
  (`WaterMeshBuilder._inflow()`, a sheet like a riffle's, no collision). (2) The fall's foot: the
  painted curtain faded out 0.12 to 0.42 m over the pool and the ring's foam was a point, so the
  shaded face showed between the curtain and a pool whose head was a crisp dark-blue line; now the
  curtain runs 3 cm under the pool (`BOTTOM_SINK_M`, a 4 cm tear) into a foam line across its whole
  width with a solid core (`RING_FOOT_HALF`, `RING_CORE`), and its glass is the river's blue
  (`GLASS_MID_SHARE` 0.7, `GLASS_ALPHA` 0.78; it was a grey film at 0.25 to 0.5 alpha over the
  shaded face), the brink's glass 8 cm long in the shallow wash. (3) The short ankle fall's bottle
  neck: the cross-section's soft toe (`TOE_SOFT_M` 0.25) lifted the middle of a 1.1 m channel to
  4 cm under the level as the bed rose over the pool tail; the fall profile (then `WaterCarve.bed_line()`,
  now `WaterCarve.fall_shape()`, which returns the bank level and a crest share) gives a crest
  share (w) and `section()` keeps the crest flat across there (`MAX_SHORE_SLOPE`,
  `FALL_CREST_TOE_SOFT_M` 0.04; new carves only; hilltop digest re-pinned). Left: a thin light-cyan
  line at the brink, a small pinch at an ankle fall's brink (the lip-tuck ledge), the plunge pool's
  pale steep sides, a two-cell notch at the top of the inflow ramp, and a separate dark block in the
  pond view (the tall ankle fall's upper reach, level 2.89, whose head cap stands over the pond basin).
- **Fall continuity round 2 (card painter-fall-round2, 2026-11-19, look-pending; frames
  `compare/painter_final52_fall_round2/`, notes there).** Probed per sample. (1) The inflow ramp's
  notch and white triangle: samples level with the ramp's start (a float tie, s = -1e-6) were left to
  the river's flat, but the river does not own the pond's mask, so one wet pond sample dropped its
  sheet corner to the pond's level (the triangle) and a dry one showed the ground (the notch); a pond
  sample is never left to the river now. (2) The pond view's dark block and the tall ankle fall's wide
  flat pool were one thing: that fall's upper reach (level 2.889, ankle) was drawn on a plateau the
  pond was later dug into, so its whole area hung over a slope 0.4 to 3.4 m under it (a flat cut
  square along its area, with a run-out slab off its head). The mesh now draws such water as
  perched (`WaterMeshBuilder._perched()`, `hold_depth()`; `docs/systems/water.md`): it falls from the
  held water at `PERCHED_SLOPE` and runs down the slope as a film. (3) The square shoulders where the
  river meets the pond: the river's flat stood over the pond's dug rim out to its area's edge; the
  same perched rule takes the banks it lost, and the inflow ramp falls to the sides past the channel.
  (4) The brink's cyan hairline was the curtain's 8 cm shallow-wash tongue; it is gone (the curtain's
  glass runs to the lip). Left: the short ankle fall's pinch (the crest's ground at the lip line
  stands over the curtain's outer columns: widening the curtain did not show, a carve matter), the
  plunge pools' pale walls, small steps at the pond's upper shoulders, and two small dark-blue spill
  faces beside the tall ankle fall's lip pool.
- **One fall white (card painter-fall-frame-foam, 2026-11-19, look-pending; frames, metrics and
  notes in `compare/painter_final64_fall_frame_foam/`).** Stage 1 of the fall spike's plan
  (`compare/painter_final63_fall_spike/`, approach 1 made production). Each fall's frame
  (`WaterFallFrames`, `docs/systems/waterfalls.md` "Fall frames") rides in CUSTOM0/CUSTOM1 of the
  water surface and the curtain, read through flat varyings, and
  `painter/shaders/painter_fall_white.gdshaderinc` draws one white from it: over the brink a
  gradient (the river whitens over its last 0.7 m to full white at the lip, the curtain's streaks
  return by 0.8 m down), at the foot a two-valued churned white whose reach grows with the drop,
  and past it a halo of the same foam fading to the pool's wash over about a metre. The curtain's
  own lip roll and the painted foam ring (its shader branch and constants) are gone; the ring's
  vertices stay in the mesh for Classic and collapse in the painter shader. Round 2 had a white band
  starting 0.55 m up the river and a separate pale turquoise halo shape: the band raised the lip's
  step (dL 9.9 -> 12.3) and the halo read as a stripe with a dark sliver under the white; round 3
  made both gradients. Continuity probe, 27 captures per look (9 cases x 3 time samples, half size,
  round 3): lip dL 6.8 -> 5.8, foot dL 25.4 -> 3.4, foot bands 1.11 -> 0.11. The fades read soft,
  a little airbrushed, against the painted wash. Left: the classes this does not touch (C1, C2
  pinch, C5 pale walls, C6, C7 head slab; stages 2 to 4 of the plan).
- **Known gaps** are listed in the matrix with their effort: round and profile roofs (procgen
  records). The settlement furnishings and the field plants were filled by painter-village-parity
  (next section).

## Village furnishings (card painter-village-parity, 2026-11-18)

Three village classes that drew Classic beside painted houses now have a painted form; the frames are
in `docs/research/2026-11-09-prototypes/compare/painter_final37_village/` (`notes.md`).

- **Settlement props** (`AuthoredSettlements`: one MeshInstance3D per 48 m cell, one surface per
  `role:kind`, shared materials). `PainterVillage` (`painter/painter_village.gd`, a RefCounted made by
  `PainterSurfaces` like `PainterBuildings`, event-driven by `child_entered_tree` on the map and the
  layer, never polled) swaps the material of every `prop:*` surface except `prop:glass` for a
  stand-in on `painter_prop.gdshader` and puts the original back exactly on release. The layer now
  stamps each material with its key (`AuthoredSettlements.PART_META`, `tt_part`) so the host can tell
  the surface from the mesh alone. One stand-in per kind (`free`, `stone`, `thatch`), shared by every
  cell. Which of the eight sheet ramps a vertex takes is chosen by its procgen paint
  (`prop_tone`: honey and brown the timber, gold the thatch, red, orange and pink the clay, green the
  turf, blue, teal and violet the slate, cream the plaster, grey the wall stone; `tone_of` is its GDScript twin
  for the tests), so a market is still red, blue and gold cloth over honey wood; the ramps are the
  buildings' (`PainterBuildings.ramp`), so winter, dusk and the elevation tone props as they tone
  houses, and in winter up faces take the roof snow's ramp in a scalloped cap. How light the paint is
  picks the sheet's variant, so two barrels are never one brown. The shader is the selector light of
  the buildings (shade, middle, lit by N.L, the sun's `ATTENUATION` for cast shadow) and never
  discards (the shadow-twin and TREE_FAST rules hold trivially).
- **Baked decor** (`decor_baked`: the ivy, planters and flower boxes of a structure baked into one
  ArrayMesh with shared wind materials). `PainterVillage` swaps each surface for the plants' stand-in
  (`PainterSurfaces.stand_in_of`, now static): bark (a material named `*bark*`) in the SOLID kind,
  leaf in the WALL_LEAF kind since card painter-roofs-ivy (below; a leaf-mass kind would read the
  node origin, which is wrong for baked geometry),
  toned by `PainterPlantTone.tone` (moved out of `PainterSurfaces` at the glb-parity merge to stay under the file cap); one stand-in per original material, shared across the
  structures. The non-bakable decor MultiMeshes (`decor_<asset>`) are not covered.
- **Field plants** (`AuthoredFieldPlants`: orchard trees, garden flowers and shrubs, hedges, crops).
  The layer now answers like a scatter (`rows_by_asset`, `resolved_species`, signals `cells_applied`
  and `species_added`; its meshes come from `PaletteLibrary.resolve`, which duplicates per call, so it
  reports the ones it resolved). `PainterSurfaces` binds it as a plant source
  (`_is_plant_source`; `_scatters` is now an untyped Array) and `PainterTrees` draws its mapped tree
  and bush rows as stroke crowns, exactly as for a scatter, hiding the GLB chunk nodes; the rest wear
  the plants' stand-ins. Seasonal behaviour is the sheet's, like every painted plant.
- **Left Classic on purpose:** `prop:glass` (lantern glass) and water parts (lights; the lantern's
  halo is painted since card painter-village-polish, below). Cloth no
  longer sways (the Classic cloth wind is on the Classic material). Planter flowers lose their petal
  accents (the decor stand-in is a solid).
- **A/B switches** for measurement: `PainterVillage.furnishings`, `decor_plants`, `field_plants`
  (all in `PainterStateReset`); read at paint time, so release and paint again.
- **Classic is untouched**: a map never painted never loads `PainterVillage`'s stand-ins, and the
  Classic-pinned tests compare material identity before and after a paint and release.
- **Cost** (pinned procedure, home camera, GPU ms, Painted minus Classic, pairs x3): a two-street
  village with fields, winter -0.57 and summer -0.52 (Painted before the card: -0.30 and -0.32); the
  12-loose-house village, winter -1.13 and summer -0.93 (unchanged by the card: it has no props or
  fields). Raw numbers: `compare/painter_final37_village/notes.md`.

## Village polish (card painter-village-polish, 2026-11-19; look-pending)

Frames and the bisect: `docs/research/2026-11-09-prototypes/compare/painter_final40_village_polish/`
(`notes.md`). Owner answers 2026-11-19: lighter, warmer timber; the winter village roofs' snow reads as
flat splotches.

- **Roof snow of the street lots was never bodied.** The manner houses' blanket (above) did not
  regress (frames at 5b3c08f0 and main are the same). The flat splotches are on roofs that have no
  manner records: the street lots', wall rows' and boundaries' roofs, Classic until painter-coverage
  (bf4d0219) painted the wall layers (`PainterBuildings.WALL_LAYERS`) with the A3b fallback shader
  (`painter_structure.gdshader`), whose snow was `snow_cover`'s patchy tint. Those roofs now take
  `roof_snow_body` (`painter_structure_common.gdshaderinc`, A3b only): in winter's `roof-snow`
  the snow covers most of a slope in broad brush-edged masses from two noises (a metre and a third of
  one), has a continuous lip along the eave whose first stretch is the layer's shaded face, bare
  stretches opening above the eave, a heaped ridge, an inner edge band that falls into the snow's
  shade and an outer band that casts a shadow on the roof; the snow's shading normal is tilted along
  the fall line by a 1.7 m noise so it has broad lit swells and blue hollows (`shade_n`; the face's own
  `up` and the marks keep the plain normal), and no roof mark shows under it (the course dashes read
  as a grid of ticks). Still discard-free, no new texture reads; `snow_cover` stays for the
  hand-drawn shader's `snow_body` false A/B. A GDScript twin is not needed (shader only; a test pins the
  names).
- **Plank walls.** The wall layers' `Wood` part maps to `wall_boards` (honey boards, the pattern
  with seams), not `trim_wood` (the dark beam role): the street lots' bodies and fences read as wood,
  not chocolate slabs.
- **Props' wood is lighter and warmer.** `PainterVillage.prop_wood_middle(timber)`: the timber role's
  middle tone with its lightness times `WOOD_VALUE` 1.7 (at most `WOOD_MAX_L` 0.8), chroma times
  `WOOD_CHROMA` 1.45 and hue turned `WOOD_TURN` 14 degrees toward honey; relative, so dusk and grimdark
  timber stay dark and winter's follows the sheet. `PainterBuildings.ramp` takes an optional `middle`.
  `painter_prop.gdshader` spans a wood paint's darkness over its own range (0.2 to 0.82, not 0.6 to
  0.92), so fences (paint 0.45) take the middle of the ramp and posts (0.24) the dark end.
- **Lantern halo.** The halo surfaces (`prop:glow`, a quad of four coincident vertices) were being
  swapped for the prop shader and so drew nothing in Painted. `PainterVillage` now gives them
  `painter_glow.gdshader` (`GLOW_SHADER`, one shared material, sample `glow` in `PainterWarmup`): the
  Classic billboard (UV corner, UV2 half-size) painted as three soft-edged steps (a wide amber wash,
  a warmer middle, a pale core) with a torn outline (the radius wanders with the angle), blended over
  the scene, no discard. Lantern glass stays Classic.
- **Frames of what had none** (owner, "show me those first"): decor_baked ivy, flags and flower boxes
  (all four surfaces on `painter_plant.gdshader`; game camera and eye level), the grimdark village,
  lamps and cloth: `notes.md`.
- **Not done:** baked ivy is a solid flat green with no lit or shaded form at eye level; cloth does
  not sway and a flag's tone follows the slate ramp (a dark navy); the street lots' roofs show
  camouflage-like variant patches in grimdark (the A3b patches); fences read tan-grey beside the
  honey barrels at noon (the timber ramp's shade turns away from honey).
- Tests: `test_painter_village.gd` (the swap and exact restore, Classic lights kept, a cell baked
  later, the layer made later, the tone rule, mood and sun, decor stand-ins and restore, field
  plants as a source, orchard trees drawn by `PainterTrees`, the A/B switches, no per-frame hooks);
  `test_painter_warmup.gd` lists the prop shader.

## Fields (card painter-fields, 2026-11-19; look-pending)

The coverage verification's top gap: under Painted a crop field's earth (`dirt_opening`) sorted into
the forest floor's moss green (`opening` is a floor word), its crops were thinned and toned as the
meadow's grass and drawn as round dab mounds (shrubs at the eye), and its hedge bushes took the light
bush green, so only a flowering field read. `PainterFields` (`painter/painter_fields.gd`):

- **The ground.** A field map (R8, one texel per height sample, nearest: the index of the crop or
  garden field whose disc covers it; null and a `field_present` false with no field) and per field
  two vec4 and an int (`f_geo`, `f_row`, `f_kind`: centre, radius, the rows' angle; the first row's
  offset, the count and the pitch; style and crop), at most 32 fields. `painter_field.gdshaderinc`
  paints, in `ground_at` over any role but rock and char: a soil disc (VillageFields.DISC_FACTOR, rim
  moved by the ground's noise) and over it the crop's rows as long strokes (1.7 m, each its own value
  and taper, 0.34 m half width, the row line wandering a little), a darker furrow line midway
  between rows and a headland of bare soil where the rows stop (VillageCrops.ROW_REACH). The rows are
  exactly the plant rows `VillageCrops.plants_of` plants, so the plants stand on their painted rows.
  A garden's beds are soil capsules (VillageFields' bed layout) a step darker (peat). Under 2.5 px a
  row the stripes fade to their mean. The ground's marks are not searched inside a field
  (`field_inner`): its rows are its strokes; a mark asked at its middle near the rim takes the field
  there, so the rim is brush marks. Bound with the path slots (`PainterGroundPaths.bind`, `tones`,
  `set_tones`), so `painter_surfaces.gd` did not grow.
- **Tones.** The soil is the mood's `path` turned to `soil-hue` (66), chroma times `soil-chroma`
  (1.25), lightness `soil-lift` (-0.19). A crop is the sheet's `grass` moved by `crop-own` of the way
  its plant's own colour (`own_of_asset`: the texture mean of the asset's first non-bloom surface,
  cached) stands from the meadow grass's (hue whole, lightness 0.7, chroma by its ratio to 0.8),
  then `crop-lift` and `crop-chroma`; barley's own is half way to its gold coat surface
  (`grass_savanna`). The hue move fades as the mood's grass leaves the meadow green (`GREEN_HUE` 135,
  `GREEN_SPAN` 55: winter's straw grass is every crop's straw; round 1 turned ripe wheat salmon over
  snow). `field-snow` (winter 0.75) lays snow over the crop strokes and all of it over the soil; the
  furrow lines stay soil.
- **Crop plants.** `AuthoredFieldPlants` marks a crop asset's record `crop`
  (`VillageCrops.PLANT_ASSETS`); `PainterPlantRoles.of_record` passes it through
  `PainterFields.plant_entry` (the entry gets `crop` and the measured `own`). `PainterPlantTone`
  tones a crop grass by `crop_lch`, never thins a crop (`keep` 1) and sets `tuft_blades`, which turns
  the wide-tuft dab cut off (`painter_selector`'s `tuft_wide`): the texture's blades stand, so at the
  eye a row reads as a standing crop. A crop flower (the flowering field's daisies) is only unthinned.
  Barley and young share the meadow grass asset, so their plants are one green; only their bands
  differ.
- **Hedges.** `AuthoredFieldPlants.rows_by_asset` and `resolved_species` key a hedge bush
  (`VillageFields.HEDGE_SHRUBS`, field hedgerows and hedged boundaries) as `hedge:` + its id;
  species.json maps `hedge:` to the bush species `bush_hedge` (tree_roles.json: the bush's leaf
  times `bush-value` 0.76, `bush-chroma` 0.92, turned `bush-turn` 10, `dry-share` 0.55), so the ring
  is a deeper, cooler green than the meadow's bushes and a rust in autumn. The GLB chunk nodes keep
  their asset names, so PainterTrees hides them as before.
- **A/B switch.** `PainterFields.enabled` (in `PainterStateReset`): false paints as before the card
  (no field map, crops as meadow grass, the hedge in the bush tone). Read at paint time.
- Frames: `docs/research/2026-11-09-prototypes/compare/painter_final50_fields/` (notes.md; round 2
  is the verdict). Cost not timed with the pinned procedure (one R8 fetch per ground pixel where a
  map has fields, two in the mark search's gate; crops unthinned add plants).
- Tests: `test_painter_fields.gd`.

## One roof snow (card painter-roof-snow, 2026-11-18; look-pending)

Frames: `docs/research/2026-11-09-prototypes/compare/painter_final45_roof_snow/` (`notes.md`, before,
r1, full). Owner answers 2026-11-18: the roof snow reads as flat splotches, "make it feel softer and
with more body", "why don't these share an implementation for snow coverage?", the manner houses
"much patchier"; lantern halos "tone it down a little"; "warmer fences too".

- **One implementation.** `painter/shaders/painter_snow.gdshaderinc` is the only roof snow: the
  hand-drawn blanket (code 10) and the roof pieces under it, the hand-drawn roofs with no record
  (round and Taper roofs, and every roof while `PainterMannerHost.snow_body` is off), the A3b roofs
  of the street lots, wall rows and boundaries, and the props' up faces all call it. `snow_hold` (a
  face's share by its slope), `snow_cover_of` (whole, none, or long soft streaks down a steep run,
  never a veil), `snow_gap` (a few short soft gaps along the ridge: the only bare roof),
  `snow_paint` (the blanket's broad washes, swells and hollows and the dabs that move the light's
  turn, now shared), `snow_roll` (for a layer with no mesh: the shading normal rolls over the eave
  in a lip, a 0.2 m front in the blue shade under a lit roll, a lit heap at the ridge, a slow
  drift), `snow_frame` (a face's metres along the eave, up the slope and to the eave and the ridge,
  from h's screen-space rate against height, so a lip is the same width on any roof),
  `snow_marks`, `snow_warm`, `snow_sky_shade`. `snow_cover` (the cow-spot patches),
  `roof_snow_body` and the props' scalloped cap are gone; `p_n2` and `p_wash` moved to
  `painter_noise.gdshaderinc`.
- **Calmer blanket.** The blanket's verge stretches, eave strokes, flecks, `thin` veil and dry
  grain are gone; only the shared ridge gaps show the roof's colour.
- **Light on snow.** The A3b and prop shaders turn the light over a soft step (0.06) pushed by the
  layer's dabs, as the blanket does, and on A3b snow a point is in cast shadow only under 0.3 of the
  light (the hand-drawn roofs' threshold): a grazing sun's partial self-shadow drew a diagonal hatch
  of ticks across the street roofs.
- **Fences.** The wall layers' `Wood` part (street lots' planks, yard fences, window frames,
  bridge decks) is `lot_wood`, role `LOT_WOOD_ROLE`: the props' honey
  (`PainterVillage.prop_wood_middle` of the timber) at `LOT_WOOD_CHROMA` 0.85 of its chroma
  (`PainterBuildings.lot_wood_middle`), so a fence matches the barrels and a plank house is honey,
  not orange (since painter-walls-round3 a street house's planks take the calmer `house-wood`, below).
- **Lantern halo** (`painter_glow.gdshader`): the wash reaches 0.84 of the quad (`reach`), alphas
  0.15, 0.34, 0.88 (were 0.22, 0.45, 0.95), energy 1.12 (was 1.25).
- **Cost.** No texture reads; on winter roofs the A3b layer evaluates about 34 hashes (the
  blanket's paint) where `roof_snow_body` took about 24; the props' cap adds the layer's 2D noises
  in winter only. Not measured on the lane (no new texture fetch).
- **Not done:** a roof with no blanket mesh (street lots, round roofs) has its body only in
  shading, not geometry: no overhanging lip or verge roll, so it still reads flatter than the
  hand-drawn houses at home zoom; A3b knows no verge distance; steep spires (the wizard tower)
  hold no snow (since card painter-roof-polish a cap and ledges, "Roof polish" below); a few tiny
  dark specks where a ridge gap meets a far roof's ridge.
- Tests: `test_painter_buildings.gd` (every roof and prop shader includes the layer, no old
  coverage left), `test_painter_manner.gd` (no veil, grain or bare strokes), `test_painter_coverage.gd`
  (`Wood` is `lot_wood`, its middle the props' honey at 0.85 chroma in three moods).

## Round roofs, ruin roofs, ivy (card painter-roofs-ivy, 2026-11-18; look-pending)

Owner, 2026-11-18: "Fix ivy and roofs next", and of the grimdark streets "why is everything so
splotchy?". Frames and notes: `docs/research/2026-11-09-prototypes/compare/painter_final48_roofs_ivy/`
(`notes.md`; `before/`, `r1/`, `r2_full/` the verdict).

- **A roof with no manner record follows its paint.** Round and Taper roofs (round hut, roundhouse,
  yurt, dome hall, tulou, trullo, windmill caps, the towers' spires, pagoda) carry no record (CUSTOM0.z
  0), and `roof_tone` sent every paint that was not red or brown to slate, so they read one blotchy
  blue-grey. In `painter_structure_manner.gdshader` such a roof piece (pattern 5 or more, pick 0 to 2)
  reads its recipe paint (the vertex colour) once per vertex: a picked roof takes the role nearest the
  paint's hue (`paint_roof_tone`: red and orange clay, ochre and brown shingle, green turf, blue and
  violet slate), and the role's ramp is turned in OKLab from the role's reference tone to the paint
  (`paint_turn`, `paint_turned` in `painter_structure_common.gdshaderinc`): the hue by their
  difference, the chroma by their ratio (0.5 to 2.6), the lightness by theirs (0.82 to 1.22). The
  reference is the role's middle in summer (`PainterBuildings.paint_refs`, uniform `paint_ref`, set on
  manner roof materials only), so the turn is relative and each mood's own moves of the role carry
  over (grimdark's round roofs are a muted brown-red, not summer's terracotta). A grey paint (chroma
  under `PAINT_GREY` 0.04) keeps its role and hue and takes only the ratios (a cream felt yurt). The
  turn is per vertex (a flat varying) plus three OKLab round trips in the fragment; no texture reads.
  These roofs also take half the variant patches and the lit dabs at half (`loose_roof`).
- **Ruin roofs** are their roof kind (Fire, above); nothing new is needed, the hold is gone.
- **Calm street roofs.** The camouflage patches on grimdark's street roofs (A3b, the wall layers) were
  the light step, not the variants: grimdark's `tone-hi` 0.66 under a 25 degree sun sets a slope's N.L
  right at the step, and the step's 0.12 wobble and the 0.5 cast threshold (partial self-shadow) broke
  each slope into lit and mid patches. A bare A3b roof now steps with 0.03 of wobble, 0.02 of
  softness and the snow's 0.3 cast threshold, so a slope is lit or not as one plane. The roof family's
  variant spread is also held to a share of a dark roof's lightness (`PainterBuildings.roof_spread`:
  lightness over `ROOF_SPREAD_L` 0.5, at least 0.4), which alone did not calm them (`r1`).
- **Ivy has leaves.** Plant kind 5 (`PainterPlantRoles.KIND_WALL_LEAF`, the decor's leaf surfaces) is
  drawn on the card's face normal (`cross(dFdx, dFdy)` turned toward the eye, since the baked normals
  are the wall's) as a 0.2 m Voronoi of leaf dabs (`ivy_dab`): each dab's normal tilts toward its
  edge, takes its own variant and value, and its rim tucks darker; under 6 pixels per dab the dabs
  fade to the plain face, so the game camera sees a calm mass. It takes the crowns' ramp (the bushes'
  green) and the plants' frost on up faces, so winter ivy is green with snow on top, not white.
- **Not done:** the tulou reads a lighter grey than Classic's dark grey-brown; the crystal spire is a
  more saturated azure than Classic's pale aqua; steep spires still hold no snow.
- Tests: `test_painter_buildings.gd` (the reference tones on a manner roof, the turn's functions in the
  shader, a dark roof's variants swing no more than summer's, a wall keeps its spread),
  `test_painter_village.gd` (leaf is WALL_LEAF, bark SOLID, the ivy takes the crowns' ramp),
  `test_structure_burn.gd` (a ruin's roof is painted as its kind, burn 0).

## Street roofs follow their paint (card painter-roof-clay, 2026-11-19; look-pending)

The coverage verification (painter_final49, addendum item 3): a street's red tile roofs read
mud-brown with dark blotches under Painted, its orange roofs brown and its green ones slate. Frames
and notes: `docs/research/2026-11-09-prototypes/compare/painter_final51_roof_clay/` (`notes.md`;
`before/`, `r1/`, `r2_full/` the verdict).

- **Cause (a headless probe, `jobs/roof_probe.gd` there).** A street lot's roof is the wall node's
  `Roof` part (procgen's `wood` kind), which `WALL_PARTS` mapped to `roof_wood`: the A3b shader's
  wooden roof (pick 2), whose `roof_tone` never takes the clay. Terracotta (OKLab hue 32) and orange
  (hue 47) paints fell to the shingle (C0.061 against the clay's 0.134), and `roof_tone` sends every
  hue from 100 to the slate, so a green paint drew blue. The sheet's clay was never the problem (L0.55
  C0.134 h34 against the terracotta paint's L0.61 C0.148 h32).
- **The fix.** `Roof` is `roof_tile` (Classic draws it with the structures' tile shader), and the
  A3b shader's picked roofs (pick 1 and 2) follow their paint the way the manner's round roofs do:
  the role nearest the paint (`paint_roof_tone`: red and orange clay, ochre and brown shingle, green
  turf, blue and grey slate) and its ramp turned from the role's summer middle (`paint_ref[4]`, set
  by `_tone` on every roof material now, not only the manner's) to the paint (`paint_turn`,
  `paint_turned`). Relative, so grimdark's street is a muted brown-red, not summer's terracotta.
- **Calmer slopes.** An A3b roof takes half the variant patches, half the lit dabs and a quarter of
  the dark dabs (the dark dabs pull a tile toward its violet shade and read as damp stains); the
  hand-drawn slopes are as calm.
- **Cost.** One OKLab conversion and the turn per vertex, three OKLab round trips a fragment on a
  picked roof; no texture reads. Not timed on the lane.
- **Not done:** the A3b tile's per-piece variant still reads as a patchwork of lighter and rosier
  tiles at zoom 16 where Classic is a smooth red; a hip face's course dashes run down the slope and
  read busier than a gable's; the street's fixed-kind roofs (`Roof_shingle`, `Roof_slate`, ...)
  keep their role's colour, not their paint's. (All three done by card painter-roof-polish, below.)
- Tests: `test_painter_buildings.gd` (a street lot's roof is a picked tile roof, its A3b material
  carries the four reference tones, a wall's none, the shader turns and reads no texture),
  `test_painter_coverage.gd` (`Roof` is `roof_tile`).

## Roof polish (card painter-roof-polish, 2026-11-19; look-pending)

The gaps the roofs-ivy, roof-clay and roof-snow cards left. Frames and notes:
`docs/research/2026-11-09-prototypes/compare/painter_final55_roof_polish/` (`notes.md`; `before/`, `r1/`,
`r2_full/` the verdict).

- **Steep roofs carry snow.** A spire's cone faces up only 0.25 to 0.35 (a headless probe: crystal spire,
  wizard tower), under `snow_hold`'s 0.24 to 0.42 ramp, so it held nothing or a half hold drawn as long
  streaks, which on a dark spire read as a glossy highlight. Both roof shaders now take
  `snow_cover_roof` (`painter_snow.gdshaderinc`): the layer by slope where a face holds it, and under
  about 0.4 of up `snow_steep` instead: a cap over the upper third (`h` from 0.52, its edge in soft
  tongues) and thin broken ledges every `SNOW_LEDGE_M` 0.6 m below it, sparse near the eave and closer
  toward the cap, evening out to a light share where a ledge is under a few pixels. Near-vertical faces
  and undersides hold none. The props keep `snow_cover_of(snow_hold(...))`.
- **Calm street tiles.** The A3b shader's tiles, slates and shingles draw soft course banding: a shadow
  under each course's lip across the whole slope, each course a touch apart (a hash per course, 0.14 of
  variant), the slope lighter toward its ridge (0.16 of light by `h`), fading before a course is under
  about three pixels. The per-tile variant (the patchwork of lighter and rosier tiles at zoom 16) and the
  broken dashes (busy ticks on a hip face) are gone.
- **Fixed-kind roofs follow their paint.** A street's `Roof_shingle` (alpine hamlet) and `Roof_slate`
  (modern row), and any structure's slate or shingle roof in the A3b look, turn their ramp from their
  kind's summer middle to the paint (`paint_turns`), as the picked roofs do. Their paint is grey only under
  `PAINT_GREY_KIND` 0.015 of chroma (`paint_grey`; a picked roof's stays 0.04): the kind fixes the role,
  so the paint's hue is the only colour cue (alpine's blue-grey shingle, C 0.026, drew brown). A slate
  takes the nearest of its material's own three ramps (slate, the moss's leaf, the ridge cap's clay:
  `paint_slate_tone`), since the slate's lit step is near grey (the sun's yellow pull cancels its blue)
  and turned 146 degrees to a modern row's peach paint it drew pink (`r1`). The manner shader's roofs with
  no record take the same threshold and slate choice.
- **Pale and dark paints land.** `PAINT_VALUE` is 0.7 to 1.5 (was 0.82 to 1.22): the crystal spire's pale
  aqua is 1.45 times its role's lightness and drew a darker, more saturated azure. A tone the ratio lifts
  past `PAINT_KNEE` 0.8 rolls off toward white (`paint_turned`) instead of clipping.
- **Not done.** The tulou: its paint is a light blue-grey (L0.58 C0.020 h249, the probe), the turn
  already lands its middle there, and its near-flat ring sits in the lit step; Classic's dark grey-brown
  is Classic's own course shadows and warm ridge grade, not the paint. The crystal spire is still bluer
  than Classic's aqua (its shade step's blue pull turns with it). The ledges read crisp and thin up close.
- **Cost.** No texture reads. Winter roofs: two more 2D noises a fragment on a steep face; the tile
  banding replaces two hashes with one; the knee four ops per turned tone; the slate choice per vertex.
  Not timed on the lane.
- Tests: `test_painter_buildings.gd` (a slate or shingle street roof turns from its kind's summer middle,
  the slate's third ramp is the clay; a pale paint lands; both roof shaders take the roof cover, the
  props the layer by slope; A3b tiles band by course with no per-tile variant or dashes).

## Roof round 3 (card painter-roof-round3, 2026-11-19; look-pending)

Owner verdicts on the roof-polish frames, taken one by one (evidence:
`docs/research/2026-11-09-prototypes/compare/painter_final60_roof_round3/` in the suite root).

- **Tile banding calmer** (l55_tiles, "Banding too strong"): A3b's course shade is 0.08 (was stronger)
  over the lower half of each course, and the band's tone variant 0.05; the courses stay as a hint.
- **Grey by saturation** (l55_flat: the trullo at the right edge went partly brown). `paint_grey(lab,
  pick)` in `painter_structure_common.gdshaderinc`: a fixed kind (pick 0) is grey when its chroma is
  under `PAINT_GREY_KIND` (0.028) times its lightness, not under a fixed chroma. The per-face paint
  jitter is value-only, so a fixed chroma split one roof: its dark faces passed as grey and its light
  ones turned to the brown ramp; by saturation all of them stay grey (probe: the trullo's paints
  (0.267,0.251,0.216) and (0.188,0.173,0.149) are grey; every fixed-kind street roof paint measured
  0.034 or more and still turns, unchanged).
- **One bodied cap on steep roofs** (l48_round_w, "streaky and weird"): `painter_snow.gdshaderinc` drops
  the ledges (`SNOW_LEDGE_M`, `snow_steep`); `snow_cover_roof(snow, up, h, f)` lays one cap down from
  the top to an edge (`snow_edge`: low on a steep face, a slow sway and tongues along it), and
  `snow_edge_m` gives the lip's roll its distance to that edge, so the cap ends in the same rolled lip
  an eave has. Both roof shaders (A3b and the manner's no-record branch) call the one pair.
- **Street roofs wear the blanket** (l45_snow, "More body"): `PainterStreetSnow`
  (`painter/buildings/street_snow.gd`) reads a wall layer's roof part back into manner roof records
  (up faces, joined into slopes by shared edges in one plane, the outline's sides named eave, ridge,
  hip or verge) and builds `PainterMannerSnow.build`'s blanket on a worker, a "StreetSnow" child of the
  roof part drawn by the manner's snow material, no shadow. Neighbouring lots' verges side by side
  become hips (`_join_verges`). Built while the mood lays roof snow, freed when it stops.
  `PainterStreetSnow.bodied = false` is the A/B switch. Measured in the street test level: 4 blankets,
  20300 triangles; 3.5 to 56 ms a row on a worker.
- **Hand walls' long trim cut** (l43_cottages, "geometry poking out of the roof"): on a stone house with a
  mason's hand (`hand_at` sags the eave and ridge), a long piece that is neither wall, roof nor beam (a
  cornice, a string course) is cut every `WALL_SEG_M` as the walls are (`manner_mesh.gd`); left whole,
  its straight middle stood out of the sagging roof as a pale lens on the townhouse.
- **Not done.** A brown slit runs down the street snow under each chimney (the roof shows through the
  blanket there; `_join_verges` did not close it, so the slope's pieces around a chimney need a probe).
  A thin pale hairline may remain on the townhouse's eave. Street lots of neighbouring streets overlap
  when two streets are placed closer than their lots reach (l51: the test jobs put streets 14 m apart and
  each side's lots reach 5.5 to 7 m); nothing stops it yet.
- **Cost.** The steep cap is cheaper than the ledges (one noise for the sway against two ledge noises);
  the street blankets add their triangles above. Not timed on the lane.
- Tests: `test_painter_street_snow.gd` (a gable's slopes and sides, a hip roof's hips and apex, a narrow
  board and a flat roof, neighbouring lots' seam, a winter wall layer's blankets, grey by saturation);
  `test_painter_buildings.gd` (one bodied cap in both roof shaders).

## Roof round 4 (card painter-roof-round4, 2026-11-19; look-pending)

Evidence: `docs/research/2026-11-09-prototypes/compare/painter_final68_roof_round4/` (notes.md, jobs/).

- **The slit beside every street chimney.** It was the blanket's own crest gaps (`snow_gap`, drawn in
  the roof's tone by the manner shader's code 10): a wall layer's blanket lays every lot's slopes
  in one frame from the lot's corner, so the gaps fell at the same place on every house of a row,
  beside its chimney, and read as a brown slit (final60 st_win_z9_p and z30). The manner shader has an
  `instance uniform float scour` (1 on the hand-drawn houses, where the gaps stay); PainterStreetSnow
  sets 0 on each blanket. A headless gap probe (a grid of downward rays over roof and blanket) found
  no hole in the blanket on the level's street, so the geometry was never the cause. Also, a street gable's two slopes
  end 6 to 10 cm apart across a flat ridge board, and each blanket crested over its own side, leaving
  a bare line on the ridge headless (map seed 9): `PainterStreetSnow._join_ridges` carries both ridges
  to the board's middle (a pair parallel, level within `LEVEL_M`, `RIDGE_JOIN_M` 0.2 apart at most).
- **The market's bare orange ends.** Not slopes: the guild and market species clad their gable ends in
  roof tile, upright triangles inside the Roof part (up 0, h 0 to 1), and `snow_cover_roof` gave an
  upright face nothing. `snow_gable(up)` in `painter_snow.gdshaderinc` covered a roof's upright faces
  (removed in roof round 5: a gable holds no snow);
  only the A3b roof shader calls it (a hand-drawn house's gables are walls, and its round roofs keep
  their upright foot). `snow_frame`'s second coordinate is the height on an upright face, so the
  washes do not run as stripes there.
- **Crowded streets** are refused at placement: walls.md "Streets".
- Still seen: short red slashes on the market's ridges near the chimneys (the A3b roof shader's own
  `snow_gap`, which the blanket does not cover everywhere); preset 6's L-plan roofs still get few
  blankets (strips fallback). Not timed: the ridge join runs on the worker; the gable term is two
  smoothsteps in the A3b fragment; crowding plans nearby rows' lots on each replan of a street drag.
- Tests: `test_painter_street_snow.gd` (a ridge board closes between the crests; a street blanket's
  `scour` is 0), `test_street_crowding.gd`.

## Roof round 5 (card painter-roof-round5, 2026-11-19; look-pending)

Evidence: `docs/research/2026-11-09-prototypes/compare/painter_final71_roof_round5/` (notes.md, jobs/,
before/, probe/, after/).

- **Bare gables.** Owner on round 4's snowed market gables: "would the gables actually have snow on
  them? i don't think they would". `snow_gable` is gone. A3b's tile gables keep their own tile, a cool
  cast (`snow_upright(up)` times the snow: shade 0.4, middle 0.25 and lit 0.15 toward `snow_ramp`),
  faint horizontal courses on the upright face (from world height, faded where a course is under half a
  pixel), the blanket's verge lip along the slope and a little uneven drift at the foot
  (`snow_foot(above, along)`, 8 to 22 cm). `snow_frame`'s height on an upright face feeds the foot.
- **Street roofs keep no crest gaps.** The A3b roof shader also has `instance uniform float scour`;
  `PainterStreetSnow` sets 0 on the street roof part as on its blanket, so the short red slashes beside
  the market's chimneys (the roof's own `snow_gap` where the blanket left it showing) are gone.
- **Steep caps of uneven drifts.** Owner on round 3's cap: "Rework". `snow_edge(up, f, n, seed)` (both
  structure shaders; one implementation) lowers or raises a steep face's edge per facet: a slow noise of
  the facet's facing (continuous round a cone, one value per face of a Taper roof), plus up to 0.3 of the
  run on the side facing the sun (`foliage_sun`), plus two broken edge noises by facing and metres
  along. Lit and shade facets now differ, and the roof's colour shows below a painted edge with its
  lip. Chosen from three in one probe (`probe/sheet_caps2.png`): a high cap with long tongues down the
  shade side read too close to the old one, a small cap with a drift band read as a stripe.
- **The townhouse's eave trim.** The hand's sag moves a roof's eave 1 to 2 cm more than the cornice
  trim under it, so the trim showed through as pale lens slivers on both slopes
  (`before/s1_townhouse_z5`). `PainterMannerMesh._sink_trim` lowers a hand-drawn house's trim and
  cornice vertices by `HAND_TRIM_SINK_M` (8 cm) in a band from 1 m below the eave to 0.6 m above it,
  chimneys excepted. The manner mesh does not build headless, so the fix is checked by frames only.
- **Crowded streets** are nudged: walls.md "Streets".
- Open: the steep cap's edge peaks at each facet seam and reads a little like icing at zoom 10; the
  tile courses on a gable are faint at the table zoom. Not timed: the cap adds three noise reads on a
  steep face, the gable term two smoothsteps and a noise.
- Tests: `test_painter_buildings.gd` (no `snow_gable`, the foot and cool terms, `scour` on the street
  roof, the trim sink), `test_street_crowding.gd`.

## The eye backdrop (card painter-eye-backdrop, 2026-11-18; look-pending)

At the eye the painted sky was a flat gradient over a hard ground line where Classic's `EyeSky`
draws clouds and ridges (`docs/painter-coverage-sweep.md` gap 1). The painted sky now carries its own
backdrop, drawn only at the eye:

- **Shader** (`painter_sky.gdshader`, uniform group `eye`): three hill ranges far to near (two broad
  octaves each, the far ones softer and misting into the horizon toward their feet; the near one cut
  crisp, with a tree-line of round or conical crowns and a wandering canopy in the crown tone, rising
  out of the far-ground tone `foot_color` over 1.6 degrees so the skirt meets it without a line), and
  one layer of cloud banks (six cells per turn, bases 3 to 13 degrees, five lobes plus a body and a
  flat base; lit where a step up and toward the sun leaves every bank, so the lit band follows the
  outline with no seams; three soft-stepped values: underside, body, lit top). `eye_on` 0 skips all of
  it, so the table view draws the old maths; the cubemap pass never draws it, so reflections are the
  gradient's. No TIME, no per-frame uniform writes.
- **Colours** (`PainterBackdrop.uniforms`, set by `PainterScene` at every take): aerial perspective in
  the mood's air, mixed in OKLab from existing tones only (no new sheet roles or numbers): near range
  the ground 15 % into the haze at 0.9 of its lightness, middle 45 % into the haze and 20 % on toward
  the sky, far the haze 50 % toward the sky and 0.14 deeper, tree-line the leaf 12 % into the haze at
  0.78 lightness, sunlit tops the near range 40 % toward the sun; a cloud's lit top the horizon pulled
  toward the sun by 0.6 times the sun's energy, its underside the sky lifted 0.02, at 0.6 of its chroma
  plus 0.01, its hue turned 60 % toward the mood's `shade-hue`. Cloud cover follows the sky's chroma
  (0.85 at chroma 0.02 or less, 0.5 at 0.08 or more): grimdark's and winter's grey skies cloud over.
- **Shapes** (`EyeSky`, under Painted): the map's skyline from `StreetSkyLook` (the biome's ridge
  height, lattice period, angularity and crowns; its seed plus the map's), so maps differ
  (`EyeSky.painter_params`). `EyeSky` installs nothing under Painted: it sets `eye_on` and the skyline on
  the painter's material (found by its `painter_sky` meta; it names no painter script, being in the
  start-up graph), and caps `fog_sky_affect` at `PAINTER_SKY_FOG` 0.5 while the eye looks (a preset fog
  at the default 1 painted the whole eye sky flat haze: winter, dusk, grimdark, autumn), putting it
  back on leaving. If Painted takes the Environment while the Classic eye sky is installed (a Settings
  Apply in the eye), the Classic eye's fog fields go back and Painted's sky and haze stay
  (`PAINTER_OWNS`); before this the Classic restore overwrote the painted sky.
- **Frames**: `docs/research/2026-11-09-prototypes/compare/painter_final42_eye_backdrop/`
  (`sheet_eye_moods.png`: summer, winter, dusk, grimdark, autumn, Painted left and Classic right, a
  late-sun turned view and the orbit view). Open: the summer far range at yaw 0 reads as a pale grey-blue
  strip rather than a defined range; no GLB-map seed (a map without a document shares the default
  skyline); cost not timed (the backdrop runs only on sky pixels at the eye; two cloud-field
  evaluations of 18 circles each where clouds can be, three ranges below about 15 degrees).

## Calm walls, ivy contact, plank houses (card painter-walls-round3, 2026-11-19; look-pending)

Owner, 2026-11-19: of the grimdark streets "the walls are still splotchy. the roofs are better"; of the
ivy "any kind of AO or similar we could add or fake to make them feel more grounded on the building?";
of the honey lot wood "Plank houses less honey". Frames and notes:
`docs/research/2026-11-09-prototypes/compare/painter_final61_walls_round3/`.

- **Calm walls.** The tan patches were the wall light step's wobble (0.12 of N.L) at grimdark's tone-hi
  0.66 and a 25 degree sun: a sunward wall sits at N.L about 0.64, on the step (the roofs' cause in
  painter-roofs-ivy). Both structure shaders: a wall's step wobbles 0.03 and turns over 0.03 wide, its
  variant patches are `WALL_PATCHES` 0.55 and its dabs `WALL_DABS` 0.45 of before; A3b's cast edge on a
  wall wobbles 0.1 (`f_soft.w`) and its stone blocks spread 0.6. `PainterBuildings.ramp` holds the
  value-spread to a share of the lightness (`roof_spread`) on walls and stone as on roofs; timber keeps it.
- **Ivy contact** (`PainterIvyContact`, `painter_ivy_contact.gdshader`): each decor wall-leaf stand-in
  gets a next pass that draws its leaf cards again, multiplied (unshaded, no depth, no shadow) over what
  is behind each card's clear texels: one soft round blot per card, let 4 cm down the card and gone
  before its edge, a cool dark tint at 0.45. A clump's cards add up to a soft shade in and round it.
  The library's leaf textures have no mipmaps at runtime, so the shade is a shape per card, not a blurred
  cutout (a first try with the shifted cutout drew dark leaf outlines). `PainterIvyContact.enabled` is
  the A/B switch.
- **Plank houses.** A street row's `Wood` mesh is every wood surface of the row, the houses and the
  lots' yard fences together. `WallGeometry.house_flags` writes UV2.x 1 on a row's wood where the vertex
  is not a yard's (procgen tags a fence `<lot>/yard`); Classic never reads UV2. The `lot_wood` material
  has `house_planks` on and a second ramp, `HOUSE_WOOD_ROLE` (`house_wood_middle`: wall-boards moved
  `HOUSE_WOOD_HONEY` 0.3 of the way to the lot honey), so plank houses read as weathered warm boards and
  fences, drawn fences and decks keep the honey. The warm-up also warms the structure shader in the UV2
  layout.
- **Open:** cost not timed; walls in grimdark read a little flat (raise `WALL_PATCHES` first); no
  under-eave weathering on A3b walls (no top in their data); the contact shade is subtle at the game
  camera.

## Rock bands and ground facets (card painter-ground-artifacts, 2026-11-20; look-pending)

Owner, 2026-11-20: rocks "have shading artifacts which look scratchy and weird"; the terrain "looks
'jagged' and low-res, especially in places where it has been raised or lowered". Frames, the shader
patch and the A/B: `docs/research/2026-11-09-prototypes/compare/painter_final99_ground_artifacts/`
(`repro3` main, `fix3` this commit, `perf` the GPU A/B).

- **Rock bands (shadow acne through the cast step).** The selector light reads the sun's shadow
  attenuation through a narrow smoothstep. On a rock face turned almost edge-on to the sun the shadow
  map's own depth bias leaves faint self-shadowing and the soft-shadow filter's noise; the narrow step
  turned that noise into parallel violet bands with stippled edges. `painter_selector.gdshaderinc` now
  fades the cast by facing (`SOLID_CAST_FACING`: a face under 0.4 of N.L takes no cast, it is already
  in the shade step) and widens the step for a solid (0.35 to 0.65). The ground's steep faces take the
  same fade (`CLIFF_CAST_FACING` in `painter_ground.gdshader`).
- **Ground facets (vertex normals).** The ground shader's cliff role, strata, lip and turned shade read
  `slope = 1 - n.y` from the interpolated vertex normal. The mesh's normals were one-sample central
  differences, so on a carved bank the contour of that slope followed the 0.25 m triangles (a zigzag of
  that size, read as low resolution). `TerrainMeshBuilder.shade_normal` (and the inlined build and
  region-update loops, and the river exit's mesh) take the difference two samples each side, averaged
  [1 2 1] across: `NORMAL_SPAN`, and a height edit now moves normals `NORMAL_RADIUS` (2) samples out
  (`queue_heights` grows its dirty rect by it). The scatter's and the ray casts' normals
  (`ScatterGenerator.vertex_normal`, native) are unchanged, so no scatter digest moved.
- **Cost.** GPU, in-run A/B (docs/PERFORMANCE.md): main against this shader pair, 8 rounds, f1 overhead
  close view 2.008 / 1.999 ms (delta -0.005), wide view 3.563 / 3.548 ms (delta -0.013): neutral. CPU,
  the mesh normal loop over a 245 x 245 grid, 10 ms before and 23 ms after: a full rebuild only.
- **Not fixed:** the shadow staircase on ground at a grazing sun (shadow-map texels stretched by
  1 / sin(elevation)); an orthographic cascade removes the steps but smears, and the far distance has no
  effect. A shadow-map resolution matter, not part of this card.

## Ground shading field (cards painter-ground-robust and -finish, 2026-11-20; look-pending)

The authored terrain's FORM is no longer lit from the mesh. Evidence, scores, the A/B and what is
still visible: `docs/research/2026-11-09-prototypes/compare/painter_final103_ground_field/` (the
build), `.../painter_final105_ground_finish/` (the finish: attribution sheets a1 to a7, the owner
and torture sheets, the score tables) and the card's handoff
(`docs/plans/handoffs/painter-ground-robust.md`, "Build" and "Finish").

- **The field.** `GroundShadeField` (`utils/terrain/ground_shade_field.gd`) bakes one RGBA half
  texel per height sample: the gradient of the band-limited heights (binomial [1 4 6 4 1] twice),
  its convexity, and the nearest steep face (the steepest one-sample step of the raw heights, the
  two axes as one gradient so a face reads the same along the grid and across it, softened), so a
  sheer step under a metre keeps its rock face. A 4-fetch cubic read looked the same on the
  torture set, so the read is bilinear. A GLB map's ground keeps the mesh's normal. The skirt reads
  the same field (below, "The map edge").
- **One rule for every edge the form makes.** `painter_ground.gdshader` reads the field at the
  pixel's map point moved by a brush-scale noise (`EDGE_FREQ` 1.9 per metre, `EDGE_REACH` 0.5 m;
  asked at the 3D surface point so it does not streak down a face, its reach shrunk by the
  ground's tilt and a sheer step near) and takes the normal, the slope, the convexity and the
  steep face from that ONE read. The rock of a slope, the lip, the foot and the terminator are
  hard steps of it. A band-limited field has smooth contours, so a round form keeps a round rock
  ring; the moved read gives every contour a brush's wobble of one size in metres. What it
  replaced, and why: a role per whole mark broke a 7 m cone's ring into mark-sized chunks; a noise
  added to the value moves a gentle form's edge by metres and a bank's by nothing; a step that is
  firm in value (+-0.03) is a blurred band on screen wherever the value turns slowly (the
  purple-grey band under a bank's shade mass was the terminator on sand, whose shade colour is
  the sheet's cool purple). Marks stop at the rock line (0.3), so the rock of a slope is the
  block-in's, and the lip and the foot are not drawn on a face itself (in the map a sheer face is
  under a texel deep: the convexity read on it flips with the texel grid).
- **A cliff's bricks are its strata on a zigzag wall.** A sheer wall turned off the grid is a
  staircase in plan (columns 0.25 / tan(angle) wide), and level strata bands step with it on
  screen. Main draws the same bricks, plus a stripe per facet from the mesh normal; with the
  strata off the face is one flat tone in both. A mesh matter, left alone.
- **Updates.** `PainterGroundField` follows `AuthoredTerrain.ground_edited` and redoes only the
  heights that changed, grown by the field's reach (6 samples); the result equals a full bake bit
  for bit (`test_ground_shade_field.gd`, and checked in the running game after a sculpt stroke).
  245 x 245 samples: 95 ms the whole map, 1.5 ms a 2.5 m dab, 0.55 ms a 1 m dab (GDScript).
- **The terminator is relative, with a floor at grazing light** (card painter-ground-rocks,
  2026-11-20, after the owner's "cleaner, but too much shade"). Ground is shade by its form, one
  hard step of the brush-edged read, where it faces the sun under `TURN_REL` 0.1 of what level
  ground does (N.L / L.y), or under `TURN_NL` 0.07 (about four degrees from edge-on) when that is
  more. The floor is where the shadow map cannot be trusted: with the terminator at 0 the pushed
  back-face caster stipples grazing ground (torture set dots +0.41 with the meadow at 0, ragged
  edges on the falls cliff with the rock at 0), and at a sun elevation of 10 the floor equals the
  0.4 the first build used at every hour. At midday that 0.4 put every bank steeper than 30
  degrees and turned from the sun in shade (29% of the owner's bank view, 27% of the falls view);
  now only ground the sun does not reach is. The old facing fade of the cast shadow
  (`CLIFF_CAST_FACING`) is gone.
- **The foot and the lip.** The foot is drawn only on the rock role (a face's own lower rim) and
  not into the shade colour: on sand it was a lone lilac lens under a shade mass, on grass a dark
  squiggle. The lip stays, lit and in shade (a crest's edge).
- **Two shade values on a cliff.** Rock whose raw steepness (the field's a) is under `UP_STEEP`
  0.3 (a ledge's top inside a cliff's reach) takes `SHADE_SKY`, a step lighter and cooler than the
  wall's shade. The meadow's and the sand's shade stay the sheet's, because the grass and flowers
  on them are toned to it (lighter ground shade made every tuft in a shadow a dark speck). On the
  owner's two views this second value changes almost nothing (their ledges are not level in the
  field); the ledge on the falls view reads again because of the terminator.
- **The block-in's tone steps have brush edges.** The five-step variant of two very slow noises
  (its contours near straight for metres: the ruled diagonals across a bank, gone with
  `patches = 0`) is read at the pixel's point moved by the same brush wobble as the form's edges.
- **Rocks and logs (kind 2)** are shaded by form alone: `painter_solid` asks the shadow map from a
  shell around the asset (`LIGHT_VERTEX` moved out from its middle, never downward, by half its
  half size and at most 0.4 m), so it never takes its own shadow (the dark blotches and jagged
  polygons at a low sun) while the caster is untouched (its ground shadow starts at its foot) and
  what a tree or the terrain throws lands on it in one smooth edge. The form's normal is the
  face's mixed 0.6 to the normal of the spheroid of the asset's box, only near that spheroid's
  surface (a stone inside a scatter keeps its faces); in a cast shadow a rock keeps the bushes'
  half step, so its planes still read. The earlier fade of the cast shadow by facing is gone.
- **A rock's planes and its shade colour** (card painter-ground-rocks-finish). The form's turn
  decides only what is in SHADE (one firm curve); what is LIT or MIDDLE on the sunward side is
  decided a plane at a time (`solid_plane()`, `SELECTOR_SOLID`, set by `painter_solid` only): the
  directions round the rock are cut into about twenty cells (a jittered Voronoi lattice on the
  sphere of the form's normals, `SOLID_PLANES`, each rock its own) and a cell is lit as its one
  direction. A rock under 0.6 m of half size keeps its mesh's faces as its planes (a stone is two
  or three of them), from 1.2 m the lattice's alone (a boulder's triangles drew stair steps). The
  shade keeps `solid_pull` of the ramp's pull, the rest the rock's own colour at the shade's value:
  `PainterPlantTone` sets it half way between 1 and the sheet's `cliff-pull` (wood: 1), since the
  full pull made a boulder's shade side the most saturated mass of a frame. Limits seen: the
  planes show where a boulder's lit side meets its middle step (a low or a side sun); a boulder
  seen from the sun's side at midday is still one pale mass, and its shade side one flat tone.
- **Contact pool, seam and wet band have pixel-wide edges** (same card). The pool and the seam
  were a 0.1 step of the occlusion field and the wet band a 0.14 step of the wet line: where the
  field falls slowly (round a group of stones, along a stream seen close) that was a soft-edged
  dark block or a soft edge a tenth of a metre wide, the only soft tonal edges of the ground. Now
  each step is as wide as a pixel or two, at most what it was. The pool and the seam are also not
  drawn on a sheer face (`role_slope` 0.55 or more), since the field is a plan view.
- **A rock's planes carry three lit values and two shade values** (card painter-rocks-forms,
  2026-11-20; evidence `docs/research/2026-11-09-prototypes/compare/painter_final109_rocks_forms/`,
  handoff `docs/plans/handoffs/painter-rocks-forms.md`). `solid_form()` replaces `solid_plane()`:
  the planes are a jittered Voronoi lattice on the OCTAHEDRAL map of the form's directions (2D,
  four cells and four hashes a pixel where the lattice in space took eight cells and twenty-four;
  `SOLID_PLANES` 2.2 cells a unit, about twenty planes a rock), turned by the rock's own angle
  (`v_turn`, from the vertex stage), and skipped by a branch on a rock under 0.6 m of half size.
  A plane takes its cell's hash as its colour variant (the per-pixel variant noise of solids is
  gone), so a plane is one flat colour. On the sunward side a plane is LIGHT where it faces the
  sun within 45 degrees (`SOLID_LIGHT` 0.7 of N.L), HALF-LIGHT from the sheet's `tone-hi`
  (`SOLID_HALF_T` 0.7 on the ramp), MIDDLE below: a boulder lit all over has a top and sides at
  every sun height. In shade, the form's own or a shadow cast on it, a plane that faces up
  (`SOLID_UP` 0.6) takes the sky's step (`SOLID_SKY`, lighter and cooler), the others the shade
  colour: two values, so a shaded boulder has a top. The bushes' half step toward the sun inside
  a cast shadow no longer applies to solids. The form's turn is still the shade's one firm edge.
  Seen and left: a soft darker smudge on a boulder's lit front where its own shadow's penumbra
  reaches the shell the shadow map is asked from (the cast colour is now the full shade, so a
  partial cast shows more than it did), and the foot's soft darkening (`base_dark`) on a large
  flat plane. Logs (kind 2 too) were not captured.
- **A solid's contact marks are per body, at the height of its foot** (same card).
  `PainterOcclusion` writes one footprint per BODY of a scatter mesh (`islands()`: triangles
  joined at welded vertices, bodies whose plans overlap taken as one, cached per mesh), its seam
  and pool reaching at most half and once the body's narrower half (`solid_reach`; a boulder keeps
  0.22 m and its old pool). The field is 0.25 m a texel (was 0.5) and RGBA half float: b and a
  carry the foot's height (b the height times a weight, a the weight, one over the mark's vertical
  reach, so the bilinear read gives a weighted height and blends to "no limit" beside a footprint
  that has none), and `painter_ground` multiplies the coverage by a fall-off of the pixel's
  distance in height from that foot before the brush's threshold. A footprint under half a texel
  is not drawn. The rebuild writes floats and converts natively (no loop over the texels in
  GDScript). Trees, bushes and structures write the same discs and boxes as before, with no
  height.
- **Stones side by side are separate bodies** (card painter-rocks-forms-finish, 2026-11-20;
  evidence `.../painter_final109_rocks_forms/finish/`). The olive oval round the three stones on
  the falls' left cliff (and round every `Stone_Cluster` on the torture map) WAS the contact
  field: with the field off it is gone, with the seam off the oval goes and the pool stays, the
  tokens' discs change nothing. A dump of every footprint showed the cluster written by
  `_add_solids` as ONE body: `islands()` found its five stones (1632 vertices, 297 welded, 5
  components) and then joined them, because it merged bodies on any overlap of their boxes and
  the boxes of stones set side by side overlap at the corners. One box 0.85 by 0.9 m took a seam
  0.21 m and a pool 0.42 m past it and a vertical reach of 0.7 m, which is the oval and its run
  down the wall. Now only a body that lies mostly inside another's plan (`nested`, `NEST_SHARE`
  0.5 of the smaller's area) is part of it, and a mark's vertical reach is half the body's height
  plus its seam's reach (the body's width is no longer added): a stone 0.4 m across shows its
  mark within about 0.2 m of its foot's height. On the falls' cliff the mark is a small dark
  patch at the stones, about the group's width, with a short tongue (under half a metre on
  screen) below the lowest stone; the wall below is clean. Stones that nearly touch still share
  one patch: three separate marks need more than the field's 0.25 m.
  Cost: the pool and the seam of a body are written in one pass (`_boxes`), over the turned
  box's own extent. The field is no longer rebuilt whole on every change (card
  painter-rocks-forms-merge-ready, 2026-11-20). `rebuild()` runs 0.3 s after the scatter applies
  cells, a structure or the ground changes or the sun's hour does (about every 0.34 s through a
  sculpt stroke), and has three parts: the footprints are collected as marks (arrays of floats; a
  scatter multimesh whose transform and buffer did not change gives its marks from `_held`), the
  marks are sorted and compared with the last bake's (`update`), and a changed field is uploaded.
  When no mark moved nothing is baked or uploaded; when up to `MAX_DIRTY` moved and their rects
  hold under `FULL_SHARE` of the field, only those rects are wiped and baked again from the marks
  that reach them, in the sorted order, so a partial bake equals a whole one bit for bit
  (`test_a_partial_update_equals_a_whole_bake_bit_for_bit`); otherwise (a level load, the trees'
  growth) the whole field. Measured in one run against main adf2ac61's own host on the same maps
  (ms per rebuild; main bakes its 0.5 m field whole every time):

  | | main | this |
  |---|---|---|
  | level load, whole bake, falls map (202 footprints) | 10.7 | 17.4 |
  | level load, whole bake, torture map (313) | 14.8 to 15.7 | 27.7 to 28.9 |
  | nothing moved (a sun hour change, a stroke far from solids) | as a whole bake | 1.5 to 2.2 |
  | one rock placed (torture, authoring) | 15.5 | 5.6 to 5.8 (25.6 once: a new mesh's `islands`) |
  | one rock moved | 16.6 | 3.9 to 4.0 |
  | a sculpt stroke step near rocks (42 to 1628 texels) | as a whole bake | 3.4 to 4.7 |

  Of an edit's 4 ms about 1.4 is the collect, 1 to 2 the bake and 1 the upload of the whole
  texture. Not explained: the first rebuild after a stroke ends collected for 21 to 31 ms in three
  runs of three (once per stroke; no new mesh was split in the one case that logged it), and a
  rock moved by setting its instance transform took 30 ms twice and 4 ms once. Main was not
  measured at a stroke's end. The three kinds of per-body work each show when switched off alone
  (`ready/ablation__...png`): one box a mesh doubles a cluster's patch, without the foot's height
  the mark runs down the wall under the ledge's stones, and at 0.5 m the small stones' marks are
  gone; all three are kept.
- **The disc on a boulder's lit front** (same card): a round disc with two soft rims crossed the
  planes of a boulder, absent on main. Named by switch (`ready/disc_switches_crop__...png`): the
  plane was mixed in by `on_form`, the point's distance from the rock's middle, so a flat face
  dipping inside the box's spheroid showed that distance's contours. A plane is now chosen by the
  point's direction alone (`big` is the rock's size, one number a rock), and a small rock's planes
  are its mesh's own faces (`normalize(wn)`), not the rounded form's normal, whose light and
  half-light met along curves. The form's normal, which still uses `on_form`, decides the
  terminator only.
  Seen and left: the round soft-rimmed disc on a boulder's lit face (two concentric rims, about
  0.9 m in radius on a 1.2 m boulder, the "smudge" above) is NOT the shadow shell: it is unchanged
  with `LIGHT_VERTEX` left alone (`noshell`), and absent with main's solid shader in the same
  run, so it is a radial term of this card's solid shader about the rock's origin, not yet named.
- **The terrain casts with its back faces** (`TerrainBackCaster`, a shadows-only twin of each
  chunk drawn with `painter_terrain_caster.gdshader`, `cull_front`, only while Painted): ground
  that faces the sun is never shadowed by its own surface (the stipple and the hatching on grazing
  banks), and a hill's shadow still starts at its foot. The sun's `shadow_reverse_cull_face` gives
  the terrain the same shadows but flips every other caster: rejected. Classic is unchanged.
- **The caster is pushed 0.3 m toward the light** (`push_m`, depth only: along the light's own
  view axis, so the silhouette does not move). A back face is a surface things stand right in
  front of (a fall's sheet, grass and flowers on a far slope), and with no push the engine's
  shadow bias lights them in stripes: the fall was hatched at midday and mostly lit at a low sun.
  0.05 and 0.1 m still hatch it; 0.3 m is clean at sun elevations 10 and 48, and no crest took a
  dark line (the risk: a back face pushed past the lit ground just before a crest).
- **Cost.** GPU in-run A/B against main (7 rounds, the rigs 115 s apart): f1 close view
  -0.153 ms, wide -0.098 ms (two field fetches a pixel, none per mark, no marks on the rock of a
  slope).
- **Still visible (the owner judges):** the strata bricks above; a darker olive oval round the
  three stones on the cliff left of the falls, now firm-edged: it is the contact SEAM of the stone
  group (gone with `f_core = 0`; not the pool, the wet band or a cast shadow), about three times
  the stones' own size and on ground the field does not call sheer, so the face rule leaves it
  (the lever is the occlusion field's footprint for a scatter of stones, `PainterOcclusion`); the
  shade of a slope that crosses the map's edge stops at the edge in a ruled line (the skirt is
  not field-shaded); the lip as a thin light line along a crest. The soft edge at the left of the
  bank view was the wet band, not a cast shadow (above). Cost of the finish card's shaders against
  main, GPU in-run A/B: f1 close view +0.041 ms, wide +0.038 ms (the planes' lattice is 24 hashes
  a rock pixel; one hash a cell would cut it). Evidence of cards painter-ground-rocks and -finish:
  `docs/research/2026-11-09-prototypes/compare/painter_final107_ground_rocks/` (`finish/`).

## The map edge, and the cost of an edit (card painter-terrain-edge, 2026-11-21; look-pending)

- **The map edge.** The skirt's mesh normal holds only the outward fall
  (`TerrainMeshBuilder.skirt_vertex`), never the gradient ALONG the border, and the skirt was kept
  out of the shading field, so a form that crossed the border lost its normal, its rock and its
  hard terminator there: a ruled line at 6.5 h, a rectangular corner at 17.5 h. Now the skirt's
  material is bound to the same field texture as the ground (`PainterGroundField.sync` takes both
  materials: one texture object, as the zone map's; no margin is baked and no texture is added).
  Past the border the read clamps to the border's texel (texel middles lie on samples, so that texel
  IS the border), which is the form the skirt's mesh carries outward; `skirt_keep()` scales the
  read by the mesh's own fall (1 minus a smoothstep of the square-ring distance over `skirt_fall`,
  `AuthoredTerrain.SKIRT_FADE_M`), and the fall itself comes from the mesh normal. At the border
  the keep is 1 and the fall is level, so the read is the map's own. `fielded` is
  `shade_present && !world_frame` in `ground_at()`, `fragment()` and `light()`, and the lip and
  foot run on a fielded skirt. The ground's own path is unchanged: in one run, main | build, the
  owner's bank view differs in 0 pixels, and the falls and wide views in none outside water.
- **What it shows** (`painter_final115_terrain_edge/final_*.png`, a slope and a mound on each of
  the +x and +z borders, 6.5 h, 14 h, 17.5 h, main | build): rock walls, strata, lip and shade
  cross the border as one shape. Still visible: the skirt IS the border's profile pushed straight
  out, so on it a wall or a terminator runs straight out from the border, straighter than a form
  inside the map (the mound on +z at 6.5 h: a shade column with one near-straight side). The
  defect measure says the same: the ruled lines are gone (`vedge` 0.64 to 0.40 on the +x slope,
  0.72 to 0.28 on the +x mound at 17.5 h) and the walls that now run on count as straight edges
  (`vedge` 0.40 to 0.98 and 0.61 to 1.36 on the +z slope, `hedge` 0.03 to 0.19 on the +x slope).
  The lever, if the owner wants it, is the skirt's mesh (a fall that also rounds the profile along
  the border), not the shading rule.
- **No GPU readback on an edit.** A MultiMesh given only a buffer lives on the GPU alone:
  `MultiMesh.buffer` was a readback on every call (27 to 35 ms, never cached) and the first
  `get_instance_transform()` or `set_instance_transform()` another (13 ms; measured in a window,
  RTX 3080, `jobs/mmprobe.gd`). The contact field's collect (`PainterOcclusion._add_solids`) paid
  it on every multimesh the scatter had just rebuilt, and `AuthoredScatter.move_rows` paid it
  under a held sculpt stroke. `ScatterGlbUtils.multimesh_from_chunk` now writes one instance
  before it sets the buffer, so the RenderingServer keeps its CPU copy and the same reads take
  about 0.01 ms and return the same floats (`test_scatter_multimesh_cpu.gd`; the cost is one more
  copy of each settled node's buffer in RAM). Torture map, sculpt stroke across the rock row,
  three strokes each, before | after: held stroke worst frame 43.2, 43.1, 50.6 | 22.4, 21.9,
  23.4 ms (median 14.1 both, the vsync cap); frames over 33 ms 6, 3, 3 | 0, 0, 0; the rebuild at
  the stroke's end 34.0 ms (collect 31.5) | 3.9 ms (collect 1.6); a rebuild after a direct move
  27.0 | 4.8 ms; after a placed boulder 43.5 | 26.6 ms (collect 16.5 | 1.4; the rest is the whole
  bake a new mesh asks). What is left in the worst frames (26.8 ms, at the release): heights 0.9,
  terrain 0.9, fields 0.5, snap 0.5, collision 0.3 ms of timed parts; the recorder's parts no
  longer hold a readback (`h_snap` max 29.6 to 1.2 ms, `flush` max 30.1 to 1.8 ms), and the
  remainder of such a frame is outside the parts it times.
- **The rock planes' lattice** needs no change: `solid_form()` runs its four-hash loop only where
  the rock is big enough to take planes (`if (big > 0.0)`), and the whole lattice switched off
  measures within the noise (GPU in-run A/B, lattice on against off: one rock filling the view
  -0.024 ms, the rock row +0.006 ms, the falls view +0.009 ms, base drift 0.014 to 0.039 ms).
- Evidence: `docs/research/2026-11-09-prototypes/compare/painter_final115_terrain_edge/`
  (`final_*.png`, `round1/`, `owner/`, `timing/`, `scores_edge_full.tsv`, `jobs/`).

## Small stones' dabs, and where a form ends past the border (card painter-terrain-marks, 2026-11-21; look-pending)

Evidence: `docs/research/2026-11-09-prototypes/compare/painter_final117_terrain_marks/` (sheets
`item1_*`, `item2_*`, `item3_*`, `owner/`, `timing/`, `captures/`, `jobs/`); handoff
`docs/plans/handoffs/painter-terrain-marks.md`.

- **The dabs as geometry (card painter-terrain-dabs, 2026-11-21; look-pending; this one is current
  for the small stones: round 3's bake of the dabs into the seam channel and its re-bake when the
  sun turns are gone; round 3's skirt part stands).** Evidence:
  `docs/research/2026-11-09-prototypes/compare/painter_final120_terrain_dabs/`; handoff
  `docs/plans/handoffs/painter-terrain-dabs.md`.
  - *How a dab takes the ground's tone.* It is drawn with the ground chunks' own material (the
    same `ShaderMaterial` object, as `material_override`): no second material and no uniform to
    keep in step. A dab's mesh carries `CUSTOM3` alone (the flag, what the value loses, the lift,
    the stone's slot plus one); the terrain's meshes have none and read 0, so `vertex()` tells a
    dab by `CUSTOM3.x` and passes on the slot (one flat float) and the loss (one float). The
    stone's three lobes are three RGBA32F texels of `dab_lobes`, a texture `PainterDabs` writes
    (256 stones a row, a stone's slot kept while it stands, a freed slot taken by the next new
    one), read by the vertex shader for the lift and at the top of `fragment()` for the value. In
    `contact_at()` the dab's value joins the field's seam by `max` BEFORE the seam's
    threshold, on a dab's pixels alone (one compare per ground pixel). So a pixel of a dab is the
    ground at that place (its biome paint, strata, zone maps, cast shadow, pool) with the seam on
    inside the outline and nothing changed outside it. The seam is a tone the ground is set to
    (`mix` toward the soil), so a dab inside a boulder's seam, a cast shadow or another dab is
    that place's own seam tone, never a second darkening.
  - *The geometry* (`PainterSites.append_dab`). A dab's patch is the terrain's own triangles: the
    grid samples within the dab's reach of the stone (2 radii plus 0.06 m), triangulated as
    `TerrainMeshBuilder` does, 4 mm up. It lies on the ground whatever the ground's shape. (The
    first build, a fan per lobe with its vertices on the ground, dipped under every lip it
    crossed: a 0.3 to 0.8 m triangle on a 0.25 m heightfield sinks centimetres below a convex
    crease, and the marks were torn into shards: handoff, "Dead end".)
  - *The shape* is not in the triangles. `dab_value()` works it out per pixel from the three
    lobes every vertex of the patch carries (a lobe: its middle, its radius, the turn of its
    waves; `PainterSites.lobes`, placed by a hash of the stone's position: 0.95, 0.8 and 0.65
    radii, the last two 0.45 and 0.5 radii off the middle): a lobe's value falls in a straight
    line from its middle to an outline whose distance varies round it by two and three waves
    (14 % and 8 % of the radius), and the dab is the greatest of the three. Exact at any zoom:
    curved, uneven outlines with cusps where lobes meet, no facets.
  - *The sun* is a uniform: the value takes `DAB_LEAN` 0.2 (plus `DAB_LEAN_LOW` 0.1 times the
    sun's levelness) of the offset from a lobe's middle along the direction away from the sun,
    which stretches each outline to the shaded side by 1 / (1 - lean) and shortens it sunward.
    Nothing is rebuilt when the hour changes (`PainterDabs.built` stands still across it).
  - *Touching stones.* The vertex shader raises a vertex 8 mm per unit of its value, so where two
    stones' patches overlap the depth test keeps the one with the higher value there: the marks
    join along the union of their outlines, and the plain part of one patch never cuts the mark
    of another.
  - *The host* (`PainterDabs`, owned by `PainterOcclusion`, synced at the end of every
    `rebuild()`): one mesh per 16 m cell holding a site, under a `PainterDabs` node beside the
    terrain, casting no shadow. It keeps each site's patch and builds only a site that is new or
    stands on samples edited since (`PainterSurfaces._on_ground_edited` forwards the rect; a new
    terrain marks everything); a stone is known by its place and radius, so one the ground moved
    under keeps its turn in its cell and the patches after it keep their indices. A stone whose
    foot is further than twice its vertical reach from the terrain (it stands on something else)
    or off the map gets none, and a vertex whose ground lies past that reach loses value (a dab
    ends at a ledge's edge). No dab on a GLB map (no heightfield to copy) or on the skirt.
  - *The field* is main's before the marks cards for everything else: a small stone writes
    nothing into it (`test_small_stones_are_sites_and_leave_the_field_alone`), `update()` takes
    no sun, and `PainterOcclusion` no longer watches `FoliageLight.last_sun`.
  - *Measured (2026-11-21, against main 1a1a6c22 in-run; NOT merged: the frame cost gate
    fails).* GPU A/B, main | build, two rounds, twice: f1_o +0.049, +0.025 and +0.043, +0.039 ms;
    torture edge view +0.037, +0.025 and +0.036, +0.033 ms; torture wide (456 sites) +0.097,
    +0.090 and +0.142, +0.123 ms (main's own drift in those runs 0.00 to 0.05 ms; the gate was
    +0.02 ms). The second pair had a per-pixel early-out in `dab_lobe` past 2 radii, which did
    not help (taken out again), so the cost is not the outline's arithmetic: a patch is whole
    terrain cells at 0.25 m, about a fifth of the wide view's ground is patch, and the suspects
    left are the extra vertices and small triangles, and the patches' overlap. Next structure
    to try: fewer, larger triangles per patch (one quad per stone lifted enough to clear the
    ground, or a `MultiMesh` of fixed patches reading the height texture), or no patch beyond
    a zoom at which a dab is under a few pixels.
    Edits (torture, 458 sites, ms): a placed boulder's rebuild 4.89 (dabs 1.59), a moved one
    4.26 and 3.92 (dabs 0.4), a placed cluster of small stones 2.25 (dabs 0.74, 3 built), a
    moved small stone 3.27 and 2.77 (dabs 1.21 and 0.87), the rebuild under a sculpt stroke
    across the rock row 4.7 to 4.8 (dabs 1.5 to 1.6, 18 built; main's stroke end is 3.7 to
    3.9, so about 1 ms worse; taken before the host's index cache and early-out, not taken
    again). A whole build of 104 sites 5.2 ms, of 456 sites 16.2 ms; a sync with nothing
    changed 0.03 to 0.08 ms. The sun: across 6.5, 9, 12 and 14 h `built` and `uploaded` stood
    still on both maps (104 | 16 and 456 | 16) and the field's bake wrote 0 texels. Owner
    frames in one run: bank_z3 0 pixels; f1_o 27903 and wide 8423 pixels outside the moving
    water, at the stones' marks by the sheet (the `ident` maps were not looked at). Classic:
    no `PainterDabs` node. `img.gd` scores over 18 torture frames, main | build: dots 2.42 |
    2.40, lines 4.42 | 4.40, vedge 0.46 | 0.44, hedge 0.04 | 0.04.
  - *Where the cost was (card painter-terrain-dabs-cost, 2026-11-21; evidence `cost/` beside the
    above; handoff "## Cost").* In-run arms against the branch tip at torture wide (twice, about
    3.27 ms GPU): main -0.13, the dabs hidden -0.03 to -0.045, the patches drawn as plain ground
    +0.07 to +0.09 (overlapping patches tie in depth and both shade), the patches on an unshaded
    material -0.2, one unshaded quad a stone instead of the patches -0.03 to -0.04 (draw calls and
    vertices cost nothing), the fragment's dab branch removed -0.13 to -0.14 (equal to main), the
    lobes' varyings removed -0.07 to -0.10, a depth tie-break no gain. So the cost was the GROUND
    paying for the dab's code on every pixel (about 0.1 ms, 60 % of it the three flat vec4
    varyings), not the patches (0.015 to 0.04 ms). Patch counts at wide: 462 patches, 19632
    triangles, 14431 vertices in 16 cells; 8710 triangles on screen, 370020 px summed, 227712 px
    union (11 % of the frame); a sun-agnostic cut to the lobes' reach keeps 84 % of the triangles.
    The cut taken: the lobes moved to the `dab_lobes` texture (above), the value worked out at the
    top of `fragment()`. After, in-run main | new: wide +0.071 and +0.066 ms (gate +0.04: still
    fails), edge_mz +0.005 and +0.027, f1_o +0.010 and -0.002 (drift 0.02 to 0.04). Edits on the
    torture map, in one run with main: a stroke end's rebuild 4.2 to 4.6 ms (dabs 1.2 to 1.6, 16
    built, 2 cells) against main's 3.7 to 3.9; a placed boulder 2.85 to 3.0 ms against main's 3.5
    to 4.3 (main's field bakes the 464 small stones as marks: 594 marks against 129; the 25.9 ms
    figure was not reproduced). Pixel identity with the branch tip was NOT shown (handoff).
  - *The look* (sheets in the evidence folder). At f1_o main is one faceted kite under the
    three stones and round 2 three clean ovals; the build is one firm flat mark that hugs the
    stones on the side away from the sun, a quarter to a third of a stone wide there and a
    sliver elsewhere, joined across the three with no darker overlap, its outline uneven. Still
    wrong: where two lobes meet the outline makes a pointed corner (a squared tail under the
    lowest stone at f1_o), the smallest stone of st3 gets barely a sliver, and at 6.5 h the
    mark is faint against the dim ground. Inside a boulder's mark and in a cast shadow the
    build equals main to the eye (no second darkening). The slope view was mostly a boulder,
    so a dab on a slope was not judged.
- **Round 3 (card painter-terrain-marks-3, 2026-11-21; superseded for the small stones by the
  bullet above: the sites texture,
  its flag, `site_dab()` and `f_cast` of the bullets below are gone).** Evidence in `round3/` of
  the same folder.
  - *Structure.* The ground's shader does nothing per pixel for a small stone: `contact_at()` is
    main's again. A small stone's dab is baked on the CPU into the seam channel the ground
    already reads (`PainterSites.bake`, called from the contact field's own bake, so a partial
    bake still equals a whole one bit for bit), as a DISTANCE, not a coverage: the channel takes
    `EDGE` (0.45, the shader's threshold) minus the dab's signed distance over `BAND_M` (0.3 m),
    so the field's bilinear read rebuilds the outline and the shader's own noise and firm step
    make it the seam's flat mark. The dab is the union of three discs placed by a hash of the
    stone's position (0.95, 0.8 and 0.65 radii wide, the last two 0.45 and 0.5 radii off the
    middle; the first at least 0.15 m). Each disc's distance is a paraboloid's (no point at the
    middle for the filter to flatten) and is baked wide by an eighth of the texel's square (a
    bilinear read of a convex value is too high between texels).
  - *The sun.* The shader reads the field 0.3 m toward the sun (`SEAM_LEAN_M`), which would set
    a 0.2 m stone's whole dab beside it (main's displaced patch). So a dab is baked 0.3 m toward
    the sun and shows at the stone, the same shape at every hour. `PainterOcclusion` watches
    `FoliageLight.last_sun` each frame and queues a rebuild when the plan direction has turned
    by more than about 6 degrees, or by anything once it has stood still 12 frames. Cost of one
    turn: the sites' rects, or the whole field when more than 48 stones moved: 18 ms on the
    falls map (104 sites), 28 ms on the torture map (458 sites), once, debounced.
  - *Cost, measured.* GPU in-run A/B against main (7 rounds, 90 frames): f1_o +0.025 and -0.029
    ms (two runs; noise both ways), torture edge -0.035, -0.023 and -0.024, torture wide -0.027
    and -0.015. Edits: placed boulder 25.9 ms (main 26.6), move 5.0 and 4.4 (4.8), stroke-end
    rebuild 3.9 and 3.7 (3.9). Whole bake 14 ms (falls) and 22 ms (torture).
  - *What a 0.25 m distance channel holds, and does not.* The mark is firm, flat, the seam's
    tone, at the stone, uneven. Its outline is FACETED: straight runs about a texel long with
    corners, since a bilinear patch cannot carry the curve of a 0.2 m disc; and stones that
    touch share one mark (round 2 drew one oval per stone). If that is not good enough, the
    next structure with no per-pixel cost is the dabs as flat triangles on the ground; a finer
    field costs bake time and upload on every edit.
  - *The skirt.* A form's end varies across it by the brush's wobble the shader already has
    (`warp`, stretched, `SKIRT_END_VARY` 0.25 either way): no noise call and no varying of its
    own. `f_cast` is gone (it did not remove the dashes). Remaining defect: the dashes and
    streaks under the +z walls at 17.5 h, the map's cast shadow received by the skirt mesh,
    which still stands as a wall past the paint's end. The two real fixes (handoff, "Round 3"):
    end the terrain's cast shadow where forms end, or a Painted-only skirt height that relaxes
    to the base level.
- **Finish round (card painter-terrain-marks-finish, 2026-11-21; superseded by round 3 where
  they differ).** Evidence in `finish/` of the same folder.
  - *The dab is the seam's own mark.* `site_dab()` gives each stone a value that is positive
    inside an oval along the sun's line: its sunward end `SITE_NEAR` 0.85 radii from the stone's
    middle (under the stone), its far end `SITE_FAR` 1.5 radii out on the shaded side plus
    `SITE_LONG` 0.45 times the sun's levelness (1.80 at 14 h, 1.94 at 6.5 h: it leans longer
    under a low sun), `SITE_WIDE` 1.15 radii either way across; it is an ovoid in height too
    (`SITE_UP` 1.2 radii), so on ground that falls away it closes in a round end (a cut at a
    height band ended it on straight contour lines: tried, `finish/round_a/`). The value falls by
    one per `SITE_BAND_M` 0.3 m, joins the field's seam value by `max` BEFORE the step, and takes
    the same 0.3 of the same noise: one flat tone, the same pixel-wide step, two dabs that touch
    (or a dab and a boulder's seam) are one mark. Sheet `finish/dab_sheet__*.png` (main | round 1
    | build, native): firm flat lobes hugging each stone on the side away from the sun, a third to
    a half of a stone's width showing, merged in a cluster, longer at 6.5 h. Still visible: the
    edge is firm but regular (a clean oval; the wobble is 0.045 m at most), so a dab reads as a
    neat shape rather than an uneven brush mark.
  - *Where the sites are read* (`PainterSites`, split from `PainterOcclusion`). A site raises the
    field's seam channel to `FLAG` 1/64 within `GROW` 1.95 radii plus `PAD_M` 0.54 m (far under
    the seam's threshold: it draws nothing), so the field read the ground already makes says
    whether a dab can be near; only then is `occ_sites` read, one `texelFetch` of the pixel's own
    texel, and the four texels round the pixel only where the texel's radius is negative (two or
    more stones within `GROW` radii plus `TIGHT_M` 0.24 m of it). A texel keeps a stone that may
    draw in it before any other, then the one it lies deepest inside (`COVER` 1.95 radii).
    `occ_sites` is uploaded as the 32-bit floats it is (no pass to half floats; nearest reads),
    and only when a site changed; a site's change uploads the field too (its flag).
  - *Cost: NOT under the +0.02 ms rule.* In-run GPU A/B against main, 7 rounds of 90 frames: f1_o
    +0.012 ms (once; main's own drift in that run 0.030); torture edge view +0.039 then +0.055;
    torture wide +0.054 then +0.087 (the second pair is the committed shader; round 1 was +0.034
    and +0.069). Cutting the fetches did not cut the cost: the gated zone is larger than round
    1's (the flag must cover the field read's 0.3 m lean), and the second run adds two noise
    calls and a varying on every skirt pixel (the wide view is half skirt). Levers not tried: a
    flag radius without the lean (read the flag unshifted from a texture the ground reads at the
    pixel), the skirt's fine noise taken from `warp`, removing `f_cast`.
    Edits (torture map, `finish/timing/st_finish_log.txt`; main | round 1 | now): placed boulder
    26.6 | 27.4 | 28.7 ms; a move 4.8 | 5.0 and 4.5 | 5.1 and 4.3; the rebuild at a stroke's end
    3.9 | not isolated | 4.0 and 4.1; rebuilds under a sculpt stroke, median and worst: round 1
    4.3 to 5.0 and 6.9, now 4.1 and 4.6 (upload at most 1.5 ms, was 2.2).
  - *Owner frames* (`finish/owner/*_ident.png`, one run, main | build | no sites | main again):
    bank_z3 0 px. f1_o 32400 px: the three stones (main's angular patch gone, three dabs), two
    flat strips under the foam at the fall's foot that also differ with the sites unread (main
    drew a field patch there for small bodies the build makes sites: taken to be the dressing
    stones in the plunge pool, their positions not listed), and two specks of a few pixels in the
    falling water (taken to be water the mask missed). wide 14896 px: every marked spot is at a
    group of small stones; no strip along the far rim.
  - *The skirt.* A form's end now varies across it: a noise about a wall's width across
    (`SKIRT_END_FREQ` 0.45 per m, stretched to its full range) moves the end by `SKIRT_END_VARY`
    0.55 of the distance either way, a finer one roughens it. Sheet `finish/skirt_sheet__*.png`:
    the +x wall ends on a slanted line with one side running on (round 1: a vertical cap); still
    one near-straight edge, not a taper to a point. The dashed line and streaks under the +z
    walls at 17.5 h are the CAST term (gone with the cast off, unchanged with the form's turn
    off); the skirt's mesh does not cast (`SkirtExits.decoration`), so they are the map's own
    cast shadow received by the skirt's mesh, which still stands as the border's wall where its
    paint has died (it is painted as level ground; its shadows show it). A step that drops the
    cast on steep, undrawn faces of the mesh (`f_cast`) was built and did NOT remove them (they
    lie on faces within about 20 degrees of level): it is still in the shader and should come
    out. What would remove them without touching `skirt_height`: not taking the terrain's cast
    shadow past where the forms end (every shadow on the outer ground then ends there too), or a
    Painted-only flattening of the skirt's mesh.
  - *Scores* (`finish/scores.tsv`, main | build): equal within 0.1 on every torture and edge view
    but these: `edge_sz` vedge 1.37 to 0.90 and 1.00 to 0.60 (the ruled walls are gone); rk2 at
    14 h vedge 0.35 to 0.42 (the dabs' firm edges at zoom 1.4); `out_sz` at 17.5 h dots 2.12 to
    2.39 and lines 7.50 to 8.15 (the dashes and streaks above, where main had one solid block).
- **A small stone is a site, not a footprint.** Three stones 0.4 m across shared ONE angular patch
  about 1.4 times the group: a 0.25 m texel is wider than the gap between them, and a hard
  threshold of a bilinear read of two or three texels has straight edges. Structures compared
  (`item1_round1/`, main | no mark | sites): no mark at all for a body the field cannot hold (the
  stones float, flat on shaded ground); a blob in the field (main is this one; a lattice of 0.25 m
  cannot keep marks 0.4 m apart whatever the blob's weight); the stone ITSELF recorded in the
  texels near it and its mark drawn analytically. Built: the third. `PainterOcclusion` makes a
  body a `SITE` when its longer half is under `SITE_HALF_M` 0.45, it is no longer than
  `SITE_ASPECT` 1.6 times its narrower half (a thin log stays a box) and its radius
  (`sqrt(half.x * half.z)`) is at least `SITE_MIN_M` 0.09 (main drew nothing under 0.083). A site
  is not rasterized: every texel within `SITE_GROW` 1.8 radii plus a texel's diagonal of it holds,
  in a second RGBA half texture laid out as the field (`occ_sites`, made only when the map has a
  site), the stone's middle as an offset from the texel's own, its radius and its foot's height;
  a texel keeps the stone whose dab's edge lies furthest past it (`_site`; nearest in its own radii
  let a stone take every texel round a pebble beside it). Sites are marks like the others: sorted,
  baked whole or by dirty rects, bit for bit the same either way; each texture is uploaded only
  when its own marks moved. Boulders, logs, trees and structures are unchanged.
- **The dab** (`painter_ground` `contact_at()`): one filtered read of `occ_sites` says whether any
  of the four texels round the pixel holds a stone; only then are the four fetched, and each
  stone's dab is a disc `SITE_DAB` 1.2 radii wide whose middle leans `SITE_LEAN` 0.35 radii from
  the sun, with a soft edge (`SITE_IN` 0.8 to `SITE_OUT` 1.0 of its radius, wobbled by the brush
  noise) and shown within about the stone's radius of its foot's height. It joins the seam (the
  soil tone, lighter in the sun). The yard's wash does not read sites.
  What the sheets show (`item1_stones_native__...png`): three stones, three round dabs at 14 h and
  6.5 h on the falls' cliff and under each stone of the torture clusters; no angular patch. Still
  visible: the edges are soft rather than a brush's firm ones, and the lowest stone on the cliff
  (it stands on a slope, so more of its dab shows) reads as a soft drop shadow as large as the
  stone.
- **Cost of the sites.** GPU in-run A/B against main (7 rounds, 90 frames): f1_o +0.011 ms (104
  sites), torture edge view +0.034 ms, torture wide view +0.069 ms (454 sites on a 61 m map: the
  four-fetch branch runs in a zone of 0.36 m plus 1.8 radii round every stone). Over the +0.02 ms
  rule on the torture map; the lever is that zone (the texel diagonal of padding), not yet cut.
  Edits, torture map in authoring (`timing/st_build_log.txt`; main in brackets): placed boulder
  27.4 ms (26.6), a move 5.0 and 4.5 ms (4.8), a rebuild under a sculpt stroke 3.6 to 6.9 ms
  (collect 1.5 to 2.5, bake 1.2 to 2.9, upload 0.9 to 2.2: both textures go up when stones and
  boxes move together, about 1 ms more than main's one; main's rebuild at a stroke's end 3.9, and
  the build's rebuild at the stroke's end was not read out on its own); whole bake 22 ms at 583 marks (main's 313 footprints 24 ms).
- **A form ends within a few metres of the border.** The skirt's mesh is the border's profile
  pushed straight out for 24 m, so since the skirt took the field's shade a wall, a shade mass or
  a lip ran on as a ruled bar (10 m of rock wall on the +x slope; a rectangular shade block
  between the +z slope's walls at 17.5 h). The mesh is shared with Classic and with what stands on
  it (the eye rim's plants, river exits and water read `TerrainMeshBuilder.skirt_height`), so the
  mesh is left alone and the change is in the Painted shader only: what is DRAWN of the border's
  form (the field's read and the mesh's own outward fall) is scaled by a fall-off of the distance
  past the border, 1 at the border and 0 at `SKIRT_END_M` 3.5 m times 0.6 to 1.4 by the slow noise
  the outer ground already wanders by (no added noise call). Each role is a hard step of the read,
  so a wall narrows toward its steepest line and closes. Not built: relaxing the skirt's heights
  toward the base level, or low-passing the border's profile with distance (both change the
  shared mesh and need it keyed by the look).
  What the sheet shows (`item3_skirt_out_third__...png`, views centred past the border, 6.5 h and
  17.5 h, main | build): the +x wall ends about 3 m out instead of running 10 m; the +z walls
  taper to points; the +z mound's shade is a short round lobe instead of a 6 m column, and the
  detached shade island at 17.5 h is gone. Still visible: the +x wall's end is a blunt, nearly
  straight cap; under the +z walls at 17.5 h the mesh's own cast shadow shows as thin streaks and
  a dashed line (the skirt's inner ring takes shadows, and the extruded mesh is still there to
  cast them). At 7 m the walls outran the earlier edge views; 3.5 m was not compared against other
  lengths. Classic: no file of its path changed (`captures/edge_sz_h140_classic_sub.png`, not
  compared against a main frame).
- **Mechanical edges in the shade: attributed in part, not fixed.** One sheet of switches at
  6.5 h (`item2_attribution_native__...png`, native crops, build | cast shadow off | form's turn
  off). On the mound the whole shade mass in view and its edge are the CAST shadow: with the cast
  off nothing is left, with the form's turn off the picture is the build's. That edge carries a
  stippled fringe a few pixels wide (the hatched penumbra), which is therefore the shadow map's
  filter seen through the firm step of `cast` (0.44 to 0.56 of the attenuation), not the field
  or a normal. The other crop (a pyramid ramp) held no terminator, so the sawtooth along mesh
  triangles was NOT reproduced or attributed by a capture. Read from the code only, as a
  hypothesis: the terrain casts with its back faces pushed 0.3 m toward the light, so a triangle
  that faces away from the sun shadows itself whatever the field's smooth normal says, and where
  the field calls such a triangle lit the shade's edge would be the triangles' outline. Next
  steps: a native crop on a terminator with the same two switches; for the fringe, the sun's
  shadow filter quality and blur as switches (`sun.gd shadow`), since a hard-filtered map under
  the same step has no dither to show; if the sawtooth is the caster's, `painter_terrain_caster`
  could read the field at each vertex and move a vertex the field calls lit away from the light.

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
