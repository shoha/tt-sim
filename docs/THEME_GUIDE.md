# Dark Theme Usage Guide

This guide explains how to use the theme variants defined in `dark_theme.gd` to create consistent, well-organized UIs.

> **Related Documentation:**
>
> - [UI Systems Guide](UI_SYSTEMS.md) - Toasts, dialogs, transitions, etc.
> - [Architecture Guide](ARCHITECTURE.md) - Overall project structure

## Color Palette

The theme uses a semantic color system where colors are named by their purpose, not their appearance.

### Background & Surface Colors

| Color              | Hex       | Usage                                               |
| ------------------ | --------- | --------------------------------------------------- |
| `color_background` | `#1a121a` | Deepest background (inputs, tracks, recessed areas) |
| `color_surface1`   | `#2c1f2b` | Panel backgrounds, cards                            |
| `color_surface2`   | `#3e2b3c` | Elevated surfaces, hover states                     |
| `color_surface3`   | `#50374d` | Higher elevation, borders                           |
| `color_surface4`   | `#62435f` | Highest elevation                                   |

### Interactive Colors

| Color                  | Usage                                              |
| ---------------------- | -------------------------------------------------- |
| `color_accent`         | Primary interactive elements (buttons, selections) |
| `color_accent_lighter` | Hover states                                       |
| `color_accent_darker`  | Pressed states                                     |
| `color_secondary`      | Secondary actions, less prominent elements         |
| `color_success`        | Positive actions (Apply, Confirm, Play)            |
| `color_warning`        | Caution states                                     |
| `color_danger`         | Destructive actions (Delete, Quit, Leave)          |

### Text Colors

| Color                  | Usage                                        |
| ---------------------- | -------------------------------------------- |
| `color_text_on_dark`   | Text on dark backgrounds (inputs, panels)    |
| `color_text_on_accent` | Text on accent-colored backgrounds (buttons) |

---

## Icons

UI icons are Tabler Icons (MIT, https://tabler.io/icons) normalised for engine tinting and stored in `res://assets/icons/ui/` under their Tabler names (`cloud-rain.svg`; filled variants as `<name>-filled.svg`).

### Adding an icon

1. Download the outline (and optionally filled) SVG from the `@tabler/icons` package into a scratch folder.
2. Run the normaliser, which replaces `currentColor` with `#ffffff`, strips `class` attributes and Tabler's invisible hit-box path, and never fetches anything:

   ```
   python tools/normalize_icons.py <scratch>/outline assets/icons/ui <name>
   python tools/normalize_icons.py <scratch>/filled assets/icons/ui --suffix=-filled <name>
   ```

3. Import once (`godot --headless --import --path .`), then set `svg/scale=3.0` and `mipmaps/generate=true` in the generated `.import` sidecar and import again. Icons are drawn at 16 to 24 px, so a 3x raster with mipmaps stays crisp at every size.
4. Reference the icon by name: `IconButton.icon_name = "cloud-rain"`, `TileRow.add_tile(id, label, "cloud-rain")`, or `IconButton.load_icon("cloud-rain")` for a raw `Texture2D`.

### Why literal white

Godot's SVG loader renders `currentColor` as black, and `modulate` multiplies the source colour, so a black icon stays black under any tint. A white source icon takes on whatever colour the theme applies: `Button` theme items `icon_normal_color`, `icon_hover_color`, `icon_pressed_color`, `icon_disabled_color` handle every state with no per-instance code.

### Standard icon colours

| Context | Theme item / colour |
|---|---|
| Icon-only buttons | `IconButton` variation: text colour, accent on hover and press |
| Active rail item or tile | `IconButtonActive` / pressed `Tile`: accent |
| Muted marks (chevrons, slider ticks) | `ThemeColors.TEXT_MUTED` |
| Drawer tab (single-tab mode) | `ThemeColors.ACCENT` |

Licence text lives in `THIRD_PARTY_LICENSES.md` at the repo root.

---

## Spacing System

Use these consistent spacing values for margins and padding:

| Token        | Value | Usage                           |
| ------------ | ----- | ------------------------------- |
| `spacing_sm` | 4px   | Tight spacing (inline elements) |
| `spacing_md` | 8px   | Default spacing                 |
| `spacing_lg` | 12px  | Section spacing                 |
| `spacing_xl` | 16px  | Large gaps                      |

---

## Typography Hierarchy

Font sizes form a clear hierarchy for visual organization:

| Variant         | Size                | Usage                                                           |
| --------------- | ------------------- | --------------------------------------------------------------- |
| (default Label) | 20px                | Main titles (e.g., "Level Editor")                              |
| `H1`            | 18px                | Primary headings                                                |
| `H2`            | 16px                | Secondary headings                                              |
| `H3`            | 15px                | Subsection headings (e.g., "Health", "Position")                |
| `SectionHeader` | 16px + accent color | Prominent panel titles (e.g., "Level Info", "Token Properties") |
| `PanelHeader`   | 16px + light text   | Panel/popup titles on dark surfaces (e.g., "Add Pokemon")       |
| `Body`          | 14px                | Field labels, general content                                   |
| `Caption`       | 12px + 70% opacity  | Hints, status text, secondary info                              |

### When to Use Each

```
┌─────────────────────────────────────┐
│ Level Editor          [main title] │  ← Default Label (20px)
├─────────────────────────────────────┤
│ Level Info            [panel title]│  ← SectionHeader (16px, accent)
│                                     │
│ Name:     [____________]            │  ← Body (14px)
│ Author:   [____________]            │  ← Body (14px)
│                                     │
│ Map Transform         [subsection] │  ← H3 (15px)
│ Offset: X: [__] Y: [__] Z: [__]    │  ← Body (14px)
│                                     │
│ Starting level: Oak's Lab          │  ← Caption (12px, muted)
└─────────────────────────────────────┘

┌─────────────────────────────────────┐  (floating popup/overlay)
│ Add Pokemon      [____Search____]  │  ← PanelHeader (16px, light)
│  ┌─────┐ ┌─────┐ ┌─────┐           │
│  │ 🐸  │ │ 🌸  │ │ 🌺  │           │
│  └─────┘ └─────┘ └─────┘           │
│ Click a Pokemon to add it          │  ← Caption (12px, muted)
└─────────────────────────────────────┘
```

**When to use `SectionHeader` vs `PanelHeader`:**

- `SectionHeader` (accent color): For titles in the main UI panels that should draw attention
- `PanelHeader` (light text): For titles in floating popups, overlays, or context menus

---

## Button Variants

Buttons have semantic variants to communicate their purpose:

| Variant     | Color         | Usage                                                       |
| ----------- | ------------- | ----------------------------------------------------------- |
| (default)   | Accent/Orange | Utility actions (Settings, Level Editor)                    |
| `Secondary` | Teal          | Standard actions (New, Load, Save, Select, Host, Join, Close) |
| `Success`   | Green         | Primary CTA / positive actions (Play Level, Apply, Start)   |
| `Warning`   | Yellow        | Caution actions                                             |
| `Danger`    | Red           | Destructive / irreversible actions (Delete, Quit, Leave)    |

### Choosing the Right Variant

Use color to communicate **action weight**, not arbitrary grouping:

- **Success** (green): The primary call-to-action on a screen -- what most users came here to do
- **Secondary** (teal): Standard actions that aren't the primary CTA (file ops, navigation, close/dismiss)
- **Default** (accent): Utility actions that aren't game actions (Settings, Level Editor)
- **Danger** (red): Only for actions that are destructive or abandon state (Delete, Quit, Leave)

Closing or dismissing a menu is **not** destructive -- use `Secondary`, not `Danger`.

### Example Button Bar

```gdscript
# File operations - standard actions
NewButton.theme_type_variation = "Secondary"
LoadButton.theme_type_variation = "Secondary"
SaveButton.theme_type_variation = "Secondary"

# Playtest - primary CTA
PlayButton.theme_type_variation = "Success"

# Close - dismissal, not destructive
CloseButton.theme_type_variation = "Secondary"

# Delete - destructive
DeleteButton.theme_type_variation = "Danger"
```

### In .tscn Files

```
[node name="DeleteButton" type="Button" parent="..."]
theme_type_variation = &"Danger"
text = "Delete"
```

---

## Container Variants

### BoxContainer Spacing

| Variant              | Separation | Usage                          |
| -------------------- | ---------- | ------------------------------ |
| (default)            | 4px        | Tight groupings                |
| `BoxContainerTight`  | 4px        | Inline elements (X/Y/Z fields) |
| `BoxContainerSpaced` | 12px       | Section content, form fields   |

### When to Use BoxContainerSpaced

Apply to VBoxContainers that hold:

- Form fields with labels
- Multiple sections within a panel
- Any content that needs breathing room

```
[node name="FormVBox" type="VBoxContainer" parent="Panel"]
theme_type_variation = &"BoxContainerSpaced"
```

### MarginContainer Variants

| Variant            | Margins              | Usage                              |
| ------------------ | -------------------- | ---------------------------------- |
| (default)          | 8px all sides        | General-purpose inner padding      |
| `TabContentMargin` | 16px h / 12px v      | Content area inside TabContainer tabs |

Use `TabContentMargin` on the `MarginContainer` that wraps content inside each tab:

```
[node name="Margin" type="MarginContainer" parent="TabContainer/MyTab"]
theme_type_variation = &"TabContentMargin"
```

For consistent tab-change animations, call `TabUtils.animate_tab_change()` from the `tab_changed` signal (see `utils/tab_utils.gd`).

### Panel Variants

| Variant         | Background           | Usage                          |
| --------------- | -------------------- | ------------------------------ |
| (default)       | `surface1`           | Standard panels                |
| `PanelElevated` | `surface2`           | Nested panels, emphasis        |
| `PanelBordered` | Transparent + border | Grouping related controls      |
| `PanelInset`    | `background`         | Recessed areas (lists, inputs) |

---

## Animating UI Panels

Use `AnimatedVisibilityContainer` to add smooth show/hide animations to UI panels, menus, and dialogs.

### Basic Usage

Extend `AnimatedVisibilityContainer` instead of `Control`:

```gdscript
extends AnimatedVisibilityContainer
class_name MyPanel

func _ready() -> void:
    # Configure animation (optional - these are defaults)
    fade_in_duration = 0.3
    fade_out_duration = 0.2
    scale_in_from = Vector2(0.8, 0.8)
    scale_out_to = Vector2(0.9, 0.9)
    trans_in_type = Tween.TRANS_BACK
    trans_out_type = Tween.TRANS_CUBIC
    super._ready()

func open() -> void:
    animate_in()

func close() -> void:
    animate_out()
```

### Animation Properties

| Property            | Default     | Description                        |
| ------------------- | ----------- | ---------------------------------- |
| `fade_in_duration`  | 0.3s        | Duration of show animation         |
| `fade_out_duration` | 0.2s        | Duration of hide animation         |
| `scale_in_from`     | (0.8, 0.8)  | Starting scale when appearing      |
| `scale_out_to`      | (0.9, 0.9)  | Ending scale when disappearing     |
| `ease_in_type`      | EASE_OUT    | Easing for show animation          |
| `ease_out_type`     | EASE_IN     | Easing for hide animation          |
| `trans_in_type`     | TRANS_BACK  | Transition curve for show (bouncy) |
| `trans_out_type`    | TRANS_CUBIC | Transition curve for hide (smooth) |
| `start_hidden`      | true        | Whether to start hidden on ready   |

### Recommended Settings by UI Type

**Quick context menus:**

```gdscript
fade_in_duration = 0.15
fade_out_duration = 0.1
scale_in_from = Vector2(0.9, 0.9)
trans_in_type = Tween.TRANS_CUBIC
```

**Large panels (editors, dialogs):**

```gdscript
fade_in_duration = 0.25
fade_out_duration = 0.15
scale_in_from = Vector2(0.95, 0.95)
scale_out_to = Vector2(0.98, 0.98)
trans_in_type = Tween.TRANS_CUBIC
```

**Slide-in sidebars:**

```gdscript
fade_in_duration = 0.2
fade_out_duration = 0.15
scale_in_from = Vector2(1.0, 1.0)  # No scale, just fade
scale_out_to = Vector2(1.0, 1.0)
```

### Lifecycle Callbacks

Override these for custom behavior:

```gdscript
func _on_before_animate_in() -> void:
    # Called just before show animation starts
    pass

func _on_after_animate_in() -> void:
    # Called when show animation completes
    some_input.grab_focus()

func _on_before_animate_out() -> void:
    # Called just before hide animation starts
    pass

func _on_after_animate_out() -> void:
    # Called when hide animation completes (node is now hidden)
    closed.emit()  # Safe to emit signals here
```

### Animating Window Popups

For `Window`-based dialogs (FileDialog, ConfirmationDialog), animate their content containers:

```gdscript
var _popup_tween: Tween

func _open_popup() -> void:
    my_popup.popup_centered(Vector2i(400, 500))
    _animate_popup_in(my_popup.get_node("ContentVBox"))

func _close_popup() -> void:
    _animate_popup_out(my_popup, my_popup.get_node("ContentVBox"))

func _animate_popup_in(content: Control) -> void:
    if _popup_tween:
        _popup_tween.kill()

    content.modulate.a = 0.0
    content.scale = Vector2(0.9, 0.9)
    content.pivot_offset = content.size / 2

    _popup_tween = create_tween()
    _popup_tween.set_parallel(true)
    _popup_tween.set_ease(Tween.EASE_OUT)
    _popup_tween.set_trans(Tween.TRANS_BACK)
    _popup_tween.tween_property(content, "modulate:a", 1.0, 0.2)
    _popup_tween.tween_property(content, "scale", Vector2.ONE, 0.2)

func _animate_popup_out(popup: Window, content: Control) -> void:
    if _popup_tween:
        _popup_tween.kill()

    content.pivot_offset = content.size / 2

    _popup_tween = create_tween()
    _popup_tween.set_parallel(true)
    _popup_tween.set_ease(Tween.EASE_IN)
    _popup_tween.set_trans(Tween.TRANS_CUBIC)
    _popup_tween.tween_property(content, "modulate:a", 0.0, 0.15)
    _popup_tween.tween_property(content, "scale", Vector2(0.95, 0.95), 0.15)
    _popup_tween.finished.connect(popup.hide, CONNECT_ONE_SHOT)
```

### Important Notes

1. **Don't use `show()`/`hide()`** - Use `animate_in()`/`animate_out()` instead
2. **Signal timing** - Emit "closed" signals in `_on_after_animate_out()` so animations complete before parents call `queue_free()`
3. **Check animation state** - Use `is_animating()` to prevent interrupting animations
4. **Toggle helper** - Use `toggle_animated(bool)` for checkbox-driven visibility

### File Reference

- **Base class**: `scenes/ui/animated_visibility_container.gd`
- **Example usage**: `scenes/states/playing/token_context_menu.gd`, `scenes/level_editor/level_editor.gd`

---

## UI Primitives

Reusable controls under `scenes/ui/primitives/`, built in code (no `.tscn`). Every menu should compose these rather than raw Buttons and sliders.

| Primitive | Use it for | Key API |
|---|---|---|
| `IconButton` | Icon-only actions, rail items, pane headers | `icon_name`, `active`, `badge`, `static load_icon(name)` |
| `IconRail` | One-of-N section choice (drawer rail, Settings sections) | `add_item(id, icon, tooltip)`, `select(id)`, `item_pressed`, `selection_changed`, `set_badge(id, on)`, `show_labels`, `auto_select` |
| `TileRow` | Enums with up to ten options (use `columns` beyond five); multi-select toggles | `add_tile(id, label, icon)`, `select(id)` (silent), `selection_changed`, `multi_select`, `tile_toggled`, `columns`, `tile_hovered`, `tile_unhovered` |
| `TileField` | A captioned, full-width tile row (use instead of set_control(TileRow)) | caption, tiles, overridden, reset_requested |
| `Foldout` | Advanced or secondary rows | `title`, `expanded`, `body`; children authored in a `.tscn` move into `body`; re-measures wrapping bodies mid-animation |
| `PropertyRow` | Label + optional check and colour + slider + inline value | `value`, `min_value`, `max_value`, `step`, `show_check`, `show_color`, `show_slider`, `overridden`, `ticks`, `hint_low`, `hint_high`, `values_visible`, `formatter`, `set_control(control)`, `value_changed`, `reset_requested` |
| `PaneStack` | One-visible-pane content area with crossfade | `add_pane(id, pane)`, `show_pane(id)`, `pane_changed` |

Rules: most programmatic setters are silent — `TileRow.select()` and `set_tile_on()`, `PropertyRow.set_*_no_signal()` and its property setters — while user edits emit. `IconRail.select()` is the exception: it DOES emit `selection_changed`, since that is the host's way to drive a selection change programmatically (`item_pressed` is the click). Every primitive owns one `Tween`, kills it before starting another, and runs no `_process`. Numeric chips are hidden by default; the Visuals drawer's rail footer `hash` item shows them for every row and persists the choice (`UiPreferences`).

Sky tiles and the Sky preview strip come from `SwatchTextures` (shipped PNGs for HDRI skies, painted gradients otherwise).

`IconButton` sets its own theme type variation in code (`IconButton` normally, `IconButtonActive` when `active` is true), so a different `theme_type_variation` assigned on the node in a scene is overwritten at runtime.

### Regenerating the theme

`tools/regen_theme.gd` (a `SceneTree` subclass) rebuilds `themes/generated/dark_theme.tres` from `dark_theme.gd` for CI or an agent with no editor session open. It loads `dark_theme.gd` (which extends `ProgrammaticTheme`, itself an `EditorScript`) and calls its `_run()` method directly, rather than being an `EditorScript` subclass itself. Because `EditorScript` can only be instantiated inside the editor, a plain `--headless` run hangs; pass `--editor` too:

```
godot --headless --editor --path . --script res://tools/regen_theme.gd --quit-after 3
```

It preserves the theme resource's UID (captured before saving, restored with `ResourceSaver.set_uid()` after), so `project.godot`'s `gui/theme/custom="uid://..."` reference keeps working across a regeneration.

## Motion

Timing tokens live in `Constants`:

| Token | Value | Used by |
|---|---|---|
| `ANIM_HOVER_IN` / `ANIM_HOVER_OUT` | 0.12 s back-out / 0.10 s cubic-out | IconButton, Tile hover scale to `UI_HOVER_SCALE` (1.06) |
| `ANIM_PRESS` | 0.06 s | press to `UI_PRESS_SCALE` (0.96) |
| `ANIM_PANE_SWAP` / `ANIM_PANE_SWAP_OFFSET_PX` | 0.16 s cubic-out, 8 px | PaneStack crossfade, IconRail indicator |
| `ANIM_FOLDOUT` | 0.16 s cubic-out | Foldout body and chevron |
| `DrawerContainer.slide_duration` | 0.25 s cubic-out | drawer sled |

Scale and position animations use `Control.offset_transform_scale` / `offset_transform_position` (Godot 4.7) via `UiMotion.scale_to()`, so containers never relayout during motion. Sounds reuse `AudioManager.play_tick()`, `play_open()`, `play_close()`.

---

## Drawer Panels

Use `DrawerContainer` for slide-in/out panels attached to a screen edge with a persistent tab handle. The tab remains visible even when the drawer is closed, providing a clear affordance for the user.

### Basic Usage

Extend `DrawerContainer` and override `_on_ready()`:

```gdscript
extends DrawerContainer
class_name MyDrawer

func _on_ready() -> void:
    tab_text = "Menu"
    drawer_width = 200.0

    var label = Label.new()
    label.text = "Drawer content goes here"
    content_container.add_child(label)
```

### Icon Tabs

Set `tab_icon` instead of `tab_text` to show an SVG icon on the tab handle. The icon is automatically tinted with `color_accent` and padded consistently via the built-in `_TAB_ICON_PAD_H` / `_TAB_ICON_PAD_V` constants.

```gdscript
func _on_ready() -> void:
    tab_icon = preload("res://assets/icons/ui/sun.svg")
    drawer_width = 350.0
```

When `tab_icon` is set, `tab_text` is hidden. Setting `tab_icon = null` re-shows the text.

**Important:** SVG icons must use `fill="#ffffff"` (white) so the accent tint applies correctly. See the [Icons](#icons) section for details.

### Rail Mode

Set `rail_items` in `_on_ready()` to replace the single tab with an `IconRail`:

```gdscript
func _on_ready() -> void:
    edge = DrawerEdge.RIGHT
    tab_width = 44.0
    rail_items = [
        {"id": &"sun", "icon": "sun", "tooltip": "Sun"},
        {"id": &"sky", "icon": "haze", "tooltip": "Sky"},
    ]
    pane_requested.connect(_on_pane_requested)
```

Clicking an item opens the drawer and emits `pane_requested(id)`; clicking the active item closes it (through `_can_close_from_tab()`); `open()` with nothing selected reopens the last pane. Badge a single item with `set_rail_badge(id, true)`; `set_tab_badge(false)` clears all. `set_tab_tooltip()` is single-tab only.

### Configuration Properties

| Property         | Default     | Description                         |
| ---------------- | ----------- | ----------------------------------- |
| `edge`           | `LEFT`      | Which screen edge (`LEFT`, `RIGHT`) |
| `drawer_width`   | 220px       | Width of the content panel          |
| `tab_width`      | 36px        | Width of the tab handle button      |
| `tab_text`       | `""`        | Text label on the tab handle        |
| `tab_icon`       | `null`      | Icon texture on the tab (hides text)|
| `rail_items`     | `[]`        | Item specs; replaces the single tab with an `IconRail` (rail mode) |
| `slide_duration` | 0.25s       | Animation duration                  |
| `start_open`     | `false`     | Whether to start open               |
| `play_sounds`    | `true`      | Play open/close sounds              |

### Scene Setup

The `DrawerContainer` should be added as a `Control` node with full-rect anchors (`anchors_preset = 15`) and `mouse_filter = IGNORE`. The drawer builds its internal UI programmatically — no child nodes needed in the `.tscn`.

```
[node name="MyDrawer" type="Control" parent="..."]
layout_mode = 1
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2
script = ExtResource("my_drawer_script")
```

### Lifecycle Callbacks

```gdscript
func _on_ready() -> void:
    # Build your content, configure tab_text, drawer_width, etc.
    pass

func _on_opened() -> void:
    # Called after the open animation finishes.
    pass

func _on_closed() -> void:
    # Called after the close animation finishes.
    pass
```

### Public API

```gdscript
drawer.open()    # Slide open with animation
drawer.close()   # Slide closed with animation
drawer.toggle()  # Toggle open/closed
drawer.is_open   # Current state (bool)
```

### File Reference

- **Base class**: `scenes/ui/drawer_container.gd`
- **Example usage**: `scenes/states/playing/player_list_drawer.gd` (connected player roster)

---

## Full-Screen Overlay Panels

Use `AnimatedCanvasLayerPanel` for full-screen overlays that dim the background and show a centered dialog — settings menus, confirmation dialogs, pause screens, etc.

### When to Use Which Base Class

| Use case | Base class | Extends |
| --- | --- | --- |
| Panel that shows/hides within the UI tree (sidebars, context menus, editors) | `AnimatedVisibilityContainer` | `Control` |
| Slide-in/out drawer from a screen edge with a visible tab handle | `DrawerContainer` | `Control` |
| Full-screen overlay with backdrop dimming + centered dialog | `AnimatedCanvasLayerPanel` | `CanvasLayer` |

### Scene Structure

`AnimatedCanvasLayerPanel` expects this child node layout:

```
MyDialog (CanvasLayer — script extends AnimatedCanvasLayerPanel)
├── ColorRect          ← semi-transparent backdrop
└── CenterContainer
    └── PanelContainer ← the content panel
        └── ... your UI content ...
```

The base class animates `ColorRect` and `CenterContainer` opacity together, and scales `PanelContainer` with a back-ease on open and cubic-ease on close.

### Basic Usage

```gdscript
extends AnimatedCanvasLayerPanel
class_name MyDialog

signal closed

@onready var ok_button: Button = %OKButton

func _on_panel_ready() -> void:
    # Called instead of _ready(). Connect signals, load data, etc.
    ok_button.pressed.connect(_on_ok_pressed)

func _on_after_animate_in() -> void:
    # Called when the open animation finishes.
    ok_button.grab_focus()

func _on_ok_pressed() -> void:
    animate_out()

func _on_after_animate_out() -> void:
    # Called when the close animation finishes. Default: queue_free().
    closed.emit()
    queue_free()
```

### Lifecycle Hooks

Override these for custom behavior at each stage:

```gdscript
func _on_panel_ready() -> void:
    # Runs during _ready(), before animate_in().
    # Use for signal connections, data loading, overlay registration.
    pass

func _on_after_animate_in() -> void:
    # Open animation finished. Grab focus, start timers, etc.
    pass

func _on_before_animate_out() -> void:
    # About to close. Unregister overlays, save state, etc.
    pass

func _on_after_animate_out() -> void:
    # Close animation finished. Emit signals, then queue_free().
    queue_free()  # default behavior if not overridden
```

### Overlay Registration

If the panel should close on ESC, register with UIManager:

```gdscript
func _on_panel_ready() -> void:
    UIManager.register_overlay($ColorRect as Control)

func _on_before_animate_out() -> void:
    UIManager.unregister_overlay($ColorRect as Control)
```

### Sounds

Open/close sounds are played automatically. To disable:

```gdscript
@export var play_sounds: bool = false  # override in inspector
```

Or for buttons that need specialized sounds instead of the auto-connected click:

```gdscript
func _on_panel_ready() -> void:
    confirm_button.set_meta("ui_silent", true)  # skip auto-click
    confirm_button.pressed.connect(func():
        AudioManager.play_confirm()  # play specialized sound
        animate_out()
    )
```

### File Reference

- **Base class**: `scenes/ui/animated_canvas_layer_panel.gd`
- **Example usage**: `scenes/ui/settings_menu.gd`, `scenes/ui/confirmation_dialog.gd`, `scenes/ui/update_dialog.gd`, `scenes/states/paused/pause_overlay.gd`

---

## Building a Complex UI

### Step 1: Structure with Containers

```
MarginContainer (outer padding)
└── VBoxContainer [BoxContainerSpaced]
    ├── Header (HBoxContainer)
    │   ├── Title (Label)
    │   └── Buttons...
    └── HSplitContainer
        ├── LeftPanel (VBoxContainer) [BoxContainerSpaced]
        │   ├── PanelContainer
        │   │   └── VBoxContainer [BoxContainerSpaced]
        │   │       ├── SectionHeader
        │   │       └── Form fields...
        │   └── PanelContainer
        │       └── ...
        └── RightPanel (VBoxContainer) [BoxContainerSpaced]
            └── PanelContainer
                └── ...
```

### Step 2: Apply Typography

1. **Main title**: Default Label style
2. **Panel headers**: `SectionHeader` variant
3. **Subsections**: `H3` variant
4. **Field labels**: `Body` variant
5. **Status/hints**: `Caption` variant

### Step 3: Apply Button Variants

1. Identify action types:
   - Primary CTA / positive → `Success`
   - Standard actions (file ops, navigation, close) → `Secondary`
   - Utility actions (settings, tools) → default (accent)
   - Destructive / irreversible → `Danger`

2. Group related buttons with `VSeparator` between groups

### Step 4: Add Visual Separators

Use `HSeparator` between logical sections within panels:

```
[node name="Separator" type="HSeparator" parent="PanelVBox"]
```

---

## CheckBox and CheckButton Variants

Toggle controls also have color variants:

| Variant             | Usage                   |
| ------------------- | ----------------------- |
| (default)           | Standard toggles        |
| `SecondaryCheckBox` | Less prominent options  |
| `SuccessCheckBox`   | Positive/enable options |
| `WarningCheckBox`   | Caution options         |
| `DangerCheckBox`    | Destructive options     |

Same pattern for `CheckButton` variants.

---

## MenuButton Variants

| Variant               | Usage                    |
| --------------------- | ------------------------ |
| (default)             | Primary dropdown menus   |
| `SecondaryMenuButton` | Secondary menus          |
| `SuccessMenuButton`   | Positive action menus    |
| `WarningMenuButton`   | Caution menus            |
| `DangerMenuButton`    | Destructive action menus |

---

## Quick Reference: Common Patterns

### Form Field Row

```
HBoxContainer
├── Label [Body] - "Field Name:"
│   custom_minimum_size = Vector2(100, 0)
└── LineEdit [size_flags_horizontal = 3]
```

### Coordinate Input Row

```
HBoxContainer
├── Label [Body] - "X:"
├── SpinBox
├── Label [Body] - "Y:"
├── SpinBox
├── Label [Body] - "Z:"
└── SpinBox
```

### Panel with Section Header

```
PanelContainer
└── VBoxContainer [BoxContainerSpaced]
    ├── Label [SectionHeader] - "Section Title"
    ├── ... content ...
    └── ... content ...
```

### Action Button Row

```
HBoxContainer
├── Button [Success, size_flags_horizontal = 3] - "Apply"
└── Button [Danger] - "Delete"
```

---

## Pre-built UI Components

The project includes several ready-to-use UI components that follow the theme. Access them via `UIManager`:

### Confirmation Dialogs

```gdscript
# Simple confirmation
var dialog = UIManager.show_confirmation("Delete?", "This cannot be undone.")
var confirmed = await dialog.closed

# Danger confirmation (red button)
UIManager.show_danger_confirmation("Delete Level?", "All data will be lost.", my_callback)
```

### Toast Notifications

```gdscript
UIManager.show_info("Auto-saved")
UIManager.show_success("Level saved!")
UIManager.show_warning("Unsaved changes")
UIManager.show_error("Failed to load")
```

### Other Components

| Component      | Access                           | Purpose                 |
| -------------- | -------------------------------- | ----------------------- |
| Settings Menu  | `UIManager.open_settings()`      | Audio/Graphics/Grid/Controls/Network/Updates |
| Loading Screen | `LoadingOverlay.show_loading()` (owned by `Root`) | Progress indicator      |
| Input Hints    | `UIManager.set_hints([...])`     | Contextual keybindings  |
| Transitions    | `UIManager.transition(callback)` | Fade between scenes     |

See [UI Systems Guide](UI_SYSTEMS.md) for complete documentation.

---

## File Reference

- **Theme definition**: `themes/dark_theme.gd`
- **Generated theme**: `themes/generated/dark_theme.tres`
- **Base class**: `addons/theme_gen/programmatic_theme.gd`
- **UI Components**: `scenes/ui/` directory

### Theme Regeneration

The theme is generated programmatically from `themes/dark_theme.gd` (extends `ProgrammaticTheme` from the ThemeGen addon) into `themes/generated/dark_theme.tres`.

**How to regenerate:**

1. **Automatic (recommended):** With `const UPDATE_ON_SAVE = true` in `dark_theme.gd`, the `theme_gen_save_sync` plugin regenerates the `.tres` file every time you save the script.
2. **Manual:** Open `dark_theme.gd` in the Godot script editor, then use **File → Run** (or Ctrl+Shift+X).

**When to regenerate:**

- After modifying colors, fonts, spacing, or any theme properties in `dark_theme.gd`
- After adding new theme type variations (button variants, label variants, etc.)
- The generated `.tres` file should always be committed alongside the `.gd` changes

**Dependencies:** Requires the `theme_gen` and `theme_gen_save_sync` editor plugins to be enabled (see `project.godot` `[editor_plugins]`).
