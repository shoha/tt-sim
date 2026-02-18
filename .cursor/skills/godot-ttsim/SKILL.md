---
name: godot-ttsim
description: Guides agents through common TTSim development tasks in the Godot 4.6 tabletop simulator. Use when modifying GDScript files, adding UI components, creating resources, working with the asset pipeline, adding network features, editing shaders, or any TTSim development task.
---

# TTSim Development Skill

Quick-reference for agents working in the TTSim Godot 4.6 codebase. For full details, read `AGENTS.md` (root) and files in `docs/`.

## Project Orientation

1. **Read `AGENTS.md`** first for conventions, key APIs, and "where to add things"
2. Check `.cursor/rules/` for context-specific rules (autoloads, formatting, canvas layers, etc.)
3. Relevant docs are in `docs/` — see the Essential Reading table in `AGENTS.md`

## Common Tasks

### Adding a New Autoload or Static Class

Before creating anything global, follow the decision flowchart in `.cursor/rules/autoloads-and-globals.mdc`:

| Need | Approach |
|------|----------|
| Pure constants or static helpers | `class_name` script in `autoloads/`, no `extends Node`, `static func` |
| Runtime state, signals, or lifecycle | Autoload in `autoloads/`, register in `project.godot` |
| Implementation detail of existing system | Sub-component (child Node of facade autoload) |

After creating, update: `docs/ARCHITECTURE.md` autoloads/static classes tables, `AGENTS.md` Key Conventions, and `.cursor/rules/project-overview.mdc`.

### Adding a UI Panel

1. **In-scene panel** (shows/hides within UI tree): Extend `AnimatedVisibilityContainer`
2. **Full-screen overlay** (backdrop + centered dialog): Extend `AnimatedCanvasLayerPanel`
3. **Slide-out drawer** (screen edge with tab handle): Extend `DrawerContainer`

All three base classes handle open/close sounds automatically. Register overlays with `UIManager.register_overlay()` for ESC handling. Use theme variants from `docs/THEME_GUIDE.md`.

Set `mouse_filter = IGNORE` on all layout containers. Use `Constants.LAYER_*` for CanvasLayer numbers.

### Adding a New Resource

1. Create `class_name MyResource extends Resource` in `resources/`
2. Include `to_dict()` / `static func from_dict()` for network serialization
3. Use `SerializationUtils.vec3_to_dict()` / `dict_to_vec3()` for Vector3 fields
4. Update `docs/ARCHITECTURE.md` resource tables

### Adding Sound Effects

1. Drop audio file in `assets/audio/ui/` or `assets/audio/sfx/`
2. Add key to `_ui_sounds` or `_sfx_sounds` dictionary in `audio_manager.gd`
3. Add public helper method (e.g., `play_my_sound()`)
4. Call from game code. Buttons and panels get sounds automatically.
5. Update `docs/SOUND_EFFECTS.md`

### Adding an Environment Preset

1. Add entry to `EnvironmentPresets.PRESETS` in `utils/environment_presets.gd`
2. Update `docs/lighting-and-environment.md` preset table

### Working with the Asset Pipeline

```gdscript
# Load a model (async, cached)
var model = await AssetManager.get_model_instance(pack_id, asset_id, variant_id)

# Create a token
var token = await BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)

# Load a map (unified pipeline)
var map = await GlbUtils.load_map_async(path, true, light_scale)
```

Sub-component signals for progress UI: `AssetManager.downloader.download_progress`, `AssetManager.streamer.transfer_progress`.

### Working with Network State

```gdscript
# Check authority
if GameState.has_authority():
    GameState.register_token(token_state)
    NetworkStateSync.broadcast_token_properties(token)

# Batch updates (suppress signals until complete)
GameState.begin_batch_update()
# ... mutations ...
GameState.end_batch_update()

# Token permissions (static class, data lives in GameState)
TokenPermissions.grant(perms, network_id, peer_id, TokenPermissions.Permission.CONTROL)
```

### Working with the Level Editor

- Undo/redo: Snapshot-based via `LevelEditorHistory` (`Ctrl+Z` / `Ctrl+Y`)
- Autosave: 30-second timer to `user://levels/_autosave/`
- Environment editing: Changes go through `LevelEditPanel` -> `GameplayMenuController` -> `LevelPlayController`
- Cancel reverts all changes; save persists to disk

### Working with the Measure Tool

The measure tool (`scenes/states/playing/measure_tool.gd`) is a `Node` child of `GameMap`. Key integration points:

- **Setup**: `GameMap.setup_measure_tool()` creates it and calls `setup(camera, world_viewport, overlay_parent)`
- **Input routing**: `GameMap._input()` forwards M key and mouse events to `MeasureTool.handle_input()`. Always check `_is_mouse_over_gui()` before forwarding mouse clicks
- **Scale config**: Call `MeasureTool.configure(grid_cell_size, display_unit, display_unit_per_cell)` when scale changes. Use `ScaleUtils` for distance formatting
- **Lifecycle**: Deactivated by `LevelPlayController.clear_level()`. The `toggled(active)` signal syncs `DragAndDrop3D.dragging_enabled`
- **Rendering**: 2D overlay on `Constants.LAYER_MEASURE_OVERLAY` (layer 8) — uses `Control._draw()`, not 3D meshes. This keeps lines crisp above the lo-fi shader
- **Adding new gameplay tools**: Follow the same pattern — `Node` child of `GameMap`, own CanvasLayer, input routed through `GameMap._input()` with GUI guard, `set_input_as_handled()` to prevent propagation

### Working with the Grid Overlay

The grid overlay (`scenes/states/playing/grid_overlay.gd`) is a `MeshInstance3D` child of `Camera3D` inside the SubViewport. Key integration points:

- **Setup**: `GameMap.setup_grid_overlay()` creates it via `GridOverlay.create(camera_node)`
- **Configuration**: `GameMap.configure_grid(level_data)` sets shader uniforms (cell_size, origin, color), floor level, and configures DragAndDrop3D snap settings
- **Visibility**: Managed by `GameMap._update_grid_visibility()` — combines explicit toggle (G key), auto-show (measure/drag), and LevelData defaults. Never set `GridOverlay.visible` directly
- **Show/hide**: Use `show_grid()` / `hide_grid()` for animated transitions (0.2s fade). Use `hide_grid_immediate()` for level clear/reset (no animation). `is_grid_visible()` returns the intended state via `_showing` flag
- **Floor level**: `set_floor_level(y_level, tolerance)` sets the height filter. Default: Y=0.0, tolerance = `max(cell_size * 0.4, 0.5)`. Do NOT use `_map_bounds.position.y` — it includes mesh undersides
- **Shader pipeline**: `shaders/grid_overlay.gdshader` — depth-buffer projection → edge rejection → height filter → normal filter → grid math → three-layer compositing (cell tint → drag highlight → grid lines) → opacity multiplier
- **Cell tint**: `cell_tint_color` (theme `color_surface1` at 65%) with `cell_tint_inset` (10%) creates visible cell boundaries. Grid lines (`line_color`) are an optional additional layer (currently 0% opacity)
- **Drag highlights**: `set_drag_highlight(current_pos, start_pos)` / `clear_drag_highlight()` control per-cell highlighting during drags. Converts world positions to integer cell indices for the shader
- **Grid snap**: Integrated into `DragAndDrop3D._update_target_position()` via `ScaleUtils.snap_to_grid()`. Snaps to cell **centers** (not intersections). Shift held during drag bypasses snap
- **Tuning shader visuals**: Modify uniforms in `grid_overlay.gdshader` for appearance changes. `LevelData.grid_color` overrides `line_color` at runtime — changing the shader default alone won't work if `configure()` is called after

### Working with the Drag Ruler

The drag ruler (`scenes/states/playing/drag_ruler.gd`) is a `Node` child of `GameMap`. Key integration points:

- **Setup**: `GameMap.setup_drag_ruler()` creates it and connects DragAndDrop3D signals
- **Activation**: Automatic — starts on `dragging_started`, stops on `dragging_stopped`/`dragging_cancelled`
- **Scale config**: `DragRuler.configure(grid_cell_size, display_unit, display_unit_per_cell, grid_snap_enabled)` — called from `GameMap.configure_grid()`
- **Rendering**: 2D overlay on `Constants.LAYER_DRAG_RULER` (layer 7) — uses `MapOverlayUtils` for shared overlay and label creation

### Working with MapOverlayUtils

`MapOverlayUtils` (`utils/map_overlay_utils.gd`) provides shared factory methods for gameplay 2D overlays:

- `create_overlay(parent, layer, draw_callback)` → creates CanvasLayer + full-rect Control with draw signal connected
- `create_label_panel(font_size, font_color)` → creates PanelContainer + Label with dark backdrop styling
- Used by both `MeasureTool` and `DragRuler`. Use it for any new 2D overlay tool

## Post-Edit Checklist

After modifying code:

1. **Format**: Run `gdformat path/to/file.gd` (see `.cursor/rules/formatting.mdc`)
2. **Lint** (optional): Run `gdlint path/to/file.gd`
3. **Update docs** if you changed:
   - APIs, signals, autoloads -> `docs/ARCHITECTURE.md` + `AGENTS.md`
   - Scene tree -> `docs/ARCHITECTURE.md` Scene Hierarchy
   - UI systems -> `docs/UI_SYSTEMS.md`
   - Asset/model loading -> `docs/ASSET_MANAGEMENT.md`
   - Environment/lighting -> `docs/lighting-and-environment.md`
   - Sounds -> `docs/SOUND_EFFECTS.md`
   - Conventions or patterns -> `AGENTS.md` + `.cursor/rules/project-overview.mdc`
   - Measure tool or gameplay tools -> `docs/ARCHITECTURE.md` + `docs/UI_SYSTEMS.md`
   - Grid overlay or snap changes -> `docs/ARCHITECTURE.md` + `docs/UI_SYSTEMS.md`

## Finding User Screenshots / Reference Images

The user stores screenshots and reference images in the workspace at:

```
D:\dev\tt-sim\cursor_hints\
```

- Filenames contain **spaces**: `Screenshot 2026-02-14 204006.png`
- The directory has a `.gdignore` file, so Godot (and some search tools like Glob) may skip it
- **To list files**, use Shell: `Get-ChildItem "D:\dev\tt-sim\cursor_hints" -Name`
- **To read an image**, use the Read tool with the full path (quote spaces): `D:\dev\tt-sim\cursor_hints\Screenshot 2026-02-14 204006.png`
- Cursor's project assets cache (`C:\Users\hshore\.cursor\projects\d-dev-tt-sim\assets\`) may have copies with underscores replacing spaces and a `d__dev_tt-sim_cursor_hints_` prefix, but these can be **stale** — always check the workspace `cursor_hints/` directory first

## Key Gotchas

- **Token factory**: Always use `BoardTokenFactory` to create tokens — `BoardToken.new()` will fail
- **RPC serialization**: Godot RPCs cannot serialize `Vector3` or `Color` — convert to `Array` or `Dictionary`
- **Signal cleanup**: Disconnect autoload signals in `_exit_tree()`. Always guard with `is_connected()` before disconnecting
- **Async safety**: After every `await`, check `is_instance_valid(self)` — the node may have been freed
- **Autoload references**: Always use direct names (`AssetManager.method()`), never `get_node("/root/X")`
- **Process optimization**: Call `set_process(false)` / `set_physics_process(false)` in `_ready()` unless the node must tick immediately. Toggle on when work begins, off when idle
- **CanvasLayer numbers**: Use `Constants.LAYER_*`, never magic numbers
- **mouse_filter**: Set `IGNORE` on all non-interactive layout containers
- **Environment layering**: Never bake map defaults into `level_data`; they are derived at load time
- **Map loading**: Use `GlbUtils.load_map_async()` for maps (handles both `res://` and `user://` paths)
- **GLB async**: `GlbUtils.load_glb_async()` runs entirely on a background thread — zero main-thread blocking
- **Camera input**: Zoom uses `_input()` (not `_unhandled_input()`) because SubViewportContainer events may not propagate
- **Scale convention**: 1 world unit = 1 meter (glTF standard). `LevelData.grid_cell_size` bridges to game units. Never introduce a separate runtime `map_scale` for unit conversion
- **SubViewport world access**: Use `viewport.find_world_3d()` (method), not `viewport.world_3d` (property) — the property returns null if not explicitly set
- **2D over 3D rendering**: For crisp overlays above the lo-fi shader, render on a separate CanvasLayer with `Control._draw()`. Do not use 3D `ImmediateMesh` inside the SubViewport — it will be pixelated
- **Input consumption in GameMap**: When a gameplay tool consumes input, call `get_viewport().set_input_as_handled()` to prevent `_unhandled_input` handlers (token context menus, etc.) from firing
- **Physics layer 1**: Reserved for terrain/board — token collision uses other layers
- **Settings persistence**: Decentralized — each system reads/writes its own section in `Paths.SETTINGS_PATH`. Never hardcode `"user://settings.cfg"`. Always check `ConfigFile.load()` return value (ignore `ERR_FILE_NOT_FOUND`, warn on other errors) before overwriting
- **UIDs**: `.uid` files are auto-generated by Godot; never edit manually
- **Animation tree factory**: `BoardTokenAnimationTree` must also be created via its factory, not `.new()`
- **Threading**: Use `WorkerThreadPool` for one-off jobs; always call `wait_for_task_completion()` after polling. Guard `call_deferred()` callbacks with `is_instance_valid(self)` at the start of every deferred method. Stop threads in `_exit_tree()`
- **Theme regeneration**: After changing `dark_theme.gd`, save the file (with `UPDATE_ON_SAVE = true`) to regenerate `dark_theme.tres`
- **GUI-over-3D**: New UI panels automatically block 3D input if they have `mouse_filter = STOP` controls. Set `IGNORE` on transparent overlays that shouldn't block
- **GM-only controls**: Asset browser, save button, and edit drawer are hidden for clients. `GameplayMenuController` manages this based on `NetworkManager.connection_state_changed`
- **Shader limitations**: `return` is not allowed in `fragment()` / `vertex()` — use `if` blocks instead
- **Grid visibility**: Grid visibility is a combination of explicit toggle, auto-show, and LevelData defaults. Always use `GameMap._update_grid_visibility()` — never set `GridOverlay.visible` directly. Use `show_grid()`/`hide_grid()` for animated transitions, `hide_grid_immediate()` for level clear
- **Grid floor level**: The height filter uses Y=0 as the floor, NOT `_map_bounds.position.y` (which includes mesh undersides/foundations). If the grid is invisible, the floor Y or tolerance is likely wrong
- **Grid shader defaults vs runtime**: `LevelData.grid_color` is written to the `line_color` shader uniform by `configure()`. Changing the shader default alone has no effect if `configure()` runs after. Same applies to any uniform set by `configure()` or `set_floor_level()`
- **Grid cell tint compositing**: The shader composites three layers with a priority system (cell tint → drag highlight → grid lines). Drag highlights REPLACE the tint; grid lines sit on top via `max(alpha)`. Do not use `mix()` with `step()` on `final_alpha` — the tint makes alpha always > 0, breaking conditional blending
- **Grid snap**: Implemented in `DragAndDrop3D._update_target_position()` via `ScaleUtils.snap_to_grid()`. Snaps to cell **centers** (half-cell offset), not intersections. Shift bypasses. Configure via `GameMap.configure_grid(level_data)`
- **Drag ruler endpoint**: `DragRuler` reads `DragAndDrop3D._target_drag_position` (the snapped target), not the lerping `objectBody.global_position`
- **MapOverlayUtils returns Dictionary**: The factory methods return untyped Dictionaries — always type the receiving variable as `var result: Dictionary` to avoid GDScript type inference errors

For full details on all conventions, see `docs/CONVENTIONS.md`.
