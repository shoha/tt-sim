# Asset Management Guide

This document covers the asset pack system, including loading, caching, remote downloads, multiplayer synchronization, and creating custom asset packs.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Asset Packs](#asset-packs)
- [Loading Assets](#loading-assets)
- [Remote Assets](#remote-assets)
- [Multiplayer Synchronization](#multiplayer-synchronization)
- [Caching System](#caching-system)
- [Creating Asset Packs](#creating-asset-packs)
- [API Reference](#api-reference)

---

## Overview

The asset management system provides:

- **Asset Pack Discovery** - Automatic scanning for local and remote packs
- **On-Demand Loading** - Assets loaded when needed
- **HTTP Downloads** - Remote assets downloaded from URLs
- **P2P Streaming** - Fallback streaming from host when URLs unavailable
- **Placeholder System** - Visual placeholders while assets download
- **Persistent Caching** - Downloaded assets cached for reuse

### Core Components

| Autoload            | Purpose                                              |
| ------------------- | ---------------------------------------------------- |
| `AssetPackManager`  | Pack discovery, asset resolution, model cache        |
| `AssetResolver`     | Unified resolution pipeline (local → cache → remote) |
| `AssetCacheManager` | Disk cache management for downloaded files           |
| `AssetDownloader`   | HTTP downloads with queue                            |
| `AssetStreamer`     | P2P asset streaming for multiplayer                  |

---

## Architecture

### Asset Hierarchy

```
AssetPackManager
├── AssetPack (pack_id: "trainers")
│   ├── AssetEntry (asset_id: "pikachu")
│   │   ├── AssetVariant (variant_id: "default")
│   │   │   ├── model_path: "models/pikachu.glb"
│   │   │   └── icon_path: "icons/pikachu.png"
│   │   └── AssetVariant (variant_id: "shiny")
│   │       ├── model_path: "models/pikachu_shiny.glb"
│   │       └── icon_path: "icons/pikachu_shiny.png"
│   └── AssetEntry (asset_id: "charizard")
│       └── ...
└── AssetPack (pack_id: "custom_minis")
    └── ...
```

### Asset Resolution Flow

1. Check if asset is local (file exists in pack folder)
2. Check memory cache (already loaded this session)
3. Check disk cache (`user://asset_cache/`)
4. Download from URL if `base_url` or `model_url` available
5. Request from host via P2P streaming (multiplayer fallback)

---

## Asset Packs

### Pack Structure

```
user_assets/
├── my_pack/
│   ├── manifest.json       # Required: Pack metadata
│   ├── models/             # 3D model files (.glb)
│   │   ├── dragon.glb
│   │   └── knight.glb
│   └── icons/              # Icon images (.png)
│       ├── dragon.png
│       └── knight.png
```

### Manifest Format

```json
{
  "pack_id": "my_pack",
  "display_name": "My Custom Minis",
  "version": "1.0",
  "base_url": "https://example.com/assets/",
  "assets": {
    "dragon": {
      "display_name": "Dragon",
      "variants": {
        "default": {
          "model": "dragon.glb",
          "icon": "dragon.png"
        },
        "fire": {
          "model": "dragon_fire.glb",
          "icon": "dragon_fire.png"
        }
      }
    }
  }
}
```

### Pack Discovery

Packs are automatically discovered on startup from two sources:

1. **Local packs**: `res://user_assets/` - folders containing `manifest.json` (in project)
2. **Installed packs**: `user://user_assets/` - packs downloaded via the manifest URL in the asset browser (same structure: manifest.json, models/, icons/)

```gdscript
# Manually refresh packs
AssetPackManager.reload_packs()

# Get all available packs
var packs = AssetPackManager.get_packs()
```

---

## Loading Assets

### Getting Model Instances

Use `AssetPackManager.get_model_instance()` for general model loading with automatic caching:

```gdscript
# Async loading (recommended - non-blocking, uses cache)
var model = await AssetPackManager.get_model_instance("my_pack", "dragon", "default")
if model:
    add_child(model)

# Sync loading (blocks if not cached - use sparingly)
var model = AssetPackManager.get_model_instance_sync("my_pack", "dragon", "default")
```

### Creating Tokens

For game tokens that need physics and interactions:

```gdscript
# Async (handles downloading, shows placeholder if needed)
var token = await BoardTokenFactory.create_from_asset_async(
    "my_pack", "dragon", "default"
)
add_child(token)

# Sync (asset must already be available)
var token = BoardTokenFactory.create_from_asset("my_pack", "dragon", "default")
```

### Batch Preloading

For best performance when loading many tokens, preload models first:

```gdscript
# Prepare asset list
var assets_to_load: Array[Dictionary] = []
for placement in level_data.token_placements:
    assets_to_load.append({
        "pack_id": placement.pack_id,
        "asset_id": placement.asset_id,
        "variant_id": placement.variant_id
    })

# Preload with progress callback
var loaded = await AssetPackManager.preload_models(
    assets_to_load,
    func(current: int, total: int):
        print("Loading models: %d/%d" % [current, total])
)

# Now create tokens (fast - models are cached)
for placement in level_data.token_placements:
    var token = BoardTokenFactory.create_from_placement(placement)
    add_child(token)
```

### Loading Icons

```gdscript
var icon_path = AssetPackManager.resolve_icon_path("my_pack", "dragon", "default")
if icon_path:
    var icon = load(icon_path) as Texture2D
    texture_rect.texture = icon
```

---

## Remote Assets

### URL-Based Packs

Remote packs specify a `base_url` for downloading assets:

```json
{
  "pack_id": "remote_pack",
  "display_name": "Remote Minis",
  "base_url": "https://cdn.example.com/assets/remote_pack/",
  "assets": {
    "goblin": {
      "display_name": "Goblin",
      "variants": {
        "default": {
          "model": "models/goblin.glb",
          "icon": "icons/goblin.png"
        }
      }
    }
  }
}
```

The full URL is constructed as: `base_url + model_path`
Example: `https://cdn.example.com/assets/remote_pack/models/goblin.glb`

### Per-Variant URLs

Override URLs for specific variants:

```json
{
  "variants": {
    "default": {
      "model": "goblin.glb",
      "model_url": "https://other-cdn.com/goblin.glb",
      "icon_url": "https://other-cdn.com/goblin.png"
    }
  }
}
```

### Registering Remote Packs

```gdscript
# Register a remote pack programmatically
var pack = AssetPack.new()
pack.pack_id = "remote_pack"
pack.display_name = "Remote Pack"
pack.base_url = "https://cdn.example.com/packs/remote/"
AssetPackManager.register_remote_pack(pack)

# Or load from remote manifest URL (metadata only, assets download on-demand)
AssetPackManager.load_remote_pack_from_url(
    "https://example.com/packs/my_pack/manifest.json"
)

# Or download entire pack from manifest URL (all models and icons)
AssetPackManager.download_asset_pack_from_url(
    "https://example.com/packs/my_pack/manifest.json"
)
# Connect to pack_download_progress and pack_download_completed for progress
# Downloaded packs are installed to user://user_assets/{pack_id}/ (manifest, models/, icons/)
# so the pack is available after game restart
```

---

## Multiplayer Synchronization

### How Assets Sync

1. **Host creates token** with `pack_id`, `asset_id`, `variant_id`
2. **Token state sent to clients** via `NetworkStateSync`
3. **Clients receive state** and create tokens from asset references
4. **Asset resolution** follows normal flow (local → cache → download → P2P)

### Placeholder Tokens

When assets aren't immediately available, placeholder tokens are shown:

```gdscript
# Automatic placeholder handling
var token = await BoardTokenFactory.create_from_asset_async(
    pack_id, asset_id, variant_id
)
# Returns immediately with placeholder if asset downloading
# Placeholder upgrades to real model when download completes
```

Placeholders display:

- Pulsing/spinning cube animation
- Visual indication that content is loading

### P2P Streaming Fallback

If URL download fails, clients request assets from the host:

```gdscript
# Automatic - handled by AssetStreamer
# Host reads local file and streams to client in chunks
```

**P2P Features:**

- 32KB chunk size
- ZSTD compression
- Max 2 concurrent transfers
- Async chunk sending (non-blocking)

### Download Priority

Tokens set download priority based on visibility:

| Token State | Priority | Note             |
| ----------- | -------- | ---------------- |
| Visible     | 50       | Downloaded first |
| Hidden      | 100      | Lower priority   |

---

## Caching System

The asset system uses a **two-level caching strategy**:

1. **Disk Cache** - Raw downloaded files persisted to disk
2. **Memory Cache** - Loaded and processed model instances for fast cloning

### Disk Cache

Downloaded assets are cached at:

```
user://asset_cache/
├── {pack_id}/
│   ├── {asset_id}/
│   │   ├── {variant_id}.glb
│   │   └── ...
```

**Disk Cache Behavior:**

- **Persistent** - Survives game restarts
- **Automatic** - No manual management needed
- **Per-Variant** - Each variant cached separately

### Memory Model Cache

Loaded model scenes are cached in memory for fast instantiation:

```
AssetPackManager._model_cache
├── "user://asset_cache/pokemon/pikachu/default.glb" -> Node3D template
├── "res://user_assets/trainers/models/trainer.glb" -> PackedScene
└── ...
```

**Memory Cache Behavior:**

- **Session-scoped** - Cleared when switching levels or on game exit
- **De-duplicated** - Each unique model loaded only once
- **Fast cloning** - New instances created via `duplicate()` or `instantiate()`
- **Async loading** - GLB files loaded on background thread

**Why Two Caches?**

| Cache Type   | Purpose              | Speed           | Persistence  |
| ------------ | -------------------- | --------------- | ------------ |
| Disk Cache   | Avoid re-downloading | Slow (file I/O) | Persistent   |
| Memory Cache | Avoid re-parsing GLB | Fast (clone)    | Session only |

Loading a GLB file involves:

1. Reading file from disk
2. Parsing GLTF structure
3. Generating Godot nodes and materials
4. Processing collision meshes

The memory cache skips steps 1-4 by keeping the processed result in memory.

### Checking Cache

```gdscript
# Check if asset file is cached on disk
var cached_path = AssetDownloader.get_cached_path(pack_id, asset_id, variant_id)
if cached_path:
    # File is available locally
    pass

# Get model instance (uses memory cache automatically)
var model = await AssetPackManager.get_model_instance(pack_id, asset_id, variant_id)
```

### Clearing Caches

```gdscript
# Clear memory cache (call when switching levels to free memory)
AssetPackManager.clear_model_cache()

# Disk cache is persistent - no API to clear (managed by OS/user)
```

---

## Creating Asset Packs

### Model Requirements

- **Format:** glTF Binary (`.glb`)
- **Structure:** `Armature` → `Skeleton3D` → `Mesh`
- **Animations:** Optional, via `AnimationPlayer`
- **Collision:** Auto-generated if not provided

### Icon Requirements

- **Format:** PNG (`.png`)
- **Size:** 64x64 or 128x128 recommended
- **Background:** Transparent works best

### Step-by-Step Guide

1. **Create folder structure:**

```
user_assets/my_pack/
├── manifest.json
├── models/
└── icons/
```

2. **Create manifest.json:**

```json
{
  "pack_id": "my_pack",
  "display_name": "My Pack",
  "version": "1.0",
  "assets": {
    "warrior": {
      "display_name": "Warrior",
      "variants": {
        "default": {
          "model": "warrior.glb",
          "icon": "warrior.png"
        }
      }
    }
  }
}
```

3. **Add model files** to `models/`

4. **Add icon files** to `icons/`

5. **Restart game** to load pack

### Adding Variants

Multiple variants allow alternate appearances:

```json
{
  "assets": {
    "dragon": {
      "display_name": "Dragon",
      "variants": {
        "default": {
          "model": "dragon.glb",
          "icon": "dragon.png"
        },
        "fire": {
          "model": "dragon_fire.glb",
          "icon": "dragon_fire.png"
        },
        "ice": {
          "model": "dragon_ice.glb",
          "icon": "dragon_ice.png"
        }
      }
    }
  }
}
```

---

## API Reference

### AssetPackManager

#### Pack Discovery

```gdscript
func get_packs() -> Array                    # Get all loaded packs
func get_pack(pack_id: String) -> AssetPack  # Get pack by ID
func has_pack(pack_id: String) -> bool       # Check if pack exists
func reload_packs() -> void                  # Reload all packs
```

#### Asset Access

```gdscript
func get_asset(pack_id: String, asset_id: String) -> AssetEntry
func get_assets(pack_id: String) -> Array    # Get all assets in a pack
func get_all_assets() -> Array[Dictionary]   # Get all assets across all packs
func get_variants(pack_id: String, asset_id: String) -> Array[String]
func get_asset_display_name(pack_id: String, asset_id: String) -> String
```

#### Path Resolution

```gdscript
# Resolve model path (checks local, cache, triggers download if needed)
func resolve_model_path(pack_id: String, asset_id: String,
                        variant_id: String = "default", priority: int = 100) -> String

# Resolve icon path
func resolve_icon_path(pack_id: String, asset_id: String,
                       variant_id: String = "default", priority: int = 100) -> String

# Check availability
func is_asset_available(pack_id: String, asset_id: String, variant_id: String = "default") -> bool
func needs_download(pack_id: String, asset_id: String, variant_id: String = "default") -> bool
```

#### Model Instance API (with Memory Caching)

```gdscript
# Get a model instance (async, uses memory cache)
# Returns a new Node3D instance, or null if asset needs downloading
func get_model_instance(pack_id: String, asset_id: String,
                        variant_id: String = "default",
                        create_static_bodies: bool = false) -> Node3D

# Get a model instance from a resolved path (async)
func get_model_instance_from_path(path: String,
                                  create_static_bodies: bool = false) -> Node3D

# Synchronous versions (blocks if not cached - prefer async)
func get_model_instance_sync(pack_id: String, asset_id: String,
                             variant_id: String = "default",
                             create_static_bodies: bool = false) -> Node3D
func get_model_instance_from_path_sync(path: String,
                                       create_static_bodies: bool = false) -> Node3D

# Preload multiple models (for batch loading before spawning)
# assets: Array of {pack_id, asset_id, variant_id} dictionaries
func preload_models(assets: Array,
                    progress_callback: Callable = Callable(),
                    create_static_bodies: bool = false) -> int

# Clear the memory cache (call when switching levels)
func clear_model_cache() -> void
```

**Model Instance Parameters:**

| Parameter              | Purpose                                                                                                                     |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `create_static_bodies` | If `true`, generates `StaticBody3D` for collision meshes. Use `true` for maps, `false` for tokens (they use `RigidBody3D`). |

#### Remote Packs

```gdscript
func register_remote_pack(manifest: Dictionary) -> bool
func load_remote_pack_from_url(manifest_url: String) -> void
func download_asset_pack_from_url(manifest_url: String) -> bool  # Downloads all assets in pack
```

#### Signals

```gdscript
signal packs_loaded()
signal asset_available(pack_id: String, asset_id: String, variant_id: String, local_path: String)
signal asset_download_failed(pack_id: String, asset_id: String, variant_id: String, error: String)
```

### AssetDownloader

#### Download Management

```gdscript
func download_asset(pack_id: String, asset_id: String, variant_id: String,
                    url: String, priority: int = 100) -> void
func is_downloading(pack_id: String, asset_id: String, variant_id: String) -> bool
func get_download_progress(pack_id: String, asset_id: String, variant_id: String) -> float
```

#### Cache Access

```gdscript
func get_cached_path(pack_id: String, asset_id: String, variant_id: String) -> String
func is_cached(pack_id: String, asset_id: String, variant_id: String) -> bool
```

#### Signals

```gdscript
signal download_started(pack_id, asset_id, variant_id)
signal download_progress(pack_id, asset_id, variant_id, progress)
signal download_completed(pack_id, asset_id, variant_id, path)
signal download_failed(pack_id, asset_id, variant_id, error)
```

### AssetStreamer

#### P2P Streaming

```gdscript
func request_asset(pack_id: String, asset_id: String, variant_id: String) -> void
func is_streaming(pack_id: String, asset_id: String, variant_id: String) -> bool
```

#### Configuration

```gdscript
var enabled: bool  # Enable/disable P2P streaming
```

#### Signals

```gdscript
signal stream_started(pack_id, asset_id, variant_id)
signal stream_progress(pack_id, asset_id, variant_id, progress)
signal stream_completed(pack_id, asset_id, variant_id, path)
signal stream_failed(pack_id, asset_id, variant_id, error)
```

### BoardTokenFactory

Factory for creating `BoardToken` instances from asset packs. Uses `AssetPackManager` for model loading and caching.

#### Token Creation

```gdscript
# Create from model scene directly
static func create_from_scene(model_scene: Node3D, config: Resource = null) -> BoardToken

# Create from asset pack (synchronous - asset must be available)
static func create_from_asset(pack_id: String, asset_id: String,
                              variant_id: String = "default",
                              config: Resource = null) -> BoardToken

# Create from asset pack (async - handles downloading, returns placeholder if needed)
static func create_from_asset_async(pack_id: String, asset_id: String,
                                    variant_id: String = "default",
                                    config: Resource = null) -> BoardToken

# Create from TokenPlacement resource (for level loading)
static func create_from_placement(placement: TokenPlacement) -> BoardToken
static func create_from_placement_async(placement: TokenPlacement) -> BoardToken
```

**Note:** Model caching is handled by `AssetPackManager`. Call `AssetPackManager.clear_model_cache()` when switching levels to free memory.

---

## UI Components

### Asset Browser

The in-game asset browser (`AssetBrowser`) provides:

- Tabbed interface for each pack
- Search/filter by name
- Variant selection
- Drag-and-drop token creation

### Download Queue

The download queue widget (`DownloadQueue`) shows:

- Active downloads with progress bars
- Download queue length
- Error indicators

---

## Settings

Asset management settings in `user://settings.cfg`:

| Setting                    | Default | Description                       |
| -------------------------- | ------- | --------------------------------- |
| `asset_streaming_enabled`  | `true`  | Enable P2P asset streaming        |
| `max_concurrent_downloads` | `3`     | Maximum parallel HTTP downloads   |
| `download_timeout`         | `60`    | Seconds before download times out |
