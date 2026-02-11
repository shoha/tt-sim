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
│   ├── WorldViewportLayer (CanvasLayer, layer=-1)
│   │   └── SubViewportContainer (lo-fi shader post-process)
│   │       └── SubViewport
│   │           ├── CameraHolder / Camera3D
│   │           ├── MapContainer (Node3D) - map geometry added here
│   │           └── DragAndDrop3D - tokens added here
│   ├── GameplayMenu (CanvasLayer)
│   │   └── GameplayMenuController - token list, context menus
│   ├── LevelEditPanel (DrawerContainer) - slide-out editing drawer (right edge)
│   └── PlayerListDrawer (DrawerContainer) - connected players (left edge)
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

## Static Classes

These are `class_name` scripts (not autoloads) that provide globally accessible constants and static utility functions. They do not extend `Node` and are not in the scene tree.

| Class          | File                         | Purpose                              |
| -------------- | ---------------------------- | ------------------------------------ |
| `Constants`    | `autoloads/constants.gd`    | Shared constants (lo-fi defaults, canvas layers, network intervals) |
| `Paths`        | `autoloads/paths.gd`         | Path constants and static path utilities |
| `NodeUtils`    | `autoloads/node_utils.gd`    | Static node manipulation utilities   |

---

## Autoloads (Singletons)

Autoloads are registered in `project.godot` and available globally.

### Core Autoloads

| Autoload       | File                         | Purpose                              |
| -------------- | ---------------------------- | ------------------------------------ |
| `EventBus`     | `autoloads/event_bus.gd`     | Cross-system signals (pause, state, level lifecycle) |
| `LevelManager` | `autoloads/level_manager.gd` | Level save/load operations           |
| `UIManager`    | `autoloads/ui_manager.gd`    | UI systems (dialogs, toasts, etc.)   |
| `AudioManager` | `autoloads/audio_manager.gd` | Audio playback and bus control       |

### Networking Autoloads

| Autoload           | File                              | Purpose                           |
| ------------------ | --------------------------------- | --------------------------------- |
| `NetworkManager`   | `autoloads/network_manager.gd`    | Connection lifecycle, RPC routing |
| `NetworkStateSync` | `autoloads/network_state_sync.gd` | State broadcasting and batching   |
| `GameState`        | `autoloads/game_state.gd`         | Authoritative game state storage  |
| `Noray`            | `addons/netfox.noray/noray.gd`    | NAT punchthrough client           |

### Asset Management

| Autoload            | File                               | Purpose                                    |
| ------------------- | ---------------------------------- | ------------------------------------------ |
| `AssetManager`      | `autoloads/asset_manager.gd`       | Facade: pack management, resolution, model cache |

`AssetManager` is the single entry point for the asset pipeline. It owns four internal sub-components as child nodes (not separate autoloads):

| Sub-component | Access via                    | Purpose                            |
| ------------- | ----------------------------- | ---------------------------------- |
| Cache         | `AssetManager.cache`          | Disk cache with LRU eviction       |
| Downloader    | `AssetManager.downloader`     | HTTP download queue                |
| Streamer      | `AssetManager.streamer`       | P2P chunked streaming              |
| Resolver      | `AssetManager.resolver`       | Resolution pipeline (local → cache → HTTP → P2P) |

### Other Autoloads

| Autoload              | File                                | Purpose                                       |
| --------------------- | ----------------------------------- | --------------------------------------------- |
| `UpdateManager`       | `autoloads/update_manager.gd`       | GitHub release checking and in-app updates     |

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
- Late joiner handling (signal-driven, no polling)
- Automatic reconnection with exponential backoff (clients only)

See [NETWORKING.md](NETWORKING.md) for detailed documentation.

### AssetManager Responsibilities

- Asset pack discovery and registration
- Asset path resolution (local → disk cache → download → P2P)
- **Model instance loading with memory caching**
- Remote pack support
- Batch model preloading for level loading
- HTTP download queue and P2P streaming (via internal sub-components)

**Model Instance API:**

`AssetManager` provides a unified API for getting model instances with automatic caching:

```gdscript
# Get a model instance (async, uses cache)
var model = await AssetManager.get_model_instance(pack_id, asset_id, variant_id)

# Preload multiple models before batch spawning
await AssetManager.preload_models(assets_array, progress_callback)

# Clear cache when switching levels
AssetManager.clear_model_cache()
```

**Sub-component signals** (for download progress UI, etc.):

```gdscript
# HTTP download progress
AssetManager.downloader.download_completed.connect(_on_download_completed)
AssetManager.downloader.download_progress.connect(_on_download_progress)

# P2P streaming progress
AssetManager.streamer.asset_received.connect(_on_p2p_received)
AssetManager.streamer.transfer_progress.connect(_on_p2p_progress)
```

See [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md) for detailed documentation.

---

## State Management

### Root State Machine

The `Root` node implements a state stack for flexible state management.

```gdscript
enum State {
    TITLE_SCREEN,   # Main menu
    LOBBY_HOST,     # Hosting a game, waiting for players
    LOBBY_CLIENT,   # Joined a game, waiting for host to start
    PLAYING,        # Active gameplay
    PAUSED,         # Game paused (overlay state)
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

### Model Loading Flow (tokens via AssetManager)

```
1. Check memory cache (already loaded this session)
2. If not cached, load from resolved path:
   - res:// paths: Use ResourceLoader (threaded)
   - user:// GLB: Use GlbUtils async loader (full background thread)
     File I/O, GLB parsing, and scene generation all run on a
     WorkerThreadPool thread — zero main-thread blocking.
3. Cache loaded model in memory
4. Return duplicate/instance for caller
```

### Map Loading Flow (via GlbUtils.load_map / load_map_async)

Maps use a unified pipeline that handles both `res://` and `user://` paths:

```
1. GlbUtils.load_map_async(path, create_static_bodies, light_scale)
2. Loads scene (ResourceLoader for res://, GLTFDocument for user:// GLB)
3. Applies post-processing:
   - flatten_non_node3d_parents() — fix transform inheritance chains
   - process_collision_meshes() — create StaticBody3D from naming conventions
   - process_animations() — strip _loop suffix, set loop mode
   - process_lights() — apply intensity scaling
4. validate_transform_chain() — safety assertion after loading
5. Add to GameMap.map_container
```

For mid-game token spawns, `BoardTokenFactory.create_from_asset_async()` shows a
placeholder token instantly when the model isn't cached, then upgrades it
asynchronously once the background load completes.

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

Base class for in-scene animated UI panels (extends `Control`). Provides:

- `animate_in()` / `animate_out()` methods
- Configurable timing and easing via exports
- Lifecycle callbacks: `_on_before_animate_in()`, `_on_after_animate_out()`, etc.
- Automatic open/close sounds (toggle via `play_open_close_sounds` export)

Used by: `TokenContextMenu`, `AssetBrowserContainer`, `LevelEditor`

### AnimatedCanvasLayerPanel

Base class for full-screen overlay panels (extends `CanvasLayer`). Provides:

- `animate_in()` / `animate_out()` with backdrop + centered panel animation
- Automatic open/close sounds (toggle via `play_sounds` export)
- Lifecycle hooks: `_on_panel_ready()`, `_on_after_animate_in()`, `_on_before_animate_out()`, `_on_after_animate_out()`
- Expects scene structure: `ColorRect` (backdrop) + `CenterContainer/PanelContainer` (content)

Used by: `SettingsMenu`, `PauseOverlay`, `ConfirmationDialogUI`, `UpdateDialogUI`

See `THEME_GUIDE.md` for detailed usage of both base classes.

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
var light_intensity_scale: float = 1.0
var environment_preset: String = ""          # "" = use map defaults
var environment_overrides: Dictionary = {}   # Fine-tuned property tweaks
var lofi_overrides: Dictionary = {}          # Post-processing shader overrides
var token_placements: Array[TokenPlacement]
```

See [lighting-and-environment.md](lighting-and-environment.md) for the environment configuration layering model and how `environment_preset`, `environment_overrides`, and map defaults interact.

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

### Level Editor Features

- **Undo/Redo** — Snapshot-based (`Ctrl+Z` / `Ctrl+Y`). Captures `LevelData.to_dict()` before each mutation. History capped at 50 entries with deduplication.
- **Autosave** — 30-second timer writes to `user://levels/_autosave/level.json` when unsaved changes exist. On startup, prompts to recover if an autosave file is found. Cleared after manual save.

### Level Flow

1. **Level Editor** creates/edits `LevelData` (with undo/redo and autosave)
2. **LevelManager** saves/loads level files (sync or async)
3. **LevelPlayController** receives level data and:
   - Loads map via `GlbUtils.load_map_async()` (unified pipeline for `res://` and `user://` paths)
   - **Extracts and strips** embedded `WorldEnvironment` nodes from the map (preserves settings as map defaults)
   - Adds map to `GameMap.map_container` (dedicated Node3D inside SubViewport)
   - **Applies environment** via layered config: PROPERTY_DEFAULTS → map defaults → preset → overrides
   - Preloads token models via `AssetManager.preload_models()`
   - Spawns tokens progressively (yields to keep UI responsive)
   - Emits progress signals for loading overlay
   - Manages active gameplay
4. **In-game editing** — `LevelEditPanel` (drawer on right edge) allows real-time adjustments to map scale, lighting, environment, and post-processing. `GameplayMenuController` routes changes to `LevelPlayController` for immediate application. Cancel reverts all changes; save persists to disk.
5. **Root** transitions state based on level events

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

### For Cross-System Signals: EventBus

`EventBus` is a small autoload with signals that span system boundaries (e.g. `pause_requested`, `play_level_requested`, `state_changed`). Use it sparingly -- only for signals where the emitter and listener are in unrelated systems. Prefer direct signal connections for parent-child communication and autoload method calls for global operations.

---

## File Organization

```
project/
├── autoloads/           # Singleton services and static class_name scripts
│   ├── constants.gd         # Static class (class_name, not autoload)
│   ├── paths.gd             # Static class (class_name, not autoload)
│   ├── node_utils.gd        # Static class (class_name, not autoload)
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
