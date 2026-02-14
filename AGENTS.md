# TTSim – Agent Quick Reference

**TTSim** is a Godot 4.6 tabletop simulator (GDScript). This file helps AI agents understand the project quickly.

## Essential Reading

| Document | Purpose |
|----------|---------|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Project structure, state management, autoloads, systems |
| [docs/README.md](docs/README.md) | Quick start, common API usage |
| [docs/THEME_GUIDE.md](docs/THEME_GUIDE.md) | UI theme variants, typography, colors |
| [docs/UI_SYSTEMS.md](docs/UI_SYSTEMS.md) | UIManager, dialogs, toasts, overlays |
| [docs/ASSET_MANAGEMENT.md](docs/ASSET_MANAGEMENT.md) | Asset packs, model loading, caching |
| [docs/SOUND_EFFECTS.md](docs/SOUND_EFFECTS.md) | Audio files, wiring, normalization, adding new sounds |
| [docs/NETWORKING.md](docs/NETWORKING.md) | Multiplayer, Noray, state sync |
| [docs/lighting-and-environment.md](docs/lighting-and-environment.md) | Environment presets, map defaults, sky, in-game editing |
| [docs/CONVENTIONS.md](docs/CONVENTIONS.md) | RPC patterns, signal cleanup, token hierarchy, camera, settings, gotchas |

## Tech Stack

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Physics**: Jolt Physics
- **Renderer**: Forward Plus
- **Networking**: Netfox + Noray (NAT punchthrough)

## Key Conventions

- **EventBus** – `EventBus` is a small autoload with cross-system signals (`pause_requested`, `play_level_requested`, `state_changed`, `player_disconnected`, etc.). Use it only for signals that genuinely span system boundaries. Prefer direct signal connections for parent-child communication and autoload services for global operations
- **State stack** – Root manages states: `change_state()`, `push_state()`, `pop_state()`
- **Static classes** – `Constants`, `Paths`, `NodeUtils`, `TokenPermissions`, `SerializationUtils`, and `EnvironmentPresets` are `class_name` scripts (not autoloads). They provide globally accessible constants and static utility functions without a Node in the tree
- **Autoloads** – UIManager, LevelManager, AssetManager, NetworkManager, EventBus, GameState, NetworkStateSync, AudioManager, UpdateManager (see project.godot). Always reference autoloads directly (e.g. `AssetManager.method()`), never via `has_node("/root/X")` or `get_node("/root/X")`
- **Shared constants** – Use `Constants.LOFI_DEFAULTS`, `Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL`, etc. for values shared across files. Add file-local constants for single-file magic numbers
- **Map loading** – Use `GlbUtils.load_map_async()` (or `load_map()` sync) for maps; handles both `res://` and `user://` paths with full post-processing
- **GLB loading** – Use `GlbUtils.load_glb_with_processing_async()` for non-map GLBs (tokens use `AssetManager` instead)
- **Models** – Use `AssetManager.get_model_instance()` for cached model loading
- **Signal cleanup** – Disconnect autoload signals in `_exit_tree()` for non-autoload nodes. Always guard with `is_connected()` before disconnecting. Use `CONNECT_ONE_SHOT` for transient signals. See `docs/CONVENTIONS.md` for full patterns
- **Process optimization** – Use `set_process(false)` in `_ready()` and toggle on/off when needed, to avoid unnecessary per-frame work
- **UIDs** – Godot `.uid` files are auto-generated; avoid manual edits
- **CanvasLayer ordering** – Layer numbers are centralized in `Constants` (`LAYER_*`). Check screen region comments before adding UI to avoid overlaps. See `.cursor/rules/canvas-layers.mdc`
- **mouse_filter** – Set `mouse_filter = IGNORE` on pure layout containers (`Control`, `MarginContainer`, `HBoxContainer`, etc.). Only interactive controls and modal backdrops should keep the default `STOP`
- **Environment system** – Environment settings use a layering model: `PROPERTY_DEFAULTS` → map defaults → named preset → user overrides. See `docs/lighting-and-environment.md`. Key points:
  - `LevelData.environment_preset` defaults to `""` (empty = use map defaults)
  - Map defaults are extracted at load time, never baked into `level_data`
  - Use `EnvironmentPresets.apply_to_world_environment()` with `map_defaults` parameter
  - Embedded `WorldEnvironment` nodes are stripped from maps after extraction
- **In-game editing** – `LevelEditPanel` (extends `DrawerContainer`, right edge) provides real-time editing during gameplay. `GameplayMenuController` routes changes to `LevelPlayController`. Cancel reverts; save persists to disk

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
- **Environment/lighting changes** – update `docs/lighting-and-environment.md`
- **New conventions or patterns** – update this file (`AGENTS.md`) and `.cursor/rules/project-overview.mdc`
- **New gotchas or coding patterns** – update `docs/CONVENTIONS.md`
- **New RPC or network patterns** – update `docs/CONVENTIONS.md` and `docs/NETWORKING.md`

## Formatting

After editing files, run the appropriate formatter so output matches project style. See `.cursor/rules/formatting.mdc`.

- **GDScript**: `gdformat path/to/file.gd` (from `pip install gdtoolkit`)
- **Lint GDScript**: `gdlint path/to/file.gd`

## Testing

- **Unit tests** – GUT framework, configured in `tests/.gutconfig.json`. Test files in `tests/unit/` with `test_` prefix.
- **Integration test scenes** – Runnable with F6 in Godot editor: `tests/test_glb_lights.tscn`, `tests/test_play_level.tscn`, `tests/test_client_waiting.tscn`
- **Run unit tests**: In Godot editor, open the GUT panel and click Run All. Or from CLI if the GUT command-line runner is configured.

## CI/CD

- **GitHub Actions** – `.github/workflows/build.yml` exports Windows and macOS builds on push to `main` or version tags (`v*`). Uses `barichello/godot-ci:4.6` container.
- **Releases** – Tagged pushes (`v*`) create GitHub releases with build artifacts. `UpdateManager` checks for new releases and prompts in-app updates.

## File Layout

```
autoloads/     # Singletons, static class_name scripts, and facade sub-components
resources/     # Custom Resource classes (LevelData, TokenState, TokenPlacement, TokenConfig, AssetPack)
scenes/        # States, board_token, level_editor, level_loader, ui
utils/         # GlbUtils, SerializationUtils, EnvironmentPresets, TabUtils
shaders/       # GLSL shaders (lo-fi, occlusion fade, selection glow)
themes/        # dark_theme.gd → generated/dark_theme.tres
tests/         # GUT unit tests + runnable test scenes (F6 in editor)
tools/         # Python scripts (audio normalization, hooks, manifest generation)
data/          # Static data files (pokemon.json)
docs/          # Authoritative documentation
assets/        # Audio, icons, models, maps
.github/       # CI/CD workflows
.cursor/rules/ # Cursor IDE rules for AI agent guidance
```
