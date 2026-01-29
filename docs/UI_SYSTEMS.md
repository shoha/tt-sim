# UI Systems Guide

This guide documents the UI infrastructure and reusable components available in the project.

## Table of Contents

- [UIManager Autoload](#uimanager-autoload)
- [State Management](#state-management)
- [Confirmation Dialogs](#confirmation-dialogs)
- [Toast Notifications](#toast-notifications)
- [Scene Transitions](#scene-transitions)
- [Loading Screen](#loading-screen)
- [Input Hints](#input-hints)
- [Settings Menu](#settings-menu)
- [Pause Menu](#pause-menu)
- [AudioManager](#audiomanager)
- [Overlay & Modal System](#overlay--modal-system)

---

## UIManager Autoload

`UIManager` is the central hub for all UI operations. It's an autoload available globally.

### Quick Reference

```gdscript
# Confirmation dialogs
UIManager.show_confirmation("Title", "Message")
UIManager.show_danger_confirmation("Delete?", "This cannot be undone.", my_callback)

# Toast notifications
UIManager.show_info("Something happened")
UIManager.show_success("Level saved!")
UIManager.show_warning("Check your input")
UIManager.show_error("Failed to load")

# Scene transitions
await UIManager.fade_out()
await UIManager.fade_in()
await UIManager.transition(func(): change_scene())

# Loading screen
UIManager.show_loading("Loading level...")
UIManager.set_loading_progress(0.5, "Loading tokens...")
await UIManager.hide_loading()

# Input hints
UIManager.set_hints([{"key": "ESC", "action": "Pause"}])
UIManager.add_hint("E", "Interact")
UIManager.remove_hint("E")
UIManager.clear_hints()

# Settings & overlays
UIManager.open_settings()
UIManager.register_overlay(my_panel)
UIManager.unregister_overlay(my_panel)
```

---

## State Management

The application uses a **state stack** managed by the `Root` node.

### Available States

| State          | Description                         |
| -------------- | ----------------------------------- |
| `TITLE_SCREEN` | Main menu, level selection          |
| `PLAYING`      | Active gameplay with GameMap loaded |
| `PAUSED`       | Game paused, pause menu visible     |

### State Transitions

```gdscript
# From Root.gd or via UIManager access to Root

# Replace entire state stack (for major transitions)
change_state(State.PLAYING)

# Push overlay state (for pause, etc.)
push_state(State.PAUSED)

# Pop back to previous state
pop_state()

# Query current state
var current = get_current_state()
```

### State Stack Behavior

- `change_state()` - Clears stack, enters new base state
- `push_state()` - Adds state on top (current state remains underneath)
- `pop_state()` - Removes top state, returns to previous

Example flow:

```
[TITLE_SCREEN] → change_state(PLAYING) → [PLAYING]
[PLAYING] → push_state(PAUSED) → [PLAYING, PAUSED]
[PLAYING, PAUSED] → pop_state() → [PLAYING]
```

---

## Confirmation Dialogs

Reusable modal dialogs for user confirmation.

### Basic Usage

```gdscript
# Simple confirmation
var dialog = UIManager.show_confirmation(
    "Delete Token?",
    "This action cannot be undone."
)
var confirmed = await dialog.closed
if confirmed:
    delete_token()

# With callbacks (no await needed)
UIManager.show_confirmation(
    "Save Changes?",
    "Do you want to save before closing?",
    "Save",           # confirm button text
    "Discard",        # cancel button text
    func(): save(),   # confirm callback
    func(): discard() # cancel callback
)

# Danger confirmation (red confirm button)
UIManager.show_danger_confirmation(
    "Delete Level?",
    "All tokens will be lost.",
    func(): delete_level()
)
```

### Parameters

| Parameter          | Type     | Default   | Description                      |
| ------------------ | -------- | --------- | -------------------------------- |
| `title`            | String   | required  | Dialog title                     |
| `message`          | String   | required  | Dialog message                   |
| `confirm_text`     | String   | "Confirm" | Confirm button label             |
| `cancel_text`      | String   | "Cancel"  | Cancel button label              |
| `confirm_callback` | Callable | empty     | Called on confirm                |
| `cancel_callback`  | Callable | empty     | Called on cancel                 |
| `confirm_style`    | String   | "Success" | Theme variant for confirm button |

### Signals

- `closed(confirmed: bool)` - Emitted when dialog closes

---

## Toast Notifications

Non-blocking notifications that appear in the bottom-right corner.

### Types

| Type    | Method           | Color  | Use Case              |
| ------- | ---------------- | ------ | --------------------- |
| INFO    | `show_info()`    | Orange | General information   |
| SUCCESS | `show_success()` | Green  | Successful operations |
| WARNING | `show_warning()` | Yellow | Caution notices       |
| ERROR   | `show_error()`   | Red    | Error messages        |

### Usage

```gdscript
# Quick helpers
UIManager.show_info("Auto-saved")
UIManager.show_success("Level saved!")
UIManager.show_warning("Unsaved changes")
UIManager.show_error("Failed to load file")

# With custom duration
UIManager.show_toast("Custom message", UIManager.TOAST_SUCCESS, 5.0)
```

### Behavior

- Auto-dismiss after 3 seconds (configurable)
- Maximum 5 visible at once (oldest dismissed)
- Animated slide-in/out
- Does not block input

---

## Scene Transitions

Smooth fade transitions between scenes or states.

### Usage

```gdscript
# Simple fade out/in
await UIManager.fade_out(0.3)
# ... change scene ...
await UIManager.fade_in(0.3)

# Combined transition with callback
await UIManager.transition(
    func(): get_tree().change_scene_to_file("res://new_scene.tscn"),
    0.3,  # fade out duration
    0.3   # fade in duration
)

# Check transition state
if UIManager.is_transitioning():
    return  # Don't interrupt
```

### Configuration

Default fade duration: 0.3 seconds
Fade color: Dark theme background (#1a121a)

---

## Loading Screen

Progress indicator for async operations.

### Usage

```gdscript
# Show loading
UIManager.show_loading("Loading Level...")

# Update progress (0.0 to 1.0)
UIManager.set_loading_progress(0.25, "Loading map...")
UIManager.set_loading_progress(0.50, "Spawning tokens...")
UIManager.set_loading_progress(0.75, "Configuring camera...")
UIManager.set_loading_progress(1.0, "Done!")

# Hide when complete
await UIManager.hide_loading()

# For indeterminate loading (no progress bar)
UIManager.show_loading("Please wait...")
# Progress bar is hidden, just shows spinner/message
```

### Features

- Smooth progress bar animation
- Status text updates
- Blocks input while visible
- Animated show/hide

---

## Input Hints

Contextual keybinding hints at the bottom of the screen.

### Usage

```gdscript
# Set all hints at once
UIManager.set_hints([
    {"key": "ESC", "action": "Pause"},
    {"key": "E", "action": "Interact"},
    {"key": "Space", "action": "Jump"}
])

# Add/remove individual hints
UIManager.add_hint("R", "Reload")
UIManager.remove_hint("R")

# Clear all hints
UIManager.clear_hints()
```

### Best Practices

- Update hints when context changes (entering/exiting areas, selecting objects)
- Keep hints concise (1-2 words for action)
- Use standard key names (ESC, Space, LMB, RMB, etc.)

---

## Settings Menu

Tabbed settings interface with Audio, Graphics, and Controls.

### Opening

```gdscript
var settings = UIManager.open_settings()
await settings.closed  # Wait for user to close
```

### Tabs

**Audio Tab:**

- Master Volume
- Music Volume
- Sound Effects Volume
- UI Sounds Volume

**Graphics Tab:**

- Fullscreen toggle
- VSync toggle

**Controls Tab:**

- Read-only keybinding display

### Persistence

Settings are saved to `user://settings.cfg` and loaded on startup.

---

## Pause Menu

The pause menu is shown when the game is paused (ESC during gameplay).

### Features

- **Resume** - Continue playing
- **Settings** - Open settings menu
- **Return to Title** - Exit to main menu (with confirmation)

### Behavior

- Game tree is paused (`get_tree().paused = true`)
- UI elements with `process_mode = PROCESS_MODE_WHEN_PAUSED` remain interactive
- ESC toggles pause on/off

---

## AudioManager

Centralized audio management for UI and game sounds.

### Audio Buses

| Bus    | Purpose                |
| ------ | ---------------------- |
| Master | Overall volume control |
| Music  | Background music       |
| SFX    | Sound effects          |
| UI     | UI interaction sounds  |

### UI Sound Methods

```gdscript
AudioManager.play_click()    # Button clicks
AudioManager.play_hover()    # Button hover
AudioManager.play_open()     # Menu/panel open
AudioManager.play_close()    # Menu/panel close
AudioManager.play_success()  # Success feedback
AudioManager.play_error()    # Error feedback
AudioManager.play_confirm()  # Confirmation
AudioManager.play_cancel()   # Cancel/back
```

### Volume Control

```gdscript
# Set volume (0.0 to 1.0)
AudioManager.set_bus_volume("Master", 0.8)
AudioManager.set_bus_volume("Music", 0.5)

# Get current volume
var vol = AudioManager.get_bus_volume("SFX")

# Mute/unmute
AudioManager.set_bus_mute("Music", true)
var is_muted = AudioManager.is_bus_muted("Music")
```

### Adding Sound Files

Place audio files in `res://assets/audio/ui/` with these names:

- `click.wav`
- `hover.wav`
- `open.wav`
- `close.wav`
- `success.wav`
- `error.wav`
- `confirm.wav`
- `cancel.wav`

AudioManager will automatically load them on startup.

---

## Overlay & Modal System

UIManager tracks overlays and modals for proper ESC key handling.

### Priority Order (ESC key)

1. **Modals** - Confirmation dialogs, etc.
2. **Overlays** - Level Editor, Pokemon List, Settings
3. **Pause Toggle** - If playing, pause/unpause

### Registering Overlays

Any UI that should respond to ESC must register:

```gdscript
func _on_open():
    UIManager.register_overlay(self)

func _on_close():
    UIManager.unregister_overlay(self)
```

For overlays extending `AnimatedVisibilityContainer`:

```gdscript
func _on_before_animate_in() -> void:
    UIManager.register_overlay(self)

func _on_before_animate_out() -> void:
    UIManager.unregister_overlay(self)
```

### Overlay Requirements

Overlays must implement one of:

- `animate_out()` method (preferred)
- `close()` method
- `hide()` method (fallback)

---

## File Reference

| File                                         | Purpose                        |
| -------------------------------------------- | ------------------------------ |
| `autoloads/ui_manager.gd`                    | Central UI manager             |
| `autoloads/audio_manager.gd`                 | Audio management               |
| `scenes/ui/confirmation_dialog.tscn`         | Confirmation dialog            |
| `scenes/ui/toast_container.tscn`             | Toast notifications            |
| `scenes/ui/transition_overlay.tscn`          | Scene transitions              |
| `scenes/ui/loading_overlay.tscn`             | Loading screen                 |
| `scenes/ui/input_hints.tscn`                 | Input hints                    |
| `scenes/ui/settings_menu.tscn`               | Settings menu                  |
| `scenes/ui/pause_overlay.tscn`               | Pause menu                     |
| `scenes/ui/animated_visibility_container.gd` | Base class for animated panels |

---

## CanvasLayer Ordering

UI elements are organized by layer for proper z-ordering:

| Layer | Component          | Purpose                |
| ----- | ------------------ | ---------------------- |
| 2     | AppMenu            | Always-visible buttons |
| 10    | PauseOverlay       | Pause menu             |
| 80    | InputHints         | Keybinding hints       |
| 90    | ToastContainer     | Notifications          |
| 95    | SettingsMenu       | Settings overlay       |
| 100   | ConfirmationDialog | Modal dialogs          |
| 105   | LoadingOverlay     | Loading screen         |
| 110   | TransitionOverlay  | Scene transitions      |

Higher layers appear on top of lower layers.
