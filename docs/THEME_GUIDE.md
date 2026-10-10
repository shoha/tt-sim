# Painted Table Theme Guide

How to use the Painted Table theme (2026-10-09) so screens stay consistent. The rules it serves
are in [UI taste](UI_TASTE.md); this guide says where things live and which names to use.
Sections further down that predate the Painted Table (sizes, Secondary/Success examples) are
being migrated card by card; where they disagree with this top section, this section wins.

> **Related Documentation:**
>
> - [UI Systems Guide](UI_SYSTEMS.md) - Toasts, dialogs, transitions, etc.
> - [UI taste](UI_TASTE.md) - The rules UI work is judged by (C, T, S, M, I, W, G ids), the anti-patterns and the user's verdicts
> - [Architecture Guide](ARCHITECTURE.md) - Overall project structure

## Paper and glass

One rule decides the material: **if it stops play it is paper; if play continues under it, it
is glass.** Paper (`themes/generated/paper_theme.tres`) is the project default (`theme/custom`),
so menus, dialogs, pause and confirms need nothing. Every UI root shown while play continues
(the GameplayMenu HUD and its drawers and token menu, the hint bar, toasts, the download queue,
the disconnect chip, the authoring panel, measure and ruler labels) sets
`theme = ThemeColors.glass_theme()` (or the `glass_theme.tres` ext_resource in its `.tscn`).
`tests/unit/test_glass_roots.gd` fails when a new CanvasLayer scene or script is not sorted
into one of the two.

## Colour roles

`utils/theme_colors.gd` (`ThemeColors`) is the one role table. Tokens (`PAPER`, `INK`,
`PERSIMMON`, `GLASS`, `CHALK`, `EMBER` ...) are the raw palette; roles are what UI code uses,
and each theme maps them to its own token (`PAPER_ROLES`, `GLASS_ROLES`):

| Role | Paper | Glass | Use |
|---|---|---|---|
| `SURFACE`, `SURFACE_RAISED`, `SURFACE_INSET` | paper, raised, inset | glass (plum `#251B35` at 0.90: at 0.86 and lower chroma a green board pulled it to neutral charcoal), glass raised | sheets, secondary buttons, fields and tracks |
| `SURFACE_HOVER`, `SURFACE_PRESS` | deeper paper steps | deeper glass steps | hover and press washes (only ever deeper) |
| `TEXT`, `TEXT_SOFT` | ink, ink_soft | chalk, chalk_soft | text and captions (solid, never dimmed) |
| `ACCENT` (+ `_HOVER`, `_PRESS`), `ON_ACCENT` | persimmon, paper text | ember_fill (one OKLCH step under ember: ember outshone a dusk board), ink text | the one primary fill per screen, the unsaved dot |
| `STATE` (+ steps), `ON_STATE` | lake, paper text | lake_light, ink text | on-states, checks and switches, rail indicator, a changed value; on glass the text and lines of state |
| `SELECTED` (+ `_HOVER`), `ON_SELECTED` | lake, paper text | lake, chalk text | a selected tile or list row (glass adds a lake_light ring: a lake_light fill outshone the board) |
| `FOCUS` | lake (about 6:1 on paper) | lake_light | the keyboard focus ring: a state, never a control's fill hue |
| `SUCCESS`, `WARNING`, `DANGER`, `DANGER_FILL` | moss, ochre, madder | light variants; madder fill | text and icons; madder fills only a danger confirm |
| `TRACK` | lavender graphite `#887A8E` (tan pressed this dark read as muddy khaki) | `#958DA0` | an unfilled slider or switch track, 3:1 on every surface |
| `EDGE`, `SHADOW`, `BACKDROP` | pencil edge, ink 16%, sky | top rim, plum-black 25%, glass | decoration, shadows (ink-tinted, never brown or black), a solid backdrop's colour (the transition overlay's fade; the screens outside play stand on the painted backdrop, `PaintedBackdrop`, UI_SYSTEMS.md) |

Prefer a theme variation (`Caption`, `BodyState`, `Primary` ...) over reading a role. Read a
role only to draw or tint by hand, through the control being drawn:
`ThemeColors.of(control, ThemeColors.TEXT_SOFT)`, at draw time or on
`NOTIFICATION_THEME_CHANGED` (a control outside the tree resolves to paper).

## Variations

| Type | Variations |
|---|---|
| `Label` (default: Inter body 16, text) | `Wordmark` (Fraunces 56), `Title` / `H1` (Fraunces 26), `Heading` / `H2` / `SectionHeader` / `PanelHeader` (Fraunces 19), `Eyebrow` (Fraunces italic 19), `H3` (Inter 16 semibold), `Count` (H3 with tabular figures: a count that ticks in place, the table move's 3, 2, 1), `Body`, `Caption` / `RailLabel` (14, soft), `BodyState`, `CaptionState`, `Code` (Inter 19 semibold, tabular figures, slashed zero, tailed l: a code read aloud), `CountBadgeLabel` (caption, strong, on the accent), `BodyOnSelected` / `CaptionOnSelected` (body and caption in ON_SELECTED: text on a selected fill) |
| `Button` (default: the quiet secondary) | `Primary` (one per screen), `Danger` (danger confirm only), `Ghost` (no fill, soft text), `Secondary` (alias of the default), `Framed` (the default with its frame at 3:1 in the track role in every state, for a button on a chip of its own colour: the table move's Stay here), `IconButton`, `IconButtonActive`, `IconButtonDisc` (the icon button on a small raised paper disc with a pencil edge, for a button over a picture: a level card's overflow menu), `Tile`, `ListRow` (a selectable list row, the room's shelf maps: clear at rest with no edge, the hover wash, the selected fill when picked), `Card`, `FoldoutHeader` |
| `PanelContainer` (default: a `Sheet`) | `Sheet`, `Inset` / `PanelInset`, `PanelElevated`, `PanelBordered`, `KeyChip`, `CodeChip` (the room code: a key chip with 12 / 6 padding), `CardStrip` / `CardStripSelected` (a card's caption strip: clear, or the selected fill when the card is selected), `PictureCard` (a picture on a card of its own, the card's paper and trim at rest: the room's selected map with its name, the title's empty library), `Chip` (a label over the board: glass with its rim on glass, never a black box), `CountBadge` (the accent pill behind a count), `Toast` (every toast and the disconnect banner: one glass surface, no side stripe; the kind is the icon tinted state, success, warning or danger, and the words); `Panel`: `Badge` (the unsaved dot, in the cool state role: it says what is, and its item's tooltip says it in words), `CardThumb` (a card's thumbnail well: the inset wash, the shape the card clips its picture to; a map with no thumbnail paints its `MapPlaceholder` in it); `ProgressBar`: `ProgressSuccess`, `ProgressDanger` (a finished or failed bar) |
| `HBoxContainer` / `ScrollContainer` | `PropertyRow` (a sheet's label-and-control row: 16 px gap; `PropertyRow.fit_sheet_row(row)` also sets the 184 px label column), `CardGrid` (a scrolling card grid: a clear panel whose 6 px margins keep a focused card's ring inside the clip); `VScrollBar` (default: an opaque grabber in the track role, 3:1 on its leaf's surfaces, soft text on hover, text while dragged): `CardGridBar` (a card grid's bar over the painted backdrop: the grabber on a paper strip of its own, so it holds 3:1 in every mood) |

Focus and selection never share a mark (I1). The ring is focus only: a selected `Tile` is the
selected fill edge to edge, and a selected `Card` fills its caption strip; a focused selected
item shows both. Dividers (`HSeparator`, `VSeparator`, popup separators) are `DIVIDER` (2 px)
thick, so they keep a physical pixel at 1280x720. A slider's track is a 3 px rail under its
6 px fill.

The stop-play scrim is not a theme item: every full-screen sheet's backdrop `ColorRect` takes
`scenes/ui/primitives/scrim.gd` (`Scrim`), which blurs what is behind it and lays
`ThemeColors.SCRIM` over the blur (`shaders/ui_scrim.gdshader`). Never a black `ColorRect`.

Fraunces is only for the wordmark, titles, headings and eyebrows; rows and buttons use Inter.
Sizes: 56 / 26 / 19 Fraunces, 16 / 15 / 14 Inter (14 is the floor). Spacing 4, 8, 12, 16, 24,
32 (theme type `Space`), sheet padding 24, controls 40 tall; radii chip 6, control 10, card
16, sheet 20.

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

The Level Editor toolbar added `folder` (Load) and `upload` (Import JSON) alongside the existing `plus`, `device-floppy`, `download`, `player-play`, and `x`.

### Why literal white

Godot's SVG loader renders `currentColor` as black, and `modulate` multiplies the source colour, so a black icon stays black under any tint. A white source icon takes on whatever colour the theme applies: `Button` theme items `icon_normal_color`, `icon_hover_color`, `icon_pressed_color`, `icon_disabled_color` handle every state with no per-instance code.

### Standard icon colours

| Context | Theme item / colour |
|---|---|
| Icon-only buttons | `IconButton` variation: text colour, state on press |
| Active rail item or tile | `IconButtonActive` / pressed `Tile`: state |
| Muted marks (chevrons, slider ticks) | `ThemeColors.of(control, ThemeColors.TEXT_SOFT)` |
| Drawer tab (single-tab mode) | `ThemeColors.of(control, ThemeColors.ACCENT)` |

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

## Interface Size

Every screen is laid out on a 1920x1080 canvas (`window/stretch/mode="canvas_items"`,
`aspect="expand"`), and a smaller window shrinks that canvas with it: at 1280x720 a 14 px
caption drew at 9 px. Interface size (`utils/interface_size.gd`, `InterfaceSize`) sets the root
window's `content_scale_factor` instead, so the virtual canvas shrinks and the UI draws larger.

- **Auto** (the default) is the least 0.05 step from 1.0 to 1.5 that draws a 14 px caption at
  13 physical px or more (UI_TASTE T2): `ceil(13 / (14 * s))` in 0.05 steps, where `s` is the
  window's scale of the base canvas, `min(w / 1920, h / 1080)`. 720p gives 1.40 (a 1371x771
  canvas), 900p 1.15, 1080p and up 1.0. The step rounds up: rounding to the nearest gives 1.10
  at 900p, where captions draw at 12.8 px. The narrower axis counts, so a 5:4 window reads its
  width.
- **A fixed size**, 90% to 150% in 10% steps, replaces Auto rather than multiplying it, so a
  percent means the same factor on every window and nothing passes 1.5.
- **Every screen fits a 1280x720 canvas**: 150% on any 16:9 window, the smallest any choice
  gives. `tests/unit/test_interface_size_fit.gd` opens every screen and sheet the UI tour
  visits in a 1280x720 viewport and fails on any visible control outside it (a ScrollContainer
  must fit; what it holds may scroll). The same walk fails a hint bar under an open drawer or a
  bottom-corner button, and a title column that runs off its paper sheet or a sheet past the
  hub's margin. Screens that would not fit adapt to the canvas, by measurement rather than at
  a threshold:
  - The title's left column measures itself against the room the hub's margins and its
    sheet's padding leave (`TitleScreen._fit_to_canvas`; the margins are the sheet's 24 px
    from the canvas edge). A caption always sits 4 px under its own button and 12 px
    above the next control, so it reads with its button. Stacked buttons stand 12 apart when
    the column fits that way (1080p, and 1366x768 at Auto, an 800 px canvas), else 8, and the
    three section gaps (under the wordmark, around the divider) give up the rest, evenly, from
    36 / 32 / 32 down to 12. At 720p Auto the sheet fills the height to the hub's margin.
  - The new-map dialog takes the 960 sheet under 880 px and scrolls its fields when even that
    is too tall. Its fields share one track: six columns on the 960 sheet (biomes 6 + 3, the
    three sizes on the first three columns at biome width, the six landforms on all six),
    three on the 600 (sizes and biomes three across, landforms two to a biome column).
  - The input hint bar (`InputHints`) centres in the board the open drawers leave free
    (`DrawerContainer.free_span`), moves aside only as far as the play HUD's bottom-right
    buttons need (`InputHints.OBSTACLES`), and wraps its row onto a second line when the free
    span is narrower than the row (the measure tool's keys at 720p).
  - The avatar builder and roster size themselves from the canvas already.

  A screen that sizes itself reads `get_viewport().get_visible_rect().size` (the virtual
  canvas), never the window's pixel size, and refits on `size_changed`, which also fires when
  the factor changes.
- **Only the canvas scales.** `GameMap` sets its world viewport's `scaling_3d_scale` to the
  factor, so the board renders at the resolution it has at 100%: the camera framing, the render
  size and pixel-sized 3D details (grid line widths) are unchanged. Overlays drawn on the canvas
  over the board (measure labels, gizmo handles, brush outlines) are UI and follow the factor.
- **Where it lives:** Settings > Graphics, the Interface Size row (saves and applies the moment
  it is picked; Reset puts Auto back). Its choices read "Auto (recommended)" and bare percents,
  with only the one Auto picks on this window marked ("140% (Auto on this screen)" at 720p), so a
  bare "100%" does not read as the normal size (it draws 9 px captions at 720p) without five
  rows of "(smaller than Auto)"; the labels refill when the window resizes. Saved per user in the settings file's `[ui]` section as
  `interface_size` (0 for Auto, else the percent; `UiPreferences`), never networked.
  `UIManager` applies it at startup and on every root `size_changed`; a headless run keeps 1.0.
  The render-job probe `ui_primitives.gd` `window` step applies Auto (or its `content_scale`,
  or the percent after an `@` in its size, "1920x1080@150") for the run without saving it; the
  UI tour's size passes use it with `probes/ui_size.gd`.

---

## Button Variants

Buttons have semantic variants to communicate their purpose:

| Variant     | Color         | Usage                                                       |
| ----------- | ------------- | ----------------------------------------------------------- |
| (default)   | Accent/Orange | The one primary action on a screen (for example Host Game, Resume, Start, Connect, Apply) |
| `Secondary` | Teal          | Standard actions (New, Load, Save, Select, Host, Join, Close) |
| `Success`   | Green         | confirmation dialog only                                    |
| `Warning`   | Yellow        | Reserved; not currently used by any menu                    |
| `Danger`    | Red           | confirmation dialog only                                    |
| `Card`      | --            | Level cards; a selected card fills its caption strip (`CardStripSelected`) |

Every menu screen carries exactly one default-variant (accent) action; every other action is
`Secondary` with an icon. `Success` and `Danger` fills now appear only on `ConfirmationDialogUI`'s
confirm button; `Warning` fills are used by no menu screen. Destructive menu rows (Return to Title,
Quit Game, Leave, Reset to Defaults) are `Secondary` -- the confirmation that follows carries the
red. Footers are an `HBoxContainer` with `alignment = ALIGNMENT_END`, secondary actions first and
the primary last.

### Choosing the Right Variant

Use color to communicate **action weight**, not arbitrary grouping:

- **Default** (accent): The one primary action on a screen -- what most users came here to do (Host Game, Resume, Start, Connect, Apply)
- **Secondary** (teal): Everything else on a menu screen -- file ops, navigation, cancel/close/dismiss
- **Success** / **Danger** (green / red): `ConfirmationDialogUI`'s confirm button only, never a menu screen's own action
- **Warning** (yellow): Reserved; not currently used by any menu

Closing or dismissing a menu is **not** destructive -- use `Secondary`, not `Danger`.

### Example Button Bar

```gdscript
# Footer: secondary actions first, the primary last (HBoxContainer, ALIGNMENT_END)
CancelButton.theme_type_variation = "Secondary"
ApplyButton.theme_type_variation = ""  # default variant -- this screen's one accent primary
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
| `CardText`         | 8px h and bottom, 4px top | A card's name and caption, inside the card's 4px inset (12px from its edge) |

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
| `KeyChip`       | `surface2` + border  | Key caps in shortcut rows      |
| `CodeChip`      | `surface2` + border, 12 / 6 padding | The room code              |
| `Plaque`        | `surface1` + border + rest shadow, radius 16, 16 / 8 padding (glass: rim, 12 / 8) | A few words standing on the painted backdrop (the room's heading, code row and map name, the title's "Your maps"), so they read in every mood |

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
| `IconRail` | One-of-N section choice (drawer rail, Settings sections) | `add_item(id, icon, tooltip)`, `select(id)`, `item_pressed`, `selection_changed`, `set_badge(id, on)`, `show_labels`, `auto_select`; the accent indicator is placed after each `sort_children` (never on `resized`, which fires before the items are laid out) and slides on selection change |
| `TileRow` | Enums with up to ten options (use `columns` beyond five); multi-select toggles | `add_tile(id, label, icon)`, `select(id)` (silent), `selection_changed`, `multi_select`, `tile_toggled`, `columns`, `tile_hovered`, `tile_unhovered`, `photo_icons` (picture icons such as palette thumbnails: own size, untinted) |
| `TileField` | A captioned, full-width tile row (use instead of set_control(TileRow)) | caption, tiles, overridden, reset_requested |
| `Foldout` | Advanced or secondary rows | `title`, `expanded`, `body`; children authored in a `.tscn` move into `body`; re-measures wrapping bodies mid-animation; the chevron is `CHEVRON_SIZE` (16 px) square (its `expand_mode` must be set before its size, or the 72 px icon texture wins) |
| `PropertyRow` | Label + optional check and colour + slider + inline value | `value`, `min_value`, `max_value`, `step`, `show_check`, `show_color`, `show_slider`, `overridden`, `ticks`, `hint_low`, `hint_high`, `values_visible`, `formatter`, `set_control(control)`, `value_changed`, `reset_requested` |
| `PaneStack` | One-visible-pane content area with crossfade | `add_pane(id, pane)`, `show_pane(id)`, `pane_changed` |
| `LevelCard` | A saved level as a selectable, actionable card (title hub, level picker) | `setup(info)`, `set_selected(on)` (silent; fills the caption strip), static `caption_for(info, now_unix)`, static `initial_of(name)`, `locked`, `begin_rename()`, `selected`, `activated`, `action_requested`, `rename_committed` |
| `MapPlaceholder` | The picture of a map with no thumbnail (level cards, the room's shelf and preview): the painted backdrop's world in a small rect (`shaders/ui_backdrop.gdshader`, `BackdropPaint`), its land and weather seeded by the map's folder and its light the backdrop's mood for its preset (`PaintedBackdrop.mood_of`, one table), so a map paints the same everywhere and agrees with the screen behind it; its clouds hold still | `paint(key, mood)`, `mood()`, static `seed_of(key)` |
| `PaintedBackdrop` | The full-screen painted world outside play (UI_SYSTEMS.md "Painted backdrop"): a curated mood and the map's own land, making way for the screen's paper | `show_map(preset, key)`, `show_mood(mood)`, `show_last()`, `fit_around(screen)`, `refit()`, `hold_drift(held)`, static `mood_of(preset)`, static `seed_of(key)`, `last_mood`, `last_key` |
| `LevelGrid` | Grid of `LevelCard`s over a level provider; a wide grid adds columns past `columns` rather than stretch a card past `MAX_CARD_WIDTH` (400) | `provider`, `columns`, `confirm_delete`, `locked_path`, `refresh()`, `select(path)`, `selected_info()`, `card_count()`, `selection_changed`, `level_activated` |
| `UiActions` | The two menu action shapes, as static builders | `primary(label, icon, caption, parent)`, `secondary(label, icon, parent)`, `subtitle_of(button)`, `spacer(height, parent)`, `PRIMARY_HEIGHT` 56, `SECONDARY_HEIGHT` 36 |
| `MenuHeader` | The title block every menu screen opens with | `setup(title, caption = "", closable = false)`, `title_label`, `caption_label`, `close_button`, `close_requested` |

`LevelCard`'s overflow button uses the `dots-vertical` icon (`assets/icons/ui/dots-vertical.svg`).

Rules: most programmatic setters are silent — `TileRow.select()` and `set_tile_on()`, `PropertyRow.set_*_no_signal()` and its property setters — while user edits emit. `IconRail.select()` is the exception: it DOES emit `selection_changed`, since that is the host's way to drive a selection change programmatically (`item_pressed` is the click). Every primitive owns one `Tween`, kills it before starting another, and runs no `_process`. Numeric chips are hidden by default; the Visuals drawer's rail footer `hash` item shows them for every row and persists the choice (`UiPreferences`).

Sky tiles and the Sky preview strip come from `SwatchTextures` (shipped PNGs for HDRI skies, painted gradients otherwise).

`IconButton` sets its own theme type variation in code (`IconButton` normally, `IconButtonActive` when `active` is true, `IconButtonDisc` when `disc` is true), so a different `theme_type_variation` assigned on the node in a scene is overwritten at runtime.

### Regenerating the theme

`tools/regen_theme.gd` (a `SceneTree` subclass) rebuilds both `themes/generated/paper_theme.tres` and `glass_theme.tres` from their leaves (`themes/paper_theme.gd`, `themes/glass_theme.gd`, which extend `painted_theme_base.gd` <- `painted_theme_controls.gd` <- `painted_theme_kit.gd` <- `ProgrammaticTheme`). Saving a leaf in the editor regenerates that leaf; after editing the base, controls or kit, run the tool. It loads each leaf and calls its `_run()` method directly, rather than being an `EditorScript` subclass itself. Because `EditorScript` can only be instantiated inside the editor, a plain `--headless` run hangs; pass `--editor` too:

```
godot --headless --editor --path . --script res://tools/regen_theme.gd --quit-after 3
```

It preserves each theme resource's UID when it has one (captured before saving, restored with `ResourceSaver.set_uid()` after). `project.godot` and the in-play scenes reference the themes by path, so a UID change never breaks them. The switch, check and slider-knob icons are drawn from role colours as SVG in `painted_theme_controls.gd` and stored inside the `.tres`.

## Motion

Timing tokens live in `Constants`:

| Token | Value | Used by |
|---|---|---|
| `ANIM_HOVER_IN` / `ANIM_HOVER_OUT` | 0.12 s back-out / 0.10 s cubic-out | IconButton, Tile hover scale to `UI_HOVER_SCALE` (1.06) |
| `ANIM_HOVER_SOFT_IN` / `ANIM_HOVER_SOFT_OUT` | 0.24 s / 0.20 s sine in-out | LevelCard zooms its thumbnail 4% (`THUMB_HOVER_SCALE`) inside a clipped slot instead of scaling the whole card -- a whole-card scale clips against the grid |
| `ANIM_PRESS` | 0.06 s | press to `UI_PRESS_SCALE` (0.96) |
| `ANIM_PANE_SWAP` / `ANIM_PANE_SWAP_OFFSET_PX` | 0.16 s cubic-out, 8 px | PaneStack crossfade, IconRail indicator |
| `ANIM_FOLDOUT` | 0.16 s cubic-out | Foldout body and chevron |
| `DrawerContainer.slide_duration` | 0.25 s cubic-out | drawer sled |
| `ANIM_ENTRANCE` / `ANIM_ENTRANCE_STAGGER` | 0.3 s cubic-out, 0.08 s apart | `UiMotion.stagger_in()`: title, pause menu, host lobby and join screen bodies fade and lift 12 px into place |

Scale and position animations use `Control.offset_transform_scale` / `offset_transform_position` (Godot 4.7) via `UiMotion.scale_to()`, so containers never relayout during motion. Sounds reuse `AudioManager.play(&"tick")`, `&"open"` and `&"close"`.

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
- **Example usage**: `scenes/states/room/room_drawer.gd` (the room over the table)

---

## Full-Screen Overlay Panels

Use `AnimatedCanvasLayerPanel` for full-screen overlays that dim the background and show a centered dialog — settings menus, confirmation dialogs, pause screens, etc.

The base class keeps a class-level stack of live panels and only the topmost one traps Tab/Shift+Tab; panels that show or hide containers after `_ready()` (rather than just toggling a control's own `visible`) must call `rebuild_focus_trap()` afterward so the trap only names controls that are actually visible.

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
        AudioManager.play(&"confirm")  # outranks the panel's close in the same frame
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
UIManager.show_success("Map saved")
UIManager.show_warning("Unsaved changes")
UIManager.show_error(MapLoadError.for_info(info))  # what failed, why, how to recover (W3)
# A change recovered by undo rather than confirmed first (I4): the toast offers Undo.
UIManager.show_undo_toast('Removed "Marigold"', undo_callable)
```

### Other Components

| Component      | Access                           | Purpose                 |
| -------------- | -------------------------------- | ----------------------- |
| Settings Menu  | `UIManager.open_settings()`      | Audio/Graphics/Grid/Controls/Network/Updates |
| Loading Screen | `LoadingOverlay.show_loading()` (owned by `Root`) | Progress indicator      |
| Input Hints    | `UIManager.set_hints([...])`; a tool's own keys `UIManager.set_tool_hints([...])` / `clear_tool_hints()` | Contextual keybindings  |
| Transitions    | `UIManager.transition(callback)` | Fade between scenes     |

See [UI Systems Guide](UI_SYSTEMS.md) for complete documentation.

---

## File Reference

- **Role table**: `utils/theme_colors.gd`
- **Theme definition**: `themes/painted_theme_base.gd` (with `painted_theme_controls.gd`, `painted_theme_kit.gd`); leaves `themes/paper_theme.gd`, `themes/glass_theme.gd`
- **Generated themes**: `themes/generated/paper_theme.tres` (project default), `themes/generated/glass_theme.tres`
- **Fonts**: `assets/fonts/Inter-VariableFont_opsz,wght.ttf`, `assets/fonts/fraunces/` (SIL OFL, `OFL.txt`)
- **Base class**: `addons/theme_gen/programmatic_theme.gd`
- **UI Components**: `scenes/ui/` directory

### Theme Regeneration

**How to regenerate:**

1. **Automatic:** With `const UPDATE_ON_SAVE = true` in a leaf, the `theme_gen_save_sync` plugin regenerates that leaf's `.tres` every time you save the leaf.
2. **Both at once (after editing the base, controls or kit):** `tools/regen_theme.gd`, above.

**When to regenerate:**

- After modifying roles in `ThemeColors`, or fonts, spacing or any theme property in the theme scripts
- After adding new theme type variations (button variants, label variants, etc.)
- The generated `.tres` file should always be committed alongside the `.gd` changes

**Dependencies:** Requires the `theme_gen` and `theme_gen_save_sync` editor plugins to be enabled (see `project.godot` `[editor_plugins]`).
