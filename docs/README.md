# Documentation

This folder contains technical documentation for the project.

## Available Guides

| Document                                                       | Description                                       |
| -------------------------------------------------------------- | ------------------------------------------------- |
| [ARCHITECTURE.md](ARCHITECTURE.md)                             | Project structure, state management, core systems |
| [NETWORKING.md](NETWORKING.md)                                 | Multiplayer networking, state sync, connections   |
| [ASSET_MANAGEMENT.md](ASSET_MANAGEMENT.md)                     | Asset packs, downloading, caching, P2P streaming  |
| [UI_SYSTEMS.md](UI_SYSTEMS.md)                                 | UIManager, dialogs, toasts, transitions, settings |
| [THEME_GUIDE.md](THEME_GUIDE.md)                               | Theme variants, typography, styling               |
| [SOUND_EFFECTS.md](SOUND_EFFECTS.md)                           | Audio files, wiring, normalization, adding sounds  |
| [lighting-and-environment.md](lighting-and-environment.md)     | Environment presets, map defaults, sky, in-game editing |
| [CONVENTIONS.md](CONVENTIONS.md)                               | RPC patterns, signal cleanup, token hierarchy, camera, settings |

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
# Async (recommended - non-blocking, uses cache)
var model = await AssetManager.get_model_instance("my_pack", "dragon", "default")

# Sync (blocks if not cached)
var model = AssetManager.get_model_instance_sync("my_pack", "dragon", "default")
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
├── LOBBY_HOST state → Lobby scene (hosting)
├── LOBBY_CLIENT state → Lobby scene (joining)
├── PLAYING state → GameMap scene
└── PAUSED state → PauseOverlay scene

Autoloads (singletons):
├── EventBus        - Cross-system signals
├── UIManager       - UI systems (dialogs, toasts, transitions)
├── AudioManager    - Sound playback and buses
├── LevelManager    - Level file I/O
├── NetworkManager  - Multiplayer connections
├── NetworkStateSync - State broadcasting
├── GameState       - Authoritative game state
├── AssetManager    - Asset pipeline facade (pack management, resolution, model cache)
│   ├── cache       - Disk cache with LRU eviction
│   ├── downloader  - HTTP download queue
│   ├── streamer    - P2P chunked streaming
│   └── resolver    - Resolution pipeline (local → cache → HTTP → P2P)
└── UpdateManager   - GitHub release checking & updates

Static classes (class_name, no autoload):
├── Constants          - Shared constants (layers, lo-fi defaults, network intervals)
├── Paths              - Path constants and utilities
├── NodeUtils          - Node manipulation utilities
├── TokenPermissions   - Per-token, per-player permission management
├── SerializationUtils - Vector3/Color serialization helpers
└── EnvironmentPresets - Environment presets and layered configuration
```

## Contributing

When adding new features:

1. Follow existing patterns documented in ARCHITECTURE.md
2. Use theme variants from THEME_GUIDE.md
3. Register overlays with UIManager for ESC handling
4. Update relevant documentation

### Audio Setup

If you're working with audio files, run the one-time hook install:

```bash
python tools/hooks/install.py
```

This installs a pre-commit hook that auto-normalizes audio files in `assets/audio/` to consistent loudness. Requires `ffmpeg` on PATH:

```bash
winget install ffmpeg        # Windows
brew install ffmpeg          # macOS
sudo apt install ffmpeg      # Ubuntu / Debian
```

See [SOUND_EFFECTS.md](SOUND_EFFECTS.md) for the full audio reference.
