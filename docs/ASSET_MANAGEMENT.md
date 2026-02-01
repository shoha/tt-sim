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

| Autoload           | Purpose                                         |
| ------------------ | ----------------------------------------------- |
| `AssetPackManager` | Pack discovery, asset resolution, pack registry |
| `AssetDownloader`  | HTTP downloads with queue and caching           |
| `AssetStreamer`    | P2P asset streaming for multiplayer             |

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

Packs are automatically discovered on startup by scanning `res://user_assets/` for folders containing `manifest.json`.

```gdscript
# Manually refresh packs
AssetPackManager.reload_packs()

# Get all available packs
var packs = AssetPackManager.get_all_packs()
```

---

## Loading Assets

### Synchronous Loading

For assets known to be available locally:

```gdscript
var model = AssetPackManager.load_model("my_pack", "dragon", "default")
if model:
    add_child(model)
```

### Asynchronous Loading

For assets that may need downloading:

```gdscript
# Using BoardTokenFactory
var token = await BoardTokenFactory.create_from_asset_async(
    "my_pack", "dragon", "default"
)
add_child(token)
```

### Loading Icons

```gdscript
var icon = AssetPackManager.load_icon("my_pack", "dragon", "default")
if icon:
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

# Or load from remote manifest URL
await AssetPackManager.load_remote_pack_from_url(
    "https://example.com/packs/my_pack/manifest.json"
)
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

### Cache Location

Downloaded assets are cached at:

```
user://asset_cache/
├── {pack_id}/
│   ├── {asset_id}/
│   │   ├── {variant_id}.glb
│   │   └── ...
```

### Cache Behavior

- **Persistent** - Survives game restarts
- **Automatic** - No manual management needed
- **Per-Variant** - Each variant cached separately

### Checking Cache

```gdscript
# Check if asset is cached
var cached_path = AssetDownloader.get_cached_path(pack_id, asset_id, variant_id)
if cached_path:
    # Asset is available locally
    pass
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
func get_all_packs() -> Array[AssetPack]
func get_pack(pack_id: String) -> AssetPack
func reload_packs() -> void
```

#### Asset Access

```gdscript
func get_asset(pack_id: String, asset_id: String) -> AssetEntry
func get_variant(pack_id: String, asset_id: String, variant_id: String) -> AssetVariant
```

#### Loading

```gdscript
func load_model(pack_id: String, asset_id: String, variant_id: String) -> Node3D
func load_icon(pack_id: String, asset_id: String, variant_id: String) -> Texture2D
```

#### Remote Packs

```gdscript
func register_remote_pack(pack: AssetPack) -> void
func load_remote_pack_from_url(manifest_url: String) -> AssetPack
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

#### Token Creation

```gdscript
static func create_from_asset(pack_id: String, asset_id: String,
                              variant_id: String) -> BoardToken
static func create_from_asset_async(pack_id: String, asset_id: String,
                                    variant_id: String) -> BoardToken
```

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
