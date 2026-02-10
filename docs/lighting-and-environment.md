# Lighting and Environment System

This document describes the lighting and environment configuration system for levels in TT-Sim, including the in-game edit panel, environment presets, map defaults, sky presets, and the configuration layering model.

## Table of Contents

- [Overview](#overview)
- [Light Intensity Scaling](#light-intensity-scaling)
- [Environment Configuration Layering](#environment-configuration-layering)
- [Environment Presets](#environment-presets)
- [Sky Presets](#sky-presets)
- [Map Defaults](#map-defaults)
- [Environment Overrides](#environment-overrides)
- [In-Game Edit Panel](#in-game-edit-panel)
- [Post-Processing (Lo-Fi) Overrides](#post-processing-lo-fi-overrides)
- [Data Storage](#data-storage)
- [Runtime Application](#runtime-application)
- [API Reference](#api-reference)
- [Best Practices](#best-practices)

## Overview

The lighting and environment system allows Dungeon Masters (DMs) to configure how maps appear to players by controlling:

1. **Light Intensity Scaling** — Adjusts the brightness of lights embedded in GLB map files
2. **Environment Presets** — Pre-configured mood settings (fog, ambient light, glow, sky, tone mapping, etc.)
3. **Map Defaults** — Environment settings extracted from a map's embedded `WorldEnvironment` node
4. **Environment Overrides** — Fine-tuned adjustments to individual environment properties
5. **Post-Processing (Lo-Fi) Overrides** — Shader-based effects like pixelation, color depth, and color fade

All settings are stored in `LevelData` and serialized to `level.json` for folder-based levels. Changes can be made in real time using the in-game edit panel.

## Light Intensity Scaling

### The Problem

When exporting 3D models with lights from Blender to GLB format, there's a unit mismatch:

- **Blender** uses physical light units (Watts for point lights, Watts/m² for area lights)
- **glTF/GLB** uses candelas (cd) and lux (lx) via the `KHR_lights_punctual` extension
- **Godot** uses an abstract "energy" value (unitless)

This means a light that looks correct in Blender may appear much brighter or dimmer in Godot.

### Blender Export Modes

Blender offers two lighting export modes:

1. **Standard (Physical)** — Converts physical units to candelas/lux. Results in very bright lights in Godot.
2. **Unitless** — Exports the raw energy value without conversion. Generally produces better results.

### The Solution

The `light_intensity_scale` property in `LevelData` acts as a multiplier for all lights in the map:

```gdscript
# In LevelData
@export var light_intensity_scale: float = 1.0
```

- **1.0** = No change (use for Blender "Unitless" exports)
- **0.001 - 0.01** = Typical range for Blender "Standard" exports
- Can be adjusted in real-time using the in-game edit panel

### Technical Implementation

Light processing occurs in `GlbUtils`:

```gdscript
static func process_lights(node: Node, intensity_scale: float = 1.0) -> void:
    var lights: Array[Light3D] = []
    _find_lights_recursive(node, lights)
    for light in lights:
        light.light_energy *= intensity_scale
```

This is called automatically when loading maps via `GlbUtils.load_map()` or `load_map_async()`.

## Environment Configuration Layering

Environment settings are computed at runtime by layering multiple sources. This ensures map defaults are always freshly derived from the live map file, never baked into `level_data`.

### Layer Order (lowest to highest priority)

```
1. PROPERTY_DEFAULTS   — Base defaults for all environment properties
2. Map Defaults        — Applied when preset is "" and map has an embedded environment
3. Named Preset        — Applied when a named preset is selected (e.g. "tavern")
4. User Overrides      — Always applied on top of everything else
```

### How It Works

- **`environment_preset = ""`** (empty string): The map's embedded environment settings are used as the base. This is the default for new levels and for levels that use "Map Defaults".
- **`environment_preset = "tavern"`** (named preset): The named preset replaces map defaults. User overrides are still applied on top.
- **User overrides** are individual property tweaks made by the DM (e.g. increasing fog density). They always take highest priority.

This layering is computed by `EnvironmentPresets.get_environment_config()` and never mutates `level_data` — the effective config is always derived at apply-time.

## Environment Presets

### Available Presets

The `EnvironmentPresets` class (`utils/environment_presets.gd`) provides 18 pre-configured environment settings:

| Preset | Description |
|--------|-------------|
| `outdoor_day` | Bright daylight with clear sky and neutral lighting |
| `outdoor_overcast` | Cloudy day with soft diffuse lighting |
| `outdoor_sunset` | Golden hour — warm orange/pink lighting |
| `outdoor_night` | Moonlit night — cool blue tones, low visibility |
| `indoor_neutral` | Standard indoor lighting — neutral, well-lit |
| `dungeon_dark` | Dark stone corridors with minimal light |
| `dungeon_crypt` | Eerie underground tomb — cold, deathly atmosphere |
| `cave` | Natural cave — damp, earthy tones |
| `tavern` | Cozy firelit inn interior |
| `forest` | Dense forest with dappled green light |
| `swamp` | Murky swamp — thick fog, sickly green |
| `underwater` | Blue-green aquatic depths |
| `hell` | Infernal realm — fiery red/orange glow |
| `ethereal` | Fey realm — soft magical glow |
| `arctic` | Frozen tundra — cold blue-white |
| `desert` | Harsh desert — bright, warm, hazy |
| `none` | No environment effects — minimal baseline |
| `bright_editor` | Extra bright for editing (not for gameplay) |

### Preset Properties

Each preset can configure any combination of the following properties:

**Background & Sky:**
- `background_mode` — `BG_COLOR`, `BG_SKY`, or `BG_CANVAS`
- `background_color` — Background fill color
- `sky_preset` — Sky preset name (see [Sky Presets](#sky-presets))

**Ambient Light:**
- `ambient_light_source` — `AMBIENT_SOURCE_COLOR` or `AMBIENT_SOURCE_SKY`
- `ambient_light_color` — Ambient fill color
- `ambient_light_energy` — Ambient intensity

**Fog:**
- `fog_enabled`, `fog_light_color`, `fog_light_energy`
- `fog_density`, `fog_height`, `fog_height_density`

**Tone Mapping:**
- `tonemap_mode` — `Linear`, `Reinhardt`, `Filmic`, or `ACES`
- `tonemap_exposure`, `tonemap_white`

**Glow/Bloom:**
- `glow_enabled`, `glow_intensity`, `glow_strength`, `glow_bloom`

**Adjustments:**
- `adjustment_enabled` — Master toggle for brightness/contrast/saturation
- `adjustment_brightness`, `adjustment_contrast`, `adjustment_saturation`

**Advanced:**
- `ssao_enabled`, `ssao_intensity`
- `ssr_enabled`
- `sdfgi_enabled`
- `reflected_light_source` — `REFLECTION_SOURCE_BG` or `REFLECTION_SOURCE_SKY`

## Sky Presets

Sky presets create procedural skies using Godot's `ProceduralSkyMaterial`. Each defines sky/horizon/ground colors, sun angle, and other parameters.

### Available Sky Presets

| Preset | Description |
|--------|-------------|
| `clear_day` | Clear blue sky with neutral horizon |
| `sunset` | Warm orange/pink sunset sky |
| `overcast` | Gray overcast sky |
| `night_sky` | Dark night sky with faint horizon |
| `map_default` | Uses the sky resource extracted from the loaded map (only available when the map had an embedded sky) |

### How Skies Work

When a sky preset is selected:

1. `EnvironmentPresets.create_sky_from_preset()` builds a `Sky` resource with a `ProceduralSkyMaterial`
2. The environment's `background_mode` is set to `BG_SKY`
3. If `ambient_light_source` is `AMBIENT_SOURCE_SKY`, ambient lighting is derived from the sky

The special `map_default` preset reuses the `Sky` resource that was extracted from the map's embedded `WorldEnvironment` during loading. This allows maps with custom skies to have their sky preserved and restorable.

## Map Defaults

When a map file (`.tscn` or `.glb`) contains an embedded `WorldEnvironment` node, the system:

1. **Extracts** all environment properties via `EnvironmentPresets.extract_from_environment()`
2. **Preserves** the `Sky` resource (if any) for the `map_default` sky preset
3. **Strips** the embedded `WorldEnvironment` node to prevent conflicts with the programmatic one
4. **Stores** the extracted config as `_map_environment_config` on `LevelPlayController`

### Using Map Defaults

- When `environment_preset` is `""` (empty) and map defaults exist, the map's settings are used as the base layer
- The in-game edit panel shows a "Map Defaults" option in the preset dropdown when the map provides defaults
- A "Revert to Map Defaults" button clears the preset and overrides, restoring the map's original appearance
- Map defaults are **never** baked into `level_data` — they are always freshly extracted from the map at load time

### Why Map Defaults Are Not Saved

Map defaults are derived from the map file itself, not stored in `level_data`. This ensures:

- If the map file is updated (e.g. new lights added in Blender), the defaults reflect the change
- No stale data accumulates in `level.json`
- The layering model stays clean: `level_data` only stores the DM's intentional choices (preset name + overrides)

## Environment Overrides

Overrides allow fine-tuning individual properties without creating a new preset:

```gdscript
# In LevelData
@export var environment_overrides: Dictionary = {}

# Example overrides
{
    "ambient_light_color": Color(0.5, 0.4, 0.3),
    "ambient_light_energy": 0.8,
    "fog_enabled": true,
    "fog_density": 0.02,
    "adjustment_brightness": 1.2
}
```

Overrides are merged on top of the selected preset's values (or map defaults when no preset is selected). Only changed properties need to be included — everything else comes from the preset/defaults.

## In-Game Edit Panel

The `LevelEditPanel` is a slide-out drawer (extends `DrawerContainer`) that appears on the right edge of the screen during gameplay. It provides real-time editing of all level properties with immediate visual feedback.

### Accessing the Panel

1. During gameplay, the "Edit" tab appears on the right edge of the screen
2. Click the tab (or it slides out) to open the panel
3. All changes are applied to the live viewport immediately

### Panel Sections

**Map Scale** — Uniform scale slider for the map geometry.

**Lighting & Environment:**
- **Preset dropdown** — Choose a named preset or "Map Defaults"
- **Lighting Power** — Light intensity multiplier for embedded lights
- **Ambient Light** — Color and energy
- **Fog** — Toggle, color, density, height
- **Glow/Bloom** — Toggle, intensity, strength, bloom
- **Exposure** — Tone mapping mode, exposure, white point
- **Brightness / Contrast / Saturation** — Adjustment controls

**Advanced (collapsible):**
- Background mode and color
- Sky preset
- Ambient light source
- Reflected light source
- SSAO, SSR, SDFGI toggles
- Fog height density

**Post-Processing Effects:**
- Pixelation
- Color Depth
- Color Fade (lo-fi shader saturation)
- Outline

**Actions:**
- **Revert to Map Defaults** — Restores the map's embedded environment (visible only when the map has defaults)
- **Edit Details** — Opens the dedicated Level Editor for token placement and metadata
- **Save Level** — Persists all changes to disk
- **Cancel** — Reverts all changes and closes the panel

### Signal Flow

```
LevelEditPanel (UI)
  ├── environment_changed(preset, overrides) ──→ GameplayMenuController
  │                                                    ├──→ LevelPlayController.apply_environment_settings()
  │                                                    │       └── EnvironmentPresets.apply_to_world_environment()
  │                                                    │               └── get_environment_config(preset, overrides, map_defaults)
  │                                                    │                       └── Layered config → _apply_config_to_environment()
  ├── intensity_changed(scale) ──→ GameplayMenuController ──→ LevelPlayController
  ├── map_scale_changed(scale) ──→ GameplayMenuController ──→ LevelPlayController
  ├── lofi_changed(overrides) ──→ GameplayMenuController ──→ GameMap.apply_lofi_overrides()
  ├── save_requested(...) ──→ GameplayMenuController._on_edit_save_requested()
  ├── cancel_requested ──→ GameplayMenuController (reverts all changes)
  └── revert_to_map_defaults_requested ──→ GameplayMenuController._on_revert_to_map_defaults()
```

### Cancel / Revert Behavior

When the panel is closed without saving:

1. `GameplayMenuController` detects the drawer closed without a save
2. Restores all original values (map scale, light intensity, preset, overrides, lo-fi overrides)
3. Re-applies the original environment settings to the live viewport

## Post-Processing (Lo-Fi) Overrides

The game map uses a lo-fi shader for optional retro-style post-processing. These settings are independent of the `Environment` resource.

| Property | Description |
|----------|-------------|
| `pixelation` | Pixel size for retro pixelation effect |
| `color_depth` | Bit depth for color quantization |
| `saturation` | Color fade — desaturates the lo-fi output (labeled "Color Fade" in the UI to distinguish from environment saturation) |
| `outline` | Edge detection outline effect |

Lo-fi overrides are stored in `LevelData.lofi_overrides` and applied via `GameMap.apply_lofi_overrides()`.

## Data Storage

### LevelData Resource

```gdscript
# Map lighting
@export var light_intensity_scale: float = 1.0

# Environment
# Empty string = "use map defaults if available, otherwise PROPERTY_DEFAULTS"
@export var environment_preset: String = ""
@export var environment_overrides: Dictionary = {}

# Post-processing
@export var lofi_overrides: Dictionary = {}
```

**Important:** `environment_preset` defaults to `""` (empty string), not a named preset. This means new levels start with map defaults when available.

### level.json Format

For folder-based levels, settings are stored in `level.json`:

```json
{
  "level_name": "Dark Dungeon",
  "light_intensity_scale": 0.005,
  "environment_preset": "dungeon_dark",
  "environment_overrides": {
    "fog_enabled": true,
    "fog_density": 0.03,
    "ambient_light_color": "#1a1a2e"
  },
  "lofi_overrides": {
    "pixelation": 2.0,
    "color_depth": 16.0
  }
}
```

Notes:
- Color values are stored as hex strings in JSON and converted back to `Color` objects when loaded
- An empty `environment_preset` (`""`) means "use map defaults"
- Conversion is handled by `EnvironmentPresets.overrides_to_json()` / `overrides_from_json()`

## Runtime Application

### Map Loading Pipeline

When a level is loaded for play, `LevelPlayController` handles the environment setup:

1. Loads the GLB/TSCN map via `GlbUtils.load_map_async()` with `light_intensity_scale`
2. **Extracts and strips** embedded `WorldEnvironment` nodes:
   - `_extract_and_strip_map_environment()` reads all environment properties
   - Preserves the `Sky` resource if one exists
   - Removes the embedded nodes to prevent conflicts
3. Creates a programmatic `WorldEnvironment` node ("LevelEnvironment")
4. Applies the layered configuration via `EnvironmentPresets.apply_to_world_environment()`
5. Applies lo-fi shader overrides if any are set

```gdscript
func _apply_level_environment(level_data: LevelData) -> void:
    if not is_instance_valid(_world_environment):
        _world_environment = WorldEnvironment.new()
        _world_environment.name = "LevelEnvironment"
        _game_map.world_viewport.add_child(_world_environment)

    EnvironmentPresets.apply_to_world_environment(
        _world_environment,
        level_data.environment_preset,
        level_data.environment_overrides,
        _map_sky_resource,
        _map_environment_config,  # map defaults passed as a layer
    )
```

### Real-Time Updates

When the DM changes settings in the edit panel:

```gdscript
# Called from GameplayMenuController when the edit panel emits environment_changed
func apply_environment_settings(preset: String, overrides: Dictionary) -> void:
    EnvironmentPresets.apply_to_world_environment(
        _world_environment, preset, overrides, _map_sky_resource, _map_environment_config
    )
```

The `_map_environment_config` is always passed through so map defaults are available as a layer.

### Saving

When the DM clicks "Save Level":

- **Folder-based levels** (`level_folder` not empty): Saved via `LevelManager.save_level_folder()` → writes `level.json`
- **Legacy levels** (`.tres`): Saved via `LevelManager.save_level()` → writes `.tres` resource

## API Reference

### EnvironmentPresets (Static Class)

```gdscript
# Get list of available preset names
static func get_preset_names() -> Array[String]

# Get description for a preset
static func get_preset_description(preset_name: String) -> String

# Get merged configuration with layering: PROPERTY_DEFAULTS → map_defaults → preset → overrides
static func get_environment_config(
    preset_name: String = "",
    overrides: Dictionary = {},
    map_defaults: Dictionary = {},
) -> Dictionary

# Apply configuration to a WorldEnvironment node
# map_sky: Optional Sky resource from the loaded map (for "map_default" sky preset)
# map_defaults: Config extracted from map's embedded WorldEnvironment
static func apply_to_world_environment(
    world_env: WorldEnvironment,
    preset_name: String = "",
    overrides: Dictionary = {},
    map_sky: Sky = null,
    map_defaults: Dictionary = {},
) -> void

# Extract all supported settings from an existing Environment resource
# Returns a dictionary with keys matching PROPERTY_DEFAULTS
static func extract_from_environment(env: Environment) -> Dictionary

# Create a Sky resource from a sky preset name
static func create_sky_from_preset(preset_name: String) -> Sky

# Convert overrides to/from JSON-safe format (Colors → hex strings)
static func overrides_to_json(overrides: Dictionary) -> Dictionary
static func overrides_from_json(json_data: Dictionary) -> Dictionary
```

### LevelPlayController Environment Functions

```gdscript
# Apply environment settings to the live WorldEnvironment (real-time editing)
func apply_environment_settings(preset: String, overrides: Dictionary) -> void

# Get the config extracted from the loaded map's embedded WorldEnvironment
func get_map_environment_config() -> Dictionary

# Get the Sky resource extracted from the loaded map (null if none)
func get_map_sky_resource() -> Sky
```

### GlbUtils Environment Functions

```gdscript
# Strip all WorldEnvironment nodes from a scene tree
static func strip_world_environments(root: Node3D) -> void

# Process all lights in a scene tree
static func process_lights(node: Node, intensity_scale: float = 1.0) -> void

# Load map with full processing including light scaling
static func load_map_async(path: String, create_static_bodies: bool = false, light_scale: float = 1.0) -> Node3D

# Synchronous version
static func load_map(path: String, create_static_bodies: bool = false, light_scale: float = 1.0) -> Node3D
```

## Testing Tools

A standalone test scene is available at `tests/test_glb_lights.tscn` for:

- Loading arbitrary GLB files
- Testing light intensity values
- Previewing environment presets
- Experimenting with overrides
- Copying settings as JSON for `level.json`

## Best Practices

1. **For Blender exports**: Use "Unitless" lighting mode when possible. If using "Standard" mode, expect to use `light_intensity_scale` values around 0.001–0.01.

2. **Start with map defaults**: If the map has embedded lighting, start with "Map Defaults" and use overrides to tweak from there.

3. **Use the edit panel for real-time feedback**: All changes in the edit panel apply immediately to the live viewport — no need to save and reload.

4. **Consider the layering model**: Only override what you need. Overrides are applied on top of the preset/map defaults, so you can change presets without losing your tweaks.

5. **Map defaults are not saved**: They are derived from the map file at load time. If you update your map in Blender, the defaults will reflect the new lighting.

6. **Distinguish saturation controls**: The environment "Saturation" (in Lighting & Environment) adjusts Godot's `Environment.adjustment_saturation`. The lo-fi "Color Fade" (in Post-Processing Effects) is a shader-based desaturation effect.

7. **Consider player hardware**: Heavy post-processing effects (SSAO, SSR, SDFGI) may impact performance on lower-end machines.
