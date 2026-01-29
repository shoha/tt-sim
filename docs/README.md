# Documentation

This folder contains technical documentation for the project.

## Available Guides

| Document                           | Description                                       |
| ---------------------------------- | ------------------------------------------------- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Project structure, state management, core systems |
| [UI_SYSTEMS.md](UI_SYSTEMS.md)     | UIManager, dialogs, toasts, transitions, settings |
| [THEME_GUIDE.md](THEME_GUIDE.md)   | Theme variants, typography, styling               |

## Quick Start

### Showing a Toast

```gdscript
UIManager.show_success("Operation completed!")
```

### Showing a Confirmation Dialog

```gdscript
var dialog = UIManager.show_confirmation("Are you sure?", "This action cannot be undone.")
if await dialog.closed:
    # User confirmed
    perform_action()
```

### Scene Transition

```gdscript
await UIManager.transition(func():
    # This runs while screen is black
    change_to_new_scene()
)
```

### Opening Settings

```gdscript
UIManager.open_settings()
```

## Architecture Overview

```
Root (manages state)
├── TITLE_SCREEN state → TitleScreen scene
├── PLAYING state → GameMap scene
└── PAUSED state → PauseOverlay scene

Autoloads:
├── UIManager - UI systems
├── AudioManager - Sound
├── LevelManager - Level I/O
├── PokemonAutoload - Pokemon data
├── NodeUtils - Utilities
└── Paths - Path constants
```

## Contributing

When adding new features:

1. Follow existing patterns documented in ARCHITECTURE.md
2. Use theme variants from THEME_GUIDE.md
3. Register overlays with UIManager for ESC handling
4. Update relevant documentation
