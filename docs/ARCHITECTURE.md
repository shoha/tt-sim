# Project Architecture

This document provides an overview of the project's architecture, core systems, and how they interact.

## Table of Contents

- [Overview](#overview)
- [Scene Hierarchy](#scene-hierarchy)
- [Autoloads (Singletons)](#autoloads-singletons)
- [State Management](#state-management)
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
│   ├── Map (instantiated from level data)
│   ├── Tokens (BoardToken instances)
│   ├── Camera3D
│   └── GameplayMenu (CanvasLayer)
│       └── Pokemon list, context menus
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

## Autoloads (Singletons)

Autoloads are registered in `project.godot` and available globally.

| Autoload          | File                            | Purpose                            |
| ----------------- | ------------------------------- | ---------------------------------- |
| `Paths`           | `autoloads/paths.gd`            | Path constants and utilities       |
| `PokemonAutoload` | `autoloads/pokemon_autoload.gd` | Pokemon data and scene loading     |
| `NodeUtils`       | `autoloads/node_utils.gd`       | Node manipulation utilities        |
| `LevelManager`    | `autoloads/level_manager.gd`    | Level save/load operations         |
| `UIManager`       | `autoloads/ui_manager.gd`       | UI systems (dialogs, toasts, etc.) |
| `AudioManager`    | `autoloads/audio_manager.gd`    | Audio playback and bus control     |

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
- Level discovery (listing available levels)
- Level data validation

---

## State Management

### Root State Machine

The `Root` node implements a state stack for flexible state management.

```gdscript
enum State {
    TITLE_SCREEN,  # Main menu
    PLAYING,       # Active gameplay
    PAUSED,        # Game paused (overlay state)
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

Base class for animated UI panels. Provides:

- `animate_in()` / `animate_out()` methods
- Configurable timing and easing
- Lifecycle callbacks: `_on_before_animate_in()`, `_on_after_animate_out()`, etc.

See `themes/THEME_GUIDE.md` for detailed usage.

---

## Level System

### LevelData Resource

```gdscript
class_name LevelData extends Resource

var name: String
var description: String
var author: String
var map_scene_path: String
var map_offset: Vector3
var map_scale: Vector3
var token_placements: Array[TokenPlacement]
```

### TokenPlacement Resource

```gdscript
class_name TokenPlacement extends Resource

var display_name: String
var pokemon_number: String
var is_shiny: bool
var is_player_controlled: bool
var max_health: int
var current_health: int
var is_visible: bool
var position: Vector3
var rotation_y: float
var scale: Vector3
```

### Level Flow

1. **Level Editor** creates/edits `LevelData`
2. **LevelManager** saves/loads level files
3. **LevelPlayController** receives level data and:
   - Loads map scene
   - Spawns tokens from placements
   - Manages active gameplay
4. **Root** transitions state based on level events

---

## Token System

### BoardToken Scene

Physical game tokens representing Pokemon.

```
BoardToken (RigidBody3D)
├── CollisionShape3D
├── MeshInstance3D (Pokemon model)
├── BoardTokenController (script)
└── AnimationTree
```

### Token Lifecycle

1. **Spawn**: `LevelPlayController.spawn_pokemon()` creates token
2. **Setup**: Controller receives config, sets up appearance
3. **Interaction**: Drag/drop, context menu, selection
4. **Cleanup**: `queue_free()` when level clears

### Token Signals

```gdscript
signal token_added(token: BoardToken)
signal token_spawned(token: BoardToken)
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

### Avoid: Global Event Bus

The project previously used an EventBus autoload but this was removed in favor of:

- Direct signal connections for parent-child communication
- Autoload services for global operations
- Controller classes for domain logic (LevelPlayController)

---

## File Organization

```
project/
├── autoloads/           # Singleton services
├── resources/           # Custom Resource classes
├── scenes/
│   ├── board_token/     # Token system
│   ├── level_editor/    # Level editor UI
│   ├── level_loader/    # Level loading UI
│   ├── maps/            # Map scenes
│   ├── templates/       # Reusable scene templates
│   └── ui/              # UI components
├── themes/              # Theme definitions
├── docs/                # Documentation
└── assets/
    ├── fonts/
    ├── audio/
    └── models/
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

### New Autoload

1. Create script in `autoloads/`
2. Register in `project.godot` under `[autoload]`
3. Document purpose and API
