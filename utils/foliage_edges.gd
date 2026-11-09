class_name FoliageEdges
extends RefCounted

## Foliage edges: whether the foliage's cutout edges are smoothed while MSAA is on (Settings >
## Graphics, beside Antialiasing; per player, never networked). Only matters with MSAA on: an
## Antialiasing setting of 2x or more, or the eye view, which raises it to 4x.
##
## The model. With MSAA on, every wind material takes its antialiased twin (alpha_to_coverage plus
## ALPHA_ANTIALIASING_EDGE: soft, feathered leaf edges). Godot treats a material that writes ALPHA
## with an antialiasing edge as transparent, so that foliage leaves the opaque pass for the depth
## pre-pass plus the transparent pass, where it shades dearer (no opaque-pass ordering): about
## 0.6 ms of GPU at 1920x1080 on an RTX 3080, at the eye and at the orbit view with MSAA 4x
## (docs/PERFORMANCE.md "Shadow cascades and foliage edges", card gpuoptions, 2026-11-09).
## FAST keeps MSAA but puts the foliage on its plain-cutout twin, drawn opaque: hard leaf edges,
## everything else antialiased as before. alpha_to_coverage without the edge built-ins was
## measured pixel-identical to that plain cutout (the engine sets alpha to 1 after the scissor), so
## the stock engine has no cheaper soft edge.
##
## SMOOTH is the game as it shipped before this setting and stays the default.

## Feathered alpha-to-coverage edges while MSAA is on: the game before this setting.
const SMOOTH := 0
## Plain cutout edges while MSAA is on.
const FAST := 1
## The Settings choices, in menu order (the item ids in settings_menu.tscn).
const CHOICES: Array[int] = [SMOOTH, FAST]
## The choice for a player with no saved one.
const DEFAULT := SMOOTH
## The settings file key, in the [graphics] section.
const KEY := "foliage_edges"

## The applied choice. Root sets it from the settings file at startup, Settings sets it on
## Apply, and VisualEffectsController reads it whenever it picks the foliage shader variant.
static var current: int = DEFAULT


## [param choice] if it is one of CHOICES, else DEFAULT (a hand-edited or stale value).
static func sanitize(choice: int) -> int:
	return choice if CHOICES.has(choice) else DEFAULT


## The saved choice in a loaded settings file (DEFAULT when absent or not a known choice).
static func stored(config: ConfigFile) -> int:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT)
	return sanitize(int(value)) if value is int or value is float else DEFAULT


## Whether the foliage takes its antialiased shader twin at MSAA [param msaa_level] (a
## Viewport.MSAA value) under [param choice].
static func uses_antialiased_shader(msaa_level: int, choice: int) -> bool:
	return msaa_level != Viewport.MSAA_DISABLED and sanitize(choice) == SMOOTH
