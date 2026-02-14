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

| Class                | File                              | Purpose                              |
| -------------------- | --------------------------------- | ------------------------------------ |
| `Constants`          | `autoloads/constants.gd`         | Shared constants (lo-fi defaults, canvas layers, network intervals, asset priorities) |
| `Paths`              | `autoloads/paths.gd`             | Path constants and static path utilities |
| `NodeUtils`          | `autoloads/node_utils.gd`        | Static node manipulation utilities   |
| `TokenPermissions`   | `autoloads/token_permissions.gd` | Per-token, per-player permission management (query, grant, revoke, serialize) |
| `SerializationUtils` | `utils/serialization_utils.gd`   | Vector3/Color/Dictionary conversion helpers for network and file I/O |
| `EnvironmentPresets` | `utils/environment_presets.gd`   | Environment preset definitions, layered config application, sky presets |

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

### Token Permissions

`TokenPermissions` (`autoloads/token_permissions.gd`) is a **static class** (Tier 1, no autoload) that provides per-token, per-player permission management. The actual permissions data lives in `GameState._token_permissions`.

```gdscript
enum Permission { CONTROL }  # Move, rotate, scale

# Grant/revoke
TokenPermissions.grant(perms, network_id, peer_id, Permission.CONTROL)
TokenPermissions.revoke(perms, network_id, peer_id, Permission.CONTROL)

# Query
TokenPermissions.has_permission(perms, network_id, peer_id, Permission.CONTROL)
TokenPermissions.get_controlled_tokens(perms, peer_id, Permission.CONTROL)
TokenPermissions.get_peers_with_permission(perms, network_id, Permission.CONTROL)

# Cleanup
TokenPermissions.clear_for_peer(perms, peer_id)    # On disconnect
TokenPermissions.clear_for_token(perms, network_id) # On token removal

# Serialization
var dict = TokenPermissions.to_dict(perms)
var restored = TokenPermissions.from_dict(dict)
```

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
- Automatic reconnection with exponential backoff (clients only, via `NetworkReconnection`)

#### NetworkReconnection

`NetworkReconnection` (`autoloads/network_reconnection.gd`) is a `RefCounted` helper class (not an autoload) that encapsulates the exponential-backoff reconnection state machine. `NetworkManager` creates it internally and delegates client reconnection to it.

- Up to 5 retries with exponential backoff (`min(1.0 * 2^attempt, 16.0)` seconds)
- Emits `reconnecting(attempt, max_attempts)` for UI feedback
- Emits `reconnection_failed(reason)` when all attempts exhausted

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

### RootNetworkHandler

`RootNetworkHandler` (`scenes/root_network_handler.gd`) provides static helpers for client-side token state mapping. It bridges `NetworkManager` transport signals to token visuals during the PLAYING state.

| Component | Role |
|-----------|------|
| `NetworkManager` (autoload) | Connection lifecycle, RPC transport, player tracking — always active |
| `RootNetworkHandler` (static helpers) | Client-side state → token visual mapping — active during PLAYING only |

```gdscript
# Root._enter_playing_state()
RootNetworkHandler.connect_client_signals(self)

# Root._exit_playing_state()
RootNetworkHandler.disconnect_client_signals(self)
```

See [NETWORKING.md](NETWORKING.md) and [CONVENTIONS.md](CONVENTIONS.md) for complete documentation.

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

## Metadata
var level_name: String = "Untitled Level"
var level_description: String = ""
var author: String = ""
var created_at: int              # Unix timestamp
var modified_at: int             # Unix timestamp
var level_folder: String = ""    # Folder name within user://levels/ (empty = not saved)

## Map
var map_path: String = ""        # Relative (folder-based) or absolute (legacy res://)
var map_scale: Vector3 = Vector3.ONE
var map_offset: Vector3 = Vector3.ZERO

## Lighting
var light_intensity_scale: float = 1.0

## Environment
var environment_preset: String = ""          # "" = use map defaults
var environment_overrides: Dictionary = {}   # Fine-tuned property tweaks
var lofi_overrides: Dictionary = {}          # Post-processing shader overrides

## Tokens
var token_placements: Array[TokenPlacement] = []
```

Key methods: `get_absolute_map_path()` (resolves relative paths for folder-based levels), `is_folder_based()`, `to_dict()` / `from_dict()` (for network serialization), `duplicate_level()`, `validate()`.

See [lighting-and-environment.md](lighting-and-environment.md) for the environment configuration layering model and how `environment_preset`, `environment_overrides`, and map defaults interact.

### TokenPlacement Resource

Represents a placed token in a level definition (static, design-time data). Uses the pack-based asset system for model identification.

```gdscript
class_name TokenPlacement extends Resource

## Unique identifier (also used as network_id when spawned)
var placement_id: String

## Asset identification (pack-based system)
var pack_id: String = ""
var asset_id: String = ""
var variant_id: String = "default"

## Transform
var position: Vector3 = Vector3.ZERO
var rotation_y: float = 0.0
var scale: Vector3 = Vector3.ONE

## Token properties
var token_name: String = ""
var is_player_controlled: bool = false
var max_health: int = 100
var current_health: int = 100
var is_alive: bool = true
var is_visible_to_players: bool = true
var status_effects: Array[String] = []
```

### Level Editor Features

- **Undo/Redo** — Snapshot-based (`Ctrl+Z` / `Ctrl+Y`). Captures `LevelData.to_dict()` before each mutation. History capped at 50 entries with deduplication.
- **Autosave** — 30-second timer writes to `user://levels/_autosave/level.json` when unsaved changes exist. On startup, prompts to recover if an autosave file is found. Cleared after manual save.

### Level Storage Formats

**Folder-based (current):**

```
user://levels/{folder_name}/
├── level.json    # LevelData serialized as JSON
└── map.glb       # Bundled map file
```

**Legacy:** `user://levels/*.tres` (Godot Resource format, read-only migration path).

**Autosave:** `user://levels/_autosave/level.json` (cleared after manual save).

See [CONVENTIONS.md](CONVENTIONS.md) for the full `level.json` schema and path resolution details.

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

Physical game tokens representing assets from packs. **Must be created via `BoardTokenFactory`** — direct instantiation will fail.

```
BoardToken (Node3D)
├── DraggableToken (DraggingObject3D)
│   ├── RigidBody3D
│   │   ├── CollisionShape3D
│   │   ├── SelectionGlowRenderer (selection_glow.gdshader on QuadMesh)
│   │   └── Model (Armature/Skeleton3D/Mesh — or PlaceholderToken while loading)
│   └── DropIndicatorRenderer (ImmediateMesh for drop-line and circle)
└── BoardTokenController (input, context menu, rotation, scaling)
```

See [CONVENTIONS.md](CONVENTIONS.md) for the full token transform hierarchy, placeholder upgrade flow, and drag-and-drop integration details.

### Token State

Each token has an associated `TokenState` resource (runtime network-sync data, managed by `GameState`):

```gdscript
class_name TokenState extends Resource

## Network ID (matches TokenPlacement.placement_id for level-spawned tokens)
var network_id: String = ""

## Asset identification
var pack_id: String = ""
var asset_id: String = ""
var variant_id: String = "default"

## Transform
var position: Vector3 = Vector3.ZERO
var rotation: Vector3 = Vector3.ZERO
var scale: Vector3 = Vector3.ONE

## Identity
var token_name: String = "Token"
var is_player_controlled: bool = false
var character_id: String = ""

## Health
var max_health: int = 100
var current_health: int = 100
var is_alive: bool = true

## Visibility
var is_visible_to_players: bool = true
var is_hidden_from_gm: bool = false

## Status
var status_effects: Array[String] = []
```

Key methods: `from_board_token()`, `from_placement()`, `apply_to_token()`, `to_dict()` / `from_dict()`, `diff()`, `should_sync_to_client()`.

### TokenConfig Resource

Optional configuration for token creation:

```gdscript
class_name TokenConfig extends Resource

var model_scene: PackedScene       # Model to use
var animation_tree_scene: PackedScene  # Custom animations (optional)
var use_convex_collision: bool = true
var lock_rotation: bool = true
var token_name: String = "Token"
var is_player_controlled: bool = false
var max_health: int = 100
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
│   ├── constants.gd         # Static class: shared constants (layers, lo-fi, network)
│   ├── paths.gd             # Static class: path constants and utilities
│   ├── node_utils.gd        # Static class: node manipulation utilities
│   ├── token_permissions.gd # Static class: per-token, per-player permissions
│   ├── event_bus.gd         # Autoload: cross-system signals
│   ├── ui_manager.gd        # Autoload: UI systems
│   ├── audio_manager.gd     # Autoload: sound playback and buses
│   ├── level_manager.gd     # Autoload: level file I/O
│   ├── network_manager.gd   # Autoload: multiplayer connections
│   ├── network_state_sync.gd # Autoload: state broadcasting
│   ├── network_reconnection.gd # RefCounted: exponential-backoff reconnection helper
│   ├── game_state.gd        # Autoload: authoritative game state
│   ├── asset_manager.gd     # Autoload: facade for asset pipeline
│   ├── asset_cache_manager.gd # Sub-component: disk cache (child of AssetManager)
│   ├── asset_pack_manager.gd  # Sub-component: pack discovery
│   ├── asset_downloader.gd    # Sub-component: HTTP downloads
│   ├── asset_streamer.gd      # Sub-component: P2P streaming
│   ├── asset_resolver.gd      # Sub-component: resolution pipeline
│   ├── asset_model_cache.gd   # RefCounted: memory model cache (owned by AssetManager)
│   └── update_manager.gd    # Autoload: GitHub release checks
├── resources/           # Custom Resource classes
│   ├── level_data.gd        # Level metadata, environment, token placements
│   ├── token_state.gd       # Runtime network-sync token state
│   ├── token_placement.gd   # Design-time token placement in levels
│   ├── token_config.gd      # Token creation configuration
│   └── asset_pack.gd        # Asset pack metadata and entries
├── scenes/
│   ├── root.gd / root.tscn  # Root controller, state stack
│   ├── board_token/     # Token system (BoardToken, Factory, animations, drag)
│   ├── states/          # Application states
│   │   ├── title_screen/  # Main menu
│   │   ├── lobby/         # Host/client lobby
│   │   ├── playing/       # Gameplay (GameMap, camera, menus, asset browser)
│   │   └── paused/        # Pause overlay
│   ├── level_editor/    # Level editor with undo/redo
│   ├── level_loader/    # Level loading UI
│   ├── maps/            # Map scenes
│   └── ui/              # Reusable UI components
├── utils/               # Utility classes
│   ├── glb_utils.gd         # GLB/GLTF loading, map post-processing
│   ├── serialization_utils.gd # Vector3/Color serialization helpers
│   ├── environment_presets.gd  # Environment preset definitions and application
│   ├── tab_utils.gd         # TabContainer animation helpers
│   ├── update_version.gd    # Version string parsing
│   └── update_installer.gd  # Update installation
├── shaders/             # GLSL shaders (lo-fi, occlusion fade, selection)
├── themes/              # Theme definitions (dark_theme.gd → dark_theme.tres)
├── tests/               # GUT unit tests and runnable test scenes
├── tools/               # Python scripts (audio normalization, hooks)
├── data/                # Static data files (pokemon.json)
├── docs/                # Authoritative documentation
├── assets/
│   ├── audio/           # UI and SFX sound files
│   ├── icons/ui/        # SVG/PNG UI icons
│   └── models/maps/     # Built-in map scenes and textures
├── addons/              # Third-party addons (netfox, DragAndDrop3D, etc.)
└── .github/workflows/   # CI/CD (Godot build, export, releases)
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

### New Global Class or Autoload

Before creating a new autoload, evaluate which tier fits (see `.cursor/rules/autoloads-and-globals.mdc`):

| Need | Approach | Example |
|------|----------|---------|
| Pure constants or static helpers | `class_name` script, no `extends Node`, `static func` | `Constants`, `Paths`, `NodeUtils` |
| Runtime state, signals, or lifecycle | Autoload singleton (`extends Node`, register in project.godot) | `UIManager`, `NetworkManager` |
| Implementation detail of existing system | Sub-component of a facade autoload (child Node with injected deps) | `AssetManager.cache`, `AssetManager.downloader` |

For a new autoload:
1. Create script in `autoloads/`
2. Register in `project.godot` under `[autoload]`
3. Document purpose, responsibilities, and public API
4. Add to the Autoloads table in this file

For a new sub-component of an existing facade:
1. Create script in `autoloads/`
2. Do NOT register in `project.godot`
3. Add a `setup()` method for dependency injection
4. Have the parent facade create it as a child node and call `setup()`
