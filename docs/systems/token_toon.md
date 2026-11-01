# Painted pack tokens (TokenToon)

The painted look of pack tokens: Settings > Graphics > "Token shading" (`graphics/token_shading`,
0 Painted, the default, or 1 Original), applied at once with no restart. Code:
`scenes/board_token/token_toon.gd` (`TokenToon`), `shaders/token_toon.gdshader`,
`scenes/ui/settings_token_shading.gd`. Design history: the 2026-11-01 toon probe (three
approaches; the per-material ramp won because it is the only one that unifies mixed sources).

## Model

- Pack tokens only: `BoardTokenFactory.create_from_scene` and `apply_model_upgrade` call
  `TokenToon.apply` / `refresh`. An avatar (own figure look), a placeholder and a mesh with a
  `material_override` are left alone, and so is a surface that is not a plain lit BaseMaterial3D
  (unshaded, billboard, hashed alpha, additive: `TokenToon.paintable`).
- Each paintable surface gets a surface override: a `ShaderMaterial` of the source's albedo (colour,
  texture, vertex colour, UV transform), emission, alpha mode (opaque, scissor, blend) and culling
  (double-sided). The mesh keeps `ORIGINAL_META` ({overrides, sources}); Original (`strip`) puts the
  very same objects back. The painted material is made once per source and kept as a meta on the
  source, so it dies with it and tokens sharing a material share the swap.
- Shader variants: six (opaque, scissor, blend, each single or double-sided), built once at load by
  prepending defines to the one file, immutable afterwards (`TokenToon._shaders`), so the warm-up
  worker and the game use the same `Shader` objects.
- Look: three soft bands on the wrapped light term (shade 0.38, mid 0.70, lit 0.92 of the light),
  a luminance knee on the albedo (pale models do not clip), saturation 1.10, a light warm rim, and
  a per-fragment shade tint read from the albedo (violet for warm, deeper indigo for cool, scaled
  by saturation, so a grey-blue stays blue and a neutral barely tints). The tint is added through
  `SPECULAR_LIGHT` (after the albedo multiply) because a multiplier cannot put blue into an orange.
  The shader header has the rest. Texture detail is kept (the albedo is sampled once, not blurred:
  an atlas or palette texture would bleed neighbouring colours in a blurred mip).

## Other systems

- GM-hidden fade (`BoardToken._set_mesh_transparency`, 40 percent): an opaque or cutout shader has
  no alpha, so a faded painted mesh switches to the BLEND variant of the same source and the mesh's
  `fade` instance uniform carries the alpha (`TokenToon.set_fade`); unfaded, the opaque material is
  back. Switching the setting while a token is hidden resets, swaps and re-fades
  (`TokenToon.refresh`).
- Token ghost (`TokenGhost._source_of`): reads the original material through `TokenToon.source_of`.
- First-launch warm-up: `TokenToon.warmup_samples` is a `GraphicsWarmup.sample_sources()` source
  ("tokens"): the six variants on two vertex layouts (normal and UV, with and without a vertex
  colour). `token_toon.gdshader` is in `COVERED_SHADERS`. Unverified: a pack mesh with a tangent or
  a second UV set has another layout than the samples (a first such token may compile on landing).
- Selection glow and hover use their own meshes and read no token material.

## Captures and numbers (2026-11-01, `tools/render_jobs/jobs/packtoon_look.json`)

Local-only pack models (trainers, pokemon) read from the developer's user_assets; captures stay in
the render_jobs folder, never in the repo. At full size, painted against original:

- Trainers: the artist's grey-green hood becomes luminous orange with red legs, the chef a crisp
  white (original: dull grey), the detective a warm orange-brown jacket (original: dull brown).
- Gyarados a saturated blue with cream spikes and a yellow belly and soft shade bands, Tauros orange
  with a deep brown mane, Chansey a clay-smooth pink: the probe's good results held.
- The pale chunky knight reads cream-white with soft lilac-tinged shade and no clipped faces (the
  probe's 1.18 lit gain blew such tops out). The grey-blue chunky knight goes lavender-blue, lighter
  than the original and not heavy violet.
- Known fault: the tan chunky bear reads peach-pink in sun (original: tan), a hue drift from the
  brighter lit band and the warm shade tint; the cutout leaf bush goes from deep green to a lighter
  yellow-green. Lit gain was lowered from 1.05 to 0.92 for this and a third round still showed the
  bear peach: a lower saturation or a smaller warm tint is the next step.
- Cutout (double-sided scissor) works: the leaf bush keeps its cut-out shape and both faces.
- GM-hidden Scyther: clearly 40 percent see-through (wings and body), and back to opaque when shown.
- Settings: the "Token shading" row (Painted, an OptionButton like Interface size) sits between
  Lo-fi filter and Token ghost; at 1280x720 it is aligned with the rows around it.

Perf (`packtoon_perf.json`, 30 tokens, 1920x1080, vsync off, in-run alternating windows; shared
GPU, the first window ran while the card clocked up from P8): GPU median ms original_a 3.10,
painted_a 3.32, original_b 3.37, painted_b 3.39, original_c 3.40. After the clock settled the
painted window is within 0.02 ms of its original neighbours (drift is about 0.03 ms per window); the
first pair's 0.2 ms is the clock ramp. Visible draws are 815 in both (a replacement, no extra
pass). Indicative only; not entered in `docs/PERFORMANCE.md`.
