# Lighting and Environment System

This document describes the lighting and environment configuration system for levels in TT-Sim.

## Overview

The lighting and environment system allows Dungeon Masters (DMs) to configure how maps appear to players by controlling:

1. **Light Intensity Scaling** - Adjusts the brightness of lights embedded in GLB map files
2. **Environment Presets** - Pre-configured mood settings (fog, ambient light, glow, etc.)
3. **Environment Overrides** - Fine-tuned adjustments to individual environment properties

These settings are stored in `LevelData` and serialized to `level.json` for folder-based levels.

## Light Intensity Scaling

### The Problem

When exporting 3D models with lights from Blender to GLB format, there's a unit mismatch:

- **Blender** uses physical light units (Watts for point lights, Watts/m² for area lights)
- **glTF/GLB** uses candelas (cd) and lux (lx) via the `KHR_lights_punctual` extension
- **Godot** uses an abstract "energy" value (unitless)

This means a light that looks correct in Blender may appear much brighter or dimmer in Godot.

### Blender Export Modes

Blender offers two lighting export modes:

1. **Standard (Physical)** - Converts physical units to candelas/lux. Results in very bright lights in Godot.
2. **Unitless** - Exports the raw energy value without conversion. Generally produces better results.

### The Solution

The `light_intensity_scale` property in `LevelData` acts as a multiplier for all lights in the map:

```gdscript
# In LevelData
@export var light_intensity_scale: float = 1.0
```

- **1.0** = No change (use for Blender "Unitless" exports)
- **0.001 - 0.01** = Typical range for Blender "Standard" exports
- Can be adjusted in real-time using the Lighting Editor

### Technical Implementation

Light processing occurs in `GlbUtils`:

```gdscript
static func process_lights(node: Node, intensity_scale: float = 1.0) -> void:
    var lights: Array[Light3D] = []
    _find_lights_recursive(node, lights)
    for light in lights:
        light.light_energy *= intensity_scale
```

This is called automatically when loading maps via `GlbUtils.load_glb_with_processing()` or `load_glb_with_processing_async()`.

## Environment Presets

### Available Presets

The `EnvironmentPresets` class (`utils/environment_presets.gd`) provides 18 pre-configured environment settings:

| Preset | Description |
|--------|-------------|
| `outdoor_day` | Bright daylight with blue sky ambient |
| `outdoor_overcast` | Cloudy day with muted colors and light fog |
| `outdoor_sunset` | Warm orange/pink tones with atmospheric glow |
| `outdoor_night` | Dark blue moonlit atmosphere |
| `indoor_neutral` | Balanced indoor lighting (default) |
| `dungeon_dark` | Dark stone corridors with minimal light |
| `dungeon_crypt` | Eerie underground tomb atmosphere |
| `cave` | Natural cave with cool dampness |
| `tavern` | Warm firelit inn interior |
| `forest` | Dappled woodland lighting |
| `swamp` | Murky greenish fog |
| `underwater` | Blue-green aquatic environment |
| `hell` | Fiery infernal realm |
| `ethereal` | Magical mystical atmosphere |
| `arctic` | Cold icy blue tones |
| `desert` | Hot sandy wasteland |
| `none` | Minimal environment (for custom setups) |
| `bright_editor` | Extra bright for editing (not for gameplay) |

### Preset Properties

Each preset can configure:

- **Background**: Mode and color
- **Ambient Light**: Color and energy
- **Fog**: Enabled, color, density, height
- **Tonemap**: Mode, exposure, white point
- **Glow/Bloom**: Enabled, intensity, strength
- **SSAO**: Enabled, intensity
- **SSR**: Enabled
- **SDFGI**: Enabled

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
    "fog_density": 0.02
}
```

Overrides are merged on top of the selected preset's values.

## Using the Lighting Editor

### Accessing the Editor

1. Open the **Level Editor**
2. Select or create a level with a map file
3. In the **Map** section, click **"Edit..."** next to "Lighting & Environment"

### Editor Interface

The Lighting Editor displays a real-time 3D preview of your map with a floating control panel:

- **Preset Dropdown** - Select an environment preset
- **Light Scale** - Adjust light intensity (slider + direct input)
- **Overrides Section**:
  - Ambient color and energy
  - Fog toggle and density
  - Glow toggle and intensity

### Resizing the Panel

The control panel can be resized by dragging its left edge (indicated by grip lines).

### Saving/Canceling

- **Save** - Applies settings to the level data
- **Cancel** - Discards changes and exits

## Data Storage

### LevelData Resource

```gdscript
# Map lighting
@export var light_intensity_scale: float = 1.0

# Environment
@export var environment_preset: String = "indoor_neutral"
@export var environment_overrides: Dictionary = {}
```

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
  }
}
```

Note: Color values are stored as hex strings in JSON and converted back to `Color` objects when loaded.

## Runtime Application

When a level is loaded for play, `LevelPlayController` applies the settings:

1. Loads the GLB map with `light_intensity_scale` applied to all lights
2. Creates a `WorldEnvironment` node in the game map
3. Applies the preset and overrides via `EnvironmentPresets.apply_to_world_environment()`

```gdscript
func _apply_level_environment(level_data: LevelData) -> void:
    if not _world_environment:
        _world_environment = WorldEnvironment.new()
        _game_map.add_child(_world_environment)
    
    EnvironmentPresets.apply_to_world_environment(
        _world_environment,
        level_data.environment_preset,
        level_data.environment_overrides
    )
```

## Testing Tools

A standalone test scene is available at `tests/test_glb_lights.tscn` for:

- Loading arbitrary GLB files
- Testing light intensity values
- Previewing environment presets
- Experimenting with overrides
- Copying settings as JSON for `level.json`

## API Reference

### EnvironmentPresets (Static Class)

```gdscript
# Get list of available preset names
static func get_preset_names() -> Array[String]

# Get description for a preset
static func get_preset_description(preset_name: String) -> String

# Get merged configuration (defaults + preset + overrides)
static func get_environment_config(preset_name: String = "", overrides: Dictionary = {}) -> Dictionary

# Apply configuration to a WorldEnvironment node
static func apply_to_world_environment(world_env: WorldEnvironment, preset_name: String = "", overrides: Dictionary = {}) -> void

# Create a new Environment resource with settings applied
static func create_environment(preset_name: String = "", overrides: Dictionary = {}) -> Environment

# Convert overrides to/from JSON-safe format
static func overrides_to_json(overrides: Dictionary) -> Dictionary
static func overrides_from_json(json_data: Dictionary) -> Dictionary
```

### GlbUtils Light Functions

```gdscript
# Process all lights in a scene tree
static func process_lights(node: Node, intensity_scale: float = 1.0) -> void

# Load GLB with full processing including light scaling
static func load_glb_with_processing(path: String, create_static_bodies: bool = false, light_intensity_scale: float = 1.0) -> Node3D

# Async version
static func load_glb_with_processing_async(path: String, create_static_bodies: bool = false, light_intensity_scale: float = 1.0) -> AsyncLoadResult
```

## Best Practices

1. **For Blender exports**: Use "Unitless" lighting mode when possible. If using "Standard" mode, expect to use `light_intensity_scale` values around 0.001-0.01.

2. **Start with presets**: Choose the closest preset to your desired mood, then use overrides for fine-tuning.

3. **Test with the preview**: Always use the Lighting Editor preview to see how settings look before saving.

4. **Consider player hardware**: Heavy post-processing effects (SSAO, SSR, SDFGI) may impact performance on lower-end machines.

5. **Document custom settings**: If using specific override values, consider noting them in the level description for future reference.
