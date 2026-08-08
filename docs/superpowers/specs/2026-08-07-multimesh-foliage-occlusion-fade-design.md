# Extend Occlusion Fade to Tree Foliage (MultiMeshInstance3D)

**Date:** 2026-08-07
**Status:** Approved design

## Problem

`OcclusionFadeManager` (`scenes/states/playing/occlusion_fade_manager.gd`) makes map geometry
dither-discard around tokens that are hidden behind it, but only ever converts `MeshInstance3D`
nodes (`_collect_mesh_instances()` filters strictly on that type). Trees and other scattered
foliage are built by `GlbUtils.process_scatter_instances()` into `MultiMeshInstance3D` nodes whose
materials are set directly on the shared `Mesh` resource by `WindFoliage.apply_material()`
(`shaders/wind_foliage.gdshader`, for the vertex sway animation). Those materials are never
converted or fed token uniforms, so a token standing behind a large tree (e.g. in the "Sway" level)
never fades into view -- it's simply hidden.

Note this is purely a materials/uniforms gap, not a collision gap: the fade is computed entirely
from vertex/fragment world position vs. token world position in the shader, with no raycast or
physics query involved. Foliage having no `CollisionShape3D` is unrelated to why it doesn't fade;
it does mean foliage was already fully click-through for token picking, which is unaffected by
this change.

## Scope

- Extend the fade to **tree-category** foliage only. Grass is short enough to rarely fully occlude
  a token, and skipping it avoids the added per-fragment discard/dither cost on what's usually the
  densest scatter layer.
- Share the discard/dither logic between `occlusion_fade.gdshader` and `wind_foliage.gdshader`
  rather than duplicating it, so the two stay in sync as the technique evolves.
- Out of scope: grass occlusion, the `res://` `PackedScene` map-load path (per
  `process_scatter_instances()`'s existing docstring, scatter processing only runs on the
  `load_glb_with_processing()` upload path today -- that gap is pre-existing and unrelated to this
  change), any change to how the fade radius or token uniforms are computed.

## Design

### Shared shader logic

`shaders/occlusion_fade_include.gdshaderinc` (new) holds the existing discard/dither logic
factored out of `occlusion_fade.gdshader`'s `fragment()`: the per-token loop, view-space
nearer-than-token check, screen-space radius check, 16x16 Bayer dither, and floor-normal exemption.
Signature roughly:

```glsl
void apply_occlusion_fade(float vertex_view_z, vec2 screen_uv, vec3 world_normal,
        vec3 token_positions[32], float token_radii[32], int token_count,
        bool enable_occlusion, float min_alpha, float floor_threshold)
```

`occlusion_fade.gdshader` is refactored to `#include` this file and call the function instead of
holding the logic inline -- no behavior change for map geometry.

### Tree shader

`shaders/wind_foliage.gdshader` also `#include`s the new file and calls
`apply_occlusion_fade(...)` at the end of its `fragment()`, after the existing wind-sway vertex
work. It gains the same `token_positions[32]` / `token_radii[32]` / `token_count` uniforms the map
shader already exposes, plus `enable_occlusion: bool` (default `true`).

### Tagging tree multimeshes

`GlbUtils._build_multimesh_from_transforms()` already receives the classified `wind_category` for
each scattered mesh. It gains one line: after building the `MultiMeshInstance3D`, call
`multimesh_instance.set_meta("wind_foliage_category", wind_category)`. This reuses the
classification `WindFoliage.classify_category()` already computed, rather than having
`OcclusionFadeManager` re-derive it from material state.

### OcclusionFadeManager changes

- New recursive collector, `_collect_tree_multimeshes(node, result: Array[MultiMeshInstance3D])`,
  mirroring `_collect_mesh_instances()`'s walk but matching
  `child is MultiMeshInstance3D and child.get_meta("wind_foliage_category", "") == "tree"`.
- Their mesh surface materials are added to the same list `_update_token_uniforms()` already
  iterates to push `token_positions` / `token_radii` / `token_count` -- one push loop, longer list.
- No material swap/restore for these: unlike map materials (which start as `StandardMaterial3D`
  and get converted, then restored via `_restore_all_materials()`), tree materials are already the
  live `ShaderMaterial`s `WindFoliage` built at load time. `OcclusionFadeManager` only registers
  and unregisters them for uniform pushes; it never owns or replaces them.
- `set_occlusion_fade_enabled()` sets `enable_occlusion = false`/`true` on tree materials directly
  (a uniform write) instead of swapping materials, since there's no non-shader "original" to
  restore to.
- `clear()` simply drops tree materials from the tracked list; no restore step needed for them.

### Interaction with foliage sway overrides

`LevelEnvironmentManager.apply_foliage_overrides()` / `LevelPlayController.apply_foliage_overrides()`
only touch `sway_speed` / `sway_amplitude` uniforms on existing materials and don't replace or
recreate them, so this change doesn't affect that live-tuning path.

## Testing

- Unit test `GlbUtils`'s multimesh-building path: building a "tree"-classified scatter instance
  results in a node with `get_meta("wind_foliage_category") == "tree"`; a "grass"-classified one
  does not get treated as a tree by the collector.
- Unit test `OcclusionFadeManager`'s new collector against a synthetic scene tree: finds
  tree-tagged `MultiMeshInstance3D` nodes, ignores grass-tagged and untagged ones.
- Shader logic itself isn't unit-testable headlessly (consistent with this project's existing
  `MultiMesh` readback limitations). Manual verification via the `tt-sim-validator` MCP tools: load
  the "Sway" level, position a token behind one of the large trees, screenshot to confirm the
  dithered fade appears; toggle `graphics/occlusion_fade_enabled` and confirm it turns off for both
  the tree and the existing map geometry.
