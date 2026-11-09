class_name GroundClipmapSetting
extends RefCounted

## The "Ground detail" choice of Settings > Graphics (per player, never networked): how many
## levels the ground clipmap (GroundClipmap) may hold at once, or none (the per-pixel ground).
##
## The model. A level is 32 MB of GPU memory (two 2048^2 RGBA8 windows); a map needs the levels
## from the one that matches the zoom up to the one that spans the map, up to five (160 MB, a
## 320 ft map at zoom 4). A cap of N holds the N coarsest of those, so a lower cap gives up the
## sharpest levels at close zoom (the ground there reads softer than the per-pixel one) and
## keeps the memory down: 96 MB at 3, 128 MB at 4, 160 MB at 5, plus about 48 MB of strip
## viewports for the map's life (measured, clipmap3). OFF draws the per-pixel ground as before
## the clipmap. The setting is read when a map builds its terrain (whether to attach one) and by a
## clipmap that exists (the cap every frame, OFF every 30 frames), so Apply takes the cap and OFF
## at once (the clipmap frees itself and the plain shaders return) and turning it back on at the
## next map (checked through the Settings UI, clipmap3). Kept apart from GroundClipmap so Settings,
## which the start-up names, does not pull the clipmap's scripts into every launch
## (test_boot_graph).

## The clipmap off: the per-pixel ground.
const OFF := 0
## The Settings choices, in menu order (the item ids in settings_menu.tscn).
const CHOICES: Array[int] = [5, 4, 3, OFF]
## The choice for a player with no saved one: every level.
const DEFAULT := 5
## The settings file key, in the [graphics] section.
const KEY := "ground_detail_levels"

## The applied choice. Root sets it from the settings file at startup and Settings on Apply.
static var current: int = DEFAULT


## [param choice] if it is one of CHOICES, else DEFAULT (a hand-edited or stale value).
static func sanitize(choice: int) -> int:
	return choice if CHOICES.has(choice) else DEFAULT


## The saved choice in a loaded settings file (DEFAULT when absent or not a known choice).
static func stored(config: ConfigFile) -> int:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT)
	return sanitize(int(value)) if value is int or value is float else DEFAULT
