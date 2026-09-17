class_name ThemeColors
extends RefCounted

## Colours that code (not the theme resource) needs, e.g. an accent-tinted
## indicator or icon tint outside of a themed Control's style boxes. Only the
## accent lives here so far; other literals in drawer_container.gd and
## download_queue.gd still mirror `themes/dark_theme.gd` by hand.
##
## `themes/dark_theme.gd` reads ACCENT from here when the ProgrammaticTheme
## addon regenerates the theme on save, so moving or renaming this file breaks
## theme regeneration quietly: the committed .tres simply stops updating.

const ACCENT := Color("#db924b")

## color_text_on_dark at 70%: muted captions, chevrons, tick icons.
const TEXT_MUTED := Color(0.875, 0.875, 0.875, 0.7)

## The deepest background (themes/dark_theme.gd color_background): solid
## backdrops that replace the map rather than dim it, such as the lobbies.
const BACKGROUND := Color("#1a121a")
