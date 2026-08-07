# Wind Foliage Sway Tuning + Level Edit Drawer Clipping Fix

**Date:** 2026-08-07
**Status:** Approved design

## Problem

The wind-sway shader feature (`utils/wind_foliage.gd`, `shaders/wind_foliage.gdshader`) classifies
every Geoscatter-scattered instance into a `"tree"` or `"grass"` category and applies a hardcoded
preset (`sway_speed`, `sway_amplitude`, `sway_frequency`). This works, but the values are baked into
`WindFoliage.PRESETS` with no way to adjust them per level -- if a map's grass sways too fast or a
map's trees barely move, the only fix is editing source and re-deploying.

Separately, while testing this feature in the level editor, a pre-existing layout bug was found:
the level edit drawer (`level_edit_panel.tscn`/`.gd`) renders several controls flush against the
actual window edge with no margin, clipping their content off-screen entirely (confirmed both via
the validator MCP tool and in a real windowed screenshot). Any new controls added to this drawer
risk reproducing the same bug, so it needs to be fixed as part of this work.

## Scope

- Expose **per-category** (tree/grass) sway tuning, not per-detected-multimesh. A map can have an
  arbitrary number of distinct scattered source objects; giving each its own row would require
  dynamic UI generation with no existing precedent in this codebase. Per-category matches every
  other tunable in the level editor (environment/lofi/weather are all level-wide override
  dictionaries, never per-object).
- Expose **speed and amplitude** only. `sway_frequency` (controls desync between neighboring
  instances, not "how the sway feels") stays fixed at the preset default.
- Fix the drawer clipping bug, and verify it doesn't regress when the new Foliage section is added.
- Out of scope: per-instance/per-source-object tuning, exposing `sway_frequency`, any other
  unrelated drawer bugs not caused by the same overflow mechanism.

## Part 1: Foliage sway overrides

### Data model

`LevelData` (`resources/level_data.gd`) gains:

```gdscript
@export var foliage_overrides: Dictionary = {}
```

Flat keys, matching the style of `weather_overrides` (not the nested per-category shape of
`WindFoliage.PRESETS`): `tree_sway_speed`, `tree_sway_amplitude`, `grass_sway_speed`,
`grass_sway_amplitude`. Wired into `to_dict()`, `from_dict()`, and `duplicate_level()` identically
to the existing override dictionaries.

`WindFoliage` gains:

```gdscript
static func get_effective_preset(category: String, overrides: Dictionary) -> Dictionary
```

Starts from `PRESETS[category]`, overlays `<category>_sway_speed` / `<category>_sway_amplitude`
from `overrides` if present. Returns the preset unchanged if `category` isn't a valid key.

### Load-time baking

`load_map()` / `load_map_async()` already thread `light_intensity_scale` down to
`process_lights()`. `foliage_overrides` follows the identical path:

```
load_map(_async) -> load_glb_with_processing(_async) -> process_scatter_instances()
  -> WindFoliage.apply_material() [via WindFoliage.get_effective_preset()]
```

Every call site currently passing `light_intensity_scale` down this chain gains a parallel
`foliage_overrides: Dictionary = {}` parameter. This ensures a freshly loaded map's multimesh
materials are built with the correct starting values -- no separate "apply after load" step needed
for the initial render.

### Live tuning (no map reload)

Dragging a slider in the drawer must update the already-rendered materials instantly, mirroring
`LevelEnvironmentManager`'s existing light-intensity pattern (`store_original_light_energies` /
`apply_light_intensity_scale`): cache references once after load, then re-apply on demand rather
than re-walking or reloading the whole scene tree each time.

- `WindFoliage._build_shader_material()` tags each built `ShaderMaterial` with
  `set_meta("wind_category", category)`.
- `LevelEnvironmentManager` gains `store_wind_materials(node: Node)`, called once after map load
  (alongside the existing `store_original_light_energies` call site), which walks the tree once and
  caches found wind `ShaderMaterial`s (identified by the `wind_category` meta tag) keyed by
  category.
- `LevelEnvironmentManager` gains `apply_foliage_overrides(overrides: Dictionary)`, which computes
  each category's effective preset via `WindFoliage.get_effective_preset()` and calls
  `set_shader_parameter("sway_speed", ...)` / `set_shader_parameter("sway_amplitude", ...)` on every
  cached material for that category. No shader recompilation, same instant-feedback feel as every
  other slider in the drawer.

### Multiplayer sync

`weather_changed`/`environment_changed` already broadcast via `NetworkManager.broadcast_visual_settings`
so every connected client sees the same look live. `foliage_changed` does the same -- otherwise the
GM's sway tuning wouldn't match what players see. This follows `_on_edit_weather_changed()`'s exact
shape in `gameplay_menu_controller.gd`.

### UI

New "Foliage" section in `level_edit_panel.tscn`, placed after the existing "Weather" section:

- A `Label` heading ("Foliage"), then four rows using the existing
  `Label(custom_minimum_size 80px) + SliderSpinBox(size_flags_horizontal EXPAND_FILL)` pattern
  already used by every other row in this drawer: `TreeSwaySpeedSliderSpin`,
  `TreeSwayAmplitudeSliderSpin`, `GrassSwaySpeedSliderSpin`, `GrassSwayAmplitudeSliderSpin`.
- `level_edit_panel.gd` gains a `foliage_changed(overrides: Dictionary)` signal, a
  `current_foliage_overrides: Dictionary` field, a `_sync_foliage_controls()` method, and binds the
  four new sliders through the same generic `_on_foliage_override_changed(value, key)` handler
  pattern already used for weather/lofi.
- `initialize()` gains a `foliage_overrides: Dictionary = {}` parameter; `_on_save_pressed()`'s
  emitted `save_requested` tuple gains `current_foliage_overrides`.
- `gameplay_menu_controller.gd` wires `foliage_changed` exactly like `weather_changed`
  (`_on_edit_foliage_changed`, snapshot-on-open for cancel/revert, persist-on-save, broadcast on
  change).

## Part 2: Level edit drawer clipping fix

### Root cause

Reproduced live (validator MCP screenshot and a real windowed screenshot both show the same thing):
several rows in the drawer -- the "System" and "Preset" `OptionButton` dropdowns, and the
"Background" `ColorPickerButton` -- render with their right edge flush against the actual window
edge, content cut off, while narrower rows keep their expected margin.

This is a specific, reproducible Godot behavior: `OptionButton`'s minimum width is driven by its
*currently selected item's text* unless `clip_text` is explicitly set to `true`, and **Godot
containers never shrink a child below its reported minimum size** -- if a child's minimum exceeds
the space available, the child (and the row containing it) overflows past the container's own
boundary rather than being clamped. `"D&D / Pathfinder (5 ft squares)"` and `"Map Defaults"` are
long enough to exceed the drawer's ~318px content width (350px panel minus two 16px margins), and
because this drawer is docked flush against the right screen edge, that overflow bleeds off the
actual visible window instead of just looking cramped.

### Fix

- Set `clip_text = true` on every `OptionButton` in `level_edit_panel.tscn`:
  `ScalePresetDropdown`, `PresetDropdown`, `SkyPresetDropdown`, `TonemapModeDropdown`. This makes
  their minimum width follow the container's available space (as `size_flags_horizontal = 3`
  already intends) instead of their longest item's un-truncated text.
- Audit the three `ColorPickerButton`s (`BgColorPicker`, `AmbientColorPicker`, `FogColorPicker`) for
  the same class of issue and apply the equivalent fix (`custom_minimum_size` cap or
  clip-appropriate property) if they're still misbehaving once the dropdowns are fixed.
- This drawer has exactly one real-world width (350px, not user-resizable) -- the fix is that
  nothing inside it should ever be able to demand more than that.

### Verification

After the fix (and again after the new Foliage section is added, so it doesn't reintroduce the
bug): use the `tt-sim-validator` MCP tools to open the drawer, expand the Advanced section, and
screenshot -- confirm every row's right edge sits within the visible viewport with its expected
margin, for both the always-visible controls and the Advanced-toggle ones.

## Testing

- Unit test `WindFoliage.get_effective_preset()`: base preset returned unchanged when overrides
  empty/missing keys; overrides applied when present; unknown category returns an empty/default
  dict without erroring.
- Unit test `LevelData.to_dict()`/`from_dict()` round-trips `foliage_overrides`.
- Existing `tests/unit/test_wind_foliage.gd` and `tests/unit/test_glb_utils_scatter_instances.gd`
  extended to cover the load-time override-baking path.
- Manual verification via the validator MCP tools: load the "Sway" level, adjust the new sliders,
  confirm the live sway visibly changes without a map reload; confirm the drawer has no clipped
  controls per the Part 2 verification steps above.
