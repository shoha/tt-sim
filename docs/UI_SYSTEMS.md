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
- [Title Hub](#title-hub)
- [Settings Menu](#settings-menu)
- [Pause Menu](#pause-menu)
- [AudioManager](#audiomanager)
- [Overlay & Modal System](#overlay--modal-system)
- [LevelEditPanel (In-Game Edit Mode)](#leveleditpanel-in-game-edit-mode)
- [Measure Tool](#measure-tool)
- [Token Context Menu](#token-context-menu)
- [Asset Browser](#asset-browser)

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

# Loading screen -- owned by Root, not UIManager (see Loading Screen section below)
loading_overlay.show_loading("Loading level...")
loading_overlay.set_progress(0.5, "Loading tokens...")
await loading_overlay.hide_loading()

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

| State          | Description                              |
| -------------- | ---------------------------------------- |
| `TITLE_SCREEN` | Main menu, level selection               |
| `LOBBY_HOST`   | Hosting a game, waiting for players      |
| `LOBBY_CLIENT` | Joined a game, waiting for host to start |
| `PLAYING`      | Active gameplay with GameMap loaded      |
| `PAUSED`       | Game paused, pause menu visible          |

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

### `show_danger_confirmation` Signature

`show_danger_confirmation` is a thin wrapper over `show_confirmation` with `confirm_style` fixed to
`"Danger"` and no `cancel_callback`:

```gdscript
func show_danger_confirmation(
    title: String,
    message: String,
    confirm_callback: Callable = Callable(),
    confirm_text: String = "Delete",
    cancel_text: String = "Cancel"
) -> Node
```

`LevelEditPanel`'s unsaved-changes prompt calls it with `confirm_text = "Discard changes"` and
`cancel_text = "Keep editing"` — relabelling both buttons, since a bare "Cancel" next to the
drawer's own Cancel button would be ambiguous about which one it cancelled. See
[Unsaved Changes](#unsaved-changes) below.

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
| `confirm_sound_override` | Callable | empty | Played instead of the default confirm sound, if set |

### Signals

- `closed(confirmed: bool)` - Emitted when dialog closes

---

## Toast Notifications

Non-blocking notifications that appear bottom-center of the screen.

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

Progress indicator for async operations. `LoadingOverlay` (`scenes/ui/loading_overlay.gd`) is not a
UIManager-registered dialog -- `Root` instantiates and owns one directly (`_loading_overlay`) and
calls it during level loading. There is no `UIManager.show_loading()`/`hide_loading()` wrapper.

### Usage

```gdscript
# Show loading
loading_overlay.show_loading("Loading Level...")

# Update progress (0.0 to 1.0)
loading_overlay.set_progress(0.25, "Loading map...")
loading_overlay.set_progress(0.50, "Spawning tokens...")
loading_overlay.set_progress(0.75, "Configuring camera...")
loading_overlay.set_progress(1.0, "Done!")

# Hide when complete (async -- awaits the fade-out tween, emits loading_complete)
await loading_overlay.hide_loading()

# For indeterminate loading (no progress bar)
loading_overlay.show_indeterminate("Please wait...")
# Progress bar is hidden, just shows spinner/message; show_progress_bar() restores it
```

### Features

- Smooth progress bar animation (lerped toward the target value, with a looping shimmer)
- Status text updates
- Blocks mouse input while visible (full-screen near-opaque `ColorRect`, default `mouse_filter`)
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

## Title Hub

`TitleScreen` (`scenes/states/title_screen/title_screen.gd`) is the app's entry screen. It has two
zones: a left column of actions and a right zone showing the player's saved levels as cards, with
the d20 sub-viewport as a dimmed backdrop behind both.

### Left Column

Built by `_build_left_column()`. **Host Game** and **Join Game** are tall primary actions
(`_primary_action()`: icon, bold label, caption underneath); below a separator, **Play Solo**,
**Level Editor**, **Settings**, and **Quit** are compact secondary actions (`_secondary_action()`).
Host Game and Play Solo are disabled until a card is selected; once one is, their captions name it
("with <name>" for Host, the level name for Play Solo).

### Right Zone

A "Your levels" heading with a live count, and a 3-column `LevelGrid` populated from
`level_provider` (defaults to `LevelManager.get_saved_levels`; tests inject a fake before the node
enters the tree). The most recently modified level is preselected on `_ready()`
(`_preselect_most_recent()`). With no saved levels the grid is empty and an empty-state caption
reads "Make a level in the Level Editor first".

### Signals

- `host_game_requested(level_info: Dictionary)` -- Host Game pressed with a level selected
- `join_game_requested` -- Join Game pressed
- `play_solo_requested(level_info: Dictionary)` -- Play Solo pressed, or a card double-clicked or
  Enter-activated

`level_info` is one entry from `LevelManager.get_saved_levels()` -- the same Dictionary shape
`LevelCard.setup()` and `LevelCard.caption_for()` consume (see Level Cards below).

A card's thumbnail is captured on every in-play save -- the "Save Level" button and the Visuals
drawer's Save -- via `LevelManager.save_thumbnail()`; the Level Editor's own save does not write
one, so a level only edited there (never played) falls back to the placeholder art.

### Level Cards

Saved levels are three primitives under `scenes/ui/primitives/`:

- **`LevelCard`** (extends `Button`, `Card` theme variation) -- a thumbnail, name, and caption ("N
  tokens, edited <relative time>", built by the static `caption_for(info, now_unix)`). Press selects
  (`toggle_mode = true`); double-click or Enter activates. The overflow menu (the `dots-vertical`
  icon in the thumbnail's corner) offers Rename (swaps in an inline `LineEdit`), Duplicate, and
  Delete -- Delete is disabled while `locked` is true (the level currently being played). Signals:
  `selected(level_info)`, `activated(level_info)`, `action_requested(level_info, action:
  StringName)`, `rename_committed(level_info, new_name)`.
- **`LevelGrid`** (extends `ScrollContainer`) -- lays out `LevelCard`s in an `HFlowContainer`.
  `provider: Callable` returns the level list (defaults to `LevelManager.get_saved_levels`);
  `columns` sets the grid width; `locked_path` marks one card as locked; `confirm_delete: Callable`
  lets a caller override the delete confirmation (default `UIManager.show_danger_confirmation`).
  `refresh()` rebuilds the cards, `select(path)` selects silently, `selected_info()` returns the
  selected level's info, `card_count()` returns the total. Card actions (rename/duplicate/delete)
  write through `LevelManager` and call `refresh()`. Signals: `selection_changed(level_info)`,
  `level_activated(level_info)`.
- **`LevelPickerDialog`** (`scenes/ui/level_picker_dialog.gd`/`.tscn`, extends
  `AnimatedCanvasLayerPanel`) -- a modal level chooser wrapping a two-column `LevelGrid`.
  `setup(title, locked_path = "")` sets the dialog title and an optional locked card. Choose
  confirms the selected card (double-click chooses directly); Cancel closes without choosing.
  Signals: `level_chosen(level_info)`, `closed`. Used by the host lobby's Change button and the
  pause menu's Change Level (see below).

### Lobby

The host lobby (`LobbyHost`, `scenes/states/lobby/lobby_host.gd`) shows the pending level as a
strip -- thumbnail, name, token-count caption, set via `set_level(level)` -- with a Change button
that opens a `LevelPickerDialog` and emits `level_change_requested(level_info)` when a different
level is chosen.

---

## Settings Menu

Tabbed settings interface (`scenes/ui/settings_menu.gd`) with six sections: Audio, Graphics, Grid,
Controls, Network, and Updates. Sections are chosen from a labelled `IconRail` (`SECTIONS` in
`settings_menu.gd`) rather than the `TabContainer`'s own tab bar, which is hidden
(`tabs_visible = false`); the rail drives `tab_container.current_tab` instead. Graphics keeps
foliage budget and renderer options under an Advanced `Foldout`. The close button is an
`IconButton`. Keyboard section switching (the native tab bar's Ctrl+Tab) is not available while the
tab bar is hidden and the rail items are not focusable; a keyboard-navigation pass is a known
follow-up.

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

- Fullscreen toggle, VSync toggle
- Lo-fi filter toggle, occlusion fade toggle
- Antialiasing, shadow quality, water quality option buttons
- Advanced (`Foldout`): foliage density slider, SSAO/SSR/SDFGI toggles, renderer method option button

**Grid Tab:**

- Cell tint opacity, line thickness, and fade distance sliders for the grid overlay

**Controls Tab:**

- Input Device selector (sets `InputProfile` active profile)
- Read-only keybinding display (labels update dynamically based on active profile)

**Network Tab:**

- P2P enabled toggle
- Clear asset cache button, with cache size info

**Updates Tab:**

- Current version display
- Prereleases toggle
- Check for updates button and status label

### Persistence

Settings are saved to `Paths.SETTINGS_PATH` (`user://settings.cfg`) and loaded on startup.

---

## Pause Menu

`PauseOverlay` (`scenes/states/paused/pause_overlay.gd`) is shown when the game is paused (ESC
during gameplay).

### Features

- **Resume** - Continue playing
- **Edit Level** - GM-only (`NetworkManager.has_gm_access()`); resumes and opens the level editor
- **Change Level** - GM-only (`NetworkManager.has_gm_access()`); opens `LevelPickerDialog` and
  swaps the level without leaving the current game (see Change Level below)
- **Settings** - Open settings menu
- **Return to Title** - Exit to main menu (with confirmation)
- **Quit Game** - Exit the application (with confirmation)

### Behavior

- Game tree is paused (`get_tree().paused = true`) only in local, non-networked games — a networked
  game keeps running with the pause menu as an overlay, so other players are unaffected
- `PauseOverlay` itself runs with `process_mode = PROCESS_MODE_ALWAYS` so it stays interactive and
  animates whether or not the tree is actually paused
- ESC toggles pause on/off

### Change Level

Picking a level in the `LevelPickerDialog` (locked to the level currently in play) emits
`change_level_requested(level_info)`; `Root._on_pause_change_level_requested()` resumes first, then
routes through `GameplayMenuController.request_level_change(on_ready)`. If the Visuals drawer
(`LevelEditPanel`) has unsaved edits, that shows a "Discard the changes... and change the level?"
danger confirmation before continuing; a clean drawer proceeds immediately. Once ready,
`Root.request_level_change(level_info)` loads the new level and reloads it in place in the current
session (`Root._on_play_level_requested()`), broadcasting the level data to clients if the local
peer is the host.

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

UIManager tracks registered overlays and the app state for ESC key handling.

### Priority Order (ESC key)

1. **Overlays** - anything registered via `register_overlay()`: Level Editor, Settings, Help,
   Asset Browser, the `LevelEditPanel` Visuals drawer, etc. `UIManager._unhandled_input()` closes
   the top of the overlay stack first, before anything else
2. **Pause Toggle** - if no overlay is open and the app state is `PLAYING`/`PAUSED`, pause/unpause

Confirmation dialogs (modals) are not part of this stack: `ConfirmationDialog` consumes `ui_cancel`
in its own `_unhandled_input()` independently, so an open dialog dismisses on Escape without going
through `UIManager`'s overlay or pause handling.

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

For overlays extending `AnimatedCanvasLayerPanel`:

```gdscript
func _on_panel_ready() -> void:
    UIManager.register_overlay($ColorRect as Control)

func _on_before_animate_out() -> void:
    UIManager.unregister_overlay($ColorRect as Control)
```

### Overlay Requirements

`UIManager._close_top_overlay()` checks for these methods in order and calls the first one present:

- `request_close()` method — preferred for an overlay that may need to veto or prompt before
  closing (e.g. an unsaved-changes confirmation). The overlay owns the decision entirely;
  `_close_top_overlay()` does nothing else once it calls this. See `LevelEditPanel`'s
  `request_close()` in the [LevelEditPanel](#leveleditpanel-in-game-edit-mode) section below.
- `animate_out()` method
- `close()` method
- `hide()` method (fallback)

---

## DrawerContainer

Reusable slide-in/out drawer panel with a tab handle. Extends `Control`.

### Features

- Configurable edge (`LEFT` or `RIGHT`)
- Independent panel and tab animations
- `reveal()` / `conceal()` to show/hide the tab handle
- `open()` / `close()` / `toggle()` for the drawer itself
- Optional open/close sounds via `play_sounds` export
- Subclass lifecycle hook: override `_on_ready()` to configure and populate content
- `set_tab_badge(visible)` toggles a small accent dot at the tab's top-right corner
- `set_tab_tooltip(text)` sets the tooltip shown when hovering the tab handle
- Subclass hook: override `_can_close_from_tab()` to veto a close started from the tab
  button (e.g. to prompt about unsaved changes). A programmatic `close()` is never vetoed

### Usage

```gdscript
extends DrawerContainer
class_name MyDrawer

func _on_ready() -> void:
    drawer_width = 200.0
    tab_text = "Menu"
    # Populate content_container with your UI
    var label = Label.new()
    label.text = "Hello"
    content_container.add_child(label)
```

### Icon Tabs

Use `tab_icon` instead of `tab_text` to show an SVG icon on the tab handle. The icon is tinted with the theme's accent color and padded consistently. SVG files must use `fill="#ffffff"` (white) so the tint applies correctly — see the [Icons section in THEME_GUIDE.md](THEME_GUIDE.md#icons).

```gdscript
func _on_ready() -> void:
    tab_icon = preload("res://assets/icons/ui/sun.svg")
    drawer_width = 350.0
```

### Rail mode

Set `rail_items` in `_on_ready()` to replace the single tab with an `IconRail` showing one icon per pane instead of one icon for the whole drawer. Clicking an item opens the drawer and emits `pane_requested(id)`; clicking the active item closes it; `open()` with nothing selected reopens the last pane. Badge a single item with `set_rail_badge(id, true)`; `set_tab_tooltip()` only applies in single-tab mode. See [THEME_GUIDE.md's Rail Mode section](THEME_GUIDE.md#rail-mode) for the full example.

### Exports

| Property          | Type       | Default | Description                           |
| ----------------- | ---------- | ------- | ------------------------------------- |
| `edge`            | DrawerEdge | `LEFT`  | Which screen edge the drawer docks to |
| `drawer_width`    | float      | `220`   | Width of the panel                    |
| `tab_width`       | float      | `36`    | Width of the tab handle               |
| `tab_text`        | String     | `""`    | Text label on the tab handle          |
| `tab_icon`        | Texture2D  | `null`  | Icon on the tab (hides text when set) |
| `rail_items`      | Array[Dictionary] | `[]` | Item specs; replaces the single tab with an `IconRail` (rail mode) |
| `slide_duration`  | float      | `0.25`  | Animation duration                    |
| `start_open`      | bool       | `false` | Open on ready                         |
| `play_sounds`     | bool       | `true`  | Play open/close sounds                |
| `tab_top_margin`  | float      | `12`    | Tab offset from top edge              |
| `start_revealed`  | bool       | `false` | Show tab on ready                     |

### Existing Implementations

| Drawer | Edge | Tab | Purpose |
|--------|------|-----|---------|
| `PlayerListDrawer` | LEFT | `users.svg` icon | Shows connected players during networked games |
| `LevelEditPanel` | RIGHT | rail of six icons | Real-time level editing during gameplay (see below) |

See `THEME_GUIDE.md` for styling details.

---

## LevelEditPanel (In-Game Edit Mode)

`LevelEditPanel` extends `DrawerContainer` to provide real-time level editing during gameplay. It slides in from the right edge of the screen and applies all changes immediately to the live viewport.

### Accessing

During gameplay, click a rail item (Sun, Sky, Color, Weather, Film, World) on the right edge of the screen. The panel slides open on that pane; clicking another rail item switches panes without closing the drawer.

### Controls

The drawer is a rail of six panes (`SunPane`, `SkyPane`, `ColorPane`, `WeatherPane`, `FilmPane`, `WorldPane` in `scenes/states/playing/visual_panes/`), each a `LevelEditPane` that owns the fields it edits and implements `load_state(state)` / `write_state(state)` over a `LevelVisualState`:

| Rail item | Primary | Advanced |
|---|---|---|
| Sun | time of day (dawn/dusk hints, 14:30 format), Sun tiles Auto/On/Off, Shadows tiles Off/Hard/Soft, aim on map | direction (bearing), height, colour, energy, softness, darkness, back to generated |
| Sky | sky tiles with thumbnails (ten, two rows of five), preview strip and caption for the hovered or selected sky, Look picker (grouped, swatches, description), fog on/off + amount | background, ambient, fog colour, fog energy, fog height, fog falloff |
| Color | brightness (exposure), contrast, saturation, glow | light energy, fine brightness, tonemap, white point, glow strength, bloom |
| Weather | rain/snow/fog/wind tiles with Light..Heavy intensity | none |
| Film | Style tiles Off/Subtle/Retro/Heavy (+Custom), pixelate, vignette, grain | colours, dither, colour fade |
| World | scale tiles, cell size (m and ft), water tiles, Wind tiles Still/Breeze/Gusty (+Custom) | tree/grass speed and amount |

Style tiles set several fields at once and show `Custom` when the values match no preset; every slider shows end hints; raw values appear only with the rail footer toggle (persisted in `[ui] show_values`). Hovering a sky tile previews it in the strip without touching the model; HDRI skies rotate with the sun (see lighting-and-environment.md).

The Sky and Color panes share an `EnvironmentEditModel` (preset + overrides + map defaults); its `changed` signal is the single `environment_changed` broadcast. Every pane emits `changed` on a user edit, which marks the drawer dirty and badges that rail item; `mark_clean()` clears both. Override rows tint their label accent and reset on right-click via `PropertyRow.reset_requested`. Public signals and controller-facing methods (`initialize`, `apply_environment_state`, `set_sun_direction_from_gizmo`, `set_aim_sun_pressed`, `mark_clean`, `is_dirty`, `request_close`) are unchanged. A `Foldout`'s clip re-measures a wrapping body mid-animation, so its first expand is never clipped short.

### Signal Architecture

The panel emits granular signals for each type of change:

```gdscript
signal save_requested(state: LevelVisualState)
signal cancel_requested
signal intensity_changed(new_scale: float)
signal scale_config_changed(
    grid_cell_size: float, display_unit: String, display_unit_per_cell: float
)
signal environment_changed(preset: String, overrides: Dictionary)
signal lofi_changed(overrides: Dictionary)
signal weather_changed(overrides: Dictionary)
signal foliage_changed(overrides: Dictionary)
signal sun_changed(settings: SunSettings)
signal water_style_changed(style: String)
signal revert_to_map_defaults_requested
signal aim_sun_toggled(active: bool)
signal drawer_opened   # Controller should snapshot values and call initialize()
signal drawer_closed   # Controller should revert if not saved
```

`GameplayMenuController` connects these signals and routes them to `LevelPlayController` for live application. On `drawer_opened` it snapshots the current level as a `LevelVisualState` (`LevelVisualState.from_level_data()`); both Save and Cancel go through `LevelPlayController.apply_visual_state()` — Save applies the panel's emitted `state`, Cancel re-applies the snapshot taken at open time.

### Unsaved Changes

Every live edit calls `_mark_dirty()`, which raises the unsaved-changes flag, and each pane's own `changed` signal badges that pane's rail item (`set_rail_badge(id, true)`) via `_on_pane_changed()`. The drawer handle no longer shows one aggregate unsaved tooltip — per-pane badges on the rail replace it, so the GM can see which pane has unsaved edits at a glance. Only `mark_clean()` lowers the flag and clears every badge (`set_tab_badge(false)`); the controller calls it on Save, on Cancel, and when the level is cleared. Reopening the drawer (`initialize()`) does not clear it.

A dirty drawer refuses to close from its tab (`_can_close_from_tab()` returns `false`) and calls `request_close()` instead, which shows a "Discard changes" / "Keep editing" danger confirmation (the cancel button is relabelled via `show_danger_confirmation()`'s `cancel_text` parameter, since a bare "Cancel" next to the drawer's own Cancel button was ambiguous about which one it cancelled). Confirming emits `cancel_requested`, so the controller reverts and closes. Escape takes the same route: the panel registers itself with `UIManager.register_overlay()` in `open()`, and `UIManager._close_top_overlay()` prefers an overlay's `request_close()` over `animate_out()`/`close()`.

Save no longer closes the drawer — it clears the flag so tuning can continue — and advances the revert snapshot to the state just written to disk, then deactivates the sun gizmo the way a close would. A failed disk write shows the error toast only: the drawer stays dirty and the snapshot is left untouched.

`_enter_edit_mode()` re-snapshots only when the drawer is clean. The tab now vetoes a dirty close, so that guard covers the routes that bypass the prompt: `conceal()` when GM access is lost mid-edit (the drawer hides without reverting) and any programmatic reopen while dirty. In both cases the original snapshot survives, so a later Cancel still returns to the state from before the first unsaved edit.

### Environment Overrides & Preset Switching

Switching the Sky pane's preset dropdown (`_on_preset_selected()`) keeps whatever environment
overrides are already set on the shared `EnvironmentEditModel` — it re-emits `environment_changed`
with the new preset and the same overrides, and shows an info toast ("Preset changed. N
override(s) kept.") whenever there is at least one override to keep. The Sky pane's header "restore"
icon button ("Revert to the map's own lighting", visible only when the map has defaults) is the one
action that clears both together, resetting preset and overrides via `apply_environment_state("",
{})`.

Each overridden property is surfaced on its own `PropertyRow`: the Sky and Color panes tint that
row's label with the theme accent color (`overridden = true`), set a tooltip ("Overridden.
Right-click to reset to the preset value."), and wire `PropertyRow.reset_requested` — a right-click
handler — to erase just that row's key(s) from the model's overrides (dropping
`adjustment_enabled` too if that was the last remaining `adjustment_*` override). The Sky pane's
"eraser" header button is disabled whenever the model has no overrides and otherwise clears every
override at once (with its own "Overrides cleared." toast).

A Sky override survives a preset switch like every other override, by design; the per-row reset and
the "eraser" header button are the way back to the preset's own sky.

### Cancel Behavior

When the drawer closes without saving, `GameplayMenuController` restores the `LevelVisualState` snapshotted at open time and re-applies it to the live viewport via `LevelPlayController.apply_visual_state()`.

### Initialization

```gdscript
level_edit_panel.initialize(
    level_data,     # LevelData -- current values are read from this
    map_defaults,   # Dictionary from LevelPlayController.get_map_environment_config()
    has_map_sky,    # true if the map had an embedded Sky resource
)
```

See [lighting-and-environment.md](lighting-and-environment.md) for the full environment system documentation.

---

## File Reference

| File                                         | Purpose                          |
| -------------------------------------------- | -------------------------------- |
| `autoloads/ui_manager.gd`                    | Central UI manager               |
| `autoloads/audio_manager.gd`                 | Audio management                 |
| `scenes/ui/confirmation_dialog.tscn`         | Confirmation dialog              |
| `scenes/ui/toast_container.tscn`             | Toast notifications              |
| `scenes/ui/transition_overlay.tscn`          | Scene transitions                |
| `scenes/ui/loading_overlay.tscn`             | Loading screen                   |
| `scenes/ui/input_hints.tscn`                 | Input hints                      |
| `scenes/ui/settings_menu.tscn`               | Settings menu                    |
| `scenes/states/paused/pause_overlay.tscn`    | Pause menu                       |
| `scenes/ui/animated_visibility_container.gd` | Base class for animated panels        |
| `scenes/ui/drawer_container.gd`              | Base class for slide-out drawers      |
| `scenes/states/playing/level_edit_panel.gd`  | In-game real-time level editing panel (rail + `PaneStack`) |
| `scenes/states/playing/level_edit_panel.tscn`| UI layout for the edit panel          |
| `scenes/states/playing/visual_panes/`        | The six `LevelEditPane` scripts (sun, sky, color, weather, film, world) plus `EnvironmentEditModel` |
| `scenes/states/playing/measure_tool.gd`      | Distance measurement tool (2D overlay)|
| `utils/scale_utils.gd`                       | Scale conversion and formatting       |

---

## Measure Tool

The measure tool provides distance measurement for players during gameplay. It renders as a 2D overlay on its own `CanvasLayer` so that measurement lines and labels are crisp and unaffected by the lo-fi post-processing shader applied to the 3D SubViewport.

### Activation

Toggle with the **M** key. The tool uses a three-state machine: `INACTIVE` -> `PLACING_START` -> `PLACING_WAYPOINT`. Press M again, Escape, or right-click to deactivate.

Volume mode is activated by pressing **Tab** while the tool is open. Tab cycles through Line → Sphere → Cylinder → Line. The current mode is communicated by the active 3D shape and the Tab hint (which shows the next mode in the cycle).

### Visuals

All rendering is 2D, driven by `Control._draw()`:

- **Cursor dot** — A yellow circle follows the mouse while the tool is active, indicating where the next point will be placed.
- **Committed segments** — Solid colored lines between placed waypoints.
- **Preview segment** — Semi-transparent line from the last waypoint to the current cursor position.
- **Endpoint circles** — Small circles at each waypoint.
- **Segment labels** — Each segment shows its individual distance. Labels are `PanelContainer`s with a dark semi-transparent backdrop for contrast. Managed via an object pool to avoid per-frame allocation.
- **Total label** — When 2+ segments exist, a larger label shows the cumulative distance. Positioned at the midpoint of the last committed segment.
- **Preview label suppression** — The tentative segment's label is hidden when its on-screen length is < 80 pixels to avoid overlap with the total label.

### Input Hints Integration

The tool manages its own input hints via `UIManager`:

- **PLACING_START**: Shows `LMB: Place start`, `Esc: Cancel`.
- **PLACING_WAYPOINT**: Shows `LMB: Add point`, `RMB: Finish`, `Esc: Cancel`.
- **M: Measure** hint is shown in the default gameplay hints and removed while dragging a token.

### Scale Configuration

Distance labels use the active level's scale settings (`grid_cell_size`, `display_unit`, `display_unit_per_cell`) via `ScaleUtils`. When the GM changes scale in `LevelEditPanel`, the tool is reconfigured live via `MeasureTool.configure()`.

### Interaction Guards

- **Drag prevention**: `DragAndDrop3D.dragging_enabled` is set to `false` while the tool is active (via the `toggled` signal).
- **GUI click guard**: `GameMap._input()` checks `_is_mouse_over_gui()` before forwarding mouse clicks to the tool.
- **Context menu suppression**: When the tool consumes an input event, `get_viewport().set_input_as_handled()` prevents token context menus from opening.
- **Level lifecycle**: The tool is deactivated automatically when a level is cleared or a new level is loaded.

### Volume Mode

When in Sphere or Cylinder mode, `VolumeOverlay` (`scenes/states/playing/volume_overlay.gd`) renders:

- **Wireframe** — `ImmediateMesh` with `PRIMITIVE_LINES`. Sphere: 3 great-circle rings (XZ equatorial, XY, YZ). Cylinder: bottom ring + top ring + 8 vertical lines. Preview at 50% opacity; locked at full opacity.
- **Fill** — `SphereMesh` / `CylinderMesh` with `TRANSPARENCY_ALPHA` at ~12% opacity (6% during preview). Both the wireframe and fill render after the lo-fi post-process pass (transparent objects bypass `hint_screen_texture`), so both appear crisp as UI overlay elements.
- **Radius label** — `PanelContainer` label at `LAYER_MEASURE_OVERLAY`, positioned at the right edge of the shape and updated each `_process()` frame.

### Click Sound

Placing a waypoint plays `AudioManager.play_tick()` for tactile feedback.

---

## Grid Overlay

The grid overlay projects a procedural grid onto all visible 3D geometry, rendered via a depth-buffer shader. It lives inside the SubViewport (parented to Camera3D) so it receives the lo-fi post-processing effect.

### Visual Design

The grid uses a **cell tint** approach rather than traditional grid lines for readability on bright maps:

- Each cell is filled with a semi-transparent dark neutral color (`color_surface1` from the theme at 65% opacity).
- The fill is **inset** by 10% from cell edges, creating visible gaps between adjacent cells that serve as implicit grid lines.
- During token drags, the hovered cell and the starting cell are highlighted with a brighter blue fill (with edge glow), replacing the neutral tint on those cells.
- Grid lines (`line_color`) are available as an additional layer rendered on top of everything, but currently disabled (0% opacity) since the cell tint inset provides sufficient delineation.
- A height filter prevents the grid from projecting onto board tokens — only surfaces near the floor level show the grid.
- Visibility transitions are **animated** with a 0.2s fade in/out when the grid is toggled.

### Activation

- **G key** — toggles the grid on/off (local per-client) with a fade animation.
- **Auto-show** — appears automatically when the Measure Tool is active or a token is being dragged (configurable via `LevelData.grid_show_on_measure` and `grid_show_on_drag`).
- Auto-hide reverts when the triggering context ends, unless the player has explicitly toggled it on via G.

### Input Hints

| Context              | Hints                  |
| -------------------- | ---------------------- |
| Default gameplay     | `G: Grid`, `M: Measure`|
| Dragging (snap on)   | `Scroll: Height`, `Shift: Free Move` |
| Dragging (snap off)  | `Scroll: Height`       |

### Configuration

Grid appearance and behavior are configured via `LevelData` properties in the **Grid** export group. `GameMap.configure_grid()` applies these settings to the overlay and drag system when a level loads or the GM changes settings. Floor level for the height filter is computed automatically (defaults to Y=0).

---

## Drag Ruler

The drag ruler displays a distance line from a token's starting position to its current drag position. It activates automatically during token drags.

### Visuals

- Solid blue-white line from start to current position.
- Endpoint circles at both ends.
- Distance label at the midpoint (dark backdrop, same style as MeasureTool).
- When grid snap is active, shows cell count alongside distance (e.g. "6 cells / 30 ft").

### Rendering

Uses `MapOverlayUtils` for overlay and label creation. Renders on `Constants.LAYER_DRAG_RULER` (layer 7), below the measure overlay (layer 8). Uses the same dirty-flag + camera-tracking pattern as MeasureTool for efficient updates.

### Lifecycle

- Created by `GameMap.setup_drag_ruler()` during level setup.
- Connects to `DragAndDrop3D` signals: `dragging_started`, `dragging_stopped`, `dragging_cancelled`.
- Deactivated automatically on level clear via `GameMap.reset_grid_state()`.

---

## Token Context Menu

Right-click a token to open `TokenContextMenu` (`scenes/states/playing/token_context_menu.tscn` /
`.gd`), managed by `TokenContextMenuController` (`scenes/states/playing/token_context_menu_controller.gd`),
a sub-component of `GameMap`.

### Content

- **Title** — shows the token's current name (`target_token.token_name`).
- **HP adjustment, visibility toggle, reset transform** — existing actions.
- **Rename** — a `LineEdit` (`%RenameInput`) pre-filled with the current name, plus a button;
  pressing Enter (the LineEdit's `text_submitted` signal) submits the same as clicking the button.
  GM-only.
- **Duplicate** — GM-only button.
- **Remove Token** — GM-only button, styled as the danger variant.

### GM Gating

Rename, Duplicate, and Remove Token (plus their separator) are visible only when
`NetworkManager.has_gm_access()` is true — `TokenContextMenu._update_menu_content()` sets
`rename_container.visible`, `duplicate_button.visible`, and `remove_button.visible` accordingly.

### Remove: Confirmation and Undo

Requesting Remove closes the context menu first (`_context_menu.close_menu()`) before showing
`UIManager.show_danger_confirmation("Remove token", ..., "Remove")` — the menu closes before the
dialog opens so its own click-outside handler doesn't swallow the dialog's first click. On confirm,
`TokenContextMenuController._remove_token_confirmed()` records
`GameplayActionHistory.record_token_removal(token, TokenState.from_board_token(token))` (when the
local peer has GM access) before calling `LevelPlayController.remove_token(token)`, so Ctrl+Z
restores both the token and its level placement.

### Rename and Duplicate

- **Rename** emits `rename_requested(token, new_name)`; the controller records a `"token_name"`
  property change via `GameplayActionHistory.record_property_change()` — so Ctrl+Z restores the old
  name through `GameplayActionHistory.set_rename_callable()` routing to `TokenSpawner.rename_token()`
  — then calls `LevelPlayController.rename_token()`.
- **Duplicate** emits `duplicate_requested(token)`; the controller calls
  `LevelPlayController.duplicate_token(token)`, which spawns a copy of the same asset one grid cell
  over in +X (`LevelData.grid_cell_size`, falling back to 1.5 m without an active level), then copies
  name, max health, and current health onto the new token.

See [ARCHITECTURE.md](ARCHITECTURE.md) Token System / TokenSpawner for the storage-level details.

---

## Asset Browser

`AssetBrowserContainer` (`scenes/states/playing/asset_browser_container.gd`) wraps `AssetBrowser` and
manages the overlay.

- **Stays open while placing** — dragging an asset out of the browser (`asset_drag_started`) no
  longer closes the overlay, so the player can see the viewport behind it and start another drag
  without reopening it. Double-click placement (`asset_selected`) still closes it.
- **Search filters persist** — filters are not cleared when the browser closes and reopens; they're
  only cleared when the player clears them explicitly.

---

## CanvasLayer Ordering

UI elements are organized by layer for proper z-ordering. All layer numbers are defined in `autoloads/constants.gd` under `LAYER_*` constants.

| Layer | Constant               | Component          | Purpose                            |
| ----- | ---------------------- | ------------------ | ---------------------------------- |
| -1    | `LAYER_WORLD_VIEWPORT` | WorldViewportLayer | 3D scene rendering (SubViewport)   |
| 2     | `LAYER_APP_MENU`       | AppMenu            | Always-visible buttons (bottom-right) |
| 2     | `LAYER_GAMEPLAY_MENU`  | GameplayMenu       | In-game UI, edit drawer, player list |
| 3     | `LAYER_LEVEL_EDITOR`   | LevelEditor        | Level editor overlay (full-screen) |
| 5     | `LAYER_LOBBY`          | Lobby              | Host/client lobby (centered)       |
| 7     | `LAYER_DRAG_RULER`     | DragRuler          | Movement distance line during drag  |
| 8     | `LAYER_MEASURE_OVERLAY`| MeasureTool        | Distance measurement lines & labels |
| 10    | `LAYER_PAUSE`          | PauseOverlay       | Pause menu                         |
| 1     | `LAYER_INPUT_HINTS`    | InputHints         | Keybinding hints (bottom-center)   |
| 90    | `LAYER_TOAST`          | ToastContainer     | Notifications (bottom-center)      |
| 95    | `LAYER_SETTINGS`       | SettingsMenu       | Settings overlay (centered)        |
| 100   | `LAYER_DIALOG`         | ConfirmationDialog | Modals, download queue             |
| 105   | `LAYER_LOADING`        | LoadingOverlay     | Loading screen (full-screen)       |
| 110   | `LAYER_TRANSITION`     | TransitionOverlay  | Scene transitions (full-screen)    |

Higher layers appear on top of lower layers. When creating CanvasLayers in code, always use `Constants.LAYER_*` constants instead of magic numbers.
