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

## Tech Stack

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Physics**: Jolt Physics
- **Renderer**: Forward Plus
- **Networking**: Netfox + Noray (NAT punchthrough)

## Key Conventions

- **No EventBus** – Use direct signal connections or autoload services
- **State stack** – Root manages states: `change_state()`, `push_state()`, `pop_state()`
- **Autoloads** – UIManager, LevelManager, AssetPackManager, NetworkManager, Constants, etc. (see project.godot). Always reference autoloads directly (e.g. `AssetPackManager.method()`), never via `has_node("/root/X")` or `get_node("/root/X")`
- **Shared constants** – Use `Constants.LOFI_DEFAULTS`, `Constants.NETWORK_TRANSFORM_UPDATE_INTERVAL`, etc. for values shared across files. Add file-local constants for single-file magic numbers
- **Map loading** – Use `GlbUtils.load_map_async()` (or `load_map()` sync) for maps; handles both `res://` and `user://` paths with full post-processing
- **GLB loading** – Use `GlbUtils.load_glb_with_processing_async()` for non-map GLBs (tokens use `AssetPackManager` instead)
- **Models** – Use `AssetPackManager.get_model_instance()` for cached model loading
- **Signal cleanup** – Disconnect autoload signals in `_exit_tree()` for non-autoload nodes. Use `CONNECT_ONE_SHOT` for transient signals
- **Process optimization** – Use `set_process(false)` in `_ready()` and toggle on/off when needed, to avoid unnecessary per-frame work
- **UIDs** – Godot `.uid` files are auto-generated; avoid manual edits

## Adding Features

- **New state**: Add to `Root.State` enum, implement `_enter_*_state()` / `_exit_*_state()`
- **New autoload**: Create in `autoloads/`, register in `project.godot`
- **New UI panel (in-scene)**: Extend `AnimatedVisibilityContainer`, register with `UIManager.register_overlay()` for ESC handling
- **New UI overlay (full-screen dialog)**: Extend `AnimatedCanvasLayerPanel`, override `_on_panel_ready()` for setup
- **New level/token logic**: See LevelPlayController, BoardTokenFactory, GameState
- **Level editor**: Supports undo/redo (`Ctrl+Z`/`Ctrl+Y`) and autosave (30s interval, recovery on startup)

## Documentation

After making architectural or API changes, update the relevant documentation. Check the **Essential Reading** table above for which doc covers each area. Common triggers:

- **New or changed API** (functions, signals, autoloads) – update `docs/ARCHITECTURE.md` and this file's Key Conventions
- **Scene tree changes** (new nodes, reparenting) – update the Scene Hierarchy in `docs/ARCHITECTURE.md`
- **Asset/model loading changes** – update `docs/ASSET_MANAGEMENT.md`
- **UI system changes** – update `docs/UI_SYSTEMS.md`
- **New conventions or patterns** – update this file (`AGENTS.md`) and `.cursor/rules/project-overview.mdc`

## Formatting

After editing files, run the appropriate formatter so output matches project style. See `.cursor/rules/formatting.mdc`.

- **GDScript**: `gdformat path/to/file.gd` (from `pip install gdtoolkit`)
- **Lint GDScript**: `gdlint path/to/file.gd`

## File Layout

```
autoloads/     # Singletons
resources/     # Custom Resource classes (LevelData, TokenState, etc.)
scenes/        # States, board_token, level_editor, ui
utils/         # GlbUtils, environment_presets
themes/        # dark_theme.gd, theme variants
tests/         # Runnable test scenes (F6 in editor)
docs/          # Authoritative documentation
```
