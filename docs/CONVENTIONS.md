# Code Conventions & Gotchas

This document covers coding patterns, conventions, and non-obvious gotchas that aren't covered by the other docs. It supplements [ARCHITECTURE.md](ARCHITECTURE.md) and the `.cursor/rules/` files.

## Table of Contents

- [RPC Patterns](#rpc-patterns)
- [Signal Disconnection](#signal-disconnection)
- [Token Scene Structure & Factory Requirement](#token-scene-structure--factory-requirement)
- [Token Transform Hierarchy](#token-transform-hierarchy)
- [Placeholder Token Upgrade Flow](#placeholder-token-upgrade-flow)
- [Camera System](#camera-system)
- [Drag and Drop Integration](#drag-and-drop-integration)
- [Settings Persistence](#settings-persistence)
- [RootNetworkHandler vs NetworkManager](#rootnetworkhandler-vs-networkmanager)
- [Level Folder Format](#level-folder-format)

---

## RPC Patterns

RPCs live on `NetworkManager` and `AssetStreamer`. Follow these conventions when adding new RPCs.

### Naming

All RPC methods are private and prefixed with `_rpc_`:

```gdscript
@rpc("authority", "call_remote", "reliable")
func _rpc_send_level_data(level_dict: Dictionary) -> void:
    level_data_received.emit(level_dict)
```

### Authority & Reliability

| Direction | Annotation | Use Case |
|-----------|------------|----------|
| Host → Client | `@rpc("authority", "call_remote", "reliable")` | State updates, level data, game state |
| Host → Client | `@rpc("authority", "call_remote", "unreliable")` | Transform updates (rate-limited) |
| Client → Host | `@rpc("any_peer", "call_remote", "reliable")` | Client requests, P2P asset requests |

### Vector3 Serialization in RPCs

**Godot RPCs do not serialize `Vector3` directly.** Convert to `Array` for transport:

```gdscript
# Sending (host)
var pos_arr := [pos.x, pos.y, pos.z]
_rpc_receive_token_transform.rpc(network_id, pos_arr, rot_arr, scale_arr)

# Receiving (client)
@rpc("authority", "call_remote", "unreliable")
func _rpc_receive_token_transform(net_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array) -> void:
    var pos := Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
    token_transform_received.emit(net_id, pos, rot, scale)
```

This applies to `Vector3`, `Color`, and other engine types. Use `Array` or `Dictionary` for RPC arguments.

### Signal Emission Pattern

RPC methods should emit signals rather than performing logic directly. This keeps the RPC layer thin and testable:

```gdscript
# RPC method (thin - just emit)
@rpc("authority", "call_remote", "reliable")
func _rpc_receive_token_state(net_id: String, token_dict: Dictionary) -> void:
    token_state_received.emit(net_id, token_dict)

# Caller (sends)
func broadcast_token_properties(token: BoardToken) -> void:
    var state = TokenState.from_board_token(token)
    _rpc_receive_token_state.rpc(state.network_id, state.to_dict())
```

---

## Signal Disconnection

### Rule: Disconnect Autoload Signals in `_exit_tree()`

Non-autoload nodes that connect to autoload signals **must** disconnect in `_exit_tree()` to prevent callbacks on freed nodes:

```gdscript
func _ready() -> void:
    NetworkManager.player_joined.connect(_on_player_joined)

func _exit_tree() -> void:
    if NetworkManager.player_joined.is_connected(_on_player_joined):
        NetworkManager.player_joined.disconnect(_on_player_joined)
```

### Always Guard with `is_connected()`

Check before disconnecting to avoid errors if the signal was never connected or already disconnected:

```gdscript
# Good
if SomeAutoload.some_signal.is_connected(_handler):
    SomeAutoload.some_signal.disconnect(_handler)

# Bad - will error if not connected
SomeAutoload.some_signal.disconnect(_handler)
```

### Animated Panel Variant

For panels that use `animate_out()` before `queue_free()`, disconnect in `_on_before_animate_out()` instead of `_exit_tree()`:

```gdscript
func _on_before_animate_out() -> void:
    UIManager.unregister_overlay($ColorRect as Control)
    if AssetManager.packs_loaded.is_connected(_on_packs_loaded):
        AssetManager.packs_loaded.disconnect(_on_packs_loaded)
```

### State-Based Variant

For nodes that persist across states (like `Root`), disconnect when exiting the relevant state rather than in `_exit_tree()`:

```gdscript
func _exit_playing_state() -> void:
    # Disconnect signals that were connected in _enter_playing_state()
    if NetworkManager.token_transform_received.is_connected(_on_token_transform):
        NetworkManager.token_transform_received.disconnect(_on_token_transform)
```

`RootNetworkHandler` provides static helpers `connect_client_signals()` / `disconnect_client_signals()` for this pattern.

---

## Token Scene Structure & Factory Requirement

### Factory Requirement

**`BoardToken` instances must be created via `BoardTokenFactory`.** The factory sets up the full scene hierarchy, collision, selection glow, drop indicator, and marks the token as `_factory_created`. `BoardToken._enter_tree()` checks this flag.

```gdscript
# Correct
var token = await BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)

# Wrong - will fail
var token = BoardToken.new()
```

### Scene Hierarchy

```
BoardToken (Node3D)
├── DraggableToken (DraggingObject3D)
│   ├── RigidBody3D
│   │   ├── CollisionShape3D
│   │   ├── SelectionGlowRenderer (QuadMesh with selection_glow.gdshader)
│   │   └── Model (Armature/Skeleton3D/Mesh — or PlaceholderToken while loading)
│   └── DropIndicatorRenderer (ImmediateMesh — child of DraggableToken, not RigidBody3D)
└── BoardTokenController (handles input, context menu, rotation, scaling)
```

### Key Signals

| Signal | Source | When |
|--------|--------|------|
| `transform_changed` | `BoardToken` | Single discrete change (drop, rotate, scale complete) |
| `transform_updated` | `BoardToken` | Continuous updates during drag/rotate/scale (throttled by `Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL`) |
| `health_changed` | `BoardToken` | Health or max_health changed (carries old value for animations) |

---

## Token Transform Hierarchy

The token uses a nested transform chain that requires careful synchronization.

### The Problem

`RigidBody3D` is nested under `DraggableToken` under `BoardToken`. During drag, only the `RigidBody3D` moves. After drop, the hierarchy must be re-synchronized.

### Sync Mechanism

`DraggableToken._sync_parent_position()` runs after every drag/drop:

1. Copies `rigid_body.global_position` and `global_rotation` up to `BoardToken`
2. Resets `DraggableToken` and `RigidBody3D` local transforms to origin

This means **after sync, `BoardToken.global_position` is the canonical position.**

### Reading Position

```gdscript
# After sync (normal gameplay) — use BoardToken
var pos = token.global_position

# During drag (before sync) — use RigidBody3D
var rb = token.get_rigid_body()
var pos = rb.global_position

# For occlusion fade — use CollisionShape3D AABB center
# (not BoardToken position, which is at the feet)
```

### Setting Position

```gdscript
# Host or initial placement — immediate
token.set_transform_immediate(position, rotation, scale)

# Client receiving network update — interpolated
token.set_interpolation_target(position, rotation, scale)
```

Both methods delegate to `DraggableToken`, which handles the nested hierarchy correctly.

---

## Placeholder Token Upgrade Flow

When a model isn't cached in memory, tokens start as placeholders (pulsing cubes) and upgrade in-place when the model loads.

### Flow

```
1. BoardTokenFactory.create_from_asset_async()
   ├── Model in memory cache? → Real token returned instantly
   ├── Model on disk (not cached)? → Placeholder returned
   │   └── tree_entered → _async_upgrade_placeholder(path)
   └── Model needs download? → Placeholder returned
       └── AssetManager.asset_available → _async_upgrade_placeholder(path)

2. BoardToken._async_upgrade_placeholder(path)
   ├── await AssetManager.get_model_instance_from_path(path)  (background thread)
   ├── Guard: is_instance_valid(self) && is_inside_tree()
   ├── await get_tree().process_frame  (one frame yield)
   └── BoardTokenFactory.apply_model_upgrade(self, model)

3. BoardTokenFactory.apply_model_upgrade()
   ├── Remove PlaceholderToken child from RigidBody3D
   ├── Add real model as child
   ├── Update collision shape
   ├── Preserve floor Y position (prevent sinking/floating)
   ├── Update SelectionGlowRenderer size
   └── Set meta("is_placeholder", false)
```

### Gotchas

- The `BoardToken` instance **stays the same** — it's upgraded in-place, not replaced.
- `_pending_tokens` in the factory tracks tokens waiting for downloads; cleaned up via `tree_exiting`.
- After every `await`, always re-check `is_instance_valid(self)` — the token may have been freed during the async operation.
- Floor Y preservation prevents tokens from sinking into or floating above the map after model swap (different collision shapes have different heights).

---

## Camera System

Camera control lives in `game_map.gd`, not in a separate camera controller.

### Controls

| Input | Action | Implementation |
|-------|--------|----------------|
| Scroll wheel | Zoom | `camera_node.size` (orthographic), interpolated toward `_target_zoom` |
| WASD | Pan (isometric) | `cameraholder_node.translate()` with isometric direction mapping |
| Edge of screen | Pan (during drag) | Reads `drag_and_drop_node.edge_pan_direction` |
| Mouse near edge | Pan (idle) | `_handle_edge_panning()` with configurable margin |

### Isometric Direction Mapping

Camera movement directions are rotated 45 degrees for isometric view:

```
Forward (W) = (-1, 0, -1)  (up-left on screen)
Backward (S) = (+1, 0, +1) (down-right on screen)
Left (A) = (-1, 0, +1)     (down-left on screen)
Right (D) = (+1, 0, -1)    (up-right on screen)
```

### Zoom

- Uses orthographic projection; zoom changes `camera_node.size`
- Zooms toward the cursor position (not screen center)
- Zoom is disabled while dragging (scroll controls token height during drag)
- Zoom is disabled when mouse is over GUI panels

### Tilt-Shift DoF

`camera_3d.gd` drives the tilt-shift depth-of-field focal point:
- Raycasts from camera to find the world point under the cursor
- Updates `focal_point` shader parameter on a fullscreen quad
- DoF intensity scales with zoom level (0 at min zoom, stronger at max zoom)

### Input Handling Gotcha

Camera zoom uses `_input()` instead of `_unhandled_input()` because events from `SubViewportContainer` may not propagate to `_unhandled_input()`. Keyboard movement uses `_unhandled_key_input()`.

---

## Drag and Drop Integration

### DragAndDrop3D Addon

The addon (`addons/DragAndDrop3D/`) provides the core drag-and-drop system:

1. `DraggingObject3D` finds its first `CollisionObject3D` child
2. On left-click, emits `object_body_mouse_down`
3. `DragAndDrop3D` starts tracking after mouse exceeds `drag_threshold_px` (5px)
4. Each frame, raycasts to the ground and lerps the object toward the hit point

### Physics Conventions

| Layer | Purpose |
|-------|---------|
| Layer 1 | Terrain/board — used by drag raycast and drop-position raycast |
| Other layers | Token collision — not included in terrain raycasts |

- Tokens use `RigidBody3D` with `gravity_scale = 0`
- Position is set directly during drag; no physics simulation
- The raycast excludes the dragged object via its `RID`
- Map `StaticBody3D` nodes have `input_ray_pickable = false` (set by `GlbUtils.disable_static_body_picking()`) so viewport picking reaches tokens behind walls

### DraggableToken Extensions

`DraggableToken` extends `DraggingObject3D` with:
- `dragging_allowed` gate (for permission checks)
- `heightOffset` for pickup height (updated when scale or collision changes)
- Network interpolation: `set_network_target()` / `set_transform_immediate()`
- `input_ray_pickable = false` during settle animation to prevent re-picking

---

## Settings Persistence

### Architecture

Settings use a single `user://settings.cfg` (ConfigFile) but are **decentralized** — each system reads/writes its own section independently.

### Current Sections

| Section | Keys | Managed By |
|---------|------|------------|
| `audio` | `master_volume`, `music_volume`, `sfx_volume`, `ui_volume` | `AudioManager` |
| `graphics` | `fullscreen`, `vsync`, `lofi_enabled`, `occlusion_fade_enabled` | `SettingsMenu`, `GameMap` |
| `network` | `noray_server`, `noray_port`, `p2p_enabled` | `NetworkManager`, `AssetStreamer` |
| `updates` | `check_prereleases` | `UpdateManager` |

### Adding New Settings

1. Choose an appropriate section (or create a new one)
2. Load with `ConfigFile.load("user://settings.cfg")` in `_ready()` or setup
3. Save with `config.set_value(section, key, value)` then `config.save(path)`
4. Guard against missing keys with `config.get_value(section, key, default_value)`

### Gotcha

The settings path (`"user://settings.cfg"`) is duplicated across multiple files. If you need to change it, search for all occurrences.

---

## RootNetworkHandler vs NetworkManager

### Separation of Concerns

| Component | Role | Scope |
|-----------|------|-------|
| `NetworkManager` (autoload) | Connection lifecycle, RPC transport, player tracking | Always active |
| `RootNetworkHandler` (static helpers) | Client-side token state → visual mapping | Active during PLAYING state only |

### RootNetworkHandler Responsibilities

- Connect/disconnect client signals for the PLAYING state
- Handle token transform, transform batch, token state, token removed
- Apply full game state to token visuals
- Create tokens from `TokenState` via `BoardTokenFactory`

### Usage Pattern

```gdscript
# In Root._enter_playing_state()
RootNetworkHandler.connect_client_signals(self)

# In Root._exit_playing_state()
RootNetworkHandler.disconnect_client_signals(self)
```

The handler takes `LevelPlayController` and `GameMap` as arguments so it can manipulate tokens and the map without being coupled to `Root`.

---

## Level Folder Format

### On-Disk Structure

```
user://levels/
├── my_dungeon/
│   ├── level.json    # LevelData serialized as JSON
│   └── map.glb       # Bundled map file (copied during save)
├── forest_encounter/
│   ├── level.json
│   └── map.glb
└── _autosave/
    └── level.json    # Autosave (cleared after manual save)
```

### level.json Format

```json
{
  "level_name": "My Dungeon",
  "level_description": "A dark underground maze",
  "author": "DM Name",
  "created_at": 1700000000,
  "modified_at": 1700001000,
  "level_folder": "my_dungeon",
  "map_path": "map.glb",
  "map_scale": {"x": 1.0, "y": 1.0, "z": 1.0},
  "map_offset": {"x": 0.0, "y": 0.0, "z": 0.0},
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
  },
  "token_placements": [
    {
      "placement_id": "1700000000_1234",
      "pack_id": "pokemon",
      "asset_id": "pikachu",
      "variant_id": "default",
      "position": {"x": 0.0, "y": 0.0, "z": 0.0},
      "rotation_y": 0.0,
      "scale": {"x": 1.0, "y": 1.0, "z": 1.0},
      "token_name": "Pikachu",
      "is_player_controlled": false,
      "max_health": 100,
      "current_health": 100,
      "is_visible_to_players": true,
      "status_effects": [],
      "is_alive": true
    }
  ]
}
```

### Key Conventions

- `map_path` is **relative** in folder-based levels (e.g., `"map.glb"`), resolved via `LevelData.get_absolute_map_path()`
- `map_path` is **absolute** in legacy `.tres` levels (e.g., `"res://assets/models/maps/..."`)
- Colors in `environment_overrides` are stored as hex strings (`"#ff0000"`)
- Autosave writes to `user://levels/_autosave/level.json` and is cleared after manual save
- Folder names are generated via `Paths.sanitize_level_name()`: lowercase, spaces to underscores, restricted charset

---

## Threading & Async Patterns

The project uses several async patterns. Mixing them up causes hangs or crashes.

### Pattern 1: WorkerThreadPool (preferred for one-off jobs)

Used by `GlbUtils` and `LevelManager` for background loading:

```gdscript
var task_id = WorkerThreadPool.add_task(func():
    # Heavy work here (runs on background thread)
    _result = _do_expensive_parsing(data)
)

# Poll until done (main thread stays responsive)
while not WorkerThreadPool.is_task_completed(task_id):
    await get_tree().process_frame

# MUST call this after completion to clean up
WorkerThreadPool.wait_for_task_completion(task_id)
```

### Pattern 2: ResourceLoader.load_threaded (for Godot resources)

Used by `LevelManager` and `AssetModelCache` for `.tres` and `.tscn` files:

```gdscript
ResourceLoader.load_threaded_request(path)

while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
    await get_tree().process_frame

var resource = ResourceLoader.load_threaded_get(path)
```

### Pattern 3: Dedicated Thread (for long-running workers)

Used by `AssetPackTab` for icon loading:

```gdscript
var _thread := Thread.new()

func _start_loading():
    _thread.start(_load_icons_worker)

func _load_icons_worker():
    for item in items:
        call_deferred("_add_item_to_list", item)  # Main thread callback
```

### Threading Gotchas

1. **Deferred callbacks on freed nodes**: If a `Thread` calls `call_deferred()` and the target node is freed before the deferred call runs, it crashes. Stop threads in `_exit_tree()` and guard deferred callbacks.

2. **Always call `wait_for_task_completion()`**: After `WorkerThreadPool.is_task_completed()` returns true, you must call `wait_for_task_completion()` to release the task. Skipping this leaks.

3. **Mutex usage**: `AssetCacheManager` uses mutexes to protect cache dictionaries from concurrent access. New cache operations must follow the same locking pattern:
   ```gdscript
   _mutex.lock()
   var result = _cache.get(key, null)
   _mutex.unlock()
   ```

4. **Post-await validity**: After any `await`, re-check `is_instance_valid(self)` and `is_inside_tree()` before accessing node properties. The node may have been freed during the yield.

---

## Input Actions

Custom input actions defined in `project.godot`:

| Action | Binding | Used By |
|--------|---------|---------|
| `camera_move_forward` | W | `game_map.gd` — camera pan (isometric) |
| `camera_move_backward` | S | `game_map.gd` — camera pan |
| `camera_move_left` | A | `game_map.gd` — camera pan |
| `camera_move_right` | D | `game_map.gd` — camera pan |
| `camera_zoom_in` | Mouse wheel up | `game_map.gd` — orthographic zoom |
| `camera_zoom_out` | Mouse wheel down | `game_map.gd` — orthographic zoom |
| `rotate_model` | Middle mouse | `board_token_controller.gd` — token rotation (Shift = scale) |
| `select_token` | Left double-click | Defined but not currently referenced in code |

**Undo/Redo**: `Ctrl+Z` / `Ctrl+Y` are handled directly via `_unhandled_key_input()` in `level_editor.gd`, not through the input map.

---

## GUI-Over-3D Input Blocking

### The Problem

The 3D viewport renders inside a `SubViewportContainer`. UI panels (asset browser, drawers, menus) overlap the viewport. Without filtering, camera zoom and token interaction occur when scrolling or clicking on UI panels.

### The Solution

`game_map.gd` uses `_is_mouse_over_gui()` to block 3D input when the mouse is over UI:

```gdscript
func _is_mouse_over_gui() -> bool:
    var hovered = get_viewport().gui_get_hovered_control()
    if hovered == null:
        return false
    if hovered == _sub_viewport_container:
        return false  # The 3D viewport itself — allow 3D input
    return true       # Any other control — block 3D input
```

This is checked before processing camera zoom and edge panning.

### Implications for New UI

- New UI panels that overlap the viewport will **automatically** block 3D input if they have interactive controls (controls with `mouse_filter = STOP`)
- Pure layout containers with `mouse_filter = IGNORE` do **not** block 3D input (their children might, but the container itself doesn't)
- If a new panel should **not** block 3D input (e.g., a transparent HUD overlay), set all its controls to `mouse_filter = PASS` or `IGNORE`

---

## Token Animation System

### Factory Requirement

Like `BoardToken`, the `BoardTokenAnimationTree` **must be created via `BoardTokenAnimationTreeFactory.create()`**. It checks `_factory_created` in `_enter_tree()`.

### Animation States

The animation tree uses an `AnimationNodeStateMachinePlayback` with these states:

| State | Trigger | Description |
|-------|---------|-------------|
| `battlewait01` | Default / health increased | Idle animation |
| `damage01` | `health_changed` when `previous > current` | Damage reaction |
| `down01` | `health_changed` when `new_health == 0` | Death/knockout |

### Scene Structure

The `AnimationTree` is added as a child of the `RigidBody3D`. Its `tree_root` node path must point to the model root (parent of `AnimationPlayer`) so bone paths resolve correctly. The factory handles this wiring.

### Adding New Animations

1. Add the animation state to the `AnimationNodeStateMachine` in `board_token_animation_tree.tscn`
2. Add transition logic in `board_token_animation_tree.gd`'s `_on_health_changed()` or equivalent handler
3. Ensure the GLB model includes the animation with matching name
