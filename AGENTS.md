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
- **Autoloads** – UIManager, LevelManager, AssetManager, NetworkManager, EventBus, GameState, NetworkStateSync, AudioManager, UpdateManager, InputProfile (see project.godot). Always reference autoloads directly (e.g. `AssetManager.method()`), never via `has_node("/root/X")` or `get_node("/root/X")`
- **Shared constants** – Use `Constants.LOFI_DEFAULTS`, `Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL`, etc. for values shared across files. Use `Paths.SETTINGS_PATH` for the settings file path (never hardcode `"user://settings.cfg"`). Add file-local constants for single-file magic numbers
- **Map loading** – Use `GlbUtils.load_map_async()` (or `load_map()` sync) for maps; handles both `res://` and `user://` paths with full post-processing
- **GLB loading** – Use `GlbUtils.load_glb_with_processing_async()` for non-map GLBs (tokens use `AssetManager` instead)
- **Models** – Use `AssetManager.get_model_instance()` for cached model loading
- **Signal cleanup** – Disconnect autoload signals in `_exit_tree()` for non-autoload nodes. Always guard with `is_connected()` before disconnecting. Use `CONNECT_ONE_SHOT` for transient signals. Guard `call_deferred()` callbacks with `is_instance_valid(self)`. See `docs/CONVENTIONS.md` for full patterns
- **Process optimization** – Call `set_process(false)` / `set_physics_process(false)` in `_ready()` unless the node needs to tick immediately. Toggle on when work begins, off when idle. Same for `_physics_process()`. This avoids unnecessary per-frame overhead
- **UIDs** – Godot `.uid` files are auto-generated; avoid manual edits
- **CanvasLayer ordering** – Layer numbers are centralized in `Constants` (`LAYER_*`). Check screen region comments before adding UI to avoid overlaps. See `.cursor/rules/canvas-layers.mdc`
- **mouse_filter** – Set `mouse_filter = IGNORE` on pure layout containers (`Control`, `MarginContainer`, `HBoxContainer`, etc.). Only interactive controls and modal backdrops should keep the default `STOP`
- **Weather effects** – `WeatherRenderer` (`scenes/effects/weather_renderer.gd`) provides combinable visual weather (rain, snow, wind particles + fog overlay). Intensities stored in `LevelData.weather_overrides`. Created per level load in the SubViewport via `GameMap.setup_weather()`, freed via `GameMap.clear_weather()`. UI sliders in `LevelEditPanel` Weather section. See `docs/lighting-and-environment.md` Weather Effects section
- **Environment system** – Environment settings use a layering model: `PROPERTY_DEFAULTS` → map defaults → named preset → user overrides. See `docs/lighting-and-environment.md`. Key points:
  - `LevelData.environment_preset` defaults to `""` (empty = use map defaults)
  - Map defaults are extracted at load time, never baked into `level_data`
  - Use `EnvironmentPresets.apply_to_world_environment()` with `map_defaults` parameter
  - Embedded `WorldEnvironment` nodes are stripped from maps after extraction
  - Blender-exported `.glb` maps carry ambient light via glTF scene-level `extras`
    instead (see `GlbUtils.extract_lighting_config()`), since glTF has no
    `WorldEnvironment` equivalent
- **Settings persistence** – Each system reads/writes its own section in `Paths.SETTINGS_PATH` (`user://settings.cfg`). Always check `ConfigFile.load()` return value before overwriting — ignore `ERR_FILE_NOT_FOUND` but warn on other errors. See `docs/CONVENTIONS.md` Settings Persistence
- **In-game editing** – `LevelEditPanel` (extends `DrawerContainer`, right edge) provides real-time editing during gameplay (map, lighting, environment, post-processing, weather). `GameplayMenuController` routes changes to `LevelPlayController`. Cancel reverts; save persists to disk
- **Scale convention** – 1 world unit = 1 meter (glTF standard). `LevelData.grid_cell_size` adapts meters to game units. Use `ScaleUtils` for all distance conversion and formatting
- **Measure tool** – `MeasureTool` (Node child of GameMap) provides distance measurement. Renders 2D on `LAYER_MEASURE_OVERLAY` (layer 8) to stay crisp above the lo-fi shader. M key toggles. Disables token dragging while active. Input routed through `GameMap._input()` with GUI click guard. Tab cycles mode: Line → Sphere → Cylinder → Line. VolumeOverlay (child of MeasureTool, created in setup()) renders 3D wireframe + transparent fill inside the SubViewport, plus a 2D label. Tabbing from a line waypoint uses that point as the volume center.
- **Grid overlay** – `GridOverlay` (MeshInstance3D child of Camera3D inside SubViewport) projects a procedural grid via depth-buffer shader. Uses cell tint (theme `color_surface1` at 65% with 10% inset) instead of grid lines for readability on bright maps. Height filter (`grid_y_level`/`grid_y_tolerance`) prevents projection onto tokens. Animated fade in/out (0.2s). G key toggles (local per-client). Auto-shows during measure tool and token drag (configurable via `LevelData`). Managed by `GameMap`
- **Grid snap** – `DragAndDrop3D` snaps to grid cell centers when `grid_snap_enabled = true`. Hold Shift for free move override. Configured from `LevelData` via `GameMap.configure_grid()`
- **Drag ruler** – `DragRuler` (Node child of GameMap) shows movement distance during token drag. Renders 2D on `LAYER_DRAG_RULER` (layer 7). Activates/deactivates via DragAndDrop3D signals. Uses `MapOverlayUtils` for 2D overlay boilerplate
- **MapOverlayUtils** – Shared factory for creating CanvasLayer/Control overlays and styled label panels. Used by both `MeasureTool` and `DragRuler`

## Adding Features

- **New state**: Add to `Root.State` enum, implement `_enter_*_state()` / `_exit_*_state()`
- **New autoload**: See `.cursor/rules/autoloads-and-globals.mdc` for the decision flowchart. Only create an autoload for a true service with runtime state. Pure constants/utilities should be `class_name` static classes. Implementation details of existing systems should be facade sub-components
- **New UI panel (in-scene)**: Extend `AnimatedVisibilityContainer`, register with `UIManager.register_overlay()` for ESC handling
- **New UI overlay (full-screen dialog)**: Extend `AnimatedCanvasLayerPanel`, override `_on_panel_ready()` for setup
- **New slide-out drawer**: Extend `DrawerContainer`, configure `edge`, `drawer_width`, `tab_text` in `_on_ready()`
- **New level/token logic**: See LevelPlayController, BoardTokenFactory (tokens MUST be created via factory), GameState, TokenPermissions
- **New RPC**: Follow conventions in `docs/CONVENTIONS.md` — `@rpc` with `_rpc_` prefix, use `Array` not `Vector3` for parameters, emit signals from RPC methods
- **New environment preset**: Add to `EnvironmentPresets.PRESETS` in `utils/environment_presets.gd`
- **New environment property**: Add to `PROPERTY_DEFAULTS`, update `_apply_config_to_environment()`, `extract_from_environment()`, and `LevelEditPanel` controls
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

## Validation Bridge (MCP)

An MCP server that lets agents launch the game, interact with it, capture screenshots, query state, and validate code changes without human intervention. Registered as `tt-sim-validator` in Claude Code.

### When to Use

After making code changes that affect runtime behavior or visuals, use the validation tools to verify the change works. The workflow:

1. **After any code edit**: call `game_reload` to restart with new code
2. **Check for errors**: call `game_state` — look at `console_errors` for crashes
3. **Exercise the feature**: call `game_interact` with a sequence of inputs
4. **Evaluate visually**: call `game_screenshot` and inspect the result
5. **If broken**: fix the code and repeat from step 1

### Available Tools

| Tool | Purpose |
|------|---------|
| `game_launch` | Start Godot with the validation bridge. Call this first. Optional `scene` parameter for a specific scene |
| `game_stop` | Kill the running Godot instance |
| `game_reload` | Stop and relaunch. Use after code changes |
| `game_screenshot` | Capture viewport as PNG image |
| `game_state` | Query game state: app state, tokens, UI panels, camera, scene tree, console errors |
| `game_click` | Click at (x, y) viewport coords. Optional `button`: "left" (default), "right", "middle" |
| `game_drag` | Drag from (x1, y1) to (x2, y2) with interpolated motion |
| `game_key` | Press a key by name (e.g. "M", "Escape", "Home", "Space", "G") |
| `game_scroll` | Mouse wheel at (x, y). Positive delta = zoom in, negative = zoom out |
| `game_wait` | Wait N seconds for animations/transitions to settle |
| `game_interact` | **Preferred for multi-step validation.** Execute a sequence of actions and return collected screenshots + state in one call |

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

**Can catch**: crashes, missing UI, wrong colors (bold), features not responding to input, state corruption, layout obviously wrong

**Cannot catch reliably**: subtle animation timing, 1px alignment, slight color shades, performance regressions, drag interaction "feel"

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
- **Viewport size**: defaults to project settings (1920x1080). Screenshot coordinates use viewport pixels

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
