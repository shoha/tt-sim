# Lighting and Environment System

This document describes the lighting and environment configuration system for levels in TT-Sim, including the in-game edit panel, environment presets, map defaults, sky presets, the configuration layering model, and weather effects.

## Table of Contents

- [Overview](#overview)
- [Light Intensity Scaling](#light-intensity-scaling)
- [Environment Configuration Layering](#environment-configuration-layering)
- [Environment Presets](#environment-presets)
- [Sky Presets](#sky-presets)
- [Map Defaults](#map-defaults)
- [Environment Overrides](#environment-overrides)
- [Sun and Shadow](#sun-and-shadow)
- [In-Game Edit Panel](#in-game-edit-panel)
- [Post-Processing (Lo-Fi) Overrides](#post-processing-lo-fi-overrides)
- [Data Storage](#data-storage)
- [Runtime Application](#runtime-application)
- [API Reference](#api-reference)
- [Testing Tools](#testing-tools)
- [Weather Effects](#weather-effects)
- [Best Practices](#best-practices)

## Overview

The lighting and environment system allows Dungeon Masters (DMs) to configure how maps appear to players by controlling:

1. **Light Intensity Scaling** — Adjusts the brightness of lights embedded in GLB map files
2. **Environment Presets** — Pre-configured mood settings (fog, ambient light, glow, sky, tone mapping, etc.)
3. **Map Defaults** — Environment settings extracted from a map's embedded `WorldEnvironment` node
4. **Environment Overrides** — Fine-tuned adjustments to individual environment properties
5. **Post-Processing (Lo-Fi) Overrides** — Shader-based effects like pixelation, color levels, and color fade
6. **Weather Effects** — Combinable particle-based weather (rain, snow, wind) and fog overlay
7. **Sun and Shadow** — Independently art-directable direction, color, energy, and shadow softness/darkness for the level's default sun

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
- `reflected_light_source` — `REFLECTION_SOURCE_BG` or `REFLECTION_SOURCE_SKY`

## Sky Presets

Sky presets are HDRI panoramas (`PanoramaSkyMaterial`, 1024x512 EXR, VRAM compressed)
except Night, which stays a procedural gradient. Every entry also carries gradient colours:
they are the fallback when a panorama cannot load and what headless tests see.

### Available Sky Presets

| Preset | Kind | Description |
|--------|------|-------------|
| `clear_day` | HDRI | Clear midday sky, cool fill, hard shadows |
| `cloudy` | HDRI | Bright day with scattered clouds, soft fill |
| `overcast` | HDRI | Flat grey overcast, shadowless and even |
| `morning` | HDRI | Cool clear dawn, low pale sun |
| `sunset` | HDRI | Orange sunset with lit clouds, warm fill |
| `dusk` | HDRI | Blue dusk after sunset, faint warm horizon |
| `storm` | HDRI | Dark thunderstorm sky, dim and dramatic |
| `night_sky` | gradient | Dark night sky with faint horizon |
| `map_default` | map | The sky resource extracted from the loaded map (only when the map had an embedded sky) |

### How Skies Work

When a sky preset is selected:

1. `create_sky_from_preset()` builds a `PanoramaSkyMaterial` from the entry's `panorama` with its
   `energy` multiplier, or a `ProceduralSkyMaterial` from the gradient colours (also the fallback
   when the file is missing, with one warning)
2. `background_mode` is `BG_SKY`
3. Sky-sourced ambient and reflections read the panorama
4. **The sky is drawn flat**: the map camera is orthographic, and Godot draws any sky behind
   an orthographic camera as a wide-angle perspective view, which turns a panorama into a
   stretched fisheye horizon beyond the map edge. `LevelEnvironmentManager` sets
   `Environment.sky_custom_fov` to `SKY_ORTHO_FOV_DEG` (2 degrees) whenever it syncs the sky,
   so the background is the sky sampled in the camera's single view direction: a flat tone
   from the dome's ground band. Lighting and reflections use the radiance map and are
   unaffected.
5. **Sky follows the sun**: `LevelEnvironmentManager` sets `Environment.sky_rotation` to
   `EnvironmentPresets.sky_rotation_for(sun azimuth, sky key)` after every environment or sun
   change, in every sun mode. The yaw is
   `sun azimuth + sun_azimuth_deg + SKY_YAW_OFFSET_DEG` wrapped to [0, 360), with the offset
   calibrated to 180: Godot samples a panorama mirrored relative to the sun azimuth
   convention (column c sits at world azimuth 180 - c when unrotated), which is why the sky's
   azimuth is added rather than subtracted. Calibrated live in two steps by comparing the
   boulder's sky-lit side (sun off) with its sun-lit side at the same azimuth: the clear-day dome
   fixed the half turn, and the sunset dome (sky azimuth 270.7, where adding and subtracting the
   sky azimuth differ by 181 degrees) fixed the sign. `test_sunset_yaw_matches_the_live_calibration`
   pins the result with a literal.

The special `map_default` preset reuses the `Sky` resource that was extracted from the map's embedded `WorldEnvironment` during loading. This allows maps with custom skies to have their sky preserved and restorable.

### Curating a sky

1. Add a manifest entry to `tools/skies_manifest.json`.
2. Run `godot --headless --editor --path . --script res://tools/curate_skies.gd --quit-after 3`,
   then `godot --headless --import --path .`.
3. Paste the printed entry into `SKY_PRESETS`.
4. Add the tile to `SkyPane.SKY_TILES`.
5. Add the licence row in `THIRD_PARTY_LICENSES.md`.
6. Run `test_skies_manifest` and `test_environment_presets_skies`.

The curation tool measures a panorama's azimuth as the brightest column over the top 45 percent of
the image, and sets exposure by matching the panorama's sky-band mean luminance to the clear-day
gradient's (linear reference), with a manifest `energy` field overriding the computed value when set.

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

### Blender-Authored Ambient Light (glTF Extras)

Maps exported directly from Blender via the companion `terrain-paint` addon have no
embedded `WorldEnvironment` node at all -- glTF has no representation for one. Instead,
enabling **Ambient Light** in that addon's Export glTF dialog writes the World's
Background Color/Strength into the exported file's scene-level glTF `extras` (a small
JSON blob attached to the file, independent of any mesh/node data).

`GlbUtils.extract_lighting_config()` reads this back after loading a `.glb` map and
maps it onto `ambient_light_color`/`ambient_light_energy` -- the same keys
`EnvironmentPresets.PROPERTY_DEFAULTS` uses. `LevelEnvironmentManager
.extract_and_strip_map_environment()` merges it into the map-defaults layer as the
base, with anything extracted from an embedded `WorldEnvironment` node fully
overwriting the overlapping keys when one exists -- in practice a single map only ever
provides one or the other, since `.tscn` (Godot-authored) maps use the
`WorldEnvironment` path and Blender-exported `.glb` maps use the extras path, so this
rarely matters in practice.

As with `light_intensity_scale`, the Blender-side value is a starting point, not a
precise conversion -- tune further with the in-game edit panel if it looks off.

### Baked Foliage AO and Texture Packing (2026-09-16)

`terrain-paint`'s per-asset foliage bake used to ray-trace each scatter asset against
its own intersecting cutout cards -- opaque to the AO rays -- and wrote the result into
the baked ORM red (occlusion) channel. Godot scales every ambient and sky contribution
by AO, so that made foliage a near-black silhouette no matter what the environment or
preset said. It also baked into the asset's original atlas sub-region UVs, so a leaf
cluster addressing a 0.09-square corner of a shared atlas landed in ~90x90 texels of its
own 1024 texture and the other 99% was dilation padding.

Both are fixed on the `terrain-paint` side: `bake_orm(bake_ao=False)` writes a flat
white occlusion channel, and the bake runs through a packed temporary UV layer
(`tp_bake_uv`) that scales the asset's UV bounding box up to fill the texture, so the
asset gets the whole 1024 instead of a corner of it. Sandy Clearing's four catalog
biomes (`biome_01/03/07/09`) were re-baked and the map re-exported with the fix.
Measured on the exported `map.glb`, ORM red mean over opaque texels and UV footprint as
`sqrt(UV triangle area) x 1024`:

| Species / surface | ORM red before | after | effective px before | after |
| --- | --- | --- | --- | --- |
| `FP_Fallen_Leaves_B_014` | 0.946 | 1.000 | 90 | 964 |
| `FP_Ferns_031` | 0.753 | 1.000 | 453 | 1698 |
| `FP_Grass_072` | 0.038 | 1.000 | 348 | 538 |
| `FP_Tree_B_001` leaves (surface 1) | 0.086 | 1.000 | 2008 | 2008 |
| `FP_Tree_B_001` bark (surface 0) | 0.122 | 1.000 | tiled | tiled |

Every one of the 60 baked ORM textures in the map now reads exactly 1.000 in the
occlusion channel (they ranged 0.000-0.991 before), which is why
`wind_foliage_include.gdshaderinc`'s `baked_ao_strength` can stay at 0.0 without
throwing anything away: forcing it to 1.0 with the F3 "Baked foliage AO" toggle moves
canopy-region mean luminance by +0.0001 (0.0710 -> 0.0711). Before the re-bake the same
toggle was the difference between 0.033 and 0.076.

**Packing is per-object, not per-material.** `_pack_uv_layer_for_baking` skips any
object with a UV outside [0, 1], because squashing a tiling layout into the unit square
would destroy it. Tree assets carry tiled bark and atlas-sub-region leaves on the same
mesh, so all 7 trees (and 5 rocks that already filled their UV) keep their original
layout -- 53 of the map's 65 scatter assets got `tp_bake_uv`. Tree leaves therefore gain
the white AO but not the larger footprint; giving them both needs per-material packing,
which the bake does not do today.

**The larger footprint did not buy measurable detail.** The packed bake resamples the
source material rather than the old texels, so it is not limited by the previous bake --
but on these assets it had nothing more to read. Cropping each asset's UV box out of the
old texture, scaling that crop up to the footprint it occupies in the new texture, and
diffing against the new texture gives a mean absolute error of 0.0017 (fallen leaves),
0.0031 (ferns) and 0.0004 (grass) per channel; a control that degrades the *new* texture
back to the old crop's pixel budget and diffs the same way scores 0.0009, 0.0033 and
0.0003. The new textures are, to within that noise, upscales of what the old ones already
carried. So the packing is worth keeping for correct mip behaviour and for not shipping
a texture that is 99% dilation padding, but it is not a resolution win on this library,
and the source atlas -- not the bake -- is where the remaining detail budget is. (The
source atlas's own resolution was not inspected, so which of the two limits binds here is
untested.)

#### Addendum: whole-catalog re-bake (2026-09-17)

Three `terrain-paint` follow-ups landed after the run above, and the whole `Baked` catalog
was re-baked with them: UV packing now runs per *material datablock* rather than per
material slot, the catalog's helper UV layers are pruned *after* the bakes instead of
before, and baked images are written 8-bit instead of 32-bit float. All 43 biomes across
`CaseySheep/FloraPaint` (12) and `Plant Library` (31) re-baked cleanly, 3 h 6 min wall
clock for the two packs run in parallel, zero errors.

| | before | after | |
| --- | ---: | ---: | --- |
| Baked catalog, 43 `*.instances.blend` | 39.13 GiB | 2.59 GiB | 15.1x smaller |
| `sandyclearing.blend` (original) | 219,328,123 | -- | |
| `sandyclearing_rebaked.blend` | 430,101,154 | 122,772,975 | 3.5x smaller |
| `map.glb` | 117,243,848 | 99,062,400 | -15.5% |

The catalog drop is the 8-bit conversion alone, not data loss: every albedo/alpha/normal
was previously a 32-bit float image that packed to a ~12.6 MB float PNG *regardless of
content*, so a 135-image biome carried ~1.7 GB of mostly-empty float before compression.
Datablock counts are identical across the old and new files (verified on `biome_09`:
37 objects / 34 meshes / 135 images / 37 materials), every image is still packed at
1024x1024, and pixel statistics are non-degenerate everywhere.

**Tree leaves are now packed too**, which the section above called out as the gap that
needed per-material packing. Measured on the exported `map.glb`:

| Species / surface | UV bbox before | after | leaf albedo lum before | after |
| --- | --- | --- | ---: | ---: |
| `FP_Tree_B_001` leaves (surface 1) | 0.116 x 0.100 | **0.969 x 0.835** | 0.201 | 0.479 |
| `FP_Tree_B_003` leaves (surface 1) | 0.116 x 0.100 | **0.969 x 0.835** | 0.148 | 0.412 |
| `FP_Tree_B_002` leaves (surface 1) | 1.000 x 0.997 | 1.000 x 0.997 | 0.129 | 0.386 |
| `FP_Tree_B_00*` bark (surface 0) | tiled | tiled (bit-identical) | 0.151-0.182 | unchanged |

`FP_Tree_B_001` and `FP_Tree_B_003` share one leaf material datablock, which is why the
per-datablock commit fixed both at once; `FP_Tree_B_002`'s leaves were already packed. The
tiled bark UVs are bit-identical before and after, confirming the packer still skips any
layout that leaves [0, 1].

The leaf albedo brightened on all three trees, including `FP_Tree_B_002` whose UV layout
and alpha histogram did not change at all. A follow-up probe over the exported Sandy
Clearing GLB textures (mean over opaque texels, sRGB PNG values as stored) pins this down
to a colourspace bug, not the packing:

| species / surface | yesterday (float-EXR catalog) | today (8-bit catalog) |
| --- | --- | --- |
| `FP_Tree_B_002` leaves | (0.097, 0.149, 0.023) | (0.343, 0.420, 0.165) |
| `FP_Grass_072` | (0.176, 0.166, 0.018) | (0.457, 0.443, 0.144) |
| `FP_Fallen_Leaves_B_014` | (0.090, 0.036, 0.017) | (0.331, 0.208, 0.139) |
| `FP_Tree_B_002` bark (already glTF-simple, never baked) | (0.192, 0.144, 0.103) | (0.192, 0.144, 0.103) |

Today's values are, channel by channel, the sRGB transfer function applied to yesterday's
(0.149 -> 0.420, 0.097 -> 0.343, 0.023 -> 0.165): yesterday's PNGs held scene-linear albedo
in an sRGB-interpreted file, so every material the catalog actually baked (the complex
Geoscatter leaf/grass shaders) rendered one gamma too dark since the catalog was first
built, while pass-through simple materials like bark -- never touched by the baker -- were
right all along. The 8-bit path is the correct one: terrain-paint's own probe
(`engine/baking.py`, `_to_byte_image` docstring) shows a 0.6 base colour baking to 0.784
display-encoded, which Godot decodes back to about 0.58 linear -- consistent, not a second
bug. The likely mechanism (not proven) is the old float image being packed as OpenEXR, a
linear container, and re-read as linear-tagged data, so the exporter wrote it out without
encoding it. `FP_Tree_B_001`'s leaf alpha coverage also went 0.00 -> 0.15, i.e. its
canopy card was previously almost entirely transparent. Live frames at Home and at a canopy
zoom confirm the result: the canopy reads as dense, crisp, naturally-lit green instead of
the dark low-contrast mass it was, with ground, rocks and tokens pixel-unchanged.

Two invariants from the section above still hold on the new export: all 60 baked ORM
textures read exactly 1.000 in the occlusion channel, and all 60 scatter mesh surfaces now
carry exactly one UV set (`TEX_UV` present, `TEX_UV2` absent on every one).

`sandyclearing_rebaked.blend` is the file to adopt as the new `sandyclearing.blend`. The
pre-re-bake catalog files are kept alongside the new ones as `*.pre-2026-09-17`.

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

A Sky override survives a preset switch like every other override, by design; the per-row reset and
"Clear overrides" are the way back to the preset's own sky.

## Sun and Shadow

Maps with no lights of their own get a default shadow-casting `DirectionalLight3D`
("LevelSunLight") so tokens and foliage read as grounded in the scene rather than
lit only by flat ambient light. Maps that bring their own lights are left alone.

### Data Model

Sun and shadow configuration is a typed `SunSettings` resource
(`resources/sun_settings.gd`), held at `LevelData.visual_settings.sun`
(`resources/visual_settings.gd`). It replaced the old flat `sun_overrides`
dictionary, which carried only `mode` and `time_of_day` and therefore locked
direction, color, and energy together on a single hand-authored curve.

| Field | Type | Applied to | Notes |
| --- | --- | --- | --- |
| `mode` | `String` | -- | `"auto"` / `"on"` / `"off"`; semantics unchanged |
| `azimuth_degrees` | `float` | `rotation_degrees.y` | |
| `elevation_degrees` | `float` | `-rotation_degrees.x` | |
| `color` | `Color` | `light_color` | |
| `energy` | `float` | `light_energy` | |
| `shadows_enabled` | `bool` | `shadow_enabled` | promoted from hardcoded `true` |
| `softness` | `float` | `light_angular_distance` | sun angular size in degrees; sharp at contact, softens with distance |
| `shadow_darkness` | `float` | `shadow_opacity` | lifts shadows toward ambient without removing them |
| `time_of_day` | `float` | -- | the generator's last input; retained for UI |

- `"auto"` (default): the sun is shown only if the map has no lights of its own.
- `"on"`: the sun is always shown, even if the map has its own lights.
- `"off"`: the sun is never shown, even if the map has no lights.

### Time of Day Is a Generator, Not the Lighting Interface

`utils/default_sun.gd`'s `DefaultSun` used to mutate a light directly via
`configure_directional_light()`. That method is gone, replaced by an inverted
pair:

- `DefaultSun.settings_for_time(hour: float) -> SunSettings` interpolates the
  hand-authored `KEYFRAMES` (dawn 6:00, noon 12:00, dusk 18:00, night
  0:00/24:00) and returns a `SunSettings`. It is a pure generator with no side
  effects.
- `DefaultSun.apply(light: DirectionalLight3D, settings: SunSettings) -> void`
  is a dumb applier: it writes whatever the `SunSettings` says onto the light,
  with no interpolation of its own.

`time_of_day` is a static, per-level setting (not an animated day/night
cycle), and it is no longer the lighting interface itself -- it is one way to
populate one. A level's sun can be hand-aimed (direction, color, energy)
independently of `time_of_day`; changing `time_of_day` afterwards does not
silently overwrite that edit; it only offers to regenerate from the hour (see
"Back to generated" below). Time of day does **not** affect the separate
ambient/`Environment` config — the sun and the ambient/preset system are
independent layers.

### Shadow Tuning

- `softness` (applied to `light_angular_distance`) gives distance-correct
  penumbra: shadows are sharp at the contact point and soften with distance
  from the caster, which is what makes it the artistically meaningful shadow
  dial. `shadow_blur` stays fixed at its tuned value of `2.0` and is **not**
  exposed -- it is a flat uniform filter rather than a physically motivated
  one.
- `shadow_bias` and `shadow_normal_bias` remain hardcoded engine tuning at the
  sun's creation site in `level_environment_manager.gd`, calibrated for this
  project's small object scale (tokens are well under 1 unit tall) to avoid
  "peter-panning" (shadows detaching from small objects). They are correctness
  tuning for this game's geometry, not artistic dials, so they are not exposed
  on `SunSettings` or in the panel.

Shadow cost was measured directly rather than estimated: sun shadows are 41% of the
frame on a dense forest map, but PCF filter quality is only 0.6 ms of it and shortening
`directional_shadow_max_distance` changes nothing at all (every caster is already inside
30 units). Grass no longer casts shadows for this reason. See `docs/PERFORMANCE.md`.

### Key Files

| File | Purpose |
|------|---------|
| `resources/sun_settings.gd` | `SunSettings` -- typed field data, `to_dict()`/`from_dict()`, `from_legacy()` migration, `copy_settings()` |
| `resources/visual_settings.gd` | `VisualSettings` -- wraps `sun`; `to_dict()`/`from_dict()`/`copy_settings()` |
| `utils/default_sun.gd` | `DefaultSun.settings_for_time()` (generator) and `DefaultSun.apply()` (applier) |
| `scenes/states/playing/level_environment_manager.gd` | `apply_sun_settings()` -- re-configures the already-created sun light (created separately by `apply_level_environment()` at load time), resolving `mode` against whether the map brought its own lights and calling `DefaultSun.apply()` |
| `scenes/states/playing/sun_gizmo_tool.gd` | `SunGizmoTool` -- interactive ground-compass aiming tool; see [In-Game Edit Panel](#in-game-edit-panel) |

## In-Game Edit Panel

The `LevelEditPanel` is a slide-out drawer (extends `DrawerContainer`) that appears on the right edge of the screen during gameplay. It provides real-time editing of all level properties with immediate visual feedback.

### Accessing the Panel

1. During gameplay, a rail of six icons (Sun, Sky, Color, Weather, Film, World) appears on the
   right edge of the screen
2. Click a rail item to open the drawer on that pane; clicking the active item closes it
3. All changes are applied to the live viewport immediately

### Panel Sections

The drawer shows one pane at a time from an icon rail (`scenes/states/playing/visual_panes/`),
with Save and Cancel pinned below the `PaneStack` regardless of which pane is open. Each pane owns
the fields it edits and implements `load_state(state)` / `write_state(state)` over a
`LevelVisualState`.

#### Where Each Control Lives

| Rail item | Primary | Advanced |
|---|---|---|
| Sun | time of day (dawn/dusk hints, 14:30 format), Sun tiles Auto/On/Off, Shadows tiles Off/Hard/Soft, aim on map | direction (bearing), height, color, energy, softness, darkness, back to generated |
| Sky | sky tiles with thumbnails (ten, two rows of five), preview strip and caption for the hovered or selected sky, Look picker (grouped, swatches, description), fog on/off + amount | background, ambient, fog color, fog energy, fog height, fog falloff |
| Color | brightness (exposure), contrast, saturation, glow | light energy (formerly "Light scale"), fine brightness, tonemap, white point, glow strength, bloom |
| Weather | rain/snow/fog/wind tiles with Light..Heavy intensity | none |
| Film | Style tiles Off/Subtle/Retro/Heavy (+Custom), pixelate, vignette, grain | colors, dither, color fade |
| World | scale tiles, cell size (m and ft), water tiles, Wind tiles Still/Breeze/Gusty (+Custom) | tree/grass speed and amount |

The Sky and Color panes share an `EnvironmentEditModel` (preset + overrides + map defaults); Sky
writes it into the saved `LevelVisualState`, while Color's `write_state` carries only the light
energy scale. See
[UI_SYSTEMS.md's LevelEditPanel section](UI_SYSTEMS.md#leveleditpanel-in-game-edit-mode) for the
pane class names and signal wiring.

**Sun** (see [Sun and Shadow](#sun-and-shadow) for the underlying schema):

| Control | Type | Range |
| --- | --- | --- |
| Sun | tile row (`TileField`/`TileRow`) | Auto / On / Off |
| Aim Sun | `IconButton` (toggle) | activates `SunGizmoTool` |
| Direction (azimuth) | `PropertyRow`, formatted as a bearing | 0 to 360 |
| Height (elevation) | `PropertyRow` | -15 to 90 |
| Color | `PropertyRow` (color) | |
| Energy | `PropertyRow` | 0 to 4 |
| Shadows | tile row (`TileField`/`TileRow`); Off/Hard/Soft sets the enable flag and a softness bucket in one click | gates the two below |
| Softness | `PropertyRow` | 0 to 5 (degrees of angular distance) |
| Darkness | `PropertyRow` | 0 to 1 |
| Time of Day | `PropertyRow`, formatted "14:30" | 0 to 24, with sunrise/noon/sunset ticks; that it regenerates rather than nudges is conveyed by its tooltip plus the "Back to generated" button |

`SunGizmoTool` draws a compass ring on the ground at the view centre when
"Aim Sun" is active. The mapping is done in **world space on the Y=0 ground
plane**, not in screen pixels: the pointer ray is intersected with the ground
and the offset from the ring centre is measured there. Direction around the
ring sets Azimuth and distance from the centre sets Elevation (centre = 90,
overhead; rim = 0, horizon, with the rim at `RING_RADIUS_WORLD` = 4.5 world
units). The handle sits along the light's ground travel direction
`(-sin A, 0, -cos A)`, so the handle points the way the shadows fall. The ring
is drawn by unprojecting a world circle, so it reads as a ground ellipse under
the fixed isometric camera.

Screen-space would not work here: the camera is yawed 45 degrees and
isometrically foreshortened (its Y axis projects to 0.368 of its X axis on the
ground), so a screen-angle mapping aims the sun 70 to 200 degrees away from the
handle depending on the azimuth. See
`tests/unit/test_sun_gizmo_tool.gd`, which anchors azimuths to absolute world
directions and closes the loop through `DefaultSun.apply()` on a real
`DirectionalLight3D`.

Azimuth and Elevation are two-way synced, so dragging updates the numeric
fields and editing the fields moves the handle. Right mouse button deactivates
the gizmo. It shares its modal-tool contract with `MeasureTool` and the two are
kept mutually exclusive by `GameMap` (see `AGENTS.md`'s "Modal map tools"
note).

Editing any sun property while Mode is "Auto" promotes it to "On" — otherwise
the edit would be a silent no-op on a map that already brings its own lights,
since Auto only shows the default sun when the map has none. When the current
settings diverge from what `DefaultSun.settings_for_time()` would generate for
the current Time of Day, a "Back to generated" button appears, offering to
regenerate direction, color, and energy from that hour.

The Film, Weather, and World panes' fields are listed in the table above; see
[Weather Effects](#weather-effects) for the Weather pane's rain/snow/fog/wind mechanics and the
foliage sway fields' shared network-sync path.

**Actions:**
- **Save** and **Cancel** are pinned below the pane stack (the scene's `ButtonsRow` is moved under
  the `PaneStack` in `_on_ready()`), so they stay visible regardless of which pane is open.
- **Revert to Map Defaults** lives on the Sky pane's header ("restore" icon, tooltip "Revert to the
  map's own lighting") instead of a bottom action button, and is visible only when the map has
  defaults.

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
  ├── sun_changed(settings: SunSettings) ──→ GameplayMenuController ──→ LevelPlayController.apply_sun_settings()
  ├── save_requested(...) ──→ GameplayMenuController._on_edit_save_requested()
  ├── cancel_requested ──→ GameplayMenuController (reverts all changes)
  └── revert_to_map_defaults_requested ──→ GameplayMenuController._on_revert_to_map_defaults()
```

### Cancel / Revert Behavior

`GameplayMenuController` snapshots the live level into one `_original_state: LevelVisualState`
(`resources/level_visual_state.gd`) when the drawer opens — a transient bundle of every
live-editable visual field (light intensity, environment preset + overrides, water style, lo-fi,
weather, foliage, sun, and the grid scale fields). When the panel is closed without saving:

1. `GameplayMenuController` detects the drawer closed without a save
2. `_original_state.apply_to_level_data()` writes the snapshot back onto `LevelData`, then
   `LevelPlayController.apply_visual_state(_original_state)` re-applies it to the live viewport (see
   [Data Storage](#data-storage) and `docs/ARCHITECTURE.md`'s GameplayMenuController section for the
   full apply path, including the client receive path, which goes through the same
   `apply_visual_state()`)
3. Any pending `VisualBroadcastThrottle` batch is dropped and the full snapshot is re-broadcast

### Unsaved Changes and the Close Prompt

`LevelEditPanel.is_dirty()` tracks whether a live edit has been made since the last Save/Cancel/
level-clear; every edit handler calls `_mark_dirty()`, which shows an accent-colored badge on the
drawer's tab and switches its tooltip to "Visuals (unsaved changes)". A dirty drawer will not close
from its tab or from Escape — both route through `request_close()`, which shows a "Discard changes"
/ "Keep editing" confirmation before reverting; confirming discards by emitting `cancel_requested`
(the same path described above). `_enter_edit_mode()` only re-snapshots `_original_state` when the
drawer is clean, so Cancel still returns to the state from before the first unsaved edit even across
a conceal/reopen while dirty.

Save (`_on_edit_save_requested()`) no longer closes the drawer: it persists to disk, advances
`_original_state` to the just-saved values, calls `level_edit_panel.mark_clean()`, and deactivates
the sun-aiming gizmo the same way a close would — tuning can continue immediately afterward. If the
disk write fails, only the error toast is shown: the drawer stays dirty and `_original_state` is
left untouched.

Switching the Sky pane's preset dropdown keeps any environment overrides already set (a toast
reports how many were kept), and each overridden property's `PropertyRow` is tinted and
right-click-resettable individually. See
[UI_SYSTEMS.md's LevelEditPanel section](UI_SYSTEMS.md#leveleditpanel-in-game-edit-mode) for the
override-row details. The Sky pane's "restore" header button is the one action that clears the
preset and every override together.

## Post-Processing (Lo-Fi) Overrides

The game map uses a lo-fi shader for optional retro-style post-processing. These settings are independent of the `Environment` resource.

| Property | Description |
|----------|-------------|
| `pixelation` | Pixel size for retro pixelation effect |
| `saturation` | Color fade — desaturates the lo-fi output (labeled "Color Fade" in the UI to distinguish from environment saturation) |
| `color_levels` | Color quantization step count (labeled "Color Levels" in the UI) |
| `dither_strength` | Ordered-dither strength, breaks up quantization banding |
| `vignette_strength` | Screen-edge darkening strength |
| `vignette_radius` | Vignette falloff radius (a valid `lofi_overrides` key; not exposed as a panel control, so it only changes via `Constants.LOFI_DEFAULTS` or direct edits to a level's data) |
| `grain_intensity` | Film-grain noise intensity |

Lo-fi overrides are stored in `LevelData.lofi` (a typed `LofiSettings`) and applied via `GameMap.apply_lofi_overrides()`.

## Data Storage

### LevelData Resource

```gdscript
# On-disk schema version (see Schema Versions below).
@export var format_version: int = 1

# Map lighting
@export var light_intensity_scale: float = 1.0

# Environment
# Empty string = "use map defaults if available, otherwise PROPERTY_DEFAULTS"
@export var environment_preset: String = ""
@export var environment_overrides: Dictionary = {}

# Post-processing (typed; serialized under "lofi_overrides")
@export var lofi: LofiSettings = LofiSettings.default()

# Weather effects (0.0 = off, 1.0 = max), typed; serialized under "weather_overrides"
# Keys: "rain_intensity", "snow_intensity", "fog_intensity", "wind_intensity"
@export var weather: WeatherSettings = WeatherSettings.default()

# Foliage wind-sway tuning (per-category speed/amplitude for scattered foliage),
# typed; serialized under "foliage_overrides"
# Keys: "tree_sway_speed", "tree_sway_amplitude", "grass_sway_speed", "grass_sway_amplitude"
@export var foliage: FoliageSettings = FoliageSettings.default()

# Typed sun and shadow configuration (see Sun and Shadow above). Replaced the
# flat sun_overrides dictionary in format_version 1.
@export var visual_settings: VisualSettings = VisualSettings.default()
```

`lofi`, `weather`, and `foliage` replaced the old sparse `lofi_overrides`/`weather_overrides`/
`foliage_overrides` `Dictionary` fields with typed `Resource`s (`resources/lofi_settings.gd`,
`resources/weather_settings.gd`, `resources/foliage_settings.gd`), each with a `KEYS` array,
`default()`, a complete `to_dict()` (every key, every time — so a full apply can never leave a
previous level's value behind), a sparse-tolerant `from_dict()` (a level file with only some keys
set still loads, filling the rest with defaults), and `copy_settings()`. The JSON keys these
serialize under (`lofi_overrides`, `weather_overrides`, `foliage_overrides`) are unchanged, `level.json`
below is still accurate, and `FORMAT_VERSION` stays 1 — `LevelData._set()` also absorbs the legacy
dictionary-typed property from older `.tres` files.

**Important:** `environment_preset` defaults to `""` (empty string), not a named preset. This means new levels start with map defaults when available.

### level.json Format

For folder-based levels, settings are stored in `level.json`:

```json
{
  "format_version": 1,
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
    "color_levels": 16.0
  },
  "weather_overrides": {
    "rain_intensity": 0.7,
    "fog_intensity": 0.3
  },
  "foliage_overrides": {
    "tree_sway_speed": 0.8,
    "grass_sway_amplitude": 0.05
  },
  "visual_settings": {
    "sun": {
      "mode": "on",
      "azimuth_degrees": 135.0,
      "elevation_degrees": 48.333,
      "color": "#ffd5b6",
      "energy": 0.9,
      "shadows_enabled": true,
      "softness": 0.0,
      "shadow_darkness": 1.0,
      "time_of_day": 14.0
    }
  }
}
```

Notes:
- Color values are stored as hex strings in JSON and converted back to `Color` objects when loaded
- An empty `environment_preset` (`""`) means "use map defaults"
- Conversion is handled by `EnvironmentPresets.overrides_to_json()` / `overrides_from_json()`

### Schema Versions

`LevelData.format_version` (`FORMAT_VERSION = 1` today) tracks the shape of
the serialized level so `from_dict()` can migrate old data forward instead of
guessing at it:

- **Version 0** means "no `format_version` key" — a level saved before
  versioning existed. Its sun configuration lives in the legacy flat
  `sun_overrides` dictionary (`{"mode": ..., "time_of_day": ...}`), and
  `SunSettings.from_legacy()` migrates it into a `SunSettings`
  appearance-preservingly: direction, color, and energy come from the same
  `DefaultSun.settings_for_time()` lerp the old runtime used, and the three
  newly-exposed shadow fields take the values that were hardcoded before this
  change (`shadows_enabled = true`, `softness = 0.0`,
  `shadow_darkness = 1.0`). This is exact, not approximate — see
  `tests/unit/test_sun_settings_migration.gd`.
- **Version 1** stores `visual_settings` directly (a `VisualSettings`
  dictionary, currently just `{"sun": {...}}`) and ignores any stray
  `sun_overrides` key that might still be present in the raw data.
- Saving a level via either save path writes `format_version: 1`.
- **Legacy `.tres` levels take a second migration route.** `LevelData` has two
  deserializers: `from_dict()` (used by `level.json` folder levels and by
  network payloads) and `ResourceLoader`, which
  `LevelManager.load_level()` still uses for `.tres` levels with `res://` map
  paths. `ResourceLoader` sets `@export` properties directly and never calls
  `from_dict()`, so the migration branch above cannot fire for it. A
  `LevelData._set()` hook absorbs the removed `sun_overrides` property and runs
  `SunSettings.from_legacy()` on it; without that hook the value would be
  discarded as an unknown property and the level would silently come up with
  the 14:00 default sun. Any future removal of a `LevelData` `@export` needs
  the same treatment.
- This is a one-way door: an older build opening a version-1 level finds no
  `sun_overrides` key and falls back to the default sun. Because level
  exports are shared between users who may be on different game versions,
  downgrading to an older build is lossy for sun configuration on levels
  saved by a newer one. This is an accepted, deliberate trade-off, not a bug.

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
6. Sets up `WeatherRenderer` and applies persisted weather overrides

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

## Weather Effects

The weather system adds combinable visual atmosphere effects to maps. All effects are purely cosmetic with no gameplay mechanics.

### Architecture

Weather uses a hybrid rendering approach:

- **Rain, Snow, Wind** — `GPUParticles3D` emitters inside the SubViewport (depth-correct, affected by lo-fi post-process)
- **Fog** — Delta applied to the existing environment fog density (layers on top of whatever the host configured in lighting)

`WeatherRenderer` (`scenes/effects/weather_renderer.gd`) is the core class. It is created as a child of the SubViewport by `GameMap.setup_weather()` during level load, and freed on level unload via `GameMap.clear_weather()`.

### Data Model

Weather state is stored in `LevelData.weather` as a typed `WeatherSettings` resource
(`resources/weather_settings.gd`); its `to_dict()` produces the same flat dictionary of floats as
before, serialized under the `weather_overrides` key:

```gdscript
{
    "rain_intensity": 0.0,   # 0.0 (off) to 1.0 (heavy)
    "snow_intensity": 0.0,
    "fog_intensity": 0.0,
    "wind_intensity": 0.0,
}
```

All values default to 0.0. An empty dictionary means no weather. Multiple effects can be active simultaneously.

### UI Controls

The Weather pane (`scenes/states/playing/visual_panes/weather_pane.gd`) shows four toggle tiles (rain, snow, fog, wind); turning a tile on reveals a `PropertyRow` intensity slider (0.0-1.0, step 0.05) for it and remembers the value for the session when turned back off. Changes apply in real-time. Save/Cancel handles weather as one field of the `LevelVisualState` snapshot alongside the other visual fields (see [Cancel / Revert Behavior](#cancel--revert-behavior)).

### Network Sync

Weather piggybacks on the existing `broadcast_visual_settings` / `visual_settings_received` path with a `"weather_overrides"` key. No new RPCs or signals. Included in full state sync for late joiners (part of `LevelData.to_dict()`).

Foliage wind-sway tuning (`LevelData.foliage`, see [Data Storage](#data-storage)) is broadcast the same way, via a `"foliage_overrides"` key on the same `broadcast_visual_settings` / `visual_settings_received` path — no new RPCs or signals for it either.

Sun and shadow settings (see [Sun and Shadow](#sun-and-shadow)) also piggyback on this path, via a flat `"sun_settings"` key carrying `SunSettings.to_dict()`. The late-joiner mirror is the one place this key is *not* flat: `NetworkManager._patch_current_level_dict()` nests it under `visual_settings.sun` and stamps `format_version`, because `_current_level_dict` is in `LevelData.to_dict()` shape and a top-level `sun_settings` key would be silently ignored by `LevelData.from_dict()` -- a client joining after a live sun edit would otherwise see the default sun instead of the host's. See `autoloads/network_manager.gd`'s `broadcast_visual_settings()` and `_patch_current_level_dict()`.

While the drawer is open, live edits are applied to the local viewport immediately but `VisualBroadcastThrottle` merges successive `broadcast_visual_settings` calls into one RPC every 100 ms rather than sending one per slider tick; Save and Cancel discard any pending merged batch first and send their own full, authoritative snapshot instead.

### Particle Details

| Effect | Particles | Mesh | Key Properties |
|--------|-----------|------|----------------|
| Rain | 1000 | BoxMesh (thin streak) | Fast fall (12-16 vel), `particle_flag_align_y`, collision via `GPUParticlesCollisionHeightField3D` |
| Snow | 600 | SphereMesh | Slow drift (1-2 vel), turbulence enabled for natural lateral movement |
| Wind | 200 | BoxMesh (elongated wisp) | Diagonal travel, `particle_flag_align_y`, medium speed (6-10 vel) |
| Fog | N/A | N/A | Adds up to 0.05 to base `fog_density` at max intensity |

### Camera Tracking

`WeatherRenderer._process()` positions emitters above the camera holder and scales emission box extents proportionally with `camera.size`. Only runs when at least one emitter is active (checked via `emitter.emitting`).

### Transitions

All intensity changes animate smoothly over 1 second via tweens on `amount_ratio`. Fog density is also tweened. Setting intensity to 0 stops the emitter after the tween completes.

### Lifecycle

- **Level load**: `LevelPlayController._finalize_map_loading()` calls `game_map.setup_weather(_environment_manager)` after environment is applied
- **Level unload**: `LevelPlayController.clear_level_map()` calls `game_map.clear_weather()` which frees the renderer via `queue_free()`
- **Re-creation**: A fresh `WeatherRenderer` is created on each level load (no stale state across levels)

### Key Files

| File | Purpose |
|------|---------|
| `scenes/effects/weather_renderer.gd` | Core renderer class (emitters, fog, camera tracking, transitions) |
| `resources/level_data.gd` | `weather` field (typed `WeatherSettings`; serialization, duplication) |
| `scenes/states/playing/level_edit_panel.gd` | Weather UI section (sliders, signals) |
| `scenes/states/playing/gameplay_menu_controller.gd` | Signal routing, snapshot/revert, network broadcast |
| `scenes/states/playing/level_play_controller.gd` | Lifecycle (setup, network sync, teardown) |
| `scenes/states/playing/game_map.gd` | `setup_weather()`, `apply_weather_overrides()`, `clear_weather()` |
| `utils/wind_foliage.gd` | `PRESETS`, `get_effective_preset()` — foliage wind-sway classification and per-category preset merging |
| `utils/glb_utils.gd` | Bakes `foliage_overrides` into wind `ShaderMaterial`s at map-load time (`process_scatter_instances()`) |
| `resources/level_data.gd` | `foliage` field (typed `FoliageSettings`; serialization, duplication) |
| `scenes/states/playing/level_environment_manager.gd` | `store_wind_materials()`, `apply_foliage_overrides()` — live re-tuning of already-loaded materials |
| `scenes/states/playing/level_play_controller.gd` | `apply_foliage_overrides()` — delegates to `LevelEnvironmentManager`, network sync |

### Tuning Parameters

All particle parameters (counts, velocities, scales, colors, alpha curves) are defined programmatically in `WeatherRenderer._create_*_emitter()` methods. To tune:

1. Adjust constants in the `_create_rain_emitter()`, `_create_snow_emitter()`, or `_create_wind_emitter()` methods
2. For fog, change the density multiplier (currently `0.05`) in `_transition_fog()`
3. Transition speed is controlled by `TRANSITION_DURATION` (currently 1.0 seconds)

### Future Enhancements

- **Snow buildup**: Shader on map geometry that blends snow texture onto upward-facing surfaces, with coverage driven by snow intensity and elapsed time

## Best Practices

1. **For Blender exports**: Use "Unitless" lighting mode when possible. If using "Standard" mode, expect to use `light_intensity_scale` values around 0.001–0.01. Maps exported via the companion `terrain-paint` addon's Export glTF operator always use Unitless mode (`export_import_convert_lighting_mode='COMPAT'`, hardcoded, not user-configurable) specifically so `light_intensity_scale`'s default of `1.0` works correctly with no manual tuning — this only matters if you're exporting from Blender by some other means (e.g. File > Export directly, bypassing terrain-paint).

2. **Start with map defaults**: If the map has embedded lighting, start with "Map Defaults" and use overrides to tweak from there.

3. **Use the edit panel for real-time feedback**: All changes in the edit panel apply immediately to the live viewport — no need to save and reload.

4. **Consider the layering model**: Only override what you need. Overrides are applied on top of the preset/map defaults, so you can change presets without losing your tweaks.

5. **Map defaults are not saved**: They are derived from the map file at load time. If you update your map in Blender, the defaults will reflect the new lighting.

6. **Distinguish saturation controls**: The environment "Saturation" (in Lighting & Environment) adjusts Godot's `Environment.adjustment_saturation`. The lo-fi "Color Fade" (in Post-Processing Effects) is a shader-based desaturation effect.

7. **Consider player hardware**: Heavy post-processing effects (SSAO, SSR, SDFGI) may impact performance on lower-end machines.
