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
- [Menu Design Language](#menu-design-language)
- [Title Hub](#title-hub)
- [Settings Menu](#settings-menu)
- [Pause Menu](#pause-menu)
- [AudioManager](#audiomanager)
- [Overlay & Modal System](#overlay--modal-system)
- [LevelEditPanel (In-Game Edit Mode)](#leveleditpanel-in-game-edit-mode)
- [Measure Tool](#measure-tool)
- [Submerged Token Marker](#submerged-token-marker)
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
| `AUTHORING`    | Building or dressing a map in the game view (offline only); see [Authoring Mode](#authoring-mode) |

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

The dialog's title comes from a `MenuHeader`; the footer is end-aligned with Cancel before Confirm,
and this is the only screen where `Success` and `Danger` fills remain (see
[Menu Design Language](#menu-design-language)).

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

Contextual keybinding hints in a bar at the bottom centre of the screen (`InputHints`,
`scenes/ui/input_hints.tscn` / `.gd`, owned by `UIManager`). Each hint is a chip: the key in a
`KeyChip` key cap (the help overlay's shortcut style) beside a `Caption` action label.

- **Placement**: the bar (`%HintBar`) is anchored to the bottom edge and stays there. Its
  entrance and exit tween its alpha and `offset_transform_position` (12 px below its place to
  0), a draw offset that never touches anchors or offsets; tweening `position` instead rewrote
  the offsets against the top anchor and parked the bar at the top of the screen until
  2026-10-09. The bar slides only when it appears (first hint) or empties (last hint gone).
- **Diffing**: hint changes are diffed by key, never rebuilt. A kept key's chip stays the same
  node (a new action relabels it in place), a new key's chip fades in, a removed key's chip
  fades out where it stands and is freed, and a key re-added while its chip is still fading out
  takes that chip back. So a hint toggled mid-drag (Shift: Free Move) moves nothing else.
  `remove_hint` on a key that is not shown does nothing.

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

## Menu Design Language

Every menu screen -- the title, the pause menu, both lobby screens, Settings, the confirmation
dialog, and the help overlay -- shares one structure, built from three primitives in
`scenes/ui/primitives/`:

- **`MenuHeader`** opens the screen: `setup(title, caption = "", closable = false)` sets a
  sentence-case title, an optional muted caption, and an optional close button on the title's
  right, with a rule underneath. Callers hold onto `title_label`, `caption_label`, and
  `close_button` when they need to read or reach them later.
- **`UiActions`** builds the rows: `UiActions.primary()` for the one tall accent action a screen
  opens with, `UiActions.secondary()` for every other row. Exactly one primary per screen -- the
  rest are `Secondary` with an icon.
- **`UiMotion.stagger_in(UiMotion.visible_children(box), self)`** fades and lifts the body's
  visible children into place, one after another, once the screen has animated in.

Semantic colour survives only where it started: `Success` and `Danger` fills belong to
`ConfirmationDialogUI`'s confirm button alone. A destructive menu row (Return to Title, Quit Game,
Leave, Reset to Defaults) stays `Secondary` -- the confirmation dialog that follows it is what
carries the red.

Footers are an `HBoxContainer` with `alignment = ALIGNMENT_END`: secondary actions first, the
primary action last, so they hug the right edge.

See [THEME_GUIDE.md's UI Primitives](THEME_GUIDE.md#ui-primitives) and
[Button Variants](THEME_GUIDE.md#button-variants) sections for the full API and variant table.

---

## Title Hub

`TitleScreen` (`scenes/states/title_screen/title_screen.gd`) is the app's entry screen. It has two
zones: a left column of actions and a right zone showing the player's saved levels as cards, with
the d20 sub-viewport as a dimmed backdrop behind both.

### Left Column

Built by `_build_left_column()`. **Host Game** and **Join Game** are tall primary actions
(`UiActions.primary()`: icon, bold label, caption underneath); below a separator, **Play Solo**,
**Level Editor**, **Build Map**, **Avatars**, **Settings**, and **Quit** are compact secondary actions
(`UiActions.secondary()`). Build Map emits `build_map_requested`, which Root turns into the
new-map dialog and then [authoring mode](#authoring-mode). Avatars opens the
[avatar roster](#avatar-library).
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

### Avatar Library

Players make their avatars ahead of time and place them in any game (user decision,
2026-10-06). The library is local to the machine (no Steam Cloud yet).

Avatars are a dev feature for now (user, 2026-10-08: not ready for testers).
`DevFeatures.avatars` (`utils/dev_features.gd`) is on only in runs of the editor binary
(the editor, CLI tests, render jobs) and off in exported builds, where the title screen's
Avatars button, the browser's Avatar tab and Edit Avatar are absent. Saved levels and
synced games with avatar tokens still load and draw them. To release avatars, delete the
flag and its three checks.

- **`AvatarLibrary`** (`utils/avatar_library.gd`): one JSON file per avatar in
  `user://avatars/<id>.json`: `{"format": 1, "id": "av_<ms>_<hex>", "name", "recipe",
  "created", "updated"}` (unix seconds; `recipe` per `ASSET_PIPELINE.md` section 10,
  normalised on load). `list()` (newest made first), `get_entry`, `save` (new, or update
  by id), `duplicate_entry`, `rename`, `delete`. A broken, foreign or unknown-format file
  is skipped with a warning and left on disk. Every call takes an optional directory, and
  the static `directory` can be pointed elsewhere (tests, render jobs); `events().changed`
  fires after every write.
- **`AvatarRoster`** (`scenes/ui/avatar_roster.gd`/`.tscn`): the title screen's Avatars
  panel. An `AvatarGrid` of `AvatarCard`s (rendered figure, name, overflow menu with Edit,
  Duplicate, Delete; Delete confirms), led by a "Make an avatar" card; an empty library
  shows an invitation. Its height follows the cards. A card opens the builder
  (`AvatarBuilder.open_for_library`), which needs no token or level and saves into the
  library on confirm.
- **`AvatarThumbnails`** (`scenes/states/playing/avatar_thumbnails.gd`): one renderer under
  the tree root draws a figure a frame on the builder preview's stage and framing, cached
  per recipe for the session.
- **In game**, the Add Token browser's Avatar tab (`AvatarTab`) lists the saved avatars
  first (one click places, `GameplayMenuController.place_library_avatar`) above "Make an
  avatar". Every builder confirm in a game offers "Save to my avatars", ticked
  (`AvatarSaveChoice`); for an avatar placed from the library (the token's local
  `avatar_library_id` meta) it offers "Update <name>" (default) or a new avatar.

### Level Cards

Saved levels are three primitives under `scenes/ui/primitives/`:

- **`LevelCard`** (extends `Button`, `Card` theme variation) -- a thumbnail, name, and caption ("N
  tokens, edited <relative time>", built by the static `caption_for(info, now_unix)`). Press selects
  (`toggle_mode = true`); double-click or Enter activates. The overflow menu (the `dots-vertical`
  icon in the thumbnail's corner) offers Edit (Level Editor), Edit map (authoring mode; the grid
  forwards it as `level_map_edit_requested`, the title as `edit_map_requested`), Rename (swaps in
  an inline `LineEdit`), Duplicate, and Delete -- Delete is disabled while `locked` is true (the level currently being played). Signals:
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

`LobbyHost` and `LobbyClient` (`scenes/states/lobby/lobby_host.gd` /
`scenes/states/lobby/lobby_client.gd`) both extend `AnimatedCanvasLayerPanel` with
`play_sounds = false` and a no-op `_on_after_animate_out()` -- `Root` frees them directly on state
exit, so a stray `animate_out()` must never free the lobby a second time.

The host screen opens with its `MenuHeader` ("Host a game"), then Your Name and Room Code fields,
the room code in a `KeyChip` with a copy button (`DisplayServer.clipboard_set()`, toast "Code
copied") and an invite button beside it, a framed thumbnail strip showing the pending level --
thumbnail, name, token-count caption, set via `set_level(level)` -- with a Change button that opens
a `LevelPickerDialog` and emits `level_change_requested(level_info)` when a different level is
chosen, the Players list, and an end-aligned footer with Cancel and Start (Start is the only accent
action).

The join screen opens with its `MenuHeader` ("Join a game"), captioned Your Name and Room Code
fields, a full-width Connect button, and a footer button that reads "Back" while the form is up and
"Leave" once a connection attempt is under way or connected (`_set_footer_action()`) -- the same
button, renamed with the situation.

Both screens guard their network calls for tests: `LobbyHost.start_hosting` (default `true`) gates
`NetworkManager.host_game()` and its signal connections, and `LobbyClient.connect_network` (default
`true`) gates the equivalent client-side connections. Tests set these `false` before adding the
screen to the tree so headless runs never reach the network layer.

---

## Settings Menu

Tabbed settings interface (`scenes/ui/settings_menu.gd`) with six sections: Audio, Graphics, Grid,
Controls, Network, and Updates. Sections are chosen from a labelled `IconRail` (`SECTIONS` in
`settings_menu.gd`) rather than the `TabContainer`'s own tab bar, which is hidden
(`tabs_visible = false`); the rail drives `tab_container.current_tab` instead. The menu selects
its first section in `_ready`, before the rail has laid out its items; the rail's accent
underline is placed from the items' laid-out rects after every sort of the rail
(`sort_children`), so it sits under the selected section from the first frame (it read every
item at x = 0 and sat at x = 18 under no section until 2026-10-09). Graphics keeps
foliage budget and renderer options under an Advanced `Foldout`, whose 16 px chevron sits
inline left of its title. The header is a closable
`MenuHeader`; `close_button` is `header.close_button`. Keyboard section switching (the native tab
bar's Ctrl+Tab) is not available while the tab bar is hidden and the rail items are not focusable; a
keyboard-navigation pass is a known follow-up.

The footer is end-aligned: `Reset to Defaults` is a quiet `Secondary` action, `Apply` carries the
accent.

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

The scene holds only the shell: `_on_panel_ready()` builds a `MenuHeader` ("Paused" / "Esc to
resume") and the rows through `UiActions`. **Resume** is the only accent action, continuing play.
**Edit Level** and **Change Level** are still GM-gated (`NetworkManager.has_gm_access()`) --
Edit Level resumes and opens the level editor, Change Level opens `LevelPickerDialog` and swaps the
level without leaving the current game (see Change Level below). **Settings** opens the settings
menu. **Return to Title** and **Quit Game** are `Secondary` and still confirm before acting.

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

### Playing Sounds

```gdscript
AudioManager.play(&"confirm")   # any sound declared in tools/sfx_spec.py
```

`play()` is the only entry point. Gain, pitch jitter, cooldown and priority come from the
manifest (`assets/audio/sfx_manifest.json`, written from `tools/sfx_spec.py`), and one frame's
requests coalesce to the highest-priority sound per bus, so a button that confirms and closes a
dialog is heard once. Names, tiers and how to add a sound: `docs/SOUND_EFFECTS.md`.

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

### Adding a Sound

A spec entry in `tools/sfx_spec.py`, `tools/generate_sfx.py --install`, and a
`play(&"name")` call; see "Adding a Sound" in `docs/SOUND_EFFECTS.md`.

---

## Overlay & Modal System

UIManager tracks registered overlays and the app state for ESC key handling.

### Priority Order (ESC key)

1. **Overlays** - anything registered via `register_overlay()`: Level Editor, Settings, Help,
   Asset Browser, the `LevelEditPanel` Visuals drawer, the `AuthoringPanel` (for the whole
   authoring session), etc. `UIManager._unhandled_input()` closes
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

### Help Overlay

`HelpOverlay` (`scenes/ui/help_overlay.gd`, triggered by F1) is built entirely in code from
`_get_shortcut_data()`: a `MenuHeader` ("Keyboard shortcuts", closable), then one `SectionHeader`
per group (Navigation, Tokens, Tools, General) with its rows underneath, each row a `KeyChip`
140 px wide (`CHIP_MIN_WIDTH`) holding the key label next to the action text.

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
| `LevelEditPanel` | RIGHT | rail of seven icons | Real-time level editing during gameplay (see below) |
| `AuthoringPanel` | LEFT | rail of three tools + four footer actions | Authoring mode's tools, save and leave (see [Authoring Mode](#authoring-mode)) |

Rail-mode helpers beyond badges: `set_rail_item_enabled(id, on)` (a tool not available yet),
`set_footer_item_enabled(id, on)` (Undo with nothing to undo) and `set_footer_badge(id, on)`
(Save with unsaved changes).

See `THEME_GUIDE.md` for styling details.

---

## Authoring Mode

Root's `AUTHORING` state (`scenes/states/authoring/`; flow and data in
[ARCHITECTURE.md's Authoring Flow](ARCHITECTURE.md#authoring-flow)). The screen is the game
view itself, with one piece of chrome: the `AuthoringPanel` rail on the left edge.

### New map dialog

`NewMapDialog` (`new_map_dialog.gd` / `.tscn`, an `AnimatedCanvasLayerPanel` on
`LAYER_DIALOG`) is the only question before a new map: a `MenuHeader` ("New map", closable),
a Size `TileField` (100 / 150 / 200 ft, 20 / 30 / 40 squares in the tooltips), a Start from
`TileField` of the palette biomes' thumbnails plus Bare ground (the bare surface's albedo),
three columns, `photo_icons` so pictures draw untinted at their size, and a caption naming
the ground the choice implies ("Ground: forest floor"). Under it a Landform `TileField`
(P5-3): one glyph tile per `StartingLandform.KINDS` entry, in that order and all on one row
(`columns` = the kind count), tile ids `landform_<kind>`, labels from `StartingLandform.NAMES`,
icons `assets/icons/ui/landform-<kind>.svg`, and a caption under the row that is the chosen
kind's `CAPTIONS` entry (it describes the landform, never a feature this seed may not draw).
The default is `StartingLandform.DEFAULT` (Valley) with a biome and Flat with Bare ground:
picking Bare ground switches the row to Flat, and picking a biome again brings back the
landform shown before, unless the author picked one in between. Nothing to type. The footer
is Cancel (Secondary) and Create map (the one primary). Temperate forest is preselected.
`map_chosen({size_ft, biome_id, landform, seed})` with a fresh seed; while a landform other
than Flat opens, the loading line names it ("Shaping the valley...",
`NewMap.opening_status`); Escape, Cancel and the close button
emit nothing. It registers its backdrop as an overlay like `LevelPickerDialog`.

### Tool drawer

`AuthoringPanel` extends `DrawerContainer` (LEFT, rail mode, 320 px). Rail items: Biome
(`trees`), Thin / Clear (`eraser`), Place (`tree`), Sculpt (`mountain`), Paint (`brush`),
Water (`droplet`), Bridge (`building-bridge`).
Footer items: Undo
(`arrow-back-up`) and Redo (`arrow-forward-up`), disabled while `AuthoringHistory` has
nothing to offer; Save (`device-floppy`, badged while there are unsaved changes); Leave
(`door-exit`). Item ids double as node names for `game_click_control`: `biome`,
`thin_clear`, `place`, `sculpt`, `paint`, `water`, `bridge`, `undo`, `redo`, `save_map`,
`leave_authoring`. On a
dressed Blender map Sculpt and Paint are disabled and their tooltips say why ("Sculpt: not on
a Blender map, whose ground is the map file's"; `set_sculpt_available`,
`set_paint_available`, `DrawerContainer.set_rail_item_tooltip`), since the ground there is
the GLB's own (`AuthoringEditor.can_sculpt()` / `can_paint()`). Water there is disabled the
same way unless the document already has water painted over the GLB, which it can still
erase: then the rail item stays enabled with a tooltip saying so, and the River, Pond and
depth tiles are disabled (`set_water_available(carves, has_water)`). Bridge there is disabled
the same way unless the document has water ("Bridge: crosses water made with the Water tool;
a Blender map's own water is part of the map file"; `set_bridge_available`): crossings snap
to document water, and a GLB's water plane is not in the document. The drawer content is a Map name `LineEdit`
(`MapNameEdit`, the one text field; placeholder "Untitled map") above a `PaneStack` with one
pane per tool. Each pane is a `MenuHeader` with a short caption, a wrapped caption line
saying the tool's gestures (`BiomeHint`, `ThinHint`, `PlaceHint`; MenuHeader captions do not
wrap, so long text there widens the drawer past its closed position), what the tool needs,
and nothing numeric in the main flow:

- **Biome**: `BiomeField` lists the palette biomes (two columns, labels trimmed to the last
  two words, full name in the tooltip). Picking a tile emits `biome_selected`: the Biome brush
  paints that biome, its assets and ground surface start loading in the background, and its
  Place group opens.
- **Thin / Clear**: nothing to pick.
- **Place**: one `Foldout` per palette biome headed by its thumbnail (`Foldout.icon`), each a
  three-column `TileRow` with a tile per species big enough to place by hand (large, medium
  and small size classes; ground cover is only painted). Tile ids are
  `<biome id>|<species key>`, labels read "Dwarf pine", icons are the `tree` / `leaf` /
  `grain` glyphs by kind. One selection across all groups; picking emits `place_selected`.
  Per-asset thumbnails would read better than glyphs; they could be rendered once at startup
  from the palette GLBs (not built).
- **Sculpt**: `SculptField`, four tiles in one row: Raise (`arrow-bar-up`), Smooth
  (`wave-sine`), Flatten (`fold`), Tier (`stairs-up`); ids and node names `sculpt_raise`,
  `sculpt_smooth`, `sculpt_flatten`, `sculpt_tier`. Raise is preselected. Picking a tile emits
  `sculpt_selected(op)` (a `HeightBrush` operation) and activates the Sculpt brush. The hint
  line (`SculptHint`) says the modifiers. No numbers in the main flow.
- **Paint** (P3-6): three `TileField`s of palette surface swatches, grouped by the surface's
  role: Built (`PaintBuiltField`: Cobblestone, Dirt track, Flagstone, Planks, Stone tiles),
  Ground (`PaintGroundField`: Grass, Moss, Sand, Mud and the other ground surfaces) and Rock
  (`PaintRockField`: Rock, Basalt, Sandstone). Built comes first because paths and yards are
  what the tool is mostly for. Three columns, `photo_icons`, the swatch a 52 px crop of the
  surface's albedo (`SwatchTextures.palette_thumbnail`), readable labels
  (`AuthoringPanel.surface_label`: "dirt_road_packed" reads "Dirt track"), and a tooltip
  saying what painting it does (a built surface clears the plants under it; ground covers
  walkable ground; rock restyles a face). Tile ids and node names are `paint_<surface>`. One
  selection across the groups; Dirt track is preselected, so the tool paints at once.
  Picking a tile emits `paint_selected(surface)`, which warms the surface's textures
  (`AuthoredTerrain.warm_surface`) and activates the Paint brush. The swatches cost one
  texture decode each, so `ensure_paint_tiles()` builds them once, under the loading screen
  (the controller calls it) or on the pane's first show. When all eight paint slots hold
  paint, the tiles of surfaces not on the map are disabled and their tooltip says why
  ("All 8 paint slots hold paint. Erase one surface completely (Ctrl+drag) to free a slot.";
  `set_paint_limits`), and a refused press shows the same line as a warning toast. The hint
  line (`PaintHint`) says the gestures, that paths stop at rock faces (climb with a ramp) and
  that built surfaces clear plants.
  **Built order per map (2026-09-27):** the Built tiles show the path surfaces of the biomes
  on the map first: the palette's `path_surfaces` (ASSET_PIPELINE section 9) of each biome in
  `MapDocument.biome_ids` order, then of the base surface's biome (the palette's first biome
  on it), unioned and deduplicated, then every other built surface in palette order
  (`AuthoringPanel.paint_order`; it orders, never filters). With no biome listing paths the
  order is the palette's. The controller re-orders on every edit, undo and redo
  (`AuthoringController._refresh_paint_order` -> `AuthoringPanel.order_paint_tiles`, a no-op
  while the biome list is unchanged; tiles are moved, not rebuilt). Until the author picks a
  Paint tile in the session, the preselected surface follows the order (the first listed
  path, else Dirt track), so a badlands map starts on its own track rather than one that
  vanishes on red sand; once picked, re-ordering never changes the selection.
- **Water** (P4-4, `WaterToolPane`, `water_tool_pane.gd`): a Shape `TileField` with River
  (`ripple`, "Draw a river: it flows the way you draw it, always downhill; a steep drop makes
  a waterfall", P4c-5) and Pond (`circle-dashed`, "Paint a pond or a lake: still water in a
  basin"), a Depth `TileField` with Ankle (`shoe`), Waist (`walk`) and Deep (`swimming`), and
  under it a one-line hint of what the depth means for tokens ("Ankle deep: a stream tokens
  wade across.", "Waist deep: tokens wade, slowly.", "Deep: tokens swim, floating at the
  surface."). Tile ids and node names `water_river`, `water_pond`, `water_ankle`,
  `water_waist`, `water_deep`; River and Waist are preselected. Picking a tile emits
  `water_shape_selected` / `water_depth_selected` and activates the Water brush. The hint line
  (`WaterHint`) says the gestures, that a river falls by itself over a steep drop, that the
  ground stays carved when water is erased, and that sculpting never makes or moves a fall
  (P4c-5 wording: "River: draw its line from where the water comes to where it goes; over a
  steep drop it falls by itself. Pond: paint an area; start inside a pond to grow it.
  Shift+wheel or [ and ] set the width. Hold Ctrl as you press to erase water; the ground
  stays carved (Sculpt's Smooth fills a dry channel). Sculpting never makes or moves a
  waterfall: erase the river and draw it again."). No numbers in the main flow: its
  `Advanced` foldout (`WaterAdvanced`) holds Width (the full channel, twice the brush radius,
  "Stream" / "River") and Flow (the river's flow speed 0 to 2, "Still" / "Rushing"), values
  hidden.
- **Bridge** (P4b-2, P4d-3, `BridgeToolPane`, `bridge_tool_pane.gd`): a Crossing `TileField`
  (`BridgeKindField`, four columns, one row of 64 px tiles in the 320 px drawer) with Planks
  (`bridge-plank`, "A plank footbridge: arched boards on posts, bank to bank"), Stones
  (`stepping-stones`, "Stepping stones: flat rocks one stride apart, just above the water"),
  Arch (`building-bridge`, "A stone arch: a barrel of the biome's rock with a paved deck and
  parapets, bank to bank") and Ford (`ford`, "A ford: a gravel bar just under the surface with
  marker stones, for wading across"); ids and node names `bridge_plank`, `bridge_stones`,
  `bridge_arch`, `bridge_ford`; Planks preselected. Picking a tile emits
  `bridge_kind_selected(kind)` and activates the Bridge tool. The hint line (`BridgeHint`) says
  the gesture, that bridges cross calm water and not a waterfall (P4c-5), what an arch and a
  ford need (P4d-3), the width keys,
  Ctrl-click to remove, and that a crossing follows later edits and goes with its water
  (wording: "Drag a line across a river or pond, from one bank to the other: the crossing
  finds the banks and sizes itself. Bridges cross calm water, not a waterfall. Arches cross
  like planks; a ford needs wadeable water (its width runs along the river). Shift+wheel or
  [ and ] set its width. Hold Ctrl and click a crossing to remove it. A crossing follows later
  edits to its banks and goes when its water does."); while the map has no water a second
  line (`BridgeWaterHint`) says to make a river or pond first. No numbers and no Advanced foldout: a crossing sizes itself
  to the water, and its width is Shift+wheel. **Why its own rail item, not a tile in Water:**
  a crossing is an object laid over water with its own gesture (a line placed whole on
  release) and its own Ctrl (remove a crossing, not erase water); as a third Shape tile beside
  River and Pond, the Depth tiles and Width row would sit over it meaning nothing, and a
  newcomer scanning the rail for "bridge" would not find it under a droplet.
- Biome, Thin / Clear, Sculpt and Paint end in an `Advanced` foldout with Size (1 to 12 m, "Small" /
  "Large") and Strength (0.25 to 2x, "Gentle" / "Strong") `PropertyRow`s, values hidden like
  the Visuals drawer's; all follow the gestures (`set_brush_values`).

Picking a rail item selects and activates that brush (`tool_selected`); the Biome brush waits
for a biome. The active tool's rail item stays tinted (`set_active_tool`,
`DrawerContainer.set_rail_item_active`) while the drawer is closed, so the map can be painted
full screen. Save keeps the drawer open and shows a success toast.

### Brushes and gestures

`BrushTool` (`scenes/states/authoring/brush_tool.gd`) is the one brush, in seven modes; its
input table is the pure `BrushTool.decide()`, and the Sculpt operation of a press is the pure
`BrushTool.sculpt_op(tile, ctrl, shift)`; the Water mode's work is `WaterBrush`'s and the
Bridge mode's `BridgeBrush`'s:

| Gesture | Biome | Thin / Clear | Place | Sculpt | Paint | Water | Bridge |
|---------|-------|--------------|-------|--------|-------|-------|--------|
| Left drag | paint the biome | thin; with Ctrl at the press, clear | click places a prop (random asset of the species, random yaw), drag while pressed turns it to face the pointer | the tile's operation: Raise a soft mound (Ctrl at the press: lower), Smooth toward the local mean, Flatten to the ground height under the press, Tier (below) | paint the picked surface with the soft falloff; with Ctrl at the press, erase every painted surface back to the automatic ground and the biome ground | River: draw the line from where the water comes to where it goes (a ribbon previews it; the release carves it); Pond: paint its area (a press inside a pond extends it); with Ctrl at the press, either tile: erase water (a river whole, pond area) | draw a line across water: the snapped crossing previews live, the release places it; a line that makes none shows why beside the cursor, and a release there says it in a toast |
| Ctrl | - | - | - | - | - | - | held while hovering: the crossing under the pointer is outlined red ("Remove plank bridge"); Ctrl+click removes it |
| Shift at the press | - | - | - | Smooth, whichever tile is picked | - | - | - |
| Hold still while pressed | builds strength (up to 4x after 2 s) | same | - | same (Raise keeps building; Tier is already whole) | same (toward full cover) | Pond: the dab spreads (up to 1.35x) | - |
| Plain wheel | camera zoom | camera zoom | camera zoom | camera zoom | camera zoom | camera zoom | camera zoom |
| Shift+wheel, `[` `]` | brush size, 1 to 12 m (remembered for the app session) | same | over a placed prop: its scale within the species' range (at least +-25 %) | brush size | brush size | the river's width or pond brush (never below the depth's narrowest channel: ankle 0.44, waist 1.33, deep 2.96 m half-width) | the crossing's width (per kind: plank deck 0.8 to 3 m, stones 0.4 to 1.2 m, arch deck 1.2 to 3 m, ford bar 1.5 to 4 m along the river; 12 % a notch) |
| Right click, Escape | cancel the stroke in progress (reverted); idle: right click puts the brush down, Escape goes to the drawer | same | over a placed prop: remove it; during a placement: cancel it | same as Biome | same as Biome | same (a river being drawn is dropped) | same (a line being drawn is dropped) |
| Delete / Backspace | - | - | remove the prop under the pointer | - | - | - | - |
| Ctrl+Z / Ctrl+Y | undo / redo one stroke | same | one placement (place and turn), removal, or scale gesture | one stroke | one stroke | one river, pond stroke or erase | one placement or removal |

Bridge (P4b-2). The drawn line is dashed from the press to the pointer, over a solid dark
keyline in screen pixels so it reads on dark foliage and pale sand alike (P4b-3: the first
1.75 px dash was lost over a forest floor); once it makes a
crossing (a short line near the water already does: the snap reaches 8 m past its ends) the
ghost shows exactly what the release places, snapped to the first dry bank each side: a
deck's outline along its arch with plank ticks (planks in warm wood, a stone arch in pale
stone), each stepping stone's outline at its top, or a ford's bar as a gravel band at its
crest (P4d-3), and a dot on each bank anchor. The readout beside the cursor says
the kind and the span in the level's units ("Plank bridge  16 ft", "Stone arch  20 ft"), or
idle its width ("Stepping stones  4 ft wide", "Ford  8 ft wide", to the half unit; a ford's
width runs along the river). A line that makes nothing turns red, heavier
and with a dot at both ends, and the
readout gives the reason in plain words (`BridgeBrush.refusal_text`): "No water to cross here.
Drag from bank to bank over a river or pond.", "No dry bank to land on at one end. Try a
narrower spot.", "Too wide to cross (at most 79 ft). Try a narrower spot.", "Too close to the
waterfall. Bridges cross calm water." (P4c-5: within 1 m of a fall's face or its foam ring,
`systems/crossings.md`), "Too deep to ford. Fords cross wadeable water." (P4d-2: a ford's
line over deep water), or, for a click, "Drag a line from one bank across the water to
the other."; releasing there shows the same as a warning toast. The tool's pointer ray sees crossings (the other brushes skip them), so Ctrl
hovering a deck or a stone picks it where it is drawn. Crossings follow later edits (Sculpt,
Water; `systems/crossings.md` "Following edits"): re-anchored in place, or removed with their water, with
an info toast ("A crossing lost its water and was removed. Undo brings both back.") and one
undo for both. The tool starts loading the crossing textures when it opens and makes their
materials 0.4 s later, so the first placement costs about 7-9 ms of main thread (plan 2 ms,
geometry and nodes 3 ms), not 25-30.

Water (P4-4). The river flows the way it was drawn (its first point is upstream), except that
a stroke drawn uphill (its end standing 0.75 m or more above its start) is reversed, so water
always runs downhill (P4c-5; `WaterBrush.flow_line`, two ground reads per frame, so the ribbon
and the carve agree). A river drawn over sloped ground is split into flat reaches joined by
small rapids, and over a steep drop it falls by itself with no control (phase 4c:
`systems/waterfalls.md`); its ends inside the map close in rounded heads.
A river that starts or ends in another river or pond joins it there (a confluence: it is cut
at that water's edge and meets it at its level, or below for an outflow; an end on a
waterfall's face moves into the plunge pool below it), and a line lying all in water is
refused with a toast. The ribbon preview shows the width, a gradient and chevrons the way the
water will really run (downhill, whichever way the line was drawn), and the readout "River
Waist  40 ft" (the line's length in the level's units); Pond shows "Pond  Deep" and its
painted dabs. The F1 help's "Map building" group has a "Waterfall" row (P4c-5): "A river
over a steep drop falls there by itself. Sculpting never makes or moves a fall: erase the
river and draw it again"; its Bridge row reads "Drag across calm water, bank to bank: planks,
stones, an arch or a ford", with an "Arch (Bridge)" row ("A stone arch crosses like planks:
the biome's rock, a paved deck") and a "Ford (Bridge)" row ("A gravel bar for wading: needs
wadeable water; its width runs along the river") after it (P4d-3). The carve
computes on a worker and lands over three frames, so a release never holds the view
(`docs/PERFORMANCE.md` "Water tool"); the ribbon stays faintly
until it lands. Ctrl erases a river whole, every reach of the stroke it touches (drawn red
while held) and the streams that flow into it, rather than cutting a hole mid-channel (to
shorten one, erase it and draw it again), and pond area under the brush (a shrunk pond settles to its new rim). The
ground stays as carved: Sculpt's Smooth fills a dry channel. On a dressed Blender map only
erasing is available (see the rail above).

Paint. A surface covers walkable ground only (the user's cliff-face decision): ground and built
surfaces painted across a tier's face give way to the automatic rock there, so a road painted
over a ledge stops at the edge and resumes on top; paths climb by sculpted ramps (a few Shift
passes across a face). Painting a Rock tile (Rock, Basalt, Sandstone) applies anywhere, so a
face can be restyled deliberately, or bare rock laid on flat ground. Built surfaces and painted
rock clear the plants under them when the stroke is released (they shrink away); a tree just
beside a road keeps standing unless the paint covers its trunk, while tall grass and shrubs
thin out in a metre-wide fringe beside built paint (short grass and flowers stay) so a narrow
path still reads from the game camera. The paint's edge is frayed by a
small warp and noise, so a path reads as worn into the ground rather than laid on it. A quick
pass lays partial cover (a worn trail); lingering fills it in. Eight surfaces can be on a map at
once (see the Paint pane above); erasing one completely frees its slot.

Tier. The press reads the ground height under the pointer and picks a whole tier
(`HeightBrush.tier_target_level`, through `AuthoringEditor.tier_target`): from flat ground or
between tiers, the next tier up (Ctrl: the tier below); from a tier top, that same tier when
the brush reaches lower ground (a stroke from its edge extends it) and the tier above when
the brush is all on the top (a stroke inside it steps up); with Ctrl from a top, the tier
below, or the press tier itself when higher ground is in reach (cutting it down to here). The
target stays that tier for the whole stroke, so passing over existing tiers never climbs.
Every stroke ends exactly on `k * tier_height_m` (5 ft by default) with a rock face at the
ring's edge, a rounded lip and scree at the foot (ARCHITECTURE.md "Sculpting"). The face is
a soft profile (about 66 degrees at its steepest, its toe easing out up to half a metre past
the ring), so a curved or diagonal tier reads as one continuous rock face rather than stair
steps along the sample grid, and the grid overlay's edge follows the lip smoothly.

Smooth softens whatever it touches, a tier's edge included: that is how a face becomes a
ramp (a few passes of a 2.5 m brush across a face lay it back to about 22 degrees). The
middle of a flat top stays flat, since its local mean is itself; to keep an edge crisp, keep
the ring off it.

Rocks survive sculpting: boulders and stones the ground moves under tilt with it while the
stroke is held and stay where they are when it ends, even on a new face or a hill's flank
(never leaning more than 55 degrees, bedded so they never float), breaking up the edge of the
height jump. They become placed props, so the author can turn, scale or remove them with
Place like any other; one undo puts them back as they were. Trees, shrubs, logs and plants
still follow the slope rules.

Sculpting ignores trees: canopies between the camera and the ring dither away (the same
occlusion fade Thin / Clear uses), and the ring re-conforms to the moving ground every frame
while a stroke is held. A still pointer keeps its ground point during a stroke (the ray would
otherwise walk a rising hill toward the camera).

The cursor is a ring on the ground at the pointer with the brush radius, re-conformed to the
ground by downward rays when it moves, drawn on `LAYER_MEASURE_OVERLAY` above the lo-fi pass
with a dark under-stroke and a light over-stroke so it reads on any ground and in either lo-fi
theme. Tint: the biome's thumbnail colour, warm white to thin, red to clear (Ctrl), the accent
for Place (a small marker where a prop will go, red where the prop's base would straddle a
drop of more than 0.25 m, such as a tier's rim, since it is sunk to the lowest ground under
its base so it never floats; a ring around a hovered prop, showing where a click takes it:
the footprint for rocks, logs and shrubs, the trunk for trees, never under 0.35 m so a small
stone is easy to hit, `PropRows.pick_radius`); for Sculpt,
sand to raise or build a tier, blue-grey to lower or cut, the accent to flatten, pale green to
smooth; for Paint, the surface's swatch colour lifted toward white
(`AuthoringController.surface_tint`), red to erase (Ctrl); for Water, a light blue, red to
erase (Ctrl). A faint fill shows the reach (a fan from the centre drawn with explicit indices: a
triangulated outline failed with "Invalid polygon data, triangulation failed" whenever the
conformed ring projected to a self-intersecting outline, over raised ground or a Blender map's
collision), and while a stroke is held an inner ring at half strength brightens as dwell
builds. Tier and Flatten add a small readout under the ring in the level's units
(`BrushTool.tier_readout`: "Tier 1  +5 ft", "Tier -1  -5 ft", "Ground  0 ft"; "Flatten  +3
ft"), shown while hovering too, so the author sees what a press will build before pressing. The ring hides over the drawer. While Thin / Clear (or Sculpt, Paint or Water) is the tool, tree canopies between
the camera and the ring dither away like geometry over a token (the ring is
`OcclusionFadeManager.set_focus()`, radius 1.35x the brush), so the ground being thinned stays
visible under a forest. It rides on the occlusion fade and so follows the player's Occlusion
fade setting (on by default); it is not forced on in authoring, because turning the manager on
also converts a dressed Blender map's materials. RMB never pans while the brush is active (MMB and the
keyboard still do). Ctrl+Z / Ctrl+Y (`ui_undo` / `ui_redo`) go to
`AuthoringController.undo()` / `redo()`, which first ends a gesture in progress. The F1 help
lists these under "Map building".

### Escape and leaving

The panel registers itself with `UIManager.register_overlay()` for the whole session
(`begin_session()`), so Escape never reaches the pause handling. `request_close()` closes the
drawer when it is open; with the drawer closed it asks to leave. Leaving with everything
saved is immediate. With unsaved changes `UIManager.show_choice()` asks "Leave with unsaved
changes?" with Keep editing (Cancel and Escape), Discard (a Secondary alternate action,
`ConfirmationDialogUI.add_alternate_action`), and Save and leave (the confirm button).
Leaving goes back to the title, or to the Level Editor on the same level when authoring was
opened from there.

A leftover autosave is offered when authoring opens ("Recover an unsaved map?": Recover /
Discard); a recovered map starts unsaved.

---

## LevelEditPanel (In-Game Edit Mode)

`LevelEditPanel` extends `DrawerContainer` to provide real-time level editing during gameplay. It slides in from the right edge of the screen and applies all changes immediately to the live viewport.

### Accessing

During gameplay, click a rail item (Sun, Sky, Color, Weather, Water, Film, World) on the right edge of the screen. The panel slides open on that pane; clicking another rail item switches panes without closing the drawer.

### Controls

The drawer is a rail of seven panes (`SunPane`, `SkyPane`, `ColorPane`, `WeatherPane`, `WaterPane`, `FilmPane`, `WorldPane` in `scenes/states/playing/visual_panes/`), each a `LevelEditPane` that owns the fields it edits and implements `load_state(state)` / `write_state(state)` over a `LevelVisualState`:

| Rail item | Primary | Advanced |
|---|---|---|
| Sun | time of day (dawn/dusk hints, 14:30 format), Sun tiles Auto/On/Off, Shadows tiles Off/Hard/Soft, aim on map | direction (bearing), height, colour, energy, softness, darkness, back to generated |
| Sky | sky tiles with thumbnails (ten, two rows of five), preview strip and caption for the hovered or selected sky, Look picker (grouped, swatches, description), fog on/off + amount | background, ambient, fog colour, fog energy, fog height, fog falloff |
| Color | brightness (exposure), contrast, saturation, glow | light energy, fine brightness, tonemap, white point, glow strength, bloom |
| Weather | rain/snow/fog/wind tiles with Light..Heavy intensity | none |
| Water | Look tiles Stylized/Realistic (+Custom), Color tiles Lagoon/Lake/River/Swamp/Ocean/Glacial (+Custom) with painted swatches, Motion tiles Still/Gentle/Lively/Rough (+Custom), Clarity | deep/shallows/foam colours, waves, ripple detail, speed, foam, glint softness, shine, sky reflection, caustics, caustic detail, shallows width, distortion, edge foam cutoff, token ripples, ripple reach |
| Film | Style tiles Off/Subtle/Retro/Heavy (+Custom), pixelate, vignette, grain | colours, dither, colour fade |
| World | scale tiles, cell size (m and ft), Wind tiles Still/Breeze/Gusty (+Custom) | tree/grass speed and amount |

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
signal water_changed(overrides: Dictionary)
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

Placing a waypoint plays `AudioManager.play(&"tick")` for tactile feedback.

---

## Grid Overlay

The grid overlay projects a procedural grid onto all visible 3D geometry, rendered via a depth-buffer shader. It lives inside the SubViewport (parented to Camera3D) so it receives the lo-fi post-processing effect.

### Visual Design

The grid uses a **cell tint** approach rather than traditional grid lines for readability on bright maps:

- Each cell is filled with a semi-transparent dark neutral color (`color_surface1` from the theme at 65% opacity).
- The fill is **inset** by 10% from cell edges, creating visible gaps between adjacent cells that serve as implicit grid lines.
- During token drags, the hovered cell and the starting cell are highlighted with a brighter blue fill (with edge glow), replacing the neutral tint on those cells.
- Grid lines (`line_color`) are available as an additional layer rendered on top of everything, but currently disabled (0% opacity) since the cell tint inset provides sufficient delineation.
- A height filter prevents the grid from projecting onto board tokens — only surfaces near the ground show the grid. On a map with authored terrain, and on a Blender map with relief (its layer-1 collision sampled at load), it is the ground itself: the grid lies on every tier top, slope and clearing (within 0.2 m of the ground under each pixel), while cliff faces, tokens and plants stay clean. A Blender map with no collision, or whose ground is at Y = 0 already (a room or dungeon floor), keeps a fixed band around Y = 0 (see ARCHITECTURE.md "Grid Overlay", "Ground field").
- **Water (phase 4):** where water stands, the grid lies on its **surface**, not the bed, so squares stay continuous across a river or a pond, on authored maps and Blender maps alike (the Blender River level included). The ground field is max(ground, water level) on wet samples; a pixel of bed (or of a wading token's legs) seen through the water is lifted onto the surface along its view ray, and the grid draws after the water (render priority) so it composites over it. The measure tool and the drag ruler measure along the same surface (`systems/water.md` Runtime, "Grid, measure, ruler, cursor").
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

Grid appearance and behavior are configured via `LevelData` properties in the **Grid** export group. `GameMap.configure_grid()` applies these settings to the overlay and drag system when a level loads or the GM changes settings. Floor level for the height filter is computed automatically (defaults to Y=0); a map with a ground field follows its ground instead (`GameMap.set_grid_ground()`: authored terrain through `set_ground_terrain()`, refreshed at load and, in authoring, when a sculpt stroke, undo or redo settles; a Blender map's sampled collision through `MapSourceLoader.fit_grid_ground_async()` at load, or the dressing ground in authoring).

A token dragged across a tier edge with grid snap lands on the tier its snapped cell is on, not the one under the pointer (the drag re-resolves the height at the cell centre on authored terrain; ARCHITECTURE.md "Grid-Snapped Movement"). Dragged into water it stands on the bed in wadeable water and floats at the surface in deep water (the float rule, `systems/water.md` Runtime); the drop indicator lies on the water surface.

---

## Drag Ruler

The drag ruler displays a distance line from a token's starting position to its current drag position. It activates automatically during token drags.

### Visuals

- Solid blue-white line from start to current position.
- Endpoint circles at both ends.
- Distance label at the midpoint (dark backdrop, same style as MeasureTool).
- When grid snap is active, shows cell count alongside distance (e.g. "6 cells / 30 ft").
- When the ground at the target is more than 0.15 m above or below the ground where the drag started, adds the elevation and direct distance like the measure tool (e.g. "2 cells / 11 ft  |  +5 ft elev  |  12 ft direct"). The token's own lift while dragged and scroll height do not count. Over water the ground is the water surface (the grid's), not the bed a wading token stands on or the float height.

### Rendering

Uses `MapOverlayUtils` for overlay and label creation. Renders on `Constants.LAYER_DRAG_RULER` (layer 7), below the measure overlay (layer 8). Uses the same dirty-flag + camera-tracking pattern as MeasureTool for efficient updates.

### Lifecycle

- Created by `GameMap.setup_drag_ruler()` during level setup.
- Connects to `DragAndDrop3D` signals: `dragging_started`, `dragging_stopped`, `dragging_cancelled`.
- Deactivated automatically on level clear via `GameMap.reset_grid_state()`.

---

## Submerged Token Marker

A token the water hides gets a cue on the water surface above it (P4b-0, user ask
2026-09-27: small tokens wading waist-deep water disappeared except for their wake). Code:
`SubmergedMarker` (`scenes/board_token/submerged_marker.gd`), `shaders/submerged_marker.gdshader`,
`WaterSurface.is_submerged` / `submerged_surface`, `TokenWater.update_cue` (a DraggableToken's `water`).

### When it shows

- The token's base is under a water surface and less than 10 cm of it, or a fifth of its
  height if more, stands above (`WaterSurface.SUBMERGED_FREEBOARD_M`, `SUBMERGED_SHARE`): a
  0.71 m creature wading 0.9 m of water, or with only its crest out. Tokens floating in deep
  water ride at the surface and show none; nor do tokens in ankle water or on a bank.
- Authored and Blender water alike: the surface is found with a ray on the water surfaces'
  own layer (`WaterSurface.LAYER`), the bodies both kinds of map carry.
- Checked when a landing, a synced move or a transform settles, when the token enters or
  leaves a water zone, and when its size or shape changes. While a token is dragged (or a
  peer's move is interpolating) it is checked at the predicted landing each time the token
  has moved 3 cm, so the cue follows a token carried along a river and shows before the drop
  that it will go under. Nothing runs per frame for a token at rest.

### Visuals

A flat quad on the water, 3 cm above the surface: a soft dark disc (something is down
there), a bright pale-aqua ring at the token's footprint (1.15 x half its widest collision
extent, 0.3-1.4 m) with a thin dark keyline so it reads on pale shallows and dark depths, and
a slow ripple spreading from the ring every 2.6 s. Line widths have a floor in screen pixels,
so the ring stays crisp at max play zoom. Unshaded, alpha-blended, no depth write, drawn after
the water (`render_priority` 2). Fades in and out over 0.18 s.

### Structure

The marker is a child of the token's `RigidBody3D`, so it hides with the token (a token
hidden from players hides its cue too), but `top_level` (it stands in world space) and left
out of `DraggableToken`'s visual children, so the water sink, the float bob, the drag lean
and the pickup scale never move it. Its size uses the token's logical scale
(`BoardToken.get_logical_scale`), not the near-zero scale of a spawn animation. Purely
visual and local: every peer decides for its own copy. Render check: `jobs/p4b_cue.json`.

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
- **Edit Avatar** — on an avatar token only, for the GM and for a player holding CONTROL on it
  (`TokenContextMenu.can_edit_avatar`). Closes the menu and opens the avatar builder on the token
  (see Avatar Builder below).
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
- **Avatar tab** — the first tab (`AvatarTab`) holds one primary action, "Make an avatar", which
  closes the browser and opens the avatar builder for a new player figure.

---

## Avatar Builder

`AvatarBuilder` (`scenes/states/playing/avatar_builder.tscn` / `.gd`, an `AnimatedCanvasLayerPanel`
added under the window root) is where a player makes or edits their avatar token
(ARCHITECTURE.md "Avatar tokens" has the data flow). The layout is a `MenuHeader`, a name field with
"Surprise me" beside it, a body of three columns, and a Cancel / primary footer:

- **Preview** (left, `AvatarBuilderPreview`): the figure in its own `SubViewport` through the game
  camera's basis, on a slow turntable; dragging on it spins the figure and the turn resumes two
  seconds after the drag. A dark floor disc grounds it.
- **Rail** (`IconRail`, vertical, labelled) and **panes** (`PaneStack`), one at a time, each with
  an `H3` title and a `sparkles` reroll button for its own section:
  - *Pose* (`AvatarStanceTiles`): one tile per kit stance whose icon is the player's own figure in
    that stance, rendered as a white silhouette in a 56x76 `SubViewport` (`UPDATE_ONCE`, redrawn
    after a parts or shape change) so the `Tile` theme tints it like any icon.
  - *Face*: `TileRow`s of the sheet's eye, brow, mouth and mark cells (`AvatarFaceIcons`: each cell
    cropped to its mark and laid over a skin square, so a brow or a blush reads on the dark panel;
    the marks row's first cell is the bare square, "none").
  - *Colours*: an `AvatarSwatchRow` per palette slot (base fill, shadow edge, accent edge when
    picked), labelled Skin, Hair, Eyes, Outfit, Trim, Accent; a slot's row shows only when a chosen
    part paints it (`slots_used`), skin and eyes always, so Leather and Metal appear with the first
    gear part.
  - *Shape*: a `PropertyRow` slider per proportion control (Height, Build, Head) with word hints
    at the ends; values are quantised to 0.05 and reach the figure once a frame.
  - *Parts*: shown only when a slot has more than one part; a `TileRow` of thumbnails per such slot
    (`assets/avatar_kit/thumbnails/<id>.png`).
- **Surprise me** draws a whole recipe (`AvatarSurprise.recipe`) and, unless the player typed a
  name, a new name from `AvatarSurprise.NAMES`; a new avatar starts from a random `AvatarPresets`
  recipe, never a blank figure.
- **Modes**: `open_for_new` emits `create_confirmed(recipe, name)`; `open_for_token` previews every
  pick on the placed token, puts the original back on Cancel (or ESC, or the header's close) and
  emits `edit_confirmed` for the context menu controller to commit as one undo entry. The panel
  registers its backdrop with `UIManager` so ESC cancels.

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
