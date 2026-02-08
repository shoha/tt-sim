# Sound Effects Reference

This document catalogs all sound effects used (or expected) across the game, organized by category. The `AudioManager` autoload manages playback across four audio buses: **Master**, **Music**, **SFX**, and **UI**.

---

## Audio File Locations

| Category | Directory                    | Formats        |
|----------|------------------------------|----------------|
| UI       | `res://assets/audio/ui/`     | `.wav`, `.ogg`  |
| SFX      | `res://assets/audio/sfx/`    | `.wav`, `.ogg`  |

Files are auto-loaded by `AudioManager._load_ui_sounds()` and `_load_sfx_sounds()` on startup. Simply drop correctly-named files into the directories above and they will be picked up automatically.

---

## Modular Sound Wiring

Sound effects are wired up **automatically** wherever possible so that new UI elements get sounds without manual intervention.

### Automatic Button Sounds (via SceneTree)

`AudioManager` listens to `SceneTree.node_added`. Every `BaseButton` that enters the scene tree automatically gets:

- **`pressed`** → `play_click()` (click sound)
- **`mouse_entered`** → `play_hover()` (hover sound, at -6 dB)

**Opting out:** To silence a specific button (e.g. because it plays a specialized sound instead), set metadata before or during `_ready()`:

```gdscript
button.set_meta("ui_silent", true)
```

The auto-connect defers to the button's `ready` signal, so metadata set during `_ready()` is respected.

### Automatic Panel Sounds (via base classes)

There are **two** panel base classes that handle animation and sounds automatically:

#### `AnimatedVisibilityContainer` (extends `Control`)

For in-scene panels that show/hide within the UI tree.

- **`animate_in()`** → `play_open()`
- **`animate_out()`** → `play_close()`
- **Opt out:** set `play_open_close_sounds = false` in inspector or script

Panels using this: `TokenContextMenu`, `AssetBrowserContainer`, `LevelEditor`

#### `AnimatedCanvasLayerPanel` (extends `CanvasLayer`)

For full-screen overlay panels with a backdrop (`ColorRect`) + centered content (`CenterContainer/PanelContainer`).

- **`animate_in()`** → `play_open()`
- **`animate_out()`** → `play_close()`
- **Opt out:** set `play_sounds = false` in inspector or script
- Provides lifecycle hooks: `_on_panel_ready()`, `_on_after_animate_in()`, `_on_before_animate_out()`, `_on_after_animate_out()`

Panels using this: `SettingsMenu`, `PauseOverlay`, `ConfirmationDialogUI`, `UpdateDialogUI`

#### `LevelEditor` popups

The level editor's `_animate_popup_in()` / `_animate_popup_out()` methods also play open/close sounds.

The level editor's `LoadDialog` and `DeleteConfirmDialog` also play close sounds when dismissed via the X button (`close_requested` signal).

### Specialized Button Sounds

Some buttons play specialized sounds instead of the generic click:

| Button                             | Sound                | How                                      |
|------------------------------------|----------------------|------------------------------------------|
| Confirmation dialog "Confirm"      | `play_confirm()`     | Button has `ui_silent` meta; calls manually |
| Confirmation dialog "Cancel"       | `play_cancel()`      | Button has `ui_silent` meta; calls manually |

---

## UI Sounds (Bus: UI)

These are played via `AudioManager.play_<name>()` helper methods. Default pitch variation: ±8%.

| File                | AudioManager Method    | Volume  | Description                       | Wiring              |
|---------------------|------------------------|---------|-----------------------------------|----------------------|
| `click.wav`         | `play_click()`         | 0 dB    | Button press / tap                | **Auto** (all buttons) |
| `hover.ogg`         | `play_hover()`         | -6 dB   | Button hover / focus              | **Auto** (all buttons) |
| `open.ogg`          | `play_open()`          | 0 dB    | Menu or panel opening             | **Auto** (panels)    |
| `close.ogg`         | `play_close()`         | 0 dB    | Menu or panel closing             | **Auto** (panels)    |
| `success.wav`       | `play_success()`       | 0 dB    | Success feedback (e.g. level win) | Manual               |
| `error.wav`         | `play_error()`         | 0 dB    | Error feedback                    | Manual               |
| `confirm.ogg`       | `play_confirm()`       | 0 dB    | Confirmation dialog accept        | **Wired**            |
| `cancel.wav`        | `play_cancel()`        | 0 dB    | Cancel / back action              | **Wired**            |

---

## SFX Sounds (Bus: SFX)

These are played via `AudioManager.play_<name>()` helper methods. Default pitch variation: ±8%.

| File                  | AudioManager Method      | Volume  | Description                          | Status        |
|-----------------------|--------------------------|---------|--------------------------------------|---------------|
| `token_pickup.wav`    | `play_token_pickup()`    | 0 dB    | Picking up / starting to drag a token| **Wired**     |
| `token_drop.wav`      | `play_token_drop()`      | 0 dB    | Dropping / placing a token           | **Wired**     |
| `token_slide.wav`     | `play_token_slide()`     | -3 dB   | Token sliding / movement on board    | Not wired     |
| `token_hover.ogg`     | `play_token_hover()`     | -6 dB   | Mouse hovering over a board token    | **Wired**     |
| `token_whoosh.wav`    | `play_token_whoosh()`    | -3 dB   | Rapid drag swoosh (velocity-based)   | **Wired**     |

### Where SFX Sounds Are Used

| Sound              | File                      | Trigger                          |
|--------------------|---------------------------|----------------------------------|
| `play_token_pickup()` | `draggable_token.gd`    | Drag start                      |
| `play_token_drop()`   | `draggable_token.gd`    | Settle start (immediate on drop/cancel) |
| `play_token_hover()`  | `board_token_controller.gd` | Mouse enters token rigid body |
| `play_token_whoosh()` | `draggable_token.gd`    | Horizontal drag speed >= 48 units/sec (0.15s cooldown, velocity-scaled pitch) |

### Additional SFX Candidates (Not Yet in AudioManager)

These are interactions that could benefit from sound effects but don't have corresponding entries in `AudioManager` yet. Adding them would require both a new audio file and a new method in `audio_manager.gd`.

| Proposed File           | Proposed Method             | Description                                    | Where to Wire                          |
|-------------------------|-----------------------------|------------------------------------------------|----------------------------------------|
| `token_snap.wav`        | `play_token_snap()`         | Token snapping to grid position                | `drag_and_drop_3d.gd` snap logic       |
| `token_rotate.wav`      | `play_token_rotate()`       | Token rotation snap                            | `board_token_controller.gd` rotation   |
| `token_scale.wav`       | `play_token_scale()`        | Token scale change                             | `board_token_controller.gd` scaling    |
| `token_cancel.wav`      | `play_token_cancel()`       | Drag cancelled / token returns to origin       | `draggable_token.gd` cancel handler    |
| `level_start.wav`       | `play_level_start()`        | Level begins loading / transition starts       | `level_play_controller.gd`             |
| `level_complete.wav`    | `play_level_complete()`     | Level finishes loading / ready to play         | `level_play_controller.gd` / `root.gd` |

---

## Audio Bus Layout

```
Master
├── Music   (background music, not yet implemented)
├── SFX     (game interaction sounds — tokens, level events)
│   ├── Effect: LowPassFilter  (cutoff 7kHz — softens digital sharpness)
│   └── Effect: Reverb          (small room, 12% wet — subtle physical space)
└── UI      (interface sounds — clicks, hovers, panels)
    └── Effect: LowPassFilter  (cutoff 7kHz — warm, muffled-speaker feel)
```

Each bus has independent volume (0–100%) and mute controls, adjustable from the Settings menu.

### Lo-fi Bus Effects

The SFX and UI buses have effects applied to achieve a warm, lo-fi aesthetic. These are configured in `default_bus_layout.tres` and can be tweaked in the Godot editor (bottom panel → Audio tab).

| Bus | Effect | Key Settings | Purpose |
|-----|--------|-------------|---------|
| SFX | LowPassFilter | cutoff: 7kHz | Rolls off harsh highs for a warm tone |
| SFX | Reverb | room: 0.2, wet: 12%, damping: 0.7 | Subtle sense of physical space (tabletop feel) |
| UI  | LowPassFilter | cutoff: 7kHz | Softens UI clicks/chimes to match the lo-fi vibe |

**Tuning tips:**
- Lower the cutoff (e.g. 5kHz) for a more muffled, retro feel
- Raise the cutoff (e.g. 10kHz) if sounds feel too dull
- Increase reverb wet (e.g. 0.2) for more spatial depth, decrease (e.g. 0.05) for drier sound
- All changes are audible immediately in the editor's Audio tab

---

## Sound Design Guidelines

- **UI sounds** should be short (< 200ms), clean, and non-intrusive. Consider subtle clicks and swooshes.
- **SFX sounds** can be slightly longer but should still be snappy. Token interactions should feel tactile.
- **Pitch variation** (±8% by default) adds natural variety — avoid perfectly identical repeated sounds.
- **Format**: `.wav` is preferred for short sound effects (low latency). `.ogg` is acceptable for longer SFX.
- **Sample rate**: 44100 Hz or 22050 Hz are both fine for short effects.
- **Channels**: Mono is preferred for UI/SFX (saves memory, no stereo placement needed).

### Volume Normalization

All audio files are automatically normalized on commit via a pre-commit hook. This ensures consistent perceived loudness regardless of the source.

**Two-tier strategy:**

| File length | Method | Target | Tolerance |
|---|---|---|---|
| >= ~400ms | LUFS (EBU R128 measurement + gain + limiter) | -18 LUFS | ±1.5 dB |
| < ~400ms | Peak normalization (gain + limiter) | -3 dBFS | ±1.5 dB |

Short files (clicks, pops) can't be measured by the LUFS algorithm, so they fall back to peak normalization automatically.

**Setup (one-time):**

```bash
python tools/hooks/install.py
```

**Requirements:** `ffmpeg` on PATH:

```bash
# Windows
winget install ffmpeg

# macOS
brew install ffmpeg

# Ubuntu / Debian
sudo apt install ffmpeg

# Fedora
sudo dnf install ffmpeg

# Arch
sudo pacman -S ffmpeg
```

**How it works:**
- The pre-commit hook detects staged audio files in `assets/audio/`
- Measures loudness (LUFS) and peak levels via `tools/normalize_audio.py`
- Applies the exact gain needed to reach the target, with a hard limiter at -1 dBTP to prevent clipping
- Re-stages the normalized files so the commit includes corrected versions
- Files already within tolerance are skipped (idempotent — re-running does nothing)
- If ffmpeg is not installed, the hook prints a warning and continues (non-blocking)

**Manual usage:**

```bash
python tools/normalize_audio.py                 # Normalize all audio files
python tools/normalize_audio.py --dry-run       # Preview without modifying
python tools/normalize_audio.py --target -16    # Custom LUFS target
python tools/normalize_audio.py --peak -1       # Custom peak target for short files
python tools/normalize_audio.py --backup        # Keep originals as .bak
```

---

## Adding Sounds to New UI Elements

### Buttons
No action needed. Any `BaseButton` added to the scene tree will automatically play click and hover sounds. To opt out:

```gdscript
my_button.set_meta("ui_silent", true)
```

### Panels / Dialogs
- **In-scene panel** (shows/hides within UI): extend `AnimatedVisibilityContainer`. Sounds are automatic.
- **Full-screen overlay** (backdrop + centered dialog): extend `AnimatedCanvasLayerPanel`. Sounds are automatic. Override `_on_panel_ready()` for setup, and use lifecycle hooks for custom behavior:

```gdscript
extends AnimatedCanvasLayerPanel
class_name MyDialog

func _on_panel_ready() -> void:
    # Connect signals, load data, etc.
    my_button.pressed.connect(_on_my_button_pressed)

func _on_after_animate_in() -> void:
    my_button.grab_focus()

func _on_after_animate_out() -> void:
    closed.emit()
    queue_free()
```

### New SFX
1. Add the audio file to `res://assets/audio/sfx/`
2. Add a key to `_sfx_sounds` dictionary in `audio_manager.gd`
3. Add a public helper method (e.g. `play_token_snap()`)
4. Call the method from the appropriate game code

---

## Implementation Checklist

### Phase 1: Audio Files (13 files)
- [x] `assets/audio/ui/click.wav` (JDSherbert Tabletop SFX)
- [x] `assets/audio/ui/hover.ogg` (Kenney Interface Sounds)
- [x] `assets/audio/ui/open.ogg` (Kenney — pluck)
- [x] `assets/audio/ui/close.ogg` (Kenney — pluck)
- [x] `assets/audio/ui/success.wav` (ObsydianX Interface SFX)
- [x] `assets/audio/ui/error.wav` (ObsydianX Interface SFX)
- [x] `assets/audio/ui/confirm.ogg` (Kenney Interface Sounds)
- [x] `assets/audio/ui/cancel.wav` (ObsydianX Interface SFX)
- [x] `assets/audio/sfx/token_pickup.wav` (JDSherbert Tabletop SFX)
- [x] `assets/audio/sfx/token_drop.wav` (JDSherbert Tabletop SFX)
- [ ] `assets/audio/sfx/token_slide.wav` (JDSherbert Tabletop SFX — file exists, not wired)
- [x] `assets/audio/sfx/token_hover.ogg` (Kenney — tick)
- [x] `assets/audio/sfx/token_whoosh.wav` (JDSherbert — swipe)

All audio files are CC0-licensed. All files are normalized via the pre-commit hook.

### Phase 2: Wiring (done)
- [x] Auto-connect all button click/hover sounds via `SceneTree.node_added`
- [x] Panel open/close sounds in `AnimatedVisibilityContainer` base class
- [x] Panel sounds via `AnimatedCanvasLayerPanel` base class (SettingsMenu, PauseOverlay, ConfirmationDialogUI, UpdateDialogUI)
- [x] Level editor popup sounds (open/close + X button close on LoadDialog and DeleteConfirmDialog)
- [x] Specialized confirm/cancel sounds in `ConfirmationDialogUI`
- [x] Token drop sound plays at settle start (immediate feedback on release)
- [x] Token whoosh sound on rapid drag (velocity-based trigger with pitch scaling)
- [ ] Wire `AudioManager.play_token_slide()` to token movement
- [ ] Wire `AudioManager.play_success()` / `play_error()` to relevant feedback points

### Phase 3: Expanded SFX (optional)
- [ ] Add token snap, rotate, scale, cancel sounds to `AudioManager`
- [ ] Add level transition sounds to `AudioManager`
- [ ] Wire new SFX methods to game interactions
