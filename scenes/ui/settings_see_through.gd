class_name SettingsSeeThrough
extends RefCounted

## The Graphics tab's two "see tokens through scenery" options, split out of settings_menu.gd
## to keep that file under the lint budget. They are independent:
## - Token ghost (graphics/token_ghost_enabled, default on): the translucent silhouette of a
##   token that foliage, a trunk, a rock or a wall covers (TokenGhost).
## - Canopy fade (graphics/canopy_fade_enabled, default off): the close-zoom window of thinned
##   crowns round the screen centre (CanopyFade).
## (The per-token Occlusion fade, graphics/occlusion_fade_enabled, was removed on 2026-11-15; a
## settings file that still holds the key loads fine, since nothing reads it.)

const KEY_GHOST := "token_ghost_enabled"
const KEY_CANOPY := "canopy_fade_enabled"
## TokenGhost and CanopyFade, loaded by path so the title does not compile them (perf audit boot2).
const TOKEN_GHOST := "res://scenes/board_token/token_ghost.gd"
const CANOPY_FADE := "res://scenes/states/playing/canopy_fade.gd"


## Puts the saved values in `config` on the checks without firing their handlers.
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	menu.token_ghost_check.set_pressed_no_signal(
		config.get_value("graphics", KEY_GHOST, _ghost().DEFAULT_ENABLED)
	)
	menu.canopy_fade_check.set_pressed_no_signal(
		config.get_value("graphics", KEY_CANOPY, _canopy().DEFAULT_ENABLED)
	)


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", KEY_GHOST, menu.token_ghost_check.button_pressed)
	config.set_value("graphics", KEY_CANOPY, menu.canopy_fade_check.button_pressed)


static func show_defaults(menu: SettingsMenu) -> void:
	menu.token_ghost_check.set_pressed_no_signal(_ghost().DEFAULT_ENABLED)
	menu.canopy_fade_check.set_pressed_no_signal(_canopy().DEFAULT_ENABLED)


## Applies the two checks now. Both are static state that any later map reads too.
static func apply(menu: SettingsMenu, _game_map: Node3D) -> void:
	_ghost().set_enabled(menu.token_ghost_check.button_pressed, menu.get_tree())
	_canopy().enabled = menu.canopy_fade_check.button_pressed


static func _ghost() -> Variant:
	return load(TOKEN_GHOST)


static func _canopy() -> Variant:
	return load(CANOPY_FADE)


static func apply_tooltips(menu: SettingsMenu) -> void:
	menu.token_ghost_check.tooltip_text = (
		"Draw a see-through silhouette of a token that foliage, a rock or a wall covers, with an "
		+ "outline (gold while it is selected or hovered), so a covered token can be found and "
		+ "selected. Plants and walls are left alone."
	)
	menu.canopy_fade_check.tooltip_text = (
		"Thin the tree crowns in a window round the middle of the screen when zoomed in. "
		+ "Off by default: the window follows the camera."
	)
