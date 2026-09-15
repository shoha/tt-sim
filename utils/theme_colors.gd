class_name ThemeColors
extends RefCounted

## Single source of truth for colours that code (not the theme resource) needs —
## e.g. drawing an accent-tinted indicator or icon tint outside of a themed
## Control's style boxes. `themes/dark_theme.gd` is the source of truth for the
## theme resource itself; this class exists so plain code doesn't have to poke
## into that `@tool` script or duplicate its color literals.

const ACCENT := Color("#db924b")
