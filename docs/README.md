# Documentation

This folder contains technical documentation for the project.

## Available Guides

| Document                                   | Description                                       |
| ------------------------------------------ | ------------------------------------------------- |
| [ARCHITECTURE.md](ARCHITECTURE.md)         | Project structure, state management, core systems |
| [NETWORKING.md](NETWORKING.md)             | Multiplayer networking, state sync, connections   |
| [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md) | Asset packs, downloading, caching, P2P streaming  |
| [UI_SYSTEMS.md](UI_SYSTEMS.md)             | UIManager, dialogs, toasts, transitions, settings |
| [THEME_GUIDE.md](THEME_GUIDE.md)           | Theme variants, typography, styling               |

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

### Hosting a Multiplayer Game

```gdscript
NetworkManager.host_game()
NetworkManager.room_code_received.connect(func(code):
    print("Share this code: ", code)
)
```

### Joining a Multiplayer Game

```gdscript
NetworkManager.join_game("ABC123")
```

### Loading an Asset

```gdscript
var model = AssetPackManager.load_model("my_pack", "dragon", "default")
```

### Creating a Token from Asset

```gdscript
var token = await BoardTokenFactory.create_from_asset_async(
    "my_pack", "dragon", "default"
)
add_child(token)
```

## Architecture Overview

```
Root (manages state)
├── TITLE_SCREEN state → TitleScreen scene
├── LOBBY state → Lobby scene (host/client)
├── PLAYING state → GameMap scene
└── PAUSED state → PauseOverlay scene

Autoloads:
├── UIManager - UI systems
├── AudioManager - Sound
├── LevelManager - Level I/O
├── NodeUtils - Utilities
├── Paths - Path constants
├── NetworkManager - Multiplayer connections
├── NetworkStateSync - State broadcasting
├── GameState - Authoritative game state
├── AssetPackManager - Asset pack registry
├── AssetDownloader - HTTP downloads
└── AssetStreamer - P2P streaming
```

## Contributing

When adding new features:

1. Follow existing patterns documented in ARCHITECTURE.md
2. Use theme variants from THEME_GUIDE.md
3. Register overlays with UIManager for ESC handling
4. Update relevant documentation
