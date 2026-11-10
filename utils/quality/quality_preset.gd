class_name QualityPreset
extends RefCounted

## Graphics quality presets (Settings > Graphics "Quality"): one name for a set of the Graphics
## rows a weak GPU needs, per player, never networked.
##
## The model. A preset is not a setting of its own: it is a name for four existing rows, the
## ones that buy the most frame time per unit of look on a weak GPU (docs/PERFORMANCE.md
## "Minimum-spec estimate" and "Quality presets"): Shadow quality, Shadow cascades, Ambient
## occlusion and Render scale. Picking a preset sets those rows; the rows stay editable, and a
## change to any of them makes the selection read Custom (matching()). Nothing else is saved for
## it, so a preset can never disagree with the rows a player sees, and every reader of the
## settings file (the sun, the environment, the world viewport) keeps reading the rows as
## before.
##
## HIGH is the game as it shipped: exactly the rows' own defaults, so a player on High has the
## same pixels as one with no settings file. LOW drops the costs a weak GPU pays most for and
## keeps the look's structure; LOWEST is LOW drawn at 75 % and enlarged with FSR 1.0, the floor:
## nothing lower is offered as a preset, since below it the board reads blurred or flat.
## QualityAuto picks one of them on a first run (docs/systems/graphics_quality.md).

## No preset: the rows hold a combination none of them names.
const CUSTOM := -1
## The shipped defaults.
const HIGH := 0
## The weak-GPU set.
const LOW := 1
## LOW at render scale 75 %.
const LOWEST := 2
## The Settings choices, in menu order (the option's item ids).
const CHOICES: Array[int] = [HIGH, LOW, LOWEST]
## The preset of a player with no saved rows.
const DEFAULT := HIGH

## The [graphics] keys a preset sets.
const KEY_SHADOW_QUALITY := "shadow_quality"
const KEY_SSAO := "ssao_enabled"

## Each preset's rows: shadow_quality (a RenderingServer soft-shadow tier), shadow_cascades
## (ShadowCascades), ssao_enabled and render_scale (RenderScale). LOW keeps the Soft High tier and
## drops the cascade blend and the ambient occlusion: measured on an RTX 3080 that is 22 % off a
## filled 200 ft map's home view and 25 % off a standard one, with 0.2 to 0.4 of 255 mean change
## and under 1 % of pixels moved by more than 8 (the blend is pixel-identical at the home pitch
## and at 25 degrees now). Soft Low would take another 4 to 6 % but hatches every penumbra, and
## Hard edges move 5 to 10 % of pixels, so neither is in it (docs/PERFORMANCE.md "Quality
## presets").
const ROWS := {
	HIGH:
	{
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"shadow_cascades": ShadowCascades.BLENDED,
		"ssao_enabled": true,
		"render_scale": RenderScale.FULL,
	},
	LOW:
	{
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"shadow_cascades": ShadowCascades.UNBLENDED,
		"ssao_enabled": false,
		"render_scale": RenderScale.FULL,
	},
	LOWEST:
	{
		"shadow_quality": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"shadow_cascades": ShadowCascades.UNBLENDED,
		"ssao_enabled": false,
		"render_scale": 75,
	},
}

## The Settings label of each preset.
const LABELS := {HIGH: "High", LOW: "Low", LOWEST: "Lowest", CUSTOM: "Custom"}


## [param preset] if it is one of CHOICES, else DEFAULT. Pure.
static func sanitize(preset: int) -> int:
	return preset if CHOICES.has(preset) else DEFAULT


## A copy of [param preset]'s rows (see ROWS). Pure.
static func rows_for(preset: int) -> Dictionary:
	return (ROWS[sanitize(preset)] as Dictionary).duplicate()


## The preset whose rows equal [param rows] (the keys of ROWS), or CUSTOM. Pure.
static func matching(rows: Dictionary) -> int:
	for preset in CHOICES:
		if _same_rows(ROWS[preset], rows):
			return preset
	return CUSTOM


## The four rows as a loaded settings file holds them, each row's own default when absent.
static func saved_rows(config: ConfigFile) -> Dictionary:
	return {
		"shadow_quality": int(SettingsMenu.saved_shadow_quality(config)),
		"shadow_cascades": ShadowCascades.stored(config),
		"ssao_enabled":
		bool(
			config.get_value(
				"graphics", KEY_SSAO, Constants.RENDERING_TOGGLES_DEFAULTS["ssao_enabled"]
			)
		),
		"render_scale": RenderScale.stored(config),
	}


## Writes [param preset]'s rows into [param config]'s [graphics] section (not saved to disk).
static func write(config: ConfigFile, preset: int) -> void:
	var rows := rows_for(preset)
	config.set_value("graphics", KEY_SHADOW_QUALITY, rows.shadow_quality)
	config.set_value("graphics", ShadowCascades.KEY, rows.shadow_cascades)
	config.set_value("graphics", KEY_SSAO, rows.ssao_enabled)
	config.set_value("graphics", RenderScale.KEY, rows.render_scale)


## Applies [param rows] now, as Settings' Apply does for those rows: the sun's shadow tier
## (global), the cascades and render scale that later maps read, and on [param game_map] (the
## open GameMap, or null at the title) its sun, its world render and its environment's
## occlusion. [param config] supplies the reflection and GI rows the environment call also takes.
static func apply_rows(rows: Dictionary, game_map: Node3D, config: ConfigFile) -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(int(rows.shadow_quality))
	ShadowCascades.current = ShadowCascades.sanitize(int(rows.shadow_cascades))
	RenderScale.current = RenderScale.sanitize(int(rows.render_scale))
	if game_map == null:
		return
	if game_map.world_viewport:
		ShadowCascades.apply_in(game_map.world_viewport, ShadowCascades.current)
		RenderScale.apply_to(game_map.world_viewport, game_map.get_window(), RenderScale.current)
	var controller: Node = game_map.get_level_play_controller()
	if controller:
		var defaults := Constants.RENDERING_TOGGLES_DEFAULTS
		controller.get_environment_manager().apply_rendering_toggles(
			bool(rows.ssao_enabled),
			bool(config.get_value("graphics", "ssr_enabled", defaults["ssr_enabled"])),
			bool(config.get_value("graphics", "sdfgi_enabled", defaults["sdfgi_enabled"])),
		)


static func _same_rows(a: Dictionary, b: Dictionary) -> bool:
	for key in a:
		if not b.has(key) or b[key] != a[key]:
			return false
	return true
