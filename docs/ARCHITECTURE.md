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
  - [Scale & Measurement](#scale--measurement)
  - [Measure Tool](#measure-tool)
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
│   │           │   └── GridOverlay (MeshInstance3D) - depth-projected grid overlay shader
│   │           ├── MapContainer (Node3D) - map geometry added here
│   │           ├── DragAndDrop3D - tokens added here (grid snap support)
│   │           └── [Dynamic] WeatherRenderer (Node3D) - particle weather effects
│   ├── MeasureTool (Node) - distance measurement, 2D overlay on LAYER_MEASURE_OVERLAY
│   ├── DragRuler (Node) - movement distance during token drag, 2D overlay on LAYER_DRAG_RULER
│   ├── [Authoring] BrushTool (Node) - map brushes, ring cursor on LAYER_MEASURE_OVERLAY
│   ├── GameplayMenu (CanvasLayer)
│   │   └── GameplayMenuController - token list, context menus
│   ├── LevelEditPanel (DrawerContainer) - slide-out editing drawer (right edge)
│   └── PlayerListDrawer (DrawerContainer) - connected players (left edge)
│
├── [Dynamic] PauseOverlay (CanvasLayer) - shown in PAUSED state
│
├── [Dynamic] GameMap (Node3D) - also shown in AUTHORING state, set up with
│   │                            setup_authoring() (GameplayMenu hidden and disabled)
│   └── .../MapContainer/LevelMap - AuthoredTerrain or the GLB, AuthoredScatter, AuthoredProps
└── [Dynamic] AuthoringController (Node) - AUTHORING state
    ├── AuthoringUI (CanvasLayer, LAYER_AUTHORING)
    │   └── AuthoringPanel (DrawerContainer, left edge rail) - tools, save, leave
    └── AutosaveTimer (Timer, 30 s)
```

### Dynamic vs Static Scenes

| Scene        | Lifecycle          | Managed By                   |
| ------------ | ------------------ | ---------------------------- |
| AppMenu      | Always present     | Root.\_setup_app_menu()      |
| TitleScreen  | TITLE_SCREEN state | Root.\_enter_state()         |
| GameMap      | PLAYING state      | Root.\_enter_playing_state() |
| PauseOverlay | PAUSED state       | Root.\_enter_paused_state()  |
| GameMap + AuthoringController | AUTHORING state | Root.\_enter_authoring_state() |

---

## Static Classes

These are `class_name` scripts (not autoloads) that provide globally accessible constants and static utility functions. They do not extend `Node` and are not in the scene tree.

| Class                | File                              | Purpose                              |
| -------------------- | --------------------------------- | ------------------------------------ |
| `Constants`          | `autoloads/constants.gd`         | Shared constants (lo-fi defaults, canvas layers, network intervals, asset priorities) |
| `Paths`              | `autoloads/paths.gd`             | Path constants (`SETTINGS_PATH`, level dirs) and static path utilities |
| `NodeUtils`          | `autoloads/node_utils.gd`        | Static node manipulation utilities   |
| `TokenPermissions`   | `autoloads/token_permissions.gd` | Per-token, per-player permission management (query, grant, revoke, serialize) |
| `SerializationUtils` | `utils/serialization_utils.gd`   | Vector3/Color/Dictionary conversion helpers for network and file I/O |
| `EnvironmentPresets` | `utils/environment_presets.gd`   | Environment preset definitions, layered config application, sky presets |
| `ScaleUtils`         | `utils/scale_utils.gd`           | World-to-display distance conversion, formatting, scale presets, grid snapping |
| `MapOverlayUtils`    | `utils/map_overlay_utils.gd`     | Shared CanvasLayer/Control/label panel factory for 2D map overlays |

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
| `InputProfile` | `autoloads/input_profile.gd` | Input device profiles (Mouse/Trackpad) and key label lookup |

### Networking Autoloads

| Autoload           | File                              | Purpose                           |
| ------------------ | --------------------------------- | --------------------------------- |
| `NetworkManager`   | `autoloads/network_manager.gd`    | Connection lifecycle, RPC routing |
| `NetworkStateSync` | `autoloads/network_state_sync.gd` | State broadcasting and batching   |
| `GameState`        | `autoloads/game_state.gd`         | Authoritative game state storage  |

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
| `PerformanceMonitor`  | `autoloads/performance_monitor.gd`  | Custom timer registration for the F3 performance overlay |

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
    AUTHORING,      # Building or dressing a map in the game view (offline only)
}
```

`UIManager` mirrors only `PLAYING` and `PAUSED` as ints; AUTHORING is appended so
nothing else shifts. Escape in AUTHORING goes through the overlay stack (the
AuthoringPanel), never the pause menu.

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

### Authoring Flow

Authoring mode is where a GM builds a map, or dresses a Blender-made one, inside the same
`GameMap` players see (camera, lighting, sky, weather, grid), so every choice is judged at
the game camera. Design: `docs/superpowers/specs/2026-09-26-in-game-map-authoring-design.md`
(local), "Authoring mode (phase 2)".

**Entry.** `Root.request_authoring(level, return_to)` is the one door, refused with a
toast while hosting or joined (`Root.authoring_refusal()`, pure) and for built-in `res://`
maps. Three callers: the title's **Build Map** (`TitleScreen.build_map_requested`, a new
level), a level card's **Edit map** (`LevelCard.ACTION_EDIT_MAP` ->
`LevelGrid.level_map_edit_requested` -> `TitleScreen.edit_map_requested`), and the Level
Editor's **Build map in game** (`LevelEditor.build_map_requested` ->
`AppMenuController.build_map_requested`, refused while a chosen map file is not yet saved
into the level folder). A level with a map opens at once; one without shows
`NewMapDialog`, and cancelling it changes nothing. `_begin_authoring()` closes the Level
Editor overlay and `change_state(State.AUTHORING)`.

**Enter.** `_enter_authoring_state()` instantiates `GameMap` and an `AuthoringController`,
whose `setup(game_map)` calls `GameMap.setup_authoring()`, `setup_measure_tool()` and
`setup_grid_overlay()` and builds the `AuthoringPanel`. `start(request)` first offers a
leftover autosave (`AuthoringAutosave`), then loads:

- a new map: `NewMap.create(size_ft, biome_id, seed)` (the biome's `ground_surface` is the
  base surface and its masks carry the starting cover), built with
  `MapSourceLoader.build_async("", doc)`; after install the whole map is passed to
  `AuthoredScatter.request_region()` so the cover grows in on worker threads;
- a level with `map.ttmap`: `MapSourceLoader.load_async(glb, document_path)`;
- a GLB-only level: `build_async(glb, null)`, then `NewMap.create_dressing()` makes an
  empty document (`has_base_map`) reaching the GLB's farthest geometry, written on the first
  save.

The loader runs with `separate_props = true` (scatter in `AuthoredScatter`, props in
`AuthoredProps`, both always present) and `MapSourceLoader.install()` puts the root into
`MapContainer` exactly as a play-time load does. Then the scatter node gets
`attach_document(document)`, the camera zoom-out limit becomes
`max(20, GameMap.fit_zoom_for_extent(extent, 12 m) * 1.08)` (52.4 for a 200 ft map at
16:9), pan bounds come from the document extent (`GameMap.set_map_bounds`), and every frame
`LevelEnvironmentManager.fit_shadow_distance_to_view()` keeps the sun's shadows reaching the
map's far corner (above the fixed 100 m only when zoomed out past the play range).

**Source of truth.** The `MapDocument`. Masks and heights are edited in it in place; the
scatter and props rows live in their AuthoredScatter nodes while editing and are copied
back (`_sync_document()`) before every save and autosave. `AuthoringSession` counts
revisions (dirty = the saved revision is not the current one); `AuthoringHistory` is the
undo stack brushes record `{label, undo, redo, bytes}` entries into (at most 100 entries and
64 MB of `bytes`, oldest dropped first, the newest always kept).

**Brushes.** `GameMap.setup_brush_tool()` creates `BrushTool` (modal tool contract, like
`MeasureTool` and `SunGizmoTool`: dispatched from `GameMap._input()` behind the GUI click
guard, exclusive with the other two through their `toggled` signals, and
`CameraController.rmb_can_start_pan()` refuses while it is active). The brush reads
`event.position`, raycasts once per frame on layer 1 (AuthoredTerrain and Blender collision
alike), and turns gestures into calls on an `AuthoringEditor`
(`scenes/states/authoring/authoring_editor.gd`, made per opened map) which does the edits:

- **Mask strokes** (`MaskStroke`, rules in the pure `MaskBrush`): each frame the brush
  exposes the capsule it swept for the frame's seconds times flow times the dwell gain; every
  sample in it moves `1 - exp(-3 * falloff * seconds)` of the way to its target (falloff
  `(1 - t^2)^2`), in floats kept for the stroke and written back as bytes. Paint approaches
  density 1; painting over another biome is a contest (the owner fades as the newcomer
  would grow on bare ground, and the sample changes hands when the newcomer is the denser);
  thin decays density; clear decays it six times faster. On a document with `has_base_map`
  every mode also writes the erase mask as a thin amount (0..127) that becomes 255 (erased)
  once it passes the sample's hashed noise threshold, so Blender instances disappear with a
  probability equal to how thinned their spot is (clear compresses the thresholds below
  0.85). About 1 ms per frame for a 4 m brush and 7 ms for a 12 m one on a dressed 200 ft map
  (headless, worst case writing both biome and erase masks).
- **Per frame** `flush()` takes the rectangle of samples whose bytes changed and makes one
  update each: `AuthoredTerrain.update_biome_region()`, `AuthoredScatter.request_region()`,
  and `BaseScatterEraser.refresh()`, which re-filters a dressed GLB's own scatter chunks in
  the touched cells from the unfiltered rows still in the root's scene extras, with the
  loader's rule (`MapDocument.erase_filter`) and order, keeping each chunk's visible
  fraction and shrinking the removed instances out. Picking a biome warms its assets
  (`AuthoredScatter.prepare_biome`) and its ground surface
  (`AuthoredTerrain.warm_biome_surface`, threaded texture loads).
- **History:** a stroke records the "before" bytes of every 40 x 40 sample block it first
  touches and pairs them with the blocks' final bytes at the end, ZSTD-compressed (a 30 m
  stroke with a 4 m brush: about 5 KB; the scenario session averaged 11 KB per stroke); undo
  and redo put one side back and refresh exactly its rectangle. A stroke that changes nothing
  leaves no entry and no trace (a biome it added and masks it allocated are dropped).
  Cancelling (RMB) reverts the blocks. Props (`PropRows`, rows in `AuthoredProps`) record the
  one 10 m cell a gesture changed, before and after: a placement plus its turn is one entry,
  consecutive Shift+wheel notches on one prop are one entry (committed 0.6 s after the last).
  Placed props are bedded with `DragPlaceController.raycast_terrain_down`, oriented like
  generated ones (upright or on the ground normal, then yaw), and scaled within the species'
  spread widened to at least +-25 %.

**Save.** `save_async()` waits for scatter regeneration to land, then
`AuthoringController.write_level()`: a new level gets `LevelManager.new_folder_name()`,
`map.ttmap` is written first through `MapDocumentIO.write()` (atomic; invalidates the host
hash cache), then `level.json` with `map_document` set (`LevelManager.save_level_folder`),
then a 320x180 thumbnail of the current view (`LevelManager.save_thumbnail`). The drawer
stays open. Autosave every 30 s while dirty to `user://levels/_autosave/map.ttmap` plus
`map_level.json` (the Level Editor owns `level.json` in that slot; `get_saved_levels()`
never lists `_autosave`).

**Leave.** The rail's leave item, or Escape with the drawer closed, calls
`request_leave()`: at once when clean, else `UIManager.show_choice()` with Keep editing /
Discard / Save and leave. `exit_requested(level)` makes Root change to TITLE_SCREEN (whose
grid is rebuilt, so the saved card and thumbnail show) and, when the request came from the
Level Editor, reopen the editor on the saved level (`open_level_editor_with_level`).
`_exit_authoring_state()` calls `teardown()` (drops any load in flight, releases Escape)
and frees both nodes.

---

## Networking

The project uses a **host-authoritative architecture** for multiplayer.

### Key Concepts

- **Host** acts as the server, clients connect via room codes or Steam invite
- **Steam Networking** provides relay transport via Valve's SDR network (no server infrastructure)
- **GameState** is the single source of truth (host-authoritative)
- **NetworkStateSync** handles rate-limited state broadcasting

### Connection Flow

```
Host Flow:
1. Initialize Steam → Create Steam lobby
2. Start SteamMultiplayerPeer host → Emit room code (base-36 lobby ID)
3. Clients connect → Send level data and game state

Client Flow:
1. Enter room code (or accept Steam invite) → Join Steam lobby
2. Create SteamMultiplayerPeer client → Connect to host
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

#### Token tracking API

- `TokenSpawner.track_network_token(token)` / `untrack_network_token(network_id)` register and forget tokens created from network state, keeping the `network_id` reverse index that `find_token_by_network_id()` (drag locks, permissions, undo) depends on. `RootNetworkHandler` calls the `LevelPlayController` forwards of the same names and never writes `spawned_tokens` directly.
- `TokenPlacement.sync_from_board_token(token)` is the single place that copies live token state (transform, stats, `is_alive`, `status_effects`) into a placement; both `from_board_token()` and the in-play Save Level path use it.
- `BoardToken.heal(amount)` on a downed token revives it via `revive(amount)`, so context-menu heals and undo of a killing blow bring the token back.
- In single-player, `TokenSpawner._on_token_transform_changed` syncs moves into `GameState` directly (there is no host broadcast offline).

---

## Asset Management

The asset system supports local and remote asset packs with multiplayer synchronization.

### Key Concepts

- **Asset Packs** contain models and icons with manifest.json
- **Variants** allow multiple versions of an asset (e.g., shiny, fire)
- **Remote packs** specify `base_url` for HTTP downloads
- **P2P streaming** provides fallback when the client has no URL: host redirects to HTTP if it knows a public URL, otherwise streams the file directly
- **Placeholders** shown while assets download
- **Two-level caching** - disk cache for downloads, memory cache for loaded models

### Asset Resolution

```
1. Check local file (user://user_assets/)
2. Check disk cache (user://asset_cache/)
3. Download from URL (if available)
4. Request from host via P2P (host redirects to HTTP if it has a public URL, otherwise streams)
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
   - WaterGlbUtils.process_water_meshes() — animated water on "-water" meshes
   - ScatterGlbUtils.process_scatter_instances() — user:// GLBs only: chunked
     MultiMeshInstance3D foliage from the tt_scatter_instances scene extras
   - MeshInstancingUtils.process_duplicate_mesh_instancing() — collapse duplicates
     sharing one Mesh into MultiMeshInstance3D nodes (must run last: it depends on
     collision meshes already being hidden and water planes already claimed)
4. validate_transform_chain() — safety assertion after loading
5. Add to GameMap.map_container
```

`load_map` / `load_map_async` (and `load_glb_with_processing(_async)`) take an optional
`scatter_filter`, a keep-predicate `func(origin: Vector3) -> bool` handed to
`process_scatter_instances(..., row_filter)`: a level's `map.ttmap` passes
`MapDocument.erase_filter()` so its erase mask removes the Blender scatter under erased
samples (origins in the GLB-root frame, which is the document's frame). No filter, no
change. A species the filter empties is still resolved so its template is freed.

**Play-time level load** (`LevelPlayLoader._load_level_map_async`): a folder level has a
`map.glb` (`map_path`), a `map.ttmap` (`map_document`), or both.

1. `_resolve_map_sources()`: each named file comes from the level folder, else (a client)
   from the download cache when its content hash matches the host's
   (`LevelData.map_hashes`), else it is missing. A client requests what is missing and
   `MapDownloadCoordinator` resumes the load once every file is here. A host missing its
   GLB fails; a host missing only its document plays the GLB with a warning toast.
2. `load_map_sources_async(glb_path, document_path)` (shared with the client download
   path; a thin wrapper over `MapSourceLoader.load_async`, which authoring mode uses too):
   reads and validates the document and splits its scatter + props rows into
   10 m cells on a worker thread; loads the GLB with the erase filter, or builds a bare
   `LevelMap` root holding an `AuthoredTerrain` (ground textures preloaded on threads,
   chunk meshes built per frame) that carries `AUTHORED_MAP_LIGHTING` as scene extras;
   then, when the document has rows, one `AuthoredScatter` under the root: species load
   on threads (`prepare_assets`) and resolve within an 8 ms frame budget
   (`resolve_prepared`), and cells build within the same budget (`begin_build` /
   `build_cells` / `end_build`). Props are merged into the same rows (the document on
   `LevelPlayController.loaded_map_document` keeps them apart for the authoring tools).
   An unreadable document beside a GLB loads the GLB alone (warning toast); alone it fails.
3. `_finalize_map_loading(root)` as for any map: `MapSourceLoader.install()` (environment,
   water, weather, `notify_map_loaded`, measure tool and grid, and
   `AuthoredScatter.species_added` wired to `GameMap.adopt_foliage_materials()` and
   `add_wind_materials()`), then the foliage density budget and its toast.

Measured (headless, main thread only, fully painted 200 ft temperate forest: 30,755 rows,
1,007 nodes): document read 180-540 ms on a worker, terrain about 100 ms spread over
frames, species 56 ms (about 0.3-0.6 s with a real renderer), cells 110-125 ms spread,
budget 7 ms, finalize about 60-70 ms in one frame. Longest load frame 70-84 ms (the last
cell batch + budget + finalize); warm load 0.53 s, cold 1.1 s headless, about 2 s cold
with rendering.

Scatter building is split in two. `ScatterGlbUtils.build_scatter(parent, groups,
resolve, foliage_overrides, chunk_size)` takes rows (species key -> Y-up transform rows)
and a resolver, `resolve.call(key) -> {"mesh", "wind_category", optional "name"}` or `{}`
to skip, and builds the chunked, shuffled, wind-shaded MultiMeshInstance3D nodes under
`parent`; it never classifies by name and never frees what the resolver returned.
`process_scatter_instances()` is the GLB wrapper: its resolver finds the template node
by name in the map, classifies its wind category with `WindFoliage.classify_category()`,
and frees the templates afterwards. In-game authored maps do not go through
`build_scatter()`: `AuthoredScatter` (see "Authored scatter" below) resolves each palette
species once, builds each (species, cell) node with `ScatterGlbUtils.build_chunk()`, and
rebuilds single cells while a brush paints. `PaletteLibrary.resolver()` still plugs a
palette into `build_scatter()` for one-shot builds (`utils/palette_library.gd`, the built-in palette
of `docs/ASSET_PIPELINE.md` section 9), which loads each asset GLB once per palette root
(the editor-imported PackedScene through `ResourceLoader`, since an export ships no raw
`.glb`; `GLTFDocument` only for a GLB without an import, such as a `user://` test
fixture), takes the wind category from `palette.json`, and hands out a fresh `Mesh.duplicate()` per
call so one map load's wind overrides never leak into the next. The output is the same
nodes either way, so FoliageDensityController, OcclusionFadeManager and the foliage
budget apply unchanged.

Duplicate mesh instancing is a load-time draw-call optimisation: Blender linked
duplicates (Shift+D, or a Place Helper scatter stroke) arrive as N nodes sharing one
Mesh resource, and each group of 25+ small ones becomes a single MultiMeshInstance3D.
It needs nothing from the exporting tool, so it also applies to user-uploaded maps
authored without terrain-paint — unlike `process_scatter_instances()`, whose
Geoscatter instances are not real objects in the file and must be carried as scene
extras. Groups are skipped when instancing would break something else: large meshes
(OcclusionFadeManager only fades real MeshInstance3D surfaces), skinned or animated
nodes, and anything with a material override. Source nodes that have children — a
prop's own collision body, typically — are kept with `mesh = null` rather than freed,
so collision survives.

#### Known limitations and future iterations

Recorded from the first pass so a later one doesn't have to rediscover them. None are
bugs; each is a deliberate trade made to keep the first version safe.

1. **Instanced props get no occlusion fade.** OcclusionFadeManager swaps
   StandardMaterial3D for its fade shader per MeshInstance3D surface, which a
   MultiMesh has no equivalent of. Worked around today by the `max_extent` guard
   (2.0m), which keeps anything token-sized out of a MultiMesh entirely. *Real fix:*
   run the fade logic in the MultiMesh's own material, exactly as wind foliage already
   does — `occlusion_fade_include.gdshaderinc` is shared, and
   `OcclusionFadeManager._collect_tree_materials()` already registers ShaderMaterials
   found on a MultiMesh's mesh surfaces. Note the material has to be set on the shared
   `Mesh`'s surfaces, not as an override: MultiMeshInstance3D has no per-surface
   override API (see `WindFoliage.apply_material`). Once that exists, `max_extent`
   could be raised or dropped.
2. **A MultiMesh is culled as one AABB.** Props spread across a whole map are drawn
   whenever any part of the group is on screen, so this trades per-instance frustum
   culling for the draw-call saving. Fine for the small props it currently accepts.
   *If profiling ever shows fill/vertex cost dominating:* build one MultiMesh per
   spatial grid cell instead of one per mesh, so each has a tight AABB.
3. **No per-instance picking or per-instance state.** Harmless today because map
   StaticBody3D nodes are `input_ray_pickable = false` anyway, but a future
   "click this rock" feature would need instanced props excluded — by name suffix, or
   by keeping their visual node.
4. **Thresholds are constants, not content-tunable.** `DUPLICATE_INSTANCING_MIN_COUNT`
   (25) and `DUPLICATE_INSTANCING_MAX_EXTENT` (2.0) are already parameters on the
   function; if real maps disagree about the right values, surface them through
   `LevelData` alongside `foliage_overrides`.
5. **Only shared-Mesh duplicates group.** Objects duplicated with independent mesh
   data (Blender's full copy, or Place Helper's "Object" duplicate mode rather than
   "Instance") each carry their own Mesh resource and are left alone, even when
   geometrically identical. *Options if that becomes common:* hash surface arrays to
   detect equivalent meshes (expensive at load time), or merge duplicate mesh
   datablocks on the Blender side before export — the authoring-side fix is much
   cheaper than the runtime one.
6. **Retired source nodes stay in the tree** (with `mesh = null`) whenever they have
   children, so node count doesn't drop even though draw calls do. Reparenting those
   children up one level with composed transforms would let the node be freed, but
   that's more scene surgery than the saving justifies.
7. **`cast_shadow` is taken from the group's first node.** Duplicates that disagree
   about shadow casting will all follow the representative. If that ever matters, add
   `cast_shadow` to the grouping key rather than special-casing it.

For mid-game token spawns, `BoardTokenFactory.create_from_asset_async()` shows a
placeholder token instantly when the model isn't cached, then upgrades it
asynchronously once the background load completes.

### Creating Packs

Place in `user://user_assets/` (Windows: `%APPDATA%\Godot\app_userdata\TTSim\user_assets\`):

```
my_pack/
├── manifest.json   ← optional; omit for manifest-free auto-discovery
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
var map_path: String = ""        # Relative (folder-based) or absolute (legacy res://); "" = no GLB
var map_document: String = ""    # "" or "map.ttmap": the authored map document
var map_scale: Vector3 = Vector3.ONE
var map_hashes: Dictionary       # Not saved: per-file SHA-256 from the host broadcast
var map_offset: Vector3 = Vector3.ZERO

## Scale (1 world unit = 1 meter, per glTF standard)
var grid_cell_size: float = 1.524         # World meters per grid square (default = 5 ft)
var display_unit: String = "ft"           # Unit label for distance display
var display_unit_per_cell: float = 5.0    # Display units per grid cell

## Lighting
var light_intensity_scale: float = 1.0

## Environment
var environment_preset: String = ""          # "" = use map defaults
var environment_overrides: Dictionary = {}   # Fine-tuned property tweaks
var lofi: LofiSettings                       # Typed post-processing shader params; serialized as "lofi_overrides"
var weather: WeatherSettings                 # Typed weather intensities (rain, snow, fog, wind); serialized as "weather_overrides"
var foliage: FoliageSettings                 # Typed wind-sway tuning; serialized as "foliage_overrides"

## Tokens
var token_placements: Array[TokenPlacement] = []
```

Key methods: `get_absolute_map_path()` (resolves relative paths for folder-based levels), `get_absolute_map_document_path()`, `has_map()` (a GLB, a document, or both), `is_folder_based()`, `to_dict()` / `from_dict()` (for network serialization), `duplicate_level()`, `validate()` (accepts a document-only level and checks every named file exists).

`map_document` arrives from the host in the level dict, so `from_dict()` accepts only `""`
or `"map.ttmap"`. `map_hashes` (streaming variant id -> SHA-256, see `MapFileHash`) is
written by `to_dict()` only when non-empty, which only a broadcast level is, and is
sanitized on read (known variants, 64 lowercase hex characters).

`lofi`, `weather`, and `foliage` are typed `Resource` fields (`resources/lofi_settings.gd`,
`resources/weather_settings.gd`, `resources/foliage_settings.gd`), not raw dictionaries. Each has a
`KEYS` array, `default()`, a complete `to_dict()` (every key, every time), a sparse-tolerant
`from_dict()` (older level files with only some keys still load, filling the rest with defaults),
and `copy_settings()`. The JSON keys under which they serialize (`lofi_overrides`,
`weather_overrides`, `foliage_overrides`) are unchanged from the old dictionary-based fields, so
existing level files load without migration; `_set()` also absorbs the legacy dictionary shape from
older `.tres` files.

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
├── map.glb       # Bundled Blender-made map (map_path), optional
└── map.ttmap     # Authored map document (map_document), optional
```

A level needs at least one of the two map files. `LevelManager` lists a level with
either, `duplicate_level()` copies whichever exist (dropping a named file that is
missing, refusing a level left with none), and the level editor keeps a level's document
when it saves (it does not create documents).

**Legacy:** `user://levels/*.tres` (Godot Resource format, read-only migration path).

**Autosave:** `user://levels/_autosave/level.json` (cleared after manual save).

See [CONVENTIONS.md](CONVENTIONS.md) for the full `level.json` schema and path resolution details.

### Map document (map.ttmap)

In-game map authoring (in progress) stores everything authored in tt-sim for one level in
`user://levels/{folder_name}/map.ttmap`, beside `level.json` and the optional `map.glb`.
Without a `map.glb` it is a fully in-game map; with one (`has_base_map`) it dresses that
Blender map. The format is tt-sim-internal, not a producer contract, so it lives here
rather than in `ASSET_PIPELINE.md`.

- **Classes:** `MapDocument` (`resources/map_document.gd`) is the in-memory form and owns
  the geometry and domain limits; `MapDocumentIO` (`utils/map_document_io.gd`) reads and
  writes the file: `write(doc, path) -> Error`, `read(path) -> {document, warnings}`,
  and the pure `parse(entries)` / `serialize(doc)` pair the tests drive.
- **Container:** one ZIP (`ZIPPacker`/`ZIPReader`), format 1. Entries: `manifest.json`
  (format, palette version, map seed, size in cells, cell size, sample spacing, tier
  height, base surface, `has_base_map`), `height.bin` (float32 LE heights), `scatter.json`
  and `props.json` (palette asset id -> `[lx, ly, lz, qx, qy, qz, qw, sx, sy, sz]` Y-up
  rows, the `tt_scatter_instances` format), optional `erase.png` (L8, > 127 = erased),
  optional `authoring/biomes.png` (R = biome slot, 0 none / index + 1; G = density) with
  `authoring/biomes.json` (`{"biomes": [palette biome id, ...]}`). Unknown entries are
  ignored, so later phases add `surfaces.png` and `splines.json` without a format bump.
- **Geometry:** the map is `w * cell_size_m` by `h * cell_size_m`, centred on the origin,
  floor at Y = 0. Heights and masks share one row-major grid (Z rows, X columns) of
  `round(extent / sample_spacing_m) + 1` samples per axis whose outermost samples sit on
  the map edges (the real step is `extent / (samples - 1)`, within half a spacing of the
  nominal one). `MapDocument.world_to_sample()` / `sample_to_world()` convert.
- **In memory:** rows are one flat `PackedFloat32Array` per asset (10 floats a row) and
  masks are `PackedByteArray`s on the sample grid, the forms brushes edit cheaply;
  `MapDocument.scatter_groups()` converts rows to the Array rows
  `ScatterGlbUtils.build_scatter()` takes.
- **Untrusted input:** documents arrive from the host peer, so `parse()` validates like
  `PaletteLibrary`: caps before allocation (1..64 cells per axis, spacing 0.1..1.0 m, at
  most 641 samples per axis, per-entry byte caps and 64 MB in total, 200,000 rows per asset
  and 1,000,000 in all, ids up to 200 characters), NaN/Inf rejected, `height.bin` exactly
  the grid size, PNG sizes read from the IHDR header and matched to the grid before
  decoding, malformed rows and optional entries skipped with a warning (at most 50 kept),
  never raised. A document with no usable manifest or heights is `null`. Unknown asset ids
  are kept; they resolve against the palette at load.
- **ZIP bomb guard:** `ZIPReader` cannot report an entry's size, and `read_file()` sizes
  its buffer from the size the archive declares (measured: a 432-byte archive claiming
  400 MB allocated 400 MB). `read()` therefore parses the ZIP central directory itself,
  picking records the way minizip does and refusing Zip64, and reads only entries whose
  declared size passes the caps.
- **Atomic write:** `write()` refuses a document the reader would reject or trim, packs
  into `map.ttmap.tmp` in the same folder, then renames it over the target. On Windows
  `DirAccess.rename_absolute` replaces an existing file; if the rename fails (for example
  another handle holds the target open) the old file is untouched and the temp removed.

### Authored terrain

`AuthoredTerrain` (`scenes/terrain/authored_terrain.gd`, Node3D, `create(doc)`) is the
ground of a map without `map.glb`, built from the document heights. It goes under (or is)
`LevelMap` and must be in `MapContainer` before `apply_level_environment` and
`notify_map_loaded`, since the reflection probe and camera bounds read chunk AABBs.

- **Chunks:** one `MeshInstance3D` per 10 m `ScatterChunker` cell (`TerrainChunk_c<x>_<z>`),
  vertices in world space. The sample grid is not aligned to the cells, so a chunk owns the
  samples from the first at or past its lower cell edge to the first at or past its upper
  edge; neighbours share that column bit for bit. Normals are central differences on the
  whole grid, so shared vertices light identically. The pure geometry is
  `TerrainMeshBuilder` (`utils/terrain_mesh_builder.gd`).
- **Collision:** one `StaticBody3D` (layer 1 / mask 1, `input_ray_pickable = false`, like
  GLB map bodies) with a `HeightMapShape3D` of the full grid, the body scaled by the real
  sample step on X and Z so every sample lands on its document position (the shape is
  centred like the document). Jolt triangulates each quad on the same diagonal as the mesh.
- **Sculpting (phase 3):** edit `doc.heights`, then `rebuild_chunks(cells)` (cells within
  one sample of the edit, for normals) and `update_collision()`.
- **Ground material:** `shaders/authored_ground.gdshader`, built by
  `build_ground_material(surface, seed)` from the palette surface (albedo, normal, ORM,
  height at `tile_m`); a missing surface warns and falls back to a flat earth colour.
  Anti-tiling is a triangle-grid tile-and-blend (terrain-paint's mosaic idea done live:
  3 cells per pixel with hashed rotation and offset, sharpened height-weighted blend),
  plus height-map cavity shading and world-space value-noise brightness and dry/lush
  drifts. Normals are written from the planar UV frame, no mesh tangents. The tile frame is
  computed once per pixel so phase 3 splatting adds only per-surface fetches.
- **Cost (measured 2026-09-26):** a 200 ft map (64 chunks) builds in about 35 ms warm,
  80-100 ms on first load with the textures. The ground pass costs about 1.4x a
  StandardMaterial3D ground with the same textures (in-run interleaved A/B at 1920x1080,
  +0.5 ms; measured while another application held the GPU, so the ratio, not the
  absolute time, is the number to trust).
- **Biome ground:** each painted biome's palette `ground_surface` blends over the base.
  The CPU turns `biome_slots` / `biome_density` into one RGBA8 texel per sample
  (`BiomeGroundLayers`, `utils/biome_ground_layers.gd`, pure): channel i holds the painted
  density of the biome whose surface is layer i, the base is the remainder. Weights rather
  than slots because a slot cannot be filtered (bilinear weights give smooth ramps at
  0.25 m in one fetch), biomes sharing a surface share a channel, and a biome on the base
  surface (or on a surface the palette lacks) writes nothing and costs nothing. Up to 4
  layers (`layer_*[4]` sampler arrays; arrays take no default hints, so every entry is
  bound). Layers are assigned by first appearance and kept for the session; past 4
  surfaces the least covered fall back to the nearest layer or base by mean albedo (last
  mip of the albedo), with one warning per surface. In the built-in palette that only
  happens with five distinct non-grass biomes on a grass map, and savanna grass then draws
  as forest floor (nearest mean colour), which is a poor match: raise the layer count in
  phase 3 rather than tune the fallback.
  The shader reads the weights through a noise domain warp (`biome_edge_warp_m`), adds
  finer noise to partial totals only (`biome_edge_noise`), multiplies density by
  `biome_weight_gain` so the ground reaches the sparse fringe of the scatter, and
  height-blends (`weight + (height - 0.5) * biome_height_contrast`, surfaces within
  `biome_blend_width` of the top score show), so an edge frays along texture detail
  instead of following the brush. Surfaces with zero weight at a pixel are not sampled.
  The dry/lush tints fade out on unsaturated albedo so snow is not stained.
- **Biome ground updates:** the brush edits the masks, then calls
  `update_biome_region(sample_rect)`; that recomputes those texels into a CPU mirror
  (`get_biome_weights()`) and blits just that rectangle into the `DrawableTexture2D` the
  material samples (`shaders/texel_copy_blit.gdshader`: nearest, blending disabled; the
  default blit mixes by source alpha, which corrupts the fourth weight). Godot 4.7 has no
  sub-rectangle upload for an ImageTexture (`ImageTexture.update`,
  `texture_2d_update` and `RenderingDevice.texture_update` are whole-texture);
  `DrawableTexture2D.blit_rect` is the partial path. A biome appended to `biome_ids` gets
  its layer on the next update by setting uniforms; the material is never rebuilt.
- **Biome ground cost (measured 2026-09-26, GPU held at 99% by another application, so
  ratios only):** 3 m dab update 0.05 ms median (15 x 14 samples, CPU + blit submit);
  whole-map update 4 ms; the first dab of a biome with a new surface 21-25 ms (texture
  loads and binding; T6 should warm the surface when a biome tile is picked); painted
  200 ft map build 41-44 ms. Ground viewport GPU time at the game camera against no
  painted biome, in-run interleaved: one forest disc 1.07x, whole view one layer 1.18x,
  four layer discs 1.11x, a synthetic worst case with every sample a different biome at
  half density (every pixel blends the base and several layers) 2.04x.

### Scatter generator

`ScatterGenerator` (`utils/scatter_generator.gd`, pure statics) turns a palette biome
(`PaletteLibrary.species()`, rules per `ASSET_PIPELINE.md` section 9) and a painted density
field into document rows: `generate(biome_id, species, density_at, height_at, normal_at,
map_seed, cells, bounds)` returns palette asset id -> flat rows for the instances whose
origin lies in the given 10 m chunk cells and inside the map. The fields are Callables so
tests pass analytic ones; `document_fields(doc, biome_id)` builds them from a `MapDocument`
(bilinear density for that biome's slot, bilinear heights, normals from central height
differences) and `generate_for_document()` wires both together. `ScatterPlan`
(`utils/scatter_plan.gd`) is the pure planning half: `build()` decides per species which
candidate field it draws from and how dense that field must be (packing curve, keep
models, clearance); the generator only evaluates candidates.

- **Region independence:** every species (random species share one field per size class)
  draws from a global candidate field, four hashed candidates per bucket keyed by map
  seed, biome, field and bucket, and each candidate's fate is a pure, memoized function
  of that field. A chunk comes out byte-identical alone, with neighbours or in the whole
  map, which is what lets a brush regenerate only touched chunks. Relation-driven species
  (stones near boulders) can change up to a relation's reach beyond a repainted chunk.
- **Spacing:** Matern III (a candidate survives unless a surviving higher-priority one is
  within spacing), resolved by a memoized explicit-stack recursion. It packs toward the
  random sequential packing limit, so boreal's 0.032 trees per m2 at 4.5 m land at about
  0.93x where Matern II saturates at half that. Candidate intensity inverts a measured
  packing curve (`ScatterPlan.PACKING_TIMES`), capped at `MAX_PACKING_TIME`; the plan
  reports any target past the cap as `reachable < 1`.
- **Thinning after spacing:** painted density, the pattern noise (Geoscatter's
  `dist_influence` with revert, feature size derived from its noise settings), slope with
  a 10 degree falloff, clump membership, near/avoid relations and clearance around larger
  classes multiply into one keep probability tested against a hashed uniform. Half paint
  therefore delivers half even for a saturated packing, and spacing always holds.
  Intensities are raised by the modelled keep so delivered density lands on the palette
  target; `tests/unit/test_scatter_generator_calibration.gd` prints the per-species table.
- **Cost (measured 2026-09-26, headless GDScript):** a whole 200 ft map takes 0.3 to 1.3 s
  depending on the biome, one 10 m chunk of the densest biome about 35 ms. Ground cover
  dominates (about 15 us per candidate).
- **Relation halo:** `species_reach(plan)` gives, per species, how far painted density can
  reach into its instances (relations, clump parents' relations and clearance, chained);
  `generate_species_cells()` takes a cell list per species so a brush regenerates every
  species where it painted and only the relation-driven ones around it.

### Authored scatter

`AuthoredScatter` (`utils/authored_scatter.gd`, Node3D) builds and owns the palette scatter
of an authored map: a direct child of `LevelMap` with an identity transform, so
`store_wind_materials`, `FoliageDensityController` and the other LevelMap walks find it.
Play-time loading calls `build_all(doc.scatter)`; authoring calls `set_cells()` through the
brush scheduler, so both build identical nodes.

- **Species:** each palette asset id is resolved once per instance (`PaletteLibrary.resolve`,
  `WindFoliage.apply_material` with the level's foliage overrides) and kept; rebuilds never
  create materials. A species first painted mid-session emits `species_added(materials)`;
  the owner passes them to `GameMap.adopt_foliage_materials()` (occlusion fade registration,
  then the current Antialiasing shader variant, the order load uses) and
  `LevelEnvironmentManager.add_wind_materials()` (cached for re-tuning and tuned to the
  overrides applied last). `prepare_biome()` starts threaded loads of a biome's asset
  scenes; species then resolve one per frame, and a finished brush job waits for its
  species instead of loading them on the main thread.
- **Cells:** one `MultiMeshInstance3D` per (asset id, 10 m cell) named
  `<asset id made node-safe>_MultiMesh_c<x>_<z>`, always suffixed, built by
  `ScatterGlbUtils.build_chunk` (same meta, shadow and cull settings as GLB scatter).
  Instances are ordered by a hash of each instance seeded by that name
  (`instance_order`), so the density budget's visible prefix keeps the same instances when
  a rebuild adds or removes others. `set_cells(rows_by_cell)` replaces exactly the given
  cells (asset id -> flat rows) and leaves every other node and MultiMesh untouched.
- **Density budget:** re-applied after every rebuild. The budget is map-wide
  (`FoliageBudget.plan` thins all species by one ratio), so the general case re-plans the
  whole budget root (default the parent); while the map is under budget only the rebuilt
  nodes are touched. `GameMap.apply_foliage_density()` hands a changed setting to every
  instance through the `authored_scatter` group (`set_budget`).
- **Grow-in:** rows already in a cell stay in its node; new rows go to a temporary
  `..._grow<n>` node that grows in over `GROW_SECONDS` (0.35 s, cubic ease-out) and is
  merged back when its tween ends, carrying its visible count so the budget totals do not
  move. Wind species grow through the `grow` instance uniform that every wind shader
  variant (AA, no-AA, the three debug ones) multiplies `VERTEX` by; other species (rocks)
  rise out of the ground by moving the temporary node. Instances an animated rebuild removes
  shrink away the same two ways on a self-freeing `..._shrink<n>` node (`ScatterShrink`,
  0.3 s); an unanimated rebuild (a prop turned or scaled in place) replaces them at once.
- **Brushes:** `attach_document(doc)`, then `request_region(rect)` with the rectangle of
  changed mask samples. `ScatterRegen` (`utils/scatter_regen.gd`) marks per cell and biome
  the species to regenerate (the rectangle grown by each species' reach plus one sample
  step), coalesces queued cells, and hands out one-cell jobs of plain data; `run()` executes
  them on `WorkerThreadPool` (at most 4 at once, never more than half the cores) against a
  snapshot of the document, decoding only the mask window the job can read. The snapshot
  duplicates the masks, heights and biome list (one copy per dispatch, about 0.1 ms):
  GDScript packed arrays are shared by reference, not copy-on-write, so without it a worker
  read masks the brush was writing.
  Latest wins per cell: every request bumps the cells' generations and a finished job is
  applied only where nobody has requested since; a dropped job's species stay dirty for the
  next one. `rows_by_asset()` returns the current rows for saving.

### Level Flow

1. **Level Editor** creates/edits `LevelData` (with undo/redo and autosave)
2. **LevelManager** saves/loads level files (sync or async)
3. **LevelPlayController** receives level data and:
   - Loads map via `GlbUtils.load_map_async()` (unified pipeline for `res://` and `user://` paths)
   - **Extracts and strips** embedded `WorldEnvironment` nodes from the map (preserves settings as map defaults)
   - Adds map to `GameMap.map_container` (dedicated Node3D inside SubViewport)
   - **Applies environment** via layered config: PROPERTY_DEFAULTS → map defaults → preset → overrides
   - **Sets up weather** via `GameMap.setup_weather()` and applies persisted `weather_overrides`
   - Preloads token models via `AssetManager.preload_models()`
   - Spawns tokens progressively (yields to keep UI responsive)
   - Emits progress signals for loading overlay
   - Manages active gameplay
4. **In-game editing** — `LevelEditPanel` (drawer on right edge) allows real-time adjustments to map scale, lighting, environment, post-processing, and weather. `GameplayMenuController` routes changes to `LevelPlayController` for immediate application. Cancel reverts all changes; save persists to disk. The drawer snapshots and restores a `LevelVisualState` (`resources/level_visual_state.gd`), a transient bundle of every live-editable visual field; `LevelPlayController.apply_visual_state()` is the single live apply path used by Cancel, Save, and the client receive path alike. See "GameplayMenuController" below.
5. **Root** transitions state based on level events

### Scale & Measurement

The project follows the **glTF standard: 1 world unit = 1 meter**. All imported GLB models (maps and tokens) are authored in meters and used at their native scale. There is no `map_scale`-based unit conversion at runtime.

`LevelData` provides three properties in the **Scale** export group that bridge world meters to game-specific display units:

- `grid_cell_size` (float) — World meters per grid square. Default `1.524` (= 5 ft). This is the fundamental adapter between metric world space and the game's logical grid.
- `display_unit` (String) — Label shown to players (e.g. `"ft"`, `"m"`, `"sq"`).
- `display_unit_per_cell` (float) — How many display units fit in one grid cell. Default `5.0` (5 ft per cell).

`ScaleUtils` (`utils/scale_utils.gd`) is a static utility class that performs all conversions:

```gdscript
# Convert world distance (meters) to display units
ScaleUtils.world_to_display(distance_m, grid_cell_size, display_unit_per_cell) -> float

# Format a world distance as a human-readable string (e.g. "25 ft")
ScaleUtils.format_distance(distance_m, level_data) -> String

# Format with elevation delta when height difference is significant
ScaleUtils.format_distance_with_elevation(dist_2d, dist_3d, elev_delta, level_data) -> String

# Apply a named preset (e.g. "dnd_5e", "metric_1m") to a LevelData
ScaleUtils.apply_preset(preset_key, level_data) -> void
```

GMs configure scale in the `LevelEditPanel` via a preset dropdown and a `grid_cell_size` slider. Changes propagate through `GameplayMenuController` to `LevelPlayController`, which updates `LevelData` and reconfigures the `MeasureTool`, `GridOverlay`, and `DragRuler`.

### Grid Overlay

`GridOverlay` (`scenes/states/playing/grid_overlay.gd`) renders a procedural grid onto all visible 3D geometry using a depth-buffer projection shader. It is a `MeshInstance3D` with a full-screen `QuadMesh` parented to `Camera3D` inside the SubViewport.

**Rendering — Shader Pipeline:**

The grid shader (`shaders/grid_overlay.gdshader`) follows a multi-stage pipeline:

1. **Depth reconstruction** — reads `hint_depth_texture` (reversed-Z) to reconstruct the world-space position of each visible pixel. A full-screen quad (2×2 `QuadMesh`, `flip_faces = true`) is forced to fill the screen via `POSITION = vec4(VERTEX.xy, 1.0, 1.0)` in the vertex shader.
2. **Edge rejection** — discards sky/void pixels (`raw_depth < 0.0001`) and geometry silhouette edges. Samples all 4 depth neighbors with a 2-texel kernel; discards if any neighbor is void. Also rejects pixels with large linear depth discontinuities between neighbors (`depth_threshold = max(0.1 * linear_c, 0.2)`).
3. **Height filter** — discards pixels outside `[grid_y_level ± grid_y_tolerance]`. This prevents the grid from projecting onto board tokens (which extend above the floor) and ceilings. Floor Y defaults to 0.0 (glTF convention); tolerance is `max(cell_size * 0.4, 0.5)`.
4. **Normal filter** — reconstructs surface normals via cross product of depth-buffer neighbors. Discards steep/vertical surfaces where `abs(dot(normal, UP)) < normal_threshold` (default 0.7). Only mostly-horizontal playable surfaces show the grid.
5. **Grid math** — computes grid UVs from world XZ coordinates, applies `fwidth()` anti-aliasing with configurable `line_thickness`.
6. **Distance fade** — `smoothstep` fade based on XZ distance from `grid_center` (camera look-at point projected onto the `grid_y_level` plane).
7. **Three-layer compositing** (bottom to top):
   - **Cell tint** — every cell gets a semi-transparent fill using `cell_tint_color` (theme `color_surface1` at 65% opacity). An inset mask (`cell_tint_inset`, default 10%) fades the tint near cell edges, creating visible gaps between adjacent cells without explicit grid lines.
   - **Drag highlight** — during token drags, the hovered cell and start cell are filled with a brighter color (`cell_fill_color` / `cell_start_fill_color`) with an edge glow effect. Replaces the tint layer on highlighted cells.
   - **Grid lines** — optional white lines on top (`line_color`). Currently set to 0% opacity (lines hidden) since the cell tint inset provides sufficient cell delineation.
8. **Opacity multiplier** — a global `opacity` uniform (0.0–1.0) is applied to `ALPHA`, enabling animated fade in/out from GDScript.

The overlay lives inside the SubViewport, so it naturally receives the lo-fi post-processing effect.

**Animated Visibility:**

`show_grid()` and `hide_grid()` tween the shader's `opacity` uniform over 0.2 seconds. A `_showing` boolean tracks intended state so rapid toggles interrupt cleanly. `hide_grid_immediate()` skips animation for level clear/reset.

**Visibility State Machine:**

Grid visibility combines three sources:

- **Explicit toggle** (G key) — local per-client, persists until toggled or level changes.
- **Auto-show** — temporarily visible while the MeasureTool is active (`grid_show_on_measure`) or a token is being dragged (`grid_show_on_drag`). Reverts when the context ends.
- **LevelData default** (`grid_visible`) — initial state when a level loads.

Logic: `visible = explicit_toggle OR (show_on_measure AND measuring) OR (show_on_drag AND dragging)`

**Floor Level & Token Exclusion:**

The height filter (`grid_y_level` / `grid_y_tolerance`) prevents the grid from projecting onto token bodies. `GameMap.configure_grid()` sets floor Y to 0.0 (GLB maps are authored with floors at the origin). The AABB bottom of the map is NOT used because it includes mesh undersides/foundations which are well below the actual walkable floor. Tolerance is computed as `max(cell_size * 0.4, 0.5)`, covering slight elevation changes (rugs, gentle ramps) while excluding token figures.

**Configuration:**

`LevelData` provides grid properties in the **Grid** export group: `grid_visible`, `grid_snap_enabled`, `grid_show_on_measure`, `grid_show_on_drag`, `grid_color`, `grid_origin`, `grid_type`. The `grid_type` field defaults to `"square"` and is reserved for future hex grid support.

### Grid-Snapped Movement

When `LevelData.grid_snap_enabled` is `true`, dragged tokens snap to the nearest grid cell center on XZ. This is implemented directly in `DragAndDrop3D._update_target_position()` via `ScaleUtils.snap_to_grid()`.

On release, `DragAndDrop3D.stop_drag()` writes the last snapped target's X and Z onto the body before emitting `dragging_stopped`, so the token lands on the cell the drag ruler and grid highlight showed rather than wherever the frame-rate-dependent follow lerp happened to leave it. Y is left to `DraggableToken`'s settle tween.

- **Shift modifier**: Hold Shift during drag to bypass grid snap (free move). Shift always means "free move" regardless of settings.
- **Configuration**: `GameMap.configure_grid()` sets `DragAndDrop3D.grid_snap_enabled`, `grid_cell_size`, and `grid_origin` from `LevelData`.

### Drag Ruler

`DragRuler` (`scenes/states/playing/drag_ruler.gd`) shows a distance line from a token's start position to its current position during drags. It activates automatically via `DragAndDrop3D.dragging_started` and deactivates on `dragging_stopped`/`dragging_cancelled`.

- Renders on `CanvasLayer` at `Constants.LAYER_DRAG_RULER` (layer 7, below the measure overlay).
- Uses `MapOverlayUtils` for overlay and label creation.
- Shows formatted distance (e.g. "30 ft") and cell count when grid snap is active (e.g. "6 cells / 30 ft").
- Reads `DragAndDrop3D._target_drag_position` (the snapped target) for the endpoint, not the lerping visual position.

### Shared Overlay Infrastructure (MapOverlayUtils)

`MapOverlayUtils` (`utils/map_overlay_utils.gd`) provides factory methods for creating `CanvasLayer` + `Control` overlays and styled `PanelContainer` + `Label` panels. Both `MeasureTool` and `DragRuler` use these helpers to avoid duplicating boilerplate.

### Measure Tool

`MeasureTool` (`scenes/states/playing/measure_tool.gd`) lets players measure distances on the game map. It is a `Node` (not `Node3D`) child of `GameMap`, initialized via `setup(camera, world_viewport, overlay_parent)`.

**State Machine:**

| State              | Description                                      |
| ------------------ | ------------------------------------------------ |
| `INACTIVE`         | Tool is off. No processing or rendering.         |
| `PLACING_START`    | Activated (M key). Cursor dot follows mouse, waiting for first click. |
| `PLACING_WAYPOINT` | First point placed. Preview segment stretches to cursor. Click to add waypoints, right-click/Escape to finish. |
| `PLACING_VOLUME_CENTER`  | Volume mode active. Cursor dot follows mouse, waiting for center click. |
| `PLACING_VOLUME_RADIUS`  | Center placed. Preview volume (wire + fill) stretches to cursor. Click locks radius. |

**Volume Mode:**

Tab cycles the tool's `Mode` enum (LINE → SPHERE → CYLINDER → LINE). In SPHERE or CYLINDER mode, clicking places a center point and dragging sets the radius; a second click locks the volume. RMB cancels the current step. Switching from SPHERE to CYLINDER preserves the placed center and radius. Tabbing from LINE to a volume mode carries the last placed waypoint as the volume center. The cylinder extends `CYLINDER_HEIGHT` (10 world meters, ~33 ft) above the center Y.

**Rendering Architecture:**

The tool renders entirely in 2D to avoid the lo-fi post-processing shader applied to the 3D SubViewport:

- A `CanvasLayer` at `Constants.LAYER_MEASURE_OVERLAY` (layer 8) hosts all visuals.
- A `Control` node (`_draw_control`) uses `_draw()` to render lines, circles, and the cursor dot by projecting 3D world points to 2D screen coordinates via `Camera3D.unproject_position()`.
- `PanelContainer`-based labels (pooled) display per-segment and total distances.

**Optimizations:**

- `set_process(false)` when inactive; `set_process(true)` on activation.
- Dirty flag (`_needs_redraw`) prevents redundant redraws. Marked dirty by mouse movement, clicks, camera changes, or configuration updates.
- Camera state tracking (`_last_camera_size`, `_last_camera_pos`) detects zoom/pan and triggers redraws to keep 2D projections in sync.
- `process_priority = 1` ensures the tool runs after `GameMap`'s camera updates.
- Segment label pool (`_segment_label_pool`) avoids creating/destroying nodes per frame.

**Input Handling:**

- `GameMap._input()` intercepts M key and mouse events, forwarding them to `MeasureTool.handle_input()`.
- GUI click guard: mouse clicks over UI elements (checked via `_is_mouse_over_gui()`) are not forwarded to the measure tool.
- When the tool consumes an event, `get_viewport().set_input_as_handled()` prevents propagation to `_unhandled_input` (blocking token context menus, etc.).
- Ctrl held during measurement snaps to token base positions instead of terrain.
- The `toggled(active)` signal disables `DragAndDrop3D.dragging_enabled` while measuring to prevent accidental token drags.

**Lifecycle:**

- Created and set up by `GameMap.setup_measure_tool()` during level load.
- Deactivated automatically by `LevelPlayController.clear_level()` on level unload.
- Configured with current scale settings via `configure(grid_cell_size, display_unit, display_unit_per_cell)`.

**Key Files:**

| File | Purpose |
| ---- | ------- |
| `scenes/states/playing/measure_tool.gd` | Tool logic, state machine, 2D rendering, label management |
| `scenes/states/playing/volume_overlay.gd` | 3D sphere/cylinder wireframe + fill + 2D radius label |
| `scenes/states/playing/grid_overlay.gd` | Grid overlay (MeshInstance3D + depth shader uniform management) |
| `shaders/grid_overlay.gdshader` | Depth-projected procedural grid shader |
| `scenes/states/playing/drag_ruler.gd` | Movement distance display during token drags |
| `utils/map_overlay_utils.gd` | Shared CanvasLayer/label factory for 2D overlays |
| `scenes/states/playing/game_map.gd` | Input routing, tool setup, grid/ruler lifecycle, G key toggle |
| `scenes/states/playing/level_play_controller.gd` | Lifecycle (deactivation on level clear, grid configuration) |
| `scenes/states/playing/gameplay_menu_controller.gd` | Scale config routing |
| `utils/scale_utils.gd` | Distance conversion, formatting, and grid snapping |
| `addons/DragAndDrop3D/nodes/drag_and_drop_3d.gd` | Grid snap in drag system (Shift override) |

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

See [CONVENTIONS.md](CONVENTIONS.md) for the full token transform hierarchy, placeholder upgrade flow, drag-and-drop integration, and animation system details.

### TokenSpawner

`TokenSpawner` (`scenes/states/playing/token_spawner.gd`) is a plain-object sub-component of `LevelPlayController` (not a Node) that owns spawned-token storage — the `placement_id -> BoardToken` map and the `network_id` reverse index — together with the operations that mutate it, the matching `TokenPlacement`, and `GameState`:

- `remove_token(token) -> bool` — disconnects the token's state signals, forgets it in both indices, removes its `TokenPlacement` from the active `LevelData`, removes it from `GameState`, and broadcasts the removal. Requires authority; does not record undo (the caller owns action history, since it knows to record before removing).
- `rename_token(token, new_name)` — trims and ignores blank/whitespace-only names, updates the live token, the matching `TokenPlacement.token_name` if one exists, and calls `notify_token_properties_changed()`.
- `notify_token_properties_changed(token)` — public wrapper around the same property-change handler used for signal-driven changes (health, visibility, status effects), so a rename syncs to `GameState` and broadcasts to clients the same way.
- `_track_token_from_undo()` — re-registers a token re-created by `_on_removal_undo_requested` (Ctrl+Z on a removal), restoring both the spawner's indices and the level placement.

`LevelPlayController.remove_token()` / `rename_token()` are same-named forwards to the `TokenSpawner` methods above (kept as same-named wrappers since the context menu and `GameplayActionHistory`'s undo/redo replay call them on `LevelPlayController`). `LevelPlayController.duplicate_token(token) -> BoardToken` spawns a copy of the same asset one grid cell over in +X (`LevelData.grid_cell_size`, or 1.5 m without an active level), then copies name, max health, and current health onto the new token via `rename_token()` / `set_max_health()` / `heal()` / `take_damage()`, plus the source's rotation and scale (`set_transform_immediate()` followed by an explicit `transform_changed` emit, since that setter emits nothing itself) and its player visibility (`set_visible_to_players()`, so a hidden source produces a hidden copy and the network sees it). Permissions are not copied — the copy starts GM-only. It requires authority (returns `null` otherwise), and the context menu records a `GameplayActionHistory.record_token_spawn()` entry afterwards so Ctrl+Z removes the copy again through `TokenSpawner.remove_token()`.

TokenSpawner is the single place removal and rename touch storage, placement data, and `GameState` together — never `queue_free()` a token node directly outside TokenSpawner.

### Drag-to-Place (Asset Browser)

`DragPlaceController` (`scenes/states/playing/drag_place_controller.gd`), a child `Node` of `GameMap`, handles dragging an asset out of the asset browser and dropping it on the map to spawn a new token — distinct from `DragAndDrop3D`'s dragging of already-placed tokens on the board.

- `raycast_terrain(camera, space_state, screen_pos)` — a static, independently-testable raycast against physics layer 1 (terrain/board) only, up to 1000 world meters, used to find the terrain surface (including slopes) under the cursor.
- Falls back to the existing Y=0 ground-plane intersection when the terrain raycast misses (e.g. camera pointed off the map).
- Dropping while the mouse is over GUI (`GameMap.is_mouse_over_gui()`) cancels the placement instead of spawning.
- **Snap, then resolve the height.** Grid snap moves X/Z by up to half a cell while preserving Y (`ScaleUtils.snap_to_grid` keeps `y`), so the camera hit's height is only correct for the unsnapped point — on a slope it leaves the token below the surface, where `DraggableToken._find_landing_position()`'s downward ray from the collision bottom cannot recover it. So `_complete_drag_place()` snaps X/Z first and then, when the camera ray actually hit terrain, re-resolves the height with `raycast_terrain_down(space_state, xz)` — a second static helper that casts straight down from `TERRAIN_DOWNCAST_HEIGHT` — spawning at the hit plus `PLACE_CLEARANCE` (0.25). A downcast miss (snapped off the edge of the terrain) keeps the snapped position.
- On a successful drop, calls `LevelPlayController.spawn_asset(..., settle := true)`, which drops the token the remaining clearance onto the ground via `DraggableToken.drop_to_ground()`. `TokenSpawner.spawn_asset()` runs that settle **after** `add_token_to_level()`: the settle clears `input_ray_pickable` for the landing tween and `_on_settle_complete()` restores it, so tracking (which also calls `set_interactive()`) must not run in the middle of the tween.
- The asset browser's double-click/select path (`GameplayMenuController._on_asset_selected()`) resolves its camera-centre position the same way — `raycast_terrain_down` plus `settle := true` — so both placement routes land on terrain.

### GameplayMenuController

`GameplayMenuController` (`scenes/states/playing/gameplay_menu_controller.gd`) routes between gameplay UI and `LevelPlayController`:

- **Asset browser** → `LevelPlayController.spawn_asset()` (token spawning)
- **LevelEditPanel** → `LevelPlayController` methods (map scale, lighting, environment, lo-fi, weather)
- **Save/cancel** → `LevelManager.save_level_folder()` / revert
- **Network changes** → Updates visibility of GM-only controls (asset browser, save, edit drawer)

**GM-only controls:** When connected as a client (not host), the asset browser, save button, and level edit drawer are hidden. `GameplayMenuController` listens to `NetworkManager.connection_state_changed` to toggle visibility.

**Edit mode:** When the edit drawer opens, the controller snapshots the live level into one `_original_state: LevelVisualState` (`resources/level_visual_state.gd`) — a transient bundle of every live-editable visual field (light intensity, environment preset + overrides, water style, lo-fi, weather, foliage, sun, and the grid scale fields). Cancel calls `_original_state.apply_to_level_data()` then `LevelPlayController.apply_visual_state(_original_state)` plus `update_measure_tool_scale()` (grid fields aren't part of `apply_visual_state()` itself), drops any pending throttle batch, and re-broadcasts the full snapshot. Save calls `state.apply_to_level_data()`, drops the pending batch, re-broadcasts the full snapshot so the host's late-joiner copy (`NetworkManager._current_level_dict`) reflects it, then persists to disk via `LevelManager`. `LevelEditPanel.save_requested` carries the edited `LevelVisualState` directly. When networked, live edits are applied locally at once but the per-field network broadcast is coalesced by `VisualBroadcastThrottle` (`scenes/states/playing/visual_broadcast_throttle.gd`) into one merged RPC per 100 ms, built from `LevelVisualState.to_broadcast_dict()`; Save and Cancel drop any pending batch before sending their own full snapshot. The client receive path (`LevelPlayController._on_visual_settings_received`) rebuilds a `LevelVisualState` from the current level data, patches it with `patch_from_broadcast_dict()`, writes it back with `apply_to_level_data()`, and applies it with `apply_visual_state()`.

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
│   ├── asset_manager.gd     # Autoload: facade for asset pipeline (includes pack discovery)
│   ├── asset_cache_manager.gd # Sub-component: disk cache (child of AssetManager)
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
│   ├── effects/         # Visual effects (WeatherRenderer)
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
