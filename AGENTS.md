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
- **Autoloads** – UIManager, LevelManager, AssetPackManager, NetworkManager, etc. (see project.godot)
- **GLB loading** – Use `GlbUtils.load_glb_async()` and `GlbUtils.process_collision_meshes()` / `process_animations()`
- **Models** – Use `AssetPackManager.get_model_instance()` for cached model loading
- **UIDs** – Godot `.uid` files are auto-generated; avoid manual edits

## Adding Features

- **New state**: Add to `Root.State` enum, implement `_enter_*_state()` / `_exit_*_state()`
- **New autoload**: Create in `autoloads/`, register in `project.godot`
- **New UI panel**: Extend `AnimatedVisibilityContainer`, register with `UIManager.register_overlay()` for ESC handling
- **New level/token logic**: See LevelPlayController, BoardTokenFactory, GameState

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
