# The painted look

The painted look draws a level in the painter's style: one sheet of tones, chosen together, owns
the light, and later the ground, plants, trees and buildings. It ships beside Classic, the game's
usual look, which stays the default and the fallback for weak GPUs and for presets no mood paints
yet (owner, 2026-11-12). Phase 1 card A1 (painter-a1) landed the light only: under Painted the
ground, plants, trees and buildings still wear their Classic materials (cards A1b, A2, A3 follow).
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

Only summer has all three keyframes so far. dusk, grimdark, winter and autumn carry the spike's
tuning (each made for one sun between 24 and 34 degrees) as a single `high` keyframe they hold at
every sun; `PainterSheet.HIGH_ONLY` is the lint's allow-list for that, and each mood leaves it
when its own look card authors its `low` and `night`.

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
  (take, follow the sun and the preset, the exact round trip), `test_boot_graph.gd`.
- Look: the render job of card painter-a1 (`tools/render_jobs/local/painter-a1/`, not committed);
  its captures are in `D:/dev/tabletop/docs/research/2026-11-09-prototypes/compare/painter_a1/`.
