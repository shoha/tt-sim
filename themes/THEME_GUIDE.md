# Dark Theme Usage Guide

This guide explains how to use the theme variants defined in `dark_theme.gd` to create consistent, well-organized UIs.

## Color Palette

The theme uses a semantic color system where colors are named by their purpose, not their appearance.

### Background & Surface Colors

| Color | Hex | Usage |
|-------|-----|-------|
| `color_background` | `#1a121a` | Deepest background (inputs, tracks, recessed areas) |
| `color_surface1` | `#2c1f2b` | Panel backgrounds, cards |
| `color_surface2` | `#3e2b3c` | Elevated surfaces, hover states |
| `color_surface3` | `#50374d` | Higher elevation, borders |
| `color_surface4` | `#62435f` | Highest elevation |

### Interactive Colors

| Color | Usage |
|-------|-------|
| `color_accent` | Primary interactive elements (buttons, selections) |
| `color_accent_lighter` | Hover states |
| `color_accent_darker` | Pressed states |
| `color_secondary` | Secondary actions, less prominent elements |
| `color_success` | Positive actions (Apply, Confirm, Play) |
| `color_warning` | Caution states |
| `color_danger` | Destructive actions (Delete, Close) |

### Text Colors

| Color | Usage |
|-------|-------|
| `color_text_on_dark` | Text on dark backgrounds (inputs, panels) |
| `color_text_on_accent` | Text on accent-colored backgrounds (buttons) |

---

## Spacing System

Use these consistent spacing values for margins and padding:

| Token | Value | Usage |
|-------|-------|-------|
| `spacing_sm` | 4px | Tight spacing (inline elements) |
| `spacing_md` | 8px | Default spacing |
| `spacing_lg` | 12px | Section spacing |
| `spacing_xl` | 16px | Large gaps |

---

## Typography Hierarchy

Font sizes form a clear hierarchy for visual organization:

| Variant | Size | Usage |
|---------|------|-------|
| (default Label) | 20px | Main titles (e.g., "Level Editor") |
| `H1` | 18px | Primary headings |
| `H2` | 16px | Secondary headings |
| `H3` | 15px | Subsection headings (e.g., "Health", "Position") |
| `SectionHeader` | 16px + accent color | Panel titles (e.g., "Level Info", "Token Properties") |
| `Body` | 14px | Field labels, general content |
| `Caption` | 12px + 70% opacity | Hints, status text, secondary info |

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
```

---

## Button Variants

Buttons have semantic variants to communicate their purpose:

| Variant | Color | Usage |
|---------|-------|-------|
| (default) | Accent/Orange | Primary actions |
| `Secondary` | Teal | Less prominent actions (New, Load, Save, Select) |
| `Success` | Green | Positive/confirm actions (Apply, Play) |
| `Warning` | Yellow | Caution actions |
| `Danger` | Red | Destructive actions (Delete, Close) |

### Example Button Bar

```gdscript
# File operations - secondary importance
NewButton.theme_type_variation = "Secondary"
LoadButton.theme_type_variation = "Secondary"
SaveButton.theme_type_variation = "Secondary"

# Playtest - positive action
PlayButton.theme_type_variation = "Success"

# Close - destructive
CloseButton.theme_type_variation = "Danger"
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

| Variant | Separation | Usage |
|---------|------------|-------|
| (default) | 4px | Tight groupings |
| `BoxContainerTight` | 4px | Inline elements (X/Y/Z fields) |
| `BoxContainerSpaced` | 12px | Section content, form fields |

### When to Use BoxContainerSpaced

Apply to VBoxContainers that hold:
- Form fields with labels
- Multiple sections within a panel
- Any content that needs breathing room

```
[node name="FormVBox" type="VBoxContainer" parent="Panel"]
theme_type_variation = &"BoxContainerSpaced"
```

### Panel Variants

| Variant | Background | Usage |
|---------|------------|-------|
| (default) | `surface1` | Standard panels |
| `PanelElevated` | `surface2` | Nested panels, emphasis |
| `PanelBordered` | Transparent + border | Grouping related controls |
| `PanelInset` | `background` | Recessed areas (lists, inputs) |

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
   - Primary action → default (accent)
   - File/secondary operations → `Secondary`
   - Confirm/positive → `Success`
   - Destructive → `Danger`

2. Group related buttons with `VSeparator` between groups

### Step 4: Add Visual Separators

Use `HSeparator` between logical sections within panels:

```
[node name="Separator" type="HSeparator" parent="PanelVBox"]
```

---

## CheckBox and CheckButton Variants

Toggle controls also have color variants:

| Variant | Usage |
|---------|-------|
| (default) | Standard toggles |
| `SecondaryCheckBox` | Less prominent options |
| `SuccessCheckBox` | Positive/enable options |
| `WarningCheckBox` | Caution options |
| `DangerCheckBox` | Destructive options |

Same pattern for `CheckButton` variants.

---

## MenuButton Variants

| Variant | Usage |
|---------|-------|
| (default) | Primary dropdown menus |
| `SecondaryMenuButton` | Secondary menus |
| `SuccessMenuButton` | Positive action menus |
| `WarningMenuButton` | Caution menus |
| `DangerMenuButton` | Destructive action menus |

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

## File Reference

- **Theme definition**: `themes/dark_theme.gd`
- **Generated theme**: `themes/generated/dark_theme.tres`
- **Base class**: `addons/theme_gen/programmatic_theme.gd`

To regenerate the theme after changes, run the script via **File → Run** in Godot's script editor, or enable hot-reload with `const UPDATE_ON_SAVE = true`.
