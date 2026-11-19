# Painted coverage sweep: the ranked worklist (2026-11-18, card painter-coverage-sweep)

The rendered follow-up to `docs/painter-coverage-audit.md` (which was read from code). Five gallery
levels (plants and species families, two structure levels of 48 recipes, props, a world with water,
crossings, paths and a terrace) were captured Painted and Classic at orbit (zoom 16 to 52) and at the
eye, summer plus winter and dusk on key views. About 150 frames; the evidence, the position-to-class
table and the per-class findings are in
`D:/dev/tabletop/docs/research/2026-11-09-prototypes/compare/painter_final41_coverage_sweep/notes.md`
(frames cited below are in that folder).

Headline: asset parity is closer than the audit's tables suggested. Every tree, bush, rock, wood, prop,
house, profile-roof and ruin class has a painted form that sits with the others; the village,
field-plant and prop cards closed what they said they closed. What is left is a short list of visible
mismatches, one of them a whole-surface one (the eye-level sky).

## Ranked gaps

Ranked by how visible at tabletop zoom (orbit) and at eye level. S is under half a day, M a day or
two, L more.

1. **Eye-level sky and horizon are bare (H at the eye, every eye frame).** Painted shows a flat cyan sky
   and a hard ground line; Classic has clouds and a far hill band. The orbit view and the map edge are
   fine (the clipmap and skirt fade into the painted haze). Frames: `full_plants/g_eye_trees_p.png` vs
   `_c`, `sheets/sheetC.png`, `sheets/world_sheet3.png` rows 1-2.
   Card `painter-eye-backdrop` (M): the painted form of `EyeSky` clouds and a far hill band tinted by the
   mood (sheet numbers, no new look rules); files `scenes/states/playing/eye_sky.gd`, the painted sky
   in `painter/painter_scene.gd`, `skirt_backdrop.gd`, the sheet; verify with the eye frames in five moods.
2. **Rectangular dark pools under structures and under the trees the painter does not grow (H at orbit).**
   Hard-edged teal slabs that run past the footprint, merge into bands across a row of buildings and
   read as shadow errors; under acacia, palm and dead tree the pool is a rectangle where grown trees get
   a round one. Visible in summer, dusk and winter. Frames: `sheets/sheetA.png` row 1,
   `sheets/sheetF.png` row 2, `full_plants/b_trees2_p.png`. Card `painter-pool-shapes` (S to M):
   `painter/painter_occlusion.gd` `_add_solids` and `_add_structures` write rectangular footprints; write
   rounded, footprint-clipped coverage (round for a trunk, a soft rounded rectangle without overhang for a
   building); `tests/unit/test_painter_occlusion.gd` pins the shapes; look round on the same gallery.
3. **Flowers are lost (H at the eye, M at orbit).** Placed carpet and bell-cluster flowers do not show at
   all at the eye; in scatter on the meadow the white, yellow and red flowers of Classic nearly vanish and
   only purple dots remain, so a flowery meadow reads empty. Frames: `full_plants/h_eye_flowers_p.png` vs
   `_c`, `sheets/world_sheet1.png` row 2, `sheets/world_sheet3.png` row 3. Card `painter-flowers` (M):
   the KIND_FLOWER stand-in in `painter/plant_roles.gd` and the flower shader: size, one dab per bloom, colour from the flower's own hue (a small palette of six); verify
   meadow, alpine and wetland at orbit and the eye.
4. **Round and Taper roofs are one blue-grey (M, a handful of landmarks in every village).** Round hut,
   roundhouse, yurt, dome hall, tulou, trullo, windmill caps, wizard tower, crystal spire and pagoda roofs
   draw as one blotchy slate colour where Classic gives red, thatch, brown or purple; in winter the snow
   lands as cow-spot patches. Profile roofs (gambrel, mansard, dutch, saltbox, minka) are fine. Frames:
   `sheets/sheetA.png` rows 1 and 3-4, `sheets/sheetD.png` row 1, `full_struct/struct1_c3_p.png`. Card
   `painter-round-roofs` (L, crosses procgen): either procgen records for round and Taper surfaces (the
   roadmap A7 item) or, first and cheaper (S to M), choose the roof's tone from its paint in
   `painter/painter_buildings.gd` KINDS so the mass look follows the recipe's roof colour and
   the snow cap reads as a clean cap.
5. **Every path surface is one sand stroke (M at orbit).** Cobblestone and flagstone read apart in
   Classic; Painted draws both as the same beige ribbon. Frames: `sheets/world_sheet3.png` row 3,
   `full_world/w4_pond_path_p.png`. Card `painter-path-surfaces` (M): per-surface tone and a
   brush-stroke pattern (cobble dabs, flagstone plates) for the biome's path surfaces in
   `painter/shaders/painter_ground.gdshader` and the sheet's path roles; verify with all five path
   surfaces of two biomes.
6. **Terrace and cliff faces read as dark purple smears (M, any sculpted map).** The tier faces are a
   dark purple-grey and the tops barely lift; Classic reads as stepped stone. Frames:
   `sheets/world_sheet2.png` row 2, `full_world/w6_tier_p.png`. Card `painter-cliffs` (S to M): the cliff
   role tone and a lit top edge in `painter_ground.gdshader`; verify on a tier, a slope cliff and a
   badlands cliff.
7. **Ruin roofs draw black (L to M, five recipes).** In `ruin_cottage` and `ruin_barn` the roof remnant is a
   flat black plane (blue or brown in Classic). Frames: `sheets/sheetB.png` row 3,
   `full_struct/struct2_c1_p.png`. Card `painter-ruin-roofs` (S): find the surface the ruin recipe
   gives its roof remnant (`painter/painter_buildings.gd` KINDS has no row for it, or it hits
   the dark fallback) and bind it to the roof kind; `tests/unit/test_painter_buildings.gd`.
8. **Weather and bursts could not be shown (unknown, M while active).** `GameMap.apply_weather_overrides`
   with rain and snow at 1.0, and `SplashBurst`, `DustBurst` and `SparkleBurst.create_at`, drew nothing
   visible in either look in this harness (orbit zoom 20 and 9). Card `painter-weather-verify` (S for the
   probe, then one card per effect): drive the real Weather pane or a level weather block in a render job,
   confirm the particles, and judge the stepped, brush-edged forms from the audit's gap 5.

Smaller items found on the way, not ranked: the `chinese_hall` recipe is refused at its own default lot
("invalid"; `utils/structure_placement.gd` `default_size` against its limits), the dead shrub and the
mushroom cap are a different hue in Painted (tone only), the painted meadow lacks Classic's gold and moss
patches (more uniform, reads calm).

## Not assessed (follow-up verification, one card)

- Street rows and drawn walls: the street row placed by the harness drew nothing in either look; check it
  with the Streets tool. Crops and field plants (need a village). Fire (painter-final30's `g_fire`
  frames hold the verdict). Legacy GLB maps (painter-glb-parity's fixture world is the evidence). Grid,
  ping and measure overlays at the eye. Indoor and effect presets (owner: not the priority).
- Audit "could not verify" items, settled: Classic-form classes (glass, glow, ironwork) read fine beside
  the painted ones, no seam; the clipmap and far ground are painted, no Classic ground shows beyond the
  chunks and the map edge is clean; profile roofs yes, round and Taper partial (gap 4).

## Suggested order

Gaps 2, 1 and 3 first (each a whole-class read at the default view), then 4 (S step), 5 and 6 together
as one ground-shader card, then 7 and 8. A verification card for the not-assessed list can run beside
any of them.
