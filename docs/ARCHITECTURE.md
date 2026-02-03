# Project Architecture

This document provides an overview of the project's architecture, core systems, and how they interact.

## Table of Contents

- [Overview](#overview)
- [Scene Hierarchy](#scene-hierarchy)
- [Autoloads (Singletons)](#autoloads-singletons)
- [State Management](#state-management)
- [Networking](#networking)
- [Asset Management](#asset-management)
- [UI Architecture](#ui-architecture)
- [Level System](#level-system)
- [Token System](#token-system)

---

## Overview

The project follows a hierarchical scene structure with centralized state management. Key architectural decisions:

- **State Stack Pattern** - Root manages application state with push/pop semantics
- **Autoload Services** - Global singletons for cross-cutting concerns
- **Dynamic Scene Loading** - Scenes loaded/unloaded based on state
- **Signal-based Communication** - Loose coupling between components

---

## Scene Hierarchy

```
Root (Node3D)
├── LevelPlayController (Node) - manages active level gameplay
├── AppMenu (CanvasLayer) - always-visible UI buttons
│   └── AppMenu (Control) - Level Editor button, etc.
│
├── [Dynamic] TitleScreen (CanvasLayer) - shown in TITLE_SCREEN state
│
├── [Dynamic] GameMap (Node3D) - shown in PLAYING state
│   ├── Map (instantiated from level data)
│   ├── Tokens (BoardToken instances)
│   ├── Camera3D
│   └── GameplayMenu (CanvasLayer)
│       └── Pokemon list, context menus
│
└── [Dynamic] PauseOverlay (CanvasLayer) - shown in PAUSED state
```

### Dynamic vs Static Scenes

| Scene        | Lifecycle          | Managed By                   |
| ------------ | ------------------ | ---------------------------- |
| AppMenu      | Always present     | Root.\_setup_app_menu()      |
| TitleScreen  | TITLE_SCREEN state | Root.\_enter_state()         |
| GameMap      | PLAYING state      | Root.\_enter_playing_state() |
| PauseOverlay | PAUSED state       | Root.\_enter_paused_state()  |

---

## Autoloads (Singletons)

Autoloads are registered in `project.godot` and available globally.

### Core Autoloads

| Autoload       | File                         | Purpose                            |
| -------------- | ---------------------------- | ---------------------------------- |
| `Paths`        | `autoloads/paths.gd`         | Path constants and utilities       |
| `NodeUtils`    | `autoloads/node_utils.gd`    | Node manipulation utilities        |
| `LevelManager` | `autoloads/level_manager.gd` | Level save/load operations         |
| `UIManager`    | `autoloads/ui_manager.gd`    | UI systems (dialogs, toasts, etc.) |
| `AudioManager` | `autoloads/audio_manager.gd` | Audio playback and bus control     |

### Networking Autoloads

| Autoload           | File                              | Purpose                           |
| ------------------ | --------------------------------- | --------------------------------- |
| `NetworkManager`   | `autoloads/network_manager.gd`    | Connection lifecycle, RPC routing |
| `NetworkStateSync` | `autoloads/network_state_sync.gd` | State broadcasting and batching   |
| `GameState`        | `autoloads/game_state.gd`         | Authoritative game state storage  |
| `Noray`            | `addons/netfox.noray/noray.gd`    | NAT punchthrough client           |

### Asset Management Autoloads

| Autoload            | File                               | Purpose                                    |
| ------------------- | ---------------------------------- | ------------------------------------------ |
| `AssetPackManager`  | `autoloads/asset_pack_manager.gd`  | Pack discovery, asset loading, model cache |
| `AssetResolver`     | `autoloads/asset_resolver.gd`      | Unified asset resolution pipeline          |
| `AssetCacheManager` | `autoloads/asset_cache_manager.gd` | Disk cache management                      |
| `AssetDownloader`   | `autoloads/asset_downloader.gd`    | HTTP downloads with queue                  |
| `AssetStreamer`     | `autoloads/asset_streamer.gd`      | P2P asset streaming                        |

### UIManager Responsibilities

- Modal and overlay stack management
- ESC key handling prioritization
- Confirmation dialogs
- Toast notifications
- Scene transitions
- Loading screens
- Input hints
- Settings menu

### LevelManager Responsibilities

- Level file I/O (save/load)
- Async level loading (non-blocking for UI responsiveness)
- Level discovery (listing available levels)
- Level data validation

### NetworkManager Responsibilities

- Host/join game connections via Noray
- Player tracking and role management
- RPC routing for state synchronization
- Late joiner handling

See [NETWORKING.md](NETWORKING.md) for detailed documentation.

### AssetPackManager Responsibilities

- Asset pack discovery and registration
- Asset path resolution (local → disk cache → download → P2P)
- **Model instance loading with memory caching**
- Remote pack support
- Batch model preloading for level loading

**Model Instance API:**

The `AssetPackManager` provides a unified API for getting model instances with automatic caching:

```gdscript
# Get a model instance (async, uses cache)
var model = await AssetPackManager.get_model_instance(pack_id, asset_id, variant_id)

# Preload multiple models before batch spawning
await AssetPackManager.preload_models(assets_array, progress_callback)

# Clear cache when switching levels
AssetPackManager.clear_model_cache()
```

This centralizes model loading logic that was previously duplicated in `BoardTokenFactory` and `LevelPlayController`.

See [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md) for detailed documentation.

---

## State Management

### Root State Machine

The `Root` node implements a state stack for flexible state management.

```gdscript
enum State {
    TITLE_SCREEN,  # Main menu
    LOBBY,         # Multiplayer lobby (host or client)
    PLAYING,       # Active gameplay
    PAUSED,        # Game paused (overlay state)
}
```

### State Transitions

```gdscript
# Base state change (clears stack)
change_state(State.PLAYING)

# Overlay state (pushes on top)
push_state(State.PAUSED)

# Return to previous state
pop_state()
```

### State Entry/Exit Hooks

Each state has entry and exit handlers:

```gdscript
func _enter_state(state: State) -> void:
    match state:
        State.TITLE_SCREEN:
            # Instantiate title screen
        State.PLAYING:
            # Instantiate GameMap, load level
        State.PAUSED:
            # Pause tree, show pause menu

func _exit_state(state: State) -> void:
    match state:
        State.TITLE_SCREEN:
            # Free title screen
        State.PLAYING:
            # Clear level, free GameMap
        State.PAUSED:
            # Resume tree, hide pause menu
```

### State Signal

```gdscript
signal state_changed(old_state: State, new_state: State)
```

---

## Networking

The project uses a **host-authoritative architecture** for multiplayer.

### Key Concepts

- **Host** acts as the server, clients connect via room codes
- **Noray** provides NAT punchthrough for peer-to-peer connections
- **GameState** is the single source of truth (host-authoritative)
- **NetworkStateSync** handles rate-limited state broadcasting

### Connection Flow

```
Host Flow:
1. Connect to Noray → Get room code (OID)
2. Start ENet server → Wait for clients
3. Clients connect → Send level data and game state

Client Flow:
1. Enter room code → Connect to Noray
2. NAT punchthrough → Connect to host
3. Receive level data → Receive game state → Play
```

### State Synchronization

- **Transform updates**: Unreliable, rate-limited (20/sec), batched
- **Property updates**: Reliable, immediate
- **Full state sync**: Sent to late joiners

See [NETWORKING.md](NETWORKING.md) for complete documentation.

---

## Asset Management

The asset system supports local and remote asset packs with multiplayer synchronization.

### Key Concepts

- **Asset Packs** contain models and icons with manifest.json
- **Variants** allow multiple versions of an asset (e.g., shiny, fire)
- **Remote packs** specify `base_url` for HTTP downloads
- **P2P streaming** provides fallback when URLs unavailable
- **Placeholders** shown while assets download
- **Two-level caching** - disk cache for downloads, memory cache for loaded models

### Asset Resolution

```
1. Check local file (res://user_assets/)
2. Check disk cache (user://asset_cache/)
3. Download from URL (if available)
4. Request from host via P2P
```

### Model Loading Flow

```
1. Check memory cache (already loaded this session)
2. If not cached, load from resolved path:
   - res:// paths: Use ResourceLoader (threaded)
   - user:// GLB: Use GlbUtils async loader (background I/O)
3. Cache loaded model in memory
4. Return duplicate/instance for caller
```

### Creating Packs

Place in `user_assets/`:

```
my_pack/
├── manifest.json
├── models/*.glb
└── icons/*.png
```

See [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md) for complete documentation.

---

## UI Architecture

### Layer System

UI uses CanvasLayers for z-ordering:

| Layer  | Purpose                 |
| ------ | ----------------------- |
| 2      | Persistent UI (AppMenu) |
| 10     | Pause overlay           |
| 80-110 | UIManager components    |

### Overlay System

Overlays are UI panels that respond to ESC key:

1. Register with `UIManager.register_overlay(self)`
2. Implement `animate_out()` or `close()` method
3. Unregister with `UIManager.unregister_overlay(self)`

ESC priority:

1. Close modals (confirmation dialogs)
2. Close overlays (level editor, settings)
3. Toggle pause (if playing)

### AnimatedVisibilityContainer

Base class for animated UI panels. Provides:

- `animate_in()` / `animate_out()` methods
- Configurable timing and easing
- Lifecycle callbacks: `_on_before_animate_in()`, `_on_after_animate_out()`, etc.

See `themes/THEME_GUIDE.md` for detailed usage.

---

## Level System

### LevelData Resource

```gdscript
class_name LevelData extends Resource

var name: String
var description: String
var author: String
var map_scene_path: String
var map_offset: Vector3
var map_scale: Vector3
var token_placements: Array[TokenPlacement]
```

### TokenPlacement Resource

```gdscript
class_name TokenPlacement extends Resource

var display_name: String
var pokemon_number: String
var is_shiny: bool
var is_player_controlled: bool
var max_health: int
var current_health: int
var is_visible: bool
var position: Vector3
var rotation_y: float
var scale: Vector3
```

### Level Flow

1. **Level Editor** creates/edits `LevelData`
2. **LevelManager** saves/loads level files (sync or async)
3. **LevelPlayController** receives level data and:
   - Loads map scene asynchronously (threaded resource loading)
   - Preloads token models via `AssetPackManager.preload_models()`
   - Spawns tokens progressively (yields to keep UI responsive)
   - Emits progress signals for loading overlay
   - Manages active gameplay
4. **Root** transitions state based on level events

---

## Token System

### BoardToken Scene

Physical game tokens representing assets from packs.

```
BoardToken (RigidBody3D)
├── CollisionShape3D
├── MeshInstance3D (model from asset pack)
├── BoardTokenController (script)
├── AnimationTree
└── network_id: String (unique identifier)
```

### Token State

Each token has an associated `TokenState` resource:

```gdscript
class_name TokenState extends Resource

var network_id: String      # Unique identifier
var pack_id: String         # Asset pack reference
var asset_id: String        # Asset reference
var variant_id: String      # Variant reference
var display_name: String
var position: Vector3
var rotation: Vector3
var scale: Vector3
var is_visible: bool
var current_health: int
var max_health: int
```

### Token Lifecycle

1. **Spawn**: Created from asset pack via `BoardTokenFactory`
2. **Register**: Added to `GameState` with unique `network_id`
3. **Sync**: State changes broadcast via `NetworkStateSync`
4. **Interaction**: Drag/drop, context menu, selection
5. **Cleanup**: Removed from `GameState`, `queue_free()`

### Network Synchronization

```gdscript
# Host creates token
var token = BoardTokenFactory.create_from_asset(pack_id, asset_id, variant_id)
GameState.register_token(token.get_state())
NetworkStateSync.broadcast_token_properties(token)

# Token moves
NetworkStateSync.broadcast_token_transform(token)

# Token removed
GameState.remove_token(network_id)
NetworkStateSync.broadcast_token_removed(network_id)
```

### Token Signals

```gdscript
signal token_added(token: BoardToken)
signal token_spawned(token: BoardToken)
signal transform_changed(token: BoardToken)
signal properties_changed(token: BoardToken)
```

---

## Communication Patterns

### Preferred: Direct Signal Connections

```gdscript
# In parent
child.some_signal.connect(_on_child_signal)

# In child
some_signal.emit(data)
```

### For Cross-Cutting Concerns: Autoloads

```gdscript
# Any script can call
UIManager.show_success("Saved!")
AudioManager.play_click()
LevelManager.save_level(data)
```

### Avoid: Global Event Bus

The project previously used an EventBus autoload but this was removed in favor of:

- Direct signal connections for parent-child communication
- Autoload services for global operations
- Controller classes for domain logic (LevelPlayController)

---

## File Organization

```
project/
├── autoloads/           # Singleton services
│   ├── network_manager.gd
│   ├── network_state_sync.gd
│   ├── game_state.gd
│   ├── asset_pack_manager.gd
│   ├── asset_downloader.gd
│   ├── asset_streamer.gd
│   └── ...
├── resources/           # Custom Resource classes
│   ├── token_state.gd
│   ├── asset_pack.gd
│   └── ...
├── scenes/
│   ├── board_token/     # Token system
│   │   ├── board_token.gd
│   │   ├── board_token_factory.gd
│   │   └── placeholder_token.gd
│   ├── states/          # Application states
│   │   ├── lobby/       # Multiplayer lobby
│   │   └── playing/     # Gameplay with asset browser
│   ├── level_editor/    # Level editor UI
│   ├── level_loader/    # Level loading UI
│   ├── maps/            # Map scenes
│   ├── templates/       # Reusable scene templates
│   └── ui/              # UI components
├── themes/              # Theme definitions
├── docs/                # Documentation
├── user_assets/         # Custom asset packs
│   └── {pack_id}/
│       ├── manifest.json
│       ├── models/
│       └── icons/
├── addons/
│   └── netfox.noray/    # NAT punchthrough addon
└── assets/
    ├── fonts/
    ├── audio/
    └── models/
```

---

## Adding New Features

### New UI Component

1. Create scene extending appropriate base (Control, CanvasLayer)
2. For animated panels, extend `AnimatedVisibilityContainer`
3. Apply theme variants from `THEME_GUIDE.md`
4. Register with UIManager if it should respond to ESC
5. Document in `UI_SYSTEMS.md`

### New State

1. Add to `Root.State` enum
2. Implement `_enter_*_state()` and `_exit_*_state()` functions
3. Update UIManager state constants to match
4. Update documentation

### New Autoload

1. Create script in `autoloads/`
2. Register in `project.godot` under `[autoload]`
3. Document purpose and API
