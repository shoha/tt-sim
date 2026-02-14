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

## Key Gotchas

- **Autoload references**: Always use direct names (`AssetManager.method()`), never `get_node("/root/X")`
- **Signal cleanup**: Disconnect autoload signals in `_exit_tree()` for non-autoload nodes
- **Process optimization**: `set_process(false)` in `_ready()`, toggle on/off as needed
- **CanvasLayer numbers**: Use `Constants.LAYER_*`, never magic numbers
- **mouse_filter**: Set `IGNORE` on all non-interactive layout containers
- **Environment layering**: Never bake map defaults into `level_data`; they are derived at load time
- **Map loading**: Use `GlbUtils.load_map_async()` for maps (handles both `res://` and `user://` paths)
- **GLB async**: `GlbUtils.load_glb_async()` runs entirely on a background thread — zero main-thread blocking
- **UIDs**: `.uid` files are auto-generated by Godot; never edit manually
- **Shader limitations**: `return` is not allowed in `fragment()` / `vertex()` — use `if` blocks instead
