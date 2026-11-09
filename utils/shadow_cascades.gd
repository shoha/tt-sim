class_name ShadowCascades
extends RefCounted

## Shadow cascades: how the sun's shadow map is split over the view and whether neighbouring
## splits blend (Settings > Graphics, beside Shadow quality; per player, never networked).
##
## The model. The sun draws its shadows into cascades, PSSM splits by view depth
## (LevelEnvironmentManager builds the sun with four). With blending on, the engine shades every
## lit pixel from two cascades and mixes them near each split, not only the pixels in a blend
## band, so blending costs a second filtered shadow lookup across the whole frame: about
## 0.45-0.5 ms of GPU at 1920x1080 on an RTX 3080, at the home view and at the eye. A single
## cascade (SHADOW_ORTHOGONAL) is one lookup with no split selection and a much cheaper shadow
## map at the eye, but its texels cover the whole shadow distance, so far shadows go soft and
## faint at wide zoom (docs/PERFORMANCE.md "Shadow cascades and foliage edges", card gpuoptions,
## 2026-11-09). Two splits instead of four was measured too and buys almost nothing (0.03 ms at
## home, 0.14 at the eye), so it is not offered.
##
## BLENDED is the game as it shipped before this setting and stays the default: the blend keeps
## far trees' shadows from popping as the orbit camera tilts (docs/lighting-and-environment.md).
## UNBLENDED drops the blend (pixel-identical at the home pose measured, but the tilt pop
## returns); SINGLE is the lowest tier, for slow GPUs.

## Four splits, blended: the game before this setting.
const BLENDED := 0
## Four splits, no blending between them.
const UNBLENDED := 1
## One cascade over the whole shadow distance.
const SINGLE := 2
## The Settings choices, in menu order (the item ids in settings_menu.tscn).
const CHOICES: Array[int] = [BLENDED, UNBLENDED, SINGLE]
## The choice for a player with no saved one.
const DEFAULT := BLENDED
## The settings file key, in the [graphics] section.
const KEY := "shadow_cascades"

## The applied choice. Root sets it from the settings file at startup, Settings sets it on
## Apply, and LevelEnvironmentManager reads it whenever it builds the sun.
static var current: int = DEFAULT


## [param choice] if it is one of CHOICES, else DEFAULT (a hand-edited or stale value).
static func sanitize(choice: int) -> int:
	return choice if CHOICES.has(choice) else DEFAULT


## The saved choice in a loaded settings file (DEFAULT when absent or not a known choice).
static func stored(config: ConfigFile) -> int:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT)
	return sanitize(int(value)) if value is int or value is float else DEFAULT


## The DirectionalLight3D shadow mode for [param choice].
static func mode_for(choice: int) -> DirectionalLight3D.ShadowMode:
	if sanitize(choice) == SINGLE:
		return DirectionalLight3D.SHADOW_ORTHOGONAL
	return DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


## Whether [param choice] blends neighbouring splits.
static func blends(choice: int) -> bool:
	return sanitize(choice) == BLENDED


## Sets [param light]'s shadow mode and split blending for [param choice].
static func apply_to(light: DirectionalLight3D, choice: int) -> void:
	if light == null:
		return
	light.directional_shadow_mode = mode_for(choice)
	light.directional_shadow_blend_splits = blends(choice)


## Applies [param choice] to every DirectionalLight3D directly under [param world] (the sun lives
## there; LevelEnvironmentManager adds it to the world viewport). Returns how many.
static func apply_in(world: Node, choice: int) -> int:
	if world == null:
		return 0
	var count := 0
	for child in world.get_children():
		if child is DirectionalLight3D:
			apply_to(child as DirectionalLight3D, choice)
			count += 1
	return count
