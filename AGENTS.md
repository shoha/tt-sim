# TTSim – Agent Quick Reference

**TTSim** is a Godot 4.7 tabletop simulator (GDScript). This file helps AI agents understand the project quickly.

## Essential Reading

| Document | Purpose |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Project structure, state management, autoloads, systems |
| [docs/README.md](docs/README.md) | Quick start, common API usage |
| [docs/THEME_GUIDE.md](docs/THEME_GUIDE.md) | UI theme variants, typography, colors |
| [docs/UI_SYSTEMS.md](docs/UI_SYSTEMS.md) | UIManager, dialogs, toasts, overlays |
| [docs/ASSET_MANAGEMENT.md](docs/ASSET_MANAGEMENT.md) | Asset packs, model loading, caching |
| [docs/SOUND_EFFECTS.md](docs/SOUND_EFFECTS.md) | Audio files, wiring, normalization, adding new sounds |
| [docs/NETWORKING.md](docs/NETWORKING.md) | Multiplayer, Steam networking, state sync |
| [docs/lighting-and-environment.md](docs/lighting-and-environment.md) | Environment presets, map defaults, sky, in-game editing |
| [docs/CONVENTIONS.md](docs/CONVENTIONS.md) | RPC patterns, signal cleanup, token hierarchy, camera, settings, gotchas |

## Tech Stack

- **Engine**: Godot 4.7
- **Language**: GDScript
- **Physics**: Jolt Physics
- **Renderer**: Forward Plus
- **Networking**: GodotSteam (SteamMultiplayerPeer, Steam Lobbies)

## Key Conventions

- **EventBus** – `EventBus` is a small autoload with cross-system signals (`pause_requested`, `state_changed`, `player_disconnected`, etc.). Use it only for signals that genuinely span system boundaries. Prefer direct signal connections for parent-child communication and autoload services for global operations
- **State stack** – Root manages states: `change_state()`, `push_state()`, `pop_state()`
- **Static classes** – `Constants`, `Paths`, `NodeUtils`, `TokenPermissions`, `SerializationUtils`, `EnvironmentPresets`, `ScaleUtils`, and `MapOverlayUtils` are `class_name` scripts (not autoloads). They provide globally accessible constants and static utility functions without a Node in the tree
- **Autoloads** – UIManager, LevelManager, AssetManager, NetworkManager, EventBus, GameState, NetworkStateSync, AudioManager, UpdateManager, InputProfile, PerformanceMonitor (see project.godot). Always reference autoloads directly (e.g. `AssetManager.method()`), never via `has_node("/root/X")` or `get_node("/root/X")`
- **Shared constants** – Use `Constants.LOFI_DEFAULTS`, `Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL`, etc. for values shared across files. Use `Paths.SETTINGS_PATH` for the settings file path (never hardcode `"user://settings.cfg"`). Add file-local constants for single-file magic numbers
- **Map loading** – Use `GlbUtils.load_map_async()` (or `load_map()` sync) for maps; handles both `res://` and `user://` paths with full post-processing
- **GLB loading** – Use `GlbUtils.load_glb_with_processing_async()` for non-map GLBs (tokens use `AssetManager` instead)
- **Duplicate mesh instancing** – `MeshInstancingUtils.process_duplicate_mesh_instancing()` runs last in the map pipeline, collapsing groups of 25+ small MeshInstance3D nodes that share one Mesh resource (Blender linked duplicates) into one MultiMeshInstance3D each. Large/skinned/animated/material-overridden nodes are skipped, and source nodes with children keep their place with `mesh = null` so their collision bodies survive. Known limitations and their planned workarounds are listed in `docs/ARCHITECTURE.md` Map Loading Flow — read those before extending it
- **Models** – Use `AssetManager.get_model_instance()` for cached model loading
- **Signal cleanup** – Disconnect autoload signals in `_exit_tree()` for non-autoload nodes. Always guard with `is_connected()` before disconnecting. Use `CONNECT_ONE_SHOT` for transient signals. Guard `call_deferred()` callbacks with `is_instance_valid(self)`. See `docs/CONVENTIONS.md` for full patterns
- **Process optimization** – Call `set_process(false)` / `set_physics_process(false)` in `_ready()` unless the node needs to tick immediately. Toggle on when work begins, off when idle. Same for `_physics_process()`. This avoids unnecessary per-frame overhead
- **UIDs** – Godot `.uid` files are auto-generated; avoid manual edits
- **CanvasLayer ordering** – Layer numbers are centralized in `Constants` (`LAYER_*`). Check screen region comments before adding UI to avoid overlaps. See `.cursor/rules/canvas-layers.mdc`
- **mouse_filter** – Set `mouse_filter = IGNORE` on pure layout containers (`Control`, `MarginContainer`, `HBoxContainer`, etc.). Only interactive controls and modal backdrops should keep the default `STOP`
- **Weather effects** – `WeatherRenderer` (`scenes/effects/weather_renderer.gd`) provides combinable visual weather (rain, snow, wind particles + fog overlay). Intensities stored in `LevelData.weather` (a typed `WeatherSettings`, serialised under `weather_overrides`). Created per level load in the SubViewport via `GameMap.setup_weather()`, freed via `GameMap.clear_weather()`. UI sliders in `LevelEditPanel` Weather section. See `docs/lighting-and-environment.md` Weather Effects section
- **Water disturbance uniform** – `WaterRippleRegistry` (`utils/water_ripple_registry.gd`) is the only writer of the shared water material's `water_disturbance_points` uniform (via `flush_disturbances()`, called from every live `WaterZone._process()` but pushed at most once per frame). `WaterZone._process()` must never push the uniform directly -- it only registers/unregisters submerged tokens and calls `flush_disturbances()`
- **Foliage wind-sway tuning** – Per-category wind-sway speed/amplitude for scattered foliage tunes `WindFoliage.PRESETS` (tree/grass). Overrides live in `LevelData.foliage`, a typed `FoliageSettings` (`resources/foliage_settings.gd`; keys: `tree_sway_speed`, `tree_sway_amplitude`, `grass_sway_speed`, `grass_sway_amplitude`), serialised under the unchanged `foliage_overrides` JSON key. Baked into wind `ShaderMaterial`s at map-load time by `GlbUtils`; live-re-tunable without a map reload via `LevelEnvironmentManager.apply_foliage_overrides()` / `LevelPlayController.apply_foliage_overrides()`. See `docs/lighting-and-environment.md` Data Storage section
- **Foliage primitive budget** – Imported (`user://`) maps' scattered-foliage primitive count is capped by a per-user setting (`graphics/foliage_budget` in `user://settings.cfg`, default `FoliageBudget.PRIMITIVE_BUDGET` = 8,000,000, range 2M-24M), adjustable in Settings > Graphics and not networked -- peers may run different densities safely, since scatter foliage carries no collision. This is because a MultiMesh is culled as one AABB so every instance is vertex-processed whenever any part of its species is on screen (superseded by spatial chunking below -- true for every map before chunking landed, now only the worst case at full zoom-out). Import (`ScatterGlbUtils.process_scatter_instances()`) builds every scatter instance and shuffles each chunk; the cap is applied at runtime, live in both directions with no map reload, by `FoliageDensityController` (`scenes/states/playing/foliage_density_controller.gd`), which writes `MultiMesh.visible_instance_count` on every chunk. The player gets one toast from `level_loader.gd` when the setting thins the map. Built-in `res://` maps never run the scatter pipeline. Measured attribution, the setting's derivation, known dead ends, and the measurement procedure are all in `docs/PERFORMANCE.md` – read it before attempting any rendering optimisation
- **Spatial foliage chunking** – Scatter species are split into world-space cells at import by `ScatterChunker` (`utils/scatter_chunker.gd`) so frustum culling can discard off-screen foliage. A species occupying a single cell keeps its unsuffixed `<Species>_MultiMesh` name; a split species gets a `_c<x>_<z>` suffix. See `docs/PERFORMANCE.md`
- **Environment system** – Environment settings use a layering model: `PROPERTY_DEFAULTS` → map defaults → named preset → user overrides. See `docs/lighting-and-environment.md`. Key points:
  - `LevelData.environment_preset` defaults to `""` (empty = use map defaults)
  - Map defaults are extracted at load time, never baked into `level_data`
  - Use `EnvironmentPresets.apply_to_world_environment()` with `map_defaults` parameter
  - Embedded `WorldEnvironment` nodes are stripped from maps after extraction
  - Blender-exported `.glb` maps carry ambient light via glTF scene-level `extras`
    instead (see `GlbUtils.extract_lighting_config()`), since glTF has no
    `WorldEnvironment` equivalent
  - Sun and shadow configuration is a separate axis from this layering model: it
    lives in `LevelData.visual_settings.sun` as a typed `SunSettings`, not in
    `PROPERTY_DEFAULTS`/`environment_overrides`. `LevelData.format_version` gates
    migration of pre-`SunSettings` payloads in `from_dict()`. See
    `docs/lighting-and-environment.md`'s Sun and Shadow section
- **Settings persistence** – Each system reads/writes its own section in `Paths.SETTINGS_PATH` (`user://settings.cfg`). Always check `ConfigFile.load()` return value before overwriting — ignore `ERR_FILE_NOT_FOUND` but warn on other errors. See `docs/CONVENTIONS.md` Settings Persistence
- **In-game editing** – `LevelEditPanel` (extends `DrawerContainer`, right edge) provides real-time editing during gameplay (map, lighting, environment, post-processing, weather). `GameplayMenuController` routes changes to `LevelPlayController`. Cancel reverts; save persists to disk.
  - Visual state and apply path: the drawer snapshots and restores a `LevelVisualState` (`resources/level_visual_state.gd`) — a transient bundle of every live-editable visual field — on open/Cancel/Save; `LevelPlayController.apply_visual_state()` is the single live apply path used by Cancel, Save, and the client receive path alike
  - Sun pane (`visual_panes/sun_pane.gd`): time of day with sunrise/noon/sunset ticks, mode tiles, aim on map, and the direction/colour/energy/shadow rows under Advanced, with Time of Day acting as a generator that can (re)populate direction/color/energy from an hour rather than driving them directly
  - Broadcast throttle: live edits are applied locally at once but broadcast to clients through `VisualBroadcastThrottle` (one merged RPC per 100 ms); Save and Cancel drop any pending batch before sending their full snapshot
  - Dirty state and prompts: the panel tracks unsaved edits (`is_dirty()`/`_mark_dirty()`/`mark_clean()`) — a dirty drawer badges the edited panes' rail items (there is no aggregate handle tooltip any more), and vetoes a rail close or Escape with a "Discard changes" / "Keep editing" prompt via `request_close()`; Save clears the flag but leaves the drawer open instead of closing it
  - Override indicators: overridden environment properties get an accent-tinted row label with a tooltip and a right-click per-row reset, and switching presets keeps existing overrides (with a toast) rather than clearing them
  - Panes: the drawer is a `DrawerContainer` in rail mode hosting six `LevelEditPane`s in a `PaneStack` (`scenes/states/playing/visual_panes/`); the Sky and Color panes share an `EnvironmentEditModel`. Adding a live-synced property means a row in the right pane plus that pane's `load_state`/`write_state` lines. Primary controls are tile rows (`TileField`) and hinted sliders; exact numbers live under each pane's Advanced foldout and show only with the rail footer values toggle. Style tiles (Shadows, Film style, Wind) map onto existing fields and show Custom when nothing matches.
- **Scale convention** – 1 world unit = 1 meter (glTF standard). `LevelData.grid_cell_size` adapts meters to game units. Use `ScaleUtils` for all distance conversion and formatting
- **Measure tool** – `MeasureTool` (Node child of GameMap) provides distance measurement. Renders 2D on `LAYER_MEASURE_OVERLAY` (layer 8) to stay crisp above the lo-fi shader. M key toggles. Disables token dragging while active. Input routed through `GameMap._input()` with GUI click guard. Tab cycles mode: Line → Sphere → Cylinder → Line. VolumeOverlay (child of MeasureTool, created in setup()) renders 3D wireframe + transparent fill inside the SubViewport, plus a 2D label. Tabbing from a line waypoint uses that point as the volume center.
- **Grid overlay** – `GridOverlay` (MeshInstance3D child of Camera3D inside SubViewport) projects a procedural grid via depth-buffer shader. Uses cell tint (theme `color_surface1` at 65% with 10% inset) instead of grid lines for readability on bright maps. Height filter (`grid_y_level`/`grid_y_tolerance`) prevents projection onto tokens. Animated fade in/out (0.2s). G key toggles (local per-client). Auto-shows during measure tool and token drag (configurable via `LevelData`). Managed by `GameMap`
- **Grid snap** – `DragAndDrop3D` snaps to grid cell centers when `grid_snap_enabled = true`. Hold Shift for free move override. Configured from `LevelData` via `GameMap.configure_grid()`
- **Deferred pointer raycasts** – Pointer raycasts for token drag-and-drop (`DragAndDrop3D`) and the measure tool are deferred to `_process`, which runs the raycast at most once per frame regardless of how many motion/wheel events arrived that frame; input handlers (`_input`/`_unhandled_input`) only record the latest pointer position, never raycast synchronously
- **Drag ruler** – `DragRuler` (Node child of GameMap) shows movement distance during token drag. Renders 2D on `LAYER_DRAG_RULER` (layer 7). Activates/deactivates via DragAndDrop3D signals. Uses `MapOverlayUtils` for 2D overlay boilerplate
- **MapOverlayUtils** – Shared factory for creating CanvasLayer/Control overlays and styled label panels. Used by `MeasureTool`, `DragRuler`, and `SunGizmoTool`
- **Modal map tools** – `MeasureTool` and `SunGizmoTool` share a contract (`is_active()`, `activate()`, `deactivate()`, `toggle()`, `handle_input()`, a `toggled` signal). Both are created and owned by `GameMap` (`setup_measure_tool()`/`setup_sun_gizmo()`), dispatched from the same branch structure in `GameMap._input()`, and wired into `CameraController` (`set_measure_tool()`/`set_sun_gizmo()`) to suppress right-mouse-button pan while either is active. `GameMap` keeps the two mutually exclusive by connecting each tool's `toggled` signal and deactivating the other on activation, so neither tool needs to know the other exists

## Adding Features

- **New state**: Add to `Root.State` enum, implement `_enter_*_state()` / `_exit_*_state()`
- **New autoload**: See `.cursor/rules/autoloads-and-globals.mdc` for the decision flowchart. Only create an autoload for a true service with runtime state. Pure constants/utilities should be `class_name` static classes. Implementation details of existing systems should be facade sub-components
- **New UI panel (in-scene)**: Extend `AnimatedVisibilityContainer`, register with `UIManager.register_overlay()` for ESC handling. Compose `scenes/ui/primitives/` (IconButton, IconRail, TileRow, Foldout, PropertyRow) rather than raw Buttons; see `docs/THEME_GUIDE.md` UI Primitives
- **New UI overlay (full-screen dialog)**: Extend `AnimatedCanvasLayerPanel`, override `_on_panel_ready()` for setup
- **New slide-out drawer**: Extend `DrawerContainer`, configure `edge`, `drawer_width`, `tab_text` in `_on_ready()`. If the drawer can hold unsaved edits, override `_can_close_from_tab()` to veto a tab close and use `set_tab_badge()` for an unsaved indicator (see `LevelEditPanel`) — set `rail_items` for a multi-pane drawer (see `LevelEditPanel`)
- **New level/token logic**: See LevelPlayController, BoardTokenFactory (tokens MUST be created via factory), GameState, TokenPermissions. Removal, rename, and duplicate go through `TokenSpawner` (`LevelPlayController.remove_token()`/`rename_token()`/`duplicate_token()` forward to it) — it is the single owner of spawned-token storage, the matching `TokenPlacement`, and `GameState` together. Never `queue_free()` a token node directly outside TokenSpawner
- **New RPC**: Follow conventions in `docs/CONVENTIONS.md` — `@rpc` with `_rpc_` prefix, use `Array` not `Vector3` for parameters, emit signals from RPC methods
- **New environment preset**: Add to `EnvironmentPresets.PRESETS` in `utils/environment_presets.gd`. Also add a tile entry to `SkyPane.SKY_TILES` (`scenes/states/playing/visual_panes/sky_pane.gd`), or the Sky pane cannot show or select the new preset
- **New environment property**: Add to `PROPERTY_DEFAULTS`, update `_apply_config_to_environment()`, `extract_from_environment()`, and `LevelEditPanel` controls. Sun and shadow properties are the exception: they go on `SunSettings` instead (field, `to_dict()`, `from_dict()`, `DefaultSun.apply()`, and the Sun pane (`visual_panes/sun_pane.gd`)), not on `PROPERTY_DEFAULTS`. `copy_settings()` needs no change for a value-type field — it is `duplicate()`-based, so only a nested `Resource` field would require a new deep-copy line
- **New level schema field**: Add the `@export`, update `to_dict()`/`from_dict()`/`duplicate_level()`. If the shape of an existing field changes, bump `LevelData.FORMAT_VERSION`, add a migration branch in `from_dict()`, and add a test proving old payloads still load correctly
- **New live-synced visual property**: field on `LevelData` (+ `to_dict()`/`from_dict()`/`duplicate_level()`), field + one-liners in `LevelVisualState`'s `from_level_data()`, `apply_to_level_data()`, `copy()`, `to_broadcast_dict()`, and `patch_from_broadcast_dict()` (`resources/level_visual_state.gd`), one apply line in `LevelPlayController.apply_visual_state()`, a `PropertyRow` in the matching pane plus its `load_state`/`write_state` lines; give the row `hint_low`/`hint_high` and a `formatter` when the unit is not obvious. If the property must survive a late join, also update `NetworkManager._patch_current_level_dict()`. About 6 edits total — see `resources/level_visual_state.gd`'s header comment for the same recipe in code
- **Level editor**: Supports undo/redo (`Ctrl+Z`/`Ctrl+Y`) and autosave (30s interval, recovery on startup)

## Documentation

After making architectural or API changes, update the relevant documentation. Check the **Essential Reading** table above for which doc covers each area. Common triggers:

- **New or changed API** (functions, signals, autoloads) – update `docs/ARCHITECTURE.md` and this file's Key Conventions
- **Scene tree changes** (new nodes, reparenting) – update the Scene Hierarchy in `docs/ARCHITECTURE.md`
- **Asset/model loading changes** – update `docs/ASSET_MANAGEMENT.md`
- **UI system changes** – update `docs/UI_SYSTEMS.md`
- **Environment/lighting/weather changes** – update `docs/lighting-and-environment.md`
- **New conventions or patterns** – update this file (`AGENTS.md`) and `.cursor/rules/project-overview.mdc`
- **New gotchas or coding patterns** – update `docs/CONVENTIONS.md`
- **New RPC or network patterns** – update `docs/CONVENTIONS.md` and `docs/NETWORKING.md`
- **Measure tool or gameplay tool changes** – update `docs/ARCHITECTURE.md` (Scale & Measurement / Measure Tool / Grid Overlay / Drag Ruler sections) and `docs/UI_SYSTEMS.md` (Measure Tool / Grid Overlay / Drag Ruler sections)
- **Grid overlay or snap changes** – update `docs/ARCHITECTURE.md` (Grid Overlay / Grid-Snapped Movement sections) and `docs/UI_SYSTEMS.md` (Grid Overlay section)

## Formatting

After editing files, run the appropriate formatter so output matches project style. See `.cursor/rules/formatting.mdc`.

- **GDScript**: `gdformat path/to/file.gd` (from `pip install gdtoolkit`)
- **Lint GDScript**: `gdlint path/to/file.gd`

## Testing

- **Unit tests** – GUT framework (`addons/gut/`), configured in `tests/.gutconfig.json`. Test files in `tests/unit/` with `test_` prefix.
- **Integration test scenes** – Runnable with F6 in Godot editor: `tests/test_glb_lights.tscn`, `tests/test_play_level.tscn`, `tests/test_client_waiting.tscn`

### Running tests from the CLI

`godot` must be on PATH (bash wrapper at `~/.local/bin/godot` pointing to the local install).

**Run all unit tests (headless):**
```
godot --headless --path . --script res://addons/gut/gut_cmdln.gd -- -gconfig=tests/.gutconfig.json
```

**After a fresh clone or when new `class_name` scripts are added**, run the import step first (required once):
```
godot --headless --import --path .
```
Then run tests normally.

**After any batch of file renames/deletions** (e.g. an agent-driven refactor moving code between
files), run the import step again before reopening the editor, even if nothing new needs
registering. `.godot/` (gitignored, local-only) caches UIDs and editor session state; if it drifts
from what's on disk you'll see spurious `Unrecognized UID` or `Cannot load shader/script`
errors on next editor launch for files that were renamed or deleted. These are cache staleness,
not real bugs -- reimporting resyncs the cache. If they persist, delete the `.godot/` folder
entirely (safe, fully regenerated) and reimport. Prefer closing the GUI editor before a large
agent-driven restructuring pass and reopening it after, rather than leaving it open while files
change underneath it.

**Check for GDScript compilation errors** (loads the project, reports all parse/compile errors, exits):
```
godot --headless --path . --quit-after 1
```
Filter to just errors: pipe output through `grep -E "ERROR:|SCRIPT ERROR:"`.

**Lint a file:**
```
gdlint path/to/file.gd
```

### Headless testing cannot verify real rendering output

`--headless` runs Godot's dummy rendering driver, which accepts rendering-server
calls without error but cannot produce real pixels or reliably round-trip certain
GPU-resource state. Confirmed via direct probe: `MultiMesh.set_instance_transform()`
succeeds with no error under `--headless`, but `MultiMesh.get_instance_transform()`
always reads back an *identity* transform afterward, regardless of what was set --
reproduced with zero scene tree involvement at all, so it's not something caller
code can work around. If a GUT test needs to assert on a `MultiMesh`'s actual
per-instance transform values, don't round-trip through the `MultiMesh` API at all
-- isolate the pure transform-computing logic into its own function and test that
directly (see `ScatterGlbUtils._row_to_transform` and its tests in
`tests/unit/test_glb_utils_scatter_instances.gd` for the pattern, and
`MeshInstancingUtils.transform_relative_to`, which is public for exactly this reason).

More generally, if a bug report describes something that *should* be visible not
rendering (invisible geometry, wrong material, etc.), a headless GUT test that only
checks node/resource *existence* (right node type, right instance count, right mesh
assigned) can pass while the actual rendered result is still broken -- it proves the
data pipeline is wired correctly, not that anything is visible. To actually see
whether something renders, run a real scene non-headlessly and capture a screenshot:

```gdscript
# minimal probe pattern -- a Node3D script + matching .tscn, run via:
#   godot --path . res://path/to/probe.tscn
func _ready() -> void:
	# ... build/load the scene under test, add camera/light/WorldEnvironment ...
	pass

func _process(_delta: float) -> void:
	frames_waited += 1
	if frames_waited == 10:  # let a few real frames render first
		get_viewport().get_texture().get_image().save_png("user://probe_render.png")
		get_tree().quit(0)
```

This is how a real "textures baked correctly but scattered instances still render
completely invisible in-game" bug was actually root-caused (2026-08-05, see
terrain-paint's `CLAUDE.md` "Scatter Instances" section for the Blender-side half of
the story): headless checks confirmed the `MultiMeshInstance3D` was built with the
right instance count and mesh, but only a real Vulkan/Forward+ render -- comparing
the exact mesh+material against a forced-opaque copy of the same mesh side by side
-- revealed the real material was rendering nothing at all, isolating the bug to
material/UV handling rather than the instancing mechanism. `Camera3D.look_at()`
requires the camera to already be `is_inside_tree()`; use
`look_at_from_position(pos, target, up)` instead when building a probe scene
programmatically, since it doesn't have that requirement and works immediately
after construction.

Camera-view screenshots taken this way land under `user://` -- Godot's app-data
directory for this project (`%APPDATA%\Godot\app_userdata\TTSim\` on Windows), not
inside the repo -- so they're safe to leave behind but won't show up in `git status`
either way. Delete throwaway probe `.gd`/`.tscn` files (and their `.uid` sidecars)
from `tests/unit/` once done; they're not real tests and shouldn't be committed.

## Validation Bridge (MCP)

An MCP server that lets agents launch the game, interact with it, capture screenshots, query state, and validate code changes without human intervention. Registered as `tt-sim-validator` in Claude Code.

### When to Use

After making code changes that affect runtime behavior or visuals, use the validation tools to verify the change works. The workflow:

1. **After any code edit**: call `game_reload` to restart with new code
2. **Check for errors**: call `game_state` — look at `console_errors` for crashes
3. **Freeze the clock**: call `game_time` with `freeze` before driving anything. A frozen game
   cannot race your interaction, and screenshots show a settled world rather than whatever the
   renderer had mid-frame
4. **Find what to click**: call `game_controls`, then `game_click_control` by name. Only fall back
   to `game_click` with raw coordinates for 3D world clicks, which have no Control to name
5. **Advance deliberately**: call `game_time` with `step_until` and the condition you are actually
   waiting for, or `step` for an exact slice. Use `game_wait` only for real-time waits that game
   time cannot express
6. **Evaluate**: `game_screenshot`, `game_state`, and `game_eval` for anything the fixed state
   snapshot does not report
7. **Resume and stop**: `game_time` with `resume`, then `game_stop`. Idle instances waste resources
   and throttle later measurement runs

### Available Tools

| Tool | Purpose |
|------|---------|
| `game_launch` | Start Godot with the validation bridge. Call this first. Optional `scene` parameter for a specific scene |
| `game_stop` | Kill the running Godot instance |
| `game_reload` | Stop and relaunch. Use after code changes |
| `game_screenshot` | Capture the game window as PNG image |
| `game_state` | Query game state: app state, tokens, UI panels, camera, scene tree, console errors, plus `frozen` and `time_scale` |
| `game_click` | Click at (x, y) window coords (same space as `game_screenshot` pixels). Optional `button`: "left" (default), "right", "middle" |
| `game_drag` | Drag from (x1, y1) to (x2, y2) with interpolated motion |
| `game_key` | Press a key by name (e.g. "M", "Escape", "Home", "Space", "G"), or a modifier chord (e.g. "Ctrl+Z", "Shift+Alt+F") |
| `game_scroll` | Mouse wheel at (x, y). Positive delta = zoom in, negative = zoom out |
| `game_wait` | Wait N seconds for animations/transitions to settle |
| `game_interact` | **Preferred for multi-step validation.** Execute a sequence of actions and return collected screenshots + state in one call |
| `game_time` | Deterministic time control: `freeze`, `step`, `step_until`, `resume`. Prefer over `game_wait` |
| `game_eval` | Evaluate a GDScript expression against the current scene and return the value |
| `game_controls` | List Controls (max 200, with a `truncated` flag) with viewport-space rect and centre. Sees dialogs parented to the window root |
| `game_click_control` | Click a Control by name, path, or button text. The bridge converts canvas space to window space, so the caller does no coordinate math |

### game_interact Example

Instead of making 10 tool calls, send one batch:

```json
{
  "steps": [
    {"action": "click", "x": 960, "y": 540},
    {"action": "wait", "seconds": 0.5},
    {"action": "key", "key": "M"},
    {"action": "wait", "seconds": 0.3},
    {"action": "screenshot"},
    {"action": "state"}
  ]
}
```

Returns all screenshots and the final state in one response.

### game_state Response

```json
{
  "ok": true,
  "app_state": "PLAYING",
  "tokens": [
    {"network_id": "abc", "name": "Goblin", "position": {"x": 1, "y": 0, "z": 2}, "visible": true, "health": 30, "max_health": 30, "alive": true}
  ],
  "ui": {
    "PlayerListDrawer": {"open": false},
    "LevelEditPanel": {"open": true}
  },
  "camera": {"position": {"x": 5, "y": 0, "z": 5}, "zoom": 8.0},
  "scene_tree": {"name": "Root", "type": "Node3D", "children": [...]},
  "console_errors": []
}
```

Use `app_state` to verify scene transitions worked. Use `tokens` to verify token operations. Use `console_errors` to catch runtime errors.

### Validation Levels

1. **Smoke test** (always do this): `game_reload` + `game_state` — catches compile errors and crashes
2. **Targeted interaction**: reason about what you changed and exercise that feature
3. **Acceptance criteria**: if the task specifies expected behavior, verify with screenshots + state

### What You Can vs. Cannot Catch

**Can catch**: crashes, missing UI, wrong colors (bold), features not responding to input, state corruption, layout obviously wrong, state that only settles after N frames (via `step_until`)

**Cannot catch reliably**: subtle animation timing, 1px alignment, slight color shades, performance regressions, drag interaction "feel", anything requiring a second game instance (multiplayer sync)

### Architecture

```
Agent → MCP Server (TypeScript, tools/mcp/) → TCP localhost:7777 → Validation Bridge (GDScript autoload, addons/validation_bridge/)
```

The bridge only activates when Godot is launched with `-- --validation-bridge`. Normal gameplay, editor play, and release builds are unaffected.

### Troubleshooting

- **"Game is not running"**: call `game_launch` first
- **Launch timeout**: check that `godot` is on PATH, or set `GODOT_PATH` env var
- **Bridge not connecting**: port 7777 may be in use from a previous session. `game_stop` then `game_launch`
- **Stale errors after reload**: `console_errors` accumulates since launch. Check timestamps/context
- **Clicks land on nothing / buttons do not react**: almost always a coordinate-space mismatch, not a broken bridge. `game_state` reports `viewport.window_size`, `viewport.viewport_size` and `viewport.hovered_control` — check `hovered_control` after a click to confirm what you actually hit before concluding anything else. `game_click_control` avoids this problem — the bridge converts the Control's canvas-space centre into window space with `get_viewport().get_final_transform()` before injecting, so the caller does no coordinate math — and is the right default; reach for `game_click` with raw coordinates only for 3D world clicks. (This conversion was missing until it was measured: `click_control` used to inject the unconverted centre, miss the Control, and still answer `{"ok": true}`, because it only ever checked that it had *found* the Control. Verify with `hovered_control` if a named click ever looks wrong.)
- **Viewport size**: `project.godot` sets a 1920x1080 base with `window/stretch/aspect="expand"`, so the viewport is NOT a fixed size — its height is `1920 / window_aspect`. A 1278x1360 window gives a 1920x2043 viewport, which quietly quadruples fill cost and invalidates any FPS number taken that way
- **Click coordinates and screenshots are both WINDOW pixels, not VIEWPORT pixels.** Under this project's normal `aspect="expand"` config the two already coincide, so no conversion is needed between a screenshot and a `game_click`/`game_drag`/`game_scroll` call. The exception is an `override.cfg` forcing `aspect="keep"`: a 1920x1080 viewport inside a 1278x1360 window is then letterboxed — scale 0.6656 with ~320px black bars top and bottom, so screenshot `(x, y)` becomes window `(x, y + 320)`. Read both sizes from `game_state` and convert in that case, or you will click empty space and conclude the bridge is broken. `game_click`, `game_drag` and `game_scroll` pass the caller's coordinates to the injector untouched, so that conversion (when needed) is on the caller — but it is no longer the only option: `game_click_control` does the conversion for you for anything that is a named Control, and is the reason to prefer it
- **A click "not working" may have worked**: `app_state` only changes on real state transitions, and `_get_scene_tree()` walks `get_tree().current_scene`, so anything parented to `get_tree().root` (dialogs, including the level browser) is invisible to it. `game_controls` is not blind to the window root, so it is the way to check whether a dialog actually opened; take a screenshot too before concluding a click failed
- **Bridge commands time out after 30 s**, except `step` and `step_until`, which get a budget derived from the frames they may run (the bridge's cap of 6000 frames is ~100 real seconds). A timed-out command is not cancelled on the bridge — it finishes and answers late — so the client discards that late reply rather than matching it to whatever request is outstanding by then. The protocol has no request ids; this keeps the stream aligned but is not a substitute for them
- **A freeze does not survive a disconnect.** The bridge resumes normal time when its client goes away, so a crashed or timed-out agent cannot leave the game stopped for the next one. `game_state` reports `frozen` and `time_scale`, so check those first when nothing appears to move
- **The pause menu IS testable.** `Escape` used to appear to hang the bridge, because `scenes/root.gd` sets `get_tree().paused = true` and that stopped `_process` on the bridge autoload. It now runs with `PROCESS_MODE_ALWAYS`, so pressing `Escape` and driving the pause menu and Settings screen works normally. If a future autoload needs to stay live while paused, it needs the same process mode
- **Token drags are still unreliable, and the cause is not isolated.** `_inject_drag` had a real flush asymmetry — it never called `Input.flush_buffered_events()` — and that has been corrected. But three separate 10-iteration measurements in `res://tests/test_play_level.tscn` all came back 0/10: before the flush fix, after it, and again with the full freeze-plus-stepping stack and no fixed waits. The flush fix did not move the number. Do not assume the root cause is understood, and do not treat a single failed drag as proof the agent's coordinates were wrong. Separately, project memory records roughly 1-in-5 to 1-in-8 success historically against the real PLAYING scene driven through MCP — a different context (real scene, not the test scene) from the 0/10 runs above, so neither number should be read onto the other
- **`game_wait` ignores the time scale**, so it still works while the game is frozen — but a frozen game does not advance during it, so nothing happens. Use `game_time` with `step` when game time actually needs to pass
- **`step` only guarantees `_physics_process` state.** A step advances an exact number of physics frames, so anything driven by `_physics_process` advances exactly and repeatably. State driven by `_process` (camera smoothing, `_process`-based tweens) advances by however much wall-clock those frames happened to consume, and is NOT frame-rate independent even under `step`. It is still far more controlled than a bare `game_wait`, just not exact for `_process`-driven state
- **`game_controls` returns at most 200 Controls and says so.** The response carries a `truncated` boolean; when it is `true` the walk hit the cap, and a control you cannot find may be past the cap rather than absent from the scene. Narrow the search (`visibleOnly`) or use `game_click_control`, which matches by name/path/text rather than requiring you to spot the entry
- **Injected clicks cannot reach `OptionButton` popup menu items.** The popup is a Godot `PopupMenu`, which is a `Window`, not a `Control` — `game_controls` cannot see its entries and `game_click_control` cannot click them. Drive the popup with `game_key` (arrow keys, then Enter) instead. Note also that the popup drops the first keypress and resets to index 0 every time it opens
- **`game_eval` runs against the current scene, not the tree root.** Bare autoload names do not resolve — use `get_node("/root/GameState")` instead of `GameState`. `find_child` also needs `find_child("Name", true, false)` to see nodes added without an owner, which includes `GameMap`
- **`game_eval` cannot reach Godot engine singletons.** It evaluates the expression through `Expression`, which does not resolve global singletons like `Input` — an expression referencing `Input` fails to parse/resolve. Project autoloads are still reachable via `get_node("/root/<Autoload>")` as above; a true engine singleton (`Input`, `Engine`, etc.) is simply unavailable through `game_eval`

## CI/CD

- **GitHub Actions** – `.github/workflows/build.yml` exports Windows, macOS, and Linux builds on push to `main` or version tags (`v*`). Uses `barichello/godot-ci:4.6` container.
- **Releases** – Tagged pushes (`v*`) create GitHub releases with build artifacts. `UpdateManager` checks for new releases and prompts in-app updates.
- **Versioning rule** – `project.godot config/version` is the single source of truth. It always holds the version being worked *toward*, not the one last shipped. CI reads it for every build; for tagged builds it validates the tag matches and fails the build if not.
- **Cutting a release** – Ensure `project.godot config/version` is set to the intended release version (e.g. `0.1.2`). Tag: `git tag v0.1.2 && git push origin v0.1.2`. CI validates tag == project.godot version. **Immediately after**: bump `project.godot` to the next version (e.g. `0.1.3`) and push — this ensures subsequent builds are correctly versioned as pre-releases of `0.1.3`.
- **Hotfixes** – Branch from the release tag, apply the fix, tag a patch release (e.g. `v0.1.2.1`), then merge the fix back to main if applicable.

## File Layout

```
autoloads/                  # Singletons, static class_name scripts, and facade sub-components
resources/                  # Custom Resource classes (LevelData, TokenState, TokenPlacement, TokenConfig, AssetPack)
scenes/                     # States, board_token, effects, level_editor, level_loader, ui
utils/                      # GlbUtils, SerializationUtils, EnvironmentPresets, TabUtils
shaders/                    # GLSL shaders (lo-fi, occlusion fade, selection glow)
themes/                     # dark_theme.gd → generated/dark_theme.tres
tests/                      # GUT unit tests + runnable test scenes (F6 in editor)
tools/                      # Python scripts (audio normalization, hooks, manifest generation)
tools/mcp/                  # TypeScript MCP server for agent validation bridge
addons/validation_bridge/   # GDScript autoload for in-game validation (TCP server)
data/                       # Static data files (pokemon.json)
docs/                       # Authoritative documentation
assets/                     # Audio, icons, models, maps
.github/                    # CI/CD workflows
.cursor/rules/              # Cursor IDE rules for AI agent guidance
```
